`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name : tb_mac_packed
// Description : mac_packed (mux + mac_v3 + post_mac[4-stage]) 검증용 self-checking TB
//               (Verilog-2001, SystemVerilog 문법 미사용)
//
//  * 데이터 포맷 : Q7.8 (fmap / weight / data_out 모두 16bit, 소수 8bit)
//  * 판정 방식   : golden model(무한정밀 합 -> round-half-away-from-zero -> 포화)과
//                  bit-exact 비교. mismatch 0 && timeout 0 이면 PASS
//  * SNR(dB)     : 10*log10( sum(ideal^2) / sum((hw - ideal)^2) )
//                  ideal = sum(x*w) / 2^8  (반올림·포화가 없는 실수 결과, 출력 LSB 단위)
//                  -> 반올림(양자화) 오차와 포화 오차가 모두 noise 로 반영됨
//  * 실행 방법   : Vivado Tcl 콘솔에서  run all
//
//  [웨이브폼 디버그 신호]
//    err_mism / err_timeout : 오류 검출 시 다음 클럭에 1클럭 펄스,  err_any = OR
//    dbg_tc                 : 현재 테스트 케이스 번호 (1부터)
//    dbg_exp / dbg_got      : 마지막 mismatch 의 기대값 / 실제값
//    -> Tcl: add_wave {{/tb_mac_packed/err_*}} {{/tb_mac_packed/dbg_*}}
//                  Behavioral / Post-Synthesis / Post-Implementation 시뮬레이션 공용
//
//  타이밍 (RTL 분석 결과)
//    T0       : enable=1 && proc=0 인 posedge, x0/w0 샘플
//    T1..Tn-1 : x1..x(n-1) 샘플
//  입력 프로토콜 (TB 구동 방식)
//    - enable : N개 데이터가 들어가는 N클럭 동안 1 유지, 마지막 데이터 후 0
//               (계속 1이면 T(N+3) 에서 다음 연산이 바로 시작됨)
//    - iter   : 연산 시작부터 결과가 나올 때까지 값 유지
//    - 데이터 구간 밖 fmap/weight : IDLE_JUNK=1 이면 난수(무시되는지 검증), 0 이면 0
//    Tn+2     : mac_v3 valid_out (누산 결과)
//    Tn+3~5   : post_mac  load -> shift/round -> saturate
//    Tn+6     : 결과가 data_out 에 1클럭 동안 출력 (dut.valid_out_post_mac = 1)
//               -> latency = N+6, 연속 동작 시 결과 간격(throughput) = N+3
//  top 에 valid 포트가 없으므로 dut.valid_out_post_mac 를 계층 참조로 관찰한다.
//
//  구동 / 샘플 시점 (타이밍 시뮬레이션 대응)
//    netlist 에서는 클럭이 IBUF/BUFG 를 거쳐 FF 에 수 ns 늦게 도착한다 (예: 5.66ns).
//    negedge(posedge+5ns) 에서 구동/샘플하면 실제 FF 클럭 엣지와 겹쳐
//    hold violation + 1클럭 밀린 샘플이 발생하므로,
//    - 입력 : posedge + IN_DLY 에서 구동 (다음 posedge 에 캡처됨)
//    - 출력 : valid 상승 + SMP_DLY 에서 data_out 캡처 (출력 버퍼 지연 흡수)
//    IN_DLY  조건 : (클럭 삽입지연 + hold) < IN_DLY + 입력지연 < (클럭주기 + 클럭 삽입지연 - setup)
//    SMP_DLY 조건 : 출력경로 지연(FF -> data_out 포트) < SMP_DLY < 클럭주기
//////////////////////////////////////////////////////////////////////////////////
module tb_mac_packed;

    // ------------------------------------------------------------------
    // Parameters
    // ------------------------------------------------------------------
    localparam integer WORD_W      = 16;
    localparam integer ACC_W       = WORD_W*2+1;
    localparam integer ITER_CNT    = 16;      // mac_packed 기본값과 같게 유지
    localparam integer Q_SCALE     = 8;
    localparam integer HALF        = 1 << (Q_SCALE-1);
    localparam integer DIV         = 1 << Q_SCALE;
    localparam integer CLK_PERIOD  = 10;
    localparam integer LAT_OFS     = 6;       // 예상 latency = N + LAT_OFS (출력 표시용)
    localparam integer MAX_N       = 576;     // TB 최대 누산 길이 = ResNet-20 최대 (3x3x64)
    localparam integer TIMEOUT_CYC = MAX_N + 64;
    localparam integer OUT_MAX     =  (1 << (WORD_W-1)) - 1;
    localparam integer OUT_MIN     = -(1 << (WORD_W-1));
    localparam integer FULL        =  (1 << (WORD_W-1));   // 풀스케일 랜덤 진폭
    localparam integer MAX_LOG     = 5;       // 케이스당 출력할 mismatch 로그 수
    localparam integer MAX_TC      = 32;
    localparam integer STREAM_MAX  = 64;
    localparam integer NAME_LEN    = 40;      // 케이스 이름 최대 글자 수

    parameter  real    IN_DLY      = 8.0;     // [ns] posedge 후 입력 구동 시점
    parameter  real    SMP_DLY     = 6.0;     // [ns] valid 상승 후 data_out 캡처 시점
    parameter  integer IDLE_JUNK   = 1;       // 1: 데이터 구간 밖 fmap/weight 에 난수, 0: 0 구동

    // ------------------------------------------------------------------
    // DUT
    // ------------------------------------------------------------------
    reg                         clk       = 1'b0;
    reg                         rst_n     = 1'b0;
    reg                         enable    = 1'b0;
    reg         [ITER_CNT-1:0]  iter      = {ITER_CNT{1'b0}};
    reg  signed [WORD_W-1:0]    fmap_in   = {WORD_W{1'b0}};
    reg  signed [WORD_W-1:0]    weight_in = {WORD_W{1'b0}};
    wire signed [WORD_W-1:0]    data_out;

    // 파라미터 override 없음 : 합성 netlist 에는 파라미터가 없으므로 (기본값 사용)
    mac_packed dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .enable    (enable),
        .iter      (iter),
        .fmap_in   (fmap_in),
        .weight_in (weight_in),
        .data_out  (data_out)
    );

    always #(CLK_PERIOD/2) clk = ~clk;

    wire res_valid = dut.valid_out_post_mac;   // 결과 유효 (내부 신호)

    // 클럭 카운터 (blocking: 같은 posedge 의 DUT NBA 갱신보다 먼저 증가)
    integer cyc = 0;
    always @(posedge clk) cyc = cyc + 1;

    // 결과 캡처 모니터 : valid 상승 시점의 cycle 기록, SMP_DLY 후 data_out 캡처
    integer                  cap_cnt = 0;
    integer                  cap_cyc = 0;
    reg  signed [WORD_W-1:0] cap_data;
    always @(posedge res_valid) begin
        if (res_valid === 1'b1) begin
            cap_cyc = cyc;
            #(SMP_DLY);
            cap_data = data_out;
            cap_cnt  = cap_cnt + 1;
        end
    end

    // ------------------------------------------------------------------
    // FAIL 1클럭 펄스 (웨이브폼용) : 이벤트 카운터가 바뀌면 다음 posedge 에서 1클럭 동안 1
    // ------------------------------------------------------------------
    integer                  mism_ev     = 0;
    integer                  to_ev       = 0;
    integer                  mism_seen   = 0;
    integer                  to_seen     = 0;
    reg                      err_mism    = 1'b0;
    reg                      err_timeout = 1'b0;
    wire                     err_any     = err_mism | err_timeout;
    integer                  dbg_tc      = 0;
    reg  signed [WORD_W-1:0] dbg_exp     = {WORD_W{1'b0}};
    reg  signed [WORD_W-1:0] dbg_got     = {WORD_W{1'b0}};

    always @(posedge clk) begin
        err_mism    <= (mism_ev != mism_seen);
        err_timeout <= (to_ev   != to_seen);
        mism_seen   <= mism_ev;
        to_seen     <= to_ev;
    end

    // ------------------------------------------------------------------
    // 자극 버퍼 / 통계
    // ------------------------------------------------------------------
    integer seed = 20261115;

    reg  signed [WORD_W-1:0] xv [0:MAX_N-1];
    reg  signed [WORD_W-1:0] wv [0:MAX_N-1];
    reg  signed [63:0]       exp_mem [0:STREAM_MAX-1];

    // 현재 케이스
    integer tc_id;
    integer tc_n, tc_trials, tc_mism, tc_timeout, tc_lat_min, tc_lat_max, tc_note;
    real    tc_sig_pow, tc_err_pow, tc_max_err;

    // 케이스별 결과 저장 (summary 출력용)
    reg  [8*NAME_LEN-1:0] r_name     [0:MAX_TC-1];
    integer               r_n        [0:MAX_TC-1];
    integer               r_trials   [0:MAX_TC-1];
    integer               r_mism     [0:MAX_TC-1];
    integer               r_to       [0:MAX_TC-1];
    integer               r_lmin     [0:MAX_TC-1];
    integer               r_lmax     [0:MAX_TC-1];
    integer               r_pass     [0:MAX_TC-1];
    integer               r_snr_type [0:MAX_TC-1];   // 0: 값, 1: INF, 2: N/A
    integer               r_note     [0:MAX_TC-1];
    integer               r_i1       [0:MAX_TC-1];
    integer               r_i2       [0:MAX_TC-1];
    real                  r_snr      [0:MAX_TC-1];
    real                  r_maxe     [0:MAX_TC-1];

    integer n_pass, n_fail;

    // ------------------------------------------------------------------
    // Functions
    // ------------------------------------------------------------------
    // [-amp, amp-1] 범위의 균일 난수
    function automatic signed [WORD_W-1:0] rnd;
        input integer amp;
        reg   [31:0]  u;
        integer       r;
        begin
            u   = $random(seed);
            r   = u % (2*amp);
            r   = r - amp;
            rnd = r[WORD_W-1:0];
        end
    endfunction

    // 데이터 구간 밖에서 구동할 값
    function automatic signed [WORD_W-1:0] idle_data;
        input integer dummy;
        begin
            idle_data = (IDLE_JUNK != 0) ? rnd(FULL) : {WORD_W{1'b0}};
        end
    endfunction

    // 무한정밀 내적 sum(xv[i]*wv[i])
    function automatic signed [63:0] golden_sum;
        input integer n;
        integer            i;
        reg signed [63:0]  s;
        begin
            s = 64'sd0;
            for (i = 0; i < n; i = i + 1)
                s = s + xv[i] * wv[i];
            golden_sum = s;
        end
    endfunction

    // 스펙 golden : >>Q_SCALE, round-half-away-from-zero, 16bit 포화
    function automatic integer golden_requant;
        input signed [63:0] s;
        reg   signed [63:0] q;
        begin
            if (s >= 0) q = (s + HALF)     >>> Q_SCALE;
            else        q = (s + HALF - 1) >>> Q_SCALE;
            if      (q > OUT_MAX) golden_requant = OUT_MAX;
            else if (q < OUT_MIN) golden_requant = OUT_MIN;
            else                  golden_requant = q;
        end
    endfunction

    // ------------------------------------------------------------------
    // 공통 task
    // ------------------------------------------------------------------
    task apply_reset;
        begin
            enable = 1'b0;
            rst_n  = 1'b0;
            repeat (3) @(posedge clk);
            #(IN_DLY) rst_n = 1'b1;
            repeat (2) @(posedge clk);
        end
    endtask

    task case_begin;
        input [8*NAME_LEN-1:0] name;
        input integer          n;
        begin
            r_name[tc_id] = name;
            dbg_tc        = tc_id + 1;
            tc_n          = n;
            tc_trials     = 0;
            tc_mism       = 0;
            tc_timeout    = 0;
            tc_lat_min    = 1 << 30;
            tc_lat_max    = -1;
            tc_note       = 0;
            tc_sig_pow    = 0.0;
            tc_err_pow    = 0.0;
            tc_max_err    = 0.0;
            r_i1[tc_id]   = 0;
            r_i2[tc_id]   = 0;
        end
    endtask

    // 결과 1개 누적 (bit-exact 비교 + SNR 파워 누적)
    task automatic record;
        input real                 ideal;
        input signed [WORD_W-1:0]  hw;
        input integer              gold;
        input integer              tag;
        real    hwr, e, ae;
        integer hwi;
        begin
            hwr        = hw;
            hwi        = hw;
            e          = hwr - ideal;
            ae         = (e < 0.0) ? -e : e;
            tc_sig_pow = tc_sig_pow + ideal * ideal;
            tc_err_pow = tc_err_pow + e * e;
            if (ae > tc_max_err) tc_max_err = ae;
            tc_trials  = tc_trials + 1;
            if (((^hw) === 1'bx) || (hwi != gold)) begin
                tc_mism = tc_mism + 1;
                mism_ev = mism_ev + 1;
                dbg_exp = gold;
                dbg_got = hw;
                if (tc_mism <= MAX_LOG)
                    $display("    [MISMATCH] TC%0d #%0d : expected=%0d, got=%0d (ideal=%.3f)  t=%0t",
                             tc_id + 1, tag, gold, hw, ideal, $time);
            end
        end
    endtask

    task note_lat;
        input integer lat;
        begin
            if (lat < tc_lat_min) tc_lat_min = lat;
            if (lat > tc_lat_max) tc_lat_max = lat;
        end
    endtask

    // 케이스 이름 출력 (앞쪽 null 문자 제거 + 오른쪽 공백 패딩)
    task print_name;
        input integer idx;
        input integer width;
        reg [8*NAME_LEN-1:0] nm;
        reg [7:0]            ch;
        integer              b, cnt;
        begin
            nm  = r_name[idx];
            cnt = 0;
            for (b = NAME_LEN-1; b >= 0; b = b - 1) begin
                ch = nm[b*8 +: 8];
                if (ch != 8'd0) begin
                    $write("%c", ch);
                    cnt = cnt + 1;
                end
            end
            while (cnt < width) begin
                $write(" ");
                cnt = cnt + 1;
            end
        end
    endtask

    task print_line;
        input integer idx;
        begin
            if (idx + 1 < 10) $write("TC0%0d ", idx + 1);
            else              $write("TC%0d ",  idx + 1);
            print_name(idx, 37);

            if      (r_n[idx] < 0)  $write("| N= - ");
            else if (r_n[idx] < 10) $write("| N= %0d ", r_n[idx]);
            else                    $write("| N=%0d ",  r_n[idx]);

            $write("| trials=%4d | mism=%3d | t/o=%2d ", r_trials[idx], r_mism[idx], r_to[idx]);

            if (r_lmax[idx] < 0)                $write("| lat=  -   ");
            else if (r_lmin[idx] == r_lmax[idx]) $write("| lat=%3d   ", r_lmin[idx]);
            else                                 $write("| lat=%2d~%2d ", r_lmin[idx], r_lmax[idx]);

            $write("| max|e|=%10.3f LSB ", r_maxe[idx]);

            case (r_snr_type[idx])
                0       : $write("| SNR=%8.2f dB ", r_snr[idx]);
                1       : $write("| SNR=     INF dB ");
                default : $write("| SNR=     N/A dB ");
            endcase

            if (r_pass[idx]) $display("| PASS");
            else             $display("| FAIL");
        end
    endtask

    task print_note;
        input integer idx;
        begin
            case (r_note[idx])
                1 : $display("       note: +-0.5 -> +-1, +-1.5 -> +-2, +-2.5 -> +-3, 127/256 -> 0, 129/256 -> 1");
                2 : $display("       note: clipping error is counted as noise -> low SNR is expected here");
                3 : $display("       note: result interval = %0d~%0d cycles (expected N+3 = %0d)",
                             r_i1[idx], r_i2[idx], r_n[idx] + 3);
                4 : $display("       note: no spurious valid after reset, then normal MAC results");
                default : ;
            endcase
        end
    endtask

    task case_end;
        begin
            r_n[tc_id]      = tc_n;
            r_trials[tc_id] = tc_trials;
            r_mism[tc_id]   = tc_mism;
            r_to[tc_id]     = tc_timeout;
            r_lmin[tc_id]   = tc_lat_min;
            r_lmax[tc_id]   = tc_lat_max;
            r_maxe[tc_id]   = tc_max_err;
            r_note[tc_id]   = tc_note;
            r_snr[tc_id]    = 0.0;

            if (tc_sig_pow == 0.0)      r_snr_type[tc_id] = 2;
            else if (tc_err_pow == 0.0) r_snr_type[tc_id] = 1;
            else begin
                r_snr_type[tc_id] = 0;
                r_snr[tc_id]      = 10.0 * $log10(tc_sig_pow / tc_err_pow);
            end

            r_pass[tc_id] = (tc_mism == 0) && (tc_timeout == 0) && (tc_trials > 0);

            print_line(tc_id);
            print_note(tc_id);

            if (r_pass[tc_id]) n_pass = n_pass + 1;
            else               n_fail = n_fail + 1;
            tc_id = tc_id + 1;
        end
    endtask

    // ------------------------------------------------------------------
    // 단일 MAC 연산 : enable 을 N클럭 동안 유지하며 데이터 입력 -> 결과 대기
    //   - 입력은 posedge + IN_DLY 에서 구동 -> 다음 posedge 에 캡처
    //   - iter 는 결과가 나올 때까지 유지
    //   - lat : T0 부터 결과가 나온 posedge 까지의 클럭 수
    // ------------------------------------------------------------------
    task automatic do_mac;
        input  integer             n;
        output signed [WORD_W-1:0] hw;
        output integer             lat;
        output                     to;
        integer k, start_cnt, t0;
        begin
            to        = 1'b0;
            lat       = -1;
            hw        = {WORD_W{1'bx}};
            start_cnt = cap_cnt;

            @(posedge clk); #(IN_DLY);                       // -> 다음 posedge 가 T0
            enable    = 1'b1;
            iter      = n;
            fmap_in   = (n > 0) ? xv[0] : idle_data(0);
            weight_in = (n > 0) ? wv[0] : idle_data(0);
            t0        = cyc + 1;

            k = 1;
            while ((cap_cnt == start_cnt) && (k <= TIMEOUT_CYC)) begin
                @(posedge clk); #(IN_DLY);                   // -> 다음 posedge 가 T(k)
                enable    = (k < n) ? 1'b1 : 1'b0;           // N개 데이터 동안 enable 유지
                fmap_in   = (k < n) ? xv[k] : idle_data(0);
                weight_in = (k < n) ? wv[k] : idle_data(0);
                k = k + 1;
            end

            if (cap_cnt == start_cnt) to = 1'b1;
            else begin
                hw  = cap_data;
                lat = cap_cyc - t0;
            end
        end
    endtask

    // xv/wv 에 채워진 벡터로 1회 실행 후 기록
    task automatic run_one;
        input integer n;
        input integer tag;
        reg signed [WORD_W-1:0] hw;
        integer                 lat;
        reg                     to;
        reg signed [63:0]       s;
        real                    ideal;
        begin
            s = golden_sum(n);
            do_mac(n, hw, lat, to);
            if (to) begin
                tc_timeout = tc_timeout + 1;
                to_ev      = to_ev + 1;
                $display("    [TIMEOUT ] TC%0d #%0d : no valid within %0d cycles -> reset  t=%0t",
                         tc_id + 1, tag, TIMEOUT_CYC, $time);
                apply_reset;
            end else begin
                note_lat(lat);
                ideal = s;
                ideal = ideal / DIV;
                record(ideal, hw, golden_requant(s), tag);
            end
        end
    endtask

    // ------------------------------------------------------------------
    // Test cases
    // ------------------------------------------------------------------
    // Bypass : enable=0, idle 상태에서 data_out == fmap_in
    task tc_bypass;
        input [8*NAME_LEN-1:0] name;
        input integer          trials;
        integer t, fi;
        real    fr;
        begin
            case_begin(name, -1);
            @(posedge clk); #(IN_DLY);
            enable = 1'b0;
            repeat (2) @(posedge clk);
            for (t = 0; t < trials; t = t + 1) begin
                @(posedge clk); #(IN_DLY);
                fmap_in   = rnd(FULL);
                weight_in = rnd(FULL);
                iter      = {ITER_CNT{1'b0}};
                #(CLK_PERIOD - 1);                           // 조합 경로(IBUF->mux->OBUF) 지연 흡수
                fi = fmap_in;
                fr = fmap_in;
                record(fr, data_out, fi, t);
            end
            case_end;
        end
    endtask

    // 랜덤 내적
    task tc_random;
        input [8*NAME_LEN-1:0] name;
        input integer          n, amp_x, amp_w, trials;
        integer t, i;
        begin
            case_begin(name, n);
            for (t = 0; t < trials; t = t + 1) begin
                for (i = 0; i < n; i = i + 1) begin
                    xv[i] = rnd(amp_x);
                    wv[i] = rnd(amp_w);
                end
                run_one(n, t);
            end
            if (amp_x == FULL && amp_w == FULL) tc_note = 2;
            case_end;
        end
    endtask

    // 반올림 경계 (N=1) : x*w/256 이 정확히 .5 이거나 바로 옆인 값
    task tc_rounding;
        integer i;
        begin
            case_begin("Rounding (half away from zero)", 1);
            for (i = 0; i < 14; i = i + 1) begin
                case (i)
                    0  : begin xv[0] =    1; wv[0] =   128; end   //  0.5   ->  1
                    1  : begin xv[0] =   -1; wv[0] =   128; end   // -0.5   -> -1
                    2  : begin xv[0] =    3; wv[0] =   128; end   //  1.5   ->  2
                    3  : begin xv[0] =   -3; wv[0] =   128; end   // -1.5   -> -2
                    4  : begin xv[0] =    5; wv[0] =   128; end   //  2.5   ->  3
                    5  : begin xv[0] =   -5; wv[0] =   128; end   // -2.5   -> -3
                    6  : begin xv[0] =    1; wv[0] =   127; end   //  0.496 ->  0
                    7  : begin xv[0] =   -1; wv[0] =   127; end   // -0.496 ->  0
                    8  : begin xv[0] =    1; wv[0] =   129; end   //  0.504 ->  1
                    9  : begin xv[0] =   -1; wv[0] =   129; end   // -0.504 -> -1
                    10 : begin xv[0] =  256; wv[0] =   256; end   //  1.0 * 1.0
                    11 : begin xv[0] = -256; wv[0] =   256; end   // -1.0 * 1.0
                    12 : begin xv[0] =    0; wv[0] = 32767; end   //  0
                    default : begin xv[0] = 255; wv[0] = 255; end // 254.00390625
                endcase
                run_one(1, i);
            end
            tc_note = 1;
            case_end;
        end
    endtask

    // 포화 경계 / 극단값
    task tc_saturation;
        integer i;
        begin
            case_begin("Saturation corners", -1);
            // #0 +32767 경계 (포화 안 됨)
            xv[0] =  32767; wv[0] = 256;                               run_one(1, 0);
            // #1 +32768 -> 32767 포화
            xv[0] =  32767; wv[0] = 256; xv[1] =   1; wv[1] = 256;     run_one(2, 1);
            // #2 32767.5 -> 반올림 32768 -> 포화
            xv[0] =  32767; wv[0] = 256; xv[1] = 128; wv[1] =   1;     run_one(2, 2);
            // #3 -32768 경계 (포화 안 됨)
            xv[0] = -32768; wv[0] = 256;                               run_one(1, 3);
            // #4 -32769 -> -32768 포화
            xv[0] = -32768; wv[0] = 256; xv[1] =  -1; wv[1] = 256;     run_one(2, 4);
            // #5 (+max * +max) x4 -> +포화
            for (i = 0; i < 4; i = i + 1) begin xv[i] =  32767; wv[i] =  32767; end  run_one(4, 5);
            // #6 (+max * -min) x4 -> -포화
            for (i = 0; i < 4; i = i + 1) begin xv[i] =  32767; wv[i] = -32768; end  run_one(4, 6);
            // #7 (-min * -min) x4 -> +포화
            for (i = 0; i < 4; i = i + 1) begin xv[i] = -32768; wv[i] = -32768; end  run_one(4, 7);
            // #8 (-min * -min) x7 : 34bit 누산기가 넘치지 않는 최대 횟수 (7 x 2^30 < 2^33)
            for (i = 0; i < 7; i = i + 1) begin xv[i] = -32768; wv[i] = -32768; end  run_one(7, 8);
            tc_note = 2;
            case_end;
        end
    endtask

    // 연속 동작 : 연산 사이에 쉬는 클럭 없이 다음 연산 시작
    //   - 각 연산 : enable=1 로 N클럭 데이터 입력 -> 3클럭 drain(enable=0) -> 다음 연산
    //   - 결과 간격(throughput) = N+3 클럭이어야 함
    task tc_stream;
        input [8*NAME_LEN-1:0] name;
        input integer          n, amp_x, amp_w, ops;
        integer           i, j, k, got, wcyc, seen, last_c, intv_min, intv_max;
        reg signed [63:0] s;
        real              ideal;
        begin
            case_begin(name, n);
            intv_min = 1 << 30;
            intv_max = -1;
            fork
                begin : drv_proc
                    for (j = 0; j < ops; j = j + 1) begin
                        for (i = 0; i < n; i = i + 1) begin
                            xv[i] = rnd(amp_x);
                            wv[i] = rnd(amp_w);
                        end
                        exp_mem[j] = golden_sum(n);
                        for (k = 0; k < n + 3; k = k + 1) begin
                            @(posedge clk); #(IN_DLY);
                            enable    = (k < n) ? 1'b1 : 1'b0;
                            iter      = n;
                            fmap_in   = (k < n) ? xv[k] : idle_data(0);
                            weight_in = (k < n) ? wv[k] : idle_data(0);
                        end
                    end
                    @(posedge clk); #(IN_DLY);
                    enable = 1'b0;                           // 마지막 연산 후 재시작 방지
                end
                begin : chk_proc
                    got    = 0;
                    wcyc   = 0;
                    seen   = cap_cnt;
                    last_c = -1;
                    while ((got < ops) && (wcyc < ops * (n + 3) + TIMEOUT_CYC)) begin
                        @(posedge clk); #1;
                        wcyc = wcyc + 1;
                        if (cap_cnt != seen) begin
                            seen  = cap_cnt;
                            s     = exp_mem[got];
                            ideal = s;
                            ideal = ideal / DIV;
                            record(ideal, cap_data, golden_requant(s), got);
                            if (last_c >= 0) begin
                                if (cap_cyc - last_c < intv_min) intv_min = cap_cyc - last_c;
                                if (cap_cyc - last_c > intv_max) intv_max = cap_cyc - last_c;
                            end
                            last_c = cap_cyc;
                            got    = got + 1;
                        end
                    end
                    if (got < ops) begin
                        tc_timeout = tc_timeout + (ops - got);
                        to_ev      = to_ev + 1;
                        $display("    [TIMEOUT ] TC%0d only %0d/%0d results received", tc_id + 1, got, ops);
                    end
                end
            join
            if ((intv_min != intv_max) || (intv_max != n + 3)) begin   // throughput 불일치도 FAIL
                tc_mism = tc_mism + 1;
                mism_ev = mism_ev + 1;
                $display("    [MISMATCH] TC%0d result interval %0d~%0d (expected %0d)",
                         tc_id + 1, intv_min, intv_max, n + 3);
            end
            r_i1[tc_id] = intv_min;
            r_i2[tc_id] = intv_max;
            tc_note     = 3;
            repeat (4) @(posedge clk);
            case_end;
        end
    endtask

    // 연산 도중 비동기 리셋 -> 정상 복귀 확인
    task tc_reset_mid;
        input integer n, trials;
        integer spurious, t, i, c0;
        begin
            case_begin("Async reset during MAC -> recovery", n);
            spurious = 0;

            // 연산 시작 후 중간에 리셋
            @(posedge clk); #(IN_DLY);
            enable    = 1'b1;
            iter      = n;
            fmap_in   = rnd(1024);
            weight_in = rnd(256);
            repeat (n / 2 + 1) begin
                @(posedge clk); #(IN_DLY);
                enable    = 1'b1;                            // 데이터 입력 도중
                fmap_in   = rnd(1024);
                weight_in = rnd(256);
            end
            rst_n  = 1'b0;                                   // 클럭 엣지 사이 비동기 리셋
            enable = 1'b0;
            repeat (2) @(posedge clk);
            #(IN_DLY) rst_n = 1'b1;

            // 리셋 이후 잔여 valid 가 나오면 안 됨
            c0 = cap_cnt;
            repeat (n + 6) @(posedge clk);
            #(SMP_DLY + 1);
            spurious = cap_cnt - c0;
            if (spurious > 0) begin
                tc_mism = tc_mism + 1;
                mism_ev = mism_ev + 1;
                $display("    [MISMATCH] TC%0d spurious valid after reset (%0d)", tc_id + 1, spurious);
            end

            // 정상 연산으로 복귀하는지 확인
            for (t = 0; t < trials; t = t + 1) begin
                for (i = 0; i < n; i = i + 1) begin
                    xv[i] = rnd(1024);
                    wv[i] = rnd(256);
                end
                run_one(n, t);
            end
            tc_note = 4;
            case_end;
        end
    endtask

    // ------------------------------------------------------------------
    // Main
    // ------------------------------------------------------------------
    integer m;

    initial begin
        tc_id  = 0;
        n_pass = 0;
        n_fail = 0;

        $display("");
        $display("====================================================================================================================================");
        $display(" tb_mac_packed : Q7.8 MAC (mac_v3) + post_mac self-check");
        $display("   WORD_W=%0d  ACC_W=%0d (acc %0d bit)  ITER_CNT=%0d  Q_SCALE=%0d  MAX_N=%0d", WORD_W, ACC_W, ACC_W+1, ITER_CNT, Q_SCALE, MAX_N);
        $display("   CLK=%0d ns (%0d MHz)  IN_DLY=%0.2f ns  SMP_DLY=%0.2f ns  IDLE_JUNK=%0d  seed=%0d",
                 CLK_PERIOD, 1000 / CLK_PERIOD, IN_DLY, SMP_DLY, IDLE_JUNK, seed);
        $display("   expected latency = N+%0d cycles, back-to-back interval = N+3 cycles", LAT_OFS);
        $display(" PASS = bit-exact vs golden (round-half-away-from-zero, saturate) / SNR = vs ideal real result (no rounding, no clipping)");
        $display("====================================================================================================================================");

        apply_reset;

        //           name                                     N    amp_x  amp_w  trials
        tc_bypass  ("Bypass (enable=0) after reset",                                 200);
        tc_rounding;
        tc_saturation;
        tc_random  ("iter=0  (empty sum -> 0)",               0,  1024,   256,   20);
        tc_random  ("iter=1  single product",                 1,  1024,   256,  200);
        tc_random  ("iter=3  X0W0+X1W1+X2W2",                 3,  1024,   256,  200);
        tc_random  ("iter=9  3x3 conv, typical",              9,  1024,   256,  300);  // fmap +-4.0, w +-1.0
        tc_random  ("iter=9  3x3 conv, small signal",         9,    64,    64,  300);  // fmap / w +-0.25
        tc_random  ("iter=27 3x3x3 conv (RGB input)",        27,  1024,   256,  200);
        tc_random  ("iter=144 3x3x16 (ResNet-20 L1)",       144,  1024,   256,  100);
        tc_random  ("iter=288 3x3x32 (ResNet-20 L2)",       288,  1024,   256,   50);
        tc_random  ("iter=576 3x3x64 (ResNet-20 L3)",       576,  1024,   256,   50);
        tc_random  ("iter=4  full-scale random (clipping)",   4,  FULL,  FULL,  200);
        tc_stream  ("Back-to-back (no gap between ops)",      9,  1024,   256,   50);
        tc_reset_mid(9, 50);
        tc_bypass  ("Bypass after MAC operations",                                   100);

        // ---------------- Summary ----------------
        $display("");
        $display("====================================================================================================================================");
        $display(" SUMMARY");
        $display("------------------------------------------------------------------------------------------------------------------------------------");
        for (m = 0; m < tc_id; m = m + 1) begin
            $write(" ");
            print_line(m);
        end
        $display("------------------------------------------------------------------------------------------------------------------------------------");
        if (n_fail == 0)
            $display(" RESULT : ALL %0d TEST CASES PASSED", n_pass);
        else
            $display(" RESULT : %0d PASSED, %0d FAILED  <<<<<", n_pass, n_fail);
        $display("====================================================================================================================================");
        $finish;
    end

    // 전체 watchdog (10 ms)
    initial begin
        #(10_000_000);
        $display("[FATAL] global simulation timeout");
        $finish;
    end

endmodule
`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name : tb_pooling_packed
// Description : pooling_packed (pooling_unit[avgpool + maxpool + mux] + mux) self-checking TB
//               (Verilog-2001)
//
//  * 데이터 포맷 : Q7.8 16bit signed
//  * 윈도우 크기 : max_iter / avg_iter (= N, 윈도우 내 데이터 개수). stride 는 상위 모듈 담당 -> 미검증
//  * 입력 프로토콜 : enable_avg 또는 enable_max 를 N클럭 동안 1, 해당 iter 는 결과가 나올 때까지 유지
//                    사용하지 않는 쪽 iter 는 0 으로 구동 (idle 모듈이 iter 값과 무관하게 조용해야 함)
//  * 판정
//      - maxpool : golden = signed max(x0..x(N-1))
//      - avgpool : golden = sum / N  (AVG_ROUND 로 반올림 규칙 선택)
//                  shift(>>>) 방식 avgpool          -> AVG_ROUND=0 (기본, floor)
//                  div_layer 사용, DIV_ROUND=0      -> AVG_ROUND=1
//                  div_layer 사용, DIV_ROUND=1      -> AVG_ROUND=2
//  * ResNet-20 은 global avg pooling(8x8 = 64)만 사용 -> 2의 거듭제곱 윈도우만 기본 검증
//    (N=9 / 31 등 2의 거듭제곱이 아닌 avg 는 TEST_NON_POW2=1 일 때만 실행)
//      - mism  : golden 과 bit-exact 불일치 개수
//      - v_err : valid_out 이 1클럭 넘게 유지되었거나, 연산 요청 없이 valid 가 뜬 횟수
//      - t/o   : TIMEOUT_CYC 안에 valid 가 오지 않은 횟수
//      - PASS  : mism = 0, v_err = 0, t/o = 0
//  * SNR(dB) : 10*log10( sum(ideal^2) / sum((hw - ideal)^2) ),  ideal = 실수 결과 (avg: sum/N)
//  * 결과 관찰 : top 에 valid 포트가 없으므로 dut.valid_out (pooling_unit valid) 을 계층 참조
//  * 구동 / 샘플 시점은 mac TB 와 동일 (posedge+IN_DLY 구동, posedge+SMP_DLY 샘플)
//  * 실행 : Vivado Tcl 콘솔에서 run all
//
//  [웨이브폼 디버그 신호]  (FAIL 원인 위치를 파형에서 바로 찾기 위함)
//    err_mism / err_valid / err_timeout : 해당 오류가 검출되면 다음 클럭에 1클럭 펄스
//    err_any                            : 위 셋의 OR
//    dbg_tc                             : 현재 테스트 케이스 번호 (1부터)
//    dbg_exp / dbg_got                  : 마지막 mismatch 의 기대값 / 실제값
//    dbg_* (POOL_DBG_PROBE)             : avgpool / maxpool 내부 valid, proc, iter_cnt, iter_reg
//    -> Tcl: add_wave {{/tb_pooling_packed/err_*}} {{/tb_pooling_packed/dbg_*}}
//       첫 err_any 펄스 직전 몇 클럭의 dbg_* 를 보면 원인 확인 가능
//    합성 netlist 시뮬레이션처럼 내부 이름이 없으면 아래 `define POOL_DBG_PROBE 를 주석 처리
//////////////////////////////////////////////////////////////////////////////////
`define POOL_DBG_PROBE                       // 내부 신호 probe (netlist 시뮬레이션이면 주석 처리)

module tb_pooling_packed;

    // ------------------------------------------------------------------
    // Parameters
    // ------------------------------------------------------------------
    localparam integer WORD_W      = 16;
    localparam integer ACC_W       = WORD_W*2+1;
    localparam integer MAX_ITER_CNT = 16;     // pooling_packed 기본값과 같게 유지
    localparam integer AVG_ITER_CNT = 16;
    localparam integer CLK_PERIOD  = 10;
    localparam integer MAX_N       = 64;      // TB 에서 쓰는 최대 윈도우 (자극 버퍼 크기, 8x8 global avg)
    localparam integer TIMEOUT_CYC = 160;     // MAX_N + 최대 latency 보다 충분히 크게
    localparam integer FULL        = (1 << (WORD_W-1));     // 32768
    localparam integer MAX_LOG     = 5;
    localparam integer MAX_TC      = 32;
    localparam integer STREAM_MAX  = 64;
    localparam integer STREAM_GAP  = 1;       // 연속 동작 시 연산 사이 enable=0 클럭 수
    localparam integer NAME_LEN    = 40;
    localparam integer MODE_AVG    = 0;
    localparam integer MODE_MAX    = 1;

    parameter  real    IN_DLY      = 8.0;     // [ns] posedge 후 입력 구동 시점
    parameter  real    SMP_DLY     = 6.0;     // [ns] posedge 후 valid / data_out 샘플 시점
    parameter  integer IDLE_JUNK   = 1;       // 1: 데이터 구간 밖 data_in 에 난수, 0: 0 구동
    parameter  integer AVG_ROUND   = 0;       // 0: floor (>>>), 1: 0 방향 버림, 2: 반올림(0.5 는 0 에서 먼 쪽)
    parameter  integer TEST_NON_POW2 = 0;     // 1: 2의 거듭제곱이 아닌 avg 윈도우(N=9, 31)도 검증

    // ------------------------------------------------------------------
    // DUT
    // ------------------------------------------------------------------
    reg                         clk        = 1'b0;
    reg                         rst_n      = 1'b0;
    reg                         enable_avg = 1'b0;
    reg                         enable_max = 1'b0;
    reg     [MAX_ITER_CNT-1:0]  max_iter   = {MAX_ITER_CNT{1'b0}};
    reg     [AVG_ITER_CNT-1:0]  avg_iter   = {AVG_ITER_CNT{1'b0}};
    reg  signed [WORD_W-1:0]    data_in    = {WORD_W{1'b0}};
    wire signed [WORD_W-1:0]    data_out;

    // 파라미터 override 없음 : 합성 netlist 에서도 그대로 사용 가능 (기본값 사용)
    pooling_packed dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .enable_avg (enable_avg),
        .enable_max (enable_max),
        .max_iter   (max_iter),
        .avg_iter   (avg_iter),
        .data_in    (data_in),
        .data_out   (data_out)
    );

    always #(CLK_PERIOD/2) clk = ~clk;

    wire res_valid = dut.valid_out;            // 결과 유효 (내부 신호)

    // ------------------------------------------------------------------
    // 클럭 카운터 / 결과 모니터
    //   매 posedge + SMP_DLY 에서 valid 샘플
    //   - 0 -> 1 : 결과 캡처 (op_active=0 이면 요청 없는 valid -> v_err)
    //   - 2클럭 이상 연속 1 : valid 가 펄스가 아님 -> v_err (한 번만 카운트)
    // ------------------------------------------------------------------
    integer cyc = 0;
    always @(posedge clk) cyc = cyc + 1;

    integer                  cap_cnt   = 0;
    integer                  cap_cyc   = 0;
    reg  signed [WORD_W-1:0] cap_data  = {WORD_W{1'b0}};
    integer                  v_run     = 0;
    integer                  v_err_cnt = 0;
    integer                  v_log     = 0;
    reg                      op_active = 1'b0;
    integer                  tc_id;

    always @(posedge clk) begin
        #(SMP_DLY);
        if (res_valid === 1'b1) begin
            v_run = v_run + 1;
            if (v_run == 1) begin
                cap_cyc  = cyc;
                cap_data = data_out;
                cap_cnt  = cap_cnt + 1;
                if (!op_active) begin
                    v_err_cnt = v_err_cnt + 1;
                    if (v_log < MAX_LOG)
                        $display("    [VALID   ] TC%0d valid_out asserted without request (t=%0t)", tc_id + 1, $time);
                    v_log = v_log + 1;
                end
            end else if (v_run == 2) begin
                v_err_cnt = v_err_cnt + 1;
                if (v_log < MAX_LOG)
                    $display("    [VALID   ] TC%0d valid_out held high > 1 cycle (t=%0t)", tc_id + 1, $time);
                v_log = v_log + 1;
            end
        end else begin
            v_run = 0;
        end
    end

    // ------------------------------------------------------------------
    // FAIL 1클럭 펄스 (웨이브폼용)
    //   이벤트 카운터가 바뀌면 다음 posedge 에서 1클럭 동안 1
    // ------------------------------------------------------------------
    integer                  mism_ev   = 0;
    integer                  to_ev     = 0;
    integer                  mism_seen = 0;
    integer                  to_seen   = 0;
    integer                  verr_seen = 0;
    reg                      err_mism    = 1'b0;
    reg                      err_valid   = 1'b0;
    reg                      err_timeout = 1'b0;
    wire                     err_any     = err_mism | err_valid | err_timeout;
    integer                  dbg_tc      = 0;
    reg  signed [WORD_W-1:0] dbg_exp     = {WORD_W{1'b0}};
    reg  signed [WORD_W-1:0] dbg_got     = {WORD_W{1'b0}};

    always @(posedge clk) begin
        err_mism    <= (mism_ev   != mism_seen);
        err_valid   <= (v_err_cnt != verr_seen);
        err_timeout <= (to_ev     != to_seen);
        mism_seen   <= mism_ev;
        verr_seen   <= v_err_cnt;
        to_seen     <= to_ev;
    end

`ifdef POOL_DBG_PROBE
    wire                     dbg_valid_avg = dut.uut_pooling_unit.valid_out_avg;
    wire                     dbg_valid_max = dut.uut_pooling_unit.valid_out_max;
    wire                     dbg_avg_proc  = dut.uut_pooling_unit.uut_avgpool.proc;
    wire [AVG_ITER_CNT-1:0]  dbg_avg_cnt   = dut.uut_pooling_unit.uut_avgpool.iter_cnt;
    wire [AVG_ITER_CNT-1:0]  dbg_avg_iter  = dut.uut_pooling_unit.uut_avgpool.iter_reg;
    wire                     dbg_max_proc  = dut.uut_pooling_unit.uut_maxpool.proc;
    wire [MAX_ITER_CNT-1:0]  dbg_max_cnt   = dut.uut_pooling_unit.uut_maxpool.iter_cnt;
    wire [MAX_ITER_CNT-1:0]  dbg_max_iter  = dut.uut_pooling_unit.uut_maxpool.iter_reg;
`endif

    // ------------------------------------------------------------------
    // 자극 버퍼 / 통계
    // ------------------------------------------------------------------
    integer seed = 20261117;

    reg  signed [WORD_W-1:0] dv      [0:MAX_N-1];
    reg  signed [WORD_W-1:0] exp_mem [0:STREAM_MAX-1];
    real                     ide_mem [0:STREAM_MAX-1];

    integer tc_n, tc_trials, tc_mism, tc_timeout, tc_lat_min, tc_lat_max, tc_note, tc_v0;
    real    tc_sig_pow, tc_err_pow, tc_max_err;

    reg  [8*NAME_LEN-1:0] r_name     [0:MAX_TC-1];
    integer               r_n        [0:MAX_TC-1];
    integer               r_trials   [0:MAX_TC-1];
    integer               r_mism     [0:MAX_TC-1];
    integer               r_verr     [0:MAX_TC-1];
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
    // [lo, hi] 범위 균일 난수
    function automatic signed [WORD_W-1:0] rnd;
        input integer lo, hi;
        reg   [31:0]  u;
        integer       r;
        begin
            u   = $random(seed);
            r   = u % (hi - lo + 1);
            r   = r + lo;
            rnd = r[WORD_W-1:0];
        end
    endfunction

    function automatic signed [WORD_W-1:0] idle_data;
        input integer dummy;
        begin
            idle_data = (IDLE_JUNK != 0) ? rnd(-FULL, FULL-1) : {WORD_W{1'b0}};
        end
    endfunction

    function automatic signed [63:0] win_sum;
        input integer n;
        integer i;
        reg signed [63:0] s;
        begin
            s = 64'sd0;
            for (i = 0; i < n; i = i + 1) s = s + dv[i];
            win_sum = s;
        end
    endfunction

    function automatic integer win_max;
        input integer n;
        integer i, m;
        begin
            m = dv[0];
            for (i = 1; i < n; i = i + 1)
                if (dv[i] > m) m = dv[i];
            win_max = m;
        end
    endfunction

    // 평균 golden (AVG_ROUND 규칙)
    function automatic integer avg_golden;
        input signed [63:0] s;
        input integer       n;
        reg   signed [63:0] q, a;
        begin
            case (AVG_ROUND)
                1 : q = s / n;                                    // 0 방향 버림
                2 : begin                                         // 반올림, half away from zero
                        a = (s < 0) ? -s : s;
                        q = (a + n / 2) / n;
                        if (s < 0) q = -q;
                    end
                default : begin                                   // floor (산술 shift 와 동일)
                        q = s / n;
                        if ((s < 0) && (q * n != s)) q = q - 1;
                    end
            endcase
            avg_golden = q;
        end
    endfunction

    // 현재 dv[0..n-1] 에 대한 golden / ideal
    task automatic golden;
        input  integer mode, n;
        output integer gold;
        output real    ideal;
        reg signed [63:0] s;
        begin
            if (mode == MODE_MAX) begin
                gold  = win_max(n);
                ideal = gold;
            end else begin
                s     = win_sum(n);
                gold  = avg_golden(s, n);
                ideal = s;
                ideal = ideal / n;
            end
        end
    endtask

    // ------------------------------------------------------------------
    // 공통 task
    // ------------------------------------------------------------------
    task set_en;
        input integer mode;
        input         val;
        begin
            enable_avg = (mode == MODE_AVG) ? val : 1'b0;
            enable_max = (mode == MODE_MAX) ? val : 1'b0;
        end
    endtask

    // 사용하는 쪽 iter = n, 반대쪽 iter = 0
    task set_iter;
        input integer mode, n;
        begin
            avg_iter = (mode == MODE_AVG) ? n : 0;
            max_iter = (mode == MODE_MAX) ? n : 0;
        end
    endtask

    task apply_reset;
        begin
            enable_avg = 1'b0;
            enable_max = 1'b0;
            rst_n      = 1'b0;
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
            tc_v0         = v_err_cnt;
            v_log         = 0;
            r_i1[tc_id]   = 0;
            r_i2[tc_id]   = 0;
        end
    endtask

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

            $write("| trials=%4d | mism=%4d | v_err=%4d | t/o=%3d ",
                   r_trials[idx], r_mism[idx], r_verr[idx], r_to[idx]);

            if (r_lmax[idx] < 0)                 $write("| lat=  -   ");
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
                1 : $display("       note: data_out must equal data_in (no pooling request)");
                2 : $display("       note: result interval = %0d~%0d cycles (N + gap %0d = %0d)",
                             r_i1[idx], r_i2[idx], STREAM_GAP, r_n[idx] + STREAM_GAP);
                3 : $display("       note: no valid after reset, then normal results");
                4 : $display("       note: non power-of-2 window -> needs divider (avgpool USE_DIV=1)");
                default : ;
            endcase
        end
    endtask

    task case_end;
        begin
            r_n[tc_id]      = tc_n;
            r_trials[tc_id] = tc_trials;
            r_mism[tc_id]   = tc_mism;
            r_verr[tc_id]   = v_err_cnt - tc_v0;
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

            r_pass[tc_id] = (tc_mism == 0) && (r_verr[tc_id] == 0) &&
                            (tc_timeout == 0) && (tc_trials > 0);

            print_line(tc_id);
            print_note(tc_id);

            if (r_pass[tc_id]) n_pass = n_pass + 1;
            else               n_fail = n_fail + 1;
            tc_id = tc_id + 1;
        end
    endtask

    // ------------------------------------------------------------------
    // 단일 풀링 연산 : enable 을 N클럭 유지하며 dv[0..N-1] 입력 -> valid 대기
    //   lat : T0(첫 데이터 캡처 posedge) 부터 valid 가 뜬 posedge 까지 클럭 수
    // ------------------------------------------------------------------
    task automatic do_pool;
        input  integer             mode, n;
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
            op_active = 1'b1;
            set_en(mode, 1'b1);
            set_iter(mode, n);
            data_in   = dv[0];
            t0        = cyc + 1;

            k = 1;
            while ((cap_cnt == start_cnt) && (k <= TIMEOUT_CYC)) begin
                @(posedge clk); #(IN_DLY);
                set_en(mode, (k < n) ? 1'b1 : 1'b0);         // N개 데이터 동안 enable 유지
                data_in = (k < n) ? dv[k] : idle_data(0);
                k = k + 1;
            end
            op_active = 1'b0;

            if (cap_cnt == start_cnt) to = 1'b1;
            else begin
                hw  = cap_data;
                lat = cap_cyc - t0;
            end
        end
    endtask

    task automatic run_one;
        input integer mode, n, tag;
        reg signed [WORD_W-1:0] hw;
        integer                 lat, gold;
        reg                     to;
        real                    ideal;
        begin
            golden(mode, n, gold, ideal);
            do_pool(mode, n, hw, lat, to);
            if (to) begin
                tc_timeout = tc_timeout + 1;
                to_ev      = to_ev + 1;
                if (tc_timeout <= MAX_LOG)
                    $display("    [TIMEOUT ] TC%0d #%0d : no valid within %0d cycles -> reset  t=%0t",
                             tc_id + 1, tag, TIMEOUT_CYC, $time);
                apply_reset;
            end else begin
                note_lat(lat);
                record(ideal, hw, gold, tag);
            end
        end
    endtask

    // ------------------------------------------------------------------
    // Test cases
    // ------------------------------------------------------------------
    // Bypass : enable 없음 -> data_out == data_in, valid 없어야 함
    task tc_bypass;
        input [8*NAME_LEN-1:0] name;
        input integer          it, trials;
        integer t, di;
        real    dr;
        begin
            case_begin(name, -1);
            @(posedge clk); #(IN_DLY);
            enable_avg = 1'b0;
            enable_max = 1'b0;
            avg_iter   = it;
            max_iter   = it;
            repeat (2) @(posedge clk);
            for (t = 0; t < trials; t = t + 1) begin
                @(posedge clk); #(IN_DLY);
                data_in = rnd(-FULL, FULL-1);
                #(CLK_PERIOD - 1);                           // 조합 경로 지연 흡수
                di = data_in;
                dr = data_in;
                record(dr, data_out, di, t);
            end
            tc_note = 1;
            case_end;
        end
    endtask

    // 랜덤 윈도우
    task tc_random;
        input [8*NAME_LEN-1:0] name;
        input integer          mode, n, lo, hi, trials;
        integer t, i;
        begin
            case_begin(name, n);
            for (t = 0; t < trials; t = t + 1) begin
                for (i = 0; i < n; i = i + 1) dv[i] = rnd(lo, hi);
                run_one(mode, n, t);
            end
            if ((mode == MODE_AVG) && ((n & (n - 1)) != 0)) tc_note = 4;
            case_end;
        end
    endtask

    // 연속 동작 : enable N클럭 + STREAM_GAP 클럭 휴지 -> 다음 윈도우
    task tc_stream;
        input [8*NAME_LEN-1:0] name;
        input integer          mode, n, ops;
        integer i, j, k, got, wcyc, seen, last_c, intv_min, intv_max, g;
        real    id;
        begin
            case_begin(name, n);
            intv_min  = 1 << 30;
            intv_max  = -1;
            op_active = 1'b1;
            fork
                begin : drv_proc
                    for (j = 0; j < ops; j = j + 1) begin
                        for (i = 0; i < n; i = i + 1) dv[i] = rnd(0, FULL-1);
                        golden(mode, n, g, id);
                        exp_mem[j] = g;
                        ide_mem[j] = id;
                        for (k = 0; k < n + STREAM_GAP; k = k + 1) begin
                            @(posedge clk); #(IN_DLY);
                            set_en(mode, (k < n) ? 1'b1 : 1'b0);
                            set_iter(mode, n);
                            data_in = (k < n) ? dv[k] : idle_data(0);
                        end
                    end
                    @(posedge clk); #(IN_DLY);
                    set_en(mode, 1'b0);
                end
                begin : chk_proc
                    got    = 0;
                    wcyc   = 0;
                    seen   = cap_cnt;
                    last_c = -1;
                    while ((got < ops) && (wcyc < ops * (n + STREAM_GAP) + TIMEOUT_CYC)) begin
                        @(posedge clk); #(IN_DLY + 1);
                        wcyc = wcyc + 1;
                        if (cap_cnt != seen) begin
                            seen = cap_cnt;
                            record(ide_mem[got], cap_data, exp_mem[got], got);
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
            op_active = 1'b0;
            if ((intv_max >= 0) && (intv_min != intv_max)) begin   // 결과 간격이 일정하지 않으면 FAIL
                tc_mism = tc_mism + 1;
                mism_ev = mism_ev + 1;
                $display("    [MISMATCH] TC%0d result interval not constant (%0d~%0d)", tc_id + 1, intv_min, intv_max);
            end
            r_i1[tc_id] = (intv_max < 0) ? 0 : intv_min;
            r_i2[tc_id] = (intv_max < 0) ? 0 : intv_max;
            tc_note     = 2;
            repeat (4) @(posedge clk);
            case_end;
        end
    endtask

    // avg / max 번갈아 실행 (pooling_unit 내부 mux 선택 검증)
    task tc_alternate;
        input integer n, trials;
        integer t, i;
        begin
            case_begin("Alternating avg <-> max", n);
            for (t = 0; t < trials; t = t + 1) begin
                for (i = 0; i < n; i = i + 1) dv[i] = rnd(0, FULL-1);
                run_one((t % 2 == 0) ? MODE_AVG : MODE_MAX, n, t);
            end
            case_end;
        end
    endtask

    // 연산 도중 비동기 리셋 -> 정상 복귀
    task tc_reset_mid;
        input integer n, trials;
        integer t, i;
        begin
            case_begin("Async reset during avg -> recovery", n);
            @(posedge clk); #(IN_DLY);
            set_en(MODE_AVG, 1'b1);
            set_iter(MODE_AVG, n);
            data_in = rnd(0, 4095);
            repeat (n / 2 + 1) begin
                @(posedge clk); #(IN_DLY);
                data_in = rnd(0, 4095);
            end
            rst_n = 1'b0;                                    // 클럭 엣지 사이 비동기 리셋
            set_en(MODE_AVG, 1'b0);
            repeat (2) @(posedge clk);
            #(IN_DLY) rst_n = 1'b1;
            repeat (n + 10) @(posedge clk);                  // 이 구간 valid 는 모니터가 v_err 로 기록

            for (t = 0; t < trials; t = t + 1) begin
                for (i = 0; i < n; i = i + 1) dv[i] = rnd(0, FULL-1);
                run_one(MODE_AVG, n, t);
            end
            tc_note = 3;
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
        $display("==================================================================================================================================================");
        $display(" tb_pooling_packed : Q7.8 avg / max pooling self-check");
        $display("   WORD_W=%0d  ACC_W=%0d  MAX_ITER_CNT=%0d  AVG_ITER_CNT=%0d  window N = iter (tested up to %0d), stride: not handled here",
                 WORD_W, ACC_W, MAX_ITER_CNT, AVG_ITER_CNT, MAX_N);
        $display("   TEST_NON_POW2=%0d  TIMEOUT=%0d cycles", TEST_NON_POW2, TIMEOUT_CYC);
        $display("   CLK=%0d ns (%0d MHz)  IN_DLY=%0.2f ns  SMP_DLY=%0.2f ns  IDLE_JUNK=%0d  STREAM_GAP=%0d  seed=%0d",
                 CLK_PERIOD, 1000 / CLK_PERIOD, IN_DLY, SMP_DLY, IDLE_JUNK, STREAM_GAP, seed);
        case (AVG_ROUND)
            1       : $display("   avg golden = sum / N, truncate toward zero");
            2       : $display("   avg golden = sum / N, round half away from zero");
            default : $display("   avg golden = floor(sum / N)  (same as arithmetic shift >>> for power-of-2 N)");
        endcase
        $display("   PASS = mism 0 && v_err 0 (valid is a 1-cycle pulse, only on request) && t/o 0");
        $display("==================================================================================================================================================");

        apply_reset;

        //           name                                    mode      N    lo       hi       trials
        tc_bypass  ("Bypass (no enable, iters=0)",                       0,                    200);
        tc_random  ("Max  N=1",                          MODE_MAX,  1, -FULL,   FULL-1,   100);
        tc_random  ("Max  N=4  2x2, post-ReLU",          MODE_MAX,  4,     0,   FULL-1,   300);
        tc_random  ("Max  N=9  3x3, signed",             MODE_MAX,  9, -FULL,   FULL-1,   300);
        tc_random  ("Max  N=4  all negative",            MODE_MAX,  4, -FULL,       -1,   200);
        tc_random  ("Max  N=64 8x8",                     MODE_MAX, 64, -FULL,   FULL-1,   100);
        tc_random  ("Avg  N=1",                          MODE_AVG,  1, -FULL,   FULL-1,   100);
        tc_random  ("Avg  N=2",                          MODE_AVG,  2,     0,   FULL-1,   300);
        tc_random  ("Avg  N=4  2x2, post-ReLU",          MODE_AVG,  4,     0,   FULL-1,   300);
        tc_random  ("Avg  N=4  signed (rounding)",       MODE_AVG,  4, -FULL,   FULL-1,   300);
        tc_random  ("Avg  N=8",                          MODE_AVG,  8,     0,   FULL-1,   300);
        tc_random  ("Avg  N=16",                         MODE_AVG, 16,     0,   FULL-1,   200);
        tc_random  ("Avg  N=64 8x8 GAP, post-ReLU",      MODE_AVG, 64,     0,   FULL-1,   200);   // ResNet-20 global avg pool
        tc_random  ("Avg  N=64 8x8 GAP, signed",         MODE_AVG, 64, -FULL,   FULL-1,   200);
        if (TEST_NON_POW2 != 0) begin
            tc_random  ("Avg  N=9  3x3 (non power of 2)",    MODE_AVG,  9,     0,   FULL-1,   200);
            tc_random  ("Avg  N=31 (non power of 2)",        MODE_AVG, 31, -FULL,   FULL-1,   100);
        end
        tc_stream  ("Back-to-back max",                  MODE_MAX,  4,                     50);
        tc_stream  ("Back-to-back avg",                  MODE_AVG,  4,                     50);
        tc_stream  ("Back-to-back avg 8x8",              MODE_AVG, 64,                     20);
        tc_alternate(4, 100);
        tc_reset_mid(8, 50);
        tc_bypass  ("Bypass after pooling (iters=4 held)",               4,                    100);

        // ---------------- Summary ----------------
        $display("");
        $display("==================================================================================================================================================");
        $display(" SUMMARY");
        $display("--------------------------------------------------------------------------------------------------------------------------------------------------");
        for (m = 0; m < tc_id; m = m + 1) begin
            $write(" ");
            print_line(m);
        end
        $display("--------------------------------------------------------------------------------------------------------------------------------------------------");
        if (n_fail == 0)
            $display(" RESULT : ALL %0d TEST CASES PASSED", n_pass);
        else
            $display(" RESULT : %0d PASSED, %0d FAILED  <<<<<", n_pass, n_fail);
        $display("==================================================================================================================================================");
        $finish;
    end

    // 전체 watchdog (20 ms)
    initial begin
        #(20_000_000);
        $display("[FATAL] global simulation timeout");
        $finish;
    end

endmodule
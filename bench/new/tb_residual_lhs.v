`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name : tb_residual_packed
// Description : residual_packed (residual_unit + mux) self-checking TB  (Verilog-2001)
//
//  * 동작 (RTL 분석) : enable=1 인 클럭의 data_in / data_skip 를 샘플
//                      -> 2클럭 뒤 data_out = sat16(data_in + data_skip), valid 1클럭
//                      매 클럭 1개 처리 (enable 을 계속 1로 두면 매 클럭 결과)
//                      valid 가 아닐 때 data_out = data_in (bypass)
//  * 판정 : 입력마다 기대값을 큐에 넣고, valid 가 뜰 때마다 순서대로 꺼내 bit-exact 비교
//      - mism  : 기대값 불일치 (결과 latency 가 케이스 안에서 일정하지 않아도 1 증가)
//      - v_err : 큐가 비어 있는데 valid 가 뜬 횟수 (요청 없는 결과)
//      - t/o   : 입력했는데 결과가 나오지 않은 개수 (케이스 끝 drain 후 큐에 남은 수)
//      - PASS  : mism 0, v_err 0, t/o 0
//  * SNR(dB) : ideal = data_in + data_skip (포화 없는 실제 합) 기준
//              덧셈은 정확하므로 포화가 없으면 INF, 포화 케이스는 잘린 양이 noise 로 잡힘
//  * 구동 / 샘플 : posedge + IN_DLY 구동, posedge + SMP_DLY 샘플 (mac / pooling TB 와 동일)
//  * 결과 관찰 : top 에 valid 포트가 없으므로 dut.valid_mux 를 계층 참조
//               (post-impl 시뮬레이션에서 이 넷이 최적화로 사라지면 uut_residual 에 DONT_TOUCH)
//  * 실행 : Vivado Tcl 콘솔에서 run all
//
//  [웨이브폼 디버그 신호]
//    err_mism / err_valid / err_timeout : 오류 검출 시 다음 클럭에 1클럭 펄스, err_any = OR
//    dbg_tc, dbg_exp / dbg_got          : 현재 케이스 번호, 마지막 mismatch 기대값 / 실제값
//    dbg_* (RES_DBG_PROBE)              : residual_unit 내부 proc / done / valid / data_add
//    -> Tcl: add_wave {{/tb_residual_packed/err_*}} {{/tb_residual_packed/dbg_*}}
//    내부 이름이 없는 netlist 시뮬레이션이면 아래 `define RES_DBG_PROBE 를 주석 처리
//////////////////////////////////////////////////////////////////////////////////
`define RES_DBG_PROBE

module tb_residual_packed;

    // ------------------------------------------------------------------
    // Parameters
    // ------------------------------------------------------------------
    localparam integer WORD_W     = 16;
    localparam integer CLK_PERIOD = 10;
    localparam integer FULL       = (1 << (WORD_W-1));   // 32768
    localparam integer OUT_MAX    =  FULL - 1;
    localparam integer OUT_MIN    = -FULL;
    localparam integer QDEPTH     = 1024;                // 기대값 큐 깊이
    localparam integer DRAIN_CYC  = 16;                  // 케이스 끝 결과 대기 클럭
    localparam integer MAX_LOG    = 5;
    localparam integer MAX_TC     = 16;
    localparam integer NAME_LEN   = 40;
    localparam integer EXP_LAT    = 2;                   // RTL 분석 latency (표시용)

    parameter  real    IN_DLY     = 8.0;                 // [ns] posedge 후 입력 구동
    parameter  real    SMP_DLY    = 6.0;                 // [ns] posedge 후 valid / data_out 샘플
    parameter  integer IDLE_JUNK  = 1;                   // 1: enable=0 구간 입력에 난수, 0: 0

    // ------------------------------------------------------------------
    // DUT
    // ------------------------------------------------------------------
    reg                       clk       = 1'b0;
    reg                       rst_n     = 1'b0;
    reg                       enable    = 1'b0;
    reg  signed [WORD_W-1:0]  data_in   = {WORD_W{1'b0}};
    reg  signed [WORD_W-1:0]  data_skip = {WORD_W{1'b0}};
    wire signed [WORD_W-1:0]  data_out;

    residual_packed dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .enable    (enable),
        .data_in   (data_in),
        .data_skip (data_skip),
        .data_out  (data_out)
    );

    always #(CLK_PERIOD/2) clk = ~clk;

    wire res_valid = dut.valid_mux;            // 결과 유효 (내부 신호)

    integer cyc = 0;
    always @(posedge clk) cyc = cyc + 1;

    // ------------------------------------------------------------------
    // 기대값 큐 (입력 순서대로)
    // ------------------------------------------------------------------
    reg  signed [WORD_W-1:0] q_exp [0:QDEPTH-1];
    real                     q_ide [0:QDEPTH-1];
    integer                  q_cyc [0:QDEPTH-1];        // 입력이 샘플된 posedge 번호
    integer                  q_wr  = 0;
    integer                  q_rd  = 0;

    // ------------------------------------------------------------------
    // 케이스 통계
    // ------------------------------------------------------------------
    integer tc_id = 0;
    integer tc_trials, tc_mism, tc_timeout, tc_lat_min, tc_lat_max, tc_note, tc_v0, tc_mlog;
    real    tc_sig_pow, tc_err_pow, tc_max_err;
    integer v_err_cnt = 0;

    reg  [8*NAME_LEN-1:0] r_name     [0:MAX_TC-1];
    integer               r_trials   [0:MAX_TC-1];
    integer               r_mism     [0:MAX_TC-1];
    integer               r_verr     [0:MAX_TC-1];
    integer               r_to       [0:MAX_TC-1];
    integer               r_lmin     [0:MAX_TC-1];
    integer               r_lmax     [0:MAX_TC-1];
    integer               r_pass     [0:MAX_TC-1];
    integer               r_snr_type [0:MAX_TC-1];   // 0: 값, 1: INF, 2: N/A
    integer               r_note     [0:MAX_TC-1];
    real                  r_snr      [0:MAX_TC-1];
    real                  r_maxe     [0:MAX_TC-1];
    integer n_pass = 0, n_fail = 0;

    // ------------------------------------------------------------------
    // FAIL 1클럭 펄스 (웨이브폼용) : 이벤트 카운터가 바뀌면 다음 posedge 에서 1클럭 동안 1
    // ------------------------------------------------------------------
    integer                  mism_ev     = 0;
    integer                  to_ev       = 0;
    integer                  mism_seen   = 0;
    integer                  to_seen     = 0;
    integer                  verr_seen   = 0;
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

`ifdef RES_DBG_PROBE
    wire                     dbg_proc  = dut.uut_residual.proc;
    wire                     dbg_done  = dut.uut_residual.done;
    wire                     dbg_valid = dut.uut_residual.valid_out;
    wire signed [WORD_W:0]   dbg_add   = dut.uut_residual.data_add;
`endif

    // ------------------------------------------------------------------
    // Functions
    // ------------------------------------------------------------------
    integer seed = 20261117;

    function automatic signed [WORD_W-1:0] rnd;          // [lo, hi] 균일 난수
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

    function automatic integer sat_add;                  // golden : 16bit 포화 덧셈
        input integer a, b;
        integer s;
        begin
            s = a + b;
            if      (s > OUT_MAX) sat_add = OUT_MAX;
            else if (s < OUT_MIN) sat_add = OUT_MIN;
            else                  sat_add = s;
        end
    endfunction

    // ------------------------------------------------------------------
    // 결과 누적
    // ------------------------------------------------------------------
    task record;
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
                if (tc_mlog < MAX_LOG)
                    $display("    [MISMATCH] TC%0d #%0d : expected=%0d, got=%0d (ideal=%.1f)  t=%0t",
                             tc_id + 1, tag, gold, hw, ideal, $time);
                tc_mlog = tc_mlog + 1;
            end
        end
    endtask

    // ------------------------------------------------------------------
    // 결과 모니터 : 매 posedge + SMP_DLY 에 valid 확인 -> 큐에서 꺼내 비교
    // ------------------------------------------------------------------
    integer mon_lat, mon_vlog;
    initial mon_vlog = 0;

    always @(posedge clk) begin
        #(SMP_DLY);
        if (res_valid === 1'b1) begin
            if (q_rd == q_wr) begin
                v_err_cnt = v_err_cnt + 1;
                if (mon_vlog < MAX_LOG)
                    $display("    [VALID   ] TC%0d valid without pending input  t=%0t", tc_id + 1, $time);
                mon_vlog = mon_vlog + 1;
            end else begin
                mon_lat = cyc - q_cyc[q_rd % QDEPTH];
                if (mon_lat < tc_lat_min) tc_lat_min = mon_lat;
                if (mon_lat > tc_lat_max) tc_lat_max = mon_lat;
                record(q_ide[q_rd % QDEPTH], data_out, q_exp[q_rd % QDEPTH], q_rd);
                q_rd = q_rd + 1;
            end
        end
    end

    // ------------------------------------------------------------------
    // 구동
    // ------------------------------------------------------------------
    // 다음 posedge 에 샘플될 입력 1클럭 구동 (en=1 이면 기대값 큐에 push)
    task drive;
        input                     en;
        input signed [WORD_W-1:0] x;
        input signed [WORD_W-1:0] s;
        integer xi, si;
        real    id;
        begin
            @(posedge clk); #(IN_DLY);
            enable    = en;
            data_in   = en ? x : idle_data(0);
            data_skip = en ? s : idle_data(0);
            if (en) begin
                xi = x;
                si = s;
                id = xi + si;
                q_exp[q_wr % QDEPTH] = sat_add(xi, si);
                q_ide[q_wr % QDEPTH] = id;
                q_cyc[q_wr % QDEPTH] = cyc + 1;
                q_wr = q_wr + 1;
            end
        end
    endtask

    // enable=0 으로 DRAIN_CYC 대기 후 미수신 결과를 timeout 으로 처리
    task drain;
        integer miss;
        begin
            repeat (DRAIN_CYC) drive(1'b0, 0, 0);
            @(posedge clk); #(SMP_DLY + 1);
            miss = q_wr - q_rd;
            if (miss > 0) begin
                tc_timeout = tc_timeout + miss;
                to_ev      = to_ev + 1;
                $display("    [TIMEOUT ] TC%0d %0d result(s) missing  t=%0t", tc_id + 1, miss, $time);
                q_rd = q_wr;
            end
        end
    endtask

    task apply_reset;
        begin
            enable = 1'b0;
            rst_n  = 1'b0;
            q_rd   = q_wr;                               // 진행 중이던 입력은 버려짐 (정상)
            repeat (3) @(posedge clk);
            #(IN_DLY) rst_n = 1'b1;
            repeat (2) @(posedge clk);
        end
    endtask

    // ------------------------------------------------------------------
    // 케이스 시작 / 종료 / 출력
    // ------------------------------------------------------------------
    task case_begin;
        input [8*NAME_LEN-1:0] name;
        begin
            r_name[tc_id] = name;
            dbg_tc        = tc_id + 1;
            tc_trials     = 0;
            tc_mism       = 0;
            tc_timeout    = 0;
            tc_lat_min    = 1 << 30;
            tc_lat_max    = -1;
            tc_note       = 0;
            tc_mlog       = 0;
            tc_sig_pow    = 0.0;
            tc_err_pow    = 0.0;
            tc_max_err    = 0.0;
            tc_v0         = v_err_cnt;
            mon_vlog      = 0;
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
            $write("| trials=%4d | mism=%4d | v_err=%4d | t/o=%3d ",
                   r_trials[idx], r_mism[idx], r_verr[idx], r_to[idx]);
            if (r_lmax[idx] < 0)                 $write("| lat=  -   ");
            else if (r_lmin[idx] == r_lmax[idx]) $write("| lat=%3d   ", r_lmin[idx]);
            else                                 $write("| lat=%2d~%2d ", r_lmin[idx], r_lmax[idx]);
            $write("| max|e|=%10.1f LSB ", r_maxe[idx]);
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
                1 : $display("       note: data_out must equal data_in (enable=0)");
                2 : $display("       note: saturation error is counted as noise -> low SNR expected");
                3 : $display("       note: in-flight inputs dropped by reset, then normal results");
                default : ;
            endcase
        end
    endtask

    task case_end;
        begin
            if ((tc_lat_max >= 0) && (tc_lat_min != tc_lat_max)) begin
                tc_mism = tc_mism + 1;                   // latency 가 일정하지 않음
                mism_ev = mism_ev + 1;
                $display("    [MISMATCH] TC%0d latency not constant (%0d~%0d)", tc_id + 1, tc_lat_min, tc_lat_max);
            end
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
    // Test cases
    // ------------------------------------------------------------------
    // enable=0 : data_out == data_in (조합 bypass), valid 없어야 함
    task tc_bypass;
        input [8*NAME_LEN-1:0] name;
        input integer          trials;
        integer t, di;
        real    dr;
        begin
            case_begin(name);
            repeat (2) drive(1'b0, 0, 0);
            for (t = 0; t < trials; t = t + 1) begin
                @(posedge clk); #(IN_DLY);
                enable    = 1'b0;
                data_in   = rnd(-FULL, FULL-1);
                data_skip = rnd(-FULL, FULL-1);
                #(CLK_PERIOD - 1);                       // 조합 경로(IBUF -> mux -> OBUF) 지연 흡수
                di = data_in;
                dr = data_in;
                record(dr, data_out, di, t);
            end
            tc_note = 1;
            case_end;
        end
    endtask

    // 랜덤 입력 : en_pct = enable 확률(%) (100 이면 매 클럭 연속 입력)
    task tc_random;
        input [8*NAME_LEN-1:0] name;
        input integer          xlo, xhi, slo, shi, en_pct, samples, note;
        integer n;
        begin
            case_begin(name);
            n = 0;
            while (n < samples) begin
                if (($random(seed) & 32'h7fff_ffff) % 100 < en_pct) begin
                    drive(1'b1, rnd(xlo, xhi), rnd(slo, shi));
                    n = n + 1;
                end else
                    drive(1'b0, 0, 0);
            end
            drain;
            tc_note = note;
            case_end;
        end
    endtask

    // 1클럭 펄스 입력 (입력 사이 1~3 클럭 휴지)
    task tc_single;
        input [8*NAME_LEN-1:0] name;
        input integer          samples;
        integer t;
        begin
            case_begin(name);
            for (t = 0; t < samples; t = t + 1) begin
                drive(1'b1, rnd(-1024, 1023), rnd(-1024, 1023));
                repeat (1 + (($random(seed) & 32'h7fff_ffff) % 3)) drive(1'b0, 0, 0);
            end
            drain;
            case_end;
        end
    endtask

    // 포화 경계
    task tc_saturation;
        integer i;
        reg signed [WORD_W-1:0] a, b;
        begin
            case_begin("Saturation corners");
            for (i = 0; i < 14; i = i + 1) begin
                case (i)
                    0  : begin a =  32767; b =      0; end   //  32767        (no sat)
                    1  : begin a =  32767; b =      1; end   //  32768 ->  32767
                    2  : begin a =  32767; b =  32767; end   //  65534 ->  32767
                    3  : begin a = -32768; b =      0; end   // -32768        (no sat)
                    4  : begin a = -32768; b =     -1; end   // -32769 -> -32768
                    5  : begin a = -32768; b = -32768; end   // -65536 -> -32768
                    6  : begin a =  32767; b = -32768; end   //     -1
                    7  : begin a =  16384; b =  16383; end   //  32767        (no sat)
                    8  : begin a =  16384; b =  16384; end   //  32768 ->  32767
                    9  : begin a = -16384; b = -16384; end   // -32768        (no sat)
                    10 : begin a = -16384; b = -16385; end   // -32769 -> -32768
                    11 : begin a =      0; b =      0; end
                    12 : begin a =    256; b =   -256; end   //  1.0 + -1.0
                    default : begin a = 128; b = 128; end    //  0.5 + 0.5
                endcase
                drive(1'b1, a, b);
                drive(1'b0, 0, 0);
            end
            drain;
            tc_note = 2;
            case_end;
        end
    endtask

    // 연속 입력 중 비동기 리셋 -> valid 없음 -> 정상 복귀
    task tc_reset_mid;
        integer t;
        begin
            case_begin("Async reset during stream -> recovery");
            for (t = 0; t < 10; t = t + 1)
                drive(1'b1, rnd(-1024, 1023), rnd(-1024, 1023));
            #1;
            apply_reset;                                 // 진행 중 입력 폐기, 리셋 후 valid 가 뜨면 v_err
            repeat (8) drive(1'b0, 0, 0);
            for (t = 0; t < 200; t = t + 1)
                drive(1'b1, rnd(-1024, 1023), rnd(-1024, 1023));
            drain;
            tc_note = 3;
            case_end;
        end
    endtask

    // ------------------------------------------------------------------
    // Main
    // ------------------------------------------------------------------
    integer m;

    initial begin
        $display("");
        $display("====================================================================================================================================");
        $display(" tb_residual_packed : Q7.8 saturating residual add self-check");
        $display("   WORD_W=%0d  out = sat16(data_in + data_skip)  expected latency=%0d  throughput=1/clk", WORD_W, EXP_LAT);
        $display("   CLK=%0d ns (%0d MHz)  IN_DLY=%0.2f ns  SMP_DLY=%0.2f ns  IDLE_JUNK=%0d  seed=%0d",
                 CLK_PERIOD, 1000 / CLK_PERIOD, IN_DLY, SMP_DLY, IDLE_JUNK, seed);
        $display("   PASS = mism 0 && v_err 0 && t/o 0   (SNR vs unsaturated sum)");
        $display("====================================================================================================================================");

        rst_n = 1'b0;
        repeat (3) @(posedge clk);
        #(IN_DLY) rst_n = 1'b1;
        repeat (2) @(posedge clk);

        //          name                                   x lo    x hi   skip lo skip hi en%  samples note
        tc_bypass  ("Bypass (enable=0) after reset",                                          200);
        tc_single  ("Single pulse, typical (+-4.0)",                                          300);
        tc_random  ("Stream, enable held, typical",       -1024,   1023,  -1024,   1023, 100,  500, 0);
        tc_random  ("Random enable 50%, typical",         -1024,   1023,  -1024,   1023,  50,  500, 0);
        tc_random  ("Post-ReLU in + signed skip",             0,   4095,  -4096,   4095, 100,  500, 0);
        tc_saturation;
        tc_random  ("Full-scale random (saturation)",     -FULL, FULL-1,  -FULL, FULL-1, 100,  500, 2);
        tc_random  ("Random enable 30%, full-scale",      -FULL, FULL-1,  -FULL, FULL-1,  30,  300, 2);
        tc_reset_mid;
        tc_bypass  ("Bypass after operations",                                                100);

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

    initial begin
        #(10_000_000);
        $display("[FATAL] global simulation timeout");
        $finish;
    end

endmodule
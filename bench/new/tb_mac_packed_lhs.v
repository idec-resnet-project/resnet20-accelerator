`timescale 1ns / 1ps
//==============================================================================
// tb_mac_packed.v  -  mac_packed self-checking testbench
//------------------------------------------------------------------------------
//  * behavioral sim / post-implementation timing sim 둘 다 같은 파일로 동작
//      - DUT 는 parameter override 없이 인스턴스 (timing netlist 에는 parameter 가 없음)
//      - 입력 : posedge 후 IN_DLY 에 인가  (IN_DLY = IN_DLY_RATIO x 주기)
//      - 출력 : 시작 시 bypass 경로로 clk->out 을 자동 측정(calibration)해서
//               "launch edge + (tco_min + tco_max + T)/2" 시점에 샘플
//               (behavioral 은 tco = 0 -> launch edge + T/2)
//  * 데이터 : 16b signed Q7.8  (value = int / 256)
//  * DUT    : mac_packed  sum(fmap x weight) + (bias_in << FRAC_BITS) -> 반올림/포화 -> 16b
//             스케일 : fmap/weight/bias_in/data_out = Q7.8, 누산기 = Q15.16
//             bias 는 양자화 전(누산기 스케일, bias << 8)에 더함 : 반올림 1회 + 포화 1회
//             bias_in 은 케이스 동안 상수
//             last_input (선택 포트) : 윈도우 마지막 입력 클럭에 1 인지 확인 (없으면 `define NO_LAST_INPUT)
//             mac_v3 프로토콜 : 시작(첫 입력) 후 iter 개 입력을 연속으로 받음 (중간 valid_in 무시),
//                               윈도우 사이에 idle 3클럭 이상 필요 (gap >= 3)
//             iter 는 첫 입력 시점에만 래치 -> mixed 케이스에서 나머지 시점엔 garbage 인가
//  * 판정   : valid_out == 1 인 사이클의 data_out 을 샘플 -> 기대값(bit-exact)과 비교
//             bypass(enable=0) 케이스 : valid_out 이 한 번도 안 떠야 하고,
//                                      data_out 이 data_in 을 그대로 통과해야 PASS
//  * SNR    : 10*log10( sum(ref^2) / sum((dut-ref)^2) ), ref = 반올림 없는 실수 모델
//             오차 0 -> INF (평균에서 제외)
//  * latency: valid_in(=enable) 이 내려간 뒤 valid_out 이 1 이 될 때까지 지난 posedge 수
//             (= 마지막 입력을 캡처한 posedge 부터 valid_out 을 올린 posedge 까지)
//
//  주파수 변경 : CLK_FREQ_MHZ  (예: xelab ... -generic_top "CLK_FREQ_MHZ=50.0")
//  Vivado xsim : 기본 run time(1000ns)으로는 안 끝납니다 -> Tcl 콘솔에서  run all
//==============================================================================
module tb_mac_packed;

    //--------------------------------------------------------------------------
    // user parameters  (xelab -generic_top "NAME=VALUE" 로 변경 가능)
    //--------------------------------------------------------------------------
    parameter real    CLK_FREQ_MHZ = 100.0;  // 클럭 주파수 [MHz]
    parameter real    IN_DLY_RATIO = 0.6;    // 입력 인가 시점 = posedge 후 (IN_DLY_RATIO x 주기)
    parameter integer EN_MODE      = 0;      // 0: enable 케이스 동안 1 고정 / 1: enable 이 valid_in 과 같이 오르내림
    parameter integer REF_CLIP     = 1;      // SNR ideal 모델  1: Q7.8 범위 clip / 0: clip 없음
    parameter integer SEED         = 1;      // 랜덤 시드
    parameter integer FRAC_BITS    = 8;      // 소수부 비트 : Q7.8 -> 8 (fmap/weight/bias/data_out 모두 Q7.8)
    parameter integer CHECK_LAST   = 1;      // 1: last_input 확인 (post-impl timing sim 에서는 0 권장, 조합 출력)

    //--------------------------------------------------------------------------
    // derived / fixed
    //--------------------------------------------------------------------------
    localparam integer WORD_W     = 16;
    localparam real    CLK_PERIOD = 1000.0 / CLK_FREQ_MHZ;      // [ns]
    localparam real    IN_DLY     = CLK_PERIOD * IN_DLY_RATIO;  // [ns]
    localparam real    START_DLY  = 200.0;                      // GSR(100ns) 이후 시작 [ns]
    localparam real    QSCALE     = 1.0 * (1 << FRAC_BITS);     // Q7.8 -> 256.0
    localparam real    QMAX_R     = 32767.0 / QSCALE;
    localparam real    QMIN_R     = -32768.0 / QSCALE;

    localparam integer MAXS          = 4096;    // 입력 샘플
    localparam integer MAXO          = 4096;    // 출력 샘플
    localparam integer MAXH          = 16384;   // pass-through 기록 (사이클)
    localparam integer MAXC          = 64;      // 케이스
    localparam integer DRAIN         = 32;      // 마지막 입력 후 대기 클럭
    localparam integer CAL_N         = 8;       // calibration 패턴 수
    localparam integer MAX_ERR_PRINT = 5;
    localparam integer PT_X          = 99999;   // pass-through 기록에서 X 표시

    localparam integer DM_FULL   = 0;   // int16 전 범위 랜덤
    localparam integer DM_SMALL  = 1;   // [-512, 511]  (+-2.0)
    localparam integer DM_POS    = 2;   // [0, 32767]
    localparam integer DM_NEG    = 3;   // [-32768, -1]
    localparam integer DM_CUSTOM = 4;   // run_case 호출 전에 stim_x 를 직접 채움

    //--------------------------------------------------------------------------
    // DUT  (parameter override 없음 : post-impl timing netlist 와 동일하게 사용)
    //--------------------------------------------------------------------------
    localparam integer ITER_W = 16;

    reg               clk;
    reg               rst_n;
    reg               enable;
    reg               valid_in;
    reg  [ITER_W-1:0] iter;
    reg  [WORD_W-1:0] fmap_in;
    reg  [WORD_W-1:0] weight_in;
    reg  [WORD_W-1:0] bias_in;
    wire              valid_out;
    wire [WORD_W-1:0] data_out;
    wire              last_input;

    mac_packed dut
    (
        .clk       (clk),
        .rst_n     (rst_n),
        .enable    (enable),
        .valid_in  (valid_in),
        .iter      (iter),
        .fmap_in   (fmap_in),
        .weight_in (weight_in),
        .bias_in   (bias_in),
        .valid_out (valid_out),
`ifndef NO_LAST_INPUT
        .last_input(last_input),
`endif
        .data_out  (data_out)
    );
`ifdef NO_LAST_INPUT
    assign last_input = 1'b0;
    localparam integer HAS_LAST = 0;
`else
    localparam integer HAS_LAST = 1;
`endif

    //--------------------------------------------------------------------------
    // clock
    //--------------------------------------------------------------------------
    initial clk = 1'b0;
    always #(CLK_PERIOD / 2.0) clk = ~clk;

    //--------------------------------------------------------------------------
    // storage
    //--------------------------------------------------------------------------
    integer stim_x   [0:MAXS-1];
    integer stim_w   [0:MAXS-1];   // weight
    integer win_n    [0:MAXO-1];   // 윈도우별 iter
    integer iter_static;           // idle 때 iter 포트 값
    reg [31:0] bias_cfg;           // 케이스 동안 bias_in 값 (Q7.8 정수)
    integer iter_garb;             // 1 = idle / 윈도우 중간에 iter 포트 garbage
    reg     exp_last;              // 지금 버스에 있는 입력이 윈도우 마지막 입력이면 1
    integer li_err;                // last_input 불일치 수
    integer li_cnt;                // last_input 확인 횟수
    integer xx;
    integer exp_int  [0:MAXO-1];
    real    exp_real [0:MAXO-1];
    integer last_cap [0:MAXO-1];   // 토큰별 마지막 입력을 캡처한 posedge 번호
    integer got_val  [0:MAXO-1];
    integer got_cyc  [0:MAXO-1];   // valid_out 을 올린 posedge 번호
    integer pt_val   [0:MAXH-1];   // posedge 별 data_out (bypass 확인용)

    reg [8*64-1:0] r_name [0:MAXC-1];
    integer r_pass [0:MAXC-1];
    integer r_nexp [0:MAXC-1];
    integer r_ngot [0:MAXC-1];
    integer r_nerr [0:MAXC-1];
    integer r_lcnt [0:MAXC-1];
    integer r_lmin [0:MAXC-1];
    integer r_lmax [0:MAXC-1];
    real    r_lavg [0:MAXC-1];
    integer r_kind [0:MAXC-1];     // 0: finite SNR, 1: INF, 2: N/A
    real    r_snr  [0:MAXC-1];

    integer n_case;
    integer seed;
    integer en_cfg;
    integer cur_cap;
    integer ii;

    //--------------------------------------------------------------------------
    // posedge counter + output sampler
    //   샘플 시점 = posedge + smp_r,  샘플값의 launch edge = cyc - smp_k
    //--------------------------------------------------------------------------
    integer cyc;
    real    smp_r;
    integer smp_k;
    reg     mon_en;
    integer out_cnt;
    integer x_cnt;
    integer pt_base;

    initial
    begin : SAMPLER
        integer lc, ix;
        forever
        begin
            @(posedge clk);
            cyc = cyc + 1;
            if (mon_en && (CHECK_LAST != 0) && (HAS_LAST != 0))
            begin
                li_cnt = li_cnt + 1;
                if (last_input !== exp_last)
                begin
                    li_err = li_err + 1;
                    if (li_err <= MAX_ERR_PRINT)
                        $display("    last_input mismatch t=%0t : exp=%b got=%b", $time, exp_last, last_input);
                end
            end
            #(smp_r);
            lc = cyc - smp_k;
            if (mon_en)
            begin
                ix = lc - pt_base;
                if ((ix >= 0) && (ix < MAXH))
                begin
                    if ((^data_out) === 1'bx) pt_val[ix] = PT_X;
                    else                      pt_val[ix] = $signed(data_out);
                end
                if ((^valid_out) === 1'bx)
                begin
                    x_cnt = x_cnt + 1;
                    if (x_cnt <= MAX_ERR_PRINT)
                        $display("    [X] t=%0t valid_out=%b data_out=%h", $time, valid_out, data_out);
                end
                else if (valid_out === 1'b1)
                begin
                    if ((^data_out) === 1'bx)
                    begin
                        x_cnt = x_cnt + 1;
                        if (x_cnt <= MAX_ERR_PRINT)
                            $display("    [X] t=%0t valid_out=%b data_out=%h", $time, valid_out, data_out);
                    end
                    if (out_cnt < MAXO)
                    begin
                        got_val[out_cnt] = $signed(data_out);
                        got_cyc[out_cnt] = lc;
                    end
                    out_cnt = out_cnt + 1;
                end
            end
        end
    end

    //--------------------------------------------------------------------------
    // calibration watcher (data_out 변화 시각 기록)
    //--------------------------------------------------------------------------
    reg  [WORD_W-1:0] cal_pat;
    reg               cal_on;
    reg               cal_first;
    reg               cal_hit;
    real              cal_tfirst;
    real              cal_tset;
    real              tco_min;
    real              tco_max;

    always @(data_out)
    begin
        if (cal_on)
        begin
            if (!cal_first)
            begin
                cal_first  = 1'b1;
                cal_tfirst = $realtime;
            end
            if (data_out === cal_pat)
            begin
                cal_hit  = 1'b1;
                cal_tset = $realtime;
            end
        end
    end

    //--------------------------------------------------------------------------
    // helpers
    //--------------------------------------------------------------------------
    task tick;
        begin
            @(posedge clk);
            #(IN_DLY);
        end
    endtask

    task gen_val;
        input  integer mode;
        output integer v;
        reg    [31:0]  r;
        begin
            r = $random(seed);
            case (mode)
                DM_SMALL : v = $signed(r[9:0]);
                DM_POS   : v = r[14:0];
                DM_NEG   : v = -1 - $signed({1'b0, r[14:0]});
                default  : v = $signed(r[15:0]);
            endcase
        end
    endtask

    // 유효 입력 1개 (다음 posedge 에 캡처)
    task drive_in;
        input integer x;
        input integer w;
        input integer it;
        input integer is_last;
        begin
            enable    = en_cfg;
            valid_in  = 1'b1;
            exp_last  = (en_cfg != 0) && (is_last != 0);
            bias_in   = bias_cfg[WORD_W-1:0];
            iter      = it;
            fmap_in   = x;
            weight_in = w;
            cur_cap   = cyc + 1;
            tick;
        end
    endtask

    // idle 1클럭 (버스에는 랜덤 garbage)
    task drive_idle;
        reg [31:0] r;
        begin
            r         = $random(seed);
            enable    = (EN_MODE == 0) ? en_cfg : 1'b0;
            valid_in  = 1'b0;
            exp_last  = 1'b0;
            bias_in   = bias_cfg[WORD_W-1:0];
            fmap_in   = r[15:0];
            weight_in = r[31:16];
            if (iter_garb)
            begin
                r    = $random(seed);
                iter = r[ITER_W-1:0];
            end
            else
                iter = iter_static;
            tick;
        end
    endtask

    task reset_dut;
        begin
            mon_en    = 1'b0;
            valid_in  = 1'b0;
            enable    = (EN_MODE == 0) ? en_cfg : 1'b0;
            iter      = iter_static;
            exp_last  = 1'b0;
            bias_in   = bias_cfg[WORD_W-1:0];
            fmap_in   = {WORD_W{1'b0}};
            weight_in = {WORD_W{1'b0}};
            rst_n     = 1'b0;
            repeat (4) tick;
            rst_n     = 1'b1;
            repeat (4) drive_idle;
        end
    endtask

    task set_xw;
        input integer idx;
        input integer x;
        input integer w;
        begin
            stim_x[idx] = x;
            stim_w[idx] = w;
        end
    endtask

    task begin_case;
        integer k;
        begin
            for (k = 0; k < MAXH; k = k + 1) pt_val[k] = PT_X;
            out_cnt = 0;
            x_cnt   = 0;
            li_err  = 0;
            li_cnt  = 0;
            pt_base = cyc + 1;
            mon_en  = 1'b1;
        end
    endtask

    task case_header;
        input [8*64-1:0] name;
        begin
            $display("------------------------------------------------------------------------");
            $display("[CASE %2d] %0s", n_case + 1, name);
        end
    endtask

    //--------------------------------------------------------------------------
    // calibration : enable=0 (bypass) 에서 data_out <= fmap_in 레지스터의 clk->out 측정
    //--------------------------------------------------------------------------
    task calibrate;
        integer i, n_ok;
        real    d1, d2, ofs;
        begin
            en_cfg  = 0;
            cal_on  = 1'b0;
            reset_dut;
            fmap_in = {WORD_W{1'b0}};
            repeat (4) tick;
            tco_min = 1.0e9;
            tco_max = -1.0e9;
            n_ok    = 0;
            for (i = 0; i < CAL_N; i = i + 1)
            begin
                cal_pat   = (i % 2 == 0) ? {WORD_W{1'b1}} : {WORD_W{1'b0}};
                cal_first = 1'b0;
                cal_hit   = 1'b0;
                cal_on    = 1'b1;
                fmap_in   = cal_pat;
                @(posedge clk);
                d1 = $realtime;                    // capture edge 시각
                #(IN_DLY);
                repeat (3) tick;
                cal_on = 1'b0;
                if (cal_hit)
                begin
                    if (cal_tfirst - d1 < tco_min) tco_min = cal_tfirst - d1;
                    if (cal_tset   - d1 > tco_max) tco_max = cal_tset   - d1;
                    n_ok = n_ok + 1;
                end
            end
            if (n_ok == 0)
            begin
                $display("[CAL] WARNING : no data_out change seen on bypass path -> assuming tco = 0");
                tco_min = 0.0;
                tco_max = 0.0;
            end
            else if (n_ok < CAL_N)
                $display("[CAL] WARNING : only %0d / %0d patterns observed (check input timing IN_DLY)", n_ok, CAL_N);
            if (tco_min < 0.0) tco_min = 0.0;
            ofs   = (tco_min + tco_max + CLK_PERIOD) / 2.0;
            smp_k = $rtoi(ofs / CLK_PERIOD);
            smp_r = ofs - smp_k * CLK_PERIOD;
            $display("[CAL] clk->data_out : min %6.3f ns / max %6.3f ns  (behavioral = 0 / 0)", tco_min, tco_max);
            $display("[CAL] output sample : launch edge + %6.3f ns  (posedge + %6.3f ns, k=%0d)", ofs, smp_r, smp_k);
            if ((tco_max - tco_min) > 0.8 * CLK_PERIOD)
                $display("[CAL] WARNING : output bit skew (%6.3f ns) is large vs clock period", tco_max - tco_min);
        end
    endtask

    //--------------------------------------------------------------------------
    // check + report
    //   bypass = 1 : valid_out 0개 + data_out == data_in (pass-through) 확인
    //--------------------------------------------------------------------------
    task finish_case;
        input [8*64-1:0] name;
        input integer    n_exp;
        input integer    bypass;
        integer i, d, v, idx, n_got, n_err, pass, kind, lat, lmin, lmax, lsum, lcnt, ok, pt_lat;
        real    dr, sig, noi, snr, lavg;
        begin
            n_got = out_cnt;
            n_err = 0;
            sig   = 0.0;
            noi   = 0.0;
            lmin  = 1000000;
            lmax  = -1000000;
            lsum  = 0;
            lcnt  = 0;
            pass  = 0;

            if (bypass)
            begin
                // pass-through 지연 d (0~3) 중 전 샘플이 일치하는 최소값
                pt_lat = -1;
                for (d = 0; (d <= 3) && (pt_lat < 0); d = d + 1)
                begin
                    ok = 1;
                    for (i = 0; i < n_exp; i = i + 1)
                    begin
                        idx = last_cap[i] + d - pt_base;
                        if ((idx < 0) || (idx >= MAXH)) ok = 0;
                        else if (pt_val[idx] !== exp_int[i]) ok = 0;
                    end
                    if (ok) pt_lat = d;
                end
                d = (pt_lat < 0) ? 0 : pt_lat;
                for (i = 0; i < n_exp; i = i + 1)
                begin
                    idx = last_cap[i] + d - pt_base;
                    if ((idx >= 0) && (idx < MAXH)) v = pt_val[idx];
                    else                            v = PT_X;
                    if (v !== exp_int[i])
                    begin
                        n_err = n_err + 1;
                        if (n_err <= MAX_ERR_PRINT)
                            $display("    pass-through mismatch @%0d : exp=%0d  got=%0d", i, exp_int[i], v);
                        if (v == PT_X) v = 0;
                    end
                    dr  = v / QSCALE;
                    sig = sig + exp_real[i] * exp_real[i];
                    noi = noi + (dr - exp_real[i]) * (dr - exp_real[i]);
                end
                if (pt_lat >= 0)
                begin
                    lmin = pt_lat;
                    lmax = pt_lat;
                    lsum = pt_lat;
                    lcnt = 1;
                end
                if (n_got != 0)
                    $display("    valid_out asserted %0d times while enable=0 (expected 0)", n_got);
                pass = (pt_lat >= 0) && (n_got == 0) && (x_cnt == 0);
            end
            else
            begin
                for (i = 0; i < n_exp; i = i + 1)
                begin
                    if ((i < n_got) && (i < MAXO)) v = got_val[i];
                    else                           v = 0;

                    if ((i >= n_got) || (v !== exp_int[i]))
                    begin
                        n_err = n_err + 1;
                        if (n_err <= MAX_ERR_PRINT)
                        begin
                            if (i >= n_got)
                                $display("    mismatch @%0d : exp=%0d  got=<missing>", i, exp_int[i]);
                            else
                                $display("    mismatch @%0d : exp=%0d  got=%0d", i, exp_int[i], v);
                        end
                    end

                    if ((i < n_got) && (i < MAXO))
                    begin
                        lat  = got_cyc[i] - last_cap[i];
                        lsum = lsum + lat;
                        lcnt = lcnt + 1;
                        if (lat < lmin) lmin = lat;
                        if (lat > lmax) lmax = lat;
                    end

                    dr  = v / QSCALE;
                    sig = sig + exp_real[i] * exp_real[i];
                    noi = noi + (dr - exp_real[i]) * (dr - exp_real[i]);
                end
                if (n_got > n_exp)
                    $display("    extra outputs : %0d (expected %0d)", n_got - n_exp, n_exp);
                pass = (n_err == 0) && (n_got == n_exp) && (x_cnt == 0);
            end

            if (x_cnt > 0)
                $display("    X/Z on outputs : %0d samples  (timing violation / uninitialized FF?)", x_cnt);
            if ((CHECK_LAST != 0) && (HAS_LAST != 0))
            begin
                $display("  last_in : checked=%0d  mismatches=%0d", li_cnt, li_err);
                if (li_err != 0) pass = 0;
            end

            if (noi == 0.0)      begin kind = 1; snr = 0.0; end
            else if (sig == 0.0) begin kind = 2; snr = 0.0; end
            else                 begin kind = 0; snr = 10.0 * $log10(sig / noi); end

            lavg = (lcnt > 0) ? (lsum * 1.0 / lcnt) : 0.0;

            if (bypass)
                $display("  outputs : inputs=%0d  valid_out=%0d (expect 0)  pass-through mismatches=%0d", n_exp, n_got, n_err);
            else
                $display("  outputs : expected=%0d  received=%0d  mismatches=%0d", n_exp, n_got, n_err);

            if (lcnt == 0)
                $display("  LATENCY : N/A");
            else if (bypass)
                $display("  LATENCY : %0d clk  (bypass : data_in -> data_out pass-through, no valid_out)", lmin);
            else if (lmin == lmax)
                $display("  LATENCY : %0d clk  (posedges after valid_in(enable) falls)", lmin);
            else
                $display("  LATENCY : min %0d / avg %0.2f / max %0d clk  (posedges after valid_in(enable) falls)", lmin, lavg, lmax);

            if (kind == 0)      $display("  SNR     : %8.2f dB", snr);
            else if (kind == 1) $display("  SNR     :      INF dB  (DUT == ideal reference)");
            else                $display("  SNR     :      N/A     (reference power = 0)");
            $display("  RESULT  : %s", pass ? "PASS" : "FAIL");

            r_name[n_case] = name;
            r_pass[n_case] = pass;
            r_nexp[n_case] = n_exp;
            r_ngot[n_case] = n_got;
            r_nerr[n_case] = n_err;
            r_lcnt[n_case] = lcnt;
            r_lmin[n_case] = lmin;
            r_lmax[n_case] = lmax;
            r_lavg[n_case] = lavg;
            r_kind[n_case] = kind;
            r_snr [n_case] = snr;
            n_case         = n_case + 1;
        end
    endtask

    //--------------------------------------------------------------------------
    // summary
    //--------------------------------------------------------------------------
    task print_summary;
        input [8*32-1:0] title;
        integer i, npass, nfin, ninf, nlat, lmin_all, lmax_all;
        real    ssum, smin, smax, lsum_all;
        reg [8*9-1:0] s_lat;
        reg [8*9-1:0] s_snr;
        begin
            npass    = 0;
            nfin     = 0;
            ninf     = 0;
            nlat     = 0;
            ssum     = 0.0;
            smin     = 1.0e9;
            smax     = -1.0e9;
            lsum_all = 0.0;
            lmin_all = 1000000;
            lmax_all = -1000000;

            $display("");
            $display("====================================================================================================");
            $display("  %0s TEST SUMMARY   (CLK %0.3f MHz = %0.3f ns, IN_DLY %0.3f ns, EN_MODE %0d)",
                     title, CLK_FREQ_MHZ, CLK_PERIOD, IN_DLY, EN_MODE);
            $display("====================================================================================================");
            $display("  No | Result |  Exp |  Got |  Err |  Lat(clk) |  SNR(dB)  | Case");
            $display(" ----+--------+------+------+------+-----------+-----------+------------------------------------------");
            for (i = 0; i < n_case; i = i + 1)
            begin
                if (r_pass[i]) npass = npass + 1;

                if (r_lcnt[i] == 0)
                    s_lat = "      -  ";
                else if (r_lmin[i] == r_lmax[i])
                    $sformat(s_lat, "%9d", r_lmin[i]);
                else
                    $sformat(s_lat, "%4d~%4d", r_lmin[i], r_lmax[i]);

                if (r_lcnt[i] > 0)
                begin
                    nlat     = nlat + 1;
                    lsum_all = lsum_all + r_lavg[i];
                    if (r_lmin[i] < lmin_all) lmin_all = r_lmin[i];
                    if (r_lmax[i] > lmax_all) lmax_all = r_lmax[i];
                end

                if (r_kind[i] == 0)
                begin
                    nfin = nfin + 1;
                    ssum = ssum + r_snr[i];
                    if (r_snr[i] < smin) smin = r_snr[i];
                    if (r_snr[i] > smax) smax = r_snr[i];
                    $sformat(s_snr, "%9.2f", r_snr[i]);
                end
                else if (r_kind[i] == 1)
                begin
                    ninf  = ninf + 1;
                    s_snr = "      INF";
                end
                else
                    s_snr = "      N/A";

                $display("  %2d |  %s  | %4d | %4d | %4d | %s | %s | %0s",
                         i + 1, r_pass[i] ? "PASS" : "FAIL", r_nexp[i], r_ngot[i], r_nerr[i], s_lat, s_snr, r_name[i]);
            end
            $display(" ----+--------+------+------+------+-----------+-----------+------------------------------------------");
            $display("  TOTAL           : %0d / %0d PASS  (%0d FAIL)", npass, n_case, n_case - npass);
            if (nfin > 0)
            begin
                $display("  AVERAGE SNR     : %8.2f dB   (finite cases = %0d, INF cases = %0d excluded)", ssum / nfin, nfin, ninf);
                $display("  SNR MIN / MAX   : %8.2f dB / %8.2f dB", smin, smax);
            end
            else
                $display("  AVERAGE SNR     :      INF   (all %0d cases bit-exact)", ninf);
            if (nlat > 0)
                $display("  AVERAGE LATENCY : %8.2f clk  (min %0d / max %0d, cases = %0d)", lsum_all / nlat, lmin_all, lmax_all, nlat);
            else
                $display("  AVERAGE LATENCY :      N/A");
            $display("  * SNR reference : ideal real-valued model (%0s)", REF_CLIP ? "Q7.8 range clip" : "no clip");
            $display("  * LATENCY       : posedges after valid_in(enable) falls until valid_out=1  (bypass: pass-through delay)");
            $display("====================================================================================================");
        end
    endtask

    //--------------------------------------------------------------------------
    // reference helpers
    //--------------------------------------------------------------------------
    // (acc + (acc<0 ? h-1 : h)) >>> FRAC_BITS  -> int16 saturate   (h = 0.5 LSB)
    function integer mac_round_sat;
        input signed [63:0] a;
        reg   signed [63:0] h;
        reg   signed [63:0] t;
        begin
            h = 64'sd1 <<< (FRAC_BITS - 1);
            if (a < 0) t = (a + h - 64'sd1) >>> FRAC_BITS;
            else       t = (a + h) >>> FRAC_BITS;
            if (t > 64'sd32767)       mac_round_sat = 32767;
            else if (t < -64'sd32768) mac_round_sat = -32768;
            else                      mac_round_sat = t[31:0];
        end
    endfunction

    function real clipr;
        input real v;
        begin
            if (v > QMAX_R)      clipr = QMAX_R;
            else if (v < QMIN_R) clipr = QMIN_R;
            else                 clipr = v;
        end
    endfunction

    //--------------------------------------------------------------------------
    // run_case
    //   en     : 1 = MAC, 0 = bypass (n_win 개 샘플 pass-through)
    //   n_iter : 윈도우당 곱셈 수 (iter 포트)
    //   n_win  : 윈도우(출력) 개수
    //   dmode  : DM_SMALL / DM_FULL / DM_CUSTOM (stim_x, stim_w 를 미리 채움)
    //   gap    : 윈도우 사이 idle 클럭 (>= 3)
    //   imode  : 0 = iter 고정, 1 = 윈도우마다 iter = t % (n_iter+1), 시작 외 시점엔 iter garbage
    //   bias   : bias_in (Q7.8 정수, 케이스 동안 상수). 기대값 = sat(round(sum + (bias << FRAC_BITS)))
    //--------------------------------------------------------------------------
    task run_case;
        input [8*64-1:0] name;
        input integer    en;
        input integer    n_iter;
        input integer    n_win;
        input integer    dmode;
        input integer    gap;
        input integer    imode;
        input integer    bias;
        integer    t, j, k, x, nt, ne, idx, n_in, itv;
        reg [31:0] r;
        reg signed [63:0] acc;
        reg signed [63:0] prod;
        reg signed [63:0] bb;
        reg signed [33:0] a34;
        real       racc;
        begin
            //------------------------------------------------------------------
            // window sizes / stimulus
            //------------------------------------------------------------------
            n_in = 0;
            for (t = 0; t < n_win; t = t + 1)
            begin
                if (en && imode) win_n[t] = t % (n_iter + 1);
                else             win_n[t] = n_iter;
                if (en) n_in = n_in + ((win_n[t] < 1) ? 1 : win_n[t]);
                else    n_in = n_in + 1;
            end
            if (dmode != DM_CUSTOM)
            begin
                for (j = 0; j < n_in; j = j + 1)
                begin
                    gen_val(dmode, x);
                    stim_x[j] = x;
                    gen_val(dmode, x);
                    stim_w[j] = x;
                end
            end
            if (gap < 3 && en)
                $display("  [WARN] gap=%0d : mac_v3 needs >= 3 idle clocks between windows", gap);

            //------------------------------------------------------------------
            // reference
            //------------------------------------------------------------------
            idx = 0;
            for (t = 0; t < n_win; t = t + 1)
            begin
                if (en)
                begin
                    nt  = win_n[t];
                    ne  = (nt < 1) ? 1 : nt;
                    acc = 0;
                    for (k = 0; k < nt; k = k + 1)
                    begin
                        prod = stim_x[idx + k];
                        prod = prod * stim_w[idx + k];
                        acc  = acc + prod;
                    end
                    idx         = idx + ne;
                    bb          = bias;                   // Q7.8 -> Q15.16 정렬 후 양자화 전 덧셈
                    bb          = bb <<< FRAC_BITS;
                    acc         = acc + bb;
                    a34         = acc[33:0];              // RTL 누산기 폭(34b) 그대로
                    exp_int[t]  = mac_round_sat(a34);
                    racc        = acc;
                    exp_real[t] = REF_CLIP ? clipr(racc / (QSCALE * QSCALE)) : (racc / (QSCALE * QSCALE));
                end
                else
                begin
                    exp_int[t]  = stim_x[t];
                    exp_real[t] = stim_x[t] / QSCALE;
                end
            end

            case_header(name);
            $display("  config  : enable=%0d  iter=%0d%0s  windows=%0d  gap=%0d  bias=%0d (%0.4f)",
                     en, n_iter, imode ? " (mixed 0~iter, iter port garbage)" : " ", n_win, gap,
                     bias, bias / QSCALE);

            //------------------------------------------------------------------
            // drive
            //------------------------------------------------------------------
            en_cfg      = en;
            iter_static = n_iter;
            bias_cfg    = bias;
            iter_garb   = 0;
            reset_dut;
            iter_garb   = (en && imode) ? 1 : 0;
            begin_case;

            idx = 0;
            for (t = 0; t < n_win; t = t + 1)
            begin
                if (en)
                begin
                    nt = win_n[t];
                    ne = (nt < 1) ? 1 : nt;
                    for (k = 0; k < ne; k = k + 1)
                    begin
                        if ((k == 0) || !imode)
                            itv = nt;
                        else
                        begin
                            r   = $random(seed);
                            itv = r[ITER_W-1:0];
                        end
                        drive_in(stim_x[idx], stim_w[idx], itv, (k == ne - 1));
                        idx = idx + 1;
                    end
                end
                else
                begin
                    drive_in(stim_x[t], stim_w[t], n_iter, 0);
                end
                last_cap[t] = cur_cap;
                for (k = 0; k < gap; k = k + 1) drive_idle;
            end
            repeat (DRAIN) drive_idle;
            mon_en    = 1'b0;
            iter_garb = 0;

            finish_case(name, n_win, (en == 0));
        end
    endtask

    //--------------------------------------------------------------------------
    // watchdog
    //--------------------------------------------------------------------------
    initial
    begin
        #(START_DLY);
        repeat (400000) @(posedge clk);
        $display("[TB] GLOBAL TIMEOUT");
        print_summary("mac_packed");
        $finish;
    end

    //--------------------------------------------------------------------------
    // test sequence
    //--------------------------------------------------------------------------
    initial
    begin
        cyc         = 0;
        smp_r       = CLK_PERIOD / 2.0;
        smp_k       = 0;
        mon_en      = 1'b0;
        out_cnt     = 0;
        x_cnt       = 0;
        pt_base     = 0;
        cal_on      = 1'b0;
        n_case      = 0;
        seed        = SEED;
        en_cfg      = 0;
        cur_cap     = 0;
        iter_static = 0;
        iter_garb   = 0;
        bias_cfg    = 0;
        exp_last    = 1'b0;
        li_err      = 0;
        li_cnt      = 0;
        rst_n       = 1'b0;
        enable      = 1'b0;
        valid_in    = 1'b0;
        iter        = {ITER_W{1'b0}};
        fmap_in     = {WORD_W{1'b0}};
        weight_in   = {WORD_W{1'b0}};
        bias_in     = {WORD_W{1'b0}};

        #(START_DLY);
        tick;

        $display("========================================================================");
        $display(" tb_mac_packed  (FRAC_BITS %0d, CLK %0.3f MHz = %0.3f ns, IN_DLY %0.3f ns, EN_MODE %0d, REF_CLIP %0d)",
                 FRAC_BITS, CLK_FREQ_MHZ, CLK_PERIOD, IN_DLY, EN_MODE, REF_CLIP);
        $display(" bias added before quantization : out = sat(round(sum(x*w) + (bias << %0d)))   last_input check %0d",
                 FRAC_BITS, (CHECK_LAST != 0) && (HAS_LAST != 0));
        $display("========================================================================");

        calibrate;

        //        name                                          en  iter  win  dmode      gap imode  bias
        run_case("[MAC] iter=1",                                 1,    1,  32, DM_SMALL,    4, 0,      0);
        run_case("[MAC] iter=3",                                 1,    3,  32, DM_SMALL,    4, 0,      0);
        run_case("[MAC] iter=9 (3x3 kernel)",                    1,    9,  32, DM_SMALL,    4, 0,      0);
        run_case("[MAC] iter=16",                                1,   16,  16, DM_SMALL,    4, 0,      0);
        run_case("[MAC] iter=25 (5x5 kernel)",                   1,   25,  16, DM_SMALL,    4, 0,      0);
        run_case("[MAC] iter=64 (long accumulation)",            1,   64,   8, DM_SMALL,    4, 0,      0);
        run_case("[MAC] iter=0 (expect 0)",                      1,    0,   8, DM_SMALL,    4, 0,      0);
        run_case("[MAC] mixed iter 0~9, iter port garbage",      1,    9,  30, DM_SMALL,    4, 1,      0);
        run_case("[MAC] iter=9, min gap (3 idle clk)",           1,    9,  32, DM_SMALL,    3, 0,      0);
        run_case("[MAC] iter=9, single-shot (gap 12)",           1,    9,  16, DM_SMALL,   12, 0,      0);

        // bias (Q7.8) : 양자화 전 덧셈
        run_case("[BIAS] iter=9, bias=+1.0 (256)",               1,    9,  32, DM_SMALL,    4, 0,    256);
        run_case("[BIAS] iter=9, bias=-1.171875 (-300)",         1,    9,  32, DM_SMALL,    4, 0,   -300);
        run_case("[BIAS] iter=1, bias=+0.0039 (1 LSB)",          1,    1,  32, DM_SMALL,    4, 0,      1);
        run_case("[BIAS] iter=25, bias=+3.5 (896)",              1,   25,  16, DM_SMALL,    4, 0,    896);
        run_case("[BIAS] iter=0 (expect bias = 100)",            1,    0,   8, DM_SMALL,    4, 0,    100);
        run_case("[BIAS] iter=0 (expect bias = -32768)",         1,    0,   8, DM_SMALL,    4, 0, -32768);
        run_case("[BIAS] mixed iter 0~9, bias=-77",              1,    9,  30, DM_SMALL,    4, 1,    -77);
        run_case("[BIAS] bias=+32767 (+saturation)",             1,    9,  16, DM_SMALL,    4, 0,  32767);
        run_case("[BIAS] bias=-32768 (-saturation)",             1,    9,  16, DM_SMALL,    4, 0, -32768);
        run_case("[BIAS] full-range random iter=4, bias=+5000",  1,    4,  32, DM_FULL,     4, 0,   5000);

        // rounding boundary (iter=1) : +-0.5, +-1.5 LSB  (h = 0.5 LSB = 1 << (FRAC_BITS-1))
        ii = 1 << (FRAC_BITS - 1);
        set_xw(0,    1, ii);       //  +0.5 LSB ->  1
        set_xw(1,   -1, ii);       //  -0.5 LSB -> -1
        set_xw(2,    1, ii - 1);   //  <0.5     ->  0
        set_xw(3,   -1, ii - 1);   //  >-0.5    ->  0
        set_xw(4,    3, ii);       //  +1.5     ->  2
        set_xw(5,   -3, ii);       //  -1.5     -> -2
        set_xw(6,    1, ii + 1);   //  >0.5     ->  1
        set_xw(7,   -1, ii + 1);   //  <-0.5    -> -1
        set_xw(8,   ii, ii);       //  ii*ii / 2^F
        set_xw(9, 1 - 2*ii, 1);    //  -(1 LSB - 1) -> -1
        run_case("[MAC] rounding boundary (iter=1)",             1,    1,  10, DM_CUSTOM,   4, 0,      0);

        // bias 와 합친 뒤 반올림 1회 : sum = -0.5 LSB, bias = +1 LSB -> +0.5 LSB -> 1 (따로 반올림하면 0)
        for (ii = 0; ii < 8; ii = ii + 1) set_xw(ii, -1, 1 << (FRAC_BITS - 1));
        run_case("[BIAS] round once after bias (-0.5+1 -> 1)",   1,    1,   8, DM_CUSTOM,   4, 0,      1);

        // +/- saturation (iter=4, full-scale)
        for (ii = 0;  ii < 4;  ii = ii + 1) set_xw(ii, -32768, -32768);
        for (ii = 4;  ii < 8;  ii = ii + 1) set_xw(ii, -32768,  32767);
        for (ii = 8;  ii < 12; ii = ii + 1) set_xw(ii,  32767,  32767);
        for (ii = 12; ii < 16; ii = ii + 1) set_xw(ii,  32767, -32768);
        run_case("[MAC] +/- saturation (full-scale, iter=4)",    1,    4,   4, DM_CUSTOM,   4, 0,      0);

        // full-range random : iter=7 = 34b 누산기 overflow 없는 최대
        run_case("[MAC] full-range random iter=7 (saturation)",  1,    7,  32, DM_FULL,     4, 0,      0);

        // all zero
        for (ii = 0; ii < 36; ii = ii + 1) set_xw(ii, 0, 0);
        run_case("[MAC] all-zero input",                         1,    9,   4, DM_CUSTOM,   4, 0,      0);

        // weight = 1.0 (1 << FRAC_BITS) -> 출력 = x 그대로
        for (ii = 0; ii < 32; ii = ii + 1)
        begin
            gen_val(DM_FULL, xx);
            set_xw(ii, xx, 1 << FRAC_BITS);
        end
        run_case("[MAC] weight=1.0 identity (iter=1)",           1,    1,  32, DM_CUSTOM,   4, 0,      0);

        // weight = 1.0 + bias -> 출력 = sat(x + bias)
        for (ii = 0; ii < 32; ii = ii + 1)
        begin
            gen_val(DM_FULL, xx);
            set_xw(ii, xx, 1 << FRAC_BITS);
        end
        run_case("[BIAS] weight=1.0, bias=-12345 (x + bias)",    1,    1,  32, DM_CUSTOM,   4, 0, -12345);

        // bypass : bias_in 무시
        run_case("[MAC] bypass (enable=0)",                      0,    9,  64, DM_FULL,     0, 0,      0);
        run_case("[MAC] bypass (enable=0), bias_in=1234 ignored",0,    9,  64, DM_FULL,     0, 0,   1234);

        print_summary("mac_packed");
        $finish;
    end

endmodule
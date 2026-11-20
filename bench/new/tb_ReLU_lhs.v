`timescale 1ns / 1ps
//==============================================================================
// tb_ReLU_packed.v  -  ReLU_packed self-checking testbench
//------------------------------------------------------------------------------
//  * behavioral sim / post-implementation timing sim 둘 다 같은 파일로 동작
//      - DUT 는 parameter override 없이 인스턴스 (timing netlist 에는 parameter 가 없음)
//      - 입력 : posedge 후 IN_DLY 에 인가  (IN_DLY = IN_DLY_RATIO x 주기)
//      - 출력 : 시작 시 bypass 경로로 clk->out 을 자동 측정(calibration)해서
//               "launch edge + (tco_min + tco_max + T)/2" 시점에 샘플
//               (behavioral 은 tco = 0 -> launch edge + T/2)
//  * 데이터 : 16b signed Q7.8  (value = int / 256)
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
module tb_ReLU_packed;

    //--------------------------------------------------------------------------
    // user parameters  (xelab -generic_top "NAME=VALUE" 로 변경 가능)
    //--------------------------------------------------------------------------
    parameter real    CLK_FREQ_MHZ = 100.0;  // 클럭 주파수 [MHz]
    parameter real    IN_DLY_RATIO = 0.6;    // 입력 인가 시점 = posedge 후 (IN_DLY_RATIO x 주기)
    parameter integer EN_MODE      = 0;      // 0: enable 케이스 동안 1 고정 / 1: enable 이 valid_in 과 같이 오르내림
    parameter integer REF_CLIP     = 1;      // SNR ideal 모델  1: Q7.8 범위 clip / 0: clip 없음
    parameter integer SEED         = 1;      // 랜덤 시드

    //--------------------------------------------------------------------------
    // derived / fixed
    //--------------------------------------------------------------------------
    localparam integer WORD_W     = 16;
    localparam real    CLK_PERIOD = 1000.0 / CLK_FREQ_MHZ;      // [ns]
    localparam real    IN_DLY     = CLK_PERIOD * IN_DLY_RATIO;  // [ns]
    localparam real    START_DLY  = 200.0;                      // GSR(100ns) 이후 시작 [ns]
    localparam real    QSCALE     = 256.0;
    localparam real    QMAX_R     = 32767.0 / 256.0;
    localparam real    QMIN_R     = -32768.0 / 256.0;

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
    reg               clk;
    reg               rst_n;
    reg               enable;
    reg               valid_in;
    reg  [WORD_W-1:0] data_in;
    wire              valid_out;
    wire [WORD_W-1:0] data_out;

    ReLU_packed dut
    (
        .clk       (clk),
        .rst_n     (rst_n),
        .enable    (enable),
        .valid_in  (valid_in),
        .data_in   (data_in),
        .valid_out (valid_out),
        .data_out  (data_out)
    );

    //--------------------------------------------------------------------------
    // clock
    //--------------------------------------------------------------------------
    initial clk = 1'b0;
    always #(CLK_PERIOD / 2.0) clk = ~clk;

    //--------------------------------------------------------------------------
    // storage
    //--------------------------------------------------------------------------
    integer stim_x   [0:MAXS-1];
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
        begin
            enable   = en_cfg;
            valid_in = 1'b1;
            data_in  = x;
            cur_cap  = cyc + 1;
            tick;
        end
    endtask

    // idle 1클럭 (버스에는 랜덤 garbage)
    task drive_idle;
        reg [31:0] r;
        begin
            r        = $random(seed);
            enable   = (EN_MODE == 0) ? en_cfg : 1'b0;
            valid_in = 1'b0;
            data_in  = r[15:0];
            tick;
        end
    endtask

    task reset_dut;
        begin
            mon_en   = 1'b0;
            valid_in = 1'b0;
            enable   = (EN_MODE == 0) ? en_cfg : 1'b0;
            data_in  = {WORD_W{1'b0}};
            rst_n    = 1'b0;
            repeat (4) tick;
            rst_n    = 1'b1;
            repeat (4) drive_idle;
        end
    endtask

    task begin_case;
        integer k;
        begin
            for (k = 0; k < MAXH; k = k + 1) pt_val[k] = PT_X;
            out_cnt = 0;
            x_cnt   = 0;
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
    // calibration : enable=0 (bypass) 에서 data_out <= data_in 레지스터의 clk->out 측정
    //--------------------------------------------------------------------------
    task calibrate;
        integer i, n_ok;
        real    d1, d2, ofs;
        begin
            en_cfg  = 0;
            cal_on  = 1'b0;
            reset_dut;
            data_in = {WORD_W{1'b0}};
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
                data_in   = cal_pat;
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
    // run_case
    //   en     : 1 = ReLU, 0 = bypass
    //   n      : 샘플 수
    //   gap    : 샘플마다 뒤에 붙는 idle 클럭 (0 = back-to-back)
    //   bubble : 1 = 샘플 앞에 1/4 확률로 idle 1클럭
    //--------------------------------------------------------------------------
    task run_case;
        input [8*64-1:0] name;
        input integer    en;
        input integer    n;
        input integer    dmode;
        input integer    gap;
        input integer    bubble;
        integer    j, k, x;
        reg [31:0] r;
        begin
            if (dmode != DM_CUSTOM)
            begin
                for (j = 0; j < n; j = j + 1)
                begin
                    gen_val(dmode, x);
                    stim_x[j] = x;
                end
            end

            for (j = 0; j < n; j = j + 1)
            begin
                if (en) exp_int[j] = (stim_x[j] < 0) ? 0 : stim_x[j];
                else    exp_int[j] = stim_x[j];
                exp_real[j] = exp_int[j] / QSCALE;
            end

            case_header(name);
            $display("  config  : enable=%0d  samples=%0d  gap=%0d  bubble=%0d", en, n, gap, bubble);

            en_cfg = en;
            reset_dut;
            begin_case;

            for (j = 0; j < n; j = j + 1)
            begin
                if (bubble)
                begin
                    r = $random(seed);
                    if (r[1:0] == 2'b00) drive_idle;
                end
                drive_in(stim_x[j]);
                last_cap[j] = cur_cap;
                for (k = 0; k < gap; k = k + 1) drive_idle;
            end
            repeat (DRAIN) drive_idle;
            mon_en = 1'b0;

            finish_case(name, n, (en == 0));
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
        print_summary("ReLU_packed");
        $finish;
    end

    //--------------------------------------------------------------------------
    // test sequence
    //--------------------------------------------------------------------------
    initial
    begin
        cyc      = 0;
        smp_r    = CLK_PERIOD / 2.0;
        smp_k    = 0;
        mon_en   = 1'b0;
        out_cnt  = 0;
        x_cnt    = 0;
        pt_base  = 0;
        cal_on   = 1'b0;
        n_case   = 0;
        seed     = SEED;
        en_cfg   = 0;
        cur_cap  = 0;
        rst_n    = 1'b0;
        enable   = 1'b0;
        valid_in = 1'b0;
        data_in  = {WORD_W{1'b0}};

        #(START_DLY);
        tick;

        $display("========================================================================");
        $display(" tb_ReLU_packed  (Q7.8, CLK %0.3f MHz = %0.3f ns, IN_DLY %0.3f ns, EN_MODE %0d, REF_CLIP %0d)",
                 CLK_FREQ_MHZ, CLK_PERIOD, IN_DLY, EN_MODE, REF_CLIP);
        $display("========================================================================");

        calibrate;

        //        name                                        en    n  dmode     gap bubble
        run_case("[ReLU] full-range random, back-to-back",     1,  256, DM_FULL,   0, 0);
        run_case("[ReLU] full-range random, random bubble",    1,  256, DM_FULL,   0, 1);
        run_case("[ReLU] single-shot (gap 4)",                 1,   32, DM_FULL,   4, 0);
        run_case("[ReLU] small range (+-2.0), bubble",         1,  128, DM_SMALL,  0, 1);
        run_case("[ReLU] all positive (pass)",                 1,   64, DM_POS,    0, 0);
        run_case("[ReLU] all negative (-> 0)",                 1,   64, DM_NEG,    0, 0);

        // boundary values
        stim_x[ 0] = -32768; stim_x[ 1] = -32767; stim_x[ 2] =   -256; stim_x[ 3] =     -1;
        stim_x[ 4] =      0; stim_x[ 5] =      1; stim_x[ 6] =    255; stim_x[ 7] =    256;
        stim_x[ 8] =  32766; stim_x[ 9] =  32767; stim_x[10] = -12345; stim_x[11] =  12345;
        stim_x[12] =     -2; stim_x[13] =      2; stim_x[14] =   -129; stim_x[15] =    128;
        run_case("[ReLU] boundary values",                     1,   16, DM_CUSTOM, 0, 0);

        // 부호 교대 (+, -, +, - ...)
        for (ii = 0; ii < 64; ii = ii + 1)
            stim_x[ii] = (ii % 2) ? -(ii * 300 + 1) : (ii * 300 + 1);
        run_case("[ReLU] alternating sign",                    1,   64, DM_CUSTOM, 0, 0);

        run_case("[ReLU] long stream (1024, back-to-back)",    1, 1024, DM_FULL,   0, 0);
        run_case("[ReLU] bypass (enable=0)",                   0,   64, DM_FULL,   0, 1);

        print_summary("ReLU_packed");
        $finish;
    end

endmodule
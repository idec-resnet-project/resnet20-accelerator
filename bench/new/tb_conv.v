`timescale 1ns / 1ps
//==============================================================================
// tb_conv_top.v
//------------------------------------------------------------------------------
//  conv_top self-checking testbench
//
//  * 데이터 포맷 : 16b signed Q7.8 (value = int / 256, range -128.0 ~ +127.996)
//      - MAC : Q7.8 x Q7.8 = Q15.16 누적 -> post_mac (>>>8, 반올림, 포화) -> Q7.8
//  * 기준 모델 2개
//      - exp_int  : RTL 과 bit-exact 해야 하는 고정소수점(Q7.8) 정수 모델  -> PASS/FAIL
//      - exp_real : 반올림/절삭이 없는 이상적 실수 모델(표현 범위 clip 만 적용) -> SNR
//  * SNR(dB) = 10*log10( sum(ref^2) / sum((dut-ref)^2) ),  dut/ref 는 Q7.8 -> 실수(/256)
//      - 오차 0  -> "INF" (bit-exact) : 평균 계산에서 제외
//  * 케이스 구성
//      A. 블록 0개(bypass)
//      B. 블록 1개 : MAC / ReLU / RES / MAXPOOL / GAP
//      C. 블록 2개 : 모든 조합
//      D. 블록 3개 : 모든 조합
//      E. 블록 4개 : MAC+ReLU+RES+(MAX|GAP)
//      F. 코너 케이스
//  * 결과는 케이스마다 즉시 출력, 마지막에 요약표 + 평균 SNR 출력
//
//  Vivado xsim : 기본 run time(1000ns)으로는 끝까지 안 돕니다. Tcl 콘솔에서  run all
//==============================================================================
//------------------------------------------------------------------------------
// DUT 선택 : 기본은 conv_top_wrapper (입출력 IOB 레지스터 + reset sync)
//   conv_top 을 직접 쓰려면 컴파일 옵션으로  -d DUT_MODULE=conv_top  (xvlog)
//------------------------------------------------------------------------------
`ifndef DUT_MODULE
`define DUT_MODULE conv_top_wrapper
`endif

module tb_conv_top;

    //--------------------------------------------------------------------------
    // parameters
    //--------------------------------------------------------------------------
    localparam integer WORD_W   = 16;
    localparam integer BW_MAC   = 16;
    localparam integer BW_POOL  = 16;
    localparam integer BW_GAP   = 16;
    localparam integer PC       = 1;
    localparam integer PF       = 1;

    // CLK_PERIOD : post-impl timing sim 에서 clk->out 이 주기를 넘으면 늘려야 함 (예: 20.0)
    parameter  real    CLK_PERIOD = 20.0;
    // IN_DLY : posedge 후 이 시간(ns)에 입력 인가 (0 < IN_DLY < CLK_PERIOD)
    //   post-impl (xc7z020-1, wrapper IOB 입력) report_datasheet 기준
    //     hold  : 엣지 후 ~5.25ns 까지 입력 유지 필요 (clock insertion ~5ns)
    //     setup : 다음 엣지 + ~1.1ns 이전 도착
    //   -> 입력 변경 허용 구간 = 엣지 후 5.25 ~ (CLK_PERIOD + 1.1) ns
    //   0.5*T(=5ns) 는 hold 경계라 비트별로 캡처 사이클이 갈림 -> 0.75*T 사용
    parameter  real    IN_DLY     = CLK_PERIOD * 0.75;
    localparam real    QSCALE     = 256.0;            // Q7.8 : 1 sign + 7 int + 8 frac, LSB = 2^-8
    localparam real    QMAX_R     = 32767.0 / 256.0;
    localparam real    QMIN_R     = -32768.0 / 256.0;

    localparam integer MAXS          = 8192;  // 입력 샘플 최대 개수
    localparam integer MAXT          = 2048;  // 1단(MAC 출력 or 입력) 토큰 최대 개수
    localparam integer MAXO          = 1024;  // 출력 최대 개수
    localparam integer MAXC          = 64;    // 케이스 최대 개수
    localparam integer MAC_GAP       = 4;     // MAC 윈도우 사이 idle 클럭 (최소 3 필요)
    localparam integer POOL_GAP      = 2;     // pooling 윈도우 사이 idle 클럭 (최소 1 필요)
    localparam integer DRAIN         = 150;   // 마지막 입력 이후 출력 대기 클럭
    localparam integer MAX_ERR_PRINT = 5;
    localparam real    START_DELAY   = 200.0; // TB 시작 전 대기 (ns)

    localparam integer DM_SMALL  = 0;   // x,w 랜덤 [-512, 511]  (+-2.0 in Q7.8)
    localparam integer DM_FULL   = 1;   // x,w 랜덤 int16 전 범위
    localparam integer DM_CUSTOM = 2;   // 호출 전에 stim_x/stim_w 를 직접 채움

    //--------------------------------------------------------------------------
    // DUT I/O
    //--------------------------------------------------------------------------
    reg                         clk;
    reg                         nrst;
    reg                         mac_enable;
    reg  [BW_MAC-1:0]           mac_iteration;
    reg                         residual_enable;
    reg                         relu_enable;
    reg                         pooling_enable;
    reg  [BW_POOL-1:0]          pooling_iteration;
    reg                         gap_enable;
    reg  [BW_GAP-1:0]           gap_iteration;
    reg                         in_enable;
    reg  [PC*WORD_W-1:0]        in_data;
    reg  [PC*WORD_W-1:0]        kernel_data;
    reg  [PC*WORD_W-1:0]        bias_data;
    wire                        out_enable;
    wire [WORD_W-1:0]           out_data;

    `DUT_MODULE
    #(
        .WORD_W                     (WORD_W),
        .BITWIDTH_MAC_ITERATION     (BW_MAC),
        .BITWIDTH_POOLING_ITERATION (BW_POOL),
        .BITWIDTH_GAP_ITERATION     (BW_GAP),
        .PARALLEL_PC                (PC),
        .PARALLEL_PF                (PF)
    )
    dut
    (
        .clk               (clk),
        .nrst              (nrst),
        .mac_enable        (mac_enable),
        .mac_iteration     (mac_iteration),
        .residual_enable   (residual_enable),
        .relu_enable       (relu_enable),
        .pooling_enable    (pooling_enable),
        .pooling_iteration (pooling_iteration),
        .gap_enable        (gap_enable),
        .gap_iteration     (gap_iteration),
        .in_enable         (in_enable),
        .in_data           (in_data),
        .kernel_data       (kernel_data),
        .bias_data         (bias_data),
        .out_enable        (out_enable),
        .out_data          (out_data)
    );

    //--------------------------------------------------------------------------
    // clock
    //--------------------------------------------------------------------------
    initial clk = 1'b0;
    always #(CLK_PERIOD/2.0) clk = ~clk;

    //--------------------------------------------------------------------------
    // storage
    //--------------------------------------------------------------------------
    integer stim_x   [0:MAXS-1];
    integer stim_w   [0:MAXS-1];
    integer t_int    [0:MAXT-1];
    real    t_real   [0:MAXT-1];
    integer exp_int  [0:MAXO-1];
    real    exp_real [0:MAXO-1];
    integer dut_out  [0:MAXO-1];

    reg [8*64-1:0] r_name [0:MAXC-1];
    integer r_pass [0:MAXC-1];
    integer r_nexp [0:MAXC-1];
    integer r_ngot [0:MAXC-1];
    integer r_nerr [0:MAXC-1];
    integer r_lat  [0:MAXC-1];
    integer r_kind [0:MAXC-1];   // 0: finite SNR, 1: INF (bit-exact), 2: N/A
    real    r_snr  [0:MAXC-1];

    integer n_case;
    integer seed;
    integer ii;
    reg [31:0] rr;

    //--------------------------------------------------------------------------
    // cycle counter & output monitor (posedge 샘플, 입력은 posedge+IN_DLY 인가)
    //--------------------------------------------------------------------------
    integer cyc;
    reg     mon_en;
    integer out_cnt;
    integer first_in_cyc;
    integer first_out_cyc;

    integer x_cnt;      // out_enable / out_data 에 X/Z 가 보인 횟수

    initial cyc = 0;
    always @(posedge clk) cyc <= cyc + 1;

    // 출력은 posedge 에서 샘플 (직전 사이클에 레지스터된 값).
    // 입력은 posedge + IN_DLY 에 바뀌므로 드라이버와 race 없음.
    // post-impl : clk->out(pad) < CLK_PERIOD 이면 안정된 값을 읽음.
    always @(posedge clk)
    begin
        if (mon_en)
        begin
            if ((in_enable === 1'b1) && (first_in_cyc < 0))
                first_in_cyc = cyc;
            if ((^out_enable === 1'bx) || ((out_enable === 1'b1) && (^out_data === 1'bx)))
            begin
                x_cnt = x_cnt + 1;
                if (x_cnt <= MAX_ERR_PRINT)
                    $display("    [X] t=%0t out_enable=%b out_data=%h", $time, out_enable, out_data);
            end
            if (out_enable === 1'b1)
            begin
                if (out_cnt < MAXO)
                    dut_out[out_cnt] = $signed(out_data);
                if (first_out_cyc < 0)
                    first_out_cyc = cyc;
                out_cnt = out_cnt + 1;
            end
        end
    end

    //--------------------------------------------------------------------------
    // reference model helpers
    //--------------------------------------------------------------------------
    function integer sat16;
        input integer v;
        begin
            if (v > 32767)       sat16 = 32767;
            else if (v < -32768) sat16 = -32768;
            else                 sat16 = v;
        end
    endfunction

    // post_mac 와 동일 : (acc + (acc<0 ? 127 : 128)) >>> 8  -> int16 saturate
    function integer mac_round_sat;
        input signed [63:0] a;
        reg   signed [63:0] t;
        begin
            if (a < 0) t = (a + 64'sd127) >>> 8;
            else       t = (a + 64'sd128) >>> 8;
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

    function integer ilog2;
        input integer v;
        integer t;
        begin
            ilog2 = 0;
            t     = v;
            while (t > 1)
            begin
                t     = t >> 1;
                ilog2 = ilog2 + 1;
            end
        end
    endfunction

    // 입력 인가 시점 : posedge 이후 IN_DLY
    task tick;
        begin
            @(posedge clk);
            #(IN_DLY);
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

    //--------------------------------------------------------------------------
    // run_case
    //   n_out  : 기대 최종 출력 개수
    //   K      : pooling window (pool 미사용 시 1)
    //   1단 토큰 수 S = n_out*K, MAC 사용 시 토큰 1개당 iter 개의 (x,w) 입력
    //--------------------------------------------------------------------------
    task run_case;
        input [8*64-1:0] name;
        input            en_mac;
        input            en_relu;
        input            en_res;
        input            en_max;
        input            en_gap;
        input integer    n_iter;
        input integer    p_iter;
        input integer    g_iter;
        input integer    bias;
        input integer    n_out;
        input integer    dmode;
        input integer    bubble;

        integer K, Neff, S, n_in, n_exp, n_got;
        integer i, j, k, idx, tx, tw, v, vmax, isum, sh;
        integer n_err, pass, lat, kind;
        reg     [31:0]     rnd;
        reg signed [63:0]  acc;
        reg signed [63:0]  prod;
        real    racc, rmax, rsum, dr, sig, noi, snr;
        begin
            //------------------------------------------------------------------
            // sizes
            //------------------------------------------------------------------
            if (en_max || en_gap) K = en_gap ? g_iter : p_iter;
            else                  K = 1;
            if (K < 1) K = 1;
            if (en_mac) Neff = (n_iter < 1) ? 1 : n_iter;
            else        Neff = 1;
            S     = n_out * K;
            n_in  = S * Neff;
            n_exp = n_out;

            if (en_gap && (((K & (K-1)) != 0) || (K > 128)))
                $display("  [WARN] GAP iter=%0d : avgpool divides only for 2^n (<=128)", K);
            if (en_max && en_gap && (p_iter != g_iter))
                $display("  [WARN] MAX+GAP both enabled : pooling_iteration must equal gap_iteration");

            //------------------------------------------------------------------
            // stimulus
            //------------------------------------------------------------------
            if (dmode != DM_CUSTOM)
            begin
                for (i = 0; i < n_in; i = i + 1)
                begin
                    if (dmode == DM_SMALL)
                    begin
                        rnd = $random(seed); stim_x[i] = (rnd % 1024) - 512;
                        rnd = $random(seed); stim_w[i] = (rnd % 1024) - 512;
                    end
                    else
                    begin
                        rnd = $random(seed); stim_x[i] = $signed(rnd[15:0]);
                        rnd = $random(seed); stim_w[i] = $signed(rnd[15:0]);
                    end
                end
            end

            //------------------------------------------------------------------
            // reference : MAC -> ReLU -> RES
            //------------------------------------------------------------------
            for (j = 0; j < S; j = j + 1)
            begin
                if (en_mac)
                begin
                    acc = 0;
                    for (k = 0; k < n_iter; k = k + 1)
                    begin
                        prod = stim_x[j*Neff + k];
                        prod = prod * stim_w[j*Neff + k];
                        acc  = acc + prod;
                    end
                    t_int[j]  = mac_round_sat(acc);
                    racc      = acc;
                    t_real[j] = clipr(racc / 65536.0);
                end
                else
                begin
                    t_int[j]  = stim_x[j];
                    t_real[j] = stim_x[j] / QSCALE;
                end

                if (en_relu)
                begin
                    if (t_int[j]  < 0)   t_int[j]  = 0;
                    if (t_real[j] < 0.0) t_real[j] = 0.0;
                end

                if (en_res)
                begin
                    t_int[j]  = sat16(t_int[j] + bias);
                    t_real[j] = clipr(t_real[j] + bias / QSCALE);
                end
            end

            //------------------------------------------------------------------
            // reference : POOL (K 개 연속 유효 출력 단위)
            //   MAX/GAP 동시 enable 시 pooling_unit mux 는 avg 를 선택
            //------------------------------------------------------------------
            for (j = 0; j < n_exp; j = j + 1)
            begin
                if (en_max || en_gap)
                begin
                    vmax = t_int[j*K];
                    rmax = t_real[j*K];
                    isum = 0;
                    rsum = 0.0;
                    for (k = 0; k < K; k = k + 1)
                    begin
                        if (t_int[j*K+k]  > vmax) vmax = t_int[j*K+k];
                        if (t_real[j*K+k] > rmax) rmax = t_real[j*K+k];
                        isum = isum + t_int[j*K+k];
                        rsum = rsum + t_real[j*K+k];
                    end
                    if (en_gap)
                    begin
                        sh          = ilog2(K);
                        exp_int[j]  = isum >>> sh;     // floor (arith shift)
                        exp_real[j] = rsum / K;
                    end
                    else
                    begin
                        exp_int[j]  = vmax;
                        exp_real[j] = rmax;
                    end
                end
                else
                begin
                    exp_int[j]  = t_int[j];
                    exp_real[j] = t_real[j];
                end
            end

            //------------------------------------------------------------------
            // reset + config
            //------------------------------------------------------------------
            mon_en = 0;
            tick;
            tx                 = bias;
            nrst              <= 1'b0;
            in_enable         <= 1'b0;
            in_data           <= {(PC*WORD_W){1'b0}};
            kernel_data       <= {(PC*WORD_W){1'b0}};
            bias_data         <= {PC{tx[WORD_W-1:0]}};
            mac_enable        <= en_mac;
            relu_enable       <= en_relu;
            residual_enable   <= en_res;
            pooling_enable    <= en_max;
            gap_enable        <= en_gap;
            mac_iteration     <= n_iter;
            pooling_iteration <= p_iter;
            gap_iteration     <= g_iter;
            repeat (4) tick;
            nrst <= 1'b1;
            repeat (8) tick;   // wrapper: reset sync 2 + 입력 reg 1 + config reg 1 이상

            out_cnt       = 0;
            first_in_cyc  = -1;
            first_out_cyc = -1;
            x_cnt         = 0;
            mon_en        = 1;

            //------------------------------------------------------------------
            // drive
            //------------------------------------------------------------------
            idx = 0;
            if (en_mac)
            begin
                // MAC : iter 개 연속 입력 -> idle MAC_GAP 클럭 (proc 해제 대기)
                for (j = 0; j < S; j = j + 1)
                begin
                    for (k = 0; k < Neff; k = k + 1)
                    begin
                        tx = stim_x[idx];
                        tw = stim_w[idx];
                        idx = idx + 1;
                        in_enable   <= 1'b1;
                        in_data     <= {PC{tx[WORD_W-1:0]}};
                        kernel_data <= {PC{tw[WORD_W-1:0]}};
                        tick;
                    end
                    in_enable   <= 1'b0;
                    in_data     <= {(PC*WORD_W){1'b0}};
                    kernel_data <= {(PC*WORD_W){1'b0}};
                    repeat (MAC_GAP) tick;
                end
            end
            else
            begin
                // streaming : pool 미사용 시 랜덤 bubble(1/4 확률),
                //             pool 사용 시 window 단위 연속 입력 + idle POOL_GAP
                for (j = 0; j < S; j = j + 1)
                begin
                    if ((bubble != 0) && !(en_max || en_gap))
                    begin
                        rnd = $random(seed);
                        if (rnd[1:0] == 2'b00)
                        begin
                            in_enable <= 1'b0;
                            tick;
                        end
                    end
                    tx = stim_x[j];
                    tw = stim_w[j];
                    in_enable   <= 1'b1;
                    in_data     <= {PC{tx[WORD_W-1:0]}};
                    kernel_data <= {PC{tw[WORD_W-1:0]}};
                    tick;
                    if ((en_max || en_gap) && ((j % K) == (K-1)))
                    begin
                        in_enable <= 1'b0;
                        in_data   <= {(PC*WORD_W){1'b0}};
                        repeat (POOL_GAP) tick;
                    end
                end
            end
            in_enable   <= 1'b0;
            in_data     <= {(PC*WORD_W){1'b0}};
            kernel_data <= {(PC*WORD_W){1'b0}};
            repeat (DRAIN) tick;
            mon_en = 0;

            //------------------------------------------------------------------
            // check + SNR
            //------------------------------------------------------------------
            n_got = out_cnt;
            lat   = ((first_in_cyc >= 0) && (first_out_cyc >= 0)) ? (first_out_cyc - first_in_cyc) : -1;
            n_err = 0;
            sig   = 0.0;
            noi   = 0.0;

            $display("------------------------------------------------------------------------");
            $display("[CASE %2d] %0s", n_case + 1, name);
            $display("  config  : MAC=%0d(iter=%0d) ReLU=%0d RES=%0d(bias=%0d) MAX=%0d(iter=%0d) GAP=%0d(iter=%0d)",
                     en_mac, n_iter, en_relu, en_res, bias, en_max, p_iter, en_gap, g_iter);

            for (i = 0; i < n_exp; i = i + 1)
            begin
                if ((i < n_got) && (i < MAXO)) v = dut_out[i];
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

                dr  = v / QSCALE;
                sig = sig + exp_real[i] * exp_real[i];
                noi = noi + (dr - exp_real[i]) * (dr - exp_real[i]);
            end
            if (n_got > n_exp)
                $display("    extra outputs : %0d (expected %0d)", n_got - n_exp, n_exp);

            if (x_cnt > 0)
                $display("    X/Z on outputs : %0d cycles  (timing violation / uninitialized FF?)", x_cnt);

            pass = (n_err == 0) && (n_got == n_exp) && (x_cnt == 0);

            if (noi == 0.0)
            begin
                kind = 1;
                snr  = 0.0;
            end
            else if (sig == 0.0)
            begin
                kind = 2;
                snr  = 0.0;
            end
            else
            begin
                kind = 0;
                snr  = 10.0 * $log10(sig / noi);
            end

            $display("  outputs : expected=%0d  received=%0d  mismatches=%0d  latency=%0d clk",
                     n_exp, n_got, n_err, lat);
            if (kind == 0)      $display("  SNR     : %8.2f dB", snr);
            else if (kind == 1) $display("  SNR     :      INF dB  (DUT == ideal reference)");
            else                $display("  SNR     :      N/A     (reference power = 0)");
            $display("  RESULT  : %s", pass ? "PASS" : "FAIL");

            r_name[n_case] = name;
            r_pass[n_case] = pass;
            r_nexp[n_case] = n_exp;
            r_ngot[n_case] = n_got;
            r_nerr[n_case] = n_err;
            r_lat [n_case] = lat;
            r_kind[n_case] = kind;
            r_snr [n_case] = snr;
            n_case         = n_case + 1;
        end
    endtask

    //--------------------------------------------------------------------------
    // summary
    //--------------------------------------------------------------------------
    task print_summary;
        integer i, npass, nfin, ninf;
        real    ssum, smin, smax;
        begin
            npass = 0;
            nfin  = 0;
            ninf  = 0;
            ssum  = 0.0;
            smin  = 1.0e9;
            smax  = -1.0e9;

            $display("");
            $display("====================================================================================================");
            $display("                                     conv_top TEST SUMMARY");
            $display("====================================================================================================");
            $display("  No | Result |  Exp |  Got |  Err |  Lat |  SNR(dB)  | Case");
            $display(" ----+--------+------+------+------+------+-----------+---------------------------------------------");
            for (i = 0; i < n_case; i = i + 1)
            begin
                if (r_pass[i]) npass = npass + 1;
                if (r_kind[i] == 0)
                begin
                    nfin = nfin + 1;
                    ssum = ssum + r_snr[i];
                    if (r_snr[i] < smin) smin = r_snr[i];
                    if (r_snr[i] > smax) smax = r_snr[i];
                    $display("  %2d |  %s  | %4d | %4d | %4d | %4d | %9.2f | %0s",
                             i+1, r_pass[i] ? "PASS" : "FAIL", r_nexp[i], r_ngot[i], r_nerr[i], r_lat[i], r_snr[i], r_name[i]);
                end
                else if (r_kind[i] == 1)
                begin
                    ninf = ninf + 1;
                    $display("  %2d |  %s  | %4d | %4d | %4d | %4d |       INF | %0s",
                             i+1, r_pass[i] ? "PASS" : "FAIL", r_nexp[i], r_ngot[i], r_nerr[i], r_lat[i], r_name[i]);
                end
                else
                begin
                    $display("  %2d |  %s  | %4d | %4d | %4d | %4d |       N/A | %0s",
                             i+1, r_pass[i] ? "PASS" : "FAIL", r_nexp[i], r_ngot[i], r_nerr[i], r_lat[i], r_name[i]);
                end
            end
            $display(" ----+--------+------+------+------+------+-----------+---------------------------------------------");
            $display("  TOTAL        : %0d / %0d PASS  (%0d FAIL)", npass, n_case, n_case - npass);
            if (nfin > 0)
            begin
                $display("  AVERAGE SNR  : %8.2f dB   (finite SNR cases = %0d, INF(bit-exact) cases = %0d excluded)",
                         ssum / nfin, nfin, ninf);
                $display("  MIN / MAX    : %8.2f dB / %8.2f dB", smin, smax);
            end
            else
                $display("  AVERAGE SNR  : all cases bit-exact (INF)");
            $display("  * SNR reference : ideal real-valued model (no rounding/truncation, Q7.8 range clip only)");
            $display("====================================================================================================");
        end
    endtask

    //--------------------------------------------------------------------------
    // global watchdog
    //--------------------------------------------------------------------------
    initial
    begin
        #(50_000_000);
        $display("[TB] GLOBAL TIMEOUT");
        print_summary;
        $finish;
    end

    //--------------------------------------------------------------------------
    // test sequence
    //--------------------------------------------------------------------------
    //                  name                                              MAC ReLU RES MAX GAP  N  P  G  bias  n_out dmode    bubble
    initial
    begin
        seed              = 32'h1234_5678;
        n_case            = 0;
        mon_en            = 0;
        out_cnt           = 0;
        first_in_cyc      = -1;
        first_out_cyc     = -1;
        x_cnt             = 0;
        nrst              = 1'b0;
        mac_enable        = 1'b0;
        relu_enable       = 1'b0;
        residual_enable   = 1'b0;
        pooling_enable    = 1'b0;
        gap_enable        = 1'b0;
        mac_iteration     = 0;
        pooling_iteration = 0;
        gap_iteration     = 0;
        in_enable         = 1'b0;
        in_data           = 0;
        kernel_data       = 0;
        bias_data         = 0;

        // 시작 전 대기 (입력 초기화 + nrst=0 유지 상태, Xilinx GSR 100ns 이후)
        #(START_DELAY);

        $display("========================================================================");
        $display(" tb_conv_top start  (WORD_W=%0d, Q7.8, PARALLEL_PC=%0d, CLK=%5.1fns, IN_DLY=%5.1fns)",
                 WORD_W, PC, CLK_PERIOD, IN_DLY);
        $display("========================================================================");

        //======================================================================
        // A. 0 block
        //======================================================================
        run_case("[0] BYPASS (all disabled)",            0,0,0,0,0,  1, 1, 1,    0,  64, DM_FULL,  1);

        //======================================================================
        // B. 1 block
        //======================================================================
        run_case("[1] MAC",                              1,0,0,0,0,  9, 1, 1,    0,  32, DM_SMALL, 0);
        run_case("[1] ReLU",                             0,1,0,0,0,  1, 1, 1,    0,  64, DM_FULL,  1);
        run_case("[1] RES",                              0,0,1,0,0,  1, 1, 1,  300,  64, DM_FULL,  1);
        run_case("[1] MAXPOOL",                          0,0,0,1,0,  1, 4, 1,    0,  16, DM_FULL,  0);
        run_case("[1] GAP",                              0,0,0,0,1,  1, 1, 8,    0,  16, DM_FULL,  0);

        //======================================================================
        // C. 2 blocks
        //======================================================================
        run_case("[2] MAC+ReLU",                         1,1,0,0,0,  9, 1, 1,    0,  32, DM_SMALL, 0);
        run_case("[2] MAC+RES",                          1,0,1,0,0,  4, 1, 1, -150,  32, DM_SMALL, 0);
        run_case("[2] MAC+MAXPOOL",                      1,0,0,1,0,  9, 4, 1,    0,   8, DM_SMALL, 0);
        run_case("[2] MAC+GAP",                          1,0,0,0,1,  9, 1, 4,    0,   8, DM_SMALL, 0);
        run_case("[2] ReLU+RES",                         0,1,1,0,0,  1, 1, 1, -500,  64, DM_FULL,  1);
        run_case("[2] ReLU+MAXPOOL",                     0,1,0,1,0,  1, 4, 1,    0,  16, DM_FULL,  0);
        run_case("[2] ReLU+GAP",                         0,1,0,0,1,  1, 1, 4,    0,  16, DM_FULL,  0);
        run_case("[2] RES+MAXPOOL",                      0,0,1,1,0,  1, 2, 1,  200,  16, DM_FULL,  0);
        run_case("[2] RES+GAP",                          0,0,1,0,1,  1, 1,16, -100,  16, DM_FULL,  0);

        //======================================================================
        // D. 3 blocks
        //======================================================================
        run_case("[3] MAC+ReLU+RES",                     1,1,1,0,0,  9, 1, 1,  128,  32, DM_SMALL, 0);
        run_case("[3] MAC+ReLU+MAXPOOL",                 1,1,0,1,0,  9, 4, 1,    0,   8, DM_SMALL, 0);
        run_case("[3] MAC+ReLU+GAP",                     1,1,0,0,1,  9, 1, 4,    0,   8, DM_SMALL, 0);
        run_case("[3] MAC+RES+MAXPOOL",                  1,0,1,1,0,  9, 4, 1,  -64,   8, DM_SMALL, 0);
        run_case("[3] MAC+RES+GAP",                      1,0,1,0,1,  9, 1, 4,   64,   8, DM_SMALL, 0);
        run_case("[3] ReLU+RES+MAXPOOL",                 0,1,1,1,0,  1, 4, 1, -300,  16, DM_FULL,  0);
        run_case("[3] ReLU+RES+GAP",                     0,1,1,0,1,  1, 1, 8,  256,  16, DM_FULL,  0);

        //======================================================================
        // E. 4 blocks
        //======================================================================
        run_case("[4] MAC+ReLU+RES+MAXPOOL",             1,1,1,1,0,  9, 4, 1,  100,   8, DM_SMALL, 0);
        run_case("[4] MAC+ReLU+RES+GAP",                 1,1,1,0,1,  9, 1, 4, -100,   8, DM_SMALL, 0);

        //======================================================================
        // F. corner cases
        //======================================================================
        // F1. MAC rounding boundary (iter=1) : +-0.5, +-1.5 LSB 등 반올림 경계
        set_xw(0,    1, 128);   //  128 ->  +0.5  ->  1
        set_xw(1,   -1, 128);   // -128 ->  -0.5  -> -1
        set_xw(2,    1, 127);   //  127 ->  0
        set_xw(3,   -1, 127);   // -127 ->  0
        set_xw(4,    3, 128);   //  384 ->  +1.5  ->  2
        set_xw(5,   -3, 128);   // -384 ->  -1.5  -> -2
        set_xw(6,    1, 129);   //  129 ->  1
        set_xw(7,   -1, 129);   // -129 -> -1
        set_xw(8,  128, 128);   // 16384 -> 64
        set_xw(9, -255,   1);   // -255 -> -1
        run_case("[C] MAC rounding boundary (iter=1)",    1,0,0,0,0,  1, 1, 1,    0,  10, DM_CUSTOM, 0);

        // F2. MAC iter=0 -> 0 출력
        run_case("[C] MAC iter=0 (expect 0)",             1,0,0,0,0,  0, 1, 1,    0,   8, DM_SMALL, 0);

        // F3. MAC iter=16 (long accumulation)
        run_case("[C] MAC iter=16",                       1,0,0,0,0, 16, 1, 1,    0,  16, DM_SMALL, 0);

        // F4. MAC +/- saturation (iter=4, full-scale)
        for (ii = 0;  ii < 4;  ii = ii + 1) set_xw(ii, -32768, -32768);
        for (ii = 4;  ii < 8;  ii = ii + 1) set_xw(ii, -32768,  32767);
        for (ii = 8;  ii < 12; ii = ii + 1) set_xw(ii,  32767,  32767);
        for (ii = 12; ii < 16; ii = ii + 1) set_xw(ii,  32767, -32768);
        run_case("[C] MAC +/- saturation (full-scale)",   1,0,0,0,0,  4, 1, 1,    0,   4, DM_CUSTOM, 0);

        // F5. MAC full-range random (iter=7 : 34b acc overflow 없는 최대) -> 잦은 saturation
        run_case("[C] MAC full-range random (iter=7)",    1,0,0,0,0,  7, 1, 1,    0,  32, DM_FULL,  0);

        // F6. MAC zero input
        for (ii = 0; ii < 36; ii = ii + 1) set_xw(ii, 0, 0);
        run_case("[C] MAC all-zero input",                1,0,0,0,0,  9, 1, 1,    0,   4, DM_CUSTOM, 0);

        // F7. ReLU boundary values
        set_xw( 0, -32768, 0); set_xw( 1, -32767, 0); set_xw( 2,   -256, 0); set_xw( 3,     -1, 0);
        set_xw( 4,      0, 0); set_xw( 5,      1, 0); set_xw( 6,    255, 0); set_xw( 7,    256, 0);
        set_xw( 8,  32766, 0); set_xw( 9,  32767, 0); set_xw(10, -12345, 0); set_xw(11,  12345, 0);
        set_xw(12,     -2, 0); set_xw(13,      2, 0); set_xw(14,   -129, 0); set_xw(15,    128, 0);
        run_case("[C] ReLU boundary values",              0,1,0,0,0,  1, 1, 1,    0,  16, DM_CUSTOM, 0);

        // F8/F9. residual saturation
        run_case("[C] RES + saturation (bias=+32767)",    0,0,1,0,0,  1, 1, 1, 32767, 64, DM_FULL,  0);
        run_case("[C] RES - saturation (bias=-32768)",    0,0,1,0,0,  1, 1, 1,-32768, 64, DM_FULL,  0);

        // F10. MAXPOOL iter=1 (pass-through)
        run_case("[C] MAXPOOL iter=1",                    0,0,0,1,0,  1, 1, 1,    0,  16, DM_FULL,  0);

        // F11. MAXPOOL negative / equal / extreme windows (iter=4)
        set_xw( 0,     -5, 0); set_xw( 1,     -3, 0); set_xw( 2,     -7, 0); set_xw( 3,   -100, 0);
        set_xw( 4, -32768, 0); set_xw( 5, -32768, 0); set_xw( 6, -32768, 0); set_xw( 7, -32768, 0);
        set_xw( 8,      7, 0); set_xw( 9,      7, 0); set_xw(10,      7, 0); set_xw(11,      7, 0);
        set_xw(12,  32767, 0); set_xw(13, -32768, 0); set_xw(14,      0, 0); set_xw(15,      1, 0);
        set_xw(16,     -1, 0); set_xw(17, -32768, 0); set_xw(18,     -2, 0); set_xw(19,     -3, 0);
        set_xw(20,      0, 0); set_xw(21,      0, 0); set_xw(22,      0, 0); set_xw(23,     -1, 0);
        run_case("[C] MAXPOOL negative/equal/extreme",    0,0,0,1,0,  1, 4, 1,    0,   6, DM_CUSTOM, 0);

        // F12. GAP iter=1 (pass-through)
        run_case("[C] GAP iter=1",                        0,0,0,0,1,  1, 1, 1,    0,  16, DM_FULL,  0);

        // F13. GAP negative floor (iter=2)
        set_xw( 0,     -1, 0); set_xw( 1,     -2, 0);   // -3 >>> 1 = -2
        set_xw( 2,     -1, 0); set_xw( 3,      0, 0);   // -1 >>> 1 = -1
        set_xw( 4,      1, 0); set_xw( 5,      0, 0);   //  1 >>> 1 =  0
        set_xw( 6,      3, 0); set_xw( 7,      4, 0);   //  7 >>> 1 =  3
        set_xw( 8, -32768, 0); set_xw( 9, -32768, 0);   // -32768
        set_xw(10,  32767, 0); set_xw(11,  32766, 0);   //  32766
        run_case("[C] GAP negative floor (iter=2)",       0,0,0,0,1,  1, 1, 2,    0,   6, DM_CUSTOM, 0);

        // F14. GAP iter=16 full-scale
        for (ii = 0;  ii < 16; ii = ii + 1) set_xw(ii,  32767, 0);
        for (ii = 16; ii < 32; ii = ii + 1) set_xw(ii, -32768, 0);
        for (ii = 32; ii < 48; ii = ii + 1) set_xw(ii, (ii % 2) ? -32768 : 32767, 0);
        run_case("[C] GAP iter=16 full-scale",            0,0,0,0,1,  1, 1,16,    0,   3, DM_CUSTOM, 0);

        // F15. MAX+GAP 동시 enable (pooling_unit mux 우선순위 : avg)
        run_case("[C] MAX+GAP both enabled (avg wins)",   0,0,0,1,1,  1, 4, 4,    0,  16, DM_FULL,  0);

        // F16. 긴 연속 스트림 (back-to-back, bubble 없음)
        run_case("[C] ReLU+RES long back-to-back stream", 0,1,1,0,0,  1, 1, 1,  -77, 256, DM_FULL,  0);

        print_summary;
        $finish;
    end

endmodule
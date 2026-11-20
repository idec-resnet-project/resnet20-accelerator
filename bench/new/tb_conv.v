`timescale 1ns / 1ps
//==============================================================================
// tb_conv_top.v  -  conv_top / core self-checking testbench
//------------------------------------------------------------------------------
//  * behavioral sim / post-implementation timing sim 둘 다 같은 파일로 동작
//  * 다른 RTL 교체
//      - DUT 는 parameter override 없이 인스턴스 (post-impl netlist / 다른 RTL 그대로 연결)
//      - 포트만 사용, 내부 신호 참조 없음, latency 는 고정값이 아니라 측정
//      - 기본 DUT  : conv_top_wrapper (안의 core = `CORE_MODULE, 기본 conv_top)
//      - NO_WRAPPER       : wrapper 없이 `CORE_MODULE 을 직접 DUT 로 사용
//      - NO_RESIDUAL_PORT : DUT 에 residual_data 포트가 없을 때 (RES_SRC = 1 로 사용)
//            예) xvlog -d CORE_MODULE=core   /   xvlog -d NO_RESIDUAL_PORT
//  * 처리 순서 : MAC(+bias) -> RES -> ReLU -> MAXPOOL -> GAP  (ResNet : conv -> add -> ReLU)
//      - MAXPOOL + GAP 동시 enable : 직렬 (MAX 결과 Kg 개를 GAP 으로 평균), 입력 토큰 Kp*Kg 개당 출력 1개
//                                    (POOL_CASCADE = 0 이면 이전 conv_top 방식 : avg 결과만 출력)
//      - bias_data     : MAC 결과에 더하는 bias (케이스마다 상수)
//      - residual_data : shortcut 값. 출력 1개를 만드는 MAC 윈도우의 "마지막 입력" 과 같은 클럭에 인가
//                        (RES_SRC = 1 이면 포트 대신 MAC 윈도우 중앙 입력 in_data 를 residual 로 기대)
//      - residual 은 MAC 이 켜져 있을 때만 동작 (mac_enable && residual_enable)
//  * 입력 : posedge 후 IN_DLY (= IN_DLY_RATIO x 주기) 에 인가
//  * 출력 : wrapper 의 reset loopback (in_data -> out_data, 2클럭) 으로 clk->out 을 자동 측정해서
//           "launch edge + (tco_min + tco_max + T)/2" 시점에 샘플
//           (behavioral 은 tco = 0 -> launch edge + T/2,  NO_WRAPPER 는 측정 없이 tco = 0 가정)
//  * 데이터 : 16b signed Q7.8 (FRAC_BITS = 8) : fmap / weight / bias_data / residual_data / out_data
//             누산기 Q15.16, bias 는 << 8 해서 양자화 전에 더함
//      - MAC : sum(x*w) + (bias << FRAC_BITS) -> 반올림(+-0.5 LSB, 0 에서 먼 쪽) + 포화
//  * 기준 모델 (RTL 구조와 무관한 기능 모델)
//      - exp_int  : bit-exact 고정소수점 모델 -> PASS/FAIL
//      - exp_real : 반올림/절삭 없는 실수 모델  -> SNR
//  * 판정   : out_enable == 1 인 사이클의 out_data 를 샘플 -> exp_int 와 순서대로 비교
//  * SNR    : 10*log10( sum(ref^2) / sum((dut-ref)^2) ), 오차 0 -> INF (평균에서 제외)
//  * latency: in_enable 이 내려간 뒤 out_enable 이 1 이 될 때까지 지난 posedge 수
//             (= 출력 1개를 만드는 마지막 입력을 캡처한 posedge 부터 결과를 낸 posedge 까지)
//             wrapper 의 입출력 레지스터 +2 클럭은 빼고 core 기준으로 표시
//
//  주파수 변경 : CLK_FREQ_MHZ  (예: xelab ... -generic_top "CLK_FREQ_MHZ=50.0")
//  Vivado xsim : 기본 run time(1000ns)으로는 안 끝납니다 -> Tcl 콘솔에서  run all
//==============================================================================
`ifndef CORE_MODULE
`define CORE_MODULE conv_top
`endif

`ifdef NO_WRAPPER
`define TB_DUT `CORE_MODULE
`else
`define TB_DUT conv_top_wrapper
`endif

module tb_conv_top;

    //--------------------------------------------------------------------------
    // user parameters  (xelab -generic_top "NAME=VALUE" 로 변경 가능)
    //--------------------------------------------------------------------------
    parameter real    CLK_FREQ_MHZ = 100.0;  // 클럭 주파수 [MHz]
    parameter real    IN_DLY_RATIO = 0.75;   // 입력 인가 시점 = posedge 후 (IN_DLY_RATIO x 주기)
    parameter integer FRAC_BITS    = 8;      // 소수부 비트 : Q7.8 -> 8
    parameter integer RES_SRC      = 0;      // residual 값  0: residual_data 포트 / 1: MAC 윈도우 중앙 입력 (내부 캡처)
    parameter integer POOL_CASCADE = 1;      // MAX+GAP 동시 enable  1: MAX -> GAP 직렬 (ResNet 순서) / 0: avg 결과만 (이전 conv_top)
    parameter integer GAP_ROUND    = 0;      // GAP 나눗셈  0: floor (>>>) / 1: 0 방향 절삭
    parameter integer GAP_NPOW2    = 0;      // 1: GAP K 가 2^n 이 아닌 케이스 포함
    parameter integer MAC_GAP      = 4;      // MAC 윈도우 사이 idle 클럭 (현재 conv_top 최소 3)
    parameter integer POOL_GAP     = 2;      // pooling 윈도우 사이 idle 클럭 (현재 conv_top 최소 1)
    parameter integer RST_WAIT     = 8;      // nrst 해제 후 첫 입력까지 대기 클럭
    parameter integer REF_CLIP     = 1;      // SNR ideal 모델  1: 표현 범위 clip / 0: clip 없음
    parameter integer SEED         = 1;      // 랜덤 시드

    //--------------------------------------------------------------------------
    // derived / fixed
    //--------------------------------------------------------------------------
    localparam integer WORD_W     = 16;
    localparam integer BW_MAC     = 16;
    localparam integer BW_POOL    = 16;
    localparam integer BW_GAP     = 16;
    localparam integer PC         = 1;
    localparam real    CLK_PERIOD = 1000.0 / CLK_FREQ_MHZ;      // [ns]
    localparam real    IN_DLY     = CLK_PERIOD * IN_DLY_RATIO;  // [ns]
    localparam real    START_DLY  = 200.0;                      // GSR(100ns) 이후 시작 [ns]
    localparam real    QSCALE     = 1.0 * (1 << FRAC_BITS);     // 1.0 에 해당하는 정수
    localparam real    QMAX_R     = 32767.0 / QSCALE;
    localparam real    QMIN_R     = -32768.0 / QSCALE;

`ifdef NO_WRAPPER
    localparam integer WRAP_LAT   = 0;       // wrapper 입출력 레지스터 지연
    localparam integer CAL_EN     = 0;       // reset loopback 보정 사용 여부
`else
    localparam integer WRAP_LAT   = 2;
    localparam integer CAL_EN     = 1;
`endif
`ifdef NO_RESIDUAL_PORT
    localparam integer HAS_RES_PORT = 0;
`else
    localparam integer HAS_RES_PORT = 1;
`endif

    localparam integer MAXS          = 8192;  // 입력 샘플
    localparam integer MAXT          = 2048;  // 1단 토큰 (MAC 출력 or 입력)
    localparam integer MAXO          = 1024;  // 최종 출력
    localparam integer MAXC          = 64;    // 케이스
    localparam integer DRAIN         = 100;   // 마지막 입력 후 대기 클럭
    localparam integer CAL_N         = 8;     // calibration 패턴 수
    localparam integer MAX_ERR_PRINT = 5;

    localparam integer DM_SMALL  = 0;   // x,w 랜덤 [-512, 511]
    localparam integer DM_FULL   = 1;   // x,w 랜덤 int16 전 범위
    localparam integer DM_CUSTOM = 2;   // 호출 전에 stim_x / stim_w 를 직접 채움

    localparam integer RM_SMALL  = 0;   // residual 랜덤 [-512, 511]
    localparam integer RM_FULL   = 1;   // residual 랜덤 int16 전 범위
    localparam integer RM_CONST  = 2;   // residual = rconst 고정

    //--------------------------------------------------------------------------
    // DUT  (parameter override 없음)
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
    reg  [PC*WORD_W-1:0]        residual_data;
    wire                        out_enable;
    wire [WORD_W-1:0]           out_data;

    `TB_DUT dut
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
`ifndef NO_RESIDUAL_PORT
        .residual_data     (residual_data),
`endif
        .out_enable        (out_enable),
        .out_data          (out_data)
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
    integer stim_w   [0:MAXS-1];
    integer t_int    [0:MAXT-1];
    real    t_real   [0:MAXT-1];
    integer tok_cap  [0:MAXT-1];   // 1단 토큰별 마지막 입력을 캡처한 posedge 번호
    integer res_v    [0:MAXT-1];   // 토큰별 residual 값
    integer exp_int  [0:MAXO-1];
    real    exp_real [0:MAXO-1];
    integer last_cap [0:MAXO-1];   // 최종 출력별 마지막 입력을 캡처한 posedge 번호
    integer got_val  [0:MAXO-1];
    integer got_cyc  [0:MAXO-1];   // out_enable 을 올린 posedge 번호

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

    initial
    begin : SAMPLER
        integer lc;
        forever
        begin
            @(posedge clk);
            cyc = cyc + 1;
            #(smp_r);
            lc = cyc - smp_k;
            if (mon_en)
            begin
                if ((^out_enable) === 1'bx)
                begin
                    x_cnt = x_cnt + 1;
                    if (x_cnt <= MAX_ERR_PRINT)
                        $display("    [X] t=%0t out_enable=%b out_data=%h", $time, out_enable, out_data);
                end
                else if (out_enable === 1'b1)
                begin
                    if ((^out_data) === 1'bx)
                    begin
                        x_cnt = x_cnt + 1;
                        if (x_cnt <= MAX_ERR_PRINT)
                            $display("    [X] t=%0t out_enable=%b out_data=%h", $time, out_enable, out_data);
                    end
                    if (out_cnt < MAXO)
                    begin
                        got_val[out_cnt] = $signed(out_data);
                        got_cyc[out_cnt] = lc;
                    end
                    out_cnt = out_cnt + 1;
                end
            end
        end
    end

    //--------------------------------------------------------------------------
    // calibration watcher (out_data 변화 시각 기록)
    //--------------------------------------------------------------------------
    reg  [WORD_W-1:0] cal_pat;
    reg               cal_on;
    reg               cal_first;
    reg               cal_hit;
    real              cal_tfirst;
    real              cal_tset;
    real              tco_min;
    real              tco_max;

    always @(out_data)
    begin
        if (cal_on)
        begin
            if (!cal_first)
            begin
                cal_first  = 1'b1;
                cal_tfirst = $realtime;
            end
            if (out_data === cal_pat)
            begin
                cal_hit  = 1'b1;
                cal_tset = $realtime;
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

    // GAP 정수 나눗셈 : GAP_ROUND 0 = floor, 1 = 0 방향 절삭
    function integer gap_div;
        input integer s;
        input integer k;
        integer q;
        begin
            q = s / k;
            if ((GAP_ROUND == 0) && (s < 0) && (q * k != s))
                q = q - 1;
            gap_div = q;
        end
    endfunction

    function real clipr;
        input real v;
        begin
            if (REF_CLIP == 0)   clipr = v;
            else if (v > QMAX_R) clipr = QMAX_R;
            else if (v < QMIN_R) clipr = QMIN_R;
            else                 clipr = v;
        end
    endfunction

    //--------------------------------------------------------------------------
    // drive helpers  (항상 posedge + IN_DLY 시점에서 호출)
    //--------------------------------------------------------------------------
    task tick;
        begin
            @(posedge clk);
            #(IN_DLY);
        end
    endtask

    // 유효 입력 1개 (다음 posedge 에 캡처)
    task drive_in;
        input integer x;
        input integer w;
        input integer r;
        begin
            in_enable     = 1'b1;
            in_data       = {PC{x[WORD_W-1:0]}};
            kernel_data   = {PC{w[WORD_W-1:0]}};
            residual_data = {PC{r[WORD_W-1:0]}};
            cur_cap       = cyc + 1;
            tick;
        end
    endtask

    // idle 1클럭 (데이터 버스에는 랜덤 garbage)
    task drive_idle;
        reg [31:0] r;
        begin
            r             = $random(seed);
            in_enable     = 1'b0;
            in_data       = {PC{r[15:0]}};
            kernel_data   = {PC{r[31:16]}};
            r             = $random(seed);
            residual_data = {PC{r[15:0]}};
            tick;
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
    // calibration : nrst=0 상태에서 wrapper loopback (in_data -> in_data_q -> out_data_q)
    //   in_data 를 캡처한 posedge 다음 posedge 가 out_data 의 launch edge
    //--------------------------------------------------------------------------
    task calibrate;
        integer i, n_ok;
        real    tl, ofs;
        begin
            tco_min = 0.0;
            tco_max = 0.0;
            if (CAL_EN == 0)
                $display("[CAL] skipped (NO_WRAPPER) : assuming clk->out = 0 (behavioral only)");
            else
            begin
                nrst      = 1'b0;
                in_enable = 1'b0;
                in_data   = {(PC*WORD_W){1'b0}};
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
                    in_data   = {PC{cal_pat}};
                    @(posedge clk);                    // in_data_q 캡처
                    @(posedge clk);                    // out_data_q launch
                    tl = $realtime;
                    #(IN_DLY);
                    repeat (3) tick;
                    cal_on = 1'b0;
                    if (cal_hit && (cal_tfirst >= tl))
                    begin
                        if (cal_tfirst - tl < tco_min) tco_min = cal_tfirst - tl;
                        if (cal_tset   - tl > tco_max) tco_max = cal_tset   - tl;
                        n_ok = n_ok + 1;
                    end
                end
                if (n_ok == 0)
                begin
                    $display("[CAL] WARNING : no loopback seen on out_data during reset -> assuming clk->out = 0");
                    $display("[CAL]           (wrapper without reset loopback, or input timing IN_DLY problem)");
                    tco_min = 0.0;
                    tco_max = 0.0;
                end
                else if (n_ok < CAL_N)
                    $display("[CAL] WARNING : only %0d / %0d patterns observed (check input timing IN_DLY)", n_ok, CAL_N);
                if (tco_min < 0.0) tco_min = 0.0;
            end
            ofs   = (tco_min + tco_max + CLK_PERIOD) / 2.0;
            smp_k = $rtoi(ofs / CLK_PERIOD);
            smp_r = ofs - smp_k * CLK_PERIOD;
            $display("[CAL] clk->out_data : min %6.3f ns / max %6.3f ns  (behavioral = 0 / 0)", tco_min, tco_max);
            $display("[CAL] output sample : launch edge + %6.3f ns  (posedge + %6.3f ns, k=%0d)", ofs, smp_r, smp_k);
            if ((tco_max - tco_min) > 0.8 * CLK_PERIOD)
                $display("[CAL] WARNING : output bit skew (%6.3f ns) is large vs clock period", tco_max - tco_min);
        end
    endtask


    //--------------------------------------------------------------------------
    // run_case
    //   enable 플래그 : MAC ReLU RES MAX GAP  (처리 순서는 MAC -> RES -> ReLU -> MAX -> GAP)
    //   n_iter / p_iter / g_iter : MAC / MAXPOOL / GAP iteration
    //   bias   : MAC bias (bias_data, 케이스 동안 상수)
    //   rmode, rconst : residual 값 (RM_SMALL / RM_FULL / RM_CONST)  - RES_SRC = 0 일 때
    //   n_out  : 기대 최종 출력 개수
    //   토큰(1단 출력) 수 S = n_out * Kp * Kg, MAC 사용 시 토큰 1개당 iter 개의 (x,w) 입력
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
        input integer    rmode;
        input integer    rconst;
        input integer    n_out;
        input integer    dmode;
        input integer    bubble;

        integer Kp, Kg, K, Kw, Neff, S, n_in, n_exp, use_res, cidx;
        integer i, j, k, g, idx, base, vmax, isum, rv;
        reg     [31:0]     rnd;
        reg signed [63:0]  acc;
        reg signed [63:0]  prod;
        reg signed [63:0]  bb;
        real    racc, rmax, rsum;
        begin
            //------------------------------------------------------------------
            // sizes
            //   Kp : MAXPOOL window, Kg : GAP window, K = 출력 1개당 토큰 수
            //------------------------------------------------------------------
            use_res = (en_mac && en_res) ? 1 : 0;
            if (en_max && en_gap && (POOL_CASCADE != 0)) begin Kp = p_iter; Kg = g_iter; end
            else if (en_gap)                             begin Kp = 1;      Kg = g_iter; end
            else if (en_max)                             begin Kp = p_iter; Kg = 1;      end
            else                                         begin Kp = 1;      Kg = 1;      end
            if (Kp < 1) Kp = 1;
            if (Kg < 1) Kg = 1;
            K     = Kp * Kg;
            Kw    = (en_max && en_gap && (POOL_CASCADE != 0)) ? Kp : K;   // pooling 윈도우 단위 (idle 삽입)
            if (en_mac) Neff = (n_iter < 1) ? 1 : n_iter;
            else        Neff = 1;
            cidx  = (n_iter >= 1) ? (n_iter >> 1) : 0;                     // MAC 윈도우 중앙 입력 번호
            S     = n_out * K;
            n_in  = S * Neff;
            n_exp = n_out;

            $display("------------------------------------------------------------------------");
            $display("[CASE %2d] %0s", n_case + 1, name);
            $display("  config  : MAC=%0d(iter=%0d,bias=%0d) RES=%0d ReLU=%0d MAX=%0d(iter=%0d) GAP=%0d(iter=%0d)",
                     en_mac, n_iter, bias, en_res, en_relu, en_max, p_iter, en_gap, g_iter);
            if (en_res && !en_mac)
                $display("  [NOTE] RES without MAC : residual is not applied (mac_enable && residual_enable)");
            if (use_res && (RES_SRC == 0) && (HAS_RES_PORT == 0))
                $display("  [WARN] RES_SRC=0 but NO_RESIDUAL_PORT : set RES_SRC=1 for internal capture");
            if (en_max && en_gap && (POOL_CASCADE == 0) && (p_iter != g_iter))
                $display("  [WARN] MAX+GAP parallel : pooling_iteration must equal gap_iteration");

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

            // residual 값 (토큰마다 1개)
            for (j = 0; j < S; j = j + 1)
            begin
                if (RES_SRC == 1)
                    res_v[j] = stim_x[j*Neff + cidx];
                else if (rmode == RM_SMALL)
                begin
                    rnd = $random(seed); res_v[j] = (rnd % 1024) - 512;
                end
                else if (rmode == RM_FULL)
                begin
                    rnd = $random(seed); res_v[j] = $signed(rnd[15:0]);
                end
                else
                    res_v[j] = rconst;
            end

            //------------------------------------------------------------------
            // reference : MAC(+bias) -> RES -> ReLU
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
                    bb        = bias;
                    bb        = bb <<< FRAC_BITS;
                    acc       = acc + bb;
                    t_int[j]  = mac_round_sat(acc);
                    racc      = acc;
                    t_real[j] = clipr(racc / (QSCALE * QSCALE));
                end
                else
                begin
                    t_int[j]  = stim_x[j];
                    t_real[j] = stim_x[j] / QSCALE;
                end

                if (use_res)
                begin
                    t_int[j]  = sat16(t_int[j] + res_v[j]);
                    t_real[j] = clipr(t_real[j] + res_v[j] / QSCALE);
                end

                if (en_relu)
                begin
                    if (t_int[j]  < 0)   t_int[j]  = 0;
                    if (t_real[j] < 0.0) t_real[j] = 0.0;
                end
            end

            //------------------------------------------------------------------
            // reference : MAXPOOL (Kp) -> GAP (Kg)
            //------------------------------------------------------------------
            for (j = 0; j < n_exp; j = j + 1)
            begin
                isum = 0;
                rsum = 0.0;
                for (g = 0; g < Kg; g = g + 1)
                begin
                    base = j*K + g*Kp;
                    vmax = t_int[base];
                    rmax = t_real[base];
                    for (k = 1; k < Kp; k = k + 1)
                    begin
                        if (t_int[base+k]  > vmax) vmax = t_int[base+k];
                        if (t_real[base+k] > rmax) rmax = t_real[base+k];
                    end
                    isum = isum + vmax;
                    rsum = rsum + rmax;
                end
                if (en_gap)
                begin
                    exp_int[j]  = gap_div(isum, Kg);
                    exp_real[j] = rsum / Kg;
                end
                else
                begin
                    exp_int[j]  = isum;
                    exp_real[j] = rsum;
                end
            end

            //------------------------------------------------------------------
            // reset + config
            //------------------------------------------------------------------
            mon_en            = 1'b0;
            idx               = bias;
            nrst              = 1'b0;
            in_enable         = 1'b0;
            in_data           = {(PC*WORD_W){1'b0}};
            kernel_data       = {(PC*WORD_W){1'b0}};
            residual_data     = {(PC*WORD_W){1'b0}};
            bias_data         = {PC{idx[WORD_W-1:0]}};
            mac_enable        = en_mac;
            relu_enable       = en_relu;
            residual_enable   = en_res;
            pooling_enable    = en_max;
            gap_enable        = en_gap;
            mac_iteration     = n_iter;
            pooling_iteration = p_iter;
            gap_iteration     = g_iter;
            repeat (4) tick;
            nrst              = 1'b1;
            repeat (RST_WAIT) drive_idle;

            out_cnt = 0;
            x_cnt   = 0;
            mon_en  = 1'b1;

            //------------------------------------------------------------------
            // drive
            //------------------------------------------------------------------
            idx = 0;
            if (en_mac)
            begin
                // MAC : iter 개 연속 입력 (마지막 입력과 같은 클럭에 residual_data) -> idle MAC_GAP 클럭
                for (j = 0; j < S; j = j + 1)
                begin
                    for (k = 0; k < Neff; k = k + 1)
                    begin
                        if (k == Neff - 1)
                            rv = res_v[j];
                        else
                        begin
                            rnd = $random(seed);
                            rv  = $signed(rnd[15:0]);
                        end
                        drive_in(stim_x[idx], stim_w[idx], rv);
                        idx = idx + 1;
                    end
                    tok_cap[j] = cur_cap;
                    repeat (MAC_GAP) drive_idle;
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
                        if (rnd[1:0] == 2'b00) drive_idle;
                    end
                    rnd = $random(seed);
                    drive_in(stim_x[j], stim_w[j], $signed(rnd[15:0]));
                    tok_cap[j] = cur_cap;
                    if ((en_max || en_gap) && ((j % Kw) == (Kw-1)))
                        repeat (POOL_GAP) drive_idle;
                end
            end
            for (j = 0; j < n_exp; j = j + 1)
                last_cap[j] = tok_cap[j*K + K - 1];

            repeat (DRAIN) drive_idle;
            mon_en = 1'b0;

            finish_case(name, n_exp);
        end
    endtask

    //--------------------------------------------------------------------------
    // check + report
    //--------------------------------------------------------------------------
    task finish_case;
        input [8*64-1:0] name;
        input integer    n_exp;
        integer i, v, n_got, n_err, pass, kind, lat, lmin, lmax, lsum, lcnt;
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
                    lat  = got_cyc[i] - last_cap[i] - WRAP_LAT;
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
            if (x_cnt > 0)
                $display("    X/Z on outputs : %0d samples  (timing violation / uninitialized FF?)", x_cnt);

            pass = (n_err == 0) && (n_got == n_exp) && (x_cnt == 0);

            if (noi == 0.0)      begin kind = 1; snr = 0.0; end
            else if (sig == 0.0) begin kind = 2; snr = 0.0; end
            else                 begin kind = 0; snr = 10.0 * $log10(sig / noi); end

            lavg = (lcnt > 0) ? (lsum * 1.0 / lcnt) : 0.0;

            $display("  outputs : expected=%0d  received=%0d  mismatches=%0d", n_exp, n_got, n_err);
            if (lcnt == 0)
                $display("  LATENCY : N/A");
            else if (lmin == lmax)
                $display("  LATENCY : %0d clk  (posedges after in_enable falls, core, wrapper +%0d excluded)", lmin, WRAP_LAT);
            else
                $display("  LATENCY : min %0d / avg %0.2f / max %0d clk  (posedges after in_enable falls, core, wrapper +%0d excluded)",
                         lmin, lavg, lmax, WRAP_LAT);
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
            $display("  conv_top TEST SUMMARY   (CLK %0.3f MHz = %0.3f ns, IN_DLY %0.3f ns, wrapper latency %0d excluded)",
                     CLK_FREQ_MHZ, CLK_PERIOD, IN_DLY, WRAP_LAT);
            $display("  FRAC_BITS %0d, RES_SRC %0d, POOL_CASCADE %0d, GAP_ROUND %0d", FRAC_BITS, RES_SRC, POOL_CASCADE, GAP_ROUND);
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
            $display("  * SNR reference : ideal real-valued model (%0s)", REF_CLIP ? "range clip" : "no clip");
            $display("  * LATENCY       : posedges after in_enable falls until out_enable=1 (core, wrapper +%0d excluded)", WRAP_LAT);
            $display("====================================================================================================");
        end
    endtask

    //--------------------------------------------------------------------------
    // watchdog
    //--------------------------------------------------------------------------
    initial
    begin
        #(START_DLY);
        repeat (2000000) @(posedge clk);
        $display("[TB] GLOBAL TIMEOUT");
        print_summary;
        $finish;
    end


    //--------------------------------------------------------------------------
    // test sequence
    //--------------------------------------------------------------------------
    initial
    begin
        cyc               = 0;
        smp_r             = CLK_PERIOD / 2.0;
        smp_k             = 0;
        mon_en            = 1'b0;
        out_cnt           = 0;
        x_cnt             = 0;
        cal_on            = 1'b0;
        n_case            = 0;
        seed              = SEED;
        cur_cap           = 0;
        nrst              = 1'b0;
        mac_enable        = 1'b0;
        relu_enable       = 1'b0;
        residual_enable   = 1'b0;
        pooling_enable    = 1'b0;
        gap_enable        = 1'b0;
        mac_iteration     = {BW_MAC{1'b0}};
        pooling_iteration = {BW_POOL{1'b0}};
        gap_iteration     = {BW_GAP{1'b0}};
        in_enable         = 1'b0;
        in_data           = {(PC*WORD_W){1'b0}};
        kernel_data       = {(PC*WORD_W){1'b0}};
        bias_data         = {(PC*WORD_W){1'b0}};
        residual_data     = {(PC*WORD_W){1'b0}};

        #(START_DLY);
        tick;

        $display("========================================================================");
        $display(" tb_conv_top  (CLK %0.3f MHz = %0.3f ns, IN_DLY %0.3f ns, wrapper latency %0d)",
                 CLK_FREQ_MHZ, CLK_PERIOD, IN_DLY, WRAP_LAT);
        $display(" FRAC_BITS %0d, RES_SRC %0d (%0s), residual_data port %0d, POOL_CASCADE %0d, GAP_ROUND %0d (%0s)",
                 FRAC_BITS, RES_SRC, RES_SRC ? "MAC center tap" : "residual_data port", HAS_RES_PORT,
                 POOL_CASCADE, GAP_ROUND, GAP_ROUND ? "trunc to 0" : "floor");
        $display(" MAC_GAP %0d, POOL_GAP %0d, RST_WAIT %0d, REF_CLIP %0d", MAC_GAP, POOL_GAP, RST_WAIT, REF_CLIP);
        $display("========================================================================");
        if ((RES_SRC == 0) && (HAS_RES_PORT == 0))
            $display("[WARN] RES_SRC=0 needs residual_data port. Use RES_SRC=1 with NO_RESIDUAL_PORT.");

        calibrate;

        //  처리 순서 : MAC(+bias) -> RES -> ReLU -> MAX -> GAP  (residual 은 MAC 이 켜져 있을 때만)
        //        name                                   MAC ReLU RES MAX GAP   N  P  G   bias  rmode     rconst n_out dmode     bubble
        //======================================================================
        // A. 0 block
        //======================================================================
        run_case("[0] BYPASS (all disabled)",            0,0,0,0,0,  1, 1, 1,     0, RM_SMALL,     0,  64, DM_FULL,  1);

        //======================================================================
        // B. 1 block
        //======================================================================
        run_case("[1] MAC",                              1,0,0,0,0,  9, 1, 1,     0, RM_SMALL,     0,  32, DM_SMALL, 0);
        run_case("[1] MAC + bias",                       1,0,0,0,0,  9, 1, 1,   300, RM_SMALL,     0,  32, DM_SMALL, 0);
        run_case("[1] ReLU",                             0,1,0,0,0,  1, 1, 1,     0, RM_SMALL,     0,  64, DM_FULL,  1);
        run_case("[1] MAXPOOL",                          0,0,0,1,0,  1, 4, 1,     0, RM_SMALL,     0,  16, DM_FULL,  0);
        run_case("[1] GAP",                              0,0,0,0,1,  1, 1, 8,     0, RM_SMALL,     0,  16, DM_FULL,  0);

        //======================================================================
        // C. 2 blocks
        //======================================================================
        run_case("[2] MAC+RES",                          1,0,1,0,0,  9, 1, 1,     0, RM_SMALL,     0,  32, DM_SMALL, 0);
        run_case("[2] MAC+RES (bias, full-range skip)",  1,0,1,0,0,  4, 1, 1,  -150, RM_FULL,      0,  32, DM_SMALL, 0);
        run_case("[2] MAC+ReLU",                         1,1,0,0,0,  9, 1, 1,     0, RM_SMALL,     0,  32, DM_SMALL, 0);
        run_case("[2] MAC+MAXPOOL",                      1,0,0,1,0,  9, 4, 1,     0, RM_SMALL,     0,   8, DM_SMALL, 0);
        run_case("[2] MAC+GAP",                          1,0,0,0,1,  9, 1, 4,     0, RM_SMALL,     0,   8, DM_SMALL, 0);
        run_case("[2] ReLU+MAXPOOL",                     0,1,0,1,0,  1, 4, 1,     0, RM_SMALL,     0,  16, DM_FULL,  0);
        run_case("[2] ReLU+GAP",                         0,1,0,0,1,  1, 1, 4,     0, RM_SMALL,     0,  16, DM_FULL,  0);

        //======================================================================
        // D. 3 blocks
        //======================================================================
        run_case("[3] MAC+RES+ReLU",                     1,1,1,0,0,  9, 1, 1,   128, RM_SMALL,     0,  32, DM_SMALL, 0);
        run_case("[3] MAC+RES+MAXPOOL",                  1,0,1,1,0,  9, 4, 1,   -64, RM_SMALL,     0,   8, DM_SMALL, 0);
        run_case("[3] MAC+RES+GAP",                      1,0,1,0,1,  9, 1, 4,    64, RM_SMALL,     0,   8, DM_SMALL, 0);
        run_case("[3] MAC+ReLU+MAXPOOL",                 1,1,0,1,0,  9, 4, 1,     0, RM_SMALL,     0,   8, DM_SMALL, 0);
        run_case("[3] MAC+ReLU+GAP",                     1,1,0,0,1,  9, 1, 4,     0, RM_SMALL,     0,   8, DM_SMALL, 0);

        //======================================================================
        // E. 4 blocks
        //======================================================================
        run_case("[4] MAC+RES+ReLU+MAXPOOL",             1,1,1,1,0,  9, 4, 1,   100, RM_SMALL,     0,   8, DM_SMALL, 0);
        run_case("[4] MAC+RES+ReLU+GAP",                 1,1,1,0,1,  9, 1, 4,  -100, RM_SMALL,     0,   8, DM_SMALL, 0);

        //======================================================================
        // E2. 5 blocks (ResNet 전체 : conv -> add -> ReLU -> MAXPOOL -> GAP)
        //======================================================================
        run_case("[5] MAC+RES+ReLU+MAX->GAP",            1,1,1,1,1,  9, 4, 4,    50, RM_SMALL,     0,   4, DM_SMALL, 0);
        run_case("[5] MAC+RES+ReLU+MAX->GAP (P=2,G=8)",  1,1,1,1,1,  9, 2, 8,   -50, RM_SMALL,     0,   4, DM_SMALL, 0);

        //======================================================================
        // F. corner cases
        //======================================================================
        // F1. MAC rounding boundary (iter=1) : +-0.5, +-1.5 LSB (FRAC_BITS 기준)
        ii = 1 << (FRAC_BITS - 1);
        set_xw(0,    1,    ii);   //  +0.5 LSB ->  1
        set_xw(1,   -1,    ii);   //  -0.5 LSB -> -1
        set_xw(2,    1,  ii-1);   //  < +0.5   ->  0
        set_xw(3,   -1,  ii-1);   //  > -0.5   ->  0
        set_xw(4,    3,    ii);   //  +1.5 LSB ->  2
        set_xw(5,   -3,    ii);   //  -1.5 LSB -> -2
        set_xw(6,    1,  ii+1);   //  > +0.5   ->  1
        set_xw(7,   -1,  ii+1);   //  < -0.5   -> -1
        set_xw(8,   ii,    ii);
        set_xw(9, -255,     1);
        run_case("[C] MAC rounding boundary (iter=1)",    1,0,0,0,0,  1, 1, 1,     0, RM_SMALL,     0,  10, DM_CUSTOM, 0);

        // F2. MAC iter=0 -> bias 만 출력 (bias 0 -> 0)
        run_case("[C] MAC iter=0 (expect 0)",             1,0,0,0,0,  0, 1, 1,     0, RM_SMALL,     0,   8, DM_SMALL, 0);

        // F3. MAC iter=16 (long accumulation)
        run_case("[C] MAC iter=16",                       1,0,0,0,0, 16, 1, 1,     0, RM_SMALL,     0,  16, DM_SMALL, 0);

        // F4. MAC +/- saturation (iter=4, full-scale)
        for (ii = 0;  ii < 4;  ii = ii + 1) set_xw(ii, -32768, -32768);
        for (ii = 4;  ii < 8;  ii = ii + 1) set_xw(ii, -32768,  32767);
        for (ii = 8;  ii < 12; ii = ii + 1) set_xw(ii,  32767,  32767);
        for (ii = 12; ii < 16; ii = ii + 1) set_xw(ii,  32767, -32768);
        run_case("[C] MAC +/- saturation (full-scale)",   1,0,0,0,0,  4, 1, 1,     0, RM_SMALL,     0,   4, DM_CUSTOM, 0);

        // F5. MAC full-range random (iter=7) -> 잦은 saturation
        run_case("[C] MAC full-range random (iter=7)",    1,0,0,0,0,  7, 1, 1,     0, RM_SMALL,     0,  32, DM_FULL,  0);

        // F6. MAC bias saturation
        run_case("[C] MAC bias +32767 (saturation)",      1,0,0,0,0,  9, 1, 1, 32767, RM_SMALL,     0,  16, DM_SMALL, 0);
        run_case("[C] MAC bias -32768 (saturation)",      1,0,0,0,0,  9, 1, 1,-32768, RM_SMALL,     0,  16, DM_SMALL, 0);

        // F7. MAC zero input
        for (ii = 0; ii < 36; ii = ii + 1) set_xw(ii, 0, 0);
        run_case("[C] MAC all-zero input",                1,0,0,0,0,  9, 1, 1,     0, RM_SMALL,     0,   4, DM_CUSTOM, 0);

        // F8. ReLU boundary values
        set_xw( 0, -32768, 0); set_xw( 1, -32767, 0); set_xw( 2,   -256, 0); set_xw( 3,     -1, 0);
        set_xw( 4,      0, 0); set_xw( 5,      1, 0); set_xw( 6,    255, 0); set_xw( 7,    256, 0);
        set_xw( 8,  32766, 0); set_xw( 9,  32767, 0); set_xw(10, -12345, 0); set_xw(11,  12345, 0);
        set_xw(12,     -2, 0); set_xw(13,      2, 0); set_xw(14,   -129, 0); set_xw(15,    128, 0);
        run_case("[C] ReLU boundary values",              0,1,0,0,0,  1, 1, 1,     0, RM_SMALL,     0,  16, DM_CUSTOM, 0);

        // F9. residual saturation / identity (MAC + RES)
        run_case("[C] MAC+RES skip=+32767 (+ saturation)",1,0,1,0,0,  4, 1, 1,     0, RM_CONST, 32767,  32, DM_SMALL, 0);
        run_case("[C] MAC+RES skip=-32768 (- saturation)",1,0,1,0,0,  4, 1, 1,     0, RM_CONST,-32768,  32, DM_SMALL, 0);
        run_case("[C] MAC+RES skip=0 (identity)",         1,0,1,0,0,  9, 1, 1,     0, RM_CONST,     0,  32, DM_SMALL, 0);
        run_case("[C] MAC+RES iter=1",                    1,0,1,0,0,  1, 1, 1,     0, RM_FULL,      0,  32, DM_SMALL, 0);

        // F10. MAXPOOL iter=1 (pass-through)
        run_case("[C] MAXPOOL iter=1",                    0,0,0,1,0,  1, 1, 1,     0, RM_SMALL,     0,  16, DM_FULL,  0);

        // F11. MAXPOOL negative / equal / extreme windows (iter=4)
        set_xw( 0,     -5, 0); set_xw( 1,     -3, 0); set_xw( 2,     -7, 0); set_xw( 3,   -100, 0);
        set_xw( 4, -32768, 0); set_xw( 5, -32768, 0); set_xw( 6, -32768, 0); set_xw( 7, -32768, 0);
        set_xw( 8,      7, 0); set_xw( 9,      7, 0); set_xw(10,      7, 0); set_xw(11,      7, 0);
        set_xw(12,  32767, 0); set_xw(13, -32768, 0); set_xw(14,      0, 0); set_xw(15,      1, 0);
        set_xw(16,     -1, 0); set_xw(17, -32768, 0); set_xw(18,     -2, 0); set_xw(19,     -3, 0);
        set_xw(20,      0, 0); set_xw(21,      0, 0); set_xw(22,      0, 0); set_xw(23,     -1, 0);
        run_case("[C] MAXPOOL negative/equal/extreme",    0,0,0,1,0,  1, 4, 1,     0, RM_SMALL,     0,   6, DM_CUSTOM, 0);

        // F12. GAP iter=1 (pass-through)
        run_case("[C] GAP iter=1",                        0,0,0,0,1,  1, 1, 1,     0, RM_SMALL,     0,  16, DM_FULL,  0);

        // F13. GAP negative rounding (iter=2) : floor / 0 방향 절삭은 GAP_ROUND 로 선택
        set_xw( 0,     -1, 0); set_xw( 1,     -2, 0);   // -3/2 : floor -2, trunc -1
        set_xw( 2,     -1, 0); set_xw( 3,      0, 0);   // -1/2 : floor -1, trunc  0
        set_xw( 4,      1, 0); set_xw( 5,      0, 0);   //  1/2 :  0
        set_xw( 6,      3, 0); set_xw( 7,      4, 0);   //  7/2 :  3
        set_xw( 8, -32768, 0); set_xw( 9, -32768, 0);   // -32768
        set_xw(10,  32767, 0); set_xw(11,  32766, 0);   //  32766
        run_case("[C] GAP negative rounding (iter=2)",    0,0,0,0,1,  1, 1, 2,     0, RM_SMALL,     0,   6, DM_CUSTOM, 0);

        // F14. GAP iter=16 full-scale
        for (ii = 0;  ii < 16; ii = ii + 1) set_xw(ii,  32767, 0);
        for (ii = 16; ii < 32; ii = ii + 1) set_xw(ii, -32768, 0);
        for (ii = 32; ii < 48; ii = ii + 1) set_xw(ii, (ii % 2) ? -32768 : 32767, 0);
        run_case("[C] GAP iter=16 full-scale",            0,0,0,0,1,  1, 1,16,     0, RM_SMALL,     0,   3, DM_CUSTOM, 0);

        // F15. GAP K 가 2^n 이 아닌 경우 (GAP_NPOW2 = 1 일 때만)
        if (GAP_NPOW2 != 0)
        begin
            run_case("[C] GAP iter=3 (non 2^n)",          0,0,0,0,1,  1, 1, 3,     0, RM_SMALL,     0,  16, DM_FULL,  0);
            run_case("[C] GAP iter=9 (non 2^n)",          0,0,0,0,1,  1, 1, 9,     0, RM_SMALL,     0,  16, DM_FULL,  0);
        end

        // F16. MAX+GAP 동시 enable : MAX -> GAP 직렬 (POOL_CASCADE = 0 이면 avg 결과만)
        run_case("[C] MAX->GAP (P=4, G=4)",               0,0,0,1,1,  1, 4, 4,     0, RM_SMALL,     0,   8, DM_FULL,  0);
        run_case("[C] MAX->GAP (P=2, G=8)",               0,0,0,1,1,  1, 2, 8,     0, RM_SMALL,     0,   8, DM_FULL,  0);
        run_case("[C] MAX->GAP (P=9, G=2)",               0,0,0,1,1,  1, 9, 2,     0, RM_SMALL,     0,   8, DM_FULL,  0);
        run_case("[C] ReLU+MAX->GAP",                     0,1,0,1,1,  1, 4, 4,     0, RM_SMALL,     0,   8, DM_FULL,  0);
        run_case("[C] MAC+MAX->GAP",                      1,0,0,1,1,  9, 4, 4,     0, RM_SMALL,     0,   4, DM_SMALL, 0);

        // F17. 긴 연속 스트림 (back-to-back, bubble 없음)
        run_case("[C] ReLU long back-to-back stream",     0,1,0,0,0,  1, 1, 1,     0, RM_SMALL,     0, 256, DM_FULL,  0);

        print_summary;
        $finish;
    end

endmodule
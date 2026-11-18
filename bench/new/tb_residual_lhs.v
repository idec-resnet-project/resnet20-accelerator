`timescale 1ns / 1ps

//==========================================================================
// tb_residual_packed
//  DUT : residual_packed
//        residual_unit (포화 덧셈, 3클럭) + mux
//        valid_mux = proc || done || valid_resi   (파이프라인 3단 전체)
//        data_out  = valid_mux ? resi_data : data_in
//        valid_out = valid_resi
//
//  내부 계층 참조 없이 TB 안의 모델만으로 검사 (포트 이름 바뀌어도 안전)
//   - proc 모델 = 1클럭 전에 입력이 받아짐
//   - done 모델 = 2클럭 전에 입력이 받아짐
//   - resi_data 모델 = 마지막으로 나온 residual 결과 (리셋 후 0)
//
//  매 클럭 자동 검사
//   1) valid_out=1      -> data_out == sat(a+b), 지연 == LATENCY
//   2) proc/done 구간    -> data_out == 직전 residual 결과 (mux가 residual 쪽 유지)
//   3) 그 외             -> data_out == data_in (바이패스)
//
//  출력 파라미터
//   - 설정값   : WORD_W, LATENCY, INT_MAX/MIN, GAUSS_STD
//   - 테스트별 : N, clipped, max|err|, MSE, SNR(dB)
//   - 전체     : 입력/출력/리셋 버림 개수, mux 경로별 클럭 수
//                (residual / stale(proc 구간) / bypass), 지연 min/max,
//                clipped 비율, max|err|, MSE, SNR, 오류 종류별 개수, PASS/FAIL
//   - CSV      : residual_packed_log.csv (valid 출력 1개당 1줄)
//
//  SNR 기준 = 이상적 덧셈(포화 없음). 오차는 포화(clipping)에서만 생김
//   SNR(dB) = 10*log10( sum(ref^2) / sum((ref-out)^2) )
//
//  T1 : 단발 입력
//  T2 : 연속 입력 + 포화 경계값
//  T3 : enable=0 이면 입력 무시
//  T4 : 균등분포 풀레인지 랜덤 (포화 많음, SNR 약 12 dB 예상)
//  T5 : 가우시안 랜덤 (실제 데이터에 가까움, 보고서용 SNR)
//  T6 : 데이터 corner case
//  T7 : 제어 corner case (bubble, enable 토글/중단, X 입력, 비동기 리셋)
//==========================================================================
module tb_residual_packed;

    localparam integer WORD_W    = 16;
    localparam integer LATENCY   = 3;
    localparam integer QDEPTH    = 1024;
    localparam integer MAXV      =  (1 << (WORD_W-1)) - 1;
    localparam integer MINV      = -(1 << (WORD_W-1));
    localparam integer GAUSS_STD = 8000;
    localparam integer MAX_PRINT = 10;   // 오류 종류별 최대 출력 줄 수

    reg                       clk       = 1'b0;
    reg                       rst_n     = 1'b0;
    reg                       enable    = 1'b0;
    reg                       valid_in  = 1'b0;
    reg  signed [WORD_W-1:0]  data_in   = 0;
    reg  signed [WORD_W-1:0]  data_skip = 0;
    wire                      valid_out;
    wire signed [WORD_W-1:0]  data_out;

    residual_packed #(.WORD_W(WORD_W)) dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .enable    (enable),
        .valid_in  (valid_in),
        .data_in   (data_in),
        .data_skip (data_skip),
        .valid_out (valid_out),
        .data_out  (data_out)
    );

    always #5 clk = ~clk;   // 100 MHz

    //----------------------------------------------------------------------
    // 기준 모델
    //----------------------------------------------------------------------
    function signed [WORD_W-1:0] sat_add;
        input signed [WORD_W-1:0] a;
        input signed [WORD_W-1:0] b;
        reg   signed [WORD_W:0]   s;
        begin
            s = a + b;
            if (s > MAXV)      sat_add = MAXV;
            else if (s < MINV) sat_add = MINV;
            else               sat_add = s[WORD_W-1:0];
        end
    endfunction

    function signed [WORD_W-1:0] clip;
        input integer v;
        begin
            if (v > MAXV)      clip = MAXV;
            else if (v < MINV) clip = MINV;
            else               clip = v;
        end
    endfunction

    //----------------------------------------------------------------------
    // 스코어보드 상태
    //----------------------------------------------------------------------
    reg signed [WORD_W-1:0] exp_q    [0:QDEPTH-1];
    integer                 ideal_q  [0:QDEPTH-1];
    reg signed [WORD_W-1:0] a_q      [0:QDEPTH-1];
    reg signed [WORD_W-1:0] b_q      [0:QDEPTH-1];
    integer                 in_cyc_q [0:QDEPTH-1];

    integer wr_ptr = 0, rd_ptr = 0;
    integer cyc      = 0;
    integer cur_test = 0;
    reg     verbose  = 1'b1;
    reg     acc_now  = 1'b0;   // 이번 클럭에 입력이 받아지는지
    reg     acc_d1   = 1'b0;   // 1클럭 전 (= proc 모델)
    reg     acc_d2   = 1'b0;   // 2클럭 전 (= done 모델)
    reg     sel_m;             // mux 선택 모델
    reg signed [WORD_W-1:0] last_res = 0;   // resi_data 모델

    // 개수
    integer n_in = 0, n_out = 0, n_flushed = 0;
    integer n_mux_res = 0;     // valid_out=1
    integer n_mux_hold = 0;    // proc/done 구간, 직전 결과 유지
    integer n_mux_byp = 0;     // data_in 바이패스
    integer lat_min = 1 << 30, lat_max = -1;

    // 오류 종류별
    integer e_data  = 0;   // 결과값 불일치
    integer e_lat   = 0;   // 지연 불일치
    integer e_unexp = 0;   // 입력 없는데 valid_out
    integer e_mux   = 0;   // 비-valid 클럭 data_out 불일치 (hold / bypass)
    integer e_x     = 0;   // valid_out 이 X/Z
    integer e_misc  = 0;   // directed 체크

    // SNR (테스트별)
    real    sig_pow = 0.0, noise_pow = 0.0;
    integer snr_n = 0, snr_sat = 0, max_err = 0;
    // SNR (전체)
    real    tot_sig = 0.0, tot_noise = 0.0;
    integer tot_n = 0, tot_sat = 0, tot_max_err = 0;

    integer idx, lat, err_i, abs_err;
    real    ref_r, err_r;
    reg signed [WORD_W-1:0] exp_mux;
    integer fd;

    //----------------------------------------------------------------------
    // 매 클럭 검사
    //  posedge에서 읽으면 DUT 레지스터는 갱신 전 값, data_in은 이번 클럭 값
    //----------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst_n) begin

            // X/Z 체크
            if (valid_out !== 1'b0 && valid_out !== 1'b1) begin
                e_x = e_x + 1;
                if (e_x <= MAX_PRINT)
                    $display("[ERR] t=%0t valid_out is %b", $time, valid_out);
            end

            // (2)(3) valid 아닌 클럭: hold 또는 bypass
            sel_m = acc_d1 || acc_d2;   // proc || done (valid_out=1 은 아래에서 처리)
            if (valid_out !== 1'b1) begin
                exp_mux = sel_m ? last_res : data_in;
                if (data_out !== exp_mux) begin
                    e_mux = e_mux + 1;
                    if (e_mux <= MAX_PRINT)
                        $display("[ERR] t=%0t %s: data_out=%0d exp=%0d (last_res=%0d, data_in=%0d)",
                                 $time, sel_m ? "hold  " : "bypass",
                                 data_out, exp_mux, last_res, data_in);
                end
                if (sel_m) n_mux_hold = n_mux_hold + 1;
                else       n_mux_byp  = n_mux_byp + 1;
            end
            else
                n_mux_res = n_mux_res + 1;

            // (1) residual 결과
            if (valid_out === 1'b1) begin
                n_out = n_out + 1;
                if (rd_ptr == wr_ptr) begin
                    e_unexp = e_unexp + 1;
                    if (e_unexp <= MAX_PRINT)
                        $display("[ERR] t=%0t unexpected valid_out (no pending input): data_out=%0d",
                                 $time, data_out);
                    last_res = data_out;
                end
                else begin
                    idx = rd_ptr % QDEPTH;
                    lat = cyc - in_cyc_q[idx];
                    if (lat < lat_min) lat_min = lat;
                    if (lat > lat_max) lat_max = lat;

                    if (data_out !== exp_q[idx]) begin
                        e_data = e_data + 1;
                        if (e_data <= MAX_PRINT)
                            $display("[ERR] t=%0t #%0d  %0d + %0d -> data_out=%0d  exp=%0d",
                                     $time, rd_ptr, a_q[idx], b_q[idx], data_out, exp_q[idx]);
                    end
                    if (lat != LATENCY) begin
                        e_lat = e_lat + 1;
                        if (e_lat <= MAX_PRINT)
                            $display("[ERR] t=%0t #%0d latency=%0d (exp %0d)",
                                     $time, rd_ptr, lat, LATENCY);
                    end
                    if (verbose && data_out === exp_q[idx] && lat == LATENCY)
                        $display("[OK ] t=%0t #%0d  %0d + %0d -> %0d  (latency %0d)",
                                 $time, rd_ptr, a_q[idx], b_q[idx], data_out, lat);

                    // SNR 누적
                    err_i   = ideal_q[idx] - data_out;
                    abs_err = (err_i < 0) ? -err_i : err_i;
                    ref_r   = ideal_q[idx];
                    err_r   = err_i;
                    sig_pow   = sig_pow   + ref_r * ref_r;
                    noise_pow = noise_pow + err_r * err_r;
                    tot_sig   = tot_sig   + ref_r * ref_r;
                    tot_noise = tot_noise + err_r * err_r;
                    snr_n = snr_n + 1;
                    tot_n = tot_n + 1;
                    if (err_i != 0) begin
                        snr_sat = snr_sat + 1;
                        tot_sat = tot_sat + 1;
                    end
                    if (abs_err > max_err)     max_err     = abs_err;
                    if (abs_err > tot_max_err) tot_max_err = abs_err;

                    // CSV
                    $fwrite(fd, "%0d,T%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d\n",
                            rd_ptr, cur_test, a_q[idx], b_q[idx], ideal_q[idx],
                            exp_q[idx], data_out, err_i, lat, (err_i != 0));

                    last_res = exp_q[idx];   // 이후 hold 구간 기대값
                    rd_ptr   = rd_ptr + 1;
                end
            end

            // 입력 기록 + proc/done 모델 시프트
            acc_now = (enable === 1'b1 && valid_in === 1'b1);
            acc_d2  = acc_d1;
            acc_d1  = acc_now;
            if (acc_now) begin
                idx           = wr_ptr % QDEPTH;
                exp_q[idx]    = sat_add(data_in, data_skip);
                ideal_q[idx]  = data_in + data_skip;
                a_q[idx]      = data_in;
                b_q[idx]      = data_skip;
                in_cyc_q[idx] = cyc;
                wr_ptr        = wr_ptr + 1;
                n_in          = n_in + 1;
            end

            cyc = cyc + 1;
        end
    end

    //----------------------------------------------------------------------
    // SNR 태스크
    //----------------------------------------------------------------------
    task snr_reset;
        input integer t;
        begin
            cur_test  = t;
            sig_pow   = 0.0;
            noise_pow = 0.0;
            snr_n     = 0;
            snr_sat   = 0;
            max_err   = 0;
        end
    endtask

    task snr_report;
        begin
            if (snr_n == 0)
                $display("[SNR] T%0d : no samples", cur_test);
            else if (noise_pow == 0.0)
                $display("[SNR] T%0d : N=%0d  clipped=0  max|err|=0  MSE=0  SNR = inf (bit-exact)",
                         cur_test, snr_n);
            else
                $display("[SNR] T%0d : N=%0d  clipped=%0d (%0.1f%%)  max|err|=%0d  MSE=%0.2f  SNR = %0.2f dB",
                         cur_test, snr_n, snr_sat, 100.0 * snr_sat / snr_n, max_err,
                         noise_pow / snr_n, 10.0 * $log10(sig_pow / noise_pow));
        end
    endtask

    //----------------------------------------------------------------------
    // 자극 태스크 (negedge 구동)
    //----------------------------------------------------------------------
    task send;
        input signed [WORD_W-1:0] a;
        input signed [WORD_W-1:0] b;
        begin
            @(negedge clk);
            enable    = 1'b1;
            valid_in  = 1'b1;
            data_in   = a;
            data_skip = b;
        end
    endtask

    task idle;
        input integer n;
        integer k;
        begin
            for (k = 0; k < n; k = k + 1) begin
                @(negedge clk);
                valid_in  = 1'b0;
                data_in   = $random;   // 바이패스 경로 확인용
                data_skip = $random;
            end
        end
    endtask

    //----------------------------------------------------------------------
    // 테스트 시퀀스
    //----------------------------------------------------------------------
    integer i;
    integer seed = 7;

    initial begin
        fd = $fopen("residual_packed_log.csv", "w");
        $fwrite(fd, "idx,test,a,b,ideal,expected,dut_out,err,latency,clipped\n");

        $display("==========================================");
        $display(" tb_residual_packed");
        $display(" WORD_W=%0d  LATENCY=%0d  INT_MAX=%0d  INT_MIN=%0d  GAUSS_STD=%0d",
                 WORD_W, LATENCY, MAXV, MINV, GAUSS_STD);
        $display("==========================================");

        repeat (3) @(negedge clk);
        rst_n  = 1'b1;
        enable = 1'b1;

        // T1
        $display("=== T1: single pulse ===");
        snr_reset(1);
        send(100, 23);
        idle(6);
        snr_report;

        // T2
        $display("=== T2: back-to-back + saturation ===");
        snr_reset(2);
        send(   -50,     20);
        send( 30000,  10000);
        send(-30000, -10000);
        send( 32767,      0);
        send(-32768,      0);
        send( 32767,      1);
        send(-32768,     -1);
        send( 16384,  16383);
        send( 16384,  16384);
        idle(6);
        snr_report;

        // T3
        $display("=== T3: enable=0 drops input ===");
        snr_reset(3);
        @(negedge clk); enable = 1'b0; valid_in = 1'b1; data_in = 1234; data_skip = 1;
        @(negedge clk); data_in = 5; data_skip = 6;
        @(negedge clk); valid_in = 1'b0; enable = 1'b1;
        idle(6);
        snr_report;

        // T4
        $display("=== T4: uniform full-range random, 1000 cycles ===");
        verbose = 1'b0;
        snr_reset(4);
        for (i = 0; i < 1000; i = i + 1) begin
            @(negedge clk);
            enable    = ({$random} % 10) != 0;
            valid_in  = ({$random} % 10) < 7;
            data_in   = $random;
            data_skip = $random;
        end
        idle(10);
        snr_report;

        // T5
        $display("=== T5: gaussian random (std=%0d), 1000 cycles ===", GAUSS_STD);
        snr_reset(5);
        for (i = 0; i < 1000; i = i + 1) begin
            @(negedge clk);
            enable    = ({$random} % 10) != 0;
            valid_in  = ({$random} % 10) < 7;
            data_in   = clip($dist_normal(seed, 0, GAUSS_STD));
            data_skip = clip($dist_normal(seed, 0, GAUSS_STD));
        end
        idle(10);
        snr_report;

        // T6
        $display("=== T6: data corner cases ===");
        verbose = 1'b1;
        snr_reset(6);
        send( 32767,  32767);   // -> 32767
        send(-32768, -32768);   // -> -32768 (ideal -65536)
        send( 32767, -32768);   // -1
        send(-32768,  32767);   // -1
        send( 32766,      1);   // 32767, 포화 아님
        send( 16383,  16385);   // 32768 -> 포화
        send(-32767,     -1);   // -32768, 포화 아님
        send(-16384, -16384);   // -32768, 포화 아님
        send(-16385, -16384);   // -32769 -> 포화
        send(     0,      0);
        send(    -1,      1);
        send(    -1,     -1);   // -2
        send(  1234,  -1234);
        idle(6);
        snr_report;

        // T7
        $display("=== T7: control corner cases ===");
        snr_reset(7);

        $display("--- T7a: valid bubble ---");
        for (i = 0; i < 10; i = i + 1) begin
            @(negedge clk);
            enable    = 1'b1;
            valid_in  = (i % 2 == 0);
            data_in   = i * 100;
            data_skip = i;
        end
        idle(6);

        $display("--- T7b: enable toggle ---");
        for (i = 0; i < 10; i = i + 1) begin
            @(negedge clk);
            enable    = (i % 2 == 1);
            valid_in  = 1'b1;
            data_in   = -i * 300;
            data_skip = 7;
        end
        idle(6);
        enable = 1'b1;

        $display("--- T7c: enable drop while in flight ---");
        send(111, 222);
        send(333, 444);
        @(negedge clk); enable = 1'b0; valid_in = 1'b0;
        repeat (6) @(negedge clk);
        enable = 1'b1;

        $display("--- T7d: X on data while valid=0 ---");
        for (i = 0; i < 4; i = i + 1) begin
            @(negedge clk);
            valid_in  = 1'b0;
            data_in   = {WORD_W{1'bx}};
            data_skip = {WORD_W{1'bx}};
        end
        send(5, 6);
        @(negedge clk); valid_in = 1'b0; data_in = {WORD_W{1'bx}}; data_skip = {WORD_W{1'bx}};
        repeat (5) @(negedge clk);
        // 바이패스로 X가 보이는 건 설계대로.
        // residual 경로(valid/hold 구간)에 X가 섞이면 위 스코어보드가 mismatch로 잡음

        $display("--- T7e: async reset mid-stream ---");
        send(1000, 1);
        send(2000, 2);
        send(3000, 3);
        @(negedge clk);
        valid_in = 1'b0;
        rst_n    = 1'b0;
        #1;
        // 리셋 즉시: valid_out=0, proc/done=0 -> mux 바이패스 -> data_out == data_in
        if (valid_out !== 1'b0 || data_out !== data_in) begin
            $display("[ERR] t=%0t async reset: valid_out=%b data_out=%0d data_in=%0d",
                     $time, valid_out, data_out, data_in);
            e_misc = e_misc + 1;
        end
        else
            $display("[OK ] t=%0t async reset: valid_out=0, mux bypasses data_in immediately", $time);
        n_flushed = n_flushed + (wr_ptr - rd_ptr);
        $display("      flushed %0d in-flight input(s)", wr_ptr - rd_ptr);
        rd_ptr   = wr_ptr;
        acc_d1   = 1'b0;
        acc_d2   = 1'b0;
        last_res = 0;   // residual_unit data_out 리셋값
        repeat (2) @(negedge clk);
        if (valid_out !== 1'b0) begin
            $display("[ERR] t=%0t valid_out=1 during reset", $time);
            e_misc = e_misc + 1;
        end
        rst_n     = 1'b1;
        enable    = 1'b1;
        valid_in  = 1'b1;
        data_in   = 4000;
        data_skip = 4;
        idle(6);
        snr_report;

        //------------------------------------------------------------------
        // 최종 요약
        //------------------------------------------------------------------
        $display("==========================================");
        $display(" SUMMARY  (WORD_W=%0d, LATENCY=%0d)", WORD_W, LATENCY);
        $display("------------------------------------------");
        $display(" inputs accepted      : %0d", n_in);
        $display(" valid outputs        : %0d", n_out);
        $display(" flushed by reset     : %0d", n_flushed);
        if (lat_max < 0)
            $display(" latency min / max    : - / -");
        else
            $display(" latency min / max    : %0d / %0d", lat_min, lat_max);
        $display(" mux cycles  residual : %0d   (valid_out=1, new result)", n_mux_res);
        $display("             hold     : %0d   (proc/done stage, previous result held)", n_mux_hold);
        $display("             bypass   : %0d   (data_in passthrough)", n_mux_byp);
        if (tot_n > 0) begin
            $display(" clipped outputs      : %0d (%0.2f%%)", tot_sat, 100.0 * tot_sat / tot_n);
            $display(" max |err| vs ideal   : %0d", tot_max_err);
            $display(" MSE vs ideal         : %0.4f", tot_noise / tot_n);
            if (tot_noise == 0.0)
                $display(" overall SNR          : inf (bit-exact)");
            else
                $display(" overall SNR          : %0.2f dB", 10.0 * $log10(tot_sig / tot_noise));
        end
        $display("------------------------------------------");
        $display(" errors  data mismatch     : %0d", e_data);
        $display("         latency mismatch  : %0d", e_lat);
        $display("         unexpected valid  : %0d", e_unexp);
        $display("         hold/bypass mism. : %0d", e_mux);
        $display("         valid X/Z         : %0d", e_x);
        $display("         directed checks   : %0d", e_misc);
        $display("------------------------------------------");
        if (e_data + e_lat + e_unexp + e_mux + e_x + e_misc == 0
            && n_in == n_out + n_flushed && rd_ptr == wr_ptr)
            $display(" RESULT: PASS");
        else
            $display(" RESULT: FAIL");
        $display(" log file: residual_packed_log.csv");
        $display("==========================================");
        $fclose(fd);
        $finish;
    end

    initial begin
        #300000;
        $display("[ERR] timeout");
        $finish;
    end

endmodule
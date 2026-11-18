`timescale 1ns / 1ps

//==========================================================================
// tb_ReLU_packed
//  DUT : ReLU_packed = ReLU (1클럭 레지스터) + mux
//        ReLU     : enable=1 -> valid=1, out = (in<0) ? 0 : in   (다음 클럭)
//                   enable=0 -> valid=0, out 유지
//        mux      : data_out = valid ? relu_out : data_in (조합 바이패스)
//
//  ReLU_packed에는 valid 출력 포트가 없으므로 TB 안의 모델로 valid를 계산
//  (내부 계층 참조 없음 -> 하위 신호 이름이 바뀌어도 안전)
//
//  매 클럭 자동 검사
//   1) 직전 클럭 enable=1 -> data_out == ReLU(직전 클럭 data_in)   (지연 1)
//   2) 그 외              -> data_out == data_in                  (바이패스)
//
//  출력 파라미터
//   - 설정값   : WORD_W, LATENCY, GAUSS_STD
//   - 테스트별 : ReLU 출력 수, 그중 0으로 잘린 수(음수), 바이패스 클럭 수,
//                바이패스로 통과한 음수 개수, 오류 수
//   - 전체     : 위 항목 합계, 오류 종류별 개수,
//                SNR vs 이상적 ReLU max(0,x) (ReLU는 근사가 없으므로 inf가 정상),
//                PASS/FAIL
//   - CSV      : relu_packed_log.csv (매 클럭 1줄)
//
//  T1 : 단발 enable
//  T2 : 연속 enable + 데이터 corner (0, ±1, 최대/최소, 경계)
//  T3 : enable 매 클럭 토글
//  T4 : enable=0 유지 -> 음수 포함 바이패스
//  T5 : 균등분포 풀레인지 랜덤 (enable 80%)
//  T6 : 가우시안 랜덤 (enable 80%)
//  T7 : enable=0 동안 data=X -> 바이패스로 X, enable 후 정상 복귀
//  T8 : 처리 중 비동기 리셋 -> 즉시 바이패스, 해제 첫 클럭부터 동작
//==========================================================================
module tb_ReLU_packed;

    localparam integer WORD_W    = 16;
    localparam integer LATENCY   = 1;
    localparam integer MAXV      =  (1 << (WORD_W-1)) - 1;
    localparam integer MINV      = -(1 << (WORD_W-1));
    localparam integer GAUSS_STD = 8000;
    localparam integer MAX_PRINT = 10;

    reg                       clk     = 1'b0;
    reg                       rst_n   = 1'b0;
    reg                       enable  = 1'b0;
    reg  signed [WORD_W-1:0]  data_in = 0;
    wire signed [WORD_W-1:0]  data_out;

    ReLU_packed #(.WORD_W(WORD_W)) dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .enable   (enable),
        .data_in  (data_in),
        .data_out (data_out)
    );

    always #5 clk = ~clk;   // 100 MHz

    //----------------------------------------------------------------------
    // 기준 모델
    //----------------------------------------------------------------------
    function signed [WORD_W-1:0] relu;
        input signed [WORD_W-1:0] x;
        begin
            relu = (x < 0) ? {WORD_W{1'b0}} : x;
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
    // 스코어보드
    //  posedge에서 읽으면 DUT 레지스터는 갱신 전 값, data_in은 이번 클럭 값
    //----------------------------------------------------------------------
    reg                     en_d1   = 1'b0;   // 직전 클럭 enable (= valid 모델)
    reg signed [WORD_W-1:0] in_d1   = 0;      // 직전 클럭 입력
    reg signed [WORD_W-1:0] exp_v;
    integer cyc      = 0;
    integer cur_test = 0;
    reg     verbose  = 1'b1;

    // 테스트별
    integer t_relu = 0, t_clamp = 0, t_byp = 0, t_byp_neg = 0, t_err = 0;
    // 전체
    integer n_relu = 0, n_clamp = 0, n_byp = 0, n_byp_neg = 0;
    integer e_relu = 0;   // ReLU 경로 불일치
    integer e_byp  = 0;   // 바이패스 경로 불일치
    integer e_misc = 0;   // directed 체크

    // SNR vs 이상적 ReLU
    real    sig_pow = 0.0, noise_pow = 0.0;
    real    ref_r, err_r;
    integer err_i;
    integer fd;

    always @(posedge clk) begin
        if (rst_n) begin
            if (en_d1) begin
                // 1) ReLU 경로
                exp_v  = relu(in_d1);
                t_relu = t_relu + 1;
                n_relu = n_relu + 1;
                if (in_d1 < 0) begin
                    t_clamp = t_clamp + 1;
                    n_clamp = n_clamp + 1;
                end
                if (data_out !== exp_v) begin
                    e_relu = e_relu + 1;
                    t_err  = t_err + 1;
                    if (e_relu <= MAX_PRINT)
                        $display("[ERR] t=%0t relu: in=%0d -> data_out=%0d exp=%0d",
                                 $time, in_d1, data_out, exp_v);
                end
                else if (verbose)
                    $display("[OK ] t=%0t relu   %6d -> %6d", $time, in_d1, data_out);

                err_i     = exp_v - data_out;
                ref_r     = exp_v;
                err_r     = err_i;
                sig_pow   = sig_pow   + ref_r * ref_r;
                noise_pow = noise_pow + err_r * err_r;

                $fwrite(fd, "%0d,T%0d,relu,%0d,%0d,%0d,%0d\n",
                        cyc, cur_test, in_d1, exp_v, data_out, (data_out !== exp_v));
            end
            else begin
                // 2) 바이패스 경로
                t_byp = t_byp + 1;
                n_byp = n_byp + 1;
                if (data_in < 0) begin
                    t_byp_neg = t_byp_neg + 1;
                    n_byp_neg = n_byp_neg + 1;
                end
                if (data_out !== data_in) begin
                    e_byp = e_byp + 1;
                    t_err = t_err + 1;
                    if (e_byp <= MAX_PRINT)
                        $display("[ERR] t=%0t bypass: data_out=%0d but data_in=%0d",
                                 $time, data_out, data_in);
                end
                $fwrite(fd, "%0d,T%0d,bypass,%0d,%0d,%0d,%0d\n",
                        cyc, cur_test, data_in, data_in, data_out, (data_out !== data_in));
            end

            // 다음 클럭용 모델 갱신
            en_d1 = (enable === 1'b1);
            if (en_d1) in_d1 = data_in;

            cyc = cyc + 1;
        end
    end

    //----------------------------------------------------------------------
    // 테스트별 리포트
    //----------------------------------------------------------------------
    task test_start;
        input integer t;
        begin
            cur_test  = t;
            t_relu    = 0;
            t_clamp   = 0;
            t_byp     = 0;
            t_byp_neg = 0;
            t_err     = 0;
        end
    endtask

    task test_report;
        begin
            $display("[T%0d] relu outputs=%0d (clamped to 0: %0d)  bypass=%0d (negative passed: %0d)  errors=%0d",
                     cur_test, t_relu, t_clamp, t_byp, t_byp_neg, t_err);
        end
    endtask

    //----------------------------------------------------------------------
    // 자극 (negedge 구동)
    //----------------------------------------------------------------------
    task drive;
        input                     en;
        input signed [WORD_W-1:0] d;
        begin
            @(negedge clk);
            enable  = en;
            data_in = d;
        end
    endtask

    integer i;
    integer seed = 11;

    initial begin
        fd = $fopen("relu_packed_log.csv", "w");
        $fwrite(fd, "cycle,test,path,input,expected,dut_out,error\n");

        $display("==========================================");
        $display(" tb_ReLU_packed");
        $display(" WORD_W=%0d  LATENCY=%0d  INT_MAX=%0d  INT_MIN=%0d  GAUSS_STD=%0d",
                 WORD_W, LATENCY, MAXV, MINV, GAUSS_STD);
        $display("==========================================");

        repeat (3) @(negedge clk);
        rst_n = 1'b1;

        // T1 : 단발 enable
        $display("=== T1: single enable pulse ===");
        test_start(1);
        drive(1'b1,  -5);
        drive(1'b0, 123);
        drive(1'b0, 456);
        drive(1'b1,  77);
        drive(1'b0, -99);
        drive(1'b0,   0);
        test_report;

        // T2 : 연속 enable + corner
        $display("=== T2: continuous enable + corner values ===");
        test_start(2);
        drive(1'b1,      0);   // 0 -> 0 (부호비트 0)
        drive(1'b1,      1);
        drive(1'b1,     -1);   // -> 0
        drive(1'b1,  32767);   // 최대
        drive(1'b1, -32768);   // 최소 -> 0
        drive(1'b1,  16384);
        drive(1'b1, -16384);
        drive(1'b1,    255);
        drive(1'b1,   -256);
        drive(1'b1,  32766);
        drive(1'b1, -32767);
        drive(1'b0,   1000);
        drive(1'b0,  -1000);
        test_report;

        // T3 : enable 토글
        $display("=== T3: enable toggles every cycle ===");
        test_start(3);
        for (i = 0; i < 16; i = i + 1)
            drive(i % 2 == 0, (i % 3 == 0) ? -i * 1000 : i * 1000);
        drive(1'b0, 0);
        test_report;

        // T4 : enable=0 유지 -> 바이패스 (음수도 그대로 통과)
        $display("=== T4: enable=0, bypass (negatives pass through) ===");
        test_start(4);
        verbose = 1'b0;
        for (i = 0; i < 20; i = i + 1)
            drive(1'b0, $random);
        test_report;

        // T5 : 균등 랜덤
        $display("=== T5: uniform full-range random, 1000 cycles ===");
        test_start(5);
        for (i = 0; i < 1000; i = i + 1)
            drive(({$random} % 10) < 8, $random);
        drive(1'b0, 0);
        test_report;

        // T6 : 가우시안 랜덤
        $display("=== T6: gaussian random (std=%0d), 1000 cycles ===", GAUSS_STD);
        test_start(6);
        for (i = 0; i < 1000; i = i + 1)
            drive(({$random} % 10) < 8, clip($dist_normal(seed, 0, GAUSS_STD)));
        drive(1'b0, 0);
        test_report;

        // T7 : enable=0 동안 X
        $display("=== T7: X on data while enable=0 ===");
        test_start(7);
        verbose = 1'b1;
        for (i = 0; i < 3; i = i + 1)
            drive(1'b0, {WORD_W{1'bx}});
        drive(1'b1,  321);
        drive(1'b1, -321);
        drive(1'b0,    0);
        drive(1'b0,    0);
        test_report;

        // T8 : 비동기 리셋
        $display("=== T8: async reset mid-stream ===");
        test_start(8);
        drive(1'b1, 1111);
        drive(1'b1, 2222);
        @(negedge clk);
        data_in = -3333;
        rst_n   = 1'b0;
        #1;
        if (data_out !== data_in) begin
            $display("[ERR] t=%0t async reset: data_out=%0d but data_in=%0d (expected bypass)",
                     $time, data_out, data_in);
            e_misc = e_misc + 1;
        end
        else
            $display("[OK ] t=%0t async reset: valid cleared, mux bypasses data_in immediately", $time);
        en_d1 = 1'b0;
        @(negedge clk);
        data_in = 4444;
        #1;
        if (data_out !== data_in) begin
            $display("[ERR] t=%0t during reset: data_out=%0d but data_in=%0d", $time, data_out, data_in);
            e_misc = e_misc + 1;
        end
        // 해제와 동시에 enable -> 해제 후 첫 클럭부터 ReLU 동작
        @(negedge clk);
        rst_n   = 1'b1;
        enable  = 1'b1;
        data_in = -5555;
        drive(1'b1, 6666);
        drive(1'b0,    0);
        drive(1'b0,    0);
        test_report;

        //------------------------------------------------------------------
        // 최종 요약
        //------------------------------------------------------------------
        $display("==========================================");
        $display(" SUMMARY  (WORD_W=%0d, LATENCY=%0d)", WORD_W, LATENCY);
        $display("------------------------------------------");
        $display(" relu outputs           : %0d", n_relu);
        $display("   clamped to 0 (neg)   : %0d (%0.2f%%)", n_clamp,
                 (n_relu > 0) ? 100.0 * n_clamp / n_relu : 0.0);
        $display(" bypass cycles          : %0d", n_byp);
        $display("   negative passed      : %0d   (enable=0 -> raw data_in, by design)", n_byp_neg);
        if (noise_pow == 0.0)
            $display(" SNR vs ideal max(0,x)  : inf (bit-exact)");
        else
            $display(" SNR vs ideal max(0,x)  : %0.2f dB", 10.0 * $log10(sig_pow / noise_pow));
        $display("------------------------------------------");
        $display(" errors  relu path      : %0d", e_relu);
        $display("         bypass path    : %0d", e_byp);
        $display("         directed       : %0d", e_misc);
        $display("------------------------------------------");
        if (e_relu + e_byp + e_misc == 0)
            $display(" RESULT: PASS");
        else
            $display(" RESULT: FAIL");
        $display(" log file: relu_packed_log.csv");
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
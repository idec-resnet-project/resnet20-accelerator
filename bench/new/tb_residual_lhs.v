`timescale 1ns / 1ps

//==========================================================================
// tb_residual_unit
//  - 자기검증(self-checking) TB: 기대값 큐와 DUT 출력을 자동 비교
//  - 값, 지연(LATENCY), 입력/출력 개수 모두 체크
//  T1 : 단발 입력
//  T2 : 연속 입력 + 포화 경계값
//  T3 : enable=0 이면 입력 무시되는지
//  T4 : 랜덤 1000 클럭 (valid/enable 랜덤, 데이터 풀레인지)
//==========================================================================
module tb_residual_unit;

    localparam integer WORD_W  = 16;
    localparam integer LATENCY = 3;
    localparam integer QDEPTH  = 1024;
    localparam integer MAXV    =  (1 << (WORD_W-1)) - 1;
    localparam integer MINV    = -(1 << (WORD_W-1));

    reg                       clk       = 1'b0;
    reg                       rst_n     = 1'b0;
    reg                       enable    = 1'b0;
    reg                       valid_in  = 1'b0;
    reg  signed [WORD_W-1:0]  data_in   = 0;
    reg  signed [WORD_W-1:0]  data_skip = 0;
    wire                      valid_out;
    wire signed [WORD_W-1:0]  data_out;

    residual_unit #(.WORD_W(WORD_W)) dut (
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
    // 기준 모델: 포화 덧셈
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

    //----------------------------------------------------------------------
    // 스코어보드
    //  posedge에서 DUT 레지스터 값을 읽으면 갱신 전(직전 사이클) 값이 보임
    //  입력은 negedge에서 바꾸므로 race 없음
    //----------------------------------------------------------------------
    reg signed [WORD_W-1:0] exp_q    [0:QDEPTH-1];
    reg signed [WORD_W-1:0] a_q      [0:QDEPTH-1];
    reg signed [WORD_W-1:0] b_q      [0:QDEPTH-1];
    integer                 in_cyc_q [0:QDEPTH-1];

    integer wr_ptr = 0, rd_ptr = 0;
    integer cyc    = 0;
    integer n_in   = 0, n_out = 0, n_err = 0;
    integer lat;
    integer idx;
    reg     verbose = 1'b1;

    always @(posedge clk) begin
        if (rst_n) begin
            // ---- 출력 확인 ----
            if (valid_out === 1'bx) begin
                $display("[ERR] t=%0t valid_out is X", $time);
                n_err = n_err + 1;
            end
            else if (valid_out) begin
                n_out = n_out + 1;
                if (rd_ptr == wr_ptr) begin
                    $display("[ERR] t=%0t unexpected output (no pending input): data_out=%0d",
                             $time, data_out);
                    n_err = n_err + 1;
                end
                else begin
                    idx = rd_ptr % QDEPTH;
                    lat = cyc - in_cyc_q[idx];
                    if (data_out !== exp_q[idx] || lat != LATENCY) begin
                        $display("[ERR] t=%0t #%0d  %0d + %0d -> data_out=%0d  exp=%0d  latency=%0d (exp %0d)",
                                 $time, rd_ptr, a_q[idx], b_q[idx], data_out, exp_q[idx], lat, LATENCY);
                        n_err = n_err + 1;
                    end
                    else if (verbose) begin
                        $display("[OK ] t=%0t #%0d  %0d + %0d -> %0d  (latency %0d)",
                                 $time, rd_ptr, a_q[idx], b_q[idx], data_out, lat);
                    end
                    rd_ptr = rd_ptr + 1;
                end
            end

            // ---- 입력 기록 ----
            if (enable === 1'b1 && valid_in === 1'b1) begin
                idx           = wr_ptr % QDEPTH;
                exp_q[idx]    = sat_add(data_in, data_skip);
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
    // 자극 태스크 (negedge에서 구동)
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
                data_in   = $random;   // valid 아닐 때 쓰레기 값 -> 무시돼야 정상
                data_skip = $random;
            end
        end
    endtask

    //----------------------------------------------------------------------
    // 테스트 시퀀스
    //----------------------------------------------------------------------
    integer i;

    initial begin
        repeat (3) @(negedge clk);
        rst_n  = 1'b1;
        enable = 1'b1;

        // T1 : 단발 입력 -> valid_out 1클럭, 3클럭 뒤
        $display("=== T1: single pulse ===");
        send(100, 23);
        idle(6);

        // T2 : 연속 입력 + 포화 경계
        $display("=== T2: back-to-back + saturation ===");
        send(   -50,     20);
        send( 30000,  10000);   // +sat -> 32767
        send(-30000, -10000);   // -sat -> -32768
        send( 32767,      0);
        send(-32768,      0);
        send( 32767,      1);   // +sat
        send(-32768,     -1);   // -sat
        send( 16384,  16383);   // 딱 32767
        send( 16384,  16384);   // +sat
        idle(6);

        // T3 : enable=0 -> 입력 무시, 출력 없어야 함
        $display("=== T3: enable=0 drops input ===");
        @(negedge clk); enable = 1'b0; valid_in = 1'b1; data_in = 1234; data_skip = 1;
        @(negedge clk); data_in = 5; data_skip = 6;
        @(negedge clk); valid_in = 1'b0; enable = 1'b1;
        idle(6);

        // T4 : 랜덤
        $display("=== T4: random 1000 cycles ===");
        verbose = 1'b0;
        for (i = 0; i < 1000; i = i + 1) begin
            @(negedge clk);
            enable    = ({$random} % 10) != 0;   // 90%
            valid_in  = ({$random} % 10) < 7;    // 70%
            data_in   = $random;
            data_skip = $random;
        end
        idle(10);

        // 결과
        $display("==========================================");
        $display(" inputs accepted : %0d", n_in);
        $display(" outputs seen    : %0d", n_out);
        $display(" errors          : %0d", n_err);
        if (n_err == 0 && n_in == n_out && rd_ptr == wr_ptr)
            $display(" RESULT: PASS");
        else
            $display(" RESULT: FAIL");
        $display("==========================================");
        $finish;
    end

    // 워치독
    initial begin
        #200000;
        $display("[ERR] timeout");
        $finish;
    end

endmodule
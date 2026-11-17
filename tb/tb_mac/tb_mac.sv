`timescale 1ns/1ps

module tb_mac;

    localparam integer BITWIDTH = 16;
    localparam integer ITER_WIDTH = 16;
    localparam integer FRAC_BITS = 8;
    localparam integer SCALE = 1 << FRAC_BITS;
    localparam integer MAX_CYCLES = 512;
    localparam integer EXPECTED_PASS = 11;

    // ==========================================
    // Clock / Reset
    // ==========================================
    logic clk = 1'b0;
    logic nrst = 1'b0;

    logic enable = 1'b1;
    logic [ITER_WIDTH-1:0] iteration = 16'd1;
    logic in_enable = 1'b0;

    logic signed [BITWIDTH-1:0] in_data = '0;
    logic signed [BITWIDTH-1:0] kernel_data = '0;

    wire out_enable;
    wire signed [BITWIDTH-1:0] out_data;

    // 100 MHz
    always #5 clk = ~clk;

    // ==========================================
    // DUT
    // ==========================================
    mac #(
        .BITWIDTH(BITWIDTH),
        .BITWIDTH_MAC_ITERATION(ITER_WIDTH)
    ) dut (
        .clk         (clk),
        .nrst        (nrst),
        .enable      (enable),
        .iteration   (iteration),
        .in_enable   (in_enable),
        .in_data     (in_data),
        .kernel_data (kernel_data),
        .out_enable  (out_enable),
        .out_data    (out_data)
    );

    // ==========================================
    // Transaction-based Reference Model
    // ==========================================

    // Input sampled at previous clock edge
    bit model_mul_valid = 0;
    bit model_mul_enable = 0;

    logic signed [BITWIDTH-1:0] model_input = '0;
    logic signed [BITWIDTH-1:0] model_kernel = '0;

    // Mathematical accumulation
    longint signed model_sum = 0;
    integer model_count = 0;

    // Expected output schedule
    bit expected_valid [0:MAX_CYCLES-1];
    logic signed [BITWIDTH-1:0]
        expected_data [0:MAX_CYCLES-1];

    integer cycle_count = 0;
    integer pass_count = 0;
    integer fail_count = 0;

    integer i;
    initial begin
        for (i = 0; i < MAX_CYCLES; i++) begin
            expected_valid[i] = 0;
            expected_data[i] = '0;
        end
    end

    // ------------------------------------------
    // Fixed-point reference
    // ------------------------------------------
    function automatic signed [BITWIDTH-1:0] mac_ref(
        input longint signed sum
    );
        longint signed rounded;
        longint signed maximum;
        longint signed minimum;
        begin
            // Round to nearest, ties away from zero
            if (sum < 0)
                rounded = -((-sum + SCALE/2) / SCALE);
            else
                rounded = (sum + SCALE/2) / SCALE;

            maximum = (64'sd1 <<< (BITWIDTH-1)) - 1;
            minimum = -(64'sd1 <<< (BITWIDTH-1));

            if (rounded > maximum)
                mac_ref = maximum;
            else if (rounded < minimum)
                mac_ref = minimum;
            else
                mac_ref = rounded;
        end
    endfunction

    // ------------------------------------------
    // Model and scoreboard
    // ------------------------------------------
    always @(posedge clk) begin
        if (!nrst) begin
            model_mul_valid = 0;
            model_mul_enable = 0;
            model_input = '0;
            model_kernel = '0;

            model_sum = 0;
            model_count = 0;

            for (integer j = 0; j < MAX_CYCLES; j++) begin
                expected_valid[j] = 0;
                expected_data[j] = '0;
            end
        end
        else begin
            cycle_count = cycle_count + 1;

            if (cycle_count >= MAX_CYCLES-4)
                $fatal(1, "[FAIL] Scoreboard capacity exceeded");

            // Process the input captured one edge earlier.
            // This corresponds to the DUT accumulation stage.
            if (model_mul_valid) begin

                if (!model_mul_enable) begin
                    // Bypass
                    model_sum = 0;
                    model_count = 0;

                    expected_valid[cycle_count+3] = 1;
                    expected_data[cycle_count+3] = model_input;
                end
                else if (iteration != 0) begin
                    model_sum = model_sum
                        + ($signed(model_input)
                           * $signed(model_kernel));

                    model_count = model_count + 1;

                    if (model_count == iteration) begin
                        expected_valid[cycle_count+3] = 1;
                        expected_data[cycle_count+3] =
                            mac_ref(model_sum);

                        model_sum = 0;
                        model_count = 0;
                    end
                end
            end

            // Capture the current input for the next edge
            model_mul_valid = in_enable;

            if (in_enable) begin
                model_mul_enable = enable;
                model_input = in_data;
                model_kernel = kernel_data;
            end
        end

        // Wait for DUT nonblocking assignments
        #1;

        if (!nrst) begin
            if (out_enable !== 1'b0 ||
                out_data !== '0) begin
                fail_count = fail_count + 1;
                $display("[FAIL] Reset output mismatch");
            end
        end
        else begin
            if (out_enable !== expected_valid[cycle_count]) begin
                fail_count = fail_count + 1;

                $display(
                    "[FAIL] cycle=%0d valid=%b expected=%b",
                    cycle_count,
                    out_enable,
                    expected_valid[cycle_count]
                );
            end
            else if (expected_valid[cycle_count]) begin
                if (out_data !== expected_data[cycle_count]) begin
                    fail_count = fail_count + 1;

                    $display(
                        "[FAIL] cycle=%0d output=%0d expected=%0d",
                        cycle_count,
                        out_data,
                        expected_data[cycle_count]
                    );
                end
                else begin
                    pass_count = pass_count + 1;

                    $display(
                        "[PASS] cycle=%0d output=%0d",
                        cycle_count,
                        out_data
                    );
                end
            end
        end
    end

    // ==========================================
    // Input Driver
    // ==========================================
    task automatic send_input(
        input bit en,
        input bit valid,
        input signed [BITWIDTH-1:0] data,
        input signed [BITWIDTH-1:0] weight
    );
        begin
            @(negedge clk);

            enable = en;
            in_enable = valid;
            in_data = data;
            kernel_data = weight;

            if (valid) begin
                $display(
                    "[INPUT] cycle=%0d data=%0d weight=%0d enable=%b",
                    cycle_count,
                    data,
                    weight,
                    en
                );
            end
        end
    endtask

    // Stop sending data and drain the pipeline.
    task automatic drain;
        begin
            send_input(1, 0, 0, 0);
            repeat (6) @(negedge clk);
        end
    endtask

    // ==========================================
    // Test Sequence
    // ==========================================
    initial begin
        $display("====================================");
        $display(" MAC 5-Stage Pipeline Simulation");
        $display(" Clock: 100 MHz");
        $display(" Fixed-point: Q7.8");
        $display("====================================");

        // Reset
        repeat (3) @(negedge clk);
        nrst = 1'b1;

        // ----------------------------------
        // Test 1: Positive multiplication
        // 2.0 * 3.0 = 6.0
        // ----------------------------------
        $display("[TEST 1] Positive MAC");
        iteration = 1;

        send_input(1, 1, 512, 768);
        drain();

        // ----------------------------------
        // Test 2: Negative multiplication
        // -2.0 * 3.0 = -6.0
        // ----------------------------------
        $display("[TEST 2] Negative MAC");
        iteration = 1;

        send_input(1, 1, -512, 768);
        drain();

        // ----------------------------------
        // Test 3: Accumulate 3 inputs
        // 1*2 + 2*1 + 1*1 = 5.0
        // ----------------------------------
        $display("[TEST 3] Accumulation");
        iteration = 3;

        send_input(1, 1, 256, 512);
        send_input(1, 1, 512, 256);
        send_input(1, 1, 256, 256);
        drain();

        // ----------------------------------
        // Test 4: Accumulate with a bubble
        // 2*2 + 1*3 = 7.0
        // ----------------------------------
        $display("[TEST 4] Invalid Cycle");
        iteration = 2;

        send_input(1, 1, 512, 512);
        send_input(1, 0, 999, 999);
        send_input(1, 1, 256, 768);
        drain();

        // ----------------------------------
        // Test 5: Negative bypass
        // ----------------------------------
        $display("[TEST 5] Negative Bypass");
        iteration = 1;

        send_input(0, 1, -768, 0);
        drain();

        // ----------------------------------
        // Test 6: Positive bypass
        // ----------------------------------
        $display("[TEST 6] Positive Bypass");

        send_input(0, 1, 512, 0);
        drain();

        // ----------------------------------
        // Test 7: Positive saturation
        // ----------------------------------
        $display("[TEST 7] Positive Saturation");
        iteration = 1;

        send_input(1, 1, 32767, 32767);
        drain();

        // ----------------------------------
        // Test 8: Negative saturation
        // ----------------------------------
        $display("[TEST 8] Negative Saturation");

        send_input(1, 1, -32768, 32767);
        drain();

        // ----------------------------------
        // Test 9: Positive rounding
        // 128 / 256 = 0.5 -> 1
        // ----------------------------------
        $display("[TEST 9] Positive Rounding");

        send_input(1, 1, 128, 1);
        drain();

        // ----------------------------------
        // Test 10: Negative rounding
        // -128 / 256 = -0.5 -> -1
        // ----------------------------------
        $display("[TEST 10] Negative Rounding");

        send_input(1, 1, -128, 1);
        drain();

        // ----------------------------------
        // Test 11: Reset during accumulation
        // ----------------------------------
        $display("[TEST 11] Pipeline Reset");
        iteration = 3;

        send_input(1, 1, 256, 256);
        send_input(1, 1, 256, 256);

        // Abort partial accumulation
        @(negedge clk);
        nrst = 1'b0;
        in_enable = 1'b0;

        repeat (3) @(negedge clk);
        nrst = 1'b1;

        // Check normal operation after reset
        iteration = 1;

        send_input(1, 1, 256, 512);
        drain();

        // ----------------------------------
        // Summary
        // ----------------------------------
        $display("====================================");
        $display(" MAC Simulation Summary");
        $display(" PASS: %0d", pass_count);
        $display(" FAIL: %0d", fail_count);
        $display("====================================");

        if (fail_count == 0 &&
            pass_count == EXPECTED_PASS)
            $display("[PASS] ALL TESTS PASSED");
        else
            $fatal(1, "[FAIL] MAC verification failed");

        $finish;
    end

    // ==========================================
    // Timeout
    // ==========================================
    initial begin
        #10000;
        $fatal(1, "[FAIL] Simulation timeout");
    end

endmodule

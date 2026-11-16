`timescale 1ns/1ps

module tb_mac;

    //===============================
    // Parameters
    //===============================
    localparam int BITWIDTH = 16;
    localparam int ITER_WIDTH = 16;
    localparam int CLK_PERIOD = 10; // 100 MHz

    //===============================
    // Clock and reset
    //===============================
    logic clk = 0;
    logic nrst = 0;

    always #(CLK_PERIOD/2) clk = ~clk;

    //===============================
    // MAC interface
    //===============================
    logic enable = 0;
    logic [ITER_WIDTH-1:0] iteration = 0;
    logic in_enable = 0;

    logic signed [BITWIDTH-1:0] in_data = 0;
    logic signed [BITWIDTH-1:0] kernel_data = 0;

    wire out_enable;
    wire signed [BITWIDTH-1:0] out_data;

    //===============================
    // DUT
    //===============================
    mac #(
        .BITWIDTH(BITWIDTH),
        .BITWIDTH_MAC_ITERATION(ITER_WIDTH)
    ) dut (
        .clk(clk),
        .nrst(nrst),
        .enable(enable),
        .iteration(iteration),
        .in_enable(in_enable),
        .in_data(in_data),
        .kernel_data(kernel_data),
        .out_enable(out_enable),
        .out_data(out_data)
    );

    //===============================
    // Test counters
    //===============================
    integer pass_count = 0;
    integer fail_count = 0;

    //===============================
    // Input task
    //===============================
    task automatic send_input(
        input signed [15:0] data,
        input signed [15:0] weight
    );
        begin
            @(negedge clk);
            in_enable  = 1;
            in_data    = data;
            kernel_data = weight;

            // Hold data through the next rising edge
            @(negedge clk);
            in_enable = 0;
        end
    endtask

    //===============================
    // Output checker
    //===============================
    task automatic check_output(
        input signed [15:0] expected
    );
        integer timeout;
        bit found;
        begin
            timeout = 0;
            found = 0;

            // Poll at falling edges after NBA updates
            while (timeout < 20 && !found) begin
                @(negedge clk);
                if (out_enable) begin
                    found = 1;

                    if (out_data === expected) begin
                        $display(
                            "[ PASS ] expected=%0d actual=%0d",
                            expected, out_data
                        );
                        pass_count++;
                    end
                    else begin
                        $display(
                            "[ FAIL ] expected=%0d actual=%0d",
                            expected, out_data
                        );
                        fail_count++;
                    end
                end
                timeout++;
            end

            if (!found) begin
                $display("[ FAIL ] Output timeout");
                fail_count++;
            end
        end
    endtask

    //===============================
    // Test sequence
    //===============================
    initial begin
        // Reset
        repeat (3) @(negedge clk);
        nrst = 1;

        // ----------------------------
        // Test 1: Basic MAC
        // 1.0*0.5 + 2.0*0.5 + 3.0*0.5
        // = 3.0 (Q7.8 = 768)
        // ----------------------------
        $display("[ TEST 1 ] Basic MAC");

        enable = 1;
        iteration = 3;

        send_input(16'sd256, 16'sd128);
        send_input(16'sd512, 16'sd128);
        send_input(16'sd768, 16'sd128);

        check_output(16'sd768);

        // ----------------------------
        // Test 2: Negative MAC
        // -1.0*1.0 + -2.0*1.0 = -3.0
        // ----------------------------
        $display("[ TEST 2 ] Negative MAC");

        iteration = 2;

        send_input(-16'sd256, 16'sd256);
        send_input(-16'sd512, 16'sd256);

        check_output(-16'sd768);

        // ----------------------------
        // Test 3: Bypass
        // ----------------------------
        $display("[ TEST 3 ] Bypass");

        enable = 0;
        iteration = 1;

        send_input(16'sd384, 16'sd256);

        check_output(16'sd384);

        // ----------------------------
        // Test 4: Positive saturation
        // 100.0 * 2.0 = 200.0
        // Expected: 0x7FFF
        // ----------------------------
        $display("[ TEST 4 ] Positive saturation");

        enable = 1;
        iteration = 1;

        send_input(16'sd25600, 16'sd512);

        check_output(16'sh7FFF);

        // ----------------------------
        // Test 5: Negative saturation
        // -100.0 * 2.0 = -200.0
        // Expected: 0x8000
        // ----------------------------
        $display("[ TEST 5 ] Negative saturation");

        send_input(-16'sd25600, 16'sd512);

        check_output(16'sh8000);

        //===============================
        // Test summary
        //===============================
        $display("--------------------------------");
        $display("PASS: %0d", pass_count);
        $display("FAIL: %0d", fail_count);
        $display("--------------------------------");

        if (fail_count == 0) begin
            $display("[ PASS ] ALL TESTS PASSED");
        end
        else begin
            $fatal(1, "[ FAIL ] MAC verification failed");
        end

        $finish;
    end

    //===============================
    // Simulation timeout
    //===============================
    initial begin
        #10000;
        $fatal(1, "Simulation timeout");
    end

endmodule

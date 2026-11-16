`timescale 1ns/1ps

module tb_relu;

    localparam integer BITWIDTH = 16;

    // --------------------------------
    // Clock / Reset
    // --------------------------------
    logic clk = 1'b0;
    logic nrst = 1'b0;

    logic enable = 1'b1;
    logic in_enable = 1'b0;
    logic signed [BITWIDTH-1:0] in_data = '0;

    wire out_enable;
    wire signed [BITWIDTH-1:0] out_data;

    // 100 MHz
    always #5 clk = ~clk;

    // --------------------------------
    // DUT
    // --------------------------------
    relu #(
        .BITWIDTH(BITWIDTH)
    ) dut (
        .clk(clk),
        .nrst(nrst),
        .enable(enable),
        .in_enable(in_enable),
        .in_data(in_data),
        .out_enable(out_enable),
        .out_data(out_data)
    );

    // --------------------------------
    // Reference pipeline
    // --------------------------------
    logic stage1_valid = 1'b0;
    logic signed [BITWIDTH-1:0] stage1_data = '0;

    logic expected_valid = 1'b0;
    logic signed [BITWIDTH-1:0] expected_data = '0;

    integer pass_count = 0;
    integer fail_count = 0;
    integer cycle_count = 0;

    // Independent expected ReLU operation
    function automatic signed [BITWIDTH-1:0] relu_ref(
        input bit en,
        input signed [BITWIDTH-1:0] value
    );
        begin
            if (en && value < 0)
                relu_ref = '0;
            else
                relu_ref = value;
        end
    endfunction

    // Two register stages
    always @(posedge clk or negedge nrst) begin
        if (!nrst) begin
            stage1_valid  <= 1'b0;
            stage1_data   <= '0;
            expected_valid <= 1'b0;
            expected_data  <= '0;
        end
        else begin
            stage1_valid <= in_enable;

            if (in_enable)
                stage1_data <= relu_ref(enable, in_data);

            expected_valid <= stage1_valid;

            if (stage1_valid)
                expected_data <= stage1_data;
        end
    end

    // --------------------------------
    // Scoreboard
    // --------------------------------
    always @(posedge clk) begin
        #1;

        if (nrst) begin
            cycle_count = cycle_count + 1;

            if (out_enable !== expected_valid ||
                (expected_valid &&
                 out_data !== expected_data)) begin

                fail_count = fail_count + 1;

                $display(
                    "[FAIL] cycle=%0d valid=%b/%b data=%0d/%0d",
                    cycle_count,
                    out_enable,
                    expected_valid,
                    out_data,
                    expected_data
                );
            end
            else if (expected_valid) begin
                pass_count = pass_count + 1;

                $display(
                    "[PASS] cycle=%0d output=%0d",
                    cycle_count,
                    out_data
                );
            end
        end
    end

    // --------------------------------
    // Input driver
    // --------------------------------
    task automatic send(
        input bit en,
        input bit valid,
        input signed [BITWIDTH-1:0] value
    );
        begin
            @(negedge clk);

            enable = en;
            in_enable = valid;
            in_data = value;

            if (valid)
                $display(
                    "[INPUT] time=%0t data=%0d enable=%b expected=%0d",
                    $time,
                    value,
                    en,
                    relu_ref(en, value)
                );
        end
    endtask

    // --------------------------------
    // Test sequence
    // --------------------------------
    initial begin
        $display("==============================");
        $display(" ReLU Pipeline Simulation");
        $display("==============================");

        // Reset
        repeat (3) @(negedge clk);
        nrst = 1'b1;

        // ReLU enabled
        send(1, 1, -16'sd3);
        send(1, 1,  16'sd2);
        send(1, 1, -16'sd1);
        send(1, 1,  16'sd5);
        send(1, 1,  16'sd0);
        send(1, 1, -16'sd8);
        send(1, 1,  16'sd7);

        // Invalid input cycle
        send(1, 0, 16'sd99);

        // Bypass
        send(0, 1, -16'sd4);
        send(0, 1,  16'sd6);

        // Boundary values
        send(1, 1,  16'sh7FFF);
        send(1, 1,  16'sh8000);

        // Drain pipeline
        send(1, 0, '0);
        repeat (3) @(posedge clk);

        #2;

        $display("==============================");
        $display(" PASS: %0d", pass_count);
        $display(" FAIL: %0d", fail_count);
        $display("==============================");

        if (fail_count == 0 && pass_count == 11)
            $display("[PASS] ALL TESTS PASSED");
        else
            $fatal(1, "[FAIL] ReLU test failed");

        $finish;
    end

    // Timeout
    initial begin
        #10000;
        $fatal(1, "[FAIL] Simulation timeout");
    end

endmodule

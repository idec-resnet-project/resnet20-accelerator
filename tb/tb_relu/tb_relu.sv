`timescale 1ns/1ps

module tb_relu;
    localparam integer BITWIDTH = 16;
    logic clk = 0;
    logic nrst = 0;
    logic enable = 1;
    logic in_enable = 0;
    logic signed [BITWIDTH-1:0] in_data = '0;
    wire out_enable;
    wire signed [BITWIDTH-1:0] out_data;

    always #5 clk = ~clk; // 100 MHz
    relu #(.BITWIDTH(BITWIDTH)) dut (.*);

    logic ref_valid1 = 0, ref_valid2 = 0;
    logic signed [BITWIDTH-1:0] ref_data1 = 0, ref_data2 = 0;
    integer pass_count = 0, fail_count = 0, valid_sent = 0;
    integer cycle_count = 0;

    function automatic signed [BITWIDTH-1:0] relu_ref(
        input bit en, input signed [BITWIDTH-1:0] value
    );
        relu_ref = (en && value < 0) ? '0 : value;
    endfunction

    always @(posedge clk or negedge nrst) begin
        if (!nrst) begin
            ref_valid1 <= 0;
            ref_valid2 <= 0;
            ref_data1 <= 0;
            ref_data2 <= 0;
        end else begin
            ref_valid1 <= in_enable;
            ref_data1 <= relu_ref(enable, in_data);
            ref_valid2 <= ref_valid1;
            ref_data2 <= ref_data1;
        end
    end

    // Compare after nonblocking assignments settle.
    always @(posedge clk) begin
        #1;
        if (nrst) begin
            cycle_count = cycle_count + 1;
            if ((out_enable !== ref_valid2) ||
                (ref_valid2 && out_data !== ref_data2)) begin
                fail_count = fail_count + 1;
                $display("[FAIL] cycle=%0d valid=%b expected_valid=%b data=%0d expected_data=%0d",
                    cycle_count, out_enable, ref_valid2, out_data, ref_data2);
            end else if (ref_valid2) begin
                pass_count = pass_count + 1;
                $display("[PASS] cycle=%0d output=%0d", cycle_count, out_data);
            end
        end
    end

    task automatic send(input bit en, input bit valid,
                        input signed [BITWIDTH-1:0] value);
        @(negedge clk);
        enable = en;
        in_enable = valid;
        in_data = value;
        if (valid) valid_sent = valid_sent + 1;
    endtask

    initial begin
        repeat (3) @(negedge clk);
        nrst = 1;
        send(1, 1, -16'sd3);
        send(1, 1,  16'sd2);
        send(1, 1, -16'sd1);
        send(1, 1,  16'sd5);
        send(1, 1,  16'sd0);
        send(1, 1, -16'sd8);
        send(1, 1,  16'sd7);
        send(1, 0,  16'sd99); // invalid data is don't-care
        send(0, 1, -16'sd4);  // bypass negative
        send(0, 1,  16'sd6);
        send(1, 1,  16'sh7fff);
        send(1, 1,  16'sh8000);
        send(1, 0, '0);
        repeat (3) @(negedge clk);
        if (fail_count == 0 && pass_count == valid_sent)
            $display("[PASS] ALL TESTS PASSED (%0d vectors)", pass_count);
        else
            $fatal(1, "[FAIL] pass=%0d fail=%0d sent=%0d",
                pass_count, fail_count, valid_sent);
        $finish;
    end
    initial begin
        #10000;
        $fatal(1, "[FAIL] Timeout");
    end
endmodule

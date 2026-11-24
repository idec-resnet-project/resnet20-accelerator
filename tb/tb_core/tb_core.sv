
`timescale 1ns/1ps

module tb_mac;

reg clk;
reg nrst;
reg enable;
reg [15:0] iteration;
reg in_enable;
reg signed [15:0] in_data;
reg signed [15:0] kernel_data;

wire out_enable;
wire signed [15:0] out_data;

integer output_count = 0;

// 1. MAC 모듈 연결
mac #(
    .BITWIDTH(16),
    .BITWIDTH_MAC_ITERATION(16),
    .FRAC_W(8),
    .ACC_W(48)
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

// 2. Clock: 10ns period (100MHz)
initial clk = 0;
always #5 clk = ~clk;

// 3. Send 4 MAC inputs
task send_four;
    input signed [15:0] data_value;
    input signed [15:0] kernel_value;
    integer i;
    begin
        enable = 1;
        iteration = 4;

        for (i = 0; i < 4; i = i + 1) begin
            @(negedge clk);
            in_enable = 1;
            in_data = data_value;
            kernel_data = kernel_value;
        end

        @(negedge clk);
        in_enable = 0;
    end
endtask

// 4. Verify outputs
always @(posedge clk) begin
    #1;
    if (nrst && out_enable) begin
        output_count = output_count + 1;

        $display("TIME=%0t OUTPUT=%0d",
                 $time, out_data);

        case (output_count)
            1: if (out_data !== 16'sd256)
                   $error("TEST 1 FAILED");
            2: if (out_data !== -16'sd256)
                   $error("TEST 2 FAILED");
            3: if (out_data !== 16'sd7)
                   $error("BYPASS FAILED");
            default: $error("Unexpected output");
        endcase
    end
end

// 5. Test scenarios
initial begin
    nrst = 0;
    enable = 0;
    iteration = 4;
    in_enable = 0;
    in_data = 0;
    kernel_data = 0;

    // Reset release
    #22;
    nrst = 1;

    // TEST 1: Positive accumulation
    // 128 * 128 * 4 / 256 = 256
    send_four(16'sd128, 16'sd128);

    repeat (8) @(negedge clk);

    // TEST 2: Negative accumulation
    // -128 * 128 * 4 / 256 = -256
    send_four(-16'sd128, 16'sd128);

    repeat (8) @(negedge clk);

    // TEST 3: Fast bypass
    enable = 0;
    in_enable = 1;
    in_data = 16'sd7;
    kernel_data = 0;

    @(negedge clk);
    in_enable = 0;

    repeat (5) @(negedge clk);

    if (output_count == 3)
        $display("ALL TESTS COMPLETED");
    else
        $error("Expected 3 outputs, got %0d",
               output_count);

    $finish;
end

endmodule

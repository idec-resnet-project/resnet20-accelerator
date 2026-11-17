`timescale 1ns/1ps

module relu #(parameter integer BITWIDTH = 16)(
    input  wire clk,
    input  wire nrst,
    input  wire enable,
    input  wire in_enable,
    input  wire signed [BITWIDTH-1:0] in_data,
    output wire out_enable,
    output wire signed [BITWIDTH-1:0] out_data
);
    reg stage1_valid;
    reg signed [BITWIDTH-1:0] stage1_data;
    reg stage2_valid;
    reg signed [BITWIDTH-1:0] stage2_data;

    wire zero_negative = enable & in_data[BITWIDTH-1];
    wire signed [BITWIDTH-1:0] relu_value =
        in_data & {BITWIDTH{~zero_negative}};

    assign out_enable = stage2_valid;
    assign out_data   = stage2_data;

    always @(posedge clk or negedge nrst) begin
        if (!nrst) begin
            stage1_valid <= 1'b0;
            stage1_data  <= {BITWIDTH{1'b0}};
            stage2_valid <= 1'b0;
            stage2_data  <= {BITWIDTH{1'b0}};
        end else begin
            stage1_valid <= in_enable;
            stage1_data  <= relu_value;
            stage2_valid <= stage1_valid;
            stage2_data  <= stage1_data;
        end
    end
endmodule

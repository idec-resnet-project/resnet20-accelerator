`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/11/20 10:11:01
// Design Name: AI Accelerator Core
// Module Name: saturate
// Project Name: MAC
// Target Devices: Zed Board
// Tool Versions: Vivado 2022.2
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module saturate #(
    parameter integer IN_W = 17,
    parameter integer OUT_W = 16
)(
    input  wire signed [ IN_W-1:0] data_in,
    output wire signed [OUT_W-1:0] data_out
);

    localparam signed [OUT_W-1:0] MIN_VALUE = {1'b1, {(OUT_W-1){1'b0}}};
    localparam signed [OUT_W-1:0] MAX_VALUE = {1'b0, {(OUT_W-1){1'b1}}};

    wire [IN_W-OUT_W:0] top_bits = data_in[IN_W-1:OUT_W-1];
    wire all_zero = ~|top_bits;
    wire all_one = &top_bits;
    wire in_range = all_zero | all_one;
    wire is_negative = data_in[IN_W-1];

    assign data_out = (in_range) ? data_in[OUT_W-1:0] : (is_negative) ? MIN_VALUE : MAX_VALUE;
endmodule

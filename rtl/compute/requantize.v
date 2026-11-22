`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/11/20 10:24:28
// Design Name: AI Accelerate Core
// Module Name: requantize
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


module requantize #(
    parameter integer IN_W = 37,
    parameter integer FRAC_W = 8,
    parameter integer OUT_W = 16
)(
    input wire signed [IN_W-1:0] data_in,
    output wire signed [OUT_W-1:0] data_out
);

    localparam integer ROUND_W = IN_W - FRAC_W;

    localparam signed [IN_W-1:0] HALF = {{(IN_W-1){1'b0}}, 1'b1} <<< (FRAC_W - 1);
    localparam signed [IN_W-1:0] HALF_MINUS = HALF - 1;

    wire signed [IN_W-1:0] temp = data_in + ((data_in < 0) ? HALF_MINUS : HALF);
    wire signed [ROUND_W-1:0] rounded = temp[IN_W-1:FRAC_W];

    saturate #(
        .IN_W   (ROUND_W),
        .OUT_W  (OUT_W)
    ) u_saturate(
        .data_in(rounded),
        .data_out(data_out)
    );
endmodule

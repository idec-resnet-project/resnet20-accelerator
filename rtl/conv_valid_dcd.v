//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/11/10 14:07:48
// Design Name: 
// Module Name: mac_packed
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

`timescale 1ns / 1ps

module conv_valid_dcd
#(
    parameter integer WORD_W = 16
)
(
    input   wire    mac_enable,
    input   wire    residual_enable,
    input   wire    relu_enable,
    input   wire    pooling_enable,
    input   wire    gap_enable,

    input   wire    mac_valid_out,
    input   wire    residual_valid_out,
    input   wire    relu_valid_out,
    input   wire    pooling_valid_out,
    input   wire    gap_valid_out,

    output  wire    mac_valid_in,
    output  wire    residual_valid_in,
    output  wire    relu_valid_in,
    output  wire    pooling_valid_in,
    output  wire    gap_valid_in,

    output  wire    valid_out
);
    
    assign mac_valid_in         = mac_enable && mac_valid_out;
    assign residual_valid_in    = residual_enable && residual_valid_out;
    assign relu_valid_in        = relu_enable && relu_valid_out;
    assign pooling_valid_in     = pooling_enable && pooling_valid_out;
    assign gap_valid_in         = gap_enable && gap_valid_out;

    
   
endmodule
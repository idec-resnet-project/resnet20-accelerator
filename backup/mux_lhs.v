`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/11/10 12:16:12
// Design Name: 
// Module Name: mux
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


module mux

#(
parameter integer WORD_W = 16
)
(
       
    input  wire [WORD_W-1:0] data_x,
    input  wire [WORD_W-1:0] data_y,
    input  wire              enable,
    output wire [WORD_W-1:0] data_out
    );
    
    assign data_out = (enable) ? data_y : data_x;
    
endmodule
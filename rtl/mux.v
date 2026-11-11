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
parameter integer BITWIDTH = 16
)
(
       
    input  wire [BITWIDTH-1:0] orig_data,
    input  wire [BITWIDTH-1:0] proc_data,
    input  wire                enable,
    output wire [BITWIDTH-1:0] out_data
    );
    
    assign out_data = (enable) ? proc_data : orig_data;
    
endmodule

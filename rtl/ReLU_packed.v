`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/11/10 12:16:12
// Design Name: 
// Module Name: ReLU_packed
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


module ReLU_packed#(
parameter integer BITWIDTH = 16
)
(
    input  wire clk,
    input  wire nrst,
    input  wire enable,
    input  wire in_enable,
    input  wire signed [BITWIDTH-1:0] in_data,
    output wire out_enable,
    output wire signed [BITWIDTH-1:0] out_data
    );
    wire [BITWIDTH-1:0] relu_out;
    mux uut_mux
    (
    .orig_data(in_data),
    .proc_data(relu_out),
    .enable(enable),      
    .out_data(out_data)
    );
    
    ReLU uut_ReLU
    (
    .clk(clk),                          
    .nrst(nrst),                         
    .enable(enable),                       
    .in_enable(in_enable),                    
    .in_data(in_data),                                
    .out_enable(out_enable),                   
    .out_data(relu_out)
    );
    
endmodule

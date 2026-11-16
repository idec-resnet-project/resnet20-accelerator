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
parameter integer WORD_W = 16
)
(
    input  wire clk,
    input  wire rst_n,
    input  wire enable,    
    input  wire signed [WORD_W-1:0] data_in,
    output wire out_enable,
    output wire signed [WORD_W-1:0] data_out    
    );


    wire [WORD_W-1:0] relu_out;
    mux uut_mux
    (
    .data_x(data_in),
    .data_y(relu_out),
    .enable(enable),      
    .out_data(data_out)
    );
    
    ReLU uut_ReLU
    (
    .clk(clk),                          
    .rst_n(rst_n),                         
    .enable(enable),                        
    .data_in(data_in),                                
    .valid_out(out_enable),                   
    .data_out(relu_out)
    );
    
endmodule

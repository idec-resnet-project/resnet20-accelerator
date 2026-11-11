`timescale 1ns / 1ps
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


module mac_packed#(
    parameter integer BITWIDTH = 16, //input data size = 16
    parameter integer ACC_WIDTH= 64,
    parameter integer ITER_CNT = 5 
)(
    input wire clk, 
    input wire nrst,
    input wire enable, //en = 0 -> data bypass, en = 1 -> using mac
    input wire [4:0] iteration, //if iteration = 3 -> Y = X0W0 + X1W1 + X2W2
    //input wire in_valid, //buffer --in_vaild--> mac
        
    //output in_ready, //buffer <--in_ready-- mac
   
    input wire signed [BITWIDTH-1:0] in_data,     //feature value
    input wire signed [BITWIDTH-1:0] kernel_data, //weight value
   
    output wire out_valid, //mac --out_vaild--> other
    //input out_ready, //mac <--out_ready-- other
    output wire signed [ACC_WIDTH-1:0] out_data //mac --out_data--> other
    );
    
    
    wire [ACC_WIDTH-1:0] proc_data;
    mux#(
    .BITWIDTH(ACC_WIDTH)
    ) uut_mux    
    (
    .orig_data(in_data),
    .proc_data(proc_data),
    
    .enable(enable),   
    .out_data(out_data)  
    );
    
    mac_v2 uut_mac
    (
    .clk(clk),                    
    .nrst(nrst),                   
    .enable(enable), //en = 0 -> data
    .iteration(iteration),
    //.in_valid(in_valid),
    .in_data(in_data),    
    .kernel_data(kernel_data),            
    .out_valid(out_valid), 
    .out_data(proc_data) //m
    );
    
endmodule

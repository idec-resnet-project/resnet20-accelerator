//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/11/10 12:54:19
// Design Name: 
// Module Name: pooling_packed
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

module pooling_packed #(
    parameter integer WORD_W = 16,          
    parameter integer ACC_W = WORD_W*2+1, 
    parameter integer ITER_CNT = 5   
)(
    input wire clk, 
    input wire rst_n,
    input wire enable_avg,                      
    input wire enable_max,
    input wire [ITER_CNT-1:0] iter,         
                                            

    input wire signed [WORD_W-1:0] data_in, 
    

    //output reg                     valid_out,                   
    output wire signed [WORD_W-1:0] data_out
    );

    wire    valid_out;
    wire    signed [WORD_W-1:0] data_out_pool;


    pooling_unit #(
        .WORD_W(WORD_W),
        .ACC_W(ACC_W),
        .ITER_CNT(ITER_CNT)
    ) uut_pooling_unit
    (
        .clk(clk),
        .rst_n(rst_n),
        .enable_avg(enable_avg),
        .enable_max(enable_max),
        .iter(iter),
        .data_in(data_in),
        .valid_out(valid_out),
        .data_out(data_out_pool)
    );

    mux #(
        .WORD_W(WORD_W)
    ) uut_mux    
    (
        .data_x(data_in),
        .data_y(data_out_pool),    
        .enable(valid_out),   
        .data_out(data_out)  
    );

    endmodule
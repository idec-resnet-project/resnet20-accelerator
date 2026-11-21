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
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     enable,  
    input  wire                     valid_in,  
    input  wire signed [WORD_W-1:0] data_in,
    
    output reg                     valid_out,
    output reg signed [WORD_W-1:0] data_out    
    );

    wire              valid_relu;
    wire signed [WORD_W-1:0] relu_out;
    wire signed [WORD_W-1:0] data_out_wire;
    
    always @ (posedge clk or negedge rst_n)
    begin
        if(!rst_n)
        begin
            valid_out   <= 0;
            data_out    <= 0;
        end
        else
        begin
            valid_out   <= valid_relu;
            data_out    <= data_out_wire;
        end
       
    end
    //assign valid_out = valid_relu;

    mux 
    #(
    .WORD_W(WORD_W)
    )uut_mux
    (
    .data_x(data_in),
    .data_y(relu_out),
    .enable(valid_relu),      
    .data_out(data_out_wire)
    );
    
    ReLU
    #(
    .WORD_W(WORD_W)
    ) uut_ReLU
    (
    .clk(clk),                          
    .rst_n(rst_n),                         
    .enable(enable),    
    .valid_in(valid_in),                    
    .data_in(data_in),                                
    .valid_out(valid_relu),     // valid_out 포트는 위 assign 으로만 구동
    .data_out(relu_out)
    );
    
endmodule
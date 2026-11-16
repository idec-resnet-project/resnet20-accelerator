`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/11/09 18:15:04
// Design Name: 
// Module Name: ReLU
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


module ReLU
#(
parameter integer BITWIDTH = 16
)
(
    input wire clk,
    input wire nrst,
    input wire enable,
    input wire in_enable,
    input wire signed [BITWIDTH-1:0] in_data,
    
    output reg out_enable,
    output reg signed [BITWIDTH-1:0] out_data
    );
    
    
    always @(posedge clk or negedge nrst)
    begin
        if(!nrst)
        begin
            out_enable  <= 0;
            out_data    <= 0;           
        end
        else if(in_enable)
            begin
                out_enable <= 1;                 
                out_data   <= (enable && in_data[BITWIDTH-1]) ? 0 : in_data;
                
            end
            
         else
            out_enable  <= 0;
     end
endmodule

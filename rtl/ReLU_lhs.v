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
parameter integer WORD_W = 16
)
(
    input wire clk,
    input wire rst_n,
    input wire enable,
    input wire signed [WORD_W-1:0] data_in,
    
    output reg valid_out,
    output reg signed [WORD_W-1:0] data_out
    );    
    always @(posedge clk or negedge rst_n)
    begin
    //=======================================================================
    // Sync Reset Logic for ReLU unit
    //=======================================================================
        if(!rst_n)
        begin
            valid_out  <= 0;
            data_out    <= 0;           
        end
    //=======================================================================
    // when enable is high, check for input data sign bit
    // if input data is negative, output is 0
    // else output the input data
    // when enable is low, output is 0
    //=======================================================================
        else if(enable)
            begin
                valid_out <= 1;                 
                data_out   <= (enable && data_in[WORD_W-1]) ? 0 : data_in;
                
            end
            
         else
            valid_out  <= 0;
     end
endmodule

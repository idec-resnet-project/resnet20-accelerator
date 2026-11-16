//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/11/10 12:54:19
// Design Name: 
// Module Name: maxpool
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

module maxpool #(
    parameter integer WORD_W = 16, 
    parameter integer ACC_W = WORD_W*2+1, 
    parameter integer ITER_CNT = 5   
)(
    input wire clk, 
    input wire rst_n,
    input wire enable,            
    input wire [ITER_CNT-1:0] iter,  
                                  

    input wire signed [WORD_W-1:0] data_in,      
    

    output reg              valid_out,   
    output reg signed [WORD_W-1:0] data_out 
    );
    
    reg [ITER_CNT-1:0] iter_cnt;
    reg [WORD_W-1:0]   max;
    always @(posedge clk or negedge rst_n)
    begin
        if(!rst_n)
        begin
            valid_out   <= 0;
            data_out    <= 0;
            iter_cnt    <= 0;
            max         <= 0;
        end
        else 
        begin
            if(enable && (iter_cnt == 0))
            begin
                iter_cnt    <= 1;
                max         <=  data_in; 
                valid_out   <= 0;           
            end
            else if( iter_cnt < iter)
            begin
                iter_cnt    <= iter_cnt + 1;
                max         <= (max < data_in) ? data_in : max; 
            end

            else if(iter_cnt == iter)
            begin
                data_out    <= max;
                valid_out   <= 1;
            end
            else
            begin
                valid_out   <= 0;
            end   
        end
    end
endmodule
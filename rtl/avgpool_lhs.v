//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/11/10 12:54:19
// Design Name: 
// Module Name: mac
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

module avgpool #(
    parameter integer WORD_W = 16,          
    parameter integer ACC_W = 64, 
    parameter integer ITER_CNT = 5   
)(
    input wire clk, 
    input wire rst_n,
    input wire enable,                      
    input wire [ITER_CNT-1:0] iter,         
                                            

    input wire signed [WORD_W-1:0] data_in, 
    

    output reg valid_out,                   
    output reg signed [WORD_W-1:0] data_out 
    );
    
    reg [WORD_W*2-1:0] sum;
    reg [ITER_CNT-1:0] iter_cnt;
    
    always @ (posedge clk or negedge rst_n)
    begin
        if(!rst_n)
        begin
            valid_out   <= 0;
            data_out    <= 0;
            sum         <= 0;            
        end
        
        else 
        begin
            if(enable && !(iter_cnt == iter))
            begin
                 sum <= sum + data_in;
                 iter_cnt <= iter_cnt + 1;
                 valid_out <= 0;             
            end
            
            else 
            begin
                if(iter_cnt == iter)
                begin
                    if(iter[0])
                        data_out <= sum / iter;
                    else                    
                        data_out <= (sum >> iter);                    
                    end                    
                    valid_out <= 1;
                    iter_cnt  <= 0;                    
                end
            end
        end
endmodule
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/11/10 12:54:19
// Design Name: 
// Module Name: avgpool
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
    parameter integer ACC_W = WORD_W*2+1, 
    parameter integer ITER_CNT = 5   
)(
    input wire clk, 
    input wire rst_n,
    input wire enable,             
    input wire valid_in,         
    input wire [ITER_CNT-1:0] iter,         
                                            

    input wire signed [WORD_W-1:0] data_in, 
    

    output reg                     valid_out,                   
    output reg signed [WORD_W-1:0] data_out 
    );
    
    reg signed  [ACC_W-1:0] sum;
    reg         [ITER_CNT-1:0] iter_cnt;
    reg         [ITER_CNT-1:0] iter_reg;
    //reg signed  [WORD_W-1:0] avg_result;
    reg         [ITER_CNT-1:0] divisor;
    reg                        proc;
    //=======================================================================
    // iteration count is 2's power, divisor = log2(iteration count)
    // iteration count is odd number, divisor = 0   
    //=======================================================================
        always @(*)
        begin
            divisor = {ITER_CNT{1'd0}};
            case(iter_reg)
                {16'b00000000}:  divisor = 4'd0;
                {16'b00000010}:  divisor = 4'd1;
                {16'b00000100}:  divisor = 4'd2;
                {16'b00001000}:  divisor = 4'd3;
                {16'b00010000}:  divisor = 4'd4;
                {16'b00100000}:  divisor = 4'd5;
                {16'b01000000}:  divisor = 4'd6;
                {16'b10000000}:  divisor = 4'd7;
                //{ITER_CNT{'d16}}: divisor = {ITER_CNT{1'd4}};
                default: divisor = {ITER_CNT{1'd0}};                
            endcase
        end
        
        always @ (posedge clk or negedge rst_n)
        begin
            //=======================================================================
            // Async Reset Logic for avgpool unit
            //=======================================================================
            if(!rst_n)
            begin
                valid_out   <= 0;
                data_out    <= 0;
                sum         <= 0;  
                iter_cnt    <= 0;
                iter_reg    <= 0;   
                proc        <= 0;       
            end
            
            else 
            begin
            //=======================================================================
            // when enable is high and iteration count is 0,
            // set sum to data_in and iteration count to 1
            //=======================================================================
                if(enable && valid_in && (iter_cnt == 0))
                begin
                    sum        <= data_in;
                    iter_cnt   <= 1;
                    valid_out  <= 0;       
                    proc       <= 1;   
                    iter_reg   <= iter;   
                end
            //=======================================================================
            // when enable is high and iteration count is less than iter,
            // add data_in to sum and increment iteration count
            //=======================================================================
                else if(proc && (iter_cnt < iter_reg))
                begin
                    sum        <= sum + data_in;
                    iter_cnt   <= iter_cnt + 1;                             
                end
            //=======================================================================
            // when iteration count is equal to iter,
            // output is sum/iter when iter is odd number
            // output is sum >>> iter when iter is 2's power
            //=======================================================================       
                else if(proc && iter_cnt == iter_reg)
                begin
                //=======================================================================
                // when iteration count is odd number, output is sum/iter ==> not implemented
                // when iteration count is 2's power, output is sum >>> clog2(iter)=divisor
                //=======================================================================                                  
                    data_out <= (sum >>> divisor);       //need arangements                                           
                    valid_out  <= 1;
                    iter_cnt   <= 0;          
                    iter_reg   <= 0; 
                    proc       <= 0;                             
                 end
                 else if(valid_out)
                    valid_out <= 0;
            end
        end
endmodule
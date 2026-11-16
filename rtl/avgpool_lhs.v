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
    input wire [ITER_CNT-1:0] iter,         
                                            

    input wire signed [WORD_W-1:0] data_in, 
    

    output reg                     valid_out,                   
    output reg signed [WORD_W-1:0] data_out 
    );
    
    reg signed  [ACC_W-1:0] sum;
    reg         [ITER_CNT-1:0] iter_cnt;
    reg signed  [WORD_W-1:0] avg_result;
    reg         [ITER_CNT-1:0] divisor;
    //=======================================================================
    // iteration count is 2's power, divisor = log2(iteration count)
    // iteration count is odd number, divisor = 0   
    //=======================================================================
    always @(*)
    begin
        divisor = {ITER_CNT{1'd0}};
        case(iter)
            {4'b0000}:  divisor = {ITER_CNT{1'd0}};
            {4'b0010}:  divisor = {ITER_CNT{1'd1}};
            {4'b0100}:  divisor = {ITER_CNT{2'd2}};
            {4'b1000}:  divisor = {ITER_CNT{2'd3}};
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
        end
        
        else 
        begin
        //=======================================================================
        // when enable is high and iteration count is 0,
        // set sum to data_in and iteration count to 1
        //=======================================================================
            if(enable && (iter_cnt == 0))
            begin
                 sum        <= data_in;
                 iter_cnt   <= 1;
                 valid_out  <= 0;             
            end
        //=======================================================================
        // when enable is high and iteration count is less than iter,
        // add data_in to sum and increment iteration count
        //=======================================================================
            else if(enable && (iter_cnt < iter))
            begin
                sum        <= sum + data_in;
                iter_cnt   <= iter_cnt + 1;                             
            end
        //=======================================================================
        // when iteration count is equal to iter,
        // output is sum/iter when iter is odd number
        // output is sum >>> iter when iter is 2's power
        //=======================================================================       
            else 
            begin
                if(iter_cnt == iter)
                begin
            //=======================================================================
            // when iteration count is odd number, output is sum/iter ==> not implemented
            // when iteration count is 2's power, output is sum >>> clog2(iter)=divisor
            //=======================================================================
                    /*if(iter[0])
                        avg_result <= sum / iter;
                    else     */               
                        data_out <= (sum >>> divisor);       //need arangements             
                    end
                    //data_out   <= avg_result;                    
                    valid_out  <= 1;
                    iter_cnt   <= 0;                    
                end
            end
        end
endmodule
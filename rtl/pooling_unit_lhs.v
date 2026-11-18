`timescale 1ns / 1ps

module pooling_unit #(
    parameter integer WORD_W = 16,          
    parameter integer ACC_W = WORD_W*2+1, 
    parameter integer MAX_ITER_CNT = 5,
    parameter integer AVG_ITER_CNT = 5 
)(
    input wire clk, 
    input wire rst_n,
    input wire valid_in,
    input wire enable_avg,                      
    input wire enable_max,
    input wire [MAX_ITER_CNT-1:0] max_iter,         
    input wire [AVG_ITER_CNT-1:0] avg_iter,                                          

    input wire signed [WORD_W-1:0] data_in, 
    

    output wire                     valid_out,                   
    output wire signed [WORD_W-1:0] data_out 
    );

    wire    valid_out_packed;
    wire    valid_out_avg;
    wire    valid_out_max;
    wire    signed [WORD_W-1:0] data_out_avg;
    wire    signed [WORD_W-1:0] data_out_max;
    

    assign  valid_out        = valid_out_avg || valid_out_max;
    assign  valid_out_packed = ~valid_out_avg && valid_out_max;
    
    avgpool #(
        .WORD_W(WORD_W),
        .ACC_W(ACC_W),
        .ITER_CNT(AVG_ITER_CNT)
    ) uut_avgpool (
        .clk(clk),
        .rst_n(rst_n),
        .enable(enable_avg),
        .valid_in(valid_in),
        .iter(avg_iter),
        .data_in(data_in),
        .valid_out(valid_out_avg),
        .data_out(data_out_avg)
    );

    maxpool #(
        .WORD_W(WORD_W),
        .ACC_W(ACC_W),
        .ITER_CNT(MAX_ITER_CNT)
    ) uut_maxpool (
        .clk(clk),
        .rst_n(rst_n),
        .enable(enable_max),
        .valid_in(valid_in),
        .iter(max_iter),
        .data_in(data_in),
        .valid_out(valid_out_max),
        .data_out(data_out_max)
    );
    
    mux
    #(
        .WORD_W(WORD_W)
    ) uut_mux    
    (
        .data_x(data_out_avg),
        .data_y(data_out_max),    
        .enable(valid_out_packed),   
        .data_out(data_out)  
    );

    endmodule
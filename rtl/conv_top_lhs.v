`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/11/10 12:16:12
// Design Name: 
// Module Name: conv_top
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


module conv_top

#(
    parameter integer WORD_W = 16,
    parameter integer BITWIDTH_MAC_ITERATION     = 16,
    parameter integer BITWIDTH_POOLING_ITERATION = 16,
    parameter integer BITWIDTH_GAP_ITERATION     = 16,
    // parallelism
    parameter integer PARALLEL_PC                = 1,
    parameter integer PARALLEL_PF                = 1
)
    (
    input  wire                                  clk,
    input  wire                                  nrst,
    
    // config
    input  wire                                  mac_enable,
    input  wire [BITWIDTH_MAC_ITERATION-1:0]     mac_iteration,
    input  wire                                  residual_enable,
    input  wire                                  relu_enable,
    input  wire                                  pooling_enable,
    input  wire [BITWIDTH_POOLING_ITERATION-1:0] pooling_iteration,
    input  wire                                  gap_enable,
    input  wire [BITWIDTH_GAP_ITERATION-1:0]     gap_iteration,
    
    // input
    input  wire                                  in_enable,
    input  wire [PARALLEL_PC*WORD_W-1:0]         in_data,
    input  wire [PARALLEL_PC*WORD_W-1:0]         kernel_data,
    input  wire [PARALLEL_PC*WORD_W-1:0]         bias_data,
    
    // output
    output reg                                   out_enable,
    output reg  [WORD_W-1:0]                     out_data
   
    );
    wire    [PARALLEL_PC*WORD_W-1:0]    mac_out;
    wire    [PARALLEL_PC*WORD_W-1:0]    ReLU_out;
    wire    [PARALLEL_PC*WORD_W-1:0]    pooling_out;
    wire    [PARALLEL_PC*WORD_W-1:0]    residual_out;

    wire                                mac_valid_out;
    wire                                relu_valid_out;
    wire                                pooling_valid_out;
    wire                                gap_valid_out;
    wire                                residual_valid_out;

    wire                                mac_valid_in;
    wire                                relu_valid_in;
    wire                                pooling_valid_in;
    wire                                gap_valid_in;
    wire                                residual_valid_in;

    always @(posedge clk or negedge nrst)
    begin
        if(!nrst)
        begin
            out_data    <= 0;
            out_enable  <= 0;
        end
        
        else
            begin
            out_data    <= pooling_out;      
            out_enable  <= 1;
            end   
    end
    
    genvar i;
    
    generate
    for(i = 0; i<PARALLEL_PC; i=i+1)
    begin
    mac_packed
    #(
    .WORD_W(WORD_W),
    .ACC_W(WORD_W*2+1),
    .ITER_CNT(BITWIDTH_MAC_ITERATION)
    ) 
    uut_mac
    (
    .clk        (clk),                                                
    .rst_n      (nrst),                                              
    .enable     (mac_enable),                                                    
    .iter       (mac_iteration), 
    .valid_in   (),  
    .fmap_in    (in_data[i*WORD_W+:WORD_W]),                          
    .weight_in  (kernel_data[i*WORD_W+:WORD_W]),  
    .valid_out  (mac_valid_out),             
    .data_out   (mac_out[i*WORD_W+:WORD_W])             
     );
    
    ReLU_packed
    #(
    .WORD_W(WORD_W)
    )
    uut_ReLU
    (
    .clk        (clk),      
    .rst_n      (nrst),    
    .enable     (relu_enable),   
    .data_in    (mac_out[i*WORD_W+:WORD_W]),  
    //.valid_out(),
    .data_out   (ReLU_out[i*WORD_W+:WORD_W])
    );
    
    residual_packed
    #(
    .WORD_W(WORD_W)
    )
    uut_residual
    (
    .clk        (clk),        
    .rst_n      (nrst),      
    .enable     (residual_enable),     
    //.valid_in(),   
    .data_in    (ReLU_out[i*WORD_W+:WORD_W]),    
    .data_skip  (bias_data[i*WORD_W+:WORD_W]),
    .data_out   (residual_out[i*WORD_W+:WORD_W])       
    );
    end
    endgenerate
    pooling_packed
    #(
    .WORD_W(WORD_W),
    .ACC_W(WORD_W*2+1),
    .MAX_ITER_CNT(BITWIDTH_POOLING_ITERATION),
    .AVG_ITER_CNT(BITWIDTH_GAP_ITERATION)
    )
    uut_pooling
    (
    .clk(clk),          
    .rst_n(nrst),        
    .enable_avg(gap_enable),   
    .enable_max(pooling_enable),   
    .max_iter(pooling_iteration),
    .avg_iter(gap_iteration),     
    .data_in(residual_out),
    .data_out(pooling_out)          
    );
    
    
endmodule
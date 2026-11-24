//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/11/10 14:07:48
// Design Name: 
// Module Name: mac_packed
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
module mac_packed#(
    parameter integer WORD_W   = 16, //input data size = 16
    parameter integer ACC_W    = WORD_W*2+1,
    parameter integer ITER_CNT = 16 
)(
    input   wire                            clk, 
    input   wire                            rst_n,
    input   wire                            enable, //en = 0 -> data bypass, en = 1 -> using mac 
    input   wire                            valid_in, //valid_in = 1 -> data is valid, valid_in = 0 -> data is invalid   
    input   wire           [ITER_CNT-1:0]   iter, //if iteration = 3 -> Y = X0W0 + X1W1 + X2W2  
    input   wire    signed [WORD_W-1:0]     fmap_in,     //feature value
    input   wire    signed [WORD_W-1:0]     weight_in, //weight value   
    input   wire    signed [WORD_W-1:0]     bias_in, //bias value   
    
    output  wire                             valid_out, //valid_out = 1 -> data is valid, valid_out = 0 -> data is invalid
    output  wire     signed [WORD_W-1:0]     data_out //mac --out_data--> other
    );
    
    
    wire          [ACC_W:0]     proc_data;
    wire          [WORD_W-1:0]  rounded_data;
    wire                        mac_proc;
    wire                        valid_out_mac;
    wire                        valid_out_post_mac;
    wire                        valid_mux;   
    wire   signed [WORD_W-1:0]  data_out_wire;
    
    assign  valid_mux = valid_out_post_mac||mac_proc||enable||valid_out_mac;
    assign valid_out = valid_out_post_mac;
    assign data_out  = data_out_wire;
 
    mux#(
    .WORD_W(WORD_W)
    ) uut_mux    
    (
    .data_x(fmap_in),
    .data_y(rounded_data),    
    .enable(valid_mux),   
    .data_out(data_out_wire)  
    );
    
    mac_v3 
    #(
    .WORD_W(WORD_W),
    .ACC_W(ACC_W),
    .ITER_CNT(ITER_CNT)
    )
    uut_mac
    (
    .clk(clk),                    
    .rst_n(rst_n),                   
    .enable(enable), //en = 0 -> data
    .valid_in(valid_in), //valid_in = 1 -> data is valid, valid_in = 0 -> data is invalid
    .iter(iter),    
    .fmap_in(fmap_in),    
    .weight_in(weight_in), 
    .bias_in(bias_in),
    .proc(mac_proc),       
    .valid_out(valid_out_mac), 
    .data_out(proc_data) //m
    );
    
    
    post_mac 
    #(
    .WORD_W(WORD_W),
    .ACC_W(ACC_W)
    )
    uut_post_mac
    (
    .clk(clk),     
    .rst_n(rst_n),    
    .valid_in(valid_out_mac),
    .valid_out(valid_out_post_mac),    
    .data_in(proc_data), 
    .data_out(rounded_data) 
    );
    
endmodule
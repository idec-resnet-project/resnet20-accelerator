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


module residual_packed

#(
parameter integer WORD_W = 16
)
    (
      input  wire                     clk,      
      input  wire                     rst_n,    
      input  wire                     enable,   
      //input  wire                     valid_in, 
      input  wire signed [WORD_W-1:0] data_in,  
      input  wire signed [WORD_W-1:0] data_skip,
                                                  
      //output wire                      valid_out,
      output wire  signed [WORD_W-1:0] data_out   
           
    );
    
    wire    [WORD_W-1:0]    resi_data;
    wire                    valid_mux;
    
    residual_unit 
    #(
    .WORD_W(WORD_W)
    )uut_residual
    (
        .clk(clk),      
        .rst_n(rst_n),    
        .enable(enable),   
        //.valid_in(valid_in), 
        .data_in(data_in),  
        .data_skip(data_skip),                  
        .valid_out(valid_mux),
        .data_out(resi_data)      
    );
    
    mux 
    #(
    .WORD_W(WORD_W)
    )
    uut_mux
    (
        .data_x(data_in), 
        .data_y(resi_data), 
        .enable(valid_mux), 
        .data_out(data_out)    
    );
endmodule
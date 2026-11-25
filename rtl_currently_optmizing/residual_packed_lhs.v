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
      input  wire                     valid_in, 
      input  wire signed [WORD_W-1:0] data_in,  
      input  wire signed [WORD_W-1:0] data_skip,
                                                  
      output reg                                valid_out,
      output reg  signed [WORD_W-1:0]           data_out   
           
    );
    
    wire    [WORD_W-1:0]    resi_data;
    wire                    valid_mux;
    wire                    proc_resi;
    wire                    valid_resi;
    wire                    done_resi;
    wire    signed [WORD_W-1:0] data_out_wire;
    assign                  valid_mux = valid_resi || proc_resi || done_resi;
    
    always @ (posedge clk or negedge rst_n)
    begin
        if(!rst_n)
        begin
            valid_out   <= 0;
            data_out    <= 0;
        end
        else
        begin
            valid_out   <= valid_resi;
            data_out    <= data_out_wire;
        end
    end
    //assign                  valid_out = valid_resi;
    residual_unit 
    #(
    .WORD_W(WORD_W)
    )uut_residual
    (
        .clk        (clk),      
        .rst_n      (rst_n),    
        .enable     (enable),   
        .valid_in   (valid_in), 
        .data_in    (data_in),  
        .data_skip  (data_skip),                
        .done       (done_resi),    
        .proc       (proc_resi),      
        .valid_out  (valid_resi),
        .data_out   (resi_data)      
    );
    
    mux 
    #(
    .WORD_W(WORD_W)
    )
    uut_mux
    (
        .data_x     (data_in), 
        .data_y     (resi_data), 
        .enable     (valid_mux), 
        .data_out   (data_out_wire)    
    );
endmodule
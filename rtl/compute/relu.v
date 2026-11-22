`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/11/15 10:38:50
// Design Name: AI Accelerator Core
// Module Name: ReLU
// Project Name: AI Accelerator
// Target Devices: Zed Board
// Tool Versions: Vivado 2022.2
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module relu #(parameter integer BITWIDTH = 16)(
    input wire clk,
    input wire nrst,
    input wire enable,
    input wire in_enable,
    input wire signed [BITWIDTH-1:0] in_data,
    output reg out_enable,
    output reg signed [BITWIDTH-1:0] out_data
);

    wire is_negative = in_data[BITWIDTH - 1];
    wire signed [BITWIDTH-1:0] valid_data = (enable && is_negative) ? 0 : in_data;
    
    reg pending_enable;
    reg signed [BITWIDTH-1:0] pending_data;

    always @(posedge clk or negedge nrst) begin
        if(!nrst) begin
            pending_enable <= 0;
            pending_data <= 0;
        end else begin
            pending_enable <= in_enable;
            if(in_enable) pending_data <= valid_data;
        end
    end

    always @(posedge clk or negedge nrst) begin
        if(!nrst) begin
            out_enable <= 0;
            out_data <= 0;
        end else begin
            out_enable <= pending_enable;
            if(pending_enable) out_data <= pending_data;
        end
    end
endmodule

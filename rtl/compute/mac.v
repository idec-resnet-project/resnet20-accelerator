`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/11/20 16:46:53
// Design Name: AI Accelerator Core
// Module Name: mac
// Project Name: MAC
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


module mac #(
    parameter integer BITWIDTH = 16,
    parameter integer ITER_W = 5,
    parameter integer FRAC_W = 8,
    parameter integer MULTI_REG = 1
)(
    input wire clk,
    input wire nrst,
    input wire enable,
    input wire [ITER_W-1:0] iteration,
    input wire in_enable,
    input wire signed [BITWIDTH-1:0] in_data,
    input wire signed [BITWIDTH-1:0] kernel_data,
    output reg out_enable,
    output reg signed [BITWIDTH-1:0] out_data
);

    wire is_last;

    window_counter #(
        .ITER_W(ITER_W)
    ) u_window_counter(
        .clk(clk),
        .nrst(nrst),
        .enable(enable),
        .iteration(iteration),
        .in_enable(in_enable),
        .is_first(),
        .is_last(is_last)
    );

    wire                         m_valid;
    wire                         m_bypass;
    wire                         m_last;
    wire signed [BITWIDTH*2-1:0] m_product;

    mac_multiplier #(
        .BITWIDTH(BITWIDTH),
        .FRAC_W(FRAC_W),
        .MULTI_REG(MULTI_REG)
    ) u_mac_multiplier(
        .clk(clk),
        .nrst(nrst),
        .enable(enable),
        .in_enable(in_enable),
        .in_last(is_last),
        .in_data(in_data),
        .kernel_data(kernel_data),

        .out_valid(m_valid),
        .out_bypass(m_bypass),
        .out_last(m_last),
        .out_product(m_product)
    );

    wire                       pending_enable;
    wire signed [BITWIDTH-1:0] pending_data;

    mac_accumulator #(
        .BITWIDTH(BITWIDTH),
        .ITER_W (ITER_W),
        .FRAC_W (FRAC_W)
    ) u_mac_accumulator(
        .clk(clk),
        .nrst(nrst),
        .in_valid(m_valid),
        .in_bypass(m_bypass),
        .in_last(m_last),
        .in_product(m_product),

        .out_enable(pending_enable),
        .out_data(pending_data) 
    );

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

`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/11/19 14:42:19
// Design Name: AI Accelerator Core
// Module Name: mac_multiplier
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


module mac_multiplier #(
    parameter integer BITWIDTH = 16,
    parameter integer FRAC_W = 8,
    parameter integer MULTI_REG = 1
)(
    input wire clk,
    input wire nrst,
    input wire enable,
    input wire in_enable,
    input wire in_last,
    input wire signed [BITWIDTH-1:0] in_data,
    input wire signed [BITWIDTH-1:0] kernel_data,

    output wire out_valid,
    output wire out_bypass,
    output wire out_last,
    output wire signed [BITWIDTH*2-1:0] out_product
);

    localparam integer PROD_W = BITWIDTH * 2;

    localparam signed [BITWIDTH-1:0] ONE = {{(BITWIDTH-1){1'b0}}, 1'b1};

    wire signed [BITWIDTH-1:0] kernel_sel = enable ? kernel_data : ONE;
    wire signed [PROD_W-1:0] product = in_data * kernel_data;

    generate
        if(MULTI_REG) begin : g_multi_reg
            reg                       r_valid;
            reg                       r_bypass;
            reg                       r_last;
            reg signed [PROD_W-1:0]   r_product;

            always @(posedge clk or negedge nrst) begin
                if(!nrst) begin
                    r_valid <= 0;
                    r_bypass <= 0;
                    r_last <= 0;
                end else begin
                    r_valid <= in_enable;
                    if(in_enable) begin
                        r_bypass <= !enable;
                        r_last <= in_last;
                    end
                end
            end

            always @(posedge clk) begin
                if(!nrst) r_product <= 0;
                else r_product <= product;
            end

            assign out_valid   = r_valid;
            assign out_bypass  = r_bypass;
            assign out_last    = r_last;
            assign out_product = r_product;
        end else begin : no_multi_reg
            assign out_valid   = in_enable;
            assign out_bypass  = !enable;
            assign out_last    = in_last;
            assign out_product = product;
        end
    endgenerate
endmodule

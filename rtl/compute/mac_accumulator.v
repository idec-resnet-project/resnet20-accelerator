`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/11/20 13:44:23
// Design Name: AI Accelerator Core
// Module Name: mac_accumulator
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


module mac_accumulator #(
    parameter integer BITWIDTH = 16,
    parameter integer ITER_W = 5,
    parameter integer FRAC_W = 8
)(
    input wire clk,
    input wire nrst,

    input wire in_valid,
    input wire in_bypass,
    input wire in_last,
    input wire signed [BITWIDTH*2-1:0] in_product,

    output reg                       out_enable,
    output reg signed [BITWIDTH-1:0] out_data 
);

    localparam integer PROD_W = BITWIDTH * 2;
    localparam integer ACC_W = PROD_W + ITER_W;

    reg signed [ACC_W-1:0] accumulator;
    wire signed [ACC_W-1:0] total = accumulator + in_product;
    wire signed [BITWIDTH-1:0] result;

    requantize #(
        .IN_W    (ACC_W),
        .FRAC_W  (FRAC_W),
        .OUT_W   (BITWIDTH)
    ) u_requantize(
        .data_in(total),
        .data_out(result)
    );

    always @(posedge clk or negedge nrst) begin
        if(!nrst) begin
            accumulator <= 0;
            out_enable <= 0;
            out_data <= 0;
        end else begin
            out_enable <= in_valid && (in_bypass || in_last);

            if(in_valid) begin
                if(in_bypass || in_last) begin
                    accumulator <= 0;
                    out_data <= result;
                end else begin
                    accumulator <= total;
                end
            end
        end
    end
endmodule

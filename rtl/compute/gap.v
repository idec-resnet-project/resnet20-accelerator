`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/11/16 18:50:24
// Design Name: AI Accelerator Core
// Module Name: gap
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


module gap #(
    parameter integer BITWIDTH = 16,
    parameter integer ITER_W = 5
)(
    input wire clk,
    input wire nrst,
    input wire enable,
    input wire [ITER_W-1:0] iteration,
    input wire in_enable,
    input wire signed [BITWIDTH-1:0] in_data,
    output reg out_enable,
    output reg signed [BITWIDTH-1:0] out_data
);

    localparam integer SUM_W = BITWIDTH + ITER_W;
    localparam integer SHIFT_W = (ITER_W > 1) ? $clog2(ITER_W) : 1;

    function automatic [SHIFT_W-1:0] pow([ITER_W-1:0] value);
        integer i;

        begin
            pow = {(SHIFT_W){1'b0}};
            for(i = 0; i < ITER_W; i = i+1) begin
                if(value[i]) pow = i;
            end
        end
    endfunction

    reg [ITER_W-1:0] input_count;
    wire is_last = (input_count == iteration - 1'b1);

    always @(posedge clk or negedge nrst) begin
        if(!nrst) begin
            input_count <= {ITER_W{1'b0}};
        end else begin
            if(in_enable) begin
                if(!enable || is_last) input_count <= {ITER_W{1'b0}};
                else input_count <= input_count + 1'b1;
            end
        end
    end

    reg signed [SUM_W-1:0] accumulator;
    wire signed [SUM_W-1:0] extended_in = in_data;
    wire signed [SUM_W-1:0] total = accumulator + extended_in;

    reg               pending_enable;
    reg               pending_negative;
    reg  [SUM_W-1:0]  pending_abs;
    reg  [ITER_W-1:0] pending_shift;

    always @(posedge clk or negedge nrst) begin
        if(!nrst) begin
            accumulator <= 0;
            pending_enable <= 0;
            pending_negative <= 0;
            pending_abs <= {SUM_W{1'b0}};
            pending_shift <= {SHIFT_W{1'b0}};
        end else begin
            pending_enable <= 0;
            if(in_enable) begin
                if(!enable) begin
                    accumulator <= 0;
                    pending_negative <= (extended_in < 0);
                    pending_abs <= (extended_in < 0) ? -extended_in : extended_in;
                    pending_shift <= {SHIFT_W{1'b0}};
                    pending_enable <= 1'b1;
                end else if(is_last) begin
                    accumulator <= 0;
                    pending_negative <= (total < 0);
                    pending_abs <= (total < 0) ? -total : total;
                    pending_shift <= pow(iteration);
                    pending_enable <= 1'b1;
                end else begin
                    accumulator <= total;
                end
            end
        end
    end

    wire [SUM_W-1:0] half_divider = ({{(SUM_W-1){1'b0}}, 1'b1} << pending_shift) >> 1;
    wire [SUM_W-1:0] quotient = (pending_abs + half_divider) >> pending_shift;
    wire signed [SUM_W:0] avg_temp = pending_negative ? -$signed({1'b0, quotient}) : $signed({1'b0, quotient});
    wire signed [BITWIDTH-1:0] average;

    saturate #(
        .IN_W     (SUM_W + 1),
        .OUT_W    (BITWIDTH)
    ) u_saturate (
        .data_in  (avg_temp),
        .data_out (average)
    );

    always @(posedge clk or negedge nrst) begin
        if(!nrst) begin
            out_enable <= 0;
            out_data <= 0;
        end else begin
            out_enable <= pending_enable;
            if(pending_enable) out_data <= average;
        end
    end
endmodule

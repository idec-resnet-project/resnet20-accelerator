`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/11/16 18:50:13
// Design Name: AI Accelerator Core
// Module Name: pooling
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


module pooling #(
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

    reg [ITER_W-1:0] input_count;
    wire is_first = (input_count == {ITER_W{1'b0}});
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

    reg signed [BITWIDTH-1:0] maximum;
    wire signed [BITWIDTH-1:0] next_maximum = (is_first || in_data > maximum) ? in_data : maximum;

    reg pending_enable;
    reg signed [BITWIDTH-1:0] pending_data;

    always @(posedge clk or negedge nrst) begin
        if(!nrst) begin
            pending_enable <= 0;
            pending_data <= 0;
            maximum <= 0;
        end else begin
            pending_enable <= in_enable && (!enable || is_last);
            if(in_enable) begin
                if(!enable) pending_data <= in_data;
                else if(is_last) pending_data <= next_maximum;
                else maximum <= next_maximum; 
            end
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

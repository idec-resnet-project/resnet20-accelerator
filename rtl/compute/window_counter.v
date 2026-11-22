`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/11/19 14:18:28
// Design Name: AI Accelerator Core
// Module Name: window_counter
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


module window_counter #(parameter integer ITER_W = 5)(
    input wire clk,
    input wire nrst,
    input wire enable,
    input wire [ITER_W-1:0] iteration,
    input wire in_enable,
    output wire is_first,
    output wire is_last
);

    reg [ITER_W-1:0] input_count;

    assign is_first = (input_count == {ITER_W{1'b0}});
    assign is_last = (input_count == iteration - 1'b1);

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
endmodule

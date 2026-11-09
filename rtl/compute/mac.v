`timescale 1ns/1ps
// Interface placeholder.
module mac #(
    parameter integer BITWIDTH = 16,
    parameter integer BITWIDTH_MAC_ITERATION = 16
)(
    input  wire                                     clk,
    input  wire                                     nrst,
    input  wire                                     enable,
    input  wire        [BITWIDTH_MAC_ITERATION-1:0] iteration,
    input  wire                                     in_enable,
    input  wire signed [BITWIDTH-1:0]               in_data,
    input  wire signed [BITWIDTH-1:0]               kernel_data,
    output reg                                      out_enable,
    output reg signed  [BITWIDTH-1:0]               out_data
);

endmodule

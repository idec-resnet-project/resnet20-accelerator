module core #(
    // bitwidth
    parameter integer BITWIDTH    = 16,
    parameter integer BITWIDTH_MAC_ITERATION     = 16,
    parameter integer BITWIDTH_POOLING_ITERATION = 16,
    parameter integer BITWIDTH_GAP_ITERATION     = 16,
    // parallelism
    parameter integer PARALLEL_PC                = 1,
    parameter integer PARALLEL_PF                = 1
)(
    input  wire                                  clk,
    input  wire                                  nrst,

    // config
    input  wire                                  mac_enable,
    input  wire [BITWIDTH_MAC_ITERATION-1:0]     mac_iteration,
    input  wire                                  residual_enable,
    input  wire                                  relu_enable,
    input  wire                                  pooling_enable,
    input  wire [BITWIDTH_POOLING_ITERATION-1:0] pooling_iteration,
    input  wire                                  gap_enable,
    input  wire [BITWIDTH_GAP_ITERATION-1:0]     gap_iteration,
    
    // input
    input  wire                                  in_enable,
    input  wire [BITWIDTH-1:0]                   in_data,
    input  wire [BITWIDTH-1:0]                   kernel_data,
    input  wire [BITWIDTH-1:0]                   bias_data,
    
    // output
    output reg                                   out_enable,
    output reg  [BITWIDTH-1:0]                   out_data
);


endmodule

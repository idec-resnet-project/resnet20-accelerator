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


module conv_top
#(
    parameter integer WORD_W = 16,
    parameter integer BITWIDTH_MAC_ITERATION     = 16,
    parameter integer BITWIDTH_POOLING_ITERATION = 16,
    parameter integer BITWIDTH_GAP_ITERATION     = 16,
    // parallelism
    parameter integer PARALLEL_PC                = 1,
    parameter integer PARALLEL_PF                = 1
)
(
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
    input  wire [PARALLEL_PC*WORD_W-1:0]         in_data,
    input  wire [PARALLEL_PC*WORD_W-1:0]         kernel_data,
    input  wire [PARALLEL_PC*WORD_W-1:0]         bias_data,
    //input  wire [PARALLEL_PC*WORD_W-1:0]         residual_data,
    // resi data는 외부에서 받을지 내부에서 capture할지 결정해야함.
    // core 입장에서는 외부에서 주는게 편하긴 함

    // output
    output reg                                   out_enable,
    output reg  [WORD_W-1:0]                     out_data
);

    //=======================================================================
    // data
    //=======================================================================
    wire [PARALLEL_PC*WORD_W-1:0] mac_out;
    wire [PARALLEL_PC*WORD_W-1:0] ReLU_out;
    wire [PARALLEL_PC*WORD_W-1:0] residual_out;
    wire [WORD_W-1:0]             pooling_out;
    //=======================================================================
    // resi data capture
    // residual data는 외부에서 받을지 내부에서 capture할지 결정해야함.
    // core 입장에서는 외부에서 주는게 편하긴 함
    //=======================================================================
    reg [WORD_W-1:0] residual_data_capture[PARALLEL_PC-1:0];

    //=======================================================================
    // valid
    //=======================================================================
    // 모듈 -> 디코더 (lane 별)
    wire [PARALLEL_PC-1:0] valid_out_mac;
    wire [PARALLEL_PC-1:0] valid_out_relu;
    wire [PARALLEL_PC-1:0] valid_out_residual;
    wire                   valid_out_pooling;

    // 디코더 -> 모듈
    wire mac_valid_in;
    wire relu_valid_in;
    wire residual_valid_in;
    wire pooling_valid_in;
    wire chain_valid_out;

    //=======================================================================
    // config 레지스터
    //=======================================================================
    reg mac_enable_reg;
    reg relu_enable_reg;
    reg residual_enable_reg;
    reg pooling_enable_reg;
    reg gap_enable_reg;
    
    reg rst_reg_all;
    reg rst_reg_mac;
    reg rst_reg_relu;
    reg rst_reg_residual;
    reg rst_reg_pooling;
    
    always @(posedge clk or negedge nrst)
    begin
        if (!nrst)
        begin
            mac_enable_reg      <= 1'b0;
            relu_enable_reg     <= 1'b0;
            residual_enable_reg <= 1'b0;
            pooling_enable_reg  <= 1'b0;
            gap_enable_reg      <= 1'b0;
            rst_reg_all         <= nrst;
            rst_reg_mac         <= 1'b0;
            rst_reg_relu        <= 1'b0;
            rst_reg_residual    <= 1'b0;
            rst_reg_pooling     <= 1'b0;
            out_data            <= {WORD_W{1'b0}};
            residual_data_capture <= {PARALLEL_PC*WORD_W{1'b0}};
            out_enable          <= 1'b0;            
        end
        else
        begin
            mac_enable_reg      <= mac_enable;
            relu_enable_reg     <= relu_enable;
            residual_enable_reg <= residual_enable;
            pooling_enable_reg  <= pooling_enable;
            gap_enable_reg      <= gap_enable;
            out_data            <= pooling_out;
            out_enable          <= chain_valid_out;       
            rst_reg_all         <= nrst;
            rst_reg_mac         <= rst_reg_all;
            rst_reg_relu        <= rst_reg_all;
            rst_reg_residual    <= rst_reg_all;
            rst_reg_pooling     <= rst_reg_all;     
        end
    end

    //=======================================================================
    // valid 체인 디코더
    //=======================================================================
    conv_valid_dcd uut_valid_dcd
    (
        .mac_enable         (mac_enable_reg),
        .relu_enable        (relu_enable_reg),
        .residual_enable    (residual_enable_reg),
        .pooling_enable     (pooling_enable_reg),
        .gap_enable         (gap_enable_reg),

        .in_valid           (in_enable),

        .mac_valid_out      (valid_out_mac[0]),
        .relu_valid_out     (valid_out_relu[0]),
        .residual_valid_out (valid_out_residual[0]),
        .pooling_valid_out  (valid_out_pooling),

        .mac_valid_in       (mac_valid_in),
        .relu_valid_in      (relu_valid_in),
        .residual_valid_in  (residual_valid_in),
        .pooling_valid_in   (pooling_valid_in),

        .valid_out          (chain_valid_out)
    );

    //=======================================================================
    // lane: MAC -> ReLU -> residual
    //=======================================================================
    genvar i;
    generate
    for (i = 0; i < PARALLEL_PC; i = i + 1)
    begin : g_lane

        mac_packed
        #(
            .WORD_W   (WORD_W),
            .ACC_W    (WORD_W*2+1),
            .ITER_CNT (BITWIDTH_MAC_ITERATION)
        )
        uut_mac
        (
            .clk       (clk),
            .rst_n     (rst_reg_mac),
            .enable    (mac_enable_reg),
            .valid_in  (mac_valid_in),
            .iter      (mac_iteration),
            .fmap_in   (in_data[i*WORD_W +: WORD_W]),
            .weight_in (kernel_data[i*WORD_W +: WORD_W]),
            .bias_in   (bias_data[i*WORD_W +: WORD_W]),
            .valid_out (valid_out_mac[i]),
            .data_out  (mac_out[i*WORD_W +: WORD_W])
        );



        residual_packed
        #(
            .WORD_W (WORD_W)
        )
        uut_residual
        (
            .clk       (clk),
            .rst_n     (rst_reg_residual),
            .enable    (residual_enable_reg),
            .valid_in  (residual_valid_in),
            .data_in   (mac_out[i*WORD_W +: WORD_W]),
            .data_skip (residual_data_capture[i]),
            .valid_out (valid_out_residual[i]),
            .data_out  (residual_out[i*WORD_W +: WORD_W])
        );

        ReLU_packed
        #(
            .WORD_W (WORD_W)
        )
        uut_ReLU
        (
            .clk       (clk),
            .rst_n     (rst_reg_relu),
            .enable    (relu_enable_reg),
            .valid_in  (relu_valid_in),
            .data_in   (residual_out[i*WORD_W +: WORD_W]),
            .valid_out (valid_out_relu[i]),
            .data_out  (ReLU_out[i*WORD_W +: WORD_W])
        );
    end
    endgenerate

    //=======================================================================
    // pooling (lane 0)
    //=======================================================================
    pooling_packed
    #(
        .WORD_W       (WORD_W),
        .ACC_W        (WORD_W*2+1),
        .MAX_ITER_CNT (BITWIDTH_POOLING_ITERATION),
        .AVG_ITER_CNT (BITWIDTH_GAP_ITERATION)
    )
    uut_pooling
    (
        .clk        (clk),
        .rst_n      (rst_reg_pooling),
        .enable_avg (gap_enable_reg),
        .enable_max (pooling_enable_reg),
        .valid_in   (pooling_valid_in),
        .max_iter   (pooling_iteration),
        .avg_iter   (gap_iteration),
        .data_in    (ReLU_out[WORD_W-1:0]),
        .valid_out  (valid_out_pooling),
        .data_out   (pooling_out)
    );

endmodule

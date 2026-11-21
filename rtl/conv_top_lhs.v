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
// Revision 0.02 - residual_data 를 MAC 결과와 정렬 (residual_data_capture FIFO)
//                 이전에는 residual_data 포트가 data_skip 에 직결되어 MAC 결과가 나오는
//                 시점(마지막 입력 + 7 clk)의 포트 값(= 다음 윈도우 값 / idle 0)을 더했음
// Revision 0.01 - File Created
// Additional Comments:
//   residual_data : MAC 윈도우마다 1개. 윈도우 마지막 입력 클럭에 유효하면 됨
//                   (윈도우 입력 동안 유지해도 동일). 내부 FIFO 가 MAC 결과와 맞춰서 더함
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
    input  wire [PARALLEL_PC*WORD_W-1:0]         residual_data,
    // resi data 는 외부(컨트롤러)에서 받음 : MAC 윈도우 마지막 입력 클럭에 유효
    // MAC 결과와의 정렬은 내부 residual_data_capture FIFO 가 담당

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
    wire [PARALLEL_PC*WORD_W-1:0] residual_skip;      // MAC 결과와 정렬된 residual (packed)
    wire                          residual_overflow;  // 디버그용 (FIFO 넘침, sticky)


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
            mac_enable_reg          <= 1'b0;
            relu_enable_reg         <= 1'b0;
            residual_enable_reg     <= 1'b0;
            pooling_enable_reg      <= 1'b0;
            gap_enable_reg          <= 1'b0;
            rst_reg_all             <= nrst;
            rst_reg_mac             <= 1'b0;
            rst_reg_relu            <= 1'b0;
            rst_reg_residual        <= 1'b0;
            rst_reg_pooling         <= 1'b0;
            out_data                <= {WORD_W{1'b0}};
            out_enable              <= 1'b0;
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
    // 꺼진 블록의 valid 를 1클럭 지연하는 레지스터가 dcd 안에 있어 clk / reset 연결
    conv_valid_dcd uut_valid_dcd
    (
        .clk                (clk),
        .nrst               (rst_reg_all),

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
    // residual 정렬 FIFO
    //   push : MAC 윈도우 마지막 입력 클럭의 residual_data
    //   pop  : MAC valid_out 클럭 -> 같은 클럭에 residual 의 data_skip 으로 사용
    //   reset 은 MAC 과 같은 타이밍 (rst_reg_all 에서 1단) 이라 윈도우 카운터가 MAC 과 같이 시작
    //=======================================================================
    residual_data_capture
    #(
        .WORD_W(WORD_W),
        .BITWIDTH_MAC_ITERATION(BITWIDTH_MAC_ITERATION),
        .BITWIDTH_POOLING_ITERATION(BITWIDTH_POOLING_ITERATION),
        .BITWIDTH_GAP_ITERATION(BITWIDTH_GAP_ITERATION),
        .PARALLEL_PC(PARALLEL_PC),
        .PARALLEL_PF(PARALLEL_PF)
    )
    uut_residual_data_capture
    (
        .clk                (clk),
        .nrst               (rst_reg_residual),
        .mac_enable         (mac_enable_reg),
        .residual_enable    (residual_enable_reg),
        .mac_valid_in       (mac_valid_in),
        .mac_iteration      (mac_iteration),
        .mac_valid_out      (valid_out_mac[0]),
        .residual_data      (residual_data),
        .residual_data_out  (residual_skip),
        .overflow           (residual_overflow)
    );

    //=======================================================================
    // lane: MAC -> residual -> ReLU
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
            .data_skip (residual_skip[i*WORD_W +: WORD_W]),
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
`timescale 1ns / 1ps
//==============================================================================
// conv_top_wrapper.v  -  test / timing-sim wrapper for conv_top
//------------------------------------------------------------------------------
//  * 포트는 conv_top 과 동일 -> TB 에서 모듈 이름만 바꿔서 사용
//  * 모든 입력 : IOB FF 로 1단 등록  -> 모든 입력 비트가 같은 클럭 엣지에 캡처됨
//                (핀 -> 내부 로직 경로가 비트마다 달라 사이클이 어긋나는 문제 제거)
//  * 모든 출력 : IOB FF 로 1단 등록  -> clk-to-pad 지연이 비트마다 균일
//  * nrst     : async assert / sync deassert 2-FF 동기화
//  * 지연     : conv_top 대비 +2 클럭 (입력 1 + 출력 1)
//==============================================================================
module conv_top_wrapper
#(
    parameter integer WORD_W                     = 16,
    parameter integer BITWIDTH_MAC_ITERATION     = 16,
    parameter integer BITWIDTH_POOLING_ITERATION = 16,
    parameter integer BITWIDTH_GAP_ITERATION     = 16,
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

    // output
    output wire                                  out_enable,
    output wire [WORD_W-1:0]                     out_data
);

    //=======================================================================
    // reset synchronizer (async assert, sync deassert)
    //=======================================================================
    (* ASYNC_REG = "TRUE" *) reg [1:0] nrst_sync;

    always @(posedge clk or negedge nrst)
    begin
        if (!nrst)
            nrst_sync <= 2'b00;
        else
            nrst_sync <= {nrst_sync[0], 1'b1};
    end

    wire nrst_i = nrst_sync[1];

    //=======================================================================
    // input registers (IOB)
    //=======================================================================
    (* IOB = "TRUE" *) reg                                  mac_enable_q;
    (* IOB = "TRUE" *) reg [BITWIDTH_MAC_ITERATION-1:0]     mac_iteration_q;
    (* IOB = "TRUE" *) reg                                  residual_enable_q;
    (* IOB = "TRUE" *) reg                                  relu_enable_q;
    (* IOB = "TRUE" *) reg                                  pooling_enable_q;
    (* IOB = "TRUE" *) reg [BITWIDTH_POOLING_ITERATION-1:0] pooling_iteration_q;
    (* IOB = "TRUE" *) reg                                  gap_enable_q;
    (* IOB = "TRUE" *) reg [BITWIDTH_GAP_ITERATION-1:0]     gap_iteration_q;
    (* IOB = "TRUE" *) reg                                  in_enable_q;
    (* IOB = "TRUE" *) reg [PARALLEL_PC*WORD_W-1:0]         in_data_q;
    (* IOB = "TRUE" *) reg [PARALLEL_PC*WORD_W-1:0]         kernel_data_q;
    (* IOB = "TRUE" *) reg [PARALLEL_PC*WORD_W-1:0]         bias_data_q;

    always @(posedge clk or negedge nrst_i)
    begin
        if (!nrst_i)
        begin
            mac_enable_q        <= 1'b0;
            mac_iteration_q     <= {BITWIDTH_MAC_ITERATION{1'b0}};
            residual_enable_q   <= 1'b0;
            relu_enable_q       <= 1'b0;
            pooling_enable_q    <= 1'b0;
            pooling_iteration_q <= {BITWIDTH_POOLING_ITERATION{1'b0}};
            gap_enable_q        <= 1'b0;
            gap_iteration_q     <= {BITWIDTH_GAP_ITERATION{1'b0}};
            in_enable_q         <= 1'b0;
            in_data_q           <= {(PARALLEL_PC*WORD_W){1'b0}};
            kernel_data_q       <= {(PARALLEL_PC*WORD_W){1'b0}};
            bias_data_q         <= {(PARALLEL_PC*WORD_W){1'b0}};
        end
        else
        begin
            mac_enable_q        <= mac_enable;
            mac_iteration_q     <= mac_iteration;
            residual_enable_q   <= residual_enable;
            relu_enable_q       <= relu_enable;
            pooling_enable_q    <= pooling_enable;
            pooling_iteration_q <= pooling_iteration;
            gap_enable_q        <= gap_enable;
            gap_iteration_q     <= gap_iteration;
            in_enable_q         <= in_enable;
            in_data_q           <= in_data;
            kernel_data_q       <= kernel_data;
            bias_data_q         <= bias_data;
        end
    end

    //=======================================================================
    // core
    //=======================================================================
    wire                 core_out_enable;
    wire [WORD_W-1:0]    core_out_data;

    conv_top
    #(
        .WORD_W                     (WORD_W),
        .BITWIDTH_MAC_ITERATION     (BITWIDTH_MAC_ITERATION),
        .BITWIDTH_POOLING_ITERATION (BITWIDTH_POOLING_ITERATION),
        .BITWIDTH_GAP_ITERATION     (BITWIDTH_GAP_ITERATION),
        .PARALLEL_PC                (PARALLEL_PC),
        .PARALLEL_PF                (PARALLEL_PF)
    )
    u_conv_top
    (
        .clk               (clk),
        .nrst              (nrst_i),
        .mac_enable        (mac_enable_q),
        .mac_iteration     (mac_iteration_q),
        .residual_enable   (residual_enable_q),
        .relu_enable       (relu_enable_q),
        .pooling_enable    (pooling_enable_q),
        .pooling_iteration (pooling_iteration_q),
        .gap_enable        (gap_enable_q),
        .gap_iteration     (gap_iteration_q),
        .in_enable         (in_enable_q),
        .in_data           (in_data_q),
        .kernel_data       (kernel_data_q),
        .bias_data         (bias_data_q),
        .out_enable        (core_out_enable),
        .out_data          (core_out_data)
    );

    //=======================================================================
    // output registers (IOB)
    //=======================================================================
    (* IOB = "TRUE" *) reg              out_enable_q;
    (* IOB = "TRUE" *) reg [WORD_W-1:0] out_data_q;

    always @(posedge clk or negedge nrst_i)
    begin
        if (!nrst_i)
        begin
            out_enable_q <= 1'b0;
            out_data_q   <= {WORD_W{1'b0}};
        end
        else
        begin
            out_enable_q <= core_out_enable;
            out_data_q   <= core_out_data;
        end
    end

    assign out_enable = out_enable_q;
    assign out_data   = out_data_q;

endmodule
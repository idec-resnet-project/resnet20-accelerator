`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: residual_data_capture
// Description:
//   residual(skip) 데이터를 MAC 결과와 정렬하는 FIFO
//   * capture : MAC 윈도우의 "마지막 입력" 클럭에 residual_data (packed, PARALLEL_PC lane 전체) 를 잡음
//               -> 컨트롤러가 윈도우 입력 동안 유지하든 (RES_DRIVE 0/1),
//                  마지막 입력 클럭에만 주든 (RES_DRIVE 2) 모두 같은 값을 잡음
//   * push    : capture 다음 클럭에 FIFO 에 씀 (타이밍 분리용 1단)
//   * pop     : MAC valid_out (= residual 의 valid_in) 클럭에 꺼냄
//               -> residual_data_out 은 그 클럭에 MAC 결과와 같은 윈도우의 residual
//               (MAC 결과는 마지막 입력 후 최소 6 clk 뒤라 push 1 clk 지연은 영향 없음)
//   * 윈도우 마지막 입력 판단 (mac_v3 와 같은 규칙 : 첫 입력에서 iter 래치, iter 개, iter = 0 이면 1개)
//       첫 입력 : iter <= 1 이면 그 입력이 마지막, 아니면 남은 입력 수 (iter - 1) 를 tap_rem 에 저장
//       이후    : tap_rem == 1 이면 마지막, 아니면 tap_rem - 1
//   * DEPTH : 동시에 진행 중인 윈도우 수 이상 (현재 최악 iter<=1, MAC_GAP 3 -> 2개) -> 4
//
// Revision:
// Revision 0.03 - 타이밍 개선 (tap_cnt -> fifo 경로 WNS 0.402 ns @100MHz)
//                 . 업카운터 + (iter-1) 비교  -> 다운카운터 + (== 1) 비교
//                 . 마지막 입력 판정과 FIFO write 사이에 레지스터 1단 (push_q / data_q)
// Revision 0.02 - MAC 출력 정렬용 FIFO 로 재작성 (push: 마지막 입력, pop: MAC valid_out)
// Revision 0.01 - File Created
//////////////////////////////////////////////////////////////////////////////////

module residual_data_capture
#(
    parameter integer WORD_W                     = 16,
    parameter integer BITWIDTH_MAC_ITERATION     = 16,
    parameter integer BITWIDTH_POOLING_ITERATION = 16,
    parameter integer BITWIDTH_GAP_ITERATION     = 16,
    // parallelism
    parameter integer PARALLEL_PC                = 1,
    parameter integer PARALLEL_PF                = 1,
    // FIFO
    parameter integer DEPTH                      = 4,     // 2^n
    parameter integer AW                         = 2      // log2(DEPTH)
)
(
    input  wire                                  clk,
    input  wire                                  nrst,

    input  wire                                  mac_enable,       // 레지스터된 enable
    input  wire                                  residual_enable,  // 레지스터된 enable
    input  wire                                  mac_valid_in,     // MAC 입력 valid (in_enable)
    input  wire [BITWIDTH_MAC_ITERATION-1:0]     mac_iteration,    // 윈도우 첫 입력에서 래치
    input  wire                                  mac_valid_out,    // MAC 결과 valid (pop)

    input  wire [PARALLEL_PC*WORD_W-1:0]         residual_data,
    output wire [PARALLEL_PC*WORD_W-1:0]         residual_data_out,
    output wire                                  overflow          // push 시 FIFO full (디버그용, sticky)
);

    localparam integer IW = BITWIDTH_MAC_ITERATION;

    //=======================================================================
    // 윈도우 마지막 입력 판단 (다운카운터)
    //   tap_busy = 0 : 다음 입력이 윈도우 첫 입력
    //   tap_rem      : 지금 입력 이후 남은 입력 수 (tap_busy = 1 일 때 >= 1)
    //=======================================================================
    reg           tap_busy;
    reg  [IW-1:0] tap_rem;

    wire          first_is_last = ~|mac_iteration[IW-1:1];          // iter <= 1 (iter = 0 이면 입력 1개)
    wire          rem_is_one    = (tap_rem == {{(IW-1){1'b0}}, 1'b1});
    wire          tap_last      = tap_busy ? rem_is_one : first_is_last;

    always @(posedge clk or negedge nrst)
    begin
        if (!nrst)
        begin
            tap_busy <= 1'b0;
            tap_rem  <= {IW{1'b0}};
        end
        else if (mac_enable && mac_valid_in)
        begin
            if (!tap_busy)
            begin
                tap_busy <= !first_is_last;
                tap_rem  <= mac_iteration - 1'b1;
            end
            else
            begin
                tap_busy <= !rem_is_one;
                tap_rem  <= tap_rem - 1'b1;
            end
        end
    end

    //=======================================================================
    // capture -> push (1단)
    //=======================================================================
    wire cap_en = mac_enable && residual_enable;
    wire cap    = cap_en && mac_valid_in && tap_last;

    reg                           push_q;
    reg  [PARALLEL_PC*WORD_W-1:0] data_q;

    always @(posedge clk or negedge nrst)
    begin
        if (!nrst)
            push_q <= 1'b0;
        else
            push_q <= cap;
    end

    always @(posedge clk)
    begin
        if (cap)
            data_q <= residual_data;
    end

    //=======================================================================
    // FIFO (packed 그대로 저장)
    //=======================================================================
    wire pop = cap_en && mac_valid_out;

    reg  [PARALLEL_PC*WORD_W-1:0] fifo [0:DEPTH-1];
    reg  [AW:0]                   wp;
    reg  [AW:0]                   rp;
    reg                           ovf;

    wire empty = (wp == rp);
    wire full  = (wp[AW] != rp[AW]) && (wp[AW-1:0] == rp[AW-1:0]);
    wire wr    = push_q && (!full || pop);

    always @(posedge clk or negedge nrst)
    begin
        if (!nrst)
        begin
            wp  <= {(AW+1){1'b0}};
            rp  <= {(AW+1){1'b0}};
            ovf <= 1'b0;
        end
        else
        begin
            if (wr)                     wp  <= wp + 1'b1;
            if (pop && !empty)          rp  <= rp + 1'b1;
            if (push_q && full && !pop) ovf <= 1'b1;
        end
    end

    always @(posedge clk)
    begin
        if (wr)
            fifo[wp[AW-1:0]] <= data_q;
    end

    // pop 클럭에 MAC 결과와 같은 윈도우의 residual (비어 있으면 0)
    assign residual_data_out = empty ? {(PARALLEL_PC*WORD_W){1'b0}} : fifo[rp[AW-1:0]];
    assign overflow          = ovf;

endmodule
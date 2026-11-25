`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: mac_v3
// Description:
//   y = sum(fmap x weight) + (bias << FRAC_BITS)   (누산기 Q(2F) 스케일, 반올림/포화는 post_mac)
//   * 유효 입력 (enable && valid_in) 만 센다 -> 윈도우 중간에 valid_in = 0 (bubble) 이 끼어도 됨
//   * 윈도우를 연달아 받을 수 있음 (윈도우 사이 idle 0 클럭 가능)
//   * iter 는 윈도우 첫 입력에서만 래치 (iter = 0 : 입력 1개를 받고 bias 만 출력)
//   * bias_in 은 윈도우 첫 입력 클럭에서만 샘플
//
//   파이프라인 (유효 입력 1개당)
//     stage0 (조합) : 다운카운터로 윈도우 첫 / 마지막 입력 판정
//     stage1        : 입력 레지스터 + 표시 (valid / first / last / zero), bias 래치
//     stage2        : 곱
//     stage3        : 누산  첫 입력이면 bias 에서 새로 시작 -> 연달아 와도 윈도우끼리 섞이지 않음
//                    마지막 입력이면 data_out / valid_out (1클럭 펄스)
//   latency : 마지막 입력 캡처 edge -> valid_out 2 clk
//
// Revision:
// Revision 0.04 - 파이프라인 구조로 재작성 (유효 입력만 카운트, 연속 윈도우, bias 첫 입력만)
//                 FRAC_BITS parameter (기본 8 = Q7.8, tb_core 는 10 = Q5.10)
//////////////////////////////////////////////////////////////////////////////////

module mac_v3
#(
    parameter integer WORD_W    = 16,
    parameter integer ACC_W     = WORD_W*2+1,
    parameter integer ITER_CNT  = 5,
    parameter integer Q_SCALE = 8
)
(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         enable,
    input  wire                         valid_in,
    input  wire        [ITER_CNT-1:0]   iter,
    input  wire signed [WORD_W-1:0]     fmap_in,
    input  wire signed [WORD_W-1:0]     weight_in,
    input  wire signed [WORD_W-1:0]     bias_in,

    output reg                          proc,       // 윈도우 진행 중 / 파이프라인에 입력이 남아 있음
    output reg                          valid_out,
    output reg  signed [ACC_W:0]        data_out
);

    wire take = enable && valid_in;

    //=======================================================================
    // stage0 : 윈도우 첫 / 마지막 입력 판정 (다운카운터)
    //   busy = 0 : 지금 입력이 윈도우 첫 입력
    //   rem      : 지금 입력 이후 남은 입력 수 (busy = 1 일 때 >= 1)
    //=======================================================================
    reg                 busy;
    reg [ITER_CNT-1:0]  rem;

    wire first      = !busy;
    wire first_last = ~|iter[ITER_CNT-1:1];                          // iter <= 1
    wire rem_is_one = (rem == {{(ITER_CNT-1){1'b0}}, 1'b1});
    wire last       = busy ? rem_is_one : first_last;

    always @(posedge clk)
    begin
        if (!rst_n)
        begin
            busy <= 1'b0;
            rem  <= {ITER_CNT{1'b0}};
        end
        else if (take)
        begin
            if (first)
            begin
                busy <= !first_last;
                rem  <= iter - 1'b1;
            end
            else
            begin
                busy <= !rem_is_one;
                rem  <= rem - 1'b1;
            end
        end
    end

    //=======================================================================
    // stage1 : 입력 레지스터
    //=======================================================================
    reg                     v1, f1, l1, z1;
    reg signed [WORD_W-1:0] fmap;
    reg signed [WORD_W-1:0] weight;
    reg signed [WORD_W-1:0] bias1;

    always @(posedge clk)
    begin
        if (!rst_n)
        begin
            v1     <= 1'b0;
            f1     <= 1'b0;
            l1     <= 1'b0;
            z1     <= 1'b0;
            fmap   <= {WORD_W{1'b0}};
            weight <= {WORD_W{1'b0}};
            bias1  <= {WORD_W{1'b0}};
        end
        else
        begin
            v1 <= take;
            f1 <= first;
            l1 <= last;
            z1 <= first && (iter == {ITER_CNT{1'b0}});               // iter = 0 : bias 만
            if (take)
            begin
                fmap   <= fmap_in;
                weight <= weight_in;
                if (first)
                    bias1 <= bias_in;
            end
        end
    end

    //=======================================================================
    // stage2 : 곱
    //=======================================================================
    reg                       v2, f2, l2, z2;
    reg signed [WORD_W*2-1:0] multi;
    reg signed [WORD_W-1:0]   bias2;

    always @(posedge clk)
    begin
        if (!rst_n)
        begin
            v2    <= 1'b0;
            f2    <= 1'b0;
            l2    <= 1'b0;
            z2    <= 1'b0;
            multi <= {(WORD_W*2){1'b0}};
            bias2 <= {WORD_W{1'b0}};
        end
        else
        begin
            v2    <= v1;
            f2    <= f1;
            l2    <= l1;
            z2    <= z1;
            bias2 <= bias1;
            if (v1)
                multi <= fmap * weight;
        end
    end

    //=======================================================================
    // stage3 : 누산
    //=======================================================================
    reg  signed [ACC_W:0] acc;
    wire signed [ACC_W:0] bias_ext = {{(ACC_W+1-WORD_W-Q_SCALE){bias2[WORD_W-1]}}, bias2, {Q_SCALE{1'b0}}};
    wire signed [ACC_W:0] base     = f2 ? bias_ext : acc;
    wire signed [ACC_W:0] sum      = z2 ? base : base + multi;

    always @(posedge clk)
    begin
        if (!rst_n)
        begin
            acc       <= {(ACC_W+1){1'b0}};
            valid_out <= 1'b0;
            data_out  <= {(ACC_W+1){1'b0}};
        end
        else
        begin
            valid_out <= v2 && l2;
            if (v2)
            begin
                acc <= sum;
                if (l2)
                    data_out <= sum;
            end
        end
    end

    always @(*)
        proc = busy | v1 | v2;

endmodule
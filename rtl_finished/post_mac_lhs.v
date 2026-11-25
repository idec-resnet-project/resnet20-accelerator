`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: post_mac
// Description:
//   누산기 Q(2F) -> 16b Q(15-F).F : +-0.5 LSB 반올림 (0 에서 먼 쪽) 후 int16 포화
//   * 4단 파이프라인, 매 클럭 입력 가능 (연속 valid_in 도 하나도 빠뜨리지 않음)
//     flag 1단 = data 1단, 각 data 레지스터는 같은 단의 flag 로만 갱신
//       edge0 : valid_in  -> proc      | data_ext, bias     (입력 저장 + 반올림 상수 선택)
//       edge1 : proc      -> proc_done | shifted            (가산 + >>> FRAC_BITS)
//       edge2 : proc_done -> done      | sat_p, sat_n, low  (포화 비교)
//       edge3 : done      -> valid_out | data_out           (선택 / 출력)
//
// Revision:
// Revision 0.02 - 4단 파이프라인 (연속 입력 지원, 이전 버전은 연속 2개 중 1개 누락)
//                 FRAC_BITS parameter (기본 8 = Q7.8)
//////////////////////////////////////////////////////////////////////////////////

module post_mac #(
    parameter integer WORD_W    = 16,
    parameter integer ACC_W     = WORD_W*2+1,
    parameter integer Q_SCALE = 8
)(
    input   wire                     clk,
    input   wire                     rst_n,
    input   wire                     valid_in,
    input   wire signed [ACC_W:0]    data_in,
    output  reg                      valid_out,
    output  reg  signed [WORD_W-1:0] data_out
);

    //localparam integer Q_SCALE = FRAC_BITS;

    localparam signed [WORD_W-1:0] INT_MAX = {1'b0, {(WORD_W-1){1'b1}}};
    localparam signed [WORD_W-1:0] INT_MIN = {1'b1, {(WORD_W-1){1'b0}}};

    localparam signed [Q_SCALE:0] M_Q = {1'b0, 1'b0, {(Q_SCALE-1){1'b1}}};   // 0.5 LSB - 1 (음수)
    localparam signed [Q_SCALE:0] P_Q = {1'b0, 1'b1, {(Q_SCALE-1){1'b0}}};   // 0.5 LSB     (양수)

    // stage1
    reg signed [ACC_W+1:0]          data_ext;
    reg signed [Q_SCALE:0]          bias;
    reg                             proc;
    // stage2
    reg signed [ACC_W+1-Q_SCALE:0]  shifted;
    reg                             proc_done;
    // stage3
    reg                             sat_p;
    reg                             sat_n;
    reg        [WORD_W-1:0]         low;
    reg                             done;

    always @(posedge clk or negedge rst_n)
    begin
        if (!rst_n)
        begin
            data_ext  <= 0;
            bias      <= 0;
            proc      <= 1'b0;
            shifted   <= 0;
            proc_done <= 1'b0;
            sat_p     <= 1'b0;
            sat_n     <= 1'b0;
            low       <= {WORD_W{1'b0}};
            done      <= 1'b0;
            data_out  <= {WORD_W{1'b0}};
            valid_out <= 1'b0;
        end
        else
        begin
            // stage1 : 입력 저장 + 반올림 상수 선택
            proc <= valid_in;
            if (valid_in)
            begin
                data_ext <= {data_in[ACC_W], data_in};
                bias     <= data_in[ACC_W] ? M_Q : P_Q;
            end

            // stage2 : 반올림 가산 + scale down
            proc_done <= proc;
            if (proc)
                shifted <= (data_ext + bias) >>> Q_SCALE;

            // stage3 : 포화 비교
            done <= proc_done;
            if (proc_done)
            begin
                sat_p <= (shifted > INT_MAX);
                sat_n <= (shifted < INT_MIN);
                low   <= shifted[WORD_W-1:0];
            end

            // stage4 : 출력 (valid 와 같은 엣지)
            valid_out <= done;
            if (done)
            begin
                if (sat_p)
                    data_out <= INT_MAX;
                else if (sat_n)
                    data_out <= INT_MIN;
                else
                    data_out <= low;
            end
        end
    end

endmodule
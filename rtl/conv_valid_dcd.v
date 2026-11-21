//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date: 2026/11/10 14:07:48
// Design Name:
// Module Name: conv_valid_dcd
// Project Name:
// Target Devices:
// Tool Versions:
// Description:
//   conv_top valid 체인 디코더
//   처리 순서 : MAC -> RES -> ReLU -> POOL(MAXPOOL / GAP)
//
// Dependencies:
//
// Revision:
// Revision 0.02 - valid_in 연결 순서를 MAC -> RES -> ReLU -> POOL 로 수정
//               - 꺼진 블록의 valid 를 레지스터 1단 지연 (data 와 정렬)
// Revision 0.01 - File Created
// Additional Comments:
//   꺼진 블록 (enable = 0) 은 packed 모듈 안에서 data 만 출력 레지스터 1단을 통과한다
//   (data_out <= mux(data_in)). valid 를 조합으로 바로 넘기면 data 가 valid 보다
//   꺼진 블록 수만큼 늦어지므로, 꺼진 블록의 valid 도 byp_* 레지스터로 1클럭 늦춘다.
//////////////////////////////////////////////////////////////////////////////////

module conv_valid_dcd
(
    input  wire clk,
    input  wire nrst,

    // 레지스터된 enable
    input  wire mac_enable,
    input  wire relu_enable,
    input  wire residual_enable,
    input  wire pooling_enable,
    input  wire gap_enable,

    // 체인 입력 valid
    input  wire in_valid,

    // 각 모듈 valid_out
    input  wire mac_valid_out,
    input  wire relu_valid_out,
    input  wire residual_valid_out,
    input  wire pooling_valid_out,

    // 각 모듈 valid_in
    output wire mac_valid_in,
    output wire relu_valid_in,
    output wire residual_valid_in,
    output wire pooling_valid_in,

    // 체인 최종 valid
    output wire valid_out
);

    //=======================================================================
    // 꺼진 블록의 valid : 앞 단 valid 를 1클럭 지연 (data 출력 레지스터 1단과 정렬)
    //=======================================================================
    reg byp_mac;
    reg byp_res;
    reg byp_relu;
    reg byp_pool;

    wire v_mac  = mac_enable                     ? mac_valid_out      : byp_mac;
    wire v_res  = residual_enable                ? residual_valid_out : byp_res;
    wire v_relu = relu_enable                    ? relu_valid_out     : byp_relu;
    wire v_pool = (pooling_enable || gap_enable) ? pooling_valid_out  : byp_pool;

    always @(posedge clk or negedge nrst)
    begin
        if (!nrst)
        begin
            byp_mac  <= 1'b0;
            byp_res  <= 1'b0;
            byp_relu <= 1'b0;
            byp_pool <= 1'b0;
        end
        else
        begin
            byp_mac  <= in_valid;
            byp_res  <= v_mac;
            byp_relu <= v_res;
            byp_pool <= v_relu;
        end
    end

    //=======================================================================
    // 각 모듈 valid_in = 바로 앞 단의 valid  (MAC -> RES -> ReLU -> POOL)
    //=======================================================================
    assign mac_valid_in      = in_valid;
    assign residual_valid_in = v_mac;
    assign relu_valid_in     = v_res;
    assign pooling_valid_in  = v_relu;
    assign valid_out         = v_pool;

endmodule
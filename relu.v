
`timescale 1ns / 1ps

// ReLU: 음수는 0, 양수와 0은 그대로 출력
module ReLU #(
    parameter integer DATA_WIDTH = 16  // 데이터 비트폭 (기본 16비트)
)(
    input  wire                         clk,       // 클럭
    input  wire                         rst_n,     // 리셋 (0이면 초기화)
    input  wire                         enable,    // 입력 처리 활성화
    input  wire signed [DATA_WIDTH-1:0] data_in,   // 부호 있는 입력 데이터

    output reg                          valid_out, // 출력 유효 신호
    output reg signed [DATA_WIDTH-1:0]  data_out   // ReLU 연산 결과
);

// 클럭 상승 시 동작, 리셋은 비동기 처리
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // 리셋 시 출력 초기화
        valid_out <= 1'b0;
        data_out  <= {DATA_WIDTH{1'b0}};
    end
    else begin
        // enable이 1이면 유효한 출력 생성
        valid_out <= enable;

        if (enable)
            // 최상위 부호 비트가 1(음수)이면 0, 아니면 입력 그대로
            data_out <= data_in[DATA_WIDTH-1]
                      ? {DATA_WIDTH{1'b0}}
                      : data_in;

        // enable=0이면 data_out은 이전 값 유지
    end
end

endmodule

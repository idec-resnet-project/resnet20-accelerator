
module mac #(
    parameter DATA_W = 8,
    parameter ACC_W  = 32
)(
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     en,
    input  wire                     clear,
    input  wire signed [DATA_W-1:0] data_a,
    input  wire signed [DATA_W-1:0] data_b,

    output reg signed [ACC_W-1:0]   acc_out
);

// MAC 연산 결과를 누적하는 레지스터
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        acc_out <= 0;

    // 새로운 연산을 시작할 때 누적값 초기화
    else if (clear)
        acc_out <= 0;

    // enable이 1이면 곱셈 결과를 기존 값에 누적
    else if (en)
        acc_out <= acc_out + (data_a * data_b);
end

endmodule

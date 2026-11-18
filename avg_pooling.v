
module avg_pooling #(
    parameter integer WORD_W = 16
)(
    input wire clk,
    input wire rst_n,
    input wire enable,
    input wire valid_in,

    input wire signed [WORD_W-1:0] data_0,
    input wire signed [WORD_W-1:0] data_1,
    input wire signed [WORD_W-1:0] data_2,
    input wire signed [WORD_W-1:0] data_3,

    output reg signed [WORD_W-1:0] data_out,
    output reg valid_out
);

// 덧셈할 때 값이 넘치지 않도록 2비트 추가
wire signed [WORD_W+1:0] sum_result;

assign sum_result =
    $signed({{2{data_0[WORD_W-1]}}, data_0}) +
    $signed({{2{data_1[WORD_W-1]}}, data_1}) +
    $signed({{2{data_2[WORD_W-1]}}, data_2}) +
    $signed({{2{data_3[WORD_W-1]}}, data_3});

// 4로 나누기 위해 오른쪽으로 2비트 이동
wire signed [WORD_W-1:0] avg_result;

assign avg_result = sum_result >>> 2;

// 결과 저장
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        data_out  <= 0;
        valid_out <= 0;
    end
    else begin
        valid_out <= enable && valid_in;

        if (enable && valid_in)
            data_out <= avg_result;
    end
end

endmodule


module max_pooling #(
    parameter integer WORD_W = 16
)(
    input  wire clk,
    input  wire rst_n,
    input  wire enable,
    input  wire valid_in,

    input  wire signed [WORD_W-1:0] data_0,
    input  wire signed [WORD_W-1:0] data_1,
    input  wire signed [WORD_W-1:0] data_2,
    input  wire signed [WORD_W-1:0] data_3,

    output reg signed [WORD_W-1:0] data_out,
    output reg valid_out
);

// 4개 데이터를 2개씩 나눠 비교
wire signed [WORD_W-1:0] max_01;
wire signed [WORD_W-1:0] max_23;

assign max_01 = (data_0 >= data_1) ? data_0 : data_1;
assign max_23 = (data_2 >= data_3) ? data_2 : data_3;

// 위에서 구한 두 값 중 더 큰 값 선택
wire signed [WORD_W-1:0] max_result;

assign max_result = (max_01 >= max_23) ? max_01 : max_23;

// 클럭에 맞춰 결과 저장
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        data_out <= 0;
        valid_out <= 0;
    end
    else begin
        valid_out <= enable && valid_in;

        if (enable && valid_in)
            data_out <= max_result;
    end
end

endmodule

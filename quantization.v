
module quantization #(
    parameter integer IN_W = 32,
    parameter integer WORD_W = 16,
    parameter integer SHIFT = 2
)(
    input wire clk,
    input wire rst_n,
    input wire enable,
    input wire valid_in,

    input wire signed [IN_W-1:0] data_in,

    output reg signed [WORD_W-1:0] data_out,
    output reg valid_out
);

// 비트 이동으로 값의 크기 조정
wire signed [IN_W-1:0] scaled_data;

assign scaled_data = data_in >>> SHIFT;

// 16비트 출력의 최대, 최소 범위
localparam signed [WORD_W-1:0] MAX_VAL =
    {1'b0, {(WORD_W-1){1'b1}}};

localparam signed [WORD_W-1:0] MIN_VAL =
    {1'b1, {(WORD_W-1){1'b0}}};

// 비교할 때 비트폭을 맞춰줌
wire signed [IN_W-1:0] max_ext;
wire signed [IN_W-1:0] min_ext;

assign max_ext = MAX_VAL;
assign min_ext = MIN_VAL;

// 범위를 넘어가면 최대값이나 최소값으로 처리
wire signed [WORD_W-1:0] quant_result;

assign quant_result =
    (scaled_data > max_ext) ? MAX_VAL :
    (scaled_data < min_ext) ? MIN_VAL :
    scaled_data[WORD_W-1:0];

// 클럭에 맞춰 결과 저장
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        data_out <= 0;
        valid_out <= 0;
    end
    else begin
        valid_out <= enable && valid_in;

        if (enable && valid_in)
            data_out <= quant_result;
    end
end

endmodule

레지스터 끊어주기 파이프라인

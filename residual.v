
module residual_add #(
    parameter integer DATA_W = 16
)(
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     enable,
    input  wire                     valid_in,

    input  wire signed [DATA_W-1:0] data_in,
    input  wire signed [DATA_W-1:0] skip_in,

    output reg signed [DATA_W-1:0]  data_out,
    output reg                      valid_out
);

// 두 입력을 더할 때 오버플로가 생길 수 있어서 1비트 추가
wire signed [DATA_W:0] sum_ext;

assign sum_ext =
    $signed({data_in[DATA_W-1], data_in}) +
    $signed({skip_in[DATA_W-1], skip_in});

// signed 데이터의 최대, 최소 범위 설정
localparam signed [DATA_W-1:0] MAX_VAL =
    {1'b0, {(DATA_W-1){1'b1}}};

localparam signed [DATA_W-1:0] MIN_VAL =
    {1'b1, {(DATA_W-1){1'b0}}};

// 범위를 넘어가면 최대값이나 최소값으로 처리
wire signed [DATA_W-1:0] sat_result;

assign sat_result =
    (sum_ext[DATA_W] != sum_ext[DATA_W-1]) ?
        (sum_ext[DATA_W] ? MIN_VAL : MAX_VAL) :
        sum_ext[DATA_W-1:0];

// 클럭에 맞춰 결과 저장
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        data_out  <= 0;
        valid_out <= 0;
    end
    else begin
        // 입력이 유효한지 확인
        valid_out <= enable && valid_in;

        // enable과 valid가 1일 때만 결과 저장
        if (enable && valid_in)
            data_out <= sat_result;
    end
end

endmodule

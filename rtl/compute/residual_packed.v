`timescale 1ns/1ps

module residual_packed #(
    parameter integer BITWIDTH = 16
)(
    input  wire                       clk,
    input  wire                       nrst,
    input  wire                       enable,
    input  wire                       in_enable,
    input  wire signed [BITWIDTH-1:0]  in_data,
    input  wire signed [BITWIDTH-1:0]  skip_data,

    output reg                        out_enable,
    output reg signed [BITWIDTH-1:0]   out_data
);

    wire signed [BITWIDTH-1:0] res_data;
    wire                      res_valid;
    wire signed [BITWIDTH-1:0] mux_data;

    reg signed [BITWIDTH-1:0] bypass_reg;
    reg                      enable_reg;

    // 1. Residual: 덧셈 결과 저장 → 포화
    residual #(
        .BITWIDTH(BITWIDTH)
    ) u_residual (
        .clk        (clk),
        .nrst       (nrst),
        .in_enable  (in_enable),
        .in_data    (in_data),
        .skip_data  (skip_data),
        .out_enable (res_valid),
        .out_data   (res_data)
    );

    // 2. 바이패스 데이터와 선택 신호도 한 단계 저장
    always @(posedge clk or negedge nrst) begin
        if (!nrst) begin
            bypass_reg <= 0;
            enable_reg <= 0;
        end
        else if (in_enable) begin
            bypass_reg <= in_data;
            enable_reg <= enable;
        end
    end

    // 3. 같은 입력에 해당하는 두 경로 중 하나 선택
    mux #(
        .WORD_W(BITWIDTH)
    ) u_mux (
        .data_x   (bypass_reg), // enable_reg=0: bypass
        .data_y   (res_data),   // enable_reg=1: residual
        .enable   (enable_reg),
        .data_out (mux_data)
    );

    // 4. 선택 결과와 valid를 출력 레지스터에 저장
    always @(posedge clk or negedge nrst) begin
        if (!nrst) begin
            out_data   <= 0;
            out_enable <= 0;
        end
        else begin
            out_enable <= res_valid;

            if (res_valid) begin
                out_data <= mux_data;
            end
        end
    end

endmodule
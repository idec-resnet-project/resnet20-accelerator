
`timescale 1ns/1ps

module mac #(
    parameter integer BITWIDTH               = 16,
    parameter integer BITWIDTH_MAC_ITERATION = 16,
    parameter integer FRAC_W                 = 8,
    parameter integer ACC_W                  = 3*BITWIDTH
)(
    input  wire                                      clk,
    input  wire                                      nrst,
    input  wire                                      enable,
    input  wire [BITWIDTH_MAC_ITERATION-1:0]         iteration,
    input  wire                                      in_enable,
    input  wire signed [BITWIDTH-1:0]                in_data,
    input  wire signed [BITWIDTH-1:0]                kernel_data,
    output reg                                       out_enable,
    output reg signed [BITWIDTH-1:0]                 out_data
);

//=====================================
// 0. Parameters
//=====================================
localparam signed [ACC_W:0] ROUND_HALF =
    ({{ACC_W{1'b0}}, 1'b1} << (FRAC_W-1)); //반올림 상수

localparam signed [ACC_W:0] SAT_LIMIT =
    ({{ACC_W{1'b0}}, 1'b1} << (BITWIDTH-1)); //포화 한계값

localparam signed [ACC_W:0] SAT_MAX = SAT_LIMIT - 1; //포화 최대값

localparam signed [ACC_W:0] SAT_MIN = -SAT_LIMIT; //포화 최소값

//=====================================
// 1. Stage 1 - Multiplier
// Feature x Weight
//=====================================
wire signed [2*BITWIDTH-1:0]     mul_data;
reg  signed [2*BITWIDTH-1:0]     mul_reg;
reg                              valid_s1;

// Control and Bypass alignment
reg                              enable_d; // d: delay
reg [BITWIDTH_MAC_ITERATION-1:0] iteration_d;
reg signed [BITWIDTH-1:0]        bypass_data_s1;

assign mul_data = in_data * kernel_data;

//=====================================
// 2. Stage 2 - Adder & Accumulator
//=====================================
wire signed [ACC_W-1:0]           acc_data;
reg  signed [ACC_W-1:0]           acc_reg;
reg  [BITWIDTH_MAC_ITERATION-1:0] count;

reg  signed [ACC_W-1:0]           reg_s2;
reg                               valid_s2;
reg                               bypass_mode_s2;
reg  signed [BITWIDTH-1:0]        bypass_data_s2;

assign acc_data = acc_reg + mul_reg;

//=====================================
// 3. Stage 3 - Rounding (반올림)
//=====================================
wire signed [ACC_W:0]             round_data;
wire signed [ACC_W:0]             round_ext;

reg  signed [ACC_W:0]             reg_s3;
reg                               valid_s3;
reg                               bypass_mode_s3;
reg  signed [BITWIDTH-1:0]        bypass_data_s3;

assign round_ext = $signed({reg_s2[ACC_W-1], reg_s2});

// 양수: +ROUND_HALF, 음수: +(ROUND_HALF-1), 산술 오른쪽 시프트로 반올림
assign round_data = (round_ext >= 0) ?
   ((round_ext + ROUND_HALF) >>> FRAC_W) :
    ((round_ext + (ROUND_HALF - 1'b1)) >>> FRAC_W);

//=====================================
// 4. Stage 4 - Saturation (포화)
//=====================================
wire signed [BITWIDTH-1:0] sat_data;

assign sat_data =
    (reg_s3 > SAT_MAX) ? SAT_MAX[BITWIDTH-1:0] :
    (reg_s3 < SAT_MIN) ? SAT_MIN[BITWIDTH-1:0] :
                         reg_s3[BITWIDTH-1:0];

//=====================================
// 5. Sequential Pipeline
//=====================================
always @(posedge clk or negedge nrst) begin

    if (!nrst) begin
        // Stage 1
        mul_reg          <= 0;
        valid_s1         <= 0;
        enable_d         <= 0;
        iteration_d      <= 0;
        bypass_data_s1   <= 0;

        // Stage 2
        acc_reg          <= 0;
        count            <= 0;
        reg_s2           <= 0;
        valid_s2         <= 0;
        bypass_mode_s2   <= 0;
        bypass_data_s2   <= 0;

        // Stage 3
        reg_s3           <= 0;
        valid_s3         <= 0;
        bypass_mode_s3   <= 0;
        bypass_data_s3   <= 0;

        // Stage 4
        out_data         <= 0;
        out_enable       <= 0;

    end
    else begin

        //=============================
        // Stage 1: Multiplier
        //=============================
        valid_s1 <= in_enable;

        if (in_enable) begin
            mul_reg     <= mul_data;
            enable_d    <= enable;
            iteration_d <= iteration;
            bypass_data_s1   <= in_data;
        end

        //=============================
        // Stage 2: Accumulator
        //=============================
        valid_s2 <= 1'b0;

        if (valid_s1) begin

            if (!enable_d) begin
                // Bypass
                acc_reg          <= 0;
                count            <= 0;

                bypass_data_s2   <= bypass_data_s1;
                bypass_mode_s2   <= 1'b1;
                valid_s2     <= 1'b1;
            end

            else if (count == iteration_d - 1'b1) begin
                // Final accumulation
                reg_s2       <= acc_data;
                bypass_mode_s2   <= 1'b0;
                valid_s2     <= 1'b1;

                acc_reg <= 0;
                count   <= 0;
            end

            else begin
                // Continue accumulation
                acc_reg <= acc_data;
                count   <= count + 1'b1;
            end
        end

        //=============================
        // Stage 3: Rounding
        //=============================
        valid_s3 <= valid_s2;

        if (valid_s2) begin
            bypass_mode_s3 <= bypass_mode_s2;

            if (bypass_mode_s2) begin
                bypass_data_s3 <= bypass_data_s2;
            end
            else begin
                reg_s3 <= round_data;
            end
        end

        //=============================
        // Stage 4: Saturation & Output
        //=============================
        out_enable <= valid_s3;

        if (valid_s3) begin
            if (bypass_mode_s3) begin
                out_data <= bypass_data_s3 ;
            end
            else begin
                out_data <= sat_data;
            end
        end

    end
end

endmodule

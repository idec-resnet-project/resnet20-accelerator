
`timescale 1ns/1ps

module general_average_pooling #(
    parameter integer BITWIDTH = 16,
    parameter integer BITWIDTH_GAP_ITERATION = 16
)(
    input  wire clk,
    input  wire nrst,
    input  wire enable,
    input  wire [BITWIDTH_GAP_ITERATION-1:0] iteration,
    input  wire in_enable,
    input  wire signed [BITWIDTH-1:0] in_data,
    output reg out_enable,
    output reg signed [BITWIDTH-1:0] out_data
);

//=====================================
// 0. Existing Registers & Wires
//=====================================
reg signed [2*BITWIDTH-1:0] sum_reg;
reg [BITWIDTH_GAP_ITERATION-1:0] count;

wire signed [2*BITWIDTH-1:0] total_sum;
wire signed [BITWIDTH_GAP_ITERATION:0] divisor;

assign total_sum = sum_reg + in_data;
assign divisor = $signed({1'b0, iteration});

//=====================================
// 1. Shift Amount
//=====================================
localparam integer SHIFT_W =
    (BITWIDTH_GAP_ITERATION <= 1) ? 1 :
    $clog2(BITWIDTH_GAP_ITERATION);

reg [SHIFT_W-1:0] shift_amount;
integer i;

always @(*) begin
    shift_amount = 0;

    for (i = 0; i < BITWIDTH_GAP_ITERATION; i = i + 1) begin
        if (iteration[i])
            shift_amount = i;
    end
end

//=====================================
// 2. Pipeline Registers (New)
//=====================================

// Stage 1: Final Sum
reg signed [2*BITWIDTH-1:0] total_reg;
reg signed [BITWIDTH_GAP_ITERATION:0] divisor_reg;
reg [SHIFT_W-1:0] shift_reg;
reg valid_s1;

// Stage 2: Average
reg signed [BITWIDTH-1:0] avg_reg;
reg valid_s2;

// Rounding & Shift
wire signed [2*BITWIDTH-1:0] half_value;
wire signed [2*BITWIDTH-1:0] shifted_avg;

assign half_value = $signed(divisor_reg) >>> 1;

assign shifted_avg = (total_reg < 0) ?
    -((-total_reg + half_value) >> shift_reg) :
      ((total_reg + half_value) >> shift_reg);

//=====================================
// 3. Sequential Pipeline
//=====================================
always @(posedge clk or negedge nrst) begin

    if (!nrst) begin
        out_data    <= 0;
        out_enable  <= 0;
        sum_reg     <= 0;
        count       <= 0;

        total_reg   <= 0;
        divisor_reg <= 0;
        shift_reg   <= 0;
        valid_s1    <= 0;

        avg_reg     <= 0;
        valid_s2    <= 0;
    end

    else begin

        //=============================
        // Stage 1: Accumulation
        //=============================
        valid_s1 <= 0;

        if (in_enable) begin

            if (!enable) begin
                // Bypass
                sum_reg <= 0;
                count   <= 0;
            end

            else if (count >= iteration - 1'b1) begin
                // Final input
                total_reg   <= total_sum;
                divisor_reg <= divisor;
                shift_reg   <= shift_amount;
                valid_s1    <= 1;

                sum_reg <= 0;
                count   <= 0;
            end

            else if (count == 0) begin
                sum_reg <= in_data;
                count   <= count + 1'b1;
            end

            else begin
                sum_reg <= in_data + sum_reg;
                count   <= count + 1'b1;
            end
        end

        //=============================
        // Stage 2: Rounding & Shift
        //=============================
        valid_s2 <= valid_s1;

        if (valid_s1) begin
            avg_reg <= shifted_avg[BITWIDTH-1:0];
        end

        //=============================
        // Stage 3: Output
        //=============================
        out_enable <= 0;

        if (in_enable && !enable) begin
            out_data   <= in_data;
            out_enable <= 1;
        end

        else if (valid_s2) begin
            out_data   <= avg_reg;
            out_enable <= 1;
        end

    end
end

endmodule

`timescale 1ns/1ps

// Five registered stages: multiply, accumulate, round, saturate, output.
// One input product per clock; one completed MAC result per iteration group.
// Keep iteration stable while a group is being accumulated.
module mac #(
    parameter integer BITWIDTH = 16,
    parameter integer BITWIDTH_MAC_ITERATION = 16
)(
    input  wire clk,
    input  wire nrst,
    input  wire enable,
    input  wire [BITWIDTH_MAC_ITERATION-1:0] iteration,
    input  wire in_enable,
    input  wire signed [BITWIDTH-1:0] in_data,
    input  wire signed [BITWIDTH-1:0] kernel_data,
    output reg out_enable,
    output reg signed [BITWIDTH-1:0] out_data
);
    localparam integer FRAC_BITS = 8;
    // Maximum sum of 2**ITER_WIDTH signed products requires
    // 2*BITWIDTH + ITER_WIDTH bits (including the sign bit).
    localparam integer ACC_WIDTH = 2*BITWIDTH + BITWIDTH_MAC_ITERATION;
    localparam signed [ACC_WIDTH-1:0] HALF_LSB =
        {{(ACC_WIDTH-1){1'b0}},1'b1} <<< (FRAC_BITS-1);
    localparam signed [ACC_WIDTH-1:0] MAX_VALUE =
        ({{(ACC_WIDTH-1){1'b0}},1'b1} <<< (BITWIDTH-1)) - 1'b1;
    localparam signed [ACC_WIDTH-1:0] MIN_VALUE =
        -({{(ACC_WIDTH-1){1'b0}},1'b1} <<< (BITWIDTH-1));

    // Stage 1: DSP multiplication and bypass alignment.
    reg signed [2*BITWIDTH-1:0] product_r;
    reg signed [BITWIDTH-1:0] bypass_r;
    reg valid_r, mode_r;
    always @(posedge clk or negedge nrst) begin
        if (!nrst) begin
            product_r <= 0;
            bypass_r <= 0;
            valid_r <= 0;
            mode_r <= 0;
        end else begin
            valid_r <= in_enable;
            if (in_enable) begin
                mode_r <= enable;
                if (enable) product_r <= in_data * kernel_data;
                else bypass_r <= in_data;
            end
        end
    end

    // Stage 2: feedback accumulator. Keep this stage at one addition.
    reg signed [ACC_WIDTH-1:0] accumulator;
    reg [BITWIDTH_MAC_ITERATION-1:0] count;
    reg signed [ACC_WIDTH-1:0] sum_r;
    reg signed [BITWIDTH-1:0] bypass_s2;
    reg complete_r, bypass_mode_s2;
    wire signed [ACC_WIDTH-1:0] product_ext =
        {{(ACC_WIDTH-2*BITWIDTH){product_r[2*BITWIDTH-1]}},product_r};
    wire signed [ACC_WIDTH-1:0] sum_next = accumulator + product_ext;
    always @(posedge clk or negedge nrst) begin
        if (!nrst) begin
            accumulator <= 0;
            count <= 0;
            sum_r <= 0;
            bypass_s2 <= 0;
            complete_r <= 0;
            bypass_mode_s2 <= 0;
        end else begin
            complete_r <= 0;
            if (valid_r) begin
                if (!mode_r) begin
                    accumulator <= 0;
                    count <= 0;
                    bypass_s2 <= bypass_r;
                    bypass_mode_s2 <= 1;
                    complete_r <= 1;
                end else if (iteration != 0) begin
                    if (count == iteration - 1'b1) begin
                        sum_r <= sum_next;
                        accumulator <= 0;
                        count <= 0;
                        bypass_mode_s2 <= 0;
                        complete_r <= 1;
                    end else begin
                        accumulator <= sum_next;
                        count <= count + 1'b1;
                    end
                end
            end
        end
    end

    // Stage 3: round-to-nearest, ties away from zero.
    // Division by 2**FRAC_BITS becomes a constant shift.
    wire signed [ACC_WIDTH-1:0] rounded_positive =
        (sum_r + HALF_LSB) >>> FRAC_BITS;
    wire signed [ACC_WIDTH-1:0] rounded_negative =
        -(((-sum_r) + HALF_LSB) >>> FRAC_BITS);
    reg signed [ACC_WIDTH-1:0] rounded_r;
    reg signed [BITWIDTH-1:0] bypass_s3;
    reg valid_s3, bypass_mode_s3;
    always @(posedge clk or negedge nrst) begin
        if (!nrst) begin
            rounded_r <= 0;
            bypass_s3 <= 0;
            valid_s3 <= 0;
            bypass_mode_s3 <= 0;
        end else begin
            valid_s3 <= complete_r;
            if (complete_r) begin
                rounded_r <= sum_r < 0 ? rounded_negative : rounded_positive;
                bypass_s3 <= bypass_s2;
                bypass_mode_s3 <= bypass_mode_s2;
            end
        end
    end

    // Stage 4: saturate and select bypass.
    reg signed [BITWIDTH-1:0] converted_r;
    reg valid_s4;
    always @(posedge clk or negedge nrst) begin
        if (!nrst) begin
            converted_r <= 0;
            valid_s4 <= 0;
        end else begin
            valid_s4 <= valid_s3;
            if (valid_s3) begin
                if (bypass_mode_s3) converted_r <= bypass_s3;
                else if (rounded_r > MAX_VALUE) converted_r <= MAX_VALUE[BITWIDTH-1:0];
                else if (rounded_r < MIN_VALUE) converted_r <= MIN_VALUE[BITWIDTH-1:0];
                else converted_r <= rounded_r[BITWIDTH-1:0];
            end
        end
    end

    // Stage 5: registered output.
    always @(posedge clk or negedge nrst) begin
        if (!nrst) begin
            out_enable <= 0;
            out_data <= 0;
        end else begin
            out_enable <= valid_s4;
            if (valid_s4) out_data <= converted_r;
        end
    end
endmodule

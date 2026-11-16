`timescale 1ns/1ps

// Same-clock, valid-only MAC.
// Q7.8 fixed-point arithmetic.
// Configuration must remain stable during accumulation.
module mac #(
    parameter integer BITWIDTH = 16,
    parameter integer BITWIDTH_MAC_ITERATION = 16
)(
    input  wire                                     clk,
    input  wire                                     nrst,
    input  wire                                     enable,
    input  wire        [BITWIDTH_MAC_ITERATION-1:0] iteration,
    input  wire                                     in_enable,
    input  wire signed [BITWIDTH-1:0]               in_data,
    input  wire signed [BITWIDTH-1:0]               kernel_data,
    output reg                                      out_enable,
    output reg signed [BITWIDTH-1:0]                out_data
);

    //===============================
    // Parameters
    //===============================
    localparam integer FRAC_BITS = 8;
    localparam integer ACC_WIDTH = 32;
    localparam integer ACTIVATION_DIVISOR = 1 << FRAC_BITS;

    //===============================
    // Internal registers
    //===============================

    // Multiply
    reg signed [2*BITWIDTH-1:0] product;
    reg signed [BITWIDTH-1:0] bypass_data;
    reg mul_valid;
    reg mul_enable;

    // Accumulate
    reg signed [ACC_WIDTH-1:0] accumulator;
    reg [BITWIDTH_MAC_ITERATION-1:0] input_count;

    reg signed [ACC_WIDTH-1:0] acc_result;
    reg acc_valid;
    reg acc_bypass;

    // Fixed-point conversion
    reg signed [BITWIDTH-1:0] converted_data;
    reg conv_valid;

    // Intermediate values
    wire signed [ACC_WIDTH-1:0] extended_product;
    wire signed [ACC_WIDTH-1:0] total;

    assign extended_product = $signed(product);
    assign total = accumulator + extended_product;

    //===============================
    // Fixed-point functions
    //===============================

    // Saturate to signed BITWIDTH range
    function automatic signed [BITWIDTH-1:0] saturate;
        input signed [ACC_WIDTH-1:0] value;
        reg signed [ACC_WIDTH-1:0] limit;
        begin
            limit = 32'sd1 <<< (BITWIDTH-1);

            if (value >= limit)
                saturate = limit - 1;
            else if (value < -limit)
                saturate = -limit;
            else
                saturate = value;
        end
    endfunction

    // Round to nearest, ties away from zero
    function automatic signed [ACC_WIDTH-1:0] rounded_divide;
        input signed [ACC_WIDTH-1:0] value;
        input integer divisor;
        begin
            if (value < 0)
                rounded_divide =
                    -((-value + divisor/2) / divisor);
            else
                rounded_divide =
                    (value + divisor/2) / divisor;
        end
    endfunction

    //===============================
    // Multiply
    //===============================
    always @(posedge clk or negedge nrst) begin
        // Reset
        if (!nrst) begin
            product     <= 0;
            bypass_data <= 0;
            mul_valid   <= 0;
            mul_enable  <= 0;
        end
        else begin
            mul_valid <= in_enable;

            if (in_enable) begin
                mul_enable <= enable;

                if (enable) begin
                    // Q7.8 x Q7.8 = Q14.16
                    product <= in_data * kernel_data;
                end
                else begin
                    // Bypass multiplication
                    bypass_data <= in_data;
                end
            end
        end
    end

    //===============================
    // Accumulate
    //===============================
    always @(posedge clk or negedge nrst) begin
        // Reset
        if (!nrst) begin
            accumulator <= 0;
            input_count <= 0;
            acc_result  <= 0;
            acc_valid   <= 0;
            acc_bypass  <= 0;
        end
        else begin
            acc_valid <= 0;

            if (mul_valid) begin
                if (!mul_enable) begin
                    // Bypass MAC operation
                    accumulator <= 0;
                    input_count <= 0;

                    acc_result <= $signed(bypass_data);
                    acc_valid  <= 1;
                    acc_bypass <= 1;
                end
                else if (iteration != 0) begin
                    if (input_count == iteration - 1'b1) begin
                        // Final accumulation
                        acc_result <= total;
                        acc_valid  <= 1;
                        acc_bypass <= 0;

                        // Reset for next MAC operation
                        accumulator <= 0;
                        input_count <= 0;
                    end
                    else begin
                        // Continue accumulation
                        accumulator <= total;
                        input_count <= input_count + 1'b1;
                    end
                end
            end
        end
    end

    //===============================
    // Fixed-point conversion
    //===============================
    always @(posedge clk or negedge nrst) begin
        // Reset
        if (!nrst) begin
            converted_data <= 0;
            conv_valid      <= 0;
        end
        else begin
            conv_valid <= acc_valid;

            if (acc_valid) begin
                if (acc_bypass) begin
                    // Preserve original Q7.8 input
                    converted_data <= acc_result[BITWIDTH-1:0];
                end
                else begin
                    // Q14.16 -> Q7.8
                    // Rounding and saturation
                    converted_data <= saturate(
                        rounded_divide(
                            acc_result,
                            ACTIVATION_DIVISOR
                        )
                    );
                end
            end
        end
    end

    //===============================
    // Output
    //===============================
    always @(posedge clk or negedge nrst) begin
        // Reset
        if (!nrst) begin
            out_enable <= 0;
            out_data   <= 0;
        end
        else begin
            out_enable <= conv_valid;

            if (conv_valid) begin
                out_data <= converted_data;
            end
        end
    end

endmodule

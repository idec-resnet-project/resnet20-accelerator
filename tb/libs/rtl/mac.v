// Same-clock, valid-only stream. Configuration stays stable until drained.
module mac #(
    parameter integer BITWIDTH = 16,
    parameter integer BITWIDTH_MAC_ITERATION = 16
)(
    input wire clk,
    input wire nrst,
    input wire enable,
    input wire [BITWIDTH_MAC_ITERATION-1:0] iteration,
    input wire in_enable,
    input wire signed [BITWIDTH-1:0] in_data,
    input wire signed [BITWIDTH-1:0] kernel_data,
    output wire out_enable,
    output wire signed [BITWIDTH-1:0] out_data
);
    mac_accumulate #(
        .BITWIDTH               (BITWIDTH),
        .BITWIDTH_MAC_ITERATION (BITWIDTH_MAC_ITERATION),
        .INPUT_FRAC_BITS        (8)
    ) u_accumulate (
        .clk         (clk),
        .nrst        (nrst),
        .enable      (enable),
        .iteration   (iteration),
        .in_enable   (in_enable),
        .in_data     (in_data),
        .kernel_data (kernel_data),
        .bias_data   ({BITWIDTH{1'b0}}),
        .last_input  (),
        .out_enable  (out_enable),
        .out_data    (out_data)
    );

endmodule

// Input and bias use INPUT_FRAC_BITS. MAC output uses OUTPUT_FRAC_BITS.
module mac_accumulate #(
    parameter integer BITWIDTH = 16,
    parameter integer BITWIDTH_MAC_ITERATION = 16,
    parameter integer INPUT_FRAC_BITS = 10,
    parameter integer OUTPUT_FRAC_BITS = INPUT_FRAC_BITS
)(
    input wire clk,
    input wire nrst,
    input wire enable,
    input wire [BITWIDTH_MAC_ITERATION-1:0] iteration,
    input wire in_enable,
    input wire signed [BITWIDTH-1:0] in_data,
    input wire signed [BITWIDTH-1:0] kernel_data,
    input wire signed [BITWIDTH-1:0] bias_data,
    output wire last_input,
    output reg out_enable,
    output reg signed [BITWIDTH-1:0] out_data
);

    localparam integer OUTPUT_SHIFT = 2 * INPUT_FRAC_BITS - OUTPUT_FRAC_BITS;
    // Full product, maximum tap count, and one guard bit for the bias.
    localparam integer ACC_WIDTH = 2*BITWIDTH + BITWIDTH_MAC_ITERATION + 1;
    localparam [ACC_WIDTH-1:0] ONE = 1;

    // synthesis translate_off
    initial begin
        if (OUTPUT_FRAC_BITS < 0 || OUTPUT_FRAC_BITS >= BITWIDTH ||
            OUTPUT_FRAC_BITS > 2 * INPUT_FRAC_BITS)
            $fatal(1, "OUTPUT_FRAC_BITS exceeds the supported MAC precision");
    end
    // synthesis translate_on

    // Stage 1. Count accepted taps and capture the product and its controls together.
    reg [BITWIDTH_MAC_ITERATION-1:0] input_count;
    assign last_input = enable && in_enable && input_count == iteration - 1'b1;

    reg product_valid, product_first, product_last, product_bypass;
    reg signed [2*BITWIDTH-1:0] product_q;
    reg signed [BITWIDTH-1:0] bias_q, bypass_q;
    always @(posedge clk or negedge nrst) begin
        if (!nrst) begin
            input_count <= 0;
            product_valid <= 0;
        end else begin
            product_valid <= in_enable;
            if (!enable || !in_enable || last_input)
                input_count <= 0;
            else
                input_count <= input_count + 1'b1;
        end
    end

    // Payload registers are consumed only when their corresponding valid bit is set.
    always @(posedge clk) begin
        if (in_enable) begin
            product_q <= in_data * kernel_data;
            bias_q <= bias_data;
            bypass_q <= in_data;
            product_first <= input_count == 0;
            product_last <= last_input;
            product_bypass <= !enable;
        end
    end

    // Stage 2. The first tap loads the scaled bias, later taps use the running sum.
    reg signed [ACC_WIDTH-1:0] accumulator;
    wire signed [ACC_WIDTH-1:0] extended_bias = bias_q;
    wire signed [ACC_WIDTH-1:0] addend = product_first ?
                                          (extended_bias <<< INPUT_FRAC_BITS) : accumulator;
    reg sum_valid, sum_bypass;
    reg signed [BITWIDTH-1:0] bypass_delayed;
    always @(posedge clk or negedge nrst) begin
        if (!nrst)
            sum_valid <= 0;
        else
            sum_valid <= product_valid && (product_last || product_bypass);
    end
    always @(posedge clk) begin
        if (product_valid) begin
            accumulator <= addend + product_q;
            sum_bypass <= product_bypass;
            bypass_delayed <= bypass_q;
        end
    end

    // Stage 3. Round to nearest, with exact ties away from zero, then saturate.
    localparam signed [ACC_WIDTH-1:0] LIMIT = $signed(ONE) <<< (BITWIDTH-1);
    wire signed [ACC_WIDTH-1:0] rounded;
    generate
        if (OUTPUT_SHIFT == 0) begin : no_shift
            assign rounded = accumulator;
        end else begin : round_shift
            // The arithmetic shift takes the floor. Negative exact ties keep that floor.
            wire below_half_bit_set = |(accumulator & ((ONE << (OUTPUT_SHIFT-1)) - ONE));
            wire increment = accumulator[OUTPUT_SHIFT-1] &&
                             (!accumulator[ACC_WIDTH-1] || below_half_bit_set);
            assign rounded = (accumulator >>> OUTPUT_SHIFT) + $signed({1'b0, increment});
        end
    endgenerate
    wire signed [BITWIDTH-1:0] saturated = (rounded >= LIMIT) ? LIMIT - 1 :
                                           (rounded < -LIMIT) ? -LIMIT : rounded;

    always @(posedge clk or negedge nrst) begin
        if (!nrst) begin
            out_enable <= 0;
            out_data <= 0;
        end else begin
            out_enable <= sum_valid;
            if (sum_valid)
                out_data <= sum_bypass ? bypass_delayed : saturated;
        end
    end
endmodule

`timescale 1ns/1ps

module core #(
    // Bitwidth
    parameter integer BITWIDTH                   = 16,
    parameter integer BITWIDTH_MAC_ITERATION     = 16,
    parameter integer BITWIDTH_POOLING_ITERATION = 16,
    parameter integer BITWIDTH_GAP_ITERATION     = 16,
    parameter integer OUTPUT_FRAC_BITS           = 10,

    // Parallelism
    parameter integer PARALLEL_PC                = 1,
    parameter integer PARALLEL_PF                = 1
)(
    input  wire                                     clk,
    input  wire                                     nrst,

    // Configuration
    input  wire                                     mac_enable,
    input  wire [BITWIDTH_MAC_ITERATION-1:0]        mac_iteration,
    input  wire                                     residual_enable,
    input  wire                                     relu_enable,
    input  wire                                     pooling_enable,
    input  wire [BITWIDTH_POOLING_ITERATION-1:0]    pooling_iteration,
    input  wire                                     gap_enable,
    input  wire [BITWIDTH_GAP_ITERATION-1:0]        gap_iteration,
    input  wire                                     output_is_logit,

    // Input stream
    input  wire                                     in_enable,
    input  wire signed [BITWIDTH-1:0]               in_data,
    input  wire signed [BITWIDTH-1:0]               kernel_data,
    input  wire signed [BITWIDTH-1:0]               bias_data,

    // Output stream
    output reg                                      out_enable,
    output reg signed [BITWIDTH-1:0]                out_data
);
    // --------------------------------
    // Q5.10 limits
    // --------------------------------
    localparam integer INPUT_FRAC_BITS = 10;
    localparam integer SCALE = 1 << INPUT_FRAC_BITS;
    localparam integer LOGIT_DIVISOR = 1 << (2 * INPUT_FRAC_BITS - OUTPUT_FRAC_BITS);
    localparam signed [63:0] MAX_WORD = (64'sd1 <<< (BITWIDTH - 1)) - 1;
    localparam signed [63:0] MIN_WORD = -(64'sd1 <<< (BITWIDTH - 1));

    // --------------------------------
    // MAC, residual, and GAP state
    // --------------------------------
    reg signed [63:0]                           mac_sum;
    reg        [BITWIDTH_MAC_ITERATION-1:0]     mac_count;
    reg                                         waiting_for_skip;
    reg signed [BITWIDTH-1:0]                   mac_result;

    reg signed [63:0]                           gap_sum;
    reg        [BITWIDTH_GAP_ITERATION-1:0]     gap_count;

    // Extend the bias before shifting it to the product scale.
    wire signed [2*BITWIDTH-1:0]                 product = in_data * kernel_data;
    wire signed [63:0]                           extended_bias = bias_data;
    wire signed [63:0]                           mac_total =
        (mac_count == 0 ? (extended_bias <<< INPUT_FRAC_BITS) : mac_sum) + product;
    wire signed [63:0]                           residual_total = $signed(mac_result) + $signed(in_data);

    // --------------------------------
    // Fixed-point arithmetic
    // --------------------------------
    function automatic signed [BITWIDTH-1:0] saturate(input signed [63:0] value);
        if (value > MAX_WORD) saturate = MAX_WORD[BITWIDTH-1:0];
        else if (value < MIN_WORD) saturate = MIN_WORD[BITWIDTH-1:0];
        else saturate = value[BITWIDTH-1:0];
    endfunction

    function automatic signed [63:0] rounded_divide(
        input signed [63:0] value, input integer divisor
    );
        if (value < 0) rounded_divide = -((-value + divisor / 2) / divisor);
        else rounded_divide = (value + divisor / 2) / divisor;
    endfunction

    // --------------------------------
    // Activation and output
    // --------------------------------
    task automatic emit(input signed [BITWIDTH-1:0] value);
        reg signed [BITWIDTH-1:0] activated;
        reg signed [63:0] total;
        begin
            activated = (relu_enable && value < 0) ? 0 : value;
            if (gap_enable) begin
                total = gap_sum + activated;
                if (gap_count == gap_iteration - 1'b1) begin
                    gap_count <= 0;
                    gap_sum <= 0;
                    out_data <= saturate(rounded_divide(total, int'(gap_iteration)));
                    out_enable <= 1;
                end else begin
                    gap_count <= gap_count + 1'b1;
                    gap_sum <= total;
                end
            end else begin
                out_data <= activated;
                out_enable <= 1;
            end
        end
    endtask

    // --------------------------------
    // Configuration and input processing
    // --------------------------------
    // synthesis translate_off
    initial begin
        if (BITWIDTH != 16 || PARALLEL_PC != 1 || PARALLEL_PF != 1)
            $fatal(1, "Dummy core supports 16-bit Q5.10 and one lane");
        if (OUTPUT_FRAC_BITS < 0 || OUTPUT_FRAC_BITS >= BITWIDTH)
            $fatal(1, "Invalid dummy logit fraction width: %0d", OUTPUT_FRAC_BITS);
    end
    // synthesis translate_on

    always @(posedge clk or negedge nrst) begin
        if (!nrst) begin
            mac_sum <= 0;
            mac_count <= 0;
            mac_result <= 0;
            waiting_for_skip <= 0;
            gap_sum <= 0;
            gap_count <= 0;
            out_enable <= 0;
            out_data <= 0;
        end else begin
            out_enable <= 0;
            if (in_enable) begin
                // synthesis translate_off
                if (pooling_enable || (gap_enable && gap_iteration == 0) ||
                    (mac_enable && mac_iteration == 0))
                    $fatal(1, "Unsupported dummy core configuration");
                // synthesis translate_on

                // The first valid word after the dot product carries the shortcut.
                if (waiting_for_skip) begin
                    waiting_for_skip <= 0;
                    emit(saturate(residual_total));
                end else if (!mac_enable) begin
                    emit(in_data);
                end else if (mac_count == mac_iteration - 1'b1) begin
                    mac_count <= 0;
                    if (residual_enable) begin
                        mac_result <= saturate(rounded_divide(mac_total, SCALE));
                        waiting_for_skip <= 1;
                    end else if (output_is_logit) begin
                        // FC requantizes directly from the accumulator to the output format.
                        out_data <= saturate(rounded_divide(mac_total, LOGIT_DIVISOR));
                        out_enable <= 1;
                    end else begin
                        emit(saturate(rounded_divide(mac_total, SCALE)));
                    end
                end else begin
                    mac_count <= mac_count + 1'b1;
                    mac_sum <= mac_total;
                end
            end
        end
    end
endmodule

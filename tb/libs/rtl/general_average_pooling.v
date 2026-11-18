// Same-clock, valid-only stream. Configuration stays stable until drained.
module general_average_pooling #(
    parameter integer BITWIDTH = 16,
    parameter integer BITWIDTH_GAP_ITERATION = 16
)(
    input wire clk,
    input wire nrst,
    input wire enable,
    input wire [BITWIDTH_GAP_ITERATION-1:0] iteration,
    input wire in_enable,
    input wire signed [BITWIDTH-1:0] in_data,
    output reg out_enable,
    output reg signed [BITWIDTH-1:0] out_data
);

    // ------------------------------------
    // Fixed-point arithmetic
    // ------------------------------------
    localparam integer SUM_WIDTH = BITWIDTH + BITWIDTH_GAP_ITERATION;
    reg signed [SUM_WIDTH-1:0] accumulator;
    reg [BITWIDTH_GAP_ITERATION-1:0] input_count;
    reg pending_enable;
    reg signed [SUM_WIDTH-1:0] pending_sum;
    reg [BITWIDTH_GAP_ITERATION-1:0] pending_divisor;
    wire signed [SUM_WIDTH-1:0] extended_input = $signed(in_data);
    wire signed [SUM_WIDTH-1:0] total = accumulator + extended_input;

    // An average of signed BITWIDTH inputs fits in BITWIDTH, including -2^(BITWIDTH-1).
    wire [SUM_WIDTH-1:0] magnitude = pending_sum[SUM_WIDTH-1] ? -pending_sum : pending_sum;
    wire [SUM_WIDTH-1:0] divisor = pending_divisor;
    wire [SUM_WIDTH-1:0] dividend = magnitude + (divisor >> 1);
    // Register the rounded magnitude before the first pair of division steps.
    localparam integer BITS_PER_STAGE = 2;
    localparam integer DIV_STAGES = (BITWIDTH + BITS_PER_STAGE - 1) / BITS_PER_STAGE;
    reg [SUM_WIDTH-1:0] remainder_q [0:DIV_STAGES];
    reg [BITWIDTH_GAP_ITERATION-1:0] divisor_q [0:DIV_STAGES];
    reg [BITWIDTH-1:0] quotient_q [0:DIV_STAGES];
    reg negative_q [0:DIV_STAGES];
    reg [DIV_STAGES:0] valid_q;

    always @(posedge clk or negedge nrst) begin
        if (!nrst) valid_q <= 0;
        else valid_q <= {valid_q[DIV_STAGES-1:0], pending_enable};
    end

    always @(posedge clk) begin
        if (pending_enable) begin
            remainder_q[0] <= dividend;
            divisor_q[0] <= pending_divisor;
            quotient_q[0] <= 0;
            negative_q[0] <= pending_sum[SUM_WIDTH-1];
        end
    end

    // Each registered stage resolves up to two quotient bits, MSB first.
    genvar stage, step;
    generate
        for (stage = 0; stage < DIV_STAGES; stage = stage+1) begin : divide_stage
            localparam integer BITS_LEFT = BITWIDTH - stage*BITS_PER_STAGE;
            localparam integer STEPS = BITS_LEFT < BITS_PER_STAGE ? BITS_LEFT : BITS_PER_STAGE;
            wire [SUM_WIDTH-1:0] remainder [0:STEPS];
            wire [STEPS-1:0] quotient_bits;
            assign remainder[0] = remainder_q[stage];

            for (step = 0; step < STEPS; step = step+1) begin : divide_bit
                localparam integer BIT_INDEX = BITS_LEFT - step - 1;
                wire [SUM_WIDTH-1:0] trial = divisor_q[stage] << BIT_INDEX;
                wire fits = remainder[step] >= trial;
                assign quotient_bits[STEPS-1-step] = fits;
                assign remainder[step+1] = fits ? remainder[step] - trial : remainder[step];
            end

            always @(posedge clk) begin
                if (valid_q[stage]) begin
                    remainder_q[stage+1] <= remainder[STEPS];
                    divisor_q[stage+1] <= divisor_q[stage];
                    quotient_q[stage+1] <= (quotient_q[stage] << STEPS) | quotient_bits;
                    negative_q[stage+1] <= negative_q[stage];
                end
            end
        end
    endgenerate

    wire signed [BITWIDTH-1:0] average = negative_q[DIV_STAGES] ?
                                         -quotient_q[DIV_STAGES] : quotient_q[DIV_STAGES];

    always @(posedge clk or negedge nrst) begin
        if (!nrst) begin
            accumulator <= 0;
            input_count <= 0;
            pending_sum <= 0;
            pending_divisor <= 1;
            pending_enable <= 0;
            out_enable <= 0;
            out_data <= 0;
        end else begin
            out_enable <= valid_q[DIV_STAGES];
            if (valid_q[DIV_STAGES])
                out_data <= average;

            pending_enable <= 0;
            if (in_enable) begin
                if (!enable) begin
                    accumulator <= 0;
                    input_count <= 0;
                    pending_sum <= extended_input;
                    pending_divisor <= 1;
                    pending_enable <= 1;
                end else if (input_count == iteration - 1'b1) begin
                    pending_sum <= total;
                    pending_divisor <= iteration;
                    pending_enable <= 1;
                    accumulator <= 0;
                    input_count <= 0;
                end else begin
                    accumulator <= total;
                    input_count <= input_count + 1'b1;
                end
            end
        end
    end
endmodule

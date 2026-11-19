
module core #(
    // Bitwidth
    parameter integer BITWIDTH                   = 16,
    parameter integer BITWIDTH_MAC_ITERATION     = 16,
    parameter integer BITWIDTH_POOLING_ITERATION = 16,
    parameter integer BITWIDTH_GAP_ITERATION     = 16,
    // Parallelism
    parameter integer PARALLEL_PC                = 1,
    parameter integer PARALLEL_PF                = 1,
    parameter integer OUTPUT_FRAC_BITS          = 10,
    parameter integer PIPELINE_BOUNDARIES        = 1
)(
    input  wire                                  clk,
    input  wire                                  nrst,

    // Configuration
    input  wire                                  mac_enable,
    input  wire [BITWIDTH_MAC_ITERATION-1:0]      mac_iteration,
    input  wire                                  residual_enable,
    input  wire                                  relu_enable,
    input  wire                                  pooling_enable,
    input  wire [BITWIDTH_POOLING_ITERATION-1:0]  pooling_iteration,
    input  wire                                  gap_enable,
    input  wire [BITWIDTH_GAP_ITERATION-1:0]      gap_iteration,

    // Input stream
    input  wire                                  in_enable,
    input  wire        [BITWIDTH-1:0]             in_data,
    input  wire        [BITWIDTH-1:0]             kernel_data,
    input  wire        [BITWIDTH-1:0]             bias_data,

    // Output stream
    output wire                                   out_enable,
    output wire         [BITWIDTH-1:0]             out_data,

    // Supply the shortcut with the last MAC tap.
    input  wire         [BITWIDTH-1:0]             residual_data
);
    wire mac_last_input;
    wire mac_valid, residual_valid, relu_valid, pooling_valid, gap_valid;
    wire signed [BITWIDTH-1:0] mac_data, residual_out_data, relu_data, pooling_data, gap_data;

    // synthesis translate_off
    initial begin
        if (PARALLEL_PC != 1 || PARALLEL_PF != 1)
            $fatal(1, "The reference core supports one lane");
    end
    // synthesis translate_on

    // --------------------------------
    // Align the MAC result and shortcut
    // --------------------------------
    wire use_residual = mac_enable && residual_enable;
    reg [BITWIDTH-1:0] shortcut_tap, shortcut_sum, shortcut_result;

    // Match the MAC's product, sum, and output registers.
    always @(posedge clk) begin
        if (use_residual && mac_last_input)
            shortcut_tap <= residual_data;
        shortcut_sum <= shortcut_tap;
        shortcut_result <= shortcut_sum;
    end

    // --------------------------------
    // Reference datapath
    // --------------------------------
    mac_accumulate #(
        .BITWIDTH               (BITWIDTH),
        .BITWIDTH_MAC_ITERATION (BITWIDTH_MAC_ITERATION),
        .INPUT_FRAC_BITS        (10),
        .OUTPUT_FRAC_BITS       (OUTPUT_FRAC_BITS)
    ) u_mac (
        .clk             (clk),
        .nrst            (nrst),
        .enable          (mac_enable),
        .iteration       (mac_iteration),
        .in_enable       (in_enable),
        .in_data         (in_data),
        .kernel_data     (kernel_data),
        .bias_data       (bias_data),
        .last_input      (mac_last_input),
        .out_enable      (mac_valid),
        .out_data        (mac_data)
    );

    wire residual_input_valid;
    wire signed [BITWIDTH-1:0] residual_input, residual_shortcut;
    core_stream_boundary #(.WIDTH(2*BITWIDTH), .REGISTERED(PIPELINE_BOUNDARIES)) to_residual (
        .clk(clk), .nrst(nrst), .in_valid(mac_valid), .in_data({mac_data, shortcut_result}),
        .out_valid(residual_input_valid), .out_data({residual_input, residual_shortcut})
    );

    residual #(.BITWIDTH(BITWIDTH)) u_residual (
        .clk        (clk),
        .nrst       (nrst),
        .enable     (use_residual),
        .in_enable  (residual_input_valid),
        .in_data    (residual_input),
        .skip_data  (residual_shortcut),
        .out_enable (residual_valid),
        .out_data   (residual_out_data)
    );

    wire relu_input_valid;
    wire signed [BITWIDTH-1:0] relu_input;
    core_stream_boundary #(.WIDTH(BITWIDTH), .REGISTERED(PIPELINE_BOUNDARIES)) to_relu (
        .clk(clk), .nrst(nrst), .in_valid(residual_valid), .in_data(residual_out_data),
        .out_valid(relu_input_valid), .out_data(relu_input)
    );

    relu #(.BITWIDTH(BITWIDTH)) u_relu (
        .clk        (clk),
        .nrst       (nrst),
        .enable     (relu_enable),
        .in_enable  (relu_input_valid),
        .in_data    (relu_input),
        .out_enable (relu_valid),
        .out_data   (relu_data)
    );

    wire pooling_input_valid;
    wire signed [BITWIDTH-1:0] pooling_input;
    core_stream_boundary #(.WIDTH(BITWIDTH), .REGISTERED(PIPELINE_BOUNDARIES)) to_pooling (
        .clk(clk), .nrst(nrst), .in_valid(relu_valid), .in_data(relu_data),
        .out_valid(pooling_input_valid), .out_data(pooling_input)
    );

    pooling #(
        .BITWIDTH                   (BITWIDTH),
        .BITWIDTH_POOLING_ITERATION (BITWIDTH_POOLING_ITERATION)
    ) u_pooling (
        .clk        (clk),
        .nrst       (nrst),
        .enable     (pooling_enable),
        .iteration  (pooling_iteration),
        .in_enable  (pooling_input_valid),
        .in_data    (pooling_input),
        .out_enable (pooling_valid),
        .out_data   (pooling_data)
    );

    wire gap_input_valid;
    wire signed [BITWIDTH-1:0] gap_input;
    core_stream_boundary #(.WIDTH(BITWIDTH), .REGISTERED(PIPELINE_BOUNDARIES)) to_gap (
        .clk(clk), .nrst(nrst), .in_valid(pooling_valid), .in_data(pooling_data),
        .out_valid(gap_input_valid), .out_data(gap_input)
    );

    general_average_pooling #(
        .BITWIDTH               (BITWIDTH),
        .BITWIDTH_GAP_ITERATION (BITWIDTH_GAP_ITERATION)
    ) u_gap (
        .clk        (clk),
        .nrst       (nrst),
        .enable     (gap_enable),
        .iteration  (gap_iteration),
        .in_enable  (gap_input_valid),
        .in_data    (gap_input),
        .out_enable (gap_valid),
        .out_data   (gap_data)
    );

    assign out_enable = gap_valid;
    assign out_data = gap_data;
endmodule

// Each boundary moves its payload and valid together, including valid bubbles.
module core_stream_boundary #(
    parameter integer WIDTH = 16,
    parameter integer REGISTERED = 1
)(
    input wire clk, nrst,
    input wire in_valid,
    input wire [WIDTH-1:0] in_data,
    output wire out_valid,
    output wire [WIDTH-1:0] out_data
);
    generate
        if (REGISTERED) begin : registered_stream
            reg valid;
            reg [WIDTH-1:0] data;
            always @(posedge clk or negedge nrst) begin
                if (!nrst) begin
                    valid <= 0;
                    data <= 0;
                end else begin
                    valid <= in_valid;
                    if (in_valid) data <= in_data;
                end
            end
            assign out_valid = valid;
            assign out_data = data;
        end else begin : direct_stream
            assign out_valid = in_valid;
            assign out_data = in_data;
        end
    endgenerate
endmodule

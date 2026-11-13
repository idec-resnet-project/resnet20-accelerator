
module core #(
    // Bitwidth
    parameter integer BITWIDTH                   = 16,
    parameter integer BITWIDTH_MAC_ITERATION     = 16,
    parameter integer BITWIDTH_POOLING_ITERATION = 16,
    parameter integer BITWIDTH_GAP_ITERATION     = 16,
    // Parallelism
    parameter integer PARALLEL_PC                = 1,
    parameter integer PARALLEL_PF                = 1
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
    output reg                                   out_enable,
    output reg         [BITWIDTH-1:0]             out_data
);
    wire mac_last_input;
    wire mac_valid, residual_valid, relu_valid, pooling_valid, gap_valid;
    wire signed [BITWIDTH-1:0] mac_data, residual_data, relu_data, pooling_data, gap_data;

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
    reg waiting_for_skip;
    reg mac_held_valid, skip_held_valid;
    reg signed [BITWIDTH-1:0] mac_held_data, skip_held_data;

    wire skip_valid = waiting_for_skip && in_enable;
    wire pair_valid = (mac_valid || mac_held_valid) && (skip_valid || skip_held_valid);
    wire residual_in_valid = use_residual ? pair_valid : mac_valid;
    wire signed [BITWIDTH-1:0] residual_main = mac_held_valid ? mac_held_data : mac_data;
    wire signed [BITWIDTH-1:0] residual_skip = skip_held_valid ? skip_held_data : in_data;

    always @(posedge clk or negedge nrst) begin
        if (!nrst) begin
            waiting_for_skip <= 0;
            mac_held_valid <= 0;
            skip_held_valid <= 0;
            mac_held_data <= 0;
            skip_held_data <= 0;
        end else begin
            // The next valid input after the last MAC tap carries the shortcut.
            if (skip_valid)
                waiting_for_skip <= 0;
            else if (use_residual && mac_last_input)
                waiting_for_skip <= 1;

            if (!use_residual || pair_valid) begin
                mac_held_valid <= 0;
                skip_held_valid <= 0;
            end else begin
                if (mac_valid) begin
                    mac_held_valid <= 1;
                    mac_held_data <= mac_data;
                end
                if (skip_valid) begin
                    skip_held_valid <= 1;
                    skip_held_data <= in_data;
                end
            end
        end
    end

    // --------------------------------
    // Reference datapath
    // --------------------------------
    mac_accumulate #(
        .BITWIDTH               (BITWIDTH),
        .BITWIDTH_MAC_ITERATION (BITWIDTH_MAC_ITERATION),
        .INPUT_FRAC_BITS        (10)
    ) u_mac (
        .clk             (clk),
        .nrst            (nrst),
        .enable          (mac_enable),
        .iteration       (mac_iteration),
        .in_enable       (in_enable && !waiting_for_skip),
        .in_data         (in_data),
        .kernel_data     (kernel_data),
        .bias_data       (bias_data),
        .last_input      (mac_last_input),
        .out_enable      (mac_valid),
        .out_data        (mac_data)
    );

    residual #(.BITWIDTH(BITWIDTH)) u_residual (
        .clk        (clk),
        .nrst       (nrst),
        .enable     (use_residual),
        .in_enable  (residual_in_valid),
        .in_data    (residual_main),
        .skip_data  (residual_skip),
        .out_enable (residual_valid),
        .out_data   (residual_data)
    );

    relu #(.BITWIDTH(BITWIDTH)) u_relu (
        .clk        (clk),
        .nrst       (nrst),
        .enable     (relu_enable),
        .in_enable  (residual_valid),
        .in_data    (residual_data),
        .out_enable (relu_valid),
        .out_data   (relu_data)
    );

    pooling #(
        .BITWIDTH                   (BITWIDTH),
        .BITWIDTH_POOLING_ITERATION (BITWIDTH_POOLING_ITERATION)
    ) u_pooling (
        .clk        (clk),
        .nrst       (nrst),
        .enable     (pooling_enable),
        .iteration  (pooling_iteration),
        .in_enable  (relu_valid),
        .in_data    (relu_data),
        .out_enable (pooling_valid),
        .out_data   (pooling_data)
    );

    general_average_pooling #(
        .BITWIDTH               (BITWIDTH),
        .BITWIDTH_GAP_ITERATION (BITWIDTH_GAP_ITERATION)
    ) u_gap (
        .clk        (clk),
        .nrst       (nrst),
        .enable     (gap_enable),
        .iteration  (gap_iteration),
        .in_enable  (pooling_valid),
        .in_data    (pooling_data),
        .out_enable (gap_valid),
        .out_data   (gap_data)
    );

    always @* begin
        out_enable = gap_valid;
        out_data = gap_data;
    end
endmodule

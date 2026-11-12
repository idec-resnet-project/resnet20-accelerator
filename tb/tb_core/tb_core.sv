`timescale 1ns/1ps

module tb_core #(
    parameter int SKIP_DELAY_CYCLES = 1,
    parameter int OUTPUT_FRAC_BITS  = 10
);
    // Five registered datapath stages with two clocks per stage.
    localparam int CORE_PIPELINE_CYCLES = 10;
    localparam int CORE_FRAC_BITS = 10;

    // --------------------------------
    // Clock and reset
    // --------------------------------
    logic clk  = 0;
    logic nrst = 0;

    always #5 clk = ~clk;

    // --------------------------------
    // Core interface
    // --------------------------------
    // Layer configuration
    logic residual_enable = 0;
    logic relu_enable     = 0;
    logic gap_enable      = 0;
    logic [15:0] mac_iteration = 0;
    logic [15:0] gap_iteration = 0;

    // Input stream
    logic               in_enable   = 0;
    logic signed [15:0] in_data     = 0;
    logic signed [15:0] kernel_data = 0;
    logic signed [15:0] bias_data   = 0;

    // Output stream
    wire               out_enable;
    wire signed [15:0] out_data;

    int input_gap = 0;

    core dut (
        .clk               (clk),
        .nrst              (nrst),

        // Configuration
        .mac_enable        (1'b1),
        .mac_iteration     (mac_iteration),
        .residual_enable   (residual_enable),
        .relu_enable       (relu_enable),
        .pooling_enable    (1'b0),
        .pooling_iteration (16'd0),
        .gap_enable        (gap_enable),
        .gap_iteration     (gap_iteration),

        // Input
        .in_enable         (in_enable),
        .in_data           (in_data),
        .kernel_data       (kernel_data),
        .bias_data         (bias_data),

        // Output
        .out_enable        (out_enable),
        .out_data          (out_data)
    );

    // --------------------------------
    // Model, schedule, and checking
    // --------------------------------
    `include "resnet20_model.svh"
    `include "data_schedule.svh"
    `include "resnet20_scoreboard.svh"
    `include "resnet20_driver.svh"

    // --------------------------------
    // Inference sequence
    // --------------------------------
    task automatic run_resnet20;
        layer_t layer;

        for (int i = 0; i < LAYER_COUNT; i++) begin
            layer = layers[i];
            case (layer.op)
                OP_INPUT: begin
                    read_hex("vectors/input_q5_10.hex", layer.width * layer.height * layer.cin,
                             feature);
                end

                OP_SKIP: begin
                    // Preserve the identity shortcut before updating feature.
                    for (int j = 0; j < layer.width * layer.height * layer.cin; j++)
                        shortcut[j] = feature[j];
                end

                default: run_affine(i);
            endcase
        end

        if (weights_consumed != WEIGHT_WORDS)
            $fatal(1, "Consumed %0d bytes, expected %0d", 2 * weights_consumed, 2 * WEIGHT_WORDS);
        $display("[ PASS ] full ResNet-20 consumed %0d weight bytes", 2 * weights_consumed);
    endtask

    // --------------------------------
    // Test entry point
    // --------------------------------
    initial begin : test
        string weight_path;
        if (!$value$plusargs("weight_path=%s", weight_path))
            weight_path = "../../../verification/resnet20/weight.bin";
        if ($value$plusargs("input_gap=%d", input_gap) && input_gap < 0)
            $fatal(1, "input_gap must be nonnegative");
        if (SKIP_DELAY_CYCLES < 1)
            $fatal(1, "SKIP_DELAY_CYCLES must be positive");
        if (OUTPUT_FRAC_BITS < 0 || OUTPUT_FRAC_BITS > 15)
            $fatal(1, "OUTPUT_FRAC_BITS must be between 0 and 15");
        weights_consumed = 0;
        $display("[ INFO ] ResNet-20 Q5.10 input_gap=%0d skip_delay=%0d output_frac_bits=%0d",
                 input_gap, SKIP_DELAY_CYCLES, OUTPUT_FRAC_BITS);

        read_model(weight_path);
        check_schedule();
`ifdef TB_CORE_POST_SYNTHESIS
        // The Vivado global startup reset holds the primitives for 100 ns.
        repeat (11) @(posedge clk);
`endif
        repeat (3) @(negedge clk);
        nrst = 1;
        check_arithmetic();
        run_resnet20();
        $write("[ INFO ] Q%0d.%0d logits:", 15 - OUTPUT_FRAC_BITS, OUTPUT_FRAC_BITS);
        for (int i = 0; i < LOGIT_COUNT; i++) begin
            feature[i] = format_logit(feature[i]);
            $write(" %0d", feature[i]);
        end
        $display("");
        check_logit_snr();
        idle(2);
        $display("[ PASS ] ALL TESTS PASSED");
        $finish;
    end
endmodule

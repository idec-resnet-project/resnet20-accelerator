`timescale 1ns/1ps

module gap #(
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
    localparam integer CW = BITWIDTH_GAP_ITERATION;
    localparam integer AW = BITWIDTH + CW;
    reg signed [AW-1:0] accumulator;
    reg [CW-1:0] input_count;
    reg signed [AW-1:0] pending_sum;
    reg [CW-1:0] pending_divisor;
    reg pending_valid;

    wire signed [AW-1:0] extended_input = {{CW{in_data[BITWIDTH-1]}}, in_data};
    wire signed [AW-1:0] next_sum = accumulator + extended_input;
    wire [AW-1:0] magnitude = pending_sum[AW-1] ?
                              (~pending_sum + 1'b1) : pending_sum;
    wire [AW-1:0] divisor_ext = {{BITWIDTH{1'b0}}, pending_divisor};
    wire [AW-1:0] rounded_magnitude = magnitude + (divisor_ext >> 1);
    // pending_divisor is initialized to 1 and is never assigned zero.
    wire [AW-1:0] quotient = rounded_magnitude / divisor_ext;
    wire signed [AW-1:0] average = pending_sum[AW-1] ?
                                    -$signed(quotient) : $signed(quotient);

    always @(posedge clk or negedge nrst) begin
        if (!nrst) begin
            accumulator    <= {AW{1'b0}};
            input_count    <= {CW{1'b0}};
            pending_sum    <= {AW{1'b0}};
            pending_divisor<= {{(CW-1){1'b0}},1'b1};
            pending_valid  <= 1'b0;
            out_enable     <= 1'b0;
            out_data       <= {BITWIDTH{1'b0}};
        end else begin
            out_enable <= pending_valid;
            if (pending_valid)
                out_data <= average[BITWIDTH-1:0];
            pending_valid <= 1'b0;

            // A zero-length configuration is invalid. Flush partial window.
            if (enable && iteration == {CW{1'b0}}) begin
                accumulator <= {AW{1'b0}};
                input_count <= {CW{1'b0}};
            end else if (in_enable) begin
                if (!enable) begin
                    // Bypass each valid input; discard partial GAP accumulation.
                    accumulator     <= {AW{1'b0}};
                    input_count     <= {CW{1'b0}};
                    pending_sum     <= extended_input;
                    pending_divisor <= {{(CW-1){1'b0}},1'b1};
                    pending_valid   <= 1'b1;
                end else if (input_count == iteration - 1'b1) begin
                    pending_sum     <= next_sum;
                    pending_divisor <= iteration;
                    pending_valid   <= 1'b1;
                    accumulator     <= {AW{1'b0}};
                    input_count     <= {CW{1'b0}};
                end else begin
                    accumulator <= next_sum;
                    input_count <= input_count + 1'b1;
                end
            end
        end
    end
endmodule

`timescale 1ns/1ps
// Same-clock, valid-only stream. Configuration stays stable until drained.
module relu #(parameter integer BITWIDTH = 16)(
    input wire clk,
    input wire nrst,
    input wire enable,
    input wire in_enable,
    input wire signed [BITWIDTH-1:0] in_data,
    output wire out_enable,
    output wire signed [BITWIDTH-1:0] out_data
);

    //===============================
    // Stage 1: ReLU
    //===============================
    reg pending_enable;
    reg signed [BITWIDTH-1:0] pending_data;

    //===============================
    // Stage 2: Output
    //===============================
    reg valid;
    reg signed [BITWIDTH-1:0] data;

    assign out_enable = valid;
    assign out_data   = data;

    always @(posedge clk or negedge nrst) begin
        if (!nrst) begin
            pending_enable <= 1'b0;
            pending_data   <= {BITWIDTH{1'b0}};
            valid          <= 1'b0;
            data           <= {BITWIDTH{1'b0}};
        end
        else begin
            // Stage 1
            pending_enable <= in_enable;

            if (in_enable) begin
                pending_data <= (enable && in_data[BITWIDTH-1]) ? {BITWIDTH{1'b0}} : in_data;
            end

            // Stage 2
            valid <= pending_enable;

            if (pending_enable) begin
                data <= pending_data;
            end
        end
    end

endmodule

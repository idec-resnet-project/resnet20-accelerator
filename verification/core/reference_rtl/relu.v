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

    reg pending_enable;
    reg signed [BITWIDTH-1:0] pending_data;

    reg valid;
    reg signed [BITWIDTH-1:0] data;
    assign out_enable = valid;
    assign out_data = data;

    always @(posedge clk or negedge nrst) begin
        if (!nrst) begin
            pending_enable <= 0;
            pending_data <= 0;
            valid <= 0;
            data <= 0;
        end else begin
            pending_enable <= in_enable;
            if (in_enable)
                pending_data <= (enable && in_data < 0) ? 0 : in_data;

            valid <= pending_enable;
            if (pending_enable) data <= pending_data;
        end
    end
endmodule

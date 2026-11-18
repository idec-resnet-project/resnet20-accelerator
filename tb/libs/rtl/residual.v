// Same-clock, valid-only stream. Configuration stays stable until drained.
module residual #(parameter integer BITWIDTH = 16)(
    input wire clk,
    input wire nrst,
    input wire enable,
    input wire in_enable,
    input wire signed [BITWIDTH-1:0] in_data,
    input wire signed [BITWIDTH-1:0] skip_data,
    output reg out_enable,
    output reg signed [BITWIDTH-1:0] out_data
);

    // ------------------------------------
    // Fixed-point arithmetic
    // ------------------------------------
    reg pending_enable;
    reg signed [BITWIDTH-1:0] pending_data;
    // skip_data must address the same feature as in_data on this enabled clock.
    wire signed [BITWIDTH:0] sum = in_data + skip_data;
    wire overflow = sum[BITWIDTH] ^ sum[BITWIDTH-1];
    wire [BITWIDTH-1:0] limit = {sum[BITWIDTH], {(BITWIDTH-1){~sum[BITWIDTH]}}};
    wire [BITWIDTH-1:0] saturated = overflow ? limit : sum[BITWIDTH-1:0];

    always @(posedge clk or negedge nrst) begin
        if (!nrst) begin
            pending_enable <= 0;
            pending_data <= 0;
            out_enable <= 0;
            out_data <= 0;
        end else begin
            pending_enable <= in_enable;
            if (in_enable)
                pending_data <= enable ? saturated : in_data;

            out_enable <= pending_enable;
            if (pending_enable) out_data <= pending_data;
        end
    end
endmodule

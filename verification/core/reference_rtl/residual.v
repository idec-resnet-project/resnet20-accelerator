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
    function automatic signed [BITWIDTH-1:0] saturate(input signed [63:0] value);
        reg signed [63:0] limit;
        begin
            limit = 64'sd1 <<< (BITWIDTH-1);
            if (value >= limit) saturate = limit - 1;
            else if (value < -limit) saturate = -limit;
            else saturate = value;
        end
    endfunction

    reg pending_enable;
    reg signed [BITWIDTH-1:0] pending_data;
    // skip_data must address the same feature as in_data on this enabled clock.
    wire signed [63:0] main_extended = $signed(in_data);
    wire signed [63:0] skip_extended = $signed(skip_data);

    always @(posedge clk or negedge nrst) begin
        if (!nrst) begin
            pending_enable <= 0;
            pending_data <= 0;
            out_enable <= 0;
            out_data <= 0;
        end else begin
            pending_enable <= in_enable;
            if (in_enable)
                pending_data <= enable ? saturate(main_extended + skip_extended) : in_data;

            out_enable <= pending_enable;
            if (pending_enable) out_data <= pending_data;
        end
    end
endmodule

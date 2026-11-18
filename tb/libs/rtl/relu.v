// Same-clock, valid-only stream. Configuration stays stable until drained.
module relu #(parameter integer BITWIDTH = 16)(
    input wire clk,
    input wire nrst,
    input wire enable,
    input wire in_enable,
    input wire signed [BITWIDTH-1:0] in_data,
    output reg out_enable,
    output reg signed [BITWIDTH-1:0] out_data
);

    reg pending_enable;
    reg signed [BITWIDTH-1:0] pending_data;

    always @(posedge clk or negedge nrst) begin
        if (!nrst) begin
            pending_enable <= 0;
            pending_data <= 0;
            out_enable <= 0;
            out_data <= 0;
        end else begin
            pending_enable <= in_enable;
            if (in_enable)
                pending_data <= (enable && in_data[BITWIDTH-1]) ? {BITWIDTH{1'b0}} : in_data;

            out_enable <= pending_enable;
            if (pending_enable) out_data <= pending_data;
        end
    end
endmodule


`timescale 1ns/1ps

module relu #(parameter integer BITWIDTH = 16)(
    input  wire                       clk,
    input  wire                       nrst,
    input  wire                       enable,
    input  wire                       in_enable,
    input  wire signed [BITWIDTH-1:0] in_data,
    output reg                        out_enable,
    output reg signed [BITWIDTH-1:0]  out_data
);

// NEW: Pipeline registers
reg signed [BITWIDTH-1:0] relu_reg;
reg valid_reg;

always @(posedge clk or negedge nrst) begin
    if (!nrst) begin
        out_data   <= 0;
        out_enable <= 0;
        relu_reg   <= 0;  // NEW
        valid_reg  <= 0;  // NEW
    end

    else begin

        // NEW: Stage 1 - ReLU
        valid_reg <= in_enable;

        if (in_enable) begin
            if (!enable) begin
                relu_reg <= in_data;  // Bypass
            end
            else begin
                if (in_data < 0) begin
                    relu_reg <= 0;
                end
                else begin
                    relu_reg <= in_data;
                end
            end
        end

        out_enable <= valid_reg;

        if (valid_reg) begin
            out_data <= relu_reg;
        end
    end
end

endmodule

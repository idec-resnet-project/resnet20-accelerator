`timescale 1ns/1ps
// Interface placeholder. Ports match rtl_dummy/residual.v.
module residual #(parameter integer BITWIDTH = 16)(
    input  wire                       clk,
    input  wire                       nrst,
    input  wire                       enable,
    input  wire                       in_enable,
    input  wire signed [BITWIDTH-1:0] in_data,
    input  wire signed [BITWIDTH-1:0] skip_data,
    output reg                        out_enable,
    output reg signed  [BITWIDTH-1:0] out_data
);
wire signed [BITWIDTH:0]  res_sum;
assign res_sum = in_data + skip_data;

always @(posedge clk or negedge nrst) begin
    if (!nrst) begin
        out_data   <= 0;
        out_enable <= 0;
    end
    else if (in_enable) begin
        out_enable <= 1;
        if (!enable) begin
            out_data <= in_data;              // Bypass
        end
        else begin
            if (res_sum > (2**(BITWIDTH-1))-1) begin
                out_data <= (2**(BITWIDTH-1))-1;              // Saturation
            end
            else if (res_sum < -2**(BITWIDTH-1)) begin
                out_data <= -2**(BITWIDTH-1);             // Saturation
            end
            else begin
                out_data <= res_sum; // Residual sum
            end
        end
    end
    else begin
        out_enable <= 0;
    end
end


endmodule

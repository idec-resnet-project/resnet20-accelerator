`timescale 1ns/1ps
// Interface placeholder. Ports match rtl_dummy/relu.v.
module relu #(parameter integer BITWIDTH = 16)(
    input  wire                       clk,
    input  wire                       nrst,
    input  wire                       enable,
    input  wire                       in_enable,
    input  wire signed [BITWIDTH-1:0] in_data,
    output reg                       out_enable,
    output reg signed [BITWIDTH-1:0] out_data
);

always @(posedge clk or negedge nrst) begin
   if (!nrst) begin       
        out_data         <= 0;
        out_enable        <= 0;
    end
    else if (in_enable) begin
        out_enable        <= 1;
        if (!enable) begin
            out_data         <= in_data;
        end
        else begin
            if (in_data < 0) begin
                out_data         <= 0;
            end
            else begin
            out_data         <= in_data;
            end
        end
    end
    else begin
        out_enable        <= 0;
    end
end

endmodule
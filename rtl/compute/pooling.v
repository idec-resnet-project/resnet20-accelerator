`timescale 1ns/1ps
// Interface placeholder.
module pooling #(
    parameter integer BITWIDTH = 16,
    parameter integer BITWIDTH_POOLING_ITERATION = 16
)(
    input  wire                                         clk,
    input  wire                                         nrst,
    input  wire                                         enable,
    input  wire        [BITWIDTH_POOLING_ITERATION-1:0] iteration,
    input  wire                                         in_enable,
    input  wire signed [BITWIDTH-1:0]                   in_data,
    output reg                                          out_enable,
    output reg signed  [BITWIDTH-1:0]                   out_data
);

reg signed [BITWIDTH-1:0] max_reg;
reg [BITWIDTH_POOLING_ITERATION-1:0] count;

always @(posedge clk or negedge nrst) begin
	if (!nrst) begin       
        out_data         <= 0;
        out_enable       <= 0;
        max_reg          <= 0;
        count            <= 0;
    end

    else begin
        out_enable        <= 0;

        if (in_enable) begin
            if (!enable) begin //bypass
                out_data         <= in_data;
                out_enable       <= 1;
                count            <= 0;
            end
        
            else if (count >= iteration-1) begin
                out_data     <= (in_data > max_reg) ? in_data : max_reg;
                count        <= 0;
                out_enable   <= 1;
            end
                        
            else if (count == 0) begin
                max_reg <= in_data;
                count   <= count + 1;
            end

            else begin
                max_reg <= (in_data > max_reg) ? in_data : max_reg;
                count <= count + 1;
            end
        end
    end
end

endmodule
`timescale 1ns/1ps
// Interface placeholder.
module general_average_pooling #(
    parameter integer BITWIDTH = 16,
    parameter integer BITWIDTH_GAP_ITERATION = 16
)(
    input  wire                                     clk,
    input  wire                                     nrst,
    input  wire                                     enable,
    input  wire        [BITWIDTH_GAP_ITERATION-1:0] iteration,
    input  wire                                     in_enable,
    input  wire signed [BITWIDTH-1:0]               in_data,
    output reg                                      out_enable,
    output reg signed  [BITWIDTH-1:0]               out_data
);

reg signed [2*BITWIDTH-1:0] sum_reg;
reg [BITWIDTH_GAP_ITERATION-1:0] count;

wire signed [2*BITWIDTH-1:0] total_sum;
wire signed [BITWIDTH_GAP_ITERATION:0] divisor;

assign total_sum = sum_reg + in_data;
assign divisor = $signed({1'b0, iteration});

always @(posedge clk or negedge nrst) begin
	if (!nrst) begin       
        out_data         <= 0;
        out_enable       <= 0;
        sum_reg          <= 0;
        count            <= 0;
    end

    else begin
        out_enable        <= 0;

        if (in_enable) begin
            if (!enable) begin //bypass
                out_data         <= in_data;
                out_enable       <= 1;
                sum_reg          <= 0;
                count            <= 0;
            end
        
            else if (count >= iteration-1) begin
                out_data <= (total_sum < 0)? 
          -((-total_sum + divisor/2) / divisor)
          :  ((total_sum + divisor/2) / divisor);
          
			          count        <= 0;
                out_enable   <= 1;
            end
                        
            else if (count == 0) begin
                sum_reg <= in_data;
                count   <= count + 1;
            end

            else begin
                sum_reg <= in_data + sum_reg;
                count <= count + 1;
            end
        end
    end
end

endmodule

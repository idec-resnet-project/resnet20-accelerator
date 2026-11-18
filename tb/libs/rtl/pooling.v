// Same-clock, valid-only stream. Configuration stays stable until drained.
module pooling #(
    parameter integer BITWIDTH = 16,
    parameter integer BITWIDTH_POOLING_ITERATION = 16
)(
    input wire clk,
    input wire nrst,
    input wire enable,
    input wire [BITWIDTH_POOLING_ITERATION-1:0] iteration,
    input wire in_enable,
    input wire signed [BITWIDTH-1:0] in_data,
    output reg out_enable,
    output reg signed [BITWIDTH-1:0] out_data
);

    reg signed [BITWIDTH-1:0] maximum;
    reg [BITWIDTH_POOLING_ITERATION-1:0] input_count;
    reg pending_enable;
    reg signed [BITWIDTH-1:0] pending_data;
    wire signed [BITWIDTH-1:0] next_maximum =
        (input_count == 0 || in_data > maximum) ? in_data : maximum;

    always @(posedge clk or negedge nrst) begin
        if (!nrst) begin
            pending_enable <= 0;
            pending_data <= 0;
            out_enable <= 0;
            out_data <= 0;
            maximum <= 0;
            input_count <= 0;
        end else begin
            out_enable <= pending_enable;
            if (pending_enable) out_data <= pending_data;

            pending_enable <= 0;
            if (in_enable) begin
                if (!enable) begin
                    input_count <= 0;
                    pending_data <= in_data;
                    pending_enable <= 1;
                end else if (input_count == iteration - 1'b1) begin
                    pending_data <= next_maximum;
                    pending_enable <= 1;
                    input_count <= 0;
                end else begin
                    maximum <= next_maximum;
                    input_count <= input_count + 1'b1;
                end
            end
        end
    end
endmodule

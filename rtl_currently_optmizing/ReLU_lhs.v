`timescale 1ns / 1ps
module ReLU
#(
parameter integer WORD_W = 16
)
(
    input wire                      clk,
    input wire                      rst_n,
    input wire                      enable,
    input wire                      valid_in,

    input wire signed [WORD_W-1:0]  data_in,

    output reg                      valid_out,
    output reg signed [WORD_W-1:0]  data_out
    );
    always @(posedge clk or negedge rst_n)
    begin
        if(!rst_n)
        begin
            valid_out  <= 0;
            data_out    <= 0;
        end
        else if(enable && valid_in)
            begin
                valid_out <= 1;
                data_out   <= (valid_in && data_in[WORD_W-1]) ? 0 : data_in;

            end

         else
            valid_out  <= 0;
     end
endmodule
`timescale 1ns / 1ps

module post_mac #(
    parameter integer WORD_W = 16, 
    parameter integer ACC_W  = WORD_W*2+1
)(
    input   wire                     clk,
    input   wire                     rst_n,
    input   wire                     valid_in,    
    input   wire signed [ACC_W:0]  data_in,
    output  reg                      valid_out,
    output  reg  signed [WORD_W-1:0] data_out
);

    localparam integer Q_SCALE = 8;

    localparam signed [WORD_W-1:0] INT_MAX = {1'b0, {(WORD_W-1){1'b1}}}; 
    localparam signed [WORD_W-1:0] INT_MIN = {1'b1, {(WORD_W-1){1'b0}}}; 

    localparam signed [Q_SCALE:0] M_Q = {1'b0, 1'b0, {(Q_SCALE-1){1'b1}}}; 
    localparam signed [Q_SCALE:0] P_Q = {1'b0, 1'b1, {(Q_SCALE-1){1'b0}}}; 

    
    wire signed [ACC_W:0]         data_ext = {data_in[ACC_W-1], data_in};
    wire signed [Q_SCALE:0]       bias     = data_in[ACC_W-1] ? M_Q : P_Q;
    wire signed [ACC_W-Q_SCALE:0] shifted  = (data_ext + bias) >>> Q_SCALE;

    
    always @(posedge clk or negedge rst_n) 
    begin
        if (!rst_n) 
            begin
                data_out    <= {WORD_W{1'b0}};
                valid_out   <= 0;
            end 
        else 
            if(valid_in)
            begin
                if (shifted > INT_MAX)
                    data_out <= INT_MAX;
                else if (shifted < INT_MIN)
                    data_out <= INT_MIN;
                else
                    data_out <= shifted[WORD_W-1:0];
                valid_out <= 1;
            end
            
            else
                begin
                    valid_out <= 0;
                    data_out  <= {WORD_W{1'b0}};
                end
    end

endmodule
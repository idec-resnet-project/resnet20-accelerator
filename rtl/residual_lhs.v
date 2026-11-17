`timescale 1ns / 1ps

module residual_unit
#(
    parameter integer WORD_W = 16
) 
(
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     enable,
    //input  wire                     valid_in,
    input  wire signed [WORD_W-1:0] data_in,
    input  wire signed [WORD_W-1:0] data_skip,

    output reg                      valid_out,
    output reg  signed [WORD_W-1:0] data_out
);
    
    localparam signed [WORD_W-1:0] INT_MAX = {1'b0, {(WORD_W-1){1'b1}}};
    localparam signed [WORD_W-1:0] INT_MIN = {1'b1, {(WORD_W-1){1'b0}}};
    
    localparam signed [WORD_W:0] SAT_MAX = {2'b00, {(WORD_W-1){1'b1}}};
    localparam signed [WORD_W:0] SAT_MIN = {2'b11, {(WORD_W-1){1'b0}}};
    
    reg signed [WORD_W-1:0] data_x;
    reg signed [WORD_W-1:0] data_y;
    reg signed [WORD_W:0]   data_add;
    reg                     proc;
    reg                     done;

    always @(posedge clk or negedge rst_n) 
    begin
        if (!rst_n) 
        begin
            data_x    <= {WORD_W{1'b0}};
            data_y    <= {WORD_W{1'b0}};
            data_add  <= {(WORD_W+1){1'b0}};
            data_out  <= {WORD_W{1'b0}};
            proc      <= 1'b0;
            done      <= 1'b0;
            valid_out <= 1'b0;
        end 
        else
        begin
            // stage 1 : 입력 저장
            proc <= enable /*&& valid_in*/;
            if (enable /*&& valid_in*/)
            begin
                data_x <= data_in;
                data_y <= data_skip;
            end

            
            done <= proc;
            if (proc)
                data_add <= data_x + data_y;

            
            valid_out <= done;
            if (done)
            begin
                if (data_add < SAT_MIN)
                    data_out <= INT_MIN;
                else if (data_add > SAT_MAX)
                    data_out <= INT_MAX;
                else
                    data_out <= data_add[WORD_W-1:0];
            end
        end
    end
endmodule
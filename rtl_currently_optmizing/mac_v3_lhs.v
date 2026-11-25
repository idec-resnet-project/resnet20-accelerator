`timescale 1ns / 1ps

module mac_v3
#(
    parameter integer WORD_W   = 16,
    parameter integer ACC_W    = WORD_W*2+1,
    parameter integer ITER_CNT = 5,
    parameter integer Q_SCALE  = 10
)
(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         enable,
    input  wire                         valid_in,
    input  wire        [ITER_CNT-1:0]   iter,
    input  wire signed [WORD_W-1:0]     fmap_in,
    input  wire signed [WORD_W-1:0]     weight_in,
    input  wire signed [WORD_W-1:0]     bias_in,

    output reg                          proc,
    output reg                          valid_out,
    output reg  signed [ACC_W:0]        data_out
);

    reg signed [WORD_W-1:0]    fmap;
    reg signed [WORD_W-1:0]    weight;
    //reg signed [WORD_W-1:0]    bias;
    reg signed [WORD_W*2-1:0]  multi;
    reg signed [ACC_W:0]       acc;
    reg        [ITER_CNT-1:0]  iter_cnt;
    reg        [ITER_CNT-1:0]  iter_reg;
    reg                        iter_load;
    //reg                        proc;
    
    always @(posedge clk)
        begin
            if (!rst_n)
                begin
                    iter_cnt  <= {ITER_CNT{1'b0}};
                    iter_reg  <= {ITER_CNT{1'b0}};
                    proc      <= 1'b0;
                    valid_out <= 1'b0;
                    iter_load <= 1'b0;
                end
            else
                begin
                    if (enable && valid_in)
                        begin
                            iter_reg  <= iter;
                            iter_cnt  <= {{(ITER_CNT-1){1'b0}}, 1'b1};
                            proc      <= 1'b1;
                            valid_out <= 1'b0;                            
                        end
                    if (proc)
                        begin
                            if (iter_cnt <= iter_reg+1)
                                begin
                                    iter_cnt  <= iter_cnt + 1'b1;
                                    valid_out <= 1'b0;
                                end
                            else
                                begin

                                    iter_cnt  <= {ITER_CNT{1'b0}};
                                    proc      <= 1'b0;
                                    valid_out <= 1'b1;
                                end
                        end
                    else
                        begin
                            valid_out <= 1'b0;
                        end
                end
        end

    always @(posedge clk)
    begin
        if (!rst_n)
            begin
                fmap     <= {WORD_W{1'b0}};
                weight   <= {WORD_W{1'b0}};
                multi    <= {(WORD_W*2){1'b0}};
                acc      <= {(ACC_W+1){1'b0}};
                //bias     <= {WORD_W{1'b0}};
                data_out <= {(ACC_W+1){1'b0}};
            end

        else
            begin
                if (enable && valid_in)
                    begin
                        //bias     <= bias_in;
                        fmap     <= fmap_in;
                        weight   <= weight_in;
                        multi    <= $signed(fmap) * $signed(weight);
                        acc      <= {{(ACC_W+1-WORD_W-Q_SCALE){bias_in[WORD_W-1]}}, bias_in, {Q_SCALE{1'b0}}}; //acc + multi;
                        data_out <= {(ACC_W+1){1'b0}};
                    end
                if (proc)
                    begin
                        if (iter_cnt <= iter_reg+1)
                            begin
                                fmap   <= fmap_in;
                                weight <= weight_in;
                                multi  <= $signed(fmap) * $signed(weight);
                                acc    <= acc + multi;
                            end

                        else
                            begin
                                data_out <= acc;
                                acc      <= multi + bias_in;
                                multi    <= $signed(fmap) * $signed(weight);
                                fmap     <= fmap_in;
                                weight   <= weight_in;
                            end
                    end
                else
                    begin
                        data_out <= {(ACC_W+1){1'b0}};
                        //fmap     <= 0;//fmap_in;
                        //weight   <= 0;//weight_in;
                        multi    <= {(WORD_W*2){1'b0}};
                        acc      <= {(ACC_W+1){1'b0}};
                    end

            end
    end

endmodule
`timescale 1ns / 1ps

module mac_v3 
#(
    parameter integer WORD_W   = 16,
    parameter integer ACC_W    = WORD_W*2+1, 
    parameter integer ITER_CNT = 5   
)
(
    input  wire                         clk, 
    input  wire                         rst_n,
    input  wire                         enable,
    input  wire        [ITER_CNT-1:0]   iter,
    input  wire signed [WORD_W-1:0]     fmap_in,
    input  wire signed [WORD_W-1:0]     weight_in,
    
    output reg                          proc,
    output reg                          valid_out,
    output reg  signed [ACC_W:0]        data_out
);

    reg signed [WORD_W-1:0]    fmap;
    reg signed [WORD_W-1:0]    weight;
    reg signed [WORD_W*2-1:0]  multi;
    reg signed [ACC_W:0]       acc;
    reg        [ITER_CNT-1:0]  iter_cnt;
    reg        [ITER_CNT-1:0]  iter_reg;
    //reg                        proc;

    //=======================================================================
    // Iteration count Logic
    //=======================================================================
    always @(posedge clk or negedge rst_n) 
        begin
    //=======================================================================
    // Reset Logic
    //=======================================================================
            if (!rst_n) 
                begin
                    iter_cnt  <= {ITER_CNT{1'b0}};
                    iter_reg  <= {ITER_CNT{1'b0}};
                    proc      <= 1'b0;
                    valid_out <= 1'b0;
                end 
    //=======================================================================
    // Iteration count Logic
    //=======================================================================
            else 
                begin
    //=======================================================================
    // when valid input(enable) is high
    // set iter_cnt to 1 and proc(processing register) to high
    //=======================================================================
                    if (enable && !proc) 
                        begin                
                            iter_reg  <= iter;
                            iter_cnt  <= {{(ITER_CNT-1){1'b0}}, 1'b1};
                            proc      <= 1'b1;
                            valid_out <= 1'b0;
                        end 
                    else if (proc) 
                        begin
    //=======================================================================
    // while processing, update iteration count
    // when iter_cnt is lower than iter_reg+1, no valid output, top module output is 0
    //=======================================================================
                            if (iter_cnt <= iter_reg+1) 
                                begin
                                    iter_cnt  <= iter_cnt + 1'b1;
                                    valid_out <= 1'b0;
                                end 
    //=======================================================================
    // when iter_cnt is higher than iter_reg+1, 
    // processing is done, set proc to low, valid output is high
    //=======================================================================   
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

    //=======================================================================
    // MAC Logic
    //=======================================================================   
    always @(posedge clk) 
    begin
    //=======================================================================
    // Sync Reset Logic for dsp unit
    //=======================================================================
        if (!rst_n) 
            begin
                fmap     <= {WORD_W{1'b0}};
                weight   <= {WORD_W{1'b0}};
                multi    <= {(WORD_W*2){1'b0}};
                acc      <= {(ACC_W+1){1'b0}};
                data_out <= {(ACC_W+1){1'b0}};
            end 
    
        else 
            begin
    //=======================================================================
    // intiate MAC, load input data, multiply and accumulate
    //=======================================================================   
                
                if (enable && !proc) 
                    begin
                        fmap     <= fmap_in;
                        weight   <= weight_in;
                        multi    <= $signed(fmap) * $signed(weight);
                        acc      <= acc + multi;
                        data_out <= {(ACC_W+1){1'b0}};
                    end 
    //=======================================================================
    // while processing, load input data, multiply and accumulate
    // if iter_cnt is 1 reset acc reg to 0, else accumulate
    // when iter_cnt is higher than iter_reg+1, 
    //output the accumulated data and reset acc and multi reg to 0
    //=======================================================================                
                else if (proc) 
                    begin
                        if (iter_cnt <= iter_reg+1) 
                            begin                
                                fmap   <= fmap_in;
                                weight <= weight_in;
                                multi  <= $signed(fmap) * $signed(weight);
                                acc    <= (iter_cnt == 1) ? 0 : acc + multi;
                            end 
                        
                        else 
                            begin
                                data_out <= acc; 
                                acc      <= {(ACC_W+1){1'b0}};
                                multi    <= {(WORD_W*2){1'b0}};
                            end
                    end
    //=======================================================================
    // when not processing, output is 0, reset acc and multi reg to 0
    //=======================================================================             
                else 
                    begin
                        data_out <= {(ACC_W+1){1'b0}};
                        fmap     <= fmap_in;
                        weight   <= weight_in;
                        multi    <= {(WORD_W*2){1'b0}};
                        acc      <= {(ACC_W+1){1'b0}};
                    end
                
            end
    end

endmodule
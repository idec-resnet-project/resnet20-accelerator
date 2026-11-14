
assign fmem_rd_addr_temp = cnt_run[BRAM_FEATRE_CAPACITY-1:0];
assign fmem_rd_addr[0]   = cnt_run[BRAM_FEATRE_CAPACITY-1:0];
assign fmem_rd_addr[1]   = cnt_run[BRAM_FEATRE_CAPACITY-1:0];
assign kmem_rd_addr      = cnt_run[BRAM_KERNEL_CAPACITY-1:0];
assign bmem_rd_addr      = cnt_run[BRAM_BIAS_CAPACITY-1:0];
assign rmem_rd_addr      = cnt_run[BRAM_FEATRE_CAPACITY-1:0];

always_ff @(negedge clk or posedge nrst) begin
    if (!nrst)                  kernel_row <= 0;
    else if (cstate == RUN) begin
        if (kernel_row == kw)   kernel_row <= '0;
        else                    kernel_row <= kernel_row + 1;
    end else                    kernel_row <= '0;
end 

always_ff @(negedge clk or posedge nrst) begin
    if (!nrst)                      kernel_col <= 0;
    else if (cstate == RUN) begin
        if (kernel_col == kw)       kernel_col <= '0;
        else if (kernel_row == kw)  kernel_col <= kernel_col + 1;
        else                        kernel_col <= kernel_col;
    end else                        kernel_col <= '0;
end 

always_ff @(negedge clk or posedge nrst) begin
    if (!nrst)                      in_channel <= 0;
    else if (cstate == RUN) begin
        if (in_channel == fc)       in_channel <= '0;
        else if (kernel_col == kw)  in_channel <= in_channel + 1;
        else                        in_channel <= in_channel;
    end else                        in_channel <= '0;
end 

always_ff @(negedge clk or posedge nrst) begin
    if (!nrst)                      feature_row <= 0;
    else if (cstate == RUN) begin
        if (feature_row == fw)      feature_row <= '0;
        else if (in_channel == fc)  feature_row <= feature_row + 1;
        else                        feature_row <= feature_row;
    end else                        feature_row <= '0;
end 

always_ff @(negedge clk or posedge nrst) begin
    if (!nrst)                      feature_col <= 0;
    else if (cstate == RUN) begin
        if (feature_col == fw)      feature_col <= '0;
        else if (feature_row == fw) feature_col <= feature_col + 1;
        else                        feature_col <= feature_col;
    end else                        feature_col <= '0;
end 

always_ff @(negedge clk or posedge nrst) begin
    if (!nrst)                      out_channel <= 0;
    else if (cstate == RUN) begin
        if (out_channel == kc)      out_channel <= '0;
        else if (feature_col == fw) out_channel <= out_channel + 1;
        else                        out_channel <= out_channel;
    end else                        out_channel <= '0;
end 
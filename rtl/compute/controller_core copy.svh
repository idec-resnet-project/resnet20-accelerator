// core configure
assign in_enable = (cstate == RUN) & (cnt_run != len_feature+1);

assign mac_iteration = (ctrl_kw+1)*(ctrl_kw+1)*(ctrl_fc+1);
assign gap_iteration = (ctrl_fw+1)*(ctrl_fw+1);

assign core_in_f_addr  = {addr_cin, addr_frow, addr_fcol};
assign core_in_k_addr  = {addr_krow, addr_kcol, addr_cin, addr_cout};
assign core_in_b_addr  = {addr_cin};
assign core_out_f_addr = {addr_cout, addr_frow, addr_fcol}

// fmem
assign fmem_wr_enable[0] = (is_fmem0_in) ? 0 : (out_enable | dma_feature_hk);
assign fmem_wr_enable[1] = (is_fmem0_in) ? (out_enable | dma_feature_hk) : 0;
assign fmem_wr_addr[0]   = (is_fmem0_in) ? core_out_f_addr : '0;
assign fmem_wr_addr[1]   = (~is_fmem0_in) ? core_out_f_addr : '0;
assign fmem_rd_addr_temp = addr_frow + ctrl_fw * (addr_fcol + ctrl_fw * addr_cin);
assign fmem_rd_addr[0]   = (is_fmem0_in) ? fmem_rd_addr_temp :cnt_feature[BRAM_FEATRE_CAPACITY-1:0];
assign fmem_rd_addr[1]   = (is_fmem0_in) ? cnt_feature[BRAM_FEATRE_CAPACITY-1:0] : fmem_rd_addr_temp;

// kernel
assign kmem_wr_enable    = dma_kernel_hk;
assign kmem_rd_addr      = core_in_k_addr;
assign kmem_wr_addr      = core_in_k_addr;

assign bmem_wr_enable    = dma_bias_hk;
assign bmem_rd_addr      = core_in_b_addr;
assign bmem_wr_addr      = core_in_b_addr;

assign rmem_wr_enable    = (ctrl_is_skip) ? out_enable : 0;
assign rmem_wr_addr      = (~is_fmem0_in) ? core_in_f_addr : '0;
assign rmem_rd_addr      = (is_fmem0_in) ? fmem_rd_addr_temp :cnt_feature[BRAM_FEATRE_CAPACITY-1:0];


always_ff @(negedge clk or posedge nrst) begin : KERNEK_ROW
    if (!nrst)                  addr_krow <= 0;
    else if (cstate == IN_KERNEL) begin
        if (addr_krow == ctrl_kw)    addr_krow <= '0;
        else if (dma_kernel_hk)      addr_krow <= addr_krow + 1;
        else                         addr_krow <= addr_krow;
    end 
    else if (cstate == RUN) begin
        if (addr_krow == ctrl_kw)    addr_krow <= '0;
        else                         addr_krow <= addr_krow + 1;
    end 
    else                         addr_krow <= '0;
end 

always_ff @(negedge clk or posedge nrst) begin : KERNEK_COL
    if (!nrst)                           addr_kcol <= 0;
    else if (cstate == RUN | cstate == IN_KERNEL) begin
        if (addr_kcol == ctrl_kw & addr_krow == ctrl_kw)        addr_kcol <= '0;
        else if (addr_krow == ctrl_kw)   addr_kcol <= addr_kcol + 1;
        else                             addr_kcol <= addr_kcol;
    end 
    else                             addr_kcol <= '0;
end 

always_ff @(negedge clk or posedge nrst) begin : FEATURE_ROW
    if (!nrst)                      addr_frow <= 0;
    else if (cstate == IN_FEATURE) begin
        if (dma_feature_hk) begin
            if (addr_frow == ctrl_fw)      addr_frow <= '0;
            else                           addr_frow <= addr_frow + 1;
        end 
        else                           addr_frow <= addr_frow;
    end 
    else if (cstate == RUN) begin
        if (addr_frow == ctrl_fw & addr_cin == ctrl_fc)      addr_frow <= '0;
        else if (addr_cin == ctrl_fc)  addr_frow <= addr_frow + 1;
        else                           addr_frow <= addr_frow;
    end 
    else                        addr_frow <= '0;
end 

always_ff @(negedge clk or posedge nrst) begin : FEATURE_COL
    if (!nrst)                      addr_fcol <= 0;
    else if (cstate == IN_FEATURE) begin
        if (dma_feature_hk) begin
            if (addr_fcol == ctrl_fw & addr_frow == ctrl_fw)      addr_fcol <= '0;
            else if (addr_frow == ctrl_fw)                        addr_fcol <= addr_fcol + 1;
            else                                                  addr_fcol <= addr_fcol;  
        end else                                                  addr_fcol <= addr_fcol;
    end                       
    else if (cstate == RUN) begin
        if (addr_fcol == ctrl_fw & addr_frow == ctrl_fw)      addr_fcol <= '0;
        else if (addr_frow == ctrl_fw) addr_fcol <= addr_fcol + 1;
        else                        addr_fcol <= addr_fcol;

    end else                        addr_fcol <= '0;
end 

always_ff @(negedge clk or posedge nrst) begin : CHANNEL_IN
    if (!nrst)                      addr_cin <= 0;
    else if (cstate == IN_BIAS) begin
        if (addr_cin == ctrl_fc)       addr_cin <= '0;
        else if (dma_bias_hk)  addr_cin <= addr_cin + 1;
        else                        addr_cin <= addr_cin;
    end 
    else if (cstate == IN_FEATURE) begin
        if (addr_fcol == ctrl_fw) begin
            if   (addr_frow == ctrl_fw & dma_feature_hk) begin
                if   (addr_cin == ctrl_fc)     addr_cin <= '0;
                else                           addr_cin <= addr_cin + 1;
            end
            else                               addr_cin <= addr_cin;
        end 
        else                        addr_cin <= addr_cin;
    end 
    else if (cstate == RUN | cstate == IN_KERNEL) begin
        if (addr_cin == ctrl_fc & addr_kcol == ctrl_kw)       addr_cin <= '0;
        else if (addr_kcol == ctrl_kw)  addr_cin <= addr_cin + 1;
        else                        addr_cin <= addr_cin;
    end 
    else                        addr_cin <= '0;
end 

always_ff @(negedge clk or posedge nrst) begin : CHANNEL_OUT
    if (!nrst)                      addr_cout <= 0;
    else if (cstate == IN_KERNEL) begin
        if (addr_cout == ctrl_kc & addr_cin == ctrl_fc)      addr_cout <= '0;
        else if (addr_cin == ctrl_fc) addr_cout <= addr_cout + 1;
        else                        addr_cout <= addr_cout;
    end else if (cstate == RUN) begin
        if (addr_cout == ctrl_kc & addr_fcol == ctrl_fw)      addr_cout <= '0;
        else if (addr_fcol == ctrl_fw) addr_cout <= addr_cout + 1;
        else                        addr_cout <= addr_cout;
    end else                        addr_cout <= '0;
end 
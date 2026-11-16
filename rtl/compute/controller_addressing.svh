// local variables
reg [5:0] addr_frow;
reg [5:0] addr_fcol;
reg [5:0] addr_cin;
reg [5:0] addr_krow;
reg [5:0] addr_kcol;
reg [5:0] addr_cout; 

wire [BRAM_FEATRE_CAPACITY-1:0] core_in_f_addr;
wire [BRAM_FEATRE_CAPACITY-1:0] core_in_k_addr;
wire [BRAM_FEATRE_CAPACITY-1:0] core_in_b_addr;
wire [BRAM_KERNEL_CAPACITY-1:0] core_out_f_addr;

wire [BRAM_FEATRE_CAPACITY-1:0]fmem_rd_addr_temp;

assign core_in_f_addr  = {addr_cin, addr_frow, addr_fcol};
assign core_in_k_addr  = {addr_krow, addr_kcol, addr_cin, addr_cout};
assign core_in_b_addr  = {addr_cin};

assign fmem_rd_addr_temp = addr_frow + fw * (addr_fcol + fw * addr_cin);
assign fmem_rd_addr[0]   = (is_fmem0_in) ? fmem_rd_addr_temp :cnt_feature[BRAM_FEATRE_CAPACITY-1:0];
assign fmem_rd_addr[1]   = (is_fmem0_in) ? cnt_feature[BRAM_FEATRE_CAPACITY-1:0] : fmem_rd_addr_temp;
assign kmem_rd_addr      = cnt_run[BRAM_KERNEL_CAPACITY-1:0];
assign bmem_rd_addr      = cnt_run[BRAM_BIAS_CAPACITY-1:0];
assign rmem_rd_addr      = cnt_run[BRAM_FEATRE_CAPACITY-1:0];


always_ff @(negedge clk or posedge nrst) begin
    if (!nrst)                  addr_krow <= 0;
    else if (cstate == RUN) begin
        if (addr_krow == kw)    addr_krow <= '0;
        else                    addr_krow <= addr_krow + 1;
    end else                    addr_krow <= '0;
end 

always_ff @(negedge clk or posedge nrst) begin
    if (!nrst)                      addr_kcol <= 0;
    else if (cstate == RUN) begin
        if (addr_kcol == kw)        addr_kcol <= '0;
        else if (addr_krow == kw)   addr_kcol <= addr_kcol + 1;
        else                        addr_kcol <= addr_kcol;
    end else                        addr_kcol <= '0;
end 

always_ff @(negedge clk or posedge nrst) begin
    if (!nrst)                      addr_cin <= 0;
    else if (cstate == RUN) begin
        if (addr_cin == fc)       addr_cin <= '0;
        else if (addr_kcol == kw)  addr_cin <= addr_cin + 1;
        else                        addr_cin <= addr_cin;
    end else                        addr_cin <= '0;
end 

always_ff @(negedge clk or posedge nrst) begin
    if (!nrst)                      addr_frow <= 0;
    else if (cstate == RUN) begin
        if (addr_frow == fw)      addr_frow <= '0;
        else if (addr_cin == fc)  addr_frow <= addr_frow + 1;
        else                        addr_frow <= addr_frow;
    end else                        addr_frow <= '0;
end 

always_ff @(negedge clk or posedge nrst) begin
    if (!nrst)                      addr_fcol <= 0;
    else if (cstate == RUN) begin
        if (addr_fcol == fw)      addr_fcol <= '0;
        else if (addr_frow == fw) addr_fcol <= addr_fcol + 1;
        else                        addr_fcol <= addr_fcol;
    end else                        addr_fcol <= '0;
end 

always_ff @(negedge clk or posedge nrst) begin
    if (!nrst)                      addr_cout <= 0;
    else if (cstate == RUN) begin
        if (addr_cout == kc)      addr_cout <= '0;
        else if (addr_fcol == fw) addr_cout <= addr_cout + 1;
        else                        addr_cout <= addr_cout;
    end else                        addr_cout <= '0;
end 
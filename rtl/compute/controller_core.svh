// core configure
always_ff @(posedge clk or negedge nrst) begin
    if (!nrst) in_enable <= '0;
    else in_enable <= (cstate == RUN) & (cnt_run != len_feature+1);
end
// counter
reg [ADDR_BITWIDTH-1:0] addr_frow_next;
reg [ADDR_BITWIDTH-1:0] addr_fcol_next;
reg [ADDR_BITWIDTH-1:0] addr_cin_next;
reg [ADDR_BITWIDTH-1:0] addr_krow_next;
reg [ADDR_BITWIDTH-1:0] addr_kcol_next;
reg [ADDR_BITWIDTH-1:0] addr_cout_next;
reg [ADDR_BITWIDTH-1:0] addr_orow_next;
reg [ADDR_BITWIDTH-1:0] addr_ocol_next;
reg [ADDR_BITWIDTH-1:0] addr_oc_next;


wire  addr_frow_carry;
wire  addr_fcol_carry;
wire  addr_cin_carry;
wire  addr_krow_carry;
wire  addr_kcol_carry;
wire  addr_cout_carry;
wire  addr_orow_carry;
wire  addr_ocol_carry;
wire  addr_oc_carry;

wire  addr_frfc_carry;
wire  addr_frfccin_carry;
wire  addr_krkc_carry;
wire  addr_krkccin_carry;
wire  addr_krkccincout_carry;
wire  addr_krkccinfr_carry;
wire  addr_krkccinfrfc_carry;
wire  addr_krkccinfrfccout_carry;
wire  addr_oroc_carry;
wire  addr_orococ_carry;

assign mac_iteration = (ctrl_kw+1)*(ctrl_kw+1)*(ctrl_fc+1);
assign gap_iteration = (ctrl_fw+1)*(ctrl_fw+1);

assign core_in_f_addr  = {addr_cin, addr_fcol_slided[ADDR_BITWIDTH-1:0], addr_frow_slided[ADDR_BITWIDTH-1:0]};
assign core_in_k_addr  = {addr_cout, addr_cin, addr_kcol, addr_krow};
assign core_in_b_addr  = {addr_cout};
assign core_out_f_addr = {addr_oc, addr_ocol, addr_orow};
assign output_read_addr = dma_result_hk ? {addr_oc_next, addr_ocol_next, addr_orow_next} : core_out_f_addr;
assign core_residual_addr = {addr_cout, addr_fcol >> ctrl_stride, addr_frow >> ctrl_stride};
// fmem
assign fmem_rd_addr_temp = addr_frow + ctrl_fw * (addr_fcol + ctrl_fw * addr_cin);
assign fmem_wr_enable[0] = (ctrl_input_enable) ? ((is_fmem0_in)  ? '0 : dma_feature_hk)
                           : ((is_fmem0_in)  ? '0 : out_enable & cstate[5]);
assign fmem_wr_enable[1] = (ctrl_input_enable) ? ((~is_fmem0_in)  ? '0 : dma_feature_hk)
                           : ((~is_fmem0_in)  ? '0 : out_enable & cstate[5]);
assign fmem_wr_addr[0]   = (ctrl_input_enable)  ? core_in_f_addr : core_out_f_addr;
assign fmem_wr_addr[1]   = (ctrl_input_enable)  ? core_in_f_addr : core_out_f_addr;
assign fmem_rd_addr[0]   = (cstate == OUTPUT) ? output_read_addr : core_in_f_addr;
assign fmem_rd_addr[1]   = (cstate == OUTPUT) ? output_read_addr : core_in_f_addr;

// kernel
assign kmem_wr_enable    = dma_kernel_hk;
assign kmem_rd_addr      = core_in_k_addr;
assign kmem_wr_addr      = core_in_k_addr;

assign bmem_wr_enable    = dma_bias_hk;
assign bmem_rd_addr      = core_in_b_addr;
assign bmem_wr_addr      = core_in_b_addr;

assign rmem_wr_enable    =  (ctrl_is_skip) ? out_enable & cstate[5] : '0;
assign rmem_wr_addr      =  core_out_f_addr;
reg [BRAM_FEATRE_CAPACITY-1:0] rmem_rd_addr_buf[LATENCY_RESIDUAL-1:0];
assign rmem_rd_addr      =  rmem_rd_addr_buf[0];


integer i;
always_ff @(posedge clk or negedge nrst) begin : RMEM_RD_ADDR_BUF
    if (!nrst) begin
        for (i=0; i<LATENCY_RESIDUAL; i=i+1) begin
            rmem_rd_addr_buf[i] <= '0;
        end
    end else begin
        rmem_rd_addr_buf[LATENCY_RESIDUAL-1] <=  core_residual_addr;
        for (i=0; i<LATENCY_RESIDUAL-1; i=i+1) begin
            rmem_rd_addr_buf[i] <= rmem_rd_addr_buf[i+1];
        end
    end
end



assign is_skip_connection = cfg_residual_enable;

// counter carry
assign addr_frow_carry  = addr_frow == (ctrl_fw - (ctrl_stride & ctrl_fw[0]));
assign addr_fcol_carry  = addr_fcol == (ctrl_fw - (ctrl_stride & ctrl_fw[0]));
assign addr_cin_carry   = addr_cin  == ctrl_fc;
assign addr_krow_carry  = addr_krow == ctrl_kw;
assign addr_kcol_carry  = addr_kcol == ctrl_kw;
assign addr_cout_carry  = addr_cout == ctrl_kc;
assign addr_orow_carry  = addr_orow == ctrl_ow;
assign addr_ocol_carry  = addr_ocol == ctrl_ow;
assign addr_oc_carry    = addr_oc == ctrl_kc;

assign addr_frfc_carry        = addr_fcol_carry & addr_frow_carry;
assign addr_frfccin_carry     = addr_fcol_carry & addr_frow_carry & addr_cin_carry;
assign addr_krkc_carry        = addr_kcol_carry & addr_krow_carry;
assign addr_krkccin_carry     = addr_krkc_carry & addr_cin_carry;
assign addr_krkccincout_carry = addr_krkccin_carry & addr_cout_carry;
assign addr_krkccinfr_carry         = addr_krkccin_carry & addr_frow_carry;
assign addr_krkccinfrfc_carry       = addr_krkccinfr_carry & addr_fcol_carry;
assign addr_krkccinfrfccout_carry   = addr_krkccinfrfc_carry & addr_cout_carry;
assign addr_oroc_carry    = addr_orow_carry & addr_ocol_carry;
assign addr_orococ_carry  = addr_oroc_carry & addr_oc_carry;

// sliding carry


assign addr_frow_signed = $signed({1'b0, addr_frow});
assign addr_fcol_signed = $signed({1'b0, addr_fcol});


assign slide_frow_carry = addr_frow_slided > ctrl_fw;
assign slide_fcol_carry = addr_fcol_slided > ctrl_fw;

always_ff @(posedge clk or negedge nrst) begin : IS_ZERO
    if (!nrst) begin 
        is_zero <= 0;
    end else begin
        is_zero <= slide_frow_carry | slide_fcol_carry;
    end
end

always_comb begin
    case (cstate)
        IN_FEATURE : begin
            if (dma_feature_hk) begin
                addr_frow_next  = (addr_frow_carry)     ? '0 : addr_frow + 1;
                addr_fcol_next  = (addr_frfc_carry)     ? '0 : addr_fcol + addr_frow_carry;
                addr_cin_next   = (addr_frfccin_carry)  ? '0 : addr_cin  + addr_frfc_carry;
                addr_krow_next  = addr_krow;
                addr_kcol_next  = addr_kcol;
                addr_cout_next  = addr_cout;
                addr_orow_next  = addr_orow;
                addr_ocol_next  = addr_ocol;
                addr_oc_next    = addr_oc;
            end else begin
                addr_frow_next  = addr_frow; 
                addr_fcol_next  = addr_fcol;
                addr_cin_next   = addr_cin;
                addr_krow_next  = addr_krow;
                addr_kcol_next  = addr_kcol;
                addr_cout_next  = addr_cout;
                addr_orow_next  = addr_orow;
                addr_ocol_next  = addr_ocol;
                addr_oc_next    = addr_oc;
            end
        end
        IN_KERNEL : begin
            if (dma_kernel_hk) begin
                addr_frow_next  = addr_frow;
                addr_fcol_next  = addr_fcol;
                addr_cin_next   = (addr_krkccin_carry)      ? '0 : addr_cin  + addr_krkc_carry;
                addr_krow_next  = (addr_krow_carry)         ? '0 : addr_krow + 1;
                addr_kcol_next  = (addr_krkc_carry)         ? '0 : addr_kcol + addr_krow_carry;
                addr_cout_next  = (addr_krkccincout_carry)  ? '0 : addr_cout + addr_krkccin_carry;
                addr_orow_next  = addr_orow;
                addr_ocol_next  = addr_ocol;
                addr_oc_next    = addr_oc;
            end else begin
                addr_frow_next  = addr_frow; 
                addr_fcol_next  = addr_fcol;
                addr_cin_next   = addr_cin;
                addr_krow_next  = addr_krow;
                addr_kcol_next  = addr_kcol;
                addr_cout_next  = addr_cout;
                addr_orow_next  = addr_orow;
                addr_ocol_next  = addr_ocol;
                addr_oc_next    = addr_oc;
            end
        end
        IN_BIAS : begin
            if (dma_bias_hk) begin
                addr_frow_next  = addr_frow;
                addr_fcol_next  = addr_fcol;
                addr_cin_next   = addr_cin;
                addr_krow_next  = addr_krow;
                addr_kcol_next  = addr_kcol;
                addr_cout_next  = (addr_cout_carry) ? '0 : addr_cout + 1;
                addr_orow_next  = addr_orow;
                addr_ocol_next  = addr_ocol;
                addr_oc_next    = addr_oc;
            end else begin
                addr_frow_next  = addr_frow; 
                addr_fcol_next  = addr_fcol;
                addr_cin_next   = addr_cin;
                addr_krow_next  = addr_krow;
                addr_kcol_next  = addr_kcol;
                addr_cout_next  = addr_cout;
                addr_orow_next  = addr_orow;
                addr_ocol_next  = addr_ocol;
                addr_oc_next    = addr_oc;
            end
        end
        RUN : begin
            addr_frow_next  = (addr_krkccinfr_carry)           ? '0 : addr_frow + (addr_krkccin_carry << ctrl_stride);
            addr_fcol_next  = (addr_krkccinfrfc_carry)         ? '0 : addr_fcol + (addr_krkccinfr_carry << ctrl_stride);
            addr_cin_next   = (addr_krkccin_carry)             ? '0 : addr_cin + addr_krkc_carry;
            addr_krow_next  = (addr_krow_carry)                ? '0 : addr_krow + 1;
            addr_kcol_next  = (addr_krkc_carry)                ? '0 : addr_kcol + addr_krow_carry;
            addr_cout_next  = (addr_krkccinfrfccout_carry)     ? '0 : addr_cout + addr_krkccinfrfc_carry;
            addr_orow_next  = (addr_orow_carry   & out_enable) ? '0 : addr_orow + out_enable;
            addr_ocol_next  = (addr_oroc_carry   & out_enable) ? '0 : addr_ocol + (addr_orow_carry & out_enable);
            addr_oc_next    = (addr_orococ_carry & out_enable) ? '0 : addr_oc   + (addr_oroc_carry & out_enable);
        end
        OUTPUT : begin
            if (dma_result_hk || (cnt_dma_output == 0)) begin
                addr_frow_next  = addr_frow; 
                addr_fcol_next  = addr_fcol;
                addr_cin_next   = addr_cin;
                addr_krow_next  = addr_krow;
                addr_kcol_next  = addr_kcol;
                addr_cout_next  = addr_cout;
                addr_orow_next  = (addr_orow_carry)     ? '0 : addr_orow + 1;
                addr_ocol_next  = (addr_oroc_carry)     ? '0 : addr_ocol + addr_orow_carry;
                addr_oc_next    = (addr_orococ_carry)   ? '0  : addr_oc  + addr_oroc_carry;
            end else begin
                addr_frow_next  = addr_frow; 
                addr_fcol_next  = addr_fcol;
                addr_cin_next   = addr_cin;
                addr_krow_next  = addr_krow;
                addr_kcol_next  = addr_kcol;
                addr_cout_next  = addr_cout;
                addr_orow_next  = addr_orow;
                addr_ocol_next  = addr_ocol;
                addr_oc_next    = addr_oc;
            end
        end
        default : begin
                addr_frow_next  = '0; 
                addr_fcol_next  = '0;
                addr_cin_next   = '0;
                addr_krow_next  = '0;
                addr_kcol_next  = '0;
                addr_cout_next  = '0;
                addr_orow_next  = '0;
                addr_ocol_next  = '0;
                addr_oc_next    = '0;
        end 
    endcase
end

always_ff @(posedge clk or negedge nrst) begin : FEATURE_ROW
    if (!nrst) begin
        addr_frow <= 0;
        addr_fcol <= 0;
        addr_cin  <= 0;
        addr_krow <= 0;
        addr_kcol <= 0;
        addr_cout <= 0;
    end else begin
        addr_frow <= addr_frow_next;
        addr_fcol <= addr_fcol_next;
        addr_cin  <= addr_cin_next;
        addr_krow <= addr_krow_next;
        addr_kcol <= addr_kcol_next;
        addr_cout <= addr_cout_next;
        addr_orow <= addr_orow_next;        
        addr_ocol <= addr_ocol_next;
        addr_oc   <= addr_oc_next;        
    end        
end 

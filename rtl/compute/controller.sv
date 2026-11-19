// Jihye independent Controller v0.5 (verified: conv1x1 SNR 54.61 dB, integration TB w/ hyunkeon b79596c top+core)
//   v0.4 + (1) convolution read addressing (nested counters kx->ky->ic->ox->oy->oc)
//          (2) input-side BRAM read latency alignment (in_enable delayed 1 cycle)
//          (3) bias read address = oc
//          (4) port/ping-pong contract of top_bottleneck @ hyunkeon b79596c
//              (is_feature_in, output_init_flag, write->FB[is], read->FB[~is])
// Memory layout (dense, same as DMA stream order):
//   feature [ic][y][x]  addr = (ic*W + y)*W + x
//   kernel  [oc][ic][ky][kx]
//   bias    [oc]
//   result  [oc][y][x]  (core output order)
// TODO: padding zero-insertion (no is_zero path in top yet), pooling schedule.
module controller #(
    parameter integer CONFIG_BITWIDTH            = 32,
    parameter integer CONFIG_DATA_BITWIDTH       = 6,
    parameter integer BITWIDTH_MAC_ITERATION     = 16,
    parameter integer BITWIDTH_POOLING_ITERATION = 16,
    parameter integer BITWIDTH_GAP_ITERATION     = 16,
    parameter integer BRAM_FEATRE_CAPACITY       = 14,
    parameter integer BRAM_KERNEL_CAPACITY       = 16,
    parameter integer BRAM_BIAS_CAPACITY         = 6,
    parameter integer ADDR_BITWIDTH              = 3   // unused (kept for top compatibility)
)(
    input  wire clk, nrst,
    input  wire cfg_enable,
    input  wire [CONFIG_BITWIDTH-1:0] cfg,
    output reg  [3:0] cfg_response,
    output reg  mac_enable, residual_enable, relu_enable, pooling_enable, gap_enable,
    output wire [BITWIDTH_MAC_ITERATION-1:0] mac_iteration,
    output wire [BITWIDTH_POOLING_ITERATION-1:0] pooling_iteration,
    output wire [BITWIDTH_GAP_ITERATION-1:0] gap_iteration,
    output reg  is_fmem0_in,
    output wire is_feature_in,
    output wire output_init_flag,
    output wire in_enable,
    input  wire out_enable,
    input  wire dma_feature_valid,
    output wire dma_feature_ready,
    input  wire dma_feature_last,
    input  wire dma_kernel_valid,
    output wire dma_kernel_ready,
    input  wire dma_kernel_last,
    input  wire dma_bias_valid,
    output wire dma_bias_ready,
    input  wire dma_bias_last,
    output wire dma_result_valid,
    input  wire dma_result_ready,
    output wire dma_result_last,
    output wire fmem_wr_enable[0:1],
    output wire [BRAM_FEATRE_CAPACITY-1:0] fmem_wr_addr[0:1],
    output wire [BRAM_FEATRE_CAPACITY-1:0] fmem_rd_addr[0:1],
    output wire kmem_wr_enable,
    output wire [BRAM_KERNEL_CAPACITY-1:0] kmem_wr_addr, kmem_rd_addr,
    output wire bmem_wr_enable,
    output wire [BRAM_BIAS_CAPACITY-1:0] bmem_wr_addr, bmem_rd_addr,
    output wire rmem_wr_enable,
    output wire [BRAM_FEATRE_CAPACITY-1:0] rmem_wr_addr, rmem_rd_addr
);
    localparam [7:0] IDLE = 8'h01, DECODE = 8'h02,
        IN_FEATURE = 8'h04, IN_KERNEL = 8'h08,
        IN_BIAS = 8'h10, RUN = 8'h20, OUTPUT = 8'h40, ERROR = 8'h80;
    localparam [3:0] RESP_IDLE=4'h0, RESP_DONE=4'h1,
        RESP_INPUT=4'h2, RESP_RUN=4'h4,
        RESP_OUTPUT=4'h6, RESP_ERROR=4'h8;

    reg [7:0] cstate, nstate;
    reg seen_command;
    reg cfg_input_enable, cfg_output_enable, cfg_is_skip, cfg_stride, cfg_padding;
    reg [5:0] size_w, size_h, size_c;
    reg [5:0] fw, fc, kw, kc, ow, oc;   // 0-based: input W,Cin / kernel K,Cout / output W,Cout
    reg [5:0] nw, nc;                   // 0-based size of the map the next main-path command reads
    wire [5:0] conv_ow = ( {26'd0,nw} + (cfg_padding ? 32'd2 : 32'd0) - {26'd0,size_w} ) >> cfg_stride;

    // ------------------------------------------------------------------
    // Lengths
    // ------------------------------------------------------------------
    reg [31:0] cnt_feature, cnt_kernel, cnt_bias, cnt_run, cnt_output, cnt_dma_output;
    wire [31:0] feature_count = (fw+32'd1)*(fw+32'd1)*(fc+32'd1);
    wire [31:0] kernel_count  = (kw+32'd1)*(kw+32'd1)*(fc+32'd1)*(kc+32'd1);
    wire [31:0] bias_count    = kc+32'd1;
    wire [31:0] output_count  = gap_enable ? (oc+32'd1) :
                               (mac_enable ? (ow+32'd1)*(ow+32'd1)*(oc+32'd1) : feature_count);
    wire [31:0] tap_count     = (kw+32'd1)*(kw+32'd1)*(fc+32'd1);
    wire [31:0] gap_count     = (ow+32'd1)*(ow+32'd1);
    wire [31:0] len_feature = feature_count-1;
    wire [31:0] len_kernel  = kernel_count-1;
    wire [31:0] len_bias    = bias_count-1;
    wire [31:0] len_output  = output_count-1;

    assign mac_iteration     = mac_enable ? tap_count[BITWIDTH_MAC_ITERATION-1:0] : '0;
    assign pooling_iteration = (ow+32'd1); // PROVISIONAL
    assign gap_iteration     = gap_enable ? gap_count[BITWIDTH_GAP_ITERATION-1:0] : '0;

    // ------------------------------------------------------------------
    // DMA
    // ------------------------------------------------------------------
    assign dma_feature_ready = (cstate == IN_FEATURE);
    assign dma_kernel_ready  = (cstate == IN_KERNEL);
    assign dma_bias_ready    = (cstate == IN_BIAS);
    // Handshake = valid & ready at the posedge (AXIS definition). BRAM writes use the
    // combinational form (captured on that posedge); counters/FSM (negedge) use the
    // posedge-sampled copy so they never race with a source that drives on negedge.
    wire hk_feature = dma_feature_valid && dma_feature_ready;
    wire hk_kernel  = dma_kernel_valid  && dma_kernel_ready;
    wire hk_bias    = dma_bias_valid    && dma_bias_ready;
    reg  hk_feature_p, hk_kernel_p, hk_bias_p, hk_output_p;
    assign is_feature_in = (cstate == IN_FEATURE);

    // Result stream. top_bottleneck registers TDATA (posedge) on
    // (handshake | output_init_flag) from FB[is_fmem0_in] doutb, so the read
    // address runs one word ahead of the word being presented.
    //   stage 0 : addr 0 issued            (BRAM fetches word 0)
    //   stage 1 : output_init_flag         (TDATA <- word 0, fetch word 1)
    //   stage 2 : TVALID; on handshake TDATA <- word k+1, fetch word k+2
    reg [1:0] out_stage;
    reg [BRAM_FEATRE_CAPACITY-1:0] out_ptr;
    assign dma_result_valid = (cstate == OUTPUT) && (out_stage == 2'd2);
    assign output_init_flag = (cstate == OUTPUT) && (out_stage == 2'd1);
    wire hk_output = dma_result_valid && dma_result_ready;
    always @(posedge clk or negedge nrst) begin
        if (!nrst) {hk_feature_p, hk_kernel_p, hk_bias_p, hk_output_p} <= 4'b0;
        else       {hk_feature_p, hk_kernel_p, hk_bias_p, hk_output_p} <= {hk_feature, hk_kernel, hk_bias, hk_output};
    end
    assign dma_result_last  = dma_result_valid && (cnt_dma_output == len_output);
    wire out_load = hk_output || output_init_flag;            // posedge view (address)
    wire out_load_p = hk_output_p || output_init_flag;        // negedge view (pointer)
    wire [BRAM_FEATRE_CAPACITY-1:0] out_rd_addr = out_load ? out_ptr + 1'b1 : out_ptr;

    // ------------------------------------------------------------------
    // RUN issue sequencer (one issue per cycle)
    //   MAC : for oc, for oy, for ox, { for ic, for ky, for kx : tap } [+ shortcut slot]
    //   else: linear over the feature map
    // ------------------------------------------------------------------
    reg [5:0] r_kx, r_ky, r_ic, r_ox, r_oy, r_oc;
    reg       r_res;          // current issue is the residual shortcut slot
    reg [31:0] r_lin;          // non-MAC linear index
    reg       issue_done;
    wire issue = (cstate == RUN) && !issue_done;

    wire c_kx = (r_kx == kw);
    wire c_ky = (r_ky == kw);
    wire c_ic = (r_ic == fc);
    wire c_ox = (r_ox == ow);
    wire c_oy = (r_oy == ow);
    wire c_oc = (r_oc == oc);
    wire tap_end   = c_kx && c_ky && c_ic;           // last tap of this output pixel
    wire pix_end   = mac_enable ? ((residual_enable ? r_res : tap_end)) : 1'b1;
    wire all_end   = mac_enable ? (pix_end && c_ox && c_oy && c_oc) : (r_lin == len_feature);

    // Address of the current issue
    wire [2:0]  stride_v = cfg_stride ? 3'd2 : 3'd1;
    wire signed [9:0] iy = $signed({4'd0, r_oy}) * $signed({7'd0, stride_v}) + $signed({4'd0, r_ky}) - (cfg_padding ? 10'sd1 : 10'sd0);
    wire signed [9:0] ix = $signed({4'd0, r_ox}) * $signed({7'd0, stride_v}) + $signed({4'd0, r_kx}) - (cfg_padding ? 10'sd1 : 10'sd0);
    wire        in_pad = (iy < 0) || (ix < 0) || (iy > $signed({4'd0, fw})) || (ix > $signed({4'd0, fw}));
    wire [31:0] iy_u = in_pad ? 32'd0 : {22'd0, iy};   // TODO: zero insertion for padding
    wire [31:0] ix_u = in_pad ? 32'd0 : {22'd0, ix};
    wire [31:0] feat_addr_mac = ({26'd0, r_ic} * (fw+32'd1) + iy_u) * (fw+32'd1) + ix_u;
    wire [31:0] kern_addr     = (({26'd0, r_oc} * (fc+32'd1) + r_ic) * (kw+32'd1) + r_ky) * (kw+32'd1) + r_kx;
    wire [31:0] out_index     = ({26'd0, r_oc} * (ow+32'd1) + r_oy) * (ow+32'd1) + r_ox;
    wire [31:0] feat_addr     = mac_enable ? feat_addr_mac : r_lin;

    // BRAM data arrives one cycle after the address -> delay in_enable by one cycle.
    reg in_en_q;
    assign in_enable = in_en_q;

    // ------------------------------------------------------------------
    // BRAM control
    //   writes (DMA feature or core result) -> FB[is_fmem0_in]
    //   core reads FB[~is_fmem0_in], result DMA reads FB[is_fmem0_in]
    // ------------------------------------------------------------------
    reg                            core_wr, core_wr_skip;
    reg [BRAM_FEATRE_CAPACITY-1:0] core_wr_addr;
    reg                            toggle_pending;
    wire fb_wr = hk_feature || (core_wr && !core_wr_skip);
    wire [BRAM_FEATRE_CAPACITY-1:0] fb_wr_addr = hk_feature ? cnt_feature[BRAM_FEATRE_CAPACITY-1:0] : core_wr_addr;
    assign fmem_wr_enable[0] = fb_wr && !is_fmem0_in;
    assign fmem_wr_enable[1] = fb_wr &&  is_fmem0_in;
    assign fmem_wr_addr[0]   = fb_wr_addr;
    assign fmem_wr_addr[1]   = fb_wr_addr;
    wire [BRAM_FEATRE_CAPACITY-1:0] fb_rd_addr = (cstate == OUTPUT) ? out_rd_addr : feat_addr[BRAM_FEATRE_CAPACITY-1:0];
    assign fmem_rd_addr[0]   = fb_rd_addr;
    assign fmem_rd_addr[1]   = fb_rd_addr;
    assign kmem_wr_enable = hk_kernel;
    assign kmem_wr_addr   = cnt_kernel[BRAM_KERNEL_CAPACITY-1:0];
    assign kmem_rd_addr   = kern_addr[BRAM_KERNEL_CAPACITY-1:0];
    assign bmem_wr_enable = hk_bias;
    assign bmem_wr_addr   = cnt_bias[BRAM_BIAS_CAPACITY-1:0];
    assign bmem_rd_addr   = r_oc[BRAM_BIAS_CAPACITY-1:0];
    assign rmem_wr_enable = core_wr && core_wr_skip;
    assign rmem_wr_addr   = core_wr_addr;
    assign rmem_rd_addr   = out_index[BRAM_FEATRE_CAPACITY-1:0];

    // ------------------------------------------------------------------
    // Response
    // ------------------------------------------------------------------
    always @* begin
        case (cstate)
            IDLE: cfg_response = seen_command ? RESP_DONE : RESP_IDLE;
            DECODE, IN_FEATURE, IN_KERNEL, IN_BIAS: cfg_response = RESP_INPUT;
            RUN: cfg_response = RESP_RUN;
            OUTPUT: cfg_response = RESP_OUTPUT;
            default: cfg_response = RESP_ERROR;
        endcase
    end

    // ------------------------------------------------------------------
    // Next state
    // ------------------------------------------------------------------
    always @* begin
        nstate = cstate;
        case (cstate)
            IDLE: if (cfg_enable) nstate = DECODE;
            DECODE: begin
                if (cfg_input_enable) nstate = IN_FEATURE;
                else if (mac_enable) nstate = IN_KERNEL;
                else nstate = RUN;
            end
            IN_FEATURE: if (hk_feature_p && cnt_feature == len_feature)
                nstate = mac_enable ? IN_KERNEL : ((cfg_is_skip || gap_enable || relu_enable || residual_enable || pooling_enable) ? RUN : IDLE);
            IN_KERNEL: if (hk_kernel_p && cnt_kernel == len_kernel) nstate = IN_BIAS;
            IN_BIAS: if (hk_bias_p && cnt_bias == len_bias) nstate = RUN;
            RUN: if (out_enable && cnt_output == len_output)
                nstate = cfg_output_enable ? OUTPUT : IDLE;
            OUTPUT: if (hk_output_p && cnt_dma_output == len_output) nstate = IDLE;
            ERROR: if (cfg_enable) nstate = DECODE;
            default: nstate = ERROR;
        endcase
    end

    // ------------------------------------------------------------------
    // Registers (negedge, active-low async reset)
    // ------------------------------------------------------------------
    always @(negedge clk or negedge nrst) begin
        if (!nrst) begin
            cstate <= IDLE;
            seen_command <= 1'b0;
            cfg_input_enable <= 0; cfg_output_enable <= 0; cfg_is_skip <= 0;
            cfg_stride <= 0; cfg_padding <= 0;
            mac_enable <= 0; residual_enable <= 0; relu_enable <= 0;
            pooling_enable <= 0; gap_enable <= 0;
            size_w <= 0; size_h <= 0; size_c <= 0;
            fw <= 0; fc <= 0; kw <= 0; kc <= 0; ow <= 0; oc <= 0;
            nw <= 0; nc <= 0;
            out_stage <= 2'd0; out_ptr <= '0;
            r_kx <= 0; r_ky <= 0; r_ic <= 0; r_ox <= 0; r_oy <= 0; r_oc <= 0;
            r_res <= 0; r_lin <= 0; issue_done <= 0; in_en_q <= 0;
            core_wr <= 1'b0; core_wr_skip <= 1'b0; core_wr_addr <= '0;
            toggle_pending <= 1'b0;
            is_fmem0_in <= 0;
            cnt_feature <= 0; cnt_kernel <= 0; cnt_bias <= 0;
            cnt_run <= 0; cnt_output <= 0; cnt_dma_output <= 0;
        end else begin
            cstate <= nstate;
            if (cstate == IDLE && cfg_enable) begin
                seen_command <= 1'b1;
                cfg_input_enable <= cfg[0]; cfg_output_enable <= cfg[1];
                gap_enable <= cfg[2]; pooling_enable <= cfg[3];
                relu_enable <= cfg[4]; residual_enable <= cfg[5];
                mac_enable <= cfg[6]; cfg_is_skip <= cfg[7];
                cfg_stride <= cfg[8]; cfg_padding <= cfg[9];
                size_w <= cfg[15:10]; size_h <= cfg[21:16]; size_c <= cfg[27:22];
            end
            if (cstate == DECODE) begin
                if (cfg_input_enable) begin
                    fw <= size_w; fc <= size_c;
                    ow <= size_w; oc <= size_c;
                    nw <= size_w; nc <= size_c;
                end else if (mac_enable) begin
                    kw <= size_w; kc <= size_c;
                    fw <= nw; fc <= nc;
                    ow <= conv_ow;
                    oc <= size_c;
                    if (!cfg_is_skip) begin
                        nw <= gap_enable ? 6'd0 : conv_ow;
                        nc <= size_c;
                    end
                end else begin
                    fw <= nw; fc <= nc;
                    ow <= nw; oc <= nc;
                end
            end
            if (cstate == RUN && nstate != RUN && gap_enable) ow <= 0;

            // Ping-pong: switch after a command that wrote FB (INPUT, main-path
            // RUN, OUTPUT). Delayed one cycle so the last registered write lands first.
            toggle_pending <= (cstate == IN_FEATURE && nstate == IDLE) ||
                              (cstate == RUN    && nstate == IDLE && !cfg_is_skip) ||
                              (cstate == OUTPUT && nstate == IDLE && !cfg_is_skip);
            if (toggle_pending) is_fmem0_in <= ~is_fmem0_in;

            // Core result write (registered: aligns with out_data on next posedge)
            core_wr      <= (cstate == RUN) && out_enable;
            core_wr_skip <= cfg_is_skip;
            core_wr_addr <= cnt_output[BRAM_FEATRE_CAPACITY-1:0];

            // Issue sequencer
            in_en_q <= issue;
            if (cstate != RUN) begin
                r_kx <= 0; r_ky <= 0; r_ic <= 0; r_ox <= 0; r_oy <= 0; r_oc <= 0;
                r_res <= 0; r_lin <= 0; issue_done <= 0;
            end else if (issue) begin
                if (all_end) issue_done <= 1'b1;
                if (!mac_enable) begin
                    r_lin <= r_lin + 1;
                end else if (r_res) begin
                    r_res <= 1'b0;
                end else begin
                    r_kx <= c_kx ? 6'd0 : r_kx + 1;
                    if (c_kx) r_ky <= c_ky ? 6'd0 : r_ky + 1;
                    if (c_kx && c_ky) r_ic <= c_ic ? 6'd0 : r_ic + 1;
                    if (tap_end && residual_enable) r_res <= 1'b1;
                end
                if (mac_enable && pix_end) begin
                    r_ox <= c_ox ? 6'd0 : r_ox + 1;
                    if (c_ox) r_oy <= c_oy ? 6'd0 : r_oy + 1;
                    if (c_ox && c_oy) r_oc <= c_oc ? 6'd0 : r_oc + 1;
                end
            end

            // Output stream stages
            if (cstate != OUTPUT) begin
                out_stage <= 2'd0; out_ptr <= '0;
            end else begin
                if (out_stage != 2'd2) out_stage <= out_stage + 2'd1;
                if (out_load_p) out_ptr <= out_ptr + 1'b1;
            end

            cnt_feature    <= cstate != IN_FEATURE ? 0 : cnt_feature + (hk_feature_p ? 1 : 0);
            cnt_kernel     <= cstate != IN_KERNEL  ? 0 : cnt_kernel  + (hk_kernel_p  ? 1 : 0);
            cnt_bias       <= cstate != IN_BIAS    ? 0 : cnt_bias    + (hk_bias_p    ? 1 : 0);
            cnt_dma_output <= cstate != OUTPUT     ? 0 : cnt_dma_output + (hk_output_p ? 1 : 0);
            cnt_run        <= cstate != RUN        ? 0 : cnt_run + (issue ? 1 : 0);
            cnt_output     <= cstate != RUN        ? 0 : cnt_output + (out_enable ? 1 : 0);
        end
    end
endmodule

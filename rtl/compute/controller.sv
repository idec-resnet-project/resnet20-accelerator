// Jihye independent Controller v0.4 (v0.3 + registered core-result write: address alignment, last write kept): FSM, streaming, counters, basic sequential BRAM.
// NOTE: Convolution feature/kernel read addressing is intentionally provisional.
// This is a functional-control prototype, NOT a complete ResNet-20 accelerator.
module controller #(
    parameter integer CONFIG_BITWIDTH = 32,
    parameter integer BITWIDTH_MAC_ITERATION = 16,
    parameter integer BITWIDTH_POOLING_ITERATION = 16,
    parameter integer BITWIDTH_GAP_ITERATION = 16,
    parameter integer BRAM_FEATRE_CAPACITY = 14,
    parameter integer BRAM_KERNEL_CAPACITY = 16,
    parameter integer BRAM_BIAS_CAPACITY = 6
)(
    input wire clk, nrst,
    input wire cfg_enable,
    input wire [CONFIG_BITWIDTH-1:0] cfg,
    output reg [3:0] cfg_response,
    output reg mac_enable, residual_enable, relu_enable, pooling_enable, gap_enable,
    output wire [BITWIDTH_MAC_ITERATION-1:0] mac_iteration,
    output wire [BITWIDTH_POOLING_ITERATION-1:0] pooling_iteration,
    output wire [BITWIDTH_GAP_ITERATION-1:0] gap_iteration,
    output wire in_enable,
    input wire out_enable,
    output reg is_fmem0_in,
    input wire dma_feature_valid,
    output wire dma_feature_ready,
    input wire dma_feature_last,
    input wire dma_kernel_valid,
    output wire dma_kernel_ready,
    input wire dma_kernel_last,
    input wire dma_bias_valid,
    output wire dma_bias_ready,
    input wire dma_bias_last,
    output wire dma_result_valid,
    input wire dma_result_ready,
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
    reg [5:0] fw, fc, kw, kc, ow, oc; // 0-based W,C,K,Cout and output dimensions
    reg [5:0] nw, nc;                 // 0-based size of the feature map the NEXT main-path command reads
                                      // (SKIP commands must not overwrite this)
    wire [5:0] conv_ow = ( {26'd0,nw} + (cfg_padding ? 32'd2 : 32'd0) - {26'd0,size_w} ) >> cfg_stride;
    reg [31:0] cnt_feature, cnt_kernel, cnt_bias, cnt_run, cnt_output, cnt_dma_output;
    wire [31:0] feature_count = (fw+32'd1)*(fw+32'd1)*(fc+32'd1);
    wire [31:0] kernel_count  = (kw+32'd1)*(kw+32'd1)*(fc+32'd1)*(kc+32'd1);
    wire [31:0] bias_count    = kc+32'd1;
    wire [31:0] output_count  = gap_enable ? (oc+32'd1) :
                               (mac_enable ? (ow+32'd1)*(ow+32'd1)*(oc+32'd1) : feature_count);
    wire [31:0] tap_count     = (kw+32'd1)*(kw+32'd1)*(fc+32'd1);
    wire [31:0] gap_count     = (ow+32'd1)*(ow+32'd1);
    // Residual MAC: core.v consumes one extra in_enable after the last tap (shortcut word).
    wire [31:0] in_per_output = mac_enable ? (tap_count + (residual_enable ? 32'd1 : 32'd0)) : 32'd1;
    wire [31:0] run_cycles    = output_count*in_per_output*
                               (gap_enable ? gap_count : 32'd1);

    // Debug-compatible zero-based final indices; only meaningful for nonzero sizes.
    wire [31:0] len_feature = feature_count-1;
    wire [31:0] len_kernel  = kernel_count-1;
    wire [31:0] len_bias    = bias_count-1;
    wire [31:0] len_output  = output_count-1;

    assign mac_iteration = mac_enable ? tap_count[BITWIDTH_MAC_ITERATION-1:0] : '0;
    assign pooling_iteration = (ow+32'd1); // PROVISIONAL, depends on pooling contract
    assign gap_iteration = gap_enable ? gap_count[BITWIDTH_GAP_ITERATION-1:0] : '0;

    assign dma_feature_ready = (cstate == IN_FEATURE);
    assign dma_kernel_ready = (cstate == IN_KERNEL);
    assign dma_bias_ready = (cstate == IN_BIAS);
    // BRAM read latency = 1 cycle: assert TVALID only after the word for the
    // current read address is on doutb, and drop it for one cycle after each
    // handshake while the next word is fetched (TDATA stays stable while stalled).
    reg out_data_ready;
    assign dma_result_valid = (cstate == OUTPUT) && out_data_ready;
    assign dma_result_last = dma_result_valid && (cnt_dma_output == len_output);
    wire hk_feature = dma_feature_valid && dma_feature_ready;
    wire hk_kernel  = dma_kernel_valid  && dma_kernel_ready;
    wire hk_bias    = dma_bias_valid    && dma_bias_ready;
    wire hk_output  = dma_result_valid  && dma_result_ready;
    assign in_enable = (cstate == RUN) && (cnt_run < run_cycles);

    // First-pass write routing. Confirm feature buffer selection in top_bottleneck.
    // Core result write. out_enable/out_data change on posedge, the controller
    // samples on negedge, so the write is registered here (enable + address of
    // the output index) and the BRAM captures it on the following posedge,
    // when out_data still holds that output. Fixes +1 address shift and the
    // lost last write.
    reg                            core_wr;      // registered: write core result
    reg                            core_wr_skip; // registered: target is RB
    reg [BRAM_FEATRE_CAPACITY-1:0] core_wr_addr;
    reg                            toggle_pending;
    wire core_wr_fb = core_wr && !core_wr_skip;
    assign fmem_wr_enable[0] = (!is_fmem0_in && hk_feature) || (is_fmem0_in && core_wr_fb);
    assign fmem_wr_enable[1] = ( is_fmem0_in && hk_feature) || (!is_fmem0_in && core_wr_fb);
    assign fmem_wr_addr[0] = hk_feature ? cnt_feature[BRAM_FEATRE_CAPACITY-1:0] : core_wr_addr;
    assign fmem_wr_addr[1] = hk_feature ? cnt_feature[BRAM_FEATRE_CAPACITY-1:0] : core_wr_addr;
    wire [31:0] addr_read_counter = (cstate == OUTPUT) ? cnt_dma_output : cnt_run;
    // Sequential placeholder addresses: NOT stride/padding-aware convolution traversal.
    assign fmem_rd_addr[0] = addr_read_counter[BRAM_FEATRE_CAPACITY-1:0];
    assign fmem_rd_addr[1] = addr_read_counter[BRAM_FEATRE_CAPACITY-1:0];
    assign kmem_wr_enable = hk_kernel;
    assign kmem_wr_addr = cnt_kernel[BRAM_KERNEL_CAPACITY-1:0];
    assign kmem_rd_addr = cnt_run[BRAM_KERNEL_CAPACITY-1:0];
    assign bmem_wr_enable = hk_bias;
    assign bmem_wr_addr = cnt_bias[BRAM_BIAS_CAPACITY-1:0];
    assign bmem_rd_addr = '0;
    assign rmem_wr_enable = core_wr && core_wr_skip;
    assign rmem_wr_addr = core_wr_addr;
    assign rmem_rd_addr = cnt_output[BRAM_FEATRE_CAPACITY-1:0];

    // State-dependent status. DONE remains visible in IDLE until next command.
    always @* begin
        case (cstate)
            IDLE: cfg_response = seen_command ? RESP_DONE : RESP_IDLE;
            DECODE, IN_FEATURE, IN_KERNEL, IN_BIAS: cfg_response = RESP_INPUT;
            RUN: cfg_response = RESP_RUN;
            OUTPUT: cfg_response = RESP_OUTPUT;
            default: cfg_response = RESP_ERROR;
        endcase
    end

    // Explicit terminal-beat checks avoid last-word off-by-one bugs.
    always @* begin
        nstate = cstate;
        case (cstate)
            IDLE: if (cfg_enable) nstate = DECODE;
            DECODE: begin
                if (cfg_input_enable) nstate = IN_FEATURE;
                else if (mac_enable) nstate = IN_KERNEL;
                else nstate = RUN;
            end
            IN_FEATURE: if (hk_feature && cnt_feature == len_feature)
                nstate = mac_enable ? IN_KERNEL : ((cfg_is_skip || gap_enable || relu_enable || residual_enable || pooling_enable) ? RUN : IDLE);
            IN_KERNEL: if (hk_kernel && cnt_kernel == len_kernel) nstate = IN_BIAS;
            IN_BIAS: if (hk_bias && cnt_bias == len_bias) nstate = RUN;
            RUN: if (out_enable && cnt_output == len_output)
                nstate = cfg_output_enable ? OUTPUT : IDLE;
            OUTPUT: if (hk_output && cnt_dma_output == len_output) nstate = IDLE;
            ERROR: if (cfg_enable) nstate = DECODE;
            default: nstate = ERROR;
        endcase
    end

    // The starter TB in jihye branch samples on the falling edge.
    // Active-low asynchronous reset.
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
            out_data_ready <= 1'b0;
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
                    fw <= nw; fc <= nc;          // read the main-path map, not the last command's output
                    ow <= conv_ow;
                    oc <= size_c;
                    if (!cfg_is_skip) begin      // SKIP output goes to rmem -> main-path size unchanged
                        nw <= gap_enable ? 6'd0 : conv_ow;
                        nc <= size_c;
                    end
                end else begin
                    fw <= nw; fc <= nc;
                    ow <= nw; oc <= nc;
                end
            end
            if (cstate == RUN && nstate != RUN && gap_enable) ow <= 0; // GAP -> 1x1 spatial output
            // Switch only after results actually land in feature buffer.
            // Ping-pong switch after results land in FB. Delayed by one cycle
            // so the last registered core write still uses the old select.
            toggle_pending <= (cstate == RUN && nstate == IDLE && !cfg_is_skip && !cfg_input_enable) ||
                              (cstate == OUTPUT && nstate == IDLE && !cfg_is_skip);
            if (toggle_pending) is_fmem0_in <= ~is_fmem0_in;
            core_wr      <= (cstate == RUN) && out_enable;
            core_wr_skip <= cfg_is_skip;
            core_wr_addr <= cnt_output[BRAM_FEATRE_CAPACITY-1:0];
            cnt_feature <= cstate != IN_FEATURE ? 0 : cnt_feature + (hk_feature ? 1 : 0);
            cnt_kernel <= cstate != IN_KERNEL ? 0 : cnt_kernel + (hk_kernel ? 1 : 0);
            cnt_bias <= cstate != IN_BIAS ? 0 : cnt_bias + (hk_bias ? 1 : 0);
            cnt_dma_output <= cstate != OUTPUT ? 0 : cnt_dma_output + (hk_output ? 1 : 0);
            out_data_ready <= (cstate == OUTPUT) && !hk_output;
            cnt_run <= cstate != RUN ? 0 : cnt_run + (in_enable ? 1 : 0);
            cnt_output <= cstate != RUN ? 0 : cnt_output + (out_enable ? 1 : 0);
        end
    end
endmodule

`timescale 1ns/1ps
// ============================================================================
// tb_controller : standalone testbench for controller.sv
//                 (branch feat/memory-hyunkeon-1.0.0)
// - DMA and core are simple models; checks FSM, counters, sizes, DONE
// - Scenarios run in order (each uses the previous output size):
//   S1 INPUT     4x4x2 feature
//   S2 CONV_RELU 3x3, Cout 2, pad 1
//   S3 CONV_GAP  3x3, Cout 4, pad 1, ReLU + GAP
//   S4 FC_OUT    1x1, Cout 10
// - Log: [ PASS ] / [ FAIL ] / [ INFO ], FAIL count at the end
// ============================================================================
module tb_controller;

    // ------------------------------------------------------------------
    // Parameters (same as controller defaults)
    // ------------------------------------------------------------------
    localparam integer CONFIG_BITWIDTH            = 32;
    localparam integer BITWIDTH_MAC_ITERATION     = 16;
    localparam integer BITWIDTH_POOLING_ITERATION = 16;
    localparam integer BITWIDTH_GAP_ITERATION     = 16;
    localparam integer BRAM_FEATRE_CAPACITY       = 14;
    localparam integer BRAM_KERNEL_CAPACITY       = 16;
    localparam integer BRAM_BIAS_CAPACITY         = 6;

    localparam integer TIMEOUT_CYCLES = 50000;   // max cycles per command

    localparam [3:0] RESP_IDLE = 4'b0000;
    localparam [3:0] RESP_DONE = 4'b0001;

    // ------------------------------------------------------------------
    // Clock / reset
    // ------------------------------------------------------------------
    logic clk  = 1'b0;
    logic nrst = 1'b0;
    always #5 clk = ~clk;          // 10 ns period (DUT runs on negedge)

    // ------------------------------------------------------------------
    // DUT ports
    // ------------------------------------------------------------------
    logic                                   cfg_enable = 1'b0;
    logic [CONFIG_BITWIDTH-1:0]             cfg        = '0;
    wire  [3:0]                             cfg_response;

    wire                                    mac_enable;
    wire  [BITWIDTH_MAC_ITERATION-1:0]      mac_iteration;
    wire                                    residual_enable;
    wire                                    relu_enable;
    wire                                    pooling_enable;
    wire  [BITWIDTH_POOLING_ITERATION-1:0]  pooling_iteration;
    wire                                    gap_enable;
    wire  [BITWIDTH_GAP_ITERATION-1:0]      gap_iteration;

    wire                                    in_enable;
    logic                                   out_enable = 1'b0;   // driven by core model
    wire                                    is_bmem0_in;

    logic dma_feature_valid = 1'b0, dma_feature_last = 1'b0;   // driven by DMA model
    logic dma_kernel_valid  = 1'b0, dma_kernel_last  = 1'b0;
    logic dma_bias_valid    = 1'b0, dma_bias_last    = 1'b0;
    wire  dma_feature_ready, dma_kernel_ready, dma_bias_ready;

    wire  dma_result_valid, dma_result_last;
    logic dma_result_ready = 1'b1;                               // always ready

    wire                             fmem_wr_enable [0:1];
    wire [BRAM_FEATRE_CAPACITY-1:0]  fmem_wr_addr   [0:1];
    wire [BRAM_FEATRE_CAPACITY-1:0]  fmem_rd_addr   [0:1];
    wire                             kmem_wr_enable;
    wire [BRAM_KERNEL_CAPACITY-1:0]  kmem_rd_addr, kmem_wr_addr;
    wire                             bmem_wr_enable;
    wire [BRAM_BIAS_CAPACITY-1:0]    bmem_rd_addr, bmem_wr_addr;
    wire                             rmem_wr_enable;
    wire [BRAM_FEATRE_CAPACITY-1:0]  rmem_rd_addr, rmem_wr_addr;

    controller #(
        .CONFIG_BITWIDTH            (CONFIG_BITWIDTH),
        .BITWIDTH_MAC_ITERATION     (BITWIDTH_MAC_ITERATION),
        .BITWIDTH_POOLING_ITERATION (BITWIDTH_POOLING_ITERATION),
        .BITWIDTH_GAP_ITERATION     (BITWIDTH_GAP_ITERATION),
        .BRAM_FEATRE_CAPACITY       (BRAM_FEATRE_CAPACITY),
        .BRAM_KERNEL_CAPACITY       (BRAM_KERNEL_CAPACITY),
        .BRAM_BIAS_CAPACITY         (BRAM_BIAS_CAPACITY)
    ) dut (
        .clk               (clk),
        .nrst              (nrst),
        .cfg_enable        (cfg_enable),
        .cfg               (cfg),
        .cfg_response      (cfg_response),
        .mac_enable        (mac_enable),
        .mac_iteration     (mac_iteration),
        .residual_enable   (residual_enable),
        .relu_enable       (relu_enable),
        .pooling_enable    (pooling_enable),
        .pooling_iteration (pooling_iteration),
        .gap_enable        (gap_enable),
        .gap_iteration     (gap_iteration),
        .in_enable         (in_enable),
        .out_enable        (out_enable),
        .is_bmem0_in       (is_bmem0_in),
        .dma_feature_valid (dma_feature_valid),
        .dma_feature_ready (dma_feature_ready),
        .dma_feature_last  (dma_feature_last),
        .dma_kernel_valid  (dma_kernel_valid),
        .dma_kernel_ready  (dma_kernel_ready),
        .dma_kernel_last   (dma_kernel_last),
        .dma_bias_valid    (dma_bias_valid),
        .dma_bias_ready    (dma_bias_ready),
        .dma_bias_last     (dma_bias_last),
        .dma_result_valid  (dma_result_valid),
        .dma_result_ready  (dma_result_ready),
        .dma_result_last   (dma_result_last),
        .fmem_wr_enable    (fmem_wr_enable),
        .fmem_wr_addr      (fmem_wr_addr),
        .fmem_rd_addr      (fmem_rd_addr),
        .kmem_wr_enable    (kmem_wr_enable),
        .kmem_rd_addr      (kmem_rd_addr),
        .kmem_wr_addr      (kmem_wr_addr),
        .bmem_wr_enable    (bmem_wr_enable),
        .bmem_rd_addr      (bmem_rd_addr),
        .bmem_wr_addr      (bmem_wr_addr),
        .rmem_wr_enable    (rmem_wr_enable),
        .rmem_rd_addr      (rmem_rd_addr),
        .rmem_wr_addr      (rmem_wr_addr)
    );

    // ------------------------------------------------------------------
    // FSM state bits (one-hot cstate)
    // ------------------------------------------------------------------
    wire st_idle   = dut.cstate[0];
    wire st_decode = dut.cstate[1];
    wire st_feat   = dut.cstate[2];
    wire st_run    = dut.cstate[5];
    wire st_output = dut.cstate[6];

    // ------------------------------------------------------------------
    // Monitors (cleared in issue())
    // ------------------------------------------------------------------
    int  n_fail = 0;
    bit  abort  = 0;         // stop DMA model on timeout
    int  mon_in_enable;      // cycles with in_enable = 1 in RUN
    int  mon_out_enable;     // outputs from core model
    int  mon_result;         // result words transferred
    int  mon_result_last_at; // index of TLAST (0 = never)
    int  mon_fwr;            // fmem write cycles in IN_FEATURE
    int  mon_fwr_x;          // fmem_wr_enable = X cycles
    int  mon_waddr_x;        // fmem_wr_addr = X/Z cycles

    task automatic clear_monitors();
        mon_in_enable = 0; mon_out_enable = 0; mon_result = 0; mon_result_last_at = 0;
        mon_fwr = 0; mon_fwr_x = 0; mon_waddr_x = 0;
    endtask

    // Count events on negedge (same edge as DUT)
    always @(negedge clk) if (nrst) begin
        if (st_run && in_enable === 1'b1) mon_in_enable++;
        if (st_feat) begin
            if ($isunknown(fmem_wr_enable[0]) || $isunknown(fmem_wr_enable[1])) mon_fwr_x++;
            else if (fmem_wr_enable[0] || fmem_wr_enable[1])                   mon_fwr++;
            if ($isunknown(fmem_wr_addr[0]) || $isunknown(fmem_wr_addr[1]))      mon_waddr_x++;
        end
        if (dma_result_valid === 1'b1 && dma_result_ready) begin
            mon_result++;
            if (dma_result_last === 1'b1 && mon_result_last_at == 0) mon_result_last_at = mon_result;
        end
    end

    // ------------------------------------------------------------------
    // Core model: 1-cycle out_enable every (mac_iteration * gap window) inputs
    // ------------------------------------------------------------------
    int core_cnt = 0;
    int per_out;
    always @(posedge clk) begin
        per_out = (mac_enable ? int'(mac_iteration) : 1) * (gap_enable ? int'(gap_iteration) : 1);
        if (per_out < 1) per_out = 1;
        out_enable <= 1'b0;
        if (!nrst || !st_run) begin
            core_cnt <= 0;
        end else if (in_enable === 1'b1) begin
            if (core_cnt >= per_out - 1) begin
                core_cnt   <= 0;
                out_enable <= 1'b1;
                mon_out_enable++;
            end else begin
                core_cnt <= core_cnt + 1;
            end
        end
    end

    // ------------------------------------------------------------------
    // Config builder (bit map from controller_configure.svh)
    //   [0] input  [1] output  [2] gap  [3] pooling  [4] relu  [5] residual  [6] mac
    //   [7] skip   [8] stride-1 [9] padding
    //   [15:10] a-1  [21:16] b-1  [27:22] c-1
    //     INPUT / SKIP : a, b, c = W, H, Cin
    //     MAC commands : a, b, c = Kw, Kh, Cout
    // ------------------------------------------------------------------
    function automatic logic [31:0] mk_cfg(
        input bit in_en, out_en, mac, res, relu, pool, gap, skip,
        input int stride, pad, a, b, c);
        logic [5:0] a1, b1, c1;
        a1 = a - 1; b1 = b - 1; c1 = c - 1;
        return {4'b0000, c1, b1, a1, pad[0], 1'(stride - 1),
                skip, mac, res, relu, pool, gap, out_en, in_en};
    endfunction

    // ------------------------------------------------------------------
    // Check helpers
    // ------------------------------------------------------------------
    task automatic check_eq(input string what, input longint got, input longint exp);
        if (got === exp) $display("[ PASS ] %-28s = %0d", what, got);
        else begin
            $display("[ FAIL ] %-28s = %0d (expected %0d)", what, got, exp);
            n_fail++;
        end
    endtask

    task automatic info(input string what, input longint val);
        $display("[ INFO ] %-28s = %0d", what, val);
    endtask

    // ------------------------------------------------------------------
    // Issue command: cfg_enable high for 1 cycle, cfg held
    // ------------------------------------------------------------------
    task automatic issue(input logic [31:0] c);
        clear_monitors();
        @(posedge clk);
        cfg        <= c;
        cfg_enable <= 1'b1;
        @(posedge clk);
        cfg_enable <= 1'b0;
    endtask

    // ------------------------------------------------------------------
    // DMA source model: send req words per channel, last on final word
    //   negedge: count valid & ready (same edge as DUT)
    //   posedge: drive next valid / last
    //   set req_* in run_cmd() to start
    // ------------------------------------------------------------------
    int req_feat = 0, req_kern = 0, req_bias = 0;   // words to send
    int sent_feat = 0, sent_kern = 0, sent_bias = 0; // words transferred

    always @(negedge clk) begin
        if (dma_feature_valid && dma_feature_ready === 1'b1) sent_feat++;
        if (dma_kernel_valid  && dma_kernel_ready  === 1'b1) sent_kern++;
        if (dma_bias_valid    && dma_bias_ready    === 1'b1) sent_bias++;
    end

    always @(posedge clk) begin
        dma_feature_valid <= !abort && (sent_feat < req_feat);
        dma_feature_last  <= !abort && (sent_feat < req_feat) && (sent_feat == req_feat - 1);
        dma_kernel_valid  <= !abort && (sent_kern < req_kern);
        dma_kernel_last   <= !abort && (sent_kern < req_kern) && (sent_kern == req_kern - 1);
        dma_bias_valid    <= !abort && (sent_bias < req_bias);
        dma_bias_last     <= !abort && (sent_bias < req_bias) && (sent_bias == req_bias - 1);
    end

    // ------------------------------------------------------------------
    // Run one command: issue -> DMA (3 channels) -> wait for IDLE
    // ------------------------------------------------------------------
    task automatic run_cmd(input string name, input logic [31:0] c,
                           input int n_feat, input int n_kern, input int n_bias);
        int  t;
        bit  timed_out;
        $display("");
        $display("================ %s  (cfg = 0x%08h) ================", name, c);
        issue(c);

        // Print size registers after DECODE
        wait (!st_idle);
        wait (!st_decode);
        @(posedge clk);
        info("fw (in W-1)", dut.fw);   info("fc (in C-1)", dut.fc);
        info("kw (kernel K-1)", dut.kw);   info("kc (Cout-1)",  dut.kc);
        info("ow (out W-1)", dut.ow);   info("oc (out C-1)", dut.oc);
        info("len_feature", dut.len_feature); info("len_kernel", dut.len_kernel);
        info("len_bias",    dut.len_bias);    info("len_output", dut.len_output);
        info("mac_iteration", mac_iteration); info("gap_iteration", gap_iteration);

        // Start all DMA channels (wait for ready)
        abort    = 0;
        sent_feat = 0; sent_kern = 0; sent_bias = 0;
        req_feat  = n_feat; req_kern = n_kern; req_bias = n_bias;

        // Wait for IDLE or ERROR, with timeout
        t = 0;
        while (!(st_idle || dut.cstate[7]) && t < TIMEOUT_CYCLES) begin
            @(posedge clk);
            t++;
        end
        timed_out = (t >= TIMEOUT_CYCLES);
        abort = 1;                       // stop remaining DMA
        repeat (3) @(posedge clk);
        info("feature words sent", sent_feat);
        info("kernel words sent",  sent_kern);
        info("bias words sent",    sent_bias);
        req_feat = 0; req_kern = 0; req_bias = 0;
        abort = 0;

        if (timed_out) begin
            $display("[ FAIL ] %s : no IDLE within %0d cycles (cstate = %b)",
                     name, TIMEOUT_CYCLES, dut.cstate);
            info("cnt_run",    dut.cnt_run);
            info("cnt_output", dut.cnt_output);
            n_fail++;
        end else begin
            $display("[ PASS ] %s : back to IDLE", name);
        end
        check_eq("cfg_response (DONE = 1)", cfg_response, RESP_DONE);
    endtask

    // ------------------------------------------------------------------
    // Scenarios
    // ------------------------------------------------------------------
    initial begin
        $display("tb_controller start");
        repeat (5) @(posedge clk);
        nrst = 1'b1;
        repeat (3) @(posedge clk);
        check_eq("cfg_response after reset (0)", cfg_response, RESP_IDLE);

        // ---------------- S1 : INPUT 4x4x2 ----------------
        run_cmd("S1 INPUT 4x4x2",
                mk_cfg(1,0, 0,0,0,0,0, 0, 1,0, 4,4,2), 32, 0, 0);
        check_eq("S1 fw",                   dut.fw, 3);
        check_eq("S1 fc",                   dut.fc, 1);
        check_eq("S1 fmem write count", mon_fwr, 32);
        check_eq("S1 fmem_wr_enable X cycles",  mon_fwr_x, 0);
        check_eq("S1 fmem_wr_addr X/Z cycles",  mon_waddr_x, 0);

        // ---------------- S2 : CONV_RELU 3x3, Cout 2, pad 1 ----------------
        run_cmd("S2 CONV_RELU 3x3 Cout2",
                mk_cfg(0,0, 1,0,1,0,0, 0, 1,1, 3,3,2), 0, 3*3*2*2, 2);
        check_eq("S2 fw (4 -> 3)",       dut.fw, 3);
        check_eq("S2 fc (2 -> 1)",     dut.fc, 1);
        check_eq("S2 ow (4 -> 3)",       dut.ow, 3);
        check_eq("S2 oc (2 -> 1)",       dut.oc, 1);
        check_eq("S2 mac_iteration (3x3x2)", mac_iteration, 18);
        check_eq("S2 core outputs (4x4x2)", mon_out_enable, 32);
        check_eq("S2 core input cycles (32x18)", mon_in_enable, 32*18);

        // ---------------- S3 : CONV + ReLU + GAP 3x3, Cout 4, pad 1 ----------------
        run_cmd("S3 CONV_RELU_GAP 3x3 Cout4",
                mk_cfg(0,0, 1,0,1,0,1, 0, 1,1, 3,3,4), 0, 3*3*2*4, 4);
        check_eq("S3 oc (4 -> 3)",        dut.oc, 3);
        check_eq("S3 core outputs (GAP 4)",  mon_out_enable, 4);
        check_eq("S3 ow (GAP out 1x1 -> 0)",   dut.ow, 0);

        // ---------------- S4 : FC_OUT 1x1, Cout 10 ----------------
        run_cmd("S4 FC_OUT 1x1 Cout10",
                mk_cfg(0,1, 1,0,0,0,0, 0, 1,0, 1,1,10), 0, 1*1*4*10, 10);
        check_eq("S4 fw (FC in 1x1 -> 0)",    dut.fw, 0);
        check_eq("S4 fc (4 -> 3)",    dut.fc, 3);
        check_eq("S4 len_output (10 -> 9)",   dut.len_output, 9);
        check_eq("S4 result words",           mon_result, 10);
        check_eq("S4 TLAST index (10th)",     mon_result_last_at, 10);

        // ---------------- Summary ----------------
        $display("");
        if (n_fail == 0) $display("[ PASS ] tb_controller : all checks passed");
        else             $display("[ FAIL ] tb_controller : %0d FAIL(s), see [ FAIL ] lines", n_fail);
        $finish;
    end

endmodule


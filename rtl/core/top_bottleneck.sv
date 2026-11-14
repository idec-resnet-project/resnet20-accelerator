module top_bottleneck #(
    // bitwidth 
    parameter integer BITWIDTH                   = 16,
    parameter integer CONFIG_BITWIDTH            = 32,
    parameter integer BITWIDTH_MAC_ITERATION     = 16,
    parameter integer BITWIDTH_POOLING_ITERATION = 16,
    parameter integer BITWIDTH_GAP_ITERATION     = 16,
    // parallelism
    parameter integer PARALLEL_PC                = 1,
    parameter integer PARALLEL_PF                = 1,
    // Buffer address widths. Each RAM stores 2**width words.
    parameter integer BRAM_FEATRE_CAPACITY       = 14,
    parameter integer BRAM_KERNEL_CAPACITY       = 16,
    parameter integer BRAM_BIAS_CAPACITY         = 6
)(
    input  wire                       clk,
    input  wire                       nrst,
    
    // config
    input  wire [CONFIG_BITWIDTH-1:0] cfg,
    
    // IDMA feature
    input  wire                       dma_feature_valid,
    output wire                       dma_feature_ready,
    input  wire                       dma_feature_last,
    input  wire [BITWIDTH-1:0]        dma_feature_data,
    
    // IDMA kernel
    input  wire                       dma_kernel_valid,
    output wire                       dma_kernel_ready,
    input  wire                       dma_kernel_last,
    input  wire [BITWIDTH-1:0]        dma_kernel_data,

    // IDMA bias
    input  wire                       dma_bias_valid,
    output wire                       dma_bias_ready,
    input  wire                       dma_bias_last,
    input  wire [BITWIDTH-1:0]        dma_bias_data,
    
    // ODMA output
    output wire                       dma_result_valid,
    input  wire                       dma_result_ready,
    output wire                       dma_result_last,
    output wire [BITWIDTH-1:0]        dma_result_data
);
// --------------------------------
// wire & reg
// --------------------------------
// Feature buffer
wire                            fmem_wr_en   [0:1];
wire [BRAM_FEATRE_CAPACITY-1:0] fmem_wr_addr [0:1];
wire [BITWIDTH-1:0]             fmem_wr_data [0:1];
wire [BRAM_FEATRE_CAPACITY-1:0] fmem_rd_addr [0:1];
wire [BITWIDTH-1:0]             fmem_rd_data [0:1];
// Kernel buffer
wire                            kmem_wr_en;
wire [BRAM_KERNEL_CAPACITY-1:0] kmem_wr_addr;
wire [BITWIDTH-1:0]             kmem_wr_data;
wire [BRAM_KERNEL_CAPACITY-1:0] kmem_rd_addr;
wire [BITWIDTH-1:0]             kmem_rd_data;
// Bias buffer
wire                          bmem_wr_en;
wire [BRAM_BIAS_CAPACITY-1:0] bmem_wr_addr;
wire [BITWIDTH-1:0]           bmem_wr_data;
wire [BRAM_BIAS_CAPACITY-1:0] bmem_rd_addr;
wire [BITWIDTH-1:0]           bmem_rd_data;
// Residual buffer holds a feature map.
wire                            rmem_wr_en;
wire [BRAM_FEATRE_CAPACITY-1:0] rmem_wr_addr;
wire [BITWIDTH-1:0]             rmem_wr_data;
wire [BRAM_FEATRE_CAPACITY-1:0] rmem_rd_addr;
wire [BITWIDTH-1:0]             rmem_rd_data;

// control
wire                                  mac_enable;
wire [BITWIDTH_MAC_ITERATION-1:0]     mac_iteration;
wire                                  residual_enable;
wire                                  relu_enable;
wire                                  pooling_enable;
wire [BITWIDTH_POOLING_ITERATION-1:0] pooling_iteration;
wire                                  gap_enable;
wire [BITWIDTH_GAP_ITERATION-1:0]     gap_iteration;
wire                                  in_enable;
wire                                  out_enable;

// --------------------------------
// controll
// --------------------------------


// --------------------------------
// Buffer
// --------------------------------
// Feature buffer

generate
    for (genvar i = 0; i < 2; i = i + 1) begin : gen_feature_mem
        buffer #(
            .DEPTH    (BRAM_FEATRE_CAPACITY),
            .BITWIDTH (BITWIDTH)
        ) u_mem (
            .clka  (clk),
            .wea   (fmem_wr_en[i]),
            .addra (fmem_wr_addr[i]),
            .dina  (fmem_wr_data[i]),
            .clkb  (clk),
            .addrb (fmem_rd_addr[i]),
            .doutb (fmem_rd_data[i])
        );
    end
endgenerate

// Kernel buffer

buffer #(
    .DEPTH    (BRAM_KERNEL_CAPACITY),
    .BITWIDTH (BITWIDTH)
) u_kernel_mem (
    .clka  (clk),
    .wea   (kmem_wr_en),
    .addra (kmem_wr_addr),
    .dina  (kmem_wr_data),
    .clkb  (clk),
    .addrb (kmem_rd_addr),
    .doutb (kmem_rd_data)
);

// Bias buffer

buffer #(
    .DEPTH    (BRAM_BIAS_CAPACITY),
    .BITWIDTH (BITWIDTH)
) u_bias_mem (
    .clka  (clk),
    .wea   (bmem_wr_en),
    .addra (bmem_wr_addr),
    .dina  (bmem_wr_data),
    .clkb  (clk),
    .addrb (bmem_rd_addr),
    .doutb (bmem_rd_data)
);

// Residual buffer holds a feature map.

buffer #(
    .DEPTH    (BRAM_FEATRE_CAPACITY),
    .BITWIDTH (BITWIDTH)
) u_residual_mem (
    .clka  (clk),
    .wea   (rmem_wr_en),
    .addra (rmem_wr_addr),
    .dina  (rmem_wr_data),
    .clkb  (clk),
    .addrb (rmem_rd_addr),
    .doutb (rmem_rd_data)
);

// --------------------------------
// Controller
// --------------------------------

controller #(
    .CONFIG_BITWIDTH            (CONFIG_BITWIDTH),
    .BITWIDTH_MAC_ITERATION     (BITWIDTH_MAC_ITERATION),
    .BITWIDTH_POOLING_ITERATION (BITWIDTH_POOLING_ITERATION),
    .BITWIDTH_GAP_ITERATION     (BITWIDTH_GAP_ITERATION)
) u_controller (
    .clk               (clk),
    .nrst              (nrst),
    // config
    .cfg               (cfg),
    // control
    .mac_enable        (mac_enable),
    .mac_iteration     (mac_iteration),
    .residual_enable   (residual_enable),
    .relu_enable       (relu_enable),
    .pooling_enable    (pooling_enable),
    .pooling_iteration (pooling_iteration),
    .gap_enable        (gap_enable),
    .gap_iteration     (gap_iteration),
    // I/O
    .in_enable         (in_enable),
    .out_enable        (out_enable),
    // DMAs
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
    .dma_result_last   (dma_result_last)
);

// --------------------------------
// Core
// --------------------------------
core #(
    .BITWIDTH                   (BITWIDTH),
    .BITWIDTH_MAC_ITERATION     (BITWIDTH_MAC_ITERATION),
    .BITWIDTH_POOLING_ITERATION (BITWIDTH_POOLING_ITERATION),
    .BITWIDTH_GAP_ITERATION     (BITWIDTH_GAP_ITERATION),
    .PARALLEL_PC                (PARALLEL_PC),
    .PARALLEL_PF                (PARALLEL_PF)
) u_core (
    .clk               (clk),
    .nrst              (nrst),
    // control
    .mac_enable        (mac_enable),        // mac 
    .mac_iteration     (mac_iteration),
    .residual_enable   (residual_enable),   // residual
    .relu_enable       (relu_enable),       // relu
    .pooling_enable    (pooling_enable),    // pooling
    .pooling_iteration (pooling_iteration), 
    .gap_enable        (gap_enable),        // GAP
    .gap_iteration     (gap_iteration),
    // input
    .in_enable         (in_enable),         
    .in_data           (),
    .kernel_data       (),                  
    .bias_data         (),
    // output
    .out_enable        (out_enable),        
    .out_data          ()
);

endmodule

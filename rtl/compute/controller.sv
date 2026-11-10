module controller #(
    // bitwidth 
    parameter integer CONFIG_BITWIDTH            = 32,
    parameter integer BITWIDTH_MAC_ITERATION     = 16,
    parameter integer BITWIDTH_POOLING_ITERATION = 16,
    parameter integer BITWIDTH_GAP_ITERATION     = 16
)(
    input  wire                                  clk,
    input  wire                                  nrst,

    // config
    input  wire [CONFIG_BITWIDTH-1:0]            cfg,
    output wire                                  mac_enable,
    output wire [BITWIDTH_MAC_ITERATION-1:0]     mac_iteration,
    output wire                                  residual_enable,
    output wire                                  relu_enable,
    output wire                                  pooling_enable,
    output wire [BITWIDTH_POOLING_ITERATION-1:0] pooling_iteration,
    output wire                                  gap_enable,
    output wire [BITWIDTH_GAP_ITERATION-1:0]     gap_iteration,
    
    // core input
    output wire                                  in_enable,
    input  wire                                  out_enable,
    
    // DMA feature
    input  wire                                  dma_feature_valid,
    output wire                                  dma_feature_ready,
    input  wire                                  dma_feature_last,

    // DMA kernel
    input  wire                                  dma_kernel_valid,
    output wire                                  dma_kernel_ready,
    input  wire                                  dma_kernel_last,
    
    // DMA output
    output wire                                  dma_output_valid,
    input  wire                                  dma_output_ready,
    output wire                                  dma_output_last,
    // Feature memory read
    input  wire                                  fmem_rd_valid,
    output wire                                  fmem_rd_ready,
    // Kernel memory read
    input  wire                                  kmem_rd_valid,
    output wire                                  kmem_rd_ready,
    // Residual memory write
    output wire                                  rmem_wr_valid,
    input  wire                                  rmem_wr_ready
);

// --------------------------------
// FSM
// -------------------------------



// --------------------------------
// counters
// --------------------------------



// --------------------------------
// core control
// --------------------------------


// --------------------------------
// buffer control
// --------------------------------

endmodule

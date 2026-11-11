module top_bottleneck #(
    // bitwidth 
    parameter integer BITWIDTH                   = 16,
    parameter integer CONFIG_BITWIDTH            = 32,
    parameter integer BITWIDTH_MAC_ITERATION     = 16,
    parameter integer BITWIDTH_POOLING_ITERATION = 16,
    parameter integer BITWIDTH_GAP_ITERATION     = 16,
    // parallelism
    parameter integer PARALLEL_PC                = 1,
    parameter integer PARALLEL_PF                = 1
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
// Buffer
// --------------------------------
localparam integer BRAM_DATA_WIDTH = 16;
localparam integer BRAM_DEPTH      = 2048;
localparam integer BRAM_ADDR_WIDTH = $clog2(BRAM_DEPTH);

// Feature buffer
wire                       feature_mem_wr_en   [0:1];
wire [BRAM_ADDR_WIDTH-1:0] feature_mem_wr_addr [0:1];
wire [BRAM_DATA_WIDTH-1:0] feature_mem_wr_data [0:1];
wire [BRAM_ADDR_WIDTH-1:0] feature_mem_rd_addr [0:1];
wire [BRAM_DATA_WIDTH-1:0] feature_mem_rd_data [0:1];

generate
    for (genvar i = 0; i < 2; i = i + 1) begin : gen_feature_mem
        blk_mem_gen_0 u_mem (
            .clka  (clk),
            .wea   (feature_mem_wr_en[i]),
            .addra (feature_mem_wr_addr[i]),
            .dina  (feature_mem_wr_data[i]),
            .clkb  (clk),
            .addrb (feature_mem_rd_addr[i]),
            .doutb (feature_mem_rd_data[i])
        );
    end
endgenerate

// Kernel buffer
wire                       kernel_mem_wr_en;
wire [BRAM_ADDR_WIDTH-1:0] kernel_mem_wr_addr;
wire [BRAM_DATA_WIDTH-1:0] kernel_mem_wr_data;
wire [BRAM_ADDR_WIDTH-1:0] kernel_mem_rd_addr;
wire [BRAM_DATA_WIDTH-1:0] kernel_mem_rd_data;

blk_mem_gen_0 u_kernel_mem (
    .clka  (clk),
    .wea   (kernel_mem_wr_en),
    .addra (kernel_mem_wr_addr),
    .dina  (kernel_mem_wr_data),
    .clkb  (clk),
    .addrb (kernel_mem_rd_addr),
    .doutb (kernel_mem_rd_data)
);

// Residual buffer
wire                       residual_mem_wr_en;
wire [BRAM_ADDR_WIDTH-1:0] residual_mem_wr_addr;
wire [BRAM_DATA_WIDTH-1:0] residual_mem_wr_data;
wire [BRAM_ADDR_WIDTH-1:0] residual_mem_rd_addr;
wire [BRAM_DATA_WIDTH-1:0] residual_mem_rd_data;

blk_mem_gen_0 u_residual_mem (
    .clka  (clk),
    .wea   (residual_mem_wr_en),
    .addra (residual_mem_wr_addr),
    .dina  (residual_mem_wr_data),
    .clkb  (clk),
    .addrb (residual_mem_rd_addr),
    .doutb (residual_mem_rd_data)
);

// --------------------------------
// Controller
// --------------------------------

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

controller #(
    .CONFIG_BITWIDTH            (CONFIG_BITWIDTH),
    .BITWIDTH_MAC_ITERATION     (BITWIDTH_MAC_ITERATION),
    .BITWIDTH_POOLING_ITERATION (BITWIDTH_POOLING_ITERATION),
    .BITWIDTH_GAP_ITERATION     (BITWIDTH_GAP_ITERATION)
) u_controller (
    .clk               (clk),
    .nrst              (nrst),
    .cfg               (cfg),
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
    .mac_enable        (mac_enable),
    .mac_iteration     (mac_iteration),
    .residual_enable   (residual_enable),
    .relu_enable       (relu_enable),
    .pooling_enable    (pooling_enable),
    .pooling_iteration (pooling_iteration),
    .gap_enable        (gap_enable),
    .gap_iteration     (gap_iteration),
    .in_enable         (in_enable),
    .in_data           (),
    .kernel_data       (),
    .out_enable        (out_enable),
    .out_data          ()
);

endmodule

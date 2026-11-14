module axi_bottleneck #(
    // bitwidth 
    localparam integer BITWIDTH                   = 16,
    parameter integer  BITWIDTH_MAC_ITERATION     = 16,
    parameter integer  BITWIDTH_POOLING_ITERATION = 16,
    parameter integer  BITWIDTH_GAP_ITERATION     = 16,
    // parallelism
    parameter integer  PARALLEL_PC                = 1,
    parameter integer  PARALLEL_PF                = 1,
    // AXI4-Lite  
    parameter integer  AXI_LITE_ADDR_WIDTH        = 32,
    parameter integer AXI_LITE_DATA_WIDTH         = 32,
    parameter [31:0]   CONFIG_DEFAULT             = '0,
    // Buffer address widths. Each RAM stores 2**width words.
    parameter integer BRAM_FEATRE_CAPACITY        = 14,
    parameter integer BRAM_KERNEL_CAPACITY        = 16,
    parameter integer BRAM_BIAS_CAPACITY          = 6
)(
    input  wire                             s_axi_aclk,
    input  wire                             s_axi_aresetn,

    // AXI4-Lite
    input  wire [AXI_LITE_ADDR_WIDTH-1:0]   s_axi_awaddr,
    input  wire [2:0]                       s_axi_awprot,
    input  wire                             s_axi_awvalid,
    output wire                             s_axi_awready,
    input  wire [AXI_LITE_DATA_WIDTH-1:0]   s_axi_wdata,
    input  wire [AXI_LITE_DATA_WIDTH/8-1:0] s_axi_wstrb,
    input  wire                             s_axi_wvalid,
    output wire                             s_axi_wready,
    output wire [1:0]                       s_axi_bresp,
    output wire                             s_axi_bvalid,
    input  wire                             s_axi_bready,
    input  wire [AXI_LITE_ADDR_WIDTH-1:0]   s_axi_araddr,
    input  wire [2:0]                       s_axi_arprot,
    input  wire                             s_axi_arvalid,
    output wire                             s_axi_arready,
    output wire [AXI_LITE_DATA_WIDTH-1:0]   s_axi_rdata,
    output wire [1:0]                       s_axi_rresp,
    output wire                             s_axi_rvalid,
    input  wire                             s_axi_rready,

    // IDMA feature
    input  wire [BITWIDTH-1:0]              s_axis_feature_tdata,
    input  wire                             s_axis_feature_tvalid,
    input  wire                             s_axis_feature_tlast,
    output wire                             s_axis_feature_tready,

    // IDMA kernel
    input  wire [BITWIDTH-1:0]              s_axis_kernel_tdata,
    input  wire                             s_axis_kernel_tvalid,
    input  wire                             s_axis_kernel_tlast,
    output wire                             s_axis_kernel_tready,

    // IDMA bias
    input  wire [BITWIDTH-1:0]              s_axis_bias_tdata,
    input  wire                             s_axis_bias_tvalid,
    input  wire                             s_axis_bias_tlast,
    output wire                             s_axis_bias_tready,

    // ODMA
    output wire [BITWIDTH-1:0]              m_axis_output_tdata,
    output wire [BITWIDTH/8-1:0]            m_axis_output_tkeep,
    output wire                             m_axis_output_tvalid,
    input  wire                             m_axis_output_tready,
    output wire                             m_axis_output_tlast
);
// ----------------------------------------
// DMA control
// ----------------------------------------
assign m_axis_output_tkeep = '1;

// ----------------------------------------
// axi-lite register
// ----------------------------------------
wire [AXI_LITE_DATA_WIDTH-1:0] cfg;
wire                           cfg_enable;
wire [3:0]                     cfg_response;

axi_lite_reg #(
    .AXI_LITE_ADDR_WIDTH (AXI_LITE_ADDR_WIDTH),
    .AXI_LITE_DATA_WIDTH (AXI_LITE_DATA_WIDTH),
    .DEFAULT             (CONFIG_DEFAULT)
) u_axi_lite_reg (
    .s_axi_aclk    (s_axi_aclk),
    .s_axi_aresetn (s_axi_aresetn),
    .s_axi_awaddr  (s_axi_awaddr),
    .s_axi_awprot  (s_axi_awprot),
    .s_axi_awvalid (s_axi_awvalid),
    .s_axi_awready (s_axi_awready),
    .s_axi_wdata   (s_axi_wdata),
    .s_axi_wstrb   (s_axi_wstrb),
    .s_axi_wvalid  (s_axi_wvalid),
    .s_axi_wready  (s_axi_wready),
    .s_axi_bresp   (s_axi_bresp),
    .s_axi_bvalid  (s_axi_bvalid),
    .s_axi_bready  (s_axi_bready),
    .s_axi_araddr  (s_axi_araddr),
    .s_axi_arprot  (s_axi_arprot),
    .s_axi_arvalid (s_axi_arvalid),
    .s_axi_arready (s_axi_arready),
    .s_axi_rdata   (s_axi_rdata),
    .s_axi_rresp   (s_axi_rresp),
    .s_axi_rvalid  (s_axi_rvalid),
    .s_axi_rready  (s_axi_rready),
    .cfg_data      (cfg),
    .cfg_data_enable (cfg_enable),
    .cfg_response    (cfg_response)
);

// ----------------------------------------
// Top
// ----------------------------------------

top_bottleneck #(
    .BITWIDTH                   (BITWIDTH),
    .CONFIG_BITWIDTH            (AXI_LITE_DATA_WIDTH),
    .BITWIDTH_MAC_ITERATION     (BITWIDTH_MAC_ITERATION),
    .BITWIDTH_POOLING_ITERATION (BITWIDTH_POOLING_ITERATION),
    .BITWIDTH_GAP_ITERATION     (BITWIDTH_GAP_ITERATION),
    .PARALLEL_PC                (PARALLEL_PC),
    .PARALLEL_PF                (PARALLEL_PF),
    .BRAM_FEATRE_CAPACITY       (BRAM_FEATRE_CAPACITY),
    .BRAM_KERNEL_CAPACITY       (BRAM_KERNEL_CAPACITY),
    .BRAM_BIAS_CAPACITY          (BRAM_BIAS_CAPACITY)
) u_top_bottleneck (
    .clk               (s_axi_aclk),
    .nrst              (s_axi_aresetn),
    .cfg_enable        (cfg_enable),
    .cfg               (cfg),
    .cfg_response      (cfg_response),
    .dma_feature_valid (s_axis_feature_tvalid),
    .dma_feature_ready (s_axis_feature_tready),
    .dma_feature_last  (s_axis_feature_tlast),
    .dma_feature_data  (s_axis_feature_tdata),
    .dma_kernel_valid  (s_axis_kernel_tvalid),
    .dma_kernel_ready  (s_axis_kernel_tready),
    .dma_kernel_last   (s_axis_kernel_tlast),
    .dma_kernel_data   (s_axis_kernel_tdata),
    .dma_bias_valid    (s_axis_bias_tvalid),
    .dma_bias_ready    (s_axis_bias_tready),
    .dma_bias_last     (s_axis_bias_tlast),
    .dma_bias_data     (s_axis_bias_tdata),
    .dma_result_valid  (m_axis_output_tvalid),
    .dma_result_ready  (m_axis_output_tready),
    .dma_result_last   (m_axis_output_tlast),
    .dma_result_data   (m_axis_output_tdata)
);

endmodule

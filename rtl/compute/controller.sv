module controller #(
    // bitwidth 
    parameter integer CONFIG_BITWIDTH            = 32,
    parameter integer CONFIG_DATA_BITWIDTH      = 6,
    parameter integer BITWIDTH_MAC_ITERATION     = 16,
    parameter integer BITWIDTH_POOLING_ITERATION = 16,
    parameter integer BITWIDTH_GAP_ITERATION     = 16,
    parameter integer BRAM_FEATRE_CAPACITY       = 14,
    parameter integer BRAM_KERNEL_CAPACITY       = 16,
    parameter integer BRAM_BIAS_CAPACITY         = 6,
    parameter integer ADDR_BITWIDTH             = 3
)(
    input  wire                                  clk,
    input  wire                                  nrst,

    // config
    input  wire                                  cfg_enable,
    input  wire [CONFIG_BITWIDTH-1:0]            cfg,
    output wire [3:0]                            cfg_response,
    output reg                                   mac_enable,
    output reg  [BITWIDTH_MAC_ITERATION-1:0]     mac_iteration,
    output reg                                   residual_enable,
    output reg                                   relu_enable,
    output reg                                   pooling_enable,
    output reg  [BITWIDTH_POOLING_ITERATION-1:0] pooling_iteration,
    output reg                                   gap_enable,
    output reg  [BITWIDTH_GAP_ITERATION-1:0]     gap_iteration,
    
    // core input
    output reg                                   in_enable,
    input  wire                                  out_enable,
    output reg                                  output_init_flag,

    // top control
    output reg                                   is_fmem0_in,
    output reg                                   is_zero,
    output wire                                  is_feature_in,
    
    // DMA feature
    input  wire                                  dma_feature_valid,
    output wire                                  dma_feature_ready,
    input  wire                                  dma_feature_last,

    // DMA kernel
    input  wire                                  dma_kernel_valid,
    output wire                                  dma_kernel_ready,
    input  wire                                  dma_kernel_last,

    // DMA bias
    input  wire                                  dma_bias_valid,
    output wire                                  dma_bias_ready,
    input  wire                                  dma_bias_last,
    
    // DMA output
    output wire                                  dma_result_valid,
    input  wire                                  dma_result_ready,
    output wire                                  dma_result_last,
    // Feature
    output wire                                  fmem_wr_enable[0:1],
    output wire [BRAM_FEATRE_CAPACITY-1:0]       fmem_wr_addr[0:1],
    output wire [BRAM_FEATRE_CAPACITY-1:0]       fmem_rd_addr[0:1],
    // Kernel                                    
    output wire                                  kmem_wr_enable,
    output wire [BRAM_KERNEL_CAPACITY-1:0]       kmem_rd_addr,
    output wire [BRAM_KERNEL_CAPACITY-1:0]       kmem_wr_addr,
    // Bias                                      
    output wire                                  bmem_wr_enable,
    output wire [BRAM_BIAS_CAPACITY-1:0]         bmem_rd_addr,
    output wire [BRAM_BIAS_CAPACITY-1:0]         bmem_wr_addr,
    // Residual                                  
    output wire                                  rmem_wr_enable,
    output wire [BRAM_FEATRE_CAPACITY-1:0]       rmem_rd_addr,
    output wire [BRAM_FEATRE_CAPACITY-1:0]       rmem_wr_addr
);

// FSM
typedef enum reg [7:0] {
    IDLE       = 8'b00000001,
    DECODE     = 8'b00000010,
    IN_FEATURE = 8'b00000100,
    IN_KERNEL  = 8'b00001000,
    IN_BIAS    = 8'b00010000,
    RUN        = 8'b00100000,
    OUTPUT     = 8'b01000000,
    ERROR      = 8'b10000000
} state_t;

typedef enum reg [3:0] { 
    RESP_IDLE     = 4'b0000,
    RESP_DONE     = 4'b0001,
    RESP_INPUT    = 4'b0010,
    RESP_RUN      = 4'b0100,
    RESP_OUTPUT   = 4'b0110,
    RESP_ERROR    = 4'b1000
} response_t;

// counter
localparam BITWIDTH_CNT = 32;

// core
localparam LATENCY_RESIDUAL = 1;
localparam LATENCY_CORE = 1;

// ----------------------------------------------------------------
// wire & reg
// ----------------------------------------------------------------
// FSM
state_t                 cstate; // current
response_t              rstate; // response

reg                     is_fisrt_IDLE;

wire [BITWIDTH_CNT-1:0] len_feature;
wire [BITWIDTH_CNT-1:0] len_kernel;
wire [BITWIDTH_CNT-1:0] len_bias;
wire [BITWIDTH_CNT-1:0] len_output;

// counter
reg [BITWIDTH_CNT-1:0] cnt_feature;
reg [BITWIDTH_CNT-1:0] cnt_kernel;
reg [BITWIDTH_CNT-1:0] cnt_bias;
reg [BITWIDTH_CNT-1:0] cnt_run;
reg [BITWIDTH_CNT-1:0] cnt_output;
reg [BITWIDTH_CNT-1:0] cnt_dma_output;

// configure
wire                              cfg_input_enable;
wire                              cfg_output_enable;
wire                              cfg_mac_enable;
wire                              cfg_residual_enable;
wire                              cfg_relu_enable;
wire                              cfg_pooling_enable;
wire                              cfg_gap_enable;
wire                              cfg_is_skip;    
wire                              cfg_stride;     
wire                              cfg_padding;    
wire [CONFIG_DATA_BITWIDTH-1:0]   cfg_w;
wire [CONFIG_DATA_BITWIDTH-1:0]   cfg_h;
wire [CONFIG_DATA_BITWIDTH-1:0]   cfg_c;

reg                               ctrl_input_enable;
reg                               ctrl_output_enable;
reg                               ctrl_is_skip;
reg                               ctrl_is_after_skip;
reg [CONFIG_DATA_BITWIDTH-1:0]    ctrl_fw, ctrl_fc; // width == height
reg [CONFIG_DATA_BITWIDTH-1:0]    ctrl_kw, ctrl_kc;
reg [CONFIG_DATA_BITWIDTH-1:0]    ctrl_ow, ctrl_oc;
reg                               ctrl_padding;
reg                               ctrl_stride;

wire [CONFIG_DATA_BITWIDTH-1:0]   ctrl_ow_next;

// core
reg [ADDR_BITWIDTH-1:0] addr_frow;
reg [ADDR_BITWIDTH-1:0] addr_fcol;
reg [ADDR_BITWIDTH-1:0] addr_cin;
reg [ADDR_BITWIDTH-1:0] addr_krow;
reg [ADDR_BITWIDTH-1:0] addr_kcol;
reg [ADDR_BITWIDTH-1:0] addr_cout; 
reg [ADDR_BITWIDTH-1:0] addr_orow;
reg [ADDR_BITWIDTH-1:0] addr_ocol;
reg [ADDR_BITWIDTH-1:0] addr_oc; 

wire [BRAM_FEATRE_CAPACITY-1:0] core_in_f_addr;
wire [BRAM_KERNEL_CAPACITY-1:0] core_in_k_addr;
wire [BRAM_BIAS_CAPACITY-1:0] core_in_b_addr;
wire [BRAM_FEATRE_CAPACITY-1:0] core_out_f_addr;

wire [BRAM_FEATRE_CAPACITY-1:0] fmem_rd_addr_temp;
wire [BRAM_FEATRE_CAPACITY-1:0] output_read_addr;

// DMA
wire dma_kernel_hk;
wire dma_bias_hk;
wire dma_feature_hk;
wire dma_result_hk;   

// ----------------------------------------------------------------
// FSM
// ----------------------------------------------------------------
`include "controller_fsm.svh"

assign is_feature_in = ctrl_input_enable & (cstate == IN_FEATURE);

always @(posedge clk or negedge nrst) begin
    if (!nrst) begin
       output_init_flag <= 0; 
    end else begin
        output_init_flag <= cnt_dma_output == 0; 
    end
end
// ----------------------------------------------------------------
// counter
// ----------------------------------------------------------------
`include "controller_counter.svh"
 
// ----------------------------------------------------------------
// configure
// ----------------------------------------------------------------
`include "controller_configure.svh"

// ----------------------------------------------------------------
// core
// ----------------------------------------------------------------
`include "controller_core.svh"


// ----------------------------------------------------------------
// AXI control
// ----------------------------------------------------------------
`include "controller_axi.svh"

endmodule

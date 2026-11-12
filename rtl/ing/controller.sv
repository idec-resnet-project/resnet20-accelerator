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

    // DMA bias
    input  wire                                  dma_bias_valid,
    output wire                                  dma_bias_ready,
    input  wire                                  dma_bias_last,
    
    // DMA output
    output wire                                  dma_result_valid,
    input  wire                                  dma_result_ready,
    output wire                                  dma_result_last,
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
    RESP_IDLE       = 4'b0000,
    DONE            = 4'b0001,
    INPUT           = 4'b0010,
    RESP_RUN        = 4'b0100,
    RESP_OUTPUT     = 4'b0110,
    DECODE_ERROR    = 4'b1000, // error case : 의미는 크게 없고 Wave 편의로 그냥 추가함. 
    INPUT_ERROR     = 4'b1010,
    RUN_ERROR       = 4'b1100,
    OUTPUT_ERROR    = 4'b1110
} response_t;

// counter
localparam BITWIDTH_CNT = 32;

// --------------------------------
// wire & reg
// --------------------------------
// FSM
state_t     cstate; // current
state_t     nstate; // next
response_t  rstate; // response

// counter
reg [BITWIDTH_CNT-1:0] cnt_feature;
reg [BITWIDTH_CNT-1:0] cnt_kernel;
reg [BITWIDTH_CNT-1:0] cnt_bias;
reg [BITWIDTH_CNT-1:0] cnt_run;
reg [BITWIDTH_CNT-1:0] cnt_output;

// buffer switch
reg is_bmem_in; // use with core

// configure
wire            input_enable,
wire            output_enable,
wire            is_skip,        // if (is_skip == 1) save core output in residual buffer
wire            stride,         // stride-1 (1~2)
wire            padding,        // padding (0~1)
wire            size,           // {W-1, H-1, C-1} 각 6bit 씩
wire            PL_state   


// CNN
reg [5:0] fw, fc; // width == height
reg [5:0] kw, kd, kc;
reg [5:0] ow, oc
wire padding;
wire stride;
reg [BITWIDTH_CNT:0] len_in, len_out;

// --------------------------------
// FSM
// -------------------------------

// --------------------------------
// core control
// --------------------------------
// config
assign mac_enable       = cfg[2];
assign residual_enable  = cfg[3];
assign relu_enable      = cfg[4];
assign pool_enable      = cfg[5];
assign gap_enable       = cfg[6];
assign stride           = cfg[8];
assign padding          = cfg[8]; 


// --------------------------------
// AXI control
// --------------------------------


// -------------------------------- 
// calc CNN  
// --------------------------------
always_ff @(negedge clk or posedge nrst) begin : update_feaure_size
    if (!nrst) begin
        fw <= 0;
        fc <= 0;
    end else if (cstat == IN_FEATURE) begin
        fw <= cfg[]
always_ff @(negedge clk or posedge nrst) begin : calc_CNN_size
    if (!nrst) begin
        fw <= 0;
        fc <= 0;
        kw <= 0;
        kd <= 0;
        kc <= 0;
        padding <= 0;
        stride <= 0;
    end
end


endmodule

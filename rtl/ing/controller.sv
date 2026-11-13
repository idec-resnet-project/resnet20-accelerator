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
    output reg                                   mac_enable,
    output reg  [BITWIDTH_MAC_ITERATION-1:0]     mac_iteration,
    output reg                                   residual_enable,
    output reg                                   relu_enable,
    output reg                                   pooling_enable,
    output reg  [BITWIDTH_POOLING_ITERATION-1:0] pooling_iteration,
    output reg                                   gap_enable,
    output reg  [BITWIDTH_GAP_ITERATION-1:0]     gap_iteration,
    
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
localparam BITWIDTH_CTG_DATA = 6;

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

// DMA
wire dma_kernel_hk;
wire dma_bias_hk;
wire dma_feature_hk;
wire dma_result_hk;

// configure
wire                              cfg_input_enable;
wire                              cfg_output_enable;
wire                              cfg_mac_enable;
wire                              cfg_residualenable;
wire                              cfg_relu_enable;
wire                              cfg_pooling_enable;
wire                              cfg_gap_enable;
wire                              cfg_is_skip;    
wire                              cfg_stride;     
wire                              cfg_padding;    
wire [BITWIDTH_CTG_DATA-1:0]      cfg_w;    
wire [BITWIDTH_CTG_DATA-1:0]      cfg_h;       
wire [BITWIDTH_CTG_DATA-1:0]      cfg_c;       

// CNN
reg [BITWIDTH_CTG_DATA-1:0]  fw, fc; // width == height
reg [BITWIDTH_CTG_DATA-1:0]  kw, kd, kc;
reg [BITWIDTH_CTG_DATA-1:0]  ow, oc
wire                         padding;
wire                         stride;
reg [BITWIDTH_CNT-1:0]       len_in, len_out;
wire [BITWIDTH_CTG_DATA-1:0] next_ow;

// --------------------------------
// FSM
// -------------------------------


// --------------------------------
// count
// --------------------------------
always_ff @(negedge clk or posedge nrst) begin : counter_feature
    if (!nrst) begin
        cnt_feature <= 0;
    end else if ()
end
 

// --------------------------------
// core control
// --------------------------------
// config
assign cfg_input_enable     = cfg[0]; 
assign cfg_output_enable    = cfg[1]; 
assign cfg_mac_enable       = cfg[2];
assign cfg_residualenable   = cfg[3];
assign cfg_relu_enable      = cfg[4];
assign cfg_pooling_enable   = cfg[5];
assign cfg_gap_enable       = cfg[6];
assign cfg_is_skip          = cfg[7];
assign cfg_stride           = cfg[8];
assign cfg_padding          = cfg[9];
assign cfg_w                = cfg[15:10];
assign cfg_h                = cfg[21:16];
assign cfg_c                = cfg[27:22];

assign next_ow              = ((ow - ctg_w + {ctg_padding, 1'b0}) << ctg_stride) + 1;

always_ff @(negedge clk or posedge nrst) begin : update_config
    if (!nrst) begin
        mac_enable      <= '0;
        residualenable  <= '0;
        relu_enable     <= '0;
        pooling_enable  <= '0;
        gap_enable      <= '0;
    end else if (cstat == DECODE) begin
        mac_enable      <= cfg_mac_enable;
        residualenable  <= cfg_residualenable;
        relu_enable     <= cfg_relu_enable;
        pooling_enable  <= cfg_pooling_enable;
        gap_enable      <= cfg_gap_enable;
    end else begin
        mac_enable      <= mac_enable; 
        residualenable  <= residualenable; 
        relu_enable     <= relu_enable; 
        pooling_enable  <= pooling_enable; 
        gap_enable      <= gap_enable; 
    end
end

always_ff @(negedge clk or posedge nrst) begin : calc_CNN_size
    if (!nrst) begin
        fw      <= '0;
        fc      <= '0;
        kw      <= '0;
        kd      <= '0;
        kc      <= '0;
        ow      <= '0;
        oc      <= '0;
        padding <= '0;
        stride  <= '0;
    end else if (cstate == DECODE) begin
        if (ctg_input_enable) begin
            fw      <= fw;
            fc      <= fc;
            kw      <= kw;
            kd      <= kd;
            kc      <= kc;
            ow      <= cfg_w;
            oc      <= cfg_c;
            padding <= padding;
            stride  <= stride;
        end else begin
            fw      <= ow;
            fc      <= oc;
            kw      <= cfg_w;
            kd      <= oc;
            kc      <= cfg_c;
            ow      <= next_ow;
            oc      <= ctg_c;
            padding <= ctg_padding;
            stride  <= ctg_stride;
        end
    end else begin
        fw      <= fw;
        fc      <= fc;
        kw      <= kw;
        kd      <= kd;
        kc      <= kc;
        ow      <= ow;
        oc      <= oc;
        padding <= padding;
        stride  <= stride;
    end
end


// --------------------------------
// AXI control
// --------------------------------



endmodule

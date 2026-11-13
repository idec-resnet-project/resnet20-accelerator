module controller #(
    // bitwidth 
    parameter integer CONFIG_BITWIDTH            = 32,
    parameter integer BITWIDTH_MAC_ITERATION     = 16,
    parameter integer BITWIDTH_POOLING_ITERATION = 16,
    parameter integer BITWIDTH_GAP_ITERATION     = 16,
    parameter integer BRAM_FEATRE_CAPACITY       = 14,
    parameter integer BRAM_KERNEL_CAPACITY       = 16,
    parameter integer BRAM_BIAS_CAPACITY         = 6
)(
    input  wire                                  clk,
    input  wire                                  nrst,

    // config
    input  wire                                  cfg_enable,
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

    // top control
    output reg                                   is_bmem0_in,
    
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
    output reg  [BRAM_FEATRE_CAPACITY-1:0]       fmem_wr_addr[0:1],
    output reg  [BRAM_FEATRE_CAPACITY-1:0]       fmem_rd_addr[0:1],
    // Kernel                                    
    output wire                                  kmem_wr_enable,
    output reg  [BRAM_KERNEL_CAPACITY-1:0]       kmem_rd_addr,
    output reg  [BRAM_KERNEL_CAPACITY-1:0]       kmem_wr_addr,
    // Bias                                      
    output wire                                  bmem_wr_enable,
    output reg  [BRAM_BIAS_CAPACITY-1:0]         bmem_rd_addr,
    output reg  [BRAM_BIAS_CAPACITY-1:0]         bmem_wr_addr,
    // Residual                                  
    output wire                                  rmem_wr_enable,
    output reg  [BRAM_FEATRE_CAPACITY-1:0]         rmem_rd_addr,
    output reg  [BRAM_FEATRE_CAPACITY-1:0]         rmem_wr_addr
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
localparam BITWIDTH_CfG_DATA = 6;
localparam LATENCY_RESIDUAL = 1;

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
reg [BITWIDTH_CNT-1:0] cnt_dma_output;

wire len_feaure;
wire len_kernel;
wire len_bias;
wire len_output;

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
wire                              cfg_residual_enable;
wire                              cfg_relu_enable;
wire                              cfg_pooling_enable;
wire                              cfg_gap_enable;
wire                              cfg_is_skip;    
wire                              cfg_stride;     
wire                              cfg_padding;    
wire [BITWIDTH_CfG_DATA-1:0]      cfg_w;    
wire [BITWIDTH_CfG_DATA-1:0]      cfg_h;       
wire [BITWIDTH_CfG_DATA-1:0]      cfg_c;       

reg                               input_enable;
reg                               output_enable;

// CNN
reg [BITWIDTH_CfG_DATA-1:0]  fw, fc; // width == height
reg [BITWIDTH_CfG_DATA-1:0]  kw, kd, kc;
reg [BITWIDTH_CfG_DATA-1:0]  ow, oc;
reg                         padding;
reg                         stride;
reg [BITWIDTH_CNT-1:0]       len_in, len_out;
wire [BITWIDTH_CfG_DATA-1:0] next_ow;

// --------------------------------
// FSM
// -------------------------------
assign len_feature = (fw+1) * (fw+1) * (fc+1) - 1;
assign len_kernel = (kw+1) * (kw+1) * (kc+1) * (kd+1) - 1;
assign len_bias = fc;
assign len_output = (ow+1) * (ow+1) * (oc+1) - 1;

always_ff @(posedge clk or posedge nrst) begin : fmem_select
    if (!nrst) begin
        is_bmem0_in <= 1;
    end else if (cstate == DECODE) begin
        is_bmem0_in <= ~is_bmem0_in;
    end else begin
        is_bmem0_in <= is_bmem0_in;
    end
end

always_ff @(posedge clk or posedge nrst) begin : FSM_cstate
    if (!nrst) begin
        cstate <= IDLE;
    end else begin
        case(cstate)
            IDLE: begin
                if (cfg_enable) begin // TODO : make port cfg_enable
                    cstate <= DECODE;
                end else begin
                    cstate <= IDLE;
                end   
            end
            DECODE: begin
                if (input_enable) begin
                    cstate <= IN_FEATURE;
                end else if (mac_enable) begin
                    cstate <= IN_KERNEL;
                end else begin
                    cstate <= ERROR;
                end
            end
            IN_FEATURE: begin
                if (cnt_feature == len_feature) begin
                    if (mac_enable) begin
                        cstate <= IN_KERNEL;
                    end else if (cfg[6:2] == '0) begin
                        cstate <= IDLE;
                    end else begin
                        cstate <= RUN;
                    end
                end else begin
                    cstate <= IN_FEATURE;
                end   
            end
            IN_KERNEL: begin
                if (cnt_kernel == len_kernel) begin
                    cstate <= IN_BIAS;
                end else begin
                    cstate <= IN_KERNEL;
                end   
            end
            IN_BIAS: begin
                if (cnt_bias == len_bias) begin
                    cstate <= RUN;
                end else begin
                    cstate <= IN_BIAS;
                end   
            end
            RUN: begin
                if (cnt_output == len_output) begin
                    if (cfg_output_enable) begin
                        cstate <= OUTPUT;
                    end else begin
                        cstate <= IDLE;
                    end
                end else begin
                    cstate <= RUN;
                end   
            end
            OUTPUT: begin
                if (cnt_dma_output == len_output) begin
                    cstate <= IDLE;
                end else begin
                    cstate <= OUTPUT;
                end   
            end
            ERROR: begin
                if (cfg_enable) begin
                    cstate <= DECODE;
                end else begin
                    cstate <= ERROR;
                end   
            end
            default:
                cstate <= IDLE;
        endcase
    end
end


// --------------------------------
// count
// --------------------------------
// DMA
always_ff @(negedge clk or posedge nrst) begin : counter_feature
    if (!nrst) begin
        cnt_feature <= 0;
    end else if (dma_feature_hk) begin
        cnt_feature <= cnt_feature + 1;
    end else begin
        cnt_feature <= cnt_feature;
    end
end

always_ff @(negedge clk or posedge nrst) begin : counter_kernel
    if (!nrst) begin
        cnt_kernel <= 0;
    end else if (dma_kernel_hk) begin
        cnt_kernel <= cnt_kernel + 1;
    end else begin
        cnt_kernel <= cnt_kernel;
    end
end

always_ff @(negedge clk or posedge nrst) begin : counter_bias
    if (!nrst) begin
        cnt_bias <= 0;
    end else if (dma_bias_hk) begin
        cnt_bias <= cnt_bias + 1;
    end else begin
        cnt_bias <= cnt_bias;
    end
end

always_ff @(negedge clk or posedge nrst) begin : counter_dma_output
    if (!nrst) begin
        cnt_dma_output <= 0;
    end else if (dma_result_hk) begin
        cnt_dma_output <= cnt_dma_output + 1;
    end else begin
        cnt_dma_output <= cnt_dma_output;
    end
end


// core
always_ff @(negedge clk or posedge nrst) begin : counter_core_in
    if (!nrst) begin
        cnt_run <= 0;
    end else if (cstate == RUN) begin
        cnt_run <= cnt_run + 1;
    end else begin
        cnt_run <= cnt_run;
    end
end

always_ff @(negedge clk or posedge nrst) begin : counter_core_out
    if (!nrst) begin
        cnt_output <= 0;
    end else if (out_enable) begin
        cnt_output <= cnt_output + 1;
    end else begin
        cnt_output <= cnt_output;
    end
end

 

// --------------------------------
// core control
// --------------------------------
// config
assign cfg_input_enable     = cfg[0]; 
assign cfg_output_enable    = cfg[1]; 
assign cfg_mac_enable       = cfg[2];
assign cfg_residual_enable   = cfg[3];
assign cfg_relu_enable      = cfg[4];
assign cfg_pooling_enable   = cfg[5];
assign cfg_gap_enable       = cfg[6];
assign cfg_is_skip          = cfg[7];
assign cfg_stride           = cfg[8];
assign cfg_padding          = cfg[9];
assign cfg_w                = cfg[15:10];
assign cfg_h                = cfg[21:16];
assign cfg_c                = cfg[27:22];

assign next_ow              = ((ow - cfg_w + {cfg_padding, 1'b0}) << cfg_stride) + 1;

always_ff @(negedge clk or posedge nrst) begin : update_config
    if (!nrst) begin
        input_enable    <= '0;
        output_enable   <= '0;
        mac_enable      <= '0;
        residual_enable  <= '0;
        relu_enable     <= '0;
        pooling_enable  <= '0;
        gap_enable      <= '0;
    end else if (cstate == DECODE) begin
        input_enable    <= cfg_input_enable;
        output_enable   <= cfg_output_enable;
        mac_enable      <= cfg_mac_enable;
        residual_enable  <= cfg_residual_enable;
        relu_enable     <= cfg_relu_enable;
        pooling_enable  <= cfg_pooling_enable;
        gap_enable      <= cfg_gap_enable;
    end else begin
        input_enable    <= input_enable;
        output_enable   <= output_enable;
        mac_enable      <= mac_enable; 
        residual_enable  <= residual_enable; 
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
        if (cfg_input_enable) begin
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
            oc      <= cfg_c;
            padding <= cfg_padding;
            stride  <= cfg_stride;
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
assign dma_feature_hk   = dma_feature_valid & dma_feature_ready;
assign dma_featur_ready = cstate[3];

assign dma_kernel_hk    = dma_kernel_valid  & dma_kernel_ready;
assign dma_kernel_ready = cstate[4];

assign dma_bias_hk      = dma_bias_valid    & dma_bias_ready;
assign dma_biad_ready   = cstate[5];

assign dma_result_hk    = dma_result_valid  & dma_result_ready;
assign dma_result_valid = cstate[6];
assign dma_result_islast= (cnt_dma_output == len_output);

endmodule

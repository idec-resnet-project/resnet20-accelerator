module controller #(
    // bitwidth 
    parameter integer CONFIG_BITWIDTH               = 32,
    parameter integer BITWIDTH_MAC_ITERATION        = 16,
    parameter integer BITWIDTH_POOLING_ITERATION    = 16,
    parameter integer BITWIDTH_GAP_ITERATION        = 16,
    parameter integer LAYER_DEPTH                   = 30,
    parameter integer BRAM_FEATRE_CAPACITY          = 14,
    parameter integer BRAM_KERNEL_CAPACITY          = 16,
    parameter integer BRAM_BIAS_CAPACITY            = 6,
    parameter integer CONFIG_DATA_BITWIDTH          = 6,
    parameter integer ADDR_BITWIDTH                 = 3   
)(
    input  wire                                  clk,
    input  wire                                  nrst,

    // config
    input  wire [CONFIG_BITWIDTH-1:0]            cfg,
    input  wire                                  cfg_enable,
    input  wire [3:0]                            cfg_response,
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
    localparam BITWIDTH_CNT = 32;
    // FSM - for one-hot encoding
    typedef enum logic [7:0] {
        STATE_IDLE          = 8'b00000001,
        STATE_DECODE        = 8'b00000010,
        STATE_IN_FEATURE    = 8'b00000100,
        STATE_IN_PARAM      = 8'b00001000,
        STATE_RUN           = 8'b00010000,
        STATE_DRAIN         = 8'b00100000,
        STATE_OUTPUT        = 8'b01000000,
        STATE_ERROR         = 8'b10000000
    } state_t;

    typedef enum logic [3:0] { 
        RESP_IDLE           = 4'b0000,
        RESP_DONE           = 4'b0001,
        RESP_INPUT          = 4'b0010,
        RESP_RUN            = 4'b0100,
        RESP_OUTPUT         = 4'b0110,
        RESP_DECODE_ERROR   = 4'b1000, // error case : 의미는 크게 없고 Wave 편의로 그냥 추가함. 
        RESP_INPUT_ERROR    = 4'b1010,
        RESP_RUN_ERROR      = 4'b1100,
        RESP_OUTPUT_ERROR   = 4'b1110
    }response_t;

    typedef enum logic [3:0] { 
        MAC_IDLE                    = 4'd0,
        MAC_INPUT                   = 4'd1,
        MAC_CONV                    = 4'd2,
        MAC_SKIP                    = 4'd3,
        MAC_CONV_RELU               = 4'd4,
        MAC_CONV_REDSIDUAL_RELU     = 4'd5,
        MAC_SKIP_CONV               = 4'd6, // error case : 의미는 크게 없고 Wave 편의로 그냥 추가함. 
        MAC_CONV_REDSIDUAL_RELU_GAP = 4'd7,
        MAC_FC_OUT                  = 4'd8
    }network_t;

    typedef struct packed {
        logic [3:0]  PL_state;       // [31:28]  읽기 시 상태 응답 자리
        logic [17:0] size;           // [27:10]  {C-1, H-1, W-1}, 각 6비트
        logic        padding;        // [9]      padding (0~1)
        logic        stride;         // [8]      stride-1 (1~2)
        logic        is_skip;        // [7]      if (is_skip == 1) save core output in residual buffer
        logic [4:0]  core_enable;    // [6:2]    {mac, residual, relu, pooling, GAP}
        logic        output_enable;  // [1]
        logic        input_enable;   // [0]
    } op_code_t;

    // wire & reg
    // --------------------------------
    // FSM
    state_t     state_now;       // current
    state_t     state_past;        // next
    response_t  resp_state;     // response
    network_t   layer_state;    // layer status

    
    reg [BITWIDTH_MAC_ITERATION-1:0]        counter_iteration_mac;
    reg [BITWIDTH_POOLING_ITERATION-1:0]    counter_iteration_pooling;
    reg [BITWIDTH_GAP_ITERATION-1:0]        counter_iteration_gap;
    reg [PHASE_ITERATION-1:0]               counter_iteration_phase;
    //reg [LAYER_DEPTH-1:0]                   = 30

    op_code_t op_code,op_past;
    wire cfg_transition;
    wire idle_end,decode_end,feature_end,parameter_end,run_end,drain_end,output_end,error_escape;
    
    // counter
    reg [BITWIDTH_CNT-1 :0] cnt_feature;
    reg [BITWIDTH_CNT-1 :0] cnt_kernel;
    reg [BITWIDTH_CNT-1 :0] cnt_bias;
    reg [BITWIDTH_CNT-1 :0] cnt_run;
    reg [BITWIDTH_CNT-1 :0] cnt_output;
    reg [LAYER_DEPTH-1  :0] cnt_layer;

    //wire op_transition = cfg_transition;
    //wire cmd_transition = (op_past[31:28] != cmd_code);

    assign idle_end          = (~idle_past)         &    idle_last;
    assign decode_end        = (~decode_past)       &    decode_last;
    assign feature_end       = (~feature_past)      &    feature_last;
    assign parameter_end     = (~parameter_past)    &    parameter_last;
    assign run_end           = (~run_past)          &    run_last;
    assign drain_end         = (~drain_past)        &    drain_last;
    assign output_end        = (~output_past)       &    output_last;
    assign error_escape      = (~error_escape)      &    error_last;
    
    assign cfg_transition = (~cfg_enable_past) & cfg_enable;
        // --------------------------------
        
    // counter

    //layer 
   
    assign cmd_code         = cfg[31:28];      //Read bits?
    assign input_channel    = cfg[27:22];      //size : channel - 1
    assign input_height     = cfg[21:16];      //size : height -1
    assign input_width      = cfg[15:10];      //size : width -1
    assign padding          = cfg[9];          //padding
    assign stride           = cfg[8];          //stride
    assign is_skip          = cfg[7];          //is_skip
    assign mac_enable       = cfg[6];          //core_enable : MAC
    assign residual_enable  = cfg[5];          //core_enable : Residual
    assign relu_enable      = cfg[4];          //core_enable : ReLU
    assign pooling_enable   = cfg[3];          //core_enable : Pooling
    assign gap_enable       = cfg[2];          //core_enable : GAP
    assign output_enable    = cfg[1];          //output_enable       
    assign input_enable     = cfg[0];          //input_enable

    assign dma_feature_ready = dma_feature_valid & dma_feature_last;
    assign dma_kernel_ready = dma_kernel_valid & dma_kernel_last;
    assign dma_bias_ready = dma_bias_valid & dma_bias_last;

    assign op_code = cfg_enable? 

    always_ff @(posedge clk or negedge nrst) begin
        if(!nrst) begin
            op_past <= 32'd0;
            op_code <= 32'd0;
            cfg_enable_past <= 1'b0;
       end
        else begin
            cfg_enable_past <= cfg_enable;
            op_code <= cfg;
            op_past <= op_state;
        end
    end

    //reg idx,InX, InY,stride,;
    //iy,ix,w,cin, ic, 

    //mac_iteration
    //pooling_iteration
    //gap_iteration
    //counter_width
    //counter_height
    //counter_channel
/*
    for (int ic = 0; ic < cin; ++ic) {
        for (int ky = 0; ky < k; ++ky) {
            int iy = oy * stride + ky - pad;
            if (iy < 0 || iy >= h) continue;
            for (int kx = 0; kx < k; ++kx) {
                int ix = ox * stride + kx - pad;
                if (ix >= 0 && ix < w) {
                    // Feature storage is HWC. Kernel taps are ordered ic, ky, kx.
                    int feature_index = (iy * w + ix) * cin + ic;
                    int kernel_index = (ic * k + ky) * k + kx;
                    acc += model->feature[feature_index] * kernel[kernel_index];
                }
            }
        }
    }*/

/*
    always_ff @(posedge clk or negedge nrst) begin
        if(!nrst) begin
            //y -> x -> channel(H/W/C)
            if(idx)
            input_width
            input_height
            input_channel
        end
        else begin
            counter_width <= input_width
        end
    end
*/


    // --------------------------------
    // FSM
    // -------------------------------



    //0. CPU -> Memory : weight.bin / image file
    //0. CPU : read weight from Memory

    //1. command write - AXI-Lite : Controller read command(32bit)
    //2. data transfer - DMA start -> waiting for end
        //2-1 : CPU -> AXI-Lite -> DMA start
        //2-2 : feature DMA(3,072 input FEATURE) -> Feature Buffer(Block RAM #0)
        //2-3 : check status - DMA Done or Error
    //3. data transfer - DMA start -> waiting for end
        //3-1 : CPU -> AXI-Lite -> DMA Start
        //3-2 : Kernel DMA(2^16) -> Kernal Block RAM(Buffer)
        //3-3 : chekc status - DMA Done or Error
    //4. MAC Run -> Kernel, Bias, Feature input to MAC -> Output to Feature Buffer #1
        //4-1 : Kernel & Bias & input select(Mux : Feature Block #0 or Resdual or 0) to MAC 
        //4-2 : MAC Result to Feature #1
    //5. Residual Selected
        //5-a : Skip connection - Feature block to Residual Buffer
        //5-b : Skip Conv.(1 x 1 Conv.) - Kernel & Bias & input to MAC -> Output to Residual Buffer
    //6. Residual Add(Conv + Res + ReLU)
        //6-1 : Kernel & Bias & Feature input & Residual Input to MAC -> Output to Feature Buffer #1
    //7. check status - Done or error
    //8. output state
        //8-1 : Kernel & Bias & Feature input to MAC
        //8-2 : output flag -> DMA -> save to Memory
        //8-3 : CPU read form DDR Memory

    //3. check status - Done or Error

    //Memory     C file control  controller
    //DDR(on PS) <-> AXI DMA <-> BRAM Buffer

    //pseudo-code
    //op_past <= op_state;

    //}
    //assign mac_enable       = cfg[6];          //core_enable : MAC
    //assign residual_enable  = cfg[5];          //core_enable : Residual
    //assign relu_enable      = cfg[4];          //core_enable : ReLU
    //assign pooling_enable   = cfg[3];          //core_enable : Pooling
    //assign gap_enable       = cfg[2];          //core_enable : GAP
    //assign output_enable    = cfg[1];          //output_enable       
    //assign input_enable     = cfg[0];          //input_enable

    //counter : state counter;

    always_ff @(posedge clk or negedge nrst) begin
        if(!nrst) begin
            counter_STATE <= 8'd0;
        end
        else begin
            if(cfg_transition || input_enable) begin
                counter_STATE <= 8'd0;
            end
            else begin
                counter_STATE <= counter_STATE + 1'b1;
            end       
        end
    end
    
    always_comb @(*) begin
        if(!nrst) begin
            state_now <= STATE_IDLE;
        end
        else begin
            case (state_now)
                STATE_IDLE : begin        //read from AXI AW/W
                    if(cfg_transition)
                        state_now <= STATE_DECODE;
                    else
                        state_now <= STATE_IDLE;
                end
                STATE_DECODE : begin
                    if(input_enable)
                        state_now <= STATE_IN_FEATURE;
                    else if(mac_enable)
                        state_now <= STATE_IN_PARAM;
                    else if( (~is_skip) & mac_enable )
                        state_now <= STATE_DECODE;
                    //else if()
                    //    op_state <= STATE_ERROR;
                    else begin
                        state_now <= STATE_DECODE;
                    end
                end
                STATE_IN_FEATURE : begin
                    if(dma_feature_ready & dma_feature_valid) begin
                        state_now <= STATE_IN_FEATURE;
                    end
                    else if(dma_bias_ready & dma_bias_valid) begin
                        state_now <= STATE_IN_PARAM;
                    end
                    //else if()
                    //    state_now <= STATE_ERROR;
                    else begin
                        state_now <= STATE_IN_FEATURE;
                    end
                end
                STATE_IN_PARAM : begin
                    if(STATE_IN_PARAM)
                    -> STATE_IN_PARAM
                    -> STATE_RUN
                    -> STATE_ERROR
                end
                STATE_RUN: begin
                    if(STATE_RUN)
                    -> STATE_DRAIN
                    -> STATE_RUN
                end
                STATE_DRAIN: begin
                    if(STATE_DRAIN)
                    -> STATE_DRAIN
                    -> STATE_OUTPUT
                    -> STATE_IDLE
                end
                STATE_OUTPUT: begin
                    if(STATE_OUTPUT)
                    -> STATE_IDLE
                end
                STATE_ERROR: begin
                    if(STATE_ERROR)
                    -> STATE_IDLE
                    -> STATE_ERROR
                end
                default : counter_STATE <= 8'd0;
        endcase
    end





    assign mac_iteration = counter_iteration_mac;

    always_ff @(posedge clk or negedge nrst) begin
        if(!nrst) begin
            counter_iteration_mac <= {BITWIDTH_MAC_ITERATION{1'b0}};
        end
        else begin
            if((state_now == STATE_OUTPUT) && (state_now != state_next)) begin
                if(counter_iteration_mac >= {1'b1,{(BITWIDTH_MAC_ITERATION-1){1'b0}}} - 1'b1) begin
                    counter_iteration_mac <= {BITWIDTH_MAC_ITERATION{1'b0}};
                end
                else begin
                    counter_iteration_mac <= counter_iteration_mac + 1'b1;
                end
            end
            else begin
                counter_iteration_mac <= counter_iteration_mac;
            end
        end
    end
    
    assign pooling_iteration = counter_iteration_pooling;

    always_ff @(posedge clk or negedge nrst) begin
        if(!nrst) begin
            counter_iteration_pooling <= {BITWIDTH_POOLING_ITERATION{1'b0}};
        end
        else begin
            if((state_now == STATE_OUTPUT) && (state_now != state_next)) begin
                if(counter_iteration_pooling >= {1'b1,{(BITWIDTH_POOLING_ITERATION-1){1'b0}}} - 1'b1) begin
                    counter_iteration_pooling <= {BITWIDTH_POOLING_ITERATION{1'b0}};
                end
                else begin
                    counter_iteration_pooling <= counter_iteration_pooling + 1'b1;
                end
            end
        end
    end

    assign gap_iteration = counter_iteration_gap;

    always_ff @(posedge clk or negedge nrst) begin
        if(!nrst) begin
            counter_iteration_gap <= {BITWIDTH_GAP_ITERATION{1'b0}};
        end
        else begin
            if((state_now == STATE_OUTPUT) && (state_now != state_next)) begin
                if(counter_iteration_gap >= {1'b1,(BITWIDTH_GAP_ITERATION-1){1'b0}} - 1'b1) begin
                    counter_iteration_gap <= {BITWIDTH_GAP_ITERATION{1'b0}};
                end
                else begin
                    counter_iteration_gap <= counter_iteration_gap + 1'b1;
                end
            end
        end
    end


    // --------------------------------
    // core control
    // --------------------------------

    // --------------------------------
    // AXI control
    // --------------------------------


endmodule

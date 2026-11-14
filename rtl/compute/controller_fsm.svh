
always_ff @(negedge clk or posedge nrst) begin : FSM_FLAG_First_IDLE
    if (!nrst) begin
        is_fisrt_IDLE <= '1;
    end else if ((cstate != IDLE) & is_fisrt_IDLE) begin
        is_fisrt_IDLE <= '0;
    end else begin
        is_fisrt_IDLE <= is_fisrt_IDLE;
    end
end

always_ff @(negedge clk or posedge nrst) begin : FSM_FLAG_AFTER_SKIP
    if (!nrst) begin
        is_after_skip <= '0;
    end else if ((cstate == RUN) & is_skip) begin
        is_after_skip <= '1;
    end else if ((cstate == RUN) & ~cfg_is_skip & is_after_skip) begin
        is_after_skip <= '0;
    end else begin
        is_after_skip <= is_after_skip;
    end
end

always_comb begin : RESPONSE
    case(cstate)
        IDLE : rstate = (is_fisrt_IDLE) ? RESP_IDLE : RESP_DONE;
        DECODE, IN_FEATURE, IN_KERNEL, IN_BIAS : rstate = RESP_INPUT;
        OUTPUT : rstate = RESP_OUTPUT;
        ERROR  : rstate = RESP_ERROR;
        default : rstate = RESP_IDLE;
    endcase
end

always_ff @(negedge clk or posedge nrst) begin : fmem_select
    if (!nrst) begin
        is_bmem0_in <= 1;
    end else if (cstate == DECODE) begin
        is_bmem0_in <= ~is_bmem0_in;
    end else begin
        is_bmem0_in <= is_bmem0_in;
    end
end

always_ff @(negedge clk or posedge nrst) begin : FSM_cstate
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
                    cstate <= RUN;
                end
            end
            IN_FEATURE: begin
                if ((cnt_feature == len_feature) & dma_feature_hk) begin
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
                if ((cnt_kernel == len_kernel) & dma_kernel_hk) begin
                    cstate <= IN_BIAS;
                end else begin
                    cstate <= IN_KERNEL;
                end   
            end
            IN_BIAS: begin
                if ((cnt_bias == len_bias) & dma_bias_hk) begin
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
                if ((cnt_dma_output == len_output) & dma_result_hk) begin
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
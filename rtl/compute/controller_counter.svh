always_ff @(negedge clk or posedge nrst) begin : counter_feature
    if (!nrst) begin
        cnt_feature <= 0;
    end else if (cstate == IN_FEATURE) begin
        if (dma_feature_hk) begin
            cnt_feature <= cnt_feature + 1;
        end else begin
            cnt_feature <= cnt_feature;
        end
    end else begin
        cnt_feature <= '0;
    end
end

always_ff @(negedge clk or posedge nrst) begin : counter_kernel
    if (!nrst) begin
        cnt_kernel <= 0;
    end else if (cstate == IN_KERNEL) begin
        if (dma_kernel_hk) begin
            cnt_kernel <= cnt_kernel + 1;
        end else begin
            cnt_kernel <= cnt_kernel;
        end
    end else begin
        cnt_kernel <= '0;
    end
end

always_ff @(negedge clk or posedge nrst) begin : counter_bias
    if (!nrst) begin
        cnt_bias <= 0;
    end else if (cstate == IN_BIAS) begin
        if (dma_bias_hk) begin
            cnt_bias <= cnt_bias + 1;
        end else begin
            cnt_bias <= cnt_bias;
        end
    end else begin
        cnt_bias <= '0;
    end
end

always_ff @(negedge clk or posedge nrst) begin : counter_dma_output
    if (!nrst) begin
        cnt_dma_output <= 0;
    end else if (cstate == OUTPUT) begin
        if (dma_result_hk) begin
            cnt_dma_output <= cnt_dma_output + 1;
        end else begin
            cnt_dma_output <= cnt_dma_output;
        end
    end else begin
        cnt_dma_output <= '0;
    end
end


// core
always_ff @(negedge clk or posedge nrst) begin : counter_core_in
    if (!nrst) begin
        cnt_run <= 0;
    end else if (cstate == RUN) begin
        if (cnt_run == len_feature) begin
            cnt_run <= cnt_run;
        end else begin
            cnt_run <= cnt_run+1;
        end
    end else begin
        cnt_run <= '0;
    end
end

always_ff @(negedge clk or posedge nrst) begin : counter_core_out
    if (!nrst) begin
        cnt_output <= 0;
    end else if (cstate == RUN) begin
        if (out_enable) begin 
            cnt_output <= cnt_output + 1;
        end else begin
            cnt_output <= cnt_output;
        end
    end else begin
        cnt_output <= '0;
    end
end
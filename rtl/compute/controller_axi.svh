assign dma_feature_hk   = dma_feature_valid & dma_feature_ready;
assign dma_feature_ready = cstate[2];

assign dma_kernel_hk    = dma_kernel_valid  & dma_kernel_ready;
assign dma_kernel_ready = cstate[3];

assign dma_bias_hk      = dma_bias_valid    & dma_bias_ready;
assign dma_bias_ready   = cstate[4];

assign dma_result_hk    = dma_result_valid  & dma_result_ready;
assign dma_result_valid = cstate[6];
assign dma_result_last= (cnt_dma_output == oc);
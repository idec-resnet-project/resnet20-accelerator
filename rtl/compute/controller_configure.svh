
assign cfg_input_enable     = cfg[0]; 
assign cfg_output_enable    = cfg[1]; 
assign cfg_mac_enable       = cfg[6];
assign cfg_residual_enable  = cfg[5];
assign cfg_relu_enable      = cfg[4];
assign cfg_pooling_enable   = cfg[3];
assign cfg_gap_enable       = cfg[2];
assign cfg_is_skip          = cfg[7];
assign cfg_stride           = cfg[8];
assign cfg_padding          = cfg[9];
assign cfg_w                = cfg[15:10];
assign cfg_h                = cfg[21:16];
assign cfg_c                = cfg[27:22];

assign ctrl_ow_next              = ((((ctrl_is_after_skip) ? ctrl_fw : ctrl_ow) - cfg_w + {cfg_padding, 1'b0}) >> cfg_stride);

always_ff @(posedge clk or negedge nrst) begin : update_config
    if (!nrst) begin
        ctrl_input_enable    <= '0;
        ctrl_output_enable   <= '0;
        mac_enable      <= '0;
        residual_enable  <= '0;
        relu_enable     <= '0;
        pooling_enable  <= '0;
        gap_enable      <= '0;
    end else if (cfg_enable) begin
        ctrl_input_enable    <= cfg_input_enable;
        ctrl_output_enable   <= cfg_output_enable;
        mac_enable      <= cfg_mac_enable;
        residual_enable  <= cfg_residual_enable;
        relu_enable     <= cfg_relu_enable;
        pooling_enable  <= cfg_pooling_enable;
        gap_enable      <= cfg_gap_enable;
        ctrl_is_skip         <= cfg_is_skip;
    end else begin
        ctrl_input_enable    <= ctrl_input_enable;
        ctrl_output_enable   <= ctrl_output_enable;
        mac_enable      <= mac_enable; 
        residual_enable  <= residual_enable; 
        relu_enable     <= relu_enable; 
        pooling_enable  <= pooling_enable; 
        gap_enable      <= gap_enable; 
        ctrl_is_skip         <= ctrl_is_skip;
    end
end

always_ff @(posedge clk or negedge nrst) begin : calc_CNN_size
    if (!nrst) begin
        ctrl_fw      <= '0;
        ctrl_fc      <= '0;
        ctrl_kw      <= '0;
        ctrl_kc      <= '0;
        ctrl_ow      <= '0;
        ctrl_oc      <= '0;
        ctrl_padding <= '0;
        ctrl_stride  <= '0;
    end else if (cstate == DECODE) begin
        if (cfg_input_enable) begin
            ctrl_fw      <= cfg_w;
            ctrl_fc      <= cfg_c;
            ctrl_kw      <= ctrl_kw;
            ctrl_kc      <= ctrl_kc;
            ctrl_ow      <= cfg_w;
            ctrl_oc      <= cfg_c;
            ctrl_padding <= ctrl_padding;
            ctrl_stride  <= ctrl_stride;
        end else if (cfg_mac_enable) begin 
            if (ctrl_is_after_skip) begin
                ctrl_fw      <= ctrl_fw;
                ctrl_fc      <= ctrl_fc;
                ctrl_kw      <= cfg_w;
                ctrl_kc      <= cfg_c;
                ctrl_ow      <= ctrl_ow_next;
                ctrl_oc      <= cfg_c;
                ctrl_padding <= cfg_padding;
                ctrl_stride  <= cfg_stride;  
            end else if (cfg_gap_enable) begin
                ctrl_fw      <= ctrl_ow;
                ctrl_fc      <= ctrl_oc;
                ctrl_kw      <= cfg_w;
                ctrl_kc      <= cfg_c;
                ctrl_ow      <= 0;
                ctrl_oc      <= cfg_c;
                ctrl_padding <= cfg_padding;
                ctrl_stride  <= cfg_stride;
            end else begin
                ctrl_fw      <= ctrl_ow;
                ctrl_fc      <= ctrl_oc;
                ctrl_kw      <= cfg_w;
                ctrl_kc      <= cfg_c;
                ctrl_ow      <= ctrl_ow_next;
                ctrl_oc      <= cfg_c;
                ctrl_padding <= cfg_padding;
                ctrl_stride  <= cfg_stride;  
            end      
        end else if (cfg_is_skip) begin
            ctrl_fw      <= ctrl_ow;
            ctrl_fc      <= ctrl_oc;
            ctrl_kw      <= cfg_w;
            ctrl_kc      <= cfg_c;
            ctrl_ow      <= ctrl_ow;
            ctrl_oc      <= ctrl_oc;
            ctrl_padding <= cfg_padding;
            ctrl_stride  <= cfg_stride;
        end else begin
            ctrl_fw      <= ctrl_fw;
            ctrl_fc      <= ctrl_fc;
            ctrl_kw      <= ctrl_kw;
            ctrl_kc      <= ctrl_kc;
            ctrl_ow      <= ctrl_ow;
            ctrl_oc      <= ctrl_oc;
            ctrl_padding <= ctrl_padding;
            ctrl_stride  <= ctrl_stride;  
        end
    end else begin
        ctrl_fw      <= ctrl_fw;
        ctrl_fc      <= ctrl_fc;
        ctrl_kw      <= ctrl_kw;
        ctrl_kc      <= ctrl_kc;
        ctrl_ow      <= ctrl_ow;
        ctrl_oc      <= ctrl_oc;
        ctrl_padding <= ctrl_padding;
        ctrl_stride  <= ctrl_stride;
    end
end
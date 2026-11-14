assign cfg_input_enable     = cfg[0]; 
assign cfg_output_enable    = cfg[1]; 
assign cfg_mac_enable       = cfg[6];
assign cfg_residual_enable   = cfg[5];
assign cfg_relu_enable      = cfg[4];
assign cfg_pooling_enable   = cfg[3];
assign cfg_gap_enable       = cfg[2];
assign cfg_is_skip          = cfg[7];
assign cfg_stride           = cfg[8];
assign cfg_padding          = cfg[9];
assign cfg_w                = cfg[15:10];
assign cfg_h                = cfg[21:16];
assign cfg_c                = cfg[27:22];

assign next_ow              = ((((is_after_skip) ? fw : ow) - cfg_w + {cfg_padding, 1'b0}) >> cfg_stride);

always_ff @(negedge clk or posedge nrst) begin : update_config
    if (!nrst) begin
        input_enable    <= '0;
        output_enable   <= '0;
        mac_enable      <= '0;
        residual_enable  <= '0;
        relu_enable     <= '0;
        pooling_enable  <= '0;
        gap_enable      <= '0;
    end else if (cfg_enable) begin
        input_enable    <= cfg_input_enable;
        output_enable   <= cfg_output_enable;
        mac_enable      <= cfg_mac_enable;
        residual_enable  <= cfg_residual_enable;
        relu_enable     <= cfg_relu_enable;
        pooling_enable  <= cfg_pooling_enable;
        gap_enable      <= cfg_gap_enable;
        is_skip         <= cfg_is_skip;
    end else begin
        input_enable    <= input_enable;
        output_enable   <= output_enable;
        mac_enable      <= mac_enable; 
        residual_enable  <= residual_enable; 
        relu_enable     <= relu_enable; 
        pooling_enable  <= pooling_enable; 
        gap_enable      <= gap_enable; 
        is_skip         <= is_skip;
    end
end

always_ff @(negedge clk or posedge nrst) begin : calc_CNN_size
    if (!nrst) begin
        fw      <= '0;
        fc      <= '0;
        kw      <= '0;
        kc      <= '0;
        ow      <= '0;
        oc      <= '0;
        padding <= '0;
        stride  <= '0;
    end else if (cstate == DECODE) begin
        if (cfg_input_enable) begin
            fw      <= cfg_w;
            fc      <= cfg_c;
            kw      <= kw;
            kc      <= kc;
            ow      <= cfg_w;
            oc      <= cfg_c;
            padding <= padding;
            stride  <= stride;
        end else if (cfg_mac_enable) begin 
            if (is_after_skip) begin
                fw      <= fw;
                fc      <= fc;
                kw      <= cfg_w;
                kc      <= cfg_c;
                ow      <= next_ow;
                oc      <= cfg_c;
                padding <= cfg_padding;
                stride  <= cfg_stride;  
            end else begin
                fw      <= ow;
                fc      <= oc;
                kw      <= cfg_w;
                kc      <= cfg_c;
                ow      <= next_ow;
                oc      <= cfg_c;
                padding <= cfg_padding;
                stride  <= cfg_stride;  
            end      
        end else if (cfg_is_skip) begin
            fw      <= ow;
            fc      <= oc;
            kw      <= cfg_w;
            kc      <= cfg_c;
            ow      <= ow;
            oc      <= oc;
            padding <= cfg_padding;
            stride  <= cfg_stride;
        end else begin
            fw      <= fw;
            fc      <= fc;
            kw      <= kw;
            kc      <= kc;
            ow      <= ow;
            oc      <= oc;
            padding <= padding;
            stride  <= stride;  
        end
    end else begin
        fw      <= fw;
        fc      <= fc;
        kw      <= kw;
        kc      <= kc;
        ow      <= ow;
        oc      <= oc;
        padding <= padding;
        stride  <= stride;
    end
end
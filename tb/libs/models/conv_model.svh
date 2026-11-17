    // Both tests use stride 1.
    localparam int OUTPUT_SIZE = INPUT_SIZE + 2 * PADDING - KERNEL_SIZE + 1;
    localparam int SCALE = 1024; // Q5.10

    localparam bit [31:0] OP_INPUT  = 32'h01;
    localparam bit [31:0] OP_OUTPUT = 32'h02;
    localparam bit [31:0] OP_RELU   = 32'h10;
    localparam bit [31:0] OP_MAC    = 32'h40;

    function automatic string model_data_dir(string tb_dir);
        // The simulator runs in the per-test log directory.
        return ".";
    endfunction

    function automatic bit [31:0] instruction_word(bit [31:0] op,
                                                     int size, channels, padding);
        // Bit 8 stays zero for stride 1.
        return op | (padding << 9) | ((size - 1) << 10) |
               ((size - 1) << 16) | ((channels - 1) << 22);
    endfunction

    function automatic void write_reference(model_command load, model_command conv);
        int fd, iy, ix, feature_index, kernel_index;
        real sum;

        fd = $fopen(conv.reference_logits_path, "w");
        if (!fd) $fatal(1, "Cannot write %s", conv.reference_logits_path);
        // Feature and result streams are channel-major. X varies fastest.
        for (int oc = 0; oc < OUT_CHANNELS; oc++) begin
            for (int y = 0; y < OUTPUT_SIZE; y++) begin
                for (int x = 0; x < OUTPUT_SIZE; x++) begin
                    sum = $itor(conv.payload[BIAS].words[oc]) / SCALE;
                    for (int ic = 0; ic < IN_CHANNELS; ic++) begin
                        for (int ky = 0; ky < KERNEL_SIZE; ky++) begin
                            for (int kx = 0; kx < KERNEL_SIZE; kx++) begin
                                iy = y + ky - PADDING;
                                ix = x + kx - PADDING;
                                if (iy >= 0 && iy < INPUT_SIZE && ix >= 0 && ix < INPUT_SIZE) begin
                                    feature_index = (ic * INPUT_SIZE + iy) * INPUT_SIZE + ix;
                                    kernel_index = ((oc * IN_CHANNELS + ic) * KERNEL_SIZE + ky) *
                                                   KERNEL_SIZE + kx;
                                    sum += ($itor(load.payload[FEATURE].words[feature_index]) / SCALE) *
                                           ($itor(conv.payload[KERNEL].words[kernel_index]) / SCALE);
                                end
                            end
                        end
                    end
                    $fdisplay(fd, "%.17g", (RELU_ENABLE && sum < 0.0) ? 0.0 : sum);
                end
            end
        end
        $fclose(fd);
    endfunction

    function automatic model_run_config build_model_config(string data_dir, int output_frac_bits);
        model_run_config cfg = new;
        model_command load = new;
        model_command conv = new;

        cfg.output_frac_bits = output_frac_bits;
        load.instruction = instruction_word(OP_INPUT, INPUT_SIZE, IN_CHANNELS, 0);
        load.payload[FEATURE].words = new[INPUT_SIZE * INPUT_SIZE * IN_CHANNELS];
        // Multiples of 1/8 keep the reference exactly representable in Q5.10.
        foreach (load.payload[FEATURE].words[i])
            load.payload[FEATURE].words[i] = ((i * 7) % 19 - 9) * (SCALE / 8);

        conv.instruction = instruction_word(OP_MAC | OP_OUTPUT | (RELU_ENABLE ? OP_RELU : 0),
                                            KERNEL_SIZE, OUT_CHANNELS, PADDING);
        conv.payload[KERNEL].words = new[OUT_CHANNELS * IN_CHANNELS * KERNEL_SIZE * KERNEL_SIZE];
        foreach (conv.payload[KERNEL].words[i])
            conv.payload[KERNEL].words[i] = ((i * 5) % 11 - 5) * (SCALE / 8);
        conv.payload[BIAS].words = new[OUT_CHANNELS];
        foreach (conv.payload[BIAS].words[i])
            conv.payload[BIAS].words[i] = ((i % 2 == 0) ? -SCALE / 4 : SCALE / 8) * (1 + i / 2);
        conv.result_count = OUTPUT_SIZE * OUTPUT_SIZE * OUT_CHANNELS;
        conv.reference_logits_path = {data_dir, "/reference_conv_float.txt"};
        write_reference(load, conv);

        cfg.commands.push_back(load);
        cfg.commands.push_back(conv);
        return cfg;
    endfunction

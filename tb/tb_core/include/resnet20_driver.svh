    // --------------------------------
    // Input stream timing
    // --------------------------------
    task automatic idle(input int cycles);
        repeat (cycles) begin
            @(negedge clk);
            in_enable = 0;
        end
    endtask

    task automatic drive(input word_t value, kernel, bias, input int index);
        in_enable = 1;
        in_data = value;
        kernel_data = kernel;
        bias_data = bias;
        if (index >= 0) queue_output(index);
    endtask

    task automatic send_word(input word_t value, kernel, bias, input int index);
        @(negedge clk);
        drive(value, kernel, bias, index);
    endtask

    task automatic send_skip(input word_t value, input int index);
        idle(SKIP_DELAY_CYCLES - 1);
        @(negedge clk);
        // A residual result must wait until the shortcut word is driven.
        if (out_enable !== 1'b0) $fatal(1, "%s: output before skip input", compare_name);
        drive(value, 0, 0, index);
    endtask

    task automatic configure(input bit residual, relu, gap, input int taps, group_size,
                             input bit is_logit = 0);
        residual_enable = residual;
        relu_enable = relu;
        gap_enable = gap;
        mac_iteration = 16'(taps);
        gap_iteration = 16'(group_size);
        output_is_logit = is_logit;
    endtask

    // --------------------------------
    // Layer execution
    // --------------------------------
    task automatic run_affine(input int index);
        layer_t layer;
        tap_t address;
        int out_h, out_w, taps, bias_base, result_words;
        int output_word_index, expected_index;
        bit residual, use_gap;
        word_t value;
        longint budget;

        layer = layers[index];
        taps = layer.cin * layer.size * layer.size;
        out_h = output_extent(layer.height, layer.size, layer.stride, layer.pad);
        out_w = output_extent(layer.width, layer.size, layer.stride, layer.pad);
        residual = (layer.op & FLAG_RESIDUAL) != 0;
        use_gap = (layer.op & FLAG_GAP) != 0;
        result_words = use_gap ? layer.cout : out_h * out_w * layer.cout;
        bias_base = layer.weight_base + taps * layer.cout;
        if (layer.weight_base != weights_consumed)
            $fatal(1, "%s: weight consumption order mismatch", layer_name[index]);
        budget = longint'(out_h) * out_w * layer.cout *
                 (longint'(taps) * (input_gap + 1) + (residual ? SKIP_DELAY_CYCLES : 0)) + 16;
        begin_compare(layer_name[index], use_gap ? 1 : out_w, layer.cout, result_words, budget);
        configure(residual, (layer.op & FLAG_RELU) != 0, use_gap, taps, out_h * out_w,
                  layer.op == OP_FC_OUT);

        // Channel-major transmission also keeps each GAP window contiguous.
        for (int oc = 0; oc < layer.cout; oc++) begin
            for (int y = 0; y < out_h; y++) begin
                for (int x = 0; x < out_w; x++) begin
                    output_word_index = output_index(y, x, oc, out_w, layer.cout);
                    expected_index = output_word_index;
                    if (use_gap)
                        expected_index = (y == out_h - 1 && x == out_w - 1) ? oc : -1;
                    for (int tap = 0; tap < taps; tap++) begin
                        address = schedule_tap(layer, y, x, oc, tap);
                        value = address.padded ? 16'sd0 : feature[address.feature_index];
                        send_word(value, weights[address.kernel_index],
                                  tap == 0 ? weights[bias_base + oc] : 16'sd0,
                                  !residual && tap == taps - 1 ? expected_index : -1);
                        if (tap != taps - 1) idle(input_gap);
                    end
                    if (residual) send_skip(shortcut[output_word_index], expected_index);
                    idle(input_gap);
                end
            end
        end
        finish_compare();
        // Projection writes the shortcut bank while the main path keeps its input.
        for (int i = 0; i < result_words; i++) begin
            if (layer.op == OP_PROJECTION) shortcut[i] = actual[i];
            else feature[i] = actual[i];
        end
        weights_consumed = bias_base + layer.cout;
    endtask

    // --------------------------------
    // Directed arithmetic checks
    // --------------------------------
    task automatic check_arithmetic;
        directed_expected[0] = 1;
        directed_expected[1] = -1;
        begin_compare("bias sampled once and signed ties", 2, 1, 2, 4 * (input_gap + 1) + 16, 1);
        configure(0, 0, 0, 2, 0);
        send_word(1, 512, 1, -1);
        idle(input_gap);
        send_word(-2, 512, 456, 0);
        idle(input_gap);
        send_word(-1, 512, -1, -1);
        idle(input_gap);
        send_word(2, 512, 456, 1);
        finish_compare();

        directed_expected[0] = 32767;
        directed_expected[1] = -32768;
        begin_compare("MAC saturation", 2, 1, 2, 2 * (input_gap + 1) + 16, 1);
        configure(0, 0, 0, 1, 0);
        send_word(32767, 32767, 0, 0);
        idle(input_gap);
        send_word(-32768, 32767, 0, 1);
        finish_compare();

        directed_expected[0] = -1;
        directed_expected[1] = 32767;
        begin_compare("skip timing and residual saturation", 2, 1, 2,
                      2 * (longint'(SKIP_DELAY_CYCLES) + input_gap + 1) + 16, 1);
        configure(1, 0, 0, 1, 0);
        send_word(32767, 32767, 0, -1);
        send_skip(-32768, 0);
        idle(input_gap);
        send_word(0, 0, 32767, -1);
        send_skip(1, 1);
        finish_compare();
    endtask

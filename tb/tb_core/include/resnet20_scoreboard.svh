    // --------------------------------
    // Expected values and output order
    // --------------------------------
    word_t directed_expected[0:1];
    word_t actual[0:MAX_TENSOR_WORDS-1];
    int pending[0:MAX_TENSOR_WORDS-1];
    bit scheduled[0:MAX_TENSOR_WORDS-1];
    int queued, received, expected_count, compare_width, compare_channels;
    longint elapsed, deadline;
    bit comparing;
    bit check_directed;
    string compare_name;

    task automatic begin_compare(input string name, input int width, channels, count,
                                 input longint cycle_budget, input bit directed = 0);
        @(negedge clk);
        in_enable = 0;
        compare_name = name;
        compare_width = width;
        compare_channels = channels;
        expected_count = count;
        queued = 0;
        received = 0;
        elapsed = 0;
        deadline = cycle_budget;
        check_directed = directed;
        for (int i = 0; i < count; i++) scheduled[i] = 0;
        comparing = 1;
    endtask

    task automatic queue_output(input int index);
        if (index < 0 || index >= expected_count || queued >= expected_count || scheduled[index])
            $fatal(1, "%s: invalid or duplicate output index %0d", compare_name, index);
        scheduled[index] = 1;
        pending[queued] = index;
        queued++;
    endtask

    // --------------------------------
    // Output sampling and diagnostics
    // --------------------------------
    always @(posedge clk) begin : observe_output
        int index, y, x, oc;
        if (nrst) begin
            if (comparing) begin
                elapsed++;
                if (elapsed > deadline)
                    $fatal(1, "%s: timeout after %0d cycles (%0d/%0d outputs)",
                           compare_name, elapsed, received, expected_count);
            end
            if (out_enable === 1'b1) begin
                if (!comparing || received >= queued)
                    $fatal(1, "%s: unexpected or early output at sample %0d", compare_name, received);
                // Scheduled indices map stream order to HWC tensor storage.
                index = pending[received];
                if ($isunknown(out_data))
                    $fatal(1, "%s: unknown data at output index %0d", compare_name, index);
                if (check_directed && out_data !== directed_expected[index]) begin
                    oc = index % compare_channels;
                    x = (index / compare_channels) % compare_width;
                    y = index / (compare_width * compare_channels);
                    $fatal(1, "%s (y=%0d x=%0d oc=%0d): expected %0d, got %0d",
                           compare_name, y, x, oc, directed_expected[index], out_data);
                end
                actual[index] = out_data;
                received++;
            end else if (out_enable !== 1'b0) begin
                $fatal(1, "%s: unknown out_enable", compare_name);
            end
        end
    end

    task automatic finish_compare;
        repeat (CORE_PIPELINE_CYCLES + 1) begin
            @(negedge clk);
            in_enable = 0;
        end
        if (received != expected_count || queued != expected_count)
            $fatal(1, "%s: received %0d, scheduled %0d, expected %0d",
                   compare_name, received, queued, expected_count);
        comparing = 0;
        $display("[ PASS ] %s (%0d words, %0d cycles)", compare_name, received, elapsed);
    endtask

    // --------------------------------
    // Final logit SNR
    // --------------------------------
    function automatic word_t format_logit(input word_t value);
        int sample, divisor;

        sample = int'(value);
        if (OUTPUT_FRAC_BITS < CORE_FRAC_BITS) begin
            divisor = 1 << (CORE_FRAC_BITS - OUTPUT_FRAC_BITS);
            if (sample < 0) sample = -((-sample + divisor / 2) / divisor);
            else sample = (sample + divisor / 2) / divisor;
        end else begin
            sample = sample <<< (OUTPUT_FRAC_BITS - CORE_FRAC_BITS);
        end

        if (sample > 32767) return 32767;
        if (sample < -32768) return -32768;
        return word_t'(sample);
    endfunction

    task automatic check_logit_snr;
        localparam real MIN_SNR_DB = 50.0;
        localparam real OUTPUT_SCALE = 2.0 ** OUTPUT_FRAC_BITS;
        int fd;
        real reference, error_value, signal_power, error_power, snr_db;
        string extra;

        fd = $fopen("vectors/reference_logits_float.txt", "r");
        if (!fd) $fatal(1, "Cannot open float reference logits");
        signal_power = 0.0;
        error_power = 0.0;
        for (int i = 0; i < LOGIT_COUNT; i++) begin
            if ($fscanf(fd, "%f", reference) != 1)
                $fatal(1, "Missing or invalid float reference logit %0d", i);
            error_value = reference - ($itor(int'(feature[i])) / OUTPUT_SCALE);
            signal_power += reference * reference;
            error_power += error_value * error_value;
        end
        if ($fscanf(fd, "%s", extra) == 1) $fatal(1, "Extra float reference logits");
        $fclose(fd);

        if (signal_power <= 0.0) $fatal(1, "Float reference logits have no signal power");
        if (error_power == 0.0) begin
            $display("[ PASS ] logit SNR = inf dB (minimum %.2f dB)", MIN_SNR_DB);
        end else begin
            snr_db = 10.0 * $log10(signal_power / error_power);
            if (snr_db < MIN_SNR_DB)
                $fatal(1, "Logit SNR %.2f dB is below %.2f dB", snr_db, MIN_SNR_DB);
            $display("[ PASS ] logit SNR = %.2f dB (minimum %.2f dB)", snr_db, MIN_SNR_DB);
        end
    endtask

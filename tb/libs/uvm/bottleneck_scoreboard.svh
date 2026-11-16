    `uvm_analysis_imp_decl(_axi)
    `uvm_analysis_imp_decl(_axis)

    // --------------------------------
    // Monitor-based checks
    // --------------------------------
    class bottleneck_scoreboard extends uvm_scoreboard;
        `uvm_component_utils(bottleneck_scoreboard)

        uvm_analysis_imp_axi #(axi_lite_item, bottleneck_scoreboard) axi;
        uvm_analysis_imp_axis #(axis_beat, bottleneck_scoreboard) axis;
        model_run_config cfg;
        model_command current;
        // Per-command and cumulative handshake counts
        int count[4];
        int total[4];
        int writes;
        int checked_commands;
        model_words_t captured_logits;

        function new(string name, uvm_component parent);
            super.new(name, parent);
            axi = new("axi", this);
            axis = new("axis", this);
            foreach (total[s]) total[s] = 0;
            checked_commands = 0;
        endfunction

        function void begin_command(model_command command);
            current = command;
            writes = 0;
            if (command.result_count != 0)
                captured_logits = new[command.result_count];
            foreach (count[s]) count[s] = 0;
        endfunction

        function int expected_count(int stream);
            if (stream == RESULT) return current.result_count;
            return current.payload[stream].words.size();
        endfunction

        // --------------------------------
        // Observed command and packet data
        // --------------------------------
        function void write_axi(axi_lite_item item);
            if (current == null) return;
            writes++;
            if (item.addr !== cfg.command_addr || item.data !== current.instruction ||
                item.resp !== 2'b00)
                `uvm_error("COMMAND", "Observed AXI-Lite command mismatch")
        endfunction

        function void write_axis(axis_beat beat);
            int stream_index, index;
            if (current == null) return;
            stream_index = int'(beat.stream);
            index = count[stream_index];
            count[stream_index]++;
            total[stream_index]++;
            if (index >= expected_count(stream_index)) begin
                `uvm_error("EXTRA_BEAT", $sformatf("%s beat %0d", beat.stream.name(), index))
                return;
            end
            if (beat.keep !== 2'b11 || beat.last !== (index == expected_count(stream_index) - 1))
                `uvm_error("FRAMING", $sformatf("%s beat %0d", beat.stream.name(), index))
            if (stream_index == RESULT) begin
                check_result_word(index, beat.data);
            end else if (beat.data !== current.payload[stream_index].words[index][15:0])
                `uvm_error("PAYLOAD", $sformatf("%s beat %0d", beat.stream.name(), index))
        endfunction

        // --------------------------------
        // Final logit SNR
        // --------------------------------
        function void check_result_word(int index, logic [15:0] data);
            if ($isunknown(data)) begin
                `uvm_error("RESULT", $sformatf("Unknown data at logit %0d", index))
                return;
            end
            captured_logits[index] = int'($signed(data));
        endfunction

        function void check_logit_snr();
            int fd;
            real output_scale, reference, error_value, signal_power, error_power, snr_db;
            string extra;

            fd = $fopen(current.reference_logits_path, "r");
            if (!fd) begin
                `uvm_error("LOGIT_SNR", $sformatf("Cannot open %s", current.reference_logits_path))
                return;
            end
            signal_power = 0.0;
            error_power = 0.0;
            output_scale = 2.0 ** cfg.output_frac_bits;
            foreach (captured_logits[i]) begin
                if ($fscanf(fd, "%f", reference) != 1) begin
                    $fclose(fd);
                    `uvm_error("LOGIT_SNR", $sformatf("Missing or invalid float reference logit %0d", i))
                    return;
                end
                error_value = reference - ($itor(captured_logits[i]) / output_scale);
                signal_power += reference * reference;
                error_power += error_value * error_value;
            end
            if ($fscanf(fd, "%s", extra) == 1) begin
                $fclose(fd);
                `uvm_error("LOGIT_SNR", "Extra float reference logits")
                return;
            end
            $fclose(fd);

            if (signal_power <= 0.0) begin
                `uvm_error("LOGIT_SNR", "Float reference logits have no signal power")
            end else if (error_power == 0.0) begin
                `uvm_info("LOGIT_SNR", $sformatf("PASS: inf dB (minimum %.2f dB)",
                          cfg.min_logit_snr_db), UVM_LOW)
            end else begin
                snr_db = 10.0 * $log10(signal_power / error_power);
                if (snr_db < cfg.min_logit_snr_db)
                    `uvm_error("LOGIT_SNR", $sformatf("%.2f dB is below %.2f dB",
                               snr_db, cfg.min_logit_snr_db))
                else
                    `uvm_info("LOGIT_SNR", $sformatf("PASS: %.2f dB (minimum %.2f dB, output_frac_bits=%0d)",
                              snr_db, cfg.min_logit_snr_db, cfg.output_frac_bits), UVM_LOW)
            end
        endfunction

        // --------------------------------
        // Transfer count checks
        // --------------------------------
        function void end_command();
            if (writes != 1) `uvm_error("COMMAND_COUNT", $sformatf("Observed %0d writes", writes))
            foreach (count[s]) begin
                if (count[s] != expected_count(s))
                    `uvm_error("BEAT_COUNT", $sformatf("Stream %0d got %0d expected %0d",
                                                      s, count[s], expected_count(s)))
            end
            if (current.result_count != 0 && count[RESULT] == current.result_count)
                check_logit_snr();
            checked_commands++;
            current = null;
        endfunction
    endclass

    `uvm_analysis_imp_decl(_axi)
    `uvm_analysis_imp_decl(_axis)

    class bottleneck_scoreboard extends uvm_scoreboard;
        `uvm_component_utils(bottleneck_scoreboard)
        uvm_analysis_imp_axi #(axi_lite_item, bottleneck_scoreboard) axi;
        uvm_analysis_imp_axis #(axis_beat, bottleneck_scoreboard) axis;
        model_run_config cfg;
        model_command current;
        int count[4], total[4], writes, errors, checked_commands;
        int max_result_delta = 0;
        bit expect_bad_result;

        function new(string name, uvm_component parent);
            super.new(name, parent);
            axi = new("axi", this);
            axis = new("axis", this);
            foreach (total[s]) total[s] = 0;
            checked_commands = 0;
            errors = 0;
        endfunction

        function void begin_command(model_command command);
            current = command;
            writes = 0;
            foreach (count[s]) count[s] = 0;
        endfunction

        function int expected_count(int stream);
            if (stream == RESULT) return current.expected.size();
            return current.payload[stream].words.size();
        endfunction

        function void write_axi(axi_lite_item item);
            if (current == null) return;
            writes++;
            if (item.addr !== cfg.command_addr || item.data !== current.instruction ||
                item.resp !== 2'b00)
                `uvm_error("COMMAND", "Observed AXI-Lite command mismatch")
        endfunction

        function void write_axis(axis_beat beat);
            int s, index, expected, delta, magnitude;
            if (current == null) return;
            s = int'(beat.stream);
            index = count[s];
            count[s]++;
            total[s]++;
            if (index >= expected_count(s)) begin
                `uvm_error("EXTRA_BEAT", $sformatf("%s beat %0d", beat.stream.name(), index))
                return;
            end
            if (beat.keep !== 2'b11 || beat.last !== (index == expected_count(s) - 1))
                `uvm_error("FRAMING", $sformatf("%s beat %0d", beat.stream.name(), index))
            if (s == RESULT) begin
                expected = int'($signed(current.expected[index][15:0]));
                delta = int'($signed(beat.data)) - expected;
                magnitude = delta < 0 ? -delta : delta;
                if (magnitude > max_result_delta) max_result_delta = magnitude;
                if ($isunknown(beat.data) || delta > cfg.output_tolerance ||
                    delta < -cfg.output_tolerance) begin
                    errors++;
                    if (expect_bad_result)
                        `uvm_info("EXPECTED_MISMATCH", $sformatf("result[%0d] rejected", index),
                                  UVM_LOW)
                    else
                        `uvm_error("RESULT", $sformatf("result[%0d]=%0d expected %0d",
                                   index, $signed(beat.data), expected))
                end
            end else if (beat.data !== current.payload[s].words[index][15:0])
                `uvm_error("PAYLOAD", $sformatf("%s beat %0d", beat.stream.name(), index))
        endfunction

        function void end_command();
            if (writes != 1) `uvm_error("COMMAND_COUNT", $sformatf("Observed %0d writes", writes))
            foreach (count[s]) begin
                if (count[s] != expected_count(s))
                    `uvm_error("BEAT_COUNT", $sformatf("Stream %0d got %0d expected %0d",
                                                      s, count[s], expected_count(s)))
            end
            checked_commands++;
            current = null;
        endfunction
    endclass

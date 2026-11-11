    // --------------------------------
    // Model command sequence
    // --------------------------------
    class model_run_seq extends uvm_sequence #(uvm_sequence_item);
        bottleneck_env env;
        model_run_config cfg;

        function new(string name = "model_run_seq");
            super.new(name);
        endfunction

        // --------------------------------
        // AXI-Lite command and status
        // --------------------------------
        task access_reg(bit write, bit [31:0] address, inout bit [31:0] data,
                        input int aw_delay = 0, input int w_delay = 0,
                        input bit [1:0] expected_resp = 0);
            axi_lite_transfer transfer = new;
            axi_lite_item item = new;
            item.write = write;
            item.addr = address;
            item.data = data;
            item.aw_delay = aw_delay;
            item.w_delay = w_delay;
            item.timeout_cycles = cfg.timeout_cycles;
            transfer.request = item;
            transfer.start(env.ctrl.sequencer);
            if (item.resp !== expected_resp)
                `uvm_fatal("AXI_RESP", $sformatf("Response %0h for address %08h", item.resp, address))
            data = item.data;
        endtask

        task write_command(model_command cmd, int aw_delay = 0, int w_delay = 0);
            bit [31:0] word_value;
            word_value = cmd.instruction;
            access_reg(1, cfg.command_addr, word_value, aw_delay, w_delay);
        endtask

        task read_status(output bit [31:0] state);
            state = 0;
            access_reg(0, cfg.status_addr, state);
        endtask

        task wait_status(output bit [31:0] state, output bit timed_out,
                         input int max_polls);
            timed_out = 0;
            for (int i = 0; i < max_polls; i++) begin
                read_status(state);
                if (state & (cfg.error_mask | cfg.done_mask)) return;
            end
            timed_out = 1;
        endtask

        // --------------------------------
        // AXI-Stream transfers
        // --------------------------------
        function axis_item source_request(model_command cmd, model_stream_e stream);
            axis_item item = new;
            item.words = cmd.payload[stream].words;
            item.count = item.words.size();
            item.timeout_cycles = cfg.timeout_cycles;
            item.initial_delay = int'(stream) * 2;
            item.gap_max = stream == BIAS ? 3 : 1;
            return item;
        endfunction

        task transfer_stream(model_stream_e stream, axis_item item);
            axis_transfer transfer = new;
            transfer.request = item;
            transfer.start(env.streams[stream].sequencer);
        endtask

        task send_source(model_command cmd, model_stream_e stream);
            axis_item item;
            if (cmd.payload[stream].words.size() == 0) return;
            item = source_request(cmd, stream);
            transfer_stream(stream, item);
            if (item.timed_out || item.aborted)
                `uvm_fatal("TX_FAILED", $sformatf("%s transfer did not finish", stream.name()))
        endtask

        // --------------------------------
        // Command execution
        // --------------------------------
        task send_and_check(model_command cmd, int index);
            bit [31:0] state;
            bit timed_out;
            env.scoreboard.begin_command(cmd);
            write_command(cmd, (index % 2) * 2, (1 - index % 2) * 2);
            if (index == 0) begin
                read_status(state);
                if (state & (cfg.done_mask | cfg.error_mask))
                    `uvm_fatal("STALE_STATUS", "New INPUT retained old status before receiving data")
            end
            // The feature, kernel, and bias DMA channels are independent.
            fork
                send_source(cmd, FEATURE);
                send_source(cmd, KERNEL);
                send_source(cmd, BIAS);
            join
            wait_status(state, timed_out, cfg.timeout_cycles / 4);
            if (timed_out || (state & cfg.error_mask) || !(state & cfg.done_mask))
                `uvm_fatal("COMMAND_FAILED", $sformatf("command[%0d] state=%08h timeout=%0b",
                                                       index, state, timed_out))
        endtask

        task execute_command(model_command cmd, int index);
            axis_item receive_item;
            if (cmd.result_count != 0) begin
                receive_item = new;
                receive_item.count = cmd.result_count;
                receive_item.timeout_cycles = cfg.timeout_cycles;
                receive_item.initial_delay = 100;
                receive_item.gap_max = 3;
                // Arm the output sink before the command can produce data.
                fork
                    transfer_stream(RESULT, receive_item);
                    begin
                        wait (receive_item.armed);
                        send_and_check(cmd, index);
                    end
                join
                if (receive_item.timed_out || receive_item.aborted)
                    `uvm_fatal("RX_FAILED", "Result transfer did not finish")
            end else begin
                send_and_check(cmd, index);
            end
            env.scoreboard.end_command();
        endtask

        virtual task body();
            foreach (cfg.commands[i]) execute_command(cfg.commands[i], i);
        endtask
    endclass

    class model_base_test extends uvm_test;
        bottleneck_env env;
        model_run_config cfg;
        model_run_seq seq;
        function new(string name, uvm_component parent); super.new(name, parent); endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(model_run_config)::get(this, "", "run_cfg", cfg))
                `uvm_fatal("NOCFG", "Missing model_run_config")
            env = bottleneck_env::type_id::create("env", this);
        endfunction

        function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);
            env.scoreboard.cfg = cfg;
            seq = new;
            seq.env = env;
            seq.cfg = cfg;
        endfunction

        task reset_dut();
            @(negedge env.ctrl.driver.vif.clk);
            env.ctrl.driver.vif.reset_request = 1;
            repeat (4) @(posedge env.ctrl.driver.vif.clk);
            @(negedge env.ctrl.driver.vif.clk);
            env.ctrl.driver.vif.reset_request = 0;
        endtask

        task check_reset();
            bit [31:0] state;
            seq.read_status(state);
            if (state != 0) `uvm_fatal("RESET", $sformatf("Unexpected status %08h", state))
        endtask

        virtual task exercise();
            seq.start(null);
        endtask

        task run_phase(uvm_phase phase);
            phase.raise_objection(this);
            reset_dut();
            check_reset();
            exercise();
            `uvm_info("COUNTS", $sformatf("commands=%0d feature=%0d kernel=%0d bias=%0d result=%0d max_result_delta=%0d LSB",
                env.scoreboard.checked_commands, env.scoreboard.total[FEATURE],
                env.scoreboard.total[KERNEL], env.scoreboard.total[BIAS],
                env.scoreboard.total[RESULT], env.scoreboard.max_result_delta), UVM_LOW)
            phase.drop_objection(this);
        endtask
    endclass

    class model_inference_test extends model_base_test;
        `uvm_component_utils(model_inference_test)
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        virtual task exercise();
            seq.exercise_stalls = 1;
            seq.start(null);
            if (env.streams[RESULT].monitor.stall_cycles == 0)
                `uvm_fatal("NO_STALL", "Full inference did not exercise result backpressure")
        endtask
    endclass

    class model_unit_test extends model_base_test;
        `uvm_component_utils(model_unit_test)
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
    endclass

    class model_fault_test extends model_base_test;
        `uvm_component_utils(model_fault_test)
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        virtual task exercise();
            env.scoreboard.expect_bad_result = 1;
            seq.start(null);
            if (env.scoreboard.errors != 1)
                `uvm_fatal("FAULT_MISSED", "Scoreboard did not reject the corrupted result")
        endtask
    endclass

    class model_regression_test extends model_base_test;
        `uvm_component_utils(model_regression_test)
        function new(string name, uvm_component parent); super.new(name, parent); endfunction

        task bad_packet(int count, int last_index);
            axis_item item;
            bit [31:0] state;
            bit timed_out;
            seq.write_command(cfg.commands[0], 3, 0);
            item = seq.source_request(cfg.commands[0], FEATURE);
            item.count = count;
            item.last_index = last_index;
            seq.transfer_stream(FEATURE, item);
            seq.wait_status(state, timed_out, 16);
            if (item.timed_out || item.aborted || timed_out || !(state & cfg.error_mask) ||
                (state & cfg.done_mask))
                `uvm_fatal("PACKET_ERROR", "Malformed packet did not set ERROR")
            `uvm_info("EXPECTED_PACKET_ERROR",
                      $sformatf("Rejected count=%0d last_index=%0d", count, last_index), UVM_LOW)
        endtask

        virtual task exercise();
            bit [31:0] state;
            bit timed_out;
            axis_item item;

            seq.start(null);
            seq.start(null); // DONE from the previous inference must clear on new INPUT.
            bad_packet(1, 0);
            bad_packet(2, -1);

            seq.write_command(cfg.commands[0]);
            seq.wait_status(state, timed_out, 8);
            if (!timed_out) `uvm_fatal("TIMEOUT_MISSED", "Missing data did not cause a poll timeout")

            item = seq.source_request(cfg.commands[0], FEATURE);
            item.pause_after_first = 12;
            fork
                seq.transfer_stream(FEATURE, item);
                begin
                    wait (item.armed);
                    repeat (2) @(posedge env.ctrl.driver.vif.clk);
                    reset_dut();
                end
            join
            if (!item.aborted) `uvm_fatal("RESET_MISSED", "In-flight stream was not aborted")
            check_reset();

            seq.exercise_stalls = 1;
            seq.start(null);
            if (env.streams[RESULT].monitor.stall_cycles == 0)
                `uvm_fatal("NO_STALL", "Result backpressure was not exercised")
            `uvm_info("RECOVERY", "Stale DONE, timeout, in-flight reset and backpressure checked",
                      UVM_LOW)
        endtask
    endclass

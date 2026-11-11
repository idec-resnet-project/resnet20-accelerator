    // --------------------------------
    // Full inference
    // --------------------------------
    class model_inference_test extends uvm_test;
        `uvm_component_utils(model_inference_test)

        bottleneck_env env;
        model_run_config cfg;
        model_run_seq seq;
        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

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

        task run_phase(uvm_phase phase);
            phase.raise_objection(this);
            reset_dut();
            check_reset();
            seq.start(null);
            if (env.streams[RESULT].monitor.stall_cycles == 0)
                `uvm_fatal("NO_STALL", "Full inference did not exercise result backpressure")
            `uvm_info("COUNTS", $sformatf("commands=%0d feature=%0d kernel=%0d bias=%0d result=%0d",
                env.scoreboard.checked_commands, env.scoreboard.total[FEATURE],
                env.scoreboard.total[KERNEL], env.scoreboard.total[BIAS],
                env.scoreboard.total[RESULT]), UVM_LOW)
            phase.drop_objection(this);
        endtask
    endclass

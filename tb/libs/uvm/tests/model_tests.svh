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
            uvm_top.set_report_severity_id_action(UVM_INFO, "RNTST", UVM_NO_ACTION);
            uvm_top.set_report_severity_id_action(UVM_INFO, "UVM/COMP/NAMECHECK", UVM_NO_ACTION);
            uvm_top.set_report_severity_id_action(UVM_INFO, "TEST_DONE", UVM_NO_ACTION);
            uvm_top.set_report_severity_id_action(UVM_INFO, "UVM/REPORT/SERVER", UVM_NO_ACTION);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(model_run_config)::get(this, "", "run_cfg", cfg))
                test_fatal("NOCFG", "Missing model_run_config");
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
`ifdef TB_CORE_POST_SYNTHESIS
            // Xilinx primitives remain under global startup reset for 100 ns.
            #100ns;
`endif
            @(negedge env.ctrl.driver.vif.clk);
            env.ctrl.driver.vif.reset_request = 0;
        endtask

        task check_reset();
            bit [31:0] state;
            seq.read_status(state);
            if (state != 0) test_fatal("RESET", $sformatf("Unexpected status %08h", state));
        endtask

        task run_phase(uvm_phase phase);
            phase.raise_objection(this);
            reset_dut();
            check_reset();
            seq.start(null);
            if (env.streams[RESULT].monitor.stall_cycles == 0)
                test_fatal("NO_STALL", "Inference did not exercise result backpressure");
            phase.drop_objection(this);
        endtask
        function void final_phase(uvm_phase phase);
            uvm_report_server server;
            int status_file;
            super.final_phase(phase);
            server = uvm_report_server::get_server();
            if (cfg.commands.size() == 0 || env.scoreboard.checked_commands != cfg.commands.size())
                test_error("COMMAND_COUNT", "The command plan did not complete");
            if (!test_failed && server.get_severity_count(UVM_ERROR) == 0 &&
                server.get_severity_count(UVM_FATAL) == 0) begin
                status_file = $fopen("uvm_test_passed", "w");
                if (status_file)
                    $fclose(status_file);
                else
                    test_error("STATUS_FILE", "Cannot create uvm_test_passed");
            end
        endfunction
    endclass

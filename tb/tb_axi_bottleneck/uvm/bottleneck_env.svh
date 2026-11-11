    class bottleneck_env extends uvm_env;
        `uvm_component_utils(bottleneck_env)
        axi_lite_agent ctrl;
        axis_agent streams[4];
        bottleneck_scoreboard scoreboard;
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            ctrl = axi_lite_agent::type_id::create("ctrl", this);
            streams[FEATURE] = axis_agent::type_id::create("feature", this);
            streams[KERNEL] = axis_agent::type_id::create("kernel", this);
            streams[BIAS] = axis_agent::type_id::create("bias", this);
            streams[RESULT] = axis_agent::type_id::create("output", this);
            foreach (streams[s]) streams[s].stream = model_stream_e'(s);
            scoreboard = bottleneck_scoreboard::type_id::create("scoreboard", this);
        endfunction
        function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);
            ctrl.monitor.observed.connect(scoreboard.axi);
            foreach (streams[s]) streams[s].monitor.observed.connect(scoreboard.axis);
        endfunction
    endclass

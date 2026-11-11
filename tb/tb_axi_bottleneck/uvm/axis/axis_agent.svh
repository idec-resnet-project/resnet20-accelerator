    // --------------------------------
    // Stream packet
    // --------------------------------
    class axis_item extends uvm_sequence_item;
        `uvm_object_utils(axis_item)

        model_words_t words;
        int count;
        int initial_delay = 0;
        int gap_max = 0;
        int timeout_cycles = 1_000_000;
        bit armed, aborted, timed_out;
        function new(string name = "axis_item");
            super.new(name);
        endfunction
    endclass

    // --------------------------------
    // Single packet sequence
    // --------------------------------
    class axis_transfer extends uvm_sequence #(axis_item);
        axis_item request;
        function new(string name = "axis_transfer");
            super.new(name);
        endfunction

        virtual task body();
            start_item(request);
            finish_item(request);
        endtask
    endclass

    // --------------------------------
    // Source and sink driver
    // --------------------------------
    class axis_driver extends uvm_driver #(axis_item);
        `uvm_component_utils(axis_driver)

        virtual axis_if vif;
        bit sink;
        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual axis_if)::get(this, "", "vif", vif))
                `uvm_fatal("NOVIF", "Missing AXI-Stream interface")
        endfunction

        task drive(axis_item item);
            int beat, gap, stall;
            bit accepted;
            beat = 0;
            stall = 0;
            gap = item.initial_delay;
            // The model sequence waits here before issuing an output command.
            item.armed = 1;
            while (beat < item.count) begin
                if (!vif.nrst) begin
                    item.aborted = 1;
                    break;
                end
                if (sink) vif.tready = gap == 0;
                else begin
                    vif.tvalid = gap == 0;
                    vif.tdata = item.words[beat][15:0];
                    vif.tlast = beat == item.count - 1;
                end
                @(posedge vif.clk);
                accepted = vif.nrst && vif.tvalid && vif.tready;
                @(negedge vif.clk);
                if (accepted) begin
                    beat++;
                    stall = 0;
                    gap = item.gap_max ? $urandom_range(item.gap_max, 0) : 0;
                end else if (gap > 0) gap--;
                else if (++stall >= item.timeout_cycles) begin
                    item.timed_out = 1;
                    break;
                end
            end
            if (sink) vif.tready = 0;
            else vif.tvalid = 0;
        endtask

        task run_phase(uvm_phase phase);
            axis_item item;
            if (sink) vif.tready = 0;
            else begin
                vif.tvalid = 0;
                vif.tlast = 0;
                vif.tdata = 0;
            end
            forever begin
                seq_item_port.get_next_item(item);
                wait (vif.nrst);
                @(negedge vif.clk);
                drive(item);
                seq_item_port.item_done();
            end
        endtask
    endclass

    // --------------------------------
    // Observed transfer
    // --------------------------------
    class axis_beat extends uvm_object;
        model_stream_e stream;
        logic [15:0] data;
        logic [1:0] keep;
        logic last;
        function new(string name = "axis_beat");
            super.new(name);
        endfunction
    endclass

    // --------------------------------
    // Handshake and stall monitor
    // --------------------------------
    class axis_monitor extends uvm_monitor;
        `uvm_component_utils(axis_monitor)

        virtual axis_if vif;
        model_stream_e stream;
        uvm_analysis_port #(axis_beat) observed;
        int stall_cycles = 0;
        function new(string name, uvm_component parent);
            super.new(name, parent);
            observed = new("observed", this);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual axis_if)::get(this, "", "vif", vif))
                `uvm_fatal("NOVIF", "Missing AXI-Stream monitor interface")
        endfunction

        task run_phase(uvm_phase phase);
            axis_beat beat;
            bit stalled;
            logic [18:0] held;
            forever begin
                @(posedge vif.clk);
                if (!vif.nrst) begin
                    stalled = 0;
                    continue;
                end
                // A pending transfer must keep its payload and TVALID stable.
                if (stalled && (vif.tvalid !== 1'b1 ||
                    {vif.tdata, vif.tkeep, vif.tlast} !== held))
                    `uvm_error("AXIS_STALL", "TVALID or payload changed before handshake")
                stalled = vif.tvalid && !vif.tready;
                if (stalled) begin
                    stall_cycles++;
                    held = {vif.tdata, vif.tkeep, vif.tlast};
                end
                if (vif.tvalid && vif.tready) begin
                    beat = new;
                    beat.stream = stream;
                    beat.data = vif.tdata;
                    beat.keep = vif.tkeep;
                    beat.last = vif.tlast;
                    observed.write(beat);
                end
            end
        endtask
    endclass

    // --------------------------------
    // AXI-Stream agent
    // --------------------------------
    class axis_agent extends uvm_agent;
        `uvm_component_utils(axis_agent)

        uvm_sequencer #(axis_item) sequencer;
        axis_driver driver;
        axis_monitor monitor;
        model_stream_e stream;
        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            sequencer = new("sequencer", this);
            driver = axis_driver::type_id::create("driver", this);
            driver.sink = stream == RESULT;
            monitor = axis_monitor::type_id::create("monitor", this);
            monitor.stream = stream;
        endfunction

        function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);
            driver.seq_item_port.connect(sequencer.seq_item_export);
        endfunction
    endclass

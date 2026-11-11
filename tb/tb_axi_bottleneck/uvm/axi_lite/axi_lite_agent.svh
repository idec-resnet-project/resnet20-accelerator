    class axi_lite_item extends uvm_sequence_item;
        `uvm_object_utils(axi_lite_item)
        bit write;
        bit [31:0] addr, data;
        bit [1:0] resp;
        int aw_delay, w_delay;
        int timeout_cycles = 1_000_000;
        function new(string name = "axi_lite_item"); super.new(name); endfunction
    endclass

    class axi_lite_transfer extends uvm_sequence #(axi_lite_item);
        axi_lite_item request;
        function new(string name = "axi_lite_transfer"); super.new(name); endfunction
        virtual task body();
            start_item(request);
            finish_item(request);
        endtask
    endclass

    class axi_lite_driver extends uvm_driver #(axi_lite_item);
        `uvm_component_utils(axi_lite_driver)
        virtual axi_lite_if vif;

        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual axi_lite_if)::get(this, "", "vif", vif))
                `uvm_fatal("NOVIF", "Missing AXI-Lite interface")
        endfunction

        task drive_aw(axi_lite_item item);
            repeat (item.aw_delay) @(negedge vif.clk);
            vif.awaddr = item.addr;
            vif.awvalid = 1;
            for (int i = 0; i < item.timeout_cycles; i++) begin
                @(posedge vif.clk);
                if (!vif.nrst || vif.awready) begin
                    @(negedge vif.clk);
                    vif.awvalid = 0;
                    return;
                end
            end
            `uvm_fatal("AXI_TIMEOUT", "AW timeout")
        endtask

        task drive_w(axi_lite_item item);
            repeat (item.w_delay) @(negedge vif.clk);
            vif.wdata = item.data;
            vif.wvalid = 1;
            for (int i = 0; i < item.timeout_cycles; i++) begin
                @(posedge vif.clk);
                if (!vif.nrst || vif.wready) begin
                    @(negedge vif.clk);
                    vif.wvalid = 0;
                    return;
                end
            end
            `uvm_fatal("AXI_TIMEOUT", "W timeout")
        endtask

        task drive_write(axi_lite_item item);
            fork
                drive_aw(item);
                drive_w(item);
            join
            vif.bready = 1;
            for (int i = 0; i < item.timeout_cycles; i++) begin
                @(posedge vif.clk);
                if (!vif.nrst || vif.bvalid) begin
                    item.resp = vif.nrst ? vif.bresp : 2'b10;
                    @(negedge vif.clk);
                    vif.bready = 0;
                    return;
                end
            end
            `uvm_fatal("AXI_TIMEOUT", "B timeout")
        endtask

        task drive_read(axi_lite_item item);
            bit accepted;
            accepted = 0;
            vif.araddr = item.addr;
            vif.arvalid = 1;
            vif.rready = 1;
            for (int i = 0; i < item.timeout_cycles; i++) begin
                @(posedge vif.clk);
                if (vif.arready) accepted = 1;
                if (!vif.nrst || vif.rvalid) begin
                    item.data = vif.rdata;
                    item.resp = vif.nrst ? vif.rresp : 2'b10;
                    @(negedge vif.clk);
                    vif.arvalid = 0;
                    vif.rready = 0;
                    return;
                end
                @(negedge vif.clk);
                if (accepted) vif.arvalid = 0;
            end
            `uvm_fatal("AXI_TIMEOUT", "AR/R timeout")
        endtask

        task run_phase(uvm_phase phase);
            axi_lite_item item;
            vif.awvalid = 0;
            vif.awprot = 0;
            vif.wvalid = 0;
            vif.wstrb = '1;
            vif.bready = 0;
            vif.arvalid = 0;
            vif.arprot = 0;
            vif.rready = 0;
            forever begin
                seq_item_port.get_next_item(item);
                wait (vif.nrst);
                @(negedge vif.clk);
                if (item.write) drive_write(item);
                else drive_read(item);
                seq_item_port.item_done();
            end
        endtask
    endclass

    class axi_lite_monitor extends uvm_monitor;
        `uvm_component_utils(axi_lite_monitor)
        virtual axi_lite_if vif;
        uvm_analysis_port #(axi_lite_item) observed;
        function new(string name, uvm_component parent);
            super.new(name, parent);
            observed = new("observed", this);
        endfunction
        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual axi_lite_if)::get(this, "", "vif", vif))
                `uvm_fatal("NOVIF", "Missing AXI-Lite monitor interface")
        endfunction
        task run_phase(uvm_phase phase);
            bit [31:0] awaddr, wdata;
            axi_lite_item item;
            forever begin
                @(posedge vif.clk);
                if (!vif.nrst) continue;
                if (vif.awvalid && vif.awready) awaddr = vif.awaddr;
                if (vif.wvalid && vif.wready) wdata = vif.wdata;
                if (vif.bvalid && vif.bready) begin
                    item = new;
                    item.write = 1;
                    item.addr = awaddr;
                    item.data = wdata;
                    item.resp = vif.bresp;
                    observed.write(item);
                end
            end
        endtask
    endclass

    class axi_lite_agent extends uvm_agent;
        `uvm_component_utils(axi_lite_agent)
        uvm_sequencer #(axi_lite_item) sequencer;
        axi_lite_driver driver;
        axi_lite_monitor monitor;
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            sequencer = new("sequencer", this);
            driver = axi_lite_driver::type_id::create("driver", this);
            monitor = axi_lite_monitor::type_id::create("monitor", this);
        endfunction
        function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);
            driver.seq_item_port.connect(sequencer.seq_item_export);
        endfunction
    endclass

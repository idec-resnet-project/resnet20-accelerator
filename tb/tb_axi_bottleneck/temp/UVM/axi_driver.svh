// 드라이버: 트랜잭션을 AXI 채널 신호로 바꾼다.
class driver extends uvm_driver #(item);

    `uvm_component_utils(driver)

    virtual axi_if vif;

    uvm_analysis_port #(item) expected_ap;
    int ADDRESS;

    // 생성자
    function new(string name, uvm_component parent);
        super.new(name, parent);
        expected_ap = new("expected_ap", this);
    endfunction

    // 설정 단계: 인터페이스 핸들을 가져온다.
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db#(virtual axi_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "AXI interface is missing")
        if (!uvm_config_db#(int)::get(this, "", "ADDRESS", ADDRESS))
            `uvm_fatal("NOVIF", "ADDRESS is missing")

    endfunction

    task AW_phase(item req);
        @(vif.cb);
        vif.cb.m_axi_awid <= 0;
        vif.cb.m_axi_awvalid <= 1;
        vif.cb.m_axi_awaddr <= ADDRESS;
        vif.cb.m_axi_awlen <= req.N - 1;
        vif.cb.m_axi_awsize <= 2; 
        vif.cb.m_axi_awburst <= 1;
        vif.cb.m_axi_awlock <= 0;
        vif.cb.m_axi_awcache <= 0;
        vif.cb.m_axi_awprot <= 0;
        vif.cb.m_axi_awqos <= 0;

        do 
            @(vif.cb);
        while (vif.cb.m_axi_awready !== 1'b1);
        vif.cb.m_axi_awvalid <= 0;
    endtask

    task W_phase(item req);
        @(vif.cb);
        vif.cb.m_axi_wvalid <= 1;
        vif.cb.m_axi_wstrb <= '1;

        for (int i=0; i<req.N; i++) begin
            vif.cb.m_axi_wdata <= {24'b0, req.data[i][7:0]};
            vif.cb.m_axi_wlast <= (i == req.N-1);
            do
                @(vif.cb);
            while (vif.cb.m_axi_wready !== 1'b1);
        end
        vif.cb.m_axi_wvalid <= 0;
        vif.cb.m_axi_wlast <= 0;
    endtask

    task B_phase();
        vif.cb.m_axi_bready <= 1;
        do
            @(vif.cb);
        while (vif.cb.m_axi_bvalid !== 1'b1);
        if (vif.cb.m_axi_bresp !== 2'b00)
            `uvm_error("BRESP", "AXI write response is not OKAY")
        vif.cb.m_axi_bready <= 0;
    endtask

    task AR_phase(item req);
        @(vif.cb);
        vif.cb.m_axi_arid <= 0;
        vif.cb.m_axi_arvalid <= 1;
        vif.cb.m_axi_araddr <= ADDRESS;
        vif.cb.m_axi_arlen <= req.N - 1;
        vif.cb.m_axi_arsize <= 2; 
        vif.cb.m_axi_arburst <= 1;
        vif.cb.m_axi_arlock <= 0;
        vif.cb.m_axi_arcache <= 0;
        vif.cb.m_axi_arprot <= 0;
        vif.cb.m_axi_arqos <= 0;

        do 
            @(vif.cb);
        while (vif.cb.m_axi_arready !== 1'b1);
        vif.cb.m_axi_arvalid <= 0;
    endtask
    
    task R_phase(item req);
        @(vif.cb);
        vif.cb.m_axi_rready <= 1;

        for (int i=0; i<req.N; i++) begin
            do
                @(vif.cb);
            while (vif.cb.m_axi_rvalid !== 1'b1);
            if (vif.cb.m_axi_rresp !== 2'b00)
                `uvm_error("RRESP", "AXI read response is not OKAY")
            if (vif.cb.m_axi_rlast !== (i == req.N-1))
                `uvm_error("RLAST", "AXI read burst length does not match N")
        end
        vif.cb.m_axi_rready <= 0;
    endtask

    task run_phase(uvm_phase phase);
        item req;

        @(vif.cb);
        vif.cb.m_axi_awid <= 0;
        vif.cb.m_axi_awaddr <= 0;
        vif.cb.m_axi_awlen <= 0;
        vif.cb.m_axi_awsize <= 2;
        vif.cb.m_axi_awburst <= 1;
        vif.cb.m_axi_awlock <= 0;
        vif.cb.m_axi_awcache <= 0;
        vif.cb.m_axi_awprot <= 0;
        vif.cb.m_axi_awqos <= 0;
        vif.cb.m_axi_awvalid <= 0;
        vif.cb.m_axi_wdata <= 0;
        vif.cb.m_axi_wstrb <= '1;
        vif.cb.m_axi_wlast <= 0;
        vif.cb.m_axi_wvalid <= 0;
        vif.cb.m_axi_bready <= 0;
        vif.cb.m_axi_arid <= 0;
        vif.cb.m_axi_araddr <= 0;
        vif.cb.m_axi_arlen <= 0;
        vif.cb.m_axi_arsize <= 2;
        vif.cb.m_axi_arburst <= 1;
        vif.cb.m_axi_arlock <= 0;
        vif.cb.m_axi_arcache <= 0;
        vif.cb.m_axi_arprot <= 0;
        vif.cb.m_axi_arqos <= 0;
        vif.cb.m_axi_arvalid <= 0;
        vif.cb.m_axi_rready <= 0;

        do
            @(vif.cb);
        while (vif.rst !== 1'b1);

        `uvm_info("AXI_READY", "Reset released; waiting for a transaction", UVM_MEDIUM)

        forever begin
            seq_item_port.get_next_item(req);
            `uvm_info("AXI_WRITE", $sformatf("Starting %0d UART bytes", req.N), UVM_MEDIUM)
            expected_ap.write(req);

            AW_phase(req);
            W_phase(req);
            B_phase();
            AR_phase(req);
            R_phase(req);

            seq_item_port.item_done();
        end
    endtask

endclass

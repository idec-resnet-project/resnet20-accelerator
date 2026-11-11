module tb_axi_bottleneck;
    import uvm_pkg::*;
    import model_contract_pkg::*;
    import tb_axi_bottleneck_pkg::*;
    import resnet20_pkg::*;

    logic clk = 0;
    wire nrst;
    always #5 clk = ~clk;

    axi_lite_if ctrl(clk, nrst);
    assign nrst = !ctrl.reset_request;
    axis_if feature_axis(clk, nrst);
    axis_if kernel_axis(clk, nrst);
    axis_if bias_axis(clk, nrst);
    axis_if output_axis(clk, nrst);
    assign feature_axis.tkeep = 2'b11;
    assign kernel_axis.tkeep = 2'b11;
    assign bias_axis.tkeep = 2'b11;
    model_backend backend;

    axi_bottleneck_dummy dut (
        .s_axi_aclk(clk),
        .s_axi_aresetn(nrst),
        .s_axi_awaddr(ctrl.awaddr),
        .s_axi_awprot(ctrl.awprot),
        .s_axi_awvalid(ctrl.awvalid),
        .s_axi_awready(ctrl.awready),
        .s_axi_wdata(ctrl.wdata),
        .s_axi_wstrb(ctrl.wstrb),
        .s_axi_wvalid(ctrl.wvalid),
        .s_axi_wready(ctrl.wready),
        .s_axi_bresp(ctrl.bresp),
        .s_axi_bvalid(ctrl.bvalid),
        .s_axi_bready(ctrl.bready),
        .s_axi_araddr(ctrl.araddr),
        .s_axi_arprot(ctrl.arprot),
        .s_axi_arvalid(ctrl.arvalid),
        .s_axi_arready(ctrl.arready),
        .s_axi_rdata(ctrl.rdata),
        .s_axi_rresp(ctrl.rresp),
        .s_axi_rvalid(ctrl.rvalid),
        .s_axi_rready(ctrl.rready),
        .s_axis_feature_tdata(feature_axis.tdata),
        .s_axis_feature_tvalid(feature_axis.tvalid),
        .s_axis_feature_tlast(feature_axis.tlast),
        .s_axis_feature_tready(feature_axis.tready),
        .s_axis_kernel_tdata(kernel_axis.tdata),
        .s_axis_kernel_tvalid(kernel_axis.tvalid),
        .s_axis_kernel_tlast(kernel_axis.tlast),
        .s_axis_kernel_tready(kernel_axis.tready),
        .s_axis_bias_tdata(bias_axis.tdata),
        .s_axis_bias_tvalid(bias_axis.tvalid),
        .s_axis_bias_tlast(bias_axis.tlast),
        .s_axis_bias_tready(bias_axis.tready),
        .m_axis_output_tdata(output_axis.tdata),
        .m_axis_output_tkeep(output_axis.tkeep),
        .m_axis_output_tvalid(output_axis.tvalid),
        .m_axis_output_tlast(output_axis.tlast),
        .m_axis_output_tready(output_axis.tready)
    );

    // Real RTL integration. Enable when bias reception and status reads are implemented.
    /*
    axi_bottleneck dut (
        .s_axi_aclk(clk),
        .s_axi_aresetn(nrst),
        .s_axi_awaddr(ctrl.awaddr),
        .s_axi_awprot(ctrl.awprot),
        .s_axi_awvalid(ctrl.awvalid),
        .s_axi_awready(ctrl.awready),
        .s_axi_wdata(ctrl.wdata),
        .s_axi_wstrb(ctrl.wstrb),
        .s_axi_wvalid(ctrl.wvalid),
        .s_axi_wready(ctrl.wready),
        .s_axi_bresp(ctrl.bresp),
        .s_axi_bvalid(ctrl.bvalid),
        .s_axi_bready(ctrl.bready),
        .s_axi_araddr(ctrl.araddr),
        .s_axi_arprot(ctrl.arprot),
        .s_axi_arvalid(ctrl.arvalid),
        .s_axi_arready(ctrl.arready),
        .s_axi_rdata(ctrl.rdata),
        .s_axi_rresp(ctrl.rresp),
        .s_axi_rvalid(ctrl.rvalid),
        .s_axi_rready(ctrl.rready),
        .s_axis_feature_tdata(feature_axis.tdata),
        .s_axis_feature_tvalid(feature_axis.tvalid),
        .s_axis_feature_tlast(feature_axis.tlast),
        .s_axis_feature_tready(feature_axis.tready),
        .s_axis_kernel_tdata(kernel_axis.tdata),
        .s_axis_kernel_tvalid(kernel_axis.tvalid),
        .s_axis_kernel_tlast(kernel_axis.tlast),
        .s_axis_kernel_tready(kernel_axis.tready),
        .s_axis_bias_tdata(bias_axis.tdata),
        .s_axis_bias_tvalid(bias_axis.tvalid),
        .s_axis_bias_tlast(bias_axis.tlast),
        .s_axis_bias_tready(bias_axis.tready),
        .m_axis_output_tdata(output_axis.tdata),
        .m_axis_output_tkeep(output_axis.tkeep),
        .m_axis_output_tvalid(output_axis.tvalid),
        .m_axis_output_tlast(output_axis.tlast),
        .m_axis_output_tready(output_axis.tready)
    );
    */

    initial begin
        model_run_config cfg;
        string tb_dir, test_name;
        bit unit_test;

        if (!$value$plusargs("TB_DIR=%s", tb_dir)) tb_dir = ".";
        if (!$value$plusargs("UVM_TESTNAME=%s", test_name)) test_name = "model_inference_test";
        unit_test = test_name != "model_inference_test";
        cfg = build_model_config({tb_dir, "/", MODEL_DATA_SUBDIR}, unit_test);
        backend = build_model_backend(unit_test);
        dut.set_backend(backend, test_name == "model_fault_test");
        uvm_config_db#(model_run_config)::set(null, "uvm_test_top", "run_cfg", cfg);
        uvm_config_db#(virtual axi_lite_if)::set(null, "uvm_test_top.env.ctrl*", "vif", ctrl);
        uvm_config_db#(virtual axis_if)::set(null, "uvm_test_top.env.feature*", "vif", feature_axis);
        uvm_config_db#(virtual axis_if)::set(null, "uvm_test_top.env.kernel*", "vif", kernel_axis);
        uvm_config_db#(virtual axis_if)::set(null, "uvm_test_top.env.bias*", "vif", bias_axis);
        uvm_config_db#(virtual axis_if)::set(null, "uvm_test_top.env.output*", "vif", output_axis);
        run_test(test_name);
    end

    initial begin
        #100ms;
        $fatal(1, "Simulation watchdog timed out");
    end

    final begin
        if (backend != null) backend.close();
    end
endmodule

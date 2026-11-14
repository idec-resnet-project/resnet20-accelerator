module tb_axi_bottleneck;
    localparam int OUTPUT_FRAC_BITS = 10;
    import uvm_pkg::*;
    import model_contract_pkg::*;
    import tb_axi_bottleneck_pkg::*;
    import resnet20_pkg::*;

    // --------------------------------
    // Clock and reset
    // --------------------------------
    logic clk = 0;
    wire nrst;
    always #1 clk = ~clk;

    assign nrst = !ctrl.reset_request;

    // --------------------------------
    // Bus interfaces
    // --------------------------------
    axi_lite_if ctrl         (clk, nrst);
    axis_if     feature_axis (clk, nrst);
    axis_if     kernel_axis  (clk, nrst);
    axis_if     bias_axis    (clk, nrst);
    axis_if     output_axis  (clk, nrst);

    // All input words carry two valid bytes.
    assign feature_axis.tkeep = 2'b11;
    assign kernel_axis.tkeep  = 2'b11;
    assign bias_axis.tkeep    = 2'b11;

    // --------------------------------
    // DUT port map
    // --------------------------------
`ifdef TB_AXI_BOTTLENECK_USE_RTL
    axi_bottleneck dut (
`else
    axi_bottleneck_dummy dut (
`endif
        .s_axi_aclk            (clk),
        .s_axi_aresetn         (nrst),

        // AXI-Lite write address
        .s_axi_awaddr          (ctrl.awaddr),
        .s_axi_awprot          (ctrl.awprot),
        .s_axi_awvalid         (ctrl.awvalid),
        .s_axi_awready         (ctrl.awready),

        // AXI-Lite write data
        .s_axi_wdata           (ctrl.wdata),
        .s_axi_wstrb           (ctrl.wstrb),
        .s_axi_wvalid          (ctrl.wvalid),
        .s_axi_wready          (ctrl.wready),

        // AXI-Lite write response
        .s_axi_bresp           (ctrl.bresp),
        .s_axi_bvalid          (ctrl.bvalid),
        .s_axi_bready          (ctrl.bready),

        // AXI-Lite read address
        .s_axi_araddr          (ctrl.araddr),
        .s_axi_arprot          (ctrl.arprot),
        .s_axi_arvalid         (ctrl.arvalid),
        .s_axi_arready         (ctrl.arready),

        // AXI-Lite read data and response
        .s_axi_rdata           (ctrl.rdata),
        .s_axi_rresp           (ctrl.rresp),
        .s_axi_rvalid          (ctrl.rvalid),
        .s_axi_rready          (ctrl.rready),

        // Feature input DMA
        .s_axis_feature_tdata  (feature_axis.tdata),
        .s_axis_feature_tvalid (feature_axis.tvalid),
        .s_axis_feature_tlast  (feature_axis.tlast),
        .s_axis_feature_tready (feature_axis.tready),

        // Kernel input DMA
        .s_axis_kernel_tdata   (kernel_axis.tdata),
        .s_axis_kernel_tvalid  (kernel_axis.tvalid),
        .s_axis_kernel_tlast   (kernel_axis.tlast),
        .s_axis_kernel_tready  (kernel_axis.tready),

        // Bias input DMA
        .s_axis_bias_tdata     (bias_axis.tdata),
        .s_axis_bias_tvalid    (bias_axis.tvalid),
        .s_axis_bias_tlast     (bias_axis.tlast),
        .s_axis_bias_tready    (bias_axis.tready),

        // Result output DMA
        .m_axis_output_tdata   (output_axis.tdata),
        .m_axis_output_tkeep   (output_axis.tkeep),
        .m_axis_output_tvalid  (output_axis.tvalid),
        .m_axis_output_tlast   (output_axis.tlast),
        .m_axis_output_tready  (output_axis.tready)
    );

    // --------------------------------
    // Model setup and UVM configuration
    // --------------------------------
`ifndef TB_AXI_BOTTLENECK_USE_RTL
    model_backend backend;
`endif

    initial begin : configure_test
        model_run_config cfg;
        string tb_dir;

        if (OUTPUT_FRAC_BITS < 0 || OUTPUT_FRAC_BITS > 15)
            $fatal(1, "OUTPUT_FRAC_BITS must be between 0 and 15");
        if (!$value$plusargs("TB_DIR=%s", tb_dir)) tb_dir = ".";
        cfg = build_model_config({tb_dir, "/", MODEL_DATA_SUBDIR}, OUTPUT_FRAC_BITS);
`ifndef TB_AXI_BOTTLENECK_USE_RTL
        backend = build_model_backend(cfg.output_frac_bits);
        dut.set_backend(backend);
`endif

        uvm_config_db#(model_run_config)::set(null, "uvm_test_top", "run_cfg", cfg);
        uvm_config_db#(virtual axi_lite_if)::set(null, "uvm_test_top.env.ctrl*", "vif", ctrl);
        uvm_config_db#(virtual axis_if)::set(null, "uvm_test_top.env.feature*", "vif", feature_axis);
        uvm_config_db#(virtual axis_if)::set(null, "uvm_test_top.env.kernel*", "vif", kernel_axis);
        uvm_config_db#(virtual axis_if)::set(null, "uvm_test_top.env.bias*", "vif", bias_axis);
        uvm_config_db#(virtual axis_if)::set(null, "uvm_test_top.env.output*", "vif", output_axis);
        run_test("model_inference_test");
    end

    // --------------------------------
    // Watchdog and model cleanup
    // --------------------------------
    initial begin
        #100000ms;
        $fatal(1, "Simulation watchdog timed out");
    end

`ifndef TB_AXI_BOTTLENECK_USE_RTL
    final begin
        if (backend != null) backend.close();
    end
`endif
endmodule

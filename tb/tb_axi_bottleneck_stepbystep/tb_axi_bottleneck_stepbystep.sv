package stepbystep_conv1x1_model_pkg;
    import model_contract_pkg::*;

    localparam int INPUT_SIZE = 8;
    localparam int IN_CHANNELS = 3;
    localparam int OUT_CHANNELS = 4;
    localparam int KERNEL_SIZE = 1;
    localparam int STRIDE = 1;
    localparam int PADDING = 0;
    localparam bit RELU_ENABLE = 0;
    localparam bit SEQUENTIAL_PAYLOADS = 1;

    `include "models/conv_model.svh"
endpackage

package stepbystep_conv3x3_model_pkg;
    import model_contract_pkg::*;

    localparam int INPUT_SIZE = 4;
    localparam int IN_CHANNELS = 2;
    localparam int OUT_CHANNELS = 2;
    localparam int KERNEL_SIZE = 3;
    localparam int STRIDE = 1;
    localparam int PADDING = 1;
    localparam bit RELU_ENABLE = 1;
    localparam bit SEQUENTIAL_PAYLOADS = 0;

    `include "models/conv_model.svh"
endpackage

package stepbystep_conv3x3stride_model_pkg;
    import model_contract_pkg::*;

    localparam int INPUT_SIZE = 4;
    localparam int IN_CHANNELS = 2;
    localparam int OUT_CHANNELS = 2;
    localparam int KERNEL_SIZE = 3;
    localparam int STRIDE = 2;
    localparam int PADDING = 1;
    localparam bit RELU_ENABLE = 1;
    localparam bit SEQUENTIAL_PAYLOADS = 0;

    `include "models/conv_model.svh"
endpackage

package stepbystep_test_pkg;
    import uvm_pkg::*;
    import model_contract_pkg::*;
    import tb_axi_bottleneck_pkg::*;
    `include "uvm_macros.svh"

    class stepbystep_stage extends model_inference_test;
        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        // The suite starts each stage explicitly.
        virtual task run_phase(uvm_phase phase);
        endtask

        virtual function void final_phase(uvm_phase phase);
        endfunction
    endclass

    class stepbystep_test extends uvm_test;
        `uvm_component_utils(stepbystep_test)

        string stage_names[4] = '{"conv1x1", "conv3x3", "conv3x3stride", "toy"};
        stepbystep_stage stages[4];
        bit stage_failed[4];

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        virtual function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            foreach (stages[i])
                stages[i] = new(stage_names[i], this);
        endfunction

        virtual task run_phase(uvm_phase phase);
            bit prior_failure;
            int errors_before;
            uvm_report_server server = uvm_report_server::get_server();

            phase.raise_objection(this);
            prior_failure = test_failed;
            foreach (stages[i]) begin
                $display("[ %0d/%0d ] %s", i + 1, $size(stages), stage_names[i]);
                test_failed = 0;
                errors_before = server.get_severity_count(UVM_ERROR);
                stages[i].run_inference();
                if (stages[i].cfg.commands.size() == 0 ||
                    stages[i].env.scoreboard.checked_commands != stages[i].cfg.commands.size())
                    test_error("COMMAND_COUNT", "The command plan did not complete");
                stage_failed[i] = test_failed || server.get_severity_count(UVM_ERROR) != errors_before;
                prior_failure |= stage_failed[i];
                test_failed = prior_failure;
            end
            phase.drop_objection(this);
        endtask

        virtual function void final_phase(uvm_phase phase);
            int status_file;
            uvm_report_server server = uvm_report_server::get_server();

            super.final_phase(phase);
            $display("\ntb_axi_bottleneck_stepbystep");
            $display("%-16s | %-12s | %s", "Test", "SNR", "Result");
            foreach (stages[i])
                $display("%-16s | %-12s | %s", stage_names[i],
                         stages[i].env.scoreboard.last_snr, stage_failed[i] ? "FAIL" : "PASS");
            if (test_failed || server.get_severity_count(UVM_ERROR) != 0 ||
                server.get_severity_count(UVM_FATAL) != 0) begin
                $display("[ FAIL ] tb_axi_bottleneck_stepbystep");
            end else begin
                status_file = $fopen("uvm_test_passed", "w");
                if (status_file) begin
                    $fclose(status_file);
                    $display("[ PASS ] tb_axi_bottleneck_stepbystep");
                end else begin
                    test_error("STATUS_FILE", "Cannot create uvm_test_passed");
                end
            end
        endfunction
    endclass
endpackage

module tb_axi_bottleneck_stepbystep;
    import uvm_pkg::*;
    import stepbystep_test_pkg::*;

    logic clk = 0;
    always #1 clk = ~clk;

    stepbystep_dut #("conv1x1") conv1x1(clk);
    stepbystep_dut #("conv3x3") conv3x3(clk);
    stepbystep_dut #("conv3x3stride") conv3x3stride(clk);
    stepbystep_dut #("toy") toy(clk);

    initial begin : configure_suite
        string tb_dir;

        if (!$value$plusargs("TB_DIR=%s", tb_dir)) tb_dir = ".";
        conv1x1.configure(stepbystep_conv1x1_model_pkg::build_model_config(
            ".", "reference_conv1x1_float.txt"));
        conv3x3.configure(stepbystep_conv3x3_model_pkg::build_model_config(
            ".", "reference_conv3x3_float.txt"));
        conv3x3stride.configure(stepbystep_conv3x3stride_model_pkg::build_model_config(
            ".", "reference_conv3x3stride_float.txt"));
        toy.configure(model_pkg::build_model_config(model_pkg::model_data_dir(tb_dir)));
        run_test("stepbystep_test");
    end

    initial begin
        #10000ms;
        $fatal(1, "Simulation watchdog timed out");
    end
endmodule

module stepbystep_dut #(
    parameter string STAGE_NAME = ""
)(input logic clk);
    import uvm_pkg::*;
    import model_contract_pkg::*;

    wire nrst;
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
    axi_bottleneck
`ifndef TB_CORE_POST_SYNTHESIS
    #(
        .CONFIG_DATA_BITWIDTH      (6),
        .BITWIDTH_MAC_ITERATION     (16),
        .BITWIDTH_POOLING_ITERATION (16),
        .BITWIDTH_GAP_ITERATION     (16),
        .PARALLEL_PC                (1),
        .PARALLEL_PF                (1),
        .AXI_LITE_ADDR_WIDTH        (32),
        .AXI_LITE_DATA_WIDTH        (32),
        .CONFIG_DEFAULT             ('0),
        .BRAM_FEATRE_CAPACITY       (9),
        .BRAM_KERNEL_CAPACITY       (12),
        .BRAM_BIAS_CAPACITY         (3),
        .ADDR_BITWIDTH               (3)
    )
`endif
    dut (
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

    task automatic configure(model_run_config cfg);
        string path;

        cfg.timeout_cycles = 100_000;
        path = {"uvm_test_top.", STAGE_NAME};
        uvm_config_db#(model_run_config)::set(null, path, "run_cfg", cfg);
        uvm_config_db#(virtual axi_lite_if)::set(null, {path, ".env.ctrl*"}, "vif", ctrl);
        uvm_config_db#(virtual axis_if)::set(null, {path, ".env.feature*"}, "vif", feature_axis);
        uvm_config_db#(virtual axis_if)::set(null, {path, ".env.kernel*"}, "vif", kernel_axis);
        uvm_config_db#(virtual axis_if)::set(null, {path, ".env.bias*"}, "vif", bias_axis);
        uvm_config_db#(virtual axis_if)::set(null, {path, ".env.output*"}, "vif", output_axis);
    endtask
endmodule

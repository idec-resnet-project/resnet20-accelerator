module axi_bottleneck_dummy (
    input  logic s_axi_aclk,
    input  logic s_axi_aresetn,
    input  logic [31:0] s_axi_awaddr,
    input  logic [2:0] s_axi_awprot,
    input  logic s_axi_awvalid,
    output logic s_axi_awready,
    input  logic [31:0] s_axi_wdata,
    input  logic [3:0] s_axi_wstrb,
    input  logic s_axi_wvalid,
    output logic s_axi_wready,
    output logic [1:0] s_axi_bresp,
    output logic s_axi_bvalid,
    input  logic s_axi_bready,
    input  logic [31:0] s_axi_araddr,
    input  logic [2:0] s_axi_arprot,
    input  logic s_axi_arvalid,
    output logic s_axi_arready,
    output logic [31:0] s_axi_rdata,
    output logic [1:0] s_axi_rresp,
    output logic s_axi_rvalid,
    input  logic s_axi_rready,
    input  logic [15:0] s_axis_feature_tdata,
    input  logic s_axis_feature_tvalid,
    input  logic s_axis_feature_tlast,
    output logic s_axis_feature_tready,
    input  logic [15:0] s_axis_kernel_tdata,
    input  logic s_axis_kernel_tvalid,
    input  logic s_axis_kernel_tlast,
    output logic s_axis_kernel_tready,
    input  logic [15:0] s_axis_bias_tdata,
    input  logic s_axis_bias_tvalid,
    input  logic s_axis_bias_tlast,
    output logic s_axis_bias_tready,
    output logic [15:0] m_axis_output_tdata,
    output logic [1:0] m_axis_output_tkeep,
    output logic m_axis_output_tvalid,
    output logic m_axis_output_tlast,
    input  logic m_axis_output_tready
);
    import model_contract_pkg::*;

    localparam bit [31:0] COMMAND_ADDR = 32'h6000_0000;
    localparam bit [31:0] DONE = 32'h1000_0000;
    localparam bit [31:0] ERROR = 32'h8000_0000;

    model_backend backend;
    bit corrupt_output;
    int wanted[3], received[3];
    int result_count, result_index;
    logic [15:0] result_data;
    logic [2:0] valid, last, ready;
    logic [15:0] stream_data[3];
    logic [31:0] state, awaddr, wdata;
    logic [3:0] wstrb;
    logic have_aw, have_w, active;

    function void set_backend(model_backend selected, bit inject_fault);
        backend = selected;
        corrupt_output = inject_fault;
    endfunction

    assign s_axi_awready = s_axi_aresetn && !have_aw && !s_axi_bvalid;
    assign s_axi_wready = s_axi_aresetn && !have_w && !s_axi_bvalid;
    assign s_axi_arready = s_axi_aresetn && !s_axi_rvalid;
    assign valid = {s_axis_bias_tvalid, s_axis_kernel_tvalid, s_axis_feature_tvalid};
    assign last = {s_axis_bias_tlast, s_axis_kernel_tlast, s_axis_feature_tlast};
    assign stream_data[FEATURE] = s_axis_feature_tdata;
    assign stream_data[KERNEL] = s_axis_kernel_tdata;
    assign stream_data[BIAS] = s_axis_bias_tdata;
    for (genvar s = FEATURE; s <= BIAS; s++) begin : gen_ready
        assign ready[s] = s_axi_aresetn && active && received[s] < wanted[s];
    end
    assign {s_axis_bias_tready, s_axis_kernel_tready, s_axis_feature_tready} = ready;
    assign m_axis_output_tvalid = s_axi_aresetn && result_index < result_count;
    assign m_axis_output_tlast = m_axis_output_tvalid && result_index == result_count - 1;
    assign m_axis_output_tdata = result_data;
    assign m_axis_output_tkeep = 2'b11;

    always @(posedge s_axi_aclk) begin : step
        bit bad_packet, complete;
        if (!s_axi_aresetn) begin
            have_aw <= 0;
            have_w <= 0;
            s_axi_bvalid <= 0;
            s_axi_rvalid <= 0;
            s_axi_bresp <= 0;
            s_axi_rresp <= 0;
            s_axi_rdata <= 0;
            active <= 0;
            state <= 0;
            result_count <= 0;
            result_index <= 0;
            result_data <= 0;
            foreach (received[s]) begin
                received[s] <= 0;
                wanted[s] <= 0;
            end
            if (backend != null) backend.reset();
        end else begin
            if (s_axi_awvalid && s_axi_awready) begin
                awaddr <= s_axi_awaddr;
                have_aw <= 1;
            end
            if (s_axi_wvalid && s_axi_wready) begin
                wdata <= s_axi_wdata;
                wstrb <= s_axi_wstrb;
                have_w <= 1;
            end
            if (s_axi_bvalid && s_axi_bready) s_axi_bvalid <= 0;
            if (s_axi_rvalid && s_axi_rready) s_axi_rvalid <= 0;
            if (s_axi_arvalid && s_axi_arready) begin
                s_axi_rvalid <= 1;
                s_axi_rdata <= s_axi_araddr == COMMAND_ADDR ? state : 0;
                s_axi_rresp <= s_axi_araddr == COMMAND_ADDR ? 2'b00 : 2'b10;
            end
            if (m_axis_output_tvalid && m_axis_output_tready) begin
                result_index <= result_index + 1;
                if (result_index + 1 < result_count)
                    result_data <= 16'(backend.result_word(result_index + 1));
            end

            if (have_aw && have_w && !s_axi_bvalid) begin
                have_aw <= 0;
                have_w <= 0;
                s_axi_bvalid <= 1;
                if (awaddr != COMMAND_ADDR || wstrb != 4'hf ||
                    active || m_axis_output_tvalid) begin
                    s_axi_bresp <= 2'b10;
                end else begin
                    s_axi_bresp <= 0;
                    state <= {4'b0, wdata[27:0]};
                    if (backend == null || !backend.describe(wdata)) begin
                        state <= {4'b0, wdata[27:0]} | ERROR;
                    end else begin
                        active <= 1;
                        foreach (received[s]) begin
                            received[s] <= 0;
                            wanted[s] <= backend.word_count(model_stream_e'(s));
                        end
                    end
                end
            end

            if (active) begin
                bad_packet = 0;
                complete = 1;
                for (int s = FEATURE; s <= BIAS; s++) begin
                    if (received[s] != wanted[s]) complete = 0;
                    if (valid[s] && ready[s]) begin
                        if (last[s] !== (received[s] == wanted[s] - 1)) bad_packet = 1;
                        backend.accept_word(model_stream_e'(s), received[s], int'(stream_data[s]));
                        received[s] <= received[s] + 1;
                    end
                end
                if (bad_packet) begin
                    state <= state | ERROR;
                    active <= 0;
                end else if (complete) begin
                    active <= 0;
                    if (backend.execute()) begin
                        state <= state | DONE;
                        result_count <= backend.word_count(RESULT);
                        result_index <= 0;
                        if (backend.word_count(RESULT) != 0)
                            result_data <= 16'(backend.result_word(0)) ^
                                           (corrupt_output ? 16'h0004 : 16'h0000);
                    end else begin
                        state <= state | ERROR;
                    end
                end
            end
        end
    end
endmodule

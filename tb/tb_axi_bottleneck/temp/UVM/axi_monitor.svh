// 모니터: DUT 신호를 관찰만 하고, R 채널 수신 결과를 스코어보드로 전달한다.
class monitor extends uvm_monitor;

    `uvm_component_utils(monitor)

    virtual axi_if vif;
    uvm_analysis_port #(observation) actual_ap;

    // 생성자
    function new(string name, uvm_component parent);
        super.new(name, parent);
        actual_ap = new("actual_ap", this);
    endfunction

    // 설정 단계: 인터페이스 또는 하위 컴포넌트 준비
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual axi_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "AXI interface is missing")
    endfunction

    // 실행 단계
    task run_phase(uvm_phase phase);
        observation obs;

        forever begin
            @(vif.mon_cb);
            if (vif.mon_cb.rst !== 1'b1) continue;
            if ({vif.mon_cb.m_axi_rvalid, vif.mon_cb.m_axi_rready} !== 2'b11) continue;

            obs = observation::type_id::create("obs");
            obs.data = vif.mon_cb.m_axi_rdata;
            actual_ap.write(obs);
        end
    endtask

endclass

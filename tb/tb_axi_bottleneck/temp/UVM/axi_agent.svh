// 에이전트: AXI 포트를 검증하는 시퀀서·드라이버·모니터를 묶는다.
class agent extends uvm_agent;

    `uvm_component_utils(agent)

    sequencer seqr;
    driver    drv;
    monitor   mon;

    // 생성자
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    // 설정 단계: 인터페이스 또는 하위 컴포넌트 준비
    function void build_phase(uvm_phase phase);
        super.build_phase(phase); 
        
        seqr = sequencer::type_id::create("sequencer", this);
        drv  = driver::type_id::create("driver", this);
        mon  = monitor::type_id::create("monitor", this);
    endfunction

    // 연결 단계: 컴포넌트 사이 포트 연결
    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        // connect_phase에서 드라이버의 요청 포트와 시퀀서의 제공 포트를 연결한다.
        drv.seq_item_port.connect(seqr.seq_item_export);
    endfunction

endclass

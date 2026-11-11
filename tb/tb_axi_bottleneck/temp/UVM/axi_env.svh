// 환경: 입력을 만들고 출력을 관찰하는 에이전트와 결과를 검사하는 스코어보드를 묶는다.
class env extends uvm_env;
    `uvm_component_utils(env)

    agent      agt;
    scoreboard sb;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agt = agent::type_id::create("agent", this);
        sb  = scoreboard::type_id::create("scoreboard", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        agt.drv.expected_ap.connect(sb.expected_imp);
        agt.mon.actual_ap.connect(sb.actual_imp);
    endfunction

endclass

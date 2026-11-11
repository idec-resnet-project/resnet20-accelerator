// 공통 테스트: 선택된 에이전트로 랜덤 데이터를 보내고 결과를 기다린다.
// RX/TX 인터페이스 대신 TB에서 전달한 UART 비트 시간을 사용한다.
class test extends uvm_test;

    `uvm_component_utils(test)

    env env_h;
    time bit_period;
    int test_N;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db#(time)::get(this, "", "bit_period", bit_period))
            `uvm_fatal("TIMING", "UART bit period is missing")
        if (bit_period == 0)
            `uvm_fatal("TIMING", "UART bit period must be positive")
        
        if (!uvm_config_db#(int)::get(this, "", "test_N", test_N))
            `uvm_fatal("TIMING", "UART test_N is missing")
        if (test_N <= 0)
            `uvm_fatal("TIMING", "UART test_N must be positive")

        env_h = env::type_id::create("env", this);
    endfunction

    task run_phase(uvm_phase phase);
        axi_sequence seq = axi_sequence::type_id::create("seq");

        // 테스트가 끝날 때까지 UVM 실행 단계를 유지한다.
        phase.raise_objection(this);
        seq.test_N = test_N;
        $display("------------------------------------------------");
        $display("[ TEST ] %4d frames", test_N);
        $display("[   NO ] EXPECTED  →  RECEIVED | STATUS");
        $display("------------------------------------------------");

        seq.start(env_h.agt.seqr);
        
        $display("[ TX DONE ] %4d frames", test_N);
        // 마지막 결과를 기다리되, 누락된 결과 때문에 무한 대기하지 않게 한다.
        fork
            begin
                wait (env_h.sb.pending.size() == 0);
            end
            begin
                #(12 * bit_period);
                `uvm_error("TIMEOUT", "Timed out waiting for the remaining UART results")
            end
        join_any
        disable fork;

        // 유휴 구간에서 중복 결과도 관찰한다.
        #(2 * bit_period);
        phase.drop_objection(this);
    endtask

endclass

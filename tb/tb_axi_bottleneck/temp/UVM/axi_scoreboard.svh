// 하나의 스코어보드에 기대값과 실제값을 따로 전달하는 분석 입력을 선언한다.
`uvm_analysis_imp_decl(_expected)
`uvm_analysis_imp_decl(_actual)

// 스코어보드: 전송한 바이트와 DUT가 수신한 바이트를 순서대로 비교한다.
class scoreboard extends uvm_scoreboard;

    `uvm_component_utils(scoreboard)

    uvm_analysis_imp_expected #(item, scoreboard) expected_imp;
    uvm_analysis_imp_actual #(observation, scoreboard) actual_imp;

    bit [31:0] pending[$];
    int unsigned sent     = 0;
    int unsigned received = 0;
    int unsigned matched  = 0;

    // 생성자
    function new(string name, uvm_component parent);
        super.new(name, parent);
        expected_imp = new("expected_imp", this);
        actual_imp   = new("actual_imp", this);
    endfunction

    // 전송할 기대값 저장
    function void write_expected(item txn);
        foreach (txn.data[i]) begin
            sent++;
            pending.push_back({24'b0, txn.data[i][7:0]});
        end
    endfunction

    // 수신 결과와 기대값 비교
    virtual function void write_actual(observation txn);
        bit [31:0] expected;
        received++;
        if (pending.size() == 0) begin
            `uvm_error(
                "UNEXPECTED",
                $sformatf("frame=%0d expected=N/A received=%08h (unexpected)", received, txn.data)
            )
            return;
        end

        expected = pending.pop_front();

        // UART로 보낸 하위 8비트와 AXI 수신값을 비교한다. X/Z도 그대로 표시된다.
        $display(
            "[ %4d ] %08h  →  %08h | %s",
            received, expected, txn.data,
            (txn.data === expected) ? "    " : "FAIL"
        );

        // !==로 비교하면 수신 데이터에 X/Z가 있어도 불일치로 검출한다.
        if (txn.data === expected)
            matched++;
        else
            `uvm_error("MISMATCH", $sformatf("expected=%08h received=%08h", expected, txn.data))
    endfunction

    // 종료 후 누락된 결과 검사
    function void check_phase(uvm_phase phase);
        super.check_phase(phase);
        if (sent == 0)
            `uvm_error("EMPTY", "No UART frames were sent")

        if (pending.size() != 0)
            `uvm_error(
                "MISSING",
                $sformatf("%0d UART frames were not received", pending.size())
            )
    endfunction

    // 검증 결과 요약
    function void report_phase(uvm_phase phase);
        // 마지막에 전송 수·수신 수·일치 수를 요약한다.
        super.report_phase(phase);
        $display("------------------------------------------------");
        $display("SENT      %4d   RECV      %4d", sent, received);
        $display("MATCH     %4d   MISMATCH  %4d", matched, received - matched);
        $display("PENDING   %4d", pending.size());
        $display("------------------------------------------------");
    endfunction

endclass

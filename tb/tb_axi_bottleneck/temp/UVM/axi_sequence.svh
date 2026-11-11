// 랜덤 시퀀스: 버스트 길이와 전송할 데이터를 매번 랜덤화한다.
// 시퀀스는 전송 내용을 정하고, 실제 핀 구동은 드라이버가 맡는다.
class axi_sequence extends uvm_sequence #(item);

    `uvm_object_utils(axi_sequence)

    int test_N;

    function new(string name = "axi_sequence");
        super.new(name);
    endfunction

    // 전송할 데이터 구성
    task body();
        item txn;

        for (int i = 0; i < test_N; i++) begin
            txn = item::type_id::create("item");

            start_item(txn);
            `uvm_info("AXI_SEQUENCE", "Randomizing the next burst", UVM_MEDIUM)
            if (!txn.randomize()) `uvm_fatal("RAND", "트랜잭션 랜덤화 실패")
            finish_item(txn);
        end
    endtask

endclass

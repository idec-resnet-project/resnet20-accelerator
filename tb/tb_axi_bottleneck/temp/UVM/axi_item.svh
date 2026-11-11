// 트랜잭션: UART로 전송할 데이터를 AXI 버스트 단위로 묶는다.
class item extends uvm_sequence_item;

    rand bit [31:0] data[$];
    rand int N;

    constraint burst_c {
        N inside {[1:16]};
        data.size() == N;
    }
    // 팩토리에 객체를 등록하고 data와 N을 복사·비교·출력 대상 필드로 등록한다.
    `uvm_object_utils_begin(item)
        `uvm_field_queue_int(data, UVM_DEFAULT)
        `uvm_field_int(N, UVM_DEFAULT)
    `uvm_object_utils_end

    // 생성자
    function new(string name = "item");
        super.new(name);
    endfunction

endclass

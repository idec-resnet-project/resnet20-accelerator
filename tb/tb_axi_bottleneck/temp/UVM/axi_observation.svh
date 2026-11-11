// 관찰 결과는 logic으로 저장해 X/Z를 유지한다. bit에 저장하면 X/Z가 0으로 변환된다.
class observation extends uvm_sequence_item;

    logic [31:0] data;
    `uvm_object_utils(observation)

    // 생성자
    function new(string name = "observation");
        super.new(name);
    endfunction

endclass

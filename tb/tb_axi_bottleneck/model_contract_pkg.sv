package model_contract_pkg;
    typedef int model_words_t[];

    typedef enum int { FEATURE, KERNEL, BIAS, RESULT } model_stream_e;

    class model_packet;
        model_words_t words;
    endclass

    class model_command;
        bit [31:0] instruction;
        model_packet payload[3];
        model_words_t expected;

        function new();
            foreach (payload[s]) payload[s] = new;
        endfunction
    endclass

    class model_run_config;
        bit [31:0] command_addr = 32'h6000_0000;
        bit [31:0] status_addr = 32'h6000_0000;
        bit [31:0] done_mask = 32'h1000_0000;
        bit [31:0] error_mask = 32'h8000_0000;
        int timeout_cycles = 1_000_000;
        int output_tolerance = 1;
        model_command commands[$];
    endclass

    virtual class model_backend;
        pure virtual function void reset();
        pure virtual function void close();
        pure virtual function bit describe(bit [31:0] instruction);
        pure virtual function int word_count(model_stream_e stream);
        pure virtual function void accept_word(model_stream_e stream, int index, int word_value);
        pure virtual function bit execute();
        pure virtual function int result_word(int index);
    endclass
endpackage

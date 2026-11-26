package model_contract_pkg;
    localparam int AXI_FRAC_BITS = 10;
    // --------------------------------
    // Stream payloads and command plan
    // --------------------------------
    typedef int model_words_t[];

    // Convert a channel-major stream position to its pixel-major position.
    function automatic int feature_hwc_index(int chw_index, int pixels, int channels);
        return (chw_index % pixels) * channels + chw_index / pixels;
    endfunction

    function automatic model_words_t feature_to_chw(model_words_t hwc, int pixels, int channels);
        model_words_t chw = new[hwc.size()];
        foreach (chw[i])
            chw[i] = hwc[feature_hwc_index(i, pixels, channels)];
        return chw;
    endfunction

    // Keep the stream order in sync with the DPI adapter.
    typedef enum int {
        FEATURE,
        KERNEL,
        BIAS,
        RESULT
    } model_stream_e;

    class model_packet;
        model_words_t words;
    endclass

    class model_command;
        bit [31:0] instruction;
        model_packet payload[3];
        int result_count;
        string reference_logits_path;

        function new();
            foreach (payload[s]) payload[s] = new;
        endfunction
    endclass

    // --------------------------------
    // Register map and run configuration
    // --------------------------------
    class model_run_config;
        bit [31:0] command_addr = 32'h6000_0000;
        bit [31:0] status_addr = 32'h6000_0000;
        bit [31:0] done_mask = 32'h1000_0000;
        bit [31:0] error_mask = 32'h8000_0000;
        int timeout_cycles = 10_000_000;
        int status_poll_gap_cycles = 0;
        real min_logit_snr_db = 50.0;
        model_command commands[$];
    endclass

    // --------------------------------
    // Behavioral model interface
    // --------------------------------
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

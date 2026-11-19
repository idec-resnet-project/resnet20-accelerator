package model_backend_pkg;
    import model_contract_pkg::*;
    import model_pkg::*;
    // --------------------------------
    // Float model entry points
    // --------------------------------
    import "DPI-C" function chandle model_create();
    import "DPI-C" function void model_destroy(chandle handle);
    import "DPI-C" function void model_reset(chandle handle);
    import "DPI-C" function void model_store(chandle handle, int stream, int index, int word_value);
    import "DPI-C" function int model_step(chandle handle, int op, int w, int h,
        int cin, int cout, int k, int stride, int pad);
    import "DPI-C" function int model_logit(chandle handle, int channel, int frac_bits);

    // --------------------------------
    // Model command and DPI adapter
    // --------------------------------
    class compute_backend extends model_backend;
        chandle handle;
        instruction_t inst;
        int next_command;
        int output_frac_bits;

        function new(int output_frac_bits);
            this.output_frac_bits = output_frac_bits;
            handle = model_create();
            if (handle == null) $fatal(1, "Could not allocate ResNet-20 state");
        endfunction

        virtual function void reset();
            next_command = 0;
            model_reset(handle);
        endfunction

        virtual function void close();
            model_destroy(handle);
            handle = null;
        endfunction

        virtual function bit describe(bit [31:0] instruction);
            if (instruction[7:0] == OP_INPUT) next_command = 0;
            if (next_command >= $size(PROGRAM)) return 0;
            inst = PROGRAM[next_command];
            if (pack_instruction(inst) != instruction) return 0;
            return 1;
        endfunction

        virtual function int word_count(model_stream_e stream);
            return stream_words(inst, stream);
        endfunction

        virtual function void accept_word(model_stream_e stream, int index, int word_value);
            // The DPI model stores features in HWC order.
            if (stream == FEATURE)
                index = feature_hwc_index(index, inst.width * inst.height, inst.cin);
            model_store(handle, int'(stream), index, word_value);
        endfunction

        virtual function bit execute();
            if (model_step(handle, inst.op, inst.width, inst.height, inst.cin, inst.cout,
                              inst.kernel_size, inst.stride, inst.padding) != 0) return 0;
            next_command++;
            return 1;
        endfunction

        virtual function int result_word(int index);
            return model_logit(handle, index, output_frac_bits);
        endfunction
    endclass

    function automatic model_backend build_model_backend(int output_frac_bits);
        compute_backend selected = new(output_frac_bits);
        return selected;
    endfunction

endpackage

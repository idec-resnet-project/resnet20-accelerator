    // --------------------------------
    // Float model entry points
    // --------------------------------
    import "DPI-C" function chandle resnet20_create();
    import "DPI-C" function void resnet20_destroy(chandle handle);
    import "DPI-C" function void resnet20_reset(chandle handle);
    import "DPI-C" function void resnet20_store(chandle handle, int stream, int index, int word_value);
    import "DPI-C" function int resnet20_step(chandle handle, int op, int w, int h,
        int cin, int cout, int k, int stride, int pad);
    import "DPI-C" function int resnet20_logit(chandle handle, int channel, int frac_bits);

    // --------------------------------
    // Model command and DPI adapter
    // --------------------------------
    class resnet20_backend extends model_backend;
        chandle handle;
        instruction_t inst;
        int next_command;
        int output_frac_bits;

        function new(int output_frac_bits);
            this.output_frac_bits = output_frac_bits;
            handle = resnet20_create();
            if (handle == null) $fatal(1, "Could not allocate ResNet-20 state");
        endfunction

        virtual function void reset();
            next_command = 0;
            resnet20_reset(handle);
        endfunction

        virtual function void close();
            resnet20_destroy(handle);
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
            resnet20_store(handle, int'(stream), index, word_value);
        endfunction

        virtual function bit execute();
            if (resnet20_step(handle, inst.op, inst.width, inst.height, inst.cin, inst.cout,
                              inst.kernel_size, inst.stride, inst.padding) != 0) return 0;
            next_command++;
            return 1;
        endfunction

        virtual function int result_word(int index);
            return resnet20_logit(handle, index, output_frac_bits);
        endfunction
    endclass

    function automatic model_backend build_model_backend(int output_frac_bits);
        resnet20_backend selected = new(output_frac_bits);
        return selected;
    endfunction

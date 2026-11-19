    // --------------------------------
    // Model data files
    // --------------------------------

    function automatic int read_word(int fd, string path);
        int lo, hi;
        lo = $fgetc(fd);
        hi = $fgetc(fd);
        if (lo < 0 || hi < 0) $fatal(1, "Unexpected end of %s", path);
        return (hi << 8) | lo;
    endfunction

    function automatic model_words_t read_hex(string path, int count);
        model_words_t words;
        int fd, word_value;
        string extra;
        fd = $fopen(path, "r");
        if (!fd) $fatal(1, "Cannot open %s", path);
        words = new[count];
        foreach (words[i]) begin
            if ($fscanf(fd, "%h", word_value) != 1 || word_value < 0 || word_value > 'hffff)
                $fatal(1, "Invalid word %0d in %s", i, path);
            words[i] = word_value;
        end
        if ($fscanf(fd, "%s", extra) == 1) $fatal(1, "Extra data in %s", path);
        $fclose(fd);
        return words;
    endfunction

    localparam int FIRST_BLOCK_COMMAND = 26;

    function automatic instruction_t partial_input_instruction();
        instruction_t inst;
        inst = PROGRAM[FIRST_BLOCK_COMMAND];
        inst.op = OP_INPUT;
        return inst;
    endfunction

    function automatic model_run_config build_model_config(string data_dir, int output_frac_bits);
        model_run_config cfg = new;
        model_command command;
        instruction_t inst;
        string path;
        int fd;
        localparam int WEIGHT_OFFSET_BYTES = 394368;

        cfg.output_frac_bits = output_frac_bits;
        path = {data_dir, "/weight.bin"};
        fd = $fopen(path, "rb");
        if (!fd) $fatal(1, "Cannot open %s", path);
        if ($fseek(fd, WEIGHT_OFFSET_BYTES, 0) != 0)
            $fatal(1, "Cannot seek to final block in %s", path);

        inst = partial_input_instruction();
        command = new;
        command.instruction = pack_instruction(inst);
        command.payload[FEATURE].words = feature_to_chw(
            read_hex({data_dir, "/input_q5_10.hex"}, stream_words(inst, FEATURE)),
            inst.width * inst.height, inst.cin);
        cfg.commands.push_back(command);

        for (int i = FIRST_BLOCK_COMMAND; i < $size(PROGRAM); i++) begin
            inst = PROGRAM[i];
            command = new;
            command.instruction = pack_instruction(inst);
            for (int s = KERNEL; s <= BIAS; s++) begin
                command.payload[s].words = new[stream_words(inst, model_stream_e'(s))];
                for (int j = 0; j < command.payload[s].words.size(); j++)
                    command.payload[s].words[j] = read_word(fd, path);
            end
            command.result_count = stream_words(inst, RESULT);
            if (command.result_count != 0)
                command.reference_logits_path = {data_dir, "/reference_logits_float.txt"};
            cfg.commands.push_back(command);
        end
        if ($fgetc(fd) >= 0) $fatal(1, "Unexpected trailing weights in %s", path);
        $fclose(fd);
        return cfg;
    endfunction

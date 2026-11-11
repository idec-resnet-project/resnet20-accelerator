    // --------------------------------
    // Model data files
    // --------------------------------
    localparam string MODEL_DATA_SUBDIR = "resnet20/data";

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

    // --------------------------------
    // Model command payloads and expected results
    // --------------------------------
    function automatic model_run_config build_model_config(string data_dir, int output_frac_bits);
        model_run_config cfg = new;
        model_command command;
        instruction_t inst;
        string path;
        int fd, words_read;

        cfg.output_frac_bits = output_frac_bits;
        path = {data_dir, "/weight.bin"};
        fd = $fopen(path, "rb");
        if (!fd) $fatal(1, "Cannot open %s", path);
        words_read = 0;
        for (int i = 0; i < $size(PROGRAM); i++) begin
            command = new;
            inst = PROGRAM[i];
            command.instruction = pack_instruction(inst);
            command.result_count = stream_words(inst, RESULT);
            for (int s = FEATURE; s <= BIAS; s++)
                command.payload[s].words = new[stream_words(inst, model_stream_e'(s))];

            if (inst.op == OP_INPUT)
                command.payload[FEATURE].words = read_hex({data_dir, "/input_q5_10.hex"},
                                                        stream_words(inst, FEATURE));
            for (int s = KERNEL; s <= BIAS; s++) begin
                for (int j = 0; j < command.payload[s].words.size(); j++) begin
                    command.payload[s].words[j] = read_word(fd, path);
                    words_read++;
                end
            end
            if (command.result_count != 0)
                command.reference_logits_path = {data_dir, "/reference_logits_float.txt"};
            cfg.commands.push_back(command);
        end
        if (words_read != 271690 || $fgetc(fd) >= 0)
            $fatal(1, "Expected exactly 543380 bytes in %s", path);
        $fclose(fd);
        return cfg;
    endfunction

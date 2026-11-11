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

    function automatic model_run_config build_model_config(string data_dir, bit unit_test);
        model_run_config cfg = new;
        model_command command;
        instruction_t inst;
        string path;
        int fd, words_read;
        path = {data_dir, "/weight.bin"};
        if (!unit_test) begin
            fd = $fopen(path, "rb");
            if (!fd) $fatal(1, "Cannot open %s", path);
        end else begin
            cfg.output_tolerance = 0;
        end
        words_read = 0;
        for (int i = 0; i < (unit_test ? 2 : $size(PROGRAM)); i++) begin
            command = new;
            inst = get_instruction(i, unit_test);
            command.instruction = pack_instruction(inst);
            for (int s = FEATURE; s <= BIAS; s++)
                command.payload[s].words = new[stream_words(inst, model_stream_e'(s))];
            if (unit_test) begin
                if (i == 0) command.payload[FEATURE].words = '{1536, 65024};
                else begin
                    command.payload[KERNEL].words = '{512, 65280};
                    command.payload[BIAS].words = '{128};
                    command.expected = '{1024};
                end
            end else begin
                if (inst.op == OP_INPUT)
                    command.payload[FEATURE].words = read_hex({data_dir, "/input_q5_10.hex"},
                                                        stream_words(inst, FEATURE));
                for (int s = KERNEL; s <= BIAS; s++) begin
                    for (int j = 0; j < command.payload[s].words.size(); j++) begin
                        command.payload[s].words[j] = read_word(fd, path);
                        words_read++;
                    end
                end
                if (inst.op == OP_FC_OUT)
                    command.expected = read_hex({data_dir, "/expected_logits_q5_10.hex"},
                                                stream_words(inst, RESULT));
            end
            cfg.commands.push_back(command);
        end
        if (!unit_test) begin
            if (words_read != 271690 || $fgetc(fd) >= 0)
                $fatal(1, "Expected exactly 543380 bytes in %s", path);
            $fclose(fd);
        end
        return cfg;
    endfunction

    localparam int FIRST_BLOCK_COMMAND = 26;

    function automatic instruction_t partial_input_instruction();
        instruction_t inst;
        inst = PROGRAM[FIRST_BLOCK_COMMAND];
        inst.op = OP_INPUT;
        return inst;
    endfunction

    function automatic model_run_config build_partial_config(string tb_dir, string fixture_dir);
        model_run_config cfg = new;
        model_command command;
        instruction_t inst;
        string path;
        int fd;
        localparam int WEIGHT_OFFSET_BYTES = 394368;

        path = {tb_dir, "/../tb_axi_bottleneck/", MODEL_DATA_SUBDIR, "/weight.bin"};
        fd = $fopen(path, "rb");
        if (!fd) $fatal(1, "Cannot open %s", path);
        if ($fseek(fd, WEIGHT_OFFSET_BYTES, 0) != 0)
            $fatal(1, "Cannot seek to final block in %s", path);

        inst = partial_input_instruction();
        command = new;
        command.instruction = pack_instruction(inst);
        command.payload[FEATURE].words =
            read_hex({fixture_dir, "/input_q5_10.hex"}, stream_words(inst, FEATURE));
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
                command.reference_logits_path = {fixture_dir, "/reference_logits_float.txt"};
            cfg.commands.push_back(command);
        end
        if ($fgetc(fd) >= 0) $fatal(1, "Unexpected trailing weights in %s", path);
        $fclose(fd);
        return cfg;
    endfunction

    localparam int OP_INPUT = 1;
    localparam int OP_FC_OUT = 66;
    localparam int CORE_MAC = 64;

    typedef struct packed {
        int op, width, height, cin, cout, kernel_size, stride, padding;
    } instruction_t;

    // Matches resnet20_instruction_set in verification/resnet20/resnet20.c.
    localparam instruction_t PROGRAM[30] = '{
        '{1, 32, 32, 3, 0, 0, 1, 0},
        '{80, 32, 32, 3, 16, 3, 1, 1},
        '{128, 32, 32, 16, 0, 0, 1, 0},
        '{80, 32, 32, 16, 16, 3, 1, 1},
        '{112, 32, 32, 16, 16, 3, 1, 1},
        '{128, 32, 32, 16, 0, 0, 1, 0},
        '{80, 32, 32, 16, 16, 3, 1, 1},
        '{112, 32, 32, 16, 16, 3, 1, 1},
        '{128, 32, 32, 16, 0, 0, 1, 0},
        '{80, 32, 32, 16, 16, 3, 1, 1},
        '{112, 32, 32, 16, 16, 3, 1, 1},
        '{192, 32, 32, 16, 32, 1, 2, 0},
        '{80, 32, 32, 16, 32, 3, 2, 1},
        '{112, 16, 16, 32, 32, 3, 1, 1},
        '{128, 16, 16, 32, 0, 0, 1, 0},
        '{80, 16, 16, 32, 32, 3, 1, 1},
        '{112, 16, 16, 32, 32, 3, 1, 1},
        '{128, 16, 16, 32, 0, 0, 1, 0},
        '{80, 16, 16, 32, 32, 3, 1, 1},
        '{112, 16, 16, 32, 32, 3, 1, 1},
        '{192, 16, 16, 32, 64, 1, 2, 0},
        '{80, 16, 16, 32, 64, 3, 2, 1},
        '{112, 8, 8, 64, 64, 3, 1, 1},
        '{128, 8, 8, 64, 0, 0, 1, 0},
        '{80, 8, 8, 64, 64, 3, 1, 1},
        '{112, 8, 8, 64, 64, 3, 1, 1},
        '{128, 8, 8, 64, 0, 0, 1, 0},
        '{80, 8, 8, 64, 64, 3, 1, 1},
        '{116, 8, 8, 64, 64, 3, 1, 1},
        '{66, 1, 1, 64, 10, 1, 1, 0}
    };

    function automatic instruction_t get_instruction(int index, bit unit_test);
        if (!unit_test) return PROGRAM[index];
        if (index == 0) return '{OP_INPUT, 1, 1, 2, 0, 0, 1, 0};
        return '{OP_FC_OUT, 1, 1, 2, 1, 1, 1, 0};
    endfunction

    function automatic bit [31:0] pack_instruction(instruction_t inst);
        return inst.op | ((inst.stride - 1) << 8) | (inst.padding << 9) |
               ((inst.width - 1) << 10) | ((inst.height - 1) << 16) |
               ((inst.cin - 1) << 22);
    endfunction

    function automatic int stream_words(instruction_t inst, model_stream_e stream);
        case (stream)
            FEATURE: return inst.op == OP_INPUT ? inst.width * inst.height * inst.cin : 0;
            KERNEL: return (inst.op & CORE_MAC) ? inst.cin * inst.cout *
                                                inst.kernel_size * inst.kernel_size : 0;
            BIAS: return (inst.op & CORE_MAC) ? inst.cout : 0;
            RESULT: return inst.op == OP_FC_OUT ? inst.cout : 0;
        endcase
        return 0;
    endfunction

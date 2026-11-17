    // --------------------------------
    // Instruction fields
    // --------------------------------
    localparam int OP_INPUT = 1;
    localparam int OP_FC_OUT = 66;
    localparam int CORE_MAC = 64;

    typedef struct packed {
        int op, width, height, cin, cout, kernel_size, stride, padding;
    } instruction_t;

    // --------------------------------
    // Model command table
    // --------------------------------
    // Projection and the first main-path convolution consume the same input.
    localparam instruction_t PROGRAM[5] = '{
        '{1,    8, 8, 3, 0, 0, 1, 0}, // INPUT
        '{192,  8, 8, 3, 4, 1, 2, 0}, // SKIP_CONV
        '{80,   8, 8, 3, 4, 3, 2, 1}, // CONV_RELU
        '{116,  4, 4, 4, 4, 3, 1, 1}, // RESIDUAL_GAP
        '{66,   1, 1, 4, 3, 1, 1, 0}  // FC_OUT
    };

    // --------------------------------
    // Register encoding and stream lengths
    // --------------------------------
    function automatic bit [31:0] pack_instruction(instruction_t inst);
        bit uses_mac;
        int cfg_width, cfg_height, cfg_channels;

        // MAC commands encode the kernel dimensions and output channels.
        uses_mac = (inst.op & CORE_MAC) != 0;
        cfg_width = uses_mac ? inst.kernel_size : inst.width;
        cfg_height = uses_mac ? inst.kernel_size : inst.height;
        cfg_channels = uses_mac ? inst.cout : inst.cin;

        return inst.op | ((inst.stride - 1) << 8) | (inst.padding << 9) |
               ((cfg_width - 1) << 10) | ((cfg_height - 1) << 16) |
               ((cfg_channels - 1) << 22);
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

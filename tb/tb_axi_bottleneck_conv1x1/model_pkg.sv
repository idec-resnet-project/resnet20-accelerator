package model_pkg;
    import model_contract_pkg::*;

    localparam int INPUT_SIZE = 8;
    localparam int IN_CHANNELS = 3;
    localparam int OUT_CHANNELS = 4;
    localparam int KERNEL_SIZE = 1;
    localparam int PADDING = 0;
    localparam bit RELU_ENABLE = 0;

    `include "models/conv_model.svh"
endpackage

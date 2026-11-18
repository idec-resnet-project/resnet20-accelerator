package model_pkg;
    import model_contract_pkg::*;

    localparam int INPUT_SIZE = 4;
    localparam int IN_CHANNELS = 2;
    localparam int OUT_CHANNELS = 2;
    localparam int KERNEL_SIZE = 3;
    localparam int PADDING = 1;
    localparam bit RELU_ENABLE = 1;
    localparam bit SEQUENTIAL_PAYLOADS = 0;

    `include "models/conv_model.svh"
endpackage

package model_pkg;
    import model_contract_pkg::*;
    localparam int LAYER_COUNT = 30;
    localparam int LOGIT_COUNT = 10;
    localparam int WEIGHT_WORDS = 271690;
    localparam int MAX_TENSOR_WORDS = 32 * 32 * 16;
    function automatic string model_data_dir(string tb_dir);
        return {tb_dir, "/../libs/models/resnet20/data"};
    endfunction

    `include "model_program.svh"
    `include "model_data.svh"
endpackage

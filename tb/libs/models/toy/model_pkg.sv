package model_pkg;
    import model_contract_pkg::*;
    localparam int WEIGHT_WORDS = 291;

    function automatic string model_data_dir(string tb_dir);
        return {tb_dir, "/../libs/models/toy/data"};
    endfunction

    `include "models/toy/model_program.svh"
    `include "models/toy/model_data.svh"
endpackage

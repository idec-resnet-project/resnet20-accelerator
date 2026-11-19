package model_pkg;
    import model_contract_pkg::*;
    function automatic string model_data_dir(string tb_dir);
        return {tb_dir, "/../libs/models/resnet20_partial/data"};
    endfunction

    `include "model_program.svh"
    `include "model_data.svh"
endpackage

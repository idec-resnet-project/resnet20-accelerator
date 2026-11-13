package resnet20_pkg;
    import model_contract_pkg::*;

    `include "resnet20/resnet20_program.svh"
    `include "resnet20/resnet20_data.svh"
`ifndef TB_AXI_BOTTLENECK_USE_RTL
    `include "resnet20/resnet20_compute.svh"
`endif
endpackage

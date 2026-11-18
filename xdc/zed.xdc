## 100MHz On-board Clock (Pin Y9, Bank 13)
set_property PACKAGE_PIN Y9 [get_ports {clk}]
set_property IOSTANDARD LVCMOS33 [get_ports {clk}]
create_clock -period 10.000 -name sys_clk_pin -waveform {0.000 5.000} [get_ports {clk}]

set_property DONT_TOUCH true [get_cells {uut_mac uut_post_mac uut_mux}]
set_property DONT_TOUCH true [get_nets  {valid_out_mac valid_out_post_mac}]
set_property DONT_TOUCH true [get_cells {uut_pooling uut_pooling_unit uut_avgpool uut_maxpool}
set_property DONT_TOUCH true [get_cells {uut_ReLU}
set_property DONT_TOUCH true [get_cells {uut_residual}
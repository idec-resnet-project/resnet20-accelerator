# ZedBoard 100 MHz oscillator, using the AXI DUT clock port name.
set_property PACKAGE_PIN Y9 [get_ports s_axi_aclk]
set_property IOSTANDARD LVCMOS33 [get_ports s_axi_aclk]
create_clock -name clk -period 20.000 [get_ports s_axi_aclk]

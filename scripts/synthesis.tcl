# Synthesize the DUT from tb_core's behavioral simulation.
if {![info exists ::env(TB_CORE_SYNTH_FRAC_BITS)] ||
    ![regexp {^([0-9]|1[0-5])$} $::env(TB_CORE_SYNTH_FRAC_BITS)]} {
    error "Expected an output fraction width from 0 to 15"
}
set output_frac_bits $::env(TB_CORE_SYNTH_FRAC_BITS)
set root [file normalize [file join [file dirname [info script]] ..]]
set part xc7z007sclg400-1

read_verilog -sv [file join $root tb tb_core dummy core.v]
synth_design -top core -part $part -generic OUTPUT_FRAC_BITS=$output_frac_bits
create_clock -name clk -period 10 [get_ports clk]
report_utilization -file utilization.rpt
report_timing_summary -file timing_summary.rpt
write_checkpoint -force core.dcp
write_verilog -mode funcsim -force core_funcsim.v

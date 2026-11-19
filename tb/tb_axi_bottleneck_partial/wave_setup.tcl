set tb /tb_axi_bottleneck_partial
set dut $tb/dut
set controller $dut/u_top_bottleneck/u_controller
set signals [list $tb/clk $tb/nrst $dut/s_axi_rdata $dut/m_axis_output_tkeep]
foreach prefix {s_axis_feature s_axis_kernel s_axis_bias m_axis_output} {
    foreach suffix {tvalid tready tlast tdata} {
        lappend signals ${dut}/${prefix}_${suffix}
    }
}
# Internal controller signals exist only for the RTL DUT.
if {![catch {get_objects $controller/cstate} state] && [llength $state]} {
    foreach name {cfg cfg_enable cfg_response} {
        lappend signals $dut/$name
    }
    foreach name {cstate rstate fc fw oc ow kw kc cnt_feature len_feature cnt_kernel len_kernel cnt_bias len_bias cnt_run cnt_output len_output cnt_dma_output gap_enable gap_iteration in_enable out_enable} {
        lappend signals $controller/$name
    }
}
if {[catch {log_wave [get_objects $signals]} message]} {
    puts stderr "ERROR: Wave capture setup failed: $message"
    quit
}
run all
quit

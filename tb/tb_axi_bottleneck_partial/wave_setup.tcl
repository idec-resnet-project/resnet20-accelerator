set tb /tb_axi_bottleneck_partial
set dut $tb/dut
set controller $dut/u_top_bottleneck/u_controller
set signals [list $tb/clk $tb/nrst $dut/cfg $dut/cfg_enable $dut/cfg_response $dut/s_axi_rdata $dut/m_axis_output_tkeep]
foreach prefix {s_axis_feature s_axis_kernel s_axis_bias m_axis_output} {
    foreach suffix {tvalid tready tlast tdata} {
        lappend signals ${dut}/${prefix}_${suffix}
    }
}
foreach name {cstate rstate fc fw oc ow kw kc cnt_feature len_feature cnt_kernel len_kernel cnt_bias len_bias cnt_run cnt_output len_output cnt_dma_output gap_enable gap_iteration in_enable out_enable} {
    lappend signals $controller/$name
}
if {[catch {log_wave [get_objects $signals]} message]} {
    puts stderr "ERROR: Wave capture setup failed: $message"
    quit
}
run all
quit

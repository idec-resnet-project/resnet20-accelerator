set tb /tb_axi_bottleneck_toy
set dut $tb/dut
set top $dut/u_top_bottleneck
set controller $top/u_controller

if {[catch {
    # Record DUT ports, configuration, and parameters used in the saved view.
    log_wave [get_objects [list $tb/clk $tb/nrst $dut/*]]
    # The RTL exposes internal DMA ports and controller signals.
    if {[llength [get_scopes -quiet $controller]]} {
        log_wave [get_objects $top/dma_*]
        log_wave [get_objects $controller/*]
    }
} message]} {
    puts stderr "ERROR: Wave capture setup failed: $message"
    quit
}
run all
quit

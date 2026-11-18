if {[catch {
    set root [file normalize $::env(TB_CORE_SYNTH_ROOT)]
    set board_dir [file join $root fpga zedboard]
    set board_repo [file join $board_dir board_file]
    set_param board.repoPaths [list $board_repo]
    set board [get_board_parts -quiet digilentinc.com:zedboard_resnet20:part0:1.1]
    if {[llength $board] != 1} {
        error "ZedBoard definition not found in $board_repo"
    }
    set board_xml [file normalize [get_property FILE_NAME $board]]
    if {$board_xml ne [file join $board_repo board.xml]} {
        error "Unexpected ZedBoard definition: $board_xml"
    }
    set part [get_property PART_NAME $board]
    set_part $part
    set_property BOARD_PART $board [current_project]

    set top $::env(TB_SYNTH_TOP)
    set include_dirs {}
    foreach source [split $::env(TB_SYNTH_SOURCES) "\n"] {
        lappend include_dirs [file dirname $source]
    }
    set_property include_dirs [lsort -unique $include_dirs] [current_fileset]
    foreach source [split $::env(TB_SYNTH_SOURCES) "\n"] {
        read_verilog -sv $source
    }
    if {$top eq "axi_bottleneck"} {
        read_xdc [file join $board_dir axi_bottleneck.xdc]
    } else {
        read_xdc [file join $board_dir master.xdc]
    }
    set synth_args [list -top $top -part $part]
    foreach generic $::env(TB_SYNTH_GENERICS) {
        lappend synth_args -generic $generic
    }
    synth_design {*}$synth_args
    report_utilization -file utilization.rpt
    report_timing_summary -file timing_summary.rpt
    write_checkpoint -force ${top}.dcp
    write_verilog -mode funcsim -force ${top}_funcsim.v
} message]} {
    puts stderr $::errorInfo
    exit 1
}
exit 0

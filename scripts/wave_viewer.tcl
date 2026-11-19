namespace eval wave_viewer {
    variable directory [file normalize [file join [file dirname [info script]] .. .log wave_viewer]]
    variable active_request
    variable timer

    proc open_request {request} {
        variable active_request
        if {[info exists active_request]} {
            # Preserve unsaved changes by using Vivado's normal close behavior.
            if {[current_sim -quiet] ne ""} {
                close_sim
            }
            file delete -- [file join $active_request behav_tb.wdb]
            unset active_request
        }
        set config_file [open [file join $request config.txt] r]
        fconfigure $config_file -encoding utf-8
        set config [string trim [read $config_file]]
        close $config_file
        open_wave_database -noautoloadwcfg [file join $request behav_tb.wdb]
        set active_request $request
        if {$config ne ""} {
            open_wave_config [file normalize $config]
        } else {
            create_wave_config
        }
    }

    proc poll {} {
        variable directory
        variable timer
        set heartbeat [open [file join $directory heartbeat] w]
        close $heartbeat
        foreach marker [glob -nocomplain -directory $directory */ready] {
            set request [file dirname $marker]
            file delete -- $marker
            set message OK
            if {[catch {open_request $request} problem]} {
                set message $problem
                puts stderr "Waveform viewer: $problem"
            }
            set result [open [file join $request result.tmp] w]
            puts $result $message
            close $result
            file rename -- [file join $request result.tmp] [file join $request result.txt]
        }
        set timer [after 500 [namespace code poll]]
    }

    file mkdir $directory
    if {[info exists timer]} {
        after cancel $timer
    }
    poll
}

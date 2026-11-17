if {[catch {log_wave -r /} message]} {
    puts stderr "ERROR: Wave capture setup failed: $message"
    quit
}
run all
quit

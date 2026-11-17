# ============================================================
# MAC Accelerator - Timing Constraints
# Target Frequency: 100 MHz
# Clock Period: 10 ns
# ============================================================

# 1. Primary Clock
create_clock -name sys_clk -period 10.000 \
    -waveform {0.000 5.000} [get_ports clk]

# 2. Clock Uncertainty (optional design margin)
set_clock_uncertainty -setup 0.200 [get_clocks sys_clk]

# 3. Timing Reports
# Run separately in Vivado Tcl Console:
# report_clocks
# check_timing -verbose
# report_timing_summary
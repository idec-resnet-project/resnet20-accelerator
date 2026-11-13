import os
from pathlib import Path
import shutil
import subprocess
import sys


# Send the Vivado commands through stdin so both launchers use the same flow.
VIVADO_COMMANDS = """\
if {[catch {
    set root [file normalize $::env(TB_CORE_SYNTH_ROOT)]
    set board_dir [file join $root fpga zedboard]
    set board_repo [file join $board_dir board_file]
    set_param board.repoPaths [list $board_repo]

    # Select the repository board even when Vivado ships a ZedBoard definition.
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
    puts "ZedBoard: $board_xml ($part)"

    set reference_rtl [file join $root verification core reference_rtl]
    read_verilog -sv [glob -directory $reference_rtl *.v]
    read_xdc [file join $board_dir master.xdc]
    synth_design -top core -part $part

    report_utilization -file utilization.rpt
    report_timing_summary -file timing_summary.rpt
    write_checkpoint -force core.dcp
    write_verilog -mode funcsim -force core_funcsim.v
} message]} {
    puts stderr $::errorInfo
    exit 1
}
exit 0
"""


def main():
    vivado_name = "vivado.bat" if os.name == "nt" else "vivado"
    vivado = shutil.which(vivado_name)
    if not vivado:
        print(f"[ ERROR ] {vivado_name} not found. Add Vivado bin to PATH.", file=sys.stderr)
        return 1

    root = Path(__file__).resolve().parents[1]
    build = root / ".log" / "synth" / "tb_core" / "zedboard" / "reference_rtl"
    build.mkdir(parents=True, exist_ok=True)
    log = build / "synthesis.log"
    env = os.environ.copy()
    env["TB_CORE_SYNTH_ROOT"] = root.as_posix()

    print("[ INFO ] Synthesizing reference core for ZedBoard", flush=True)
    try:
        result = subprocess.run(
            [vivado, "-mode", "tcl", "-log", "synthesis.log", "-journal", "synthesis.jou"],
            cwd=build,
            env=env,
            input=VIVADO_COMMANDS,
            text=True,
        )
    except OSError as error:
        print(f"[ ERROR ] Could not start Vivado: {error}", file=sys.stderr)
        return 1

    artifacts = (build / "core.dcp", build / "core_funcsim.v")
    if result.returncode or any(not file.is_file() or not file.stat().st_size for file in artifacts):
        print(f"[ ERROR ] Synthesis failed. See {log}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TB_PATH="$ROOT/tb/tb_core"
PATH_LOG="$ROOT/.log/sim/tb_core"
POST_SYNTHESIS="${TB_CORE_POST_SYNTHESIS:-0}"
if [[ "$POST_SYNTHESIS" == 1 ]]; then
    PATH_LOG="$ROOT/.log/sim/tb_core_synthesis"
fi
GUI=0
WINDOWS=0
usage() {
    local script=behav_sim.sh
    if [[ "$POST_SYNTHESIS" == 1 ]]; then script=synthesis_sim.sh; fi
    echo "Usage: bash scripts/$script [tb_core] [--gui]" >&2
}
while (( $# )); do
    case "$1" in
        tb_core) ;;
        --gui) GUI=1 ;;
        *) usage; exit 2 ;;
    esac
    shift
done
[[ "${INPUT_GAP:-0}" =~ ^[0-9]+$ ]] || { echo 'INPUT_GAP must be nonnegative.' >&2; exit 2; }
case "$(uname -s)" in MINGW*|MSYS*) WINDOWS=1 ;; esac
for tool in xvlog xelab xsim; do
    name="$tool"
    if (( WINDOWS )); then name="$tool.bat"; fi
    command -v "$name" >/dev/null || { echo "[ ERROR ] $name not found. Add Vivado bin to PATH." >&2; exit 1; }
done
[[ -f "$TB_PATH/tb_core.f" ]] || { echo '[ ERROR ] tb_core.f not found.' >&2; exit 1; }
python_cmd="${PYTHON:-}"
if [[ -z "$python_cmd" ]]; then
    for candidate in python3 python python3.14; do
        if "$candidate" -c 'import sys; sys.exit(sys.version_info < (3, 10))' >/dev/null 2>&1; then
            python_cmd="$candidate"
            break
        fi
    done
fi
[[ -n "$python_cmd" ]] || { echo '[ ERROR ] Set PYTHON to a Python 3.10+ executable.' >&2; exit 1; }
tool_path() {
    if (( WINDOWS )); then cygpath -am "$1"; else printf '%s\n' "$1"; fi
}
run_tool() {
    local name="$1"
    shift
    if (( WINDOWS )); then
        MSYS2_ARG_CONV_EXCL='*' MSYS_NO_PATHCONV=1 "$name.bat" "$@"
    else
        "$name" "$@"
    fi
}
netlist=
compile_flags=()
elab_targets=(tb_core)
if [[ "$POST_SYNTHESIS" == 1 ]]; then
    bash "$ROOT/scripts/synthesis.sh" tb_core
    netlist="$ROOT/.log/synth/tb_core/zedboard/reference_rtl/core_funcsim.v"
    compile_flags=(-d TB_CORE_POST_SYNTHESIS)
    # Vivado's functional Verilog netlist includes glbl.
    elab_targets+=(glbl -L unisims_ver)
fi
mkdir -p -- "$PATH_LOG"
(
    cd -- "$TB_PATH"
    if [[ "$POST_SYNTHESIS" == 1 ]]; then
        printf 'verilog work "%s"\n' "$(tool_path "$netlist")"
    fi
    while IFS= read -r source || [[ -n "$source" ]]; do
        source=${source%$'\r'}
        source=${source#"${source%%[![:space:]]*}"}
        source=${source%"${source##*[![:space:]]}"}
        [[ -z "$source" || "$source" == \#* ]] && continue
        if [[ "$POST_SYNTHESIS" == 1 && "$source" == ../../verification/core/reference_rtl/* ]]; then continue; fi
        [[ -f "$source" ]] || { echo "[ ERROR ] Source not found: $source" >&2; exit 1; }
        absolute="$(cd -- "$(dirname -- "$source")" && pwd)/$(basename -- "$source")"
        printf 'sv work "%s"\n' "$(tool_path "$absolute")"
    done < tb_core.f
) > "$PATH_LOG/sources.prj"
cd -- "$PATH_LOG"
: > simulate.log

"$python_cmd" "$(tool_path "$ROOT/verification/core/golden_ref/generate_resnet20_core.py")" --out vectors

echo '------------------------------------'
echo '[1/3] Compiling HDL...'
echo '------------------------------------'
run_tool xvlog -prj sources.prj -i "$(tool_path "$TB_PATH/include")" "${compile_flags[@]}" -log compile.log

echo '------------------------------------'
echo '[2/3] Elaborating tb_core...'
echo '------------------------------------'
debug=()
if (( GUI )); then debug+=(-debug typical); fi
run_tool xelab "${elab_targets[@]}" -s behav_tb "${debug[@]}" -timescale 1ns/1ps -log elaborate.log

echo '------------------------------------'
echo '[3/3] Running ResNet-20 core verification...'
echo '------------------------------------'
args=(behav_tb -log simulate.log)

# A response file preserves '=' through Windows batch wrappers.
: > stream_args.f
[[ -n "${INPUT_GAP:-}" ]] && printf -- '-testplusarg "input_gap=%s"\n' "$INPUT_GAP" >> stream_args.f
[[ -s stream_args.f ]] && args+=(-f stream_args.f)
if (( GUI )); then
    # -runall performs "run all; quit" even when opening the GUI.
    # Run through Tcl instead, leaving the simulator open at $finish.
    cat > gui_run.tcl <<'TCL'
add_wave /tb_core/clk /tb_core/nrst
add_wave /tb_core/in_enable /tb_core/in_data /tb_core/kernel_data /tb_core/bias_data
add_wave /tb_core/out_enable /tb_core/out_data
run all
TCL
    args+=(-gui -onfinish stop -tclbatch gui_run.tcl)
else
    args+=(-runall)
fi
run_tool xsim "${args[@]}"
if grep -Fq 'Fatal:' simulate.log || ! grep -Fq '[ PASS ] ALL TESTS PASSED' simulate.log; then
    echo "[ ERROR ] TB did not pass. See $PATH_LOG/simulate.log" >&2
    exit 1
fi

#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
OUTPUT_FRAC_BITS=10

usage() {
    echo 'Usage: bash scripts/synthesis.sh [tb_core] [--output-frac-bits N]' >&2
}
while (( $# )); do
    case "$1" in
        tb_core) ;;
        --output-frac-bits)
            shift
            [[ "${1:-}" =~ ^([0-9]|1[0-5])$ ]] || { usage; exit 2; }
            OUTPUT_FRAC_BITS="$1"
            ;;
        *) usage; exit 2 ;;
    esac
    shift
done

vivado=vivado
tcl="$ROOT/scripts/synthesis.tcl"
case "$(uname -s)" in
    MINGW*|MSYS*)
        vivado=vivado.bat
        tcl=$(cygpath -am "$tcl")
        export MSYS2_ARG_CONV_EXCL='*' MSYS_NO_PATHCONV=1
        ;;
esac
command -v "$vivado" >/dev/null || {
    echo "[ ERROR ] $vivado not found. Add Vivado bin to PATH." >&2
    exit 1
}

BUILD="$ROOT/build/synth/tb_core/frac_$OUTPUT_FRAC_BITS"
mkdir -p -- "$BUILD"
cd -- "$BUILD"
echo "[ INFO ] Synthesizing tb_core DUT with output_frac_bits=$OUTPUT_FRAC_BITS"
export TB_CORE_SYNTH_FRAC_BITS="$OUTPUT_FRAC_BITS"
"$vivado" -mode batch -source "$tcl" -log synthesis.log -journal synthesis.jou
[[ -s core.dcp && -s core_funcsim.v ]] || {
    echo "[ ERROR ] Synthesis did not produce a checkpoint and netlist. See $BUILD/synthesis.log" >&2
    exit 1
}

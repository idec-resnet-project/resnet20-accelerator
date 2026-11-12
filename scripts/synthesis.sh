#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

usage() {
    echo 'Usage: bash scripts/synthesis.sh [tb_core] [--output-frac-bits N]' >&2
}
while (( $# )); do
    case "$1" in
        tb_core) ;;
        --output-frac-bits)
            shift
            [[ "${1:-}" =~ ^([0-9]|1[0-5])$ ]] || { usage; exit 2; }
            ;;
        *) usage; exit 2 ;;
    esac
    shift
done

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

exec "$python_cmd" "$ROOT/scripts/synthesis.py"

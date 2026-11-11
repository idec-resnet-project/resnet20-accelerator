#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
TB_CORE_POST_SYNTHESIS=1 exec bash "$SCRIPT_DIR/behav_sim.sh" "$@"

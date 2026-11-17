#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
GATE_PATH_WINDOWS="$(wslpath -w -a "$ROOT_DIR/tests/fpc/Run-FpcGate.ps1")"
# Interop transfers literal environment data. No generated cmd/shell source.
# Windows path values must not have the WSLENV /p translation flag.
for name in MAXCRON_FPC MAXCRON_FPC_OUT MAXCRON_DEBUG_SAFETY MAXCRON_FPC_ARGS; do
  if [[ -v "$name" ]]; then
    export "$name"
    export WSLENV="${WSLENV:+$WSLENV:}$name/w"
  fi
done
if (( $# )); then
  MAXCRON_FPC_ARGS="$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1:]))' "$@")"
  export MAXCRON_FPC_ARGS
  export WSLENV="${WSLENV:+$WSLENV:}MAXCRON_FPC_ARGS/w"
fi
/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -NoProfile -NonInteractive -File "$GATE_PATH_WINDOWS"

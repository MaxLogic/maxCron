#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ "${1:-}" == "fpc" ]]; then
  shift
  if (( $# )); then
    exec /mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -NoProfile -NonInteractive -File "$(wslpath -w -a "$ROOT_DIR/tests/Reject-RosterSelection.ps1")"
  fi
  export MAXCRON_LONG_TESTS=1
  exec "$ROOT_DIR/build-and-run-tests-fpc.sh" "$@"
fi
if (( $# )); then
  exec /mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -NoProfile -NonInteractive -File "$(wslpath -w -a "$ROOT_DIR/tests/Reject-RosterSelection.ps1")"
fi
export MAXCRON_BAT_PATH_WINDOWS="$(wslpath -w -a "$ROOT_DIR/build-and-run-tests-long.bat")"
for name in MAXCRON_LONG_PLATFORM MAXCRON_LONG_OUT; do
  if [[ -v "$name" ]]; then
    export "$name"
    export WSLENV="${WSLENV:+$WSLENV:}$name/w"
  fi
done
exec "$ROOT_DIR/build-and-run-tests.sh" "$@"

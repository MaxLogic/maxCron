#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$ROOT_DIR/tests/__recovery/soak-reports"
mkdir -p "$OUT_DIR"

MODES="scan,heap,auto"
HOURS="${MAXCRON_LONG_SOAK_HOURS:-24}"
EXTRA_ARGS=()

for arg in "$@"; do
  case "$arg" in
    --modes=*)
      MODES="${arg#*=}"
      ;;
    --hours=*)
      HOURS="${arg#*=}"
      ;;
    *)
      EXTRA_ARGS+=("$arg")
      ;;
  esac
done

STAMP="$(date +%Y%m%d-%H%M%S)"
REPORT_PATH="$OUT_DIR/long-soak-$STAMP.log"

{
  echo "maxCron long-soak run"
  echo "timestamp=$STAMP"
  echo "hours=$HOURS"
  echo "modes=$MODES"
  echo "cwd=$ROOT_DIR"
  echo
} >"$REPORT_PATH"

"$ROOT_DIR/build-delphi.sh" tests/maxCronStressTests.dproj -config release >>"$REPORT_PATH" 2>&1

set +e
MAXCRON_LONG_SOAK_HOURS="$HOURS" \
MAXCRON_LONG_SOAK_MODES="$MODES" \
"$ROOT_DIR/tests/maxCronStressTests.exe" \
  --run:TestLongSoak24h.TTestLongSoak24h.EngineModes_LogicalSoak_NoMisses \
  "${EXTRA_ARGS[@]}" >>"$REPORT_PATH" 2>&1
RC=$?
set -e

echo >>"$REPORT_PATH"
echo "exit_code=$RC" >>"$REPORT_PATH"
echo "report=$REPORT_PATH" >>"$REPORT_PATH"

echo "Long soak report: $REPORT_PATH"
tail -n 40 "$REPORT_PATH"

exit "$RC"

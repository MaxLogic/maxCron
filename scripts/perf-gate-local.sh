#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: ./scripts/perf-gate-local.sh [options]

Runs local benchmark + structural gate in one command.

Options:
  --iterations=N      Benchmark iterations (default: 5)
  --warmup=N          Warmup iterations (default: 1)
  --out-dir=PATH      Output directory for benchmark artifacts (default: benchmarks/results)
  --baseline=FILE     Optional baseline CSV for benchmark --compare mode
  --quiet             Pass --quiet to benchmark runner
  --help              Show this help

Environment overrides for structural gate:
  MAXCRON_GATE_SPARSE_HEAP_VISITED_RATIO
  MAXCRON_GATE_SPARSE_AUTO_VISITED_RATIO
  MAXCRON_GATE_BUDGET_SWITCH_RATIO
  MAXCRON_GATE_BUDGET_REBUILD_RATIO
  MAXCRON_GATE_BUDGET_VISITED_RATIO
USAGE
}

to_abs_path() {
  local aPath="$1"

  if [[ "$aPath" = /* ]]; then
    printf '%s\n' "$aPath"
  else
    printf '%s\n' "$(pwd)/$aPath"
  fi
}

require_cmd() {
  local aCmd="$1"

  if ! command -v "$aCmd" >/dev/null 2>&1; then
    printf 'ERROR missing required command: %s\n' "$aCmd" >&2
    exit 2
  fi
}

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ITERATIONS=5
WARMUP=1
OUT_DIR_REL="benchmarks/results"
BASELINE_CSV=""
QUIET=0

for lArg in "$@"; do
  case "$lArg" in
    --iterations=*) ITERATIONS="${lArg#*=}" ;;
    --warmup=*) WARMUP="${lArg#*=}" ;;
    --out-dir=*) OUT_DIR_REL="${lArg#*=}" ;;
    --baseline=*) BASELINE_CSV="${lArg#*=}" ;;
    --quiet) QUIET=1 ;;
    --help|-h|/?) usage; exit 0 ;;
    *)
      printf 'ERROR unknown option: %s\n\n' "$lArg" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if ! [[ "$ITERATIONS" =~ ^[0-9]+$ ]] || [ "$ITERATIONS" -lt 1 ]; then
  printf 'ERROR --iterations must be an integer >= 1\n' >&2
  exit 2
fi

if ! [[ "$WARMUP" =~ ^[0-9]+$ ]] || [ "$WARMUP" -lt 0 ]; then
  printf 'ERROR --warmup must be an integer >= 0\n' >&2
  exit 2
fi

require_cmd wslpath
require_cmd /mnt/c/Windows/System32/cmd.exe

OUT_DIR_ABS="$(to_abs_path "$ROOT_DIR/$OUT_DIR_REL")"
mkdir -p "$OUT_DIR_ABS"

BASELINE_ABS=""
if [ -n "$BASELINE_CSV" ]; then
  BASELINE_ABS="$(to_abs_path "$ROOT_DIR/$BASELINE_CSV")"
  if [ ! -f "$BASELINE_ABS" ]; then
    printf 'ERROR baseline CSV not found: %s\n' "$BASELINE_ABS" >&2
    exit 2
  fi
fi

OUT_DIR_WIN="$(wslpath -w -a "$OUT_DIR_ABS")"
REPO_WIN="$(wslpath -w -a "$ROOT_DIR")"

BENCH_CMD="benchmarks\\maxCronBenchmarks.exe --iterations=${ITERATIONS} --warmup=${WARMUP} --out-dir=${OUT_DIR_WIN}"
if [ "$QUIET" -eq 1 ]; then
  BENCH_CMD+=" --quiet"
fi
if [ -n "$BASELINE_ABS" ]; then
  BASELINE_WIN="$(wslpath -w -a "$BASELINE_ABS")"
  BENCH_CMD+=" --compare=${BASELINE_WIN}"
fi

printf 'Building benchmark runner...\n'
"$ROOT_DIR/build-delphi.sh" "$ROOT_DIR/benchmarks/maxCronBenchmarks.dproj" -config release

printf '\nRunning benchmark command:\n  %s\n\n' "$BENCH_CMD"
set +e
BENCH_OUTPUT="$(/mnt/c/Windows/System32/cmd.exe /C "cd /d ${REPO_WIN} && ${BENCH_CMD}" 2>&1)"
BENCH_EXIT=$?
set -e
printf '%s\n' "$BENCH_OUTPUT"

if [ "$BENCH_EXIT" -ne 0 ]; then
  printf '\nERROR benchmark execution failed (exit=%s).\n' "$BENCH_EXIT" >&2
  exit "$BENCH_EXIT"
fi

CSV_REPORT_WIN="$(printf '%s\n' "$BENCH_OUTPUT" | sed -n 's/^CSV report: //p' | tail -n 1 | tr -d '\r')"
MD_REPORT_WIN="$(printf '%s\n' "$BENCH_OUTPUT" | sed -n 's/^Markdown report: //p' | tail -n 1 | tr -d '\r')"

if [ -z "$CSV_REPORT_WIN" ]; then
  CSV_REPORT="$(ls -1 "$OUT_DIR_ABS"/maxcron-benchmarks-*.csv | sort | tail -n 1)"
else
  CSV_REPORT="$(wslpath "$CSV_REPORT_WIN")"
fi

if [ -z "$MD_REPORT_WIN" ]; then
  MD_REPORT="$(ls -1 "$OUT_DIR_ABS"/maxcron-benchmarks-*.md | sort | tail -n 1)"
else
  MD_REPORT="$(wslpath "$MD_REPORT_WIN")"
fi

if [ ! -f "$CSV_REPORT" ]; then
  printf 'ERROR could not resolve generated CSV report path.\n' >&2
  exit 3
fi

printf '\nRunning structural gate on generated CSV:\n  %s\n\n' "$CSV_REPORT"
"$ROOT_DIR/scripts/check-benchmark-metrics.sh" "$CSV_REPORT"

printf '\nLocal performance gate PASSED.\n'
printf 'CSV: %s\n' "$CSV_REPORT"
printf 'Markdown: %s\n' "$MD_REPORT"

#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: ./scripts/generate-benchmark-trend-report.sh [options]

Generates a markdown trend report from benchmark CSV history.

Options:
  --input-dir=PATH    Directory containing maxcron-benchmarks-*.csv (default: benchmarks/results)
  --limit=N           Number of latest CSV files to include (default: 10)
  --output=FILE       Output markdown file (default: benchmarks/results/benchmark-trend.md)
  --help              Show this help
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

calc_delta_pct() {
  local aPrev="$1"
  local aCurr="$2"

  awk -v prev="$aPrev" -v curr="$aCurr" 'BEGIN {
    if (prev == 0) {
      printf "n/a"
      exit 0
    }

    delta = ((curr - prev) / prev) * 100.0
    if (delta > 0) {
      printf "+%.6f", delta
    } else {
      printf "%.6f", delta
    }
  }'
}

extract_scenario_means() {
  local aCsvPath="$1"

  awk -F',' '
  function unquote(value) {
    gsub(/\r/, "", value)
    if (value ~ /^".*"$/) {
      sub(/^"/, "", value)
      sub(/"$/, "", value)
      gsub(/""/, "\"", value)
    }
    return value
  }

  NR == 1 {
    for (i = 1; i <= NF; i++) {
      column = unquote($i)
      gsub(/^\xef\xbb\xbf/, "", column)
      headerIndex[column] = i
    }

    requiredColumns[1] = "scenario_name"
    requiredColumns[2] = "elapsed_us"
    requiredColumns[3] = "events_visited"
    requiredColumns[4] = "heap_rebuilds"
    requiredColumns[5] = "switch_count"

    for (i = 1; i <= 5; i++) {
      column = requiredColumns[i]
      if (!(column in headerIndex)) {
        printf "ERROR missing required CSV column: %s\n", column > "/dev/stderr"
        exit 20
      }
    }

    scenarioOrder[1] = "sparse_high_n_scan"
    scenarioOrder[2] = "sparse_high_n_heap"
    scenarioOrder[3] = "sparse_high_n_auto"
    scenarioOrder[4] = "adversarial_auto_no_budget"
    scenarioOrder[5] = "adversarial_auto_budget"

    next
  }

  NR > 1 {
    if ($0 ~ /^[[:space:]]*$/) {
      next
    }

    scenario = unquote($(headerIndex["scenario_name"]))
    elapsedUs = unquote($(headerIndex["elapsed_us"])) + 0
    visited = unquote($(headerIndex["events_visited"])) + 0
    rebuilds = unquote($(headerIndex["heap_rebuilds"])) + 0
    switches = unquote($(headerIndex["switch_count"])) + 0

    sum[scenario, "elapsed"] += elapsedUs
    sum[scenario, "visited"] += visited
    sum[scenario, "rebuilds"] += rebuilds
    sum[scenario, "switches"] += switches
    count[scenario]++
  }

  END {
    for (i = 1; i <= 5; i++) {
      scenario = scenarioOrder[i]
      if (!(scenario in count) || (count[scenario] == 0)) {
        printf "ERROR missing scenario rows in CSV: %s\n", scenario > "/dev/stderr"
        exit 21
      }

      printf "%s\t%.6f\t%.6f\t%.6f\t%.6f\n", scenario,
        (sum[scenario, "elapsed"] / count[scenario]) / 1000.0,
        (sum[scenario, "visited"] / count[scenario]),
        (sum[scenario, "rebuilds"] / count[scenario]),
        (sum[scenario, "switches"] / count[scenario])
    }
  }' "$aCsvPath"
}

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INPUT_DIR_REL="benchmarks/results"
OUTPUT_REL="benchmarks/results/benchmark-trend.md"
LIMIT=10

for lArg in "$@"; do
  case "$lArg" in
    --input-dir=*) INPUT_DIR_REL="${lArg#*=}" ;;
    --output=*) OUTPUT_REL="${lArg#*=}" ;;
    --limit=*) LIMIT="${lArg#*=}" ;;
    --help|-h|/?) usage; exit 0 ;;
    *)
      printf 'ERROR unknown option: %s\n\n' "$lArg" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if ! [[ "$LIMIT" =~ ^[0-9]+$ ]] || [ "$LIMIT" -lt 1 ]; then
  printf 'ERROR --limit must be an integer >= 1\n' >&2
  exit 2
fi

INPUT_DIR_ABS="$(to_abs_path "$ROOT_DIR/$INPUT_DIR_REL")"
OUTPUT_ABS="$(to_abs_path "$ROOT_DIR/$OUTPUT_REL")"
mkdir -p "$(dirname "$OUTPUT_ABS")"

mapfile -t ALL_CSVS < <(ls -1 "$INPUT_DIR_ABS"/maxcron-benchmarks-*.csv 2>/dev/null | sort)
if [ "${#ALL_CSVS[@]}" -eq 0 ]; then
  printf 'ERROR no benchmark CSV files found in: %s\n' "$INPUT_DIR_ABS" >&2
  exit 3
fi

if [ "${#ALL_CSVS[@]}" -le "$LIMIT" ]; then
  CSVS=("${ALL_CSVS[@]}")
else
  START_INDEX=$(( ${#ALL_CSVS[@]} - LIMIT ))
  CSVS=("${ALL_CSVS[@]:$START_INDEX}")
fi

GENERATED_UTC="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"

{
  printf '# maxCron benchmark trend report\n\n'
  printf -- '- Generated (UTC): %s\n' "$GENERATED_UTC"
  printf -- '- Input dir: `%s`\n' "$INPUT_DIR_ABS"
  printf -- '- Included CSV files: %s\n\n' "${#CSVS[@]}"

  printf '## Scenario trend (mean per run)\n\n'
  printf '| Run | Scenario | Elapsed ms mean | Elapsed delta %% vs prev | Visited mean | Visited delta %% vs prev | Rebuild mean | Switch mean |\n'
  printf '| --- | --- | --- | --- | --- | --- | --- | --- |\n'

  declare -A PREV_ELAPSED=()
  declare -A PREV_VISITED=()

  for lCsvPath in "${CSVS[@]}"; do
    lRunName="$(basename "$lCsvPath" .csv)"

    while IFS=$'\t' read -r lScenario lElapsedMs lVisitedMean lRebuildMean lSwitchMean; do
      lElapsedDelta='n/a'
      lVisitedDelta='n/a'

      if [ -n "${PREV_ELAPSED[$lScenario]+x}" ]; then
        lElapsedDelta="$(calc_delta_pct "${PREV_ELAPSED[$lScenario]}" "$lElapsedMs")"
      fi

      if [ -n "${PREV_VISITED[$lScenario]+x}" ]; then
        lVisitedDelta="$(calc_delta_pct "${PREV_VISITED[$lScenario]}" "$lVisitedMean")"
      fi

      printf '| %s | %s | %s | %s | %s | %s | %s | %s |\n' \
        "$lRunName" "$lScenario" "$lElapsedMs" "$lElapsedDelta" "$lVisitedMean" "$lVisitedDelta" \
        "$lRebuildMean" "$lSwitchMean"

      PREV_ELAPSED[$lScenario]="$lElapsedMs"
      PREV_VISITED[$lScenario]="$lVisitedMean"
    done < <(extract_scenario_means "$lCsvPath")
  done

  printf '\n## Included files\n\n'
  for lCsvPath in "${CSVS[@]}"; do
    printf -- '- `%s`\n' "$lCsvPath"
  done
} > "$OUTPUT_ABS"

printf 'Trend report written: %s\n' "$OUTPUT_ABS"

#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: ./scripts/check-benchmark-metrics.sh <benchmark.csv> [more.csv ...]

Checks structural benchmark ratios that are stable across machines.
Thresholds are configurable via environment variables:
  MAXCRON_GATE_SPARSE_HEAP_VISITED_RATIO (default: 0.25)
  MAXCRON_GATE_SPARSE_AUTO_VISITED_RATIO (default: 0.25)
  MAXCRON_GATE_BUDGET_SWITCH_RATIO      (default: 1.05)
  MAXCRON_GATE_BUDGET_REBUILD_RATIO     (default: 1.05)
  MAXCRON_GATE_BUDGET_VISITED_RATIO     (default: 1.05)
USAGE
}

calc_ratio() {
  local aNumerator="$1"
  local aDenominator="$2"

  awk -v numerator="$aNumerator" -v denominator="$aDenominator" 'BEGIN {
    if (denominator == 0) {
      printf "0"
      exit 0
    }

    printf "%.12f", (numerator / denominator)
  }'
}

check_ratio_le() {
  local aLabel="$1"
  local aValue="$2"
  local aThreshold="$3"

  if awk -v value="$aValue" -v threshold="$aThreshold" 'BEGIN { exit (value <= threshold) ? 0 : 1 }'; then
    printf 'PASS %s ratio=%s threshold<=%s\n' "$aLabel" "$aValue" "$aThreshold"
    return 0
  fi

  printf 'FAIL %s ratio=%s threshold<=%s\n' "$aLabel" "$aValue" "$aThreshold" >&2
  return 1
}

extract_means() {
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
    requiredColumns[2] = "events_visited"
    requiredColumns[3] = "heap_rebuilds"
    requiredColumns[4] = "switch_count"

    for (i = 1; i <= 4; i++) {
      column = requiredColumns[i]
      if (!(column in headerIndex)) {
        printf "ERROR missing required CSV column: %s\n", column > "/dev/stderr"
        exit 20
      }
    }

    next
  }

  NR > 1 {
    if ($0 ~ /^[[:space:]]*$/) {
      next
    }

    scenario = unquote($(headerIndex["scenario_name"]))
    visited = unquote($(headerIndex["events_visited"])) + 0
    rebuilds = unquote($(headerIndex["heap_rebuilds"])) + 0
    switches = unquote($(headerIndex["switch_count"])) + 0

    sum[scenario, "visited"] += visited
    sum[scenario, "rebuilds"] += rebuilds
    sum[scenario, "switches"] += switches
    count[scenario]++
  }

  END {
    requiredScenarios[1] = "sparse_high_n_scan"
    requiredScenarios[2] = "sparse_high_n_heap"
    requiredScenarios[3] = "sparse_high_n_auto"
    requiredScenarios[4] = "adversarial_auto_no_budget"
    requiredScenarios[5] = "adversarial_auto_budget"

    for (i = 1; i <= 5; i++) {
      scenario = requiredScenarios[i]
      if (!(scenario in count) || (count[scenario] == 0)) {
        printf "ERROR missing scenario rows in CSV: %s\n", scenario > "/dev/stderr"
        exit 21
      }
    }

    for (i = 1; i <= 5; i++) {
      scenario = requiredScenarios[i]
      printf "%s_visited_mean=%.12f\n", scenario, (sum[scenario, "visited"] / count[scenario])
      printf "%s_rebuilds_mean=%.12f\n", scenario, (sum[scenario, "rebuilds"] / count[scenario])
      printf "%s_switches_mean=%.12f\n", scenario, (sum[scenario, "switches"] / count[scenario])
    }
  }' "$aCsvPath"
}

if [ "$#" -lt 1 ]; then
  usage
  exit 2
fi

: "${MAXCRON_GATE_SPARSE_HEAP_VISITED_RATIO:=0.25}"
: "${MAXCRON_GATE_SPARSE_AUTO_VISITED_RATIO:=0.25}"
: "${MAXCRON_GATE_BUDGET_SWITCH_RATIO:=1.05}"
: "${MAXCRON_GATE_BUDGET_REBUILD_RATIO:=1.05}"
: "${MAXCRON_GATE_BUDGET_VISITED_RATIO:=1.05}"

lExitCode=0

for lCsvPath in "$@"; do
  if [ ! -f "$lCsvPath" ]; then
    printf 'ERROR CSV not found: %s\n' "$lCsvPath" >&2
    lExitCode=2
    continue
  fi

  printf 'Checking benchmark metrics: %s\n' "$lCsvPath"
  declare -A lMetrics=()

  while IFS='=' read -r lKey lValue; do
    lMetrics["$lKey"]="$lValue"
  done < <(extract_means "$lCsvPath")

  lSparseHeapVisitedRatio=$(calc_ratio "${lMetrics[sparse_high_n_heap_visited_mean]}" "${lMetrics[sparse_high_n_scan_visited_mean]}")
  lSparseAutoVisitedRatio=$(calc_ratio "${lMetrics[sparse_high_n_auto_visited_mean]}" "${lMetrics[sparse_high_n_scan_visited_mean]}")
  lBudgetSwitchRatio=$(calc_ratio "${lMetrics[adversarial_auto_budget_switches_mean]}" "${lMetrics[adversarial_auto_no_budget_switches_mean]}")
  lBudgetRebuildRatio=$(calc_ratio "${lMetrics[adversarial_auto_budget_rebuilds_mean]}" "${lMetrics[adversarial_auto_no_budget_rebuilds_mean]}")
  lBudgetVisitedRatio=$(calc_ratio "${lMetrics[adversarial_auto_budget_visited_mean]}" "${lMetrics[adversarial_auto_no_budget_visited_mean]}")

  lFileFailed=0
  check_ratio_le 'sparse_high_n heap/scan visited' "$lSparseHeapVisitedRatio" "$MAXCRON_GATE_SPARSE_HEAP_VISITED_RATIO" || lFileFailed=1
  check_ratio_le 'sparse_high_n auto/scan visited' "$lSparseAutoVisitedRatio" "$MAXCRON_GATE_SPARSE_AUTO_VISITED_RATIO" || lFileFailed=1
  check_ratio_le 'adversarial budget/no-budget switches' "$lBudgetSwitchRatio" "$MAXCRON_GATE_BUDGET_SWITCH_RATIO" || lFileFailed=1
  check_ratio_le 'adversarial budget/no-budget rebuilds' "$lBudgetRebuildRatio" "$MAXCRON_GATE_BUDGET_REBUILD_RATIO" || lFileFailed=1
  check_ratio_le 'adversarial budget/no-budget visited' "$lBudgetVisitedRatio" "$MAXCRON_GATE_BUDGET_VISITED_RATIO" || lFileFailed=1

  if [ "$lFileFailed" -ne 0 ]; then
    lExitCode=1
  fi

done

exit "$lExitCode"

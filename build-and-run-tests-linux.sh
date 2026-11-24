#!/usr/bin/env bash
set -uo pipefail
export LC_ALL=C

fail_gate() {
    printf 'LINUX GATE FAILED reason=%s detail=%s\n' "$2" "$3" >&2
    exit "$1"
}

reject_roster() {
    printf 'ROSTER_PHASE phase=roster name=%s native_exit=5\n' "$1"
    printf 'ROSTER_REJECTED reason=%s detail=%s\n' "$2" "$3"
    exit 5
}

configuration_error() {
    fail_gate 2 configuration "$1"
}

if [[ $# != 1 ]]; then
    reject_roster arguments count 'Usage: ./build-and-run-tests-linux.sh <delphi|fpc|fpc-aarch64>'
fi
lane=$1
case "$lane" in
    delphi) ;;
    fpc|fpc-aarch64) configuration_error "The $lane Linux lane is not available yet." ;;
    *) reject_roster arguments count "Unsupported Linux lane: $lane" ;;
esac

[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] ||
    configuration_error 'The Delphi Linux64 gate requires an x86_64 Linux host.'
[[ -n ${HOME:-} ]] || configuration_error 'HOME must be set.'
root=${MAXCRON_ROSTER_OUT:-"$HOME/dev-artifacts/runs/maxCron"}
[[ $root =~ ^/[A-Za-z0-9/._+-]*$ ]] ||
    configuration_error 'MAXCRON_ROSTER_OUT must be an absolute Linux path using only A-Z, a-z, 0-9, /, ., _, + or -.'
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P) ||
    configuration_error 'Cannot resolve the repository path.'
prebuilt=${MAXCRON_LINUX_PREBUILT:-}
entries=(unit)
manifests=(DelphiLinuxLong)
programs=(maxCronTests)
seconds=172800
if [[ ${MAXCRON_LONG_TESTS:-} != 1 ]]; then
    entries+=(stress)
    manifests=(DelphiLinuxUnit DelphiLinuxStress)
    programs+=(maxCronStressTests)
    seconds=7200
fi
seconds=${MAXCRON_LINUX_TIMEOUT_SECONDS:-$seconds}
[[ $seconds =~ ^[1-9][0-9]*$ ]] ||
    configuration_error 'MAXCRON_LINUX_TIMEOUT_SECONDS must be a positive integer.'
if [[ -n $prebuilt ]]; then
    prebuilt=$(cd -- "$prebuilt" && pwd -P) ||
        configuration_error 'MAXCRON_LINUX_PREBUILT must name an existing lane directory.'
    for i in "${!entries[@]}"; do
        [[ -f $prebuilt/${entries[i]}/${programs[i]} ]] ||
            configuration_error "Missing prebuilt runner: ${entries[i]}/${programs[i]}"
    done
else
    powershell=/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe
    [[ -x $powershell ]] && command -v wslpath >/dev/null ||
        configuration_error 'Building Delphi Linux64 requires Windows PowerShell and wslpath in WSL.'
fi

mkdir -p -- "$root" || fail_gate 3 output "Cannot create output root: $root"
stamp=$(date -u +%Y%m%dT%H%M%SZ) || fail_gate 3 output 'Cannot timestamp the run directory.'
run=$(mktemp -d "$root/linux-$lane-$stamp-XXXXXX") ||
    fail_gate 3 output "Cannot allocate a run directory under $root"
printf 'LINUX GATE OUTPUT %s\n' "$run"
mkdir -- "$run/tmp" || fail_gate 3 output "Cannot create $run/tmp"

if [[ -z $prebuilt ]]; then
    win_build=$(wslpath -w -a "$repo/tests/linux/Build-DelphiLinux64.ps1") ||
        fail_gate 3 build 'Cannot resolve the Windows build script path.'
    export WSLENV="${WSLENV:+$WSLENV:}MAXCRON_BUILD_ROOT/w:MAXCRON_DCCLINUX64/w:MAXCRON_LINUX_SDK/w:MAXCRON_LONG_TESTS/w:MAXCRON_DEBUG_SAFETY/w"
    "$powershell" -NoProfile -NonInteractive -File "$win_build" > "$run/build.log" 2>&1
    rc=$?
    cat -- "$run/build.log" || fail_gate 3 log "Cannot read $run/build.log"
    case "$rc" in
        0) ;;
        2) configuration_error 'The Delphi build rejected its configuration.' ;;
        124) fail_gate 124 timeout 'The Delphi build timed out.' ;;
        *) fail_gate 3 build "The Delphi build exited $rc." ;;
    esac
    outputs=()
    while IFS= read -r line; do
        line=${line%$'\r'}
        if [[ $line == 'LINUX64_OUTPUT '* ]]; then
            outputs+=("${line#LINUX64_OUTPUT }")
        fi
    done < "$run/build.log" || fail_gate 3 log "Cannot read $run/build.log"
    [[ ${#outputs[@]} == ${#entries[@]} ]] ||
        fail_gate 3 build "Expected ${#entries[@]} LINUX64_OUTPUT receipts, found ${#outputs[@]}."
fi

for i in "${!entries[@]}"; do
    work="$run/${entries[i]}"
    exe="${programs[i]}"
    mkdir -- "$work" || fail_gate 3 output "Cannot create $work"
    if [[ -n $prebuilt ]]; then
        source="$prebuilt/${entries[i]}"
    else
        source=$(wslpath -u "${outputs[i]}") ||
            fail_gate 3 build "Cannot resolve the path for $exe"
    fi
    cp -- "$source/$exe" "$work/$exe" && chmod +x -- "$work/$exe" ||
        fail_gate 3 output "Cannot stage $exe in $work"
done

child_env=(env -i PATH=/usr/bin:/bin "HOME=$HOME" LANG=C.UTF-8 "TMPDIR=$run/tmp"
    "MAXCRON_TEST_ROOT=$repo")
for setting in MAXCRON_LONG_TESTS MAXCRON_STRESS MAXCRON_DEBUG_SAFETY; do
    if [[ -v $setting ]]; then
        child_env+=("$setting=${!setting}")
    fi
done

verify_run() {
    local entry=$1 log=$2 manifest=$3 line field total_found total_passed
    local verified=0 receipt=''
    local -A totals=() counts=()
    local -a executed=() expected=()
    local summary='^Tests (Found|Passed|Failed|Errored|Ignored)[[:space:]]*:[[:space:]]*([0-9]+)[[:space:]]*$'
    while IFS= read -r line || [[ -n $line ]]; do
        line=${line%$'\r'}
        if [[ $line =~ $summary ]]; then
            field=${BASH_REMATCH[1]}
            counts[$field]=$((${counts[$field]:-0} + 1))
            totals[$field]=${BASH_REMATCH[2]}
        elif [[ $line == ROSTER_VERIFIED || $line == ROSTER_VERIFIED[[:space:]]* ]]; then
            ((verified += 1))
            receipt=$line
        elif [[ $line == ROSTER_REJECTED || $line == ROSTER_REJECTED[[:space:]]* ]]; then
            reject_roster "$entry" count 'Runner reported ROSTER_REJECTED despite exiting successfully.'
        elif [[ $line == 'ROSTER_TEST '* ]]; then
            executed+=("${line#ROSTER_TEST }")
        fi
    done < "$log" || fail_gate 3 log "Cannot read the verification input for $entry"

    for field in Found Passed Failed Errored Ignored; do
        [[ ${counts[$field]:-0} == 1 ]] ||
            fail_gate 1 summary "$entry expected one Tests $field line, found ${counts[$field]:-0}."
    done
    total_found=${totals[Found]}
    total_passed=${totals[Passed]}
    if [[ $total_found == 0 || $total_passed != "$total_found" ||
          ${totals[Failed]} != 0 || ${totals[Errored]} != 0 || ${totals[Ignored]} != 0 ]]; then
        fail_gate 1 summary "$entry found=$total_found passed=$total_passed failed=${totals[Failed]} errored=${totals[Errored]} ignored=${totals[Ignored]}."
    fi
    [[ $verified == 1 && $receipt == "ROSTER_VERIFIED $entry expected=$total_found found=$total_found passed=$total_found" ]] ||
        reject_roster "$entry" count "Expected one ROSTER_VERIFIED receipt with expected, found and passed all equal to $total_found."
    [[ ${#executed[@]} == "$total_found" ]] ||
        reject_roster "$entry" count 'ROSTER_TEST count differs from Tests Found.'

    local expected_sorted executed_sorted executed_unique
    [[ -r $manifest ]] || reject_roster "$entry" missing 'Manifest could not be read.'
    while IFS= read -r line || [[ -n $line ]]; do
        line=${line#$'\xef\xbb\xbf'}
        line=${line%$'\r'}
        if [[ -n $line && $line != \#* ]]; then
            expected+=("$line")
        fi
    done < "$manifest" || reject_roster "$entry" missing 'Manifest could not be read.'
    expected_sorted=$(printf '%s\n' "${expected[@]}" | sort) ||
        fail_gate 3 roster "Cannot sort the expected identities for $entry"
    executed_sorted=$(printf '%s\n' "${executed[@]}" | sort) ||
        fail_gate 3 roster "Cannot sort the executed identities for $entry"
    executed_unique=$(printf '%s\n' "${executed[@]}" | sort -u) ||
        fail_gate 3 roster "Cannot check for duplicate identities in $entry"
    [[ $executed_unique == "$executed_sorted" ]] ||
        reject_roster "$entry" duplicate 'Runner reported a duplicate identity.'
    if [[ $executed_sorted != "$expected_sorted" ]]; then
        if (( ${#executed[@]} < ${#expected[@]} )); then
            reject_roster "$entry" missing 'Executed identities differ from the manifest.'
        elif (( ${#executed[@]} > ${#expected[@]} )); then
            reject_roster "$entry" extra 'Executed identities differ from the manifest.'
        else
            reject_roster "$entry" renamed 'Executed identities differ from the manifest.'
        fi
    fi
    total=$((total + total_found))
}

total=0
for i in "${!entries[@]}"; do
    entry=${manifests[i]}
    work="$run/${entries[i]}"
    log="$work/run.log"
    checks="$work/verify.log"
    (cd -- "$work" && "${child_env[@]}" timeout --kill-after=30 "$seconds" "./${programs[i]}") > "$log" 2>&1
    rc=$?
    cat -- "$log" || fail_gate 3 log "Cannot read $log"
    # DUnitX emits ANSI CSI sequences even with redirected output.
    sed -E $'s|\033\\[[0-?]*[ -/]*[@-~]||g' "$log" > "$checks" ||
        fail_gate 3 log "Cannot normalize the runner output for $entry"
    case "$rc" in
        0) verify_run "$entry" "$checks" "$repo/tests/rosters/$entry.txt" ;;
        124|137) fail_gate 124 timeout "$entry timed out (native exit $rc)." ;;
        5)
            rejections=0
            while IFS= read -r line || [[ -n $line ]]; do
                if [[ $line == 'ROSTER_REJECTED reason='* ]]; then
                    ((rejections += 1))
                fi
            done < "$checks" || fail_gate 3 log "Cannot read the verification input for $entry"
            if [[ $rejections == 1 ]]; then
                printf 'ROSTER_PHASE phase=runner name=%s native_exit=5\n' "$entry"
                exit 5
            fi
            fail_gate 1 runner "$entry exited 5 with $rejections roster rejection receipts."
            ;;
        *) fail_gate 1 runner "$entry exited $rc." ;;
    esac
done

printf 'ROSTER_GATE_VERIFIED DelphiLinuxGate %s\n' "$total"
printf 'LINUX GATE PASSED (%s, %s tests)\n' "$lane" "$total"

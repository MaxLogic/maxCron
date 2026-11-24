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
    delphi|fpc) ;;
    fpc-aarch64) configuration_error "The $lane Linux lane is not available yet." ;;
    *) reject_roster arguments count "Unsupported Linux lane: $lane" ;;
esac

[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] ||
    configuration_error "The $lane gate requires an x86_64 Linux host."
[[ -n ${HOME:-} ]] || configuration_error 'HOME must be set.'
root_setting=MAXCRON_ROSTER_OUT
[[ $lane != fpc ]] || root_setting=MAXCRON_FPC_OUT
root=${!root_setting:-"$HOME/dev-artifacts/runs/maxCron"}
[[ $root =~ ^/[A-Za-z0-9/._+-]*$ ]] ||
    configuration_error "$root_setting must be an absolute Linux path using only A-Z, a-z, 0-9, /, ., _, + or -."
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P) ||
    configuration_error 'Cannot resolve the repository path.'
prebuilt=${MAXCRON_LINUX_PREBUILT:-}
long=${MAXCRON_LONG_TESTS:-0}
runner_seconds=7200
[[ $long != 1 ]] || runner_seconds=172800
if [[ $lane == fpc ]]; then
    entries=(tests smoke smoke-heaptrc)
    manifests=(FpcLinux FpcSmoke FpcSmokeHeap)
    programs=(maxCronFpcTests maxCronFpcSmoke maxCronFpcSmoke)
    limits=("$runner_seconds" 600 600)
    [[ $long != 1 ]] || manifests[0]=FpcLinuxLong
    gate_name=FpcLinuxGate
elif [[ $long == 1 ]]; then
    entries=(unit)
    manifests=(DelphiLinuxLong)
    programs=(maxCronTests)
    limits=("$runner_seconds")
    gate_name=DelphiLinuxGate
else
    entries=(unit stress)
    manifests=(DelphiLinuxUnit DelphiLinuxStress)
    programs=(maxCronTests maxCronStressTests)
    limits=("$runner_seconds" "$runner_seconds")
    gate_name=DelphiLinuxGate
fi
time_override=${MAXCRON_LINUX_TIMEOUT_SECONDS:-}
[[ -z $time_override || $time_override =~ ^[1-9][0-9]*$ ]] ||
    configuration_error 'MAXCRON_LINUX_TIMEOUT_SECONDS must be a positive integer.'

fpc_flags=()
child_path=/usr/bin:/bin
check_fpc_tool() {
    local option=$1 expected=$2 actual
    actual=$(env -i "PATH=$child_path" "HOME=$HOME" LANG=C.UTF-8 "$fpc" "${fpc_flags[@]}" "$option" 2>&1) ||
        configuration_error "FPC $option failed: $actual"
    [[ $actual == "$expected" ]] ||
        configuration_error "FPC $option must report $expected; got $actual."
}

if [[ -n $prebuilt ]]; then
    prebuilt=$(cd -- "$prebuilt" && pwd -P) ||
        configuration_error 'MAXCRON_LINUX_PREBUILT must name an existing lane directory.'
    for i in "${!entries[@]}"; do
        [[ -f $prebuilt/${entries[i]}/${programs[i]} ]] ||
            configuration_error "Missing prebuilt runner: ${entries[i]}/${programs[i]}"
    done
elif [[ $lane == delphi ]]; then
    powershell=/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe
    [[ -x $powershell ]] && command -v wslpath >/dev/null ||
        configuration_error 'Building Delphi Linux64 requires Windows PowerShell and wslpath in WSL.'
else
    [[ -n ${MAXCRON_FPC:-} ]] || configuration_error 'Set MAXCRON_FPC to the Linux FPC driver.'
    fpc=$(realpath -s -- "$MAXCRON_FPC") || configuration_error 'Cannot resolve MAXCRON_FPC.'
    fpc_bin=${fpc%/*}
    [[ -f $fpc && -x $fpc && -r $fpc_bin/fpc.cfg ]] ||
        configuration_error 'MAXCRON_FPC must name an executable FPC driver with fpc.cfg beside it.'
    child_path="$fpc_bin:$child_path"
    fpc_flags=(-n "@$fpc_bin/fpc.cfg")
    check_fpc_tool -iV 3.3.1
    check_fpc_tool -iTO linux
    check_fpc_tool -iTP x86_64
    printf 'FPC 3.3.1 x86_64-linux at %s\n' "$fpc"
fi

mkdir -p -- "$root" || fail_gate 3 output "Cannot create output root: $root"
stamp=$(date -u +%Y%m%dT%H%M%SZ) || fail_gate 3 output 'Cannot timestamp the run directory.'
run=$(mktemp -d "$root/linux-$lane-$stamp-XXXXXX") ||
    fail_gate 3 output "Cannot allocate a run directory under $root"
printf 'LINUX GATE OUTPUT %s\n' "$run"
mkdir -- "$run/tmp" || fail_gate 3 output "Cannot create $run/tmp"

child_env=(env -i "PATH=$child_path" "HOME=$HOME" LANG=C.UTF-8 "TMPDIR=$run/tmp"
    "MAXCRON_TEST_ROOT=$repo")
for setting in MAXCRON_LONG_TESTS MAXCRON_STRESS MAXCRON_DEBUG_SAFETY; do
    if [[ -v $setting ]]; then
        child_env+=("$setting=${!setting}")
    fi
done

build_fpc_program() {
    local name=$1 program=$2 work="$run/$1" rc
    shift 2
    mkdir -- "$work" || fail_gate 3 output "Cannot create $work"
    (cd -- "$work" && "${child_env[@]}" "$fpc" "${fpc_flags[@]}" -Sew "-FU$work" "-FE$work" \
        "$@" "$repo/tests/fpc/$program.dpr") > "$work/build.log" 2>&1
    rc=$?
    cat -- "$work/build.log" || fail_gate 3 log "Cannot read $work/build.log"
    [[ $rc == 0 && -f $work/$program && -x $work/$program ]] ||
        fail_gate 3 build "FPC must produce $name/$program (native exit $rc)."
}

if [[ -z $prebuilt && $lane == fpc ]]; then
    fpc_flags+=("-Fu$repo" "-Fu$repo/tests" "-Fi$repo")
    if [[ ${MAXCRON_DEBUG_SAFETY:-} == 1 ]]; then
        fpc_flags+=(-O- -gl -Cr -Co -Ct -Ci -Sa)
    else
        fpc_flags+=(-O2 -gl)
    fi
    [[ $long != 1 ]] || fpc_flags+=(-dMAXCRON_LONG_TESTS)
    build_fpc_program check-public maxCronFpcCompileCheck
    build_fpc_program check-tests maxCronFpcCompileCheck -dMAXCRON_TESTS
    build_fpc_program gen maxCronFpcRegistryGen -vm4104,4105
    registry="$run/gen/maxCronFpcRegistry.inc"
    (cd -- "$run/gen" && "${child_env[@]}" ./maxCronFpcRegistryGen "$repo" "$registry") > "$run/gen/run.log" 2>&1
    rc=$?
    cat -- "$run/gen/run.log" || fail_gate 3 log "Cannot read $run/gen/run.log"
    [[ $rc == 0 && -s $registry ]] || fail_gate 3 build "FPC registry generation failed (native exit $rc)."
    build_fpc_program tests maxCronFpcTests -dMAXCRON_TESTS -gh -vm4104,4105 \
        "-Fu$repo/tests/fpc" "-Fu$repo/tests/unit" "-Fi$run/gen"
    build_fpc_program smoke maxCronFpcSmoke
    build_fpc_program smoke-heaptrc maxCronFpcSmoke -gh -dMAXCRON_FPC_SMOKE_NOPOOL
elif [[ -z $prebuilt ]]; then
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
    if [[ -z $prebuilt && $lane == fpc ]]; then
        break
    fi
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
    run_env=("${child_env[@]}")
    heap=
    case "$entry" in
        FpcLinux|FpcLinuxLong|FpcSmokeHeap)
            heap="$work/child.heaptrc.log"
            run_env+=(HEAPTRC=log=child.heaptrc.log)
            ;;
    esac
    (cd -- "$work" && "${run_env[@]}" timeout --kill-after=30 \
        "${time_override:-${limits[i]}}" "./${programs[i]}") > "$log" 2>&1
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
    if [[ -n $heap ]]; then
        [[ -f $heap ]] || fail_gate 1 heap "$entry did not write its heaptrc log."
        cat -- "$heap" || fail_gate 3 log "Cannot read $heap"
        heap_summary=$(grep -E '^[0-9]+ unfreed memory blocks' "$heap") ||
            fail_gate 1 heap "$entry did not report an unfreed block count."
        [[ $heap_summary =~ ^0\ unfreed\ memory\ blocks([[:blank:]]*:[[:blank:]]*0)?[[:space:]]*$ ]] ||
            fail_gate 1 heap "$entry did not report exactly one zero-unfreed heaptrc summary."
    fi
done

printf 'ROSTER_GATE_VERIFIED %s %s\n' "$gate_name" "$total"
printf 'LINUX GATE PASSED (%s, %s tests)\n' "$lane" "$total"

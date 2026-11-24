#!/usr/bin/env bash
set -eu

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT
mkdir -- "$scratch/unit" "$scratch/stress"

make_stub() {
    local path=$1 entry=$2 scenario=$3 line n=0 failed=0 errored=0 ignored=0
    local -a names=()
    while IFS= read -r line || [[ -n $line ]]; do
        line=${line#$'\xef\xbb\xbf'}
        line=${line%$'\r'}
        if [[ -n $line && $line != \#* ]]; then
            names+=("$line")
        fi
    done < "$repo/tests/rosters/$entry.txt"
    local count=${#names[@]}
    local receipt_expected=$count receipt_found=$count receipt_passed=$count
    case "$scenario" in
        failed) failed=1 ;;
        errored) errored=1 ;;
        ignored) ignored=1 ;;
        receipt-passed|contradictory-receipt) receipt_passed=0 ;;
        receipt-expected) receipt_expected=$((count + 1)) ;;
        receipt-found) receipt_found=$((count - 1)) ;;
    esac
    {
        printf '#!/bin/bash\n'
        if [[ $scenario == exit ]]; then
            printf 'exit 1\n'
        elif [[ $scenario == timeout ]]; then
            printf 'sleep 10\n'
        fi
        if [[ $scenario == coloured ]]; then
            printf 'printf "%%s\\n" %q\n' \
                $'\033[0m\033[1m'"Tests Found   : $count" \
                $'\033[0m''Tests Ignored : 0' \
                $'\033[0m\033[1m\033[32m'"Tests Passed  : $count" \
                $'\033[0m''Tests Leaked  : 0' \
                $'\033[0m''Tests Failed  : 0' \
                $'\033[0m''Tests Errored : 0'
        else
            printf "printf '%%s\\n' 'Tests Found : %d' 'Tests Passed : %d' 'Tests Failed : %d' 'Tests Ignored : %d'\n" \
                "$count" "$count" "$failed" "$ignored"
            if [[ $scenario != missing-summary ]]; then
                printf "printf '%%s\\n' 'Tests Errored : %d'\n" "$errored"
            fi
        fi
        if [[ $scenario == invalid-receipt ]]; then
            printf "printf '%%s\\n' 'ROSTER_VERIFIED %s nonsense'\n" "$entry"
        else
            printf "printf '%%s\\n' 'ROSTER_VERIFIED %s expected=%d found=%d passed=%d'\n" \
                "$entry" "$receipt_expected" "$receipt_found" "$receipt_passed"
        fi
        if [[ $scenario == rejection || $scenario == contradictory-receipt ]]; then
            printf "printf '%%s\\n' 'ROSTER_REJECTED reason=missing detail=fixture reported an incomplete execution'\n"
        fi
        for line in "${names[@]}"; do
            ((n += 1))
            if [[ $scenario == missing && $n == 1 ]]; then
                continue
            fi
            if [[ $scenario == duplicate && $n == 2 ]]; then
                line=${names[0]}
            fi
            printf 'printf "%%s\\n" %q\n' "ROSTER_TEST $line"
        done
    } > "$path"
    chmod +x -- "$path"
}

make_stub "$scratch/stress/maxCronStressTests" DelphiLinuxStress pass
failures=0
check() {
    local scenario=$1 expected=$2 root="$scratch/runs" actual=0 output
    local reason='^(ROSTER_REJECTED reason=|LINUX GATE FAILED reason=)'
    shift 2
    make_stub "$scratch/unit/maxCronTests" DelphiLinuxUnit "$scenario"
    if [[ $scenario == relative ]]; then
        root=relative-output
    fi
    env -u MAXCRON_LONG_TESTS MAXCRON_LINUX_PREBUILT="$scratch" MAXCRON_ROSTER_OUT="$root" \
        MAXCRON_LINUX_TIMEOUT_SECONDS=2 bash "$repo/build-and-run-tests-linux.sh" delphi "$@" \
        > "$scratch/$scenario.log" 2>&1 || actual=$?
    if [[ $actual != "$expected" ]]; then
        cat -- "$scratch/$scenario.log"
        printf 'FAIL %s expected=%s actual=%s\n' "$scenario" "$expected" "$actual" >&2
        ((failures += 1))
        return
    fi
    case "$scenario" in
        missing-summary) reason='^LINUX GATE FAILED reason=summary ' ;;
        receipt-*|invalid-receipt) reason='^ROSTER_REJECTED reason=count detail=.*ROSTER_VERIFIED' ;;
        rejection|contradictory-receipt) reason='^ROSTER_REJECTED reason=count detail=.*ROSTER_REJECTED' ;;
    esac
    if [[ $expected != 0 ]] && ! grep -Eq "$reason" "$scratch/$scenario.log"; then
        cat -- "$scratch/$scenario.log"
        printf 'FAIL %s did not report the expected failure reason\n' "$scenario" >&2
        ((failures += 1))
        return
    fi
    if [[ $scenario == coloured ]]; then
        IFS= read -r output < "$scratch/$scenario.log"
        if [[ $output != 'LINUX GATE OUTPUT '* ]] ||
            ! grep -Fq $'\033[0m\033[1mTests Found' "${output#LINUX GATE OUTPUT }/unit/run.log"; then
            printf 'FAIL %s did not preserve the raw coloured transcript\n' "$scenario" >&2
            ((failures += 1))
            return
        fi
    fi
    printf 'PASS %s exit=%s\n' "$scenario" "$actual"
}

check pass 0
check coloured 0
check missing-summary 1
check missing 5
check duplicate 5
check receipt-passed 5
check receipt-expected 5
check receipt-found 5
check rejection 5
check contradictory-receipt 5
check invalid-receipt 5
check exit 1
check failed 1
check errored 1
check ignored 1
check timeout 124
check arguments 5 extra
check relative 2
((failures == 0))

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
            if [[ $scenario == renamed && $n == 1 ]]; then
                line=TestRenamed.Fixture.Method
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

mkdir -- "$scratch/tests" "$scratch/smoke" "$scratch/smoke-heaptrc" "$scratch/tool"
make_stub "$scratch/smoke/maxCronFpcSmoke" FpcSmoke pass

check_fpc() {
    local scenario=$1 expected=$2 reason=$3 actual=0
    shift 3
    "$@" > "$scratch/fpc-$scenario.log" 2>&1 || actual=$?
    if [[ $actual != "$expected" ]] || ! grep -Eq "$reason" "$scratch/fpc-$scenario.log"; then
        cat -- "$scratch/fpc-$scenario.log"
        printf 'FAIL fpc-%s expected=%s actual=%s\n' "$scenario" "$expected" "$actual" >&2
        ((failures += 1))
        return
    fi
    printf 'PASS fpc-%s exit=%s\n' "$scenario" "$actual"
}

fpc_gate=(bash "$repo/build-and-run-tests-linux.sh" fpc)
fpc_prebuilt=(env -u MAXCRON_LONG_TESTS -u MAXCRON_FPC
    MAXCRON_LINUX_PREBUILT="$scratch" MAXCRON_FPC_OUT="$scratch/runs"
    MAXCRON_LINUX_TIMEOUT_SECONDS=2 "${fpc_gate[@]}")
write_heap_summary() {
    printf '%s\n' '[[ $HEAPTRC == log=child.heaptrc.log ]] || exit 1' \
        "printf '%s\\n' '$2 unfreed memory blocks' > child.heaptrc.log" >> "$1"
}

make_stub "$scratch/tests/maxCronFpcTests" FpcLinux pass
write_heap_summary "$scratch/tests/maxCronFpcTests" 0
make_stub "$scratch/smoke-heaptrc/maxCronFpcSmoke" FpcSmokeHeap pass
check_fpc no-heap-receipt 1 '^LINUX GATE FAILED reason=heap .*FpcSmokeHeap' "${fpc_prebuilt[@]}"
write_heap_summary "$scratch/smoke-heaptrc/maxCronFpcSmoke" 1
check_fpc heap-leak 1 '^LINUX GATE FAILED reason=heap .*FpcSmokeHeap' "${fpc_prebuilt[@]}"
make_stub "$scratch/smoke-heaptrc/maxCronFpcSmoke" FpcSmokeHeap pass
write_heap_summary "$scratch/smoke-heaptrc/maxCronFpcSmoke" 0
check_fpc pass 0 '^ROSTER_GATE_VERIFIED FpcLinuxGate [1-9][0-9]*$' "${fpc_prebuilt[@]}"
make_stub "$scratch/tests/maxCronFpcTests" FpcLinux duplicate
check_fpc duplicate 5 '^ROSTER_REJECTED reason=duplicate ' "${fpc_prebuilt[@]}"
make_stub "$scratch/tests/maxCronFpcTests" FpcLinux renamed
check_fpc renamed 5 '^ROSTER_REJECTED reason=renamed ' "${fpc_prebuilt[@]}"

cat > "$scratch/tool/fpc" <<'EOF'
#!/bin/bash
case "${!#}" in
    -iV) printf '%s\n' '3.3.0' ;;
    -iTO) printf '%s\n' 'win64' ;;
    -iTP) printf '%s\n' 'i386' ;;
    *) exit 99 ;;
esac
EOF
chmod +x -- "$scratch/tool/fpc"
: > "$scratch/tool/fpc.cfg"
tool_root="$scratch/tool-runs"
fpc_tool=(env -u MAXCRON_LINUX_PREBUILT MAXCRON_FPC="$scratch/tool/fpc"
    MAXCRON_FPC_OUT="$tool_root" "${fpc_gate[@]}")
check_fpc wrong-version 2 '^LINUX GATE FAILED reason=configuration .*3\.3\.1.*3\.3\.0' "${fpc_tool[@]}"
sed -i 's/3\.3\.0/3.3.1/' "$scratch/tool/fpc"
check_fpc wrong-target 2 '^LINUX GATE FAILED reason=configuration .*linux.*win64' "${fpc_tool[@]}"
sed -i 's/win64/linux/' "$scratch/tool/fpc"
check_fpc wrong-cpu 2 '^LINUX GATE FAILED reason=configuration .*x86_64.*i386' "${fpc_tool[@]}"
if [[ -e $tool_root ]]; then
    printf 'FAIL fpc-tool-check allocated an output directory\n' >&2
    ((failures += 1))
fi
sed -i -e 's/i386/x86_64/' -e 's/exit 99/exit 0/' "$scratch/tool/fpc"
check_fpc missing-build-output 3 '^LINUX GATE FAILED reason=build .*check-public/maxCronFpcCompileCheck.*native exit 0' "${fpc_tool[@]}"
((failures == 0))

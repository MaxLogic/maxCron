# Developing maxCron

This file is for working on maxCron itself: test gates, the Free Pascal gate and the
benchmarks. Using the library needs only [README.md](README.md).

## Tests

DUnitX tests live under `tests/` (runner: `tests/maxCronTests.dpr`).

### Linux gate

Run `./build-and-run-tests-linux.sh <lane>` from the repository root. The
certified default runs on x86_64 WSL had the following counts.

| Lane | What it runs | Tests passed |
| --- | --- | ---: |
| `delphi` | Delphi Linux64 unit and stress suites | 563 |
| `fpc` | Native FPC x86_64 suite and both smokes | 445 |
| `fpc-aarch64` | FPC aarch64 suite and both smokes under qemu-user | 445 |

The `delphi` lane builds on Windows from WSL and runs in Linux. Set
`MAXCRON_ROSTER_OUT` to choose its Linux output root. `MAXCRON_BUILD_ROOT`,
`MAXCRON_DCCLINUX64` and `MAXCRON_LINUX_SDK` are Windows paths for the build
root, compiler and SDK. DUnitX's leak counter is inactive on Linux, so the
`delphi` lane cannot detect memory leaks. The Windows Delphi gates and the
FPC heaptrc entries provide leak coverage.

Set `MAXCRON_FPC` to the Linux x86_64 FPC 3.3.1 driver, with `fpc.cfg` beside
it. `MAXCRON_FPC_OUT` chooses the Linux output root for both FPC lanes.
Both `MAXCRON_ROSTER_OUT` and `MAXCRON_FPC_OUT` require absolute Linux paths.
The gate exits with code 2 for a relative output root. The default is
`~/dev-artifacts/runs/maxCron`.

The `fpc-aarch64` lane also needs `ppcrossa64` and aarch64 RTL units from the
same FPC installation, `qemu-aarch64` on `PATH` and `aarch64-linux-gnu-`
binutils. `MAXCRON_AARCH64_SYSROOT` defaults to `/usr/aarch64-linux-gnu`.
The gate looks for both GCC startup objects in the sysroot's `lib` directory
first, then in installed cross GCC directories. On Ubuntu 26.04 they come
from `libgcc-15-dev-arm64-cross`. Emulated runners get four times the normal
timeout.

`MAXCRON_LONG_TESTS=1` selects the long suite for `delphi` and `fpc` and is
rejected by `fpc-aarch64`. The certified long runs passed 531 Delphi tests and
445 FPC tests. Each ran the full 2000-2040 glibc LOCAL comparison with
about 467 million checks and zero mismatches; the exact count depends on the
installed tzdata (467,273,246 with tzdata 2026f).

`MAXCRON_DEBUG_SAFETY=1` selects a Delphi Debug build or enables FPC runtime
checks. The lanes pass through `MAXCRON_STRESS`.
`MAXCRON_LINUX_TIMEOUT_SECONDS` overrides each runner's timeout directly.
`MAXCRON_LINUX_PREBUILT` trusts the supplied lane layout and runs it without
rebuilding. Use it only with binaries produced by a gate run of the same commit,
and verify their hashes before running. For a default `delphi` run, point it
at the directory containing `unit` and `stress`. For `fpc`, use the directory
containing `tests`, `smoke` and `smoke-heaptrc`.
Tests that cannot run on Linux are listed in `tests/linux/LinuxExcluded.txt`.

### Windows gates

The `build-and-run-tests.bat` and `build-and-run-tests-stress.bat` gates (and
their WSL `.sh` wrappers) require Delphi 12 (23.0) and DelphiAIKit. They build
the demo and all three test runners for Win32, then run the tests, forwarding
arguments and returning nonzero on a missing tool, build error, or test failure.
Set `DAK_EXE` to the absolute Windows path of `DelphiAIKit.exe` for the process
running the gate; otherwise the scripts search `PATH`, then
`..\..\DelphiAiKit\bin\DelphiAIKit.exe` relative to the scripts. An invalid
explicit override fails immediately. No persistent environment setting is needed.
For a `DAK_EXE` override exported inside WSL, add `DAK_EXE/w` to `WSLENV` so it
reaches Windows. The Delphi projects select the binary output paths. Roster gate
logs go under `<build-root>\roster-gates` when `MAXCRON_BUILD_ROOT` is set, or
`%TEMP%\maxCron-roster-gates` otherwise. `MAXCRON_ROSTER_OUT` takes precedence.
Release is the default. `MAXCRON_DEBUG_SAFETY=1` selects Debug.
Default gates keep all curated UTC/DST regressions and the repeated-hour restore
reviewer cases, plus deterministic matrix samples (seed `20261118`).

Run `./build-and-run-tests-long.sh` (or `build-and-run-tests-long.bat`) whenever
time-zone, search, restore or dispatch code changes, and before qualifying a
release that includes such changes. It rebuilds the same unit runner with
`MAXCRON_LONG_TESTS`: full fake/TZif host matrices on scan, heap and shadow,
all 1,584 deferred validity rows, full restore matrices, every-second fast/walk
equivalence and minute-by-minute probe/mapping/consumer walks. No test is skipped.
Default Windows RTL checks cover every host transition in 2000-2040 at
T-1 s, T and T+1 s, gap edges, both repeated-hour instances and one UTC
sample per day (seed `20261118`). The full probe-over-RTL comparison for
2000-2040 runs unchanged in long qualification.

Use `./build-and-run-tests-long.sh fpc` for the equivalent FPC qualification,
and set `MAXCRON_LONG_PLATFORM=Win64` for Delphi Win64 (Win32 is the default).
The Delphi long gate uses `<build-root>\long` when `MAXCRON_BUILD_ROOT` is set,
or `%TEMP%\maxCron-long` otherwise. `MAXCRON_LONG_OUT` takes precedence. Long and
default binaries use separate outputs.

Every test runner checks complete executed identities, including case names,
against its checked-in manifest. `tests/rosters/` contains separate Delphi
unit, stress, VCL and long rosters, FPC default and long rosters, an explicit
FPC-only list, and both FPC smoke rosters. `tests/LongTests.txt` is the
compatibility copy of the Delphi long roster. Missing, renamed, extra,
duplicated or filtered tests fail. Source hashes also reject stale test sources,
including `TestFpcShims.pas`, included `.inc` vectors, and every checked-in
corpus or fixture under `tests/data`. The dependency set is conservative across
the runners, so changing any of those inputs requires an explicit refresh:

```powershell
$env:MAXCRON_FPC = '<fpc-root>\bin\x86_64-win64\fpc.exe'
./tests/Export-TestRosters.ps1 -Compiler '<Delphi bin>/dcc64.exe' `
  -DUnitXSource '<DUnitX>/Source' -OutputRoot '<external discovery output>'
```

The exporter uses native DUnitX discovery, native FPC registration and the real
smoke checks; gates never regenerate manifests. Review identity changes before
accepting them. The FPC gate also checks the union of its Delphi shared list and
explicit FPC-only list. Combined gate manifests also pin every child run, with
entry prefixes distinguishing the normal and heap smoke identities. The Delphi
default wrappers execute the child roster declared by their combined manifest.
Run binaries from the checkout, or set `MAXCRON_TEST_ROOT`
to it when using external build outputs. Test selectors are rejected; Delphi
default runners still accept quiet console formatting.
`tests/RosterContract.Tests.ps1` runs native membership regressions through all
default/long wrappers, runners and smokes, for shared and FPC-only fixture
families, including controls with current source hashes and unchanged expected
names. It requires `ScratchRoot`, `Compiler` and `DUnitXSource` parameters.
Before the full matrix, run the setup preflight:

```powershell
python -X utf8=0 tests/roster_contract_regression.py --repository . `
  --scratch '<fresh external output>' --compiler '<Delphi bin>/dcc64.exe' `
  --dunitx '<DUnitX>/Source' --setup-only --contract-variant enabled
```

Repeat with `--contract-variant disabled` and a different fresh output directory.
Each preflight discovers the roster, runs two positive controls, checks WSL
startup and script syntax, and compiles all 72 distinct native fixture forms
with Delphi Win32/Win64 and FPC.
The disabled variant removes roster guards only in negative-case copies;
discovery and positive controls keep the contract enabled. The preflight writes
`setup.json` and subprocess receipts. Both preflights must pass before the full
RED and GREEN matrix runs; compilation failure is infrastructure failure.

`tests/roster_source_regression.py` additionally changes every include/data input
in an owned copy and checks stale rejection through the native and wrapper
manifest loaders. Build failures abort the membership matrix; they never count
as rejected test selections.
FPC continues to use fresh directories under `MAXCRON_FPC_OUT`.
Long qualification accepts no test-selection arguments (apart from the `fpc`
routing token). Empty, partial, ignored or failed runs return nonzero; Delphi
and FPC check execution against their complete discovered/generated rosters.

Roster contract violations use reserved exit code 5 and one fixed
`ROSTER_REJECTED reason=... detail=...` verdict. Only the roster comparison
helpers can originate that result. Build, generator, parity and runner phases
record their native completion codes; infrastructure failures never count as
roster rejection. The matrix requires the expected verdict reason and owner,
with every preceding phase successful. It refreshes unchanged source stamps
on every route under a non-UTF-8 locale, preserving UTF-8 BOM identities.
`tests/RosterHarness.Tests.ps1` covers the native compiler, generator and parity
failure reproductions, plus the table of compiler, linker, generator, parity,
runner and roster-helper failures (nonzero exit, crash, timeout and misleading
output).

The roster contract guards against accidental false success, including stale or
incomplete test inventories and failed tools. Test definitions, native runners
and gate scripts are trusted project code. Deliberately modifying a runner or
helper to forge or replay a verdict is outside this threat model.

#### Test exit codes and propagation

These tables describe a successfully started wrapper or native program. The
paired Windows `.sh` and `.bat` entry points use the same gate and exit codes.

| Entry point | Success | Ordinary test or infrastructure failure | Roster violation | Timeout |
| --- | ---: | --- | ---: | ---: |
| Delphi default `build-and-run-tests.bat` / `.sh` | 0 | 3, including a native runner returning 1 or 2 | 5 | 124 |
| Linux `build-and-run-tests-linux.sh` (`delphi`, `fpc`, `fpc-aarch64`) | 0 | 1 for test or heap failure, 2 for configuration, 3 for build or infrastructure | 5 | 124 |
| Delphi stress `build-and-run-tests-stress.bat` / `.sh` | 0 | 3, including a native runner returning 1 or 2 | 5 | 124 |
| Delphi long `build-and-run-tests-long.bat` / `.sh` | 0 | 3, including build failure, native runner error 2, or invalid helper output | 5 | 124 |
| FPC gate `build-and-run-tests-fpc.bat` / `.sh` | 0 | 1 for test/heap/result failure; 2 for tool/output configuration; 3 for build, generator or parity infrastructure failure | 5 | 124 |
| FPC long `build-and-run-tests-long.bat fpc` / `.sh fpc` | 0 | The same FPC 1/2/3 meanings; preflight infrastructure failure is 3 | 5 | 124 |
| FPC smoke binaries, normal and heap variants | 0 | Native 2 for a caught test/runtime/result exception; 1 is the retained final unsuccessful-result guard. The FPC gate maps either to 1 | 5 | No internal watchdog; the FPC gate supervises them and returns 124 |

A shell, OS loader, or PowerShell startup failure before orchestration can
return its platform status instead (for example Windows 9009 or shell 126/127).
The WSL launcher rejects unsupported argument quoting/newlines with 2. Such
bootstrap failures have no roster verdict and never qualify as roster rejection.

| Native phase or result | Native completion | How the wrapper propagates it |
| --- | --- | --- |
| Tool/version/CPU/target query | 0 or the tool's native status | Recorded in its tool receipt; invalid tool/configuration maps to FPC 2; a supervised deadline returns 124 |
| Build, including compiler/linker | 0 or the tool's actual nonzero exit | Recorded in the build receipt. Failure maps to Delphi 3 or FPC 3, even if the tool itself returned 5 |
| FPC registry generator | 0; parser/generation errors normally 3; a crash retains its actual native status | Recorded in the generator receipt. A non-timeout failure maps to FPC 3; native 124 propagates as 124. Generator output cannot originate roster status 5 |
| Parity helper | 0; roster violation 5; ordinary exception 3; a crash retains its native status | Recorded in the parity receipt. Explicit roster verdict plus native 5 propagates 5; another failure maps to FPC 3, except timeout status 124 which propagates |
| Delphi native unit/stress/VCL runner | 0; caught ordinary test/runtime/result error 2; retained final unsuccessful-result guard 1; roster violation 5 | Recorded in the runner receipt. Native 1/2 or a crash maps to Delphi wrapper 3; a verified roster 5 propagates 5, and timeout 124 propagates 124 |
| FPC native test runner | 0; caught ordinary test/runtime/result error 2; retained final unsuccessful-result guard 1; roster violation 5 | Recorded in the runner receipt. Native 1/2 or a crash maps to FPC gate 1; a verified roster 5 propagates 5, and timeout 124 propagates 124 |
| Roster/source/execution check | 0 or typed roster violation 5; non-contract exceptions remain native 2 or PowerShell helper 3 | Only this comparison code originates 5, immediately preceded by its check receipt and accompanied by one fixed verdict. A wrapper propagates 5 only after checking that result; arbitrary native 5 without the verdict is infrastructure failure |
| Ordinary test failure | Usually native 2 through the current result checker; final unsuccessful-result guards retain 1 | Delphi wrappers return 3; the FPC gate returns 1. It is not a roster verdict |
| Other infrastructure failure | The producer's nonzero status is retained in its phase receipt | Delphi orchestration maps it to 3; FPC uses the current configuration/build/test stage's 2/3/1. No roster status is synthesized |
| Phase deadline | The killed process's actual native exit remains in the receipt, which can be 0 if it exited but left a child holding a pipe | The supervising wrapper returns 124; enclosing wrappers preserve 124. Timeout never becomes 5 |

For example, Delphi native runner 2 becomes Delphi wrapper 3. A generator
returning 37 remains 37 in its receipt and becomes FPC wrapper 3. A genuine
parity violation returns native 5 with its verdict and becomes wrapper 5. Child
124 is preserved by runner/helper propagation; compiler/query nonzero statuses
still use the build/configuration mapping unless the supervising deadline
itself expired.

#### Production phase deadlines

Deadlines cover both process completion and draining redirected output, using
a monotonic clock. Every supervised Windows child starts suspended and joins
a Job Object with `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE` before it can execute.
On expiry the gate terminates the job, including descendants whose parents
have exited, allows up to 10 seconds to confirm the job is empty, and allows
up to 5 seconds to finish its asynchronous stdout/stderr reads. It records
the native status and returns 124. Incomplete termination or stream draining
is recorded as `ROSTER_TIMEOUT_INCOMPLETE` and still returns 124, never success
or roster status 5. Directly launching a native executable supplies no internal
watchdog; use the wrappers for supervision.

Windows Job Objects do not own processes inside the WSL virtual machine.
Terminating `wsl.exe` stops the foreground Linux probe, but a detached Linux
process can survive. The `.sh` routes delegate builds and tests to the
supervised Windows wrappers; this timeout guarantee covers their Windows
children. Linux work added to those routes needs its own Linux deadline and
cleanup. Killing the WSL client alone is not a guarantee for detached Linux
descendants.

| Phase | Deadline |
| --- | --- |
| Compiler version/CPU/target queries | 2 minutes each |
| Build, including compiler/linker | 30 minutes each |
| Registry generator, parity and ordinary roster/preflight helpers | 10 minutes each |
| Default Delphi/FPC test runner | 2 hours each |
| FPC smoke or heap smoke | 10 minutes each |
| Exhaustive Delphi/FPC long test runner | 48 hours each |
| Enclosing Delphi default/stress three-runner gate | 8 hours |

These are hang limits, not timing acceptance thresholds. The default unit
wrapper must still finish within 10 minutes on the qualification machine. The
48-hour long-run cap is deliberately conservative: the earlier long Win32 run
was cancelled after hours, so a completed full-run baseline is not yet available.

The maxCron syntax corpus is stored in `tests/data/cron-valid.txt`.

Our upstream-derived cron corpus used by tests is stored in `tests/data/cron-utils-unix-5field.txt`.
Negative corpus (expected to fail parse) is stored in `tests/data/cron-invalid.txt`.

Optional runners:
- `tests/maxCronVclTests.dpr` (GUI/VCL message pump; tests `ctVcl` / `ctAuto` behavior)
- `tests/maxCronStressTests.dpr` (heavier concurrency stress tests; ~30s)
- `tests/run-long-soak.sh` (cross-mode logical soak harness with report artifact output)

### Oracle fuzz and chaos fixtures

We can run the deterministic cron fuzz-oracle fixture (dialect/day-match combinations with brute-force oracle comparison):

```bash
tests/maxCronTests.exe --consolemode:quiet
```

Replay knobs:
- `MAXCRON_FUZZ_SEED` (default `137031`)
- `MAXCRON_FUZZ_CASES` (default `36` per dialect/day-match combination)
- `MAXCRON_FUZZ_OCCURRENCES` (default `6`)
- `MAXCRON_FUZZ_SCAN_SECONDS` (default `604800`, existing forward oracle)
- `MAXCRON_FUZZ_SCAN_DAYS` (default `3700`, day-pruned query oracle)

The fixture also runs `PreviousOccurrences_MatchBruteForceOracle`,
`ModifierPlans_NextAndPrevious_MatchBruteForceOracle`,
`Between_MatchBruteForceOracle` and `Properties_NextPreviousRelations`.
These cover previous/range queries, independent DOM/DOW modifier rules,
hashed fields and restricted years. Each uses its own seed offset (1 through 4),
leaving the existing forward oracle's random stream unchanged.

We can run async-boundary chaos coverage (queue-acquire injection, dispatch-start failure, callback exceptions, cancellation races):

```bash
tests/maxCronTests.exe --consolemode:quiet
```

### Long soak harness (24h logical window)

The long-soak harness drives a mixed workload across `scan`, `heap`, and `auto` and writes a report artifact under `tests/__recovery/soak-reports/`.

```bash
MAXCRON_LONG_SOAK_HOURS=24 ./tests/run-long-soak.sh --modes=scan,heap,auto --cm:Quiet
```

Useful options:
- `--modes=scan,heap,auto` to select engines.
- `--hours=N` to override the logical soak window (defaults to `MAXCRON_LONG_SOAK_HOURS` or `24`).

The harness executes the complete default rosters, including
`TestLongSoak24h.EngineModes_LogicalSoak_NoMisses`, which validates:
- no callback loss/duplication envelope violations per mode,
- auto-mode switch envelope bounds,
- report artifact generation with full console output and exit code.

### Debug-safety lane

Use `MAXCRON_DEBUG_SAFETY=1` to run the canonical test scripts in `Debug` configuration (range/overflow/assert checks and leak diagnostics enabled by our test runners):

```bash
MAXCRON_DEBUG_SAFETY=1 ./build-and-run-tests.sh -cm:Quiet
MAXCRON_DEBUG_SAFETY=1 ./build-and-run-tests-stress.sh -cm:Quiet
```


Queued main-thread pre-acquire failure regressions use `SetMaxCronBeforeQueuedAcquireHook`; injected failures roll back state and exit the queued path without rethrowing through `CheckSynchronize`.

### Test hooks

Under `MAXCRON_TESTS`, the portable timer does not start automatically.
`StartTimerForTests` starts it and selects the maximum sleep duration,
clamped to 1..1000 ms. Explicit `TickAt` calls remain direct cron passes using the millisecond carrier rule;
`TickAtUs` accepts exact wall-clock microseconds.

## Free Pascal gate

The tested FPC RTL pool can double-free a worker at process exit under `heaptrc`
(see the README). The all-mode smoke therefore runs without heap tracing. The
deterministic suite and the `imMainThread`/`imThread` smoke run with heap tracing
and require zero unfreed blocks. This split does not fix the RTL exit race.

Run `build-and-run-tests-fpc.bat` from Windows, or
`./build-and-run-tests-fpc.sh` from WSL (Bash, `wslpath`, and Python 3 for command-line
test arguments). The batch file is a fixed PowerShell 5.1 launcher; the WSL wrapper
invokes the same PowerShell gate directly. Neither passes settings through cmd.
The gate verifies the compiler version and target before building.
Set `MAXCRON_FPC` to the absolute Windows path to `fpc.exe` for the gate,
roster export and Python roster regressions. The scripts use `fpc.cfg` and
compiler tools beside that executable. For `<fpc-root>\bin\x86_64-win64\fpc.exe`,
they search `<fpc-root>\units\x86_64-win64\*` for units. A missing setting or
executable is a configuration error.

Set `MAXCRON_BUILD_ROOT` to a Windows directory for persistent gate outputs.
The FPC gate uses `<build-root>\fpc` or `%TEMP%\maxCron-fpc` if the build root
is unset. `MAXCRON_FPC_OUT` takes precedence over both. Each invocation creates a new
`run-<GUID>` directory under that root, fails if the name already exists, checks
its final Windows path identity and writes all build/test outputs below it.
Pre-existing output children are never reused. The printed `FPC OUTPUT` line
identifies the run directory. No WSL bridge launcher files are created.

Settings are literal environment strings. Values are never expanded or evaluated.
Supported output path characters are ASCII letters, digits, space and
`\ : . _ - +` only. Every other character, including non-ASCII characters and
shell metacharacters, is rejected with exit 2 before any output directory is
created. Colons outside the drive prefix and components ending in a space or dot
are also rejected. Normal `.` and `..` components are resolved before validation.
The batch launcher accepts no command-line arguments. WSL arguments are encoded
as a JSON array in `MAXCRON_FPC_ARGS` and passed directly to the native runner as
an argument array. The current runner rejects all test filters; run the full suite.

Every child process runs in the new run directory with an explicit environment:
`SystemRoot`, `windir`, run-local `TEMP`/`TMP`, and a `PATH` limited to the
toolchain and Windows system directories. The gate defines `MAXCRON_TEST_ROOT`
to the validated absolute repository directory for read-only fixture lookup.
Shared tests keep their existing lookup when this variable is unset.
The gate always sets `HEAPTRC` to a
log file inside the run directory, ignoring inherited settings. Mandatory heap
checks read those files. `child-processes.jsonl` records each direct launch.

Threat model: protects against misconfiguration and pre-existing links/aliases
(junction, symlink, SUBST, case/trailing forms) at the root, any ancestor and any
child; it does not defend against a concurrent malicious process replacing
directories during the run. Existing directory ancestors must resolve to a
Windows volume identity; inaccessible or unsupported destinations fail closed.
`MAXCRON_DEBUG_SAFETY=1` enables range, overflow, stack and I/O checks.
For WSL, supply Windows paths for `MAXCRON_FPC`, `MAXCRON_BUILD_ROOT` and
`MAXCRON_FPC_OUT`. The wrapper transfers them to Windows using `WSLENV`.
When invoking WSL from Windows, append those names to `WSLENV` so the values
reach WSL. Use `WSLENV` without the `/p` flag for Windows path values.

The FPC runner reuses the calculation, corpus, fuzz/oracle, interval-plan,
deadline queue, TZif/zone, text, time-boundary and deterministic scheduler tests.
Registration is generated from their DUnitX attributes. Timing, stress,
invoke-mode, lifecycle, VCL and soak suites remain Delphi tests; the FPC smoke
checks add/run/fire/shutdown in all four invoke modes. The gate exits 0 only
after all builds, tests, smokes and required heap checks pass. Its exit codes
are 1 for test/heap failure, 2 for tool/output configuration, 3 for build/helper
infrastructure failure, 5 for a roster violation, and 124 for a phase timeout.
The complete wrapper and native-phase propagation tables are in
[Test exit codes and propagation](#test-exit-codes-and-propagation).

The registry generator follows nested `IFDEF`/`IFNDEF`/`ELSE`/`ENDIF` branches for
the fixed FPC Windows x64 test environment and accepts inline fixture attributes.
Unsupported conditions or fixture/test declarations fail with exit 3. The gate
also compares generated test names per shared fixture with the real Delphi DUnitX
discovery snapshot in `tests/fpc/DelphiSharedTests.txt`. Its source hashes make a
shared-fixture edit fail until the snapshot is refreshed; equal counts with
different names also fail. The only exclusions are the three FPC shim tests and
the Delphi-only `MatchesRtlLocal` test.

After editing a shared fixture, regenerate that snapshot with
`tests/fpc/Export-DelphiTestNames.ps1 -Compiler <dcc64.exe> -DUnitXSource <DUnitX-source-directory> -OutputRoot <external-build-directory>`
under PowerShell. This compiles a discovery tool using the installed Delphi
compiler and records actual DUnitX names with their source hashes. Review the
snapshot diff alongside the test changes. Focused generator, alias and parity
regressions are in `tests/fpc/FpcGate.Tests.ps1` (Pester 5); pass `Generator` and an
owned external `ScratchRoot` using `New-PesterContainer -Data`. The generated
alias-layout and literal-path invariants and Delphi attribute-layout discovery comparison are in
`tests/fpc/gate_invariants.py` (Windows Python 3.12+, `--help`). Keep its fixtures under
an owned external output root and clean them with the bounded link-fixture helper.

## Benchmarks

High-N benchmark coverage (`TestHeavyStressMixed.EngineBenchmark_ScanVsHeap_HighN`) uses 1200 far-future events and 40 ticks:

- `scan`: 48,000 candidate visits (`1200 * 40`).
- `heap`: 1,200 candidate visits (single rebuild, then no due pops).

This benchmark demonstrates the expected behavior: heap mode keeps tick work growth bounded by due events (`k`) instead of total events (`n`) on sparse schedules.

Additional benchmark scenarios (stress runner):

- `TestHeavyStressMixed.EngineBenchmark_AutoVsScan_SparseHighN`
  - Scenario: sparse high-cardinality workload (`auto` vs `scan`).
  - Expected: `auto` should reduce candidate work significantly versus `scan` after adaptive promotion.
- `TestHeavyStressMixed.EngineBenchmark_AutoSwitchBudget_AdversarialChurn`
  - Scenario: adversarial oscillation pressure (`auto` with budget disabled vs enabled).
  - Expected: budget-enabled run should show lower switch count, fewer rebuilds, and lower candidate work; elapsed time should improve or remain competitive.

Run these scenarios as part of the complete stress roster:

```cmd
set MAXCRON_STRESS=1
tests\maxCronStressTests.exe
```

### Standalone benchmark runner (CSV + Markdown)

For machine-to-machine and run-to-run tracking, we can run a standalone non-DUnit benchmark executable:

```bash
./build-and-run-benchmarks.sh --iterations=9 --warmup=2 --out-dir=benchmarks/results
```

Direct Windows invocation:

```cmd
benchmarks\maxCronBenchmarks.exe --iterations=9 --warmup=2 --out-dir=benchmarks\results
```

Compare a fresh run against a baseline CSV (run-to-run deltas in console + Markdown):

```cmd
benchmarks\maxCronBenchmarks.exe --iterations=3 --warmup=0 --compare=benchmarks\results\maxcron-benchmarks-20260223-214451.csv --out-dir=benchmarks\results --quiet
```

Output files:

- `maxcron-benchmarks-*.csv` (raw per-iteration metrics)
- `maxcron-benchmarks-*.md` (scenario means and comparison deltas)

The runner includes these scenarios:

- `sparse_high_n_scan` (`MAXCRON_ENGINE=scan`)
- `sparse_high_n_heap` (`MAXCRON_ENGINE=heap`)
- `sparse_high_n_auto` (`MAXCRON_ENGINE=auto`, sparse-tuned controller)
- `adversarial_auto_no_budget` (`MAXCRON_ENGINE=auto`, budget disabled)
- `adversarial_auto_budget` (`MAXCRON_ENGINE=auto`, budget enabled)

Interpretation rules:

- Sparse workloads: expect `heap` and `auto` to reduce candidate visits versus `scan`.
- Adversarial churn: expect `budget` mode to reduce switch/rebuild/visited metrics versus no-budget mode.
- Timing summaries include mean/median/p95/stddev to expose both central tendency and jitter.
- Elapsed time is environment-sensitive; use it with the structural work metrics (`visited`, `rebuilds`, `switches`) for robust conclusions.

### Real-time idle CPU and firing latency

The additive `idle` and `latency` modes exercise the portable timer in a console
process with `imThread` callbacks. The default `ticks` mode and its reports retain
their existing format. Select the engine with `MAXCRON_ENGINE`; leave adaptive
settings unset to measure the default controller. Run each configuration in a
fresh process, outside a debugger, while other CPU work is low.

For a Delphi 12 Win64 Release build with outputs outside the checkout:

```powershell
$buildDir = '<build-root>\benchmarks'
$runDir = '<run-root>'
$delphiRoot = '<delphi-root>'
New-Item -ItemType Directory -Force -Path "$buildDir\dcc64", $runDir | Out-Null
& "$delphiRoot\bin\dcc64.exe" -B -Q `
  '-DRELEASE;MAXCRON_TESTS' '-NSSystem;Winapi;System.Win;Vcl' `
  "-Ulib\MaxLogicFoundation;$delphiRoot\lib\win64\release" `
  '-Ilib\MaxLogicFoundation' "-E$buildDir" "-N0$buildDir\dcc64" `
  benchmarks\maxCronBenchmarks.dpr
$env:MAXCRON_ENGINE = 'scan' # repeat with heap and auto
& "$buildDir\maxCronBenchmarks.exe" --mode=idle --events=1000 --seconds=30 `
  --iterations=3 "--csv=$runDir\idle-1000-scan.csv"
# Repeat with --events=10000, and each engine.
& "$buildDir\maxCronBenchmarks.exe" --mode=latency --fires=60 `
  --iterations=3 "--csv=$runDir\latency-scan.csv"
```

Adjust the compiler path to the installed Delphi version. The existing benchmark
build wrapper also supports these options. Real-time modes explicitly start the
portable timer because `MAXCRON_TESTS` disables automatic timer startup in this
project. Idle mode warms up for 35 seconds before its CPU window, beyond the 30-second
Windows startup-worker retirement observed during profiling. Compare it with a
baseline using the same warm-up and timed window. The Phase 0 results below used
a two-second warm-up; rerun the baseline for comparisons with this protocol.
Latency mode warms up for two seconds; `--warmup` applies to `ticks` only.
`--seconds` defaults to 60, `--events` to 1000 and `--fires` to 60. `--iterations`
still defaults to 9. `--compare` accepts only the historical `ticks` CSV format.

Idle timing excludes event creation and shutdown, measures process user+kernel
CPU over a monotonic elapsed window, and keeps all events enabled with a due date
of 2099-01-01. `cpu_one_core_pct` is relative to one logical CPU. Divide by the
machine's logical CPU count for its share of whole-machine CPU. A zero means no
increment resolved by the counter during that window.

Latency schedules explicitly dated one-shot events, one per due second. Each
callback captures its own immutable due time before the portable timer starts,
so worker arrival order and schedule advancement cannot change attribution.
Delays above one second stay unfolded. Raw `*-fires-N.csv` files retain each due
and callback local timestamp. Median averages the middle pair and p95 uses
nearest rank. The mode fails if setup expires an occurrence or it cannot collect
the requested callbacks. Avoid DST transitions or clock changes during measurement.
This measures scheduler and dispatch latency together. Each run has `--fires`
one-shot events rather than one recurring event.

#### Linux x86_64 benchmark

Build the Linux binary on Windows with
`tests\linux\Build-DelphiLinux64.ps1 -Projects benchmarks\maxCronBenchmarks.dpr`
and run the resulting ELF binary on Linux. For interval mode on Linux, pass
`--seconds=60` to measure a 60-second window. Use `--fires=N` to request a fixed
callback count.

Interval lateness is the signed difference between callback arrival and the
scheduler's recorded due time. Each due time is rounded to the nearest slot
from the run start, with half-period ties rounded forward. Missing nominal
slots count as misses. Extra callbacks for a covered slot and callbacks due
outside the nominal slots count as duplicates. The `cIntervalMedianBounds`
table sets a 1.5 ms inclusive median bound for 10 ms and 100 ms intervals.
A bounded row passes with zero misses, zero duplicates, and a median within
the bound. Periods without a bound, including 1 ms, leave `passed` blank.
An empty duration run still writes its CSV row and exits with code 1.

Delphi 12 Linux64 Release on WSL2 (Ubuntu 26.04), THREADRIPPER, 2026-11-24.
Before timing, Windows reported 17% total CPU and WSL load averages of
1.83, 2.05, and 2.82 across 64 logical CPUs. Other work was active on the host.

| Measurement | Scan | Heap | Auto |
| --- | ---: | ---: | ---: |
| Cron lateness median / p95 / max (ms) | 0.973 / 1.489 / 1.567 | 0.995 / 1.489 / 1.602 | 1.049 / 1.513 / 1.623 |
| 1 ms interval median lateness (ms) / missed | 0.499 / 23,885 | 0.502 / 23,410 | 0.497 / 22,815 |
| Idle median CPU (ms per 30 s / % of one core) | 106.147 / 0.354% | 3.697 / 0.012% | 3.722 / 0.012% |

Cron values pool three iterations of 60 callbacks per engine. Every callback
arrived inside its due second. The historical 1 ms figures use arrival slots
to estimate lateness. They are informational and pool three 60-second runs
with 180,000 nominal slots per engine. Idle used 10,000 far-future events and
five alternating fresh processes per engine, each with a 35-second warmup and
a 30-second CPU window.

The 10 ms and 100 ms intervals were re-measured on the same host on 2026-11-25
with Delphi 12 Linux64 Release on WSL2. Windows CPU was 12-15% before launch.
WSL 1-, 5-, and 15-minute load averages moved from 2.21, 3.68, and 3.55 before
the first run to 1.60, 2.09, and 2.70 after the last run, across 64 logical CPUs.
Another lane ran `qemu-aarch64` at nice 15 during the measurement.

| Due-time lateness, median / p95 / max (ms) | Scan | Heap | Auto |
| --- | ---: | ---: | ---: |
| 10 ms interval | 0.728 / 1.186 / 5.061 | 0.699 / 1.152 / 1.985 | 0.705 / 1.149 / 3.109 |
| 100 ms interval | 0.728 / 1.179 / 2.217 | 0.7515 / 1.207 / 2.094 | 0.747 / 1.192 / 2.321 |

Each cell pools three 60-second runs per engine. Every iteration had zero
misses and duplicates and passed its 1.5 ms median bound.

#### Historical Win64 baseline

Baseline on the maintainer's workstation, 2026-11-15, Delphi 12 Win64 Release, base `024b89b`.
AMD Ryzen Threadripper PRO 3975WX, 32 cores / 64 logical CPUs, Windows 11.
Three fresh runs per row, 30-second idle windows. CPU columns show median and
min-max across runs. Background jobs were active; the retained run records include
pre-run and during-run CPU load. These figures are a shared-machine reference.

| Events | Engine | CPU ms median (min-max), 30 s | One-core CPU % median | Effective engine |
| --- | --- | --- | --- | --- |
| 1000 | scan | 0.000 (0.000-0.000) | 0.000000 | scan |
| 1000 | heap | 0.000 (0.000-0.000) | 0.000000 | heap |
| 1000 | auto | 0.000 (0.000-0.000) | 0.000000 | heap |
| 10000 | scan | 62.500 (31.250-93.750) | 0.208314 | scan |
| 10000 | heap | 0.000 (0.000-0.000) | 0.000000 | heap |
| 10000 | auto | 15.625 (15.625-46.875) | 0.052081 | heap |

Once-per-second latency, scan engine, three fresh runs of 60 one-shot events
and callbacks. Revised occurrence attribution supersedes the initial baseline:

| Run | Fires | Median ms | p95 ms | Max ms |
| --- | --- | --- | --- | --- |
| 1 | 60 | 279.500 | 977.000 | 1002.999 |
| 2 | 60 | 290.500 | 976.999 | 1009.001 |
| 3 | 60 | 321.000 | 561.000 | 578.000 |

The one-second timer is not aligned to the wall-clock second. Each fresh process
can therefore have a different latency phase. Its fixed-delay cadence can also
accumulate delay beyond one second. Use raw distributions and repeated
runs when evaluating a timer change. Pooled median/p95/max: 295.500/963.000/1009.001 ms;
2/180 callbacks exceeded one second. During these latency runs, whole-host
CPU min/median/max was 5.952/12.518/33.716 percent.
These measurements do not set a latency SLA.

### Structural perf gate (stable local signal)

Use structural ratios from benchmark CSVs to gate regressions without relying on wall-clock timing:

```bash
./scripts/check-benchmark-metrics.sh benchmarks/results/maxcron-benchmarks-*.csv
```

The script checks:

- sparse high-N `heap/scan` visited ratio
- sparse high-N `auto/scan` visited ratio
- adversarial `budget/no-budget` switch/rebuild/visited ratios
- sparse high-N `heap/scan` elapsed `p95` and `p99` ratios
- sparse high-N `auto/scan` elapsed `p95` and `p99` ratios
- adversarial `budget/no-budget` elapsed `p95` and `p99` ratios

Thresholds are configurable by env vars:

- `MAXCRON_GATE_SPARSE_HEAP_VISITED_RATIO` (default `0.25`)
- `MAXCRON_GATE_SPARSE_AUTO_VISITED_RATIO` (default `0.25`)
- `MAXCRON_GATE_BUDGET_SWITCH_RATIO` (default `1.05`)
- `MAXCRON_GATE_BUDGET_REBUILD_RATIO` (default `1.05`)
- `MAXCRON_GATE_BUDGET_VISITED_RATIO` (default `1.05`)
- `MAXCRON_GATE_SPARSE_HEAP_ELAPSED_P95_RATIO` (default `1.15`)
- `MAXCRON_GATE_SPARSE_HEAP_ELAPSED_P99_RATIO` (default `1.20`)
- `MAXCRON_GATE_SPARSE_AUTO_ELAPSED_P95_RATIO` (default `1.15`)
- `MAXCRON_GATE_SPARSE_AUTO_ELAPSED_P99_RATIO` (default `1.20`)
- `MAXCRON_GATE_BUDGET_ELAPSED_P95_RATIO` (default `1.10`)
- `MAXCRON_GATE_BUDGET_ELAPSED_P99_RATIO` (default `1.15`)

### One-command local perf gate

For on-demand local verification, we can run build + benchmark + optional baseline compare + structural gate in one command:

```bash
./scripts/perf-gate-local.sh --iterations=3 --warmup=1 --out-dir=benchmarks/results --baseline=benchmarks/results/maxcron-benchmarks-20260223-214451.csv
```

This script:

- builds `benchmarks/maxCronBenchmarks.exe`
- runs the benchmark with our selected options
- resolves generated CSV/Markdown artifact paths
- runs `scripts/check-benchmark-metrics.sh` against the generated CSV

### Local trend report generator

To inspect run-to-run behavior over recent benchmark history:

```bash
./scripts/generate-benchmark-trend-report.sh --input-dir=benchmarks/results --limit=5 --output=benchmarks/results/trend-latest.md
```

The generated markdown includes per-scenario mean metrics and elapsed/visited deltas versus the previous included run.

### Reference benchmark run

The reference run on `2026-02-23` used 15 iterations and 2 warmup iterations.

```cmd
benchmarks\maxCronBenchmarks.exe --iterations=15 --warmup=2 --out-dir=benchmarks\results --quiet
```

Reference report: `benchmarks/results/maxcron-benchmarks-20260223-214451.md`

Key results:

| Comparison | Result |
| --- | --- |
| Sparse high-N (`heap` vs `scan`) visited reduction | `98.96%` |
| Sparse high-N (`heap` vs `scan`) elapsed speedup | `141.69x` |
| Sparse high-N (`auto` vs `scan`) visited reduction | `97.92%` |
| Sparse high-N (`auto` vs `scan`) elapsed speedup | `47.10x` |
| Adversarial churn (`budget` vs `no-budget`) switch reduction | `96.67%` |
| Adversarial churn (`budget` vs `no-budget`) rebuild reduction | `96.67%` |
| Adversarial churn (`budget` vs `no-budget`) visited reduction | `32.22%` |
| Adversarial churn (`budget` vs `no-budget`) elapsed speedup | `1.04x` |

Conclusion from this run:

- `heap` is the strongest choice for sparse high-cardinality workloads.
- `auto` also delivers strong sparse-workload gains while preserving adaptive behavior.
- Switch-budget controls materially reduce oscillation overhead under adversarial churn and can improve elapsed time.

### Interval benchmark

Run `--mode=interval --interval-ms=10 --fires=500` with a Release build to measure
interval lateness and process CPU. See the [Linux x86_64 benchmark](#linux-x86_64-benchmark)
for due-slot accounting and pass criteria.

## Time zone name table

The built-in IANA-to-Windows name table in `maxCron.Internal.TimeZoneNames.inc`
is generated from Unicode CLDR data. To regenerate it from a verified CLDR
archive, run `scripts/Update-CronZoneNames.ps1 -CldrCommon <path-to-common>`;
keep the archive's `LICENSE` beside `common/`.

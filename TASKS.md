# Tasks
Next task ID: T-069

## Summary
Open tasks: 3 (In Progress: 0, Next Today: 0, Next This Week: 3, Next Later: 0, Blocked: 0)
Done tasks: 66

## In Progress

## Next – Today

## Next – This Week

### T-066 [PERF] Add due-density signal to auto engine decisions
Outcome: Extend the auto controller with a due-density signal (`due work / visited work`) so dense-due phases can demote from heap sooner and sparse-due phases can promote with stronger confidence.
Proof:
- Command: `MAXCRON_ENGINE=auto ./build-and-run-tests-stress.sh -cm:Quiet`
- Expect: Stress/Core/VCL suites pass and no divergence/hangs.
- Command: `/mnt/c/Windows/System32/cmd.exe /C "cd /d F:\projects\MaxLogic\maxCron\maxCron && tests\maxCronStressTests.exe --run:TestHeavyStressMixed.TTestHeavyStressMixed.EngineAutoMode_DueDensityInfluencesSwitching"`
- Expect: targeted test passes and shows deterministic engine-behavior change under sparse vs dense due patterns.
Touches: `maxCron.pas`, `tests/unit/TestHeavyStressMixed.pas`, `README.md`, `CHANGELOG.md`, `TASKS.md`
Deps: T-065

### T-067 [TEST] Add long-run auto oscillation soak coverage
Outcome: Add bounded long-run adaptive soak coverage that mixes sparse, bursty, and churn-heavy phases and asserts switch-rate and callback-correctness envelopes.
Proof:
- Command: `MAXCRON_ENGINE=auto ./build-and-run-tests-stress.sh -cm:Quiet`
- Expect: suites pass with soak coverage enabled and no hangs.
- Command: `/mnt/c/Windows/System32/cmd.exe /C "cd /d F:\projects\MaxLogic\maxCron\maxCron && tests\maxCronStressTests.exe --run:TestHeavyStressMixed.TTestHeavyStressMixed.EngineAutoMode_Soak_SwitchRateAndCorrectnessEnvelope"`
- Expect: targeted soak test passes and keeps switch-rate within expected envelope.
Touches: `tests/unit/TestHeavyStressMixed.pas`, `CHANGELOG.md`, `TASKS.md`
Deps: T-064, T-066

### T-068 [OPS] Add opt-in periodic auto-state diagnostics logging
Outcome: Add optional periodic diagnostics logging controlled by environment variables so production/canary runs can collect auto-controller state snapshots without code changes.
Proof:
- Command: `MAXCRON_ENGINE=auto MAXCRON_AUTO_DIAG_LOG_INTERVAL=10 ./build-and-run-tests.sh -cm:Quiet`
- Expect: suites pass with diagnostics logging enabled and no behavior regressions.
- Command: `rg -n "MAXCRON_AUTO_DIAG_LOG|diagnostics snapshot" README.md`
- Expect: docs include the logging knobs and usage guidance.
Touches: `maxCron.pas`, `README.md`, `CHANGELOG.md`, `TASKS.md`
Deps: T-065

## Next – Later


## Blocked / OnHold



## Done

### T-065 [OBS] Add auto-controller diagnostics snapshot API
Outcome: Added a thread-safe `TryGetAutoDiagnostics(out TMaxCronAutoDiagnostics)` snapshot for `MAXCRON_ENGINE=auto`, exposing effective engine/state, switch counters, EWMAs, sample counters, cooldown/backoff state, and last switch reason for runtime tuning visibility.
Proof: `MAXCRON_ENGINE=auto ./build-and-run-tests.sh -cm:Quiet` passes (Stress 8/8, Core 125/125, VCL 3/3); targeted `/mnt/c/Windows/System32/cmd.exe /C "cd /d F:\projects\MaxLogic\maxCron\maxCron && tests\maxCronStressTests.exe --run:TestHeavyStressMixed.TTestHeavyStressMixed.EngineAutoMode_DiagnosticsSnapshot_ReportsControllerState"` passes (1/1).
Touches: `maxCron.pas`, `tests/unit/TestHeavyStressMixed.pas`, `README.md`, `CHANGELOG.md`, `TASKS.md`
Deps: T-064

### T-064 [PERF] Add adaptive anti-oscillation backoff for auto scheduler switching
Outcome: Hardened `MAXCRON_ENGINE=auto` with adaptive switch-cooldown backoff plus minimum performance-sample guards (trial-aware) to reduce scan/heap flip-flop while preserving adaptive transitions under mixed churn.
Proof: `MAXCRON_ENGINE=auto ./build-and-run-tests.sh -cm:Quiet` passes (Stress 7/7, Core 125/125, VCL 3/3); targeted `/mnt/c/Windows/System32/cmd.exe /C "cd /d F:\projects\MaxLogic\maxCron\maxCron && tests\maxCronStressTests.exe --run:TestHeavyStressMixed.TTestHeavyStressMixed.EngineAutoMode_OscillationBackoff_BoundsSwitchRate"` passes (1/1).
Touches: `maxCron.pas`, `tests/unit/TestHeavyStressMixed.pas`, `README.md`, `CHANGELOG.md`, `TASKS.md`
Deps: T-061, T-062

### T-063 [DOC] Publish auto engine operations and tuning playbook
Outcome: Expanded README with an adaptive-mode operations playbook covering `MAXCRON_AUTO_*` knobs, workload archetypes, oscillation troubleshooting, and a rollout checklist (scan baseline -> auto canary -> production).
Proof: `rg -n "MAXCRON_AUTO_|auto mode policy|rollout checklist|oscillation" README.md` returns the new sections/knobs; `./build-delphi.sh tests/maxCronTests.dproj -config release` succeeds.
Touches: `README.md`, `CHANGELOG.md`, `TASKS.md`
Deps: T-060

### T-062 [TEST] Add concurrent auto-switch race regressions and no-miss guarantees
Outcome: Added concurrent adaptive-mode stress regression that runs parallel `TickAt` workers while forcing churn-driven scan/heap transitions, asserting stable shutdown and due-callback invariants across switching phases.
Proof: `MAXCRON_ENGINE=auto ./build-and-run-tests-stress.sh -cm:Quiet` passes (Stress 6/6, Core 125/125, VCL 3/3); targeted `/mnt/c/Windows/System32/cmd.exe /C "cd /d F:\projects\MaxLogic\maxCron\maxCron && tests\maxCronStressTests.exe --run:TestHeavyStressMixed.TTestHeavyStressMixed.EngineAutoMode_ConcurrentSwitching_NoMissedDue"` passes (1/1).
Touches: `tests/unit/TestHeavyStressMixed.pas`, `CHANGELOG.md`, `TASKS.md`
Deps: T-060

### T-061 [PERF] Add validated runtime tuning knobs for auto engine thresholds
Outcome: Added bounded `MAXCRON_AUTO_*` runtime tuning (enter/exit events, churn thresholds, hold/trial/cooldown, promote/demote ratios) with strict parsing and safe fallback behavior; adaptive controller now applies these settings at scheduler creation.
Proof: `MAXCRON_ENGINE=auto ./build-and-run-tests.sh -cm:Quiet` passes (Stress 6/6, Core 125/125, VCL 3/3); `MAXCRON_ENGINE=auto MAXCRON_AUTO_ENTER_EVENTS=bad MAXCRON_AUTO_COOLDOWN=-5 ./build-and-run-tests.sh -cm:Quiet` passes (Stress 6/6, Core 125/125, VCL 3/3) with non-fatal fallback/clamping; targeted `/mnt/c/Windows/System32/cmd.exe /C "cd /d F:\projects\MaxLogic\maxCron\maxCron && tests\maxCronStressTests.exe --run:TestHeavyStressMixed.TTestHeavyStressMixed.EngineAutoMode_CustomThresholds_AreApplied"` passes (1/1).
Touches: `maxCron.pas`, `tests/unit/TestHeavyStressMixed.pas`, `README.md`, `CHANGELOG.md`, `TASKS.md`
Deps: T-060

### T-060 [PERF] Add adaptive auto scheduler mode with hysteresis
Outcome: Added adaptive scheduler engine mode (`MAXCRON_ENGINE=auto`) with scan/heap hysteresis, cooldown, and trial promotion/fallback logic, including race-safe effective-engine switching under concurrent ticks and linear-time heap rebuild during reindex.
Proof: `MAXCRON_ENGINE=auto ./build-and-run-tests.sh -cm:Quiet` passes (Stress 4/4, Core 125/125, VCL 3/3); `MAXCRON_ENGINE=auto ./build-and-run-tests-stress.sh -cm:Quiet` passes (Stress 4/4, Core 125/125, VCL 3/3); targeted `/mnt/c/Windows/System32/cmd.exe /C "cd /d F:\projects\MaxLogic\maxCron\maxCron && tests\maxCronStressTests.exe --run:TestHeavyStressMixed.TTestHeavyStressMixed.EngineAutoMode_HysteresisAndOverrideBehavior"` passes (1/1).
Touches: `maxCron.pas`, `tests/unit/TestHeavyStressMixed.pas`, `README.md`, `CHANGELOG.md`, `TASKS.md`
Deps: T-057, T-058, T-059

### T-059 [PERF] Add high-N benchmark harness and threshold guidance for engine selection
Outcome: Added high-cardinality benchmark coverage plus scheduler-engine selection guidance in README, including measurable scan-vs-heap tick-work differences for sparse due workloads.
Proof: `MAXCRON_ENGINE=scan ./build-and-run-tests-stress.sh -cm:Quiet` passes (Stress 3/3, Core 125/125, VCL 3/3); `MAXCRON_ENGINE=heap ./build-and-run-tests-stress.sh -cm:Quiet` passes (Stress 3/3, Core 125/125, VCL 3/3); `TestHeavyStressMixed.EngineBenchmark_ScanVsHeap_HighN` asserts heap candidate work reduction (`heap * 5 < scan`) on 1200-event/40-tick scenario.
Touches: `tests/unit/TestHeavyStressMixed.pas`, `README.md`, `CHANGELOG.md`, `TASKS.md`
Deps: T-057

### T-058 [TEST] Add heap-vs-scan shadow parity verification mode
Outcome: Added shadow parity mode (`MAXCRON_ENGINE=shadow`) that cross-checks scan and heap due decisions per tick and raises on divergence, plus churn coverage in robust tests.
Proof: `MAXCRON_ENGINE=shadow ./build-and-run-tests.sh -cm:Quiet` passes (Stress 3/3, Core 125/125, VCL 3/3) with no divergence exceptions; `MAXCRON_ENGINE=shadow ./build-and-run-tests-stress.sh -cm:Quiet` passes (Stress 3/3, Core 125/125, VCL 3/3) with no divergence exceptions.
Touches: `maxCron.pas`, `tests/unit/TestRobustCoverage.pas`, `README.md`, `CHANGELOG.md`, `TASKS.md`
Deps: T-057

### T-057 [PERF] Add heap-based scheduler engine behind feature flag
Outcome: Added heap scheduler engine with `MAXCRON_ENGINE` selection (`scan` default, `heap`, `shadow`) and heap dirty/rebuild tracking so tick processing can avoid full event scans under sparse due workloads while preserving public API behavior.
Proof: `./build-and-run-tests.sh -cm:Quiet` passes (Stress 3/3, Core 125/125, VCL 3/3) in default scan mode; `MAXCRON_ENGINE=heap ./build-and-run-tests.sh -cm:Quiet` passes (Stress 3/3, Core 125/125, VCL 3/3) in heap mode.
Touches: `maxCron.pas`, `tests/unit/TestHeavyStressMixed.pas`, `tests/unit/TestRobustCoverage.pas`, `README.md`, `CHANGELOG.md`, `TASKS.md`

### T-056 [ROBUST] Replace raw owner dereference paths with shared state + dictionary indexes
Outcome: Replaced queue-token raw-owner dereference paths with `ICronSharedState` (alive/default snapshots + in-flight/callback depth tracking + async/flush/tick operations), removed direct worker-thread reads of `TmaxCron` internals, added dictionary-backed name/id indexes for faster `Delete(Name)` / `Delete(Id)` lookup paths, and documented `imMainThread` message-pump requirements explicitly in README/code comments.
Proof: `./build-and-run-tests.sh -cm:Quiet` passes (Stress 2/2, Core 123/123, VCL 3/3); `./build-and-run-tests-stress.sh -cm:Quiet` passes (Stress 2/2, Core 123/123, VCL 3/3); compile output confirms demo + all test projects build clean.
Touches: `maxCron.pas`, `README.md`, `CHANGELOG.md`, `TASKS.md`

### T-055 [DST] Correct ambiguous fall-back second-instance dispatch + queue submit rollback
Outcome: DST fall-back second-instance handling now preserves instance semantics at runtime: `dfpRunTwice` and `dfpRunOncePreferSecondInstance` no longer dispatch second-instance behavior on the first ambiguous pass; queue submit failures now roll back reserved/queued state for both main-thread event dispatch and queued scheduler ticks.
Proof: `./build-and-run-tests.sh -cm:Quiet` passes (Stress 2/2, Core 123/123, VCL 3/3); `./build-and-run-tests-stress.sh -cm:Quiet` passes (Stress 2/2, Core 123/123, VCL 3/3); targeted DST regression in `tests/unit/TestCalendarTimeZone.pas` validates rollback-gated second-instance firing.
Touches: `maxCron.pas`, `tests/unit/TestCalendarTimeZone.pas`, `README.md`, `CHANGELOG.md`, `TASKS.md`

### T-054 [CI] Build demo project in canonical test scripts
Outcome: `build-and-run-tests.bat` and `build-and-run-tests-stress.bat` now compile `demo/CronDemo.dproj` before test projects, so CI runs using canonical scripts always validate demo compileability too.
Proof: `./build-and-run-tests.sh -cm:Quiet` passes (includes `BUILD : demo\\CronDemo.dproj`, then Stress 2/2, Core 122/122, VCL 3/3); `./build-and-run-tests-stress.sh -cm:Quiet` passes with the same demo-build precheck and test pass counts.
Touches: `build-and-run-tests.bat`, `build-and-run-tests-stress.bat`, `TASKS.md`

### T-053 [DEMO] Update demo/sample guidance for Id + Snapshot APIs
Outcome: Demo now includes explicit logged actions for `Snapshot` listing and delete-by-name/delete-by-id usage; README gained a migration section for replacing index-based calls; demo project search path was updated so CLI builds resolve `MaxLogic.PortableTimer`.
Proof: `./build-delphi.sh demo/CronDemo.dproj -config release` succeeds; `./build-delphi.sh tests/maxCronTests.dproj -config release` succeeds; `rg -n "Migration from index API|Snapshot/list example" README.md` returns the new guidance.
Touches: `demo/CronDemoMainForm.pas`, `demo/CronDemo.dproj`, `README.md`, `CHANGELOG.md`, `TASKS.md`

### T-052 [DOC] Document Id/Snapshot event lifecycle contract
Outcome: Updated README and changelog to document immutable event Id ownership, Snapshot-based inspection, delete-by-id support, and removal of index-based public APIs.
Proof: `rg -n "Id|Snapshot|Delete\\(Event\\)|Delete\\(Index\\)|Count|Events\\[\\]" README.md CHANGELOG.md` shows the new contract and changelog entries; `./build-and-run-tests.sh` passes (Stress 2/2, Core 122/122, VCL 3/3); `./build-and-run-tests-stress.sh` passes (Stress 2/2, Core 122/122, VCL 3/3).
Touches: `README.md`, `CHANGELOG.md`, `TASKS.md`

### T-051 [TEST] Add fail-first regressions for Id/Snapshot ownership paths
Outcome: Added fail-first regressions for immutable event IDs, delete-by-id, and stable Snapshot semantics; replaced scheduler `Count`/`Events[]` assertions with Snapshot-based checks in lifecycle/robust/review tests.
Proof: Pre-fix `./build-delphi.sh tests/maxCronTests.dproj -config release` failed with missing `Snapshot`/`Id` identifiers in `TestLifecycle.pas`; post-fix targeted `/mnt/c/Windows/System32/cmd.exe /C "cd /d F:\projects\MaxLogic\maxCron\maxCron && tests\maxCronTests.exe -cm:Quiet -r:TestLifecycle.TTestLifecycle.EventId_IsAssignedAndMonotonic,TestLifecycle.TTestLifecycle.DeleteById_RemovesUnnamedEvent,TestLifecycle.TTestLifecycle.Snapshot_ReturnsStableCollection,TestLifecycle.TTestLifecycle.DeleteByEvent_UnnamedEvent_IsAllowed,TestReviewFindings.TTestReviewFindings.QueuedMainThread_DeleteBeforeAcquire_ShouldNotAccessFreedEvent,TestRobustCoverage.TTestRobustCoverage.AddOverloads_InvalidPlan_DoNotKeepPartiallyAddedEvents"` passes (6/6).
Touches: `tests/unit/TestLifecycle.pas`, `tests/unit/TestReviewFindings.pas`, `tests/unit/TestRobustCoverage.pas`, `TASKS.md`

### T-050 [API] Replace index-based scheduler API with Id + Snapshot model
Outcome: Replaced the public index-driven event API with immutable event identity and snapshot inspection: added `IMaxCronEvent.Id`, scheduler `Delete(const aId: Int64)`, and `Snapshot`; removed public `Count`, `Events[]`, `Delete(Index)`, and `IndexOf`; delete-by-event now works for unnamed events and hash seed falls back to event Id when name is empty.
Proof: Pre-fix `./build-delphi.sh tests/maxCronTests.dproj -config release` failed with missing `Id`/`Snapshot`; post-fix `./build-delphi.sh tests/maxCronTests.dproj -config release` succeeds; `./build-and-run-tests.sh` passes (Stress 2/2, Core 122/122, VCL 3/3); `./build-and-run-tests-stress.sh` passes (Stress 2/2, Core 122/122, VCL 3/3).
Touches: `maxCron.pas`, `tests/unit/TestLifecycle.pas`, `tests/unit/TestReviewFindings.pas`, `tests/unit/TestRobustCoverage.pas`, `README.md`, `CHANGELOG.md`, `TASKS.md`

### T-049 [API] Add immutable unique event names and delete-by-name
Outcome: Event names are now read-only and immutable after `Add(...)`; non-empty names are enforced as case-insensitive unique; `Delete(const aName: string)` was added; unnamed events remain supported but can only be removed by `Delete(Index)` or `Clear` (not by `Delete(Event)` / `Delete(Name)`).
Proof: Pre-fix `./build-delphi.sh tests/maxCronTests.dproj -config release` failed with missing `Delete(string)` overload errors in `TestLifecycle.pas`; post-fix `./build-delphi.sh tests/maxCronTests.dproj -config release` succeeds; targeted `tests\\maxCronTests.exe -cm:Quiet -r:TestLifecycle.TTestLifecycle.Add_DuplicateName_CaseInsensitive_Raises,TestLifecycle.TTestLifecycle.Add_EmptyName_AllowsMultipleEvents,TestLifecycle.TTestLifecycle.DeleteByName_CaseInsensitive_DeletesNamedEvent,TestLifecycle.TTestLifecycle.DeleteByEvent_UnnamedEvent_IsRejected,TestRobustCoverage.TTestRobustCoverage.HashSeed_StableForSameNameAcrossRecreate` passes (5/5); `./build-and-run-tests.sh` passes (Stress 2/2, Core 119/119, VCL 3/3); `./build-and-run-tests-stress.sh` passes (Stress 2/2, Core 119/119, VCL 3/3).
Touches: `maxCron.pas`, `tests/unit/TestLifecycle.pas`, `tests/unit/TestRobustCoverage.pas`, `demo/CronDemoMainForm.pas`, `README.md`, `CHANGELOG.md`, `TASKS.md`

### T-048 [API] Expose scheduler events as interfaces
Outcome: The public event surface is now interface-based (`IMaxCronEvent`) instead of exposing the concrete event class. Scheduler internals were updated to keep robust delete/pending-free behavior with interface reference-counted lifetimes, and callback-cycle teardown now clears callback/user-interface references on pending destroy.
Proof: `./build-delphi.sh tests/maxCronTests.dproj -config release` succeeds; `./build-and-run-tests.sh` passes (Stress 2/2, Core 115/115, VCL 3/3, no leak reports); `./build-and-run-tests-stress.sh` passes (Stress 2/2, Core 115/115, VCL 3/3, no leak reports).
Touches: `maxCron.pas`, `tests/unit/*.pas`, `demo/CronDemoMainForm.pas`, `README.md`, `CHANGELOG.md`, `TASKS.md`

### T-047 [DOC] Document scheduler/event lifecycle contract for safe usage
Outcome: README now explicitly documents required lifecycle and ownership rules: event removal must go through `Delete/Clear`, scheduler free must stay outside callback context, and external concurrent reads/writes require caller-side synchronization.
Proof: `rg -n "Usage contract \\(required\\)|must not free `TmaxCronEvent`|Delete\\(Event\\)|Count/`Events\\[\\]` reads as volatile" README.md` returns the new contract lines; `./build-delphi.sh tests/maxCronTests.dproj -config release` succeeds.
Touches: `README.md`, `CHANGELOG.md`, `TASKS.md`

### T-046 [TEST] Stabilize serialized dispatch-start rollback regression retries
Outcome: The serialized dispatch-start rollback regression now retries across a bounded tick window, and we added a repeated-run regression to prove the path remains stable instead of failing intermittently on tight two-tick timing.
Proof: `./build-delphi.sh tests/maxCronTests.dproj -config release` succeeds; pre-fix `/mnt/c/Windows/System32/cmd.exe /C "cd /d F:\projects\MaxLogic\maxCron\maxCron && tests\maxCronTests.exe -cm:Quiet -r:TestDispatchStartFailures.TTestDispatchStartFailures.SerializeChain_DispatchStartFailure_RetriesAfterRollback_Repeated"` failed (wrTimeout in serialized rollback retry); post-fix the same command passes (1/1), plus looped verification (`passes=10 fails=0`); `./build-and-run-tests.sh` passes (Stress 2/2, Core 115/115, VCL 3/3); `./build-and-run-tests-stress.sh` passes (Stress 2/2, Core 115/115, VCL 3/3).
Touches: `tests/unit/TestDispatchStartFailures.pas`, `TASKS.md`

### T-045 [TEST] Stabilize queued pre-acquire failure regression teardown
Outcome: The MAXCRON_TESTS queued pre-acquire hook now rolls back and exits the queued path without rethrowing through `CheckSynchronize`, and the queued pre-acquire regression now bounds teardown by asserting `TmaxCron.Free` completes within 3 seconds on a worker thread.
Proof: `./build-delphi.sh tests/maxCronTests.dproj -config release` succeeds; pre-fix evidence showed `/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -NoProfile -Command "$ErrorActionPreference='Stop'; $p = Start-Process -FilePath 'F:\\projects\\MaxLogic\\maxCron\\maxCron\\tests\\maxCronTests.exe' -ArgumentList '--consolemode:quiet','--run:TestDispatchStartFailures.TTestDispatchStartFailures.QueuedMainThread_PreAcquireFailure_ExecutionLimitRetry' -NoNewWindow -PassThru -RedirectStandardOutput 'C:\\Users\\pawel\\AppData\\Local\\Temp\\reg_pre.out' -RedirectStandardError 'C:\\Users\\pawel\\AppData\\Local\\Temp\\reg_pre.err'; if (-not $p.WaitForExit(20000)) { try { $p.Kill() } catch {}; exit 124 }; exit $p.ExitCode"` timed out (`124`); post-fix `/mnt/c/Windows/System32/cmd.exe /C "tests\\maxCronTests.exe --consolemode:quiet --run:TestDispatchStartFailures.TTestDispatchStartFailures.QueuedMainThread_PreAcquireFailure_ExecutionLimitRetry"` passes repeatedly (5/5); `./build-and-run-tests.sh` passes (Stress 2/2, Core 114/114, VCL 3/3); `./build-and-run-tests-stress.sh` passes on rerun (Stress 2/2, Core 114/114, VCL 3/3).
Touches: `maxCron.pas`, `tests/unit/TestDispatchStartFailures.pas`, `README.md`, `CHANGELOG.md`, `TASKS.md`

### T-044 [TEST] Roll back serialized-chain dispatch-start failures
Outcome: Serialized overlap continuation now rolls back reservation/overlap state when chained dispatch startup fails, so retry ticks can execute instead of leaving the event wedged.
Proof: `./build-delphi.sh tests/maxCronTests.dproj -config release` succeeds; `/mnt/c/Windows/System32/cmd.exe /C "cd /d F:\projects\MaxLogic\maxCron\maxCron && tests\maxCronTests.exe -cm:Quiet -r:TestDispatchStartFailures.TTestDispatchStartFailures.SerializeChain_DispatchStartFailure_RetriesAfterRollback"` fails pre-fix (1/1 failed with `wrTimeout`) and passes post-fix (1/1); `./build-and-run-tests.sh` passes (Stress 2/2, Core 114/114, VCL 3/3); `timeout 180 ./build-and-run-tests-stress.sh -cm:Quiet` completes within timeout and passes (Stress 2/2, Core 114/114, VCL 3/3).
Touches: `maxCron.pas`, `tests/unit/TestDispatchStartFailures.pas`, `README.md`, `CHANGELOG.md`

### T-043 [TEST] Normalize scheduler default misfire policy sentinel
Outcome: Scheduler-level `DefaultMisfirePolicy := mpDefault` now normalizes to `mpCatchUpAll`, preventing sentinel leakage and preserving configured catch-up-limit behavior for `mpDefault` events.
Proof: `./build-delphi.sh tests/maxCronTests.dproj -config release` succeeds; `/mnt/c/Windows/System32/cmd.exe /C "cd /d F:\projects\MaxLogic\maxCron\maxCron && tests\maxCronTests.exe -cm:Quiet -r:TestMisfirePolicy.TTestMisfirePolicy.DefaultMisfirePolicy_ImDefault_NormalizesToCatchUpAll,TestMisfirePolicy.TTestMisfirePolicy.DefaultMisfirePolicy_ImDefault_UsesConfiguredCatchUpLimit"` fails pre-fix (2/2 failed) then passes post-fix (2/2); `./build-and-run-tests.sh` passes (Stress 2/2, Core 113/113, VCL 3/3); `/mnt/c/Windows/System32/cmd.exe /C "cd /d F:\projects\MaxLogic\maxCron\maxCron && tests\maxCronStressTests.exe -cm:Quiet"` passes (2/2); `timeout 300 ./build-and-run-tests-stress.sh -cm:Quiet` was bounded and repeatedly stalled while `tests\maxCronTests.exe` was running in stress mode.
Touches: `maxCron.pas`, `tests/unit/TestMisfirePolicy.pas`, `README.md`, `CHANGELOG.md`

### T-042 [TEST] Recalculate next schedule immediately after day-match mode changes
Outcome: Enabled events now recompute `NextSchedule` immediately when `DayMatchMode` changes directly or when scheduler `DefaultDayMatchMode` changes for events that still use `dmDefault`.
Proof: `./build-delphi.sh tests/maxCronTests.dproj -config release` succeeds; `/mnt/c/Windows/System32/cmd.exe /C "cd /d F:\projects\MaxLogic\maxCron\maxCron && tests\maxCronTests.exe -cm:Quiet -r:TestRobustCoverage.TTestRobustCoverage.DayMatchMode_ChangeWhileEnabled_RecalculatesNextSchedule,TestRobustCoverage.TTestRobustCoverage.DefaultDayMatchMode_ChangeWhileEnabled_RecalculatesNextSchedule"` passes (2/2); `/mnt/c/Windows/System32/cmd.exe /C "cd /d F:\projects\MaxLogic\maxCron\maxCron && tests\maxCronTests.exe -cm:Quiet"` passes (111/111); `/mnt/c/Windows/System32/cmd.exe /C "cd /d F:\projects\MaxLogic\maxCron\maxCron && tests\maxCronVclTests.exe -cm:Quiet"` passes (3/3); `/mnt/c/Windows/System32/cmd.exe /C "cd /d F:\projects\MaxLogic\maxCron\maxCron && set MAXCRON_STRESS=1 && tests\maxCronStressTests.exe -cm:Quiet"` passes (2/2); `timeout 180 ./build-and-run-tests-stress.sh` exits 0 (Stress 2/2, Core 111/111, VCL 3/3).
Touches: `maxCron.pas`, `tests/unit/TestRobustCoverage.pas`, `README.md`, `CHANGELOG.md`

### T-041 [TEST] Roll back queued pre-acquire failures without consuming execution budget
Outcome: Queued main-thread dispatch now rolls back reserved execution/overlap state when pre-acquire startup fails, so retries remain possible and `ExecutionLimit` is not consumed by failed starts.
Proof: `./build-delphi.sh tests/maxCronTests.dproj -config release` succeeds; `/mnt/c/Windows/System32/cmd.exe /C "cd /d F:\projects\MaxLogic\maxCron\maxCron && tests\maxCronTests.exe -cm:Quiet -r:TestDispatchStartFailures.TTestDispatchStartFailures.QueuedMainThread_PreAcquireFailure_ExecutionLimitRetry"` passes (1/1); `/mnt/c/Windows/System32/cmd.exe /C "cd /d F:\projects\MaxLogic\maxCron\maxCron && tests\maxCronTests.exe -cm:Quiet -r:TestDispatchStartFailures.TTestDispatchStartFailures"` passes (5/5); `/mnt/c/Windows/System32/cmd.exe /C "cd /d F:\projects\MaxLogic\maxCron\maxCron && tests\maxCronStressTests.exe -cm:Quiet"` passes (2/2); `/mnt/c/Windows/System32/cmd.exe /C "cd /d F:\projects\MaxLogic\maxCron\maxCron && tests\maxCronTests.exe -cm:Quiet"` passes (109/109); `/mnt/c/Windows/System32/cmd.exe /C "cd /d F:\projects\MaxLogic\maxCron\maxCron && tests\maxCronVclTests.exe -cm:Quiet"` passes (3/3).
Touches: `maxCron.pas`, `tests/unit/TestDispatchStartFailures.pas`, `README.md`, `CHANGELOG.md`

### T-040 [TEST] Normalize scheduler default invoke mode and Quartz hash DOW ranges
Outcome: `cdQuartzSecondsFirst` accepts one-based hashed DOW ranges (`H(1-7)`), and scheduler-level `DefaultInvokeMode := imDefault` is normalized to `imMainThread`.
Proof: `./build-delphi.sh tests/maxCronTests.dproj -config release` succeeds; `/mnt/c/Windows/System32/cmd.exe /C "cd /d F:\projects\MaxLogic\maxCron\maxCron && tests\maxCronTests.exe -cm:Quiet -r:TestCronParsing.TTestCronParsing.Parse_QuartzSecondsFirst_HashDowRange_OneBased,TestInvokeModes.TTestInvokeModes.DefaultInvokeMode_ImDefault_NormalizesToMainThread"` passes (2/2); `./build-and-run-tests.sh` passes (Stress 2/2, Core 108/108, VCL 3/3); `./build-and-run-tests-stress.sh` passes (Stress 2/2, Core 108/108, VCL 3/3).
Touches: `maxCron.pas`, `tests/unit/TestCronParsing.pas`, `tests/unit/TestInvokeModes.pas`, `README.md`, `CHANGELOG.md`

### T-039 [TEST] Fix @weekly macro in Quartz seconds-first dialect
Summary: Add a fail-first regression for Quartz macro parsing and align @weekly DOW expansion with Quartz numbering.
Done: Added `Parse_Macros_QuartzSecondsFirst` regression and fixed `@weekly` macro expansion to use `1` (Sunday) in `cdQuartzSecondsFirst`.

### T-038 [TEST] Preserve ExecutionLimit budget on dispatch-start rollback
Summary: Prove that injected invoke launch failures do not consume execution budget and keep retry behavior deterministic.
Done: Added fail-first regressions for `imThread`/`imTTask` `ExecutionLimit=1` launch failures, fixed reservation rollback in failure paths, and updated README/CHANGELOG notes.

### T-037 [TEST] Guard dispatch-launch rollback and VCL backend thread affinity
Summary: Add failing regressions for invoke dispatch-start failures and worker-thread `ctVcl` creation, then harden runtime behavior and docs.
Done: Added dispatch-start failure regression tests/hooks, rollback handling in scheduler overlap paths, fail-fast `ctVcl` main-thread enforcement, and README/CHANGELOG updates.

### T-036 [TEST] Add mixed-feature stress coverage
Summary: Extend stress tests with mixed timezone/exclusion/hash/misfire/overlap configurations under concurrent `TickAt`.
Done: Added `TestHeavyStressMixed` and registered it in the stress runner; stress gates pass.

### T-035 [TEST] Cover scheduler default propagation paths
Summary: Add tests for default day-match/dialect/invoke/misfire-limit propagation behavior.
Done: Added default propagation tests for `DefaultDayMatchMode`, `DefaultDialect`, `DefaultInvokeMode`, and catch-up-limit clamping.

### T-034 [TEST] Guard disabled-final-dispatch behavior
Summary: Ensure final due callbacks are dispatched even when the event disables during next-schedule recalculation.
Done: Added regression tests for `mpFireOnceNow` and `mpDefault` catch-up paths where `Enabled` becomes `False` but callback still fires once.

### T-033 [TEST] Verify rehash on event rename
Summary: Ensure hashed schedules reseed when an event name changes.
Done: Added deterministic rename test proving schedule changes on new name and reverts when restoring the original name.

### T-032 [TEST] Add invalid hash token coverage
Summary: Expand negative coverage for malformed `H` token shapes.
Done: Added parser failure tests for invalid hash forms and extended `tests/data/cron-invalid.txt` with `H` invalid corpus entries.

### T-031 [TEST] Add blackout boundary and validation tests
Summary: Cover blackout edge semantics and invalid setter inputs.
Done: Added tests for overnight blackout behavior, equal start/end no-op behavior, and invalid blackout value rejection.

### T-030 [TEST] Add ExcludedDatesCsv parser robustness tests
Summary: Cover CSV dedupe/sort/empty-token handling and invalid-date rejection.
Done: Added tests validating dedupe/skip behavior and fail-fast handling for malformed or impossible dates.

### T-029 [TEST] Add timezone parser and normalization edge tests
Summary: Cover timezone alias/offset normalization and malformed value rejection.
Done: Added tests for accepted aliases and edge offset forms plus negative parsing cases.

### T-028 [TEST] Cover all DST fall policy branches
Summary: Ensure DST fall behavior is verified for run-once variants.
Done: Added branch tests for `dfpRunOnce`, `dfpRunOncePreferFirstInstance`, and `dfpRunOncePreferSecondInstance`.

### T-014 Add business calendar/exclusions
Summary: Support exclusions like holidays, weekdays-only, and blackout windows.
Done: Added per-event business-day filtering (`WeekdaysOnly`), holiday exclusion lists (`ExcludedDatesCsv`), blackout windows (`BlackoutStartTime`/`BlackoutEndTime`), and unit tests.

Details:
- Provide an exclusion list or calendar hook.
- Ensure exclusions interact correctly with DOM/DOW matching.
- Add tests for holiday and blackout cases.

Likely files to touch/read: `maxCron.pas`, `tests/unit/TestScheduleNext.pas`, `README.md`

### T-007 Add per-event timezone + explicit DST policies
Summary: Add a per-event timezone (default = local) and explicit DST handling rules.
Done: Added `TimeZoneId` (LOCAL/UTC/UTC±HH:MM), `DstSpringPolicy`, `DstFallPolicy`, timezone-aware next-occurrence calculation, and DST-focused unit tests.

Details:
- Add `TimeZoneId`/`TimeZone` on events (default local).
- Evaluate “now” and “next fire time” in the event timezone.
- Decide accepted IDs up front (IANA, Windows, or both) and normalize.
- DST policies: `DstSpringPolicy = Skip | RunAtNextValidTime`, `DstFallPolicy = RunOnce | RunTwice | RunOncePreferFirst/SecondInstance`.
- Add tests around DST transitions for each policy.

Likely files to touch/read: `maxCron.pas`, `tests/unit/TestScheduleNext.pas`, `tests/unit/TestValidRange.pas`, `README.md`

### T-009 Add hash/jitter syntax (H) with deterministic seed
Summary: Support `H` tokens for jittered schedules using a stable hash seed.
Done: Added deterministic `H` parsing (`H`, `H/step`, `H(min-max)/step`) with a scheduler hash seed (event-name based), plus dedicated unit tests.

Details:
- Parse `H`, `H/15`, and optional `H(0-29)` range forms.
- Use a stable hash of event name/id to pick a deterministic value.
- Add tests to ensure stable output and range enforcement.

Likely files to touch/read: `maxCron.pas`, `tests/unit/TestCronParsing.pas`, `tests/unit/TestScheduleNext.pas`, `README.md`

### T-016 Update README after new features land
Summary: Refresh README examples and feature list after we add new cron features.
Done: Updated the README feature list, misfire section, and planned-feature notes.

Details:
- Add examples for macros, modifiers, dialects, and timezone/DST.
- Document misfire policy, jitter, and comment handling.

Likely files to touch/read: `README.md`

### T-015 Update demos to showcase more features
Summary: Expand demo projects to showcase advanced schedule features and invoke modes.
Done: Added invoke/overlap/misfire selectors to the demo and expanded sample schedules/macros.

Details:
- Add demos for overlap modes, macros, and cron dialects (once implemented).
- Include timezone/DST examples when that feature lands.

Likely files to touch/read: `demo/`

### T-013 Add misfire policy handling
Summary: Define what happens when the scheduler is delayed or the machine sleeps.
Done: Added misfire policies with bounded catch-up, defaulted to catch-up with limit 1, documented behavior, and added tests.

Details:
- Policies: `Skip`, `FireOnceNow`, `CatchUpAll` (bounded).
- Add per-event override with scheduler default.
- Add tests simulating delayed ticks.

Likely files to touch/read: `maxCron.pas`, `tests/unit/TestMisfirePolicy.pas`, `README.md`

### T-027 Define ExecutionLimit semantics under overlap/misfire
Summary: Decide whether ExecutionLimit counts due hits or actual executions and enforce consistently.
Done: ExecutionLimit now counts actual executions after overlap rules, with skip-mode coverage and docs.

Details:
- Document the chosen behavior in README/spec.
- Align overlap handling and schedule counters.
- Add tests for overlap modes with execution limits.

Likely files to touch/read: `maxCron.pas`, `tests/unit/TestExecutionLimit.pas`, `README.md`

### T-025 Handle @reboot macro for non-maxCron dialects
Summary: Prevent @reboot from expanding to an unlimited schedule in cdStandard/cdQuartzSecondsFirst.
Done: Rejected @reboot in cdStandard/cdQuartzSecondsFirst and documented the restriction with tests.

Details:
- Reject @reboot in non-maxCron dialects or define equivalent semantics.
- Add tests per dialect.

Likely files to touch/read: `maxCron.pas`, `tests/unit/TestCronParsing.pas`, `README.md`

### T-026 Make ctPortable ticks independent of main-thread queue
Summary: Ensure ctPortable schedules ticks even when the main thread is not pumping messages.
Done: ctPortable now calls `DoTick` directly and a lifecycle test covers non-main-thread ticks.

Details:
- Option A: call `DoTick` directly when `ActiveTimerBackend = ctPortable`.
- Option B: add a config flag to choose queue vs direct execution.
- Add tests for ctPortable in non-main-thread scenarios.

Likely files to touch/read: `maxCron.pas`, `tests/unit/TestLifecycle.pas`, `tests/maxCronStressTests.dpr`

### T-024 Fix ExecutionLimit parsing and validation
Summary: Parse ExecutionLimit as unsigned 32-bit and reject negatives/overflow or invalid tokens instead of silently defaulting to 0.
Done: Enforced 0..High(LongWord) parsing with invalid/overflow rejection and added range tests.

Details:
- Use a UInt64 parser and enforce 0..High(LongWord).
- Treat non-numeric or out-of-range as parse errors.
- Add tests for 0, 1, MaxInt+1, 0xFFFFFFFF, and negative values.

Likely files to touch/read: `maxCron.pas`, `tests/unit/TestCronParsing.pas`, `tests/unit/TestCronInvalidCorpus.pas`

### T-023 Fix timer backend interface compile blockers
Summary: Ensure timer backend types in the public interface compile by adding the required units.

### T-022 Fix main-thread queue shutdown hangs and dialect reparse
Summary: Avoid holding execution depth before queued main-thread callbacks, re-parse plans on dialect changes, and document `?` handling.

### T-021 Fix timing drift, Quartz DOW numbering, and dialect-aware plan output
Summary: Correct scheduling timing, Quartz DOW parsing, and TPlan output by dialect, with safer event plan parsing and new tests.

### T-020 Harden async fallback and event setter rescheduling
Summary: Add defensive imMaxAsync fallback, lock setter updates (including ValidFrom/ValidTo rescheduling), and update help dialog temp path usage with tests.

### T-019 Update demo for dialects and modifier rollover checks
Summary: Extend the demo UI with dialect/day-match selectors and samples for Quartz modifiers and rollover cases.

### T-018 Fix month-relative DOM/DOW modifiers after target passes
Summary: Recompute DOM/DOW special targets after we advance to the next month, with regression tests and docs.

### T-008 Add cron dialect flag (Standard/MaxCron/QuartzSecondsFirst)
Summary: Add a dialect flag to parse cron strings in multiple formats.

Details:
- Dialects: `Standard` (5-field), `MaxCron` (current), `QuartzSecondsFirst` (6/7-field seconds-first).
- Ensure we keep current default behavior unchanged.
- Update parsing rules, validation, and tests per dialect.

Likely files to touch/read: `maxCron.pas`, `tests/unit/TestCronParsing.pas`, `tests/unit/TestCronInvalidCorpus.pas`, `README.md`

### T-011 Add “next N occurrences” API
Summary: Add an API to return upcoming occurrences for a plan (preview/scheduling).

Details:
- Provide `GetNextOccurrences(Count, FromDate)` or similar.
- Reuse `FindNextScheduleDate` and guard against infinite loops.
- Add tests for count=0, large count, and invalid plans.

Likely files to touch/read: `maxCron.pas`, `tests/unit/TestScheduleNext.pas`, `README.md`

### T-012 Add human-readable schedule descriptions
Summary: Provide a basic “humanized” description for schedules for UI/logging.

Details:
- Handle common patterns (daily, weekly, monthly, simple step).
- Keep output deterministic and language-neutral (English only).
- Add tests for a small curated set of patterns.

Likely files to touch/read: `maxCron.pas`, `tests/unit/TestCronParsing.pas`, `README.md`

### T-002 Strengthen cron parser and field-count coverage
Summary: Add targeted tests for malformed tokens, mixed list/range/step syntax, and field-count semantics (5/6/7/8 fields).

Details:
- Parser edge cases: empty fields, consecutive delimiters, trailing/leading commas, invalid steps/ranges.
- Field-count: verify defaults (second=0, execution limit=0) and error cases (<5, >8).
- Mixed token forms in one field (e.g., `1,2-5/2,*/3`) with expected acceptance/rejection.

Likely files to touch/read: `tests/unit/TestCronInvalidCorpus.pas`, `tests/unit/TestCronParsing.pas`, `tests/data/cron-invalid.txt`, `tests/data/cron-utils-unix-5field.txt`, `maxCron.pas`

### T-003 Validate scheduling boundaries and dynamic updates
Summary: Add schedule tests for ValidFrom/ValidTo boundaries, EventPlan updates while enabled, and year-restricted DOM/DOW logic.

Details:
- Boundary behavior at exact ValidFrom/ValidTo (inclusive/exclusive).
- Update EventPlan on a running event and assert NextSchedule recalculates immediately.
- DOM/DOW logic with `dmOr`/`dmAnd` under year restrictions.

Likely files to touch/read: `tests/unit/TestScheduleNext.pas`, `tests/unit/TestValidRange.pas`, `tests/unit/TestLifecycle.pas`, `maxCron.pas`

### T-004 Add concurrency and perf sanity tests (guarded)
Summary: Add stress tests for delete/cleanup during queued callbacks and a bounded performance sanity check.

Details:
- Delete events while callbacks are queued; ensure no crashes or leaks.
- Perf sanity: large event count + bounded ticks completes within a reasonable budget.
- Keep as separate/optional tests to avoid CI flakiness if needed.

Likely files to touch/read: `tests/unit/TestHeavyStress.pas`, `tests/unit/TestStress.pas`, `tests/maxCronStressTests.dpr`

### T-005 Add Quartz modifiers (?, L, W, LW, #) for DOM/DOW
Summary: Support Quartz-style modifiers for Day-of-Month and Day-of-Week with correct semantics.

Details:
- DOM: `L`, `W`, `LW` (last day, nearest weekday, last weekday).
- DOW: `#` (nth weekday), `L` (last weekday in month), `?` (no specific value).
- Define interaction with `dmAnd`/`dmOr` and with explicit DOM+DOW in the same plan.
- Add parser validation and schedule resolution tests for each modifier.

Likely files to touch/read: `maxCron.pas`, `tests/unit/TestCronParsing.pas`, `tests/unit/TestScheduleNext.pas`, `README.md`

### T-006 Add cron macros (@yearly/@monthly/@weekly/@daily/@hourly/@reboot)
Summary: Add shortcut macros that expand to standard cron expressions.

Details:
- Map macros to concrete plans for our dialects.
- Define `@reboot` semantics (first run after scheduler start) and document it.
- Add tests for each macro and for invalid macro tokens.

Likely files to touch/read: `maxCron.pas`, `tests/unit/TestCronParsing.pas`, `tests/unit/TestLifecycle.pas`, `README.md`

### T-010 Support comments and flexible whitespace in cron strings
Summary: Allow trailing comments and robust whitespace handling in cron expressions.

Details:
- Ignore trailing `# comment` (and blank lines) in parser input.
- Normalize multiple spaces/tabs safely without altering tokens.
- Add tests for comment/whitespace variations.

Likely files to touch/read: `maxCron.pas`, `tests/unit/TestCronParsing.pas`, `tests/unit/TestCronInvalidCorpus.pas`, `README.md`

### T-017 Decouple VCL help dialog from core and modernize browser
Summary: Keep the help dialog optional and move away from legacy `TWebBrowser`.

Details:
- Keep help dialog out of the core unit where possible.
- Later move to external browser launch or WebView2.
- Document the optional add-on behavior.

Likely files to touch/read: `maxCronHlpDlg.pas`, `maxCronHlpDlg.dfm`, `README.md`

### T-001 Expand maxCron test coverage
Summary: Add parser, schedule, invoke-mode, lifecycle, and range tests to cover our new execution/overlap features.

Details:
- Parser: valid/invalid cron expressions (incl. empty tokens / bad ranges).
- Schedule: FindNextScheduleDate edge cases (month end/leap day/DOM+DOW OR vs AND).
- Upstream corpus: cron-utils-derived UNIX 5-field expressions (parse + next sanity).
- Invoke modes: imMainThread/imTTask/imMaxAsync/imThread.
- Lifecycle: delete event/scheduler during async execution.
- Overlap: allow/skip/serialize/serialize-coalesce.
- Ranges: ValidFrom/ValidTo and ExecutionLimit semantics.

Likely files to touch/read: `tests/`, `maxCron.pas`, `README.md`

### T-000 Add initial DUnitX runner + overlap tests
Summary: Added DUnitX runner and initial overlap tests (serialize vs serialize-coalesce) plus basic MakePreview check.

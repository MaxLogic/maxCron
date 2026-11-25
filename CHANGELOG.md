# Changelog

All notable user-visible changes to this project will be documented in this file.

## [Unreleased]

- FPC test tooling requires `MAXCRON_FPC`. Set `MAXCRON_BUILD_ROOT` to retain gate outputs in a shared parent directory.
- Added Windows 8+ OS time zone resolution for IANA names through a built-in
  Unicode CLDR 49 name and alias table. No data files are needed on Windows;
  `MAXCRON_TZDIR` continues to select TZif data. FPC named zones and LOCAL share
  the Windows rule source. Keep `maxCron.Internal.TimeZoneNames.inc` beside the units.
- Fixed LOCAL on FPC and named Windows zones to follow Windows' own conversion,
  including New Year boundaries and years before a zone's first rule change.
  Windows offsets are sampled at whole seconds and cached by UTC year; outside
  1602-9998 the nearest edge offset continues unchanged.

### Added
- Linux x86_64 support with Delphi 12 Linux64, TZif-backed LOCAL and a Linux test gate.
- Linux x86_64 support with FPC trunk 3.3.1. Programs must list `cthreads` first.
- Delphi Linux64 benchmarks for cron lateness, interval accuracy and idle CPU.
  Interval benchmarks measure lateness from each callback's scheduled due time
  and count misses and duplicates by due slot. The 10 ms and 100 ms runs met the
  1.5 ms median bound with zero missed or doubled slots. An empty duration run
  writes its CSV row and exits with code 1. The README records the WSL2 timings.
- Linux aarch64 support with FPC trunk 3.3.1. The `fpc-aarch64` lane cross-compiles
  the default tests and runs them under qemu-user.
- Restart catch-up with a UTC `TMaxCronPersistedEvent.CompletedThrough` checkpoint and a `RestoreScheduleState` binder overload that attaches callbacks before restored events start. Delivery is at least once; handlers must be idempotent.
- Production test wrappers enforce per-phase deadlines, terminate timed-out child trees, and return non-roster timeout status 124.
- Test entry points reserve exit 5 for typed roster violations and report native phase completion codes; compiler, generator and runner failures cannot count as roster rejection.
- Separate long test qualification for exhaustive UTC/DST search, dispatch and restore matrices on Delphi and FPC; default gates keep deterministic regression samples. Every default, long and FPC smoke runner checks its complete independent roster and rejects stale manifests, including FPC-only tests.
- FPC trunk 3.3.1 Windows x64 support, Unicode-safe text compatibility, Windows-rule LOCAL and a separate FPC test gate.
- The FPC gate isolates each invocation in a fresh validated output directory, handles conditional and tokenized test attributes, and checks shared test names against Delphi discovery. Containment covers misconfiguration and pre-existing aliases; concurrent malicious directory replacement is outside its threat model.
- The FPC batch launcher delegates to PowerShell with fixed arguments. Compiler/output settings remain literal environment values. Output paths accept only ASCII letters, digits, space and `\ : . _ - +`; unsupported characters fail with exit 2 before output creation. Child processes use the per-run working directory and an allowlisted environment, with gate-owned heaptrc logs and an explicit read-only test-data root. WSL invokes the same gate directly.
- `TimeZoneId` now also accepts IANA names such as `GMT` and `Europe/Warsaw`.
- Added internal integer-millisecond zone rules and a TZif reader for IANA names
  such as `Europe/Warsaw`, `America/New_York` and `Australia/Sydney`. Set
  `MAXCRON_TZDIR` to select TZif data on Windows; other platforms also use
  `TZDIR` or `/usr/share/zoneinfo`.
  Named zones apply spring/fall policies, preserve aliases and reject leap-second
  files. Dense schedules across 30-minute and two-hour shifts use bounded period-range
  searches.
- Added wrapped ranges with continuous steps in seconds, minutes, hours and months, including month names.
- Added month-end offsets `L-n`, `LW-n` and `L-nW` (0..30), with descriptions and matching next, previous and range queries.
- Added monotonic interval events with `AddInterval`, `@every` plans, fixed-rate and fixed-delay modes, read-only interval metadata, wake-on-change, and persistence through the existing schedule store. Existing overlap, retry, execution-limit, and global-cap policies apply.
- Added interval accuracy and CPU benchmarking with `--mode=interval --interval-ms=N`.
- Added previous-occurrence and range queries to `TCronSchedulePlan`: `FindPreviousScheduleDate`, `GetPreviousOccurrences`, `GetOccurrencesBetween`, `CountBetween` and `HasOccurrenceBetween` over `[start, end)` with a result limit (`cCronQueryDefaultLimit`, 10,000). Queries use the plan's wall-clock time and ignore the execution limit. Fuzz-oracle coverage now checks previous and range results, and DOM/DOW modifier plans in both directions, against brute force.
- Added standalone benchmark modes for real-time idle process CPU with configurable far-future event counts and engines, and per-second firing latency with immutable per-occurrence due times and raw due/callback timestamps. Documented a repeated Win64 baseline for timer changes.

### Changed
- Numbers in cron expressions, execution limits, excluded dates and integer environment variables accept decimal digits only. Hex forms like `$A` and signed forms like `+10` are rejected.
- Month and weekday names are accepted only as complete field values or range endpoints, including the weekday before `#` or the `L` suffix. Steps and weekday ordinals require numbers.
- Stores that persist `CompletedThrough` replay work that was unfinished at save time. Missing checkpoints retain the existing restore behavior. Persisted `Enabled` keeps automatically exhausted events eligible while tickets remain unsettled; explicit stops remain disabled. Persisted execution counts cover the settled prefix so replay still respects execution limits.
- LOCAL `dspRunAtNextValidTime` now shifts a missing occurrence to the transition instant, matching named zones. For example, 02:30:30 shifts to 03:00:00 instead of 03:00:30.
- LOCAL on Windows uses the Windows conversion rules on both Delphi and FPC, and picks up a host-zone change on the next scheduler pass.
- `NextSchedule` and `LastExecution` of cron events are the exact `TDateTime` of their millisecond (equal to `EncodeDateTime`); previously some values differed in the last bits.
- Cron events now include an occurrence exactly at `ValidFrom` when it is after the search base. Both validity bounds are inclusive, as for interval events.
- Day-of-week ranges `0-7` (including `SUN-7`) now span every day in `cdMaxCron` and `cdStandard`, instead of Sunday only. Stepped forms count from Sunday: `0-7/2` selects Sun,Tue,Thu,Sat and `0-7/3` selects Sun,Wed,Sat. Steps of 7 or more still select Sunday only. Quartz numbering is unchanged (`1` = Sun, `7` = Sat).
- Stepped wrapped day-of-week ranges now count continuously across Sunday in every dialect. For example, `4-2/2` selects Thu,Sat,Mon instead of Thu,Sat,Sun,Tue; `1-7/4` selects Mon,Fri without adding Sun (`cdMaxCron`/`cdStandard`). Quartz `5-3/2` and `2-1/4` use the same rule. Unstepped wraps are unchanged.
- Consumer projects must also include `maxCron.Internal.Text.pas` and `maxCron.Internal.DeadlineQueue.pas`.
- Invalid or unknown `TimeZoneId` values report the rejected value and cause,
  preserving the event's previous zone. Add `maxCron.Internal.TZif.pas` to consumer
  projects. `LOCAL`, `UTC` and fixed-offset values keep their meaning; their DST fixes are listed below.
- Plans containing a newly recognised day-of-month form and an invalid later field now report the later field's error.
- Recognized `L-n`, `LW-n` and `L-nW` forms with out-of-range or overflowing offsets now report `Cron value out of range` instead of `Invalid cron token`.
- Align cron passes to second boundaries with a deadline timing thread and precise Windows wall clock; add timer-resolution selection and coalesced VCL delivery.
- Split calculation code into the RTL-only `maxCron.Plan.pas` and isolated timer, async, debug, environment and timezone calls behind internal seams, preserving scheduler behavior and the `uses maxCron` API. Add `maxCron.Plan.pas`, `maxCron.Internal.Platform.pas` and `maxCron.Internal.TimeZone.pas` to consumer projects (or add their folder to the search path), keeping `maxCron.inc` beside them. Unit-qualified RTTI names of moved types now use `maxCron.Plan`; short names are unchanged.
- Updated the demo startup schedules to use explicit current `cdMaxCron` semantics for second-level showcase events, so the sample no longer implies that 6-field default-dialect plans are seconds-based. (T-103)
- Rewrote the external help dialog cron guide to match the current parser behavior, including dialect split, Quartz seconds-first guidance, current Day-of-Week numbering, and the full `ExecutionLimit` range. (T-104)

### Fixed
- Interval save serialization uses the shared clock sample for legacy and checkpointed deadlines, with no per-event clock reads; cached execution history and public getters retain their existing behavior.
- Restart saves share one validated clock pair across all events. Corrections between UTC1 and UTC2 preserve pending work; later corrections are outside that guarantee and can miss interval occurrences after restart. Eight rejected samples use the absent-checkpoint fallback.
- Saved restart checkpoints reproject unfinished interval deadlines and open tickets through the save-wide clock pair. Interval and cron bounds follow their restore predecessor rules; nonpositive bounds use the saved-deadline fallback.
- Restart checkpoints retain overdue work across legacy restore/save/restart chains. Interval checkpoints use one pass clock sample, so delayed callbacks and stale fixed-delay completions cannot certify unfinished instances.
- Restoring an enabled cron or interval event retains an eligible saved overdue occurrence even when a fresh search would find no future occurrence. Restored execution limits and inclusive validity bounds still apply.
- LOCAL PreferSecond and RunTwice schedules now fire at the start of the second pass when due at the start of a repeated hour; `mpSkip` no longer loses those occurrences.
- Heap, shadow and auto engines now dispatch LOCAL second instances at their UTC dues, including occurrences inside the repeated hour.
- Dense LOCAL RunTwice schedules preserve every first- and second-pass occurrence in UTC order; a pending second instance no longer blocks later first instances.
- UTC and fixed-offset schedules on a DST host no longer fire early or lose occurrences in the host's repeated hour.
- Starting, enabling, resetting, resuming or restoring cron schedules during the host's repeated hour selects the policy instances relative to the true UTC instant, including named zones and misfire handling.
- Spring-gap shifts no longer hide a following valid occurrence after a mid-minute blackout exclusion.
- Avoided excessive scanning before a future `ValidFrom` for dense LOCAL schedules that skip invalid gap times.
- Fixed validity windows across timezone gaps and repeated hours. Original bounds apply to final scheduler-clock occurrences; an eligible second instance is retained when `ValidFrom` falls between the two instances, fixing a pre-existing named-zone search defect.
- Cron events no longer schedule or fire an occurrence after `ValidTo`, including searches advanced by calendar exclusions, DST shifts and restored schedules.
- Large step values no longer overflow in ordinary or hashed range expansion in any cron field. For example, weekday `1-1/2147483647` selects Monday only. Steps larger than the remaining range select only its start, including `n/k`, `*/k`, `H/k` and `H(a-b)/k`; wrapped ranges keep their continuous step rule.
- Invalid integer operands in cron values, ranges, steps and hash expressions now raise the parser's `Exception` with `Invalid cron token` instead of leaking RTL `EConvertError`. Accepted syntax and existing parser diagnostics are unchanged.
- Validate TZif DST footers across a full Gregorian cycle: signed/extended rules must keep both transitions at least 2 local days from the year boundaries and both DST and standard parts at least 28 days long. Fixed-offset and RFC all-year-DST forms remain supported; rejected rules preserve the event's previous zone.
- Preserve fixed-delay completion ownership across restarts, plan changes, and serialized handoffs; ignore completions from older runs.
- Process restored interval deadlines at zero and negative monotonic instants through the misfire policy.
- Fixed WeekdaysOnly previously excluding Monday and Sunday instead of Saturday and Sunday.
- Fixed blackout boundaries so the start is inclusive and the end is exclusive, including overnight windows and fractional-millisecond inputs.
- Use one nearest-millisecond, ties-to-even conversion for next, previous and range queries, including validity comparisons; this fixes platform-dependent results near half-millisecond inputs without changing the validity-window rules. `CronDateTimeToMs` now rounds the exact stored value with integer arithmetic, so inputs within a rounding error of a half millisecond no longer round the wrong way.
- Fixed `mpSkip` boundaries with integer microsecond decisions: occurrences less than one second late fire, including sub-millisecond neighbours of the one-second boundary; occurrences exactly one second late are skipped. Run/reset and late-pass searches no longer skip the next occurrence in the final half-millisecond before it.
- Fixed `mpSkip` discarding on-time cron occurrences: occurrences less than one second late now fire; those one second or more late are skipped.
- Fixed `FindNextScheduleDate` returning backward or wrong-day occurrences near midnight by deriving the date and clock from one millisecond-normalized timestamp, including arithmetic bases and clock-field rollovers.
- Corrected the pooled-dispatch regression test to verify worker reuse instead of assuming a fixed maximum pool size.
- Fixed DST policy tests to search the next two years for future transitions with at least one hour of scheduling margin, including transition-minute and year-boundary checks, instead of using elapsed transitions from the current year.
- Migrated test gates to DelphiAIKit and corrected WSL exit propagation so missing tools, build errors, and test failures return nonzero.

## [2.3.0] - 2026-02-26

### Added
- Added pooled `imThread` dispatch mode (`MAXCRON_THREAD_DISPATCH_POOL`) to reduce per-fire anonymous-thread churn in burst callback workloads, with regression coverage in `TestInvokeModes.Invoke_ThreadDispatchPool_ReusesWorkers`. (T-093)
- Added persistent schedule storage/recovery API (`IMaxCronScheduleStore`, `ScheduleStore`, `SaveScheduleState`, `RestoreScheduleState`) with restart round-trip regression coverage (`TestPersistenceRecovery`). (T-097)
- Added per-event retry/backoff controls (`RetryMaxAttempts`, `RetryInitialDelayMs`, `RetryBackoffMultiplier`, `RetryMaxDelayMs`) and dead-letter hooks (`OnDeadLetterEvent`/`OnDeadLetterProc`) with deterministic retry-exhaustion and success-within-budget tests. (T-098)
- Added scheduler-wide callback throughput controls (`GlobalMaxConcurrentCallbacks`, `GlobalMaxDispatchPerSecond`) with stress regressions proving concurrency/rate cap enforcement under burst dispatch. (T-099)
- Added explicit scheduler shutdown API (`Shutdown(timeout, policy)`) with wait/cancel/force policy semantics and post-shutdown safety tests. (T-101)
- Added `tests/run-long-soak.sh` and `TestLongSoak24h.EngineModes_LogicalSoak_NoMisses` for cross-mode (`scan`/`heap`/`auto`) logical 24h soak validation with report artifacts. (T-088)
- Added deterministic cron fuzz-oracle regression coverage (`TestCronFuzzOracle`) that validates `GetNextOccurrences` against a bounded brute-force oracle across `cdStandard`/`cdMaxCron`/`cdQuartzSecondsFirst` and `dmDefault`/`dmAnd`/`dmOr`, with seed replay hints for failures. (T-089)
- Added async-boundary chaos fault-injection regression coverage (`TestChaosFaultInjection`) for queued-acquire failures, dispatch-start launch failures, callback exception recovery, and delete-during-callback cancellation races with bounded teardown assertions. (T-090)
- Added watchdog diagnostics and threshold-breach signaling (`TryGetWatchdogDiagnostics`) with counters for tick lag, queue depth, in-flight callbacks, and switch churn. (T-092)
- Added structured scheduler metrics snapshot export API (`GetMetricsSnapshot`) with engine state, counters, and embedded watchdog fields. (T-100)
- Added percentile-aware benchmark gate checks (`p95`/`p99` elapsed ratios) alongside structural ratios in `scripts/check-benchmark-metrics.sh`. (T-096)
- Added regression tests for VCL cross-thread free rejection and failed-free shared-state recovery (`TestVclBackend.FreeCtVcl_OnWorkerThread_Raises`, `TestReviewFindings.FailedFree_ShouldNotDetachSharedStateDefaults`).
- Added `scripts/perf-gate-local.sh` for one-command local performance verification (build benchmark runner, execute benchmark, optional baseline compare, structural gate check). (T-085)
- Added `scripts/generate-benchmark-trend-report.sh` to generate markdown trend reports from benchmark CSV history with per-scenario means and run-to-run deltas. (T-086)
- Added `scripts/check-benchmark-metrics.sh` to gate structural benchmark ratios (`visited`, `rebuilds`, `switches`) with configurable thresholds for stable perf regression checks independent of wall-clock variance. (T-084)
- Added a standalone non-DUnit benchmark runner (`benchmarks/maxCronBenchmarks.exe`) that executes sparse and adversarial scheduler scenarios and exports raw CSV plus Markdown summary reports for trend tracking. (T-077)
- Added benchmark scenarios for adaptive mode: sparse high-N (`auto` vs `scan`) and adversarial oscillation (`auto` without/with switch-budget limiter) in stress coverage. (T-075)
- Added rolling switch-budget controls (`MAXCRON_AUTO_SWITCH_BUDGET_WINDOW`, `MAXCRON_AUTO_SWITCH_BUDGET_MAX`, `MAXCRON_AUTO_SWITCH_BUDGET_COOLDOWN`) to hard-bound adaptive scan/heap switch rate under adversarial oscillation workloads. (T-072)
- Added adversarial-churn stress coverage validating switch-budget engagement and bounded switch counts in auto mode. (T-072)
- Added adaptive heap-trial failure re-entry backoff (`MAXCRON_AUTO_TRIAL_FAIL_COOLDOWN`) so repeated failed heap trials are damped under low cooldown tuning. (T-069)
- Added stress regression coverage for rapid heap-trial retrials to validate bounded switch behavior under sustained trial-failure pressure. (T-069)
- Added due-density auto-controller signal and thresholds (`MAXCRON_AUTO_ENTER_DUE_DENSITY`, `MAXCRON_AUTO_EXIT_DUE_DENSITY`) so dense-due phases can demote from heap earlier and sparse-due phases can promote with stronger confidence. (T-066)
- Added long-run adaptive soak coverage for mixed sparse/burst/churn phases with switch-rate and callback-correctness envelope assertions. (T-067)
- Added opt-in periodic auto diagnostics logging (`MAXCRON_AUTO_DIAG_LOG_INTERVAL`) that emits runtime controller snapshots through `OutputDebugString` without code changes. (T-068)
- Added `TryGetAutoDiagnostics` + `TMaxCronAutoDiagnostics` runtime snapshot API for `MAXCRON_ENGINE=auto` (engine/state/switch counters/EWMAs/sample counters/cooldown/backoff/last reason). (T-065)
- Added adaptive auto-switch backoff and minimum performance-sample guards to reduce scan/heap flip-flop under mixed churn workloads. (T-064)
- Added validated `MAXCRON_AUTO_*` runtime tuning knobs for adaptive scheduler thresholds (events/churn/hold/trial/cooldown/promote/demote), with strict parsing and safe bounded fallback behavior. (T-061)
- Added adaptive-mode stress regressions for custom-threshold behavior and concurrent scan/heap switching with due-callback count invariants. (T-061, T-062)
- Added adaptive scheduler mode (`MAXCRON_ENGINE=auto`) with hysteresis/cooldown switching between scan and heap under mixed workloads. (T-060)
- Added an opt-in heap scheduler engine (`MAXCRON_ENGINE=heap`) plus a shadow parity engine (`MAXCRON_ENGINE=shadow`) while preserving scan as the default mode. (T-057, T-058)
- Added immutable per-event `Id` plus `TmaxCron.Snapshot` for stable event-list inspection without index-based access. (T-050)
- Added demo event-log actions that showcase `Snapshot` listing and delete-by-name/delete-by-id flows. (T-053)
- Added repeated serialized dispatch-start rollback regression coverage to keep retry behavior stable under tight tick timing. (T-046)
- Added Quartz-style DOM/DOW modifiers (`L`, `W`, `LW`, `#`, `?`). (T-005)
- Added cron macros (`@yearly`, `@monthly`, `@weekly`, `@daily`, `@hourly`, `@reboot`). (T-006)
- Added support for trailing `#` comments and flexible whitespace in cron strings. (T-010)
- Added cron dialect parsing for Standard 5-field and Quartz seconds-first formats. (T-008)
- Added `TCronSchedulePlan.GetNextOccurrences` for schedule previews. (T-011)
- Added basic human-readable schedule descriptions. (T-012)
- Added misfire policies (Skip, FireOnceNow, CatchUpAll) with a bounded catch-up limit. (T-013)
- Added per-event timezone support (`LOCAL`, `UTC`, `UTC±HH:MM`) and DST policies (`DstSpringPolicy`, `DstFallPolicy`). (T-007)
- Added business-calendar exclusions (`WeekdaysOnly`, `ExcludedDatesCsv`, `BlackoutStartTime`/`BlackoutEndTime`). (T-014)
- Added deterministic hash/jitter cron tokens: `H`, `H/step`, `H(min-max)`, `H(min-max)/step`. (T-009)
- Added regression tests for invoke-dispatch startup failures to ensure overlap state recovers after launch exceptions.
- Added regression tests that verify `ExecutionLimit` retries correctly after injected dispatch-start failures (`imThread` and `imTTask`). (T-038)
- Added a VCL backend test that enforces `ctVcl` creation only on the VCL main thread.
- Added regressions for Quartz seconds-first hashed DOW ranges (`H(1-7)`) and scheduler `DefaultInvokeMode := imDefault` normalization behavior.
- Added stress/robust tests for heap-mode execution, shadow parity churn coverage, and high-N scan-vs-heap benchmark assertions. (T-058, T-059)

### Changed
- Optimized UTC/fixed-offset timezone conversion paths by caching stable local-offset windows for UTC->local mapping and by avoiding repeated local-time conversions when DST ambiguity rules are not in play. (T-094)
- Reduced due-evaluation hot-path float-date overhead by caching integer tick units in scan/heap comparisons and heap entries, lowering repeated `TDateTime` conversion cost in tick loops. (T-095)
- Updated canonical build/test scripts to support `MAXCRON_DEBUG_SAFETY=1`, switching builds to `Debug` configuration for safety/lifetime validation lanes. (T-091)
- Reduced heap tick allocator overhead in `DoTickAtHeap` by replacing per-tick `TList` staging allocations with dynamic-array buffers; benchmark compare against `maxcron-benchmarks-20260224-112107.csv` showed elapsed improvements (`sparse_high_n_heap -31.24%`, `sparse_high_n_auto -4.20%`, `adversarial_auto_no_budget -1.28%`, `adversarial_auto_budget -1.02%`).
- Reduced heap dense-tick reschedule overhead by reusing already-collected due-event references in `DoTickAtHeap` instead of repeating id->event dictionary/interface lookups before each heap push; benchmark compare against `maxcron-benchmarks-20260224-095249.csv` showed elapsed improvements (`sparse_high_n_heap -19.08%`, `sparse_high_n_auto -14.82%`, `adversarial_auto_no_budget -5.97%`, `adversarial_auto_budget -0.70%`). (T-087)
- Updated benchmark documentation with local (on-demand) perf-gate workflow and trend report generation commands; no scheduler/CI requirement. (T-085, T-086)
- Extended standalone benchmark summaries with elapsed median/p95/stddev and added `--compare=<baseline.csv>` mode for run-to-run delta reporting in console and Markdown output. (T-083)
- Added a guarded sparse-workload fast-promote path in auto mode so strongly sparse/high-cardinality low-churn phases can enter heap-stable earlier without waiting for a full trial window. (T-082)
- Reduced heap-mode lock churn by batching post-callback heap reschedule pushes under a single lock section per tick instead of one lock/relock per due event. (T-080)
- Changed auto dirty-signal sampling from binary mutation detection to normalized mutation density with bounded sensitivity scaling to better balance large-schedule stability and churn responsiveness. (T-081)
- Added a documented reference benchmark run (`2026-02-23`) with concrete sparse/adversarial metrics and conclusions, plus a concise production mode-selection guide for `scan`/`heap`/`auto`/`shadow`. (T-079)
- Expanded benchmark documentation with standalone runner usage (`build-and-run-benchmarks.*`), output artifact format, and interpretation guidance for sparse high-N and adversarial churn scenarios. (T-078)
- Expanded README benchmark guidance with runnable benchmark commands and expected outcomes across sparse and oscillation scenarios. (T-076)
- Extended auto diagnostics snapshot/log payload with switch-budget counters (`SwitchBudgetHits`, `SwitchBudgetCooldownTicks`, `SwitchBudgetRecentSwitches`) for runtime budget-tuning visibility. (T-073)
- Extended auto diagnostics snapshot/log payload with trial-failure backoff state (`TrialFailLevel`, `TrialFailCooldownTicks`) for runtime tuning visibility. (T-070)
- Expanded README with an auto-mode operations/tuning playbook (knob reference, archetype guidance, oscillation troubleshooting, rollout checklist). (T-063)
- Updated scheduler engine docs to cover `auto` mode behavior and explicit-mode override semantics. (T-060)
- Added README guidance for scheduler-engine selection (`scan`/`heap`/`shadow`) with high-N benchmark expectations for selecting heap mode under sparse-due workloads. (T-059)
- Changed scheduler ownership APIs to Id/snapshot model: removed public `Count`, `Events[]`, `Delete(Index)`, and `IndexOf`; added `Delete(Id)` for direct deletion by immutable event identity. (T-050)
- Added a README migration section mapping old index-based API calls to Id/snapshot equivalents. (T-053)
- Event names are now immutable after `Add(...)`; non-empty names are case-insensitive unique per scheduler; unnamed events remain supported. (T-049)
- Changed the public event handle API from concrete `TmaxCronEvent` class references to `IMaxCronEvent` interfaces, while keeping scheduler-owned registration/removal (`Delete/Clear`) semantics. (T-048)
- Clarified the README lifecycle usage contract for safe ownership/shutdown: use `Delete/Clear` instead of freeing events directly, avoid freeing scheduler from callbacks, and synchronize external concurrent reads/writes. (T-047)
- Changed the VCL help dialog to open help in an external browser instead of the legacy embedded control. (T-017)
- Updated the demo to include dialect/day-match selectors and samples for Quartz modifiers and rollover cases. (T-019)
- Updated the help dialog temp-file path handling to use RTL helpers and report ShellExecute failures. (T-020)
- Added regression tests that expose DST fall-back second-instance semantics, `cMaxAttempts` false-disable behavior with long blackout windows, and non-atomic `Add(...)` overload behavior on invalid plans.
- `NumOfExecutionsPerformed` now counts executed callbacks (after overlap rules). (T-021)
- ExecutionLimit now counts actual executions after overlap rules, not skipped/coalesced due hits. (T-027)
- Updated the demo UI with invoke/overlap/misfire controls and expanded samples. (T-015)
- Updated README to reflect misfire policies, macros, and planned features. (T-016)
- Expanded unit and stress robustness coverage for DST fall variants, timezone/exclusion/blackout parser edges, hash token failures, default-policy propagation, final-dispatch regressions, and mixed-feature concurrency. (T-028, T-029, T-030, T-031, T-032, T-033, T-034, T-035, T-036)
- Clarified documentation that `imMainThread` dispatch requires an active main-thread message pump (non-UI/service hosts should use async/thread invoke modes).

### Fixed
- Fixed `TmaxCron.Free` lifecycle/thread-safety by rejecting `ctVcl` backend free calls off the main thread and by restoring shared-state attachment when a fail-fast free attempt is aborted while callbacks are still active.
- Fixed scheduler default-policy races by synchronizing default invoke/day-match/dialect/misfire reads/writes across callback and mutation threads.
- Fixed heap rebuild complexity by switching to linear-time heapify during rebuild (`O(n)` instead of repeated `O(log n)` inserts). (T-060)
- Fixed unnamed-event deletion ergonomics by allowing `Delete(Event)` and `Delete(Id)` without index-based APIs. (T-050)
- Fixed CLI demo build path resolution by adding `..\lib\maxlogicfoundation` to demo unit search path. (T-053)
- Added `Delete(const aName: string)` with case-insensitive named-event lookup; unnamed events are rejected by `Delete(Name)`. (T-049)
- Fixed MAXCRON_TESTS queued pre-acquire hook handling to roll back state and exit the queued path without rethrowing through `CheckSynchronize`, preventing intermittent dispatch-regression hangs. (T-045)
- Fixed serialized overlap-chain dispatch-start failures to roll back reserved execution/overlap state, so retry ticks can continue instead of wedging after injected launch failures. (T-044)
- Fixed scheduler `DefaultMisfirePolicy := mpDefault` handling by normalizing to `mpCatchUpAll`, so default-policy events keep honoring configured catch-up limits. (T-043)
- Fixed Quartz seconds-first hashed DOW ranges to accept one-based values (`H(1-7)` / `H(1-7)/step`) consistently with Quartz numbering.
- Fixed scheduler default invoke-mode handling by normalizing `DefaultInvokeMode := imDefault` to `imMainThread`, preventing inline worker-thread dispatch from sentinel mode.
- Fixed `@weekly` macro expansion in `cdQuartzSecondsFirst` to use Quartz DOW numbering (`1=Sun`) instead of `0`, so macro parsing now works consistently across dialects. (T-039)
- Fixed overlap-state rollback when invoke dispatch startup fails (thread/task launch exception), preventing `omSkipIfRunning`/serialize lock-up and shutdown hangs.
- Fixed dispatch-start rollback to restore reserved execution budget so failed launches do not consume `ExecutionLimit`. (T-038)
- Fixed queued main-thread pre-acquire failure rollback so failed dispatch attempts no longer consume `ExecutionLimit` or leave overlap state wedged.
- Fixed `ctVcl` backend creation to fail fast off the VCL main thread instead of creating an unsafe VCL timer instance.
- Fixed callback shutdown protection to reject `TmaxCron.Free` while callbacks are still executing across threads, preventing cross-thread callback/destructor deadlocks.
- Fixed DST fall-back second-instance dispatch semantics: `dfpRunTwice` and `dfpRunOncePreferSecondInstance` now wait for the repeated wall-clock pass instead of firing second-instance behavior on the first ambiguous pass.
- Fixed callback/dispatch lifetime pinning by replacing raw scheduler-owner dereference paths with a shared-state interface used by worker/queued dispatch code.
- Fixed name/id event index lookups to use dictionary-backed indexes (`Delete(Name)`, `Delete(Id)`, duplicate name checks) instead of linear scans.
- Fixed `DstFallPolicy=dfpRunOncePreferSecondInstance` to keep the same ambiguous local wall-clock schedule time instead of shifting by DST delta.
- Fixed timezone offset parsing to reject malformed values like `UTC++2` and `UTC+2:3`; accepted format remains `UTC+/-HH[:MM]`.
- Fixed `DstFallPolicy=dfpRunTwice` to schedule both ambiguous fall-back instances at the same local wall-clock time.
- Fixed long exclusion windows to avoid false scheduler disable when search iteration limits are reached.
- Fixed `Add(name, plan, callback)` overloads to be atomic: invalid plans no longer leave partially-added events.
- Fixed day-match mode setters to recalculate `NextSchedule` immediately for enabled events when we change `DayMatchMode` directly or update scheduler `DefaultDayMatchMode` for `dmDefault` events.
- Fixed @reboot macro to be rejected outside cdMaxCron where ExecutionLimit is unavailable. (T-025)
- Fixed ctPortable timers to run ticks directly without requiring a main-thread queue. (T-026)
- Fixed ExecutionLimit parsing to reject invalid, negative, or overflow values instead of silently defaulting. (T-024)
- Fixed missing interface uses for timer backends that prevented compilation in some setups. (T-023)
- Fixed cron parsing to reject malformed tokens like trailing commas. (T-001)
- Fixed schedule calculation for impossible DOM/month combos and default re-parse behavior (e.g., seconds default to 0). (T-001)
- Fixed imMaxAsync keep-alive cleanup to avoid leaking async resources after callbacks. (T-001)
- Fixed imMaxAsync to fall back safely when async scheduling fails or returns nil. (T-020)
- Fixed month-relative DOM/DOW modifiers to recompute after advancing to the next month. (T-018)
- Fixed ValidFrom/ValidTo updates to reschedule enabled events immediately. (T-020)
- Fixed queued main-thread callbacks to avoid holding execution depth before they run, preventing shutdown hangs. (T-022)
- Fixed dialect changes to re-parse existing event plans for correct semantics. (T-022)
- Fixed schedule timing to use the scheduled fire time and avoid extra-second drift. (T-021)
- Fixed Quartz day-of-week numbering to use 1-7 in seconds-first dialect. (T-021)
- Fixed TPlan.Text output to respect the selected dialect. (T-021)
- Fixed EventPlan parsing to validate before applying updates. (T-021)
- Fixed flaky skip-if-running execution-limit test behavior by making retry timing deterministic. (T-027)
- Fixed a queued main-thread callback lifetime race by atomically acquiring event execution before dispatch.
- Fixed re-entrant scheduler shutdown deadlocks by rejecting `TmaxCron.Free` from inside scheduler-owned callbacks.
- Fixed `DoTickAt` tick-depth unwinding to remain balanced even when snapshot preparation raises.

# Changelog

All notable user-visible changes to this project will be documented in this file.

## [Unreleased]

### Added
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

# Changelog

All notable user-visible changes to this project will be documented in this file.

## [Unreleased]

### Added
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

### Changed
- Changed the VCL help dialog to open help in an external browser instead of the legacy embedded control. (T-017)
- Updated the demo to include dialect/day-match selectors and samples for Quartz modifiers and rollover cases. (T-019)
- Updated the help dialog temp-file path handling to use RTL helpers and report ShellExecute failures. (T-020)
- Added regression tests that expose DST fall-back second-instance semantics, `cMaxAttempts` false-disable behavior with long blackout windows, and non-atomic `Add(...)` overload behavior on invalid plans.
- `NumOfExecutionsPerformed` now counts executed callbacks (after overlap rules). (T-021)
- ExecutionLimit now counts actual executions after overlap rules, not skipped/coalesced due hits. (T-027)
- Updated the demo UI with invoke/overlap/misfire controls and expanded samples. (T-015)
- Updated README to reflect misfire policies, macros, and planned features. (T-016)
- Expanded unit and stress robustness coverage for DST fall variants, timezone/exclusion/blackout parser edges, hash token failures, default-policy propagation, final-dispatch regressions, and mixed-feature concurrency. (T-028, T-029, T-030, T-031, T-032, T-033, T-034, T-035, T-036)

### Fixed
- Fixed `DstFallPolicy=dfpRunTwice` to schedule both ambiguous fall-back instances at the same local wall-clock time.
- Fixed long exclusion windows to avoid false scheduler disable when search iteration limits are reached.
- Fixed `Add(name, plan, callback)` overloads to be atomic: invalid plans no longer leave partially-added events.
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

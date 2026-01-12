# Tasks

## In Progress

## Next – Today

## Next – This Week

## Next – Later


### T-013 Add misfire policy handling
Summary: Define what happens when the scheduler is delayed or the machine sleeps.

Details:
- Policies: `Skip`, `FireOnceNow`, `CatchUpAll` (bounded).
- Add per-event override with scheduler default.
- Add tests simulating delayed ticks.

Likely files to touch/read: `maxCron.pas`, `tests/unit/TestLifecycle.pas`, `tests/unit/TestScheduleNext.pas`, `README.md`


### T-015 Update demos to showcase more features
Summary: Expand demo projects to showcase advanced schedule features and invoke modes.

Details:
- Add demos for overlap modes, macros, and cron dialects (once implemented).
- Include timezone/DST examples when that feature lands.

Likely files to touch/read: `demo/`, `README.md`, `maxCron.pas`

### T-016 Update README after new features land
Summary: Refresh README examples and feature list after we add new cron features.

Details:
- Add examples for macros, modifiers, dialects, and timezone/DST.
- Document misfire policy, jitter, and comment handling.

Likely files to touch/read: `README.md`

## Blocked / OnHold

### T-014 Add business calendar/exclusions
Summary: Support exclusions like holidays, weekdays-only, and blackout windows.

Details:
- Provide an exclusion list or calendar hook.
- Ensure exclusions interact correctly with DOM/DOW matching.
- Add tests for holiday and blackout cases.

Likely files to touch/read: `maxCron.pas`, `tests/unit/TestScheduleNext.pas`, `README.md`


### T-007 Add per-event timezone + explicit DST policies
Summary: Add a per-event timezone (default = local) and explicit DST handling rules.

Details:
- Add `TimeZoneId`/`TimeZone` on events (default local).
- Evaluate “now” and “next fire time” in the event timezone.
- Decide accepted IDs up front (IANA, Windows, or both) and normalize.
- DST policies: `DstSpringPolicy = Skip | RunAtNextValidTime`, `DstFallPolicy = RunOnce | RunTwice | RunOncePreferFirst/SecondInstance`.
- Add tests around DST transitions for each policy.

Likely files to touch/read: `maxCron.pas`, `tests/unit/TestScheduleNext.pas`, `tests/unit/TestValidRange.pas`, `README.md`

### T-009 Add hash/jitter syntax (H) with deterministic seed
Summary: Support `H` tokens for jittered schedules using a stable hash seed.

Details:
- Parse `H`, `H/15`, and optional `H(0-29)` range forms.
- Use a stable hash of event name/id to pick a deterministic value.
- Add tests to ensure stable output and range enforcement.

Likely files to touch/read: `maxCron.pas`, `tests/unit/TestCronParsing.pas`, `tests/unit/TestScheduleNext.pas`, `README.md`



## Done

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

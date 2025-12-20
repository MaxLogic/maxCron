# Tasks

## In Progress

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

## Next – Today

## Next – This Week

## Next – Later

## Blocked

## Done

### T-000 Add initial DUnitX runner + overlap tests
Summary: Added DUnitX runner and initial overlap tests (serialize vs serialize-coalesce) plus basic MakePreview check.

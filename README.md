# maxCron 
Flexible, lightweight CRON compliant scheduler written in Delphi. 

Homepage: https://maxlogic.eu/portfolio/maxcron-scheduler-for-delphi/



## Main features:

- Compatible with most of what CRON is offering
- Multiple cron dialects (standard 5-field, maxCron 5-8 field, Quartz seconds-first)
- Quartz-style DOM/DOW modifiers and cron macros
- Per-event overlap, invoke, and misfire policies
- Execution limits and ValidFrom/ValidTo ranges
- Per-event timezone + DST handling policies
- Business calendar controls (weekdays-only, holiday list, blackout windows)
- Deterministic hash/jitter syntax (`H`, `H/step`, `H(min-max)/step`)
- Schedule previews and human-readable descriptions
- Comments and flexible whitespace support
- Pluggable schedule persistence + restore API (`ScheduleStore`, `SaveScheduleState`, `RestoreScheduleState`)
- Per-event retry/backoff controls with dead-letter hooks
- Scheduler-wide global concurrency and dispatch-rate caps
- Explicit graceful shutdown API with timeout policies (wait/cancel/force)
- Optional pooled `imThread` dispatch mode for burst-heavy workloads


# Recommended scheduler usage
```delphi
procedure TForm1.FormCreate(Sender: TObject);
var
  lEvent: IMaxCronEvent;
begin
  // create a new TmaxCron scheduler that will hold our events
  CronScheduler := TmaxCron.Create;

  // 5-field plans are minute/hour/day/month/day-of-week in the default cdMaxCron dialect.
  lEvent := CronScheduler.Add('Event1', '*/1 * * * *', OnScheduleEvent1).Run;
  lEvent := CronScheduler.Add('Event2', '*/5 * * * *', OnScheduleEvent2).Run;

  // we can also build the event in steps
  lEvent := CronScheduler.Add('EventWorker');
  lEvent.EventPlan := '0 9 * * 1-5'; // weekdays at 09:00
  lEvent.OnScheduleProc :=
    procedure(aEvent: IMaxCronEvent)
    begin
      OnScheduleTrigger(aEvent);
    end;
  lEvent.Run;

  // using the shorter overload with an anonymous method
  lEvent := CronScheduler.Add('Event4', '0 12 * * 1-5',
    procedure(aEvent: IMaxCronEvent)
    begin
      OnScheduleTrigger(aEvent);
    end).Run;
end;
```

Important usage notes:

- `Add(...)` registers an event but does not start it. Call `Run` when the event is fully configured.
- In the default `cdMaxCron` dialect, 5 fields mean `Minute Hour DayOfMonth Month DayOfWeek`.
- If we want a seconds-first Quartz expression, set `Dialect := cdQuartzSecondsFirst` (or `DefaultDialect`) before assigning the plan.

## Timer backend selection

By default `TmaxCron` uses `ctAuto`:

- If created on the VCL main thread: uses `TTimer` (`ctVcl`)
- Otherwise: uses the threaded portable timer (`ctPortable`)

```delphi
CronScheduler := TmaxCron.Create(ctAuto);
// or force one:
CronScheduler := TmaxCron.Create(ctVcl);
CronScheduler := TmaxCron.Create(ctPortable);
```

`ctVcl` must be created on the VCL main thread. Creating `ctVcl` from a worker thread now raises an exception.

## Scheduler engine selection (scan / heap / shadow / auto)

`TmaxCron` reads `MAXCRON_ENGINE` once during scheduler creation:

- `scan` (default): scans all registered events each tick.
- `heap`: keeps a min-heap of next-due schedules and processes only due candidates plus rebuilds after schedule/registry changes.
- `shadow`: diagnostic mode that computes both scan and heap due sets and raises on divergence; execution still runs through heap.
- `auto`: adaptive mode that starts in scan and switches between scan/heap using hysteresis and cooldown.

Set the engine before we create the scheduler:

```bash
export MAXCRON_ENGINE=heap
```

```cmd
set MAXCRON_ENGINE=heap
```

```bash
export MAXCRON_ENGINE=auto
```

Engine guidance:

- Use `scan` for smaller event counts or very high churn where almost every tick mutates many schedules.
- Use `heap` for high-cardinality schedules where only a small subset is due per tick.
- Use `shadow` only for CI/test verification because it intentionally does extra work each tick.
- Use `auto` when workload shape is not stable and we want runtime adaptation without hard-coding one engine.

Mode quick guide (production):

| Mode | Best fit | Caveat |
| --- | --- | --- |
| `scan` | Small/medium schedules, churn-heavy workloads, simple deterministic baseline | Work scales with total event count (`O(n)` per tick) |
| `heap` | High-cardinality sparse-due workloads where few events are due each tick | Extra maintenance/rebuild work under frequent mutations |
| `auto` | Mixed or changing workloads where we want adaptive behavior at runtime | Requires observability/tuning when workload oscillates |
| `shadow` | CI and correctness validation of scan-vs-heap parity | Intentionally slower; not for normal production runtime |

`auto` mode policy (internal):

- Enter heap trial when event-count EMA is high, due-density EMA stays low, and mutation/dirty EMA stays low.
- In strongly sparse/high-cardinality low-churn phases, auto mode can fast-promote directly to heap-stable.
- Promote to heap-stable only if measured heap tick cost beats scan baseline by margin.
- Fall back to scan when due density rises, churn rises, event count drops, or heap stops showing benefit.
- Apply hold counters and cooldown to avoid scan/heap thrashing.
- Apply trial-failure re-entry backoff so repeated failed heap trials cannot immediately retrigger.
- Apply rolling switch-budget caps to hard-bound switch rate under adversarial oscillation patterns.
- Require minimum scan/heap performance samples before ratio-based promote/demote checks.
- Increase cooldown adaptively when rapid consecutive switches are detected.
- If explicit `scan`, `heap`, or `shadow` is selected, auto-controller logic is bypassed.

### Auto tuning knobs (`MAXCRON_AUTO_*`)

`auto` mode can be tuned per deployment through environment variables (read once during scheduler creation):

| Variable | Default | Meaning | Bounds |
| --- | --- | --- | --- |
| `MAXCRON_AUTO_ENTER_EVENTS` | `256` | Minimum event-count EMA to enter heap trial | clamped to `[1..1000000]` |
| `MAXCRON_AUTO_EXIT_EVENTS` | `160` | Event-count EMA at or below this exits heap | clamped to `[0..1000000]`, then normalized to `<= ENTER_EVENTS` |
| `MAXCRON_AUTO_ENTER_DUE_DENSITY` | `0.25` | Maximum due-density EMA (`due/visited`) allowed to enter heap trial | clamped to `[0.0..1.0]` |
| `MAXCRON_AUTO_EXIT_DUE_DENSITY` | `0.60` | Due-density EMA at or above this exits heap | clamped to `[0.0..1.0]`, then normalized to `>= ENTER_DUE_DENSITY` |
| `MAXCRON_AUTO_ENTER_DIRTY` | `0.15` | Max dirty/churn EMA allowed to enter heap trial | clamped to `[0.0..1.0]` |
| `MAXCRON_AUTO_EXIT_DIRTY` | `0.40` | Dirty/churn EMA at or above this exits heap | clamped to `[0.0..1.0]`, then normalized to `>= ENTER_DIRTY` |
| `MAXCRON_AUTO_ENTER_HOLD` | `3` | Consecutive enter-candidate ticks required before heap trial | clamped to `[1..1024]` |
| `MAXCRON_AUTO_EXIT_HOLD` | `3` | Consecutive exit-candidate ticks required before leaving heap-stable | clamped to `[1..1024]` |
| `MAXCRON_AUTO_TRIAL_TICKS` | `32` | Heap trial length before promote/fallback decision | clamped to `[1..4096]` |
| `MAXCRON_AUTO_COOLDOWN` | `128` | Cooldown ticks after each engine switch | clamped to `[0..8192]` |
| `MAXCRON_AUTO_TRIAL_FAIL_COOLDOWN` | `16` | Base re-entry backoff ticks after failed heap trials (applies exponentially for consecutive failures; `0` disables) | clamped to `[0..8192]` |
| `MAXCRON_AUTO_SWITCH_BUDGET_WINDOW` | `256` | Rolling window size (ticks) used for switch-rate budgeting (`0` disables) | clamped to `[0..65536]` |
| `MAXCRON_AUTO_SWITCH_BUDGET_MAX` | `12` | Maximum switches allowed inside the budget window (`0` disables) | clamped to `[0..1024]`, normalized to `<= WINDOW` |
| `MAXCRON_AUTO_SWITCH_BUDGET_COOLDOWN` | `64` | Cooldown ticks applied when switch budget is exceeded (`0` disables) | clamped to `[0..8192]` |
| `MAXCRON_AUTO_PROMOTE_RATIO` | `0.85` | Heap promotion threshold (`heap_us <= scan_us * ratio`) | clamped to `[0.25..4.0]` |
| `MAXCRON_AUTO_DEMOTE_RATIO` | `1.05` | Heap demotion threshold (`heap_us > scan_us * ratio`) | clamped to `[0.25..4.0]`, then normalized to `> PROMOTE_RATIO` |
| `MAXCRON_AUTO_DIAG_LOG_INTERVAL` | `0` | Emit periodic auto diagnostics logs every N auto ticks (`0` = disabled) | clamped to `[0..1000000]` |

Parsing rules:

- Missing variables use built-in defaults.
- Invalid numeric text is ignored for that setting (default remains active).
- Out-of-range numeric values are clamped to safe bounds.
- Invalid settings never raise startup exceptions.

### Auto mode tuning by workload archetype

- Sparse due, high cardinality, low churn: lower `ENTER_EVENTS` (for example `128-256`), keep `ENTER_DUE_DENSITY` conservative (`0.15-0.30`), and keep `TRIAL_TICKS` moderate (`16-48`) to enter heap sooner.
- Mixed workload with periodic bursts: keep defaults first, then tune `ENTER_HOLD`/`EXIT_HOLD` upward (`3-6`) if switches are too frequent.
- Dense-due bursts (many events due each tick): lower `EXIT_DUE_DENSITY` so auto mode leaves heap sooner during burst windows.
- Churn-heavy (frequent stop/run or plan edits): raise `ENTER_EVENTS`, raise `ENTER_HOLD`, and tune `TRIAL_FAIL_COOLDOWN` upward if failed heap trials retry too aggressively.
- Adversarial oscillation patterns: tighten `SWITCH_BUDGET_MAX`, shorten `SWITCH_BUDGET_WINDOW`, and raise `SWITCH_BUDGET_COOLDOWN` to enforce a hard switch-rate ceiling.

### Oscillation troubleshooting

If we observe scan/heap oscillation in logs or profiling:

- Increase hysteresis gap: lower `PROMOTE_RATIO` and/or raise `DEMOTE_RATIO`.
- Increase hold counters (`ENTER_HOLD`, `EXIT_HOLD`) so one short burst does not trigger flips.
- Increase `COOLDOWN` so post-switch settling time is longer.
- Increase `TRIAL_FAIL_COOLDOWN` so repeated failed heap trials re-enter less frequently.
- Lower `SWITCH_BUDGET_MAX` and/or raise `SWITCH_BUDGET_COOLDOWN` to clamp maximum switch frequency.
- If churn remains continuously high, pin to `scan` explicitly (`MAXCRON_ENGINE=scan`) for that deployment.

### Auto rollout checklist

1. Run baseline in explicit `scan` mode and capture tick latency/cpu.
2. Canary with `MAXCRON_ENGINE=auto` on a representative subset.
3. Verify switch behavior and callback correctness under peak + churn phases.
4. Tune `MAXCRON_AUTO_*` only when measured behavior is unstable or suboptimal.
5. Roll out broadly with the tuned values and keep `scan` override ready for quick rollback.

### Auto diagnostics snapshot API

We can query the adaptive controller state at runtime:

```delphi
var
  Diag: TMaxCronAutoDiagnostics;
begin
  if CronScheduler.TryGetAutoDiagnostics(Diag) then
    Memo1.Lines.Add(Format('%s -> %s (%s) switches=%d reason=%s',
      [Diag.ConfiguredEngine, Diag.EffectiveEngine, Diag.AutoState, Int64(Diag.SwitchCount), Diag.LastSwitchReason]));
end;
```

`TryGetAutoDiagnostics` returns `True` only when `MAXCRON_ENGINE=auto`; otherwise it returns `False`.
The snapshot includes EWMAs, sample counters, cooldown/backoff state (including trial-failure and switch-budget counters), and last switch reason for tuning/operations visibility.

### Watchdog diagnostics + metrics snapshot API

We can query scheduler watchdog counters and threshold breaches at runtime:

```delphi
var
  Watchdog: TMaxCronWatchdogDiagnostics;
begin
  if CronScheduler.TryGetWatchdogDiagnostics(Watchdog) then
    Memo1.Lines.Add(Format('lagMs=%d inFlight=%d breach=%s',
      [Watchdog.TickLagMs, Watchdog.InFlightCallbacks, BoolToStr(Watchdog.AnyThresholdBreached, True)]));
end;
```

Watchdog thresholds are configured when we create the scheduler:
- `MAXCRON_WATCHDOG_MAX_TICK_LAG_MS` (default `2500`)
- `MAXCRON_WATCHDOG_MAX_QUEUE_DEPTH` (default `1`)
- `MAXCRON_WATCHDOG_MAX_INFLIGHT` (default `128`)
- `MAXCRON_WATCHDOG_MAX_SWITCH_CHURN` (default `8`)
- `MAXCRON_WATCHDOG_SWITCH_WINDOW` (default `256` ticks)

We can also fetch a structured export-friendly snapshot:

```delphi
var
  Snapshot: TMaxCronMetricsSnapshot;
begin
  Snapshot := CronScheduler.GetMetricsSnapshot;
  Memo1.Lines.Add(Format('engine=%s effective=%s visited=%d',
    [Snapshot.ConfiguredEngine, Snapshot.EffectiveEngine, Int64(Snapshot.TickEventsVisited)]));
end;
```

`GetMetricsSnapshot` includes capture timestamp, configured/effective engine state, auto switch count, cumulative tick/rebuild counters, and embedded watchdog fields.

### Auto diagnostics periodic logging (opt-in)

For production/canary operations, we can emit periodic diagnostics without code changes:

```bash
export MAXCRON_ENGINE=auto
export MAXCRON_AUTO_DIAG_LOG_INTERVAL=10
```

`MAXCRON_AUTO_DIAG_LOG_INTERVAL` is read during scheduler creation. When it is greater than `0`, maxCron emits a diagnostics line every N auto-controller ticks via `OutputDebugString`. `0` keeps logging disabled.

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

Run benchmark scenarios directly:

```cmd
tests\maxCronStressTests.exe --run:TestHeavyStressMixed.TTestHeavyStressMixed.EngineBenchmark_ScanVsHeap_HighN
tests\maxCronStressTests.exe --run:TestHeavyStressMixed.TTestHeavyStressMixed.EngineBenchmark_AutoVsScan_SparseHighN
tests\maxCronStressTests.exe --run:TestHeavyStressMixed.TTestHeavyStressMixed.EngineBenchmark_AutoSwitchBudget_AdversarialChurn
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

### Reference benchmark run (this machine)

Reference command used on `PAWEL3` (`2026-02-23`, `15` iterations, `2` warmup):

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

## How a job is executed (per-event)

Each event can override how its callback is invoked:

```delphi
CronScheduler.DefaultInvokeMode := imMainThread; // default

NewSchedule := CronScheduler.Add('BackgroundJob', '* * * * * * * 0');
NewSchedule.InvokeMode := imMaxAsync; // or imTTask / imThread / imMainThread
NewSchedule.Run;
```

If we assign `imDefault` to `CronScheduler.DefaultInvokeMode`, maxCron normalizes it to `imMainThread`.

Note: if we execute off the VCL main thread, we must not touch UI directly.

Important: `imMainThread` dispatch relies on a live main-thread message pump.
In service/console/non-VCL hosts (or any host without pumping), queued callbacks may never run.
For those hosts we should use `imMaxAsync`, `imTTask`, or `imThread`.

If dispatch startup fails (for example, task/thread launch raises, a queued main-thread callback fails before execution acquire, or a serialized-chain continuation launch fails), maxCron rolls back overlap state and execution reservations so future ticks continue normally and `ExecutionLimit` is not consumed by failed launches.
Our dispatch-start rollback regressions also include repeated serialized retry runs to keep this recovery path stable under tight tick timing.

### Pooled `imThread` dispatch (burst optimization)

For `imThread`, maxCron can reuse runtime worker threads instead of creating one anonymous thread per fire:

```bash
export MAXCRON_THREAD_DISPATCH_POOL=1
```

```cmd
set MAXCRON_THREAD_DISPATCH_POOL=1
```

Enabled values: `1` or `true` (case-insensitive). Any other value keeps the legacy thread-per-fire path.

### Retry/backoff + dead-letter hooks

Each event can retry callback failures and emit a dead-letter callback after retries are exhausted:

```delphi
NewSchedule.RetryMaxAttempts := 3;         // retries after the first attempt
NewSchedule.RetryInitialDelayMs := 50;     // initial delay before first retry
NewSchedule.RetryBackoffMultiplier := 2.0; // exponential factor
NewSchedule.RetryMaxDelayMs := 2000;       // cap per-retry delay

NewSchedule.OnDeadLetterProc :=
  procedure(Sender: IMaxCronEvent; const aErrorText: string; const aAttemptCount: Integer)
  begin
    // log, alert, or enqueue for manual handling
  end;
```

### Persistent schedule save/restore

We can plug in persistent storage for scheduler state:

```delphi
type
  TMyScheduleStore = class(TInterfacedObject, IMaxCronScheduleStore)
  public
    procedure Save(const aEvents: TArray<TMaxCronPersistedEvent>);
    function TryLoad(out aEvents: TArray<TMaxCronPersistedEvent>): Boolean;
  end;

CronScheduler.ScheduleStore := TMyScheduleStore.Create;
CronScheduler.SaveScheduleState;
CronScheduler.RestoreScheduleState(True); // replace existing events
```

Persistence captures event configuration/state metadata (plan, policies, counters, next schedule). Callback handlers themselves are not serialized and should be rebound by the host after restore when needed.

### Global dispatch caps

We can cap aggregate callback throughput across all events:

```delphi
CronScheduler.GlobalMaxConcurrentCallbacks := 32; // 0 = disabled
CronScheduler.GlobalMaxDispatchPerSecond := 200;  // 0 = disabled
```

Environment alternatives (read at scheduler creation):
- `MAXCRON_GLOBAL_MAX_CONCURRENT`
- `MAXCRON_GLOBAL_MAX_DISPATCH_PER_SECOND`

### Graceful shutdown API

`Shutdown` lets us stop new dispatch and optionally drain running callbacks:

```delphi
if not CronScheduler.Shutdown(5000, spWait) then
  // timeout reached before full drain
```

Policies:
- `spWait`: stop new work and wait for in-flight callbacks up to timeout.
- `spCancel`: clear schedules first, then wait for in-flight callbacks up to timeout.
- `spForce`: clear schedules and return immediately (reports whether work was still running).

After shutdown starts, `Add(...)` raises and timer-driven ticks are ignored.

Safety note: we must not call `TmaxCron.Free` from one of its own callbacks.
That re-entrant shutdown path is now rejected with an exception to prevent deadlocks.
Free the scheduler from outside callback context.

## Usage contract (required)

For safe production use we should follow these lifecycle rules:

- `Add(...)` only registers the event. New events start disabled; call `Run` (preferred) or set `Enabled := True` after configuration.
- `IMaxCronEvent` is an interface handle. Event registration lifetime is managed by `TmaxCron`.
- Every event has an immutable `Id` assigned by `TmaxCron` when we call `Add(...)`.
- Event names are optional. If provided, they are case-insensitive unique and immutable after `Add(...)`.
- We can remove schedules by handle (`Delete(Event)`), by id (`Delete(Event.Id)`), or by name (`Delete('EventName')`).
- `Delete('EventName')` applies to named events only. Unnamed events should be removed by handle or id (or `Clear`).
- `Count`, `Events[]`, `Delete(Index)`, and `IndexOf` are no longer part of the public API.
- For stable inspection, use `Snapshot` to get an array copy of registered events.
- We should free `TmaxCron` only from outside its callback context.
- We should avoid long-blocking callbacks during shutdown; if callbacks can block, we should first stop upstream work and let callbacks drain before destroying the scheduler.

If we follow this contract, maxCron stays on the intended ownership and shutdown path.

Snapshot/list example:

```delphi
var
  Events: TArray<IMaxCronEvent>;
begin
  Events := CronScheduler.Snapshot;
  if Length(Events) > 0 then
    CronScheduler.Delete(Events[0].Id);
end;
```

## Migration from index API

If we used older index-based calls, migrate as follows:

- `CronScheduler.Count` -> `Length(CronScheduler.Snapshot)`
- `CronScheduler.Events[i]` -> `CronScheduler.Snapshot[i]`
- `CronScheduler.Delete(i)` -> `CronScheduler.Delete(Event.Id)` (or `Delete(Event)` / `Delete('Name')`)
- `CronScheduler.IndexOf(Event)` -> iterate over `Snapshot` and compare `Id`

Prefer storing event handles (`IMaxCronEvent`) or immutable `Id` values in our app code, instead of relying on collection positions.

## Overlap handling (per-event)

When a schedule fires again while a previous execution is still running:

```delphi
NewSchedule.OverlapMode := omAllowOverlap;        // default
NewSchedule.OverlapMode := omSkipIfRunning;       // drop overlapping fires
NewSchedule.OverlapMode := omSerialize;           // queue and run 1-by-1
NewSchedule.OverlapMode := omSerializeCoalesce;   // serialize, but keep backlog <= 1
```

`NumOfExecutionsPerformed` counts actual callback executions (after overlap rules), not just schedule hits.
`ExecutionLimit` caps actual executions (after overlap rules); skipped/coalesced overlaps do not consume the limit.

## Misfire handling (per-event)

When the scheduler is delayed or the machine sleeps, we can control how missed occurrences are handled:

```delphi
CronScheduler.DefaultMisfirePolicy := TmaxCronMisfirePolicy.mpCatchUpAll; // default
CronScheduler.DefaultMisfireCatchUpLimit := 1; // max catch-up per tick (min 1)

NewSchedule.MisfirePolicy := TmaxCronMisfirePolicy.mpFireOnceNow; // per-event override
```

Policies:
- `mpSkip`: skip missed occurrences and advance to the next time after `now`.
- `mpFireOnceNow`: execute once, then advance to the next time after `now`.
- `mpCatchUpAll`: execute missed occurrences sequentially, bounded per tick by `DefaultMisfireCatchUpLimit`.

If we assign `mpDefault` to `CronScheduler.DefaultMisfirePolicy`, maxCron normalizes it to `mpCatchUpAll`.

When exclusions (weekdays/holidays/blackout) create long filtered ranges, maxCron advances the search cursor in larger steps and keeps the event enabled until a true terminal condition is reached.

## Timezone + DST policies (per-event)

Each event can evaluate cron time in its own timezone:

```delphi
NewSchedule.TimeZoneId := 'LOCAL';      // default
NewSchedule.TimeZoneId := 'UTC';
NewSchedule.TimeZoneId := 'UTC+02:30';  // fixed offset
```

DST behavior is configurable per event:

```delphi
NewSchedule.DstSpringPolicy := dspSkip;              // default
NewSchedule.DstSpringPolicy := dspRunAtNextValidTime;

NewSchedule.DstFallPolicy := dfpRunOnce;             // default
NewSchedule.DstFallPolicy := dfpRunTwice;
NewSchedule.DstFallPolicy := dfpRunOncePreferFirstInstance;
NewSchedule.DstFallPolicy := dfpRunOncePreferSecondInstance;
```

`dfpRunTwice` executes both ambiguous fall-back instances at the same local wall-clock time.
For `dfpRunTwice` and `dfpRunOncePreferSecondInstance`, maxCron now waits for the repeated wall-clock pass
after fallback instead of dispatching the second-instance semantics immediately on the first pass.

Performance note: UTC/fixed-offset events use a stable local-offset cache for UTC->local conversion when the target UTC hour is outside DST-transition ambiguity, which reduces repeated timezone API calls in hot paths.

## Business calendar exclusions

We can apply common exclusion filters per event:

```delphi
NewSchedule.WeekdaysOnly := True;                              // skip Sat/Sun
NewSchedule.ExcludedDatesCsv := '2031-01-02,2031-01-03';      // YYYY-MM-DD list
NewSchedule.BlackoutStartTime := EncodeTime(9, 0, 0, 0);      // skip 09:00..
NewSchedule.BlackoutEndTime := EncodeTime(17, 0, 0, 0);       // ..until 17:00
```

These exclusions are applied after cron matching and before callback dispatch.

## Hash / jitter tokens

`H` picks deterministic values from a stable hash seed (event name).

```delphi
NewSchedule := CronScheduler.Add('ShardA');
NewSchedule.EventPlan := 'H * * * * * 0 0';         // hashed minute

NewSchedule := CronScheduler.Add('ShardB');
NewSchedule.EventPlan := 'H(0-29)/5 * * * * * 0 0'; // hashed start + step
```

Supported forms:
- `H`
- `H/step`
- `H(min-max)`
- `H(min-max)/step`

For unnamed events, maxCron uses the immutable event `Id` as the hash seed fallback.

In `cdQuartzSecondsFirst`, Day-of-Week hash ranges use Quartz numbering (`1..7`), so `H(1-7)` is valid.

## DOM / DOW matching

When **both** Day-of-Month and Day-of-Week are restricted (not `*`), classic crontab typically uses **OR** semantics.
maxCron supports both:

```delphi
CronScheduler.DefaultDayMatchMode := dmAnd; // legacy (both must match)
CronScheduler.DefaultDayMatchMode := dmOr;  // crontab-style (either may match)

NewSchedule.DayMatchMode := dmDefault; // use scheduler default
NewSchedule.DayMatchMode := dmAnd;
NewSchedule.DayMatchMode := dmOr;
```
For standard cron-like behavior in tools, we should set `DayMatchMode := dmOr`.

When we change `DayMatchMode` on an enabled event, or change scheduler `DefaultDayMatchMode` for enabled `dmDefault` events, maxCron recalculates `NextSchedule` immediately.

## Unit tests

DUnitX tests live under `tests/` (runner: `tests/maxCronTests.dpr`).
Our upstream-derived cron corpus used by tests is stored in `tests/data/cron-utils-unix-5field.txt`.
Negative corpus (expected to fail parse) is stored in `tests/data/cron-invalid.txt`.

Optional runners:
- `tests/maxCronVclTests.dpr` (GUI/VCL message pump; tests `ctVcl` / `ctAuto` behavior)
- `tests/maxCronStressTests.dpr` (heavier concurrency stress tests; ~30s)
- `tests/run-long-soak.sh` (cross-mode logical soak harness with report artifact output)

### Oracle fuzz and chaos fixtures

We can run the deterministic cron fuzz-oracle fixture (dialect/day-match combinations with brute-force oracle comparison):

```bash
tests/maxCronTests.exe --consolemode:quiet --run:TestCronFuzzOracle.TTestCronFuzzOracle.NextOccurrences_MatchBruteForceOracle
```

Replay knobs:
- `MAXCRON_FUZZ_SEED` (default `137031`)
- `MAXCRON_FUZZ_CASES` (default `36` per dialect/day-match combination)
- `MAXCRON_FUZZ_OCCURRENCES` (default `6`)
- `MAXCRON_FUZZ_SCAN_SECONDS` (default `604800`)

We can run async-boundary chaos coverage (queue-acquire injection, dispatch-start failure, callback exceptions, cancellation races):

```bash
tests/maxCronTests.exe --consolemode:quiet --run:TestChaosFaultInjection.TTestChaosFaultInjection
```

### Long soak harness (24h logical window)

The long-soak harness drives a mixed workload across `scan`, `heap`, and `auto` and writes a report artifact under `tests/__recovery/soak-reports/`.

```bash
MAXCRON_LONG_SOAK_HOURS=24 ./tests/run-long-soak.sh --modes=scan,heap,auto --cm:Quiet
```

Useful options:
- `--modes=scan,heap,auto` to select engines.
- `--hours=N` to override the logical soak window (defaults to `MAXCRON_LONG_SOAK_HOURS` or `24`).

The harness executes `TestLongSoak24h.EngineModes_LogicalSoak_NoMisses`, which validates:
- no callback loss/duplication envelope violations per mode,
- auto-mode switch envelope bounds,
- report artifact generation with full console output and exit code.

### Debug-safety lane

Use `MAXCRON_DEBUG_SAFETY=1` to run the canonical test scripts in `Debug` configuration (range/overflow/assert checks and leak diagnostics enabled by our test runners):

```bash
MAXCRON_DEBUG_SAFETY=1 ./build-and-run-tests.sh -cm:Quiet
MAXCRON_DEBUG_SAFETY=1 ./build-and-run-tests-stress.sh -cm:Quiet
```

`Add(name, plan, callback)` overloads are atomic: if `plan` is invalid, no partial event is kept in the scheduler.
Queued main-thread pre-acquire failure regressions use `SetMaxCronBeforeQueuedAcquireHook`; injected failures roll back state and exit the queued path without rethrowing through `CheckSynchronize`.

# Using the TPlan helper:
TPlan is a small record that lets us set parts in a friendly way and then convert them to a cron string.
```Delphi
  var plan: TPlan;

  plan.Reset;
  plan.Dialect := cdMaxCron; // or cdStandard / cdQuartzSecondsFirst
  // you can access any of the fields just like that:
  plan.Second := '30';
  // now create a new event using our new plan
  NewSchedule := CronScheduler.Add('EventFromTPlan', plan.Text, OnScheduleTrigger).Run;
```

# Preview upcoming occurrences

We can fetch the next N fire times from a parsed plan:

```delphi
var
  Plan: TCronSchedulePlan;
  Dates: TDates;
  Count: Integer;
begin
  Plan := TCronSchedulePlan.Create;
  try
    Plan.Parse('*/5 * * * * * 0 0');
    Count := Plan.GetNextOccurrences(10, Now, Dates);
    // Dates[0..Count-1] are our upcoming occurrences.
  finally
    Plan.Free;
  end;
end;
```

## Human-readable descriptions

We can generate a basic, deterministic description for logging or UI:

```delphi
var
  Plan: TCronSchedulePlan;
  Desc: string;
begin
  Plan := TCronSchedulePlan.Create;
  try
    Plan.Parse('*/5 * * * * * 0 0');
    Desc := Plan.Describe; // "Every 5 minutes"
  finally
    Plan.Free;
  end;
end;
```

# From / To valid range

Example how to use From / To valid range. The event will fire for one year, every sunday, every second hour, but only on 1,5 and 10 month in the year.

```Delphi

  // start time is in 50 seconds
  startDate := now() + 1 / 24 / 60 / 60 * 50;
  // and stop 5 minutes afterwards
  StopDate := startDate + 1 / 24 / 60 * 5;
  log('Ranged Event start date: ' + showDate(startDate));
  log('Ranged Event stop date: ' + showDate(StopDate));
  NewSchedule := CronScheduler.Add('RangedSchedule');
  NewSchedule.EventPlan := '0 0 */2 * 1,5,10 7 *';
  NewSchedule.OnScheduleEvent := OnScheduleTrigger;
  NewSchedule.ValidFrom := startDate;
  NewSchedule.ValidTo := StopDate;
  NewSchedule.Run;
```

# Cron Format

Cron format is a simple, yet powerful and flexible way to define time and frequency of various actions.

Traditional (inherited from Unix) cron format consists of five fields separated by white spaces:

```
<Minute> <Hour> <Day_of_the_Month> <Month_of_the_Year> <Day_of_the_Week>
```

maxCron can use both traditional and "enhanced" version of cron format, which has an additional (6th) field: <Year>:

```
<Minute> <Hour> <Day_of_the_Month> <Month_of_the_Year> <Day_of_the_Week> <Year>
```

Moreover, maxCron has a unique feature and uses two additional fields: 7th <Seconds> and an 8th field <ExecutionLimit>:

```
<Minute> <Hour> <Day_of_the_Month> <Month_of_the_Year> <Day_of_the_Week> <Year> <Seconds> <ExecutionLimit>
```

The following graph shows what the format that maxCron uses consists of:

```
* * * * * * 0 0
| | | | | | | | 
| | | | | | | +-- ExecutionLimit    (range 0 - 0xffffffff. Default 0 = unlimited)
| | | | | | +---- Seconds           (range 0 - 59. Default 0)
| | | | | +------ Year              (range: 1900-3000)
| | | | +-------- Day of the Week   (range: 0-7, 0/7 standing for Sunday; 1=Monday..6=Saturday)
| | | +---------- Month of the Year (range: 1-12)
| | +------------ Day of the Month  (range: 1-31)
| +-------------- Hour              (range: 0-23)
+---------------- Minute            (range: 0-59)
```

Any of these 8 fields may be an asterisk (*). This means the entire range of possible values (each minute, each hour, etc.).

## Cron dialects

We can parse multiple cron dialects. The default remains `cdMaxCron` (current behavior).

- `cdStandard` (5-field): `<Minute> <Hour> <DayOfMonth> <Month> <DayOfWeek>`
- `cdMaxCron` (5-8 field): `<Minute> <Hour> <DayOfMonth> <Month> <DayOfWeek> [Year] [Second] [ExecutionLimit]`
- `cdQuartzSecondsFirst` (6/7-field): `<Second> <Minute> <Hour> <DayOfMonth> <Month> <DayOfWeek> [Year]`

Important: Quartz-style expressions are **seconds-first**. If we use `?`, `W`, `LW`, `#`, or any 6/7-field seconds-first plan, set `Dialect := cdQuartzSecondsFirst`. Parsing those expressions in minute-first dialects (`cdStandard`/`cdMaxCron`) will shift fields and produce different results.
Quartz also uses **1-7** for Day-of-Week numbering (`1=Sun .. 7=Sat`). In `cdStandard`/`cdMaxCron` we use `0` or `7` for Sunday and `1..6` for Monday..Saturday.

DefaultDialect applies when we create new events; we can override per event:

```delphi
CronScheduler.DefaultDialect := cdStandard;
NewSchedule := CronScheduler.Add('QuartzStyle');
NewSchedule.Dialect := cdQuartzSecondsFirst;
NewSchedule.EventPlan := '0 15 10 ? * 2#3';
```

For `cdMaxCron`, prefer either:

- 5-field plans for minute-level schedules, or
- full 8-field plans when we want to be explicit about `Year`, `Second`, and `ExecutionLimit`.

That keeps examples readable and avoids confusing minute-first maxCron plans with Quartz seconds-first syntax.

Any field may contain a list of values separated by commas, (e.g. 1,3,7) or a range of values (two integers separated by a hyphen, e.g. 1-5).

After an asterisk (*) or a range of values, you can use character / to specify that values are repeated over and over with a certain interval between them. For example, you can write "0-23/2" in Hour field to specify that some action should be performed every two hours (it will have the same effect as "0,2,4,6,8,10,12,14,16,18,20,22"); value "*/4" in Minute field means that the action should be performed every 4 minutes, "1-30/3" means the same as "1,4,7,10,13,16,19,22,25,28".

In Month and Day of Week fields, you can use names of months or days of weeks abbreviated to first three letters ("Jan,Feb,...,Dec" or "Mon,Tue,...,Sun") instead of their numeric values.

Additional syntax we support:

- Quartz-style modifiers for Day-of-Month and Day-of-Week:
  - DOM: `L` (last day), `W` (nearest weekday), `LW` (last weekday).
  - DOW: `?` (no specific value), `nL` (last weekday in month), `n#k` (nth weekday, k=1..5).
- Note: we accept `?` for Quartz compatibility and treat it as "any" when matching schedules.
- Macros: `@yearly`/`@annually`, `@monthly`, `@weekly`, `@daily`/`@midnight`, `@hourly`, `@reboot` (runs once on the next scheduler tick; `@reboot` is supported only in `cdMaxCron`; `@weekly` uses Sunday in each dialect: `0` in `cdStandard`/`cdMaxCron`, `1` in `cdQuartzSecondsFirst`).
- Comments and whitespace: trailing `# comment` is ignored; extra spaces/tabs and spaces after commas are accepted.

Examples:

```
* * * * * *                         Each minute


59 23 31 12 5 *                     One minute  before the end of year if the last day of the year is Friday

59 23 31 DEC Fri *                  Same as above (different notation)

45 17 7 6 * *                       Every  year, on June 7th at 17:45

45 17 7 6 * 2001,2002               Once a   year, on June 7th at 17:45, if the year is 2001 or  2002

0,15,30,45 0,6,12,18 1,15,31 * 1-5 *  At 00:00, 00:15, 00:30, 00:45, 06:00, 06:15, 06:30,
                                    06:45, 12:00, 12:15, 12:30, 12:45, 18:00, 18:15,
                                    18:30, 18:45, on 1st, 15th or  31st of each  month, but not on weekends

*/15 */6 1,15,31 * 1-5 *            Same as above (different notation)

0 12 * * 1-5 *                       At midday on weekdays
0 12 * * Mon-Fri *                   Same as above (different notation)

* * * 1,3,5,7,9,11 * *              Each minute in January,  March,  May, July, September, and November

1,2,3,5,20-25,30-35,59 23 31 12 * * On the  last day of year, at 23:01, 23:02, 23:03, 23:05,
                                    23:20, 23:21, 23:22, 23:23, 23:24, 23:25, 23:30,
                                    23:31, 23:32, 23:33, 23:34, 23:35, 23:59

0 9 1-7 * 1 *                       First Monday of each month, at 9 a.m.

0 0 1 * * *                         At midnight, on the first day of each month

* 0-11 * * *                        Each minute before midday

* * * 1,2,3 * *                     Each minute in January, February or March

* * * Jan,Feb,Mar * *               Same as above (different notation)

0 0 * * * *                         Daily at midnight

0 0 * * 3 *                         Each Wednesday at midnight

0 0 * * * * *                       Daily at midnight every second. That is 60 executions

0 0 * * * * 15,30                   Daily 15 and 30 second after midnight

0 0 * * * * * 3                     Daily at midnight every second. But limited to 3 executions
```

Crontab notation may be abridged by omitting the rightmost asterisks.
Please note that omitting the Seconds field does not mean that the task will be executed every second. maxCron uses a default of 0 for Seconds.

Examples:


| Full notation | Abridged notation |
| ------------- | ----------------- |
| * * * * * * |   |
| 59 23 31 12 5 2003                   | 59 23 31 12 5 2003 |
| 59 23 31 12 5 *                      | 59 23 31 12 5 |
| 45 17 7 6 * *                        | 45 17 7 6 |
| 0,15,30,45 0,6,12,18 1,15,31 * * *   | 0,15,30,45 0,6,12,18 1,15,31 |
| 0 12 * * 1-5 *                       | 0 12 * * 1-5 |
| * * * 1,3,5,7,9,11 * *               | * * * 1,3,5,7,9,11 |
| 1,2,3,5,20-25,30-35,59 23 31 12 * *  | 1,2,3,5,20-25,30-35,59 23 31 12 |
| 0 9 1-7 * 1 *                        | 0 9 1-7 * 1 |
| 0 0 1 * * *                          | 0 0 1 |
| * 0-11 * * * *                       | * 0-11 |
| * * * 1,2,3 * *                      | * * * 1,2,3 |
| 0 0 * * * *                          | 0 0 |
| 0 0 * * 3 *                          | 0 0 * * 3 |

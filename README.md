# maxCron

An in-process cron scheduler for Delphi 12 and Free Pascal. You register named
events with a cron expression or a fixed interval, and maxCron calls your
callback on time, on the main thread or a worker thread. It runs on Windows and
Linux; see [Platforms](#platforms) for the tested compilers and targets.

Homepage: https://maxlogic.eu/portfolio/maxcron-scheduler-for-delphi/

## Features

- Unix cron syntax, extended with optional year, seconds and execution-limit fields
- Monotonic interval events (`AddInterval`, `@every 100ms`)
- Multiple cron dialects (standard 5-field, maxCron 5-8 field, Quartz seconds-first)
- Quartz-style DOM/DOW modifiers and cron macros
- Per-event overlap, invoke, and misfire policies
- Execution limits and ValidFrom/ValidTo ranges
- Per-event time zones (LOCAL, UTC, fixed offsets, IANA names) with DST policies
- Business calendar controls (weekdays-only, holiday list, blackout windows)
- Deterministic hash/jitter syntax (`H`, `H/step`, `H(min-max)/step`)
- Schedule previews, previous-occurrence and range queries, and human-readable descriptions
- Comments and flexible whitespace support
- Pluggable schedule persistence + restore API (`ScheduleStore`, `SaveScheduleState`, `RestoreScheduleState`)
- Per-event retry/backoff controls with dead-letter hooks
- Scheduler-wide global concurrency and dispatch-rate caps
- Explicit graceful shutdown API with timeout policies (wait/cancel/force)
- Optional pooled `imThread` dispatch mode for burst-heavy workloads

## Installation

Clone with submodules, because the Delphi scheduler needs `lib/MaxLogicFoundation`:

```bash
git clone --recursive https://github.com/MaxLogic/maxCron.git
```

Add the repository folder to your project's unit search path, or add these units
to the project:

- `maxCron.pas`, `maxCron.Plan.pas`
- `maxCron.Internal.DeadlineQueue.pas`, `maxCron.Internal.Platform.pas`,
  `maxCron.Internal.Text.pas`, `maxCron.Internal.TimeZone.pas`,
  `maxCron.Internal.TZif.pas`

Keep `maxCron.inc` and `maxCron.Internal.TimeZoneNames.inc` beside them. For
Delphi, also add `lib/MaxLogicFoundation` to the search path. Free Pascal builds
use only the RTL; see [Free Pascal (FPC)](#free-pascal-fpc).

Your code needs only `uses maxCron`. Code that only parses plans or computes
occurrences can use `maxCron.Plan`, which depends only on the RTL.

## Quick start

A VCL form owns a scheduler and registers a few events:

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

Callbacks run on the main thread by default (`imMainThread`), which needs a
message pump. A console program or service has none, so select a worker-thread
invoke mode:

```delphi
program ConsoleCron;
{$APPTYPE CONSOLE}
uses
  System.SysUtils, maxCron;

var
  lCron: TmaxCron;
begin
  lCron := TmaxCron.Create(ctPortable);
  try
    lCron.DefaultInvokeMode := imThread;
    lCron.Add('nightly', '0 2 * * *',
      procedure(aEvent: IMaxCronEvent)
      begin
        Writeln(FormatDateTime('hh:nn:ss', Now), ' nightly job');
      end).Run;
    lCron.AddInterval('poll', 500,
      procedure(aEvent: IMaxCronEvent)
      begin
        Writeln(FormatDateTime('hh:nn:ss.zzz', Now), ' poll');
      end).Run;
    Readln;
    lCron.Shutdown(5000, spWait);
  finally
    lCron.Free;
  end;
end.
```

Important usage notes:

- `Add(...)` registers an event but does not start it. Call `Run` when the event is fully configured.
- In the default `cdMaxCron` dialect, 5 fields mean `Minute Hour DayOfMonth Month DayOfWeek`.
- If we want a seconds-first Quartz expression, set `Dialect := cdQuartzSecondsFirst` (or `DefaultDialect`) before assigning the plan.
- Callbacks off the main thread must not touch the UI directly.
- Free the scheduler from outside its own callbacks. The full rules are in the
  [usage contract](#usage-contract-required).

## Cron format

Traditional (inherited from Unix) cron format consists of five fields separated by white spaces:

```
<Minute> <Hour> <Day_of_the_Month> <Month_of_the_Year> <Day_of_the_Week>
```

The default `cdMaxCron` dialect accepts up to three more fields after these five:
a sixth `<Year>`, a seventh `<Seconds>` and an eighth `<ExecutionLimit>`:

```
<Minute> <Hour> <Day_of_the_Month> <Month_of_the_Year> <Day_of_the_Week> <Year> <Seconds> <ExecutionLimit>
```

Field ranges and defaults:

```
* * * * * * 0 0
| | | | | | | |
| | | | | | | +-- ExecutionLimit    (range 0-4294967295. Default 0 = unlimited)
| | | | | | +---- Seconds           (range 0 - 59. Default 0)
| | | | | +------ Year              (range: 1900-3000)
| | | | +-------- Day of the Week   (range: 0-7, 0/7 standing for Sunday; 1=Monday..6=Saturday)
| | | +---------- Month of the Year (range: 1-12)
| | +------------ Day of the Month  (range: 1-31)
| +-------------- Hour              (range: 0-23)
+---------------- Minute            (range: 0-59)
```

Any of these 8 fields may be an asterisk (*). This means the entire range of possible values (each minute, each hour, etc.).

### Cron dialects

maxCron parses three cron dialects. The default is `cdMaxCron`.

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

Numbers use decimal digits only; leading zeros are allowed, while hex (`0x1F`,
`$1F`) and signs (`+5`) are rejected. A month or weekday name must be a whole
value or range endpoint, such as `JAN-MAR` or `MON#2`. Steps and the ordinal
after `#` must be numbers.

Wrapped ranges in seconds, minutes, hours and months continue through the field minimum.
Steps count continuously from the range start: `22-2` means hours 22,23,0,1,2;
`22-2/2` means 22,0,2; `22-2/3` means 22,1. Month names work too:
`NOV-FEB` means November through February; `NOV-FEB/2` means November and January.
Day-of-week wraps use the same continuous step rule, in every dialect:
`4-2/2` means Thursday, Saturday and Monday; `1-7/4` means Monday and Friday
in `cdMaxCron` and `cdStandard`. In Quartz numbering, the corresponding ranges
are `5-3/2` and `2-1/4`. Without a step, `FRI-MON` selects Friday through Monday.
Day-of-month, year and `H(...)` ranges do not wrap.

In `cdMaxCron` and `cdStandard`, Sunday may be written as `0` or `7`.
For a range ending in `7`, starts `1` through `6` run forward through Sunday:
`1-7` is Monday through Sunday, and `1-7/4` is Monday and Friday.
`0-7` spans all seven days; `0-7/2` is Sunday, Tuesday, Thursday and Saturday,
`0-7/3` is Sunday, Wednesday and Saturday, and steps of 7 or more select Sunday only.
`7-7` and `SUN-SUN` select Sunday only. A range starting at `7` otherwise starts
at Sunday, so `7-2/2` is Sunday and Tuesday. Lists union the selected days.
Day names use the dialect's numbers before range expansion: `SUN-7` therefore
also spans the week, while `0-SUN` is Sunday only in these zero-based dialects.

Quartz numbering remains `1` = Sunday through `7` = Saturday; `0` is invalid.
`1-7` spans the week and `1-7/2` selects Sunday, Tuesday, Thursday and Saturday.
For any Quartz start `a` from 1 through 7, `a-7/s` steps forward from `a`
through Saturday, without restarting the step; `7-7` is Saturday only.
In either numbering, other ranges advance from the start to the endpoint,
crossing Sunday when needed, and count the step continuously from the start.
An omitted step means 1. Singleton values and `n/s` without a dash keep their meaning.
Steps larger than a range span select only its start, in every field. This also
applies to `*/n`, `n/k` and stepped hash ranges; a hash range starts at its seeded
value. For example, weekday `1-1/2147483647` selects Monday only.

Additional syntax:

- Quartz-style modifiers for Day-of-Month and Day-of-Week:
  - DOM: `L` (last day), `W` (nearest weekday), `LW` (last weekday).
    Offsets `L-n` (n days before the last day), `LW-n` (n weekdays before the last weekday),
    and `L-nW` (nearest weekday to the last day minus n days) accept n from 0 to 30.
    Nearest-weekday adjustments stay within the month. If the target falls before the month,
    that month has no match. `L-0` equals `L`; `LW-0` and `L-0W` match `LW`.
    For example, `L-2` is February 26 in 2027, `LW-2` is May 27 in 2026,
    and `L-30W` is August 3 in 2026. Large `LW-n` offsets can have no match in any month.
  - DOW: `?` (no specific value), `nL` (last weekday in month), `n#k` (nth weekday, k=1..5).
  - A modifier must be the field's only value: lists such as `L,15` or
    `1#2,3#1` are rejected.
- `?` is accepted for Quartz compatibility and matches any value.
- Macros: `@yearly`/`@annually`, `@monthly`, `@weekly`, `@daily`/`@midnight`, `@hourly`, `@reboot` (runs once on the next scheduler tick; `@reboot` is supported only in `cdMaxCron`; `@weekly` uses Sunday in each dialect: `0` in `cdStandard`/`cdMaxCron`, `1` in `cdQuartzSecondsFirst`).
- Comments and whitespace: trailing `# comment` is ignored; extra spaces/tabs and spaces after commas are accepted.

Examples in the default `cdMaxCron` dialect. Plans that restrict both day of
month and day of week use the default `dmAnd` matching, so both must match (see
[day matching](#day-of-month-and-day-of-week-matching)):

```
* * * * * *                         Each minute

59 23 31 12 5 *                     One minute before the end of the year, if December 31 is a Friday

59 23 31 DEC Fri *                  Same as above (different notation)

45 17 7 6 * *                       Every year, on June 7th at 17:45

45 17 7 6 * 2001,2002               On June 7th at 17:45, in 2001 and 2002 only

0,15,30,45 0,6,12,18 1,15,31 * 1-5 *  At 00:00, 00:15, 00:30, 00:45, 06:00, 06:15, 06:30,
                                    06:45, 12:00, 12:15, 12:30, 12:45, 18:00, 18:15,
                                    18:30, 18:45, on the 1st, 15th or 31st of each month, but not on weekends

*/15 */6 1,15,31 * 1-5 *            Same as above (different notation)

0 12 * * 1-5 *                       At midday on weekdays
0 12 * * Mon-Fri *                   Same as above (different notation)

* * * 1,3,5,7,9,11 * *              Each minute in January, March, May, July, September, and November

1,2,3,5,20-25,30-35,59 23 31 12 * * On the last day of the year, at 23:01, 23:02, 23:03, 23:05,
                                    23:20, 23:21, 23:22, 23:23, 23:24, 23:25, 23:30,
                                    23:31, 23:32, 23:33, 23:34, 23:35, 23:59

0 9 1-7 * 1 *                       First Monday of each month, at 9 a.m.

0 0 1 * * *                         At midnight, on the first day of each month

* 0-11 * * *                        Each minute before midday

* * * 1,2,3 * *                     Each minute in January, February or March

* * * Jan,Feb,Mar * *               Same as above (different notation)

0 0 * * * *                         Daily at midnight

0 0 * * 3 *                         Each Wednesday at midnight

0 0 * * * * *                       Every second of the minute after midnight: 60 runs a day

0 0 * * * * 15,30                   Daily, 15 and 30 seconds after midnight

0 0 * * * * * 3                     Every second from midnight, at most 3 runs in total
```

The first five fields are required. You can omit any of the last three: a
missing Year means every year, a missing Seconds field means second 0 (not every
second), and a missing ExecutionLimit means unlimited. `0 12 * * 1-5` is the same
plan as `0 12 * * 1-5 * 0 0`. Plans with fewer than five fields are rejected.

### Hash / jitter tokens

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

### Day-of-month and day-of-week matching

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

## Interval events

Use `AddInterval('poll', 100, Callback)` or `Add('poll', '@every 100ms', Callback)`
for monotonic intervals from 1 to 4,294,967,295 milliseconds. Events start disabled;
call `Run` or set `Enabled := True`. `Run` restarts the phase and counters.

The grammar is `@every <integer>ms|s|m|h [fixed-rate|fixed-delay] [limit N]`.
Keywords are case-insensitive, whitespace before the unit is allowed, and trailing
`# comments` work. Zero limits mean unlimited. For example,
`@every 1h fixed-delay limit 3` runs at most three callbacks. Interval parse,
canonical format, and description helpers live in `maxCron.Plan`;
`TCronSchedulePlan.Parse`, `Describe`, and `MakePreview` accept cron plans only.

Fixed rate is the default: deadlines retain their original phase. The
misfire policies skip overdue intervals, fire the latest occurrence once, or
catch up in bounded batches, paced by one interval. An occurrence less than one
interval late is on time, including under `mpSkip`. Fixed delay schedules the next
start one full interval after the final callback attempt finishes. Use
`AddInterval(..., ivFixedDelay)` or the plan keyword. Callback errors, rejected
dispatches, and overlap skips complete through the same re-arm path. Stop, delete,
or shutdown cancellation ends the event. Overlap, retry, execution-limit,
and global callback-cap policies also apply to intervals.

Query `IMaxCronIntervalEvent` with `Supports` for the read-only `IsInterval`,
`IntervalMs`, and `IntervalMode` properties. Change intervals through `EventPlan`.
`NextSchedule` projects the monotonic deadline onto local wall time and is zero
while a fixed-delay callback is in flight or the event is disabled. `LastExecution`
projects the fired occurrence, rather than the callback completion. Plans and
projected deadlines round-trip through the schedule store. A restored
future deadline is clamped to one interval; past deadlines follow the misfire policy.

`ValidFrom` and `ValidTo` apply. Time zones, DST, dialect, day matching, weekdays,
excluded dates, blackout windows, and cron jitter have no scheduling effect on
intervals; their values are retained and can be changed without restarting the phase.
Wall-clock changes do not move interval deadlines. Elapsed time across system
sleep follows the platform's monotonic clock; QPC sleep behavior is unverified.

For millisecond intervals use `ctPortable` with `imTTask`, or `imThread` with
`MAXCRON_THREAD_DISPATCH_POOL=1`. `imMainThread` and `ctVcl` add message-queue
latency. The default invoke mode is `imMainThread`, which needs a message pump in
console hosts too. Typical wait resolution is about 1 ms with high-resolution
timers, 1-2 ms with the timer-period fallback, and 15.6 ms with system defaults.
Shorter intervals follow their misfire policy or arrive in catch-up bursts.
Windows power throttling and background/minimized applications can coarsen waits;
the scheduler does not promise hard real-time precision. The accepted 1 ms minimum
interval does not guarantee delivery of every occurrence, even with high-resolution
waits. The interval benchmark observed missed occurrences under load at 1 ms;
10 ms and 100 ms runs had no missed occurrences on the measured host. The
measurements are in [DEVELOPMENT.md](DEVELOPMENT.md#linux-x86_64-benchmark).

## Event options

Each event created by `Add` or `AddInterval` can override these settings before `Run`.

### Validity window (ValidFrom / ValidTo)

`ValidFrom` and `ValidTo` limit an event to a time window. This event runs every
second hour on Sundays in January, May and October, during 2027 only:

```delphi
NewSchedule := CronScheduler.Add('Campaign', '0 */2 * 1,5,10 SUN', OnScheduleTrigger);
NewSchedule.ValidFrom := EncodeDate(2027, 1, 1);
NewSchedule.ValidTo := EncodeDateTime(2027, 12, 31, 23, 59, 59, 999);
NewSchedule.Run;
```

`ValidFrom` and `ValidTo` are both inclusive for cron and interval events; `0`
means unbounded. An occurrence exactly at either bound is eligible, including a
single-point window where both bounds are equal. Searches remain strictly after
their base time. Validity comparisons read `TDateTime` at the nearest millisecond,
with ties to even. Cron bounds use system-local time, including for named-zone
events; calendar exclusions and DST policies still apply. These bounds also
apply to shifted spring-gap occurrences and to each eligible repeated-hour instance.

### Invoke mode

Each event can override how its callback is invoked:

```delphi
CronScheduler.DefaultInvokeMode := imMainThread; // default

NewSchedule := CronScheduler.Add('BackgroundJob', '* * * * * * * 0');
NewSchedule.InvokeMode := imMaxAsync; // or imTTask / imThread / imMainThread
NewSchedule.Run;
```

If we assign `imDefault` to `CronScheduler.DefaultInvokeMode`, maxCron normalizes it to `imMainThread`.

Callbacks that run off the VCL main thread must not touch the UI directly.

Important: `imMainThread` dispatch relies on a live main-thread message pump.
In service/console/non-VCL hosts (or any host without pumping), queued callbacks may never run.
For those hosts we should use `imMaxAsync`, `imTTask`, or `imThread`.

If dispatch startup fails (for example, task/thread launch raises, a queued main-thread callback fails before execution acquire, or a serialized-chain continuation launch fails), maxCron rolls back overlap state and execution reservations so future ticks continue normally and `ExecutionLimit` is not consumed by failed launches.

#### Pooled `imThread` dispatch (burst optimization)

For `imThread`, maxCron can reuse runtime worker threads instead of creating one anonymous thread per fire:

```bash
export MAXCRON_THREAD_DISPATCH_POOL=1
```

```cmd
set MAXCRON_THREAD_DISPATCH_POOL=1
```

Enabled values: `1` or `true` (case-insensitive). Any other value keeps the legacy thread-per-fire path.

### Overlap handling

When a schedule fires again while a previous execution is still running:

```delphi
NewSchedule.OverlapMode := omAllowOverlap;        // default
NewSchedule.OverlapMode := omSkipIfRunning;       // drop overlapping fires
NewSchedule.OverlapMode := omSerialize;           // queue and run 1-by-1
NewSchedule.OverlapMode := omSerializeCoalesce;   // serialize, but keep backlog <= 1
```

`NumOfExecutionsPerformed` counts actual callback executions (after overlap rules), not just schedule hits.
`ExecutionLimit` caps actual executions (after overlap rules); skipped/coalesced overlaps do not consume the limit.

### Misfire handling

When the scheduler is delayed or the machine sleeps, we can control how missed occurrences are handled:

```delphi
CronScheduler.DefaultMisfirePolicy := TmaxCronMisfirePolicy.mpCatchUpAll; // default
CronScheduler.DefaultMisfireCatchUpLimit := 1; // max catch-up per tick (min 1)

NewSchedule.MisfirePolicy := TmaxCronMisfirePolicy.mpFireOnceNow; // per-event override
```

Policies:
- `mpSkip`: fire occurrences processed in their due second (less than one second late); skip occurrences one second or more late and advance to the next time after `now`.
- `mpFireOnceNow`: execute once, then advance to the next time after `now`.
- `mpCatchUpAll`: execute missed occurrences sequentially, bounded per tick by `DefaultMisfireCatchUpLimit`.

If we assign `mpDefault` to `CronScheduler.DefaultMisfirePolicy`, maxCron normalizes it to `mpCatchUpAll`.

When exclusions (weekdays/holidays/blackout) create long filtered ranges, maxCron advances the search cursor in larger steps and keeps the event enabled until a true terminal condition is reached.

### Retry/backoff and dead-letter hooks

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

### Time zones and DST

Each event can evaluate cron time in its own timezone:

```delphi
NewSchedule.TimeZoneId := 'LOCAL';      // default
NewSchedule.TimeZoneId := 'UTC';
NewSchedule.TimeZoneId := 'UTC+02:30';  // fixed offset
NewSchedule.TimeZoneId := 'Europe/Warsaw'; // IANA zone name
```

On Windows 8 or later, named zones use the OS time zone database through a built-in
CLDR name table, with no data files required. At every whole second, offsets equal
Windows' own conversion. A transition stored at 23:59:59.999 takes effect at the
following midnight. Zone data is cached per UTC year on first use; restart the
process after a Windows time zone update. Delphi and FPC named zones use the same
provider. FPC LOCAL uses Windows' conversion for the active system zone, including
its automatic daylight saving setting. Outside UTC years 1602-9998, the offset at
the nearest edge continues unchanged.

Set `MAXCRON_TZDIR` before assigning a name to select TZif files on Windows or
other platforms. Other platforms otherwise use `TZDIR`, then `/usr/share/zoneinfo`.
TZif versions 1-4 and compatible later versions are supported. No TZif database
is bundled for application use. The reader supports signed and extended POSIX
footer rule times when both rule-local transitions stay at least 2 local days from the year boundaries and both DST and standard parts last at least 28 days throughout a 400-year Gregorian cycle. Fixed-offset and RFC all-year-DST footers are also supported; unsupported footer rules fail when setting the zone and preserve its previous value.
Leap-second (`right/`) files are rejected.

On Linux, LOCAL resolves the host zone in this order.

1. If `TZ` is unset, read `/etc/localtime`, following symlinks. A missing,
   unreadable or invalid file selects UTC.
2. If `TZ` is set, strip one leading colon. An empty result selects UTC.
3. For a value beginning with `/`, try that absolute path as a TZif file.
   Otherwise, for a valid zone name, try its exact, case-sensitive path under
   the first nonempty setting among `MAXCRON_TZDIR` and `TZDIR`, defaulting to
   `/usr/share/zoneinfo`.
4. If no usable TZif file was found for the set value, try it as a POSIX TZ
   rule. If that fails, use UTC.

The next use after the one-second recheck interval looks at the current
settings and compares the selected file's bytes. This detects in-place file
updates and changes to the `/etc/localtime` symlink. LOCAL uses the same gap
and overlap rules as named zones.

glibc may use `posixrules` for a value such as `EST5EDT` when no matching
zone file exists. maxCron falls back to UTC for a DST rule without transition
rules and for a TZif footer or POSIX rule rejected by its validator when no
usable rule remains. The file lookup accepts only valid zone names for
relative values, excluding paths such as `../x`.

The built-in name table is derived from Unicode CLDR 49 data, copyright
2001-2026 Unicode, Inc., under the Unicode License v3. The full notice is retained
in `maxCron.Internal.TimeZoneNames.inc`.
Names match ASCII case-insensitively; the returned name uses the table spelling
on Windows or the file spelling for TZif. Aliases such as `US/Eastern`,
`Asia/Calcutta` and `Etc/UTC` are accepted and kept. Unknown names raise on assignment,
report the cause and leave the previous zone intact. Resolved rules are immutable
and cached; restart the process to pick up data-file changes.

DST behavior is configurable per event:

```delphi
NewSchedule.DstSpringPolicy := dspSkip;              // default
NewSchedule.DstSpringPolicy := dspRunAtNextValidTime;

NewSchedule.DstFallPolicy := dfpRunOnce;             // default
NewSchedule.DstFallPolicy := dfpRunTwice;
NewSchedule.DstFallPolicy := dfpRunOncePreferFirstInstance;
NewSchedule.DstFallPolicy := dfpRunOncePreferSecondInstance;
```

Cron occurrences are selected and dispatched by their UTC instants. During a repeated
hour, `dfpRunOnce` and `dfpRunOncePreferFirstInstance` select the earlier instance,
`dfpRunOncePreferSecondInstance` selects the later one, and `dfpRunTwice` selects
both in UTC order. Each occurrence runs at its own instance, including when a
schedule starts, resumes, resets or is restored during the host's repeated hour.
`UTC` and fixed-offset schedules keep their UTC firing times across host DST changes.
Misfire lateness is measured in UTC, so repeated wall times cannot hide an overdue occurrence.

For both LOCAL and named zones, `dspSkip` omits nonexistent local times.
`dspRunAtNextValidTime` runs a gap occurrence at the transition instant, the first
valid local time: a missing 02:30:30 shifts to 03:00:00. Several occurrences shifted
to that instant fire once. Eligible period ranges keep dense searches bounded
across 30-minute and two-hour changes.

`NextSchedule`, `LastExecution` and persisted schedule values remain host-local
display times. Repeated instances can therefore share one displayed value.
On Windows, LOCAL uses native conversion rules on both compilers and picks up
a host-zone change on the next scheduler pass. On Linux, LOCAL picks up a
host-zone change on the first use after the one-second recheck interval has
elapsed, and uses cached TZif rules until then. UTC, fixed-offset and named occurrences retain
their UTC dues. Interval deadlines remain monotonic.

### Business calendar exclusions

We can apply common exclusion filters per event:

```delphi
NewSchedule.WeekdaysOnly := True;                              // skip Sat/Sun
NewSchedule.ExcludedDatesCsv := '2031-01-02,2031-01-03';      // YYYY-MM-DD list
NewSchedule.BlackoutStartTime := EncodeTime(9, 0, 0, 0);      // skip 09:00..
NewSchedule.BlackoutEndTime := EncodeTime(17, 0, 0, 0);       // ..until 17:00
```

These exclusions are applied after cron matching and before callback dispatch.

Blackout windows include the start time and exclude the end time: `[09:00, 17:00)` skips 09:00 and permits 17:00. Windows can cross midnight, such as `[22:00, 06:00)`. Equal start and end times disable the window. Times are interpreted at the nearest millisecond, ties to even.

## Querying plans without a scheduler

`TCronSchedulePlan` and `TPlan` live in `maxCron.Plan`, which depends only on the RTL.

### Building plans with TPlan

`TPlan` is a record with one string property per field (`Minute`, `Hour`,
`DayOfTheMonth`, `Month`, `DayOfTheWeek`, `Year`, `Second`, `ExecutionLimit`).
`Reset` sets every field to its default, and `Text` builds the cron string for
the selected dialect. Assigning `Text` splits a plan back into fields.

```delphi
var
  lPlan: TPlan;
begin
  lPlan.Reset;
  lPlan.Dialect := cdMaxCron; // or cdStandard / cdQuartzSecondsFirst
  lPlan.Second := '30';
  // lPlan.Text is now '* * * * * * 30 0': every minute at second 30
  CronScheduler.Add('EventFromTPlan', lPlan.Text, OnScheduleTrigger).Run;
end;
```

### Upcoming occurrences

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

### Previous occurrences and range queries

`TCronSchedulePlan` also searches backwards and queries a time window:

```delphi
var
  lPlan: TCronSchedulePlan;
  lDates: TDates;
  lPrevious, lStart, lEnd: TDateTime;
  lCount: Integer;
begin
  lPlan := TCronSchedulePlan.Create;
  try
    lPlan.Parse('*/15 * * * *');
    lStart := EncodeDateTime(2026, 11, 15, 10, 0, 0, 0);
    lEnd := IncHour(lStart, 1);
    if lPlan.FindPreviousScheduleDate(IncMinute(lStart, 7), lPrevious) then
      Writeln(DateTimeToStr(lPrevious)); // 10:00
    lCount := lPlan.GetPreviousOccurrences(3, IncMinute(lStart, 7), lDates);
    // Newest first: 10:00, 09:45, 09:30.
    lCount := lPlan.GetOccurrencesBetween(lStart, lEnd, lDates, 2);
    // Oldest first: 10:00, 10:15. Fetch the next page after the last result.
    if lCount > 0 then
      lCount := lPlan.GetOccurrencesBetween(IncSecond(lDates[lCount - 1], 1), lEnd, lDates, 2);
    lCount := lPlan.CountBetween(lStart, lEnd); // 4
    if lPlan.HasOccurrenceBetween(lStart, lEnd) then
      Writeln(lCount);
  finally
    lPlan.Free;
  end;
end;
```

The example uses `System.DateUtils` and `System.SysUtils`, plus either `maxCron`
or the RTL-only `maxCron.Plan` unit. Previous searches are strictly before the
base time. Ranges include the start and exclude the end: `[start, end)`.
Comparisons read TDateTime inputs at the millisecond nearest to the exact stored
Double, ties to even, using the library conversion helper on Win32 and Win64.
Occurrences are whole seconds:
previous at `10:15:00.000` excludes that occurrence, while `10:15:00.001`
includes it. A range starting at `10:00:00.001` begins with `10:15`.

Queries stay within 1900-01-01 through 3000-12-31. A failed previous search sets
its output to zero. Nonpositive counts or limits return empty results; empty
or reversed windows return zero and `HasOccurrenceBetween` returns False.
`GetOccurrencesBetween` and `CountBetween` default to `cCronQueryDefaultLimit`
(10,000). Lists truncate at the limit; counts saturate there. Pass a larger
limit, up to `High(Integer)`, to count more, with one next-search per occurrence.

Plan queries ignore `ExecutionLimit` and use naive wall-clock time. Event
timezone, DST policy, weekdays-only rules, excluded dates, blackout and event
validity windows are not applied.

### Human-readable descriptions

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

## Scheduler lifecycle

### Usage contract (required)

An invalid cron expression raises `Exception` with a parser diagnostic such as
`Invalid cron token`, `Invalid cron step` or `Cron value out of range`; malformed
numbers raise the same `Exception`, never an RTL `EConvertError`. The
`Add(name, plan, callback)` overloads are atomic: if the plan is invalid, no
event is added.

For safe production use we should follow these lifecycle rules:

- `Add(...)` only registers the event. New events start disabled; call `Run` (preferred) or set `Enabled := True` after configuration.
- `IMaxCronEvent` is an interface handle. Event registration lifetime is managed by `TmaxCron`.
- Every event has an immutable `Id` assigned by `TmaxCron` when we call `Add(...)`.
- Event names are optional. If provided, they are case-insensitive unique and immutable after `Add(...)`.
- We can remove schedules by handle (`Delete(Event)`), by id (`Delete(Event.Id)`), or by name (`Delete('EventName')`).
- `Delete('EventName')` applies to named events only. Unnamed events should be removed by handle or id (or `Clear`).
- For stable inspection, use `Snapshot` to get an array copy of registered events.
  There is no index-based access (see [migration](#migration-from-the-index-api)).
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

### Global dispatch caps

We can cap aggregate callback throughput across all events:

```delphi
CronScheduler.GlobalMaxConcurrentCallbacks := 32; // 0 = disabled
CronScheduler.GlobalMaxDispatchPerSecond := 200;  // 0 = disabled
```

Environment alternatives (read at scheduler creation):
- `MAXCRON_GLOBAL_MAX_CONCURRENT`
- `MAXCRON_GLOBAL_MAX_DISPATCH_PER_SECOND`

Integer environment settings accept decimal digits after trimming surrounding whitespace.
An empty value counts as unset and uses the default.

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

Do not call `TmaxCron.Free` from one of its own callbacks: that re-entrant
shutdown would deadlock, so it raises an exception instead. Free the scheduler
from outside callback context.

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

Restore validates and installs an enabled event's saved due before deciding
whether it can run. An eligible overdue cron or interval occurrence follows its
misfire policy even when the plan has ended or `ValidTo` has passed since that
occurrence. Execution limits and inclusive validity bounds still apply to the
saved due. Missing or invalid saved dues use a fresh schedule search.

Persistence captures event configuration and state metadata. Callback handlers are
not serialized. Attach them with the restore binder before restored events start:

```delphi
CronScheduler.RestoreScheduleState(True,
  procedure(const aEvent: IMaxCronEvent; const aState: TMaxCronPersistedEvent)
  begin
    aEvent.OnScheduleProc := MyScheduleProc;
  end);
```

#### Restart catch-up

`SaveScheduleState` stores `CompletedThrough`, a UTC checkpoint floored to
milliseconds. Every policy instance at or before it has reached a final outcome:
the callback returned, retries exhausted, or a policy deliberately suppressed it.
Restore resumes after this checkpoint under the configured plan and policies.
The binder can change the plan before this search.

Delivery is at least once. A crash after a callback starts and before a later
save becomes durable can replay that occurrence. Out-of-order completions can
also repeat later occurrences behind an unfinished earlier callback.
**Handlers must be idempotent**: check the target state or use a durable business
operation identifier before applying side effects. A save from inside a callback
does not cover that callback yet.

Save periodically, write the store atomically, and save after
`Shutdown(timeout, spWait)` at exit. Save before `spCancel` or `spForce`, which
clear events. Misfire and overlap suppression, execution limits, validity bounds,
reported dispatch-start failures and a search-limit fallback can deliberately
discard work. Callbacks assigned after restore can miss a timer pass; use the
binder for restart catch-up.

Store implementations should persist `CompletedThrough` and read a missing
field as 0. Zero, negative or NaN checkpoints use the `NextSchedule`
restore path. Old stored data loads unchanged. Restoring legacy data and saving again
before a tick keeps the checkpoint absent; only a final scheduling outcome can
certify its pending work. UTC checkpoints distinguish both
instances of a repeated local hour. A future checkpoint after a clock correction
waits for the next cron occurrence after it.

For cron events, `mpSkip` skips occurrences at least one second late,
`mpFireOnceNow` fires once, and `mpCatchUpAll` processes all missed occurrences,
at most `DefaultMisfireCatchUpLimit` per pass. The default limit is 1 and
there is no total catch-up cap. Dense plans after long downtime may need a larger
limit or `mpFireOnceNow`. Interval events use their usual misfire rules;
fixed-rate resumes at checkpoint plus interval, and fixed-delay uses the last
settled completion plus interval. Future interval checkpoints are clamped to one
interval ahead of the current clock.

In persisted state, `Enabled` means "should still run". Automatic disabling from
plan exhaustion, `ValidTo`, or an execution limit is saved as `True` while tickets
remain unsettled. An explicit `Stop` or `Enabled := False` is always saved as
`False`. Once the tickets settle, an exhausted event saves `False` again.
The saved execution count covers the settled prefix: executions still behind
an unsettled ticket are excluded, including later callbacks that finished out of
order. Replay can therefore repeat counted but unfinished work while execution
limits and validity bounds continue to apply.

**Clock corrections during a save.** Each `SaveScheduleState` call captures one clock pair for every event, reading
MONO0, UTC1, UTC2 and MONO2. It validates the UTC change against elapsed
monotonic time, then projects unfinished interval deadlines with UTC1/MONO2.
The saved checkpoint is at most that earliest projected due minus one interval;
cron checkpoints stay at least 1 ms before each unfinished UTC occurrence.
The stored checkpoint can move backwards and replay completed work.
Saved interval `NextSchedule` uses that same pair, including legacy records with
no checkpoint. `LastExecution` retains its recorded history without another clock
read. Rejected captures bypass the live interval getters and use the shared fallback.

The detectable correction window is between UTC1 and UTC2. Any correction after
the UTC2 read is outside that guarantee, including between UTC2 and MONO2,
between events being serialized, and after persistence. Interval restore
translates the saved UTC deadline to the restart monotonic clock and clamps a
future deadline to one interval; a rollback after UTC2 can therefore miss
interval occurrences after restart. Cron occurrences retain their UTC identity.

After eight rejected clock samples, the whole save uses absent checkpoints and
conservative legacy deadlines. If a coherent sample has no positive safe
checkpoint, the store receives 0 and the earliest unfinished saved deadline.
These fallbacks can replay additional work.

## Timers and precision

### Timer backend selection

By default `TmaxCron` uses `ctAuto`:

- If created on the VCL main thread: uses `TTimer` (`ctVcl`)
- Otherwise: uses the threaded portable timer (`ctPortable`)

```delphi
CronScheduler := TmaxCron.Create(ctAuto);
// or force one:
CronScheduler := TmaxCron.Create(ctVcl);
CronScheduler := TmaxCron.Create(ctPortable);
```

`ctVcl` must be created on the VCL main thread; creating it on a worker thread raises an exception.

### Cron timer precision

Each scheduler owns one timing thread. Cron passes run once per wall-clock second,
aligned just after the second boundary, using a precise local wall clock on Windows.
`LastExecution` and `NextSchedule` retain their scheduled wall-clock values.
Cron dispatch interprets these `TDateTime` carriers at the nearest millisecond,
with ties to even. The precise clock stays in integer microseconds through due
and misfire decisions; a pass less than one second late fires under `mpSkip`,
including 999.6-999.999 ms late. Run/reset and late-pass searches use the whole
second containing the precise instant, so a pass just before an occurrence
does not skip it. The `TCronInstantUs` type and `CronDateTimeToMs`,
`CronDateTimeToInstantUs`, `CronMsToDateTime`, `CronSecondToDateTime`,
`CronInstantFloorSecond`, `CronInstantUsToDateTime`, `CronFloorDiv` and
`CronCeilDiv` helpers are available from `maxCron.Plan` and `maxCron`.
`CronInstantUsToDateTime` floors to milliseconds for display or persistence.
`ctPortable` delivers ticks on the timing thread; `ctVcl` posts coalesced ticks to
the main thread through `TThread.ForceQueue` and requires a message pump. Main-thread
load and callback dispatch add latency. The default callback mode is `imMainThread`;
a console application must pump queued work or select `imTTask`/`imThread`.

On Windows, `MAXCRON_TIMER_RESOLUTION` is read when creating the scheduler: `high` (default)
uses a high-resolution waitable timer, `period` requests 1 ms timer resolution only
for the final 20 ms of each wait, and `default` uses the system wait resolution.
If a high-resolution timer is unavailable, maxCron falls back to `period`.
`ActiveTimerResolution` reports `trHighResolution`, `trTimerPeriod`, or
`trSystemDefault`. Timer-period requests can affect the whole system on older
Windows versions. Every wait is bounded to one second so clock jumps are noticed.
Power throttling, battery operation, and background/minimized process policies may
coarsen waits; the published measurements do not cover those environments. QPC
behavior across system sleep remains platform-defined and unverified here.

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

## Platforms

| Platform | Compiler | Timers | Status |
| --- | --- | --- | --- |
| Windows x64/x86 | Delphi 12 | High-resolution waits | Supported |
| Windows x64 | FPC trunk 3.3.1 | High-resolution waits | Supported |
| Linux x86_64 | Delphi 12 Linux64 | Millisecond waits | Supported |
| Linux x86_64 | FPC trunk 3.3.1 | Millisecond waits | Supported |
| Linux aarch64 | FPC trunk 3.3.1 | Millisecond waits | Supported, tested under qemu-user |

`ctVcl`, `maxCronHlpDlg`, the Windows zone provider and
`MAXCRON_TIMER_RESOLUTION` are Windows-only. Other Delphi targets are untested.

### Linux setup

- Delphi 12 needs the Linux64 SDK on Windows. Cross-compile there and run the
  binary on the Linux target.
- FPC programs must list `cthreads` first in the program's `uses` clause,
  followed by `cwstring` for Unicode conversions.
- Install `tzdata` on the Linux target for LOCAL and named zones.

### Free Pascal (FPC)

Windows x64 and Linux x86_64/aarch64 are supported with FPC trunk 3.3.1, built from
`https://gitlab.com/freepascal.org/fpc/source` main commit
`47b0238476dd4eb2d8f7ff4158626fd8cc379ebc` (2026-11-26). FPC 3.2.x lacks the
anonymous-method support required here. `maxCron.inc` rejects older versions and
targets outside Windows x64 and Linux x86_64/aarch64.

On Windows, build from source with the official FPC 3.2.2 x86_64-win64
bootstrap and its `make`. Replace `<bootstrap-compiler>` and `<fpc-root>` with
your compiler and installation paths.

```bat
make clean all install "PP=<bootstrap-compiler>" "INSTALL_PREFIX=<fpc-root>" OS_TARGET=win64 CPU_TARGET=x86_64
```

The compiler is `<fpc-root>\bin\x86_64-win64\fpc.exe`. Invoke it with the
configuration and units from the same installation.

```bat
"<fpc-root>\bin\x86_64-win64\fpc.exe" -n "@<fpc-root>\bin\x86_64-win64\fpc.cfg" "-FD<fpc-root>\bin\x86_64-win64" "-Fu<fpc-root>\units\x86_64-win64\*" "-Fu<maxCron folder>" "<your program>"
```

On Linux, use the same compiler revision with the units for your target and
follow [Linux setup](#linux-setup).

The units set `delphiunicode`, `anonymousfunctions` and `functionreferences`
through `maxCron.inc`, with real constants kept at Double precision.
Add the same library units listed under Installation,
including `maxCron.Internal.Text.pas`. MaxLogicFoundation is not needed on FPC.
Plan text stays Unicode.

On FPC, `imMaxAsync` runs on the RTL `System.Threading` pool, as does `imTTask`.
The tested FPC build has an RTL pool shutdown race that can double-free a worker
at process exit under `heaptrc`; a program using only `TTask.Run` reproduces it.
If you check leaks with `heaptrc`, expect this report from programs that use
`imMaxAsync` or `imTTask`; it comes from the RTL pool, not from maxCron.

The tested FPC trunk includes the fix for FPC issue #42105 (`474f4bbf`,
2026-11-22). maxCron's `LOCAL` is independent of `TTimeZone.Local` and uses
Windows conversion rules on Windows and maxCron's TZif resolver on Linux.

FPC exception messages are AnsiString, so characters unavailable in the Windows
code page can be replaced in messages.

The tested compiler can report an internal `EListError` for a non-capturing
anonymous procedure literal passed directly to an overloaded `Add` call. A
literal capturing only `Self` can bind to the method-pointer overload. Use a
typed `TmaxCronNotifyProc` local variable before calling `Add`:

```pascal
lCallback := procedure(aSender: IMaxCronEvent) begin HandleSchedule(aSender); end;
lEvent := lCron.Add('job', '* * * * *', lCallback);
```

## Upgrading

### From 2.3.x

- Add the new units listed under [Installation](#installation), or add the
  repository folder to the search path.
- Cron numbers are decimal only: `$A`, `0xA` and `+10` are rejected. Month and
  weekday names must be whole values or range endpoints.
- Day-of-week ranges `0-7` and stepped ranges that wrap across Sunday select
  different days than before, and `ValidFrom` is now inclusive for cron events.
  The `Changed` section of [CHANGELOG.md](CHANGELOG.md) lists every behavior change.
- Calculation types moved to `maxCron.Plan`. They keep their type identity and
  short RTTI names, but their unit-qualified RTTI names now use `maxCron.Plan`
  (for example, `TCronSchedulePlan.UnitName`). Update reflection that looks up
  the old qualified names.

### Migration from the index API

Versions before 2.3.0 exposed index-based access. Migrate as follows:

- `CronScheduler.Count` -> `Length(CronScheduler.Snapshot)`
- `CronScheduler.Events[i]` -> `CronScheduler.Snapshot[i]`
- `CronScheduler.Delete(i)` -> `CronScheduler.Delete(Event.Id)` (or `Delete(Event)` / `Delete('Name')`)
- `CronScheduler.IndexOf(Event)` -> iterate over `Snapshot` and compare `Id`

Prefer storing event handles (`IMaxCronEvent`) or immutable `Id` values in our app code, instead of relying on collection positions.

## Development

Building, testing and benchmarking maxCron itself is described in [DEVELOPMENT.md](DEVELOPMENT.md).
Release notes are in [CHANGELOG.md](CHANGELOG.md).

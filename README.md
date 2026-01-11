# maxCron 
Flexible, lightweight CRON compliant scheduler written in Delphi. 

Homepage: https://maxlogic.eu/portfolio/maxcron-scheduler-for-delphi/



## Main features:

- Compatible with most of what CRON is offering
- Setting the CRON is as simple as setting one string. Example below.
- It supports step values (e.g., `*/5`) for interval-style schedules
- Schedule can have valid from / to limits
- Very lightweight implementation


# Sample scheduler usage:
```delphi
procedure TForm1.FormCreate(Sender: TObject);
var
  NewSchedule: TmaxCronEvent ;
begin 
  
  // create new TCronScheduler that will hold events
  CronScheduler := TmaxCron.Create;
  
  // first event
  NewSchedule := CronScheduler.Add('Event1', '1 * * * * *', OnScheduleEvent1).Run;
  
  // second event
  NewSchedule := CronScheduler.Add('Event2', '1 * * * * *', OnScheduleEvent2).Run;
  
  // third event
  NewSchedule := CronScheduler.Add('Event3', '1 * * * * *', OnScheduleEvent3).Run; 

  // you can use anonymous methods as well
  NewSchedule := CronScheduler.Add('Event2');
  NewSchedule.EventPlan := '*/2 * * * * *';
  NewSchedule.OnScheduleproc := procedure(aEvent: TmaxCronEvent)
    begin
      OnScheduleTrigger(aEvent);
    end;
  NewSchedule.Run;

  
  // using a shorter adding syntax
  NewSchedule := CronScheduler.Add('Event4', '1 * * * * *',
    procedure(aEvent: TmaxCronEvent)
    begin
      OnScheduleTrigger(aEvent);
    end).Run;
end;
```

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

## How a job is executed (per-event)

Each event can override how its callback is invoked:

```delphi
CronScheduler.DefaultInvokeMode := imMainThread; // default

NewSchedule := CronScheduler.Add('BackgroundJob', '* * * * * * * 0');
NewSchedule.InvokeMode := imMaxAsync; // or imTTask / imThread / imMainThread
NewSchedule.Run;
```

Note: if we execute off the VCL main thread, we must not touch UI directly.

## Overlap handling (per-event)

When a schedule fires again while a previous execution is still running:

```delphi
NewSchedule.OverlapMode := omAllowOverlap;        // default
NewSchedule.OverlapMode := omSkipIfRunning;       // drop overlapping fires
NewSchedule.OverlapMode := omSerialize;           // queue and run 1-by-1
NewSchedule.OverlapMode := omSerializeCoalesce;   // serialize, but keep backlog <= 1
```

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

## Unit tests

DUnitX tests live under `tests/` (runner: `tests/maxCronTests.dpr`).
Our upstream-derived cron corpus used by tests is stored in `tests/data/cron-utils-unix-5field.txt`.
Negative corpus (expected to fail parse) is stored in `tests/data/cron-invalid.txt`.

Optional runners:
- `tests/maxCronVclTests.dpr` (GUI/VCL message pump; tests `ctVcl` / `ctAuto` behavior)
- `tests/maxCronStressTests.dpr` (heavier concurrency stress tests; ~30s)

# Using the TPlan helper:
TPlan is a small record that lets us set parts in a friendly way and then convert them to a cron string.
```Delphi
  var plan: TPlan;

  plan.Reset;
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

DefaultDialect applies when we create new events; we can override per event:

```delphi
CronScheduler.DefaultDialect := cdStandard;
NewSchedule := CronScheduler.Add('QuartzStyle');
NewSchedule.Dialect := cdQuartzSecondsFirst;
NewSchedule.EventPlan := '0 15 10 ? * 2#3';
```

Any field may contain a list of values separated by commas, (e.g. 1,3,7) or a range of values (two integers separated by a hyphen, e.g. 1-5).

After an asterisk (*) or a range of values, you can use character / to specify that values are repeated over and over with a certain interval between them. For example, you can write "0-23/2" in Hour field to specify that some action should be performed every two hours (it will have the same effect as "0,2,4,6,8,10,12,14,16,18,20,22"); value "*/4" in Minute field means that the action should be performed every 4 minutes, "1-30/3" means the same as "1,4,7,10,13,16,19,22,25,28".

In Month and Day of Week fields, you can use names of months or days of weeks abbreviated to first three letters ("Jan,Feb,...,Dec" or "Mon,Tue,...,Sun") instead of their numeric values.

Additional syntax we support:

- Quartz-style modifiers for Day-of-Month and Day-of-Week:
  - DOM: `L` (last day), `W` (nearest weekday), `LW` (last weekday).
  - DOW: `?` (no specific value), `nL` (last weekday in month), `n#k` (nth weekday, k=1..5).
- Macros: `@yearly`/`@annually`, `@monthly`, `@weekly`, `@daily`/`@midnight`, `@hourly`, `@reboot` (runs once on the next scheduler tick).
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

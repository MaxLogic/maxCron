[TOC]

# maxCron 
Flexible, lightweight CRON compliant scheduler written in Delphi. 

Homepage: https://maxlogic.eu/portfolio/maxcron-scheduler-for-delphi/



## Main features:

- Compatible with most of what CRON is offering
- Setting the CRON is as simple as setting one string. Example below.
- It also supports simple intervals in addition to CRON style schedules
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

# using the TCronSchedulePlan:
The TPlan is a small class that allows you to specify the parts in a more friendly way and then convert them to a cron string
```Delphi
  plan := TCronSchedulePlan .create;
  // you can use the clear  method to reset all the values to their defaults like this:
  plan.Clear;
  // you can access any of the fields just like that:
  plan.Second := '30';
  // now create a new event using our new plan
  NewSchedule := CronScheduler.Add('EventFromTPlan', plan.text, OnScheduleTrigger).Run;
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

More over, maxCron has a unique feature, and uses two additional fields: 7th <Seconds> and a 8th field <ExecutionLimit>:

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
| | | | +-------- Day of the Week   (range: 1-7, 1 standing for Monday)
| | | +---------- Month of the Year (range: 1-12)
| | +------------ Day of the Month  (range: 1-31)
| +-------------- Hour              (range: 0-23)
+---------------- Minute            (range: 0-59)
```

Any of these 8 fields may be an asterisk (*). This would mean the entire range of possible values, i.e. each minute, each hour, etc. In the first four fields,

Any field may contain a list of values separated by commas, (e.g. 1,3,7) or a range of values (two integers separated by a hyphen, e.g. 1-5).

After an asterisk (*) or a range of values, you can use character / to specify that values are repeated over and over with a certain interval between them. For example, you can write "0-23/2" in Hour field to specify that some action should be performed every two hours (it will have the same effect as "0,2,4,6,8,10,12,14,16,18,20,22"); value "*/4" in Minute field means that the action should be performed every 4 minutes, "1-30/3" means the same as "1,4,7,10,13,16,19,22,25,28".

In Month and Day of Week fields, you can use names of months or days of weeks abbreviated to first three letters ("Jan,Feb,...,Dec" or "Mon,Tue,...,Sun") instead of their numeric values.

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

0 12 * * 1-5 * 0 12 * * Mon-Fri *) At midday on weekdays

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
Please note, that omiting the Seconds field does not mean that the task will be executed every second. MaxCron puts a 0 as a default for the Seconds part.

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


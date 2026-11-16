unit TestCronQuery;

interface

uses
  System.DateUtils, System.SysUtils,
  DUnitX.TestFramework,
  maxCron.Plan;

type
  [TestFixture]
  TTestCronQuery = class
  public
    [Test] procedure MidnightRangeRegressions;
    [Test] procedure PreviousExamples;
    [Test] procedure DomainAndExhaustion;
    [Test] procedure RangeExamples;
    [Test] procedure LimitsAndEmptyWindows;
    [Test] procedure HashAndExecutionLimit;
  end;

implementation

function Stamp(const aText: string): TDateTime;
begin
  Result := EncodeDateTime(StrToInt(Copy(aText, 1, 4)), StrToInt(Copy(aText, 6, 2)),
    StrToInt(Copy(aText, 9, 2)), StrToIntDef(Copy(aText, 12, 2), 0),
    StrToIntDef(Copy(aText, 15, 2), 0), StrToIntDef(Copy(aText, 18, 2), 0),
    StrToIntDef(Copy(aText, 21, 3), 0));
end;

function Serial(const aDate: TDateTime): Int64;
begin
  Result := CronFloorDiv(CronDateTimeToMs(aDate), 1000) + Int64(DateDelta) * 86400;
end;

procedure TTestCronQuery.PreviousExamples;
var
  lPlan: TCronSchedulePlan;
  lPrevious: TDateTime;
  lDates: TDates;

  procedure Check(const aText, aBase, aExpected: string);
  begin
    lPlan.Parse(aText);
    Assert.IsTrue(lPlan.FindPreviousScheduleDate(Stamp(aBase), lPrevious), aText + ' ' + aBase);
    Assert.AreEqual(Serial(Stamp(aExpected)), Serial(lPrevious), aText + ' ' + aBase);
  end;

begin
  lPlan := TCronSchedulePlan.Create;
  try
    Check('*/15 * * * *', '2026-11-15 10:07:30.500', '2026-11-15 10:00:00');
    Assert.AreEqual(3, lPlan.GetPreviousOccurrences(3, Stamp('2026-11-15 10:07:30.500'), lDates));
    Assert.AreEqual(Serial(Stamp('2026-11-15 09:30:00')), Serial(lDates[2]));
    Assert.AreEqual(Serial(Stamp('2026-11-15 09:45:00')), Serial(lDates[1]));
    Check('*/15 * * * *', '2026-11-15 10:15:00', '2026-11-15 10:00:00');
    Check('*/15 * * * *', '2026-11-15 10:15:00.001', '2026-11-15 10:15:00');
    Check('* * * * * * 0/20', '2026-11-16 10:00:30', '2026-11-16 10:00:20');
    Check('* * * * * * *', '2027-01-01', '2026-12-31 23:59:59');
    Check('59 23 31 12 *', '2026-12-31 23:59:00', '2025-12-31 23:59:00');
    Check('0 0 29 2 *', '2026-11-16', '2024-02-29');
    Check('0 0 29 2 *', '2024-02-29', '2020-02-29');
    Check('0 0 L * *', '2028-03-01', '2028-02-29');
    Check('0 0 L * *', '2028-02-29 00:00:00.500', '2028-02-29');
    Check('0 0 LW * *', '2026-06-01', '2026-05-29');
    Check('0 0 15W * *', '2026-11-20', '2026-11-16');
    Check('0 0 15W * *', '2026-11-16', '2026-10-15');
    Check('0 9 * * 1#2', '2026-11-16', '2026-11-09 09:00:00');
    Check('0 9 * * 5L', '2026-11-16', '2026-10-30 09:00:00');
    FreeAndNil(lPlan);
    lPlan := TCronSchedulePlan.Create;
    lPlan.Dialect := cdQuartzSecondsFirst;
    Check('0 0 12 ? * 6L', '2026-11-16', '2026-10-30 12:00:00');
    FreeAndNil(lPlan);
    lPlan := TCronSchedulePlan.Create;
    lPlan.Dialect := cdMaxCron;
    lPlan.DayMatchMode := dmOr;
    Check('0 0 1,15 * 1', '2026-11-16', '2026-11-15');
    lPlan.DayMatchMode := dmAnd;
    Check('0 0 1,15 * 1', '2026-11-16', '2026-06-15');
  finally
    lPlan.Free;
  end;
end;

procedure TTestCronQuery.DomainAndExhaustion;
var
  lPlan: TCronSchedulePlan;
  lPrevious: TDateTime;
  lDates: TDates;
begin
  lPlan := TCronSchedulePlan.Create;
  try
    lPlan.Parse('0 0 1 1 * 2020');
    Assert.IsTrue(lPlan.FindPreviousScheduleDate(Stamp('2026-11-16'), lPrevious));
    Assert.AreEqual(Serial(Stamp('2020-01-01')), Serial(lPrevious));
    Assert.IsFalse(lPlan.FindPreviousScheduleDate(Stamp('2020-01-01'), lPrevious));
    Assert.AreEqual<Double>(0.0, Double(lPrevious));
    lPlan.Parse('0 0 * * *');
    Assert.IsTrue(lPlan.FindPreviousScheduleDate(Stamp('9999-01-01'), lPrevious));
    Assert.AreEqual(Serial(Stamp('3000-12-31')), Serial(lPrevious));
    lPlan.Parse('* * * * * * *');
    Assert.IsTrue(lPlan.FindPreviousScheduleDate(Stamp('1900-01-01 00:00:00.500'), lPrevious));
    Assert.AreEqual(Serial(Stamp('1900-01-01')), Serial(lPrevious));
    Assert.IsFalse(lPlan.FindPreviousScheduleDate(Stamp('1900-01-01'), lPrevious));
    Assert.AreEqual<Double>(0.0, Double(lPrevious));
    Assert.IsFalse(lPlan.FindPreviousScheduleDate(Stamp('1800-01-01'), lPrevious));
    Assert.AreEqual(1, lPlan.GetOccurrencesBetween(Stamp('1800-01-01'),
      Stamp('1900-01-01 00:00:01'), lDates));
    Assert.AreEqual(1, lPlan.CountBetween(Stamp('3000-12-31 23:59:59'), Stamp('9999-01-01')));
    lPlan.Parse('0 0 30 2 *');
    Assert.IsFalse(lPlan.FindPreviousScheduleDate(Stamp('2026-11-16'), lPrevious));
    Assert.AreEqual(0, lPlan.GetOccurrencesBetween(Stamp('2026-01-01'), Stamp('2027-01-01'), lDates));
    lPlan.Parse('0 0 1 * 1#5');
    Assert.IsFalse(lPlan.FindPreviousScheduleDate(Stamp('3000-12-31'), lPrevious), 'Full descending walk');
    Assert.AreEqual<Double>(0.0, Double(lPrevious));
  finally
    lPlan.Free;
  end;
end;

procedure TTestCronQuery.RangeExamples;
var
  lPlan: TCronSchedulePlan;
  lDates: TDates;
  lStart, lEnd: TDateTime;
  i: Integer;
begin
  lPlan := TCronSchedulePlan.Create;
  try
    lPlan.Parse('*/15 * * * *');
    lStart := Stamp('2026-11-15 10:00:00');
    lEnd := IncHour(lStart, 1);
    Assert.AreEqual(4, lPlan.GetOccurrencesBetween(lStart, lEnd, lDates));
    for i := 0 to 3 do
    begin
      Assert.AreEqual(Serial(IncMinute(lStart, i * 15)), Serial(lDates[i]));
    end;
    Assert.AreEqual(4, lPlan.GetOccurrencesBetween(IncMilliSecond(lStart, 1), IncMilliSecond(lEnd, 1), lDates));
    for i := 0 to 3 do
    begin
      Assert.AreEqual(Serial(IncMinute(lStart, (i + 1) * 15)), Serial(lDates[i]));
    end;
    Assert.AreEqual(2, lPlan.GetOccurrencesBetween(lStart, lEnd, lDates, 2));
    Assert.AreEqual(Serial(lStart), Serial(lDates[0]));
    Assert.AreEqual(Serial(IncMinute(lStart, 15)), Serial(lDates[1]));
    lPlan.Parse('* * * * * * *');
    Assert.AreEqual(2, lPlan.GetOccurrencesBetween(IncMilliSecond(lStart, 500), IncSecond(lStart, 3), lDates));
    Assert.AreEqual(Serial(IncSecond(lStart, 1)), Serial(lDates[0]));
    Assert.AreEqual(Serial(IncSecond(lStart, 2)), Serial(lDates[1]));
    Assert.AreEqual(86400, lPlan.CountBetween(Stamp('2026-01-01'), Stamp('2026-01-02'), 100000));
    Assert.AreEqual(10000, lPlan.CountBetween(Stamp('2026-01-01'), Stamp('2026-01-02')));
    lPlan.Parse('0 0 1 1 * 2020');
    Assert.IsFalse(lPlan.HasOccurrenceBetween(Stamp('2021-01-01'), Stamp('2026-01-01')));
    Assert.IsTrue(lPlan.HasOccurrenceBetween(Stamp('2020-01-01'), Stamp('2020-01-01 00:00:01')));
  finally
    lPlan.Free;
  end;
end;

procedure TTestCronQuery.LimitsAndEmptyWindows;
var
  lPlan: TCronSchedulePlan;
  lDates: TDates;
  lStart: TDateTime;
begin
  lPlan := TCronSchedulePlan.Create;
  try
    lPlan.Parse('* * * * * * *');
    lStart := Stamp('2026-01-01');
    Assert.AreEqual(1, lPlan.GetOccurrencesBetween(lStart, IncDay(lStart), lDates, 1));
    Assert.AreEqual(0, lPlan.GetOccurrencesBetween(lStart, IncDay(lStart), lDates, 0));
    Assert.AreEqual(0, Integer(Length(lDates)));
    Assert.AreEqual(0, lPlan.GetOccurrencesBetween(lStart, IncDay(lStart), lDates, -1));
    Assert.AreEqual(0, lPlan.CountBetween(lStart, IncDay(lStart), -1));
    Assert.AreEqual(0, lPlan.GetPreviousOccurrences(0, lStart, lDates));
    Assert.AreEqual(0, Integer(Length(lDates)));
    Assert.AreEqual(0, lPlan.GetPreviousOccurrences(-1, lStart, lDates));
    Assert.AreEqual(0, lPlan.GetOccurrencesBetween(lStart, lStart, lDates));
    Assert.AreEqual(0, lPlan.GetOccurrencesBetween(lStart, IncDay(lStart, -1), lDates));
    Assert.IsFalse(lPlan.HasOccurrenceBetween(lStart, lStart));
    Assert.IsFalse(lPlan.HasOccurrenceBetween(lStart, IncDay(lStart, -1)));
  finally
    lPlan.Free;
  end;
end;

procedure TTestCronQuery.HashAndExecutionLimit;
var
  lPlan: TCronSchedulePlan;
  lDates, lExpected: TDates;
  lNext, lPrevious, lBase: TDateTime;
  i: Integer;
begin
  lPlan := TCronSchedulePlan.Create;
  try
    lBase := Stamp('2026-11-16');
    lPlan.HashSeed := 'job-a';
    lPlan.Parse('H/15 * * * * * H(0-29)/10 3');
    Assert.AreEqual(10, lPlan.GetOccurrencesBetween(lBase, IncDay(lBase), lExpected, 10));
    Assert.AreEqual(10, lPlan.GetPreviousOccurrences(10, IncSecond(lExpected[9], 1), lDates));
    for i := 0 to 9 do
    begin
      Assert.AreEqual(Serial(lExpected[9-i]), Serial(lDates[i]));
      Assert.IsTrue(lPlan.FindNextScheduleDate(IncSecond(lDates[i], -1), lNext));
      Assert.AreEqual(Serial(lDates[i]), Serial(lNext));
    end;
    Assert.IsTrue(lPlan.FindPreviousScheduleDate(IncSecond(lExpected[0], 1), lPrevious));
    Assert.AreEqual(Serial(lExpected[0]), Serial(lPrevious));
    Assert.AreEqual(3, Integer(lPlan.ExecutionLimit));
    Assert.AreEqual(10, lPlan.CountBetween(lBase, IncDay(lBase), 10));
  finally
    lPlan.Free;
  end;
end;


procedure TTestCronQuery.MidnightRangeRegressions;
var
  lPlan: TCronSchedulePlan;
  lDates: TDates;
  lStart, lEnd: TDateTime;
  i: Integer;
begin
  lPlan := TCronSchedulePlan.Create;
  try
    lPlan.Dialect := cdStandard;
    lPlan.DayMatchMode := dmOr;
    lPlan.Parse('* 23-23 LW JAN,MAR MON-FRI');
    lStart := EncodeDateTime(1900, 1, 1, 23, 59, 1, 0);
    lEnd := EncodeDate(1900, 1, 2);
    Assert.AreEqual(0, lPlan.GetOccurrencesBetween(lStart, lEnd, lDates));
    Assert.AreEqual(0, lPlan.CountBetween(lStart, lEnd));
    Assert.IsFalse(lPlan.HasOccurrenceBetween(lStart, lEnd));
    lStart := EncodeDate(1900, 1, 1);
    lEnd := EncodeDate(1900, 1, 3);
    Assert.AreEqual(120, lPlan.GetOccurrencesBetween(lStart, lEnd, lDates));
    Assert.AreEqual(120, lPlan.CountBetween(lStart, lEnd));
    Assert.IsTrue(lPlan.HasOccurrenceBetween(lStart, lEnd));
    for i := 0 to High(lDates) do
    begin
      // Calendar-derived: Monday and Tuesday each contain 23:00 through 23:59.
      Assert.AreEqual(Serial(EncodeDateTime(1900, 1, 1 + i div 60, 23, i mod 60, 0, 0)),
        Serial(lDates[i]));
      Assert.IsTrue((Serial(lDates[i]) >= Serial(lStart)) and (Serial(lDates[i]) < Serial(lEnd)));
      if i > 0 then
        Assert.IsTrue(Serial(lDates[i]) > Serial(lDates[i - 1]));
    end;
  finally
    lPlan.Free;
  end;
end;

end.

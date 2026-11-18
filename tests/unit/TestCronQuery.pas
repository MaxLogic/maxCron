unit TestCronQuery;
{$I maxCron.inc}

interface

uses
  {$IFDEF FPC}
  DateUtils, SysUtils,
  DUnitX.TestFramework,
  maxCron.Plan
  {$ELSE}
  System.DateUtils, System.SysUtils,
  DUnitX.TestFramework,
  maxCron.Plan
  {$ENDIF};

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
    [Test] procedure SyntaxAdditionsExamples;
    [Test] procedure WeekdayRangeQueries_MatchIndependentCycle;
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


procedure TTestCronQuery.WeekdayRangeQueries_MatchIndependentCycle;
const
  cSteps: array[0..8] of Integer = (0, 1, 2, 3, 4, 5, 6, 7, 8);
var
  lPlan, lExplicit: TCronSchedulePlan;
  lDialect: TmaxCronDialect;
  lFrom, lTo, lLow, lRawFrom, lRawTo, lDistance, lOffset, lStep, v, i: Integer;
  lExpected: array[0..6] of Boolean;
  lToken, lPrefix, lValues: string;
  lBase, lWeek, lActual, lExpectedDate: TDateTime;
  lDates: TDates;
begin
  lPlan := TCronSchedulePlan.Create;
  lExplicit := TCronSchedulePlan.Create;
  try
    lWeek := EncodeDate(2026, 11, 15); // Sunday; each anchor is midday, queries are strict.
    for lDialect := Low(TmaxCronDialect) to High(TmaxCronDialect) do
    begin
      FreeAndNil(lPlan);
      FreeAndNil(lExplicit);
      lPlan := TCronSchedulePlan.Create;
      lExplicit := TCronSchedulePlan.Create;
      lPlan.Dialect := lDialect;
      lExplicit.Dialect := lDialect;
      lLow := 0;
      lPrefix := '0 0 * * ';
      if lDialect = cdQuartzSecondsFirst then
      begin
        lLow := 1;
        lPrefix := '0 0 0 ? * ';
      end;
      for lRawFrom := lLow to 7 do
      begin
        for lRawTo := lLow to 7 do
        begin
          lFrom := (lRawFrom - lLow) mod 7;
          lTo := (lRawTo - lLow) mod 7;
          lDistance := (lTo - lFrom + 7) mod 7;
          if (lLow = 0) and (lRawFrom = 0) and (lRawTo = 7) then
            lDistance := 6;
          for lStep in cSteps do
          begin
            lToken := IntToStr(lRawFrom) + '-' + IntToStr(lRawTo);
            if lStep > 0 then
              lToken := lToken + '/' + IntToStr(lStep);
            lPlan.Parse(lPrefix + lToken);
            lValues := '';
            for v := 0 to 6 do
            begin
              lOffset := (v - lFrom + 7) mod 7;
              lExpected[v] := lOffset <= lDistance;
              if lStep > 0 then
                lExpected[v] := lExpected[v] and (lOffset mod lStep = 0);
              Assert.AreEqual(lExpected[v], lPlan.Day_of_the_Week.NextVal(v) = v, lToken);
              if lExpected[v] then
              begin
                if lValues <> '' then lValues := lValues + ',';
                lValues := lValues + IntToStr(v + lLow);
              end;
            end;
            lExplicit.Parse(lPrefix + lValues);
            Assert.AreEqual(lExplicit.Describe, lPlan.Describe, lToken + ' Describe');
            for v := 0 to 6 do
            begin
              lBase := lWeek + v + 0.5;
              i := 1;
              while not lExpected[(v + i) mod 7] do Inc(i);
              lExpectedDate := lWeek + v + i;
              Assert.IsTrue(lPlan.FindNextScheduleDate(lBase, lActual), lToken);
              Assert.AreEqual(Serial(lExpectedDate), Serial(lActual), lToken + ' next');
              i := 0;
              while not lExpected[(v - i + 7) mod 7] do Inc(i);
              lExpectedDate := lWeek + v - i;
              Assert.IsTrue(lPlan.FindPreviousScheduleDate(lBase, lActual), lToken);
              Assert.AreEqual(Serial(lExpectedDate), Serial(lActual), lToken + ' previous');
            end;
            i := 0;
            for v := 0 to 6 do if lExpected[v] then Inc(i);
            Assert.AreEqual(i, lPlan.CountBetween(lWeek, lWeek + 7), lToken + ' count');
            Assert.AreEqual(i, lPlan.GetOccurrencesBetween(lWeek, lWeek + 7, lDates), lToken + ' between');
            i := 0;
            for v := 0 to 6 do
            begin
              if lExpected[v] then
              begin
                Assert.AreEqual(Serial(lWeek + v), Serial(lDates[i]), lToken + ' occurrence');
                Inc(i);
              end;
            end;
          end;
        end;
      end;
    end;
  finally
    lExplicit.Free;
    lPlan.Free;
  end;
end;

procedure TTestCronQuery.SyntaxAdditionsExamples;
var
  lPlan: TCronSchedulePlan;
  lDate: TDateTime;
  lDates: TDates;

  procedure Check(const aText, aBase, aNext, aPrevious: string);
  begin
    lPlan.Parse(aText);
    Assert.IsTrue(lPlan.FindNextScheduleDate(Stamp(aBase), lDate), aText);
    Assert.AreEqual(Serial(Stamp(aNext)), Serial(lDate), aText + ' next');
    if aPrevious <> '' then
    begin
      Assert.IsTrue(lPlan.FindPreviousScheduleDate(Stamp(aBase), lDate), aText);
      Assert.AreEqual(Serial(Stamp(aPrevious)), Serial(lDate), aText + ' previous');
    end;
    Assert.AreEqual(1, lPlan.GetOccurrencesBetween(Stamp(aNext), IncSecond(Stamp(aNext), 1), lDates), aText);
    Assert.AreEqual(Serial(Stamp(aNext)), Serial(lDates[0]), aText + ' between');
    Assert.AreEqual(1, lPlan.CountBetween(Stamp(aNext), IncSecond(Stamp(aNext), 1)), aText);
  end;

begin
  lPlan := TCronSchedulePlan.Create;
  try
    Check('0 0 L-2 * *', '2026-02-01', '2026-02-26', '2026-01-29');
    Check('0 0 L-2 * *', '2027-02-01', '2027-02-26', '2027-01-29');
    Check('0 0 L-30 * *', '2026-02-01', '2026-03-01', '2026-01-01');
    Check('0 0 LW-1 * *', '2026-05-01', '2026-05-28', '2026-04-29');
    Check('0 0 LW-2 * *', '2026-05-01', '2026-05-27', '2026-04-28');
    Check('0 0 LW-19 2 *', '2026-01-01', '2026-02-02', '2025-02-03');
    Check('0 0 LW-20 2 *', '2026-01-01', '2028-02-01', '');
    Check('0 0 L-2W * *', '2026-11-01', '2026-11-27', '2026-10-29');
    Check('0 0 L-30W * *', '2026-07-02', '2026-08-03', '2026-07-01');
    Check('0 0 L-0W * *', '2026-05-01', '2026-05-29', '2026-04-30');
    Check('0 0 L-0 * *', '2026-05-01', '2026-05-31', '2026-04-30');
    Check('0 22-2 * * *', '2026-11-16 03:00', '2026-11-16 22:00', '2026-11-16 02:00');
    Check('0 22-2/2 * * *', '2026-11-16 00:30', '2026-11-16 02:00', '2026-11-16');
    Check('0 22-2/3 * * *', '2026-11-16 00:30', '2026-11-16 01:00', '2026-11-15 22:00');
    Check('50-10/15 * * * *', '2026-11-16 10:06', '2026-11-16 10:50', '2026-11-16 10:05');
    Check('* * * * * * 55-5/5 0', '2026-11-16 10:00:06', '2026-11-16 10:00:55', '2026-11-16 10:00:05');
    Check('0 0 1 NOV-FEB *', '2026-03-15', '2026-11-01', '2026-02-01');
    Check('0 0 1 NOV-FEB/2 *', '2026-03-15', '2026-11-01', '2026-01-01');
    Check('0 8 * * FRI-MON', '2026-11-18 12:00', '2026-11-20 08:00', '2026-11-16 08:00');
    Check('0 0 * * 4-2/2', '2026-11-16 12:00', '2026-11-19', '2026-11-16');
    Check('0 0 * * 1-7/4', '2026-11-15', '2026-11-16', '2026-11-13');
    Check('0 0 * * THU-TUE/2', '2026-11-16 12:00', '2026-11-19', '2026-11-16');
    Check('0 0 * * 6-1/2147483647', '2026-11-16', '2026-11-21', '2026-11-14');
    lPlan.DayMatchMode := dmOr;
    Check('0 0 L-2 * MON', '2026-11-17', '2026-11-23', '2026-11-16');
    FreeAndNil(lPlan);
    lPlan := TCronSchedulePlan.Create;
    lPlan.Dialect := cdQuartzSecondsFirst;
    Check('0 0 22-2 ? * 6-2', '2026-11-18 12:00', '2026-11-20 00:00', '2026-11-16 23:00');
    Check('0 0 0 L-2W * ?', '2026-11-01', '2026-11-27', '2026-10-29');
    Check('0 0 0 ? * 5-3/2', '2026-11-16 12:00', '2026-11-19', '2026-11-16');
    Check('0 0 0 ? * THU-TUE/2', '2026-11-16 12:00', '2026-11-19', '2026-11-16');
  finally
    lPlan.Free;
  end;
end;

end.

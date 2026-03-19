unit TestScheduleNext;

interface

uses
  System.DateUtils, System.SysUtils,
  DUnitX.TestFramework,
  maxCron;

type
  [TestFixture]
  TTestScheduleNext = class
  private
    procedure AssertNext(const aExpr: string; const aBase, aExpected: TDateTime);
  public
    [Test]
    procedure Next_SecondDefaultsToZero;

    [Test]
    procedure Next_LeapDay;

    [Test]
    procedure Next_MonthEndClamp;

    [Test]
    procedure Next_DomDow_OrVsAnd;

    [Test]
    procedure Next_DomDow_OrMode_Oracle_BruteForceMatrix;

    [Test]
    procedure Next_Dow_Sunday_ZeroOrSeven;

    [Test]
    procedure Next_Dow_Quartz_OneBased;

    [Test]
    procedure Next_Dom_LastDay;

    [Test]
    procedure Next_Dom_LastWeekday;

    [Test]
    procedure Next_Dom_LastWeekday_AfterMonth;

    [Test]
    procedure Next_Dom_NearestWeekday;

    [Test]
    procedure Next_Dom_NearestWeekday_OnSunday;

    [Test]
    procedure Next_Dom_NearestWeekday_AfterMonth;

    [Test]
    procedure Next_Dom_NearestWeekday_AtMonthStart;

    [Test]
    procedure Next_Dom_NearestWeekday_AtMonthEnd;

    [Test]
    procedure Next_Dow_LastInMonth;

    [Test]
    procedure Next_Dow_LastInMonth_AfterMonth;

    [Test]
    procedure Next_Dow_NthInMonth;

    [Test]
    procedure Next_Dow_NthInMonth_AfterMonth;

    [Test]
    procedure Next_Dow_NthInMonth_SkipMonthWhenMissing;

    [Test]
    procedure Next_Dow_NoSpec;

    [Test]
    procedure Next_YearRestriction_NoLeapDay;

    [Test]
    procedure Next_GetNextOccurrences_CountZero;

    [Test]
    procedure Next_GetNextOccurrences_LargeCount;

    [Test]
    procedure Next_GetNextOccurrences_InvalidPlan;
  end;

implementation

procedure TTestScheduleNext.AssertNext(const aExpr: string; const aBase, aExpected: TDateTime);
var
  Plan: TCronSchedulePlan;
  NextDt: TDateTime;
begin
  Plan := TCronSchedulePlan.Create;
  try
    Plan.Parse(aExpr);
    Assert.IsTrue(Plan.FindNextScheduleDate(aBase, NextDt));
    Assert.AreEqual(aExpected, NextDt, 0.0);
  finally
    Plan.Free;
  end;
end;

procedure TTestScheduleNext.Next_SecondDefaultsToZero;
var
  Base: TDateTime;
  Expected: TDateTime;
begin
  // Abridged: minute hour dom month dow year => second defaults to 0
  Base := EncodeDateTime(2025, 1, 1, 0, 0, 0, 0);
  Expected := EncodeDateTime(2025, 1, 1, 0, 1, 0, 0);
  AssertNext('* * * * * *', Base, Expected);
end;

procedure TTestScheduleNext.Next_LeapDay;
var
  Base: TDateTime;
  Expected: TDateTime;
begin
  Base := EncodeDateTime(2023, 12, 31, 23, 59, 59, 0);
  Expected := EncodeDateTime(2024, 2, 29, 0, 0, 0, 0);
  AssertNext('0 0 29 2 * * 0 0', Base, Expected);
end;

procedure TTestScheduleNext.Next_MonthEndClamp;
var
  Plan: TCronSchedulePlan;
  NextDt: TDateTime;
  Base: TDateTime;
begin
  // 31st in February should skip to next month that has 31 days
  Plan := TCronSchedulePlan.Create;
  try
    Plan.Parse('0 0 31 * * * 0 0');
    Base := EncodeDateTime(2025, 2, 1, 0, 0, 0, 0);
    Assert.IsTrue(Plan.FindNextScheduleDate(Base, NextDt));
    Assert.IsTrue(DayOf(NextDt) = 31);
    Assert.IsTrue(MonthOf(NextDt) <> 2);
  finally
    Plan.Free;
  end;
end;

procedure TTestScheduleNext.Next_DomDow_OrVsAnd;
var
  Plan: TCronSchedulePlan;
  NextDt: TDateTime;
  Base: TDateTime;
begin
  // DOM=1 and DOW=Mon (1). In OR mode we should get next Monday; in AND mode we need the next month where 1st is Monday.
  Plan := TCronSchedulePlan.Create;
  try
    Plan.Parse('0 0 1 * 1 * 0 0');
    Base := EncodeDateTime(2025, 1, 1, 23, 59, 59, 0); // next search starts at 2025-01-02 00:00:00

    Plan.DayMatchMode := dmOr;
    Assert.IsTrue(Plan.FindNextScheduleDate(Base, NextDt));
    Assert.AreEqual(EncodeDateTime(2025, 1, 6, 0, 0, 0, 0), NextDt, 0.0);

    Plan.DayMatchMode := dmAnd;
    Assert.IsTrue(Plan.FindNextScheduleDate(Base, NextDt));
    Assert.AreEqual(EncodeDateTime(2025, 9, 1, 0, 0, 0, 0), NextDt, 0.0);
  finally
    Plan.Free;
  end;
end;

procedure TTestScheduleNext.Next_DomDow_OrMode_Oracle_BruteForceMatrix;
const
  cDomValues: array [0 .. 4] of Word = (1, 2, 15, 28, 31);
  cDowValues: array [0 .. 6] of Word = (0, 1, 2, 3, 4, 5, 6);
var
  lPlan: TCronSchedulePlan;
  lBaseDates: array [0 .. 7] of TDateTime;
  lDomIndex: Integer;
  lDowIndex: Integer;
  lBaseIndex: Integer;
  lDayScan: Integer;
  lDomValue: Word;
  lDowValue: Word;
  lExpr: string;
  lBase: TDateTime;
  lActual: TDateTime;
  lExpected: TDateTime;
  lCandidate: TDateTime;
  lFound: Boolean;
  lCandidateDow: Integer;
begin
  lPlan := TCronSchedulePlan.Create;
  try
    lBaseDates[0] := EncodeDateTime(2024, 2, 29, 23, 59, 59, 0);
    lBaseDates[1] := EncodeDateTime(2025, 1, 1, 23, 59, 59, 0);
    lBaseDates[2] := EncodeDateTime(2025, 2, 28, 23, 59, 59, 0);
    lBaseDates[3] := EncodeDateTime(2025, 3, 1, 12, 0, 0, 0);
    lBaseDates[4] := EncodeDateTime(2025, 6, 15, 8, 30, 0, 0);
    lBaseDates[5] := EncodeDateTime(2025, 12, 31, 23, 59, 59, 0);
    lBaseDates[6] := EncodeDateTime(2026, 1, 31, 23, 59, 59, 0);
    lBaseDates[7] := EncodeDateTime(2026, 2, 1, 0, 0, 0, 0);

    for lDomIndex := Low(cDomValues) to High(cDomValues) do
    begin
      lDomValue := cDomValues[lDomIndex];
      for lDowIndex := Low(cDowValues) to High(cDowValues) do
      begin
        lDowValue := cDowValues[lDowIndex];
        lExpr := Format('0 0 %d * %d * 0 0', [lDomValue, lDowValue]);
        lPlan.Parse(lExpr);
        lPlan.DayMatchMode := TmaxCronDayMatchMode.dmOr;

        for lBaseIndex := Low(lBaseDates) to High(lBaseDates) do
        begin
          lBase := lBaseDates[lBaseIndex];
          lExpected := 0;
          Assert.IsTrue(lPlan.FindNextScheduleDate(lBase, lActual),
            Format('Scheduler did not find next date for expr=%s base=%s',
              [lExpr, DateTimeToStr(lBase)]));

          lCandidate := Trunc(lBase);
          if lCandidate <= lBase then
            lCandidate := IncDay(lCandidate);

          lFound := False;
          for lDayScan := 0 to 3660 do
          begin
            lCandidateDow := DayOfTheWeek(lCandidate) mod 7;
            if (DayOf(lCandidate) = lDomValue) or (lCandidateDow = lDowValue) then
            begin
              lExpected := lCandidate;
              lFound := True;
              Break;
            end;
            lCandidate := IncDay(lCandidate);
          end;

          Assert.IsTrue(lFound,
            Format('Oracle did not find next date for expr=%s base=%s', [lExpr, DateTimeToStr(lBase)]));
          Assert.AreEqual(lExpected, lActual, 0.0,
            Format('Oracle mismatch for expr=%s base=%s', [lExpr, DateTimeToStr(lBase)]));
        end;
      end;
    end;
  finally
    lPlan.Free;
  end;
end;

procedure TTestScheduleNext.Next_Dow_Sunday_ZeroOrSeven;
var
  Plan: TCronSchedulePlan;
  Next0: TDateTime;
  Next7: TDateTime;
  NextName: TDateTime;
  Base: TDateTime;
begin
  Base := EncodeDateTime(2025, 1, 1, 0, 0, 0, 0); // Wednesday

  Plan := TCronSchedulePlan.Create;
  try
    Plan.Parse('0 0 * * 0 * 0 0'); // Sunday = 0
    Assert.IsTrue(Plan.FindNextScheduleDate(Base, Next0));

    Plan.Parse('0 0 * * 7 * 0 0'); // Sunday = 7 (alias)
    Assert.IsTrue(Plan.FindNextScheduleDate(Base, Next7));

    Plan.Parse('0 0 * * Sun * 0 0'); // Sunday by name
    Assert.IsTrue(Plan.FindNextScheduleDate(Base, NextName));

    Assert.AreEqual(Next0, Next7, 0.0);
    Assert.AreEqual(Next0, NextName, 0.0);
    Assert.AreEqual(EncodeDateTime(2025, 1, 5, 0, 0, 0, 0), Next0, 0.0); // next Sunday
  finally
    Plan.Free;
  end;
end;

procedure TTestScheduleNext.Next_Dow_Quartz_OneBased;
var
  lPlan: TCronSchedulePlan;
  lNext: TDateTime;
  lBase: TDateTime;
begin
  lBase := EncodeDateTime(2025, 1, 1, 0, 0, 0, 0); // Wednesday

  lPlan := TCronSchedulePlan.Create;
  try
    lPlan.Dialect := cdQuartzSecondsFirst;
    lPlan.Parse('0 0 0 ? * 2'); // Monday (Quartz 1=Sun, 2=Mon)
    Assert.IsTrue(lPlan.FindNextScheduleDate(lBase, lNext));
    Assert.AreEqual(EncodeDateTime(2025, 1, 6, 0, 0, 0, 0), lNext, 0.0);
  finally
    lPlan.Free;
  end;
end;

procedure TTestScheduleNext.Next_Dom_LastDay;
var
  Base: TDateTime;
  Expected: TDateTime;
begin
  Base := EncodeDateTime(2025, 1, 10, 0, 0, 0, 0);
  Expected := EncodeDateTime(2025, 1, 31, 0, 0, 0, 0);
  AssertNext('0 0 L 1 *', Base, Expected);
end;

procedure TTestScheduleNext.Next_Dom_LastWeekday;
var
  lBase: TDateTime;
  lExpected: TDateTime;
begin
  lBase := EncodeDateTime(2025, 5, 1, 0, 0, 0, 0);
  lExpected := EncodeDateTime(2025, 5, 30, 0, 0, 0, 0);
  AssertNext('0 0 LW 5 *', lBase, lExpected);
end;

procedure TTestScheduleNext.Next_Dom_LastWeekday_AfterMonth;
var
  lBase: TDateTime;
  lExpected: TDateTime;
begin
  lBase := EncodeDateTime(2025, 8, 31, 0, 0, 0, 0);
  lExpected := EncodeDateTime(2025, 9, 30, 0, 0, 0, 0);
  AssertNext('0 0 LW * *', lBase, lExpected);
end;

procedure TTestScheduleNext.Next_Dom_NearestWeekday;
var
  lBase: TDateTime;
  lExpected: TDateTime;
begin
  lBase := EncodeDateTime(2025, 3, 1, 0, 0, 0, 0);
  lExpected := EncodeDateTime(2025, 3, 14, 0, 0, 0, 0);
  AssertNext('0 0 15W 3 *', lBase, lExpected);
end;

procedure TTestScheduleNext.Next_Dom_NearestWeekday_OnSunday;
var
  lBase: TDateTime;
  lExpected: TDateTime;
begin
  lBase := EncodeDateTime(2025, 6, 1, 0, 0, 0, 0);
  lExpected := EncodeDateTime(2025, 6, 16, 0, 0, 0, 0);
  AssertNext('0 0 15W 6 *', lBase, lExpected);
end;

procedure TTestScheduleNext.Next_Dom_NearestWeekday_AfterMonth;
var
  lBase: TDateTime;
  lExpected: TDateTime;
begin
  lBase := EncodeDateTime(2025, 3, 20, 0, 0, 0, 0);
  lExpected := EncodeDateTime(2025, 4, 15, 0, 0, 0, 0);
  AssertNext('0 0 15W * *', lBase, lExpected);
end;

procedure TTestScheduleNext.Next_Dom_NearestWeekday_AtMonthStart;
var
  lBase: TDateTime;
  lExpected: TDateTime;
begin
  lBase := EncodeDateTime(2025, 1, 31, 0, 0, 0, 0);
  lExpected := EncodeDateTime(2025, 2, 3, 0, 0, 0, 0);
  AssertNext('0 0 1W 2 *', lBase, lExpected);
end;

procedure TTestScheduleNext.Next_Dom_NearestWeekday_AtMonthEnd;
var
  lBase: TDateTime;
  lExpected: TDateTime;
begin
  lBase := EncodeDateTime(2025, 8, 1, 0, 0, 0, 0);
  lExpected := EncodeDateTime(2025, 8, 29, 0, 0, 0, 0);
  AssertNext('0 0 31W 8 *', lBase, lExpected);
end;

procedure TTestScheduleNext.Next_Dow_LastInMonth;
var
  lBase: TDateTime;
  lExpected: TDateTime;
begin
  lBase := EncodeDateTime(2025, 4, 1, 0, 0, 0, 0);
  lExpected := EncodeDateTime(2025, 4, 25, 0, 0, 0, 0);
  AssertNext('0 0 * 4 5L', lBase, lExpected);
end;

procedure TTestScheduleNext.Next_Dow_LastInMonth_AfterMonth;
var
  lBase: TDateTime;
  lExpected: TDateTime;
begin
  lBase := EncodeDateTime(2025, 4, 30, 0, 0, 0, 0);
  lExpected := EncodeDateTime(2025, 5, 30, 0, 0, 0, 0);
  AssertNext('0 0 * * 5L', lBase, lExpected);
end;

procedure TTestScheduleNext.Next_Dow_NthInMonth;
var
  lBase: TDateTime;
  lExpected: TDateTime;
begin
  lBase := EncodeDateTime(2025, 6, 1, 0, 0, 0, 0);
  lExpected := EncodeDateTime(2025, 6, 17, 0, 0, 0, 0);
  AssertNext('0 0 * 6 2#3', lBase, lExpected);
end;

procedure TTestScheduleNext.Next_Dow_NthInMonth_AfterMonth;
var
  lBase: TDateTime;
  lExpected: TDateTime;
begin
  lBase := EncodeDateTime(2025, 6, 20, 0, 0, 0, 0);
  lExpected := EncodeDateTime(2025, 7, 15, 0, 0, 0, 0);
  AssertNext('0 0 * * 2#3', lBase, lExpected);
end;

procedure TTestScheduleNext.Next_Dow_NthInMonth_SkipMonthWhenMissing;
var
  lBase: TDateTime;
  lExpected: TDateTime;
begin
  lBase := EncodeDateTime(2025, 2, 1, 0, 0, 0, 0);
  lExpected := EncodeDateTime(2025, 3, 31, 0, 0, 0, 0);
  AssertNext('0 0 * * 1#5', lBase, lExpected);
end;

procedure TTestScheduleNext.Next_Dow_NoSpec;
var
  Base: TDateTime;
  Expected: TDateTime;
begin
  Base := EncodeDateTime(2025, 6, 1, 0, 0, 0, 0);
  Expected := EncodeDateTime(2025, 7, 10, 0, 0, 0, 0);
  AssertNext('0 0 10 7 ?', Base, Expected);
end;

procedure TTestScheduleNext.Next_YearRestriction_NoLeapDay;
var
  Plan: TCronSchedulePlan;
  NextDt: TDateTime;
  Base: TDateTime;
begin
  Plan := TCronSchedulePlan.Create;
  try
    Plan.Parse('0 0 29 2 * 2025 0 0');
    Base := EncodeDateTime(2025, 1, 1, 0, 0, 0, 0);
    Assert.IsFalse(Plan.FindNextScheduleDate(Base, NextDt));
  finally
    Plan.Free;
  end;
end;

procedure TTestScheduleNext.Next_GetNextOccurrences_CountZero;
var
  Plan: TCronSchedulePlan;
  Dates: TDates;
  Base: TDateTime;
  Count: Integer;
begin
  Plan := TCronSchedulePlan.Create;
  try
    Plan.Parse('* * * * * *');
    Base := EncodeDateTime(2025, 1, 1, 0, 0, 0, 0);
    Count := Plan.GetNextOccurrences(0, Base, Dates);
    Assert.AreEqual(0, Count);
    Assert.AreEqual<Integer>(0, Length(Dates));
  finally
    Plan.Free;
  end;
end;

procedure TTestScheduleNext.Next_GetNextOccurrences_LargeCount;
const
  ExpectedCount = 20;
var
  Plan: TCronSchedulePlan;
  Dates: TDates;
  Base: TDateTime;
  Count: Integer;
  i: Integer;
begin
  Plan := TCronSchedulePlan.Create;
  try
    Plan.Parse('*/5 * * * * * 0 0');
    Base := EncodeDateTime(2025, 1, 1, 0, 0, 0, 0);
    Count := Plan.GetNextOccurrences(ExpectedCount, Base, Dates);
    Assert.AreEqual(ExpectedCount, Count);
    Assert.AreEqual<Integer>(ExpectedCount, Length(Dates));
    for i := 1 to Length(Dates) - 1 do
    begin
      Assert.IsTrue(Dates[i] > Dates[i - 1]);
      Assert.AreEqual<Int64>(5, MinutesBetween(Dates[i - 1], Dates[i]));
    end;
  finally
    Plan.Free;
  end;
end;

procedure TTestScheduleNext.Next_GetNextOccurrences_InvalidPlan;
var
  Plan: TCronSchedulePlan;
  Dates: TDates;
  Base: TDateTime;
  Count: Integer;
begin
  Plan := TCronSchedulePlan.Create;
  try
    Plan.Parse('0 0 29 2 * 2025 0 0');
    Base := EncodeDateTime(2025, 1, 1, 0, 0, 0, 0);
    Count := Plan.GetNextOccurrences(5, Base, Dates);
    Assert.AreEqual(0, Count);
    Assert.AreEqual<Integer>(0, Length(Dates));
  finally
    Plan.Free;
  end;
end;

end.

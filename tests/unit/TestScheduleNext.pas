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
    procedure Next_Dow_Sunday_ZeroOrSeven;

    [Test]
    procedure Next_Dom_LastDay;

    [Test]
    procedure Next_Dom_LastWeekday;

    [Test]
    procedure Next_Dom_NearestWeekday;

    [Test]
    procedure Next_Dom_NearestWeekday_AtMonthStart;

    [Test]
    procedure Next_Dom_NearestWeekday_AtMonthEnd;

    [Test]
    procedure Next_Dow_LastInMonth;

    [Test]
    procedure Next_Dow_NthInMonth;

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
  Base: TDateTime;
  Expected: TDateTime;
begin
  Base := EncodeDateTime(2025, 5, 1, 0, 0, 0, 0);
  Expected := EncodeDateTime(2025, 5, 30, 0, 0, 0, 0);
  AssertNext('0 0 LW 5 *', Base, Expected);
end;

procedure TTestScheduleNext.Next_Dom_NearestWeekday;
var
  Base: TDateTime;
  Expected: TDateTime;
begin
  Base := EncodeDateTime(2025, 3, 1, 0, 0, 0, 0);
  Expected := EncodeDateTime(2025, 3, 14, 0, 0, 0, 0);
  AssertNext('0 0 15W 3 *', Base, Expected);
end;

procedure TTestScheduleNext.Next_Dom_NearestWeekday_AtMonthStart;
var
  Base: TDateTime;
  Expected: TDateTime;
begin
  Base := EncodeDateTime(2025, 1, 31, 0, 0, 0, 0);
  Expected := EncodeDateTime(2025, 2, 3, 0, 0, 0, 0);
  AssertNext('0 0 1W 2 *', Base, Expected);
end;

procedure TTestScheduleNext.Next_Dom_NearestWeekday_AtMonthEnd;
var
  Base: TDateTime;
  Expected: TDateTime;
begin
  Base := EncodeDateTime(2025, 8, 1, 0, 0, 0, 0);
  Expected := EncodeDateTime(2025, 8, 29, 0, 0, 0, 0);
  AssertNext('0 0 31W 8 *', Base, Expected);
end;

procedure TTestScheduleNext.Next_Dow_LastInMonth;
var
  Base: TDateTime;
  Expected: TDateTime;
begin
  Base := EncodeDateTime(2025, 4, 1, 0, 0, 0, 0);
  Expected := EncodeDateTime(2025, 4, 25, 0, 0, 0, 0);
  AssertNext('0 0 * 4 5L', Base, Expected);
end;

procedure TTestScheduleNext.Next_Dow_NthInMonth;
var
  Base: TDateTime;
  Expected: TDateTime;
begin
  Base := EncodeDateTime(2025, 6, 1, 0, 0, 0, 0);
  Expected := EncodeDateTime(2025, 6, 17, 0, 0, 0, 0);
  AssertNext('0 0 * 6 2#3', Base, Expected);
end;

procedure TTestScheduleNext.Next_Dow_NthInMonth_SkipMonthWhenMissing;
var
  Base: TDateTime;
  Expected: TDateTime;
begin
  Base := EncodeDateTime(2025, 2, 1, 0, 0, 0, 0);
  Expected := EncodeDateTime(2025, 3, 31, 0, 0, 0, 0);
  AssertNext('0 0 * * 1#5', Base, Expected);
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

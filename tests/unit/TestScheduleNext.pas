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

end.

unit TestValidRange;

interface

uses
  System.DateUtils, System.Diagnostics, System.SysUtils, System.SyncObjs, System.Classes,
  DUnitX.TestFramework,
  maxCron;

type
  [TestFixture]
  TTestValidRange = class
  public
    [Test]
    procedure ValidFromTo_StopsOutsideWindow;

    [Test]
    procedure ValidFromTo_InclusiveBoundaries;

    [Test]
    procedure ValidFrom_ReschedulesWhenEnabled;

    [Test]
    procedure ValidTo_DisablesWhenPast;
  end;

implementation

procedure TTestValidRange.ValidFromTo_StopsOutsideWindow;
var
  Cron: TmaxCron;
  Evt: IMaxCronEvent;
  Count: Integer;
  StartAt: TDateTime;
  StopAt: TDateTime;
  Sw: TStopwatch;
begin
  Count := 0;
  Cron := TmaxCron.Create(ctPortable);
  try
    Evt := Cron.Add('Range');
    Evt.EventPlan := '* * * * * * * 0';
    Evt.InvokeMode := imThread;
    Evt.OverlapMode := omAllowOverlap;
    Evt.OnScheduleProc :=
      procedure(Sender: IMaxCronEvent)
      begin
        TInterlocked.Increment(Count);
      end;

    StartAt := EncodeDateTime(2025, 1, 1, 0, 0, 5, 0);
    StopAt := EncodeDateTime(2025, 1, 1, 0, 0, 7, 0);
    Evt.ValidFrom := StartAt;
    Evt.ValidTo := StopAt;
    Evt.Run;

    Cron.TickAt(EncodeDateTime(2025, 1, 1, 0, 0, 4, 0)); // before window
    Cron.TickAt(EncodeDateTime(2025, 1, 1, 0, 0, 5, 0)); // inside window
    Cron.TickAt(EncodeDateTime(2025, 1, 1, 0, 0, 6, 0)); // inside window
    Cron.TickAt(EncodeDateTime(2025, 1, 1, 0, 0, 8, 0)); // after window

    Sw := TStopwatch.StartNew;
    while (TInterlocked.CompareExchange(Count, 0, 0) < 2) and (Sw.ElapsedMilliseconds < 3000) do
      TThread.Sleep(10);

    Assert.IsTrue(TInterlocked.CompareExchange(Count, 0, 0) <= 2);
  finally
    Cron.Free;
  end;
end;

procedure TTestValidRange.ValidFromTo_InclusiveBoundaries;
var
  Plan: TCronSchedulePlan;
  NextDt: TDateTime;
  Base: TDateTime;
  StartAt: TDateTime;
  StopAt: TDateTime;
begin
  Plan := TCronSchedulePlan.Create;
  try
    Plan.Parse('* * * * * * * 0');
    Base := EncodeDateTime(2025, 1, 1, 0, 0, 0, 0);
    StartAt := EncodeDateTime(2025, 1, 1, 0, 0, 5, 0);
    StopAt := EncodeDateTime(2025, 1, 1, 0, 0, 6, 0);
    Assert.IsTrue(Plan.FindNextScheduleDate(Base, NextDt, StartAt, StopAt));
    Assert.AreEqual(StopAt, NextDt, 0.0);
    Assert.IsFalse(Plan.FindNextScheduleDate(Base, NextDt, StartAt, StartAt));
  finally
    Plan.Free;
  end;
end;

procedure TTestValidRange.ValidFrom_ReschedulesWhenEnabled;
var
  Cron: TmaxCron;
  Evt: IMaxCronEvent;
  NewFrom: TDateTime;
  NextDt: TDateTime;
begin
  Cron := TmaxCron.Create(ctPortable);
  try
    Evt := Cron.Add('RangeUpdateFrom');
    Evt.EventPlan := '* * * * * * * 0';
    Evt.Run;

    NewFrom := IncMinute(Now, 5);
    Evt.ValidFrom := NewFrom;
    NextDt := Evt.NextSchedule;
    Assert.IsTrue(NextDt >= NewFrom);
  finally
    Cron.Free;
  end;
end;

procedure TTestValidRange.ValidTo_DisablesWhenPast;
var
  Cron: TmaxCron;
  Evt: IMaxCronEvent;
begin
  Cron := TmaxCron.Create(ctPortable);
  try
    Evt := Cron.Add('RangeUpdateTo');
    Evt.EventPlan := '* * * * * * * 0';
    Evt.Run;

    Evt.ValidTo := IncSecond(Now, -1);
    Assert.IsFalse(Evt.Enabled);
  finally
    Cron.Free;
  end;
end;

end.

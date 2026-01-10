unit TestLifecycle;

interface

uses
  System.DateUtils, System.Diagnostics, System.SysUtils, System.SyncObjs, System.Classes,
  DUnitX.TestFramework,
  maxCron;

type
  [TestFixture]
  TTestLifecycle = class
  public
    [Test]
    procedure DeleteEvent_WhileRunning_DoesNotCrash;

    [Test]
    procedure FreeScheduler_WhileRunning_DoesNotCrash;

    [Test]
    procedure UpdateEventPlan_RecalculatesNextSchedule;
  end;

implementation

procedure TTestLifecycle.DeleteEvent_WhileRunning_DoesNotCrash;
var
  Cron: TmaxCron;
  Evt: TmaxCronEvent;
  Started: TEvent;
  Gate: TEvent;
  Sw: TStopwatch;
  WaitRes: TWaitResult;
begin
  Cron := TmaxCron.Create(ctPortable);
  try
    Started := TEvent.Create(nil, True, False, '');
    Gate := TEvent.Create(nil, True, False, '');
    try
      Evt := Cron.Add('DeleteWhileRunning');
      Evt.EventPlan := '* * * * * * * 0';
      Evt.InvokeMode := imThread;
      Evt.OverlapMode := omSerialize;
      Evt.OnScheduleProc :=
        procedure(Sender: TmaxCronEvent)
        begin
          Started.SetEvent;
          Gate.WaitFor(3000);
        end;
      Evt.Run;

      Cron.TickAt(Evt.NextSchedule);
      WaitRes := Started.WaitFor(2000);
      Assert.AreEqual(TWaitResult.wrSignaled, WaitRes);

      Assert.IsTrue(Cron.Delete(Evt));
      Gate.SetEvent;

      Sw := TStopwatch.StartNew;
      while (Sw.ElapsedMilliseconds < 1000) do
      begin
        CheckSynchronize(10);
        TThread.Sleep(10);
      end;
    finally
      Gate.Free;
      Started.Free;
    end;
  finally
    Cron.Free;
  end;
end;

procedure TTestLifecycle.FreeScheduler_WhileRunning_DoesNotCrash;
var
  Cron: TmaxCron;
  Evt: TmaxCronEvent;
  Started: TEvent;
  Gate: TEvent;
  WaitRes: TWaitResult;
begin
  Cron := TmaxCron.Create(ctPortable);
  Started := TEvent.Create(nil, True, False, '');
  Gate := TEvent.Create(nil, True, False, '');
  try
    Evt := Cron.Add('FreeWhileRunning');
    Evt.EventPlan := '* * * * * * * 0';
    Evt.InvokeMode := imThread;
    Evt.OverlapMode := omSerializeCoalesce;
    Evt.OnScheduleProc :=
      procedure(Sender: TmaxCronEvent)
      begin
        Started.SetEvent;
        Gate.WaitFor(3000);
      end;
    Evt.Run;

    Cron.TickAt(Evt.NextSchedule);
    WaitRes := Started.WaitFor(2000);
    Assert.AreEqual(TWaitResult.wrSignaled, WaitRes);

    Gate.SetEvent;
    Cron.Free;
    Cron := nil;

    CheckSynchronize(50);
  finally
    Gate.Free;
    Started.Free;
    if Cron <> nil then
      Cron.Free;
  end;
end;

procedure TTestLifecycle.UpdateEventPlan_RecalculatesNextSchedule;
var
  Cron: TmaxCron;
  Evt: TmaxCronEvent;
  Base: TDateTime;
  SearchFrom: TDateTime;
  Expected: TDateTime;
  YearVal: Word;
begin
  Cron := TmaxCron.Create(ctPortable);
  try
    Evt := Cron.Add('UpdatePlan');
    Evt.EventPlan := '* * * * * * * 0';
    Evt.InvokeMode := imThread;
    Evt.Run;

    Base := EncodeDateTime(YearOf(Now), MonthOf(Now), DayOf(Now), HourOf(Now), MinuteOf(Now), SecondOf(Now), 0);
    Base := IncDay(Base, 1);
    Cron.TickAt(Base);

    Evt.EventPlan := '0 0 1 1 * * 0 0';
    SearchFrom := IncSecond(Base, 2);
    YearVal := YearOf(SearchFrom);
    Expected := EncodeDateTime(YearVal, 1, 1, 0, 0, 0, 0);
    if Expected <= SearchFrom then
      Expected := EncodeDateTime(YearVal + 1, 1, 1, 0, 0, 0, 0);

    Assert.AreEqual(Expected, Evt.NextSchedule, 0.0);
  finally
    Cron.Free;
  end;
end;

end.

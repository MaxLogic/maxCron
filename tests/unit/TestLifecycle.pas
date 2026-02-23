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
    procedure PortableTimer_TicksWithoutMainThreadPump;

    [Test]
    procedure UpdateEventPlan_RecalculatesNextSchedule;

    [Test]
    procedure LastExecution_UsesScheduledTime;

    [Test]
    procedure UpdateEventPlan_InvalidDoesNotChangePlan;

    [Test]
    procedure SetDialect_ReparsesEventPlan;

    [Test]
    procedure Add_DuplicateName_CaseInsensitive_Raises;

    [Test]
    procedure Add_EmptyName_AllowsMultipleEvents;

    [Test]
    procedure DeleteByName_CaseInsensitive_DeletesNamedEvent;

    [Test]
    procedure DeleteByEvent_UnnamedEvent_IsRejected;
  end;

implementation

procedure TTestLifecycle.DeleteEvent_WhileRunning_DoesNotCrash;
var
  Cron: TmaxCron;
  Evt: IMaxCronEvent;
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
        procedure(Sender: IMaxCronEvent)
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
  Evt: IMaxCronEvent;
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
      procedure(Sender: IMaxCronEvent)
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

procedure TTestLifecycle.PortableTimer_TicksWithoutMainThreadPump;
var
  lCron: TmaxCron;
  lEvt: IMaxCronEvent;
  lHit: TEvent;
  lWaitRes: TWaitResult;
begin
  lCron := TmaxCron.Create(ctPortable);
  lHit := TEvent.Create(nil, True, False, '');
  try
    lEvt := lCron.Add('PortableTick');
    lEvt.EventPlan := '* * * * * * * 1';
    lEvt.InvokeMode := imThread;
    lEvt.OnScheduleProc :=
      procedure(Sender: IMaxCronEvent)
      begin
        lHit.SetEvent;
      end;
    lEvt.Run;

    lCron.StartTimerForTests(50);
    lWaitRes := lHit.WaitFor(2500);
    Assert.AreEqual(TWaitResult.wrSignaled, lWaitRes);
  finally
    lHit.Free;
    lCron.Free;
  end;
end;

procedure TTestLifecycle.UpdateEventPlan_RecalculatesNextSchedule;
var
  Cron: TmaxCron;
  Evt: IMaxCronEvent;
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

procedure TTestLifecycle.LastExecution_UsesScheduledTime;
var
  lCron: TmaxCron;
  lEvt: IMaxCronEvent;
  lFirstSchedule: TDateTime;
  lTickTime: TDateTime;
  lEpsilon: Double;
begin
  lCron := TmaxCron.Create(ctPortable);
  try
    lEvt := lCron.Add('LastExecutionTime');
    lEvt.EventPlan := '* * * * * * * 0';
    lEvt.Run;

    lFirstSchedule := lEvt.NextSchedule;
    lTickTime := IncMilliSecond(lFirstSchedule, 500);
    lCron.TickAt(lTickTime);

    lEpsilon := 1 / (24 * 60 * 60 * 1000);
    Assert.AreEqual(lFirstSchedule, lEvt.LastExecution, lEpsilon);
    Assert.AreEqual(IncSecond(lFirstSchedule, 1), lEvt.NextSchedule, lEpsilon);
  finally
    lCron.Free;
  end;
end;

procedure TTestLifecycle.UpdateEventPlan_InvalidDoesNotChangePlan;
var
  lCron: TmaxCron;
  lEvt: IMaxCronEvent;
  lPrevPlan: string;
  lPrevNext: TDateTime;
begin
  lCron := TmaxCron.Create(ctPortable);
  try
    lEvt := lCron.Add('InvalidPlan');
    lEvt.EventPlan := '* * * * * * * 0';
    lEvt.Run;

    lPrevPlan := lEvt.EventPlan;
    lPrevNext := lEvt.NextSchedule;
    try
      lEvt.EventPlan := '0 0 0 * * *'; // invalid day-of-month
      Assert.Fail('Expected parse error');
    except
      on Exception do
        ; // expected
    end;

    Assert.AreEqual(lPrevPlan, lEvt.EventPlan);
    Assert.AreEqual(lPrevNext, lEvt.NextSchedule, 0.0);
  finally
    lCron.Free;
  end;
end;

procedure TTestLifecycle.SetDialect_ReparsesEventPlan;
var
  lCron: TmaxCron;
  lEvt: IMaxCronEvent;
  lPrevNext: TDateTime;
  lPrevDialect: TmaxCronDialect;
begin
  lCron := TmaxCron.Create(ctPortable);
  try
    lEvt := lCron.Add('DialectReparse');
    lEvt.Dialect := cdQuartzSecondsFirst;
    lEvt.EventPlan := '0 0 0 ? * 2';
    lEvt.Run;

    lPrevNext := lEvt.NextSchedule;
    lPrevDialect := lEvt.Dialect;
    try
      lEvt.Dialect := cdStandard;
      Assert.Fail('Expected parse error');
    except
      on Exception do
        ; // expected
    end;

    Assert.AreEqual(lPrevDialect, lEvt.Dialect);
    Assert.AreEqual(lPrevNext, lEvt.NextSchedule, 0.0);
  finally
    lCron.Free;
  end;
end;

procedure TTestLifecycle.Add_DuplicateName_CaseInsensitive_Raises;
var
  lCron: TmaxCron;
begin
  lCron := TmaxCron.Create(ctPortable);
  try
    lCron.Add('Alpha');
    try
      lCron.Add('alpha');
      Assert.Fail('Expected duplicate-name validation error');
    except
      on Exception do
        ; // expected
    end;

    Assert.AreEqual(1, lCron.Count);
  finally
    lCron.Free;
  end;
end;

procedure TTestLifecycle.Add_EmptyName_AllowsMultipleEvents;
var
  lCron: TmaxCron;
  lEventA: IMaxCronEvent;
  lEventB: IMaxCronEvent;
begin
  lCron := TmaxCron.Create(ctPortable);
  try
    lEventA := lCron.Add('');
    lEventB := lCron.Add('   ');

    Assert.AreEqual('', lEventA.Name);
    Assert.AreEqual('', lEventB.Name);
    Assert.AreEqual(2, lCron.Count);
  finally
    lCron.Free;
  end;
end;

procedure TTestLifecycle.DeleteByName_CaseInsensitive_DeletesNamedEvent;
var
  lCron: TmaxCron;
  lNamed: IMaxCronEvent;
begin
  lCron := TmaxCron.Create(ctPortable);
  try
    lNamed := lCron.Add('MyEvent');
    lCron.Add('');
    Assert.AreEqual(2, lCron.Count);

    Assert.IsTrue(lCron.Delete('myevent'));
    Assert.AreEqual(1, lCron.Count);
    Assert.AreEqual('', lCron.Events[0].Name);
    Assert.IsFalse(lCron.Delete(''));
    Assert.IsFalse(lCron.Delete('missing'));
    Assert.AreEqual('MyEvent', lNamed.Name);
  finally
    lCron.Free;
  end;
end;

procedure TTestLifecycle.DeleteByEvent_UnnamedEvent_IsRejected;
var
  lCron: TmaxCron;
  lUnnamed: IMaxCronEvent;
begin
  lCron := TmaxCron.Create(ctPortable);
  try
    lUnnamed := lCron.Add('');
    Assert.AreEqual('', lUnnamed.Name);

    Assert.IsFalse(lCron.Delete(lUnnamed));
    Assert.AreEqual(1, lCron.Count);
    Assert.IsTrue(lCron.Delete(0));
  finally
    lCron.Free;
  end;
end;

end.

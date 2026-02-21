unit TestDispatchStartFailures;

interface

uses
  System.DateUtils, System.SyncObjs, System.SysUtils,
  DUnitX.TestFramework,
  maxCron;

type
  [TestFixture]
  TTestDispatchStartFailures = class
  private
    procedure RunDispatchStartFailureRecovery(const aInvokeMode: TmaxCronInvokeMode);
    procedure RunDispatchStartFailureExecutionLimitRetry(const aInvokeMode: TmaxCronInvokeMode);
  public
    [Test]
    procedure DispatchStartFailure_TTask_ReleasesOverlapState;

    [Test]
    procedure DispatchStartFailure_Thread_ReleasesOverlapState;

    [Test]
    procedure DispatchStartFailure_ExecutionLimitRetry_TTask;

    [Test]
    procedure DispatchStartFailure_ExecutionLimitRetry_Thread;
  end;

implementation

procedure TTestDispatchStartFailures.RunDispatchStartFailureRecovery(const aInvokeMode: TmaxCronInvokeMode);
var
  lCron: TmaxCron;
  lEvent: TmaxCronEvent;
  lFired: TEvent;
  lRaised: Boolean;
  lTriggered: Integer;
  lInjectOnce: Integer;
  lFirstAt: TDateTime;
  lSecondAt: TDateTime;
begin
  lCron := TmaxCron.Create(ctPortable);
  lFired := TEvent.Create(nil, True, False, '');
  lRaised := False;
  lTriggered := 0;
  lInjectOnce := 0;
  try
    lEvent := lCron.Add('DispatchStartFailure');
    lEvent.EventPlan := '* * * * * * * 0';
    lEvent.InvokeMode := aInvokeMode;
    lEvent.OverlapMode := omSkipIfRunning;
    lEvent.OnScheduleProc :=
      procedure(aSender: TmaxCronEvent)
      begin
        TInterlocked.Increment(lTriggered);
        lFired.SetEvent;
      end;
    lEvent.Run;
    lFirstAt := lEvent.NextSchedule;

    SetMaxCronBeforeDispatchHook(
      procedure(const aDispatchMode: TmaxCronInvokeMode)
      begin
        if (aDispatchMode = aInvokeMode) and (TInterlocked.CompareExchange(lInjectOnce, 1, 0) = 0) then
          raise Exception.Create('injected dispatch-start failure');
      end);
    try
      try
        lCron.TickAt(lFirstAt);
      except
        on Exception do
          lRaised := True;
      end;
    finally
      SetMaxCronBeforeDispatchHook(nil);
    end;

    Assert.IsTrue(lRaised, 'Expected injected dispatch-start failure');

    lSecondAt := lEvent.NextSchedule;
    lCron.TickAt(lSecondAt);
    Assert.AreEqual(TWaitResult.wrSignaled, lFired.WaitFor(1500),
      'Event remained locked after dispatch-start failure');
    Assert.AreEqual(1, TInterlocked.CompareExchange(lTriggered, 0, 0),
      'Expected one successful callback after recovery tick');
  finally
    SetMaxCronBeforeDispatchHook(nil);
    lFired.Free;
    // Pre-fix behavior can wedge overlap state and block destructor forever.
    // Keep the failing test bounded; once fixed, callbacks fire and teardown runs.
    if TInterlocked.CompareExchange(lTriggered, 0, 0) > 0 then
      lCron.Free;
  end;
end;

procedure TTestDispatchStartFailures.RunDispatchStartFailureExecutionLimitRetry(const aInvokeMode: TmaxCronInvokeMode);
var
  lCron: TmaxCron;
  lEvent: TmaxCronEvent;
  lFired: TEvent;
  lRaised: Boolean;
  lDispatchCount: Integer;
  lFirstAt: TDateTime;
  lSecondAt: TDateTime;
  lWaitRes: TWaitResult;
begin
  lCron := TmaxCron.Create(ctPortable);
  lFired := TEvent.Create(nil, True, False, '');
  lRaised := False;
  lDispatchCount := 0;
  try
    lEvent := lCron.Add('DispatchStartFailureLimit');
    lEvent.EventPlan := '* * * * * * * 1';
    lEvent.InvokeMode := aInvokeMode;
    lEvent.OverlapMode := omSkipIfRunning;
    lEvent.OnScheduleProc :=
      procedure(aSender: TmaxCronEvent)
      begin
        lFired.SetEvent;
      end;
    lEvent.Run;
    lFirstAt := lEvent.NextSchedule;

    SetMaxCronBeforeDispatchHook(
      procedure(const aDispatchMode: TmaxCronInvokeMode)
      begin
        if (aDispatchMode = aInvokeMode) and (TInterlocked.Increment(lDispatchCount) = 1) then
          raise Exception.Create('injected dispatch-start failure');
      end);
    try
      try
        lCron.TickAt(lFirstAt);
      except
        on Exception do
          lRaised := True;
      end;
    finally
      SetMaxCronBeforeDispatchHook(nil);
    end;

    Assert.IsTrue(lRaised, 'Expected injected dispatch-start failure');

    lSecondAt := IncSecond(lFirstAt, 5);
    lCron.TickAt(lSecondAt);
    lWaitRes := lFired.WaitFor(1500);
    if lWaitRes <> TWaitResult.wrSignaled then
    begin
      lCron.TickAt(IncSecond(lSecondAt, 5));
      lWaitRes := lFired.WaitFor(1500);
    end;
    Assert.AreEqual(TWaitResult.wrSignaled, lWaitRes,
      'ExecutionLimit should count only actual callback executions');
    Assert.AreEqual(UInt64(1), lEvent.NumOfExecutionsPerformed,
      'Expected exactly one successful callback execution after retry');
  finally
    SetMaxCronBeforeDispatchHook(nil);
    lFired.Free;
    lCron.Free;
  end;
end;

procedure TTestDispatchStartFailures.DispatchStartFailure_TTask_ReleasesOverlapState;
begin
  RunDispatchStartFailureRecovery(imTTask);
end;

procedure TTestDispatchStartFailures.DispatchStartFailure_Thread_ReleasesOverlapState;
begin
  RunDispatchStartFailureRecovery(imThread);
end;

procedure TTestDispatchStartFailures.DispatchStartFailure_ExecutionLimitRetry_TTask;
begin
  RunDispatchStartFailureExecutionLimitRetry(imTTask);
end;

procedure TTestDispatchStartFailures.DispatchStartFailure_ExecutionLimitRetry_Thread;
begin
  RunDispatchStartFailureExecutionLimitRetry(imThread);
end;

end.

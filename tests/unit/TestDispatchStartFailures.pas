unit TestDispatchStartFailures;

interface

uses
  System.SyncObjs, System.SysUtils,
  DUnitX.TestFramework,
  maxCron;

type
  [TestFixture]
  TTestDispatchStartFailures = class
  private
    procedure RunDispatchStartFailureRecovery(const aInvokeMode: TmaxCronInvokeMode);
  public
    [Test]
    procedure DispatchStartFailure_TTask_ReleasesOverlapState;

    [Test]
    procedure DispatchStartFailure_Thread_ReleasesOverlapState;
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

procedure TTestDispatchStartFailures.DispatchStartFailure_TTask_ReleasesOverlapState;
begin
  RunDispatchStartFailureRecovery(imTTask);
end;

procedure TTestDispatchStartFailures.DispatchStartFailure_Thread_ReleasesOverlapState;
begin
  RunDispatchStartFailureRecovery(imThread);
end;

end.

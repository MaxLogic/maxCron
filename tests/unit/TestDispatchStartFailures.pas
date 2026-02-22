unit TestDispatchStartFailures;

interface

uses
  System.Classes, System.DateUtils, System.Diagnostics, System.SyncObjs, System.SysUtils,
  DUnitX.TestFramework,
  maxCron;

type
  [TestFixture]
  TTestDispatchStartFailures = class
  private
    procedure RunDispatchStartFailureRecovery(const aInvokeMode: TmaxCronInvokeMode);
    procedure RunDispatchStartFailureExecutionLimitRetry(const aInvokeMode: TmaxCronInvokeMode);
    procedure RunQueuedMainThreadAcquireFailureExecutionLimitRetry;
    procedure RunSerializeChainDispatchStartFailureRetry(const aInvokeMode: TmaxCronInvokeMode);
  public
    [Test]
    procedure DispatchStartFailure_TTask_ReleasesOverlapState;

    [Test]
    procedure DispatchStartFailure_Thread_ReleasesOverlapState;

    [Test]
    procedure DispatchStartFailure_ExecutionLimitRetry_TTask;

    [Test]
    procedure DispatchStartFailure_ExecutionLimitRetry_Thread;

    [Test]
    procedure QueuedMainThread_PreAcquireFailure_ExecutionLimitRetry;

    [Test]
    procedure SerializeChain_DispatchStartFailure_RetriesAfterRollback;

    [Test]
    procedure SerializeChain_DispatchStartFailure_RetriesAfterRollback_Repeated;
  end;

implementation

procedure TTestDispatchStartFailures.RunDispatchStartFailureRecovery(const aInvokeMode: TmaxCronInvokeMode);
var
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
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
      procedure(aSender: IMaxCronEvent)
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
  lEvent: IMaxCronEvent;
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
      procedure(aSender: IMaxCronEvent)
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

procedure TTestDispatchStartFailures.RunQueuedMainThreadAcquireFailureExecutionLimitRetry;
var
  lCron: TmaxCron;
  lCronToFree: TmaxCron;
  lEvent: IMaxCronEvent;
  lFired: TEvent;
  lWorkerDone: TEvent;
  lFreeDone: TEvent;
  lHookInjectCount: Integer;
  lDispatchCount: Integer;
  lFirstAt: TDateTime;
  lSecondAt: TDateTime;
  lWaitRes: TWaitResult;
  lWorker: TThread;
  lFreeThread: TThread;
  lCanFreeCron: Boolean;
begin
  lCron := TmaxCron.Create(ctPortable);
  lCronToFree := nil;
  lFired := TEvent.Create(nil, True, False, '');
  lWorkerDone := TEvent.Create(nil, True, False, '');
  lFreeDone := TEvent.Create(nil, True, False, '');
  lHookInjectCount := 0;
  lDispatchCount := 0;
  lWorker := nil;
  lFreeThread := nil;
  lCanFreeCron := False;
  try
    lEvent := lCron.Add('QueuedPreAcquireFailure');
    lEvent.EventPlan := '* * * * * * * 1';
    lEvent.InvokeMode := imMainThread;
    lEvent.OverlapMode := omSkipIfRunning;
    lEvent.OnScheduleProc :=
      procedure(aSender: IMaxCronEvent)
      begin
        TInterlocked.Increment(lDispatchCount);
        lFired.SetEvent;
      end;
    lEvent.Run;
    lFirstAt := lEvent.NextSchedule;

    SetMaxCronBeforeQueuedAcquireHook(
      procedure(const aEvent: IMaxCronEvent)
      begin
        if (aEvent = lEvent) and (TInterlocked.CompareExchange(lHookInjectCount, 1, 0) = 0) then
          raise Exception.Create('injected queued pre-acquire failure');
      end);
    try
      lWorkerDone.ResetEvent;
      lWorker := TThread.CreateAnonymousThread(
        procedure
        begin
          try
            lCron.TickAt(lFirstAt);
          finally
            lWorkerDone.SetEvent;
          end;
        end);
      lWorker.FreeOnTerminate := True;
      lWorker.Start;

      lWaitRes := lWorkerDone.WaitFor(2000);
      Assert.AreEqual(TWaitResult.wrSignaled, lWaitRes, 'Worker did not run first tick');

      try
        CheckSynchronize(500);
      except
        on Exception do
          ;
      end;
    finally
      SetMaxCronBeforeQueuedAcquireHook(nil);
    end;

    Assert.AreEqual(1, TInterlocked.CompareExchange(lHookInjectCount, 0, 0),
      'Expected exactly one injected queued pre-acquire failure');

    lSecondAt := IncSecond(lFirstAt, 5);
    lWorkerDone.ResetEvent;
    lWorker := TThread.CreateAnonymousThread(
      procedure
      begin
        try
          lCron.TickAt(lSecondAt);
        finally
          lWorkerDone.SetEvent;
        end;
      end);
    lWorker.FreeOnTerminate := True;
    lWorker.Start;

    lWaitRes := lWorkerDone.WaitFor(2000);
    Assert.AreEqual(TWaitResult.wrSignaled, lWaitRes, 'Worker did not run second tick');

    CheckSynchronize(500);
    lWaitRes := lFired.WaitFor(1500);
    if lWaitRes <> TWaitResult.wrSignaled then
    begin
      lWorkerDone.ResetEvent;
      lWorker := TThread.CreateAnonymousThread(
        procedure
        begin
          try
            lCron.TickAt(IncSecond(lSecondAt, 5));
          finally
            lWorkerDone.SetEvent;
          end;
        end);
      lWorker.FreeOnTerminate := True;
      lWorker.Start;
      Assert.AreEqual(TWaitResult.wrSignaled, lWorkerDone.WaitFor(2000), 'Worker did not run retry tick');
      CheckSynchronize(500);
      lWaitRes := lFired.WaitFor(1500);
    end;

    Assert.AreEqual(TWaitResult.wrSignaled, lWaitRes,
      'ExecutionLimit should not be consumed by queued pre-acquire failure');
    Assert.AreEqual(UInt64(1), lEvent.NumOfExecutionsPerformed,
      'Expected one successful callback execution after queued failure retry');
    Assert.AreEqual(1, TInterlocked.CompareExchange(lDispatchCount, 0, 0),
      'Expected one successful callback execution after queued failure retry');
    lCanFreeCron := True;
  finally
    SetMaxCronBeforeQueuedAcquireHook(nil);
    lWorkerDone.Free;
    lFired.Free;
    if lCanFreeCron then
    begin
      lCronToFree := lCron;
      lCron := nil;
      lFreeDone.ResetEvent;
      lFreeThread := TThread.CreateAnonymousThread(
        procedure
        begin
          try
            lCronToFree.Free;
          finally
            lFreeDone.SetEvent;
          end;
        end);
      lFreeThread.FreeOnTerminate := True;
      lFreeThread.Start;
      lWaitRes := lFreeDone.WaitFor(3000);
      Assert.AreEqual(TWaitResult.wrSignaled, lWaitRes,
        'TmaxCron.Free should not hang after queued pre-acquire failure path');
    end;
    lFreeDone.Free;
  end;
end;

procedure TTestDispatchStartFailures.RunSerializeChainDispatchStartFailureRetry(const aInvokeMode: TmaxCronInvokeMode);
var
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lFirstStarted: TEvent;
  lFirstFinished: TEvent;
  lFirstGate: TEvent;
  lSecondStarted: TEvent;
  lDispatchAttempts: Integer;
  lCallbackCount: Integer;
  lFirstAt: TDateTime;
  lSecondAt: TDateTime;
  lThirdAt: TDateTime;
  lRetryAt: TDateTime;
  lRetryIndex: Integer;
  lWaitRes: TWaitResult;
  lCanFreeCron: Boolean;
  lWaitSw: TStopwatch;
begin
  lCron := TmaxCron.Create(ctPortable);
  lFirstStarted := TEvent.Create(nil, True, False, '');
  lFirstFinished := TEvent.Create(nil, True, False, '');
  lFirstGate := TEvent.Create(nil, True, False, '');
  lSecondStarted := TEvent.Create(nil, True, False, '');
  lDispatchAttempts := 0;
  lCallbackCount := 0;
  lCanFreeCron := False;
  try
    lEvent := lCron.Add('SerializeFinalizeDispatchFailure');
    lEvent.EventPlan := '* * * * * * * 0';
    lEvent.InvokeMode := aInvokeMode;
    lEvent.OverlapMode := omSerialize;
    lEvent.OnScheduleProc :=
      procedure(aSender: IMaxCronEvent)
      var
        lRunNo: Integer;
      begin
        lRunNo := TInterlocked.Increment(lCallbackCount);
        if lRunNo = 1 then
        begin
          lFirstStarted.SetEvent;
          lFirstGate.WaitFor(3000);
          lFirstFinished.SetEvent;
        end else begin
          lSecondStarted.SetEvent;
        end;
      end;
    lEvent.Run;
    lFirstAt := lEvent.NextSchedule;

    SetMaxCronBeforeDispatchHook(
      procedure(const aDispatchMode: TmaxCronInvokeMode)
      begin
        if (aDispatchMode = aInvokeMode) and (TInterlocked.Increment(lDispatchAttempts) = 2) then
          raise Exception.Create('injected serialize-chain dispatch-start failure');
      end);
    try
      lCron.TickAt(lFirstAt);
      lWaitRes := lFirstStarted.WaitFor(2000);
      Assert.AreEqual(TWaitResult.wrSignaled, lWaitRes, 'First serialized callback did not start');

      lSecondAt := lEvent.NextSchedule;
      lCron.TickAt(lSecondAt);
      lThirdAt := lEvent.NextSchedule;
      lFirstGate.SetEvent;
      lWaitRes := lFirstFinished.WaitFor(2000);
      Assert.AreEqual(TWaitResult.wrSignaled, lWaitRes, 'First serialized callback did not finish');

      lWaitSw := TStopwatch.StartNew;
      while (TInterlocked.CompareExchange(lDispatchAttempts, 0, 0) < 2) and
        (lWaitSw.ElapsedMilliseconds < 2000) do
        TThread.Sleep(10);
    finally
      SetMaxCronBeforeDispatchHook(nil);
    end;

    if TInterlocked.CompareExchange(lDispatchAttempts, 0, 0) < 2 then
      lCanFreeCron := True;
    Assert.IsTrue(TInterlocked.CompareExchange(lDispatchAttempts, 0, 0) >= 2,
      'Expected injected dispatch-start failure in serialized finalize chain');
    lWaitRes := TWaitResult.wrTimeout;
    lRetryAt := lThirdAt;
    for lRetryIndex := 0 to 5 do
    begin
      lCron.TickAt(lRetryAt);
      lWaitRes := lSecondStarted.WaitFor(500);
      if lWaitRes = TWaitResult.wrSignaled then
        Break;
      lRetryAt := IncSecond(lRetryAt, 1);
    end;
    Assert.AreEqual(TWaitResult.wrSignaled, lWaitRes,
      'Serialized chain should recover after dispatch-start rollback');
    Assert.AreEqual(2, TInterlocked.CompareExchange(lCallbackCount, 0, 0),
      'Expected exactly two callback executions after retry');
    lCanFreeCron := True;
  finally
    SetMaxCronBeforeDispatchHook(nil);
    lFirstGate.SetEvent;
    lSecondStarted.Free;
    lFirstGate.Free;
    lFirstFinished.Free;
    lFirstStarted.Free;
    if lCanFreeCron then
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

procedure TTestDispatchStartFailures.QueuedMainThread_PreAcquireFailure_ExecutionLimitRetry;
begin
  RunQueuedMainThreadAcquireFailureExecutionLimitRetry;
end;

procedure TTestDispatchStartFailures.SerializeChain_DispatchStartFailure_RetriesAfterRollback;
begin
  RunSerializeChainDispatchStartFailureRetry(imThread);
end;

procedure TTestDispatchStartFailures.SerializeChain_DispatchStartFailure_RetriesAfterRollback_Repeated;
var
  lIndex: Integer;
begin
  for lIndex := 1 to 10 do
    RunSerializeChainDispatchStartFailureRetry(imThread);
end;

end.

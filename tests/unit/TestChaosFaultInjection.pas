unit TestChaosFaultInjection;

interface

uses
  System.Classes, System.DateUtils, System.Diagnostics, System.SyncObjs, System.SysUtils,
  DUnitX.TestFramework,
  maxCron;

type
  [TestFixture]
  TTestChaosFaultInjection = class
  private
    procedure RunWorkerTick(const aCron: TmaxCron; const aTickAt: TDateTime; const aDone: TEvent);
    procedure RunFreeWithTimeout(var aCron: TmaxCron; const aTimeoutMs: Cardinal);
  public
    [Test]
    procedure QueueAcquireFailure_DelayedSynchronize_RecoversAndDoesNotDeadlock;

    [Test]
    procedure DispatchStartFailure_Thread_ReleasesSerializeAndRecovers;

    [Test]
    procedure CallbackException_Serialize_DoesNotWedgeSubsequentRuns;

    [Test]
    procedure CancellationRace_DeleteDuringCallback_ShutdownStaysBounded;
  end;

implementation

procedure TTestChaosFaultInjection.RunWorkerTick(const aCron: TmaxCron; const aTickAt: TDateTime;
  const aDone: TEvent);
var
  lWorker: TThread;
begin
  lWorker := TThread.CreateAnonymousThread(
    procedure
    begin
      try
        aCron.TickAt(aTickAt);
      finally
        if aDone <> nil then
          aDone.SetEvent;
      end;
    end);
  lWorker.FreeOnTerminate := True;
  lWorker.Start;
end;

procedure TTestChaosFaultInjection.RunFreeWithTimeout(var aCron: TmaxCron; const aTimeoutMs: Cardinal);
var
  lFreeDone: TEvent;
  lFreeThread: TThread;
  lStopwatch: TStopwatch;
  lWaitRes: TWaitResult;
  lCronToFree: TmaxCron;
begin
  if aCron = nil then
    Exit;

  lCronToFree := aCron;
  aCron := nil;

  lFreeDone := TEvent.Create(nil, True, False, '');
  try
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

    lStopwatch := TStopwatch.StartNew;
    repeat
      lWaitRes := lFreeDone.WaitFor(10);
      if lWaitRes = TWaitResult.wrSignaled then
        Break;
      CheckSynchronize(0);
    until lStopwatch.ElapsedMilliseconds >= Integer(aTimeoutMs);

    Assert.AreEqual(TWaitResult.wrSignaled, lWaitRes,
      Format('TmaxCron.Free exceeded timeout (%d ms)', [aTimeoutMs]));
  finally
    lFreeDone.Free;
  end;
end;

procedure TTestChaosFaultInjection.QueueAcquireFailure_DelayedSynchronize_RecoversAndDoesNotDeadlock;
var
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lWorkerDone: TEvent;
  lFired: TEvent;
  lInjectCount: Integer;
  lFirstAt: TDateTime;
  lSecondAt: TDateTime;
  lThirdAt: TDateTime;
  lWaitRes: TWaitResult;
  lPumpStart: TStopwatch;
begin
  lCron := TmaxCron.Create(ctPortable);
  lWorkerDone := TEvent.Create(nil, True, False, '');
  lFired := TEvent.Create(nil, True, False, '');
  lInjectCount := 0;
  try
    lEvent := lCron.Add('ChaosQueuedAcquire');
    lEvent.EventPlan := '* * * * * * * 2';
    lEvent.InvokeMode := imMainThread;
    lEvent.OverlapMode := omSerialize;
    lEvent.OnScheduleProc :=
      procedure(aSender: IMaxCronEvent)
      begin
        lFired.SetEvent;
      end;
    lEvent.Run;

    lFirstAt := lEvent.NextSchedule;

    SetMaxCronBeforeQueuedAcquireHook(
      procedure(const aInjectedEvent: IMaxCronEvent)
      begin
        if TInterlocked.CompareExchange(lInjectCount, 1, 0) = 0 then
          raise Exception.Create('chaos queued acquire failure');
      end);
    lWorkerDone.ResetEvent;
    RunWorkerTick(lCron, lFirstAt, lWorkerDone);
    Assert.AreEqual(TWaitResult.wrSignaled, lWorkerDone.WaitFor(2000),
      'First worker tick did not complete');

    // Keep main-thread dispatch intentionally delayed to exercise delayed synchronize boundary.
    TThread.Sleep(120);

    lSecondAt := IncSecond(lFirstAt, 2);
    lWorkerDone.ResetEvent;
    RunWorkerTick(lCron, lSecondAt, lWorkerDone);
    Assert.AreEqual(TWaitResult.wrSignaled, lWorkerDone.WaitFor(2000),
      'Second worker tick did not complete');

    lPumpStart := TStopwatch.StartNew;
    repeat
      CheckSynchronize(10);
      lWaitRes := lFired.WaitFor(0);
      if lWaitRes = TWaitResult.wrSignaled then
        Break;
    until lPumpStart.ElapsedMilliseconds >= 2000;

    if lFired.WaitFor(0) <> TWaitResult.wrSignaled then
    begin
      lThirdAt := IncSecond(lSecondAt, 2);
      lWorkerDone.ResetEvent;
      RunWorkerTick(lCron, lThirdAt, lWorkerDone);
      Assert.AreEqual(TWaitResult.wrSignaled, lWorkerDone.WaitFor(2000),
        'Third worker tick did not complete');

      lPumpStart := TStopwatch.StartNew;
      repeat
        CheckSynchronize(10);
        lWaitRes := lFired.WaitFor(0);
        if lWaitRes = TWaitResult.wrSignaled then
          Break;
      until lPumpStart.ElapsedMilliseconds >= 2000;
    end;

    Assert.AreEqual(1, TInterlocked.CompareExchange(lInjectCount, 0, 0),
      'Expected exactly one queued acquire injection');
    Assert.AreEqual(TWaitResult.wrSignaled, lFired.WaitFor(0),
      'Queued callback did not recover after delayed synchronize boundary');
  finally
    SetMaxCronBeforeQueuedAcquireHook(nil);
    lFired.Free;
    lWorkerDone.Free;
    RunFreeWithTimeout(lCron, 3000);
  end;
end;

procedure TTestChaosFaultInjection.DispatchStartFailure_Thread_ReleasesSerializeAndRecovers;
var
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lFired: TEvent;
  lFirstAt: TDateTime;
  lSecondAt: TDateTime;
  lInjectOnce: Integer;
  lRaised: Boolean;
begin
  lCron := TmaxCron.Create(ctPortable);
  lFired := TEvent.Create(nil, True, False, '');
  lInjectOnce := 0;
  lRaised := False;
  try
    lEvent := lCron.Add('ChaosDispatchStart');
    lEvent.EventPlan := '* * * * * * * 1';
    lEvent.InvokeMode := imThread;
    lEvent.OverlapMode := omSerialize;
    lEvent.OnScheduleProc :=
      procedure(aSender: IMaxCronEvent)
      begin
        lFired.SetEvent;
      end;
    lEvent.Run;

    lFirstAt := lEvent.NextSchedule;

    SetMaxCronBeforeDispatchHook(
      procedure(const aInvokeMode: TmaxCronInvokeMode)
      begin
        if (aInvokeMode = imThread) and (TInterlocked.CompareExchange(lInjectOnce, 1, 0) = 0) then
          raise Exception.Create('chaos dispatch start failure');
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

    Assert.IsTrue(lRaised, 'Expected dispatch-start injection to surface');

    lSecondAt := IncSecond(lFirstAt, 2);
    lCron.TickAt(lSecondAt);
    Assert.AreEqual(TWaitResult.wrSignaled, lFired.WaitFor(2000),
      'Serialized path stayed wedged after dispatch-start failure');
  finally
    SetMaxCronBeforeDispatchHook(nil);
    lFired.Free;
    RunFreeWithTimeout(lCron, 3000);
  end;
end;

procedure TTestChaosFaultInjection.CallbackException_Serialize_DoesNotWedgeSubsequentRuns;
var
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lFired: TEvent;
  lRunCount: Integer;
  lFirstAt: TDateTime;
  lSecondAt: TDateTime;
begin
  lCron := TmaxCron.Create(ctPortable);
  lFired := TEvent.Create(nil, True, False, '');
  lRunCount := 0;
  try
    lEvent := lCron.Add('ChaosCallbackException');
    lEvent.EventPlan := '* * * * * * * 0';
    lEvent.InvokeMode := imThread;
    lEvent.OverlapMode := omSerialize;
    lEvent.OnScheduleProc :=
      procedure(aSender: IMaxCronEvent)
      begin
        if TInterlocked.Increment(lRunCount) = 1 then
          raise Exception.Create('chaos callback exception');
        lFired.SetEvent;
      end;
    lEvent.Run;

    lFirstAt := lEvent.NextSchedule;
    lCron.TickAt(lFirstAt);

    TThread.Sleep(120);

    lSecondAt := IncSecond(lFirstAt, 2);
    lCron.TickAt(lSecondAt);

    Assert.AreEqual(TWaitResult.wrSignaled, lFired.WaitFor(2000),
      'Second serialized callback did not execute after callback exception');
    Assert.IsTrue(TInterlocked.CompareExchange(lRunCount, 0, 0) >= 2,
      'Expected second callback execution after exception recovery');
  finally
    lFired.Free;
    RunFreeWithTimeout(lCron, 3000);
  end;
end;

procedure TTestChaosFaultInjection.CancellationRace_DeleteDuringCallback_ShutdownStaysBounded;
var
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lEntered: TEvent;
  lRelease: TEvent;
  lWorkerDone: TEvent;
  lTickAt: TDateTime;
  lWaitRes: TWaitResult;
begin
  lCron := TmaxCron.Create(ctPortable);
  lEntered := TEvent.Create(nil, True, False, '');
  lRelease := TEvent.Create(nil, True, False, '');
  lWorkerDone := TEvent.Create(nil, True, False, '');
  try
    lEvent := lCron.Add('ChaosCancellationRace');
    lEvent.EventPlan := '* * * * * * * 0';
    lEvent.InvokeMode := imThread;
    lEvent.OverlapMode := omSerialize;
    lEvent.OnScheduleProc :=
      procedure(aSender: IMaxCronEvent)
      begin
        lEntered.SetEvent;
        lRelease.WaitFor(2000);
      end;
    lEvent.Run;

    lTickAt := lEvent.NextSchedule;
    RunWorkerTick(lCron, lTickAt, lWorkerDone);

    lWaitRes := lEntered.WaitFor(1500);
    Assert.AreEqual(TWaitResult.wrSignaled, lWaitRes, 'Callback did not enter for cancellation race');

    Assert.IsTrue(lCron.Delete(lEvent), 'Expected deletion during in-flight callback to succeed');

    lRelease.SetEvent;
    Assert.AreEqual(TWaitResult.wrSignaled, lWorkerDone.WaitFor(2500), 'Worker tick did not finish');
  finally
    lWorkerDone.Free;
    lRelease.Free;
    lEntered.Free;
    RunFreeWithTimeout(lCron, 3000);
  end;
end;

end.

unit TestReviewFindings;

interface

uses
  System.Classes, System.SyncObjs, System.SysUtils,
  DUnitX.TestFramework,
  maxCron;

type
  [TestFixture]
  TTestReviewFindings = class
  public
    [Test]
    procedure Free_FromOwnCallback_ShouldNotDeadlock;

    [Test]
    procedure Free_FromOtherThreadWhileCallbackRunning_ShouldFailFast;

    [Test]
    procedure QueuedMainThread_DeleteBeforeAcquire_ShouldNotAccessFreedEvent;
  end;

implementation

procedure TTestReviewFindings.Free_FromOwnCallback_ShouldNotDeadlock;
var
  lCron: TmaxCron;
  lCronToFree: TmaxCron;
  lEvent: IMaxCronEvent;
  lCallbackEntered: TEvent;
  lCallbackFinished: TEvent;
  lWaitRes: TWaitResult;
  lFreeRaised: Integer;
begin
  lCron := nil;
  lCronToFree := nil;
  lCallbackEntered := TEvent.Create(nil, True, False, '');
  lCallbackFinished := TEvent.Create(nil, True, False, '');
  lFreeRaised := 0;
  try
    lCron := TmaxCron.Create(ctPortable);
    lCronToFree := lCron;

    lEvent := lCron.Add('SelfFreeDeadlock');
    lEvent.EventPlan := '* * * * * * * 0';
    lEvent.InvokeMode := imThread;
    lEvent.OnScheduleProc :=
      procedure(aSender: IMaxCronEvent)
      begin
        lCallbackEntered.SetEvent;
        try
          lCronToFree.Free;
        except
          on Exception do
            TInterlocked.Exchange(lFreeRaised, 1);
        end;
        lCallbackFinished.SetEvent;
      end;
    lEvent.Run;

    lCron.TickAt(lEvent.NextSchedule);

    lWaitRes := lCallbackEntered.WaitFor(2000);
    Assert.AreEqual(TWaitResult.wrSignaled, lWaitRes, 'Callback did not start');

    lWaitRes := lCallbackFinished.WaitFor(1500);
    Assert.AreEqual(TWaitResult.wrSignaled, lWaitRes,
      'Free called from callback should fail fast instead of deadlocking');
    Assert.AreEqual(1, TInterlocked.CompareExchange(lFreeRaised, 0, 0),
      'Expected re-entrant free protection when freeing from own callback');
  finally
    if lCron <> nil then
      lCron.Free;
    lCallbackFinished.Free;
    lCallbackEntered.Free;
  end;
end;

procedure TTestReviewFindings.Free_FromOtherThreadWhileCallbackRunning_ShouldFailFast;
var
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lCallbackEntered: TEvent;
  lCallbackGate: TEvent;
  lFreeDone: TEvent;
  lFreeRaised: Integer;
  lFreeSucceeded: Integer;
  lFreeReturned: Integer;
  lWaitRes: TWaitResult;
  lFreeThread: TThread;
begin
  lCron := nil;
  lFreeThread := nil;
  lCallbackEntered := TEvent.Create(nil, True, False, '');
  lCallbackGate := TEvent.Create(nil, True, False, '');
  lFreeDone := TEvent.Create(nil, True, False, '');
  lFreeRaised := 0;
  lFreeSucceeded := 0;
  lFreeReturned := 0;
  try
    lCron := TmaxCron.Create(ctPortable);

    lEvent := lCron.Add('CrossThreadFree');
    lEvent.EventPlan := '* * * * * * * 1';
    lEvent.InvokeMode := imThread;
    lEvent.OverlapMode := omSerialize;
    lEvent.OnScheduleProc :=
      procedure(aSender: IMaxCronEvent)
      begin
        lCallbackEntered.SetEvent;
        lCallbackGate.WaitFor(3000);
      end;
    lEvent.Run;

    lCron.TickAt(lEvent.NextSchedule);

    lWaitRes := lCallbackEntered.WaitFor(2000);
    Assert.AreEqual(TWaitResult.wrSignaled, lWaitRes, 'Callback did not start');

    lFreeThread := TThread.CreateAnonymousThread(
      procedure
      begin
        try
          lCron.Free;
          TInterlocked.Exchange(lFreeSucceeded, 1);
        except
          on Exception do
            TInterlocked.Exchange(lFreeRaised, 1);
        end;
        TInterlocked.Exchange(lFreeReturned, 1);
        lFreeDone.SetEvent;
      end);
    lFreeThread.FreeOnTerminate := True;
    lFreeThread.Start;

    TThread.Sleep(100);
    lCallbackGate.SetEvent;

    lWaitRes := lFreeDone.WaitFor(3000);
    Assert.AreEqual(TWaitResult.wrSignaled, lWaitRes, 'Free did not return in time');
    Assert.AreEqual(1, TInterlocked.CompareExchange(lFreeRaised, 0, 0),
      'Expected fail-fast re-entrant free protection while callback is active');
  finally
    lCallbackGate.SetEvent;
    lFreeDone.WaitFor(3000);
    if (lCron <> nil) and
      (TInterlocked.CompareExchange(lFreeSucceeded, 0, 0) = 0) and
      (TInterlocked.CompareExchange(lFreeReturned, 0, 0) = 1) then
      lCron.Free;
    lFreeDone.Free;
    lCallbackGate.Free;
    lCallbackEntered.Free;
  end;
end;

procedure TTestReviewFindings.QueuedMainThread_DeleteBeforeAcquire_ShouldNotAccessFreedEvent;
var
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lWorker: TThread;
  lWorkerDone: TEvent;
  lNextAt: TDateTime;
  lWaitRes: TWaitResult;
begin
  lCron := TmaxCron.Create(ctPortable);
  lWorkerDone := TEvent.Create(nil, True, False, '');
  try
    lEvent := lCron.Add('QueuedAcquireRace');
    lEvent.EventPlan := '* * * * * * * 0';
    lEvent.InvokeMode := imMainThread;
    lEvent.OnScheduleProc :=
      procedure(aSender: IMaxCronEvent)
      begin
      end;
    lEvent.Run;
    lNextAt := lEvent.NextSchedule;

    SetMaxCronBeforeQueuedAcquireHook(
      procedure(const aEvent: IMaxCronEvent)
      begin
        if aEvent = lEvent then
          lCron.Delete(lEvent);
      end);

    lWorker := TThread.CreateAnonymousThread(
      procedure
      begin
        lCron.TickAt(lNextAt);
        lWorkerDone.SetEvent;
      end);
    lWorker.FreeOnTerminate := True;
    lWorker.Start;

    lWaitRes := lWorkerDone.WaitFor(2000);
    Assert.AreEqual(TWaitResult.wrSignaled, lWaitRes, 'Worker did not queue callback');
    CheckSynchronize(500);
    Assert.AreEqual(0, lCron.Count);
  finally
    SetMaxCronBeforeQueuedAcquireHook(nil);
    lCron.Free;
    lWorkerDone.Free;
  end;
end;

end.

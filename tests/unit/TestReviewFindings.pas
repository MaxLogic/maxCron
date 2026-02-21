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
    procedure QueuedMainThread_DeleteBeforeAcquire_ShouldNotAccessFreedEvent;
  end;

implementation

procedure TTestReviewFindings.Free_FromOwnCallback_ShouldNotDeadlock;
var
  lCron: TmaxCron;
  lCronToFree: TmaxCron;
  lEvent: TmaxCronEvent;
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
      procedure(aSender: TmaxCronEvent)
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

procedure TTestReviewFindings.QueuedMainThread_DeleteBeforeAcquire_ShouldNotAccessFreedEvent;
var
  lCron: TmaxCron;
  lEvent: TmaxCronEvent;
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
      procedure(aSender: TmaxCronEvent)
      begin
      end;
    lEvent.Run;
    lNextAt := lEvent.NextSchedule;

    SetMaxCronBeforeQueuedAcquireHook(
      procedure(const aEvent: TmaxCronEvent)
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

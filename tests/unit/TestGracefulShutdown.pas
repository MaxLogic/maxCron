unit TestGracefulShutdown;

interface

uses
  System.Classes, System.DateUtils, System.Diagnostics, System.SyncObjs, System.SysUtils,
  DUnitX.TestFramework,
  maxCron;

type
  [TestFixture]
  TTestGracefulShutdown = class
  public
    [Test]
    procedure WaitPolicy_DrainsCallbacksWithinTimeout;

    [Test]
    procedure CancelPolicy_StopsFurtherDispatch;

    [Test]
    procedure ForcePolicy_ReturnsFalseWhenWorkStillRunning;
  end;

implementation

procedure TTestGracefulShutdown.WaitPolicy_DrainsCallbacksWithinTimeout;
var
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lStarted: TEvent;
  lFinished: TEvent;
  lTickAt: TDateTime;
  lShutdownResult: Boolean;
begin
  lCron := TmaxCron.Create(ctPortable);
  lStarted := TEvent.Create(nil, True, False, '');
  lFinished := TEvent.Create(nil, True, False, '');
  try
    lEvent := lCron.Add('ShutdownWait');
    lEvent.EventPlan := '* * * * * * * 0';
    lEvent.InvokeMode := imThread;
    lEvent.OnScheduleProc :=
      procedure(aSender: IMaxCronEvent)
      begin
        lStarted.SetEvent;
        TThread.Sleep(120);
        lFinished.SetEvent;
      end;
    lEvent.Run;

    lTickAt := lEvent.NextSchedule;
    lCron.TickAt(lTickAt);

    Assert.AreEqual(TWaitResult.wrSignaled, lStarted.WaitFor(1500), 'Expected callback to start');

    lShutdownResult := lCron.Shutdown(2000, TmaxCronShutdownPolicy.spWait);
    Assert.IsTrue(lShutdownResult, 'Wait shutdown should drain running callback');
    Assert.AreEqual(TWaitResult.wrSignaled, lFinished.WaitFor(0), 'Callback should be finished after wait shutdown');

    Assert.WillRaise(
      procedure
      begin
        lCron.Add('ShouldFailAfterShutdown');
      end,
      Exception);
  finally
    lFinished.Free;
    lStarted.Free;
    lCron.Free;
  end;
end;

procedure TTestGracefulShutdown.CancelPolicy_StopsFurtherDispatch;
var
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lCount: Integer;
  lFirstTick: TDateTime;
begin
  lCount := 0;
  lCron := TmaxCron.Create(ctPortable);
  try
    lEvent := lCron.Add('ShutdownCancel');
    lEvent.EventPlan := '* * * * * * * 0';
    lEvent.InvokeMode := imMainThread;
    lEvent.OnScheduleProc :=
      procedure(aSender: IMaxCronEvent)
      begin
        Inc(lCount);
      end;
    lEvent.Run;

    lFirstTick := lEvent.NextSchedule;
    lCron.TickAt(lFirstTick);
    Assert.AreEqual(1, lCount, 'Expected callback to fire before shutdown');

    Assert.IsTrue(lCron.Shutdown(1000, TmaxCronShutdownPolicy.spCancel),
      'Cancel shutdown should complete for idle scheduler');

    lCron.TickAt(IncSecond(lFirstTick, 1));
    Assert.AreEqual(1, lCount, 'No callbacks should run after cancel shutdown');
  finally
    lCron.Free;
  end;
end;

procedure TTestGracefulShutdown.ForcePolicy_ReturnsFalseWhenWorkStillRunning;
var
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lStarted: TEvent;
  lRelease: TEvent;
  lFinished: TEvent;
  lTickAt: TDateTime;
  lShutdownResult: Boolean;
  lStopwatch: TStopwatch;
begin
  lCron := TmaxCron.Create(ctPortable);
  lStarted := TEvent.Create(nil, True, False, '');
  lRelease := TEvent.Create(nil, True, False, '');
  lFinished := TEvent.Create(nil, True, False, '');
  try
    lEvent := lCron.Add('ShutdownForce');
    lEvent.EventPlan := '* * * * * * * 0';
    lEvent.InvokeMode := imThread;
    lEvent.OnScheduleProc :=
      procedure(aSender: IMaxCronEvent)
      begin
        lStarted.SetEvent;
        lRelease.WaitFor(5000);
        lFinished.SetEvent;
      end;
    lEvent.Run;

    lTickAt := lEvent.NextSchedule;
    lCron.TickAt(lTickAt);
    Assert.AreEqual(TWaitResult.wrSignaled, lStarted.WaitFor(1500), 'Expected callback to start');

    lStopwatch := TStopwatch.StartNew;
    lShutdownResult := lCron.Shutdown(50, TmaxCronShutdownPolicy.spForce);

    Assert.IsFalse(lShutdownResult, 'Force shutdown should report unfinished work when callback is still running');
    Assert.IsTrue(lStopwatch.ElapsedMilliseconds < 500, 'Force shutdown should return quickly');

    lRelease.SetEvent;
    Assert.AreEqual(TWaitResult.wrSignaled, lFinished.WaitFor(3000), 'Callback should finish after release');
  finally
    lFinished.Free;
    lRelease.Free;
    lStarted.Free;
    lCron.Free;
  end;
end;

end.

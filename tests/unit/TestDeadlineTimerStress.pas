unit TestDeadlineTimerStress;

interface

uses
  System.Classes, System.Diagnostics, System.SyncObjs, System.SysUtils,
  AutoFree, DUnitX.TestFramework,
  maxCron, maxCron.Internal.Platform;

type
  [TestFixture]
  TTestDeadlineTimerStress = class
  public
    [Test] procedure ShutdownAndLifetime;
  end;

implementation

procedure TTestDeadlineTimerStress.ShutdownAndLifetime;
var
  g: TGarbos;
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lEntered, lRelease: TEvent;
  lTicks, lAfter, lSpin, lExceptions: UInt64;
  lStartedUs, lWallUs: Int64;
  lReads, lCallbacks: Integer;
  lWatch: TStopwatch;
begin
  GC(lEntered, TEvent.Create(nil, True, False, ''), g);
  GC(lRelease, TEvent.Create(nil, True, False, ''), g);
  lWallUs := 4000000000000000;
  lCron := nil;
  for var i := 1 to 200 do
  begin
    lReads := 0;
    lCallbacks := 0;
    lEntered.ResetEvent;
    lRelease.ResetEvent;
    // Provider read 1 sees the next pass due. Read 2 is inside DoTick after
    // TimerTimer's shutdown guard, before DoTickAt's guard. Stop does not join it.
    SetMaxCronWallClockHook(function: Int64
      begin
        Result := lWallUs;
        if TThread.CurrentThread.ThreadID <> MainThreadID then
        begin
          Result := lWallUs + 1000000;
          if TInterlocked.Increment(lReads) = 2 then
          begin
            lEntered.SetEvent;
            if lRelease.WaitFor(2000) <> wrSignaled then
              raise Exception.Create('Shutdown fixture release timeout');
          end;
        end;
      end);
    lStartedUs := CronMonotonicNowUs;
    try
      lCron := TmaxCron.Create(ctPortable);
      lEvent := lCron.Add('lifetime', '* * * * * * * 0',
        procedure(aSender: IMaxCronEvent) begin TInterlocked.Increment(lCallbacks); end);
      lEvent.InvokeMode := imThread;
      lEvent.Run;
      lCron.StartTimerForTests(1);
      Assert.AreEqual(wrSignaled, lEntered.WaitFor(2000), 'In-flight tick entered');
      Assert.IsTrue(lCron.Shutdown(2000), 'Shutdown returns while tick is held');
      lCron.GetTimerDiagnosticsForTests(lTicks, lSpin, lExceptions);
      Assert.AreEqual(UInt64(0), lTicks, 'Held tick has not completed');
      lRelease.SetEvent;
      // Synchronize the observation with completion accounting, rather than
      // assuming the non-joining Stop has already accounted for the held tick.
      lWatch := TStopwatch.StartNew;
      repeat
        lCron.GetTimerDiagnosticsForTests(lAfter, lSpin, lExceptions);
        if lAfter = lTicks + 1 then
          Break;
        TThread.Sleep(1);
      until lWatch.ElapsedMilliseconds >= 2000;
      Assert.AreEqual(lTicks + 1, lAfter, 'Exactly the already-entered tick completes');
      lEvent.Stop;
      lEvent.EventPlan := '*/2 * * * * * * 0';
      lEvent.Run;
      lCron.TickAtUs(lWallUs + 10000000);
      TThread.Sleep(1);
      lCron.GetTimerDiagnosticsForTests(lTicks, lSpin, lExceptions);
      Assert.AreEqual(lAfter, lTicks, 'No new ticks after held tick completion');
      Assert.AreEqual(0, TInterlocked.CompareExchange(lCallbacks, 0, 0), 'No callback after shutdown');
      Assert.AreEqual(UInt64(0), lSpin);
      Assert.AreEqual(UInt64(0), lExceptions);
    finally
      lRelease.SetEvent;
      lEvent := nil;
      lCron.Free;
      lCron := nil;
      SetMaxCronWallClockHook(nil);
    end;
    Assert.IsTrue(CronMonotonicNowUs - lStartedUs < 2000000, 'Bounded join');
  end;
  Writeln('R1-02: 200 barrier-held in-flight ticks, completion +1, no new ticks/callbacks, bounded joins');
end;

end.

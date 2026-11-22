unit TestDeadlineTimerStress;

interface

uses
  System.Classes, System.Diagnostics, System.SyncObjs, System.SysUtils,
  AutoFree, DUnitX.TestFramework,
  maxCron, maxCron.Internal.Platform, TestRestartCatchUp;

type
  [TestFixture]
  TTestDeadlineTimerStress = class
  public
    [Test] procedure ShutdownAndLifetime;
    [Test] procedure IntervalLifetime;
    [Test] procedure RestoreBinderBeforePortableDispatch;
  end;

implementation

procedure TTestDeadlineTimerStress.RestoreBinderBeforePortableDispatch;
var
  lCron: TmaxCron;
  lStore: IMaxCronScheduleStore;
  lState: TMaxCronPersistedEvent;
  lFired: TEvent;
  lBound, lUnbound: Integer;
begin
  lStore := TRestartStore.Create;
  lState := Default(TMaxCronPersistedEvent);
  lState.Name := 'portable restore';
  lState.EventPlan := '* * * * * * * 0';
  lState.Enabled := True;
  lState.TimeZoneId := 'UTC';
  lState.Dialect := cdMaxCron;
  lState.InvokeMode := imThread;
  lState.CompletedThrough := CronInstantUsToDateTime(CronPreciseUtcNowUs - 2000000);
  lStore.Save([lState]);
  lFired := TEvent.Create(nil, True, False, '');
  lBound := 0; lUnbound := 0;
  lCron := TmaxCron.Create(ctPortable);
  try
    lCron.ScheduleStore := lStore;
    lCron.StartTimerForTests(1);
    lCron.RestoreScheduleState(True,
      procedure(const aEvent: IMaxCronEvent; const aSaved: TMaxCronPersistedEvent)
      begin
        Assert.IsFalse(aEvent.Enabled, 'binder runs before enabling');
        aEvent.OnScheduleProc := procedure(aSender: IMaxCronEvent)
          begin
            if TInterlocked.CompareExchange(lBound, 0, 0) <> 1 then TInterlocked.Increment(lUnbound);
            lFired.SetEvent;
          end;
        TInterlocked.Exchange(lBound, 1);
      end);
    Assert.IsTrue(lFired.WaitFor(3000) = wrSignaled, 'real portable timer dispatched bound callback');
    Assert.IsTrue(lCron.Shutdown(3000, spWait));
    Assert.AreEqual(0, lUnbound);
  finally
    lCron.Free;
    lFired.Free;
  end;
end;

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

procedure TTestDeadlineTimerStress.IntervalLifetime;
var
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lStart: Int64;
  lSeed: UInt64;
  lTicks,lAfter,lSpin,lExceptions: UInt64;
  lCount: Integer;
begin
  lSeed := 20261115;
  for var i := 1 to 200 do
  begin
    lStart := CronMonotonicNowUs;
    lCron := TmaxCron.Create(ctPortable);
    try
      lEvent := lCron.AddInterval('interval lifetime',1,
        procedure(aSender: IMaxCronEvent) begin end);
      lEvent.InvokeMode := imTTask; lEvent.Run; lCron.StartTimerForTests(1);
      lSeed := (lSeed*1664525+1013904223) and $FFFFFFFF;
      TThread.Sleep(Cardinal(lSeed mod 6));
    finally lEvent := nil; lCron.Free; end;
    Assert.IsTrue(CronMonotonicNowUs-lStart<2000000,'interval lifetime bounded join');
  end;
  lCron := TmaxCron.Create(ctPortable); lCount := 0;
  try
    lEvent := lCron.AddInterval('delete self',1,
      procedure(aSender: IMaxCronEvent)
      begin TInterlocked.Increment(lCount); lCron.Delete(aSender); end,ivFixedDelay);
    lEvent.InvokeMode := imTTask; lEvent.Run; lCron.StartTimerForTests(1);
    TThread.Sleep(50); Assert.IsTrue(lCron.Shutdown(2000,spWait));
    Assert.AreEqual(1,lCount); Assert.AreEqual<NativeInt>(0, Length(lCron.Snapshot));
    Assert.AreEqual<TDateTime>(0,lEvent.NextSchedule);
    lCron.GetTimerDiagnosticsForTests(lTicks,lSpin,lExceptions);
    lEvent.EventPlan := '@every 2ms'; lEvent.Run; lEvent.Enabled := False;
    TThread.Sleep(20); lCron.GetTimerDiagnosticsForTests(lAfter,lSpin,lExceptions);
    Assert.AreEqual<UInt64>(lTicks,lAfter,'no ticks after shutdown');
    Assert.AreEqual<UInt64>(0,lSpin); Assert.AreEqual<UInt64>(0,lExceptions);
  finally lEvent := nil; lCron.Free; end;
end;

end.

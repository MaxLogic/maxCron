unit TestIntervalTiming;
interface
uses
  System.Classes, System.Diagnostics, System.SyncObjs, System.SysUtils,
  Winapi.Windows,
  DUnitX.TestFramework,
  maxCron, maxCron.Internal.Platform;
type
  [TestFixture]
  TTestIntervalTiming = class
  public
    [TestCase('high','high,10')]
    [TestCase('period','period,10')]
    [TestCase('default','default,40')]
    procedure Accuracy(const aResolution: string; const aMedianBound: Integer);
    [Test] procedure TenSecondPooledThread;
    [Test] procedure WakeAndDisable;
    [Test] procedure FixedDelaySpacingAndOverlap;
    [Test] procedure WallJumpsDoNotMoveIntervals;
  end;
implementation
procedure TTestIntervalTiming.Accuracy(const aResolution: string; const aMedianBound: Integer);
var
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lLock: TCriticalSection;
  lStart,lNow,lTemp: Int64;
  lValues: array[0..63] of Int64;
  lCount,lBad,i,j: Integer;
  lOld: string;
  lTicks,lSpin,lExceptions: UInt64;
begin
  lOld := GetEnvironmentVariable('MAXCRON_TIMER_RESOLUTION');
  Winapi.Windows.SetEnvironmentVariable('MAXCRON_TIMER_RESOLUTION',PChar(aResolution));
  lLock := TCriticalSection.Create; lCron := TmaxCron.Create(ctPortable);
  lCount := 0; lBad := 0; lStart := 0;
  try
    lEvent := lCron.AddInterval('accuracy',20,
      procedure(aSender: IMaxCronEvent)
      var lAt: Int64;
      begin
        lAt := CronMonotonicNowUs-lStart;
        lLock.Acquire;
        try
          Inc(lCount);
          if lCount>lAt div 20000+1 then Inc(lBad);
          if lCount<=Length(lValues) then lValues[lCount-1] := lAt mod 20000;
        finally lLock.Release; end;
      end);
    lEvent.InvokeMode := imTTask;
    lStart := CronMonotonicNowUs; lEvent.Run; lCron.StartTimerForTests(1000);
    TThread.Sleep(1000); lEvent.Stop;
    Assert.IsTrue(lCron.Shutdown(5000));
    lNow := CronMonotonicNowUs-lStart;
    Assert.AreEqual(0,lBad,'never early');
    Assert.IsTrue((lCount>=45) and (lCount<=51),'20ms count '+IntToStr(lCount)+' duration '+IntToStr(lNow));
    for i := 0 to lCount-2 do
      for j := i+1 to lCount-1 do
        if lValues[i]>lValues[j] then
        begin lTemp := lValues[i]; lValues[i] := lValues[j]; lValues[j] := lTemp; end;
    Assert.IsTrue(lValues[lCount div 2]<=Int64(aMedianBound)*1000,'phase median');
    lCron.GetTimerDiagnosticsForTests(lTicks,lSpin,lExceptions);
    Assert.AreEqual<UInt64>(0,lSpin); Assert.AreEqual<UInt64>(0,lExceptions);
  finally
    lEvent := nil; lCron.Free; lLock.Free;
    Winapi.Windows.SetEnvironmentVariable('MAXCRON_TIMER_RESOLUTION',PChar(lOld));
  end;
end;

procedure TTestIntervalTiming.TenSecondPooledThread;
var
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lCount: Integer;
  lOld: string;
begin
  lOld := GetEnvironmentVariable('MAXCRON_THREAD_DISPATCH_POOL');
  Winapi.Windows.SetEnvironmentVariable('MAXCRON_THREAD_DISPATCH_POOL','1');
  lCron := TmaxCron.Create(ctPortable); lCount := 0;
  try
    lEvent := lCron.AddInterval('ten seconds',100,
      procedure(aSender: IMaxCronEvent) begin TInterlocked.Increment(lCount); end);
    lEvent.InvokeMode := imThread; lEvent.Run; lCron.StartTimerForTests(1000);
    TThread.Sleep(10000); lEvent.Stop;
    Assert.IsTrue(lCron.Shutdown(5000));
    // Allow 10 missed starts on a loaded host, and two boundary races; never hide early firing.
    Assert.IsTrue((lCount>=90) and (lCount<=102),'100ms/10s count '+IntToStr(lCount));
  finally
    lEvent := nil; lCron.Free;
    Winapi.Windows.SetEnvironmentVariable('MAXCRON_THREAD_DISPATCH_POOL',PChar(lOld));
  end;
end;

procedure TTestIntervalTiming.WakeAndDisable;
var
  lCron: TmaxCron;
  lEvent,lRemoved: IMaxCronEvent;
  lFired: TEvent;
  lAt,lStart,lPhase: Int64;
  lCount,lStopped: Integer;
  lWatch: TStopwatch;
  lTicks,lSpin,lExceptions: UInt64;
begin
  lCron := TmaxCron.Create(ctPortable); lFired := TEvent.Create(nil,True,False,'');
  lAt := 0; lCount := 0;
  try
    lCron.DefaultInvokeMode := imTTask; lCron.StartTimerForTests(1000);
    lWatch := TStopwatch.StartNew;
    repeat
      lPhase := CronPreciseLocalNowUs mod 1000000;
      if (lPhase>=50000) and (lPhase<=100000) then Break;
      TThread.Sleep(1);
    until lWatch.ElapsedMilliseconds>2000;
    Assert.IsTrue(lWatch.ElapsedMilliseconds<=2000,'select cron sleep phase');
    lStart := CronMonotonicNowUs;
    lEvent := lCron.AddInterval('wake',20,
      procedure(aSender: IMaxCronEvent)
      begin lAt := CronMonotonicNowUs; TInterlocked.Increment(lCount); lFired.SetEvent; end);
    lEvent.Run;
    Assert.IsTrue(lFired.WaitFor(200)=wrSignaled,'Add/Run wake');
    Assert.IsTrue((lAt-lStart>=20000) and (lAt-lStart<200000),'first deadline');
    lEvent.Stop; TThread.Sleep(60); lStopped := lCount; TThread.Sleep(60);
    Assert.AreEqual(lStopped,lCount,'stop');
    lEvent.EventPlan := '@every 10s'; lEvent.Run; lFired.ResetEvent;
    lStart := CronMonotonicNowUs; lEvent.EventPlan := '@every 30ms';
    Assert.IsTrue(lFired.WaitFor(200)=wrSignaled,'EventPlan wake');
    Assert.IsTrue(lAt-lStart>=30000,'changed plan never early');
    lEvent.Enabled := False; TThread.Sleep(60); lFired.ResetEvent;
    lStart := CronMonotonicNowUs; lEvent.Enabled := True;
    Assert.IsTrue(lFired.WaitFor(200)=wrSignaled,'Enabled wake');
    Assert.IsTrue(lAt-lStart>=30000,'enable never early');
    lRemoved := lEvent; Assert.IsTrue(lCron.Delete(lEvent));
    TThread.Sleep(90); lStopped := lCount; TThread.Sleep(90);
    Assert.AreEqual(lStopped,lCount,'delete');
    lCron.GetTimerDiagnosticsForTests(lTicks,lSpin,lExceptions);
    Assert.AreEqual<UInt64>(0,lSpin); Assert.AreEqual<UInt64>(0,lExceptions);
  finally
    lRemoved := nil; lEvent := nil; lCron.Free; lFired.Free;
  end;
end;

procedure TTestIntervalTiming.FixedDelaySpacingAndOverlap;
var
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lPreviousEnd,lAt: Int64;
  lCount,lBad,lActive,lMaxActive: Integer;
  lMode: TmaxCronOverlapMode;
begin
  lCron := TmaxCron.Create(ctPortable); lCount := 0; lBad := 0; lPreviousEnd := 0;
  try
    lEvent := lCron.AddInterval('delay',100,
      procedure(aSender: IMaxCronEvent)
      begin
        lAt := CronMonotonicNowUs;
        if (lPreviousEnd<>0) and (lAt-lPreviousEnd<100000) then TInterlocked.Increment(lBad);
        TThread.Sleep(50); lPreviousEnd := CronMonotonicNowUs; TInterlocked.Increment(lCount);
      end,ivFixedDelay);
    lEvent.InvokeMode := imTTask; lEvent.Run; lCron.StartTimerForTests(1000);
    TThread.Sleep(700); lEvent.Stop;
    Assert.IsTrue(lCron.Shutdown(5000)); Assert.AreEqual(0,lBad,'fixed delay spacing');
    Assert.IsTrue((lCount>=3) and (lCount<=5),'delay starts');
  finally lEvent := nil; lCron.Free; end;
  for lMode := omAllowOverlap to omSkipIfRunning do
  begin
    lCron := TmaxCron.Create(ctPortable); lActive := 0; lMaxActive := 0; lCount := 0;
    try
      lEvent := lCron.AddInterval('overlap',100,
        procedure(aSender: IMaxCronEvent)
        var lNowActive,lWas: Integer;
        begin
          lNowActive := TInterlocked.Increment(lActive);
          repeat
            lWas := TInterlocked.CompareExchange(lMaxActive,0,0);
            if lWas>=lNowActive then Break;
          until TInterlocked.CompareExchange(lMaxActive,lNowActive,lWas)=lWas;
          TThread.Sleep(250); TInterlocked.Increment(lCount); TInterlocked.Decrement(lActive);
        end);
      lEvent.InvokeMode := imTTask; lEvent.OverlapMode := lMode; lEvent.Run; lCron.StartTimerForTests(1000);
      TThread.Sleep(1000); lEvent.Stop;
      // Shutdown(spWait) covers currently executing callbacks; Free also drains reserved starts.
      lCron.Shutdown(5000);
    finally lEvent := nil; lCron.Free; end;
    if lMode=omAllowOverlap then Assert.IsTrue(lMaxActive>=2,'allow overlap')
    else Assert.AreEqual(1,lMaxActive,'skip overlap');
  end;
end;

procedure TTestIntervalTiming.WallJumpsDoNotMoveIntervals;
var
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lOffset: Int64;
  lCount: Integer;
begin
  lOffset := 0; lCount := 0;
  SetMaxCronWallClockHook(function: Int64 begin Result := CronPreciseLocalNowUs+TInterlocked.Read(lOffset); end);
  lCron := TmaxCron.Create(ctPortable);
  try
    lEvent := lCron.AddInterval('wall jump',50,
      procedure(aSender: IMaxCronEvent) begin TInterlocked.Increment(lCount); end);
    lEvent.InvokeMode := imTTask; lEvent.Run; lCron.StartTimerForTests(1000);
    TThread.Sleep(350); TInterlocked.Exchange(lOffset,3600000000);
    TThread.Sleep(350); TInterlocked.Exchange(lOffset,-3600000000);
    TThread.Sleep(300); lEvent.Stop; lCron.Shutdown(5000);
    Assert.IsTrue((lCount>=18) and (lCount<=21),'wall jump count '+IntToStr(lCount));
  finally
    lEvent := nil; lCron.Free; SetMaxCronWallClockHook(nil);
  end;
end;
end.

unit TestGlobalLimits;

interface

uses
  System.Classes, System.DateUtils, System.Diagnostics, System.SyncObjs, System.SysUtils,
  DUnitX.TestFramework,
  maxCron;

type
  [TestFixture]
  TTestGlobalLimits = class
  public
    [Test]
    procedure ConcurrencyCap_EnforcedUnderBurst;

    [Test]
    procedure DispatchRateCap_EnforcedUnderBurst;
  end;

implementation

procedure TTestGlobalLimits.ConcurrencyCap_EnforcedUnderBurst;
const
  cEventCount = 12;
var
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lRelease: TEvent;
  lTwoActive: TEvent;
  lAllDone: TEvent;
  lActive: Integer;
  lMaxActive: Integer;
  lDone: Integer;
  lCurrent: Integer;
  lPreviousMax: Integer;
  lIndex: Integer;
  lTickAt: TDateTime;
begin
  lActive := 0;
  lMaxActive := 0;
  lDone := 0;
  lTickAt := Now;

  lCron := TmaxCron.Create(ctPortable);
  lRelease := TEvent.Create(nil, True, False, '');
  lTwoActive := TEvent.Create(nil, True, False, '');
  lAllDone := TEvent.Create(nil, True, False, '');
  try
    lCron.GlobalMaxConcurrentCallbacks := 2;
    lCron.GlobalMaxDispatchPerSecond := 0;

    for lIndex := 0 to cEventCount - 1 do
    begin
      lEvent := lCron.Add('GlobalConcurrency_' + IntToStr(lIndex));
      lEvent.EventPlan := '* * * * * * * 0';
      lEvent.InvokeMode := imThread;
      lEvent.OnScheduleProc :=
        procedure(aSender: IMaxCronEvent)
        begin
          lCurrent := TInterlocked.Increment(lActive);
          while True do
          begin
            lPreviousMax := TInterlocked.CompareExchange(lMaxActive, 0, 0);
            if lCurrent <= lPreviousMax then
              Break;
            if TInterlocked.CompareExchange(lMaxActive, lCurrent, lPreviousMax) = lPreviousMax then
              Break;
          end;

          if lCurrent >= 2 then
            lTwoActive.SetEvent;

          lRelease.WaitFor(5000);

          TInterlocked.Decrement(lActive);
          if TInterlocked.Increment(lDone) = cEventCount then
            lAllDone.SetEvent;
        end;
      lEvent.Run;
      if lIndex = 0 then
        lTickAt := lEvent.NextSchedule;
    end;

    lCron.TickAt(lTickAt);

    Assert.AreEqual(TWaitResult.wrSignaled, lTwoActive.WaitFor(2000),
      'Expected at least two callbacks to start');
    TThread.Sleep(100);
    Assert.IsTrue(TInterlocked.CompareExchange(lMaxActive, 0, 0) <= 2,
      'Global concurrency cap should keep active callbacks <= 2');

    lRelease.SetEvent;
    Assert.AreEqual(TWaitResult.wrSignaled, lAllDone.WaitFor(6000),
      'All callbacks should complete after release');
  finally
    lAllDone.Free;
    lTwoActive.Free;
    lRelease.Free;
    lCron.Free;
  end;
end;

procedure TTestGlobalLimits.DispatchRateCap_EnforcedUnderBurst;
const
  cEventCount = 15;
  cRateLimit = 5;
var
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lAllDone: TEvent;
  lTickAt: TDateTime;
  lDone: Integer;
  lFirstStartMs: Int64;
  lLastStartMs: Int64;
  lLock: TCriticalSection;
  lStopwatch: TStopwatch;
  lStartMs: Int64;
  lIndex: Integer;
begin
  lDone := 0;
  lFirstStartMs := -1;
  lLastStartMs := -1;
  lTickAt := Now;

  lCron := TmaxCron.Create(ctPortable);
  lAllDone := TEvent.Create(nil, True, False, '');
  lLock := TCriticalSection.Create;
  try
    lCron.GlobalMaxConcurrentCallbacks := 0;
    lCron.GlobalMaxDispatchPerSecond := cRateLimit;

    for lIndex := 0 to cEventCount - 1 do
    begin
      lEvent := lCron.Add('GlobalRate_' + IntToStr(lIndex));
      lEvent.EventPlan := '* * * * * * * 0';
      lEvent.InvokeMode := imThread;
      lEvent.OnScheduleProc :=
        procedure(aSender: IMaxCronEvent)
        begin
          lStartMs := lStopwatch.ElapsedMilliseconds;
          lLock.Acquire;
          try
            if (lFirstStartMs < 0) or (lStartMs < lFirstStartMs) then
              lFirstStartMs := lStartMs;
            if lStartMs > lLastStartMs then
              lLastStartMs := lStartMs;
          finally
            lLock.Release;
          end;

          if TInterlocked.Increment(lDone) = cEventCount then
            lAllDone.SetEvent;
        end;
      lEvent.Run;
      if lIndex = 0 then
        lTickAt := lEvent.NextSchedule;
    end;

    lStopwatch := TStopwatch.StartNew;
    lCron.TickAt(lTickAt);

    Assert.AreEqual(TWaitResult.wrSignaled, lAllDone.WaitFor(10000),
      'Expected all callbacks to complete under global rate cap');

    Assert.IsTrue((lFirstStartMs >= 0) and (lLastStartMs >= lFirstStartMs),
      'Expected callback start timestamps to be collected');
    Assert.IsTrue((lLastStartMs - lFirstStartMs) >= 1800,
      'Rate-cap enforcement should spread callback starts across multiple seconds');
  finally
    lLock.Free;
    lAllDone.Free;
    lCron.Free;
  end;
end;

end.

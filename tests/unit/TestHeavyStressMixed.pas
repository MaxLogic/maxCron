unit TestHeavyStressMixed;

interface

uses
  System.Classes, System.DateUtils, System.Diagnostics, System.SyncObjs, System.SysUtils,
  Winapi.Windows,
  DUnitX.TestFramework,
  maxCron;

type
  [TestFixture]
  TTestHeavyStressMixed = class
  private
    procedure SetError(const aLock: TCriticalSection; var aErrorText: string;
      const aWhere, aText: string);
    procedure SetEnvVar(const aName, aValue: string; out aPreviousValue: string; out aHadPrevious: Boolean);
    procedure RestoreEnvVar(const aName, aPreviousValue: string; const aHadPrevious: Boolean);
    procedure SetEngineEnv(const aValue: string; out aPreviousValue: string; out aHadPrevious: Boolean);
    procedure RestoreEngineEnv(const aPreviousValue: string; const aHadPrevious: Boolean);
    procedure RunBenchmarkScenario(const aEngine: string; const aEventCount, aTickCount: Integer;
      const aPlan: string; out aVisited: UInt64; out aRebuilds: UInt64; out aElapsedMs: Int64);
  public
    [Test]
    procedure ManyMixedEvents_ManyTicks_30s;

    [Test]
    procedure EngineBenchmark_ScanVsHeap_HighN;

    [Test]
    procedure EngineAutoMode_HysteresisAndOverrideBehavior;

    [Test]
    procedure EngineAutoMode_CustomThresholds_AreApplied;

    [Test]
    procedure EngineAutoMode_OscillationBackoff_BoundsSwitchRate;

    [Test]
    procedure EngineAutoMode_ConcurrentSwitching_NoMissedDue;
  end;

implementation

procedure TTestHeavyStressMixed.SetError(const aLock: TCriticalSection; var aErrorText: string;
  const aWhere, aText: string);
begin
  aLock.Acquire;
  try
    if aErrorText = '' then
      aErrorText := aWhere + ': ' + aText;
  finally
    aLock.Release;
  end;
end;

procedure TTestHeavyStressMixed.SetEnvVar(const aName, aValue: string; out aPreviousValue: string;
  out aHadPrevious: Boolean);
begin
  aPreviousValue := GetEnvironmentVariable(aName);
  aHadPrevious := aPreviousValue <> '';
  Winapi.Windows.SetEnvironmentVariable(PChar(aName), PChar(aValue));
end;

procedure TTestHeavyStressMixed.RestoreEnvVar(const aName, aPreviousValue: string; const aHadPrevious: Boolean);
begin
  if aHadPrevious then
    Winapi.Windows.SetEnvironmentVariable(PChar(aName), PChar(aPreviousValue))
  else
    Winapi.Windows.SetEnvironmentVariable(PChar(aName), nil);
end;

procedure TTestHeavyStressMixed.SetEngineEnv(const aValue: string; out aPreviousValue: string;
  out aHadPrevious: Boolean);
begin
  SetEnvVar('MAXCRON_ENGINE', aValue, aPreviousValue, aHadPrevious);
end;

procedure TTestHeavyStressMixed.RestoreEngineEnv(const aPreviousValue: string; const aHadPrevious: Boolean);
begin
  RestoreEnvVar('MAXCRON_ENGINE', aPreviousValue, aHadPrevious);
end;

procedure TTestHeavyStressMixed.RunBenchmarkScenario(const aEngine: string; const aEventCount, aTickCount: Integer;
  const aPlan: string; out aVisited: UInt64; out aRebuilds: UInt64; out aElapsedMs: Int64);
var
  lPreviousValue: string;
  lHadPrevious: Boolean;
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lNowDateTime: TDateTime;
  lStopwatch: TStopwatch;
  lIndex: Integer;
begin
  SetEngineEnv(aEngine, lPreviousValue, lHadPrevious);
  try
    lCron := TmaxCron.Create(ctPortable);
    try
      for lIndex := 0 to aEventCount - 1 do
      begin
        lEvent := lCron.Add('Bench_' + aEngine + '_' + IntToStr(lIndex));
        lEvent.EventPlan := aPlan;
        lEvent.Run;
      end;

      lCron.ResetTickMetricsForTests;
      lNowDateTime := Now;
      lStopwatch := TStopwatch.StartNew;
      for lIndex := 0 to aTickCount - 1 do
        lCron.TickAt(lNowDateTime);
      aElapsedMs := lStopwatch.ElapsedMilliseconds;
      lCron.GetTickMetricsForTests(aVisited, aRebuilds);
    finally
      lCron.Free;
    end;
  finally
    RestoreEngineEnv(lPreviousValue, lHadPrevious);
  end;
end;

procedure TTestHeavyStressMixed.ManyMixedEvents_ManyTicks_30s;
const
  cThreadCount = 4;
  cEventCount = 96;
  cDurationMs = 30000;
var
  lCron: TmaxCron;
  lErrorLock: TCriticalSection;
  lErrorText: string;
  lFireCount: Integer;
  lThreads: array [0 .. cThreadCount - 1] of TThread;
  lStarted: array [0 .. cThreadCount - 1] of TEvent;
  lIndex: Integer;
  lEndStamp: Int64;
  lEvent: IMaxCronEvent;
  lTomorrow: TDateTime;

  function BuildExcludedCsv: string;
  begin
    Result := FormatDateTime('yyyy"-"mm"-"dd', lTomorrow);
  end;

  function MakeWorker(const aIndex: Integer): TThread;
  begin
    Result := TThread.CreateAnonymousThread(
      procedure
      var
        lLocalTick: Integer;
        lNowDateTime: TDateTime;
        lNowStamp: Int64;
      begin
        lLocalTick := 0;
        lStarted[aIndex].SetEvent;
        while True do
        begin
          lNowStamp := TStopwatch.GetTimeStamp;
          if lNowStamp >= lEndStamp then
            Break;

          try
            lNowDateTime := Now;
            lCron.TickAt(lNowDateTime);
            if (lLocalTick mod 20) = 0 then
              lCron.TickAt(IncSecond(lNowDateTime, 5));
          except
            on E: Exception do
            begin
              SetError(lErrorLock, lErrorText, 'TickAt', E.ClassName + ': ' + E.Message);
              Exit;
            end;
          end;

          Inc(lLocalTick);
          if (lLocalTick and $0F) = 0 then
            TThread.Yield;
          TThread.Sleep(10);
        end;
      end
      );
    Result.FreeOnTerminate := False;
  end;

begin
  lFireCount := 0;
  lErrorText := '';
  lTomorrow := IncDay(Date, 1);
  lErrorLock := TCriticalSection.Create;
  try
    lCron := TmaxCron.Create(ctPortable);
    try
      lCron.DefaultMisfireCatchUpLimit := 2;

      for lIndex := 0 to cEventCount - 1 do
      begin
        lEvent := lCron.Add('Mixed' + IntToStr(lIndex));

        if (lIndex mod 6) = 5 then
          lEvent.EventPlan := '* * * * * * H/10 0'
        else
          lEvent.EventPlan := '* * * * * * * 0';

        lEvent.Tag := lIndex;
        lEvent.InvokeMode := imThread;

        case (lIndex mod 4) of
          0:
            lEvent.OverlapMode := omSerializeCoalesce;
          1:
            lEvent.OverlapMode := omSerialize;
          2:
            lEvent.OverlapMode := omSkipIfRunning;
        else
          lEvent.OverlapMode := omAllowOverlap;
        end;

        case (lIndex mod 6) of
          0:
            lEvent.TimeZoneId := 'UTC';
          1:
            lEvent.TimeZoneId := 'UTC+02:00';
          2:
            lEvent.ExcludedDatesCsv := BuildExcludedCsv;
          3:
            begin
              lEvent.BlackoutStartTime := EncodeTime(12, 0, 0, 0);
              lEvent.BlackoutEndTime := EncodeTime(12, 0, 0, 0);
            end;
          4:
            lEvent.WeekdaysOnly := True;
        end;

        case (lIndex mod 3) of
          0:
            lEvent.MisfirePolicy := mpSkip;
          1:
            lEvent.MisfirePolicy := mpFireOnceNow;
        else
          lEvent.MisfirePolicy := mpCatchUpAll;
        end;

        lEvent.OnScheduleProc :=
          procedure(aSender: IMaxCronEvent)
          begin
            try
              TInterlocked.Increment(lFireCount);
              if (aSender.Tag mod 11) = 0 then
                TThread.Sleep(2);
            except
              on E: Exception do
                SetError(lErrorLock, lErrorText, 'Callback', E.ClassName + ': ' + E.Message);
            end;
          end;

        lEvent.ValidFrom := IncSecond(Now, -1);
        lEvent.Run;
      end;

      for lIndex := 0 to cThreadCount - 1 do
        lStarted[lIndex] := TEvent.Create(nil, True, False, '');
      try
        lEndStamp := TStopwatch.GetTimeStamp + (Int64(cDurationMs) * TStopwatch.Frequency) div 1000;
        for lIndex := 0 to cThreadCount - 1 do
        begin
          lThreads[lIndex] := MakeWorker(lIndex);
          lThreads[lIndex].Start;
        end;

        for lIndex := 0 to cThreadCount - 1 do
          Assert.AreEqual(TWaitResult.wrSignaled, lStarted[lIndex].WaitFor(3000), 'Worker did not start');

        for lIndex := 0 to cThreadCount - 1 do
          lThreads[lIndex].WaitFor;

        lErrorLock.Acquire;
        try
          if lErrorText <> '' then
            Assert.Fail(lErrorText);
        finally
          lErrorLock.Release;
        end;

        Assert.IsTrue(TInterlocked.CompareExchange(lFireCount, 0, 0) > 0, 'Expected at least one callback');
      finally
        for lIndex := 0 to cThreadCount - 1 do
          lStarted[lIndex].Free;
        for lIndex := 0 to cThreadCount - 1 do
          lThreads[lIndex].Free;
      end;
    finally
      lCron.Free;
    end;
  finally
    lErrorLock.Free;
  end;
end;

procedure TTestHeavyStressMixed.EngineBenchmark_ScanVsHeap_HighN;
const
  cEventCount = 1200;
  cTickCount = 40;
  cPlan = '0 0 1 1 * 2099 0 1';
var
  lScanVisited: UInt64;
  lScanRebuilds: UInt64;
  lScanElapsedMs: Int64;
  lHeapVisited: UInt64;
  lHeapRebuilds: UInt64;
  lHeapElapsedMs: Int64;
begin
  RunBenchmarkScenario('scan', cEventCount, cTickCount, cPlan, lScanVisited, lScanRebuilds, lScanElapsedMs);
  RunBenchmarkScenario('heap', cEventCount, cTickCount, cPlan, lHeapVisited, lHeapRebuilds, lHeapElapsedMs);

  Writeln(Format('Benchmark scan: visited=%d rebuilds=%d elapsedMs=%d',
    [lScanVisited, lScanRebuilds, lScanElapsedMs]));
  Writeln(Format('Benchmark heap: visited=%d rebuilds=%d elapsedMs=%d',
    [lHeapVisited, lHeapRebuilds, lHeapElapsedMs]));

  Assert.IsTrue(lScanVisited > 0, 'Scan benchmark should visit candidates');
  Assert.IsTrue(lHeapVisited > 0, 'Heap benchmark should visit candidates');
  Assert.IsTrue(lHeapVisited * 5 < lScanVisited,
    'Heap mode should reduce candidate work for high-N non-due ticks');
end;

procedure TTestHeavyStressMixed.EngineAutoMode_HysteresisAndOverrideBehavior;
const
  cEventCount = 500;
  cAutoWarmupTicks = 96;
  cAutoChurnTicks = 18;
  cFuturePlan = '0 0 1 1 * 2099 0 1';
var
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lIndex: Integer;
  lNowDateTime: TDateTime;
  lConfiguredEngine: string;
  lEffectiveEngine: string;
  lAutoState: string;
  lSwitchCount: UInt64;
  lPreviousValue: string;
  lHadPrevious: Boolean;
begin
  SetEngineEnv('auto', lPreviousValue, lHadPrevious);
  try
    lCron := TmaxCron.Create(ctPortable);
    try
      for lIndex := 0 to cEventCount - 1 do
      begin
        lEvent := lCron.Add('AutoBench_' + IntToStr(lIndex));
        lEvent.EventPlan := cFuturePlan;
        lEvent.Run;
      end;

      lNowDateTime := Now;
      for lIndex := 0 to cAutoWarmupTicks - 1 do
        lCron.TickAt(lNowDateTime);

      lCron.GetEngineStateForTests(lConfiguredEngine, lEffectiveEngine, lAutoState, lSwitchCount);
      Assert.AreEqual('auto', lConfiguredEngine);
      Assert.AreEqual('heap', lEffectiveEngine, 'Auto mode should promote to heap under high-N low-churn load');
      Assert.IsTrue(lSwitchCount > 0, 'Auto mode should record at least one engine switch');

      lEvent := lCron.Add('AutoChurn');
      lEvent.EventPlan := cFuturePlan;
      lEvent.Run;
      for lIndex := 0 to cAutoChurnTicks - 1 do
      begin
        lEvent.Stop;
        lEvent.Run;
        lCron.TickAt(lNowDateTime);
      end;

      lCron.GetEngineStateForTests(lConfiguredEngine, lEffectiveEngine, lAutoState, lSwitchCount);
      Assert.AreEqual('auto', lConfiguredEngine);
      Assert.AreEqual('scan', lEffectiveEngine, 'High churn should force auto mode back to scan');
      Assert.AreEqual('scan-stable', lAutoState);
    finally
      lCron.Free;
    end;
  finally
    RestoreEngineEnv(lPreviousValue, lHadPrevious);
  end;

  SetEngineEnv('heap', lPreviousValue, lHadPrevious);
  try
    lCron := TmaxCron.Create(ctPortable);
    try
      lCron.GetEngineStateForTests(lConfiguredEngine, lEffectiveEngine, lAutoState, lSwitchCount);
      Assert.AreEqual('heap', lConfiguredEngine);
      Assert.AreEqual('heap', lEffectiveEngine);
      Assert.AreEqual('disabled', lAutoState);
      Assert.AreEqual(UInt64(0), lSwitchCount);
    finally
      lCron.Free;
    end;
  finally
    RestoreEngineEnv(lPreviousValue, lHadPrevious);
  end;
end;

procedure TTestHeavyStressMixed.EngineAutoMode_CustomThresholds_AreApplied;
const
  cEventCount = 500;
  cTickCount = 64;
  cFuturePlan = '0 0 1 1 * 2099 0 1';
var
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lIndex: Integer;
  lNowDateTime: TDateTime;
  lConfiguredEngine: string;
  lEffectiveEngine: string;
  lAutoState: string;
  lSwitchCount: UInt64;
  lPreviousEngineValue: string;
  lPreviousEnterEventsValue: string;
  lPreviousExitEventsValue: string;
  lPreviousTrialTicksValue: string;
  lPreviousPromoteRatioValue: string;
  lPreviousDemoteRatioValue: string;
  lPreviousCooldownValue: string;
  lHadEngineValue: Boolean;
  lHadEnterEventsValue: Boolean;
  lHadExitEventsValue: Boolean;
  lHadTrialTicksValue: Boolean;
  lHadPromoteRatioValue: Boolean;
  lHadDemoteRatioValue: Boolean;
  lHadCooldownValue: Boolean;
begin
  SetEnvVar('MAXCRON_ENGINE', 'auto', lPreviousEngineValue, lHadEngineValue);
  SetEnvVar('MAXCRON_AUTO_ENTER_EVENTS', '900', lPreviousEnterEventsValue, lHadEnterEventsValue);
  SetEnvVar('MAXCRON_AUTO_EXIT_EVENTS', '850', lPreviousExitEventsValue, lHadExitEventsValue);
  try
    lCron := TmaxCron.Create(ctPortable);
    try
      for lIndex := 0 to cEventCount - 1 do
      begin
        lEvent := lCron.Add('AutoCustomHigh_' + IntToStr(lIndex));
        lEvent.EventPlan := cFuturePlan;
        lEvent.Run;
      end;

      lNowDateTime := Now;
      for lIndex := 0 to cTickCount - 1 do
        lCron.TickAt(lNowDateTime);

      lCron.GetEngineStateForTests(lConfiguredEngine, lEffectiveEngine, lAutoState, lSwitchCount);
      Assert.AreEqual('auto', lConfiguredEngine);
      Assert.AreEqual('scan', lEffectiveEngine, 'Raised enter threshold should keep auto mode on scan');
      Assert.AreEqual(UInt64(0), lSwitchCount, 'Raised enter threshold should prevent switches');
    finally
      lCron.Free;
    end;
  finally
    RestoreEnvVar('MAXCRON_AUTO_EXIT_EVENTS', lPreviousExitEventsValue, lHadExitEventsValue);
    RestoreEnvVar('MAXCRON_AUTO_ENTER_EVENTS', lPreviousEnterEventsValue, lHadEnterEventsValue);
    RestoreEnvVar('MAXCRON_ENGINE', lPreviousEngineValue, lHadEngineValue);
  end;

  SetEnvVar('MAXCRON_ENGINE', 'auto', lPreviousEngineValue, lHadEngineValue);
  SetEnvVar('MAXCRON_AUTO_ENTER_EVENTS', '64', lPreviousEnterEventsValue, lHadEnterEventsValue);
  SetEnvVar('MAXCRON_AUTO_EXIT_EVENTS', '32', lPreviousExitEventsValue, lHadExitEventsValue);
  SetEnvVar('MAXCRON_AUTO_TRIAL_TICKS', '4', lPreviousTrialTicksValue, lHadTrialTicksValue);
  SetEnvVar('MAXCRON_AUTO_PROMOTE_RATIO', '1.25', lPreviousPromoteRatioValue, lHadPromoteRatioValue);
  SetEnvVar('MAXCRON_AUTO_DEMOTE_RATIO', '1.40', lPreviousDemoteRatioValue, lHadDemoteRatioValue);
  SetEnvVar('MAXCRON_AUTO_COOLDOWN', '2', lPreviousCooldownValue, lHadCooldownValue);
  try
    lCron := TmaxCron.Create(ctPortable);
    try
      for lIndex := 0 to cEventCount - 1 do
      begin
        lEvent := lCron.Add('AutoCustomLow_' + IntToStr(lIndex));
        lEvent.EventPlan := cFuturePlan;
        lEvent.Run;
      end;

      lNowDateTime := Now;
      for lIndex := 0 to cTickCount - 1 do
        lCron.TickAt(lNowDateTime);

      lCron.GetEngineStateForTests(lConfiguredEngine, lEffectiveEngine, lAutoState, lSwitchCount);
      Assert.AreEqual('auto', lConfiguredEngine);
      Assert.AreEqual('heap', lEffectiveEngine, 'Lower enter threshold should promote to heap');
      Assert.IsTrue(lSwitchCount > 0, 'Custom thresholds should change switching behavior');
    finally
      lCron.Free;
    end;
  finally
    RestoreEnvVar('MAXCRON_AUTO_COOLDOWN', lPreviousCooldownValue, lHadCooldownValue);
    RestoreEnvVar('MAXCRON_AUTO_DEMOTE_RATIO', lPreviousDemoteRatioValue, lHadDemoteRatioValue);
    RestoreEnvVar('MAXCRON_AUTO_PROMOTE_RATIO', lPreviousPromoteRatioValue, lHadPromoteRatioValue);
    RestoreEnvVar('MAXCRON_AUTO_TRIAL_TICKS', lPreviousTrialTicksValue, lHadTrialTicksValue);
    RestoreEnvVar('MAXCRON_AUTO_EXIT_EVENTS', lPreviousExitEventsValue, lHadExitEventsValue);
    RestoreEnvVar('MAXCRON_AUTO_ENTER_EVENTS', lPreviousEnterEventsValue, lHadEnterEventsValue);
    RestoreEnvVar('MAXCRON_ENGINE', lPreviousEngineValue, lHadEngineValue);
  end;
end;

procedure TTestHeavyStressMixed.EngineAutoMode_OscillationBackoff_BoundsSwitchRate;
const
  cEventCount = 420;
  cWarmupTicks = 24;
  cOscillationTicks = 96;
  cFuturePlan = '0 0 1 1 * 2099 0 1';
var
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lChurnEvent: IMaxCronEvent;
  lIndex: Integer;
  lNowDateTime: TDateTime;
  lConfiguredEngine: string;
  lEffectiveEngine: string;
  lAutoState: string;
  lSwitchCount: UInt64;
  lPreviousEngineValue: string;
  lPreviousEnterEventsValue: string;
  lPreviousExitEventsValue: string;
  lPreviousEnterDirtyValue: string;
  lPreviousExitDirtyValue: string;
  lPreviousEnterHoldValue: string;
  lPreviousExitHoldValue: string;
  lPreviousTrialTicksValue: string;
  lPreviousCooldownValue: string;
  lPreviousPromoteRatioValue: string;
  lPreviousDemoteRatioValue: string;
  lHadEngineValue: Boolean;
  lHadEnterEventsValue: Boolean;
  lHadExitEventsValue: Boolean;
  lHadEnterDirtyValue: Boolean;
  lHadExitDirtyValue: Boolean;
  lHadEnterHoldValue: Boolean;
  lHadExitHoldValue: Boolean;
  lHadTrialTicksValue: Boolean;
  lHadCooldownValue: Boolean;
  lHadPromoteRatioValue: Boolean;
  lHadDemoteRatioValue: Boolean;
begin
  SetEnvVar('MAXCRON_ENGINE', 'auto', lPreviousEngineValue, lHadEngineValue);
  SetEnvVar('MAXCRON_AUTO_ENTER_EVENTS', '128', lPreviousEnterEventsValue, lHadEnterEventsValue);
  SetEnvVar('MAXCRON_AUTO_EXIT_EVENTS', '96', lPreviousExitEventsValue, lHadExitEventsValue);
  SetEnvVar('MAXCRON_AUTO_ENTER_DIRTY', '0.10', lPreviousEnterDirtyValue, lHadEnterDirtyValue);
  SetEnvVar('MAXCRON_AUTO_EXIT_DIRTY', '0.15', lPreviousExitDirtyValue, lHadExitDirtyValue);
  SetEnvVar('MAXCRON_AUTO_ENTER_HOLD', '1', lPreviousEnterHoldValue, lHadEnterHoldValue);
  SetEnvVar('MAXCRON_AUTO_EXIT_HOLD', '1', lPreviousExitHoldValue, lHadExitHoldValue);
  SetEnvVar('MAXCRON_AUTO_TRIAL_TICKS', '1', lPreviousTrialTicksValue, lHadTrialTicksValue);
  SetEnvVar('MAXCRON_AUTO_COOLDOWN', '1', lPreviousCooldownValue, lHadCooldownValue);
  SetEnvVar('MAXCRON_AUTO_PROMOTE_RATIO', '1.40', lPreviousPromoteRatioValue, lHadPromoteRatioValue);
  SetEnvVar('MAXCRON_AUTO_DEMOTE_RATIO', '1.60', lPreviousDemoteRatioValue, lHadDemoteRatioValue);
  try
    lCron := TmaxCron.Create(ctPortable);
    try
      for lIndex := 0 to cEventCount - 1 do
      begin
        lEvent := lCron.Add('AutoBackoff_' + IntToStr(lIndex));
        lEvent.EventPlan := cFuturePlan;
        lEvent.Run;
      end;

      lChurnEvent := lCron.Add('AutoBackoffChurn');
      lChurnEvent.EventPlan := cFuturePlan;
      lChurnEvent.Run;

      lNowDateTime := Now;
      for lIndex := 0 to cWarmupTicks - 1 do
        lCron.TickAt(lNowDateTime);

      for lIndex := 0 to cOscillationTicks - 1 do
      begin
        if (lIndex and 1) = 1 then
        begin
          lChurnEvent.Stop;
          lChurnEvent.Run;
        end;
        lCron.TickAt(lNowDateTime);
      end;

      lCron.GetEngineStateForTests(lConfiguredEngine, lEffectiveEngine, lAutoState, lSwitchCount);
      Assert.AreEqual('auto', lConfiguredEngine);
      Assert.IsTrue((lEffectiveEngine = 'scan') or (lEffectiveEngine = 'heap'),
        'Auto mode should keep effective engine in scan/heap set');
      Assert.IsTrue(lAutoState <> 'disabled', 'Auto mode state should stay active');
      Assert.IsTrue(lSwitchCount > 0, 'Forced churn oscillation should still switch at least once');
      Assert.IsTrue(lSwitchCount <= 36,
        Format('Adaptive backoff should cap switch bursts (observed switches=%d)', [Int64(lSwitchCount)]));
    finally
      lCron.Free;
    end;
  finally
    RestoreEnvVar('MAXCRON_AUTO_DEMOTE_RATIO', lPreviousDemoteRatioValue, lHadDemoteRatioValue);
    RestoreEnvVar('MAXCRON_AUTO_PROMOTE_RATIO', lPreviousPromoteRatioValue, lHadPromoteRatioValue);
    RestoreEnvVar('MAXCRON_AUTO_COOLDOWN', lPreviousCooldownValue, lHadCooldownValue);
    RestoreEnvVar('MAXCRON_AUTO_TRIAL_TICKS', lPreviousTrialTicksValue, lHadTrialTicksValue);
    RestoreEnvVar('MAXCRON_AUTO_EXIT_HOLD', lPreviousExitHoldValue, lHadExitHoldValue);
    RestoreEnvVar('MAXCRON_AUTO_ENTER_HOLD', lPreviousEnterHoldValue, lHadEnterHoldValue);
    RestoreEnvVar('MAXCRON_AUTO_EXIT_DIRTY', lPreviousExitDirtyValue, lHadExitDirtyValue);
    RestoreEnvVar('MAXCRON_AUTO_ENTER_DIRTY', lPreviousEnterDirtyValue, lHadEnterDirtyValue);
    RestoreEnvVar('MAXCRON_AUTO_EXIT_EVENTS', lPreviousExitEventsValue, lHadExitEventsValue);
    RestoreEnvVar('MAXCRON_AUTO_ENTER_EVENTS', lPreviousEnterEventsValue, lHadEnterEventsValue);
    RestoreEnvVar('MAXCRON_ENGINE', lPreviousEngineValue, lHadEngineValue);
  end;
end;

procedure TTestHeavyStressMixed.EngineAutoMode_ConcurrentSwitching_NoMissedDue;
const
  cThreadCount = 4;
  cEventCount = 450;
  cTotalTicks = 96;
  cChurnStartTick = 28;
  cChurnEndTick = 64;
  cFuturePlan = '0 0 1 1 * 2099 0 1';
var
  lCron: TmaxCron;
  lDueEvent: IMaxCronEvent;
  lChurnEvent: IMaxCronEvent;
  lEvent: IMaxCronEvent;
  lThreads: array [0 .. cThreadCount - 1] of TThread;
  lThreadReady: array [0 .. cThreadCount - 1] of TEvent;
  lAllCallbacksDone: TEvent;
  lShutdownDone: TEvent;
  lErrorLock: TCriticalSection;
  lErrorText: string;
  lDriverTickIndex: Integer;
  lStopWorkers: Integer;
  lCallbackCount: Integer;
  lObservedCount: Integer;
  lBaseDueAt: TDateTime;
  lIndex: Integer;
  lWaitStopwatch: TStopwatch;
  lCronForShutdown: TmaxCron;
  lConfiguredEngine: string;
  lEffectiveEngine: string;
  lAutoState: string;
  lSwitchCount: UInt64;
  lPreviousEngineValue: string;
  lPreviousEnterEventsValue: string;
  lPreviousExitEventsValue: string;
  lPreviousEnterDirtyValue: string;
  lPreviousExitDirtyValue: string;
  lPreviousEnterHoldValue: string;
  lPreviousExitHoldValue: string;
  lPreviousTrialTicksValue: string;
  lPreviousCooldownValue: string;
  lPreviousPromoteRatioValue: string;
  lPreviousDemoteRatioValue: string;
  lHadEngineValue: Boolean;
  lHadEnterEventsValue: Boolean;
  lHadExitEventsValue: Boolean;
  lHadEnterDirtyValue: Boolean;
  lHadExitDirtyValue: Boolean;
  lHadEnterHoldValue: Boolean;
  lHadExitHoldValue: Boolean;
  lHadTrialTicksValue: Boolean;
  lHadCooldownValue: Boolean;
  lHadPromoteRatioValue: Boolean;
  lHadDemoteRatioValue: Boolean;

  function MakeWorker(const aWorkerIndex: Integer): TThread;
  begin
    Result := TThread.CreateAnonymousThread(
      procedure
      var
        lTickIndex: Integer;
        lTickAt: TDateTime;
      begin
        lThreadReady[aWorkerIndex].SetEvent;
        while True do
        begin
          if TInterlocked.CompareExchange(lStopWorkers, 0, 0) <> 0 then
            Break;

          try
            lTickIndex := TInterlocked.CompareExchange(lDriverTickIndex, 0, 0);
            if lTickIndex < 0 then
            begin
              TThread.Yield;
              Continue;
            end;
            lTickAt := IncSecond(lBaseDueAt, lTickIndex);
            lCron.TickAt(lTickAt);
          except
            on E: Exception do
            begin
              SetError(lErrorLock, lErrorText, 'WorkerTick', E.ClassName + ': ' + E.Message);
              Exit;
            end;
          end;

          if (lTickIndex and $07) = 0 then
            TThread.Yield;
          TThread.Sleep(1);
        end;
      end
      );
    Result.FreeOnTerminate := False;
  end;
begin
  lCron := nil;
  lCronForShutdown := nil;
  for lIndex := 0 to cThreadCount - 1 do
  begin
    lThreads[lIndex] := nil;
    lThreadReady[lIndex] := nil;
  end;

  lDriverTickIndex := -1;
  lStopWorkers := 0;
  lCallbackCount := 0;
  lErrorText := '';
  lErrorLock := TCriticalSection.Create;
  lAllCallbacksDone := TEvent.Create(nil, True, False, '');
  lShutdownDone := TEvent.Create(nil, True, False, '');
  try
    SetEnvVar('MAXCRON_ENGINE', 'auto', lPreviousEngineValue, lHadEngineValue);
    SetEnvVar('MAXCRON_AUTO_ENTER_EVENTS', '200', lPreviousEnterEventsValue, lHadEnterEventsValue);
    SetEnvVar('MAXCRON_AUTO_EXIT_EVENTS', '120', lPreviousExitEventsValue, lHadExitEventsValue);
    SetEnvVar('MAXCRON_AUTO_ENTER_DIRTY', '0.10', lPreviousEnterDirtyValue, lHadEnterDirtyValue);
    SetEnvVar('MAXCRON_AUTO_EXIT_DIRTY', '0.25', lPreviousExitDirtyValue, lHadExitDirtyValue);
    SetEnvVar('MAXCRON_AUTO_ENTER_HOLD', '2', lPreviousEnterHoldValue, lHadEnterHoldValue);
    SetEnvVar('MAXCRON_AUTO_EXIT_HOLD', '2', lPreviousExitHoldValue, lHadExitHoldValue);
    SetEnvVar('MAXCRON_AUTO_TRIAL_TICKS', '4', lPreviousTrialTicksValue, lHadTrialTicksValue);
    SetEnvVar('MAXCRON_AUTO_COOLDOWN', '2', lPreviousCooldownValue, lHadCooldownValue);
    SetEnvVar('MAXCRON_AUTO_PROMOTE_RATIO', '1.25', lPreviousPromoteRatioValue, lHadPromoteRatioValue);
    SetEnvVar('MAXCRON_AUTO_DEMOTE_RATIO', '1.40', lPreviousDemoteRatioValue, lHadDemoteRatioValue);
    try
      lCron := TmaxCron.Create(ctPortable);
      try
        lDueEvent := lCron.Add('AutoConcurrentDue');
        lDueEvent.EventPlan := '* * * * * * * 0';
        lDueEvent.InvokeMode := imMainThread;
        lDueEvent.OnScheduleProc :=
          procedure(aSender: IMaxCronEvent)
          var
            lCount: Integer;
          begin
            lCount := TInterlocked.Increment(lCallbackCount);
            if lCount >= cTotalTicks then
              lAllCallbacksDone.SetEvent;
          end;
        lDueEvent.Run;
        lBaseDueAt := lDueEvent.NextSchedule;
        lCron.TickAt(lBaseDueAt);
        lWaitStopwatch := TStopwatch.StartNew;
        while (TInterlocked.CompareExchange(lCallbackCount, 0, 0) < 1) and
          (lWaitStopwatch.ElapsedMilliseconds < 1000) do
          CheckSynchronize(5);
        Assert.AreEqual(1, TInterlocked.CompareExchange(lCallbackCount, 0, 0),
          'Initial due tick should execute exactly once');

        lChurnEvent := lCron.Add('AutoConcurrentChurn');
        lChurnEvent.EventPlan := cFuturePlan;
        lChurnEvent.Run;

        for lIndex := 0 to cEventCount - 1 do
        begin
          lEvent := lCron.Add('AutoConcurrentFar_' + IntToStr(lIndex));
          lEvent.EventPlan := cFuturePlan;
          lEvent.Run;
        end;

        for lIndex := 0 to cThreadCount - 1 do
          lThreadReady[lIndex] := TEvent.Create(nil, True, False, '');
        try
          for lIndex := 0 to cThreadCount - 1 do
          begin
            lThreads[lIndex] := MakeWorker(lIndex);
            lThreads[lIndex].Start;
          end;

          for lIndex := 0 to cThreadCount - 1 do
            Assert.AreEqual(TWaitResult.wrSignaled, lThreadReady[lIndex].WaitFor(3000), 'Worker did not start');

          for lIndex := 1 to cTotalTicks - 1 do
          begin
            TInterlocked.Exchange(lDriverTickIndex, lIndex);
            if (lIndex >= cChurnStartTick) and (lIndex < cChurnEndTick) then
            begin
              lChurnEvent.Stop;
              lChurnEvent.Run;
            end;
            lCron.TickAt(IncSecond(lBaseDueAt, lIndex));
            CheckSynchronize(0);
          end;
          TInterlocked.Exchange(lStopWorkers, 1);

          for lIndex := 0 to cThreadCount - 1 do
            lThreads[lIndex].WaitFor;
        finally
          for lIndex := 0 to cThreadCount - 1 do
          begin
            if lThreadReady[lIndex] <> nil then
              lThreadReady[lIndex].Free;
            if lThreads[lIndex] <> nil then
              lThreads[lIndex].Free;
          end;
        end;

        lErrorLock.Acquire;
        try
          if lErrorText <> '' then
            Assert.Fail(lErrorText);
        finally
          lErrorLock.Release;
        end;

        lWaitStopwatch := TStopwatch.StartNew;
        while (TInterlocked.CompareExchange(lCallbackCount, 0, 0) < cTotalTicks) and
          (lWaitStopwatch.ElapsedMilliseconds < 10000) do
          CheckSynchronize(5);

        lObservedCount := TInterlocked.CompareExchange(lCallbackCount, 0, 0);
        Assert.IsTrue(lObservedCount >= (cTotalTicks - 1),
          Format('Concurrent auto switching should not lose due callbacks (expected >= %d observed=%d)',
            [cTotalTicks - 1, lObservedCount]));
        Assert.IsTrue(lObservedCount <= cTotalTicks,
          Format('Concurrent auto switching should not duplicate due callbacks (expected <= %d observed=%d)',
            [cTotalTicks, lObservedCount]));

        lCron.GetEngineStateForTests(lConfiguredEngine, lEffectiveEngine, lAutoState, lSwitchCount);
        Assert.AreEqual('auto', lConfiguredEngine);
        Assert.IsTrue((lEffectiveEngine = 'scan') or (lEffectiveEngine = 'heap'),
          'Auto mode should keep effective engine in scan/heap set');
        Assert.IsTrue(lAutoState <> 'disabled', 'Auto mode state should stay active');
        Assert.IsTrue(lSwitchCount >= 2, 'Concurrent churn phases should force at least two auto-engine switches');

        lDueEvent := nil;
        lChurnEvent := nil;
        lEvent := nil;

        lCronForShutdown := lCron;
        lCron := nil;
        TThread.CreateAnonymousThread(
          procedure
          begin
            try
              lCronForShutdown.Free;
            except
              on E: Exception do
                SetError(lErrorLock, lErrorText, 'Shutdown', E.ClassName + ': ' + E.Message);
            end;
            lShutdownDone.SetEvent;
          end
          ).Start;

        Assert.AreEqual(TWaitResult.wrSignaled, lShutdownDone.WaitFor(5000),
          'Scheduler shutdown should remain stable during auto switching');

        lErrorLock.Acquire;
        try
          if lErrorText <> '' then
            Assert.Fail(lErrorText);
        finally
          lErrorLock.Release;
        end;
      finally
        if lCron <> nil then
          lCron.Free;
      end;
    finally
      RestoreEnvVar('MAXCRON_AUTO_DEMOTE_RATIO', lPreviousDemoteRatioValue, lHadDemoteRatioValue);
      RestoreEnvVar('MAXCRON_AUTO_PROMOTE_RATIO', lPreviousPromoteRatioValue, lHadPromoteRatioValue);
      RestoreEnvVar('MAXCRON_AUTO_COOLDOWN', lPreviousCooldownValue, lHadCooldownValue);
      RestoreEnvVar('MAXCRON_AUTO_TRIAL_TICKS', lPreviousTrialTicksValue, lHadTrialTicksValue);
      RestoreEnvVar('MAXCRON_AUTO_EXIT_HOLD', lPreviousExitHoldValue, lHadExitHoldValue);
      RestoreEnvVar('MAXCRON_AUTO_ENTER_HOLD', lPreviousEnterHoldValue, lHadEnterHoldValue);
      RestoreEnvVar('MAXCRON_AUTO_EXIT_DIRTY', lPreviousExitDirtyValue, lHadExitDirtyValue);
      RestoreEnvVar('MAXCRON_AUTO_ENTER_DIRTY', lPreviousEnterDirtyValue, lHadEnterDirtyValue);
      RestoreEnvVar('MAXCRON_AUTO_EXIT_EVENTS', lPreviousExitEventsValue, lHadExitEventsValue);
      RestoreEnvVar('MAXCRON_AUTO_ENTER_EVENTS', lPreviousEnterEventsValue, lHadEnterEventsValue);
      RestoreEnvVar('MAXCRON_ENGINE', lPreviousEngineValue, lHadEngineValue);
    end;
  finally
    lShutdownDone.Free;
    lAllCallbacksDone.Free;
    lErrorLock.Free;
  end;
end;

end.

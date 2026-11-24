unit TestWatchdogDiagnostics;

interface

uses
  System.DateUtils, System.Generics.Collections, System.SyncObjs, System.SysUtils,
  DUnitX.TestFramework,
  maxCron, TestEnvironment;

type
  [TestFixture]
  TTestWatchdogDiagnostics = class
  private
    procedure SetEnvVarWithBackup(const aName, aValue: string; const aBackups: TList<TTestEnvSnapshot>);
    procedure RestoreEnvVars(const aBackups: TList<TTestEnvSnapshot>);
  public
    [Test]
    procedure ThresholdBreaches_AreReported;
  end;

implementation

procedure TTestWatchdogDiagnostics.SetEnvVarWithBackup(const aName, aValue: string;
  const aBackups: TList<TTestEnvSnapshot>);
begin
  aBackups.Add(SaveTestEnvironmentVariable(aName));
  SetTestEnvironmentVariable(aName, aValue);
end;

procedure TTestWatchdogDiagnostics.RestoreEnvVars(const aBackups: TList<TTestEnvSnapshot>);
var
  lIndex: Integer;
begin
  for lIndex := aBackups.Count - 1 downto 0 do
    RestoreTestEnvironmentVariable(aBackups[lIndex]);
end;

procedure TTestWatchdogDiagnostics.ThresholdBreaches_AreReported;
var
  lBackups: TList<TTestEnvSnapshot>;
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lEntered: TEvent;
  lRelease: TEvent;
  lDone: TEvent;
  lDiag: TMaxCronWatchdogDiagnostics;
  lTickAt: TDateTime;
begin
  lBackups := TList<TTestEnvSnapshot>.Create;
  lCron := nil;
  lEntered := TEvent.Create(nil, True, False, '');
  lRelease := TEvent.Create(nil, True, False, '');
  lDone := TEvent.Create(nil, True, False, '');
  try
    SetEnvVarWithBackup('MAXCRON_WATCHDOG_MAX_TICK_LAG_MS', '10', lBackups);
    SetEnvVarWithBackup('MAXCRON_WATCHDOG_MAX_QUEUE_DEPTH', '0', lBackups);
    SetEnvVarWithBackup('MAXCRON_WATCHDOG_MAX_INFLIGHT', '0', lBackups);
    SetEnvVarWithBackup('MAXCRON_WATCHDOG_MAX_SWITCH_CHURN', '0', lBackups);
    SetEnvVarWithBackup('MAXCRON_WATCHDOG_SWITCH_WINDOW', '64', lBackups);

    lCron := TmaxCron.Create(ctPortable);

    lEvent := lCron.Add('WatchdogThresholdBreach');
    lEvent.EventPlan := '* * * * * * * 0';
    lEvent.InvokeMode := imThread;
    lEvent.OverlapMode := omSerialize;
    lEvent.OnScheduleProc :=
      procedure(aSender: IMaxCronEvent)
      begin
        lEntered.SetEvent;
        lRelease.WaitFor(2000);
        lDone.SetEvent;
      end;
    lEvent.Run;

    lTickAt := lEvent.NextSchedule;
    lCron.TickAt(lTickAt);

    Assert.AreEqual(TWaitResult.wrSignaled, lEntered.WaitFor(1500),
      'Callback did not enter to create in-flight watchdog sample');

    Assert.IsTrue(lCron.TryGetWatchdogDiagnostics(lDiag), 'Expected watchdog diagnostics snapshot');
    Assert.IsTrue(lDiag.InFlightCallbacks > 0,
      'Expected in-flight callback count to be positive while callback is blocked');
    Assert.IsTrue(lDiag.InFlightCallbacksBreached,
      'Expected in-flight threshold breach while callback is blocked');
    Assert.AreEqual(Cardinal(10), lDiag.MaxTickLagMs, 'Tick lag threshold should come from env override');

    lRelease.SetEvent;
    Assert.AreEqual(TWaitResult.wrSignaled, lDone.WaitFor(2000), 'Callback did not complete');

    lEvent.Stop;
    lCron.TickAt(IncSecond(Now, -2));

    Assert.IsTrue(lCron.TryGetWatchdogDiagnostics(lDiag), 'Expected watchdog diagnostics after stale tick');
    Assert.IsTrue(lDiag.TickLagBreached,
      'Expected stale TickAt timestamp to breach tick-lag threshold');
    Assert.IsFalse(lDiag.QueueDepthBreached,
      'Queue depth should remain under threshold in this deterministic path');
    Assert.IsFalse(lDiag.SwitchChurnBreached,
      'Switch churn should remain under threshold in scan mode');
    Assert.IsTrue(lDiag.AnyThresholdBreached,
      'At least one watchdog threshold should be breached in this scenario');
  finally
    if lCron <> nil then
      lCron.Free;
    RestoreEnvVars(lBackups);
    lDone.Free;
    lRelease.Free;
    lEntered.Free;
    lBackups.Free;
  end;
end;

end.

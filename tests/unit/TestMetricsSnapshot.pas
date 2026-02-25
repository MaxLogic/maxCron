unit TestMetricsSnapshot;

interface

uses
  System.DateUtils, System.SyncObjs, System.SysUtils,
  DUnitX.TestFramework,
  maxCron;

type
  [TestFixture]
  TTestMetricsSnapshot = class
  public
    [Test]
    procedure ExposesExpectedFields;
  end;

implementation

procedure TTestMetricsSnapshot.ExposesExpectedFields;
var
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lFired: TEvent;
  lSnapshot: TMaxCronMetricsSnapshot;
  lTickAt: TDateTime;
begin
  lCron := TmaxCron.Create(ctPortable);
  lFired := TEvent.Create(nil, True, False, '');
  try
    lEvent := lCron.Add('MetricsSnapshotEvent');
    lEvent.EventPlan := '* * * * * * * 1';
    lEvent.InvokeMode := imThread;
    lEvent.OverlapMode := omSerialize;
    lEvent.OnScheduleProc :=
      procedure(aSender: IMaxCronEvent)
      begin
        lFired.SetEvent;
      end;
    lEvent.Run;

    lTickAt := lEvent.NextSchedule;
    lCron.TickAt(lTickAt);
    Assert.AreEqual(TWaitResult.wrSignaled, lFired.WaitFor(2000),
      'Expected callback execution before taking metrics snapshot');

    lSnapshot := lCron.GetMetricsSnapshot;

    Assert.IsTrue(lSnapshot.CapturedAtUtc > 0, 'CapturedAtUtc should be populated');
    Assert.IsTrue(lSnapshot.ConfiguredEngine <> '', 'ConfiguredEngine should be populated');
    Assert.IsTrue(lSnapshot.EffectiveEngine <> '', 'EffectiveEngine should be populated');
    Assert.IsTrue(lSnapshot.AutoState <> '', 'AutoState should be populated');
    Assert.IsTrue(lSnapshot.TickEventsVisited > 0, 'TickEventsVisited should reflect executed ticks');
    Assert.IsTrue(lSnapshot.Watchdog.MaxTickLagMs > 0, 'Watchdog max tick lag threshold should be populated');
    Assert.IsTrue(lSnapshot.Watchdog.MaxInFlightCallbacks >= 0,
      'Watchdog in-flight threshold should be exported');
    Assert.IsTrue(lSnapshot.Watchdog.MaxQueueDepth >= 0,
      'Watchdog queue-depth threshold should be exported');
    Assert.IsTrue(lSnapshot.Watchdog.MaxSwitchChurn >= 0,
      'Watchdog switch-churn threshold should be exported');
    Assert.IsTrue(lSnapshot.Watchdog.LastTickElapsedUs >= 0,
      'Watchdog last-tick elapsed metric should be exported');
  finally
    lFired.Free;
    lCron.Free;
  end;
end;

end.

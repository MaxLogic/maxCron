unit TestLocalOverlap;
{$I maxCron.inc}

interface

uses
  DUnitX.TestFramework,
  maxCron.Internal.TimeZone;

type
  [TestFixture]
  TTestLocalOverlap = class
  private
    procedure CheckProbeAt(const aDirect, aProbe: ICronZoneRules; const aUtcMs: Int64);
  public
    [Test] procedure ConstructorDoesNotReadStoppedClock;
    [Test] procedure ClockRollback;
    [Test] procedure ClockHookAndGap;
    [Test] procedure ProbePeriodsAndMappings;
    [Test] procedure ProbeSearchConsumers;
  end;

implementation

uses
  {$IFDEF FPC}
  Math, SysUtils,
  {$ELSE}
  System.Math, System.SysUtils,
  {$ENDIF}
  AutoFree,
  maxCron, maxCron.Plan, TestZoneFakes;

type
  TProbePlanOracle = class
  public
    Plan: TCronSchedulePlan;
    function First(const aFromLocalMs: Int64; out aLocalMs: Int64): TCronInstantSearchResult;
  end;

function TProbePlanOracle.First(const aFromLocalMs: Int64; out aLocalMs: Int64): TCronInstantSearchResult;
var
  lNext: TDateTime;
begin
  if not Plan.FindNextScheduleDate(CronMsToDateTime(aFromLocalMs - 1000), lNext) then Exit(cisNotFound);
  aLocalMs := CronDateTimeToMs(lNext);
  Result := cisFound;
end;

procedure TTestLocalOverlap.ConstructorDoesNotReadStoppedClock;
var
  g: TGarbos;
  lCron: TmaxCron;
  lWallUs: Int64;
  lReads: Integer;
begin
  lWallUs := ZoneMs(2026, 7, 1, 0) * 1000;
  lReads := 0;
  SetCronSystemTimeZoneForTests(TZoneOnlyTimeZone.Create(CreateCronZone('plain UTC host', TCronFixedZoneSource.Create(0))));
  SetMaxCronWallClockHook(function: Int64 begin Inc(lReads); Result := lWallUs; end);
  try
    GC(lCron, TmaxCron.Create(ctPortable), g);
    Assert.AreEqual(0, lReads, 'a stopped test timer has no pass key to initialize');
    Assert.AreEqual(lWallUs, lCron.UtcNowUsForTests, 'the first actual clock request uses the hook');
    Assert.AreEqual(1, lReads);
  finally
    g.Clear;
    SetMaxCronWallClockHook(nil);
    SetCronSystemTimeZoneForTests(nil);
  end;
end;

procedure TTestLocalOverlap.ClockRollback;
var
  g: TGarbos;
  lCron: TmaxCron;
  lZone: ICronZoneRules;
  lChanges: TArray<TZoneChange>;
  lChange: TZoneChange;
  lInitial, lBefore, lShift, lUtcMs, lWallUs: Int64;
  lIndex: Integer;
begin
  SetMaxCronUtcClockHook(nil);
  SetMaxCronWallClockHook(function: Int64 begin Result := lWallUs; end);
  try
    for lIndex in [0, 3, 6] do
    begin
      lZone := CreateCronZone('rollback host', FakeZoneSource(lIndex));
      SetCronSystemTimeZoneForTests(TZoneAsSystemZone.Create(lZone));
      lChanges := FakeZoneChanges(lIndex, lInitial);
      for lChange in lChanges do
      begin
        lBefore := lZone.GetPeriod(lChange.UtcMs - 1000).OffsetMs;
        lShift := lBefore - lChange.OffsetMs;
        if lShift <= 0 then Continue;
        lUtcMs := lChange.UtcMs - lShift - 1000;
        lWallUs := lZone.UtcToLocalMs(lUtcMs) * 1000 + 200;
        GC(lCron, TmaxCron.Create(ctPortable), g);
        while lUtcMs <= lChange.UtcMs + lShift + 1000 do
        begin
          lWallUs := lZone.UtcToLocalMs(lUtcMs) * 1000 + 200;
          Assert.AreEqual(lUtcMs * 1000 + 200, lCron.WallUsToUtcUsForTests(lWallUs), 'realistic repeated-hour clock');
          Inc(lUtcMs, 1000);
        end;
        g.Clear;
      end;
    end;
  finally
    g.Clear;
    SetMaxCronWallClockHook(nil);
    SetCronSystemTimeZoneForTests(nil);
  end;
end;

procedure TTestLocalOverlap.ClockHookAndGap;
var
  g: TGarbos;
  lCron: TmaxCron;
  lWallUs, lUtcUs, lTransition: Int64;
begin
  lTransition := ZoneMs(2026, 3, 29, 1);
  lWallUs := ZoneMs(2026, 3, 29, 0) * 1000;
  lUtcUs := lTransition * 1000 + 999999;
  SetCronSystemTimeZoneForTests(TZoneAsSystemZone.Create(CreateCronZone('host', FakeZoneSource(0))));
  SetMaxCronWallClockHook(function: Int64 begin Result := lWallUs; end);
  SetMaxCronUtcClockHook(function: Int64 begin Result := lUtcUs; end);
  try
    GC(lCron, TmaxCron.Create(ctPortable), g);
    Assert.AreEqual(lUtcUs, lCron.UtcNowUsForTests, 'UTC hook has priority over wall hook');
    lWallUs := (lTransition + 5400000) * 1000 + 200;
    Assert.IsTrue(lCron.WallUsToUtcUsForTests(lWallUs) < lTransition * 1000, 'synthetic gap maps before transition');
  finally
    g.Clear;
    SetMaxCronUtcClockHook(nil);
    SetMaxCronWallClockHook(nil);
    SetCronSystemTimeZoneForTests(nil);
  end;
end;

procedure TTestLocalOverlap.CheckProbeAt(const aDirect, aProbe: ICronZoneRules; const aUtcMs: Int64);
var
  lDirect, lProbe: TCronZonePeriod;
  lExpected, lActual: TCronLocalMapping;
  lLocalMs: Int64;
begin
  lDirect := aDirect.GetPeriod(aUtcMs);
  lProbe := aProbe.GetPeriod(aUtcMs);
  Assert.AreEqual(lDirect.OffsetMs, lProbe.OffsetMs, 'probe offset');
  Assert.IsTrue((lDirect.StartUtcMs <= lProbe.StartUtcMs) and (lProbe.StartUtcMs <= aUtcMs), 'bounded probe start');
  Assert.IsTrue((aUtcMs < lProbe.EndUtcMs) and (lProbe.EndUtcMs <= lDirect.EndUtcMs), 'bounded probe end');
  if lDirect.StartUtcMs >= aUtcMs - cCronZoneWindowMs then
    Assert.AreEqual(lDirect.StartUtcMs, lProbe.StartUtcMs, 'nearby exact start');
  if lDirect.EndUtcMs <= aUtcMs + cCronZoneWindowMs then
    Assert.AreEqual(lDirect.EndUtcMs, lProbe.EndUtcMs, 'nearby exact end');
  lLocalMs := aDirect.UtcToLocalMs(aUtcMs);
  Assert.AreEqual(lLocalMs, aProbe.UtcToLocalMs(aUtcMs), 'probe local conversion');
  lExpected := aDirect.MapLocal(lLocalMs);
  lActual := aProbe.MapLocal(lLocalMs);
  Assert.AreEqual(Ord(lExpected.Kind), Ord(lActual.Kind), 'probe inverse kind');
  Assert.AreEqual(lExpected.FirstUtcMs, lActual.FirstUtcMs, 'probe inverse first');
  Assert.AreEqual(lExpected.SecondUtcMs, lActual.SecondUtcMs, 'probe inverse second');
  // Probe the nominal local grid too, so gap values cannot be missed by only
  // projecting real UTC instants into the local timeline.
  lExpected := aDirect.MapLocal(aUtcMs);
  lActual := aProbe.MapLocal(aUtcMs);
  Assert.AreEqual(Ord(lExpected.Kind), Ord(lActual.Kind), 'probe nominal kind');
  Assert.AreEqual(lExpected.FirstUtcMs, lActual.FirstUtcMs, 'probe nominal first');
  Assert.AreEqual(lExpected.SecondUtcMs, lActual.SecondUtcMs, 'probe nominal second');
end;

procedure TTestLocalOverlap.ProbePeriodsAndMappings;
var
  lDirect, lProbe: ICronZoneRules;
  lChanges: TArray<TZoneChange>;
  lChange: TZoneChange;
  lInitial, lQuery, lChecks: Int64;
  lIndex, lMinute, lDelta, lStep: Integer;
begin
  lChecks := 0;
  lStep := 720;
  if {$IFDEF FPC}SysUtils.{$ENDIF}GetEnvironmentVariable('MAXCRON_FULL_ZONE_PROPERTIES') = '1' then lStep := 1;
  for lIndex := 0 to 6 do
  begin
    lDirect := CreateCronZone('direct', FakeZoneSource(lIndex));
    lProbe := CreateCronProbeZoneForTests(TZoneOnlyTimeZone.Create(lDirect));
    lChanges := FakeZoneChanges(lIndex, lInitial);
    for lChange in lChanges do
    begin
      lMinute := -4320;
      while lMinute <= 4320 do
      begin
        lQuery := lChange.UtcMs + Int64(lMinute) * 60000;
        CheckProbeAt(lDirect, lProbe, lQuery);
        Inc(lChecks);
        Inc(lMinute, lStep);
      end;
      for lDelta := -1 to 1 do CheckProbeAt(lDirect, lProbe, lChange.UtcMs + lDelta);
    end;
  end;
  // F1-DESIGN-02 regression: a bounded period end is valid at Warsaw's fall.
  lDirect := CreateCronZone('Warsaw regression', FakeZoneSource(0));
  lProbe := CreateCronProbeZoneForTests(TZoneOnlyTimeZone.Create(lDirect));
  CheckProbeAt(lDirect, lProbe, ZoneMs(2026, 10, 25, 1));
  System.WriteLn('Probe semantic/mapping minute comparisons: ', lChecks);
end;

procedure TTestLocalOverlap.ProbeSearchConsumers;
const
  cPlans: array[0..6] of string = ('* * * * * * *', '*/15 * * * *', '0 * * * *',
    '30 * * * *', '59 * * * * * 59', '0 0 * * *', '0 0 1 1 * 2030');
var
  g: TGarbos;
  lOracle: TProbePlanOracle;
  lDirect, lProbe: ICronZoneRules;
  lChanges: TArray<TZoneChange>;
  lChange: TZoneChange;
  lInitial, lQuery, lExpected, lActual, lChecks: Int64;
  lIndex, lSpring, lFall, lMinute, lStep, lPattern, lCalls: Integer;
  lExpectedResult, lActualResult: TCronInstantSearchResult;
begin
  GC(lOracle, TProbePlanOracle.Create, g);
  GC(lOracle.Plan, TCronSchedulePlan.Create, g);
  lStep := 4320;
  if {$IFDEF FPC}SysUtils.{$ENDIF}GetEnvironmentVariable('MAXCRON_FULL_ZONE_PROPERTIES') = '1' then lStep := 1;
  lChecks := 0;
  for lIndex := 0 to 6 do
  begin
    lDirect := CreateCronZone('direct', FakeZoneSource(lIndex));
    lProbe := CreateCronProbeZoneForTests(TZoneOnlyTimeZone.Create(lDirect));
    lChanges := FakeZoneChanges(lIndex, lInitial);
    for lPattern := Low(cPlans) to High(cPlans) do
    begin
      lOracle.Plan.Parse(cPlans[lPattern]);
      for lSpring := 0 to 1 do
        for lFall := 0 to 2 do
          for lChange in lChanges do
          begin
            lMinute := -4320;
            while lMinute <= 4320 do
            begin
              lQuery := lChange.UtcMs + Int64(lMinute) * 60000;
              lExpectedResult := CronZoneFindNextInstant(lDirect, lQuery, lSpring <> 0,
                TCronFallChoice(lFall), lOracle.First, lExpected, lCalls);
              lActualResult := CronZoneFindNextInstant(lProbe, lQuery, lSpring <> 0,
                TCronFallChoice(lFall), lOracle.First, lActual, lCalls);
              Assert.AreEqual(Ord(lExpectedResult), Ord(lActualResult), 'direct/probe walk result');
              if lExpectedResult = cisFound then Assert.AreEqual(lExpected, lActual, 'direct/probe walk instant');
              Inc(lChecks);
              Inc(lMinute, lStep);
            end;
          end;
    end;
  end;
  System.WriteLn('Probe/direct walk comparisons: ', lChecks, ', minute step=', lStep);
end;

end.

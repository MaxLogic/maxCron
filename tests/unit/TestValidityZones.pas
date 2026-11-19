unit TestValidityZones;
{$I maxCron.inc}

interface

uses
  {$IFDEF FPC}
  SysUtils, Windows,
  {$ELSE}
  System.SysUtils,
  Winapi.Windows,
  {$ENDIF}
  AutoFree, DUnitX.TestFramework,
  maxCron, maxCron.Internal.TimeZone, TestZoneFakes;

type
  [TestFixture]
  TTestValidityZones = class
  public
    [TestCase('scan', 'scan')]
    [TestCase('heap', 'heap')]
    [TestCase('shadow', 'shadow')]
    procedure ReviewerProbes(const aEngine: string);
    [TestCase('scan', 'scan')]
    [TestCase('heap', 'heap')]
    [TestCase('shadow', 'shadow')]
    procedure UtcReferenceMatrix(const aEngine: string);
    [TestCase('scan', 'scan')]
    [TestCase('heap', 'heap')]
    [TestCase('shadow', 'shadow')]
    procedure DenseFutureWindow(const aEngine: string);
    [TestCase('scan', 'scan')]
    [TestCase('heap', 'heap')]
    [TestCase('shadow', 'shadow')]
    procedure SystemOffsetExcursions(const aEngine: string);
    [TestCase('scan', 'scan')]
    [TestCase('heap', 'heap')]
    [TestCase('shadow', 'shadow')]
    procedure FutureLocalValidityWorkBound(const aEngine: string);
  end;

implementation

type
  TValidityWorkZone = class(TInterfacedObject, ICronTimeZone)
  public
    function ToUniversalTime(const aLocal: TDateTime; const aForceDaylight: Boolean): TDateTime;
    function ToLocalTime(const aUtc: TDateTime): TDateTime;
    function IsAmbiguousTime(const aLocal: TDateTime): Boolean;
    function IsInvalidTime(const aLocal: TDateTime): Boolean;
  end;

var
  // The existing system-zone and clock test seams require serial execution.
  gValidityWorkChecks: Integer;

function TValidityWorkZone.ToUniversalTime(const aLocal: TDateTime; const aForceDaylight: Boolean): TDateTime;
begin
  Result := aLocal;
end;

function TValidityWorkZone.ToLocalTime(const aUtc: TDateTime): TDateTime;
begin
  Result := aUtc;
end;

function TValidityWorkZone.IsAmbiguousTime(const aLocal: TDateTime): Boolean;
begin
  Result := False;
end;

function TValidityWorkZone.IsInvalidTime(const aLocal: TDateTime): Boolean;
begin
  Inc(gValidityWorkChecks);
  // Fail promptly if a future lower bound is reached by enumerating seconds.
  Assert.IsTrue(gValidityWorkChecks <= 32, 'LOCAL Skip validity must not enumerate the widened offset window');
  Result := False;
end;

const
  cHour: Int64 = 3600000;
  cDay: Int64 = 86400000;
  cSpring: Int64 = 3983904000000; // 2026-03-29 00:00 UTC, verified by the reference self-check.
  cAutumn: Int64 = 4002048000000; // 2026-10-25 00:00 UTC.
  cZoneNames: array[0..3] of string = ('LOCAL', 'UTC', 'UTC+00:30', 'Validity/CET');

function ReferenceOffset(const aUtcMs: Int64; const aDst: Boolean): Int64;
begin
  Result := 0;
  if aDst then
  begin
    Result := cHour;
    if (aUtcMs >= cSpring + cHour) and (aUtcMs < cAutumn + cHour) then
      Result := 2 * cHour;
  end;
end;

function ReferenceSystem(const aUtcMs: Int64; const aSystem: Integer): Int64;
begin
  Result := aUtcMs + ReferenceOffset(aUtcMs, aSystem = 1);
end;

function ReferenceBound(const aDay: Int64; const aSystem, aIndex: Integer): Int64;
const
  cPoints: array[0..12] of Int64 = (-1, 0, 1, 15 * 60000, 45 * 60000,
    3600000 - 1, 3600000, 3600000 + 1, 2 * 3600000,
    -30 * 60000, 30 * 60000, 90 * 60000 - 1, 90 * 60000);
  cGapPoints: array[0..4] of Int64 = (2 * 3600000 - 1, 2 * 3600000,
    150 * 60000, 3 * 3600000 - 1, 3 * 3600000);
begin
  Result := 0;
  if aIndex < 0 then Exit;
  if aIndex <= High(cPoints) then
    Result := ReferenceSystem(aDay + cHour div 2 + cPoints[aIndex], aSystem)
  else
    Result := aDay + cGapPoints[aIndex - Length(cPoints)];
end;

function ReferenceEvent(const aUtcMs: Int64; const aSystem, aEvent: Integer): Int64;
begin
  case aEvent of
    0: Result := ReferenceSystem(aUtcMs, aSystem);
    1: Result := aUtcMs;
    2: Result := aUtcMs + cHour div 2;
  else
    Result := aUtcMs + ReferenceOffset(aUtcMs, True);
  end;
end;

function ReferenceFirst(const aDay, aBaseUtc, aFrom, aTo: Int64;
  const aSystem, aEvent, aFall, aSpringPolicy: Integer; out aUtc: Int64): Boolean;
var
  lNominal, lCandidate, lFirst, lSecond: Int64;
  lOffset: Int64;
  d, k, n: Integer;
  lDst: Boolean;
begin
  aUtc := 0;
  // Enumerate explicit UTC solutions of each daily 02:30 wall occurrence.
  // No library search, mapping, offset-range or validity helper is the oracle.
  lDst := (aEvent = 3) or ((aEvent = 0) and (aSystem = 1));
  for d := 0 to 3 do
  begin
    lNominal := aDay + d * cDay + 2 * cHour + cHour div 2;
    n := 0;
    lFirst := 0;
    lSecond := 0;
    for k := 0 to Ord(lDst) do
    begin
      lOffset := 0;
      if lDst then lOffset := (2 - k) * cHour;
      if aEvent = 2 then lOffset := cHour div 2;
      lCandidate := lNominal - lOffset;
      if ReferenceEvent(lCandidate, aSystem, aEvent) = lNominal then
      begin
        if n = 0 then lFirst := lCandidate else lSecond := lCandidate;
        Inc(n);
      end;
    end;
    if (n = 0) and lDst and (aDay + d * cDay = cSpring) and (aSpringPolicy = 1) then
    begin
      n := 1;
      lFirst := cSpring + cHour;
    end;
    if (n = 2) and (aFall = Ord(dfpRunOncePreferSecondInstance)) then
    begin
      lFirst := lSecond;
      n := 1;
    end else if (n = 2) and (aFall <> Ord(dfpRunTwice)) then
      n := 1;
    for k := 0 to n - 1 do
    begin
      lCandidate := lFirst;
      if k = 1 then lCandidate := lSecond;
      if (lCandidate > aBaseUtc) and
        ((aFrom = 0) or (ReferenceSystem(lCandidate, aSystem) >= aFrom)) and
        ((aTo = 0) or (ReferenceSystem(lCandidate, aSystem) <= aTo)) then
      begin
        aUtc := lCandidate;
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

function ReferenceDispatchCase(const aSystem, aEvent, aFall: Integer; const aUtc: Int64): Boolean;
begin
  // F1 (local-overlap defect d) owns repeated-system-hour LOCAL second dispatch.
  // Search assertions remain in this matrix; those dispatch rows are retained
  // separately with identical base/candidate failure proof, not ignored tests.
  Result := not ((aSystem = 1) and (aEvent = 0) and
    ((aFall = Ord(dfpRunTwice)) or (aFall = Ord(dfpRunOncePreferSecondInstance))) and
    (aUtc >= cAutumn) and (aUtc < cAutumn + 2 * cHour));
end;

procedure CheckReferenceEpochs;
begin
  Assert.AreEqual(cSpring, ZoneMs(2026, 3, 29, 0), 'Independent spring epoch');
  Assert.AreEqual(cAutumn, ZoneMs(2026, 10, 25, 0), 'Independent autumn epoch');
end;

procedure TTestValidityZones.ReviewerProbes(const aEngine: string);
var
  g: TGarbos;
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lWallUs, lBase, lFrom, lTo, lExpected, lDay: Int64;
  lOldEngine, lHint: string;
  i, lFires, lFailures: Integer;
begin
  CheckReferenceEpochs;
  lOldEngine := {$IFDEF FPC}SysUtils.{$ENDIF}GetEnvironmentVariable('MAXCRON_ENGINE');
  SetEnvironmentVariableW('MAXCRON_ENGINE', PChar(aEngine));
  SetCronSystemTimeZoneForTests(TZoneAsSystemZone.Create(CreateCronZone('UTC', TCronFixedZoneSource.Create(0))));
  RegisterCronZoneForTests('Validity/CET', FakeZoneSource(0));
  lWallUs := (cAutumn - cDay) * 1000;
  SetMaxCronWallClockHook(function: Int64 begin Result := lWallUs; end);
  lFailures := 0;
  try
    GC(lCron, TmaxCron.Create(ctPortable), g);
    lEvent := lCron.Add('reviewer-validity');
    lEvent.TimeZoneId := 'Validity/CET';
    lEvent.EventPlan := '30 2 * * *';
    lEvent.InvokeMode := imMainThread;
    lEvent.DstFallPolicy := dfpRunTwice;
    lEvent.OnScheduleProc := procedure(aSender: IMaxCronEvent) begin Inc(lFires); end;
    for i := 0 to 3 do
    begin
      lEvent.Stop;
      lDay := cAutumn;
      if i = 3 then lDay := cSpring;
      lBase := lDay;
      lFrom := lDay + cHour + cHour div 2;
      lTo := lFrom;
      lExpected := lFrom;
      case i of
        1: begin lFrom := 0; lTo := lDay + cHour + cHour div 4; lExpected := lDay + cHour div 2; end;
        2: begin lFrom := lDay + 3 * cHour div 4; lTo := 0; end;
        3: begin lFrom := lDay + cHour; lTo := lFrom; lExpected := lFrom; end;
      end;
      lEvent.DstSpringPolicy := TmaxCronDstSpringPolicy(Ord(dspSkip) + Ord(i = 3));
      lWallUs := lBase * 1000;
      lFires := 0;
      lEvent.ValidFrom := CronMsToDateTime(lFrom);
      lEvent.ValidTo := CronMsToDateTime(lTo);
      lEvent.Run;
      lHint := Format('reviewer=%d engine=%s from=%d to=%d expected=%d actual=%d enabled=%s',
        [i, aEngine, lFrom, lTo, lExpected, CronDateTimeToMs(lEvent.NextSchedule), BoolToStr(lEvent.Enabled, True)]);
      if (not lEvent.Enabled) or (CronDateTimeToMs(lEvent.NextSchedule) <> lExpected) then
      begin
        Inc(lFailures);
        System.Writeln('VALIDITY_FAIL ', lHint);
      end;
      lWallUs := lExpected * 1000;
      lCron.TickAtUs(lWallUs);
      if lFires <> 1 then
      begin
        Inc(lFailures);
        System.Writeln('VALIDITY_FIRE_FAIL ', lHint, ' fires=', lFires);
      end;
      System.Writeln('REVIEWER_CASE|', aEngine, '|', i, '|', lExpected, '|', lFires);
    end;
    Assert.AreEqual(0, lFailures, 'Reviewer four probes x engine=' + aEngine);
  finally
    lEvent := nil;
    g.Clear;
    SetMaxCronWallClockHook(nil);
    SetCronSystemTimeZoneForTests(nil);
    ClearCronZonesForTests;
    SetEnvironmentVariableW('MAXCRON_ENGINE', PChar(lOldEngine));
  end;
end;

procedure TTestValidityZones.UtcReferenceMatrix(const aEngine: string);
var
  g: TGarbos;
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lWallUs, lDay, lBaseUtc, lFrom, lTo, lExpectedUtc, lExpectedWall, lActualWall, lPoint: Int64;
  lOldEngine, lHint, lFirstFailure: string;
  lSystem, lZone, lFall, lSpringPolicy, lSeason, i, j, lFires: Integer;
  lFailures, lChecks, lDispatches: Integer;
  lExpectedFound, lCorrect, lTrace: Boolean;
begin
  CheckReferenceEpochs;
  lOldEngine := {$IFDEF FPC}SysUtils.{$ENDIF}GetEnvironmentVariable('MAXCRON_ENGINE');
  lTrace := {$IFDEF FPC}SysUtils.{$ENDIF}GetEnvironmentVariable('MAXCRON_VALIDITY_TRACE') = '1';
  SetEnvironmentVariableW('MAXCRON_ENGINE', PChar(aEngine));
  lFailures := 0;
  lChecks := 0;
  lDispatches := 0;
  lFirstFailure := '';
  lWallUs := (cSpring - cDay) * 1000;
  SetMaxCronWallClockHook(function: Int64 begin Result := lWallUs; end);
  try
    for lSystem := 0 to 1 do
      for lZone := 0 to 3 do
      begin
        if lSystem = 0 then
          SetCronSystemTimeZoneForTests(TZoneAsSystemZone.Create(CreateCronZone('UTC', TCronFixedZoneSource.Create(0))))
        else
          SetCronSystemTimeZoneForTests(TZoneAsSystemZone.Create(CreateCronZone('System/CET', FakeZoneSource(0))));
        RegisterCronZoneForTests('Validity/CET', FakeZoneSource(0));
        GC(lCron, TmaxCron.Create(ctPortable), g);
        lEvent := lCron.Add('UTC-reference-validity');
        lEvent.TimeZoneId := cZoneNames[lZone];
        lEvent.EventPlan := '30 2 * * *';
        lEvent.InvokeMode := imMainThread;
        lEvent.OnScheduleProc := procedure(aSender: IMaxCronEvent) begin Inc(lFires); end;
        for lFall := Ord(Low(TmaxCronDstFallPolicy)) to Ord(High(TmaxCronDstFallPolicy)) do
          for lSpringPolicy := 0 to 1 do
            for lSeason := 0 to 1 do
            begin
              lDay := cSpring;
              if lSeason = 1 then lDay := cAutumn;
              lBaseUtc := lDay - 3 * cHour;
              // Cartesian original-bound pairs plus every lower-only/upper-only
              // and single-point window. Points include first/second +/- 1 ms,
              // between instances, gap start, inside gap and its end.
              for i := -1 to 17 do
                for j := -1 to 17 do
                begin
                  lFrom := ReferenceBound(lDay, lSystem, i);
                  lTo := ReferenceBound(lDay, lSystem, j);
                  lEvent.Stop;
                  lWallUs := ReferenceSystem(lBaseUtc, lSystem) * 1000;
                  lFires := 0;
                  lEvent.DstFallPolicy := TmaxCronDstFallPolicy(lFall);
                  lEvent.DstSpringPolicy := TmaxCronDstSpringPolicy(Ord(dspSkip) + lSpringPolicy);
                  lEvent.ValidFrom := CronMsToDateTime(lFrom);
                  lEvent.ValidTo := CronMsToDateTime(lTo);
                  lExpectedFound := ReferenceFirst(lDay, lBaseUtc, lFrom, lTo,
                    lSystem, lZone, lFall, lSpringPolicy, lExpectedUtc);
                  lExpectedWall := 0;
                  if lExpectedFound then lExpectedWall := ReferenceSystem(lExpectedUtc, lSystem);
                  lEvent.Run;
                  lActualWall := 0;
                  if lEvent.Enabled then lActualWall := CronDateTimeToMs(lEvent.NextSchedule);
                  lCorrect := lEvent.Enabled = lExpectedFound;
                  if lExpectedFound then
                    lCorrect := lCorrect and (lActualWall = lExpectedWall);
                  Inc(lChecks);
                  lHint := Format('engine=%s system=%d event=%d season=%d fall=%d spring=%d i=%d j=%d from=%d to=%d expectedUtc=%d expectedWall=%d actualWall=%d enabled=%s',
                    [aEngine, lSystem, lZone, lSeason, lFall, lSpringPolicy, i, j, lFrom, lTo,
                    lExpectedUtc, lExpectedWall, lActualWall, BoolToStr(lEvent.Enabled, True)]);
                  if not lCorrect then
                  begin
                    Inc(lFailures);
                    if lFirstFailure = '' then lFirstFailure := lHint;
                    if lFailures <= 12 then System.Writeln('MATRIX_FAIL ', lHint);
                  end;
                  if lTrace then System.Writeln('MATRIX|', lHint, '|correct=', BoolToStr(lCorrect, True));
                  if lExpectedFound and (not ReferenceDispatchCase(lSystem, lZone, lFall, lExpectedUtc)) and lTrace then
                    System.Writeln('F1_DISPATCH_CASE|', lHint);
                  if lExpectedFound and ReferenceDispatchCase(lSystem, lZone, lFall, lExpectedUtc) then
                  begin
                    // Feed an actual rollback before a preferred second system
                    // occurrence, so existing LOCAL/named hold gates see it.
                    if (lSystem = 1) and (lExpectedUtc >= cAutumn + cHour) and
                      (lExpectedUtc < cAutumn + 2 * cHour) and ((lZone = 0) or (lZone = 3)) then
                    begin
                      lPoint := ReferenceSystem(cAutumn + cHour - 1000, lSystem);
                      lCron.TickAtUs(lPoint * 1000);
                      lPoint := ReferenceSystem(cAutumn + cHour, lSystem);
                      lCron.TickAtUs(lPoint * 1000);
                    end;
                    lWallUs := lExpectedWall * 1000;
                    lCron.TickAtUs(lWallUs);
                    Inc(lDispatches);
                    if lFires <> 1 then
                    begin
                      Inc(lFailures);
                      if lFirstFailure = '' then lFirstFailure := 'dispatch ' + lHint;
                      if lFailures <= 12 then System.Writeln('MATRIX_FIRE_FAIL ', lHint, ' fires=', lFires);
                    end;
                  end;
                end;
            end;
        lEvent := nil;
        g.Clear;
      end;
    System.Writeln('UTC_MATRIX engine=', aEngine, ' checks=', lChecks, ' dispatches=', lDispatches,
      ' failures=', lFailures, ' first=', lFirstFailure);
    Assert.AreEqual(0, lFailures, lFirstFailure);
  finally
    lEvent := nil;
    g.Clear;
    SetMaxCronWallClockHook(nil);
    SetCronSystemTimeZoneForTests(nil);
    ClearCronZonesForTests;
    SetEnvironmentVariableW('MAXCRON_ENGINE', PChar(lOldEngine));
  end;
end;

procedure TTestValidityZones.FutureLocalValidityWorkBound(const aEngine: string);
var
  g: TGarbos;
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lZone: ICronTimeZone;
  lWallUs, lDueMs: Int64;
  i: Integer;
  lOldEngine: string;
begin
  lOldEngine := {$IFDEF FPC}SysUtils.{$ENDIF}GetEnvironmentVariable('MAXCRON_ENGINE');
  SetEnvironmentVariableW('MAXCRON_ENGINE', PChar(aEngine));
  lWallUs := ZoneMs(2026, 1, 1, 0) * 1000;
  gValidityWorkChecks := 0;
  lZone := TValidityWorkZone.Create;
  SetCronSystemTimeZoneForTests(lZone);
  SetMaxCronWallClockHook(function: Int64 begin Result := lWallUs; end);
  try
    GC(lCron, TmaxCron.Create(ctPortable), g);
    lEvent := lCron.Add('future-local-validity-work');
    lEvent.EventPlan := '* * * * * * *';
    lEvent.DstSpringPolicy := TmaxCronDstSpringPolicy.dspSkip;
    // Same dense, distant-window shape as GeneratedDueInstants, with an
    // executable call bound instead of a wall-clock timeout or smaller corpus.
    for i := 0 to 7 do
    begin
      lEvent.Stop;
      lDueMs := ZoneMs(2030 + 50 * i, 12, 28, 0);
      lEvent.ValidFrom := CronMsToDateTime(lDueMs);
      lEvent.ValidTo := CronMsToDateTime(lDueMs);
      gValidityWorkChecks := 0;
      lEvent.Run;
      Assert.IsTrue(lEvent.Enabled);
      Assert.AreEqual(lDueMs, CronDateTimeToMs(lEvent.NextSchedule), 'Inclusive future singleton');
      Assert.IsTrue(gValidityWorkChecks <= 32, 'Mapping work is independent of distance and offset-window seconds');
    end;
  finally
    lEvent := nil;
    g.Clear;
    SetMaxCronWallClockHook(nil);
    SetCronSystemTimeZoneForTests(nil);
    lZone := nil;
    SetEnvironmentVariableW('MAXCRON_ENGINE', PChar(lOldEngine));
  end;
end;

procedure TTestValidityZones.DenseFutureWindow(const aEngine: string);
var
  g: TGarbos;
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lWallUs, lBaseUtc, lDueUtc, lDueWall, lActualWall: Int64;
  lSystem, lZone, lFailures: Integer;
  lOldEngine, lHint: string;
  lTrace: Boolean;
begin
  lOldEngine := {$IFDEF FPC}SysUtils.{$ENDIF}GetEnvironmentVariable('MAXCRON_ENGINE');
  lTrace := {$IFDEF FPC}SysUtils.{$ENDIF}GetEnvironmentVariable('MAXCRON_VALIDITY_TRACE') = '1';
  SetEnvironmentVariableW('MAXCRON_ENGINE', PChar(aEngine));
  lBaseUtc := cAutumn + 22 * cDay;
  lDueUtc := lBaseUtc + 3 * cDay + 6 * cHour;
  lFailures := 0;
  lWallUs := lBaseUtc * 1000;
  SetMaxCronWallClockHook(function: Int64 begin Result := lWallUs; end);
  try
    for lSystem := 0 to 1 do
      for lZone := 0 to 3 do
      begin
        if lSystem = 0 then
          SetCronSystemTimeZoneForTests(TZoneAsSystemZone.Create(CreateCronZone('UTC', TCronFixedZoneSource.Create(0))))
        else
          SetCronSystemTimeZoneForTests(TZoneAsSystemZone.Create(CreateCronZone('System/CET', FakeZoneSource(0))));
        RegisterCronZoneForTests('Validity/CET', FakeZoneSource(0));
        lWallUs := ReferenceSystem(lBaseUtc, lSystem) * 1000;
        lDueWall := ReferenceSystem(lDueUtc, lSystem);
        GC(lCron, TmaxCron.Create(ctPortable), g);
        lEvent := lCron.Add('dense-future-validity');
        lEvent.TimeZoneId := cZoneNames[lZone];
        lEvent.EventPlan := '* * * * * * *';
        lEvent.ValidFrom := CronMsToDateTime(lDueWall);
        lEvent.ValidTo := CronMsToDateTime(lDueWall);
        lEvent.Run;
        lActualWall := 0;
        if lEvent.Enabled then lActualWall := CronDateTimeToMs(lEvent.NextSchedule);
        lHint := Format('engine=%s system=%d event=%d from=%d to=%d expectedUtc=%d expectedWall=%d actualWall=%d enabled=%s',
          [aEngine, lSystem, lZone, lDueWall, lDueWall, lDueUtc, lDueWall, lActualWall, BoolToStr(lEvent.Enabled, True)]);
        if lTrace then System.Writeln('DENSE_CASE|', lHint);
        if (not lEvent.Enabled) or (lActualWall <> lDueWall) then
        begin
          Inc(lFailures);
          System.Writeln('DENSE_FAIL ', lHint);
        end;
        lEvent := nil;
        g.Clear;
      end;
    Assert.AreEqual(0, lFailures, 'Dense future bounds must not exhaust the candidate budget');
  finally
    lEvent := nil;
    g.Clear;
    SetMaxCronWallClockHook(nil);
    SetCronSystemTimeZoneForTests(nil);
    ClearCronZonesForTests;
    SetEnvironmentVariableW('MAXCRON_ENGINE', PChar(lOldEngine));
  end;
end;

procedure TTestValidityZones.SystemOffsetExcursions(const aEngine: string);
const
  cPulsePlans: array[0..3] of string = ('15 1 * * *', '15 1 * * *', '45 1 * * *', '15 1 * * *');
var
  g: TGarbos;
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lChanges: TArray<TZoneChange>;
  lDay, lWallUs, lFrom, lTo, lExpectedUtc, lExpectedWall, lActualWall, lInitial: Int64;
  lPulse, lZone, lFall, lSpringPolicy, lFailures, lChecks: Integer;
  lOldEngine, lHint: string;
  lTrace: Boolean;
begin
  lOldEngine := {$IFDEF FPC}SysUtils.{$ENDIF}GetEnvironmentVariable('MAXCRON_ENGINE');
  lTrace := {$IFDEF FPC}SysUtils.{$ENDIF}GetEnvironmentVariable('MAXCRON_VALIDITY_TRACE') = '1';
  SetEnvironmentVariableW('MAXCRON_ENGINE', PChar(aEngine));
  lDay := cAutumn + 22 * cDay;
  SetLength(lChanges, 2);
  lChanges[0].UtcMs := lDay + cHour;
  lChanges[1].UtcMs := lDay + 3 * cHour div 2;
  lWallUs := (lDay - cDay) * 1000;
  SetMaxCronWallClockHook(function: Int64 begin Result := lWallUs; end);
  lFailures := 0;
  lChecks := 0;
  try
    for lPulse := 0 to 1 do
    begin
      // A bounded offset can cross a scalar bound twice without taking its
      // exact value. Converting just that bound's UTC images is insufficient.
      lInitial := 2 * cHour;
      lChanges[0].OffsetMs := 0;
      lChanges[1].OffsetMs := 2 * cHour;
      lFrom := 0;
      lTo := lDay + 165 * 60000;
      if lPulse = 1 then
      begin
        lInitial := 0;
        lChanges[0].OffsetMs := 2 * cHour;
        lChanges[1].OffsetMs := 0;
        lFrom := lDay + 165 * 60000;
        lTo := lDay + 210 * 60000;
      end;
      SetCronSystemTimeZoneForTests(TZoneAsSystemZone.Create(CreateCronZone('System/Pulse',
        TFakeZoneSource.Create(lInitial, lChanges))));
      RegisterCronZoneForTests('Validity/PulseUTC', TCronFixedZoneSource.Create(0));
      for lZone := 0 to 3 do
      begin
        GC(lCron, TmaxCron.Create(ctPortable), g);
        lEvent := lCron.Add('offset-excursion-validity');
        if lZone = 3 then lEvent.TimeZoneId := 'Validity/PulseUTC'
        else lEvent.TimeZoneId := cZoneNames[lZone];
        lEvent.EventPlan := cPulsePlans[lZone];
        if (lZone = 0) and (lPulse = 1) then lEvent.EventPlan := '15 3 * * *';
        for lFall := Ord(Low(TmaxCronDstFallPolicy)) to Ord(High(TmaxCronDstFallPolicy)) do
          for lSpringPolicy := 0 to 1 do
          begin
            lEvent.Stop;
            lWallUs := (lDay - 12 * cHour + lInitial) * 1000;
            lEvent.DstFallPolicy := TmaxCronDstFallPolicy(lFall);
            lEvent.DstSpringPolicy := TmaxCronDstSpringPolicy(Ord(dspSkip) + lSpringPolicy);
            lEvent.ValidFrom := CronMsToDateTime(lFrom);
            lEvent.ValidTo := CronMsToDateTime(lTo);
            // Independent UTC solution of the selected daily nominal plan.
            lExpectedUtc := lDay + 75 * 60000;
            if lZone = 0 then
            begin
              if (lPulse = 0) and (lFall <> Ord(dfpRunOncePreferSecondInstance)) then
                lExpectedUtc := lDay - 45 * 60000;
              if (lPulse = 1) and (lFall = Ord(dfpRunOncePreferSecondInstance)) then
                lExpectedUtc := lDay + 195 * 60000;
            end;
            lExpectedWall := lExpectedUtc + lInitial;
            if (lExpectedUtc >= lChanges[0].UtcMs) and (lExpectedUtc < lChanges[1].UtcMs) then
              lExpectedWall := lExpectedUtc + lChanges[0].OffsetMs;
            lEvent.Run;
            Inc(lChecks);
            lActualWall := 0;
            if lEvent.Enabled then lActualWall := CronDateTimeToMs(lEvent.NextSchedule);
            lHint := Format('engine=%s pulse=%d event=%d fall=%d spring=%d from=%d to=%d expectedUtc=%d expectedWall=%d actualWall=%d enabled=%s',
              [aEngine, lPulse, lZone, lFall, lSpringPolicy, lFrom, lTo, lExpectedUtc, lExpectedWall,
              lActualWall, BoolToStr(lEvent.Enabled, True)]);
            if lTrace then System.Writeln('EXCURSION_CASE|', lHint);
            if (not lEvent.Enabled) or (lActualWall <> lExpectedWall) then
            begin
              Inc(lFailures);
              if lFailures <= 12 then System.Writeln('EXCURSION_FAIL ', lHint);
            end;
          end;
        lEvent := nil;
        g.Clear;
      end;
    end;
    System.Writeln('EXCURSION_MATRIX engine=', aEngine, ' checks=', lChecks, ' failures=', lFailures);
    Assert.AreEqual(0, lFailures, 'Original system bounds survive offset excursions');
  finally
    lEvent := nil;
    g.Clear;
    SetMaxCronWallClockHook(nil);
    SetCronSystemTimeZoneForTests(nil);
    ClearCronZonesForTests;
    SetEnvironmentVariableW('MAXCRON_ENGINE', PChar(lOldEngine));
  end;
end;

end.

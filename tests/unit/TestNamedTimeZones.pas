unit TestNamedTimeZones;
{$I maxCron.inc}

interface

uses
  {$IFDEF FPC}
  SysUtils,
  DUnitX.TestFramework
  {$ELSE}
  System.SysUtils,
  DUnitX.TestFramework
  {$ENDIF};

type
  [TestFixture]
  TTestNamedTimeZones = class
  private
    procedure CheckNext(const aName, aPlan: string; const aBase, aExpected: Int64;
      const aSpring, aFall: Integer);
    procedure CheckDenseTransition(const aName: string; const aTransition, aBefore, aAfter: Int64;
      const aSpring, aFall: Integer);
    procedure CheckNamedSequence(const aName, aPlan: string; const aBase: Int64;
      const aExpected: array of Int64; const aSpring, aFall: Integer);
  public
    [Test] procedure FastPathAvoidsRangeWalk;
    [Test] procedure FastPathMatchesWalk;
    [TestCase('2047 exclusions', '2047')]
    [TestCase('2048 exclusions', '2048')]
    [TestCase('never matching', '0')]
    procedure FastPathPreservesBudget(const aExcluded: Integer);
    [Test] procedure NamedSetterAccepts;
    [Test] procedure ZoneDataRootOrder;
    [Test] procedure GmtFixedOffsetIndependentOfDataRoot;
    [Test] procedure TrollRegression;
    [Test] procedure ShiftedWindowsN6;
    [Test] procedure NamedOracleFilters;
    [Test] procedure PoliciesAndPreciseBoundaries;
    [Test] procedure GeneratedPolicyOrder;
    [Test] procedure HostRollback;
    [Test] procedure ResumeInsideHostOverlap;
    [Test] procedure RejectionAndPersistence;
  end;

implementation

uses
  {$IFDEF FPC}
  Windows,
  Generics.Collections,
  AutoFree,
  maxCron, maxCron.Internal.TimeZone, maxCron.Internal.TZif, TestZoneFakes
  {$ELSE}
  System.Generics.Collections,
  Winapi.Windows,
  AutoFree,
  maxCron, maxCron.Internal.TimeZone, maxCron.Internal.TZif, TestZoneFakes
  {$ENDIF};

const
  cNames: array[0..5] of string = ('Europe/Warsaw', 'America/New_York', 'Australia/Sydney',
    'Australia/Lord_Howe', 'America/Sao_Paulo', 'Synthetic/Three');

type
  TCountingZoneSource = class(TInterfacedObject, ICronZoneRuleSource)
  private
    fSource: ICronZoneRuleSource;
  public
    constructor Create(const aSource: ICronZoneRuleSource);
    function GetRawPeriod(const aUtcMs: Int64): TCronZonePeriod;
  end;
  TNamedStore = class(TInterfacedObject, IMaxCronScheduleStore)
  private
    fStates: TArray<TMaxCronPersistedEvent>;
  public
    procedure Save(const aEvents: TArray<TMaxCronPersistedEvent>);
    function TryLoad(out aEvents: TArray<TMaxCronPersistedEvent>): Boolean;
  end;

var
  gFastPathPeriodCalls: Integer;

constructor TCountingZoneSource.Create(const aSource: ICronZoneRuleSource);
begin
  inherited Create;
  fSource := aSource;
end;

function TCountingZoneSource.GetRawPeriod(const aUtcMs: Int64): TCronZonePeriod;
begin
  Inc(gFastPathPeriodCalls);
  Result := fSource.GetRawPeriod(aUtcMs);
end;

procedure TTestNamedTimeZones.FastPathAvoidsRangeWalk;
var
  g: TGarbos;
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lUtc, lBase: Int64;
  lCalls, lAttempts, lWalkPeriodCalls: Integer;
begin
  SetCronSystemTimeZoneForTests(TZoneAsSystemZone.Create(CreateCronZone('UTC', TCronFixedZoneSource.Create(0))));
  RegisterCronZoneForTests('Test/Counted', TCountingZoneSource.Create(FakeZoneSource(0)));
  try
    GC(lCron, TmaxCron.Create(ctPortable), g);
    lEvent := lCron.Add('fast');
    lEvent.EventPlan := '* * * * * * *';
    lEvent.TimeZoneId := 'Test/Counted';
    lBase := ZoneMs(2026, 7, 1, 0);
    SetMaxCronNamedFastPathForTests(False);
    gFastPathPeriodCalls := 0;
    Assert.AreEqual(0, FindMaxCronNamedInstantForTests(lEvent, lBase, lUtc));
    Assert.AreEqual(lBase + 1000, lUtc);
    lWalkPeriodCalls := gFastPathPeriodCalls;
    SetMaxCronNamedFastPathForTests(True);
    gFastPathPeriodCalls := 0;
    Assert.AreEqual(0, FindMaxCronNamedInstantForTests(lEvent, lBase, lUtc));
    Assert.AreEqual(lBase + 1000, lUtc);
    Assert.AreEqual(1, gFastPathPeriodCalls, 'safe interior search needs only its containing period');
    Assert.IsTrue(lWalkPeriodCalls > gFastPathPeriodCalls, 'range walk must make additional period queries');
    GetMaxCronNamedSearchForTests(lEvent, lCalls, lAttempts);
    Assert.AreEqual(1, lCalls);
    Assert.AreEqual(1, lAttempts);
  finally
    lEvent := nil;
    g.Clear;
    SetMaxCronNamedFastPathForTests(True);
    ClearCronZonesForTests;
    SetCronSystemTimeZoneForTests(nil);
  end;
end;

procedure TTestNamedTimeZones.FastPathPreservesBudget(const aExcluded: Integer);
var
  g: TGarbos;
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lCsv: string;
  lBase, lWalkUtc, lFastUtc: Int64;
  i, lWalkResult, lFastResult: Integer;
begin
  SetCronSystemTimeZoneForTests(TZoneAsSystemZone.Create(CreateCronZone('UTC', TCronFixedZoneSource.Create(0))));
  RegisterCronZoneForTests('Test/Budget', FakeZoneSource(0));
  try
    GC(lCron, TmaxCron.Create(ctPortable), g);
    lEvent := lCron.Add('budget');
    lEvent.EventPlan := '0 0 * * *';
    if aExcluded = 0 then lEvent.EventPlan := '0 0 31 2 *';
    lEvent.TimeZoneId := 'Test/Budget';
    lBase := ZoneMs(2026, 7, 1, 0);
    lCsv := '';
    for i := 1 to aExcluded do
    begin
      if lCsv <> '' then lCsv := lCsv + ',';
      lCsv := lCsv + FormatDateTime('yyyy-mm-dd', CronMsToDateTime(lBase + Int64(i) * cCronMsPerDay));
    end;
    lEvent.ExcludedDatesCsv := lCsv;
    SetMaxCronNamedFastPathForTests(False);
    lWalkResult := FindMaxCronNamedInstantForTests(lEvent, lBase, lWalkUtc);
    SetMaxCronNamedFastPathForTests(True);
    lFastResult := FindMaxCronNamedInstantForTests(lEvent, lBase, lFastUtc);
    Assert.AreEqual(lWalkResult, lFastResult, 'fallback preserves the original exclusion budget');
    if lWalkResult = 0 then Assert.AreEqual(lWalkUtc, lFastUtc, 'fallback instant');
    if aExcluded = 0 then Assert.AreEqual(1, lWalkResult, 'impossible February date has no occurrence')
    else Assert.AreEqual(0, lWalkResult, 'excluded-date corpus has a later occurrence');
  finally
    lEvent := nil;
    g.Clear;
    SetMaxCronNamedFastPathForTests(True);
    ClearCronZonesForTests;
    SetCronSystemTimeZoneForTests(nil);
  end;
end;

procedure TTestNamedTimeZones.FastPathMatchesWalk;
const
  cPlans: array[0..6] of string = ('* * * * * * *', '*/15 * * * *', '0 * * * *',
    '30 * * * *', '59 * * * * * 59', '0 0 * * *', '0 0 1 1 * 2030');
var
  g: TGarbos;
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lChanges: TArray<TZoneChange>;
  lChange: TZoneChange;
  lInitial, lBase, lWalkUtc, lFastUtc, lSeed: Int64;
  lZone, lSpring, lFall, lPattern, lSecond, lStep, i, lSide: Integer;
  lChecks: Int64;
  lWalkResult, lFastResult: Integer;
begin
  SetCronSystemTimeZoneForTests(TZoneAsSystemZone.Create(CreateCronZone('UTC', TCronFixedZoneSource.Create(0))));
  try
    GC(lCron, TmaxCron.Create(ctPortable), g);
    lEvent := lCron.Add('equivalence');
    {$IFDEF MAXCRON_LONG_TESTS}
    lStep := 1;
    {$ELSE}
    lStep := 600;
    if {$IFDEF FPC}SysUtils.{$ENDIF}GetEnvironmentVariable('MAXCRON_FULL_ZONE_PROPERTIES') = '1' then lStep := 1;
    {$ENDIF}
    lSeed := 20261118;
    lChecks := 0;
    for lZone := 0 to 6 do
    begin
      RegisterCronZoneForTests('Test/FastPath', FakeZoneSource(lZone));
      lEvent.TimeZoneId := 'Test/FastPath';
      lChanges := FakeZoneChanges(lZone, lInitial);
      for lSpring := 0 to 1 do
        for lFall := 0 to 3 do
          for lPattern := Low(cPlans) to High(cPlans) do
          begin
            lEvent.EventPlan := cPlans[lPattern];
            lEvent.DstSpringPolicy := TmaxCronDstSpringPolicy(lSpring);
            lEvent.DstFallPolicy := TmaxCronDstFallPolicy(lFall);
            for lChange in lChanges do
            begin
              lSecond := -10800;
              while lSecond <= 10800 + 128 do
              begin
                if lSecond <= 10800 then lBase := lChange.UtcMs + Int64(lSecond) * 1000
                else begin
                  lSeed := (lSeed * 48271) mod 2147483647;
                  lBase := lChange.UtcMs + (lSeed mod (120 * 86400) - 60 * 86400) * 1000;
                end;
                SetMaxCronNamedFastPathForTests(False);
                lWalkResult := FindMaxCronNamedInstantForTests(lEvent, lBase, lWalkUtc);
                SetMaxCronNamedFastPathForTests(True);
                lFastResult := FindMaxCronNamedInstantForTests(lEvent, lBase, lFastUtc);
                Assert.AreEqual(lWalkResult, lFastResult, 'fast/walk result');
                if lFastResult = 0 then Assert.AreEqual(lWalkUtc, lFastUtc, 'fast/walk instant');
                Inc(lChecks);
                if lSecond < 10800 then Inc(lSecond, lStep)
                else Inc(lSecond);
              end;
              // Exact +/-52 h guards, including their immediate second neighbours.
              for lSide := 0 to 1 do
                for i := -1 to 1 do
                begin
                  lBase := lChange.UtcMs + (2 * lSide - 1) * 2 * cCronZoneMaxAbsOffsetMs + Int64(i) * 1000;
                  SetMaxCronNamedFastPathForTests(False);
                  lWalkResult := FindMaxCronNamedInstantForTests(lEvent, lBase, lWalkUtc);
                  SetMaxCronNamedFastPathForTests(True);
                  lFastResult := FindMaxCronNamedInstantForTests(lEvent, lBase, lFastUtc);
                  Assert.AreEqual(lWalkResult, lFastResult, 'fast/walk guard result');
                  if lFastResult = 0 then Assert.AreEqual(lWalkUtc, lFastUtc, 'fast/walk guard instant');
                  Inc(lChecks);
                end;
            end;
          end;
      ClearCronZonesForTests;
    end;
    System.WriteLn('Fast path/walk comparisons: ', lChecks, ', seed=20261118, step=', lStep, ' seconds');
  finally
    lEvent := nil;
    g.Clear;
    SetMaxCronNamedFastPathForTests(True);
    ClearCronZonesForTests;
    SetCronSystemTimeZoneForTests(nil);
  end;
end;

procedure TNamedStore.Save(const aEvents: TArray<TMaxCronPersistedEvent>);
begin
  fStates := Copy(aEvents);
end;

function TNamedStore.TryLoad(out aEvents: TArray<TMaxCronPersistedEvent>): Boolean;
begin
  aEvents := Copy(fStates);
  Result := True;
end;

procedure TTestNamedTimeZones.TrollRegression;
var
  lEngine: string;
  g: TGarbos;
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lStore: IMaxCronScheduleStore;
  lStates: TArray<TMaxCronPersistedEvent>;
  lWallUs, lExpected: Int64;
  lCount, lCalls, lAttempts: Integer;
  lOld, lOldEngine: string;
begin
  lOld := {$IFDEF FPC}SysUtils.{$ENDIF}GetEnvironmentVariable('MAXCRON_TZDIR');
  lOldEngine := {$IFDEF FPC}SysUtils.{$ENDIF}GetEnvironmentVariable('MAXCRON_ENGINE');
  SetEnvironmentVariableW('MAXCRON_TZDIR', PChar(ZoneFixtureRoot));
  SetCronSystemTimeZoneForTests(TZoneAsSystemZone.Create(CreateCronZone('UTC', TCronFixedZoneSource.Create(0))));
  SetMaxCronWallClockHook(function: Int64 begin Result := lWallUs; end);
  try
    for lEngine in ['scan', 'heap', 'shadow'] do
    begin
      SetEnvironmentVariableW('MAXCRON_ENGINE', PChar(lEngine));
      lExpected := ZoneMs(2026, 10, 25, 1) - 1000;
      lWallUs := (lExpected - 1000) * 1000;
      lCount := 0;
      GC(lCron, TmaxCron.Create(ctPortable), g);
      lStore := TNamedStore.Create;
      lCron.ScheduleStore := lStore;
      lEvent := lCron.Add('troll', '* * * * * * *', procedure(aSender: IMaxCronEvent) begin Inc(lCount); end);
      lEvent.TimeZoneId := 'Antarctica/Troll';
      lEvent.InvokeMode := imMainThread;
      lEvent.Run;
      lWallUs := lExpected * 1000 + 200;
      lCron.TickAtUs(lWallUs);
      Assert.AreEqual(1, lCount, lEngine + ' Troll 00:59:59Z');
      Assert.AreEqual(ZoneMs(2026, 10, 25, 3), CronDateTimeToMs(lEvent.NextSchedule), lEngine);
      lCron.SaveScheduleState;
      Assert.IsTrue(lStore.TryLoad(lStates));
      Assert.IsFalse(lStates[0].NextScheduleNeedsResolve, lEngine);
      GetMaxCronNamedSearchForTests(lEvent, lCalls, lAttempts);
      Assert.IsTrue((lCalls <= 6) and (lAttempts <= 6), lEngine + ' Troll lookup bound');
      lEvent := nil;
      g.Clear;
    end;
  finally
    lEvent := nil;
    g.Clear;
    SetMaxCronWallClockHook(nil);
    SetCronSystemTimeZoneForTests(nil);
    SetEnvironmentVariableW('MAXCRON_TZDIR', PChar(lOld));
    SetEnvironmentVariableW('MAXCRON_ENGINE', PChar(lOldEngine));
  end;
end;

procedure TTestNamedTimeZones.GmtFixedOffsetIndependentOfDataRoot;
var
  lWithRoot: Boolean;
  lMonth: Int64;
  lOld, lRoot, lName, lError: string;
  lZone: ICronZoneRules;
  lPeriod: TCronZonePeriod;
  lUtc: Int64;
begin
  lOld := {$IFDEF FPC}SysUtils.{$ENDIF}GetEnvironmentVariable('MAXCRON_TZDIR');
  // A non-UTC host makes the public scheduler assertion distinguish GMT from LOCAL.
  SetCronSystemTimeZoneForTests(TZoneAsSystemZone.Create(CreateCronZone('host+02', TCronFixedZoneSource.Create(7200000))));
  try
    for lWithRoot in [False, True] do
    begin
      lRoot := '';
      if lWithRoot then lRoot := ZoneFixtureRoot;
      SetEnvironmentVariableW('MAXCRON_TZDIR', PChar(lRoot));
      Assert.IsTrue(TryResolveCronZone('GMT', lRoot, lZone, lName, lError), lError);
      Assert.AreEqual('GMT', lName);
      for lMonth in TArray<Int64>.Create(1, 7) do
      begin
        lUtc := ZoneMs(2026, lMonth, 2, 0);
        lPeriod := lZone.GetPeriod(lUtc);
        Assert.AreEqual(Int64(0), lPeriod.OffsetMs);
        Assert.AreEqual(cCronZoneUnboundedStart, lPeriod.StartUtcMs);
        Assert.AreEqual(cCronZoneUnboundedEnd, lPeriod.EndUtcMs);
        Assert.AreEqual(lUtc, lZone.UtcToLocalMs(lUtc));
        Assert.AreEqual(lUtc, lZone.MapLocal(lUtc).FirstUtcMs);
      end;
      // GMT midnight is 02:00 on the fixed UTC+02:00 system clock.
      CheckNext('GMT', '0 0 * * *', ZoneMs(2026, 1, 1, 23), ZoneMs(2026, 1, 2, 2), 0, 0);
    end;
  finally
    SetCronSystemTimeZoneForTests(nil);
    SetEnvironmentVariableW('MAXCRON_TZDIR', PChar(lOld));
  end;
end;

procedure TTestNamedTimeZones.ZoneDataRootOrder;
var
  lOldMax, lOldTz: string;
  lHadMax, lHadTz: Boolean;

  function ReadValue(const aName: PWideChar; out aPresent: Boolean): string;
  var
    lSize: DWORD;
  begin
    SetLastError(ERROR_SUCCESS);
    lSize := GetEnvironmentVariableW(aName, nil, 0);
    aPresent := GetLastError <> ERROR_ENVVAR_NOT_FOUND;
    SetLength(Result, lSize);
    if lSize <> 0 then
      SetLength(Result, GetEnvironmentVariableW(aName, PWideChar(Result), lSize));
  end;

  procedure RestoreValue(const aName: PWideChar; const aValue: string; const aPresent: Boolean);
  var
    c: WideChar;
  begin
    c := #0;
    if not aPresent then
      Assert.IsTrue(SetEnvironmentVariableW(aName, nil))
    else if aValue = '' then
      Assert.IsTrue(SetEnvironmentVariableW(aName, @c))
    else
      Assert.IsTrue(SetEnvironmentVariableW(aName, PWideChar(aValue)));
  end;

begin
  lOldMax := ReadValue('MAXCRON_TZDIR', lHadMax);
  lOldTz := ReadValue('TZDIR', lHadTz);
  try
    Assert.IsTrue(SetEnvironmentVariableW('TZDIR', 'tzdir-test-root'));
    Assert.IsTrue(SetEnvironmentVariableW('MAXCRON_TZDIR', 'maxcron-test-root'));
    Assert.AreEqual('maxcron-test-root', CronZoneDataRoot);
    Assert.IsTrue(SetEnvironmentVariableW('MAXCRON_TZDIR', nil));
    Assert.AreEqual('', CronZoneDataRoot);
    Assert.IsTrue(SetEnvironmentVariableW('TZDIR', nil));
    Assert.AreEqual('', CronZoneDataRoot);
  finally
    try
      RestoreValue('MAXCRON_TZDIR', lOldMax, lHadMax);
    finally
      RestoreValue('TZDIR', lOldTz, lHadTz);
    end;
  end;
end;

procedure TTestNamedTimeZones.NamedSetterAccepts;
var
  g: TGarbos;
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lOld: string;
begin
  lOld := {$IFDEF FPC}SysUtils.{$ENDIF}GetEnvironmentVariable('MAXCRON_TZDIR');
  SetEnvironmentVariableW('MAXCRON_TZDIR', PChar(ZoneFixtureRoot));
  try
    GC(lCron, TmaxCron.Create(ctPortable), g);
    lEvent := lCron.Add('named');
    lEvent.TimeZoneId := 'Europe/Warsaw';
    Assert.AreEqual('Europe/Warsaw', lEvent.TimeZoneId);
  finally
    g.Clear;
    SetEnvironmentVariableW('MAXCRON_TZDIR', PChar(lOld));
  end;
end;

procedure TTestNamedTimeZones.CheckNext(const aName, aPlan: string; const aBase, aExpected: Int64;
  const aSpring, aFall: Integer);
var
  d: Int64;
  g: TGarbos;
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lWallUs: Int64;
  lCount: Integer;
  lContext: string;
begin
  lWallUs := aBase * 1000;
  lCount := 0;
  lContext := Format('%s %s base=%d spring=%d fall=%d', [aName, aPlan, aBase, aSpring, aFall]);
  SetMaxCronWallClockHook(function: Int64 begin Result := lWallUs; end);
  try
    GC(lCron, TmaxCron.Create(ctPortable), g);
    lEvent := lCron.Add('policy', aPlan, procedure(aSender: IMaxCronEvent) begin Inc(lCount); end);
    lEvent.InvokeMode := imMainThread;
    lEvent.TimeZoneId := aName;
    lEvent.DstSpringPolicy := TmaxCronDstSpringPolicy(aSpring);
    lEvent.DstFallPolicy := TmaxCronDstFallPolicy(aFall);
    lEvent.Run;
    Assert.AreEqual(aExpected, CronDateTimeToMs(lEvent.NextSchedule), lContext);
    lCron.TickAtUs(aExpected * 1000 - 1);
    Assert.AreEqual(0, lCount, lContext + ' -1us');
    lCron.TickAtUs(aExpected * 1000);
    Assert.AreEqual(1, lCount, lContext + ' exact');
    for d in TArray<Int64>.Create(1, 499, 500, 999999) do
    begin
      lCron.TickAtUs(aExpected * 1000 + d);
      Assert.AreEqual(1, lCount, lContext + ' +' + IntToStr(d) + 'us');
    end;
  finally
    g.Clear;
    SetMaxCronWallClockHook(nil);
  end;
end;

procedure TTestNamedTimeZones.PoliciesAndPreciseBoundaries;
var
  lEngine: string;
  lFake: Boolean;
  i: Integer;
  lFall: Integer;
  lOld, lOldEngine: string;
  lBase, lExpected: Int64;
begin
  lOld := {$IFDEF FPC}SysUtils.{$ENDIF}GetEnvironmentVariable('MAXCRON_TZDIR');
  lOldEngine := {$IFDEF FPC}SysUtils.{$ENDIF}GetEnvironmentVariable('MAXCRON_ENGINE');
  SetEnvironmentVariableW('MAXCRON_TZDIR', PChar(ZoneFixtureRoot));
  SetCronSystemTimeZoneForTests(TZoneAsSystemZone.Create(CreateCronZone('UTC', TCronFixedZoneSource.Create(0))));
  try
    for lEngine in ['scan', 'heap', 'shadow'] do
    begin
      SetEnvironmentVariableW('MAXCRON_ENGINE', PChar(lEngine));
      for lFake in [False, True] do
      begin
        if lFake then
          for i := 0 to 4 do RegisterCronZoneForTests(cNames[i], FakeZoneSource(i));
        for lFall := 0 to 3 do
        begin
          lBase := ZoneMs(2026, 10, 25, 0);
          lExpected := lBase + 1800000;
          if lFall = Ord(TmaxCronDstFallPolicy.dfpRunOncePreferSecondInstance) then Inc(lExpected, 3600000);
          CheckNext(cNames[0], '30 2 * * *', lBase, lExpected, 0, lFall);
          lBase := ZoneMs(2026, 11, 1, 5);
          lExpected := lBase + 1800000;
          if lFall = Ord(TmaxCronDstFallPolicy.dfpRunOncePreferSecondInstance) then Inc(lExpected, 3600000);
          CheckNext(cNames[1], '30 1 * * *', lBase, lExpected, 0, lFall);
          lBase := ZoneMs(2026, 4, 4, 15);
          lExpected := lBase + 1800000;
          if lFall = Ord(TmaxCronDstFallPolicy.dfpRunOncePreferSecondInstance) then Inc(lExpected, 3600000);
          CheckNext(cNames[2], '30 2 * * *', lBase, lExpected, 0, lFall);
        end;
        CheckNext(cNames[0], '30 2 * * *', ZoneMs(2026, 3, 29, 0), ZoneMs(2026, 3, 30, 0, 30), 0, 0);
        CheckNext(cNames[0], '30 2 * * *', ZoneMs(2026, 3, 29, 0), ZoneMs(2026, 3, 29, 1), 1, 0);
        CheckNext(cNames[0], '0 2 * * *', ZoneMs(2026, 3, 29, 0), ZoneMs(2026, 3, 29, 1), 1, 0);
        CheckNext(cNames[1], '30 2 * * *', ZoneMs(2026, 3, 8, 6), ZoneMs(2026, 3, 9, 6, 30), 0, 0);
        CheckNext(cNames[1], '30 2 * * *', ZoneMs(2026, 3, 8, 6), ZoneMs(2026, 3, 8, 7), 1, 0);
        CheckNext(cNames[2], '30 2 * * *', ZoneMs(2026, 10, 3, 15), ZoneMs(2026, 10, 4, 15, 30), 0, 0);
        CheckNext(cNames[2], '30 2 * * *', ZoneMs(2026, 10, 3, 15), ZoneMs(2026, 10, 3, 16), 1, 0);
        CheckNext(cNames[3], '15 2 * * *', ZoneMs(2026, 10, 3, 15), ZoneMs(2026, 10, 4, 15, 15), 0, 0);
        CheckNext(cNames[3], '15 2 * * *', ZoneMs(2026, 10, 3, 15), ZoneMs(2026, 10, 3, 15, 30), 1, 0);
        CheckNext(cNames[4], '0 0 * * *', ZoneMs(2018, 11, 4, 2), ZoneMs(2018, 11, 4, 3), 1, 0);
        CheckNext(cNames[4], '30 23 * * *', ZoneMs(2019, 2, 17, 1), ZoneMs(2019, 2, 17, 2, 30), 0,
          Ord(TmaxCronDstFallPolicy.dfpRunOncePreferSecondInstance));
        ClearCronZonesForTests;
      end;
    end;
  finally
    ClearCronZonesForTests;
    SetCronSystemTimeZoneForTests(nil);
    SetEnvironmentVariableW('MAXCRON_TZDIR', PChar(lOld));
    SetEnvironmentVariableW('MAXCRON_ENGINE', PChar(lOldEngine));
  end;
end;

procedure TTestNamedTimeZones.GeneratedPolicyOrder;
var
  lEngine: string;
  k: Integer;
  lChange: TZoneChange;
  lSpring: Integer;
  lFall: Integer;
  lPattern: Integer;
  g: TGarbos;
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lExpected: TList<Int64>;
  lChanges: TArray<TZoneChange>;
  lMap: TCronLocalMapping;
  lInitial, lBase, lEnd, lLocal, lUtc, lLast, lWallUs: Int64;
  lOldEngine, lPlan, lContext: string;
  lCount, lExpectedCount, lStep: Integer;
begin
  lOldEngine := {$IFDEF FPC}SysUtils.{$ENDIF}GetEnvironmentVariable('MAXCRON_ENGINE');
  SetCronSystemTimeZoneForTests(TZoneAsSystemZone.Create(CreateCronZone('UTC', TCronFixedZoneSource.Create(0))));
  SetMaxCronWallClockHook(function: Int64 begin Result := lWallUs; end);
  try
    GC(lExpected, TList<Int64>.Create, g);
    for lEngine in ['scan', 'heap', 'shadow'] do
    begin
      SetEnvironmentVariableW('MAXCRON_ENGINE', PChar(lEngine));
      for k := 0 to 5 do
      begin
        lChanges := FakeZoneChanges(k, lInitial);
        RegisterCronZoneForTests(cNames[k], FakeZoneSource(k));
        for lChange in lChanges do
          for lSpring := 0 to 1 do
            for lFall := 0 to 3 do
              for lPattern := 0 to 4 do
              begin
                lStep := 900; lPlan := '*/15 * * * *';
                if lPattern = 0 then
                begin
                  lStep := 1; lPlan := '* * * * * * *';
                end;
                if lPattern = 2 then lPlan := '30 * * * *';
                if lPattern = 3 then lPlan := '0 0 * * *';
                if lPattern = 4 then
                  lPlan := '30 ' + IntToStr(((lChange.UtcMs + lChange.OffsetMs) div 3600000) mod 24) + ' * * *';
                lBase := lChange.UtcMs - 2 * 86400000;
                lEnd := lChange.UtcMs + 2 * 86400000;
                if (lPattern = 0) and ({$IFDEF FPC}SysUtils.{$ENDIF}GetEnvironmentVariable('MAXCRON_FULL_ZONE_PROPERTIES') <> '1') then
                begin
                  lBase := lChange.UtcMs - 2000; lEnd := lChange.UtcMs + 2000;
                end;
                lExpected.Clear;
                lLocal := ((lBase - cCronZoneMaxAbsOffsetMs) div 1000) * 1000;
                if lStep > 1 then lLocal := (lLocal div 900000) * 900000;
                while lLocal <= lEnd + cCronZoneMaxAbsOffsetMs do
                begin
                  if ((lPattern < 2) or ((lPattern = 2) and (lLocal mod 3600000 = 1800000)) or
                    ((lPattern = 3) and (lLocal mod 86400000 = 0)) or
                    ((lPattern = 4) and (lLocal mod 86400000 =
                      ((lChange.UtcMs + lChange.OffsetMs) div 3600000 mod 24) * 3600000 + 1800000))) then
                  begin
                    lMap := ReferenceMapping(lInitial, lChanges, lLocal);
                    if (lMap.Kind <> TCronLocalKind.clkGap) or (lSpring = 1) then
                    begin
                      lUtc := lMap.FirstUtcMs;
                      if (lMap.Kind = TCronLocalKind.clkOverlap) and
                        (lFall = Ord(TmaxCronDstFallPolicy.dfpRunOncePreferSecondInstance)) then lUtc := lMap.SecondUtcMs;
                      if (lUtc > lBase) and (lUtc <= lEnd) then lExpected.Add(lUtc);
                      if (lMap.Kind = TCronLocalKind.clkOverlap) and
                        (lFall = Ord(TmaxCronDstFallPolicy.dfpRunTwice)) and
                        (lMap.SecondUtcMs > lBase) and (lMap.SecondUtcMs <= lEnd) then lExpected.Add(lMap.SecondUtcMs);
                    end;
                  end;
                  Inc(lLocal, Int64(lStep) * 1000);
                end;
                lExpected.Sort;
                lWallUs := lBase * 1000;
                lCount := 0; lExpectedCount := 0; lLast := Low(Int64);
                lCron := TmaxCron.Create(ctPortable);
                try
                  lEvent := lCron.Add('generated', lPlan, procedure(aSender: IMaxCronEvent) begin Inc(lCount); end);
                  lEvent.TimeZoneId := cNames[k]; lEvent.InvokeMode := imMainThread;
                  lEvent.DstSpringPolicy := TmaxCronDstSpringPolicy(lSpring);
                  lEvent.DstFallPolicy := TmaxCronDstFallPolicy(lFall);
                  lEvent.Run;
                  for lUtc in lExpected do
                  begin
                    if lUtc = lLast then Continue;
                    lLast := lUtc;
                    lContext := Format('%s %s %s spring=%d fall=%d utc=%d',
                      [lEngine, cNames[k], lPlan, lSpring, lFall, lUtc]);
                    Assert.AreEqual(lUtc, CronDateTimeToMs(lEvent.NextSchedule), lContext);
                    lWallUs := lUtc * 1000 - 1; lCron.TickAtUs(lWallUs);
                    Assert.AreEqual(lExpectedCount, lCount, lContext + ' early');
                    Inc(lExpectedCount);
                    lWallUs := lUtc * 1000 + 200; lCron.TickAtUs(lWallUs);
                    Assert.AreEqual(lExpectedCount, lCount, lContext + ' due');
                  end;
                finally
                  lEvent := nil; lCron.Free;
                end;
              end;
      end;
    end;
  finally
    g.Clear;
    SetMaxCronWallClockHook(nil); SetCronSystemTimeZoneForTests(nil); ClearCronZonesForTests;
    SetEnvironmentVariableW('MAXCRON_ENGINE', PChar(lOldEngine));
  end;
end;

procedure TTestNamedTimeZones.HostRollback;
var
  lEngine: string;
  lTarget: Integer;
  lFall: Integer;
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lZone: ICronZoneRules;
  lWallUs, lUtc, lBase, lEnd: Int64;
  lCount, lExpected: Integer;
  lOldEngine: string;
begin
  lOldEngine := {$IFDEF FPC}SysUtils.{$ENDIF}GetEnvironmentVariable('MAXCRON_ENGINE');
  lZone := CreateCronZone('Europe/Warsaw', FakeZoneSource(0));
  SetCronSystemTimeZoneForTests(TZoneAsSystemZone.Create(lZone));
  RegisterCronZoneForTests('Europe/Warsaw', FakeZoneSource(0));
  RegisterCronZoneForTests('America/New_York', FakeZoneSource(1));
  SetMaxCronWallClockHook(function: Int64 begin Result := lWallUs; end);
  try
    for lEngine in ['scan', 'heap', 'shadow'] do
    begin
      SetEnvironmentVariableW('MAXCRON_ENGINE', PChar(lEngine));
      for lTarget := 0 to 2 do
      for lFall := 0 to 3 do
      begin
        lBase := ZoneMs(2026, 10, 24, 23, 59); lEnd := ZoneMs(2026, 10, 25, 2);
        lWallUs := lZone.UtcToLocalMs(lBase) * 1000; lCount := 0;
        lCron := TmaxCron.Create(ctPortable);
        try
          lEvent := lCron.Add('rollback', '*/15 * * * *', procedure(aSender: IMaxCronEvent) begin Inc(lCount); end);
          if lTarget = 0 then lEvent.TimeZoneId := 'Europe/Warsaw';
          if lTarget = 1 then lEvent.TimeZoneId := 'America/New_York';
          if lTarget = 2 then lEvent.TimeZoneId := 'Etc/UTC';
          lEvent.DstFallPolicy := TmaxCronDstFallPolicy(lFall);
          lEvent.InvokeMode := imMainThread; lEvent.Run;
          lUtc := lBase + 1000; lExpected := 0;
          while lUtc <= lEnd do
          begin
            if lUtc mod 900000 = 0 then
              if (lTarget > 0) or (lUtc = lEnd) or (lFall = Ord(TmaxCronDstFallPolicy.dfpRunTwice)) or
                ((lUtc < ZoneMs(2026, 10, 25, 1)) and (lFall <> Ord(TmaxCronDstFallPolicy.dfpRunOncePreferSecondInstance))) or
                ((lUtc >= ZoneMs(2026, 10, 25, 1)) and (lFall = Ord(TmaxCronDstFallPolicy.dfpRunOncePreferSecondInstance))) then Inc(lExpected);
            lWallUs := lZone.UtcToLocalMs(lUtc) * 1000 + 200;
            lCron.TickAtUs(lWallUs);
            Assert.AreEqual(lExpected, lCount, Format('%s fall=%d UTC=%d', [lEngine, lFall, lUtc]));
            Inc(lUtc, 1000);
          end;
        finally
          lEvent := nil; lCron.Free;
        end;
      end;
    end;
  finally
    SetMaxCronWallClockHook(nil); SetCronSystemTimeZoneForTests(nil); ClearCronZonesForTests;
    SetEnvironmentVariableW('MAXCRON_ENGINE', PChar(lOldEngine));
  end;
end;

procedure TTestNamedTimeZones.ResumeInsideHostOverlap;
var
  lFall: Int64;
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lZone: ICronZoneRules;
  lWallUs, lStart, lTrueUtc: Int64;
  lCount, lStep, lSecond, lExpected: Integer;
begin
  lZone := CreateCronZone('Europe/Warsaw', FakeZoneSource(0));
  SetCronSystemTimeZoneForTests(TZoneAsSystemZone.Create(lZone));
  RegisterCronZoneForTests('Europe/Warsaw', FakeZoneSource(0));
  SetMaxCronWallClockHook(function: Int64 begin Result := lWallUs; end);
  SetMaxCronUtcClockHook(function: Int64 begin Result := lTrueUtc * 1000; end);
  try
    lStart := ZoneMs(2026, 10, 25, 1);
    lStep := 1;
    for lFall in TArray<Int64>.Create(Ord(TmaxCronDstFallPolicy.dfpRunOncePreferSecondInstance),
      Ord(TmaxCronDstFallPolicy.dfpRunTwice)) do
    begin
      lSecond := 0;
      while lSecond < 3600 do
      begin
        lTrueUtc := lStart + Int64(lSecond) * 1000;
        lWallUs := lZone.UtcToLocalMs(lTrueUtc) * 1000;
        lCount := 0;
        lCron := TmaxCron.Create(ctPortable);
        try
          lCron.DefaultMisfireCatchUpLimit := 10000;
          lEvent := lCron.Add('resume', '*/15 2 * * *', procedure(aSender: IMaxCronEvent) begin Inc(lCount); end);
          lEvent.TimeZoneId := 'Europe/Warsaw';
          lEvent.DstFallPolicy := TmaxCronDstFallPolicy(lFall);
          lEvent.InvokeMode := imMainThread;
          lEvent.Run;
          // Only quarter-hours strictly after the true start remain.
          lExpected := (3599 - lSecond) div 900;
          lTrueUtc := ZoneMs(2026, 10, 25, 2);
          lWallUs := ZoneMs(2026, 10, 25, 3) * 1000;
          lCron.TickAtUtcUs(lTrueUtc * 1000);
          Assert.AreEqual(lExpected, lCount, Format('resume second=%d fall=%d count=%d',
            [lSecond, lFall, lCount]));
        finally
          lEvent := nil;
          lCron.Free;
        end;
        Inc(lSecond, lStep);
      end;
    end;
  finally
    SetMaxCronUtcClockHook(nil);
    SetMaxCronWallClockHook(nil);
    SetCronSystemTimeZoneForTests(nil);
    ClearCronZonesForTests;
  end;
end;

procedure TTestNamedTimeZones.RejectionAndPersistence;
var
  s: string;
  g: TGarbos;
  lCron, lRestored: TmaxCron;
  lEvent: IMaxCronEvent;
  lStore: IMaxCronScheduleStore;
  lStates: TArray<TMaxCronPersistedEvent>;
  lOld: string;
  lRaised: Boolean;
begin
  lOld := {$IFDEF FPC}SysUtils.{$ENDIF}GetEnvironmentVariable('MAXCRON_TZDIR');
  SetEnvironmentVariableW('MAXCRON_TZDIR', PChar(ZoneFixtureRoot));
  try
    GC(lCron, TmaxCron.Create(ctPortable), g); GC(lRestored, TmaxCron.Create(ctPortable), g);
    lStore := TNamedStore.Create;
    lCron.ScheduleStore := lStore;
    lRestored.ScheduleStore := lStore;
    lEvent := lCron.Add('persist'); lEvent.TimeZoneId := 'europe/WARSAW';
    Assert.AreEqual('Europe/Warsaw', lEvent.TimeZoneId);
    for s in ['Europe/Nowhere', 'Synthetic/Leap', 'Synthetic/Truncated', '../etc/passwd'] do
    begin
      lRaised := False;
      try
        lEvent.TimeZoneId := s;
      except
        on E: Exception do
        begin
          lRaised := True;
          Assert.IsTrue(Pos(s, E.Message) > 0, E.Message);
          if s = 'Synthetic/Leap' then Assert.IsTrue(Pos('leap-second', E.Message) > 0, E.Message);
        end;
      end;
      Assert.IsTrue(lRaised, s); Assert.AreEqual('Europe/Warsaw', lEvent.TimeZoneId);
    end;
    lEvent.TimeZoneId := 'US/Eastern';
    Assert.AreEqual(1, lCron.SaveScheduleState);
    Assert.AreEqual(1, lRestored.RestoreScheduleState);
    Assert.AreEqual('US/Eastern', lRestored.Snapshot[0].TimeZoneId);
    Assert.IsTrue(lStore.TryLoad(lStates));
    lStates[0].TimeZoneId := 'Europe/Nowhere';
    lStore.Save(lStates);
    lRaised := False;
    try
      lRestored.RestoreScheduleState;
    except
      on E: Exception do
      begin
        lRaised := True;
        Assert.IsTrue(Pos('Unknown timezone "Europe/Nowhere"', E.Message) > 0, E.Message);
      end;
    end;
    Assert.IsTrue(lRaised);
    lEvent.TimeZoneId := 'UTC+2:30'; Assert.AreEqual('UTC+02:30', lEvent.TimeZoneId);
    lEvent.TimeZoneId := 'z'; Assert.AreEqual('UTC', lEvent.TimeZoneId);
    lEvent.TimeZoneId := 'local'; Assert.AreEqual('LOCAL', lEvent.TimeZoneId);
  finally
    g.Clear;
    SetEnvironmentVariableW('MAXCRON_TZDIR', PChar(lOld));
  end;
end;

procedure TTestNamedTimeZones.CheckDenseTransition(const aName: string;
  const aTransition, aBefore, aAfter: Int64; const aSpring, aFall: Integer);
var
  g: TGarbos;
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lStart, lEnd, lUtc, lWallUs, lShift: Int64;
  lCount, lExpected, lCalls, lAttempts: Integer;
  lEligible: Boolean;
  lContext: string;
begin
  lShift := aBefore - aAfter;
  lStart := aTransition - 10000;
  lEnd := aTransition + 10000;
  if lShift > 0 then
  begin
    Dec(lStart, lShift);
    Inc(lEnd, lShift);
  end;
  lWallUs := (lStart - 1000) * 1000;
  lCount := 0;
  lExpected := 0;
  lContext := Format('N6 %s T=%d spring=%d fall=%d', [aName, aTransition, aSpring, aFall]);
  SetMaxCronWallClockHook(function: Int64 begin Result := lWallUs; end);
  try
    GC(lCron, TmaxCron.Create(ctPortable), g);
    lEvent := lCron.Add('dense', '* * * * * * *', procedure(aSender: IMaxCronEvent) begin Inc(lCount); end);
    lEvent.TimeZoneId := aName;
    lEvent.InvokeMode := imMainThread;
    lEvent.DstSpringPolicy := TmaxCronDstSpringPolicy(aSpring);
    lEvent.DstFallPolicy := TmaxCronDstFallPolicy(aFall);
    lEvent.Run;
    lUtc := lStart;
    while lUtc <= lEnd do
    begin
      lEligible := True;
      if lShift > 0 then
        case TmaxCronDstFallPolicy(aFall) of
          TmaxCronDstFallPolicy.dfpRunOnce, TmaxCronDstFallPolicy.dfpRunOncePreferFirstInstance:
            lEligible := (lUtc < aTransition) or (lUtc >= aTransition + lShift);
          TmaxCronDstFallPolicy.dfpRunOncePreferSecondInstance:
            lEligible := (lUtc < aTransition - lShift) or (lUtc >= aTransition);
        end;
      // Every wall second is observed, including periods where the policy suppresses fires.
      lWallUs := lUtc * 1000 + 200;
      lCron.TickAtUs(lWallUs);
      if lEligible then Inc(lExpected);
      Assert.AreEqual(lExpected, lCount, lContext + ' utc=' + IntToStr(lUtc));
      if aName = 'Antarctica/Troll' then
      begin
        GetMaxCronNamedSearchForTests(lEvent, lCalls, lAttempts);
        Assert.IsTrue((lCalls <= 6) and (lAttempts <= 6), lContext + ' lookup bound');
      end;
      Inc(lUtc, 1000);
    end;
  finally
    lEvent := nil;
    g.Clear;
    SetMaxCronWallClockHook(nil);
  end;
end;

procedure TTestNamedTimeZones.CheckNamedSequence(const aName, aPlan: string; const aBase: Int64;
  const aExpected: array of Int64; const aSpring, aFall: Integer);
var
  i: Integer;
  g: TGarbos;
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lWallUs: Int64;
  lCount: Integer;
begin
  lWallUs := aBase * 1000;
  lCount := 0;
  SetMaxCronWallClockHook(function: Int64 begin Result := lWallUs; end);
  try
    GC(lCron, TmaxCron.Create(ctPortable), g);
    lEvent := lCron.Add('sequence', aPlan, procedure(aSender: IMaxCronEvent) begin Inc(lCount); end);
    lEvent.TimeZoneId := aName;
    lEvent.InvokeMode := imMainThread;
    lEvent.DstSpringPolicy := TmaxCronDstSpringPolicy(aSpring);
    lEvent.DstFallPolicy := TmaxCronDstFallPolicy(aFall);
    lEvent.Run;
    for i := 0 to High(aExpected) do
    begin
      Assert.AreEqual(aExpected[i], CronDateTimeToMs(lEvent.NextSchedule), aName + ' ' + aPlan);
      lWallUs := aExpected[i] * 1000 - 1;
      lCron.TickAtUs(lWallUs);
      Assert.AreEqual<Integer>(Integer(i), lCount, aName + ' early');
      lWallUs := aExpected[i] * 1000 + 200;
      lCron.TickAtUs(lWallUs);
      Assert.AreEqual<Integer>(Integer(i) + 1, lCount, aName + ' due');
      lCron.TickAtUs(lWallUs + 500);
      Assert.AreEqual<Integer>(Integer(i) + 1, lCount, aName + ' duplicate');
    end;
  finally
    lEvent := nil;
    g.Clear;
    SetMaxCronWallClockHook(nil);
  end;
end;

procedure TTestNamedTimeZones.ShiftedWindowsN6;
var
  lEngine: string;
  lName: string;
  c: TZoneChange;
  lSpring: Integer;
  lFall: Integer;
  lOld, lOldEngine, lPath, lError: string;
  lSource: ICronZoneRuleSource;
  lChanges: TArray<TZoneChange>;
  lInitial, lBefore, lFrom, lTo, lExpected: Int64;
  lTickCount: Int64;
begin
  lTickCount := 0;
  lOld := {$IFDEF FPC}SysUtils.{$ENDIF}GetEnvironmentVariable('MAXCRON_TZDIR');
  lOldEngine := {$IFDEF FPC}SysUtils.{$ENDIF}GetEnvironmentVariable('MAXCRON_ENGINE');
  SetEnvironmentVariableW('MAXCRON_TZDIR', PChar(ZoneFixtureRoot));
  SetCronSystemTimeZoneForTests(TZoneAsSystemZone.Create(CreateCronZone('UTC', TCronFixedZoneSource.Create(0))));
  try
    for lEngine in ['scan', 'heap', 'shadow'] do
    begin
      SetEnvironmentVariableW('MAXCRON_ENGINE', PChar(lEngine));
      for lName in ['Antarctica/Troll', 'Australia/Lord_Howe', 'Europe/Warsaw',
        'America/New_York', 'Australia/Sydney', 'America/Sao_Paulo'] do
      begin
        lFrom := ZoneMs(2026, 1, 1, 0);
        lTo := ZoneMs(2028, 1, 1, 0);
        if lName = 'America/Sao_Paulo' then
        begin
          lFrom := ZoneMs(2018, 1, 1, 0);
          lTo := ZoneMs(2020, 1, 1, 0);
        end;
        Assert.IsTrue(TryLoadCronTzifFile(ZoneFixtureRoot, lName, lSource, lPath, lError), lError);
        ZoneSourceModel(lSource, lFrom, lTo, lInitial, lChanges);
        lBefore := lInitial;
        for c in lChanges do
        begin
          for lSpring := 0 to 1 do
            for lFall := 0 to 3 do
            begin
              CheckDenseTransition(lName, c.UtcMs, lBefore, c.OffsetMs, lSpring, lFall);
              Inc(lTickCount, 21);
              if lBefore > c.OffsetMs then Inc(lTickCount, 2 * (lBefore - c.OffsetMs) div 1000);
            end;
          lBefore := c.OffsetMs;
        end;
      end;
      for lSpring := 0 to 1 do
      begin
        lExpected := ZoneMs(2026, 3, 29, 23, 30);
        if lSpring = 1 then lExpected := ZoneMs(2026, 3, 29, 1);
        CheckNamedSequence('Antarctica/Troll', '30 1 * * *', ZoneMs(2026, 3, 29, 0),
          [lExpected], lSpring, 0);
        lExpected := ZoneMs(2026, 10, 4, 15, 15);
        if lSpring = 1 then lExpected := ZoneMs(2026, 10, 3, 15, 30);
        CheckNamedSequence('Australia/Lord_Howe', '15 2 * * *', ZoneMs(2026, 10, 3, 14),
          [lExpected], lSpring, 0);
      end;
      for lFall := 0 to 3 do
      begin
        if lFall = Ord(TmaxCronDstFallPolicy.dfpRunTwice) then
          CheckNamedSequence('Antarctica/Troll', '30 1 * * *', ZoneMs(2026, 10, 24, 22),
            [ZoneMs(2026, 10, 24, 23, 30), ZoneMs(2026, 10, 25, 1, 30)], 0, lFall)
        else
        begin
          lExpected := ZoneMs(2026, 10, 24, 23, 30);
          if lFall = Ord(TmaxCronDstFallPolicy.dfpRunOncePreferSecondInstance) then
            lExpected := ZoneMs(2026, 10, 25, 1, 30);
          CheckNamedSequence('Antarctica/Troll', '30 1 * * *', ZoneMs(2026, 10, 24, 22),
            [lExpected], 0, lFall);
        end;
        CheckNamedSequence('Australia/Lord_Howe', '15 2 * * *', ZoneMs(2026, 4, 4, 13),
          [ZoneMs(2026, 4, 4, 15, 45)], 0, lFall);
      end;
    end;
    System.Writeln('N6 dense tick assertions=', lTickCount);
  finally
    SetMaxCronWallClockHook(nil);
    SetCronSystemTimeZoneForTests(nil);
    ClearCronZonesForTests;
    SetEnvironmentVariableW('MAXCRON_TZDIR', PChar(lOld));
    SetEnvironmentVariableW('MAXCRON_ENGINE', PChar(lOldEngine));
  end;
end;


procedure TTestNamedTimeZones.NamedOracleFilters;
var
  g: TGarbos;
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lWallUs: Int64;
  lCalls, lAttempts: Integer;
begin
  lWallUs := ZoneMs(2026, 3, 27, 23, 59) * 1000;
  SetCronSystemTimeZoneForTests(TZoneAsSystemZone.Create(CreateCronZone('UTC', TCronFixedZoneSource.Create(0))));
  SetMaxCronWallClockHook(function: Int64 begin Result := lWallUs; end);
  try
    GC(lCron, TmaxCron.Create(ctPortable), g);
    lEvent := lCron.Add('filters');
    lEvent.EventPlan := '* * * * * * *';
    lEvent.TimeZoneId := 'Etc/UTC';
    lEvent.ValidFrom := CronMsToDateTime(ZoneMs(2026, 3, 28, 0));
    lEvent.ValidTo := CronMsToDateTime(ZoneMs(2026, 3, 31, 2));
    lEvent.WeekdaysOnly := True;
    lEvent.ExcludedDatesCsv := '2026-03-30';
    lEvent.BlackoutStartTime := 0;
    lEvent.BlackoutEndTime := EncodeTime(1, 0, 0, 0);
    lEvent.Run;
    Assert.AreEqual(ZoneMs(2026, 3, 31, 1), CronDateTimeToMs(lEvent.NextSchedule));
    GetMaxCronNamedSearchForTests(lEvent, lCalls, lAttempts);
    Assert.AreEqual(1, lCalls);
    Assert.IsTrue(lAttempts > lCalls, 'exclusion advances share the attempt budget');
    lEvent := lCron.Add('valid-to');
    lEvent.EventPlan := '* * * * * * *';
    lEvent.TimeZoneId := 'Etc/UTC';
    lEvent.ValidFrom := CronMsToDateTime(ZoneMs(2026, 3, 31, 0));
    lEvent.ValidTo := CronMsToDateTime(ZoneMs(2026, 3, 31, 0, 30));
    lEvent.BlackoutStartTime := 0;
    lEvent.BlackoutEndTime := EncodeTime(1, 0, 0, 0);
    lEvent.Run;
    Assert.IsFalse(lEvent.Enabled, 'no allowed occurrence inside validity');
  finally
    lEvent := nil;
    g.Clear;
    SetMaxCronWallClockHook(nil);
    SetCronSystemTimeZoneForTests(nil);
  end;
end;

end.

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
    [Test] procedure DisabledPlanProbe;
    [Test] procedure NearEpochProbeRules;
    [Test] procedure LifecycleUtcBases;
    [Test] procedure RestoreBetweenInstances;
    [TestCase('scan', 'scan')]
    [TestCase('heap', 'heap')]
    [TestCase('shadow', 'shadow')]
    procedure RestoreFiniteMatrix(const aEngine: string);
    [TestCase('scan', 'scan')]
    [TestCase('heap', 'heap')]
    [TestCase('shadow', 'shadow')]
    procedure RestoreIntervalBounds(const aEngine: string);
    [TestCase('scan', 'scan')]
    [TestCase('heap', 'heap')]
    [TestCase('shadow', 'shadow')]
    procedure GeneratedFake(const aEngine: string);
    [TestCase('scan', 'scan')]
    [TestCase('heap', 'heap')]
    [TestCase('shadow', 'shadow')]
    procedure GeneratedTzif(const aEngine: string);
    [Test] procedure HostZoneChange;
    [Test] procedure PassPeriodReuse;
    [Test] procedure PassPeriodScopes;
    [TestCase('scan', 'scan')]
    [TestCase('heap', 'heap')]
    [TestCase('shadow', 'shadow')]
    [TestCase('auto', 'auto')]
    procedure Curated(const aEngine: string);
    [TestCase('scan', 'scan')]
    [TestCase('heap', 'heap')]
    [TestCase('shadow', 'shadow')]
    procedure DeferredValidityDispatch(const aEngine: string);
    [Test] procedure ClockRollback;
    [Test] procedure ClockHookAndGap;
    [Test] procedure ProbePeriodsAndMappings;
    [Test] procedure ProbeSearchConsumers;
  end;

procedure RunOverlapGeneratedMatrix(const aEngine: string; const aTzifHosts: Boolean);

implementation

uses
  {$IFDEF FPC}
  Windows,
  Classes, DateUtils, Generics.Collections, Math, SysUtils, System.IOUtils,
  {$ELSE}
  System.Classes, System.DateUtils, System.Generics.Collections, System.IOUtils, System.Math, System.SysUtils,
  Winapi.Windows,
  {$ENDIF}
  AutoFree,
  maxCron, maxCron.Internal.TZif, maxCron.Plan, TestZoneFakes;

type
  TOverlapMemoryStore = class(TInterfacedObject, IMaxCronScheduleStore)
  private
    fStates: TArray<TMaxCronPersistedEvent>;
  public
    procedure Save(const aEvents: TArray<TMaxCronPersistedEvent>);
    function TryLoad(out aEvents: TArray<TMaxCronPersistedEvent>): Boolean;
  end;
  TProbeRulesSource = class(TInterfacedObject, ICronZoneRuleSource)
  private
    fRules: ICronZoneRules;
  public
    constructor Create(const aRules: ICronZoneRules);
    function GetRawPeriod(const aUtcMs: Int64): TCronZonePeriod;
  end;
  IPeriodReadCounter = interface
    ['{55B80CAD-556B-4D90-A5C5-BBA354B1F168}']
    function Reads: Integer;
    procedure Reset;
  end;
  TCountingPeriodSource = class(TInterfacedObject, ICronZoneRuleSource, IPeriodReadCounter)
  private
    fReads: Integer;
  public
    function GetRawPeriod(const aUtcMs: Int64): TCronZonePeriod;
    function Reads: Integer;
    procedure Reset;
  end;
  TDomainHostZone = class(TInterfacedObject, ICronTimeZone)
  public
    function ToUniversalTime(const aLocal: TDateTime; const aForceDaylight: Boolean): TDateTime;
    function ToLocalTime(const aUtc: TDateTime): TDateTime;
    function IsAmbiguousTime(const aLocal: TDateTime): Boolean;
    function IsInvalidTime(const aLocal: TDateTime): Boolean;
  end;
  TProbeKind = (pkCron, pkInterval);
  TOverlapScenario = record
    Id, Host, Zone, Plan: string;
    Kind: TProbeKind;
    Fall: TmaxCronDstFallPolicy;
    Spring: TmaxCronDstSpringPolicy;
    Misfire: TmaxCronMisfirePolicy;
    StartUtc, EndUtc: Int64;     // Run at StartUtc, ticks each second after it through EndUtc
    SleepFrom, SleepTo: Int64;   // no ticks in [SleepFrom, SleepTo) (0 = none)
    BlackoutStart, BlackoutEnd: TDateTime;
    Expected: TArray<Int64>;
  end;

  TProbePlanOracle = class
  public
    fPlan: TCronSchedulePlan;
    function First(const aFromLocalMs: Int64; out aLocalMs: Int64): TCronInstantSearchResult;
  end;

// The long build executes the original exhaustive loops and assertions. Defaults
// keep the curated regressions plus a stable sample (seed 20261118).
function FullOverlapQualification: Boolean;
begin
  Result := {$IFDEF MAXCRON_LONG_TESTS}True{$ELSE}False{$ENDIF};
end;

function OverlapSample(const aKey: Int64; const aModulus: Integer): Boolean;
begin
  Result := FullOverlapQualification or (((aKey * 251 + 20261118) mod 65521) mod aModulus = 0);
end;

function OverlapProbeMinute(const aKey: Int64): Int64;
begin
  Result := ((aKey mod 65521) * 251 + 20261118) mod 8641 - 4320;
end;

procedure TTestLocalOverlap.GeneratedFake(const aEngine: string);
begin
  RunOverlapGeneratedMatrix(aEngine, False);
end;

procedure TTestLocalOverlap.GeneratedTzif(const aEngine: string);
begin
  RunOverlapGeneratedMatrix(aEngine, True);
end;

procedure TOverlapMemoryStore.Save(const aEvents: TArray<TMaxCronPersistedEvent>);
begin
  fStates := Copy(aEvents);
end;

function TOverlapMemoryStore.TryLoad(out aEvents: TArray<TMaxCronPersistedEvent>): Boolean;
begin
  aEvents := Copy(fStates);
  Result := True;
end;

constructor TProbeRulesSource.Create(const aRules: ICronZoneRules);
begin
  inherited Create;
  fRules := aRules;
end;

function TProbeRulesSource.GetRawPeriod(const aUtcMs: Int64): TCronZonePeriod;
begin
  Result := fRules.GetPeriod(aUtcMs);
end;

function TCountingPeriodSource.GetRawPeriod(const aUtcMs: Int64): TCronZonePeriod;
begin
  Inc(fReads);
  Result.StartUtcMs := cCronZoneUnboundedStart;
  Result.EndUtcMs := cCronZoneUnboundedEnd;
  Result.OffsetMs := 3600000;
end;

function TCountingPeriodSource.Reads: Integer;
begin
  Result := fReads;
end;

procedure TCountingPeriodSource.Reset;
begin
  fReads := 0;
end;

function TDomainHostZone.ToUniversalTime(const aLocal: TDateTime; const aForceDaylight: Boolean): TDateTime;
begin
  Result := CronMsToDateTime(CronDateTimeToMs(aLocal) - 3600000);
end;

function TDomainHostZone.ToLocalTime(const aUtc: TDateTime): TDateTime;
begin
  // The nonnegative carrier domain leaves a max-offset margin at each edge.
  Assert.IsTrue(CronDateTimeToMs(aUtc) >= cCronZoneMaxAbsOffsetMs, 'probe oracle lower domain');
  Assert.IsTrue(CronDateTimeToMs(aUtc) <= Int64(2958466) * 86400000 - 1000 - cCronZoneMaxAbsOffsetMs,
    'probe oracle upper domain');
  Result := CronMsToDateTime(CronDateTimeToMs(aUtc) + 3600000);
end;

function TDomainHostZone.IsAmbiguousTime(const aLocal: TDateTime): Boolean;
begin
  Result := False;
end;

function TDomainHostZone.IsInvalidTime(const aLocal: TDateTime): Boolean;
begin
  Result := False;
end;

var
  gMatrixHost: ICronZoneRules;
  gMatrixInitial, gMatrixPass: Int64;
  gMatrixChanges: TArray<TZoneChange>;

function U(const aY, aMo, aD, aH, aMi: Word; const aSec: Word = 0): Int64;
begin
  Result := CronDateTimeToMs(EncodeDateTime(aY, aMo, aD, aH, aMi, aSec, 0));
end;

function Sc(const aId, aHost, aZone, aPlan: string; const aFall: TmaxCronDstFallPolicy;
  const aMisfire: TmaxCronMisfirePolicy; const aStart, aEnd: Int64;
  const aExpected: TArray<Int64>): TOverlapScenario;
begin
  Result := Default(TOverlapScenario);
  Result.Id := aId; Result.Host := aHost; Result.Zone := aZone; Result.Plan := aPlan;
  Result.Kind := pkCron; Result.Fall := aFall; Result.Spring := dspSkip; Result.Misfire := aMisfire;
  Result.StartUtc := aStart; Result.EndUtc := aEnd;
  Result.Expected := Copy(aExpected);
end;

function Every(const aFrom, aTo, aStepMin: Int64): TArray<Int64>;
var
  t: Int64;
begin
  Result := nil;
  t := aFrom;
  while t <= aTo do
  begin
    Result := Result + [t];
    if aStepMin = 0 then Inc(t, 1000) else Inc(t, aStepMin * 60000);
  end;
end;

procedure AppendOverlapCase(var aCases: TArray<TOverlapScenario>; const s: TOverlapScenario);
begin
  SetLength(aCases, Length(aCases) + 1);
  aCases[High(aCases)] := s;
end;

function OverlapCuratedCases: TArray<TOverlapScenario>;
var
  s: TOverlapScenario;
  lStart, lEnd: Int64;
begin
  Result := nil;
    // Warsaw-like host: 2026-10-25 01:00Z local 03:00 CEST -> 02:00 CET.
    // First pass of local [02:00,03:00) = 00:00Z-01:00Z, second pass = 01:00Z-02:00Z.
    lStart := U(2026, 10, 24, 23, 50); lEnd := U(2026, 10, 25, 2, 10);

    AppendOverlapCase(Result, Sc('a1-PS', 'Warsaw', 'LOCAL', '0 2 * * *', dfpRunOncePreferSecondInstance, mpCatchUpAll, lStart, lEnd,
      [U(2026, 10, 25, 1, 0)]));
    AppendOverlapCase(Result, Sc('a2-RT', 'Warsaw', 'LOCAL', '0 2 * * *', dfpRunTwice, mpCatchUpAll, lStart, lEnd,
      [U(2026, 10, 25, 0, 0), U(2026, 10, 25, 1, 0)]));
    AppendOverlapCase(Result, Sc('a3-PS-skip', 'Warsaw', 'LOCAL', '0 2 * * *', dfpRunOncePreferSecondInstance, mpSkip, lStart, lEnd,
      [U(2026, 10, 25, 1, 0)]));
    AppendOverlapCase(Result, Sc('a4-RT-skip', 'Warsaw', 'LOCAL', '0 2 * * *', dfpRunTwice, mpSkip, lStart, lEnd,
      [U(2026, 10, 25, 0, 0), U(2026, 10, 25, 1, 0)]));
    AppendOverlapCase(Result, Sc('a5-PS-once', 'Warsaw', 'LOCAL', '0 2 * * *', dfpRunOncePreferSecondInstance, mpFireOnceNow, lStart, lEnd,
      [U(2026, 10, 25, 1, 0)]));
    AppendOverlapCase(Result, Sc('a6-PS-ctl', 'Warsaw', 'LOCAL', '30 2 * * *', dfpRunOncePreferSecondInstance, mpCatchUpAll, lStart, lEnd,
      [U(2026, 10, 25, 1, 30)]));
    AppendOverlapCase(Result, Sc('a7-RT-ctl', 'Warsaw', 'LOCAL', '30 2 * * *', dfpRunTwice, mpCatchUpAll, lStart, lEnd,
      [U(2026, 10, 25, 0, 30), U(2026, 10, 25, 1, 30)]));
    AppendOverlapCase(Result, Sc('a8-RO-ctl', 'Warsaw', 'LOCAL', '0 2 * * *', dfpRunOnce, mpCatchUpAll, lStart, lEnd,
      [U(2026, 10, 25, 0, 0)]));

    AppendOverlapCase(Result, Sc('b1-PS', 'Warsaw', 'LOCAL', '10,40 2 * * *', dfpRunOncePreferSecondInstance, mpCatchUpAll, lStart, lEnd,
      [U(2026, 10, 25, 1, 10), U(2026, 10, 25, 1, 40)]));
    AppendOverlapCase(Result, Sc('b2-RT', 'Warsaw', 'LOCAL', '10,40 2 * * *', dfpRunTwice, mpCatchUpAll, lStart, lEnd,
      [U(2026, 10, 25, 0, 10), U(2026, 10, 25, 0, 40), U(2026, 10, 25, 1, 10), U(2026, 10, 25, 1, 40)]));
    AppendOverlapCase(Result, Sc('b3-RO-15', 'Warsaw', 'LOCAL', '*/15 * * * *', dfpRunOnce, mpCatchUpAll, lStart, lEnd,
      Every(U(2026, 10, 25, 0, 0), U(2026, 10, 25, 0, 45), 15) + [U(2026, 10, 25, 2, 0)]));
    AppendOverlapCase(Result, Sc('b4-PF-15', 'Warsaw', 'LOCAL', '*/15 * * * *', dfpRunOncePreferFirstInstance, mpCatchUpAll, lStart, lEnd,
      Every(U(2026, 10, 25, 0, 0), U(2026, 10, 25, 0, 45), 15) + [U(2026, 10, 25, 2, 0)]));
    AppendOverlapCase(Result, Sc('b5-PS-15', 'Warsaw', 'LOCAL', '*/15 * * * *', dfpRunOncePreferSecondInstance, mpCatchUpAll, lStart, lEnd,
      Every(U(2026, 10, 25, 1, 0), U(2026, 10, 25, 2, 0), 15)));
    AppendOverlapCase(Result, Sc('b6-RT-15', 'Warsaw', 'LOCAL', '*/15 * * * *', dfpRunTwice, mpCatchUpAll, lStart, lEnd,
      Every(U(2026, 10, 25, 0, 0), U(2026, 10, 25, 2, 0), 15)));
    AppendOverlapCase(Result, Sc('b7-RT-15-skip', 'Warsaw', 'LOCAL', '*/15 * * * *', dfpRunTwice, mpSkip, lStart, lEnd,
      Every(U(2026, 10, 25, 0, 0), U(2026, 10, 25, 2, 0), 15)));
    AppendOverlapCase(Result, Sc('b8-PS-15-skip', 'Warsaw', 'LOCAL', '*/15 * * * *', dfpRunOncePreferSecondInstance, mpSkip, lStart, lEnd,
      Every(U(2026, 10, 25, 1, 0), U(2026, 10, 25, 2, 0), 15)));

    lStart := U(2026, 10, 25, 1, 10);
    AppendOverlapCase(Result, Sc('b9-PS-start', 'Warsaw', 'LOCAL', '30 2 * * *', dfpRunOncePreferSecondInstance, mpCatchUpAll, lStart, lEnd,
      [U(2026, 10, 25, 1, 30)]));
    AppendOverlapCase(Result, Sc('b10-RT-start', 'Warsaw', 'LOCAL', '30 2 * * *', dfpRunTwice, mpCatchUpAll, lStart, lEnd,
      [U(2026, 10, 25, 1, 30)]));
    AppendOverlapCase(Result, Sc('b11-RO-start', 'Warsaw', 'LOCAL', '30 2 * * *', dfpRunOnce, mpCatchUpAll, lStart, lEnd,
      []));
    AppendOverlapCase(Result, Sc('b12-RO15-start', 'Warsaw', 'LOCAL', '*/15 * * * *', dfpRunOnce, mpCatchUpAll, lStart, lEnd,
      [U(2026, 10, 25, 2, 0)]));
    AppendOverlapCase(Result, Sc('b13-PS15-start', 'Warsaw', 'LOCAL', '*/15 * * * *', dfpRunOncePreferSecondInstance, mpCatchUpAll, lStart, lEnd,
      Every(U(2026, 10, 25, 1, 15), U(2026, 10, 25, 2, 0), 15)));

    lStart := U(2026, 10, 24, 23, 50);
    AppendOverlapCase(Result, Sc('c1-UTC', 'Warsaw', 'UTC', '30 1 * * *', dfpRunOnce, mpCatchUpAll, lStart, lEnd,
      [U(2026, 10, 25, 1, 30)]));
    AppendOverlapCase(Result, Sc('c2-UTC+05', 'Warsaw', 'UTC+05:00', '30 6 * * *', dfpRunOnce, mpCatchUpAll, lStart, lEnd,
      [U(2026, 10, 25, 1, 30)]));
    AppendOverlapCase(Result, Sc('c3-UTC-15', 'Warsaw', 'UTC', '*/15 * * * *', dfpRunOnce, mpCatchUpAll, lStart, lEnd,
      Every(U(2026, 10, 25, 0, 0), U(2026, 10, 25, 2, 0), 15)));
    AppendOverlapCase(Result, Sc('c4-UTC-15skip', 'Warsaw', 'UTC', '*/15 * * * *', dfpRunOnce, mpSkip, lStart, lEnd,
      Every(U(2026, 10, 25, 0, 0), U(2026, 10, 25, 2, 0), 15)));
    AppendOverlapCase(Result, Sc('c5-UTC-0030', 'Warsaw', 'UTC', '30 0 * * *', dfpRunOnce, mpCatchUpAll, lStart, lEnd,
      [U(2026, 10, 25, 0, 30)]));
    AppendOverlapCase(Result, Sc('c6-EtcUTC-15', 'Warsaw', 'Etc/UTC', '*/15 * * * *', dfpRunOnce, mpCatchUpAll, lStart, lEnd,
      Every(U(2026, 10, 25, 0, 0), U(2026, 10, 25, 2, 0), 15)));
    // every minute: count early and lost fires
    s := Sc('c7-UTC-1min', 'Warsaw', 'UTC', '* * * * *', dfpRunOnce, mpCatchUpAll, lStart, lEnd,
      Every(U(2026, 10, 24, 23, 51), U(2026, 10, 25, 2, 10), 1));
    AppendOverlapCase(Result, s);


    s := Sc('e1-RO15-cu', 'Warsaw', 'LOCAL', '*/15 * * * *', dfpRunOnce, mpCatchUpAll, U(2026, 10, 24, 23, 40), lEnd,
      [U(2026, 10, 24, 23, 45)] + Every(U(2026, 10, 25, 1, 20), U(2026, 10, 25, 1, 20) + 3000, 0) + [U(2026, 10, 25, 2, 0)]);
    s.SleepFrom := U(2026, 10, 24, 23, 50); s.SleepTo := U(2026, 10, 25, 1, 20); AppendOverlapCase(Result, s);
    s := Sc('e2-RO15-skip', 'Warsaw', 'LOCAL', '*/15 * * * *', dfpRunOnce, mpSkip, U(2026, 10, 24, 23, 40), lEnd,
      [U(2026, 10, 24, 23, 45), U(2026, 10, 25, 2, 0)]);
    s.SleepFrom := U(2026, 10, 24, 23, 50); s.SleepTo := U(2026, 10, 25, 1, 20); AppendOverlapCase(Result, s);
    s := Sc('e3-RO15-once', 'Warsaw', 'LOCAL', '*/15 * * * *', dfpRunOnce, mpFireOnceNow, U(2026, 10, 24, 23, 40), lEnd,
      [U(2026, 10, 24, 23, 45), U(2026, 10, 25, 1, 20), U(2026, 10, 25, 2, 0)]);
    s.SleepFrom := U(2026, 10, 24, 23, 50); s.SleepTo := U(2026, 10, 25, 1, 20); AppendOverlapCase(Result, s);
    s := Sc('e4-PS15-cu', 'Warsaw', 'LOCAL', '*/15 * * * *', dfpRunOncePreferSecondInstance, mpCatchUpAll, U(2026, 10, 24, 23, 40), lEnd,
      [U(2026, 10, 24, 23, 45)] + Every(U(2026, 10, 25, 1, 20), U(2026, 10, 25, 1, 20) + 1000, 0) + Every(U(2026, 10, 25, 1, 30), U(2026, 10, 25, 2, 0), 15));
    s.SleepFrom := U(2026, 10, 24, 23, 50); s.SleepTo := U(2026, 10, 25, 1, 20); AppendOverlapCase(Result, s);
    s := Sc('e5-UTC15-cu', 'Warsaw', 'UTC', '*/15 * * * *', dfpRunOnce, mpCatchUpAll, U(2026, 10, 24, 23, 40), lEnd,
      [U(2026, 10, 24, 23, 45)] + Every(U(2026, 10, 25, 1, 20), U(2026, 10, 25, 1, 20) + 5000, 0) + Every(U(2026, 10, 25, 1, 30), U(2026, 10, 25, 2, 0), 15));
    s.SleepFrom := U(2026, 10, 24, 23, 50); s.SleepTo := U(2026, 10, 25, 1, 20); AppendOverlapCase(Result, s);

    lStart := U(2026, 3, 29, 0, 50); lEnd := U(2026, 3, 29, 1, 10);
    s := Sc('f1-skip', 'Warsaw', 'LOCAL', '30 2 * * *', dfpRunOnce, mpCatchUpAll, lStart, lEnd, []); AppendOverlapCase(Result, s);
    s := Sc('f2-shift', 'Warsaw', 'LOCAL', '30 2 * * *', dfpRunOnce, mpCatchUpAll, lStart, lEnd, [U(2026, 3, 29, 1, 0)]);
    s.Spring := dspRunAtNextValidTime; AppendOverlapCase(Result, s);
    s := Sc('f3-shift-sec', 'Warsaw', 'LOCAL', '30 2 29 3 * 2026 30', dfpRunOnce, mpCatchUpAll, lStart, lEnd, [U(2026, 3, 29, 1, 0)]);
    s.Spring := dspRunAtNextValidTime; AppendOverlapCase(Result, s);
    s := Sc('f4-shift-15', 'Warsaw', 'LOCAL', '*/15 * * * *', dfpRunOnce, mpCatchUpAll, lStart, lEnd,
      [U(2026, 3, 29, 0, 45) + 15 * 60000]);
    s.Spring := dspRunAtNextValidTime; AppendOverlapCase(Result, s);
    // minute-step shift of the first allowed gap occurrence (02:30:40 -> 03:00:40) hides 03:00:10
    s := Sc('f6-shift-bo', 'Warsaw', 'LOCAL', '0,30 2,3 29 3 * 2026 10,40', dfpRunOnce, mpCatchUpAll, lStart, U(2026, 3, 29, 1, 31),
      [U(2026, 3, 29, 1, 0), U(2026, 3, 29, 1, 0, 10), U(2026, 3, 29, 1, 0, 40), U(2026, 3, 29, 1, 30, 10), U(2026, 3, 29, 1, 30, 40)]);
    s.Spring := dspRunAtNextValidTime; s.BlackoutStart := EncodeTime(2, 0, 0, 0); s.BlackoutEnd := EncodeTime(2, 30, 30, 0); AppendOverlapCase(Result, s);
    s := Sc('f5-UTC-15', 'Warsaw', 'UTC', '*/15 * * * *', dfpRunOnce, mpCatchUpAll, lStart, lEnd,
      Every(U(2026, 3, 29, 1, 0), U(2026, 3, 29, 1, 0), 15)); AppendOverlapCase(Result, s);

    lStart := U(2026, 4, 4, 14, 20); lEnd := U(2026, 4, 4, 15, 40);
    AppendOverlapCase(Result, Sc('g1-PS', 'LordHowe', 'LOCAL', '30 1 * * *', dfpRunOncePreferSecondInstance, mpCatchUpAll, lStart, lEnd,
      [U(2026, 4, 4, 15, 0)]));
    AppendOverlapCase(Result, Sc('g2-RT', 'LordHowe', 'LOCAL', '30 1 * * *', dfpRunTwice, mpCatchUpAll, lStart, lEnd,
      [U(2026, 4, 4, 14, 30), U(2026, 4, 4, 15, 0)]));
    AppendOverlapCase(Result, Sc('g3-UTC', 'LordHowe', 'UTC', '10 15 * * *', dfpRunOnce, mpCatchUpAll, lStart, lEnd,
      [U(2026, 4, 4, 15, 10)]));

    lStart := U(2026, 10, 24, 22, 50); lEnd := U(2026, 10, 25, 3, 10);
    AppendOverlapCase(Result, Sc('h1-PS', 'TwoHour', 'LOCAL', '0 1 * * *', dfpRunOncePreferSecondInstance, mpCatchUpAll, lStart, lEnd,
      [U(2026, 10, 25, 1, 0)]));
    AppendOverlapCase(Result, Sc('h2-PS-ctl', 'TwoHour', 'LOCAL', '30 2 * * *', dfpRunOncePreferSecondInstance, mpCatchUpAll, lStart, lEnd,
      [U(2026, 10, 25, 2, 30)]));
    AppendOverlapCase(Result, Sc('h3-PS-2dues', 'TwoHour', 'LOCAL', '0 1,2 * * *', dfpRunOncePreferSecondInstance, mpCatchUpAll, lStart, lEnd,
      [U(2026, 10, 25, 1, 0), U(2026, 10, 25, 2, 0)]));
    AppendOverlapCase(Result, Sc('h4-RT-2dues', 'TwoHour', 'LOCAL', '0 1,2 * * *', dfpRunTwice, mpCatchUpAll, lStart, lEnd,
      [U(2026, 10, 24, 23, 0), U(2026, 10, 25, 0, 0), U(2026, 10, 25, 1, 0), U(2026, 10, 25, 2, 0)]));
    AppendOverlapCase(Result, Sc('h5-UTC', 'TwoHour', 'UTC', '30 2 * * *', dfpRunOnce, mpCatchUpAll, lStart, lEnd,
      [U(2026, 10, 25, 2, 30)]));

    s := Sc('i1-int15', 'Warsaw', 'LOCAL', '', dfpRunOnce, mpCatchUpAll, U(2026, 10, 24, 23, 50), U(2026, 10, 25, 2, 10),
      Every(U(2026, 10, 25, 0, 5), U(2026, 10, 25, 2, 5), 15));
    s.Kind := pkInterval; AppendOverlapCase(Result, s);

end;

type
  TOverlapModelFire = record
    PassUtcMs, DueUtcMs, NextUtcMs: Int64;
  end;

function OverlapHostIndex(const aName: string): Integer;
begin
  if aName = 'Warsaw' then Exit(0);
  if aName = 'LordHowe' then Exit(3);
  if aName = 'TwoHour' then Exit(6);
  if aName = 'UTC' then Exit(-1);
  raise Exception.Create('Unknown overlap host: ' + aName);
end;

function OverlapHostRules(const aName: string): ICronZoneRules;
var
  lIndex: Integer;
begin
  if aName = 'Matrix' then Exit(gMatrixHost);
  lIndex := OverlapHostIndex(aName);
  if lIndex < 0 then Result := CreateCronZone('UTC host', TCronFixedZoneSource.Create(0))
  else Result := CreateCronZone(aName, FakeZoneSource(lIndex));
end;

function OverlapHostDisplayMs(const aName: string; const aUtcMs: Int64): Int64;
var
  lIndex: Integer;
  lOffset: Int64;
  lChanges: TArray<TZoneChange>;
  lChange: TZoneChange;
begin
  if aName = 'Matrix' then
  begin
    lOffset := gMatrixInitial;
    lChanges := gMatrixChanges;
  end else begin
    lIndex := OverlapHostIndex(aName);
    if lIndex < 0 then Exit(aUtcMs);
    lChanges := FakeZoneChanges(lIndex, lOffset);
  end;
  for lChange in lChanges do
    if lChange.UtcMs <= aUtcMs then lOffset := lChange.OffsetMs;
  Result := aUtcMs + lOffset;
end;

function OverlapDateBits(const aValue: TDateTime): UInt64;
begin
  Move(aValue, Result, SizeOf(Result));
end;

function OverlapModelInstances(const s: TOverlapScenario): TArray<Int64>;
var
  g: TGarbos;
  lPlan: TCronSchedulePlan;
  lValues: TList<Int64>;
  lChanges: TArray<TZoneChange>;
  lChange: TZoneChange;
  lMap: TCronLocalMapping;
  lInitial, lMinOffset, lMaxOffset, lCursor, lLocalMs, lEndLocalMs, lTimeMs, lUtcMs: Int64;
  lNext: TDateTime;
  lIndex, i, n: Integer;
  lExcluded: Boolean;
begin
  Result := nil;
  GC(lValues, TList<Int64>.Create, g);
  if s.Kind = pkInterval then
  begin
    lUtcMs := s.StartUtc + 900000;
    while lUtcMs <= s.EndUtc + 900000 do
    begin
      lValues.Add(lUtcMs);
      Inc(lUtcMs, 900000);
    end;
    Exit(lValues.ToArray);
  end;
  lIndex := -1;
  lInitial := 0;
  if ((s.Zone = 'LOCAL') and (s.Host = 'Matrix')) or (s.Zone = 'Test/MatrixHost') then
  begin
    lInitial := gMatrixInitial;
    lChanges := gMatrixChanges;
  end else if s.Zone = 'LOCAL' then lIndex := OverlapHostIndex(s.Host)
  else if s.Zone = 'Test/Warsaw' then lIndex := 0
  else if s.Zone = 'Test/LordHowe' then lIndex := 3
  else if s.Zone = 'Test/TwoHour' then lIndex := 6
  else if s.Zone = 'Test/NewYork' then lIndex := 1
  else if s.Zone = 'UTC+05:00' then lInitial := 18000000
  else if s.Zone = 'UTC+05:30' then lInitial := 19800000
  else if (s.Zone <> 'UTC') and (s.Zone <> 'Etc/UTC') then raise Exception.Create('Unknown model zone: ' + s.Zone);
  if lIndex >= 0 then lChanges := FakeZoneChanges(lIndex, lInitial);
  lMinOffset := lInitial;
  lMaxOffset := lInitial;
  for lChange in lChanges do
  begin
    lMinOffset := Min(lMinOffset, lChange.OffsetMs);
    lMaxOffset := Max(lMaxOffset, lChange.OffsetMs);
  end;
  GC(lPlan, TCronSchedulePlan.Create, g);
  lPlan.Parse(s.Plan);
  lCursor := s.StartUtc + lMinOffset - 1000;
  lEndLocalMs := s.EndUtc + lMaxOffset;
  for i := 0 to 1000000 do
  begin
    if not lPlan.FindNextScheduleDate(CronMsToDateTime(lCursor), lNext) then Break;
    lLocalMs := CronDateTimeToMs(lNext);
    Assert.IsTrue(lLocalMs > lCursor, 'reference enumeration advances');
    lCursor := lLocalMs;
    lTimeMs := lLocalMs mod cCronMsPerDay;
    lExcluded := False;
    if s.BlackoutStart <> s.BlackoutEnd then
    begin
      if s.BlackoutStart < s.BlackoutEnd then
        lExcluded := (lTimeMs >= CronDateTimeToMs(s.BlackoutStart)) and (lTimeMs < CronDateTimeToMs(s.BlackoutEnd))
      else lExcluded := (lTimeMs >= CronDateTimeToMs(s.BlackoutStart)) or (lTimeMs < CronDateTimeToMs(s.BlackoutEnd));
    end;
    if lExcluded then Continue;
    lMap := ReferenceMapping(lInitial, lChanges, lLocalMs);
    if (lMap.Kind <> clkGap) or (s.Spring = dspRunAtNextValidTime) then
    begin
      lUtcMs := lMap.FirstUtcMs;
      if (lMap.Kind = clkOverlap) and (s.Fall = dfpRunOncePreferSecondInstance) then lUtcMs := lMap.SecondUtcMs;
      if lUtcMs > s.StartUtc then lValues.Add(lUtcMs);
      if (lMap.Kind = clkOverlap) and (s.Fall = dfpRunTwice) and (lMap.SecondUtcMs > s.StartUtc) then
        lValues.Add(lMap.SecondUtcMs);
    end;
    if lLocalMs > lEndLocalMs then Break;
  end;
  lValues.Sort;
  SetLength(Result, lValues.Count);
  n := 0;
  for lUtcMs in lValues do
    if (n = 0) or (Result[n - 1] <> lUtcMs) then
    begin
      Result[n] := lUtcMs;
      Inc(n);
    end;
  SetLength(Result, n);
end;

function OverlapModelFires(const s: TOverlapScenario; const aInstances: TArray<Int64>): TArray<TOverlapModelFire>;
var
  g: TGarbos;
  lFires: TList<TOverlapModelFire>;
  lFire: TOverlapModelFire;
  lPass: Int64;
  lIndex, lLimit, lCount: Integer;
begin
  GC(lFires, TList<TOverlapModelFire>.Create, g);
  lIndex := 0;
  lPass := s.StartUtc + 1000;
  while lPass <= s.EndUtc do
  begin
    if lIndex >= Length(aInstances) then Break;
    if aInstances[lIndex] > lPass then lPass := aInstances[lIndex];
    if (s.SleepFrom <> 0) and (lPass >= s.SleepFrom) and (lPass < s.SleepTo) then lPass := s.SleepTo;
    if lPass > s.EndUtc then Break;
    if not ((s.SleepFrom <> 0) and (lPass >= s.SleepFrom) and (lPass < s.SleepTo)) then
    begin
      lLimit := 1;
      if s.Misfire = mpDefault then lLimit := 1000;
      lCount := 0;
      while (lIndex < Length(aInstances)) and (aInstances[lIndex] <= lPass) and (lCount < lLimit) do
      begin
        if (s.Misfire = mpSkip) and (lPass - aInstances[lIndex] >= 1000) then
        begin
          while (lIndex < Length(aInstances)) and (aInstances[lIndex] <= lPass) do Inc(lIndex);
          Break;
        end;
        lFire.PassUtcMs := lPass;
        lFire.DueUtcMs := aInstances[lIndex];
        Inc(lIndex);
        if s.Misfire = mpFireOnceNow then
          while (lIndex < Length(aInstances)) and (aInstances[lIndex] <= lPass) do Inc(lIndex);
        lFire.NextUtcMs := Low(Int64);
        if lIndex < Length(aInstances) then lFire.NextUtcMs := aInstances[lIndex];
        lFires.Add(lFire);
        Inc(lCount);
      end;
    end;
    Inc(lPass, 1000);
  end;
  Result := lFires.ToArray;
end;

function CheckOverlapScenario(const s: TOverlapScenario; const aCheckLiteral: Boolean): Boolean;
var
  g: TGarbos;
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lInstances: TArray<Int64>;
  lFires: TArray<TOverlapModelFire>;
  lFire: TOverlapModelFire;
  lUtcMs, lWallUs, lMonoUs, lExpectedNextMs: Int64;
  lCount, lFailures, i: Integer;
  lProc: TmaxCronNotifyProc;
begin
  lInstances := OverlapModelInstances(s);
  lFires := OverlapModelFires(s, lInstances);
  if aCheckLiteral then
  begin
    Assert.AreEqual(Length(s.Expected), Length(lFires), 'literal/model fire count: ' + s.Id);
    for i := 0 to High(s.Expected) do Assert.AreEqual(s.Expected[i], lFires[i].PassUtcMs, 'literal/model UTC: ' + s.Id);
  end;
  lUtcMs := s.StartUtc;
  lWallUs := OverlapHostDisplayMs(s.Host, lUtcMs) * 1000;
  lMonoUs := lUtcMs * 1000;
  lCount := 0;
  lFailures := 0;
  SetCronSystemTimeZoneForTests(TZoneAsSystemZone.Create(OverlapHostRules(s.Host)));
  SetMaxCronUtcClockHook(function: Int64 begin Result := lUtcMs * 1000; end);
  SetMaxCronWallClockHook(function: Int64 begin Result := lWallUs; end);
  SetMaxCronMonotonicClockHook(function: Int64 begin Result := lMonoUs; end);
  lProc := procedure(aSender: IMaxCronEvent)
    begin
      if lCount >= Length(lFires) then Inc(lFailures)
      else begin
        lFire := lFires[lCount];
        if lUtcMs <> lFire.PassUtcMs then
        begin
          Inc(lFailures);
          if lFailures <= 2 then System.WriteLn('OVERLAP_PASS ', s.Id, ' actual=', lUtcMs, ' expected=', lFire.PassUtcMs);
        end;
        if OverlapDateBits(aSender.LastExecution) <>
          OverlapDateBits(CronMsToDateTime(OverlapHostDisplayMs(s.Host, lFire.DueUtcMs))) then
        begin
          Inc(lFailures);
          if lFailures <= 2 then System.WriteLn('OVERLAP_LAST ', s.Id, ' actualMs=', CronDateTimeToMs(aSender.LastExecution),
            ' expectedMs=', OverlapHostDisplayMs(s.Host, lFire.DueUtcMs), ' actualBits=', OverlapDateBits(aSender.LastExecution),
            ' expectedBits=', OverlapDateBits(CronMsToDateTime(OverlapHostDisplayMs(s.Host, lFire.DueUtcMs))));
        end;
        lExpectedNextMs := 0;
        if lFire.NextUtcMs <> Low(Int64) then
        begin
          lExpectedNextMs := OverlapHostDisplayMs(s.Host, lFire.NextUtcMs);
          // Intervals display the monotonic deadline projected from this pass's
          // wall offset, including before a future host transition.
          if s.Kind = pkInterval then lExpectedNextMs := OverlapHostDisplayMs(s.Host, lUtcMs) + lFire.NextUtcMs - lUtcMs;
        end;
        if (lFire.NextUtcMs <> Low(Int64)) and aSender.Enabled and
          (OverlapDateBits(aSender.NextSchedule) <>
           OverlapDateBits(CronMsToDateTime(lExpectedNextMs))) then
        begin
          Inc(lFailures);
          if lFailures <= 2 then System.WriteLn('OVERLAP_NEXT ', s.Id, ' actualMs=', CronDateTimeToMs(aSender.NextSchedule),
            ' expectedMs=', lExpectedNextMs, ' actualBits=', OverlapDateBits(aSender.NextSchedule),
            ' expectedBits=', OverlapDateBits(CronMsToDateTime(lExpectedNextMs)));
        end;
      end;
      Inc(lCount);
    end;
  try
    GC(lCron, TmaxCron.Create(ctPortable), g);
    lCron.DefaultMisfireCatchUpLimit := 1000;
    if s.Kind = pkInterval then lEvent := lCron.AddInterval(s.Id, 900000, lProc)
    else begin
      lEvent := lCron.Add(s.Id, s.Plan, lProc);
      lEvent.TimeZoneId := s.Zone;
      lEvent.DstFallPolicy := s.Fall;
      lEvent.DstSpringPolicy := s.Spring;
      lEvent.BlackoutStartTime := s.BlackoutStart;
      lEvent.BlackoutEndTime := s.BlackoutEnd;
    end;
    lEvent.MisfirePolicy := s.Misfire;
    lEvent.InvokeMode := imMainThread;
    lEvent.Run;
    if Length(lInstances) > 0 then
      if (not lEvent.Enabled) or (OverlapDateBits(lEvent.NextSchedule) <>
        OverlapDateBits(CronMsToDateTime(OverlapHostDisplayMs(s.Host, lInstances[0])))) then
      begin
        Inc(lFailures);
        System.WriteLn('OVERLAP_INITIAL ', s.Id, ' actualMs=', CronDateTimeToMs(lEvent.NextSchedule),
          ' expectedMs=', OverlapHostDisplayMs(s.Host, lInstances[0]), ' actualBits=', OverlapDateBits(lEvent.NextSchedule),
          ' expectedBits=', OverlapDateBits(CronMsToDateTime(OverlapHostDisplayMs(s.Host, lInstances[0]))));
      end;
    lUtcMs := s.StartUtc + 1000;
    while lUtcMs <= s.EndUtc do
    begin
      if not ((s.SleepFrom <> 0) and (lUtcMs >= s.SleepFrom) and (lUtcMs < s.SleepTo)) then
      begin
        lWallUs := OverlapHostDisplayMs(s.Host, lUtcMs) * 1000 + 200;
        lMonoUs := lUtcMs * 1000 + 200;
        lCron.TickAtUtcUs(lUtcMs * 1000 + 200);
      end;
      Inc(lUtcMs, 1000);
    end;
    if lCount <> Length(lFires) then Inc(lFailures);
    Result := lFailures = 0;
    System.WriteLn('OVERLAP_CASE ', s.Id, ' pass=', Result, ' expected=', Length(lFires), ' actual=', lCount, ' errors=', lFailures);
  finally
    lProc := nil;
    lEvent := nil;
    g.Clear;
    SetMaxCronUtcClockHook(nil);
    SetMaxCronWallClockHook(nil);
    SetMaxCronMonotonicClockHook(nil);
    SetCronSystemTimeZoneForTests(nil);
  end;
end;

procedure TTestLocalOverlap.Curated(const aEngine: string);
var
  lCases: TArray<TOverlapScenario>;
  s: TOverlapScenario;
  lOldEngine: string;
  lFailures: Integer;
begin
  lOldEngine := {$IFDEF FPC}SysUtils.{$ENDIF}GetEnvironmentVariable('MAXCRON_ENGINE');
  SetEnvironmentVariableW('MAXCRON_ENGINE', PChar(aEngine));
  RegisterCronZoneForTests('Test/Warsaw', FakeZoneSource(0));
  RegisterCronZoneForTests('Test/LordHowe', FakeZoneSource(3));
  RegisterCronZoneForTests('Test/TwoHour', FakeZoneSource(6));
  RegisterCronZoneForTests('Test/NewYork', FakeZoneSource(1));
  lFailures := 0;
  try
    lCases := OverlapCuratedCases;
    for s in lCases do
      if not CheckOverlapScenario(s, True) then Inc(lFailures);
    System.WriteLn('OVERLAP_CURATED engine=', aEngine, ' cases=', Length(lCases), ' failed=', lFailures);
    Assert.AreEqual(0, lFailures, 'curated UTC decisions: ' + aEngine);
  finally
    ClearCronZonesForTests;
    SetEnvironmentVariableW('MAXCRON_ENGINE', PChar(lOldEngine));
  end;
end;

function DeferredField(const aRow, aName: string): string;
var
  lStart, lEnd: Integer;
  lKey: string;
begin
  lKey := '"' + aName + '": "';
  lStart := Pos(lKey, aRow);
  if lStart = 0 then raise Exception.Create('Missing deferred field: ' + aName);
  Inc(lStart, Length(lKey));
  lEnd := lStart;
  while (lEnd <= Length(aRow)) and (aRow[lEnd] <> '"') do Inc(lEnd);
  if lEnd > Length(aRow) then raise Exception.Create('Unterminated deferred field: ' + aName);
  Result := Copy(aRow, lStart, lEnd - lStart);
end;

procedure TTestLocalOverlap.DeferredValidityDispatch(const aEngine: string);
var
  g: TGarbos;
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lRows: TStringList;
  lRow, lOldEngine: string;
  lUtcUs, lWallUs, lExpectedUtc, lExpectedWall: Int64;
  lFires, lChecks, lFailures, lRowIndex, lEligible: Integer;
begin
  GC(lRows, TStringList.Create, g);
  lRows.LoadFromFile(TPath.Combine(ExtractFileDir(ZoneFixtureRoot), 'F1LocalOverlapDeferredRows.jsonl'));
  Assert.AreEqual(1584, lRows.Count, 'exact Q4 deferred corpus');
  lOldEngine := {$IFDEF FPC}SysUtils.{$ENDIF}GetEnvironmentVariable('MAXCRON_ENGINE');
  SetEnvironmentVariableW('MAXCRON_ENGINE', PChar(aEngine));
  SetCronSystemTimeZoneForTests(TZoneAsSystemZone.Create(CreateCronZone('Q4 host', FakeZoneSource(0))));
  SetMaxCronUtcClockHook(function: Int64 begin Result := lUtcUs; end);
  lUtcUs := (ZoneMs(2026, 10, 25, 0) - 3 * 3600000) * 1000;
  lWallUs := lUtcUs + 7200000000;
  SetMaxCronWallClockHook(function: Int64 begin Result := lWallUs; end);
  lChecks := 0;
  lFailures := 0; lEligible := 0;
  try
    GC(lCron, TmaxCron.Create(ctPortable), g);
    lEvent := lCron.Add('Q4 deferred dispatch');
    lEvent.EventPlan := '30 2 * * *';
    lEvent.InvokeMode := imMainThread;
    lEvent.OnScheduleProc := procedure(aSender: IMaxCronEvent) begin Inc(lFires); end;
    for lRow in lRows do
    begin
      if DeferredField(lRow, 'engine') <> aEngine then Continue;
      Inc(lEligible);
      lRowIndex := lEligible - 1;
      if not OverlapSample(lRowIndex, 17) then Continue;
      Assert.AreEqual('1', DeferredField(lRow, 'system'));
      Assert.AreEqual('0', DeferredField(lRow, 'event'));
      Assert.AreEqual('1', DeferredField(lRow, 'season'));
      lEvent.Stop;
      lUtcUs := (ZoneMs(2026, 10, 25, 0) - 3 * 3600000) * 1000;
      lWallUs := lUtcUs + 7200000000;
      lFires := 0;
      lEvent.DstFallPolicy := TmaxCronDstFallPolicy(StrToInt(DeferredField(lRow, 'fall')));
      lEvent.DstSpringPolicy := TmaxCronDstSpringPolicy(StrToInt(DeferredField(lRow, 'spring')));
      lEvent.ValidFrom := CronMsToDateTime(StrToInt64(DeferredField(lRow, 'from')));
      lEvent.ValidTo := CronMsToDateTime(StrToInt64(DeferredField(lRow, 'to')));
      lExpectedUtc := StrToInt64(DeferredField(lRow, 'expectedUtc'));
      lExpectedWall := StrToInt64(DeferredField(lRow, 'expectedWall'));
      lEvent.Run;
      if (not lEvent.Enabled) or (CronDateTimeToMs(lEvent.NextSchedule) <> lExpectedWall) then Inc(lFailures);
      lUtcUs := lExpectedUtc * 1000;
      lWallUs := lExpectedWall * 1000;
      lCron.TickAtUtcUs(lUtcUs);
      if (lFires <> 1) or (CronDateTimeToMs(lEvent.LastExecution) <> lExpectedWall) then Inc(lFailures);
      Inc(lChecks);
    end;
    Assert.AreEqual(528, lEligible, 'exact deferred rows per engine');
    Assert.IsTrue(lChecks > 0, 'nonempty deferred subset');
    if FullOverlapQualification then Assert.AreEqual(528, lChecks, 'full deferred rows per engine');
    System.WriteLn('DEFERRED_ROWS engine=', aEngine, ' rows=', lChecks, ' full=', FullOverlapQualification);
    Assert.AreEqual(0, lFailures, 'deferred search and dispatch: ' + aEngine);
  finally
    lEvent := nil;
    g.Clear;
    SetMaxCronUtcClockHook(nil);
    SetMaxCronWallClockHook(nil);
    SetCronSystemTimeZoneForTests(nil);
    SetEnvironmentVariableW('MAXCRON_ENGINE', PChar(lOldEngine));
  end;
end;

function TProbePlanOracle.First(const aFromLocalMs: Int64; out aLocalMs: Int64): TCronInstantSearchResult;
var
  lNext: TDateTime;
begin
  if not fPlan.FindNextScheduleDate(CronMsToDateTime(aFromLocalMs - 1000), lNext) then Exit(cisNotFound);
  aLocalMs := CronDateTimeToMs(lNext);
  Result := cisFound;
end;

procedure TTestLocalOverlap.DisabledPlanProbe;
var
  g: TGarbos;
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
begin
  SetCronSystemTimeZoneForTests(TDomainHostZone.Create);
  SetMaxCronWallClockHook(function: Int64 begin Result := 0; end);
  try
    GC(lCron, TmaxCron.Create(ctPortable), g);
    lEvent := lCron.Add('disabled epoch plan');
    lEvent.EventPlan := '0 2 * * *';
    Assert.IsFalse(lEvent.Enabled, 'assigning a plan does not enable an event');
    Assert.AreEqual(Int64(7200000), CronDateTimeToMs(lEvent.NextSchedule), 'HEAD at clock zero');
    Assert.IsTrue(OverlapDateBits(CronMsToDateTime(7200000)) = OverlapDateBits(lEvent.NextSchedule));
  finally
    lEvent := nil;
    g.Clear;
    SetMaxCronWallClockHook(nil);
    SetCronSystemTimeZoneForTests(nil);
  end;
end;

procedure TTestLocalOverlap.NearEpochProbeRules;
const
  cQueries: array[0..10] of Int64 = (-172800000, -93600001, -86400000, -1001, -1, 0, 1, 999, 1000, 93600000, 172800000);
var
  lDirect, lProbe: ICronZoneRules;
  lZone: ICronTimeZone;
  lMap: TCronLocalMapping;
  lQuery, lOffset: Int64;
  lIndex: Integer;
begin
  for lIndex := 0 to 8 do
  begin
    if lIndex <= 6 then
    begin
      lDirect := CreateCronZone('epoch fake', FakeZoneSource(lIndex));
      lZone := TZoneOnlyTimeZone.Create(lDirect);
    end else if lIndex = 7 then
    begin
      lZone := CreateCronOsLocalTimeZoneForTests;
      lDirect := (lZone as ICronTimeZoneRules).GetRules;
    end else begin
      lZone := TDomainHostZone.Create;
      lDirect := CreateCronZone('bounded domain', TCronFixedZoneSource.Create(3600000));
    end;
    lProbe := CreateCronProbeZoneForTests(lZone);
    for lQuery in cQueries do
    begin
      lOffset := lDirect.GetPeriod(lQuery).OffsetMs;
      Assert.AreEqual(lOffset, lProbe.GetPeriod(lQuery).OffsetMs, 'epoch offset');
      Assert.AreEqual(lQuery + lOffset, lProbe.UtcToLocalMs(lQuery), 'epoch forward');
      lMap := lProbe.MapLocal(lQuery);
      Assert.AreEqual(Ord(clkUnique), Ord(lMap.Kind), 'epoch unique');
      Assert.AreEqual(lQuery - lOffset, lMap.FirstUtcMs, 'epoch inverse');
      Assert.AreEqual(lMap.FirstUtcMs, lMap.SecondUtcMs);
    end;
    // Both unbounded rule edges must extend a representable oracle offset.
    Assert.IsTrue(Abs(lProbe.GetPeriod(cCronZoneUnboundedStart).OffsetMs) <= cCronZoneMaxAbsOffsetMs);
    Assert.IsTrue(Abs(lProbe.GetPeriod(cCronZoneUnboundedEnd - 1).OffsetMs) <= cCronZoneMaxAbsOffsetMs);
  end;
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
  if FullOverlapQualification or ({$IFDEF FPC}SysUtils.{$ENDIF}GetEnvironmentVariable('MAXCRON_FULL_ZONE_PROPERTIES') = '1') then lStep := 1;
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
        if (lStep > 1) and (lMinute = 0) then
          lQuery := lChange.UtcMs + OverlapProbeMinute(lChange.UtcMs div 60000 + lIndex) * 60000;
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
  lCron: TmaxCron;
  lDirectEvent, lProbeEvent: IMaxCronEvent;
  lDirectDue, lProbeDue: Int64;
  lDirectResult, lProbeResult: Integer;
  lFallPolicy: TmaxCronDstFallPolicy;
  lDirect, lProbe: ICronZoneRules;
  lChanges: TArray<TZoneChange>;
  lChange: TZoneChange;
  lInitial, lQuery, lExpected, lActual, lChecks: Int64;
  lIndex, lSpring, lFall, lMinute, lStep, lPattern, lCalls: Integer;
  lExpectedResult, lActualResult: TCronInstantSearchResult;
begin
  GC(lOracle, TProbePlanOracle.Create, g);
  GC(lOracle.fPlan, TCronSchedulePlan.Create, g);
  lStep := 4320;
  if FullOverlapQualification or ({$IFDEF FPC}SysUtils.{$ENDIF}GetEnvironmentVariable('MAXCRON_FULL_ZONE_PROPERTIES') = '1') then lStep := 1;
  GC(lCron, TmaxCron.Create(ctPortable), g);
  lDirectEvent := lCron.Add('probe direct consumer');
  lProbeEvent := lCron.Add('probe consumer');
  lChecks := 0;
  try
  for lIndex := 0 to 6 do
  begin
    lDirect := CreateCronZone('direct', FakeZoneSource(lIndex));
    lProbe := CreateCronProbeZoneForTests(TZoneOnlyTimeZone.Create(lDirect));
    lChanges := FakeZoneChanges(lIndex, lInitial);
    RegisterCronZoneForTests('Test/ConsumerDirect', TProbeRulesSource.Create(lDirect));
    RegisterCronZoneForTests('Test/ConsumerProbe', TProbeRulesSource.Create(lProbe));
    // Resolve a fresh identity on each zone; the events remain disabled.
    lDirectEvent.TimeZoneId := 'UTC'; lProbeEvent.TimeZoneId := 'UTC';
    lDirectEvent.TimeZoneId := 'Test/ConsumerDirect'; lProbeEvent.TimeZoneId := 'Test/ConsumerProbe';
    for lPattern := Low(cPlans) to High(cPlans) do
    begin
      lOracle.fPlan.Parse(cPlans[lPattern]);
      lDirectEvent.EventPlan := cPlans[lPattern];
      lProbeEvent.EventPlan := cPlans[lPattern];
      for lSpring := 0 to 1 do
        for lFall := 0 to 2 do
          for lChange in lChanges do
          begin
            lMinute := -4320;
            while lMinute <= 4320 do
            begin
              lQuery := lChange.UtcMs + Int64(lMinute) * 60000;
              if (lStep > 1) and (lMinute = 0) then
                lQuery := lChange.UtcMs + OverlapProbeMinute(lChange.UtcMs div 60000 +
                  ((lIndex * 7 + lPattern) * 2 + lSpring) * 3 + lFall) * 60000;
              lExpectedResult := CronZoneFindNextInstant(lDirect, lQuery, lSpring <> 0,
                TCronFallChoice(lFall), lOracle.First, lExpected, lCalls);
              lActualResult := CronZoneFindNextInstant(lProbe, lQuery, lSpring <> 0,
                TCronFallChoice(lFall), lOracle.First, lActual, lCalls);
              Assert.AreEqual(Ord(lExpectedResult), Ord(lActualResult), 'direct/probe walk result');
              if lExpectedResult = cisFound then Assert.AreEqual(lExpected, lActual, 'direct/probe walk instant');
              lFallPolicy := dfpRunOnce;
              case TCronFallChoice(lFall) of
                cfcSecond: lFallPolicy := dfpRunOncePreferSecondInstance;
                cfcBoth: lFallPolicy := dfpRunTwice;
              end;
              lDirectEvent.DstSpringPolicy := TmaxCronDstSpringPolicy(lSpring);
              lProbeEvent.DstSpringPolicy := TmaxCronDstSpringPolicy(lSpring);
              lDirectEvent.DstFallPolicy := lFallPolicy; lProbeEvent.DstFallPolicy := lFallPolicy;
              lDirectResult := FindMaxCronNamedInstantForTests(lDirectEvent, lQuery, lDirectDue);
              lProbeResult := FindMaxCronNamedInstantForTests(lProbeEvent, lQuery, lProbeDue);
              Assert.AreEqual(lDirectResult, lProbeResult, 'direct/probe FindNextDueUtc result');
              if lExpectedResult = cisFound then
              begin
                Assert.AreEqual(lExpected, lDirectDue, 'direct wrapper/walk instant');
                Assert.AreEqual(lExpected, lProbeDue, 'probe wrapper/walk instant');
              end;
              Inc(lChecks);
              Inc(lMinute, lStep);
            end;
          end;
    end;
  end;
  System.WriteLn('Probe/direct walk and FindNextDueUtc comparisons: ', lChecks, ', minute step=', lStep);
  finally
    lDirectEvent := nil; lProbeEvent := nil;
    g.Clear; ClearCronZonesForTests;
  end;
end;

procedure TTestLocalOverlap.LifecycleUtcBases;
const
  cZones: array[0..5] of string = ('LOCAL','UTC','UTC+05:30','Test/Warsaw','Test/NewYork','Etc/UTC');
var
  g: TGarbos;
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lInstances: TArray<Int64>;
  s: TOverlapScenario;
  lUtcMs: Int64;
  lEngine, lOldEngine: string;
  z, f, a: Integer;
begin
  lOldEngine := {$IFDEF FPC}SysUtils.{$ENDIF}GetEnvironmentVariable('MAXCRON_ENGINE');
  RegisterCronZoneForTests('Test/Warsaw', FakeZoneSource(0));
  RegisterCronZoneForTests('Test/NewYork', FakeZoneSource(1));
  SetCronSystemTimeZoneForTests(TZoneAsSystemZone.Create(CreateCronZone('lifecycle host', FakeZoneSource(0))));
  SetMaxCronUtcClockHook(function: Int64 begin Result := lUtcMs * 1000; end);
  SetMaxCronWallClockHook(function: Int64 begin Result := CronSystemZoneRules.UtcToLocalMs(lUtcMs) * 1000; end);
  try
    for lEngine in ['scan','heap','shadow','auto'] do
    begin
      SetEnvironmentVariableW('MAXCRON_ENGINE',PChar(lEngine));
      for z := 0 to High(cZones) do for f := 0 to 3 do for a := 0 to 4 do
      begin
        lUtcMs := U(2026,10,24,23,0);
        GC(lCron, TmaxCron.Create(ctPortable), g);
        lEvent := lCron.Add('lifecycle');
        lEvent.EventPlan := '*/15 * * * *'; lEvent.TimeZoneId := cZones[z];
        lEvent.DstFallPolicy := TmaxCronDstFallPolicy(f);
        lEvent.Run;
        if a = 1 then lEvent.Enabled := False;
        lUtcMs := U(2026,10,25,1,10);
        case a of
          0: lEvent.Run;
          1: lEvent.Enabled := True;
          2: begin lEvent.EventPlan := '*/5 * * * *'; lEvent.EventPlan := '*/15 * * * *'; end;
          3: lEvent.DstFallPolicy := TmaxCronDstFallPolicy(f);
          4: begin lEvent.TimeZoneId := 'UTC+01:00'; lEvent.TimeZoneId := cZones[z]; end;
        end;
        s := Sc('lifecycle', 'Warsaw', cZones[z], '*/15 * * * *', TmaxCronDstFallPolicy(f),
          mpCatchUpAll, lUtcMs, lUtcMs+7200000, []);
        lInstances := OverlapModelInstances(s);
        Assert.IsTrue(Length(lInstances)>0);
        Assert.IsTrue(lEvent.Enabled);
        Assert.AreEqual(OverlapHostDisplayMs('Warsaw',lInstances[0]), CronDateTimeToMs(lEvent.NextSchedule),
          Format('lifecycle engine=%s zone=%s fall=%d action=%d',[lEngine,cZones[z],f,a]));
        lEvent := nil; g.Clear;
      end;
    end;
  finally
    lEvent := nil; g.Clear;
    SetMaxCronWallClockHook(nil); SetMaxCronUtcClockHook(nil); SetCronSystemTimeZoneForTests(nil); ClearCronZonesForTests;
    SetEnvironmentVariableW('MAXCRON_ENGINE',PChar(lOldEngine));
  end;
end;

procedure TTestLocalOverlap.RestoreFiniteMatrix(const aEngine: string);
const
  cZones: array[0..3] of string = ('LOCAL', 'UTC', 'UTC+05:30', 'Test/RestoreFinite');
  cReviewerKeys: array[0..11] of string = (
    'scan/RunOnce/FireOnceNow', 'scan/RunOnce/CatchUpAll',
    'scan/PreferFirst/FireOnceNow', 'scan/PreferFirst/CatchUpAll',
    'heap/RunOnce/FireOnceNow', 'heap/RunOnce/CatchUpAll',
    'heap/PreferFirst/FireOnceNow', 'heap/PreferFirst/CatchUpAll',
    'shadow/RunOnce/FireOnceNow', 'shadow/RunOnce/CatchUpAll',
    'shadow/PreferFirst/FireOnceNow', 'shadow/PreferFirst/CatchUpAll');
var
  lCron, lRestored: TmaxCron;
  lEvent: IMaxCronEvent;
  lStore: IMaxCronScheduleStore;
  lStates: TArray<TMaxCronPersistedEvent>;
  lDues, lPasses: TArray<Int64>;
  lFirst, lSecond, lNow, lValidWall, lExpectedLast, lObservedLast: Int64;
  lFailures, lChecks, lCases, lFires, lExpected, lDueIndex, lDueCount: Integer;
  lLimit, lSavedCount, z, f, m, t, b, v, h, i, lFiredIndex: Integer;
  lEnabled, lAllowed, lLocalZone, lReviewerCase, lReviewerFound: Boolean;
  lReviewerKeys: TArray<string>;
  lReviewerKey, lRequiredKey, lSelectedKey: string;
  lRequiredCount: Integer;
  lPlan, lContext, lFirstFailure, lOldEngine: string;

  procedure Check(const aCondition: Boolean; const aField: string);
  begin
    Inc(lChecks);
    if not aCondition then
    begin
      Inc(lFailures);
      if lFirstFailure = '' then lFirstFailure := lContext + ' ' + aField;
    end;
  end;

begin
  lOldEngine := {$IFDEF FPC}SysUtils.{$ENDIF}GetEnvironmentVariable('MAXCRON_ENGINE');
  SetEnvironmentVariableW('MAXCRON_ENGINE', PChar(aEngine));
  SetCronSystemTimeZoneForTests(TZoneAsSystemZone.Create(CreateCronZone('restore host', FakeZoneSource(0))));
  RegisterCronZoneForTests('Test/RestoreFinite', FakeZoneSource(0));
  lFirst := U(2026, 10, 25, 0, 30);
  lSecond := lFirst + 3600000;
  lValidWall := lFirst + 7200000;
  SetMaxCronUtcClockHook(function: Int64 begin Result := lNow * 1000; end);
  lFailures := 0; lChecks := 0; lCases := 0; lFirstFailure := '';
  lReviewerKeys := nil;
  try
    for z := 0 to High(cZones) do for f := 0 to 3 do for m := 0 to 2 do
      for t := 0 to 2 do for b := 0 to 1 do for v := 0 to 7 do for h := 0 to 1 do
      begin
        lLocalZone := (z = 0) or (z = 3);
        if (h = 1) and ((v = 7) or (t = 0) or (lLocalZone and (f <> Ord(dfpRunTwice)))) then Continue;
        lReviewerCase := (z = 0) and
          (TmaxCronDstFallPolicy(f) in [dfpRunOnce, dfpRunOncePreferFirstInstance]) and
          (TmaxCronMisfirePolicy(m + 1) in [mpFireOnceNow, mpCatchUpAll]) and
          (t = 1) and (b = 0) and (v = 0) and (h = 0);
        // All twelve reviewer cases: three engines x first/PreferFirst x
        // fire-once/catch-up, finite LOCAL saved before and restored between.
        if not lReviewerCase and
          not OverlapSample((((((z * 4 + f) * 3 + m) * 3 + t) * 2 + b) * 8 + v) * 2 + h, 47) then Continue;
        if lReviewerCase then
        begin
          lReviewerKey := aEngine + '/RunOnce/';
          if TmaxCronDstFallPolicy(f) = dfpRunOncePreferFirstInstance then lReviewerKey := aEngine + '/PreferFirst/';
          if TmaxCronMisfirePolicy(m + 1) = mpFireOnceNow then lReviewerKey := lReviewerKey + 'FireOnceNow'
          else lReviewerKey := lReviewerKey + 'CatchUpAll';
          lReviewerKeys := lReviewerKeys + [lReviewerKey];
        end;
        lContext := Format('engine=%s zone=%s fall=%d misfire=%d restore=%d bounded=%d variant=%d history=%d',
          [aEngine, cZones[z], f, m, t, b, v, h]);
        Inc(lCases);
        lNow := lFirst - 1000;
        lStore := TOverlapMemoryStore.Create;
        lCron := TmaxCron.Create(ctPortable); lRestored := nil;
        try
          lCron.ScheduleStore := lStore;
          lEvent := lCron.Add('finite restore');
          if lLocalZone then lPlan := '30 2' else if z = 1 then lPlan := '30 0,1' else lPlan := '0 6,7';
          if b = 0 then lPlan := lPlan + ' 25 10 * 2026' else lPlan := lPlan + ' * * * *';
          lLimit := 0;
          if (v = 1) or (v = 6) then lLimit := 1;
          lEvent.EventPlan := lPlan + ' 0 ' + IntToStr(lLimit);
          lEvent.TimeZoneId := cZones[z];
          lEvent.DstFallPolicy := TmaxCronDstFallPolicy(f);
          lEvent.MisfirePolicy := TmaxCronMisfirePolicy(m + 1);
          lEvent.InvokeMode := imMainThread;
          if b = 1 then lEvent.ValidTo := CronMsToDateTime(lValidWall);
          lEvent.Run;
          if h = 1 then
          begin
            lNow := lFirst;
            lCron.TickAtUtcUs(lNow * 1000);
          end;
          Check(lCron.SaveScheduleState = 1, 'saved count');
          Check(lStore.TryLoad(lStates), 'load saved record');
          lSavedCount := h;
          if v = 1 then lSavedCount := 1;
          lStates[0].NumOfExecutionsPerformed := lSavedCount;
          lStates[0].Enabled := v <> 2;
          if v = 3 then
          begin
            lStates[0].ValidFrom := CronMsToDateTime(lValidWall);
            lStates[0].ValidTo := CronMsToDateTime(lValidWall);
          end;
          if v = 4 then lStates[0].ValidTo := CronMsToDateTime(lValidWall - 1000);
          if v = 5 then lStates[0].ValidFrom := CronMsToDateTime(lValidWall + 1000);
          if v = 7 then lStates[0].NextSchedule := 0;
          lStore.Save(lStates);
          case t of
            0: lNow := lFirst - 1000;
            1: lNow := lSecond - 600000;
          else lNow := lSecond + 600000;
          end;
          lRestored := TmaxCron.Create(ctPortable);
          lRestored.ScheduleStore := lStore;
          Check(lRestored.RestoreScheduleState = 1, 'restored count');
          lEvent := lRestored.Snapshot[0];
          lEnabled := (v <> 2) and (v <> 4) and (v <> 5) and
            ((lLimit = 0) or (lSavedCount < lLimit));
          lDues := nil;
          if lEnabled then
          begin
            if (h = 0) and ((not lLocalZone) or (f <> Ord(dfpRunOncePreferSecondInstance))) then
              lDues := lDues + [lFirst];
            if (not lLocalZone) or (f = Ord(dfpRunTwice)) or (f = Ord(dfpRunOncePreferSecondInstance)) then
              lDues := lDues + [lSecond];
          end;
          if v = 7 then
            // Without a saved due, Run/Reset semantics select only true future
            // instances. A bootstrap is correct only on this fallback path.
            while (Length(lDues) > 0) and (lDues[0] <= lNow) do Delete(lDues, 0, 1);
          lDueCount := Length(lDues);
          if v = 7 then lEnabled := lDueCount > 0;
          Check(lEvent.Enabled = lEnabled, 'enabled before resume pass');
          if lDueCount > 0 then
            Check(CronDateTimeToMs(lEvent.NextSchedule) = lValidWall, 'saved canonical host display');
          lFires := 0; lExpected := 0; lDueIndex := 0; lExpectedLast := 0; lObservedLast := 0;
          lEvent.OnScheduleProc := procedure(aSender: IMaxCronEvent)
            begin Inc(lFires); lObservedLast := CronDateTimeToMs(aSender.LastExecution); end;
          SetLength(lPasses, 4);
          lPasses[0] := lNow;
          lPasses[1] := Max(lPasses[0] + 1000, lFirst);
          lPasses[2] := Max(lPasses[1] + 1000, lSecond);
          lPasses[3] := lPasses[2] + 1000;
          for i := 0 to High(lPasses) do
          begin
            lNow := lPasses[i];
            if (lDueIndex < lDueCount) and (lDues[lDueIndex] <= lNow) and
              ((lLimit = 0) or (lSavedCount + lExpected < lLimit)) then
            begin
              lFiredIndex := lDueIndex;
              lAllowed := (m <> 0) or (lNow - lDues[lDueIndex] < 1000);
              if lAllowed then
              begin
                Inc(lExpected);
                lExpectedLast := lDues[lFiredIndex] + 7200000;
                if lDues[lFiredIndex] >= U(2026, 10, 25, 1, 0) then Dec(lExpectedLast, 3600000);
              end;
              Inc(lDueIndex);
              if m <> 2 then
                while (lDueIndex < lDueCount) and (lDues[lDueIndex] <= lNow) do Inc(lDueIndex);
            end;
            lRestored.TickAtUtcUs(lNow * 1000);
            Check(lFires = lExpected, Format('pass=%d expected fires=%d actual=%d', [i, lExpected, lFires]));
            if lExpected > 0 then Check(lObservedLast = lExpectedLast, 'last executed instance display');
          end;
        finally
          lEvent := nil; lRestored.Free; lCron.Free; lStore := nil;
        end;
      end;
  finally
    SetMaxCronUtcClockHook(nil); SetCronSystemTimeZoneForTests(nil); ClearCronZonesForTests;
    SetEnvironmentVariableW('MAXCRON_ENGINE', PChar(lOldEngine));
  end;
  // Each engine invocation asserts its four fully qualified keys; the three
  // committed engine cases therefore assert all twelve reviewer scenarios.
  Assert.AreEqual(4, Integer(Length(lReviewerKeys)), 'all first/PreferFirst reviewer rows must execute: ' + aEngine);
  lRequiredCount := 0;
  for lRequiredKey in cReviewerKeys do
    if Pos(aEngine + '/', lRequiredKey) = 1 then
    begin
      Inc(lRequiredCount);
      lReviewerFound := False;
      for lSelectedKey in lReviewerKeys do
        if lSelectedKey = lRequiredKey then lReviewerFound := True;
      Assert.IsTrue(lReviewerFound, 'missing named reviewer row: ' + lRequiredKey);
      System.WriteLn('REVIEWER_RESTORE_CASE ', lRequiredKey);
    end;
  if (aEngine = 'scan') or (aEngine = 'heap') or (aEngine = 'shadow') then
    Assert.AreEqual(4, lRequiredCount, 'four named reviewer rows for every committed engine');
  System.WriteLn(Format('RESTORE_FINITE_MATRIX engine=%s cases=%d checks=%d failures=%d first=%s',
    [aEngine, lCases, lChecks, lFailures, lFirstFailure]));
  Assert.AreEqual(0, lFailures, lFirstFailure);
end;

procedure TTestLocalOverlap.RestoreIntervalBounds(const aEngine: string);
var
  lCron, lRestored: TmaxCron;
  lEvent: IMaxCronEvent;
  lStore: IMaxCronScheduleStore;
  lStates: TArray<TMaxCronPersistedEvent>;
  lWallUs, lMonoUs, lStart: Int64;
  lMode, lPolicy, lVariant, lFires, lExpected, lFailures, lCases: Integer;
  lEnabled: Boolean;
  lPlan, lOldEngine, lFirstFailure: string;
begin
  lOldEngine := {$IFDEF FPC}SysUtils.{$ENDIF}GetEnvironmentVariable('MAXCRON_ENGINE');
  SetEnvironmentVariableW('MAXCRON_ENGINE', PChar(aEngine));
  lStart := U(2026, 7, 1, 12, 0) * 1000;
  SetMaxCronWallClockHook(function: Int64 begin Result := lWallUs; end);
  SetMaxCronMonotonicClockHook(function: Int64 begin Result := lMonoUs; end);
  lFailures := 0; lCases := 0; lFirstFailure := '';
  try
    for lMode := 0 to 1 do for lPolicy := 0 to 2 do for lVariant := 0 to 5 do
    begin
      Inc(lCases);
      lWallUs := lStart; lMonoUs := 10000000;
      lStore := TOverlapMemoryStore.Create;
      lCron := TmaxCron.Create(ctPortable); lRestored := nil;
      try
        lCron.ScheduleStore := lStore;
        lEvent := lCron.Add('interval saved bound');
        lPlan := '@every 1s';
        if lMode = 1 then lPlan := lPlan + ' fixed-delay';
        lEvent.EventPlan := lPlan + ' limit 1';
        lEvent.MisfirePolicy := TmaxCronMisfirePolicy(lPolicy + 1);
        lEvent.InvokeMode := imMainThread;
        lEvent.ValidTo := CronInstantUsToDateTime(lStart + 1000000);
        lEvent.Run; lCron.SaveScheduleState; lStore.TryLoad(lStates);
        if lVariant = 1 then lStates[0].NumOfExecutionsPerformed := 1;
        if lVariant = 2 then lStates[0].Enabled := False;
        if lVariant = 3 then lStates[0].ValidTo := CronInstantUsToDateTime(lStart + 999000);
        if lVariant = 4 then lStates[0].ValidFrom := CronInstantUsToDateTime(lStart + 1001000);
        if lVariant = 5 then lStates[0].ValidFrom := lStates[0].ValidTo;
        lStore.Save(lStates);
        lWallUs := lStart + 1500000; lMonoUs := 90000000;
        lRestored := TmaxCron.Create(ctPortable); lRestored.ScheduleStore := lStore;
        lRestored.RestoreScheduleState;
        lEvent := lRestored.Snapshot[0]; lFires := 0;
        lEvent.OnScheduleProc := procedure(aSender: IMaxCronEvent) begin Inc(lFires); end;
        lEnabled := (lVariant = 0) or (lVariant = 5);
        lExpected := Ord(lEnabled);
        if lEvent.Enabled <> lEnabled then
        begin
          Inc(lFailures);
          if lFirstFailure = '' then lFirstFailure := Format('interval mode=%d policy=%d variant=%d enabled',
            [lMode, lPolicy, lVariant]);
        end;
        lRestored.TickAtUs(lWallUs);
        if lFires <> lExpected then
        begin
          Inc(lFailures);
          if lFirstFailure = '' then lFirstFailure := Format('interval mode=%d policy=%d variant=%d callbacks',
            [lMode, lPolicy, lVariant]);
        end;
      finally
        lEvent := nil; lRestored.Free; lCron.Free; lStore := nil;
      end;
    end;
  finally
    SetMaxCronWallClockHook(nil); SetMaxCronMonotonicClockHook(nil);
    SetEnvironmentVariableW('MAXCRON_ENGINE', PChar(lOldEngine));
  end;
  System.WriteLn(Format('RESTORE_INTERVAL_MATRIX engine=%s cases=%d failures=%d first=%s',
    [aEngine, lCases, lFailures, lFirstFailure]));
  Assert.AreEqual(0, lFailures, lFirstFailure);
end;

procedure TTestLocalOverlap.RestoreBetweenInstances;
var
  g: TGarbos;
  lCron, lRestored: TmaxCron;
  lEvent: IMaxCronEvent;
  lStore: IMaxCronScheduleStore;
  lStates: TArray<TMaxCronPersistedEvent>;
  lUtcMs: Int64;
  lFires: Integer;
  lEngine, lOldEngine: string;
begin
  lOldEngine := {$IFDEF FPC}SysUtils.{$ENDIF}GetEnvironmentVariable('MAXCRON_ENGINE');
  SetCronSystemTimeZoneForTests(TZoneAsSystemZone.Create(CreateCronZone('restore host', FakeZoneSource(0))));
  SetMaxCronUtcClockHook(function: Int64 begin Result := lUtcMs*1000; end);
  SetMaxCronWallClockHook(function: Int64 begin Result := CronSystemZoneRules.UtcToLocalMs(lUtcMs) * 1000; end);
  try
    for lEngine in ['scan','heap','shadow','auto'] do
    begin
      SetEnvironmentVariableW('MAXCRON_ENGINE',PChar(lEngine));
      lUtcMs := U(2026,10,24,23,59);
      lStore := TOverlapMemoryStore.Create;
      GC(lCron,TmaxCron.Create(ctPortable),g);
      lCron.ScheduleStore := lStore;
      lEvent := lCron.Add('restore-twice'); lEvent.EventPlan := '0 2 * * *';
      lEvent.DstFallPolicy := dfpRunTwice; lEvent.InvokeMode := imMainThread;
      lEvent.Run;
      lCron.TickAtUtcUs(U(2026,10,25,0,0)*1000);
      Assert.AreEqual(1,lCron.SaveScheduleState);
      Assert.IsTrue(lStore.TryLoad(lStates));
      Assert.AreEqual(CronDateTimeToMs(lStates[0].LastExecution),CronDateTimeToMs(lStates[0].NextSchedule));
      lUtcMs := U(2026,10,25,0,30);
      GC(lRestored,TmaxCron.Create(ctPortable),g); lRestored.ScheduleStore := lStore;
      Assert.AreEqual(1,lRestored.RestoreScheduleState);
      lEvent := lRestored.Snapshot[0]; lFires := 0;
      lEvent.OnScheduleProc := procedure(aSender: IMaxCronEvent) begin Inc(lFires); end;
      lRestored.TickAtUtcUs(U(2026,10,25,1,0)*1000-1);
      Assert.AreEqual(0,lFires);
      lRestored.TickAtUtcUs(U(2026,10,25,1,0)*1000);
      Assert.AreEqual(1,lFires);
      Assert.AreEqual(U(2026,10,25,2,0),CronDateTimeToMs(lEvent.LastExecution));
      lEvent := nil; lStore := nil; g.Clear;
    end;
  finally
    lEvent := nil; lStore := nil; g.Clear;
    SetMaxCronWallClockHook(nil); SetMaxCronUtcClockHook(nil); SetCronSystemTimeZoneForTests(nil);
    SetEnvironmentVariableW('MAXCRON_ENGINE',PChar(lOldEngine));
  end;
end;

procedure TTestLocalOverlap.PassPeriodScopes;
var
  lSource: ICronZoneRuleSource;
  lCounter: IPeriodReadCounter;
  lCounted: ICronZoneRules;
  lZones: array[0..5] of ICronZoneRules;
  lExpected: array[0..5, 0..5] of TCronZonePeriod;
  lChanges: TArray<TZoneChange>;
  lQueries: array[0..5] of Int64;
  lPeriod: TCronZonePeriod;
  lInitial: Int64;
  i, j: Integer;
begin
  // Establish expected raw periods outside any memo, then cross both edges,
  // move backwards and exceed the four-entry capacity inside one pass.
  for i := 0 to High(lZones) do
  begin
    lZones[i] := CreateCronZone('memo boundary', FakeZoneSource(i));
    lChanges := FakeZoneChanges(i, lInitial);
    for j := 0 to 5 do
    begin
      lQueries[j] := lChanges[j div 3].UtcMs + (j mod 3) - 1;
      lExpected[i, j] := lZones[i].GetPeriod(lQueries[j]);
    end;
  end;
  CronBeginZonePeriodMemo;
  try
    for i := High(lZones) downto 0 do
    begin
      lChanges := FakeZoneChanges(i, lInitial);
      for j := 5 downto 0 do
      begin
        lQueries[j] := lChanges[j div 3].UtcMs + (j mod 3) - 1;
        lPeriod := lZones[i].GetPeriod(lQueries[j]);
        Assert.AreEqual(lExpected[i, j].StartUtcMs, lPeriod.StartUtcMs);
        Assert.AreEqual(lExpected[i, j].EndUtcMs, lPeriod.EndUtcMs);
        Assert.AreEqual(lExpected[i, j].OffsetMs, lPeriod.OffsetMs);
      end;
    end;
    lSource := TCountingPeriodSource.Create;
    Assert.IsTrue(Supports(lSource, IPeriodReadCounter, lCounter));
    lCounted := CreateCronZone('memo nesting', lSource);
    lCounter.Reset;
    lCounted.GetPeriod(0);
    Assert.AreEqual(1, lCounter.Reads);
    CronBeginZonePeriodMemo;
    try
      lCounted.GetPeriod(0);
      Assert.AreEqual(2, lCounter.Reads, 'nested pass owns a fresh memo');
    finally
      CronEndZonePeriodMemo;
    end;
    lCounted.GetPeriod(0);
    Assert.AreEqual(2, lCounter.Reads, 'outer pass memo survives nesting');
  finally
    CronEndZonePeriodMemo;
  end;
  lCounted.GetPeriod(0);
  Assert.AreEqual(3, lCounter.Reads, 'memo never escapes its pass');
end;

procedure TTestLocalOverlap.PassPeriodReuse;
var
  g: TGarbos;
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lSource: ICronZoneRuleSource;
  lCounter: IPeriodReadCounter;
  lUtcMs: Int64;
  lFires, i: Integer;
begin
  lSource := TCountingPeriodSource.Create;
  Assert.IsTrue(Supports(lSource, IPeriodReadCounter, lCounter));
  SetCronSystemTimeZoneForTests(TZoneAsSystemZone.Create(CreateCronZone('counted host', lSource)));
  lUtcMs := U(2026, 7, 1, 12, 0);
  lFires := 0;
  SetMaxCronUtcClockHook(function: Int64 begin Result := lUtcMs * 1000; end);
  try
    GC(lCron, TmaxCron.Create(ctPortable), g);
    for i := 1 to 10 do
    begin
      lEvent := lCron.Add('period reuse' + IntToStr(i));
      lEvent.EventPlan := '* * * * * * *';
      if Odd(i) then lEvent.TimeZoneId := 'UTC';
      lEvent.InvokeMode := imMainThread;
      lEvent.OnScheduleProc := procedure(aSender: IMaxCronEvent) begin Inc(lFires); end;
      lEvent.Run;
    end;
    for i := 1 to 2 do
    begin
      Inc(lUtcMs, 1000);
      lCounter.Reset;
      lCron.TickAtUtcUs(lUtcMs * 1000);
      Assert.AreEqual(10 * i, lFires, 'period memo preserves all dispatches');
      Assert.IsTrue(lCounter.Reads > 0, 'each pass refreshes its period');
      Assert.IsTrue(lCounter.Reads <= 4,
        'constant host period is read once per pass, not once per due event; reads=' + IntToStr(lCounter.Reads));
    end;
  finally
    lEvent := nil;
    g.Clear;
    SetMaxCronUtcClockHook(nil);
    SetCronSystemTimeZoneForTests(nil);
  end;
end;

procedure TTestLocalOverlap.HostZoneChange;
var
  g: TGarbos;
  lCron: TmaxCron;
  lLocal, lUtc: IMaxCronEvent;
  lUtcMs: Int64;
  lLocalFires, lUtcFires: Integer;
  lEngine, lOldEngine: string;
begin
  lOldEngine := {$IFDEF FPC}SysUtils.{$ENDIF}GetEnvironmentVariable('MAXCRON_ENGINE');
  SetMaxCronUtcClockHook(function: Int64 begin Result := lUtcMs*1000; end);
  SetMaxCronWallClockHook(function: Int64 begin Result := CronSystemZoneRules.UtcToLocalMs(lUtcMs) * 1000; end);
  try
    for lEngine in ['scan','heap','shadow','auto'] do
    begin
      SetEnvironmentVariableW('MAXCRON_ENGINE',PChar(lEngine));
      SetCronSystemTimeZoneForTests(TZoneAsSystemZone.Create(CreateCronZone('old host',FakeZoneSource(0))));
      lUtcMs := U(2026,7,1,11,59); lLocalFires := 0; lUtcFires := 0;
      GC(lCron,TmaxCron.Create(ctPortable),g);
      lLocal := lCron.Add('LOCAL'); lLocal.EventPlan := '0 14 * * *';
      lLocal.OnScheduleProc := procedure(aSender: IMaxCronEvent) begin Inc(lLocalFires); end;
      lUtc := lCron.Add('UTC'); lUtc.EventPlan := '0 12 * * *'; lUtc.TimeZoneId := 'UTC';
      lUtc.OnScheduleProc := procedure(aSender: IMaxCronEvent) begin Inc(lUtcFires); end;
      lLocal.Run; lUtc.Run;
      SetCronSystemTimeZoneForTests(TZoneAsSystemZone.Create(CreateCronZone('new host',TCronFixedZoneSource.Create(0))));
      lUtcMs := U(2026,7,1,12,0); lCron.TickAtUtcUs(lUtcMs*1000);
      Assert.AreEqual(0,lLocalFires); Assert.AreEqual(1,lUtcFires);
      Assert.AreEqual(U(2026,7,1,14,0),CronDateTimeToMs(lLocal.NextSchedule));
      Assert.AreEqual(lUtcMs,CronDateTimeToMs(lUtc.LastExecution));
      lLocal := nil; lUtc := nil; g.Clear;
    end;
  finally
    lLocal := nil; lUtc := nil; g.Clear;
    SetMaxCronWallClockHook(nil); SetMaxCronUtcClockHook(nil); SetCronSystemTimeZoneForTests(nil);
    SetEnvironmentVariableW('MAXCRON_ENGINE',PChar(lOldEngine));
  end;
end;

type
  TMatrixCapture = class
  public
    fScenario: TOverlapScenario;
    fFires: TArray<TOverlapModelFire>;
    fCount: Integer;
    procedure Fired(aSender: IMaxCronEvent);
  end;

procedure TMatrixCapture.Fired(aSender: IMaxCronEvent);
var
  lExpected: TOverlapModelFire;
begin
  Assert.IsTrue(fCount < Length(fFires), 'extra model fire ' + fScenario.Id);
  lExpected := fFires[fCount];
  Assert.AreEqual(lExpected.PassUtcMs, gMatrixPass, 'UTC pass ' + fScenario.Id);
  Assert.AreEqual(OverlapHostDisplayMs('Matrix', lExpected.DueUtcMs),
    CronDateTimeToMs(aSender.LastExecution), 'last due ' + fScenario.Id);
  Assert.IsTrue(OverlapDateBits(CronMsToDateTime(OverlapHostDisplayMs('Matrix', lExpected.DueUtcMs))) =
    OverlapDateBits(aSender.LastExecution), 'canonical last ' + fScenario.Id);
  if (lExpected.NextUtcMs <> Low(Int64)) and aSender.Enabled then
    Assert.IsTrue(OverlapDateBits(CronMsToDateTime(OverlapHostDisplayMs('Matrix', lExpected.NextUtcMs))) =
      OverlapDateBits(aSender.NextSchedule), 'next display ' + fScenario.Id);
  Inc(fCount);
end;

function MatrixPlan(const aIndex: Integer; const aRepeatedStart, aRepeatedEnd: Int64): string;
var
  lMs: Int64;
begin
  if aIndex = 4 then Exit('*/15 * * * *');
  if aIndex = 5 then Exit('* * * * * * *');
  lMs := aRepeatedStart;
  case aIndex of
    1: lMs := (aRepeatedStart + aRepeatedEnd) div 2;
    2: lMs := aRepeatedEnd - 1000;
    3: lMs := aRepeatedEnd;
  end;
  Result := Format('%d %d * * * * %d',
    [MinuteOf(CronMsToDateTime(lMs)), HourOf(CronMsToDateTime(lMs)), SecondOf(CronMsToDateTime(lMs))]);
end;

procedure MatrixGroup(const aTransition, aBefore, aAfter: Int64; const aStart, aResume, aDense: Integer;
  var aCases, aFires: Int64);
const
  cZones: array[0..5] of string = ('LOCAL', 'UTC', 'UTC+05:30', 'Test/MatrixHost', 'Test/NewYork', 'Etc/UTC');
  cMisfires: array[0..3] of TmaxCronMisfirePolicy = (mpCatchUpAll, mpDefault, mpSkip, mpFireOnceNow);
var
  g: TGarbos;
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lCaptures: TObjectList<TMatrixCapture>;
  lPasses: TList<Int64>;
  lCapture: TMatrixCapture;
  lInstances: TArray<Int64>;
  s: TOverlapScenario;
  lFire: TOverlapModelFire;
  lShift, lStart, lEnd, lSleepFrom, lSleepTo, lPass, lLastPass, lRs, lRe: Int64;
  z, f, p, m, k, lFirstPlan, lLastPlan: Integer;
begin
  lShift := Abs(aAfter - aBefore);
  if lShift = 0 then lShift := 3600000;
  lStart := aTransition - lShift - 60000;
  case aStart of
    1: lStart := aTransition - 60000;
    2: lStart := aTransition + lShift div 4;
    3: lStart := aTransition + lShift + 1000;
  end;
  lEnd := aTransition + lShift + 60000;
  if lEnd < lStart + 60000 then lEnd := lStart + 60000;
  if aDense <> 0 then lEnd := lStart + 600000;
  lSleepFrom := 0; lSleepTo := 0;
  case aResume of
    1: begin lSleepFrom := aTransition - lShift + 1000; lSleepTo := aTransition + lShift div 4; end;
    2: begin lSleepFrom := aTransition - lShift div 2; lSleepTo := aTransition + lShift div 2; end;
    3: begin lSleepFrom := aTransition + lShift div 4; lSleepTo := aTransition + lShift + 1000; end;
  end;
  lRs := aTransition + Min(aBefore, aAfter);
  lRe := aTransition + Max(aBefore, aAfter);
  if lRs = lRe then Inc(lRe, 3600000);
  GC(lCaptures, TObjectList<TMatrixCapture>.Create(True), g);
  GC(lPasses, TList<Int64>.Create, g);
  lCron := nil;
  gMatrixPass := lStart;
  SetMaxCronWallClockHook(function: Int64 begin Result := OverlapHostDisplayMs('Matrix', gMatrixPass) * 1000; end);
  SetMaxCronUtcClockHook(function: Int64 begin Result := gMatrixPass * 1000; end);
  SetCronSystemTimeZoneForTests(TZoneAsSystemZone.Create(gMatrixHost));
  try
    GC(lCron, TmaxCron.Create(ctPortable), g);
    lCron.DefaultMisfireCatchUpLimit := 1000;
    lFirstPlan := 0; lLastPlan := 4;
    if aDense <> 0 then
    begin
      lFirstPlan := 5; lLastPlan := 5;
    end;
    for z := 0 to High(cZones) do
      for f := 0 to 3 do
        for p := 0 to 1 do
          for m := 0 to High(cMisfires) do
            for k := lFirstPlan to lLastPlan do
            begin
              if not OverlapSample((((z * 4 + f) * 2 + p) * 4 + m) * 6 + k, 17) then Continue;
              s := Sc(Format('matrix-%d-%d-%d-%d-%d', [z,f,p,m,k]), 'Matrix', cZones[z],
                MatrixPlan(k, lRs, lRe), TmaxCronDstFallPolicy(f), cMisfires[m], lStart, lEnd, []);
              s.Spring := TmaxCronDstSpringPolicy(p);
              s.SleepFrom := lSleepFrom; s.SleepTo := lSleepTo;
              lInstances := OverlapModelInstances(s);
              lCapture := TMatrixCapture.Create;
              lCaptures.Add(lCapture);
              lCapture.fScenario := s;
              lCapture.fFires := OverlapModelFires(s, lInstances);
              lEvent := lCron.Add('', s.Plan, lCapture.Fired);
              lEvent.TimeZoneId := s.Zone;
              lEvent.DstFallPolicy := s.Fall; lEvent.DstSpringPolicy := s.Spring;
              lEvent.MisfirePolicy := s.Misfire; lEvent.InvokeMode := imMainThread;
              lEvent.Run;
              for lPass in lInstances do
                if (lPass <= lEnd) and not ((lSleepFrom <> 0) and (lPass >= lSleepFrom) and (lPass < lSleepTo)) then lPasses.Add(lPass);
              for lFire in lCapture.fFires do lPasses.Add(lFire.PassUtcMs);
              Inc(aCases);
            end;
    if (lSleepTo > lStart) and (lSleepTo <= lEnd) then lPasses.Add(lSleepTo);
    lPasses.Add(lEnd); lPasses.Sort;
    lLastPass := Low(Int64);
    for lPass in lPasses do
      if (lPass > lStart) and (lPass <> lLastPass) then
      begin
        gMatrixPass := lPass;
        lCron.TickAtUtcUs(lPass * 1000 + 200);
        lLastPass := lPass;
      end;
    for lCapture in lCaptures do
    begin
      Assert.AreEqual(Integer(Length(lCapture.fFires)), lCapture.fCount, 'model count ' + lCapture.fScenario.Id);
      Inc(aFires, lCapture.fCount);
    end;
  finally
    lEvent := nil;
    if lCron <> nil then lCron.Clear;
    g.Clear;
    SetMaxCronUtcClockHook(nil); SetMaxCronWallClockHook(nil); SetCronSystemTimeZoneForTests(nil);
  end;
end;

procedure RunOverlapGeneratedMatrix(const aEngine: string; const aTzifHosts: Boolean);
const
  cFake: array[0..3] of Integer = (0,3,6,-1);
  cTzif: array[0..2] of string = ('Antarctica/Troll', 'Australia/Lord_Howe', 'Europe/Warsaw');
var
  lSource: ICronZoneRuleSource;
  lChange: TZoneChange;
  lOldEngine, lPath, lError: string;
  lCases, lFires, lBefore: Int64;
  h, st, r, d, lFirstHost, lLastHost: Integer;
begin
  lOldEngine := {$IFDEF FPC}SysUtils.{$ENDIF}GetEnvironmentVariable('MAXCRON_ENGINE');
  SetEnvironmentVariableW('MAXCRON_ENGINE', PChar(aEngine));
  lCases := 0; lFires := 0;
  lFirstHost := 0; lLastHost := 3;
  if aTzifHosts then
  begin
    lFirstHost := 4; lLastHost := 6;
  end;
  RegisterCronZoneForTests('Test/NewYork', FakeZoneSource(1));
  try
    for h := lFirstHost to lLastHost do
    begin
      if h < 4 then
      begin
        if cFake[h] < 0 then
        begin
          lSource := TCronFixedZoneSource.Create(0);
          gMatrixChanges := FakeZoneChanges(0, gMatrixInitial);
          gMatrixInitial := 0;
          for st := 0 to High(gMatrixChanges) do gMatrixChanges[st].OffsetMs := 0;
        end else begin
          lSource := FakeZoneSource(cFake[h]);
          gMatrixChanges := FakeZoneChanges(cFake[h], gMatrixInitial);
        end;
      end else begin
        Assert.IsTrue(TryLoadCronTzifFile(ZoneFixtureRoot, cTzif[h-4], lSource, lPath, lError), lError);
        ZoneSourceModel(lSource, U(2026,1,1,0,0), U(2027,1,1,0,0), gMatrixInitial, gMatrixChanges);
      end;
      gMatrixHost := CreateCronZone('Matrix', lSource);
      RegisterCronZoneForTests('Test/MatrixHost', lSource);
      lBefore := gMatrixInitial;
      for lChange in gMatrixChanges do
      begin
        for st := 0 to 3 do for r := 0 to 3 do for d := 0 to 1 do
          if FullOverlapQualification or ((st * 4 + r) = ((h * 7 + 20261118) mod 16)) then
            MatrixGroup(lChange.UtcMs, lBefore, lChange.OffsetMs, st, r, d, lCases, lFires);
        lBefore := lChange.OffsetMs;
      end;
      System.WriteLn('D_MODEL host=',h,' engine=',aEngine,' cases=',lCases,' fires=',lFires);
    end;
    System.WriteLn('D_MODEL_RESULT engine=',aEngine,' tzif=',aTzifHosts,' cases=',lCases,' fires=',lFires,' failed=0');
  finally
    gMatrixHost := nil; gMatrixChanges := nil;
    ClearCronZonesForTests;
    SetEnvironmentVariableW('MAXCRON_ENGINE', PChar(lOldEngine));
  end;
end;

end.

unit TestWindowsZoneOracle;
{$I maxCron.inc}

interface

uses
  DUnitX.TestFramework,
  maxCron.Internal.TimeZone;

type
  TFakeWindowsChange = record
    UtcMs, OffsetMs: Int64;
  end;
  IFakeWindowsOracle = interface(ICronWindowsZoneOracle)
    {$IFNDEF FPC}['{016C9B6F-EBAC-4711-925D-EF024C18EA2B}']{$ENDIF}
    function Calls: Int64;
    procedure SetFailure(const aFail: Boolean);
    procedure SetCacheable(const aCacheable: Boolean);
  end;
  [TestFixture]
  TTestWindowsZoneOracle = class
  public
    [Test] procedure ReproducesOracleAtCandidates;
    [Test] procedure MidnightNinesNormalize;
    [Test] procedure JanuaryFirstTransition;
    [Test] procedure WallClockYearFrame;
    [Test] procedure PreRangeJanuary;
    [Test] procedure UnexpectedChangeFoundExactly;
    [Test] procedure GuardGridFindsExcursion;
    [Test] procedure DomainEdges;
    [Test] procedure CachesSegmentsOnce;
    [Test] procedure ConcurrentReadsAgree;
    [Test] procedure OracleFailureNotCached;
    [Test] procedure IdentityChangeNotCached;
    [Test] procedure EngineMergesAcrossYears;
  end;

function FakeWindowsOracle(const aInitialMs: Int64; const aChanges: array of TFakeWindowsChange;
  const aRules: array of TCronWindowsYearRule): IFakeWindowsOracle;
function WindowsFakeChange(const aUtcMs, aOffsetMs: Int64): TFakeWindowsChange;
function WindowsTestMs(const aYear, aMonth, aDay: Word; const aHour: Word = 0): Int64;

implementation

uses
  {$IFDEF FPC} Classes, DateUtils, SyncObjs, SysUtils,
  {$ELSE} System.Classes, System.DateUtils, System.SyncObjs, System.SysUtils, {$ENDIF}
  maxCron.Plan;

type
  TFakeWindowsOracle = class(TInterfacedObject, ICronWindowsZoneOracle, IFakeWindowsOracle)
  private
    fInitialMs, fCalls: Int64;
    fChanges: TArray<TFakeWindowsChange>;
    fRules: TArray<TCronWindowsYearRule>;
    fLock: TCriticalSection;
    fFail, fCacheable: Boolean;
  public
    constructor Create(const aInitialMs: Int64; const aChanges: array of TFakeWindowsChange;
      const aRules: array of TCronWindowsYearRule);
    destructor Destroy; override;
    function OffsetAt(const aUtcMs: Int64): Int64;
    function YearRule(const aYear: Integer): TCronWindowsYearRule;
    function CanCache: Boolean;
    function Calls: Int64;
    procedure SetFailure(const aFail: Boolean);
    procedure SetCacheable(const aCacheable: Boolean);
  end;

function WindowsTestMs(const aYear, aMonth, aDay: Word; const aHour: Word): Int64;
begin
  // Calendar accessor on an exact midnight grid, including negative epoch days.
  Result := Trunc(EncodeDate(aYear, aMonth, aDay)) * cCronMsPerDay + Int64(aHour) * 3600000;
end;

function WindowsFakeChange(const aUtcMs, aOffsetMs: Int64): TFakeWindowsChange;
begin
  Result.UtcMs := aUtcMs;
  Result.OffsetMs := aOffsetMs;
end;

constructor TFakeWindowsOracle.Create(const aInitialMs: Int64;
  const aChanges: array of TFakeWindowsChange; const aRules: array of TCronWindowsYearRule);
var
  i: Integer;
begin
  inherited Create;
  fLock := TCriticalSection.Create;
  fInitialMs := aInitialMs;
  fCacheable := True;
  SetLength(fChanges, Length(aChanges));
  for i := 0 to High(aChanges) do fChanges[i] := aChanges[i];
  SetLength(fRules, Length(aRules));
  for i := 0 to High(aRules) do fRules[i] := aRules[i];
end;

destructor TFakeWindowsOracle.Destroy;
begin
  fLock.Free;
  inherited;
end;

function FakeWindowsOracle(const aInitialMs: Int64; const aChanges: array of TFakeWindowsChange;
  const aRules: array of TCronWindowsYearRule): IFakeWindowsOracle;
begin
  Result := TFakeWindowsOracle.Create(aInitialMs, aChanges, aRules);
end;

function TFakeWindowsOracle.OffsetAt(const aUtcMs: Int64): Int64;
var
  i: Integer;
begin
  if (aUtcMs mod 1000 <> 0) or (aUtcMs < WindowsTestMs(1602, 1, 1)) or
    (aUtcMs >= WindowsTestMs(9999, 1, 1)) then
    raise Exception.Create('Oracle query must be a whole second in 1602..9998');
  fLock.Acquire;
  try
    Inc(fCalls);
    if fFail then raise Exception.Create('Fake oracle failure');
  finally
    fLock.Release;
  end;
  Result := fInitialMs;
  for i := 0 to High(fChanges) do
    if aUtcMs >= fChanges[i].UtcMs then Result := fChanges[i].OffsetMs else Break;
end;

function TFakeWindowsOracle.YearRule(const aYear: Integer): TCronWindowsYearRule;
var
  i: Integer;
begin
  Result := Default(TCronWindowsYearRule);
  if Length(fRules) = 0 then Exit;
  Result := fRules[0];
  for i := 1 to High(fRules) do
    if fRules[i].Year <= aYear then Result := fRules[i] else Break;
end;

function TFakeWindowsOracle.CanCache: Boolean;
begin
  Result := fCacheable;
end;

function TFakeWindowsOracle.Calls: Int64;
begin
  fLock.Acquire;
  try Result := fCalls; finally fLock.Release; end;
end;

procedure TFakeWindowsOracle.SetFailure(const aFail: Boolean);
begin
  fFail := aFail;
end;

procedure TFakeWindowsOracle.SetCacheable(const aCacheable: Boolean);
begin
  fCacheable := aCacheable;
end;

function NewYorkOracle: IFakeWindowsOracle;
var
  lRule: TCronWindowsYearRule;
begin
  lRule := Default(TCronWindowsYearRule);
  lRule.Year := 2026;
  lRule.Bias := 300;
  lRule.DaylightBias := -60;
  lRule.DaylightDate.wMonth := 3;
  lRule.DaylightDate.wDay := 2;
  lRule.DaylightDate.wHour := 2;
  lRule.StandardDate.wMonth := 11;
  lRule.StandardDate.wDay := 1;
  lRule.StandardDate.wHour := 2;
  Result := FakeWindowsOracle(-18000000,
    [WindowsFakeChange(WindowsTestMs(2026, 3, 8, 7), -14400000),
     WindowsFakeChange(WindowsTestMs(2026, 11, 1, 6), -18000000)], [lRule]);
end;

{ NativeFixture implementations below copy the designer's ex-changepoints.json records and
  observed OS changes as literals. Records are hints; the explicit changes are the oracle. }
function CairoOracle: IFakeWindowsOracle;
const
  cRules: array[0..3] of TCronWindowsYearRule = (
    (Year: 1968; Bias: -120; StandardBias: 0; DaylightBias: -60;
      StandardDate: (wYear: 0; wMonth: 9; wDayOfWeek: 4; wDay: 5; wHour: 23; wMinute: 59; wSecond: 59; wMilliseconds: 999);
      DaylightDate: (wYear: 0; wMonth: 4; wDayOfWeek: 5; wDay: 5; wHour: 0; wMinute: 0; wSecond: 0; wMilliseconds: 0)),
    (Year: 1969; Bias: -120; StandardBias: 0; DaylightBias: -60;
      StandardDate: (wYear: 0; wMonth: 9; wDayOfWeek: 4; wDay: 5; wHour: 23; wMinute: 59; wSecond: 59; wMilliseconds: 999);
      DaylightDate: (wYear: 0; wMonth: 4; wDayOfWeek: 5; wDay: 5; wHour: 0; wMinute: 0; wSecond: 0; wMilliseconds: 0)),
    (Year: 1970; Bias: -120; StandardBias: 0; DaylightBias: -60;
      StandardDate: (wYear: 0; wMonth: 9; wDayOfWeek: 4; wDay: 5; wHour: 23; wMinute: 59; wSecond: 59; wMilliseconds: 999);
      DaylightDate: (wYear: 0; wMonth: 4; wDayOfWeek: 5; wDay: 5; wHour: 0; wMinute: 0; wSecond: 0; wMilliseconds: 0)),
    (Year: 1971; Bias: -120; StandardBias: 0; DaylightBias: -60;
      StandardDate: (wYear: 0; wMonth: 9; wDayOfWeek: 4; wDay: 5; wHour: 23; wMinute: 59; wSecond: 59; wMilliseconds: 999);
      DaylightDate: (wYear: 0; wMonth: 4; wDayOfWeek: 5; wDay: 5; wHour: 0; wMinute: 0; wSecond: 0; wMilliseconds: 0)));
begin
  Result := FakeWindowsOracle(7200000,
    [WindowsFakeChange(2187468000000, 10800000),
     WindowsFakeChange(2200769999999, 7200000),
     WindowsFakeChange(2218917600000, 10800000),
     WindowsFakeChange(2232219599999, 7200000),
     WindowsFakeChange(2250972000000, 10800000),
     WindowsFakeChange(2264273999999, 7200000)], cRules);
end;

function MoroccoEarlyOracle: IFakeWindowsOracle;
const
  cRules: array[0..4] of TCronWindowsYearRule = (
    (Year: 2016; Bias: 0; StandardBias: 0; DaylightBias: -60;
      StandardDate: (wYear: 0; wMonth: 10; wDayOfWeek: 0; wDay: 5; wHour: 3; wMinute: 0; wSecond: 0; wMilliseconds: 0);
      DaylightDate: (wYear: 0; wMonth: 3; wDayOfWeek: 0; wDay: 5; wHour: 2; wMinute: 0; wSecond: 0; wMilliseconds: 0)),
    (Year: 2017; Bias: 0; StandardBias: 0; DaylightBias: -60;
      StandardDate: (wYear: 0; wMonth: 10; wDayOfWeek: 0; wDay: 5; wHour: 3; wMinute: 0; wSecond: 0; wMilliseconds: 0);
      DaylightDate: (wYear: 0; wMonth: 3; wDayOfWeek: 0; wDay: 5; wHour: 2; wMinute: 0; wSecond: 0; wMilliseconds: 0)),
    (Year: 2018; Bias: 0; StandardBias: 0; DaylightBias: -60;
      StandardDate: (wYear: 0; wMonth: 10; wDayOfWeek: 0; wDay: 4; wHour: 3; wMinute: 0; wSecond: 0; wMilliseconds: 0);
      DaylightDate: (wYear: 0; wMonth: 3; wDayOfWeek: 0; wDay: 4; wHour: 2; wMinute: 0; wSecond: 0; wMilliseconds: 0)),
    (Year: 2019; Bias: 0; StandardBias: 0; DaylightBias: -60;
      StandardDate: (wYear: 0; wMonth: 1; wDayOfWeek: 2; wDay: 1; wHour: 0; wMinute: 0; wSecond: 0; wMilliseconds: 0);
      DaylightDate: (wYear: 0; wMonth: 6; wDayOfWeek: 0; wDay: 2; wHour: 2; wMinute: 0; wSecond: 0; wMilliseconds: 0)),
    (Year: 2020; Bias: 0; StandardBias: 0; DaylightBias: -60;
      StandardDate: (wYear: 0; wMonth: 4; wDayOfWeek: 0; wDay: 3; wHour: 3; wMinute: 0; wSecond: 0; wMilliseconds: 0);
      DaylightDate: (wYear: 0; wMonth: 5; wDayOfWeek: 0; wDay: 5; wHour: 2; wMinute: 0; wSecond: 0; wMilliseconds: 0)));
begin
  Result := FakeWindowsOracle(0,
    [WindowsFakeChange(3699655200000, 3600000),
     WindowsFakeChange(3718404000000, 0),
     WindowsFakeChange(3731104800000, 3600000),
     WindowsFakeChange(3749853600000, 0),
     WindowsFakeChange(3769207200000, 3600000),
     WindowsFakeChange(3796423200000, 0),
     WindowsFakeChange(3800052000000, 3600000)], cRules);
end;

function MoroccoLateOracle: IFakeWindowsOracle;
const
  cRules: array[0..6] of TCronWindowsYearRule = (
    (Year: 2022; Bias: 0; StandardBias: 0; DaylightBias: -60;
      StandardDate: (wYear: 0; wMonth: 3; wDayOfWeek: 0; wDay: 5; wHour: 3; wMinute: 0; wSecond: 0; wMilliseconds: 0);
      DaylightDate: (wYear: 0; wMonth: 5; wDayOfWeek: 0; wDay: 2; wHour: 2; wMinute: 0; wSecond: 0; wMilliseconds: 0)),
    (Year: 2023; Bias: 0; StandardBias: 0; DaylightBias: -60;
      StandardDate: (wYear: 0; wMonth: 3; wDayOfWeek: 0; wDay: 3; wHour: 3; wMinute: 0; wSecond: 0; wMilliseconds: 0);
      DaylightDate: (wYear: 0; wMonth: 4; wDayOfWeek: 0; wDay: 4; wHour: 2; wMinute: 0; wSecond: 0; wMilliseconds: 0)),
    (Year: 2024; Bias: 0; StandardBias: 0; DaylightBias: -60;
      StandardDate: (wYear: 0; wMonth: 3; wDayOfWeek: 0; wDay: 2; wHour: 3; wMinute: 0; wSecond: 0; wMilliseconds: 0);
      DaylightDate: (wYear: 0; wMonth: 4; wDayOfWeek: 0; wDay: 2; wHour: 2; wMinute: 0; wSecond: 0; wMilliseconds: 0)),
    (Year: 2025; Bias: 0; StandardBias: 0; DaylightBias: -60;
      StandardDate: (wYear: 0; wMonth: 2; wDayOfWeek: 0; wDay: 5; wHour: 3; wMinute: 0; wSecond: 0; wMilliseconds: 0);
      DaylightDate: (wYear: 0; wMonth: 4; wDayOfWeek: 0; wDay: 1; wHour: 2; wMinute: 0; wSecond: 0; wMilliseconds: 0)),
    (Year: 2026; Bias: 0; StandardBias: 0; DaylightBias: -60;
      StandardDate: (wYear: 0; wMonth: 9; wDayOfWeek: 0; wDay: 3; wHour: 2; wMinute: 0; wSecond: 0; wMilliseconds: 0);
      DaylightDate: (wYear: 0; wMonth: 3; wDayOfWeek: 0; wDay: 4; wHour: 2; wMinute: 0; wSecond: 0; wMilliseconds: 0)),
    (Year: 2027; Bias: 0; StandardBias: 0; DaylightBias: -60;
      StandardDate: (wYear: 0; wMonth: 0; wDayOfWeek: 0; wDay: 0; wHour: 0; wMinute: 0; wSecond: 0; wMilliseconds: 0);
      DaylightDate: (wYear: 0; wMonth: 0; wDayOfWeek: 0; wDay: 0; wHour: 0; wMinute: 0; wSecond: 0; wMilliseconds: 0)),
    (Year: 2028; Bias: 0; StandardBias: 0; DaylightBias: -60;
      StandardDate: (wYear: 0; wMonth: 0; wDayOfWeek: 0; wDay: 0; wHour: 0; wMinute: 0; wSecond: 0; wMilliseconds: 0);
      DaylightDate: (wYear: 0; wMonth: 0; wDayOfWeek: 0; wDay: 0; wHour: 0; wMinute: 0; wSecond: 0; wMilliseconds: 0)));
begin
  Result := FakeWindowsOracle(3600000,
    [WindowsFakeChange(3888352800000, 0),
     WindowsFakeChange(3891376800000, 3600000),
     WindowsFakeChange(3919197600000, 0),
     WindowsFakeChange(3922221600000, 3600000),
     WindowsFakeChange(3949437600000, 0),
     WindowsFakeChange(3953066400000, 3600000),
     WindowsFakeChange(3976383600000, 0),
     WindowsFakeChange(3983306400000, 3600000),
     WindowsFakeChange(3999027600000, 0)], cRules);
end;

function BrazilOracle: IFakeWindowsOracle;
const
  cRules: array[0..7] of TCronWindowsYearRule = (
    (Year: 1967; Bias: 240; StandardBias: 0; DaylightBias: -60;
      StandardDate: (wYear: 0; wMonth: 1; wDayOfWeek: 4; wDay: 1; wHour: 0; wMinute: 0; wSecond: 0; wMilliseconds: 0);
      DaylightDate: (wYear: 0; wMonth: 11; wDayOfWeek: 2; wDay: 1; wHour: 0; wMinute: 0; wSecond: 0; wMilliseconds: 0)),
    (Year: 1968; Bias: 240; StandardBias: 0; DaylightBias: -60;
      StandardDate: (wYear: 0; wMonth: 1; wDayOfWeek: 4; wDay: 1; wHour: 0; wMinute: 0; wSecond: 0; wMilliseconds: 0);
      DaylightDate: (wYear: 0; wMonth: 11; wDayOfWeek: 2; wDay: 1; wHour: 0; wMinute: 0; wSecond: 0; wMilliseconds: 0)),
    (Year: 1969; Bias: 240; StandardBias: 0; DaylightBias: -60;
      StandardDate: (wYear: 0; wMonth: 1; wDayOfWeek: 4; wDay: 1; wHour: 0; wMinute: 0; wSecond: 0; wMilliseconds: 0);
      DaylightDate: (wYear: 0; wMonth: 11; wDayOfWeek: 2; wDay: 1; wHour: 0; wMinute: 0; wSecond: 0; wMilliseconds: 0)),
    (Year: 1970; Bias: 240; StandardBias: 0; DaylightBias: -60;
      StandardDate: (wYear: 0; wMonth: 1; wDayOfWeek: 4; wDay: 1; wHour: 0; wMinute: 0; wSecond: 0; wMilliseconds: 0);
      DaylightDate: (wYear: 0; wMonth: 11; wDayOfWeek: 2; wDay: 1; wHour: 0; wMinute: 0; wSecond: 0; wMilliseconds: 0)),
    (Year: 1971; Bias: 240; StandardBias: 0; DaylightBias: -60;
      StandardDate: (wYear: 0; wMonth: 1; wDayOfWeek: 4; wDay: 1; wHour: 0; wMinute: 0; wSecond: 0; wMilliseconds: 0);
      DaylightDate: (wYear: 0; wMonth: 11; wDayOfWeek: 2; wDay: 1; wHour: 0; wMinute: 0; wSecond: 0; wMilliseconds: 0)),
    (Year: 1972; Bias: 240; StandardBias: 0; DaylightBias: -60;
      StandardDate: (wYear: 0; wMonth: 1; wDayOfWeek: 4; wDay: 1; wHour: 0; wMinute: 0; wSecond: 0; wMilliseconds: 0);
      DaylightDate: (wYear: 0; wMonth: 11; wDayOfWeek: 2; wDay: 1; wHour: 0; wMinute: 0; wSecond: 0; wMilliseconds: 0)),
    (Year: 1973; Bias: 240; StandardBias: 0; DaylightBias: -60;
      StandardDate: (wYear: 0; wMonth: 1; wDayOfWeek: 4; wDay: 1; wHour: 0; wMinute: 0; wSecond: 0; wMilliseconds: 0);
      DaylightDate: (wYear: 0; wMonth: 11; wDayOfWeek: 2; wDay: 1; wHour: 0; wMinute: 0; wSecond: 0; wMilliseconds: 0)),
    (Year: 1974; Bias: 240; StandardBias: 0; DaylightBias: -60;
      StandardDate: (wYear: 0; wMonth: 1; wDayOfWeek: 4; wDay: 1; wHour: 0; wMinute: 0; wSecond: 0; wMilliseconds: 0);
      DaylightDate: (wYear: 0; wMonth: 11; wDayOfWeek: 2; wDay: 1; wHour: 0; wMinute: 0; wSecond: 0; wMilliseconds: 0)));
begin
  Result := FakeWindowsOracle(-10800000,
    [WindowsFakeChange(2177636400000, -14400000),
     WindowsFakeChange(2204164800000, -10800000),
     WindowsFakeChange(2209172400000, -14400000),
     WindowsFakeChange(2235614400000, -10800000),
     WindowsFakeChange(2240708400000, -14400000),
     WindowsFakeChange(2267064000000, -10800000),
     WindowsFakeChange(2272244400000, -14400000),
     WindowsFakeChange(2299118400000, -10800000),
     WindowsFakeChange(2303866800000, -14400000),
     WindowsFakeChange(2330568000000, -10800000),
     WindowsFakeChange(2335402800000, -14400000),
     WindowsFakeChange(2362017600000, -10800000)], cRules);
end;



function SourceStats(const aSource: ICronZoneRuleSource): ICronWindowsZoneSourceStats;
begin
  Assert.IsTrue(Supports(aSource, ICronWindowsZoneSourceStats, Result));
end;

procedure CheckPeriod(const aSource: ICronZoneRuleSource; const aUtc, aOffset: Int64);
var
  lPeriod: TCronZonePeriod;
begin
  lPeriod := aSource.GetRawPeriod(aUtc);
  Assert.AreEqual(aOffset, lPeriod.OffsetMs);
  Assert.IsTrue((lPeriod.StartUtcMs <= aUtc) and (lPeriod.EndUtcMs > aUtc));
  Assert.IsTrue((lPeriod.StartUtcMs = cCronZoneUnboundedStart) or (lPeriod.StartUtcMs mod 1000 = 0));
  Assert.IsTrue((lPeriod.EndUtcMs = cCronZoneUnboundedEnd) or (lPeriod.EndUtcMs mod 1000 = 0));
end;

procedure TTestWindowsZoneOracle.ReproducesOracleAtCandidates;
var
  lOracle: IFakeWindowsOracle;
  lSource: ICronZoneRuleSource;
  t: Int64;
begin
  lOracle := NewYorkOracle;
  lSource := CreateCronWindowsZoneSourceForTests(lOracle);
  t := WindowsTestMs(2026, 3, 8, 7);
  CheckPeriod(lSource, t - 1, -18000000);
  CheckPeriod(lSource, t, -14400000);
  Assert.AreEqual(t, lSource.GetRawPeriod(t).StartUtcMs);
  Assert.AreEqual(t, lSource.GetRawPeriod(t - 1).EndUtcMs);
  t := WindowsTestMs(2026, 11, 1, 6);
  CheckPeriod(lSource, t - 1, -14400000);
  CheckPeriod(lSource, t, -18000000);
  Assert.AreEqual(Int64(0), SourceStats(lSource).UnexpectedChanges);
  Assert.IsTrue(lOracle.Calls <= 400, 'One year should need at most 400 oracle calls');
end;

procedure TTestWindowsZoneOracle.MidnightNinesNormalize;
var
  lOracle: IFakeWindowsOracle;
  lSource: ICronZoneRuleSource;
  t: Int64;
begin
  lOracle := CairoOracle;
  lSource := CreateCronWindowsZoneSourceForTests(lOracle);
  t := WindowsTestMs(1970, 9, 24, 21);
  CheckPeriod(lSource, t - 1, 10800000);
  CheckPeriod(lSource, t, 7200000);
  Assert.AreEqual(t, lSource.GetRawPeriod(t).StartUtcMs);
  Assert.AreEqual(Int64(0), SourceStats(lSource).UnexpectedChanges);
end;

procedure TTestWindowsZoneOracle.JanuaryFirstTransition;
var
  lSource: ICronZoneRuleSource;
  t: Int64;
begin
  lSource := CreateCronWindowsZoneSourceForTests(MoroccoEarlyOracle);
  t := WindowsTestMs(2019, 1, 1);
  CheckPeriod(lSource, t, 0);
  CheckPeriod(lSource, CronDateTimeToMs(EncodeDateTime(2019, 3, 8, 15, 5, 21, 0)), 0);
  CheckPeriod(lSource, WindowsTestMs(2018, 10, 28, 2), 0);
  t := WindowsTestMs(2019, 6, 9, 2);
  CheckPeriod(lSource, t - 1, 0);
  CheckPeriod(lSource, t, 3600000);
  Assert.AreEqual(Int64(0), SourceStats(lSource).UnexpectedChanges);
end;

procedure TTestWindowsZoneOracle.WallClockYearFrame;
var
  lSource: ICronZoneRuleSource;
  t: Int64;
begin
  lSource := CreateCronWindowsZoneSourceForTests(MoroccoLateOracle);
  t := WindowsTestMs(2025, 12, 31, 23);
  CheckPeriod(lSource, t - 1000, 3600000);
  CheckPeriod(lSource, t, 0);
  t := WindowsTestMs(2026, 3, 22, 2);
  CheckPeriod(lSource, t - 1000, 0);
  CheckPeriod(lSource, t, 3600000);
  Assert.AreEqual(Int64(0), SourceStats(lSource).UnexpectedChanges);
end;

procedure TTestWindowsZoneOracle.PreRangeJanuary;
var
  lSource: ICronZoneRuleSource;
  t: Int64;
begin
  lSource := CreateCronWindowsZoneSourceForTests(BrazilOracle);
  t := WindowsTestMs(1971, 1, 1, 3);
  CheckPeriod(lSource, t - 1000, -10800000);
  CheckPeriod(lSource, t, -14400000);
  CheckPeriod(lSource, WindowsTestMs(1971, 1, 7, 3) - 1000, -14400000);
  Assert.AreEqual(Int64(0), SourceStats(lSource).UnexpectedChanges);
end;

procedure TTestWindowsZoneOracle.UnexpectedChangeFoundExactly;
var
  lSource: ICronZoneRuleSource;
  t: Int64;
begin
  t := CronDateTimeToMs(EncodeDateTime(2026, 5, 17, 13, 37, 42, 0));
  lSource := CreateCronWindowsZoneSourceForTests(FakeWindowsOracle(0, [WindowsFakeChange(t, 3600000)], []));
  CheckPeriod(lSource, t - 1, 0);
  CheckPeriod(lSource, t, 3600000);
  Assert.AreEqual(t, lSource.GetRawPeriod(t).StartUtcMs);
  Assert.AreEqual(t, lSource.GetRawPeriod(t - 1).EndUtcMs);
  Assert.AreEqual(Int64(1), SourceStats(lSource).UnexpectedChanges);
end;

procedure TTestWindowsZoneOracle.GuardGridFindsExcursion;
var
  lSource: ICronZoneRuleSource;
  a, b: Int64;
begin
  a := WindowsTestMs(2026, 7, 9, 5) + 7000;
  b := WindowsTestMs(2026, 7, 12, 19) + 3000;
  lSource := CreateCronWindowsZoneSourceForTests(FakeWindowsOracle(0,
    [WindowsFakeChange(a, 3600000), WindowsFakeChange(b, 0)], []));
  CheckPeriod(lSource, a - 1, 0); CheckPeriod(lSource, a, 3600000);
  CheckPeriod(lSource, b - 1, 3600000); CheckPeriod(lSource, b, 0);
  Assert.AreEqual(a, lSource.GetRawPeriod(a).StartUtcMs);
  Assert.AreEqual(b, lSource.GetRawPeriod(b).StartUtcMs);
  Assert.AreEqual(Int64(2), SourceStats(lSource).UnexpectedChanges);
end;

procedure TTestWindowsZoneOracle.DomainEdges;
var
  lSource: ICronZoneRuleSource;
begin
  lSource := CreateCronWindowsZoneSourceForTests(FakeWindowsOracle(20700000, [], []));
  CheckPeriod(lSource, WindowsTestMs(1500, 1, 1), 20700000);
  CheckPeriod(lSource, CronDateTimeToMs(EncodeDate(9999, 12, 31)) + cCronMsPerDay, 20700000);
  CheckPeriod(lSource, cCronZoneUnboundedStart, 20700000);
  CheckPeriod(lSource, cCronZoneUnboundedEnd - 1, 20700000);
end;

procedure TTestWindowsZoneOracle.CachesSegmentsOnce;
var
  lOracle: IFakeWindowsOracle;
  lSource: ICronZoneRuleSource;
  lCalls: Int64;
begin
  lOracle := NewYorkOracle;
  lSource := CreateCronWindowsZoneSourceForTests(lOracle);
  CheckPeriod(lSource, WindowsTestMs(2026, 1, 1), -18000000);
  lCalls := lOracle.Calls;
  CheckPeriod(lSource, WindowsTestMs(2026, 8, 1), -14400000);
  Assert.AreEqual(lCalls, lOracle.Calls);
  Assert.AreEqual(lCalls, SourceStats(lSource).OracleCalls);
  Assert.AreEqual(Int64(1), SourceStats(lSource).SegmentsComputed);
end;

type
  TOracleReadThread = class(TThread)
  private
    fSource, fReference: ICronZoneRuleSource;
  protected
    procedure Execute; override;
  public
    Error: string;
    constructor Create(const aSource, aReference: ICronZoneRuleSource);
  end;

constructor TOracleReadThread.Create(const aSource, aReference: ICronZoneRuleSource);
begin
  inherited Create(True);
  fSource := aSource;
  fReference := aReference;
end;

procedure TOracleReadThread.Execute;
var
  y: Integer;
  t: Int64;
  a, b: TCronZonePeriod;
begin
  try
    for y := 2000 to 2050 do
    begin
      t := WindowsTestMs(y, 7, 1);
      a := fSource.GetRawPeriod(t);
      b := fReference.GetRawPeriod(t);
      if (a.StartUtcMs <> b.StartUtcMs) or (a.EndUtcMs <> b.EndUtcMs) or (a.OffsetMs <> b.OffsetMs) then
        raise Exception.Create('Concurrent period differs in year ' + IntToStr(y));
    end;
  except
    on E: Exception do Error := E.Message;
  end;
end;

procedure TTestWindowsZoneOracle.ConcurrentReadsAgree;
var
  lSource, lReference: ICronZoneRuleSource;
  lThreads: array[0..7] of TOracleReadThread;
  i, y: Integer;
begin
  lSource := CreateCronWindowsZoneSourceForTests(NewYorkOracle);
  lReference := CreateCronWindowsZoneSourceForTests(NewYorkOracle);
  for y := 2000 to 2050 do lReference.GetRawPeriod(WindowsTestMs(y, 7, 1));
  for i := 0 to High(lThreads) do lThreads[i] := nil;
  try
    for i := 0 to High(lThreads) do
    begin
      lThreads[i] := TOracleReadThread.Create(lSource, lReference);
      lThreads[i].Start;
    end;
    for i := 0 to High(lThreads) do
    begin
      lThreads[i].WaitFor;
      Assert.AreEqual('', lThreads[i].Error);
    end;
  finally
    for i := 0 to High(lThreads) do lThreads[i].Free;
  end;
  Assert.AreEqual(Int64(0), SourceStats(lSource).UnexpectedChanges);
end;

procedure TTestWindowsZoneOracle.OracleFailureNotCached;
var
  lOracle: IFakeWindowsOracle;
  lSource: ICronZoneRuleSource;
  lFailed: Boolean;
begin
  lOracle := NewYorkOracle;
  lSource := CreateCronWindowsZoneSourceForTests(lOracle);
  lOracle.SetFailure(True);
  lFailed := False;
  try
    lSource.GetRawPeriod(WindowsTestMs(2026, 1, 1));
  except
    on E: Exception do
    begin
      Assert.AreEqual('Fake oracle failure', E.Message);
      lFailed := True;
    end;
  end;
  Assert.IsTrue(lFailed);
  lOracle.SetFailure(False);
  CheckPeriod(lSource, WindowsTestMs(2026, 1, 1), -18000000);
  Assert.AreEqual(Int64(2), SourceStats(lSource).SegmentsComputed);
end;

procedure TTestWindowsZoneOracle.IdentityChangeNotCached;
var
  lOracle: IFakeWindowsOracle;
  lSource: ICronZoneRuleSource;
  lCalls: Int64;
begin
  lOracle := NewYorkOracle;
  lSource := CreateCronWindowsZoneSourceForTests(lOracle);
  CheckPeriod(lSource, WindowsTestMs(2026, 7, 1), -14400000);
  lOracle.SetCacheable(False);
  lCalls := lOracle.Calls;
  CheckPeriod(lSource, WindowsTestMs(2026, 7, 1), -14400000);
  CheckPeriod(lSource, WindowsTestMs(2026, 7, 1), -14400000);
  Assert.IsTrue(lOracle.Calls > lCalls);
  Assert.AreEqual(Int64(3), SourceStats(lSource).SegmentsComputed);
end;

procedure TTestWindowsZoneOracle.EngineMergesAcrossYears;
var
  lZone: ICronZoneRules;
  lPeriod: TCronZonePeriod;
  t: Int64;
begin
  lZone := CreateCronZone('no-dst', CreateCronWindowsZoneSourceForTests(FakeWindowsOracle(0, [], [])));
  t := WindowsTestMs(2030, 1, 1);
  lPeriod := lZone.GetPeriod(t);
  Assert.IsTrue(lPeriod.StartUtcMs < t - cCronZoneWindowMs);
  Assert.IsTrue(lPeriod.EndUtcMs > t + cCronZoneWindowMs);
  Assert.AreEqual(Int64(0), lPeriod.OffsetMs);
end;

end.

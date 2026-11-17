unit TestZoneFakes;
{$I maxCron.inc}

interface

uses
  {$IFDEF FPC}
  SysUtils,
  maxCron.Internal.TimeZone
  {$ELSE}
  System.SysUtils,
  maxCron.Internal.TimeZone
  {$ENDIF};

type
  TZoneChange = record
    UtcMs, OffsetMs: Int64;
  end;
  TFakeZoneSource = class(TInterfacedObject, ICronZoneRuleSource)
  private
    fInitial: Int64;
    fChanges: TArray<TZoneChange>;
  public
    constructor Create(const aInitial: Int64; const aChanges: array of TZoneChange);
    function GetRawPeriod(const aUtcMs: Int64): TCronZonePeriod;
  end;
  TZoneAsSystemZone = class(TInterfacedObject, ICronTimeZone)
  private
    fZone: ICronZoneRules;
  public
    constructor Create(const aZone: ICronZoneRules);
    function ToUniversalTime(const aLocal: TDateTime; const aForceDaylight: Boolean): TDateTime;
    function ToLocalTime(const aUtc: TDateTime): TDateTime;
    function IsAmbiguousTime(const aLocal: TDateTime): Boolean;
    function IsInvalidTime(const aLocal: TDateTime): Boolean;
  end;

function ZoneMs(const aYear, aMonth, aDay, aHour: Word; const aMinute: Word = 0): Int64;
function ZoneFixtureRoot: string;
function FakeZoneSource(const aIndex: Integer): ICronZoneRuleSource;
function FakeZoneChanges(const aIndex: Integer; out aInitial: Int64): TArray<TZoneChange>;
function ReferenceMapping(const aInitial: Int64; const aChanges: TArray<TZoneChange>;
  const aLocalMs: Int64): TCronLocalMapping;

procedure ZoneSourceModel(const aSource: ICronZoneRuleSource; const aFrom, aTo: Int64;
  out aInitial: Int64; out aChanges: TArray<TZoneChange>);
procedure CheckZoneSearchLimits;
procedure CheckZoneRanges(const aZone: ICronZoneRules; const aFrom, aTo: Int64; var aChecks: Int64);
procedure CheckZoneSearch(const aZone: ICronZoneRules; const aInitial: Int64;
  const aChanges: TArray<TZoneChange>; const aFrom, aTo: Int64; var aChecks: Int64;
  out aWindow, aMaxCalls: Integer);

implementation

uses
  {$IFDEF FPC}
  DateUtils, Generics.Collections, System.IOUtils,
  AutoFree,
  maxCron.Plan
  {$ELSE}
  System.DateUtils, System.Generics.Collections, System.IOUtils,
  AutoFree,
  maxCron.Plan
  {$ENDIF};

function ZoneMs(const aYear, aMonth, aDay, aHour, aMinute: Word): Int64;
begin
  Result := CronDateTimeToMs(EncodeDateTime(aYear, aMonth, aDay, aHour, aMinute, 0, 0));
end;

function ZoneFixtureRoot: string;
var
  lDir, lParent: string;
begin
  lDir := {$IFDEF FPC}SysUtils.{$ENDIF}GetEnvironmentVariable('MAXCRON_TEST_ROOT');
  if lDir <> '' then
  begin
    Result := TPath.Combine(TPath.Combine(TPath.Combine(lDir, 'tests'), 'data'), 'tzif');
    if not DirectoryExists(Result) then
      raise Exception.Create('Invalid MAXCRON_TEST_ROOT (expected tests/data/tzif).');
    Exit;
  end;
  lDir := ExtractFilePath(ParamStr(0));
  repeat
    Result := TPath.Combine(lDir, 'data');
    Result := TPath.Combine(Result, 'tzif');
    if DirectoryExists(Result) then Exit;
    Result := TPath.Combine(lDir, 'tests');
    Result := TPath.Combine(Result, 'data');
    Result := TPath.Combine(Result, 'tzif');
    if DirectoryExists(Result) then Exit;
    lParent := ExtractFileDir(ExcludeTrailingPathDelimiter(lDir));
    if lParent = lDir then Break;
    lDir := lParent;
  until lDir = '';
  Result := {$IFDEF FPC}SysUtils.{$ENDIF}GetEnvironmentVariable('MAXCRON_TEST_TZDIR');
  if not DirectoryExists(Result) then raise Exception.Create('Test TZif fixtures not found');
end;

constructor TFakeZoneSource.Create(const aInitial: Int64; const aChanges: array of TZoneChange);
var
  i: Integer;
begin
  inherited Create;
  fInitial := aInitial;
  SetLength(fChanges, Length(aChanges));
  for i := 0 to High(aChanges) do fChanges[i] := aChanges[i];
end;

function TFakeZoneSource.GetRawPeriod(const aUtcMs: Int64): TCronZonePeriod;
var
  lChange: TZoneChange;
begin
  Result.StartUtcMs := cCronZoneUnboundedStart;
  Result.EndUtcMs := cCronZoneUnboundedEnd;
  Result.OffsetMs := fInitial;
  for lChange in fChanges do
    if lChange.UtcMs <= aUtcMs then
    begin
      Result.StartUtcMs := lChange.UtcMs;
      Result.OffsetMs := lChange.OffsetMs;
    end else begin
      Result.EndUtcMs := lChange.UtcMs;
      Break;
    end;
end;

function FakeZoneChanges(const aIndex: Integer; out aInitial: Int64): TArray<TZoneChange>;
begin
  Result := nil;
  SetLength(Result, 2);
  case aIndex of
    0:
      begin
        aInitial := 3600000;
        Result[0].UtcMs := ZoneMs(2026, 3, 29, 1); Result[0].OffsetMs := 7200000;
        Result[1].UtcMs := ZoneMs(2026, 10, 25, 1); Result[1].OffsetMs := 3600000;
      end;
    1:
      begin
        aInitial := -18000000;
        Result[0].UtcMs := ZoneMs(2026, 3, 8, 7); Result[0].OffsetMs := -14400000;
        Result[1].UtcMs := ZoneMs(2026, 11, 1, 6); Result[1].OffsetMs := -18000000;
      end;
    2:
      begin
        aInitial := 39600000;
        Result[0].UtcMs := ZoneMs(2026, 4, 4, 16); Result[0].OffsetMs := 36000000;
        Result[1].UtcMs := ZoneMs(2026, 10, 3, 16); Result[1].OffsetMs := 39600000;
      end;
    3:
      begin
        aInitial := 39600000;
        Result[0].UtcMs := ZoneMs(2026, 4, 4, 15); Result[0].OffsetMs := 37800000;
        Result[1].UtcMs := ZoneMs(2026, 10, 3, 15, 30); Result[1].OffsetMs := 39600000;
      end;
    4:
      begin
        aInitial := -10800000;
        Result[0].UtcMs := ZoneMs(2018, 11, 4, 3); Result[0].OffsetMs := -7200000;
        Result[1].UtcMs := ZoneMs(2019, 2, 17, 2); Result[1].OffsetMs := -10800000;
      end;
    5:
      begin
        aInitial := 7200000;
        Result[0].UtcMs := ZoneMs(2026, 1, 1, 1); Result[0].OffsetMs := 3600000;
        Result[1].UtcMs := ZoneMs(2026, 1, 1, 2); Result[1].OffsetMs := 0;
      end;
  else raise Exception.Create('Unknown fake zone index');
  end;
end;

function FakeZoneSource(const aIndex: Integer): ICronZoneRuleSource;
var
  lInitial: Int64;
  lChanges: TArray<TZoneChange>;
begin
  lChanges := FakeZoneChanges(aIndex, lInitial);
  Result := TFakeZoneSource.Create(lInitial, lChanges);
end;

function ReferenceMapping(const aInitial: Int64; const aChanges: TArray<TZoneChange>;
  const aLocalMs: Int64): TCronLocalMapping;
var
  lStart, lEnd, lOffset, lCandidate: Int64;
  lCount, i: Integer;
begin
  Result := Default(TCronLocalMapping);
  Result.Kind := TCronLocalKind.clkGap;
  lStart := cCronZoneUnboundedStart;
  lOffset := aInitial;
  lCount := 0;
  for i := 0 to Length(aChanges) do
  begin
    lEnd := cCronZoneUnboundedEnd;
    if i < Length(aChanges) then lEnd := aChanges[i].UtcMs;
    lCandidate := aLocalMs - lOffset;
    if (lCandidate >= lStart) and (lCandidate < lEnd) then
    begin
      if (lCount = 0) or (lCandidate < Result.FirstUtcMs) then Result.FirstUtcMs := lCandidate;
      if (lCount = 0) or (lCandidate > Result.SecondUtcMs) then Result.SecondUtcMs := lCandidate;
      Inc(lCount);
    end;
    if i < Length(aChanges) then
    begin
      if (lCount = 0) and (aLocalMs >= lEnd + lOffset) and
        (aLocalMs < lEnd + aChanges[i].OffsetMs) then
      begin
        Result.FirstUtcMs := lEnd;
        Result.SecondUtcMs := lEnd;
      end;
      lStart := lEnd;
      lOffset := aChanges[i].OffsetMs;
    end;
  end;
  if lCount = 1 then Result.Kind := TCronLocalKind.clkUnique;
  if lCount > 1 then Result.Kind := TCronLocalKind.clkOverlap;
end;

constructor TZoneAsSystemZone.Create(const aZone: ICronZoneRules);
begin
  inherited Create;
  fZone := aZone;
end;

function TZoneAsSystemZone.ToUniversalTime(const aLocal: TDateTime;
  const aForceDaylight: Boolean): TDateTime;
var
  lMap: TCronLocalMapping;
begin
  lMap := fZone.MapLocal(CronDateTimeToMs(aLocal));
  if aForceDaylight then Result := CronMsToDateTime(lMap.FirstUtcMs)
  else Result := CronMsToDateTime(lMap.SecondUtcMs);
end;

function TZoneAsSystemZone.ToLocalTime(const aUtc: TDateTime): TDateTime;
begin
  Result := CronMsToDateTime(fZone.UtcToLocalMs(CronDateTimeToMs(aUtc)));
end;

function TZoneAsSystemZone.IsAmbiguousTime(const aLocal: TDateTime): Boolean;
begin
  Result := fZone.MapLocal(CronDateTimeToMs(aLocal)).Kind = TCronLocalKind.clkOverlap;
end;

function TZoneAsSystemZone.IsInvalidTime(const aLocal: TDateTime): Boolean;
begin
  Result := fZone.MapLocal(CronDateTimeToMs(aLocal)).Kind = TCronLocalKind.clkGap;
end;

type
  TZoneOccurrenceSource = class
  public
    Values: TArray<Int64>;
    EverySecond: Boolean;
    LimitAt, Calls: Integer;
    function First(const aFromLocalMs: Int64; out aLocalMs: Int64): TCronInstantSearchResult;
  end;

function TZoneOccurrenceSource.First(const aFromLocalMs: Int64; out aLocalMs: Int64): TCronInstantSearchResult;
var
  lLo, lHi, lMid: Integer;
begin
  Inc(Calls);
  if (LimitAt > 0) and (Calls = LimitAt) then Exit(cisLimit);
  if EverySecond then
  begin
    aLocalMs := CronCeilDiv(aFromLocalMs, 1000) * 1000;
    Exit(cisFound);
  end;
  lLo := 0;
  lHi := Length(Values);
  while lLo < lHi do
  begin
    lMid := lLo + (lHi - lLo) div 2;
    if Values[lMid] < aFromLocalMs then lLo := lMid + 1 else lHi := lMid;
  end;
  if lLo = Length(Values) then Exit(cisNotFound);
  aLocalMs := Values[lLo];
  Result := cisFound;
end;

procedure ZoneRequire(const aCondition: Boolean; const aMessage: string);
begin
  if not aCondition then raise Exception.Create(aMessage);
end;

procedure ZoneSourceModel(const aSource: ICronZoneRuleSource; const aFrom, aTo: Int64;
  out aInitial: Int64; out aChanges: TArray<TZoneChange>);
var
  p, q: TCronZonePeriod;
begin
  aChanges := nil;
  p := aSource.GetRawPeriod(aFrom);
  aInitial := p.OffsetMs;
  while p.EndUtcMs <= aTo do
  begin
    q := aSource.GetRawPeriod(p.EndUtcMs);
    if q.OffsetMs <> p.OffsetMs then
    begin
      SetLength(aChanges, Length(aChanges) + 1);
      aChanges[High(aChanges)].UtcMs := p.EndUtcMs;
      aChanges[High(aChanges)].OffsetMs := q.OffsetMs;
    end;
    p := q;
  end;
end;

procedure CheckZoneRangeSample(const aZone: ICronZoneRules; const r: TCronLocalRange;
  const aLocal: Int64; var aChecks: Int64);
var
  lMap: TCronLocalMapping;
  p, q: TCronZonePeriod;
  lCount, lPieces, lGapPieces: Integer;
  lUtc: Int64;
  s: TCronLocalRange;
  lContext: string;
begin
  if (aLocal < r.StartLocalMs) or (aLocal >= r.EndLocalMs) then Exit;
  lContext := Format('Z5 %s local=%d kind=%d', [aZone.GetName, aLocal, Ord(r.Kind)]);
  lMap := aZone.MapLocal(aLocal);
  lUtc := aLocal - r.OffsetMs;
  case r.Kind of
    clrUnique: ZoneRequire((lMap.Kind = clkUnique) and (lMap.FirstUtcMs = lUtc), lContext);
    clrFirst: ZoneRequire((lMap.Kind = clkOverlap) and (lMap.FirstUtcMs = lUtc), lContext);
    clrSecond: ZoneRequire((lMap.Kind = clkOverlap) and (lMap.SecondUtcMs = lUtc), lContext);
    clrMiddle: ZoneRequire((lMap.Kind = clkOverlap) and (lMap.FirstUtcMs < lUtc) and
      (lUtc < lMap.SecondUtcMs), lContext);
    clrGap: ZoneRequire((lMap.Kind = clkGap) and (lMap.FirstUtcMs = r.InstantUtcMs), lContext);
  end;
  lCount := 0;
  lPieces := 0;
  lGapPieces := 0;
  // Independent membership enumeration, including ranges of neighbouring periods.
  p := aZone.GetPeriod(aLocal - cCronZoneMaxAbsOffsetMs);
  while p.StartUtcMs <= aLocal + cCronZoneMaxAbsOffsetMs do
  begin
    lUtc := aLocal - p.OffsetMs;
    if (p.StartUtcMs <= lUtc) and (lUtc < p.EndUtcMs) then Inc(lCount);
    for s in CronZonePeriodRanges(aZone, p) do
      if (s.StartLocalMs <= aLocal) and (aLocal < s.EndLocalMs) then
        if s.Kind = clrGap then Inc(lGapPieces) else Inc(lPieces);
    if p.EndUtcMs = cCronZoneUnboundedEnd then Break;
    q := aZone.GetPeriod(p.EndUtcMs);
    if q.StartUtcMs < p.EndUtcMs then q.StartUtcMs := p.EndUtcMs;
    p := q;
  end;
  ZoneRequire(lCount = lPieces, lContext + ' multiplicity');
  if lCount = 0 then ZoneRequire(lGapPieces = 1, lContext + ' gap attribution')
  else ZoneRequire(lGapPieces = 0, lContext + ' gap with real instance');
  Inc(aChecks);
end;

procedure CheckZoneRanges(const aZone: ICronZoneRules; const aFrom, aTo: Int64;
  var aChecks: Int64);
var
  p: TCronZonePeriod;
  r: TCronLocalRange;
  lCovered, lStart, lEnd: Int64;
begin
  p := aZone.GetPeriod(aFrom);
  repeat
    lCovered := p.StartUtcMs;
    if lCovered <> cCronZoneUnboundedStart then Inc(lCovered, p.OffsetMs);
    for r in CronZonePeriodRanges(aZone, p) do
    begin
      ZoneRequire(r.StartLocalMs < r.EndLocalMs, 'Z5 empty range');
      if r.Kind <> clrGap then
      begin
        ZoneRequire(lCovered = r.StartLocalMs, 'Z5 coverage/disjoint/order ' + aZone.GetName);
        lCovered := r.EndLocalMs;
      end;
      // Sentinel intervals are sampled inside the requested civil-date window.
      lStart := r.StartLocalMs;
      lEnd := r.EndLocalMs;
      if lStart = cCronZoneUnboundedStart then lStart := aFrom;
      if lEnd = cCronZoneUnboundedEnd then lEnd := aTo;
      CheckZoneRangeSample(aZone, r, lStart, aChecks);
      CheckZoneRangeSample(aZone, r, lStart + 1, aChecks);
      CheckZoneRangeSample(aZone, r, lStart + 1000, aChecks);
      CheckZoneRangeSample(aZone, r, lStart + (lEnd - lStart) div 2, aChecks);
      CheckZoneRangeSample(aZone, r, lEnd - 1000, aChecks);
      CheckZoneRangeSample(aZone, r, lEnd - 1, aChecks);
    end;
    lEnd := p.EndUtcMs;
    if lEnd <> cCronZoneUnboundedEnd then Inc(lEnd, p.OffsetMs);
    ZoneRequire(lCovered = lEnd, 'Z5 uncovered end ' + aZone.GetName);
    if p.EndUtcMs >= aTo then Break;
    p := aZone.GetPeriod(p.EndUtcMs);
  until False;
end;

procedure CheckZoneSearchLimits;
var
  k: Integer;
  g: TGarbos;
  lOracle: TZoneOccurrenceSource;
  lZone: ICronZoneRules;
  lChanges: TArray<TZoneChange>;
  lBase, lUtc: Int64;
  lCalls: Integer;
begin
  lBase := ZoneMs(2026, 1, 1, 0);
  SetLength(lChanges, 2);
  lChanges[0].UtcMs := lBase + 86400000;
  lChanges[0].OffsetMs := 3600000;
  lChanges[1].UtcMs := lBase + 2 * 86400000;
  lChanges[1].OffsetMs := 7200000;
  lZone := CreateCronZone('limit-chain', TFakeZoneSource.Create(0, lChanges));
  GC(lOracle, TZoneOccurrenceSource.Create, g);
  lOracle.Values := [lChanges[0].UtcMs + 1800000, lChanges[1].UtcMs + 5400000,
    lBase + 4 * 86400000];
  for k := 1 to 3 do
  begin
    lOracle.Calls := 0;
    lOracle.LimitAt := k;
    ZoneRequire(CronZoneFindNextInstant(lZone, lBase - 1000, False, cfcBoth, lOracle.First,
      lUtc, lCalls) = cisLimit, 'Z6 required limit propagation k=' + IntToStr(k));
    ZoneRequire(lCalls = k, 'Z6 stopped exactly at injected limit');
  end;
end;

function ZoneModelWindow(const aChanges: TArray<TZoneChange>): Integer;
var
  i, j: Integer;
begin
  Result := 1;
  j := 0;
  for i := 0 to High(aChanges) do
  begin
    while aChanges[i].UtcMs - aChanges[j].UtcMs >= Int64(104) * 3600000 do Inc(j);
    if i - j + 2 > Result then Result := i - j + 2;
  end;
end;

function ZoneModelOffset(const aInitial: Int64; const aChanges: TArray<TZoneChange>;
  const aUtc: Int64): Int64;
var
  lLo, lHi, lMid: Integer;
begin
  lLo := 0;
  lHi := Length(aChanges);
  while lLo < lHi do
  begin
    lMid := lLo + (lHi - lLo) div 2;
    if aChanges[lMid].UtcMs <= aUtc then lLo := lMid + 1 else lHi := lMid;
  end;
  if lLo = 0 then Result := aInitial else Result := aChanges[lLo - 1].OffsetMs;
end;

function ZoneDenseNext(const aInitial: Int64; const aChanges: TArray<TZoneChange>;
  const aBase: Int64; const aFall: TCronFallChoice): Int64;
var
  c: TZoneChange;
  lMap: TCronLocalMapping;
  lLocal, lBefore, lShift: Int64;
  lNear: Integer;
begin
  Result := aBase + 1000;
  lNear := 0;
  for c in aChanges do
    if Abs(c.UtcMs - aBase) < Int64(6) * 86400000 then Inc(lNear);
  if lNear <= 1 then
  begin
    // Independent dense closed forms, valid for either gap policy.
    lBefore := aInitial;
    for c in aChanges do
    begin
      lShift := lBefore - c.OffsetMs;
      if lShift > 0 then
      begin
        if (aFall = cfcFirst) and (Result >= c.UtcMs) and (Result < c.UtcMs + lShift) then
          Result := c.UtcMs + lShift;
        if (aFall = cfcSecond) and (Result >= c.UtcMs - lShift) and (Result < c.UtcMs) then
          Result := c.UtcMs;
      end;
      lBefore := c.OffsetMs;
    end;
    Exit;
  end;
  // Synthetic3: a literal UTC-second brute force, including rejected middle instances.
  repeat
    lLocal := Result + ZoneModelOffset(aInitial, aChanges, Result);
    lMap := ReferenceMapping(aInitial, aChanges, lLocal);
    if ((aFall <> cfcSecond) and (lMap.FirstUtcMs = Result)) or
      ((aFall <> cfcFirst) and (lMap.SecondUtcMs = Result)) then Exit;
    Inc(Result, 1000);
  until False;
end;

procedure ZoneAppend(var aValues: TArray<Int64>; const aValue: Int64);
begin
  SetLength(aValues, Length(aValues) + 1);
  aValues[High(aValues)] := aValue;
end;

function ZoneNextSeed(var aSeed: UInt32): UInt32;
begin
  // Bounded arithmetic, deterministic even with overflow checking enabled.
  aSeed := UInt32((UInt64(aSeed) * 1664525 + 1013904223) and $FFFFFFFF);
  Result := aSeed;
end;

procedure CheckZoneSearch(const aZone: ICronZoneRules; const aInitial: Int64;
  const aChanges: TArray<TZoneChange>; const aFrom, aTo: Int64; var aChecks: Int64;
  out aWindow, aMaxCalls: Integer);
var
  c: TZoneChange;
  k: Integer;
  d: Integer;
  i: Integer;
  lSet: Integer;
  lSpring: Boolean;
  lFall: TCronFallChoice;
  lChange: TZoneChange;
  g: TGarbos;
  lOracle: TZoneOccurrenceSource;
  lValues, lExpected, lGapOccurrences, lBases: TArray<Int64>;
  lProbes: TArray<TZoneChange>;
  lMap: TCronLocalMapping;
  lBase, lBefore, lShift, lLocal, lUtc, lExpectedUtc, lLo, lHi: Int64;
  lCalls, lSkipped, lLow, lHigh, lMid: Integer;
  lResult: TCronInstantSearchResult;
  lSeed: UInt32;
  lContext: string;
begin
  aWindow := ZoneModelWindow(aChanges);
  aMaxCalls := 0;
  GC(lOracle, TZoneOccurrenceSource.Create, g);
  lSeed := 20261117;
  lProbes := Copy(aChanges);
  if Length(lProbes) = 0 then
  begin
    SetLength(lProbes, 1);
    lProbes[0].UtcMs := aFrom;
    lProbes[0].OffsetMs := aInitial;
  end;
  lBefore := aInitial;
  for c in lProbes do
  begin
    if (c.UtcMs < aFrom) or (c.UtcMs >= aTo) then
    begin
      lBefore := c.OffsetMs;
      Continue;
    end;
    lShift := Abs(lBefore - c.OffsetMs);
    lBases := nil;
    for k := -2 to 2 do
      for d := -5 to 5 do ZoneAppend(lBases, c.UtcMs + k * lShift + d * 1000);
    for i := 1 to 64 do
      ZoneAppend(lBases, c.UtcMs + (Int64(ZoneNextSeed(lSeed) mod 518401) - 259200) * 1000);
    for lSet := 0 to 6 do
    begin
      lValues := nil;
      lLo := c.UtcMs - Int64(5) * 86400000;
      lHi := c.UtcMs + Int64(5) * 86400000;
      case lSet of
        1, 2:
          begin
            lLocal := CronFloorDiv(lLo, 900000) * 900000;
            while lLocal <= lHi do
            begin
              if (lSet = 1) or (lLocal mod 3600000 = 1800000) then ZoneAppend(lValues, lLocal);
              Inc(lLocal, 900000);
            end;
          end;
        3: if c.OffsetMs < lBefore then ZoneAppend(lValues,
          CronFloorDiv(c.UtcMs + c.OffsetMs + lShift div 2, 1000) * 1000);
        4: if c.OffsetMs > lBefore then ZoneAppend(lValues,
          CronFloorDiv(c.UtcMs + lBefore + lShift div 2, 1000) * 1000);
        5:
          for i := 1 to 1 + Integer(ZoneNextSeed(lSeed) mod 20) do
            ZoneAppend(lValues, c.UtcMs + (Int64(ZoneNextSeed(lSeed) mod 518401) - 259200) * 1000);
      end;
      {$IFDEF FPC}
  TArrayHelper<Int64>.Sort(
  {$ELSE}TArray.Sort<Int64>({$ENDIF}lValues);
      lOracle.Values := lValues;
      lOracle.EverySecond := lSet = 0;
      for lSpring in [False, True] do
        for lFall := Low(TCronFallChoice) to High(TCronFallChoice) do
        begin
          lExpected := nil;
          lGapOccurrences := nil;
          for lLocal in lValues do
          begin
            lMap := ReferenceMapping(aInitial, aChanges, lLocal);
            if lMap.Kind = clkGap then
            begin
              if lSpring then ZoneAppend(lExpected, lMap.FirstUtcMs)
              else ZoneAppend(lGapOccurrences, lMap.FirstUtcMs);
            end else begin
              if (lMap.Kind = clkUnique) or (lFall <> cfcSecond) then
                ZoneAppend(lExpected, lMap.FirstUtcMs);
              if (lMap.Kind = clkOverlap) and (lFall <> cfcFirst) then
                ZoneAppend(lExpected, lMap.SecondUtcMs);
            end;
          end;
          {$IFDEF FPC}
  TArrayHelper<Int64>.Sort(
  {$ELSE}TArray.Sort<Int64>({$ENDIF}lExpected);
          {$IFDEF FPC}
  TArrayHelper<Int64>.Sort(
  {$ELSE}TArray.Sort<Int64>({$ENDIF}lGapOccurrences);
          for lBase in lBases do
          begin
            lExpectedUtc := High(Int64);
            if lSet = 0 then lExpectedUtc := ZoneDenseNext(aInitial, aChanges, lBase, lFall)
            else
            begin
              lLow := 0;
              lHigh := Length(lExpected);
              while lLow < lHigh do
              begin
                lMid := lLow + (lHigh - lLow) div 2;
                if lExpected[lMid] <= lBase then lLow := lMid + 1 else lHigh := lMid;
              end;
              if lLow < Length(lExpected) then lExpectedUtc := lExpected[lLow];
            end;
            lOracle.Calls := 0;
            lOracle.LimitAt := 0;
            lResult := CronZoneFindNextInstant(aZone, lBase, lSpring, lFall, lOracle.First, lUtc, lCalls);
            lContext := Format('Z6 %s transition=%d set=%d spring=%d fall=%d base=%d',
              [aZone.GetName, c.UtcMs, lSet, Ord(lSpring), Ord(lFall), lBase]);
            if lExpectedUtc = High(Int64) then ZoneRequire(lResult = cisNotFound, lContext + ' absent')
            else ZoneRequire((lResult = cisFound) and (lUtc = lExpectedUtc),
              lContext + Format(' expected=%d actual=%d result=%d', [lExpectedUtc, lUtc, Ord(lResult)]));
            lSkipped := 0;
            lLocal := Low(Int64);
            for lUtc in lGapOccurrences do
              if (lUtc <> lLocal) and (lUtc > lBase) and (lUtc < lExpectedUtc) then
              begin
                Inc(lSkipped);
                lLocal := lUtc;
              end;
            if (lSet = 0) and (not lSpring) then
            begin
              lLocal := aInitial;
              for lChange in aChanges do
              begin
                if (lChange.OffsetMs > lLocal) and (lChange.UtcMs > lBase) and (lChange.UtcMs < lExpectedUtc) then Inc(lSkipped);
                lLocal := lChange.OffsetMs;
              end;
            end;
            ZoneRequire(lCalls <= (2 * aWindow + 2) * (lSkipped + 1), lContext + ' call bound');
            ZoneRequire(lCalls = lOracle.Calls, lContext + ' counter');
            if lCalls > aMaxCalls then aMaxCalls := lCalls;
            Inc(aChecks);
          end;
        end;
    end;
    lBefore := c.OffsetMs;
  end;
end;


end.

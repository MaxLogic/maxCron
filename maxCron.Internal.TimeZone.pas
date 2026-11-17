unit maxCron.Internal.TimeZone;
{$I maxCron.inc}

interface

uses
  System.SysUtils;

const
  cCronZoneMaxAbsOffsetMs = Int64(26) * 3600000;
  cCronZoneUnboundedStart = -(Int64(1) shl 60);
  cCronZoneUnboundedEnd = Int64(1) shl 60;
  cCronZoneWindowMs = Int64(3) * 86400000;

type
  TCronZonePeriod = record
    StartUtcMs, EndUtcMs, OffsetMs: Int64;
  end;
  ICronZoneRuleSource = interface
    ['{5EC9093C-C9EF-46A5-8D12-7D59DD32FE19}']
    function GetRawPeriod(const aUtcMs: Int64): TCronZonePeriod;
  end;
  TCronLocalKind = (clkUnique, clkGap, clkOverlap);
  TCronLocalMapping = record
    Kind: TCronLocalKind;
    FirstUtcMs, SecondUtcMs: Int64;
  end;
  ICronZoneRules = interface
    ['{BFD7A1EF-C694-45F4-B441-C3F195960E6E}']
    function GetName: string;
    function GetPeriod(const aUtcMs: Int64): TCronZonePeriod;
    function UtcToLocalMs(const aUtcMs: Int64): Int64;
    function MapLocal(const aLocalMs: Int64): TCronLocalMapping;
  end;
  TCronLocalRangeKind = (clrUnique, clrFirst, clrSecond, clrMiddle, clrGap);
  TCronLocalRange = record
    StartLocalMs, EndLocalMs: Int64;
    Kind: TCronLocalRangeKind;
    OffsetMs, InstantUtcMs: Int64;
  end;
  TCronFallChoice = (cfcFirst, cfcSecond, cfcBoth);
  TCronInstantSearchResult = (cisFound, cisNotFound, cisLimit);
  // Least allowed whole-second occurrence at or after aFromLocalMs.
  TCronFirstOccurrenceFunc = function(const aFromLocalMs: Int64; out aLocalMs: Int64):
    TCronInstantSearchResult of object;
  TCronFixedZoneSource = class(TInterfacedObject, ICronZoneRuleSource)
  private
    fOffsetMs: Int64;
  public
    constructor Create(const aOffsetMs: Int64);
    function GetRawPeriod(const aUtcMs: Int64): TCronZonePeriod;
  end;
  ICronTimeZone = interface
    ['{F0CCDB2D-3702-41A6-B483-0522A41B7F8B}']
    function ToUniversalTime(const aLocal: TDateTime; const aForceDaylight: Boolean): TDateTime;
    function ToLocalTime(const aUtc: TDateTime): TDateTime;
    function IsAmbiguousTime(const aLocal: TDateTime): Boolean;
    function IsInvalidTime(const aLocal: TDateTime): Boolean;
  end;

// Re-reads the RTL system zone on every call, including its exception behavior.
function CronSystemTimeZone: ICronTimeZone;
{$IFDEF MAXCRON_TESTS}
// Set before creating a scheduler; nil restores the RTL zone. Tests run serially.
procedure SetCronSystemTimeZoneForTests(const aZone: ICronTimeZone);
{$ENDIF}

function CreateCronZone(const aName: string; const aSource: ICronZoneRuleSource): ICronZoneRules;
function CronZonePeriodRanges(const aZone: ICronZoneRules; const aPeriod: TCronZonePeriod):
  TArray<TCronLocalRange>;
function CronZoneFindNextInstant(const aZone: ICronZoneRules; const aAfterUtcMs: Int64;
  const aRunInGap: Boolean; const aFall: TCronFallChoice; const aFirstOccurrence: TCronFirstOccurrenceFunc;
  out aUtcMs: Int64; out aCalls: Integer): TCronInstantSearchResult;
function CronZoneMinOffsetMs(const aZone: ICronZoneRules; const aFromUtcMs, aToUtcMs: Int64): Int64;
function CronZoneMaxOffsetMs(const aZone: ICronZoneRules; const aFromUtcMs, aToUtcMs: Int64): Int64;
function TryResolveCronZone(const aName, aDataRoot: string; out aZone: ICronZoneRules;
  out aNormalizedName, aError: string): Boolean;
function IsCronZoneNameSyntax(const aName: string): Boolean;
{$IFDEF MAXCRON_TESTS}
procedure RegisterCronZoneForTests(const aName: string; const aSource: ICronZoneRuleSource);
procedure ClearCronZonesForTests;
{$ENDIF}

implementation

uses
  System.DateUtils, System.Generics.Collections, System.SyncObjs,
  maxCron.Internal.TZif;

type
  TCronZoneRules = class(TInterfacedObject, ICronZoneRules)
  private
    fName: string;
    fSource: ICronZoneRuleSource;
    function RawPeriod(const aUtcMs: Int64): TCronZonePeriod;
  public
    constructor Create(const aName: string; const aSource: ICronZoneRuleSource);
    function GetName: string;
    function GetPeriod(const aUtcMs: Int64): TCronZonePeriod;
    function UtcToLocalMs(const aUtcMs: Int64): Int64;
    function MapLocal(const aLocalMs: Int64): TCronLocalMapping;
  end;
  TCronRtlLocalTimeZone = class(TInterfacedObject, ICronTimeZone)
  public
    function ToUniversalTime(const aLocal: TDateTime; const aForceDaylight: Boolean): TDateTime;
    function ToLocalTime(const aUtc: TDateTime): TDateTime;
    function IsAmbiguousTime(const aLocal: TDateTime): Boolean;
    function IsInvalidTime(const aLocal: TDateTime): Boolean;
  end;

var
  gSystemTimeZone: ICronTimeZone;
  gZoneLock: TCriticalSection;
  gZoneCache: TDictionary<string, ICronZoneRules>;
{$IFDEF MAXCRON_TESTS}
  gTestZones: TDictionary<string, ICronZoneRules>;
{$ENDIF}
{$IFDEF MAXCRON_TESTS}
  gTestTimeZone: ICronTimeZone;

procedure SetCronSystemTimeZoneForTests(const aZone: ICronTimeZone);
begin
  gTestTimeZone := aZone;
end;
{$ENDIF}

function CronSystemTimeZone: ICronTimeZone;
begin
{$IFDEF MAXCRON_TESTS}
  if Assigned(gTestTimeZone) then
    Exit(gTestTimeZone);
{$ENDIF}
  Result := gSystemTimeZone;
end;

function TCronRtlLocalTimeZone.ToUniversalTime(const aLocal: TDateTime;
  const aForceDaylight: Boolean): TDateTime;
begin
  Result := TTimeZone.Local.ToUniversalTime(aLocal, aForceDaylight);
end;

function TCronRtlLocalTimeZone.ToLocalTime(const aUtc: TDateTime): TDateTime;
begin
  Result := TTimeZone.Local.ToLocalTime(aUtc);
end;

function TCronRtlLocalTimeZone.IsAmbiguousTime(const aLocal: TDateTime): Boolean;
begin
  Result := TTimeZone.Local.IsAmbiguousTime(aLocal);
end;

function TCronRtlLocalTimeZone.IsInvalidTime(const aLocal: TDateTime): Boolean;
begin
  Result := TTimeZone.Local.IsInvalidTime(aLocal);
end;

constructor TCronFixedZoneSource.Create(const aOffsetMs: Int64);
begin
  inherited Create;
  if (aOffsetMs < -cCronZoneMaxAbsOffsetMs) or (aOffsetMs > cCronZoneMaxAbsOffsetMs) or
    (aOffsetMs mod 1000 <> 0) then
    raise Exception.Create('Invalid fixed zone offset');
  fOffsetMs := aOffsetMs;
end;

function TCronFixedZoneSource.GetRawPeriod(const aUtcMs: Int64): TCronZonePeriod;
begin
  Result.StartUtcMs := cCronZoneUnboundedStart;
  Result.EndUtcMs := cCronZoneUnboundedEnd;
  Result.OffsetMs := fOffsetMs;
end;

constructor TCronZoneRules.Create(const aName: string; const aSource: ICronZoneRuleSource);
begin
  inherited Create;
  if aSource = nil then
    raise Exception.Create('Zone rule source is required');
  fName := aName;
  fSource := aSource;
end;

function TCronZoneRules.GetName: string;
begin
  Result := fName;
end;

function TCronZoneRules.RawPeriod(const aUtcMs: Int64): TCronZonePeriod;
begin
  if (aUtcMs < cCronZoneUnboundedStart) or (aUtcMs >= cCronZoneUnboundedEnd) then
    raise Exception.Create('Zone instant is outside the supported range');
  Result := fSource.GetRawPeriod(aUtcMs);
  if (Result.StartUtcMs > aUtcMs) or (Result.EndUtcMs <= aUtcMs) or
    (Result.StartUtcMs < cCronZoneUnboundedStart) or (Result.EndUtcMs > cCronZoneUnboundedEnd) or
    (Result.OffsetMs < -cCronZoneMaxAbsOffsetMs) or (Result.OffsetMs > cCronZoneMaxAbsOffsetMs) or
    (Result.OffsetMs mod 1000 <> 0) then
    raise Exception.Create('Invalid zone rule period');
end;

function TCronZoneRules.GetPeriod(const aUtcMs: Int64): TCronZonePeriod;
var
  lOther: TCronZonePeriod;
begin
  Result := RawPeriod(aUtcMs);
  while (Result.StartUtcMs > cCronZoneUnboundedStart) and
    (Result.StartUtcMs > aUtcMs - cCronZoneWindowMs) do
  begin
    lOther := RawPeriod(Result.StartUtcMs - 1);
    if lOther.OffsetMs <> Result.OffsetMs then Break;
    Result.StartUtcMs := lOther.StartUtcMs;
  end;
  while (Result.EndUtcMs < cCronZoneUnboundedEnd) and
    (Result.EndUtcMs <= aUtcMs + cCronZoneWindowMs) do
  begin
    lOther := RawPeriod(Result.EndUtcMs);
    if lOther.OffsetMs <> Result.OffsetMs then Break;
    Result.EndUtcMs := lOther.EndUtcMs;
  end;
end;

function TCronZoneRules.UtcToLocalMs(const aUtcMs: Int64): Int64;
begin
  Result := aUtcMs + GetPeriod(aUtcMs).OffsetMs;
end;

function TCronZoneRules.MapLocal(const aLocalMs: Int64): TCronLocalMapping;
var
  lPeriod, lNext: TCronZonePeriod;
  lCandidate, lGap: Int64;
  lCount: Integer;
begin
  Result := Default(TCronLocalMapping);
  lCount := 0;
  lGap := cCronZoneUnboundedStart;
  lPeriod := GetPeriod(aLocalMs - cCronZoneMaxAbsOffsetMs);
  while lPeriod.StartUtcMs <= aLocalMs + cCronZoneMaxAbsOffsetMs do
  begin
    lCandidate := aLocalMs - lPeriod.OffsetMs;
    if (lCandidate >= lPeriod.StartUtcMs) and (lCandidate < lPeriod.EndUtcMs) then
    begin
      if (lCount = 0) or (lCandidate < Result.FirstUtcMs) then Result.FirstUtcMs := lCandidate;
      if (lCount = 0) or (lCandidate > Result.SecondUtcMs) then Result.SecondUtcMs := lCandidate;
      Inc(lCount);
    end;
    if lPeriod.EndUtcMs >= cCronZoneUnboundedEnd then Break;
    lNext := GetPeriod(lPeriod.EndUtcMs);
    // Equal-offset merging can extend the next result back across an already visited interval.
    if lNext.StartUtcMs < lPeriod.EndUtcMs then lNext.StartUtcMs := lPeriod.EndUtcMs;
    if (aLocalMs >= lPeriod.EndUtcMs + lPeriod.OffsetMs) and
      (aLocalMs < lPeriod.EndUtcMs + lNext.OffsetMs) then lGap := lPeriod.EndUtcMs;
    lPeriod := lNext;
  end;
  if lCount > 1 then Result.Kind := TCronLocalKind.clkOverlap
  else if lCount = 1 then Result.Kind := TCronLocalKind.clkUnique
  else
  begin
    if lGap = cCronZoneUnboundedStart then raise Exception.Create('Local zone mapping has no period or gap');
    Result.Kind := TCronLocalKind.clkGap;
    Result.FirstUtcMs := lGap;
    Result.SecondUtcMs := lGap;
  end;
end;

function CreateCronZone(const aName: string; const aSource: ICronZoneRuleSource): ICronZoneRules;
begin
  Result := TCronZoneRules.Create(aName, aSource);
end;

function ZoneLocalStart(const aPeriod: TCronZonePeriod): Int64;
begin
  Result := aPeriod.StartUtcMs;
  if Result <> cCronZoneUnboundedStart then Inc(Result, aPeriod.OffsetMs);
end;

function ZoneLocalEnd(const aPeriod: TCronZonePeriod): Int64;
begin
  Result := aPeriod.EndUtcMs;
  if Result <> cCronZoneUnboundedEnd then Inc(Result, aPeriod.OffsetMs);
end;

procedure ZoneAddEndpoint(var aPoints: TArray<Int64>; const aValue, aLo, aHi: Int64);
begin
  if (aValue > aLo) and (aValue < aHi) then
  begin
    SetLength(aPoints, Length(aPoints) + 1);
    aPoints[High(aPoints)] := aValue;
  end;
end;

procedure ZoneAddRange(var aRanges: TArray<TCronLocalRange>; const aLo, aHi: Int64;
  const aKind: TCronLocalRangeKind; const aPeriod: TCronZonePeriod);
var
  i: Integer;
begin
  if aLo >= aHi then Exit;
  i := Length(aRanges);
  SetLength(aRanges, i + 1);
  aRanges[i].StartLocalMs := aLo;
  aRanges[i].EndLocalMs := aHi;
  aRanges[i].Kind := aKind;
  aRanges[i].OffsetMs := aPeriod.OffsetMs;
  aRanges[i].InstantUtcMs := aPeriod.StartUtcMs;
end;

function CronZonePeriodRanges(const aZone: ICronZoneRules; const aPeriod: TCronZonePeriod):
  TArray<TCronLocalRange>;
var
  lPeriods: TArray<TCronZonePeriod>;
  lPoints: TArray<Int64>;
  p: TCronZonePeriod;
  lLo, lHi, lPoint, lBoundary: Int64;
  lEarlier, lLater, lCovered: Boolean;
  lKind: TCronLocalRangeKind;
  i, j, lOwn: Integer;
begin
  Result := nil;
  lPeriods := nil;
  p := aPeriod;
  while p.StartUtcMs > cCronZoneUnboundedStart do
  begin
    lBoundary := p.StartUtcMs;
    p := aZone.GetPeriod(lBoundary - 1);
    // GetPeriod may merge equal-offset raw periods beyond the query window.
    // Partition at our existing boundary so the same UTC instant is never a neighbour instance.
    if p.EndUtcMs > lBoundary then p.EndUtcMs := lBoundary;
    if p.EndUtcMs <= aPeriod.StartUtcMs - 2 * cCronZoneMaxAbsOffsetMs then Break;
    SetLength(lPeriods, Length(lPeriods) + 1);
    lPeriods[High(lPeriods)] := p;
  end;
  // Reverse earlier periods, then append this period and its successors.
  lOwn := Length(lPeriods);
  for i := 0 to lOwn div 2 - 1 do
  begin
    p := lPeriods[i];
    lPeriods[i] := lPeriods[lOwn - i - 1];
    lPeriods[lOwn - i - 1] := p;
  end;
  SetLength(lPeriods, lOwn + 1);
  lPeriods[lOwn] := aPeriod;
  p := aPeriod;
  while p.EndUtcMs < cCronZoneUnboundedEnd do
  begin
    lBoundary := p.EndUtcMs;
    p := aZone.GetPeriod(lBoundary);
    if p.StartUtcMs < lBoundary then p.StartUtcMs := lBoundary;
    if p.StartUtcMs >= aPeriod.EndUtcMs + 2 * cCronZoneMaxAbsOffsetMs then Break;
    SetLength(lPeriods, Length(lPeriods) + 1);
    lPeriods[High(lPeriods)] := p;
  end;

  if (lOwn > 0) and (lPeriods[lOwn - 1].OffsetMs < aPeriod.OffsetMs) then
  begin
    lLo := aPeriod.StartUtcMs + lPeriods[lOwn - 1].OffsetMs;
    lHi := ZoneLocalStart(aPeriod);
    lPoints := [lLo, lHi];
    for i := 0 to High(lPeriods) do
    begin
      ZoneAddEndpoint(lPoints, ZoneLocalStart(lPeriods[i]), lLo, lHi);
      ZoneAddEndpoint(lPoints, ZoneLocalEnd(lPeriods[i]), lLo, lHi);
      if i > lOwn then
      begin
        ZoneAddEndpoint(lPoints, lPeriods[i].StartUtcMs + lPeriods[i - 1].OffsetMs, lLo, lHi);
        ZoneAddEndpoint(lPoints, ZoneLocalStart(lPeriods[i]), lLo, lHi);
      end;
    end;
    TArray.Sort<Int64>(lPoints);
    for i := 0 to High(lPoints) - 1 do
    begin
      lPoint := lPoints[i];
      if lPoint = lPoints[i + 1] then Continue;
      lCovered := False;
      for j := 0 to High(lPeriods) do
      begin
        if (lPoint >= ZoneLocalStart(lPeriods[j])) and (lPoint < ZoneLocalEnd(lPeriods[j])) then
          lCovered := True;
        // With no real instance, MapLocal attributes intersecting gaps to the last boundary.
        if (j > lOwn) and (lPoint >= lPeriods[j].StartUtcMs + lPeriods[j - 1].OffsetMs) and
          (lPoint < ZoneLocalStart(lPeriods[j])) then lCovered := True;
      end;
      if not lCovered then ZoneAddRange(Result, lPoint, lPoints[i + 1], clrGap, aPeriod);
    end;
  end;

  lLo := ZoneLocalStart(aPeriod);
  lHi := ZoneLocalEnd(aPeriod);
  lPoints := [lLo, lHi];
  for i := 0 to High(lPeriods) do
  begin
    ZoneAddEndpoint(lPoints, ZoneLocalStart(lPeriods[i]), lLo, lHi);
    ZoneAddEndpoint(lPoints, ZoneLocalEnd(lPeriods[i]), lLo, lHi);
  end;
  TArray.Sort<Int64>(lPoints);
  for i := 0 to High(lPoints) - 1 do
  begin
    lPoint := lPoints[i];
    if lPoint = lPoints[i + 1] then Continue;
    lEarlier := False;
    lLater := False;
    for j := 0 to High(lPeriods) do
      if (lPoint >= ZoneLocalStart(lPeriods[j])) and (lPoint < ZoneLocalEnd(lPeriods[j])) then
      begin
        if j < lOwn then lEarlier := True;
        if j > lOwn then lLater := True;
      end;
    if lEarlier and lLater then lKind := clrMiddle
    else if lEarlier then lKind := clrSecond
    else if lLater then lKind := clrFirst
    else lKind := clrUnique;
    ZoneAddRange(Result, lPoint, lPoints[i + 1], lKind, aPeriod);
  end;
end;

function CronZoneFindNextInstant(const aZone: ICronZoneRules; const aAfterUtcMs: Int64;
  const aRunInGap: Boolean; const aFall: TCronFallChoice; const aFirstOccurrence: TCronFirstOccurrenceFunc;
  out aUtcMs: Int64; out aCalls: Integer): TCronInstantSearchResult;
var
  p: TCronZonePeriod;
  r: TCronLocalRange;
  lStart, lLo, lOccurrence, lMemoFrom, lMemoOccurrence: Int64;
  lMemoValid: Boolean;
begin
  aUtcMs := 0;
  aCalls := 0;
  lStart := aAfterUtcMs + 1000;
  p := aZone.GetPeriod(lStart);
  lMemoValid := False;
  lMemoFrom := 0;
  lMemoOccurrence := 0;
  while True do
  begin
    if lMemoValid and (p.StartUtcMs >= lMemoFrom + cCronZoneMaxAbsOffsetMs) then
    begin
      if lMemoOccurrence = High(Int64) then Exit(cisNotFound);
      if p.EndUtcMs <= lMemoOccurrence - cCronZoneMaxAbsOffsetMs then
        p := aZone.GetPeriod(lMemoOccurrence - cCronZoneMaxAbsOffsetMs);
    end;
    for r in CronZonePeriodRanges(aZone, p) do
    begin
      case r.Kind of
        clrFirst: if aFall = cfcSecond then Continue;
        clrSecond: if aFall = cfcFirst then Continue;
        clrMiddle: Continue;
        clrGap: if not aRunInGap then Continue;
      end;
      lLo := r.StartLocalMs;
      if r.Kind = clrGap then
      begin
        if r.InstantUtcMs < lStart then Continue;
      end else if lLo < lStart + p.OffsetMs then lLo := lStart + p.OffsetMs;
      if lLo >= r.EndLocalMs then Continue;
      if lMemoValid and (lLo >= lMemoFrom) and
        ((lMemoOccurrence = High(Int64)) or (lLo <= lMemoOccurrence)) then
        lOccurrence := lMemoOccurrence
      else
      begin
        Inc(aCalls);
        case aFirstOccurrence(lLo, lOccurrence) of
          cisLimit: Exit(cisLimit);
          cisNotFound: lOccurrence := High(Int64);
        end;
        lMemoFrom := lLo;
        lMemoOccurrence := lOccurrence;
        lMemoValid := True;
      end;
      if (lOccurrence <> High(Int64)) and (lOccurrence < r.EndLocalMs) then
      begin
        if r.Kind = clrGap then aUtcMs := r.InstantUtcMs
        else aUtcMs := lOccurrence - p.OffsetMs;
        Exit(cisFound);
      end;
    end;
    if p.EndUtcMs >= cCronZoneUnboundedEnd then Exit(cisNotFound);
    p := aZone.GetPeriod(p.EndUtcMs);
  end;
end;

function ZoneExtremeOffset(const aZone: ICronZoneRules; const aFromUtcMs, aToUtcMs: Int64;
  const aMaximum: Boolean): Int64;
var
  lPeriod: TCronZonePeriod;
begin
  if aToUtcMs < aFromUtcMs then raise Exception.Create('Reversed zone offset range');
  lPeriod := aZone.GetPeriod(aFromUtcMs);
  Result := lPeriod.OffsetMs;
  while (lPeriod.EndUtcMs <= aToUtcMs) and (lPeriod.EndUtcMs < cCronZoneUnboundedEnd) do
  begin
    lPeriod := aZone.GetPeriod(lPeriod.EndUtcMs);
    if (aMaximum and (lPeriod.OffsetMs > Result)) or
      ((not aMaximum) and (lPeriod.OffsetMs < Result)) then Result := lPeriod.OffsetMs;
  end;
end;

function CronZoneMinOffsetMs(const aZone: ICronZoneRules; const aFromUtcMs, aToUtcMs: Int64): Int64;
begin
  Result := ZoneExtremeOffset(aZone, aFromUtcMs, aToUtcMs, False);
end;

function CronZoneMaxOffsetMs(const aZone: ICronZoneRules; const aFromUtcMs, aToUtcMs: Int64): Int64;
begin
  Result := ZoneExtremeOffset(aZone, aFromUtcMs, aToUtcMs, True);
end;

function IsCronZoneNameSyntax(const aName: string): Boolean;
var
  i, lStart: Integer;
  c: Char;
  lPart: string;
begin
  Result := False;
  if (Length(aName) < 1) or (Length(aName) > 255) then Exit;
  if not CharInSet(aName[1], ['A'..'Z', 'a'..'z']) then Exit;
  lStart := 1;
  for i := 1 to Length(aName) + 1 do
  begin
    if i <= Length(aName) then c := aName[i] else c := '/';
    if c = '/' then
    begin
      lPart := Copy(aName, lStart, i - lStart);
      if (lPart = '') or (lPart = '.') or (lPart = '..') then Exit;
      lStart := i + 1;
    end else if not CharInSet(c, ['A'..'Z', 'a'..'z', '0'..'9', '_', '+', '.', '-']) then Exit;
  end;
  Result := True;
end;

function TryFixedZone(const aName: string; out aOffsetMs: Int64; out aNormalized: string): Boolean;
var
  lName, lSuffix: string;
  lHours, lSign: Integer;
begin
  lName := UpperCase(aName);
  aOffsetMs := 0;
  aNormalized := aName;
  Result := True;
  if (lName = 'ETC/UTC') or (lName = 'ETC/UCT') or (lName = 'ETC/UNIVERSAL') or
    (lName = 'ETC/ZULU') or (lName = 'ETC/GMT') or (lName = 'ETC/GMT0') or
    (lName = 'ETC/GMT+0') or (lName = 'ETC/GMT-0') or (lName = 'ETC/GREENWICH') or
    (lName = 'GMT') or (lName = 'UCT') or (lName = 'ZULU') or (lName = 'UNIVERSAL') or
    (lName = 'GREENWICH') then
  begin
    if lName = 'ETC/UTC' then aNormalized := 'Etc/UTC';
    if lName = 'ETC/UCT' then aNormalized := 'Etc/UCT';
    if lName = 'ETC/UNIVERSAL' then aNormalized := 'Etc/Universal';
    if lName = 'ETC/ZULU' then aNormalized := 'Etc/Zulu';
    if lName = 'ETC/GMT' then aNormalized := 'Etc/GMT';
    if lName = 'ETC/GMT0' then aNormalized := 'Etc/GMT0';
    if lName = 'ETC/GMT+0' then aNormalized := 'Etc/GMT+0';
    if lName = 'ETC/GMT-0' then aNormalized := 'Etc/GMT-0';
    if lName = 'ETC/GREENWICH' then aNormalized := 'Etc/Greenwich';
    if lName = 'GMT' then aNormalized := 'GMT';
    if lName = 'UCT' then aNormalized := 'UCT';
    if lName = 'ZULU' then aNormalized := 'Zulu';
    if lName = 'UNIVERSAL' then aNormalized := 'Universal';
    if lName = 'GREENWICH' then aNormalized := 'Greenwich';
    Exit;
  end;
  Result := False;
  if (Copy(lName, 1, 7) <> 'ETC/GMT') or (Length(lName) < 9) then Exit;
  if lName[8] = '+' then lSign := -1
  else if lName[8] = '-' then lSign := 1 else Exit;
  lSuffix := Copy(lName, 9, MaxInt);
  if not TryStrToInt(lSuffix, lHours) then Exit;
  if (IntToStr(lHours) <> lSuffix) or (lHours < 0) or (lHours > 14) then Exit;
  aOffsetMs := Int64(lSign) * lHours * 3600000;
  aNormalized := 'Etc/GMT' + Copy(lName, 8, MaxInt);
  Result := True;
end;

function TryResolveCronZone(const aName, aDataRoot: string; out aZone: ICronZoneRules;
  out aNormalizedName, aError: string): Boolean;
var
  lKey, lPath: string;
  lSource: ICronZoneRuleSource;
  lOffset: Int64;
  lResolved: ICronZoneRules;
begin
  aZone := nil;
  aNormalizedName := aName;
  aError := '';
  if not IsCronZoneNameSyntax(aName) then
  begin
    aError := 'invalid IANA name syntax';
    Exit(False);
  end;
  lKey := UpperCase(aName) + #0 + aDataRoot;
  gZoneLock.Acquire;
  try
{$IFDEF MAXCRON_TESTS}
    if gTestZones.TryGetValue(UpperCase(aName), aZone) then
    begin
      aNormalizedName := aZone.GetName;
      Exit(True);
    end;
{$ENDIF}
    if gZoneCache.TryGetValue(lKey, aZone) then
    begin
      aNormalizedName := aZone.GetName;
      Exit(True);
    end;
  finally
    gZoneLock.Release;
  end;
  if TryFixedZone(aName, lOffset, aNormalizedName) then
    lSource := TCronFixedZoneSource.Create(lOffset)
  else
  begin
    if aDataRoot = '' then
    begin
      aError := 'Windows named zone provider is not available; set MAXCRON_TZDIR to use TZif data';
      Exit(False);
    end;
    if not TryLoadCronTzifFile(aDataRoot, aName, lSource, lPath, aError) then Exit(False);
    // The file loader preserves directory spelling, including TZif-only aliases.
    aNormalizedName := Copy(lPath, Length(IncludeTrailingPathDelimiter(aDataRoot)) + 1, MaxInt);
    aNormalizedName := StringReplace(aNormalizedName, PathDelim, '/', [rfReplaceAll]);
  end;
  lResolved := CreateCronZone(aNormalizedName, lSource);
  gZoneLock.Acquire;
  try
    if not gZoneCache.TryGetValue(lKey, aZone) then
    begin
      aZone := lResolved;
      gZoneCache.Add(lKey, aZone);
    end;
    aNormalizedName := aZone.GetName;
  finally
    gZoneLock.Release;
  end;
  Result := True;
end;

{$IFDEF MAXCRON_TESTS}
procedure RegisterCronZoneForTests(const aName: string; const aSource: ICronZoneRuleSource);
begin
  gZoneLock.Acquire;
  try
    gTestZones.AddOrSetValue(UpperCase(aName), CreateCronZone(aName, aSource));
    gZoneCache.Clear;
  finally
    gZoneLock.Release;
  end;
end;

procedure ClearCronZonesForTests;
begin
  gZoneLock.Acquire;
  try
    gTestZones.Clear;
    gZoneCache.Clear;
  finally
    gZoneLock.Release;
  end;
end;
{$ENDIF}

initialization
  gSystemTimeZone := TCronRtlLocalTimeZone.Create;
  gZoneLock := TCriticalSection.Create;
  gZoneCache := TDictionary<string, ICronZoneRules>.Create;
{$IFDEF MAXCRON_TESTS}
  gTestZones := TDictionary<string, ICronZoneRules>.Create;
{$ENDIF}

finalization
{$IFDEF MAXCRON_TESTS}
  gTestZones.Free;
{$ENDIF}
  gZoneCache.Free;
  gZoneLock.Free;
  gSystemTimeZone := nil;

end.

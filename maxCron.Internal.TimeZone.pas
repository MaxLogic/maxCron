unit maxCron.Internal.TimeZone;
{$I maxCron.inc}
{$IFDEF FPC}{$CODEPAGE UTF8}{$ENDIF}

interface

uses
  {$IFDEF FPC}
  SysUtils
  {$ELSE}
  System.SysUtils
  {$ENDIF};

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

type
  ICronTimeZoneRules = interface
    ['{386A2461-06EF-4CB5-BF7C-1D4C082B39D1}']
    function GetRules: ICronZoneRules;
  end;

// Re-reads the system zone on every call, including its exception behavior.
function CronSystemTimeZone: ICronTimeZone;
function CronSystemZoneRules: ICronZoneRules;
{$IFDEF MAXCRON_TESTS}
function CreateCronProbeZoneForTests(const aZone: ICronTimeZone): ICronZoneRules;
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

{$IFDEF MSWINDOWS}
type
  TCronWindowsSystemTime = record
    wYear, wMonth, wDayOfWeek, wDay, wHour, wMinute, wSecond, wMilliseconds: Word;
  end;
  TCronWindowsZoneInfo = record
    Bias: LongInt;
    StandardName: array[0..31] of WideChar;
    StandardDate: TCronWindowsSystemTime;
    StandardBias: LongInt;
    DaylightName: array[0..31] of WideChar;
    DaylightDate: TCronWindowsSystemTime;
    DaylightBias: LongInt;
  end;
  TCronWindowsDynamicInfo = record
    Zone: TCronWindowsZoneInfo;
    TimeZoneKeyName: array[0..127] of WideChar;
    DynamicDaylightTimeDisabled: Byte;
  end;
  TCronWindowsYearRule = record
    Year, Bias, StandardBias, DaylightBias: Integer;
    StandardDate, DaylightDate: TCronWindowsSystemTime;
  end;
  ICronWindowsZoneOracle = interface
    ['{44DF7553-4728-4FE2-880D-16653CEDDCCA}']
    function OffsetAt(const aUtcMs: Int64): Int64;
    function YearRule(const aYear: Integer): TCronWindowsYearRule;
    function CanCache: Boolean;
  end;
  ICronWindowsZoneSourceStats = interface
    ['{5858F4D6-843D-4487-A64B-49EB0C51975F}']
    function SegmentsComputed: Int64;
    function OracleCalls: Int64;
    function UnexpectedChanges: Int64;
  end;
{$IFDEF MAXCRON_TESTS}
function CreateCronOsLocalTimeZoneForTests: ICronTimeZone;
function CreateCronLocalWindowsSourceForTests: ICronZoneRuleSource;
function CreateCronWindowsZoneSourceForTests(const aOracle: ICronWindowsZoneOracle): ICronZoneRuleSource;
function CreateCronNamedWindowsSourceForTests(const aWindowsId: string): ICronZoneRuleSource;
{$ENDIF}
{$ENDIF}

implementation

uses
  {$IFDEF FPC}
  // Windows before SyncObjs to retain the critical-section class.
  {$IFDEF MSWINDOWS} Windows, {$ENDIF}
  DateUtils, Generics.Collections, Math, SyncObjs,
  {$ELSE}
  System.DateUtils, System.Generics.Collections, System.Math, System.SyncObjs,
  {$IFDEF MSWINDOWS} Winapi.Windows, {$ENDIF}
  {$ENDIF}
  maxCron.Internal.Text, maxCron.Internal.TZif, maxCron.Plan;

{$I maxCron.Internal.TimeZoneNames.inc}

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
  // ICronTimeZone-only adapters must have offset changes at least 15 minutes apart.
  TCronTimeZoneProbeSource = class(TInterfacedObject, ICronZoneRuleSource)
  private
    fZone: ICronTimeZone;
    fLock: TCriticalSection;
    fCached: TCronZonePeriod;
    fHasCached: Boolean;
    function OffsetAt(const aUtcMs: Int64): Int64;
    function FindBoundary(const aLeft, aRight, aOffset: Int64; const aBackwards: Boolean): Int64;
  public
    constructor Create(const aZone: ICronTimeZone);
    destructor Destroy; override;
    function GetRawPeriod(const aUtcMs: Int64): TCronZonePeriod;
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
  gProbeTimeZone: ICronTimeZone;
  gProbeZoneRules: ICronZoneRules;
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

{$IFDEF MSWINDOWS}
type
  TCronWindowsChange = record
    UtcMs, OffsetMs: Int64;
  end;
  TCronWindowsSegment = record
    StartOffsetMs: Int64;
    Changes: TArray<TCronWindowsChange>;
  end;
  TCronWindowsZoneSource = class(TInterfacedObject, ICronZoneRuleSource, ICronWindowsZoneSourceStats)
  private
    fOracle: ICronWindowsZoneOracle;
    fLock: TCriticalSection;
    fSegments: TDictionary<Integer, TCronWindowsSegment>;
    fSegmentsComputed, fOracleCalls, fUnexpectedChanges: Int64;
    function ComputeSegment(const aYear: Integer; var aCalls, aUnexpected: Int64): TCronWindowsSegment;
    function Segment(const aYear: Integer): TCronWindowsSegment;
  public
    constructor Create(const aOracle: ICronWindowsZoneOracle);
    destructor Destroy; override;
    function GetRawPeriod(const aUtcMs: Int64): TCronZonePeriod;
    function SegmentsComputed: Int64;
    function OracleCalls: Int64;
    function UnexpectedChanges: Int64;
  end;
  TCronGetDynamicZone = function(out aInfo: TCronWindowsDynamicInfo): DWORD; stdcall;
  TCronEnumDynamicZone = function(aIndex: DWORD; out aInfo: TCronWindowsDynamicInfo): DWORD; stdcall;
  TCronGetEffectiveYears = function(const aInfo: TCronWindowsDynamicInfo;
    out aFirst, aLast: DWORD): DWORD; stdcall;
  TCronGetYearInfo = function(aYear: Word; const aInfo: TCronWindowsDynamicInfo;
    out aRule: TCronWindowsZoneInfo): LongBool; stdcall;
  TCronWindowsForwardEx = function(const aInfo: TCronWindowsDynamicInfo;
    const aUtc: TCronWindowsSystemTime; out aLocal: TCronWindowsSystemTime): LongBool; stdcall;
  TCronWindowsForwardLocal = function(aInfo: Pointer; const aUtc: TCronWindowsSystemTime;
    out aLocal: TCronWindowsSystemTime): LongBool; stdcall;
  TCronWindowsRecordOracle = class(TInterfacedObject, ICronWindowsZoneOracle)
  protected
    fInfo: TCronWindowsDynamicInfo;
    fRules: TArray<TCronWindowsYearRule>;
  public
    constructor Create(const aInfo: TCronWindowsDynamicInfo);
    function OffsetAt(const aUtcMs: Int64): Int64; virtual; abstract;
    function YearRule(const aYear: Integer): TCronWindowsYearRule;
    function CanCache: Boolean; virtual;
  end;
  TCronWindowsExOracle = class(TCronWindowsRecordOracle)
  public
    function OffsetAt(const aUtcMs: Int64): Int64; override;
  end;
  TCronWindowsLocalOracle = class(TCronWindowsRecordOracle)
  public
    function OffsetAt(const aUtcMs: Int64): Int64; override;
    function CanCache: Boolean; override;
  end;
  TCronOsLocalTimeZone = class(TInterfacedObject, ICronTimeZone, ICronTimeZoneRules)
  private
    fInfo: TCronWindowsDynamicInfo;
    fZone: ICronZoneRules;
    function CurrentZone: ICronZoneRules;
  public
    function GetRules: ICronZoneRules;
    function ToUniversalTime(const aLocal: TDateTime; const aForceDaylight: Boolean): TDateTime;
    function ToLocalTime(const aUtc: TDateTime): TDateTime;
    function IsAmbiguousTime(const aLocal: TDateTime): Boolean;
    function IsInvalidTime(const aLocal: TDateTime): Boolean;
  end;

const
  cCronWindowsFirstYear = 1602;
  cCronWindowsLastYear = 9998;
  cCronWindowsGuardStepMs = cCronMsPerDay;

var
  gGetDynamicZone: TCronGetDynamicZone;
  gEnumDynamicZone: TCronEnumDynamicZone;
  gGetEffectiveYears: TCronGetEffectiveYears;
  gGetYearInfo: TCronGetYearInfo;
  gWindowsForwardEx: TCronWindowsForwardEx;
  gWindowsForwardLocal: TCronWindowsForwardLocal;
  gZoneAdvapi: HMODULE;

// Integer Gregorian calendar on the same 1899-12-30 epoch as the zone engine.
function WindowsCivilDay(const aYear, aMonth, aDay: Integer): Int64;
var
  y, m, lEra, lYearOfEra: Int64;
begin
  y := aYear;
  m := aMonth;
  if m <= 2 then Dec(y);
  lEra := CronFloorDiv(y, 400);
  lYearOfEra := y - lEra * 400;
  if m > 2 then Dec(m, 3) else Inc(m, 9);
  Result := lEra * 146097 + lYearOfEra * 365 + lYearOfEra div 4 - lYearOfEra div 100 +
    (153 * m + 2) div 5 + aDay - 1 - 693899;
end;

function WindowsCivilYear(const aUtcMs: Int64): Integer;
var
  lDay, lEra, lDayOfEra, lYearOfEra, lDayOfYear, m: Int64;
begin
  lDay := CronFloorDiv(aUtcMs, cCronMsPerDay) + 693899;
  lEra := CronFloorDiv(lDay, 146097);
  lDayOfEra := lDay - lEra * 146097;
  lYearOfEra := (lDayOfEra - lDayOfEra div 1460 + lDayOfEra div 36524 - lDayOfEra div 146096) div 365;
  lDayOfYear := lDayOfEra - (365 * lYearOfEra + lYearOfEra div 4 - lYearOfEra div 100);
  m := (5 * lDayOfYear + 2) div 153;
  Result := Integer(lYearOfEra + lEra * 400);
  if m >= 10 then Inc(Result);
end;

function WindowsTransitionMs(const aYear: Integer; const st: TCronWindowsSystemTime): Int64;
var
  lDay, lLast: Integer;
begin
  if st.wYear = 0 then
  begin
    lDay := 1 + (7 + st.wDayOfWeek - ((WindowsCivilDay(aYear, st.wMonth, 1) + 6) mod 7)) mod 7 +
      (Integer(st.wDay) - 1) * 7;
    if st.wMonth = 12 then lLast := 31
    else lLast := Integer(WindowsCivilDay(aYear, st.wMonth + 1, 1) - WindowsCivilDay(aYear, st.wMonth, 1));
    if lDay > lLast then Dec(lDay, 7);
  end else
    lDay := st.wDay;
  Result := WindowsCivilDay(aYear, st.wMonth, lDay) * cCronMsPerDay +
    Int64(st.wHour) * 3600000 + Int64(st.wMinute) * 60000 + Int64(st.wSecond) * 1000;
  // Records suggest candidates; the oracle alone determines offsets and boundaries.
  Inc(Result, st.wMilliseconds);
end;

procedure WindowsMsToSystemTime(const aMs: Int64; out aTime: TCronWindowsSystemTime);
var
  lDay, lEra, lDayOfEra, lYearOfEra, lDayOfYear, m, y, lRemainder: Int64;
begin
  lDay := CronFloorDiv(aMs, cCronMsPerDay);
  lRemainder := aMs - lDay * cCronMsPerDay;
  aTime.wDayOfWeek := Word(((lDay + 6) mod 7 + 7) mod 7);
  Inc(lDay, 693899);
  lEra := CronFloorDiv(lDay, 146097);
  lDayOfEra := lDay - lEra * 146097;
  lYearOfEra := (lDayOfEra - lDayOfEra div 1460 + lDayOfEra div 36524 - lDayOfEra div 146096) div 365;
  lDayOfYear := lDayOfEra - (365 * lYearOfEra + lYearOfEra div 4 - lYearOfEra div 100);
  m := (5 * lDayOfYear + 2) div 153;
  aTime.wDay := Word(lDayOfYear - (153 * m + 2) div 5 + 1);
  y := lYearOfEra + lEra * 400;
  if m < 10 then Inc(m, 3) else Dec(m, 9);
  if m <= 2 then Inc(y);
  aTime.wYear := Word(y);
  aTime.wMonth := Word(m);
  aTime.wHour := Word(lRemainder div 3600000);
  aTime.wMinute := Word(lRemainder div 60000 mod 60);
  aTime.wSecond := Word(lRemainder div 1000 mod 60);
  aTime.wMilliseconds := Word(lRemainder mod 1000);
end;

function WindowsSystemTimeToMs(const aTime: TCronWindowsSystemTime): Int64;
begin
  Result := WindowsCivilDay(aTime.wYear, aTime.wMonth, aTime.wDay) * cCronMsPerDay +
    Int64(aTime.wHour) * 3600000 + Int64(aTime.wMinute) * 60000 +
    Int64(aTime.wSecond) * 1000 + aTime.wMilliseconds;
end;

function WindowsSameIdentity(const aFirst, aSecond: TCronWindowsDynamicInfo): Boolean;
begin
  Result := (string(PWideChar(@aFirst.TimeZoneKeyName[0])) = string(PWideChar(@aSecond.TimeZoneKeyName[0]))) and
    (aFirst.Zone.Bias = aSecond.Zone.Bias) and
    (aFirst.DynamicDaylightTimeDisabled = aSecond.DynamicDaylightTimeDisabled);
end;

constructor TCronWindowsRecordOracle.Create(const aInfo: TCronWindowsDynamicInfo);
var
  lFirst, lLast: DWORD;
  lNative: TCronWindowsZoneInfo;
  lDynamic: Boolean;
  i, y: Integer;
begin
  inherited Create;
  fInfo := aInfo;
  if not Assigned(gGetYearInfo) then raise Exception.Create('Windows year rules API is unavailable');
  lFirst := YearOf(Date);
  lLast := lFirst;
  lDynamic := False;
  if Assigned(gGetEffectiveYears) then
    lDynamic := gGetEffectiveYears(aInfo, lFirst, lLast) = ERROR_SUCCESS;
  if not lDynamic then
  begin
    lFirst := YearOf(Date);
    lLast := lFirst;
  end;
  if (lFirst < 2) or (lLast > 9997) or (lFirst > lLast) then
    raise Exception.Create('Invalid Windows effective year range');
  if lDynamic then SetLength(fRules, lLast - lFirst + 3)
  else SetLength(fRules, 1);
  for i := 0 to High(fRules) do
  begin
    if lDynamic then y := Integer(lFirst) - 1 + i else y := lFirst;
    if not gGetYearInfo(y, aInfo, lNative) then RaiseLastOSError;
    fRules[i].Year := y;
    fRules[i].Bias := lNative.Bias;
    fRules[i].StandardBias := lNative.StandardBias;
    fRules[i].DaylightBias := lNative.DaylightBias;
    fRules[i].StandardDate := lNative.StandardDate;
    fRules[i].DaylightDate := lNative.DaylightDate;
  end;
end;

function TCronWindowsRecordOracle.YearRule(const aYear: Integer): TCronWindowsYearRule;
var
  lo, hi, m: Integer;
begin
  lo := 0;
  hi := High(fRules);
  while lo < hi do
  begin
    m := lo + (hi - lo + 1) div 2;
    if fRules[m].Year <= aYear then lo := m else hi := m - 1;
  end;
  Result := fRules[lo];
end;

function TCronWindowsRecordOracle.CanCache: Boolean;
begin
  Result := True;
end;

function WindowsCheckedOffset(const aLocal: TCronWindowsSystemTime; const aUtcMs: Int64): Int64;
begin
  Result := WindowsSystemTimeToMs(aLocal) - aUtcMs;
  if (Result mod 1000 <> 0) or (Result < -cCronZoneMaxAbsOffsetMs) or
    (Result > cCronZoneMaxAbsOffsetMs) then
    raise Exception.Create('Windows time zone conversion returned an invalid offset');
end;

function TCronWindowsExOracle.OffsetAt(const aUtcMs: Int64): Int64;
var
  lUtc, lLocal: TCronWindowsSystemTime;
begin
  WindowsMsToSystemTime(aUtcMs, lUtc);
  if not gWindowsForwardEx(fInfo, lUtc, lLocal) then
    raise EOSError.CreateFmt('Windows time zone conversion failed for "%s" (error %d)',
      [string(PWideChar(@fInfo.TimeZoneKeyName[0])), GetLastError]);
  Result := WindowsCheckedOffset(lLocal, aUtcMs);
end;

function TCronWindowsLocalOracle.OffsetAt(const aUtcMs: Int64): Int64;
var
  lUtc, lLocal: TCronWindowsSystemTime;
begin
  WindowsMsToSystemTime(aUtcMs, lUtc);
  if not gWindowsForwardLocal(nil, lUtc, lLocal) then
    raise EOSError.CreateFmt('Windows time zone conversion failed for "%s" (error %d)', ['LOCAL', GetLastError]);
  Result := WindowsCheckedOffset(lLocal, aUtcMs);
end;

function TCronWindowsLocalOracle.CanCache: Boolean;
var
  lInfo: TCronWindowsDynamicInfo;
begin
  if gGetDynamicZone(lInfo) = DWORD($FFFFFFFF) then RaiseLastOSError;
  Result := WindowsSameIdentity(lInfo, fInfo);
end;

constructor TCronWindowsZoneSource.Create(const aOracle: ICronWindowsZoneOracle);
begin
  inherited Create;
  if aOracle = nil then raise Exception.Create('Windows zone oracle is required');
  fOracle := aOracle;
  fLock := TCriticalSection.Create;
  fSegments := TDictionary<Integer, TCronWindowsSegment>.Create;
end;

destructor TCronWindowsZoneSource.Destroy;
begin
  fSegments.Free;
  fLock.Free;
  inherited;
end;

function TCronWindowsZoneSource.ComputeSegment(const aYear: Integer;
  var aCalls, aUnexpected: Int64): TCronWindowsSegment;
var
  lCandidates, lQueries: TList<Int64>;
  lChanges: TList<TCronWindowsChange>;
  lCands, lPoints: TArray<Int64>;
  lPrev, lCur: TCronWindowsYearRule;
  lTime: TCronWindowsSystemTime;
  lChange: TCronWindowsChange;
  lo, hi, j, lStd, lDst, lValue, lQueryValue, xs, q, a, b, m, lAfter, t: Int64;
  y, i, k, lLeft, lRight, lMiddle: Integer;
  function Query(const aInstant: Int64): Int64;
  begin
    Inc(aCalls);
    Result := fOracle.OffsetAt(aInstant);
  end;
  procedure Candidate(const aInstant: Int64);
  var
    lRounded: Int64;
  begin
    lRounded := -CronFloorDiv(-aInstant, 1000) * 1000;
    if (lRounded > lo) and (lRounded < hi) then lCandidates.Add(lRounded);
  end;
begin
  lo := WindowsCivilDay(aYear, 1, 1) * cCronMsPerDay;
  hi := WindowsCivilDay(aYear + 1, 1, 1) * cCronMsPerDay;
  lCandidates := TList<Int64>.Create;
  lQueries := TList<Int64>.Create;
  lChanges := TList<TCronWindowsChange>.Create;
  try
    for y := aYear - 1 to aYear + 1 do
    begin
      lPrev := fOracle.YearRule(y - 1);
      lCur := fOracle.YearRule(y);
      j := WindowsCivilDay(y, 1, 1) * cCronMsPerDay;
      Candidate(j);
      Candidate(j + (Int64(lPrev.Bias) + lPrev.StandardBias) * 60000);
      Candidate(j + (Int64(lPrev.Bias) + lPrev.DaylightBias) * 60000);
      lStd := -(Int64(lCur.Bias) + lCur.StandardBias) * 60000;
      lDst := -(Int64(lCur.Bias) + lCur.DaylightBias) * 60000;
      Candidate(j - lStd);
      Candidate(j - lDst);
      for k := 0 to 1 do
      begin
        if k = 0 then lTime := lCur.DaylightDate else lTime := lCur.StandardDate;
        if (lTime.wMonth < 1) or (lTime.wMonth > 12) or (lTime.wDay < 1) or
          (lTime.wHour > 23) or (lTime.wMinute > 59) or (lTime.wSecond > 59) or
          (lTime.wMilliseconds > 999) then Continue;
        if lTime.wYear = 0 then
        begin
          if (lTime.wDay > 5) or (lTime.wDayOfWeek > 6) then Continue;
        end else if lTime.wDay > 31 then Continue;
        t := WindowsTransitionMs(y, lTime);
        Candidate(t - lStd);
        Candidate(t - lDst);
      end;
    end;
    lCands := lCandidates.ToArray;
    {$IFDEF FPC} TArrayHelper<Int64>.Sort(lCands); {$ELSE} TArray.Sort<Int64>(lCands); {$ENDIF}
    lLeft := 0;
    for i := 0 to High(lCands) do
      if (lLeft = 0) or (lCands[i] <> lCands[lLeft - 1]) then
      begin
        lCands[lLeft] := lCands[i];
        Inc(lLeft);
      end;
    SetLength(lCands, lLeft);
    // The query list is sorted and deduplicated independently.
    for i := 0 to High(lCands) do
      if (i = 0) or (lCands[i] <> lCands[i - 1]) then
      begin
        if lCands[i] - 1000 > lo then lQueries.Add(lCands[i] - 1000);
        lQueries.Add(lCands[i]);
      end;
    q := lo + cCronWindowsGuardStepMs;
    while q < hi do
    begin
      lQueries.Add(q);
      Inc(q, cCronWindowsGuardStepMs);
    end;
    lQueries.Add(hi - 1000);
    lPoints := lQueries.ToArray;
    {$IFDEF FPC} TArrayHelper<Int64>.Sort(lPoints); {$ELSE} TArray.Sort<Int64>(lPoints); {$ENDIF}
    lValue := Query(lo);
    Result.StartOffsetMs := lValue;
    xs := lo;
    for i := 0 to High(lPoints) do
    begin
      q := lPoints[i];
      if (q <= lo) or ((i > 0) and (q = lPoints[i - 1])) then Continue;
      lQueryValue := Query(q);
      while lQueryValue <> lValue do
      begin
        a := xs;
        b := q;
        lAfter := lQueryValue;
        while b - a > 1000 do
        begin
          m := a + ((b - a) div 2000) * 1000;
          t := Query(m);
          if t = lValue then a := m
          else begin
            b := m;
            lAfter := t;
          end;
        end;
        lChange.UtcMs := b;
        lChange.OffsetMs := lAfter;
        lChanges.Add(lChange);
        lLeft := 0;
        lRight := Length(lCands);
        while lLeft < lRight do
        begin
          lMiddle := lLeft + (lRight - lLeft) div 2;
          if lCands[lMiddle] < b then lLeft := lMiddle + 1 else lRight := lMiddle;
        end;
        if (lLeft = Length(lCands)) or (lCands[lLeft] <> b) then Inc(aUnexpected);
        lValue := lAfter;
        xs := b;
      end;
      xs := q;
    end;
    Result.Changes := lChanges.ToArray;
  finally
    lChanges.Free;
    lQueries.Free;
    lCandidates.Free;
  end;
end;

function TCronWindowsZoneSource.Segment(const aYear: Integer): TCronWindowsSegment;
var
  lComputed: TCronWindowsSegment;
  lCanCache: Boolean;
  lCalls, lUnexpected: Int64;
begin
  // CanCache can call Windows for LOCAL. Evaluate it before taking the source lock.
  lCanCache := fOracle.CanCache;
  fLock.Acquire;
  try
    if lCanCache and fSegments.TryGetValue(aYear, Result) then Exit;
    Inc(fSegmentsComputed);
  finally
    fLock.Release;
  end;
  lCalls := 0;
  lUnexpected := 0;
  try
    lComputed := ComputeSegment(aYear, lCalls, lUnexpected);
  finally
    fLock.Acquire;
    try
      Inc(fOracleCalls, lCalls);
      Inc(fUnexpectedChanges, lUnexpected);
    finally
      fLock.Release;
    end;
  end;
  lCanCache := fOracle.CanCache and lCanCache;
  fLock.Acquire;
  try
    if lCanCache then
    begin
      if not fSegments.TryGetValue(aYear, Result) then
      begin
        fSegments.Add(aYear, lComputed);
        Result := lComputed;
      end;
    end else Result := lComputed;
  finally
    fLock.Release;
  end;
end;

function TCronWindowsZoneSource.GetRawPeriod(const aUtcMs: Int64): TCronZonePeriod;
var
  y, lo, hi, m: Integer;
  lSegment: TCronWindowsSegment;
begin
  y := WindowsCivilYear(aUtcMs);
  if y < cCronWindowsFirstYear then
  begin
    lSegment := Segment(cCronWindowsFirstYear);
    Result.StartUtcMs := cCronZoneUnboundedStart;
    Result.EndUtcMs := WindowsCivilDay(cCronWindowsFirstYear, 1, 1) * cCronMsPerDay;
    Result.OffsetMs := lSegment.StartOffsetMs;
    Exit;
  end;
  if y > cCronWindowsLastYear then
  begin
    lSegment := Segment(cCronWindowsLastYear);
    Result.StartUtcMs := WindowsCivilDay(cCronWindowsLastYear + 1, 1, 1) * cCronMsPerDay;
    Result.EndUtcMs := cCronZoneUnboundedEnd;
    Result.OffsetMs := lSegment.StartOffsetMs;
    if Length(lSegment.Changes) > 0 then Result.OffsetMs := lSegment.Changes[High(lSegment.Changes)].OffsetMs;
    Exit;
  end;
  lSegment := Segment(y);
  lo := 0;
  hi := Length(lSegment.Changes);
  while lo < hi do
  begin
    m := lo + (hi - lo) div 2;
    if lSegment.Changes[m].UtcMs <= aUtcMs then lo := m + 1 else hi := m;
  end;
  Result.StartUtcMs := WindowsCivilDay(y, 1, 1) * cCronMsPerDay;
  Result.EndUtcMs := WindowsCivilDay(y + 1, 1, 1) * cCronMsPerDay;
  Result.OffsetMs := lSegment.StartOffsetMs;
  if lo > 0 then
  begin
    Result.StartUtcMs := lSegment.Changes[lo - 1].UtcMs;
    Result.OffsetMs := lSegment.Changes[lo - 1].OffsetMs;
  end;
  if lo < Length(lSegment.Changes) then Result.EndUtcMs := lSegment.Changes[lo].UtcMs;
end;

function TCronWindowsZoneSource.SegmentsComputed: Int64;
begin
  fLock.Acquire;
  try Result := fSegmentsComputed; finally fLock.Release; end;
end;

function TCronWindowsZoneSource.OracleCalls: Int64;
begin
  fLock.Acquire;
  try Result := fOracleCalls; finally fLock.Release; end;
end;

function TCronWindowsZoneSource.UnexpectedChanges: Int64;
begin
  fLock.Acquire;
  try Result := fUnexpectedChanges; finally fLock.Release; end;
end;

function NamedWindowsSource(const aWindowsId: string): ICronZoneRuleSource;
var
  lInfo: TCronWindowsDynamicInfo;
  lIndex, lStatus: DWORD;
  lOracle: ICronWindowsZoneOracle;
begin
  if not Assigned(gEnumDynamicZone) or not Assigned(gGetEffectiveYears) or not Assigned(gGetYearInfo) or
    not Assigned(gWindowsForwardEx) then
    raise Exception.Create('named time zones need Windows 8 or later; set MAXCRON_TZDIR to use TZif data');
  lIndex := 0;
  repeat
    lStatus := gEnumDynamicZone(lIndex, lInfo);
    if lStatus = ERROR_NO_MORE_ITEMS then
      raise Exception.CreateFmt('Windows time zone "%s" is not installed', [aWindowsId]);
    if lStatus <> ERROR_SUCCESS then
      raise EOSError.CreateFmt('Windows time zone enumeration failed (%d)', [lStatus]);
    if CronUpperAscii(string(PWideChar(@lInfo.TimeZoneKeyName[0]))) = CronUpperAscii(aWindowsId) then
    begin
      lInfo.DynamicDaylightTimeDisabled := 0;
      lOracle := TCronWindowsExOracle.Create(lInfo);
      Exit(TCronWindowsZoneSource.Create(lOracle));
    end;
    Inc(lIndex);
  until False;
end;

function TCronOsLocalTimeZone.CurrentZone: ICronZoneRules;
var
  lInfo: TCronWindowsDynamicInfo;
  lCandidate: ICronZoneRules;
  lOracle: ICronWindowsZoneOracle;
begin
  if not Assigned(gGetDynamicZone) then raise Exception.Create('Windows dynamic zone API is unavailable');
  if not Assigned(gWindowsForwardLocal) then raise Exception.Create('Windows local conversion API is unavailable');
  if gGetDynamicZone(lInfo) = DWORD($FFFFFFFF) then RaiseLastOSError;
  gZoneLock.Acquire;
  try
    if (fZone <> nil) and WindowsSameIdentity(lInfo, fInfo) then Exit(fZone);
  finally
    gZoneLock.Release;
  end;
  // Snapshotting records calls Windows. Construct outside the global cache lock.
  lOracle := TCronWindowsLocalOracle.Create(lInfo);
  lCandidate := CreateCronZone('LOCAL', TCronWindowsZoneSource.Create(lOracle));
  gZoneLock.Acquire;
  try
    if (fZone = nil) or not WindowsSameIdentity(lInfo, fInfo) then
    begin
      fZone := lCandidate;
      fInfo := lInfo;
    end;
    Result := fZone;
  finally
    gZoneLock.Release;
  end;
end;

function TCronOsLocalTimeZone.GetRules: ICronZoneRules;
begin
  Result := CurrentZone;
end;

function TCronOsLocalTimeZone.ToUniversalTime(const aLocal: TDateTime;
  const aForceDaylight: Boolean): TDateTime;
var
  lMap: TCronLocalMapping;
begin
  lMap := CurrentZone.MapLocal(CronDateTimeToMs(aLocal));
  case lMap.Kind of
    clkGap: raise ELocalTimeInvalid.Create('Invalid local time');
    clkOverlap:
      if aForceDaylight then Result := CronMsToDateTime(lMap.FirstUtcMs)
      else Result := CronMsToDateTime(lMap.SecondUtcMs);
  else
    Result := CronMsToDateTime(lMap.FirstUtcMs);
  end;
end;

function TCronOsLocalTimeZone.ToLocalTime(const aUtc: TDateTime): TDateTime;
begin
  Result := CronMsToDateTime(CurrentZone.UtcToLocalMs(CronDateTimeToMs(aUtc)));
end;

function TCronOsLocalTimeZone.IsAmbiguousTime(const aLocal: TDateTime): Boolean;
begin
  Result := CurrentZone.MapLocal(CronDateTimeToMs(aLocal)).Kind = clkOverlap;
end;

function TCronOsLocalTimeZone.IsInvalidTime(const aLocal: TDateTime): Boolean;
begin
  Result := CurrentZone.MapLocal(CronDateTimeToMs(aLocal)).Kind = clkGap;
end;

procedure InitializeWindowsZone;
var
  lKernel: HMODULE;
begin
  lKernel := GetModuleHandleW('kernel32.dll');
  gZoneAdvapi := LoadLibraryW('advapi32.dll');
  gGetDynamicZone := TCronGetDynamicZone(GetProcAddress(lKernel, 'GetDynamicTimeZoneInformation'));
  gGetYearInfo := TCronGetYearInfo(GetProcAddress(lKernel, 'GetTimeZoneInformationForYear'));
  gWindowsForwardEx := TCronWindowsForwardEx(GetProcAddress(lKernel, 'SystemTimeToTzSpecificLocalTimeEx'));
  gWindowsForwardLocal := TCronWindowsForwardLocal(GetProcAddress(lKernel, 'SystemTimeToTzSpecificLocalTime'));
  if gZoneAdvapi <> 0 then
  begin
    gEnumDynamicZone := TCronEnumDynamicZone(GetProcAddress(gZoneAdvapi, 'EnumDynamicTimeZoneInformation'));
    gGetEffectiveYears := TCronGetEffectiveYears(GetProcAddress(gZoneAdvapi, 'GetDynamicTimeZoneInformationEffectiveYears'));
  end;
end;

{$IFDEF MAXCRON_TESTS}
function CreateCronOsLocalTimeZoneForTests: ICronTimeZone;
begin
  Result := TCronOsLocalTimeZone.Create;
end;

function CreateCronLocalWindowsSourceForTests: ICronZoneRuleSource;
var
  lInfo: TCronWindowsDynamicInfo;
  lOracle: ICronWindowsZoneOracle;
begin
  if not Assigned(gGetDynamicZone) or not Assigned(gWindowsForwardLocal) then
    raise Exception.Create('Windows local conversion API is unavailable');
  if gGetDynamicZone(lInfo) = DWORD($FFFFFFFF) then RaiseLastOSError;
  lOracle := TCronWindowsLocalOracle.Create(lInfo);
  Result := TCronWindowsZoneSource.Create(lOracle);
end;

function CreateCronWindowsZoneSourceForTests(const aOracle: ICronWindowsZoneOracle): ICronZoneRuleSource;
begin
  Result := TCronWindowsZoneSource.Create(aOracle);
end;

function CreateCronNamedWindowsSourceForTests(const aWindowsId: string): ICronZoneRuleSource;
begin
  Result := NamedWindowsSource(aWindowsId);
end;
{$ENDIF}
{$ENDIF}

function CronSystemTimeZone: ICronTimeZone;
begin
{$IFDEF MAXCRON_TESTS}
  if Assigned(gTestTimeZone) then
    Exit(gTestTimeZone);
{$ENDIF}
  Result := gSystemTimeZone;
end;

function CronSystemZoneRules: ICronZoneRules;
var
  lZone: ICronTimeZone;
  lProvider: ICronTimeZoneRules;
begin
  lZone := CronSystemTimeZone;
  if Supports(lZone, ICronTimeZoneRules, lProvider) then Exit(lProvider.GetRules);
  gZoneLock.Acquire;
  try
    if (gProbeZoneRules = nil) or (gProbeTimeZone <> lZone) then
    begin
      gProbeTimeZone := lZone;
      gProbeZoneRules := CreateCronZone('LOCAL', TCronTimeZoneProbeSource.Create(lZone));
    end;
    Result := gProbeZoneRules;
  finally
    gZoneLock.Release;
  end;
end;

{$IFDEF MAXCRON_TESTS}
function CreateCronProbeZoneForTests(const aZone: ICronTimeZone): ICronZoneRules;
begin
  Result := CreateCronZone('LOCAL probe', TCronTimeZoneProbeSource.Create(aZone));
end;
{$ENDIF}

constructor TCronTimeZoneProbeSource.Create(const aZone: ICronTimeZone);
begin
  inherited Create;
  if aZone = nil then raise Exception.Create('System zone is required');
  fZone := aZone;
  fLock := TCriticalSection.Create;
end;

destructor TCronTimeZoneProbeSource.Destroy;
begin
  fLock.Free;
  inherited;
end;

function TCronTimeZoneProbeSource.OffsetAt(const aUtcMs: Int64): Int64;
begin
  Result := CronDateTimeToMs(fZone.ToLocalTime(CronMsToDateTime(aUtcMs))) - aUtcMs;
end;

function TCronTimeZoneProbeSource.FindBoundary(const aLeft, aRight, aOffset: Int64;
  const aBackwards: Boolean): Int64;
var
  lo, hi, m: Int64;
begin
  lo := aLeft;
  hi := aRight;
  while hi - lo > cCronMsPerSecond do
  begin
    m := lo + ((hi - lo) div (2 * cCronMsPerSecond)) * cCronMsPerSecond;
    if (OffsetAt(m) = aOffset) = aBackwards then hi := m
    else lo := m;
  end;
  Result := hi;
end;

function TCronTimeZoneProbeSource.GetRawPeriod(const aUtcMs: Int64): TCronZonePeriod;
const
  cProbeStepMs = Int64(15) * 60000;
var
  lUtcMs, lCursor, lNext, lLimit: Int64;
begin
  fLock.Acquire;
  try
    if fHasCached and (aUtcMs >= fCached.StartUtcMs) and (aUtcMs < fCached.EndUtcMs) then Exit(fCached);
  finally
    fLock.Release;
  end;
  lUtcMs := CronFloorDiv(aUtcMs, cCronMsPerSecond) * cCronMsPerSecond;
  Result.OffsetMs := OffsetAt(lUtcMs);
  lCursor := lUtcMs;
  lLimit := lUtcMs - cCronZoneWindowMs;
  Result.StartUtcMs := lLimit;
  while lCursor > lLimit do
  begin
    lNext := Max(lLimit, lCursor - cProbeStepMs);
    if OffsetAt(lNext) <> Result.OffsetMs then
    begin
      Result.StartUtcMs := FindBoundary(lNext, lCursor, Result.OffsetMs, True);
      Break;
    end;
    lCursor := lNext;
  end;
  lCursor := lUtcMs;
  lLimit := lUtcMs + cCronZoneWindowMs;
  Result.EndUtcMs := lLimit;
  while lCursor < lLimit do
  begin
    lNext := Min(lLimit, lCursor + cProbeStepMs);
    if OffsetAt(lNext) <> Result.OffsetMs then
    begin
      Result.EndUtcMs := FindBoundary(lCursor, lNext, Result.OffsetMs, False);
      Break;
    end;
    lCursor := lNext;
  end;
  fLock.Acquire;
  try
    fCached := Result;
    fHasCached := True;
  finally
    fLock.Release;
  end;
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
    {$IFDEF FPC} TArrayHelper<Int64>.Sort(lPoints); {$ELSE} TArray.Sort<Int64>(lPoints); {$ENDIF}
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
  {$IFDEF FPC} TArrayHelper<Int64>.Sort(lPoints); {$ELSE} TArray.Sort<Int64>(lPoints); {$ENDIF}
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

function ZoneNameIndex(const aName: string): Integer;
var
  lo, hi, m, c: Integer;
  lName: string;
begin
  lName := CronUpperAscii(aName);
  lo := Low(cCronZoneNames);
  hi := High(cCronZoneNames);
  while lo <= hi do
  begin
    m := lo + (hi - lo) div 2;
    c := CompareStr(CronUpperAscii(cCronZoneNames[m].Name), lName);
    if c = 0 then Exit(m);
    if c < 0 then lo := m + 1 else hi := m - 1;
  end;
  Result := -1;
end;

function TryFixedZone(const aName: string; out aOffsetMs: Int64; out aNormalized: string): Boolean;
var
  lName, lSuffix: string;
  lHours, lSign: Integer;
begin
  lName := CronUpperAscii(aName);
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
  if not CronTryStrToInt(lSuffix, lHours) then Exit;
  if (CronIntToStr(lHours) <> lSuffix) or (lHours < 0) or (lHours > 14) then Exit;
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
  lIndex: Integer;
begin
  aZone := nil;
  aNormalizedName := aName;
  aError := '';
  if not IsCronZoneNameSyntax(aName) then
  begin
    aError := 'invalid IANA name syntax';
    Exit(False);
  end;
  lKey := CronUpperAscii(aName) + #0 + aDataRoot;
  gZoneLock.Acquire;
  try
{$IFDEF MAXCRON_TESTS}
    if gTestZones.TryGetValue(CronUpperAscii(aName), aZone) then
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
    lIndex := ZoneNameIndex(aName);
    if (lIndex >= 0) and (cCronZoneNames[lIndex].WindowsId = '') then
    begin
      aNormalizedName := cCronZoneNames[lIndex].Name;
      lSource := TCronFixedZoneSource.Create(Int64(cCronZoneNames[lIndex].FixedOffsetSeconds) * 1000);
    end else if aDataRoot = '' then
    begin
      if lIndex < 0 then
      begin
        aError := 'not in the time zone name table';
        Exit(False);
      end;
      {$IFDEF MSWINDOWS}
      try
        lSource := NamedWindowsSource(cCronZoneNames[lIndex].WindowsId);
      except
        on E: Exception do
        begin
          aError := E.Message;
          Exit(False);
        end;
      end;
      aNormalizedName := cCronZoneNames[lIndex].Name;
      {$ELSE}
      aError := 'set MAXCRON_TZDIR to use TZif data';
      Exit(False);
      {$ENDIF}
    end else begin
      if not TryLoadCronTzifFile(aDataRoot, aName, lSource, lPath, aError) then Exit(False);
      // The file loader preserves directory spelling, including TZif-only aliases.
      aNormalizedName := Copy(lPath, Length(IncludeTrailingPathDelimiter(aDataRoot)) + 1, MaxInt);
      aNormalizedName := StringReplace(aNormalizedName, PathDelim, '/', [rfReplaceAll]);
    end;
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
    gTestZones.AddOrSetValue(CronUpperAscii(aName), CreateCronZone(aName, aSource));
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
  {$IFDEF MSWINDOWS} InitializeWindowsZone; {$ENDIF}
  {$IFDEF MSWINDOWS}
  gSystemTimeZone := TCronOsLocalTimeZone.Create;
  {$ELSE}
  gSystemTimeZone := TCronRtlLocalTimeZone.Create;
  {$ENDIF}
  gZoneLock := TCriticalSection.Create;
  gZoneCache := TDictionary<string, ICronZoneRules>.Create;
{$IFDEF MAXCRON_TESTS}
  gTestZones := TDictionary<string, ICronZoneRules>.Create;
{$ENDIF}

finalization
{$IFDEF MAXCRON_TESTS}
  gTestZones.Free;
{$ENDIF}
  gProbeZoneRules := nil;
  gProbeTimeZone := nil;
  gZoneCache.Free;
  gZoneLock.Free;
  {$IFDEF MSWINDOWS} if gZoneAdvapi <> 0 then FreeLibrary(gZoneAdvapi); {$ENDIF}
  gSystemTimeZone := nil;

end.

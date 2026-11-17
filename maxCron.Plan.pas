unit maxCron.Plan;
{$I maxCron.inc}

interface

uses
  System.SysUtils;

const
  cIntervalPlanInvalid = 'Invalid interval plan';
  cIntervalPlanOutOfRange = 'Interval plan value out of range';
  cCronUsPerMs = 1000;
  cCronUsPerSecond = 1000000;
  cCronMsPerSecond = 1000;
  cCronMsPerDay = 86400000;
  cCronSecondsPerDay = 86400;
  /// Default result limit for plan range queries.
  cCronQueryDefaultLimit = 10000;

type
  /// Microseconds since 1899-12-30 00:00 on the originating wall clock.
  TCronInstantUs = Int64;

  TCronIntervalPlan = record
    IntervalMs: Cardinal;
    FixedDelay: Boolean;
    ExecutionLimit: LongWord;
  end;

  TCronSchedulePlan = class;

  /// <summary>
  /// How we combine Day-of-Month (DOM) and Day-of-Week (DOW) when both are restricted (not '*').
  /// dmAnd keeps our legacy maxCron behavior; dmOr matches classic crontab OR semantics.
  /// </summary>
  TmaxCronDayMatchMode = (dmDefault, dmAnd, dmOr);

  /// <summary>
  /// Cron parsing dialect. Use cdQuartzSecondsFirst for Quartz-style seconds-first 6/7-field plans
  /// and for expressions that use Quartz-style modifiers like ?, W, LW, or # to avoid field-order surprises.
  /// </summary>
  TmaxCronDialect = (cdStandard, cdMaxCron, cdQuartzSecondsFirst);

  TDates = array of TDateTime;
  TWordArray = array of Word;
  // those are the parts as they appear in that order
  TPartKind = (
    ckMinute = 0,
    ckHour,
    ckDayOfTheMonth,
    ckMonth,
    ckDayOfTheWeek,
    ckYear,
    ckSecond
    // ckExecutionLimit  - this is not a part kind but it is a part of the schedule string
    );

  /// <summary>
  /// Day-of-Month special modifiers: L, L-n, LW, LW-n, nW and L-nW.
  /// </summary>
  TCronDomModifier = (
    cdmNone,
    cdmLastDay,
    cdmNearestWeekday,
    cdmLastWeekday,
    cdmLastDayNearestWeekday
    );

  /// <summary>
  /// Day-of-Week special modifiers (Quartz-style).
  /// </summary>
  TCronDowModifier = (
    cdwNone,
    cdwLastWeekday,
    cdwNthWeekday
    );

  TPlan = record
  private
    fDialect: TmaxCronDialect;
    function asString: String;
    procedure setText(const Value: string);
  public
    parts: array [0 .. 7] of string;

    property Minute: string read parts[0] write parts[0];
    property Hour: string read parts[1] write parts[1];
    property DayOfTheMonth: string read parts[2] write parts[2];
    property Month: string read parts[3] write parts[3];
    property DayOfTheWeek: string read parts[4] write parts[4];
    property Year: string read parts[5] write parts[5];
    property Second: string read parts[6] write parts[6];
    property ExecutionLimit: string read parts[7] write parts[7];
    /// <summary>
    /// Controls how <c>Text</c> is parsed and emitted (standard 5-field, maxCron 5-8, or Quartz seconds-first).
    /// </summary>
    property Dialect: TmaxCronDialect read fDialect write fDialect;

    /// <summary>
    /// Gets or sets the cron text, respecting the current Dialect when reading or writing.
    /// </summary>
    property text: string read asString write setText;

    // resets all values to their defaults
    procedure reset;
  end;

  TCronPart = class(TObject)
  private
    FData: string;
    FValidFrom, FValidTo: word;
    fPartKind: TPartKind;
    fFullrange: boolean;
    fRange: array of word;
    FCount: integer;
    fNeedsParse: Boolean;
    fNoSpec: Boolean;
    fDomModifier: TCronDomModifier;
    fDomValue: Word;
    fDowModifier: TCronDowModifier;
    fDowValue: Word;
    fDowNth: Word;
    fDowOneBased: Boolean;
    fHashSeed: string;

    procedure Parse;
    procedure SetData(const Value: string);
    procedure ParsePart(const Value: string);
    function ReplaceMonthNames(const Value: string): string;
    function ReplaceDaynames(const Value: string): string;
    Procedure Add2Range(Value: word);
    function FindInRange(Value: word; out index: integer): boolean;
    function TryPrevVal(const aValue: Word; out aResult: Word): Boolean;
    function HasSpecial: Boolean;
    function TryParseSpecialToken(const aToken: string): Boolean;
    function TryParseDomSpecial(const aToken: string): Boolean;
    function TryParseDowSpecial(const aToken: string): Boolean;
    function NormalizeDowValue(const aValue: Integer): Integer;
    function Hash32(const aValue: string): Cardinal;
    function TryParseHashedToken(const aValue: string): Boolean;
    function GetLastDayOfMonth(const aYear, aMonth: Word): Word;
    function GetLastWeekdayOffsetOfMonth(const aYear, aMonth, aOffset: Word; out aDay: Word): Boolean;
    function GetLastWeekdayOfMonth(const aYear, aMonth: Word; out aDay: Word): Boolean;
    function GetNearestWeekdayTo(const aYear, aMonth, aDay: Word; out aNearestDay: Word): Boolean;
    function GetNthWeekdayOfMonth(const aYear, aMonth, aDow, aNth: Word; out aDay: Word): Boolean;
    function GetLastDowOfMonth(const aYear, aMonth, aDow: Word; out aDay: Word): Boolean;
    function TryGetDomSpecialDay(const aYear, aMonth: Word; out aDay: Word): Boolean;
    function TryGetDowSpecialDay(const aYear, aMonth: Word; out aDay: Word): Boolean;

    function PushYear(var NextDate: TDateTime): boolean;
    function PushMonth(var NextDate: TDateTime): boolean;
    /// <summary>
    /// Advances NextDate to the next matching DOM, including special modifiers (L/W/LW).
    /// If the month-relative target already passed, we move to the next month and recompute.
    /// </summary>
    function PushDayOfMonth(var NextDate: TDateTime): boolean;
    /// <summary>
    /// Advances NextDate to the next matching DOW, including special modifiers (nL/n#k).
    /// If the month-relative target already passed, we move to the next month and recompute.
    /// </summary>
    function PushDayOfWeek(var NextDate: TDateTime): boolean;
    function PushHour(var NextDate: TDateTime): boolean;
    function PushMinute(var NextDate: TDateTime): boolean;
    function PushSecond(var NextDate: TDateTime): boolean;
    function GetFullrange: boolean;
  public
    constructor Create(aPartKind: TPartKind);
    destructor Destroy; override;

    procedure Clear;
    function NextVal(v: word): word;
    function IsAny: Boolean;
    function IsNoSpec: Boolean;
    function HasSpecialTokens: Boolean;
    function TryGetSingleValue(out aValue: Word): Boolean;
    function TryGetStep(out aStart, aStep: Word; out aCoversFullRange: Boolean): Boolean;
    function GetValues(out aValues: TWordArray): Boolean;
    function DescribeDomSpecial: string;

    property Data: string read FData write SetData;
    property PartKind: TPartKind read fPartKind;
    property Fullrange: boolean read GetFullrange;
  end;

  // this is a helper class to calculate and parse the schedule plan
  TCronSchedulePlan = class
  private
    FSecond: TCronPart;
    FMinute: TCronPart;
    FHour: TCronPart;
    FMonth: TCronPart;
    FDayOfTheMonth: TCronPart;
    FDayOfTheWeek: TCronPart;
    FYear: TCronPart;
    fExecutionLimit: LongWord;
    fDayMatchMode: TmaxCronDayMatchMode;
    fDialect: TmaxCronDialect;
    fLastPlan: string;
    fHashSeed: string;

    function GetParts(PartKind: TPartKind): TCronPart;
    function DomMatchesDate(const aDate: TDateTime): Boolean;
    function DowMatchesDate(const aDate: TDateTime): Boolean;
    procedure SetDayOfTheMonth(const Value: TCronPart);
    procedure SetDayOfTheWeek(const Value: TCronPart);
    procedure SetHour(const Value: TCronPart);
    procedure SetMinute(const Value: TCronPart);
    procedure SetMonth(const Value: TCronPart);
    procedure SetParts(PartKind: TPartKind; const Value: TCronPart);
    procedure SetSecond(const Value: TCronPart);
    procedure SetYear(const Value: TCronPart);
    procedure SetDialect(const Value: TmaxCronDialect);
    function PushDomDow(var NextDate: TDateTime): boolean;
    procedure ApplyDialectToParts;
    function HasPossibleDayOfMonth: Boolean;
    function FindNextFromCandidate(const aCandidate, aValidTo: TDateTime;
      out aNextDateTime: TDateTime): Boolean;
    function TryFindLastMatchingDay(const aYear, aMonth, aMaxDay: Word; out aDay: Word): Boolean;
    function CollectBetween(const aStart, aEnd: TDateTime; const aLimit: Integer;
      const aStore: Boolean; out aDates: TDates): Integer;
  public
    Constructor Create;
    Destructor Destroy; override;

    procedure Parse(const CronPlan: string);
    procedure Clear;

    function FindNextScheduleDate(const aBaseDate: TDateTime;
      out aNextDateTime: TDateTime;
      const aValidFrom: TDateTime = 0;
      const aValidTo: TDateTime = 0): boolean;
    function GetNextOccurrences(const aCount: Integer; const aFromDate: TDateTime;
      out aDates: TDates; const aValidFrom: TDateTime = 0;
      const aValidTo: TDateTime = 0): Integer;
    /// Last occurrence strictly before aBaseDate; False sets the output to zero.
    function FindPreviousScheduleDate(const aBaseDate: TDateTime;
      out aPreviousDateTime: TDateTime): Boolean;
    /// Up to aCount occurrences, newest first. Nonpositive counts return an empty array.
    function GetPreviousOccurrences(const aCount: Integer; const aFromDate: TDateTime;
      out aDates: TDates): Integer;
    /// Occurrences in [aStart, aEnd), oldest first, truncated at aLimit.
    function GetOccurrencesBetween(const aStart, aEnd: TDateTime; out aDates: TDates;
      const aLimit: Integer = cCronQueryDefaultLimit): Integer;
    /// Count in [aStart, aEnd), saturating at aLimit. Queries ignore ExecutionLimit.
    function CountBetween(const aStart, aEnd: TDateTime;
      const aLimit: Integer = cCronQueryDefaultLimit): Integer;
    function HasOccurrenceBetween(const aStart, aEnd: TDateTime): Boolean;
    function Describe: string;

    property Second: TCronPart read FSecond write SetSecond;
    property Minute: TCronPart read FMinute write SetMinute;
    property Hour: TCronPart read FHour write SetHour;
    property Day_of_the_Month: TCronPart read FDayOfTheMonth write SetDayOfTheMonth;
    property Month: TCronPart read FMonth write SetMonth;
    property Day_of_the_Week: TCronPart read FDayOfTheWeek write SetDayOfTheWeek;
    property Year: TCronPart read FYear write SetYear;
    property parts[PartKind: TPartKind]: TCronPart read GetParts write SetParts;
    property ExecutionLimit: LongWord read fExecutionLimit;
    property DayMatchMode: TmaxCronDayMatchMode read fDayMatchMode write fDayMatchMode;
    property Dialect: TmaxCronDialect read fDialect write SetDialect;
    property HashSeed: string read fHashSeed write fHashSeed;
  end;

/// Floor / ceiling division for aDivisor > 0, including negative aValue.
function CronFloorDiv(const aValue, aDivisor: Int64): Int64;
function CronCeilDiv(const aValue, aDivisor: Int64): Int64;
/// Nearest millisecond to the exact value of aValue, ties to even, computed with integer
/// arithmetic on the Double's bits. NaN/<=0 => 0; >=2958466 days saturates.
function CronDateTimeToMs(const aValue: TDateTime): Int64;
function CronDateTimeToInstantUs(const aValue: TDateTime): TCronInstantUs;
/// Builds the same Double as EncodeDateTime for the decoded fields.
function CronMsToDateTime(const aMs: Int64): TDateTime;
function CronSecondToDateTime(const aSecond: Int64): TDateTime;
function CronInstantFloorSecond(const aValue: TCronInstantUs): Int64;
/// Display/persistence only: floors to whole milliseconds.
function CronInstantUsToDateTime(const aValue: TCronInstantUs): TDateTime;

function IsCronIntervalPlan(const aPlan: string): Boolean;
function TryParseCronIntervalPlan(const aPlan: string; out aResult: TCronIntervalPlan;
  out aError: string): Boolean;
function FormatCronIntervalPlan(const aPlan: TCronIntervalPlan): string;
function DescribeCronIntervalPlan(const aPlan: TCronIntervalPlan): string;

implementation

uses
  System.Classes, System.DateUtils, System.Math, System.StrUtils;

const
  cCronMaxLastDayOffset = 30;
  cDescribeLastDayMinusDays = 'the last day minus %d days';
  cDescribeLastWeekdayMinusWeekdays = 'the last weekday minus %d weekdays';
  cDescribeLastDayNearestMinusDays = 'the nearest weekday to the last day minus %d days';

function CronFloorDiv(const aValue, aDivisor: Int64): Int64;
begin
  Result := aValue div aDivisor;
  if (aValue < 0) and (aValue mod aDivisor <> 0) then
    Dec(Result);
end;

function CronCeilDiv(const aValue, aDivisor: Int64): Int64;
begin
  Result := aValue div aDivisor;
  if (aValue > 0) and (aValue mod aDivisor <> 0) then
    Inc(Result);
end;

function CronDateTimeToMs(const aValue: TDateTime): Int64;
const
  cMantissaMask: UInt64 = $000FFFFFFFFFFFFF;
  cHiddenBit: UInt64 = $0010000000000000;
  // 86400000 = 84375 * 2^10; the power of two is folded into the binary exponent.
  cMsPerDayOddFactor = 84375;
  cLowBits = 20;
  cLowMask: UInt64 = $FFFFF;
var
  lBits, lMantissa, lHigh, lLow, lQuotient, lRemainder, lHalf: UInt64;
  lExponent, lShift: Integer;
begin
  // IsNan first: an ordered comparison with NaN raises EInvalidOp under default FPC float masks.
  if IsNan(aValue) or not (aValue > 0) then
    Exit(0);
  if aValue >= 2958466 then
    Exit(Int64(2958466) * cCronMsPerDay);
  // Exact by construction: aValue = lMantissa * 2^(lExponent - 1075), so
  // aValue * 86400000 = lMantissa * 84375 / 2^lShift with lShift = 1065 - lExponent.
  // Below 2^22 days lExponent <= 1044, hence lShift >= 21. No Double rounding takes part.
  Move(aValue, lBits, SizeOf(lBits));
  lExponent := Integer((lBits shr 52) and $7FF);
  lMantissa := lBits and cMantissaMask;
  if lExponent = 0 then
    lExponent := 1
  else
    lMantissa := lMantissa or cHiddenBit;
  lShift := 1065 - lExponent;
  // Product P = lMantissa * 84375 < 2^70, split as P = lHigh * 2^20 + lLow with lLow < 2^20.
  lHigh := (lMantissa shr cLowBits) * cMsPerDayOddFactor;
  lLow := (lMantissa and cLowMask) * cMsPerDayOddFactor;
  lHigh := lHigh + (lLow shr cLowBits);
  lLow := lLow and cLowMask;
  lShift := lShift - cLowBits;
  // lHigh < 2^51: from lShift > 52 on, P < 2^70 < 2^(lShift + 19) = half a millisecond.
  if lShift > 52 then
    Exit(0);
  lQuotient := lHigh shr lShift;
  // Exact remainder P - lQuotient * 2^(lShift + 20) = lRemainder * 2^20 + lLow; half = lHalf * 2^20.
  lRemainder := lHigh and ((UInt64(1) shl lShift) - 1);
  lHalf := UInt64(1) shl (lShift - 1);
  if (lRemainder > lHalf) or ((lRemainder = lHalf) and ((lLow <> 0) or ((lQuotient and 1) <> 0))) then
    Inc(lQuotient);
  Result := Int64(lQuotient);
end;

function CronDateTimeToInstantUs(const aValue: TDateTime): TCronInstantUs;
begin
  Result := CronDateTimeToMs(aValue) * cCronUsPerMs;
end;

function CronMsToDateTime(const aMs: Int64): TDateTime;
var
  lDay, lMsOfDay: Int64;
  lTime: Double;
begin
  lDay := CronFloorDiv(aMs, cCronMsPerDay);
  lMsOfDay := aMs - lDay * cCronMsPerDay;
  lTime := lMsOfDay / 86400000.0;
  Result := lDay + lTime;
end;

function CronSecondToDateTime(const aSecond: Int64): TDateTime;
begin
  Result := CronMsToDateTime(aSecond * cCronMsPerSecond);
end;

function CronInstantFloorSecond(const aValue: TCronInstantUs): Int64;
begin
  Result := CronFloorDiv(aValue, cCronUsPerSecond);
end;

function CronInstantUsToDateTime(const aValue: TCronInstantUs): TDateTime;
begin
  Result := CronMsToDateTime(CronFloorDiv(aValue, cCronUsPerMs));
end;

const
  OneMinute = 1 / 24 / 60;
  OneSecond = OneMinute / 60;
  OneHour = 1 / 24;

const
  DayNames: array [1 .. 7] of string = (
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun');

const
  MonthNames: array [1 .. 12] of string = (
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec');

procedure SplitString(const s: string; delim: char; ts: TStrings);
var
  i: integer;
  t: string;
begin
  t := '';
  for i := 1 to length(s) do
  begin
    if (s[i] <> delim) then
      t := t + s[i]
    else
    begin
      ts.Add(t);
      t := '';
    end;
  end;

  if t <> '' then
    ts.Add(t);
end;

function StripCronComment(const aValue: string): string;
var
  i: Integer;
begin
  Result := aValue;
  for i := 1 to Length(Result) do
    if (Result[i] = '#') and ((i = 1) or (Result[i - 1] <= ' ')) then
    begin
      Result := Copy(Result, 1, i - 1);
      Break;
    end;
  Result := TrimRight(Result);
end;

function IsCronIntervalPlan(const aPlan: string): Boolean;
var
  s: string;
begin
  s := Trim(StripCronComment(aPlan));
  Result := SameText(Copy(s, 1, 6), '@every') and
    ((Length(s) = 6) or ((Length(s) > 6) and (s[7] <= ' ')));
end;

function ReadIntervalNumber(const aText: string; var aPosition: Integer;
  out aValue: Int64; out aOverflow: Boolean): Boolean;
var
  lStart, lDigit: Integer;
begin
  lStart := aPosition;
  aValue := 0;
  aOverflow := False;
  while (aPosition <= Length(aText)) and CharInSet(aText[aPosition], ['0'..'9']) do
  begin
    lDigit := Ord(aText[aPosition]) - Ord('0');
    if aValue > (Int64(High(Cardinal)) - lDigit) div 10 then
      aOverflow := True
    else if not aOverflow then
      aValue := aValue * 10 + lDigit;
    Inc(aPosition);
  end;
  Result := aPosition > lStart;
end;

procedure SkipIntervalWhitespace(const aText: string; var aPosition: Integer);
begin
  while (aPosition <= Length(aText)) and (aText[aPosition] <= ' ') do
    Inc(aPosition);
end;

function ReadIntervalWord(const aText: string; var aPosition: Integer): string;
var
  lStart: Integer;
begin
  lStart := aPosition;
  while (aPosition <= Length(aText)) and (aText[aPosition] > ' ') do
    Inc(aPosition);
  Result := Copy(aText, lStart, aPosition - lStart);
end;

function TryParseCronIntervalPlan(const aPlan: string; out aResult: TCronIntervalPlan;
  out aError: string): Boolean;
var
  s, lWord: string;
  lPosition: Integer;
  lValue, lFactor, lLimit: Int64;
  lOverflow, lLimitOverflow: Boolean;
begin
  aResult := Default(TCronIntervalPlan);
  aError := cIntervalPlanInvalid;
  Result := False;
  if not IsCronIntervalPlan(aPlan) then Exit;
  s := LowerCase(Trim(StripCronComment(aPlan)));
  lPosition := 7;
  SkipIntervalWhitespace(s, lPosition);
  if not ReadIntervalNumber(s, lPosition, lValue, lOverflow) then Exit;
  SkipIntervalWhitespace(s, lPosition);
  lWord := ReadIntervalWord(s, lPosition);
  if lWord = 'ms' then lFactor := 1
  else if lWord = 's' then lFactor := 1000
  else if lWord = 'm' then lFactor := 60000
  else if lWord = 'h' then lFactor := 3600000
  else Exit;
  SkipIntervalWhitespace(s, lPosition);
  lWord := ReadIntervalWord(s, lPosition);
  if (lWord = 'fixed-rate') or (lWord = 'fixed-delay') then
  begin
    aResult.FixedDelay := lWord = 'fixed-delay';
    SkipIntervalWhitespace(s, lPosition);
    lWord := ReadIntervalWord(s, lPosition);
  end;
  lLimit := 0;
  lLimitOverflow := False;
  if lWord = 'limit' then
  begin
    SkipIntervalWhitespace(s, lPosition);
    if not ReadIntervalNumber(s, lPosition, lLimit, lLimitOverflow) then Exit;
    // Require whitespace or end after the numeric limit.
    if (lPosition <= Length(s)) and (s[lPosition] > ' ') then Exit;
    SkipIntervalWhitespace(s, lPosition);
    lWord := ReadIntervalWord(s, lPosition);
  end;
  if lWord <> '' then Exit;
  if lOverflow or lLimitOverflow or (lValue = 0) or
    (lValue > Int64(High(Cardinal)) div lFactor) then
  begin
    aResult := Default(TCronIntervalPlan);
    aError := cIntervalPlanOutOfRange;
    Exit;
  end;
  aResult.IntervalMs := Cardinal(lValue * lFactor);
  aResult.ExecutionLimit := LongWord(lLimit);
  aError := '';
  Result := True;
end;

function IntervalUnit(const aIntervalMs: Cardinal; out aValue: Cardinal): string;
begin
  if aIntervalMs = 0 then
    raise Exception.Create(cIntervalPlanOutOfRange);
  if aIntervalMs mod 3600000 = 0 then
  begin
    aValue := aIntervalMs div 3600000; Result := 'h';
  end else if aIntervalMs mod 60000 = 0 then
  begin
    aValue := aIntervalMs div 60000; Result := 'm';
  end else if aIntervalMs mod 1000 = 0 then
  begin
    aValue := aIntervalMs div 1000; Result := 's';
  end else begin
    aValue := aIntervalMs; Result := 'ms';
  end;
end;

function FormatCronIntervalPlan(const aPlan: TCronIntervalPlan): string;
var
  lValue: Cardinal;
  lUnit: string;
begin
  lUnit := IntervalUnit(aPlan.IntervalMs, lValue);
  Result := '@every ' + UIntToStr(lValue) + lUnit;
  if aPlan.FixedDelay then Result := Result + ' fixed-delay';
  if aPlan.ExecutionLimit <> 0 then Result := Result + ' limit ' + UIntToStr(aPlan.ExecutionLimit);
end;

function DescribeCronIntervalPlan(const aPlan: TCronIntervalPlan): string;
var
  lValue: Cardinal;
  lUnit: string;
begin
  lUnit := IntervalUnit(aPlan.IntervalMs, lValue);
  if lUnit = 'ms' then lUnit := 'millisecond'
  else if lUnit = 's' then lUnit := 'second'
  else if lUnit = 'm' then lUnit := 'minute'
  else lUnit := 'hour';
  if lValue = 1 then Result := 'Every ' + lUnit
  else Result := 'Every ' + UIntToStr(lValue) + ' ' + lUnit + 's';
  if aPlan.FixedDelay then Result := Result + ' (fixed delay)';
end;

procedure SplitByWhitespace(const aValue: string; aList: TStrings);
var
  i: Integer;
  lToken: string;
  c: Char;
begin
  aList.Clear;
  lToken := '';
  for i := 1 to Length(aValue) do
  begin
    c := aValue[i];
    if c <= ' ' then
    begin
      if lToken <> '' then
      begin
        aList.Add(lToken);
        lToken := '';
      end;
    end
    else
      lToken := lToken + c;
  end;

  if lToken <> '' then
    aList.Add(lToken);
end;

function NormalizeCommaWhitespace(const aValue: string): string;
var
  i: Integer;
  lResult: string;
  c: Char;
  lSkipWhitespace: Boolean;
begin
  lResult := '';
  lSkipWhitespace := False;
  for i := 1 to Length(aValue) do
  begin
    c := aValue[i];
    if lSkipWhitespace and (c <= ' ') then
      Continue;

    if c = ',' then
    begin
      while (Length(lResult) > 0) and (lResult[Length(lResult)] <= ' ') do
        Delete(lResult, Length(lResult), 1);
      lResult := lResult + c;
      lSkipWhitespace := True;
      Continue;
    end;

    lSkipWhitespace := False;
    lResult := lResult + c;
  end;
  Result := lResult;
end;

function TryApplyCronMacro(const aValue: string; var aPlan: TPlan): Boolean;
var
  lMacro: string;
begin
  lMacro := Trim(LowerCase(aValue));
  if (lMacro = '@yearly') or (lMacro = '@annually') then
  begin
    aPlan.Minute := '0';
    aPlan.Hour := '0';
    aPlan.DayOfTheMonth := '1';
    aPlan.Month := '1';
    aPlan.DayOfTheWeek := '*';
    Exit(True);
  end;

  if lMacro = '@monthly' then
  begin
    aPlan.Minute := '0';
    aPlan.Hour := '0';
    aPlan.DayOfTheMonth := '1';
    aPlan.Month := '*';
    aPlan.DayOfTheWeek := '*';
    Exit(True);
  end;

  if lMacro = '@weekly' then
  begin
    aPlan.Minute := '0';
    aPlan.Hour := '0';
    aPlan.DayOfTheMonth := '*';
    aPlan.Month := '*';
    if aPlan.Dialect = cdQuartzSecondsFirst then
      aPlan.DayOfTheWeek := '1'
    else
      aPlan.DayOfTheWeek := '0';
    Exit(True);
  end;

  if (lMacro = '@daily') or (lMacro = '@midnight') then
  begin
    aPlan.Minute := '0';
    aPlan.Hour := '0';
    aPlan.DayOfTheMonth := '*';
    aPlan.Month := '*';
    aPlan.DayOfTheWeek := '*';
    Exit(True);
  end;

  if lMacro = '@hourly' then
  begin
    aPlan.Minute := '0';
    aPlan.Hour := '*';
    aPlan.DayOfTheMonth := '*';
    aPlan.Month := '*';
    aPlan.DayOfTheWeek := '*';
    Exit(True);
  end;

  if lMacro = '@reboot' then
  begin
    if aPlan.Dialect <> cdMaxCron then
      Exit(False);
    aPlan.Minute := '*';
    aPlan.Hour := '*';
    aPlan.DayOfTheMonth := '*';
    aPlan.Month := '*';
    aPlan.DayOfTheWeek := '*';
    aPlan.Year := '*';
    aPlan.Second := '*';
    aPlan.ExecutionLimit := '1';
    Exit(True);
  end;

  Result := False;
end;

{ TCronSchedulePlan }

procedure TCronSchedulePlan.Clear;
var
  pk: TPartKind;
begin
  fExecutionLimit := 0;
  for pk := Low(TPartKind) to High(TPartKind) do
    parts[pk].Clear;
end;

constructor TCronSchedulePlan.Create;
var
  pk: TPartKind;
begin
  inherited;

  fDayMatchMode := TmaxCronDayMatchMode.dmAnd;
  fDialect := cdMaxCron;
  fLastPlan := '';
  fHashSeed := '';
  for pk := Low(TPartKind) to High(TPartKind) do
    parts[pk] := TCronPart.Create(pk);
  ApplyDialectToParts;
end;

destructor TCronSchedulePlan.Destroy;
var
  pk: TPartKind;
begin
  for pk := Low(TPartKind) to High(TPartKind) do
    parts[pk].Free;
  inherited;
end;

function TCronSchedulePlan.HasPossibleDayOfMonth: Boolean;
var
  lMode: TmaxCronDayMatchMode;

  function HasLeapYearInRange: Boolean;
  var
    i: Integer;
    y: Word;
  begin
    if FYear.Fullrange then
      Exit(True);
    Result := False;
    for i := 0 to FYear.FCount - 1 do
    begin
      y := FYear.fRange[i];
      if IsLeapYear(y) then
        Exit(True);
    end;
  end;

  function MaxDaysForMonth(const aMonth: Word): Word;
  begin
    case aMonth of
      2:
        if HasLeapYearInRange then
          Result := 29
        else
          Result := 28;
      4, 6, 9, 11:
        Result := 30;
    else
      Result := 31;
    end;
  end;

  function HasValidDomForMonth(const aMonth: Word): Boolean;
  var
    i: Integer;
    lMax: Word;
    lVal: Word;
  begin
    if FDayOfTheMonth.fFullrange then
      Exit(True);
    if FDayOfTheMonth.FCount = 0 then
      Exit(False);
    lMax := MaxDaysForMonth(aMonth);
    for i := 0 to FDayOfTheMonth.FCount - 1 do
    begin
      lVal := FDayOfTheMonth.fRange[i];
      if (lVal >= 1) and (lVal <= lMax) then
        Exit(True);
    end;
    Result := False;
  end;

  function HasDomInAllowedMonths: Boolean;
  var
    i: Integer;
    lMonth: Word;
  begin
    if FDayOfTheMonth.fFullrange then
      Exit(True);
    if FMonth.fFullrange then
    begin
      for lMonth := 1 to 12 do
        if HasValidDomForMonth(lMonth) then
          Exit(True);
      Exit(False);
    end;
    if FMonth.FCount = 0 then
      Exit(False);
    for i := 0 to FMonth.FCount - 1 do
    begin
      lMonth := FMonth.fRange[i];
      if HasValidDomForMonth(lMonth) then
        Exit(True);
    end;
    Result := False;
  end;
begin
  lMode := fDayMatchMode;
  if lMode = TmaxCronDayMatchMode.dmDefault then
    lMode := TmaxCronDayMatchMode.dmAnd;
  if (not FDayOfTheMonth.Fullrange) and (FDayOfTheMonth.fDomModifier = TCronDomModifier.cdmNone) and
    ((lMode = TmaxCronDayMatchMode.dmAnd) or FDayOfTheWeek.Fullrange) then
    if not HasDomInAllowedMonths then
      Exit(False);

  Result := True;
end;

function TCronSchedulePlan.FindNextFromCandidate(const aCandidate, aValidTo: TDateTime;
  out aNextDateTime: TDateTime): Boolean;
var
  lValidToMs: Int64;
begin
  Result := False;
  aNextDateTime := aCandidate;
  lValidToMs := CronDateTimeToMs(aValidTo);
  if not HasPossibleDayOfMonth then
    Exit(False);

  while True do
  begin
    if (aValidTo > 0) and (CronDateTimeToMs(aNextDateTime) > lValidToMs) then
      Exit(false);



    // year
    if not FYear.PushYear(aNextDateTime) then
      Exit;

    if FMonth.PushMonth(aNextDateTime) then
      if PushDomDow(aNextDateTime) then
        if FHour.PushHour(aNextDateTime) then
          if FMinute.PushMinute(aNextDateTime) then
            if FSecond.PushSecond(aNextDateTime) then
            begin
              Exit(True);
            end;

  end;
end;

procedure DecodeSearchClock(const aStamp: TTimeStamp; out h, m, s, ms: Word);
var
  lSeconds: Integer;
begin
  // Date and clock must come from the same RTL millisecond normalization.
  lSeconds := aStamp.Time div MSecsPerSec;
  h := lSeconds div SecsPerHour;
  m := (lSeconds div SecsPerMin) mod MinsPerHour;
  s := lSeconds mod SecsPerMin;
  ms := aStamp.Time mod MSecsPerSec;
end;

procedure DecodeSearchClockMs(const aMs: Int64; out h, m, s, ms: Word);
var
  lSeconds: Integer;
begin
  // Date and clock must come from the same canonical millisecond normalization.
  lSeconds := (aMs mod cCronMsPerDay) div MSecsPerSec;
  h := lSeconds div SecsPerHour;
  m := (lSeconds div SecsPerMin) mod MinsPerHour;
  s := lSeconds mod SecsPerMin;
  ms := aMs mod MSecsPerSec;
end;

function TCronSchedulePlan.FindNextScheduleDate(const aBaseDate: TDateTime;
  out aNextDateTime: TDateTime;
  const aValidFrom,
  aValidTo: TDateTime): boolean;
var
  lStartDate: TDateTime;
  lStartMs: Int64;
  h, m, s, ms: word;
begin
  lStartMs := Max(CronDateTimeToMs(aBaseDate), CronDateTimeToMs(aValidFrom));
  DecodeSearchClockMs(lStartMs, h, m, s, ms);
  lStartDate := CronFloorDiv(lStartMs, cCronMsPerDay);
  // Keep ordinary result bytes, but carry midnight as an integer day first.
  if (h = 23) and (m = 59) and (s = 59) then
    lStartDate := lStartDate + 1
  else
    lStartDate := lStartDate + EncodeTime(h, m, s, 0) + OneSecond;

  Result := FindNextFromCandidate(lStartDate, aValidTo, aNextDateTime);
end;

function QuerySerial(const aDate: TDateTime): Int64;
begin
  Result := CronFloorDiv(CronDateTimeToMs(aDate), cCronMsPerSecond);
end;

function TCronPart.TryPrevVal(const aValue: Word; out aResult: Word): Boolean;
var
  i: Integer;
begin
  aResult := aValue;
  if Fullrange or FindInRange(aValue, i) then
    Exit(True);
  Result := i > 0;
  if Result then
    aResult := fRange[i - 1];
end;

function TCronSchedulePlan.TryFindLastMatchingDay(const aYear, aMonth, aMaxDay: Word;
  out aDay: Word): Boolean;
var
  lDomTarget, lDowTarget, lFirstDow, lDow: Word;
  lDomSpecial, lDowSpecial, lDomMatch, lDowMatch, lUseAnd: Boolean;
  d: Integer;
begin
  if FDayOfTheMonth.Fullrange and FDayOfTheWeek.Fullrange then
  begin
    aDay := aMaxDay;
    Exit(True);
  end;
  lUseAnd := (fDayMatchMode <> dmOr) or FDayOfTheMonth.Fullrange or FDayOfTheWeek.Fullrange;
  lDomSpecial := FDayOfTheMonth.HasSpecial;
  lDowSpecial := FDayOfTheWeek.HasSpecial;
  lDomTarget := 0;
  lDowTarget := 0;
  if lDomSpecial then
  begin
    if not FDayOfTheMonth.TryGetDomSpecialDay(aYear, aMonth, lDomTarget) then
      lDomTarget := 0;
  end;
  if lDowSpecial then
  begin
    if not FDayOfTheWeek.TryGetDowSpecialDay(aYear, aMonth, lDowTarget) then
      lDowTarget := 0;
  end;
  lFirstDow := DayOfTheWeek(EncodeDate(aYear, aMonth, 1)) mod 7;
  for d := aMaxDay downto 1 do
  begin
    if lDomSpecial then
      lDomMatch := d = lDomTarget
    else
      lDomMatch := FDayOfTheMonth.NextVal(d) = d;
    lDow := (lFirstDow + d - 1) mod 7;
    if lDowSpecial then
      lDowMatch := d = lDowTarget
    else
      lDowMatch := FDayOfTheWeek.NextVal(lDow) = lDow;
    if (lUseAnd and lDomMatch and lDowMatch) or (not lUseAnd and (lDomMatch or lDowMatch)) then
    begin
      aDay := d;
      Exit(True);
    end;
  end;
  Result := False;
end;

function TCronSchedulePlan.FindPreviousScheduleDate(const aBaseDate: TDateTime;
  out aPreviousDateTime: TDateTime): Boolean;
var
  y, mo, d, h, mi, s: Integer;
  lBaseMs: Int64;
  lYear, lMonth, lDay, lHour, lMinute, lSecond, lMilli, v: Word;

  procedure EndOfPreviousYear;
  begin
    Dec(y);
    mo := 12;
    d := 31;
    h := 23;
    mi := 59;
    s := 59;
  end;

  procedure EndOfPreviousMonth;
  begin
    if mo = 1 then
      EndOfPreviousYear
    else
    begin
      Dec(mo);
      d := 31;
      h := 23;
      mi := 59;
      s := 59;
    end;
  end;

  procedure EndOfPreviousDay;
  begin
    if d = 1 then
      EndOfPreviousMonth
    else
    begin
      Dec(d);
      h := 23;
      mi := 59;
      s := 59;
    end;
  end;

  procedure EndOfPreviousHour;
  begin
    if h = 0 then
      EndOfPreviousDay
    else
    begin
      Dec(h);
      mi := 59;
      s := 59;
    end;
  end;

  procedure EndOfPreviousMinute;
  begin
    if mi = 0 then
      EndOfPreviousHour
    else
    begin
      Dec(mi);
      s := 59;
    end;
  end;

begin
  aPreviousDateTime := 0;
  if not HasPossibleDayOfMonth then
    Exit(False);
  lBaseMs := CronDateTimeToMs(aBaseDate);
  if lBaseMs <= CronDateTimeToMs(EncodeDate(1900, 1, 1)) then
    Exit(False);
  if lBaseMs >= CronDateTimeToMs(EncodeDate(3001, 1, 1)) then
  begin
    y := 3000;
    mo := 12;
    d := 31;
    h := 23;
    mi := 59;
    s := 59;
  end else begin
    DecodeDate(CronFloorDiv(lBaseMs, cCronMsPerDay), lYear, lMonth, lDay);
    DecodeSearchClockMs(lBaseMs, lHour, lMinute, lSecond, lMilli);
    y := lYear;
    mo := lMonth;
    d := lDay;
    h := lHour;
    mi := lMinute;
    s := lSecond;
    if lMilli = 0 then
    begin
      if s = 0 then
        EndOfPreviousMinute
      else
        Dec(s);
    end;
  end;
  while y >= 1900 do
  begin
    if not FYear.TryPrevVal(y, v) then
      Exit(False);
    if v < y then
    begin
      y := v;
      mo := 12;
      d := 31;
      h := 23;
      mi := 59;
      s := 59;
    end;
    if not FMonth.TryPrevVal(mo, v) then
    begin
      EndOfPreviousYear;
      Continue;
    end;
    if v < mo then
    begin
      mo := v;
      d := 31;
      h := 23;
      mi := 59;
      s := 59;
    end;
    d := Min(d, DaysInAMonth(y, mo));
    if not TryFindLastMatchingDay(y, mo, d, v) then
    begin
      EndOfPreviousMonth;
      Continue;
    end;
    if v < d then
    begin
      d := v;
      h := 23;
      mi := 59;
      s := 59;
    end;
    if not FHour.TryPrevVal(h, v) then
    begin
      EndOfPreviousDay;
      Continue;
    end;
    if v < h then
    begin
      h := v;
      mi := 59;
      s := 59;
    end;
    if not FMinute.TryPrevVal(mi, v) then
    begin
      EndOfPreviousHour;
      Continue;
    end;
    if v < mi then
    begin
      mi := v;
      s := 59;
    end;
    if not FSecond.TryPrevVal(s, v) then
    begin
      EndOfPreviousMinute;
      Continue;
    end;
    aPreviousDateTime := EncodeDateTime(y, mo, d, h, mi, v, 0);
    Exit(True);
  end;
  Result := False;
end;

function TCronSchedulePlan.GetPreviousOccurrences(const aCount: Integer; const aFromDate: TDateTime;
  out aDates: TDates): Integer;
var
  lCursor, lPrevious: TDateTime;
begin
  Result := 0;
  aDates := nil;
  if aCount <= 0 then
    Exit;
  SetLength(aDates, aCount);
  lCursor := aFromDate;
  while Result < aCount do
  begin
    if not FindPreviousScheduleDate(lCursor, lPrevious) then
      Break;
    if (Result > 0) and (QuerySerial(lPrevious) >= QuerySerial(lCursor)) then
      Break;
    aDates[Result] := lPrevious;
    Inc(Result);
    lCursor := lPrevious;
  end;
  SetLength(aDates, Result);
end;

function TCronSchedulePlan.CollectBetween(const aStart, aEnd: TDateTime; const aLimit: Integer;
  const aStore: Boolean; out aDates: TDates): Integer;
var
  lEnd, lCandidate, lNext, lPrevious: TDateTime;
  lStartMs, lEndMs, lFloorMs, lCeilingMs, lLast, lLower, lSerial: Int64;
  lCapacity: Integer;
begin
  Result := 0;
  aDates := nil;
  if aLimit <= 0 then
    Exit;
  lFloorMs := CronDateTimeToMs(EncodeDate(1900, 1, 1));
  lCeilingMs := CronDateTimeToMs(EncodeDate(3001, 1, 1));
  lStartMs := Max(CronDateTimeToMs(aStart), lFloorMs);
  lEndMs := Min(CronDateTimeToMs(aEnd), lCeilingMs);
  // Clamp before decoding; the conversion helper also handles out-of-domain carriers.
  if (lStartMs >= lCeilingMs) or (lEndMs <= lFloorMs) then
    Exit;
  lLower := CronCeilDiv(lStartMs, cCronMsPerSecond);
  lLast := CronCeilDiv(lEndMs, cCronMsPerSecond) - 1;
  lCandidate := CronSecondToDateTime(lLower);
  lEnd := CronMsToDateTime(lEndMs);
  if lLast < lLower then
    Exit;
  if not FindNextFromCandidate(lCandidate, lEnd, lNext) then
    Exit;
  lCapacity := 0;
  while Result < aLimit do
  begin
    lSerial := QuerySerial(lNext);
    // Fail closed if a future search regression violates the inclusive lower bound.
    // Assertions expose the broken invariant in checked builds; release builds stop
    // with the valid prefix already collected, as required for non-progress below.
    Assert(lSerial >= lLower, 'Range search returned an occurrence before its lower bound');
    if (lSerial < lLower) or (lSerial > lLast) then
      Break;
    if aStore then
    begin
      if Result = lCapacity then
      begin
        if lCapacity = 0 then
          lCapacity := Min(aLimit, 64)
        else if lCapacity > aLimit div 2 then
          lCapacity := aLimit
        else
          lCapacity := lCapacity * 2;
        SetLength(aDates, lCapacity);
      end;
      aDates[Result] := lNext;
    end;
    Inc(Result);
    if Result = aLimit then
      Break;
    lPrevious := lNext;
    if not FindNextScheduleDate(lPrevious, lNext, 0, lEnd) then
      Break;
    Assert(QuerySerial(lNext) > lSerial, 'Range search did not advance');
    if QuerySerial(lNext) <= lSerial then
      Break;
  end;
  if aStore then
    SetLength(aDates, Result);
end;

function TCronSchedulePlan.GetOccurrencesBetween(const aStart, aEnd: TDateTime; out aDates: TDates;
  const aLimit: Integer): Integer;
begin
  Result := CollectBetween(aStart, aEnd, aLimit, True, aDates);
end;

function TCronSchedulePlan.CountBetween(const aStart, aEnd: TDateTime; const aLimit: Integer): Integer;
var
  lUnused: TDates;
begin
  Result := CollectBetween(aStart, aEnd, aLimit, False, lUnused);
end;

function TCronSchedulePlan.HasOccurrenceBetween(const aStart, aEnd: TDateTime): Boolean;
var
  lUnused: TDates;
begin
  Result := CollectBetween(aStart, aEnd, 1, False, lUnused) > 0;
end;

function FormatTwo(const aValue: Word): string;
begin
  Result := Format('%.2d', [aValue]);
end;

function FormatTime(const aHour, aMinute, aSecond: Word; const aIncludeSeconds: Boolean): string;
begin
  if aIncludeSeconds then
    Result := FormatTwo(aHour) + ':' + FormatTwo(aMinute) + ':' + FormatTwo(aSecond)
  else
    Result := FormatTwo(aHour) + ':' + FormatTwo(aMinute);
end;

function FormatDowName(const aDow: Word): string;
var
  lIndex: Word;
begin
  if aDow = 0 then
    lIndex := 7
  else
    lIndex := aDow;

  if (lIndex >= 1) and (lIndex <= 7) then
    Result := DayNames[lIndex]
  else
    Result := IntToStr(aDow);
end;

function FormatMonthName(const aMonth: Word): string;
begin
  if (aMonth >= 1) and (aMonth <= 12) then
    Result := MonthNames[aMonth]
  else
    Result := IntToStr(aMonth);
end;

function JoinValues(const aValues: TWordArray; const aKind: TPartKind): string;
var
  i: Integer;
  s: string;
begin
  s := '';
  for i := 0 to Length(aValues) - 1 do
  begin
    if i > 0 then
      s := s + ',';
    case aKind of
      TPartKind.ckDayOfTheWeek:
        s := s + FormatDowName(aValues[i]);
      TPartKind.ckMonth:
        s := s + FormatMonthName(aValues[i]);
    else
      s := s + IntToStr(aValues[i]);
    end;
  end;
  Result := s;
end;

function TCronSchedulePlan.GetNextOccurrences(const aCount: Integer; const aFromDate: TDateTime;
  out aDates: TDates; const aValidFrom: TDateTime; const aValidTo: TDateTime): Integer;
var
  lCursor: TDateTime;
  lNext: TDateTime;
  lStall: Integer;
  lMaxStall: Integer;
begin
  Result := 0;
  SetLength(aDates, 0);
  if aCount <= 0 then
    Exit;

  SetLength(aDates, aCount);
  lCursor := aFromDate;
  lStall := 0;
  lMaxStall := Max(8, aCount * 4);

  while Result < aCount do
  begin
    if not FindNextScheduleDate(lCursor, lNext, aValidFrom, aValidTo) then
      Break;

    if CronDateTimeToMs(lNext) <= CronDateTimeToMs(lCursor) then
    begin
      Inc(lStall);
      if lStall > lMaxStall then
        Break;
      lCursor := lCursor + OneSecond;
      Continue;
    end;

    aDates[Result] := lNext;
    Inc(Result);
    lCursor := lNext;
    lStall := 0;
  end;

  SetLength(aDates, Result);
end;

function TCronSchedulePlan.Describe: string;
var
  lHour: Word;
  lMinute: Word;
  lSecond: Word;
  lMonth: Word;
  lDom: Word;
  lYear: Word;
  lHasHour: Boolean;
  lHasMinute: Boolean;
  lHasSecond: Boolean;
  lHasMonth: Boolean;
  lHasDom: Boolean;
  lHasYear: Boolean;
  lTime: string;
  lYearSuffix: string;
  lValues: TWordArray;
  lStepStart: Word;
  lStep: Word;
  lStepFull: Boolean;
  lDomText: string;
begin
  lHasHour := Hour.TryGetSingleValue(lHour);
  lHasMinute := Minute.TryGetSingleValue(lMinute);
  lHasSecond := Second.TryGetSingleValue(lSecond);
  lHasMonth := Month.TryGetSingleValue(lMonth);
  lHasDom := Day_of_the_Month.TryGetSingleValue(lDom);
  lHasYear := Year.TryGetSingleValue(lYear);

  lYearSuffix := '';
  if lHasYear then
    lYearSuffix := ' in ' + IntToStr(lYear);

  if Second.TryGetStep(lStepStart, lStep, lStepFull) and (lStep > 0) and
    (Minute.IsAny) and (Hour.IsAny) and (Day_of_the_Month.IsAny) and (Month.IsAny) and
    (Day_of_the_Week.IsAny) and (Year.IsAny) then
  begin
    if lStep = 1 then
      Exit('Every second' + lYearSuffix);
    if lStepStart = 0 then
      Exit(Format('Every %d seconds%s', [lStep, lYearSuffix]));
    Exit(Format('Every %d seconds starting at %d%s', [lStep, lStepStart, lYearSuffix]));
  end;

  if Minute.TryGetStep(lStepStart, lStep, lStepFull) and (lStep > 0) and
    (Hour.IsAny) and (Day_of_the_Month.IsAny) and (Month.IsAny) and (Day_of_the_Week.IsAny) and
    (Year.IsAny) and lHasSecond then
  begin
    if lSecond = 0 then
    begin
      if lStep = 1 then
        Exit('Every minute' + lYearSuffix);
      if lStepStart = 0 then
        Exit(Format('Every %d minutes%s', [lStep, lYearSuffix]));
      Exit(Format('Every %d minutes starting at minute %d%s', [lStep, lStepStart, lYearSuffix]));
    end;
  end;

  if Hour.TryGetStep(lStepStart, lStep, lStepFull) and (lStep > 0) and
    (Day_of_the_Month.IsAny) and (Month.IsAny) and (Day_of_the_Week.IsAny) and (Year.IsAny) and
    lHasMinute and lHasSecond then
  begin
    if (lMinute = 0) and (lSecond = 0) then
    begin
      if lStep = 1 then
        Exit('Every hour' + lYearSuffix);
      if lStepStart = 0 then
        Exit(Format('Every %d hours%s', [lStep, lYearSuffix]));
      Exit(Format('Every %d hours starting at hour %d%s', [lStep, lStepStart, lYearSuffix]));
    end;
  end;

  lTime := '';
  if lHasHour and lHasMinute and lHasSecond then
  begin
    if lSecond = 0 then
      lTime := FormatTime(lHour, lMinute, lSecond, False)
    else
      lTime := FormatTime(lHour, lMinute, lSecond, True);
  end;

  if (lTime <> '') and (Day_of_the_Month.IsAny) and (Month.IsAny) and (Day_of_the_Week.IsAny) and (Year.IsAny) then
    Exit('Every day at ' + lTime + lYearSuffix);

  if (lTime <> '') and (Day_of_the_Month.IsAny) and (Month.IsAny) and (Year.IsAny) and
    (not Day_of_the_Week.IsAny) and (not Day_of_the_Week.HasSpecialTokens) then
  begin
    if Day_of_the_Week.GetValues(lValues) then
      Exit('Every week on ' + JoinValues(lValues, TPartKind.ckDayOfTheWeek) + ' at ' + lTime + lYearSuffix);
  end;

  if (lTime <> '') and (Month.IsAny) and (Year.IsAny) and (Day_of_the_Week.IsAny) then
  begin
    lDomText := Day_of_the_Month.DescribeDomSpecial;
    if lDomText <> '' then
      Exit('Every month on ' + lDomText + ' at ' + lTime + lYearSuffix);
    if lHasDom then
      Exit(Format('Every month on day %d at %s%s', [lDom, lTime, lYearSuffix]));
  end;

  if (lTime <> '') and lHasMonth and (Year.IsAny) and (Day_of_the_Week.IsAny) then
  begin
    lDomText := Day_of_the_Month.DescribeDomSpecial;
    if lDomText <> '' then
      Exit('Every year on ' + FormatMonthName(lMonth) + ' ' + lDomText + ' at ' + lTime + lYearSuffix);
    if lHasDom then
      Exit(Format('Every year on %s %d at %s%s', [FormatMonthName(lMonth), lDom, lTime, lYearSuffix]));
  end;

  Result := 'Custom schedule';
end;

function TCronSchedulePlan.PushDomDow(var NextDate: TDateTime): boolean;
var
  lMode: TmaxCronDayMatchMode;
  lDomOk: Boolean;
  lDowOk: Boolean;
  lDomCandidate: TDateTime;
  lDowCandidate: TDateTime;
begin

  lMode := fDayMatchMode;
  if lMode = TmaxCronDayMatchMode.dmDefault then
    lMode := TmaxCronDayMatchMode.dmAnd;

  // If either part is full range, "OR" reduces to the other constraint.
  if (lMode = TmaxCronDayMatchMode.dmAnd) or FDayOfTheMonth.Fullrange or FDayOfTheWeek.Fullrange then
  begin
    Result := FDayOfTheMonth.PushDayOfMonth(NextDate);
    if Result then
      Result := FDayOfTheWeek.PushDayOfWeek(NextDate);
    Exit;
  end;

  // OR mode and both are restricted: accept if either matches.
  lDomOk := DomMatchesDate(NextDate);
  lDowOk := DowMatchesDate(NextDate);
  if lDomOk or lDowOk then
    Exit(True);

  // Otherwise, advance to the earliest next date that satisfies DOM or DOW.
  lDomCandidate := NextDate;
  lDowCandidate := NextDate;

  FDayOfTheMonth.PushDayOfMonth(lDomCandidate);
  FDayOfTheWeek.PushDayOfWeek(lDowCandidate);

  if lDomCandidate <= lDowCandidate then
    NextDate := lDomCandidate
  else
    NextDate := lDowCandidate;

  Result := False;
end;

function TCronSchedulePlan.GetParts(PartKind: TPartKind): TCronPart;
begin
  case PartKind of
    ckSecond:
      Result := FSecond;
    ckMinute:
      Result := FMinute;
    ckHour:
      Result := FHour;
    ckDayOfTheMonth:
      Result := FDayOfTheMonth;
    ckMonth:
      Result := FMonth;
    ckDayOfTheWeek:
      Result := FDayOfTheWeek;
  else
    // ckyear:
    Result := FYear;
  end;
end;

function TCronSchedulePlan.DomMatchesDate(const aDate: TDateTime): Boolean;
var
  lDay: Word;
  lYear: Word;
  lMonth: Word;
  lTarget: Word;
begin
  if FDayOfTheMonth.Fullrange then
    Exit(True);
  if FDayOfTheMonth.fDomModifier <> TCronDomModifier.cdmNone then
  begin
    DecodeDate(aDate, lYear, lMonth, lDay);
    if not FDayOfTheMonth.TryGetDomSpecialDay(lYear, lMonth, lTarget) then
      Exit(False);
    Exit(lTarget = lDay);
  end;

  lDay := DayOf(aDate);
  Result := (FDayOfTheMonth.NextVal(lDay) = lDay);
end;

function TCronSchedulePlan.DowMatchesDate(const aDate: TDateTime): Boolean;
var
  lDow: Word;
  lYear: Word;
  lMonth: Word;
  lDay: Word;
  lTarget: Word;
begin
  if FDayOfTheWeek.Fullrange then
    Exit(True);
  if FDayOfTheWeek.fDowModifier <> TCronDowModifier.cdwNone then
  begin
    DecodeDate(aDate, lYear, lMonth, lDay);
    if not FDayOfTheWeek.TryGetDowSpecialDay(lYear, lMonth, lTarget) then
      Exit(False);
    Exit(lTarget = lDay);
  end;

  lDow := DayOfTheWeek(aDate) mod 7;
  Result := (FDayOfTheWeek.NextVal(lDow) = lDow);
end;

procedure TCronSchedulePlan.Parse(const CronPlan: string);
var
  plan: TPlan;
  pk: TPartKind;
  lText: string;
  lNum: Int64;
begin
  Clear;
  plan.Dialect := fDialect;
  plan.text := CronPlan;

  for pk := Low(TPartKind) to High(TPartKind) do
  begin
    parts[pk].fHashSeed := fHashSeed;
    parts[pk].Data := plan.parts[integer(pk)];
  end;

  fExecutionLimit := 0;
  lText := Trim(plan.ExecutionLimit);
  if (lText <> '') and (lText <> '*') then
  begin
    if not TryStrToInt64(lText, lNum) then
      raise Exception.Create('Invalid cron token');
    if (lNum < 0) or (lNum > High(LongWord)) then
      raise Exception.Create('Cron value out of range');
    fExecutionLimit := LongWord(lNum);
  end;
  fLastPlan := CronPlan;
end;

procedure TCronSchedulePlan.SetDayOfTheMonth(const Value: TCronPart);
begin
  FDayOfTheMonth := Value;
end;

procedure TCronSchedulePlan.SetDayOfTheWeek(const Value: TCronPart);
begin
  FDayOfTheWeek := Value;
end;

procedure TCronSchedulePlan.SetHour(const Value: TCronPart);
begin
  FHour := Value;
end;

procedure TCronSchedulePlan.SetMinute(const Value: TCronPart);
begin
  FMinute := Value;
end;

procedure TCronSchedulePlan.SetMonth(const Value: TCronPart);
begin
  FMonth := Value;
end;

procedure TCronSchedulePlan.SetParts(PartKind: TPartKind; const Value: TCronPart);
begin
  case PartKind of
    ckSecond:
      FSecond := Value;
    ckMinute:
      FMinute := Value;
    ckHour:
      FHour := Value;
    ckDayOfTheMonth:
      FDayOfTheMonth := Value;
    ckMonth:
      FMonth := Value;
    ckDayOfTheWeek:
      FDayOfTheWeek := Value;
    ckYear:
      FYear := Value;
  end;
end;

procedure TCronSchedulePlan.SetSecond(const Value: TCronPart);
begin
  FSecond := Value;
end;

procedure TCronSchedulePlan.SetYear(const Value: TCronPart);
begin
  FYear := Value;
end;

procedure TCronSchedulePlan.ApplyDialectToParts;
begin
  if FDayOfTheWeek <> nil then
    FDayOfTheWeek.fDowOneBased := (fDialect = cdQuartzSecondsFirst);
end;

procedure TCronSchedulePlan.SetDialect(const Value: TmaxCronDialect);
begin
  if fDialect = Value then
    Exit;
  fDialect := Value;
  ApplyDialectToParts;
  if fLastPlan <> '' then
    Parse(fLastPlan);
end;

{ TCronPart }

procedure TCronPart.Add2Range(Value: word);
var
  i: integer;
begin
  if Value >= FValidFrom then
    if Value <= FValidTo then
      if not self.FindInRange(Value, i) then
      begin
        SetLength(fRange, FCount + 1);
        if i < FCount then
          Move(fRange[i], fRange[i + 1], Sizeof(fRange[0]) * (FCount - i));
        fRange[i] := Value;
        inc(FCount);
      end;
end;

procedure TCronPart.Clear;
begin
  fFullrange := false;
  FCount := 0;
  fRange := NIL;
  fNeedsParse := True;
  fNoSpec := False;
  fDomModifier := TCronDomModifier.cdmNone;
  fDomValue := 0;
  fDowModifier := TCronDowModifier.cdwNone;
  fDowValue := 0;
  fDowNth := 0;
end;

constructor TCronPart.Create;
begin
  inherited Create;
  FCount := 0;
  fRange := NIL;
  fPartKind := aPartKind;
  fNeedsParse := False;
  fDowOneBased := False;

  Data := '*';

  case fPartKind of

    ckSecond,
      ckMinute:
      begin
        FValidFrom := 0;
        FValidTo := 59;
      end;
    ckHour:
      begin
        FValidFrom := 0;
        FValidTo := 23;
      end;
    ckDayOfTheMonth:
      begin
        FValidFrom := 1;
        FValidTo := 31;
      end;
    ckMonth:
      begin
        FValidFrom := 1;
        FValidTo := 12;
      end;
    ckDayOfTheWeek:
      begin
        // Internal DOW range: 0 = Sunday, 1 = Monday, ... 6 = Saturday (Quartz 1..7 is normalized when dialect is set).
        FValidFrom := 0;
        FValidTo := 6;
      end;
    ckYear:
      begin
        FValidFrom := 1900;
        FValidTo := 3000;
      end;

  end;
end;

destructor TCronPart.Destroy;
begin
  Clear;
  inherited;
end;

function TCronPart.FindInRange(Value: word; out index: integer): boolean;
var
  C, l, h, i: integer;
begin
  Result := false;
  l := 0;
  h := FCount - 1;
  while l <= h do
  begin
    i := (l + h) shr 1;

    IF fRange[i] > Value then
      C := 1
    else if fRange[i] < Value then
      C := -1
    else
      C := 0;

    if C < 0 then
      l := i + 1
    else
    begin
      h := i - 1;
      if C = 0 then
      Begin
        Result := True;
        Index := i;
        Exit;
      end;
    end;
  end;
  Index := l;
end;

function TCronPart.HasSpecial: Boolean;
begin
  Result := (fDomModifier <> TCronDomModifier.cdmNone) or (fDowModifier <> TCronDowModifier.cdwNone);
end;

function TCronPart.NormalizeDowValue(const aValue: Integer): Integer;
begin
  if fPartKind <> ckDayOfTheWeek then
    Exit(aValue);
  if fDowOneBased then
  begin
    if aValue = 0 then
      Exit(-1);
    if (aValue >= 1) and (aValue <= 7) then
    begin
      if aValue = 7 then
        Exit(6);
      Exit(aValue - 1);
    end;
    Exit(aValue);
  end;
  if aValue = 7 then
    Exit(0);
  Result := aValue;
end;

function TCronPart.Hash32(const aValue: string): Cardinal;
var
  lIndex: Integer;
  lHash: Cardinal;
  lWork: UInt64;
begin
  lHash := 2166136261;
  for lIndex := 1 to Length(aValue) do
  begin
    lWork := UInt64(lHash xor Cardinal(Ord(aValue[lIndex])));
    lWork := (lWork * UInt64(16777619)) and UInt64($FFFFFFFF);
    lHash := Cardinal(lWork);
  end;
  Result := lHash;
end;

function TCronPart.TryParseHashedToken(const aValue: string): Boolean;
var
  lText: string;
  lRangeFrom: Integer;
  lRangeTo: Integer;
  lStep: Integer;
  lSlashPos: Integer;
  lOpenPos: Integer;
  lClosePos: Integer;
  lRangeText: string;
  lDashPos: Integer;
  lHashValue: Cardinal;
  lStart: Integer;
  lValue: Integer;
  lSeed: string;
  lHasExplicitRange: Boolean;
begin
  lText := Trim(aValue);
  if lText = '' then
    Exit(False);
  if UpCase(lText[1]) <> 'H' then
    Exit(False);

  lRangeFrom := FValidFrom;
  lRangeTo := FValidTo;
  lStep := 0;
  lHasExplicitRange := False;

  lOpenPos := Pos('(', lText);
  lClosePos := Pos(')', lText);
  if (lOpenPos > 0) or (lClosePos > 0) then
  begin
    if (lOpenPos <> 2) or (lClosePos <= lOpenPos + 1) then
      raise Exception.Create('Invalid cron token');
    lRangeText := Copy(lText, lOpenPos + 1, lClosePos - lOpenPos - 1);
    lDashPos := Pos('-', lRangeText);
    if lDashPos <= 1 then
      raise Exception.Create('Invalid cron token');
    lRangeFrom := StrToInt(Copy(lRangeText, 1, lDashPos - 1));
    lRangeTo := StrToInt(Copy(lRangeText, lDashPos + 1, MaxInt));
    lHasExplicitRange := True;
    Delete(lText, lOpenPos, lClosePos - lOpenPos + 1);
  end;

  lSlashPos := Pos('/', lText);
  if lSlashPos > 0 then
  begin
    lStep := StrToInt(Copy(lText, lSlashPos + 1, MaxInt));
    if lStep <= 0 then
      raise Exception.Create('Invalid cron step');
    lText := Copy(lText, 1, lSlashPos - 1);
  end;

  if (lText <> 'H') and (lText <> 'h') then
    raise Exception.Create('Invalid cron token');

  if (fPartKind = ckDayOfTheWeek) and fDowOneBased then
  begin
    if not lHasExplicitRange then
    begin
      lRangeFrom := 1;
      lRangeTo := 7;
    end;

    if (lRangeFrom < 1) or (lRangeFrom > 7) then
      raise Exception.Create('Cron value out of range');
    if (lRangeTo < 1) or (lRangeTo > 7) or (lRangeTo < lRangeFrom) then
      raise Exception.Create('Cron value out of range');

    lRangeFrom := NormalizeDowValue(lRangeFrom);
    lRangeTo := NormalizeDowValue(lRangeTo);
  end else begin
    if (lRangeFrom < FValidFrom) or (lRangeFrom > FValidTo) then
      raise Exception.Create('Cron value out of range');
    if (lRangeTo < FValidFrom) or (lRangeTo > FValidTo) or (lRangeTo < lRangeFrom) then
      raise Exception.Create('Cron value out of range');
  end;

  lSeed := fHashSeed + '|' + IntToStr(Ord(fPartKind)) + '|' + aValue;
  lHashValue := Hash32(lSeed);
  lStart := lRangeFrom + Integer(lHashValue mod Cardinal(lRangeTo - lRangeFrom + 1));

  if lStep = 0 then
    Add2Range(lStart)
  else
  begin
    lValue := lStart;
    while lValue <= lRangeTo do
    begin
      Add2Range(lValue);
      Inc(lValue, lStep);
    end;
  end;

  Result := True;
end;

function TCronPart.TryParseSpecialToken(const aToken: string): Boolean;
var
  s: string;
begin
  if not (fPartKind in [ckDayOfTheMonth, ckDayOfTheWeek]) then
    Exit(False);

  s := Trim(aToken);
  if s = '' then
    Exit(False);

  if s = '?' then
  begin
    fNoSpec := True;
    fFullrange := True;
    fRange := NIL;
    FCount := 0;
    Exit(True);
  end;

  if fPartKind = ckDayOfTheMonth then
    Result := TryParseDomSpecial(s)
  else
    Result := TryParseDowSpecial(s);
end;

function TCronPart.TryParseDomSpecial(const aToken: string): Boolean;
var
  s, lOffset: string;
  lNum, i: Integer;
  lModifier: TCronDomModifier;
begin
  s := UpperCase(Trim(aToken));
  if (Pos('L', s) = 0) and (Pos('W', s) = 0) then
    Exit(False);
  if (Pos('#', s) > 0) or (Pos('/', s) > 0) then
    raise Exception.Create('Invalid cron token');
  if s = 'L' then
  begin
    fDomModifier := TCronDomModifier.cdmLastDay;
    Exit(True);
  end;
  if s = 'LW' then
  begin
    fDomModifier := TCronDomModifier.cdmLastWeekday;
    Exit(True);
  end;
  if (Copy(s, 1, 3) = 'LW-') or (Copy(s, 1, 2) = 'L-') then
  begin
    if Pos(',', FData) > 0 then
      raise Exception.Create('Invalid cron token');
    if Copy(s, 1, 3) = 'LW-' then
    begin
      lOffset := Copy(s, 4, MaxInt);
      lModifier := TCronDomModifier.cdmLastWeekday;
    end else begin
      lOffset := Copy(s, 3, MaxInt);
      lModifier := TCronDomModifier.cdmLastDay;
      if (lOffset <> '') and (lOffset[Length(lOffset)] = 'W') then
      begin
        Delete(lOffset, Length(lOffset), 1);
        lModifier := TCronDomModifier.cdmLastDayNearestWeekday;
      end;
    end;
    if lOffset = '' then
      raise Exception.Create('Invalid cron token');
    for i := 1 to Length(lOffset) do
    begin
      if not CharInSet(lOffset[i], ['0'..'9']) then
        raise Exception.Create('Invalid cron token');
    end;
    lNum := StrToIntDef(lOffset, MaxInt);
    if lNum > cCronMaxLastDayOffset then
      raise Exception.Create('Cron value out of range');
    fDomModifier := lModifier;
    fDomValue := lNum;
    Exit(True);
  end;
  if Pos('-', s) > 0 then
    raise Exception.Create('Invalid cron token');
  if s[Length(s)] = 'W' then
  begin
    lNum := StrToIntDef(Copy(s, 1, Length(s) - 1), -1);
    if (lNum < FValidFrom) or (lNum > FValidTo) then
      raise Exception.Create('Cron value out of range');
    fDomModifier := TCronDomModifier.cdmNearestWeekday;
    fDomValue := lNum;
    Exit(True);
  end;
  raise Exception.Create('Invalid cron token');
end;

function TCronPart.TryParseDowSpecial(const aToken: string): Boolean;
var
  s: string;
  lHashPos: Integer;
  lLeft: string;
  lRight: string;
  lNum: Integer;
  lNth: Integer;
begin
  Result := False;
  s := ReplaceDaynames(Trim(aToken));
  s := UpperCase(s);

  if Pos('W', s) > 0 then
    raise Exception.Create('Invalid cron token');

  lHashPos := Pos('#', s);
  if lHashPos > 0 then
  begin
    if (Pos('L', s) > 0) or (Pos('/', s) > 0) or (Pos('-', s) > 0) then
      raise Exception.Create('Invalid cron token');
    lLeft := Copy(s, 1, lHashPos - 1);
    lRight := Copy(s, lHashPos + 1, MaxInt);
    if (lLeft = '') or (lRight = '') then
      raise Exception.Create('Invalid cron token');
    lNum := StrToIntDef(lLeft, -1);
    lNum := NormalizeDowValue(lNum);
    if (lNum < FValidFrom) or (lNum > FValidTo) then
      raise Exception.Create('Cron value out of range');
    lNth := StrToIntDef(lRight, 0);
    if (lNth < 1) or (lNth > 5) then
      raise Exception.Create('Invalid cron token');
    fDowModifier := TCronDowModifier.cdwNthWeekday;
    fDowValue := lNum;
    fDowNth := lNth;
    Exit(True);
  end;

  if (Length(s) > 1) and (s[Length(s)] = 'L') then
  begin
    if (Pos('/', s) > 0) or (Pos('-', s) > 0) then
      raise Exception.Create('Invalid cron token');
    lLeft := Copy(s, 1, Length(s) - 1);
    lNum := StrToIntDef(lLeft, -1);
    lNum := NormalizeDowValue(lNum);
    if (lNum < FValidFrom) or (lNum > FValidTo) then
      raise Exception.Create('Cron value out of range');
    fDowModifier := TCronDowModifier.cdwLastWeekday;
    fDowValue := lNum;
    Exit(True);
  end;

  if s = 'L' then
    raise Exception.Create('Invalid cron token');
end;

function TCronPart.GetLastDayOfMonth(const aYear, aMonth: Word): Word;
begin
  Result := DaysInMonth(EncodeDate(aYear, aMonth, 1));
end;

function TCronPart.GetLastWeekdayOfMonth(const aYear, aMonth: Word; out aDay: Word): Boolean;
var
  lLastDay: Word;
  lDow: Word;
begin
  lLastDay := GetLastDayOfMonth(aYear, aMonth);
  lDow := DayOfTheWeek(EncodeDate(aYear, aMonth, lLastDay)) mod 7;
  case lDow of
    0:
      aDay := lLastDay - 2; // Sunday -> Friday
    6:
      aDay := lLastDay - 1; // Saturday -> Friday
  else
    aDay := lLastDay;
  end;
  Result := aDay >= 1;
end;

function TCronPart.GetLastWeekdayOffsetOfMonth(const aYear, aMonth, aOffset: Word;
  out aDay: Word): Boolean;
var
  i: Integer;
begin
  Result := GetLastWeekdayOfMonth(aYear, aMonth, aDay);
  if not Result then Exit;
  for i := 1 to aOffset do
  begin
    repeat
      if aDay <= 1 then Exit(False);
      Dec(aDay);
    until not ((DayOfTheWeek(EncodeDate(aYear, aMonth, aDay)) mod 7) in [0, 6]);
  end;
end;

function TCronPart.GetNearestWeekdayTo(const aYear, aMonth, aDay: Word; out aNearestDay: Word): Boolean;
var
  lLastDay: Word;
  lDow: Word;
begin
  lLastDay := GetLastDayOfMonth(aYear, aMonth);
  if (aDay < 1) or (aDay > lLastDay) then
    Exit(False);

  lDow := DayOfTheWeek(EncodeDate(aYear, aMonth, aDay)) mod 7;
  case lDow of
    0:
      if aDay = lLastDay then
        aNearestDay := aDay - 2
      else
        aNearestDay := aDay + 1;
    6:
      if aDay = 1 then
        aNearestDay := aDay + 2
      else
        aNearestDay := aDay - 1;
  else
    aNearestDay := aDay;
  end;

  Result := (aNearestDay >= 1) and (aNearestDay <= lLastDay);
end;

function TCronPart.GetNthWeekdayOfMonth(const aYear, aMonth, aDow, aNth: Word; out aDay: Word): Boolean;
var
  lFirstDow: Word;
  lDelta: Integer;
  lDay: Integer;
  lLastDay: Word;
begin
  lLastDay := GetLastDayOfMonth(aYear, aMonth);
  lFirstDow := DayOfTheWeek(EncodeDate(aYear, aMonth, 1)) mod 7;
  lDelta := (7 + aDow - lFirstDow) mod 7;
  lDay := 1 + lDelta + (Integer(aNth) - 1) * 7;
  if lDay > lLastDay then
    Exit(False);
  aDay := lDay;
  Result := True;
end;

function TCronPart.GetLastDowOfMonth(const aYear, aMonth, aDow: Word; out aDay: Word): Boolean;
var
  lLastDay: Word;
  lLastDow: Word;
  lDelta: Integer;
begin
  lLastDay := GetLastDayOfMonth(aYear, aMonth);
  lLastDow := DayOfTheWeek(EncodeDate(aYear, aMonth, lLastDay)) mod 7;
  lDelta := (7 + lLastDow - aDow) mod 7;
  aDay := lLastDay - lDelta;
  Result := aDay >= 1;
end;

function TCronPart.TryGetDomSpecialDay(const aYear, aMonth: Word; out aDay: Word): Boolean;
var
  lLast: Word;
begin
  Result := False;
  case fDomModifier of
    TCronDomModifier.cdmLastDay, TCronDomModifier.cdmLastDayNearestWeekday:
      begin
        lLast := GetLastDayOfMonth(aYear, aMonth);
        if fDomValue >= lLast then Exit;
        if fDomModifier = TCronDomModifier.cdmLastDay then
        begin
          aDay := lLast - fDomValue;
          Result := True;
        end else
          Result := GetNearestWeekdayTo(aYear, aMonth, lLast - fDomValue, aDay);
      end;
    TCronDomModifier.cdmLastWeekday:
      Result := GetLastWeekdayOffsetOfMonth(aYear, aMonth, fDomValue, aDay);
    TCronDomModifier.cdmNearestWeekday:
      Result := GetNearestWeekdayTo(aYear, aMonth, fDomValue, aDay);
  end;
end;

function TCronPart.TryGetDowSpecialDay(const aYear, aMonth: Word; out aDay: Word): Boolean;
begin
  Result := False;
  case fDowModifier of
    TCronDowModifier.cdwLastWeekday:
      Result := GetLastDowOfMonth(aYear, aMonth, fDowValue, aDay);
    TCronDowModifier.cdwNthWeekday:
      Result := GetNthWeekdayOfMonth(aYear, aMonth, fDowValue, fDowNth, aDay);
  end;
end;

function TCronPart.GetFullrange: boolean;
begin
  if fNoSpec then
    Exit(True);
  if HasSpecial then
    Exit(False);
  Result := fFullrange OR (FCount = 0)
end;

function TCronPart.NextVal(v: word): word;
var
  i: integer;
begin
  if Fullrange then
    Result := v
  else
  begin
    if FindInRange(v, i) then
      Result := v
    else
    begin
      if i < FCount then
        Result := fRange[i]
      else
        Result := fRange[0];
    end;
  end;

end;

function TCronPart.IsAny: Boolean;
begin
  Result := Fullrange or fNoSpec;
end;

function TCronPart.IsNoSpec: Boolean;
begin
  Result := fNoSpec;
end;

function TCronPart.HasSpecialTokens: Boolean;
begin
  Result := HasSpecial;
end;

function TCronPart.TryGetSingleValue(out aValue: Word): Boolean;
begin
  if fNoSpec then
    Exit(False);
  if HasSpecial then
    Exit(False);
  if (not fFullrange) and (FCount = 1) then
  begin
    aValue := fRange[0];
    Exit(True);
  end;
  Result := False;
end;

function TCronPart.TryGetStep(out aStart, aStep: Word; out aCoversFullRange: Boolean): Boolean;
var
  i: Integer;
  lStep: Integer;
begin
  aStart := 0;
  aStep := 0;
  aCoversFullRange := False;

  if fNoSpec then
    Exit(False);
  if HasSpecial then
    Exit(False);

  if fFullrange then
  begin
    aStart := FValidFrom;
    aStep := 1;
    aCoversFullRange := True;
    Exit(True);
  end;

  if FCount = 0 then
    Exit(False);

  aStart := fRange[0];
  if FCount = 1 then
  begin
    aStep := 0;
    Exit(True);
  end;

  lStep := fRange[1] - fRange[0];
  if lStep <= 0 then
    Exit(False);

  for i := 2 to FCount - 1 do
    if (fRange[i] - fRange[i - 1]) <> lStep then
      Exit(False);

  aStep := lStep;
  if (aStart = FValidFrom) and (fRange[FCount - 1] = FValidTo) then
    aCoversFullRange := ((FValidTo - FValidFrom) div aStep + 1) = FCount;

  Result := True;
end;

function TCronPart.GetValues(out aValues: TWordArray): Boolean;
begin
  SetLength(aValues, 0);
  if fNoSpec then
    Exit(False);
  if HasSpecial then
    Exit(False);
  if fFullrange then
    Exit(False);
  if FCount = 0 then
    Exit(False);

  SetLength(aValues, FCount);
  if FCount > 0 then
    Move(fRange[0], aValues[0], SizeOf(fRange[0]) * FCount);
  Result := True;
end;

function TCronPart.DescribeDomSpecial: string;
begin
  case fDomModifier of
    TCronDomModifier.cdmLastDay:
      if fDomValue = 0 then Result := 'the last day'
      else if fDomValue = 1 then Result := 'the last day minus 1 day'
      else Result := Format(cDescribeLastDayMinusDays, [fDomValue]);
    TCronDomModifier.cdmLastWeekday:
      if fDomValue = 0 then Result := 'the last weekday'
      else if fDomValue = 1 then Result := 'the last weekday minus 1 weekday'
      else Result := Format(cDescribeLastWeekdayMinusWeekdays, [fDomValue]);
    TCronDomModifier.cdmLastDayNearestWeekday:
      if fDomValue = 0 then Result := 'the nearest weekday to the last day'
      else if fDomValue = 1 then Result := 'the nearest weekday to the last day minus 1 day'
      else Result := Format(cDescribeLastDayNearestMinusDays, [fDomValue]);
    TCronDomModifier.cdmNearestWeekday:
      Result := Format('the nearest weekday to %d', [fDomValue]);
  else
    Result := '';
  end;
end;

procedure TCronPart.Parse;
var
  x: integer;
  l: TStringList;
  lToken: string;
  lHasSpecial: Boolean;
begin
  Clear;

  if Trim(FData) = '' then
  begin
    fFullrange := True;
    fRange := NIL;
    FCount := 0;
    Exit;
  end;

  if FData = '*' then
  begin
    fFullrange := True;
    fRange := NIL;
    FCount := 0;
  end
  else
  begin
    if (Length(FData) > 0) and ((FData[1] = ',') or (FData[Length(FData)] = ',') or (Pos(',,', FData) > 0)) then
      raise Exception.Create('Invalid cron token');

    l := TStringList.Create;
    try
      SplitString(FData, ',', l);
      if l.Count > 1 then
        for x := 0 to l.Count - 1 do
          if Trim(l[x]) = '*' then
            raise Exception.Create('Invalid cron token');
      lHasSpecial := False;
      for x := 0 to l.Count - 1 do
      begin
        lToken := Trim(l[x]);
        if lToken = '' then
          raise Exception.Create('Invalid cron token');
        if TryParseSpecialToken(lToken) then
        begin
          if (l.Count > 1) or lHasSpecial then
            raise Exception.Create('Invalid cron token');
          lHasSpecial := True;
        end;
      end;

      if lHasSpecial then
        Exit;

      for x := 0 to l.Count - 1 do
      begin
        if l[x] = '*' then
        begin
          fFullrange := True;
          fRange := NIL;
          FCount := 0;
        end
        else
          ParsePart(l[x]);
      end;
    finally
      l.Free;
    end;
  end;
end;

procedure TCronPart.ParsePart(const Value: string);
var
  iR: integer;
  RangeTo: Integer;
  RangeFrom: Integer;
  s: string;
  Repeater: integer;
  iSlash: Integer;
  lIsStar: Boolean;

  procedure AddRange(const aFrom, aTo, aStep: Integer);
  var
    v: Integer;
  begin
    v := aFrom;
    while v <= aTo do
    begin
      Add2Range(v);
      Inc(v, aStep);
    end;
  end;
begin

  s := Trim(Value);
  if s = '' then
    raise Exception.Create('Invalid cron token');
  if TryParseHashedToken(s) then
    Exit;
  if Pos('?', s) > 0 then
    raise Exception.Create('Invalid cron token');
  case fPartKind of
    ckMonth:
      s := ReplaceMonthNames(s);
    ckDayOfTheWeek:
      s := ReplaceDaynames(s);
  end;

  iSlash := Pos('/', s);
  if iSlash > 0 then
  begin
    Repeater := StrToInt(Copy(s, iSlash + 1, MaxInt));
    if Repeater <= 0 then
      raise Exception.Create('Invalid cron step');
    s := Copy(s, 1, iSlash - 1);
  end else
    Repeater := 1;

  iR := Pos('-', s);
  lIsStar := (s = '*');
  if lIsStar then
  begin
    RangeFrom := FValidFrom;
    RangeTo := FValidTo;
  end else if iR > 0 then
  begin
    RangeFrom := StrToInt(Copy(s, 1, iR - 1));
    RangeTo := StrToInt(Copy(s, iR + 1, MaxInt));
  end else
  begin
    RangeFrom := StrToInt(s);
    if iSlash > 0 then
    begin
      if (fPartKind = ckDayOfTheWeek) and fDowOneBased then
        RangeTo := 7
      else
        RangeTo := FValidTo; // n/k => n..max
    end
    else
      RangeTo := RangeFrom;
  end;

  if not (lIsStar and (fPartKind = ckDayOfTheWeek) and fDowOneBased) then
  begin
    RangeFrom := NormalizeDowValue(RangeFrom);
    RangeTo := NormalizeDowValue(RangeTo);
  end;

  if (RangeFrom < FValidFrom) or (RangeFrom > FValidTo) then
    raise Exception.Create('Cron value out of range');
  if (RangeTo < FValidFrom) or (RangeTo > FValidTo) then
    raise Exception.Create('Cron value out of range');

  if (iR > 0) and (RangeTo < RangeFrom) then
  begin
    if fPartKind = ckDayOfTheWeek then
    begin
      AddRange(RangeFrom, FValidTo, Repeater);
      AddRange(FValidFrom, RangeTo, Repeater);
      Exit;
    end;
    raise Exception.Create('Invalid cron range');
  end;

  AddRange(RangeFrom, RangeTo, Repeater);
end;

function TCronPart.PushDayOfMonth(var NextDate: TDateTime): boolean;
var
  dc, v, i: word;
  lYear, lMonth, lDay: Word;
  lTarget: Word;
begin
  Result := True;
  if fNoSpec then
    Exit(True);

  if fDomModifier <> TCronDomModifier.cdmNone then
  begin
    DecodeDate(NextDate, lYear, lMonth, lDay);
    if not TryGetDomSpecialDay(lYear, lMonth, lTarget) then
    begin
      NextDate := EncodeDateTime(lYear, lMonth, 1, 0, 0, 0, 0);
      NextDate := IncMonth(NextDate);
      Result := False;
      Exit;
    end;

    if lTarget < lDay then
    begin
      NextDate := EncodeDateTime(lYear, lMonth, 1, 0, 0, 0, 0);
      NextDate := IncMonth(NextDate);
      Result := False;
      Exit;
    end;

    if lTarget > lDay then
      NextDate := EncodeDateTime(lYear, lMonth, lTarget, 0, 0, 0, 0);
    Exit;
  end;

  if not Fullrange then
  begin
    v := DayOf(NextDate);
    i := NextVal(v);
    if i < v then
    begin
      NextDate := EncodeDateTime(YearOf(NextDate), MonthOf(NextDate), i, 0, 0, 0, 0);
      NextDate := IncMonth(NextDate);
      Result := false;
    end
    else if i > v then
    begin
      dc := DaysInMonth(NextDate);
      if i <= dc then
        NextDate := EncodeDateTime(YearOf(NextDate), MonthOf(NextDate), i, 0, 0, 0, 0)
      else
      begin
        NextDate := EncodeDateTime(YearOf(NextDate), MonthOf(NextDate), 1, 0, 0, 0, 0);
        NextDate := IncMonth(NextDate);
        Result := false;
      end;
    end;
  end;
end;

function TCronPart.PushDayOfWeek(var NextDate: TDateTime): boolean;
var
  v, i: word;
  lYear, lMonth, lDay: Word;
  lTarget: Word;
  lStamp: TTimeStamp;
begin
  Result := True;
  if fNoSpec then
    Exit(True);

  if fDowModifier <> TCronDowModifier.cdwNone then
  begin
    DecodeDate(NextDate, lYear, lMonth, lDay);
    if not TryGetDowSpecialDay(lYear, lMonth, lTarget) then
    begin
      NextDate := EncodeDateTime(lYear, lMonth, 1, 0, 0, 0, 0);
      NextDate := IncMonth(NextDate);
      Result := False;
      Exit;
    end;

    if lTarget < lDay then
    begin
      NextDate := EncodeDateTime(lYear, lMonth, 1, 0, 0, 0, 0);
      NextDate := IncMonth(NextDate);
      Result := False;
      Exit;
    end;

    if lTarget > lDay then
    begin
      Result := False;
      NextDate := EncodeDateTime(lYear, lMonth, lTarget, 0, 0, 0, 0);
      Exit;
    end;

    Exit(True);
  end;

  if not Fullrange then
  begin
    // Internal DOW: 0 = Sunday, 1 = Monday, ... 6 = Saturday.
    v := DayOfTheWeek(NextDate) mod 7;
    i := NextVal(v);
    if i <> v then
    begin
      Result := false;
      lStamp := DateTimeToTimeStamp(NextDate);
      NextDate := lStamp.Date - DateDelta; // reset the normalized day to midnight
      if i > v then
        NextDate := NextDate + (i - v)
      else
        NextDate := NextDate + (7 - v) + i;

    end;

  end;
end;

function TCronPart.PushHour(var NextDate: TDateTime): boolean;
var
  v, i, h, m, s, ms: Word;
  lStamp: TTimeStamp;
  lDate: TDateTime;
begin
  Result := True;
  if not Fullrange then
  begin
    lStamp := DateTimeToTimeStamp(NextDate);
    DecodeSearchClock(lStamp, h, m, s, ms);
    lDate := lStamp.Date - DateDelta;
    v := h;
    i := NextVal(v);
    if i < v then
    begin
      Result := false;
      NextDate := lDate + 1 + i * OneHour;
    end
    else if i > v then
      NextDate := lDate + i * OneHour;
  end;
end;

function TCronPart.PushMinute(var NextDate: TDateTime): boolean;
var
  h, m, s, ms, v, i: Word;
  lStamp: TTimeStamp;
  lDate: TDateTime;
begin
  Result := True;
  if not Fullrange then
  begin
    lStamp := DateTimeToTimeStamp(NextDate);
    DecodeSearchClock(lStamp, h, m, s, ms);
    lDate := lStamp.Date - DateDelta;
    v := m;
    i := NextVal(v);
    if i < v then
    begin
      Result := false;
      if h = 23 then
        NextDate := lDate + 1 + i * OneMinute
      else
        NextDate := lDate + (h + 1) * OneHour + i * OneMinute;
    end
    else if i > v then
    begin
      NextDate := lDate + h * OneHour + i * OneMinute;
    end;
  end;
end;

function TCronPart.PushMonth(var NextDate: TDateTime): boolean;
var
  v, i: word;
begin
  Result := True;
  if not Fullrange then
  begin
    v := MonthOf(NextDate);
    i := NextVal(v);
    if i < v then
    begin
      NextDate := EncodeDateTime(YearOf(NextDate) + 1, i, 1, 0, 0, 0, 0);
      Result := false;
    end
    else if i > v then
    begin
      NextDate := EncodeDateTime(YearOf(NextDate), i, 1, 0, 0, 0, 0)
    end;
  end;

end;

function TCronPart.PushSecond(var NextDate: TDateTime): boolean;
var
  h, m, s, ms, v, i: Word;
  lStamp: TTimeStamp;
  lDate: TDateTime;
begin
  Result := True;
  if not Fullrange then
  begin
    lStamp := DateTimeToTimeStamp(NextDate);
    DecodeSearchClock(lStamp, h, m, s, ms);
    lDate := lStamp.Date - DateDelta;
    v := s;
    i := NextVal(v);
    if i < v then
    begin
      Result := false;
      // Carry an integer day before adding the fractional clock.
      if (h = 23) and (m = 59) then
        NextDate := lDate + 1 + i * OneSecond
      else
        NextDate := lDate + h * OneHour + (m + 1) * OneMinute + i * OneSecond;
    end
    else if i > v then
    begin
      NextDate := lDate + h * OneHour + m * OneMinute + i * OneSecond;
    end;
  end;

end;

function TCronPart.PushYear(var NextDate: TDateTime): boolean;
var
  v, i: word;
begin
  Result := True;
  v := YearOf(NextDate);
  if v > FValidTo then
  begin
    Result := false;
    Exit;
  end;

  if not Fullrange then
  begin
    i := self.NextVal(v);
    if i < v then
      Result := false
    else if i > v then
    begin
      NextDate := EncodeDateTime(i, 1, 1, 0, 0, 0, 0)
    end;
  end;
end;

function TCronPart.ReplaceDaynames(const Value: string): string;
var
  x: integer;
  s: string;
begin
  s := Value;
  for x := 1 to 7 do
  begin
    if fDowOneBased then
    begin
      // Quartz-compatible: Sun = 1, Mon = 2, ... Sat = 7
      if x = 7 then
        s := StringReplace(s, DayNames[x], '1', [rfReplaceAll, rfIgnorecase])
      else
        s := StringReplace(s, DayNames[x], IntToStr(x + 1), [rfReplaceAll, rfIgnorecase]);
    end else
    begin
      // Cron-compatible: Sun = 0 (also accept 7 as Sunday numerically in ParsePart)
      if x = 7 then
        s := StringReplace(s, DayNames[x], '0', [rfReplaceAll, rfIgnorecase])
      else
        s := StringReplace(s, DayNames[x], IntToStr(x), [rfReplaceAll, rfIgnorecase]);
    end;
  end;
  Result := s;
end;

function TCronPart.ReplaceMonthNames(const Value: string): string;
var
  x: integer;
  s: string;
begin
  s := Value;
  for x := 1 to 12 do
    s := StringReplace(s, MonthNames[x], IntToStr(x), [rfReplaceAll, rfIgnorecase]);
  Result := s;
end;

procedure TCronPart.SetData(const Value: string);
begin
  if (FData <> Value) or fNeedsParse then
  begin
    FData := Value;
    Parse;
    fNeedsParse := False;
  end;
end;

{ TPlan }

function TPlan.asString: String;
const
  sep = ' ';

  function process(const s: string; aDefault: char = '*'): string;
  begin
    Result := Trim(s);
    if Result = '' then
      Result := aDefault;
  end;

var
  lYear: string;
begin
  case fDialect of
    cdStandard:
      Result :=
        process(Minute) + sep +
        process(Hour) + sep +
        process(DayOfTheMonth) + sep +
        process(Month) + sep +
        process(DayOfTheWeek);
    cdQuartzSecondsFirst:
      begin
        lYear := Trim(Year);
        Result :=
          process(Second, '0') + sep +
          process(Minute) + sep +
          process(Hour) + sep +
          process(DayOfTheMonth) + sep +
          process(Month) + sep +
          process(DayOfTheWeek);
        if (lYear <> '') and (lYear <> '*') then
          Result := Result + sep + lYear;
      end;
  else
    Result :=
      process(Minute) + sep +
      process(Hour) + sep +
      process(DayOfTheMonth) + sep +
      process(Month) + sep +
      process(DayOfTheWeek) + sep +
      process(Year) + sep +
      process(Second, '0') + sep +
      process(ExecutionLimit, '0');
  end;
end;

procedure TPlan.reset;
begin
  fDialect := cdMaxCron;
  Minute := '';
  Hour := '';
  DayOfTheMonth := '';
  Month := '';
  DayOfTheWeek := '';
  Year := '';
  Second := '0';
  ExecutionLimit := '0';
end;

procedure TPlan.setText(const Value: string);
var
  l: TStringList;
  s: string;
  x: integer;
  lDialect: TmaxCronDialect;
begin
  lDialect := fDialect;
  reset;
  fDialect := lDialect;

  s := StripCronComment(Value);
  s := NormalizeCommaWhitespace(s);
  s := Trim(s);
  if s = '' then
  begin
    case fDialect of
      cdStandard:
        raise Exception.Create('Cron plan must have exactly 5 fields');
      cdQuartzSecondsFirst:
        raise Exception.Create('Cron plan must have 6 or 7 fields');
    else
      raise Exception.Create('Cron plan must have at least 5 fields');
    end;
  end;
  if s[1] = '@' then
  begin
    if not TryApplyCronMacro(s, Self) then
      raise Exception.Create('Unknown cron macro');
    Exit;
  end;

  l := TStringList.Create;
  try
    SplitByWhitespace(s, l);

    case fDialect of
      cdStandard:
        if l.Count <> 5 then
          raise Exception.Create('Cron plan must have exactly 5 fields');
      cdQuartzSecondsFirst:
        if (l.Count < 6) or (l.Count > 7) then
          raise Exception.Create('Cron plan must have 6 or 7 fields');
    else
      begin
        if l.Count < 5 then
          raise Exception.Create('Cron plan must have at least 5 fields');
        if l.Count > Length(parts) then
          raise Exception.Create('Cron plan has too many fields');
      end;
    end;

    for x := 0 to l.Count - 1 do
      if (Length(l[x]) > 0) and ((l[x][1] = ',') or (l[x][Length(l[x])] = ',') or (Pos(',,', l[x]) > 0)) then
        raise Exception.Create('Invalid cron token');

    case fDialect of
      cdStandard:
        begin
          Minute := l[0];
          Hour := l[1];
          DayOfTheMonth := l[2];
          Month := l[3];
          DayOfTheWeek := l[4];
        end;
      cdQuartzSecondsFirst:
        begin
          Second := l[0];
          Minute := l[1];
          Hour := l[2];
          DayOfTheMonth := l[3];
          Month := l[4];
          DayOfTheWeek := l[5];
          if l.Count > 6 then
            Year := l[6];
        end;
    else
      for x := 0 to Min(Length(parts), l.Count) - 1 do
        parts[x] := l[x];
    end;
  finally
    l.Free;
  end;

end;

end.

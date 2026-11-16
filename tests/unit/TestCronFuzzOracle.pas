unit TestCronFuzzOracle;

interface

uses
  System.DateUtils, System.SysUtils,
  DUnitX.TestFramework,
  maxCron;

type
  [TestFixture]
  TTestCronFuzzOracle = class
  private
    function ReadEnvInt(const aName: string; const aDefault, aMin, aMax: Integer): Integer;
    function DialectToText(const aDialect: TmaxCronDialect): string;
    function DayMatchModeToText(const aMode: TmaxCronDayMatchMode): string;
    function RandomValueToken(const aMinValue, aMaxValue: Integer): string;
    function RandomValueListToken(const aMinValue, aMaxValue: Integer): string;
    function RandomRangeToken(const aMinValue, aMaxValue: Integer): string;
    function RandomStepToken(const aMinValue, aMaxValue: Integer): string;
    function BuildRandomToken(const aMinValue, aMaxValue: Integer; const aAllowWildcard: Boolean): string;
    function BuildRandomDayOfWeekToken(const aDialect: TmaxCronDialect): string;
    function PickToken(const aTokens: array of string): string;
    function BuildPlanText(const aDialect: TmaxCronDialect; const aDayMatchMode: TmaxCronDayMatchMode): string;
    function MatchesPart(const aPart: TCronPart; const aValue: Word): Boolean;
    function MatchesDateTime(const aSchedule: TCronSchedulePlan; const aDateTime: TDateTime;
      const aDayMatchMode: TmaxCronDayMatchMode): Boolean;
    function BuildOracleOccurrences(const aSchedule: TCronSchedulePlan; const aDayMatchMode: TmaxCronDayMatchMode;
      const aFromDate: TDateTime; const aCount, aMaxScanSeconds: Integer): TDates;
    function BuildCaseHint(const aSeed, aCaseIndex: Integer; const aDialect: TmaxCronDialect;
      const aDayMatchMode: TmaxCronDayMatchMode; const aPlan: string; const aFromDate: TDateTime): string;
    procedure CheckNextOracle(const aText, aDom, aDow: string;
      const aDialect: TmaxCronDialect; const aMode: TmaxCronDayMatchMode;
      const aSeed: string; const aBase: TDateTime; var aFailures: string; var aChecked: Integer);
  public
    [Test] procedure NextDate_MonotonicAndFirstOccurrence;
    [Test]
    procedure NextOccurrences_MatchBruteForceOracle;
  end;

implementation

function TTestCronFuzzOracle.ReadEnvInt(const aName: string; const aDefault, aMin, aMax: Integer): Integer;
var
  lText: string;
  lParsed: Integer;
begin
  lText := Trim(GetEnvironmentVariable(aName));
  if (lText <> '') and TryStrToInt(lText, lParsed) then
    Result := lParsed
  else
    Result := aDefault;

  if Result < aMin then
    Result := aMin;
  if Result > aMax then
    Result := aMax;
end;

function TTestCronFuzzOracle.DialectToText(const aDialect: TmaxCronDialect): string;
begin
  case aDialect of
    cdStandard:
      Result := 'standard';
    cdQuartzSecondsFirst:
      Result := 'quartz-seconds-first';
  else
    Result := 'maxcron';
  end;
end;

function TTestCronFuzzOracle.DayMatchModeToText(const aMode: TmaxCronDayMatchMode): string;
begin
  case aMode of
    dmAnd:
      Result := 'and';
    dmOr:
      Result := 'or';
  else
    Result := 'default';
  end;
end;

function TTestCronFuzzOracle.RandomValueToken(const aMinValue, aMaxValue: Integer): string;
begin
  Result := IntToStr(aMinValue + Random((aMaxValue - aMinValue) + 1));
end;

function TTestCronFuzzOracle.RandomValueListToken(const aMinValue, aMaxValue: Integer): string;
var
  lFirst: Integer;
  lSecond: Integer;
begin
  lFirst := aMinValue + Random((aMaxValue - aMinValue) + 1);
  lSecond := aMinValue + Random((aMaxValue - aMinValue) + 1);
  if lSecond = lFirst then
  begin
    if lSecond < aMaxValue then
      Inc(lSecond)
    else if lSecond > aMinValue then
      Dec(lSecond);
  end;
  if lFirst > lSecond then
  begin
    lFirst := lFirst xor lSecond;
    lSecond := lFirst xor lSecond;
    lFirst := lFirst xor lSecond;
  end;
  Result := IntToStr(lFirst) + ',' + IntToStr(lSecond);
end;

function TTestCronFuzzOracle.RandomRangeToken(const aMinValue, aMaxValue: Integer): string;
var
  lStart: Integer;
  lStop: Integer;
begin
  lStart := aMinValue + Random((aMaxValue - aMinValue) + 1);
  lStop := aMinValue + Random((aMaxValue - aMinValue) + 1);
  if lStart > lStop then
  begin
    lStart := lStart xor lStop;
    lStop := lStart xor lStop;
    lStart := lStart xor lStop;
  end;
  if lStart = lStop then
    Exit(IntToStr(lStart));
  Result := IntToStr(lStart) + '-' + IntToStr(lStop);
end;

function TTestCronFuzzOracle.RandomStepToken(const aMinValue, aMaxValue: Integer): string;
var
  lStep: Integer;
  lRangeSize: Integer;
begin
  lRangeSize := aMaxValue - aMinValue;
  if lRangeSize < 2 then
    Exit(IntToStr(aMinValue));

  lStep := 2 + Random(4);
  if lStep > lRangeSize then
    lStep := 2;
  Result := '*/' + IntToStr(lStep);
end;

function TTestCronFuzzOracle.BuildRandomToken(const aMinValue, aMaxValue: Integer;
  const aAllowWildcard: Boolean): string;
var
  lPick: Integer;
begin
  lPick := Random(6);
  if aAllowWildcard and (lPick = 0) then
    Exit('*');

  if (lPick = 1) then
    Exit(RandomValueToken(aMinValue, aMaxValue));
  if (lPick = 2) then
    Exit(RandomValueListToken(aMinValue, aMaxValue));
  if (lPick = 3) then
    Exit(RandomRangeToken(aMinValue, aMaxValue));
  if (lPick = 4) then
    Exit(RandomStepToken(aMinValue, aMaxValue));

  Result := RandomValueToken(aMinValue, aMaxValue);
end;

function TTestCronFuzzOracle.BuildRandomDayOfWeekToken(const aDialect: TmaxCronDialect): string;
begin
  if aDialect = cdQuartzSecondsFirst then
    Result := BuildRandomToken(1, 7, True)
  else
    Result := BuildRandomToken(0, 6, True);
end;

function TTestCronFuzzOracle.PickToken(const aTokens: array of string): string;
begin
  Result := aTokens[Random(Length(aTokens))];
end;

function TTestCronFuzzOracle.BuildPlanText(const aDialect: TmaxCronDialect;
  const aDayMatchMode: TmaxCronDayMatchMode): string;
var
  lDowRestricted: string;
  lSecond: string;
  lMinute: string;
  lHour: string;
  lDom: string;
  lMonth: string;
  lDow: string;
  lYear: string;
begin
  lSecond := PickToken(['0', '*/10', '*/15', '0,30']);
  lMinute := PickToken(['*', '*/5', '*/10', '0,15,30,45']);
  lHour := PickToken(['*', '*/2', '*/6', '0,12']);
  lMonth := '*';
  lYear := '*';

  if aDialect = cdQuartzSecondsFirst then
    lDowRestricted := PickToken(['1,3,5', '2,4,6', '7'])
  else
    lDowRestricted := PickToken(['1,3,5', '2,4,6', '0']);

  if (aDayMatchMode = dmAnd) or (aDayMatchMode = dmDefault) then
  begin
    lDom := '*';
    if Random(3) = 0 then
      lDow := '*'
    else
      lDow := lDowRestricted;
  end else begin
    lDom := PickToken(['*/2', '1,15', '*']);
    lDow := lDowRestricted;
  end;

  case aDialect of
    cdStandard:
      Result := lMinute + ' ' + lHour + ' ' + lDom + ' ' + lMonth + ' ' + lDow;
    cdQuartzSecondsFirst:
      Result := lSecond + ' ' + lMinute + ' ' + lHour + ' ' + lDom + ' ' + lMonth + ' ' + lDow + ' ' + lYear;
  else
    Result := lMinute + ' ' + lHour + ' ' + lDom + ' ' + lMonth + ' ' + lDow + ' ' + lYear + ' ' + lSecond + ' 0';
  end;
end;

function TTestCronFuzzOracle.MatchesPart(const aPart: TCronPart; const aValue: Word): Boolean;
begin
  if aPart.IsAny or aPart.IsNoSpec then
    Exit(True);
  Result := aPart.NextVal(aValue) = aValue;
end;

function TTestCronFuzzOracle.MatchesDateTime(const aSchedule: TCronSchedulePlan; const aDateTime: TDateTime;
  const aDayMatchMode: TmaxCronDayMatchMode): Boolean;
var
  lYear: Word;
  lMonth: Word;
  lDay: Word;
  lHour: Word;
  lMinute: Word;
  lSecond: Word;
  lMilli: Word;
  lDomMatch: Boolean;
  lDowMatch: Boolean;
  lDow: Word;
  lMode: TmaxCronDayMatchMode;
begin
  DecodeDateTime(aDateTime, lYear, lMonth, lDay, lHour, lMinute, lSecond, lMilli);

  if not MatchesPart(aSchedule.Year, lYear) then
    Exit(False);
  if not MatchesPart(aSchedule.Month, lMonth) then
    Exit(False);
  if not MatchesPart(aSchedule.Hour, lHour) then
    Exit(False);
  if not MatchesPart(aSchedule.Minute, lMinute) then
    Exit(False);
  if not MatchesPart(aSchedule.Second, lSecond) then
    Exit(False);

  lDomMatch := MatchesPart(aSchedule.Day_of_the_Month, lDay);
  lDow := DayOfTheWeek(aDateTime) mod 7;
  lDowMatch := MatchesPart(aSchedule.Day_of_the_Week, lDow);

  lMode := aDayMatchMode;
  if lMode = dmDefault then
    lMode := dmAnd;

  if (lMode = dmAnd) or aSchedule.Day_of_the_Month.Fullrange or aSchedule.Day_of_the_Week.Fullrange then
    Result := lDomMatch and lDowMatch
  else
    Result := lDomMatch or lDowMatch;
end;

function TTestCronFuzzOracle.BuildOracleOccurrences(const aSchedule: TCronSchedulePlan;
  const aDayMatchMode: TmaxCronDayMatchMode; const aFromDate: TDateTime; const aCount,
  aMaxScanSeconds: Integer): TDates;
var
  lScan: Integer;
  lCursor: TDateTime;
  lFound: Integer;
begin
  SetLength(Result, aCount);
  lCursor := IncSecond(aFromDate, 1);
  lScan := 0;
  lFound := 0;

  while (lFound < aCount) and (lScan < aMaxScanSeconds) do
  begin
    if MatchesDateTime(aSchedule, lCursor, aDayMatchMode) then
    begin
      Result[lFound] := lCursor;
      Inc(lFound);
    end;

    lCursor := IncSecond(lCursor, 1);
    Inc(lScan);
  end;

  SetLength(Result, lFound);
end;

function TTestCronFuzzOracle.BuildCaseHint(const aSeed, aCaseIndex: Integer;
  const aDialect: TmaxCronDialect; const aDayMatchMode: TmaxCronDayMatchMode; const aPlan: string;
  const aFromDate: TDateTime): string;
begin
  Result := Format('seed=%d case=%d dialect=%s dayMatch=%s from=%s plan="%s"',
    [aSeed, aCaseIndex, DialectToText(aDialect), DayMatchModeToText(aDayMatchMode),
    DateTimeToStr(aFromDate), aPlan]);
end;

procedure TTestCronFuzzOracle.NextOccurrences_MatchBruteForceOracle;
const
  cDialects: array[0..2] of TmaxCronDialect = (cdStandard, cdMaxCron, cdQuartzSecondsFirst);
  cModes: array[0..2] of TmaxCronDayMatchMode = (dmDefault, dmAnd, dmOr);
var
  lSeed: Integer;
  lCasesPerCombo: Integer;
  lOccurrenceCount: Integer;
  lMaxScanSeconds: Integer;
  lDialect: TmaxCronDialect;
  lMode: TmaxCronDayMatchMode;
  lCaseIndex: Integer;
  lSchedule: TCronSchedulePlan;
  lPlan: string;
  lFromDate: TDateTime;
  lCaseHint: string;
  lExpected: TDates;
  lActual: TDates;
  lExpectedCount: Integer;
  lActualCount: Integer;
  lIndex: Integer;
begin
  lSeed := ReadEnvInt('MAXCRON_FUZZ_SEED', 137031, 1, High(Integer));
  lCasesPerCombo := ReadEnvInt('MAXCRON_FUZZ_CASES', 36, 1, 250);
  lOccurrenceCount := ReadEnvInt('MAXCRON_FUZZ_OCCURRENCES', 6, 1, 48);
  lMaxScanSeconds := ReadEnvInt('MAXCRON_FUZZ_SCAN_SECONDS', 604800, 120, 31536000);

  RandSeed := lSeed;

  for lDialect in cDialects do
  begin
    for lMode in cModes do
    begin
      for lCaseIndex := 1 to lCasesPerCombo do
      begin
        lPlan := BuildPlanText(lDialect, lMode);
        lFromDate := EncodeDateTime(2026, 1, 1 + Random(20), Random(24), Random(60), Random(60), 0);
        lCaseHint := BuildCaseHint(lSeed, lCaseIndex, lDialect, lMode, lPlan, lFromDate);

        lSchedule := TCronSchedulePlan.Create;
        try
          lSchedule.Dialect := lDialect;
          lSchedule.DayMatchMode := lMode;
          lSchedule.Parse(lPlan);

          lExpected := BuildOracleOccurrences(lSchedule, lMode, lFromDate, lOccurrenceCount, lMaxScanSeconds);
          lExpectedCount := Length(lExpected);
          Assert.AreEqual(lOccurrenceCount, lExpectedCount,
            'Oracle did not find enough occurrences; increase MAXCRON_FUZZ_SCAN_SECONDS. ' + lCaseHint);

          lActualCount := lSchedule.GetNextOccurrences(lOccurrenceCount, lFromDate, lActual);
          Assert.AreEqual(lExpectedCount, lActualCount,
            'Occurrence count mismatch. ' + lCaseHint);

          for lIndex := 0 to lExpectedCount - 1 do
            Assert.AreEqual(lExpected[lIndex], lActual[lIndex], 0.0,
              Format('Occurrence mismatch at index=%d. %s', [lIndex, lCaseHint]));
        finally
          lSchedule.Free;
        end;
      end;
    end;
  end;
end;


type
  TNextRegression = record
    Text: string;
    Dialect, Mode, Seed, H, M, S: Integer;
  end;

function NextOracleSerial(const aDate: TDateTime): Int64;
var
  lStamp: TTimeStamp;
begin
  lStamp := DateTimeToTimeStamp(aDate);
  Result := Int64(lStamp.Date) * 86400 + lStamp.Time div 1000;
end;

function NextOracleDayMatches(const aPlan: TCronSchedulePlan; const aDom, aDow: string;
  const aDate: TDateTime): Boolean;
var
  y, mo, d, lLast, lTarget, lDow: Word;
  lDomMatch, lDowMatch: Boolean;
  lPos, lWeekday: Integer;
begin
  DecodeDate(aDate, y, mo, d);
  if (aPlan.Year.NextVal(y) <> y) or (aPlan.Month.NextVal(mo) <> mo) then
    Exit(False);
  lLast := DaysInAMonth(y, mo);
  lDow := DayOfTheWeek(aDate) mod 7;
  if (aDom = 'L') or (aDom = 'LW') then
  begin
    lTarget := lLast;
    if aDom = 'LW' then
      while DayOfTheWeek(EncodeDate(y, mo, lTarget)) in [6, 7] do
        Dec(lTarget);
    lDomMatch := d = lTarget;
  end else if (Length(aDom) > 1) and (aDom[Length(aDom)] = 'W') then
  begin
    lTarget := StrToInt(Copy(aDom, 1, Length(aDom) - 1));
    lDomMatch := False;
    if lTarget <= lLast then
    begin
      case DayOfTheWeek(EncodeDate(y, mo, lTarget)) of
        6: if lTarget = 1 then Inc(lTarget, 2) else Dec(lTarget);
        7: if lTarget = lLast then Dec(lTarget, 2) else Inc(lTarget);
      end;
      lDomMatch := d = lTarget;
    end;
  end else begin
    lDomMatch := aPlan.Day_of_the_Month.NextVal(d) = d;
  end;
  lPos := Pos('#', aDow);
  if (lPos > 0) or ((Length(aDow) > 1) and (aDow[Length(aDow)] = 'L')) then
  begin
    if lPos > 0 then
      lWeekday := StrToInt(Copy(aDow, 1, lPos - 1))
    else
      lWeekday := StrToInt(Copy(aDow, 1, Length(aDow) - 1));
    if aPlan.Dialect = cdQuartzSecondsFirst then
      Dec(lWeekday);
    if lPos > 0 then
      lDowMatch := (lDow = lWeekday) and ((d - 1) div 7 + 1 = StrToInt(Copy(aDow, lPos + 1, 1)))
    else
      lDowMatch := (lDow = lWeekday) and (d + 7 > lLast);
  end else begin
    lDowMatch := aPlan.Day_of_the_Week.NextVal(lDow) = lDow;
  end;
  if (aPlan.DayMatchMode <> dmOr) or aPlan.Day_of_the_Month.IsAny or aPlan.Day_of_the_Week.IsAny then
    Result := lDomMatch and lDowMatch
  else
    Result := lDomMatch or lDowMatch;
end;

function NextOracleFirst(const aPlan: TCronSchedulePlan; const aDom, aDow: string;
  const aBase, aEnd: TDateTime; out aNext: TDateTime): Boolean;
var
  lDay: TDateTime;
  lBound, lSerial: Int64;
  h, mi, s: Integer;
begin
  Result := False;
  aNext := 0;
  lBound := NextOracleSerial(aBase);
  lDay := DateTimeToTimeStamp(aBase).Date - DateDelta;
  // Brute force calendar days and allowed clock values; never call any search helper.
  while lDay < aEnd do
  begin
    if NextOracleDayMatches(aPlan, aDom, aDow, lDay) then
      for h := 0 to 23 do
        if aPlan.Hour.NextVal(h) = h then
          for mi := 0 to 59 do
            if aPlan.Minute.NextVal(mi) = mi then
              for s := 0 to 59 do
                if aPlan.Second.NextVal(s) = s then
                begin
                  lSerial := NextOracleSerial(lDay) + h * 3600 + mi * 60 + s;
                  if lSerial > lBound then
                  begin
                    aNext := lDay + EncodeTime(h, mi, s, 0);
                    Exit(True);
                  end;
                end;
    lDay := IncDay(lDay);
  end;
end;

procedure TTestCronFuzzOracle.CheckNextOracle(const aText, aDom, aDow: string;
  const aDialect: TmaxCronDialect; const aMode: TmaxCronDayMatchMode;
  const aSeed: string; const aBase: TDateTime; var aFailures: string; var aChecked: Integer);
var
  lPlan: TCronSchedulePlan;
  lNext, lExpected, lEnd: TDateTime;
  lFound, lExpectedFound: Boolean;
begin
  lPlan := TCronSchedulePlan.Create;
  try
    lPlan.Dialect := aDialect;
    lPlan.DayMatchMode := aMode;
    lPlan.HashSeed := aSeed;
    lPlan.Parse(aText);
    lEnd := IncDay(Trunc(aBase), 400);
    lExpectedFound := NextOracleFirst(lPlan, aDom, aDow, aBase, lEnd, lExpected);
    lFound := lPlan.FindNextScheduleDate(aBase, lNext);
    Inc(aChecked);
    if (lFound and (NextOracleSerial(lNext) <= NextOracleSerial(aBase))) or
      (lExpectedFound and ((not lFound) or (NextOracleSerial(lNext) <> NextOracleSerial(lExpected)))) or
      ((not lExpectedFound) and lFound and (lNext < lEnd)) then
      aFailures := aFailures + Format('case=%d dialect=%d mode=%d seed=%s plan="%s" base=%s found=%s next=%s expected=%s; ',
        [aChecked, Ord(aDialect), Ord(aMode), aSeed, aText, FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', aBase),
         BoolToStr(lFound, True), FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', lNext),
         FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', lExpected)]);
  finally
    lPlan.Free;
  end;
end;

function NextBoundaryBase(const aDay: TDateTime; const aKind: Integer): TDateTime;
var
  lBits: UInt64;
  i: Integer;
begin
  Result := aDay;
  case aKind of
    1..8:
      begin
        Move(Result, lBits, SizeOf(lBits));
        if aKind <= 4 then
          Dec(lBits, aKind)
        else
          Inc(lBits, aKind - 4);
        Move(lBits, Result, SizeOf(Result));
      end;
    9: Result := (aDay - 1) + EncodeTime(23, 59, 59, 999);
    10: Result := (aDay - 1) + (MSecsPerDay - 0.5) / MSecsPerDay;
    11: Result := (aDay - 1) + (MSecsPerDay - 0.499) / MSecsPerDay;
    12: Result := (aDay - 1) + (MSecsPerDay - 0.501) / MSecsPerDay;
    13: Result := (aDay - 1) + 23 * OneHour + 60 * OneMinute;
    14: Result := IncMilliSecond(IncMilliSecond(aDay, -2), 2);
    15: Result := IncSecond(IncSecond(aDay, -1), 1);
    16:
      begin
        Result := (aDay - 1) + EncodeTime(23, 59, 0, 0);
        for i := 1 to 60 do
          Result := Result + 1 / 86400;
      end;
    17: Result := (aDay - 1) + EncodeTime(23, 0, 0, 0) + EncodeTime(1, 0, 0, 0);
    18: Result := IncMilliSecond(IncSecond(aDay, -1), 999);
  end;
end;

procedure TTestCronFuzzOracle.NextDate_MonotonicAndFirstOccurrence;
const
  cRegressions: array[0..127] of TNextRegression = (
    (Text: '* 23-23 LW JAN,MAR MON-FRI'; Dialect: 0; Mode: 2; Seed: 0; H: 23; M: 59; S: 0),
    (Text: '* 23-23 LW JAN,MAR MON-FRI'; Dialect: 0; Mode: 2; Seed: 0; H: 23; M: 59; S: 0),
    (Text: '* 23-23 LW JAN,MAR MON-FRI'; Dialect: 0; Mode: 2; Seed: 1; H: 23; M: 59; S: 0),
    (Text: '* 23-23 LW JAN,MAR MON-FRI'; Dialect: 0; Mode: 2; Seed: 1; H: 23; M: 59; S: 0),
    (Text: '* 23-23 LW JAN,MAR MON-FRI'; Dialect: 1; Mode: 2; Seed: 0; H: 23; M: 59; S: 0),
    (Text: '* 23-23 LW JAN,MAR MON-FRI'; Dialect: 1; Mode: 2; Seed: 0; H: 23; M: 59; S: 0),
    (Text: '* 23-23 LW JAN,MAR MON-FRI'; Dialect: 1; Mode: 2; Seed: 1; H: 23; M: 59; S: 0),
    (Text: '* 23-23 LW JAN,MAR MON-FRI'; Dialect: 1; Mode: 2; Seed: 1; H: 23; M: 59; S: 0),
    (Text: '0,30 H/5 17-23/2 ? 1-12 * *'; Dialect: 2; Mode: 0; Seed: 1; H: 23; M: 59; S: 30),
    (Text: '0,30 H/5 17-23/2 ? 1-12 * *'; Dialect: 2; Mode: 0; Seed: 1; H: 23; M: 59; S: 30),
    (Text: '0,30 H/5 17-23/2 ? 1-12 * *'; Dialect: 2; Mode: 1; Seed: 1; H: 23; M: 59; S: 30),
    (Text: '0,30 H/5 17-23/2 ? 1-12 * *'; Dialect: 2; Mode: 1; Seed: 1; H: 23; M: 59; S: 30),
    (Text: '0,30 H/5 17-23/2 ? 1-12 * *'; Dialect: 2; Mode: 2; Seed: 1; H: 23; M: 59; S: 30),
    (Text: '0,30 H/5 17-23/2 ? 1-12 * *'; Dialect: 2; Mode: 2; Seed: 1; H: 23; M: 59; S: 30),
    (Text: 'H/5 * * JAN,MAR MON-FRI * 0 0'; Dialect: 1; Mode: 0; Seed: 1; H: 23; M: 59; S: 0),
    (Text: 'H/5 * * JAN,MAR MON-FRI * 0 0'; Dialect: 1; Mode: 0; Seed: 1; H: 23; M: 59; S: 0),
    (Text: 'H/5 * * JAN,MAR MON-FRI * 0 0'; Dialect: 1; Mode: 1; Seed: 1; H: 23; M: 59; S: 0),
    (Text: 'H/5 * * JAN,MAR MON-FRI * 0 0'; Dialect: 1; Mode: 1; Seed: 1; H: 23; M: 59; S: 0),
    (Text: 'H/5 * * JAN,MAR MON-FRI * 0 0'; Dialect: 1; Mode: 2; Seed: 1; H: 23; M: 59; S: 0),
    (Text: 'H/5 * * JAN,MAR MON-FRI * 0 0'; Dialect: 1; Mode: 2; Seed: 1; H: 23; M: 59; S: 0),
    (Text: 'H/5 * 1-28/3 1-12 0,2,4'; Dialect: 0; Mode: 2; Seed: 1; H: 23; M: 59; S: 0),
    (Text: 'H/5 * 1-28/3 1-12 0,2,4'; Dialect: 0; Mode: 2; Seed: 1; H: 23; M: 59; S: 0),
    (Text: 'H/5 * 1-28/3 1-12 0,2,4'; Dialect: 1; Mode: 2; Seed: 1; H: 23; M: 59; S: 0),
    (Text: 'H/5 * 1-28/3 1-12 0,2,4'; Dialect: 1; Mode: 2; Seed: 1; H: 23; M: 59; S: 0),
    (Text: 'H/5 13-23/2 * * *'; Dialect: 0; Mode: 0; Seed: 1; H: 23; M: 59; S: 0),
    (Text: 'H/5 13-23/2 * * *'; Dialect: 0; Mode: 0; Seed: 1; H: 23; M: 59; S: 0),
    (Text: 'H/5 13-23/2 * * *'; Dialect: 0; Mode: 1; Seed: 1; H: 23; M: 59; S: 0),
    (Text: 'H/5 13-23/2 * * *'; Dialect: 0; Mode: 1; Seed: 1; H: 23; M: 59; S: 0),
    (Text: 'H/5 13-23/2 * * *'; Dialect: 0; Mode: 2; Seed: 1; H: 23; M: 59; S: 0),
    (Text: 'H/5 13-23/2 * * *'; Dialect: 0; Mode: 2; Seed: 1; H: 23; M: 59; S: 0),
    (Text: 'H/5 13-23/2 * * *'; Dialect: 1; Mode: 0; Seed: 1; H: 23; M: 59; S: 0),
    (Text: 'H/5 13-23/2 * * *'; Dialect: 1; Mode: 0; Seed: 1; H: 23; M: 59; S: 0),
    (Text: 'H/5 13-23/2 * * *'; Dialect: 1; Mode: 1; Seed: 1; H: 23; M: 59; S: 0),
    (Text: 'H/5 13-23/2 * * *'; Dialect: 1; Mode: 1; Seed: 1; H: 23; M: 59; S: 0),
    (Text: 'H/5 13-23/2 * * *'; Dialect: 1; Mode: 2; Seed: 1; H: 23; M: 59; S: 0),
    (Text: 'H/5 13-23/2 * * *'; Dialect: 1; Mode: 2; Seed: 1; H: 23; M: 59; S: 0),
    (Text: 'H/5 * L */2 MON-FRI * 0 4294967295'; Dialect: 1; Mode: 2; Seed: 1; H: 23; M: 59; S: 0),
    (Text: 'H/5 * L */2 MON-FRI * 0 4294967295'; Dialect: 1; Mode: 2; Seed: 1; H: 23; M: 59; S: 0),
    (Text: '25,59 * * JAN,MAR * * 0 0'; Dialect: 1; Mode: 0; Seed: 0; H: 23; M: 59; S: 0),
    (Text: '25,59 * * JAN,MAR * * 0 0'; Dialect: 1; Mode: 0; Seed: 0; H: 23; M: 59; S: 0),
    (Text: '25,59 * * JAN,MAR * * 0 0'; Dialect: 1; Mode: 0; Seed: 1; H: 23; M: 59; S: 0),
    (Text: '25,59 * * JAN,MAR * * 0 0'; Dialect: 1; Mode: 0; Seed: 1; H: 23; M: 59; S: 0),
    (Text: '25,59 * * JAN,MAR * * 0 0'; Dialect: 1; Mode: 1; Seed: 0; H: 23; M: 59; S: 0),
    (Text: '25,59 * * JAN,MAR * * 0 0'; Dialect: 1; Mode: 1; Seed: 0; H: 23; M: 59; S: 0),
    (Text: '25,59 * * JAN,MAR * * 0 0'; Dialect: 1; Mode: 1; Seed: 1; H: 23; M: 59; S: 0),
    (Text: '25,59 * * JAN,MAR * * 0 0'; Dialect: 1; Mode: 1; Seed: 1; H: 23; M: 59; S: 0),
    (Text: '25,59 * * JAN,MAR * * 0 0'; Dialect: 1; Mode: 2; Seed: 0; H: 23; M: 59; S: 0),
    (Text: '25,59 * * JAN,MAR * * 0 0'; Dialect: 1; Mode: 2; Seed: 0; H: 23; M: 59; S: 0),
    (Text: '25,59 * * JAN,MAR * * 0 0'; Dialect: 1; Mode: 2; Seed: 1; H: 23; M: 59; S: 0),
    (Text: '25,59 * * JAN,MAR * * 0 0'; Dialect: 1; Mode: 2; Seed: 1; H: 23; M: 59; S: 0),
    (Text: '* 1,23 1-28/3 * 0,2,4'; Dialect: 0; Mode: 2; Seed: 0; H: 23; M: 59; S: 0),
    (Text: '* 1,23 1-28/3 * 0,2,4'; Dialect: 0; Mode: 2; Seed: 0; H: 23; M: 59; S: 0),
    (Text: '* 1,23 1-28/3 * 0,2,4'; Dialect: 0; Mode: 2; Seed: 1; H: 23; M: 59; S: 0),
    (Text: '* 1,23 1-28/3 * 0,2,4'; Dialect: 0; Mode: 2; Seed: 1; H: 23; M: 59; S: 0),
    (Text: '* 1,23 1-28/3 * 0,2,4'; Dialect: 1; Mode: 2; Seed: 0; H: 23; M: 59; S: 0),
    (Text: '* 1,23 1-28/3 * 0,2,4'; Dialect: 1; Mode: 2; Seed: 0; H: 23; M: 59; S: 0),
    (Text: '* 1,23 1-28/3 * 0,2,4'; Dialect: 1; Mode: 2; Seed: 1; H: 23; M: 59; S: 0),
    (Text: '* 1,23 1-28/3 * 0,2,4'; Dialect: 1; Mode: 2; Seed: 1; H: 23; M: 59; S: 0),
    (Text: '40,59 17-23/2 L * MON-FRI'; Dialect: 0; Mode: 2; Seed: 0; H: 23; M: 59; S: 0),
    (Text: '40,59 17-23/2 L * MON-FRI'; Dialect: 0; Mode: 2; Seed: 0; H: 23; M: 59; S: 0),
    (Text: '40,59 17-23/2 L * MON-FRI'; Dialect: 0; Mode: 2; Seed: 1; H: 23; M: 59; S: 0),
    (Text: '40,59 17-23/2 L * MON-FRI'; Dialect: 0; Mode: 2; Seed: 1; H: 23; M: 59; S: 0),
    (Text: '40,59 17-23/2 L * MON-FRI'; Dialect: 1; Mode: 2; Seed: 0; H: 23; M: 59; S: 0),
    (Text: '40,59 17-23/2 L * MON-FRI'; Dialect: 1; Mode: 2; Seed: 0; H: 23; M: 59; S: 0),
    (Text: '40,59 17-23/2 L * MON-FRI'; Dialect: 1; Mode: 2; Seed: 1; H: 23; M: 59; S: 0),
    (Text: '40,59 17-23/2 L * MON-FRI'; Dialect: 1; Mode: 2; Seed: 1; H: 23; M: 59; S: 0),
    (Text: 'H/5 * * 1-12 MON-FRI'; Dialect: 0; Mode: 0; Seed: 1; H: 23; M: 59; S: 0),
    (Text: 'H/5 * * 1-12 MON-FRI'; Dialect: 0; Mode: 0; Seed: 1; H: 23; M: 59; S: 0),
    (Text: 'H/5 * * 1-12 MON-FRI'; Dialect: 0; Mode: 1; Seed: 1; H: 23; M: 59; S: 0),
    (Text: 'H/5 * * 1-12 MON-FRI'; Dialect: 0; Mode: 1; Seed: 1; H: 23; M: 59; S: 0),
    (Text: 'H/5 * * 1-12 MON-FRI'; Dialect: 0; Mode: 2; Seed: 1; H: 23; M: 59; S: 0),
    (Text: 'H/5 * * 1-12 MON-FRI'; Dialect: 0; Mode: 2; Seed: 1; H: 23; M: 59; S: 0),
    (Text: 'H/5 * * 1-12 MON-FRI'; Dialect: 1; Mode: 0; Seed: 1; H: 23; M: 59; S: 0),
    (Text: 'H/5 * * 1-12 MON-FRI'; Dialect: 1; Mode: 0; Seed: 1; H: 23; M: 59; S: 0),
    (Text: 'H/5 * * 1-12 MON-FRI'; Dialect: 1; Mode: 1; Seed: 1; H: 23; M: 59; S: 0),
    (Text: 'H/5 * * 1-12 MON-FRI'; Dialect: 1; Mode: 1; Seed: 1; H: 23; M: 59; S: 0),
    (Text: 'H/5 * * 1-12 MON-FRI'; Dialect: 1; Mode: 2; Seed: 1; H: 23; M: 59; S: 0),
    (Text: 'H/5 * * 1-12 MON-FRI'; Dialect: 1; Mode: 2; Seed: 1; H: 23; M: 59; S: 0),
    (Text: 'H/5 * ? */2 ?'; Dialect: 0; Mode: 0; Seed: 1; H: 23; M: 59; S: 0),
    (Text: 'H/5 * ? */2 ?'; Dialect: 0; Mode: 0; Seed: 1; H: 23; M: 59; S: 0),
    (Text: 'H/5 * ? */2 ?'; Dialect: 0; Mode: 1; Seed: 1; H: 23; M: 59; S: 0),
    (Text: 'H/5 * ? */2 ?'; Dialect: 0; Mode: 1; Seed: 1; H: 23; M: 59; S: 0),
    (Text: 'H/5 * ? */2 ?'; Dialect: 0; Mode: 2; Seed: 1; H: 23; M: 59; S: 0),
    (Text: 'H/5 * ? */2 ?'; Dialect: 0; Mode: 2; Seed: 1; H: 23; M: 59; S: 0),
    (Text: 'H/5 * ? */2 ?'; Dialect: 1; Mode: 0; Seed: 1; H: 23; M: 59; S: 0),
    (Text: 'H/5 * ? */2 ?'; Dialect: 1; Mode: 0; Seed: 1; H: 23; M: 59; S: 0),
    (Text: 'H/5 * ? */2 ?'; Dialect: 1; Mode: 1; Seed: 1; H: 23; M: 59; S: 0),
    (Text: 'H/5 * ? */2 ?'; Dialect: 1; Mode: 1; Seed: 1; H: 23; M: 59; S: 0),
    (Text: 'H/5 * ? */2 ?'; Dialect: 1; Mode: 2; Seed: 1; H: 23; M: 59; S: 0),
    (Text: 'H/5 * ? */2 ?'; Dialect: 1; Mode: 2; Seed: 1; H: 23; M: 59; S: 0),
    (Text: 'H/5 * 1,15 1-12 MON-FRI'; Dialect: 0; Mode: 2; Seed: 1; H: 23; M: 59; S: 0),
    (Text: 'H/5 * 1,15 1-12 MON-FRI'; Dialect: 0; Mode: 2; Seed: 1; H: 23; M: 59; S: 0),
    (Text: 'H/5 * 1,15 1-12 MON-FRI'; Dialect: 1; Mode: 2; Seed: 1; H: 23; M: 59; S: 0),
    (Text: 'H/5 * 1,15 1-12 MON-FRI'; Dialect: 1; Mode: 2; Seed: 1; H: 23; M: 59; S: 0),
    (Text: '* 6,23 15W 1-12 MON-FRI'; Dialect: 0; Mode: 2; Seed: 0; H: 23; M: 59; S: 0),
    (Text: '* 6,23 15W 1-12 MON-FRI'; Dialect: 0; Mode: 2; Seed: 0; H: 23; M: 59; S: 0),
    (Text: '* 6,23 15W 1-12 MON-FRI'; Dialect: 0; Mode: 2; Seed: 1; H: 23; M: 59; S: 0),
    (Text: '* 6,23 15W 1-12 MON-FRI'; Dialect: 0; Mode: 2; Seed: 1; H: 23; M: 59; S: 0),
    (Text: '* 6,23 15W 1-12 MON-FRI'; Dialect: 1; Mode: 2; Seed: 0; H: 23; M: 59; S: 0),
    (Text: '* 6,23 15W 1-12 MON-FRI'; Dialect: 1; Mode: 2; Seed: 0; H: 23; M: 59; S: 0),
    (Text: '* 6,23 15W 1-12 MON-FRI'; Dialect: 1; Mode: 2; Seed: 1; H: 23; M: 59; S: 0),
    (Text: '* 6,23 15W 1-12 MON-FRI'; Dialect: 1; Mode: 2; Seed: 1; H: 23; M: 59; S: 0),
    (Text: '0,30 H/5 * LW */2 MON-FRI *'; Dialect: 2; Mode: 2; Seed: 1; H: 23; M: 59; S: 30),
    (Text: '0,30 H/5 * LW */2 MON-FRI *'; Dialect: 2; Mode: 2; Seed: 1; H: 23; M: 59; S: 30),
    (Text: '0,30 * 23,23 * */2 * *'; Dialect: 2; Mode: 0; Seed: 0; H: 23; M: 59; S: 30),
    (Text: '0,30 * 23,23 * */2 * *'; Dialect: 2; Mode: 0; Seed: 0; H: 23; M: 59; S: 30),
    (Text: '0,30 * 23,23 * */2 * *'; Dialect: 2; Mode: 0; Seed: 1; H: 23; M: 59; S: 30),
    (Text: '0,30 * 23,23 * */2 * *'; Dialect: 2; Mode: 0; Seed: 1; H: 23; M: 59; S: 30),
    (Text: '0,30 * 23,23 * */2 * *'; Dialect: 2; Mode: 1; Seed: 0; H: 23; M: 59; S: 30),
    (Text: '0,30 * 23,23 * */2 * *'; Dialect: 2; Mode: 1; Seed: 0; H: 23; M: 59; S: 30),
    (Text: '0,30 * 23,23 * */2 * *'; Dialect: 2; Mode: 1; Seed: 1; H: 23; M: 59; S: 30),
    (Text: '0,30 * 23,23 * */2 * *'; Dialect: 2; Mode: 1; Seed: 1; H: 23; M: 59; S: 30),
    (Text: '0,30 * 23,23 * */2 * *'; Dialect: 2; Mode: 2; Seed: 0; H: 23; M: 59; S: 30),
    (Text: '0,30 * 23,23 * */2 * *'; Dialect: 2; Mode: 2; Seed: 0; H: 23; M: 59; S: 30),
    (Text: '0,30 * 23,23 * */2 * *'; Dialect: 2; Mode: 2; Seed: 1; H: 23; M: 59; S: 30),
    (Text: '0,30 * 23,23 * */2 * *'; Dialect: 2; Mode: 2; Seed: 1; H: 23; M: 59; S: 30),
    (Text: '* 21,23 * */2 ? * */15 0'; Dialect: 1; Mode: 0; Seed: 0; H: 23; M: 59; S: 45),
    (Text: '* 21,23 * */2 ? * */15 0'; Dialect: 1; Mode: 0; Seed: 0; H: 23; M: 59; S: 45),
    (Text: '* 21,23 * */2 ? * */15 0'; Dialect: 1; Mode: 0; Seed: 1; H: 23; M: 59; S: 45),
    (Text: '* 21,23 * */2 ? * */15 0'; Dialect: 1; Mode: 0; Seed: 1; H: 23; M: 59; S: 45),
    (Text: '* 21,23 * */2 ? * */15 0'; Dialect: 1; Mode: 1; Seed: 0; H: 23; M: 59; S: 45),
    (Text: '* 21,23 * */2 ? * */15 0'; Dialect: 1; Mode: 1; Seed: 0; H: 23; M: 59; S: 45),
    (Text: '* 21,23 * */2 ? * */15 0'; Dialect: 1; Mode: 1; Seed: 1; H: 23; M: 59; S: 45),
    (Text: '* 21,23 * */2 ? * */15 0'; Dialect: 1; Mode: 1; Seed: 1; H: 23; M: 59; S: 45),
    (Text: '* 21,23 * */2 ? * */15 0'; Dialect: 1; Mode: 2; Seed: 0; H: 23; M: 59; S: 45),
    (Text: '* 21,23 * */2 ? * */15 0'; Dialect: 1; Mode: 2; Seed: 0; H: 23; M: 59; S: 45),
    (Text: '* 21,23 * */2 ? * */15 0'; Dialect: 1; Mode: 2; Seed: 1; H: 23; M: 59; S: 45),
    (Text: '* 21,23 * */2 ? * */15 0'; Dialect: 1; Mode: 2; Seed: 1; H: 23; M: 59; S: 45));
  cDom: array[0..5] of string = ('L', 'LW', '15W', '1', '31W', '*');
var
  lDialect: TmaxCronDialect;
  lMode: TmaxCronDayMatchMode;
  lTokens: TArray<string>;
  lFailures, lDom, lDow, lText, lYear, lMonth, lSeed: string;
  lBase, lBoundary: TDateTime;
  lChecked, lSavedSeed, i, j, k, lOffset, lShape: Integer;
begin
  lChecked := 0;
  lFailures := '';
  // Keep all 128 D2 stops, including both seeds and both window walks.
  for i := 0 to High(cRegressions) do
  begin
    lTokens := cRegressions[i].Text.Split([' ']);
    lOffset := Ord(cRegressions[i].Dialect = Ord(cdQuartzSecondsFirst));
    lSeed := '';
    if cRegressions[i].Seed = 1 then lSeed := 'job-a';
    CheckNextOracle(cRegressions[i].Text, lTokens[2 + lOffset], lTokens[4 + lOffset],
      TmaxCronDialect(cRegressions[i].Dialect), TmaxCronDayMatchMode(cRegressions[i].Mode), lSeed,
      EncodeDateTime(1900, 1, 1, cRegressions[i].H, cRegressions[i].M, cRegressions[i].S, 0),
      lFailures, lChecked);
  end;
  lSavedSeed := RandSeed;
  try
    RandSeed := 137031;
    for lDialect := Low(TmaxCronDialect) to High(TmaxCronDialect) do
      for lMode := Low(TmaxCronDayMatchMode) to High(TmaxCronDayMatchMode) do
        for j := 0 to 3 do
          for k := 0 to High(cDom) do
          begin
            case j of
              0: lBase := EncodeDate(1900, 1, 1);
              1: lBase := EncodeDate(1900, 1, 31);
              2: lBase := EncodeDate(2027, 12, 31);
            else
              lBase := EncodeDate(2028, 2, 28);
            end;
            lBase := lBase + EncodeTime(23, 59, Random(2) * 30, Random(2) * 500);
            lYear := IntToStr(YearOf(lBase));
            lMonth := '*';
            lDom := cDom[k];
            lDow := '1';
            if lDialect = cdQuartzSecondsFirst then lDow := '2';
            if k = 3 then
            begin
              lMonth := '2';
              lDow := lDow + '#5';
            end else if k = 4 then
              lDow := lDow + 'L';
            case lDialect of
              cdStandard: lText := '*/5 13-23/2 ' + lDom + ' ' + lMonth + ' ' + lDow;
              cdQuartzSecondsFirst: lText := '0,30 */5 13-23/2 ' + lDom + ' ' + lMonth + ' ' + lDow + ' ' + lYear;
            else
              lText := '*/5 13-23/2 ' + lDom + ' ' + lMonth + ' ' + lDow + ' ' + lYear + ' 0,30';
            end;
            CheckNextOracle(lText, lDom, lDow, lDialect, lMode, '', lBase, lFailures, lChecked);
          end;
  finally
    RandSeed := lSavedSeed;
  end;
  Assert.AreEqual(344, lChecked, '128 deterministic D2 stops plus 216 fixed-seed generated cases');
  // Every boundary shape is crossed with all dialects, day modes and three clocks.
  // Scan every midnight around floor, month/year and leap transitions, not just canonical bases.
  for lDialect := Low(TmaxCronDialect) to High(TmaxCronDialect) do
    for lMode := Low(TmaxCronDayMatchMode) to High(TmaxCronDayMatchMode) do
      for j := 0 to 7 do
      begin
        case j of
          0: lBoundary := EncodeDate(1900, 1, 1);
          1: lBoundary := EncodeDate(1900, 1, 31);
          2: lBoundary := EncodeDate(1900, 12, 31);
          3: lBoundary := EncodeDate(2026, 1, 31);
          4: lBoundary := EncodeDate(2026, 12, 31);
          5: lBoundary := EncodeDate(2028, 2, 28);
          6: lBoundary := EncodeDate(2000, 2, 28);
        else
          lBoundary := EncodeDate(2100, 2, 28);
        end;
        for i := 0 to 2 do
          for k := 0 to 18 do
          begin
            lBase := NextBoundaryBase(lBoundary + i, k);
            for lShape := 0 to 2 do
            begin
              case lShape of
                0: lText := '0 23 * * *'; // Reviewer's carried-midnight case.
                1: lText := '0 0 * * *';
              else
                lText := '59 23 * * *';
              end;
              if lDialect = cdQuartzSecondsFirst then
                lText := '0 ' + lText;
              CheckNextOracle(lText, '*', '*', lDialect, lMode, '', lBase, lFailures, lChecked);
            end;
          end;
      end;
  Assert.AreEqual(12656, lChecked, '344 original plus 12312 adversarial midnight cases');
  Assert.AreEqual('', lFailures, 'Next must advance and equal the independent first occurrence: ' + lFailures);
end;

end.

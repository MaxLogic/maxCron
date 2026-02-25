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
  public
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

end.

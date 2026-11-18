unit TestCronParsing;
{$I maxCron.inc}

interface

uses
  {$IFDEF FPC}
  SysUtils,
  DUnitX.TestFramework,
  maxCron
  {$ELSE}
  System.SysUtils,
  DUnitX.TestFramework,
  maxCron
  {$ENDIF};

type
  [TestFixture]
  TTestCronParsing = class
  private
    procedure AssertParses(const aExpr: string);
    procedure AssertRaisesOnParse(const aExpr: string);
    procedure AssertParsesDialect(const aExpr: string; const aDialect: TmaxCronDialect);
    procedure AssertRaisesOnParseDialect(const aExpr: string; const aDialect: TmaxCronDialect);
    procedure AssertDescription(const aExpr, aExpected: string);
  public
    [Test]
    procedure Parse_AbridgedDefaults_SecondsAndLimit;

    [Test]
    procedure Parse_WithMonthAndDayNames;

    [Test]
    procedure Parse_InvalidTokens_Raise;

    [Test]
    procedure Parse_FieldCounts_5To8;

    [Test]
    procedure Parse_MixedTokenForms;

    [Test]
    procedure Parse_ExecutionLimit_Range;

    [Test]
    procedure Parse_Macros;

    [Test]
    procedure Parse_CommentsAndWhitespace;

    [Test]
    procedure Parse_QuartzModifiers;

    [Test]
    procedure Parse_RebootMacro_SetsExecutionLimit;

    [Test]
    procedure Parse_RebootMacro_DialectRestrictions;

    [Test]
    procedure Parse_Macros_QuartzSecondsFirst;

    [Test]
    procedure Parse_Dialect_Standard_Exact5;

    [Test]
    procedure Parse_Dialect_QuartzSecondsFirst_FieldOrder;

    [Test]
    procedure Parse_QuartzSecondsFirst_HashDowRange_OneBased;

    [Test]
    procedure Describe_BasicPatterns;

    [Test]
    procedure Plan_Text_RespectsDialect;
    [Test] procedure Parse_WrappedRanges_Expansion;
    [Test] procedure Parse_InvalidIntegerGrammar_UsesParseException;
    [Test] procedure Parse_MonthEndOffsetLists_ErrorPrecedence;
    [Test] procedure Parse_MonthEndOffsets_LaterFieldDiagnostics;
    [Test] procedure Parse_MonthEndOffsets;
    [Test] procedure Describe_SyntaxAdditions;
  end;

implementation

procedure TTestCronParsing.AssertParses(const aExpr: string);
begin
  AssertParsesDialect(aExpr, cdMaxCron);
end;

procedure TTestCronParsing.AssertParsesDialect(const aExpr: string; const aDialect: TmaxCronDialect);
var
  Plan: TCronSchedulePlan;
begin
  Plan := TCronSchedulePlan.Create;
  try
    Plan.Dialect := aDialect;
    Plan.Parse(aExpr);
  finally
    Plan.Free;
  end;
end;

procedure TTestCronParsing.AssertRaisesOnParse(const aExpr: string);
begin
  AssertRaisesOnParseDialect(aExpr, cdMaxCron);
end;

procedure TTestCronParsing.AssertRaisesOnParseDialect(const aExpr: string; const aDialect: TmaxCronDialect);
begin
  try
    AssertParsesDialect(aExpr, aDialect);
    Assert.Fail('Expected parse error: ' + aExpr);
  except
    on Exception do
      ; // expected
  end;
end;

procedure TTestCronParsing.AssertDescription(const aExpr, aExpected: string);
var
  Plan: TCronSchedulePlan;
  Desc: string;
begin
  Plan := TCronSchedulePlan.Create;
  try
    Plan.Parse(aExpr);
    Desc := Plan.Describe;
    Assert.AreEqual(aExpected, Desc);
  finally
    Plan.Free;
  end;
end;

procedure TTestCronParsing.Parse_AbridgedDefaults_SecondsAndLimit;
begin
  // 6 fields -> second defaults to 0, execution limit defaults to 0
  AssertParses('0 0 1 * * *');
  AssertParses('* * * * * *');
end;

procedure TTestCronParsing.Parse_WithMonthAndDayNames;
begin
  AssertParses('59 23 31 DEC Fri * 0 0');
  AssertParses('0 0 * * Mon-Fri * 0 0');
end;

procedure TTestCronParsing.Parse_InvalidTokens_Raise;
begin
  AssertRaisesOnParse('x * * * * *');
  AssertRaisesOnParse('0 0 0 * * *'); // invalid day-of-month
  AssertRaisesOnParse('1,2, * * * * *'); // empty token (trailing comma)
  AssertRaisesOnParse('0 0 * * * * -1 0'); // invalid seconds
  AssertRaisesOnParse('0 0 1 * * * * * *'); // too many fields
  AssertRaisesOnParse('@nope');
  AssertRaisesOnParse('0 0 L,15 * *'); // mixed list with modifier
  AssertRaisesOnParse('0 0 * * 5#0'); // invalid nth
  AssertRaisesOnParse('0 0 * * L'); // missing day-of-week value for L
end;

procedure TTestCronParsing.Parse_FieldCounts_5To8;
begin
  AssertParses('* * * * *');
  AssertParses('* * * * * *');
  AssertParses('* * * * * * *');
  AssertParses('* * * * * * * 5');
  AssertRaisesOnParse('0 0 1 *');
end;

procedure TTestCronParsing.Parse_MixedTokenForms;
begin
  AssertParses('1,2-5/2,*/3 * * * *');
  AssertParses('0-10/2 1,5,10 * * *');
  AssertRaisesOnParse('1,2-5//2 * * * *');
  AssertRaisesOnParse('1-5/0 * * * *');
end;

procedure TTestCronParsing.Parse_ExecutionLimit_Range;
const
  cMaxExecutionLimit = Int64(High(LongWord));
var
  Plan: TCronSchedulePlan;
begin
  Plan := TCronSchedulePlan.Create;
  try
    Plan.Parse('0 0 * * * * 0 0');
    Assert.AreEqual(0, Integer(Plan.ExecutionLimit));
    Plan.Parse('0 0 * * * * 0 1');
    Assert.AreEqual(1, Integer(Plan.ExecutionLimit));
    Plan.Parse('0 0 * * * * 0 ' + IntToStr(Int64(MaxInt) + 1));
    Assert.AreEqual(LongWord(Int64(MaxInt) + 1), Plan.ExecutionLimit);
    Plan.Parse('0 0 * * * * 0 ' + IntToStr(cMaxExecutionLimit));
    Assert.AreEqual(High(LongWord), Plan.ExecutionLimit);
  finally
    Plan.Free;
  end;

  AssertRaisesOnParse('0 0 * * * * 0 -1');
  AssertRaisesOnParse('0 0 * * * * 0 ' + IntToStr(cMaxExecutionLimit + 1));
end;

procedure TTestCronParsing.Parse_Macros;
begin
  AssertParses('@yearly');
  AssertParses('@annually');
  AssertParses('@monthly');
  AssertParses('@weekly');
  AssertParses('@daily');
  AssertParses('@midnight');
  AssertParses('@hourly');
  AssertParses('@reboot');
end;

procedure TTestCronParsing.Parse_CommentsAndWhitespace;
begin
  AssertParses('0 0 * * * # trailing comment');
  AssertParses(#9 + '0' + #9 + '0' + #9 + '* * *');
  AssertParses('0 0 1, 2,3 * *');
end;

procedure TTestCronParsing.Parse_QuartzModifiers;
begin
  AssertParses('0 0 L * *');
  AssertParses('0 0 LW * *');
  AssertParses('0 0 15W * *');
  AssertParses('0 0 * * 5L');
  AssertParses('0 0 * * 2#3');
  AssertParses('0 0 10 7 ?');
  AssertParses('0 0 ? 7 2#3');
end;

procedure TTestCronParsing.Parse_RebootMacro_SetsExecutionLimit;
var
  Plan: TCronSchedulePlan;
begin
  Plan := TCronSchedulePlan.Create;
  try
    Plan.Parse('@reboot');
    Assert.AreEqual(1, Integer(Plan.ExecutionLimit));
  finally
    Plan.Free;
  end;
end;

procedure TTestCronParsing.Parse_RebootMacro_DialectRestrictions;
begin
  AssertRaisesOnParseDialect('@reboot', cdStandard);
  AssertRaisesOnParseDialect('@reboot', cdQuartzSecondsFirst);
end;

procedure TTestCronParsing.Parse_Macros_QuartzSecondsFirst;
begin
  AssertParsesDialect('@yearly', cdQuartzSecondsFirst);
  AssertParsesDialect('@monthly', cdQuartzSecondsFirst);
  AssertParsesDialect('@weekly', cdQuartzSecondsFirst);
  AssertParsesDialect('@daily', cdQuartzSecondsFirst);
  AssertParsesDialect('@hourly', cdQuartzSecondsFirst);
end;

procedure TTestCronParsing.Parse_Dialect_Standard_Exact5;
var
  Plan: TCronSchedulePlan;
begin
  Plan := TCronSchedulePlan.Create;
  try
    Plan.Dialect := cdStandard;
    Plan.Parse('0 0 * * *');
    Assert.AreEqual('0', Plan.Second.Data);
    Assert.IsTrue(Plan.Year.Fullrange);
    Assert.AreEqual(0, Integer(Plan.ExecutionLimit));
    AssertRaisesOnParseDialect('0 0 * * * *', cdStandard);
  finally
    Plan.Free;
  end;
end;

procedure TTestCronParsing.Parse_Dialect_QuartzSecondsFirst_FieldOrder;
var
  Plan: TCronSchedulePlan;
begin
  Plan := TCronSchedulePlan.Create;
  try
    Plan.Dialect := cdQuartzSecondsFirst;
    Plan.Parse('5 10 11 12 1 2 2025');
    Assert.AreEqual('5', Plan.Second.Data);
    Assert.AreEqual('10', Plan.Minute.Data);
    Assert.AreEqual('11', Plan.Hour.Data);
    Assert.AreEqual('12', Plan.Day_of_the_Month.Data);
    Assert.AreEqual('1', Plan.Month.Data);
    Assert.AreEqual('2', Plan.Day_of_the_Week.Data);
    Assert.AreEqual('2025', Plan.Year.Data);

    Plan.Parse('5 10 11 12 1 2');
    Assert.IsTrue(Plan.Year.Fullrange);
    AssertRaisesOnParseDialect('0 0 0 ? * 0', cdQuartzSecondsFirst);
    AssertRaisesOnParseDialect('0 0 * * *', cdQuartzSecondsFirst);
    AssertRaisesOnParseDialect('0 0 1 2 3 4 5 6', cdQuartzSecondsFirst);
  finally
    Plan.Free;
  end;
end;

procedure TTestCronParsing.Parse_QuartzSecondsFirst_HashDowRange_OneBased;
begin
  AssertParsesDialect('0 0 12 ? * H(1-7)', cdQuartzSecondsFirst);
  AssertParsesDialect('0 0 12 ? * H(1-7)/2', cdQuartzSecondsFirst);
end;

procedure TTestCronParsing.Describe_BasicPatterns;
begin
  AssertDescription('* * * * * *', 'Every minute');
  AssertDescription('*/5 * * * * * 0 0', 'Every 5 minutes');
  AssertDescription('0 0 * * * * 0 0', 'Every day at 00:00');
  AssertDescription('30 9 * * 1 * 0 0', 'Every week on Mon at 09:30');
  AssertDescription('0 10 15 * * * 0 0', 'Every month on day 15 at 10:00');
  AssertDescription('0 10 1 1 * * 0 0', 'Every year on Jan 1 at 10:00');
end;

procedure TTestCronParsing.Plan_Text_RespectsDialect;
var
  lPlan: TPlan;
begin
  lPlan.reset;
  lPlan.Dialect := cdStandard;
  lPlan.Minute := '5';
  lPlan.Hour := '6';
  lPlan.DayOfTheMonth := '7';
  lPlan.Month := '8';
  lPlan.DayOfTheWeek := '2';
  lPlan.Year := '2025';
  lPlan.Second := '30';
  lPlan.ExecutionLimit := '9';
  Assert.AreEqual('5 6 7 8 2', lPlan.Text);

  lPlan.reset;
  lPlan.Dialect := cdQuartzSecondsFirst;
  lPlan.Second := '1';
  lPlan.Minute := '2';
  lPlan.Hour := '3';
  lPlan.DayOfTheMonth := '4';
  lPlan.Month := '5';
  lPlan.DayOfTheWeek := '6';
  lPlan.Year := '*';
  Assert.AreEqual('1 2 3 4 5 6', lPlan.Text);
  lPlan.Year := '2026';
  Assert.AreEqual('1 2 3 4 5 6 2026', lPlan.Text);

  lPlan.reset;
  lPlan.Dialect := cdMaxCron;
  lPlan.Minute := '10';
  lPlan.Hour := '11';
  lPlan.DayOfTheMonth := '12';
  lPlan.Month := '1';
  lPlan.DayOfTheWeek := '2';
  lPlan.Year := '2027';
  lPlan.Second := '7';
  lPlan.ExecutionLimit := '3';
  Assert.AreEqual('10 11 12 1 2 2027 7 3', lPlan.Text);
end;


procedure TTestCronParsing.Parse_MonthEndOffsets;
const
  cForms: array[0..10] of string = ('L-0', 'L-2', 'L-30', 'LW-0', 'LW-2', 'lw-19',
    'L-0W', 'L-3W', 'l-30w', 'L-05', 'LW-30');
  cInvalid: array[0..15] of string = ('L-', 'L-W', 'L-x', 'L--1', 'L-+1', 'L-$1',
    'L-2/2', 'L-2,15', 'LW-2W', 'L-2L', '1-5W', '15W-2', '15,L-2', 'L-2,L-3', 'L-1-2', 'LW-');
  cOutOfRange: array[0..3] of string = ('L-31', 'LW-31', 'L-31W', 'L-99999999999');
var
  lDialect: TmaxCronDialect;
  lToken, lText: string;
  lPlan: TCronSchedulePlan;
  lDate: TDateTime;

  procedure CheckError(const aToken, aMessage: string);
  var
    lRaised: Boolean;
  begin
    lRaised := False;
    try
      AssertParses('0 0 ' + aToken + ' * *');
    except
      on E: Exception do
      begin
        lRaised := True;
        Assert.AreEqual('Exception', E.ClassName, aToken);
        Assert.AreEqual(aMessage, E.Message, aToken);
      end;
    end;
    Assert.IsTrue(lRaised, aToken);
  end;

begin
  for lDialect := Low(TmaxCronDialect) to High(TmaxCronDialect) do
  begin
    for lToken in cForms do
    begin
      if lDialect = cdQuartzSecondsFirst then
        lText := '0 0 0 ' + lToken + ' * ?'
      else
        lText := '0 0 ' + lToken + ' * *';
      AssertParsesDialect(lText, lDialect);
    end;
  end;
  for lToken in cInvalid do CheckError(lToken, 'Invalid cron token');
  for lToken in cOutOfRange do CheckError(lToken, 'Cron value out of range');
  lPlan := TCronSchedulePlan.Create;
  try
    // Large offsets can parse but never match the selected month or any month.
    for lToken in ['L-30', 'L-30W', 'LW-30'] do
    begin
      lPlan.Parse('0 0 ' + lToken + ' 2 *');
      Assert.IsFalse(lPlan.FindNextScheduleDate(EncodeDate(2026, 1, 1), lDate));
    end;
  finally
    lPlan.Free;
  end;
end;

procedure TTestCronParsing.Describe_SyntaxAdditions;
begin
  AssertDescription('0 22-2 * * *', 'Custom schedule');
  AssertDescription('30-0/30 * * * *', 'Every 30 minutes');
  AssertDescription('0 8 * * FRI-MON', 'Every week on Sun,Mon,Fri,Sat at 08:00');
  AssertDescription('0 9 * NOV-FEB *', 'Custom schedule');
  AssertDescription('0 10 L-2 * *', 'Every month on the last day minus 2 days at 10:00');
  AssertDescription('0 10 L-1 * *', 'Every month on the last day minus 1 day at 10:00');
  AssertDescription('0 10 LW-2 * *', 'Every month on the last weekday minus 2 weekdays at 10:00');
  AssertDescription('0 10 LW-1 * *', 'Every month on the last weekday minus 1 weekday at 10:00');
  AssertDescription('0 10 L-3W * *', 'Every month on the nearest weekday to the last day minus 3 days at 10:00');
  AssertDescription('0 10 L-1W * *', 'Every month on the nearest weekday to the last day minus 1 day at 10:00');
  AssertDescription('0 10 L-0W * *', 'Every month on the nearest weekday to the last day at 10:00');
  AssertDescription('0 10 L-0 * *', 'Every month on the last day at 10:00');
  AssertDescription('0 10 LW-0 * *', 'Every month on the last weekday at 10:00');
  AssertDescription('0 10 L-2 2 *', 'Every year on Feb the last day minus 2 days at 10:00');
end;

procedure TTestCronParsing.Parse_WrappedRanges_Expansion;
const
  cSteps: array[0..11] of Integer = (1, 2, 3, 4, 5, 6, 7, 10, 15, 30, 59, 61);
  cMonths: array[1..12] of string = ('JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
    'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC');
var
  lPlan: TCronSchedulePlan;
  lPart: TCronPart;
  lKind, lLow, lHigh, lWidth, lFrom, lTo, lStep, lSpan, lOffset, lValue, lName, lDialect: Integer;
  lExpected: array[0..59] of Boolean;
  lToken, lLeft, lRight: string;

  procedure CheckError(const aText, aMessage: string);
  var
    lRaised: Boolean;
  begin
    lRaised := False;
    try
      lPlan.Parse(aText);
    except
      on E: Exception do
      begin
        lRaised := True;
        Assert.AreEqual('Exception', E.ClassName, aText);
        Assert.AreEqual(aMessage, E.Message, aText);
      end;
    end;
    Assert.IsTrue(lRaised, aText);
  end;

begin
  lPlan := TCronSchedulePlan.Create;
  try
    for lKind := 0 to 4 do
    begin
      case lKind of
        0: begin lPart := lPlan.Second; lLow := 0; lHigh := 59; end;
        1: begin lPart := lPlan.Minute; lLow := 0; lHigh := 59; end;
        2: begin lPart := lPlan.Hour; lLow := 0; lHigh := 23; end;
        3: begin lPart := lPlan.Month; lLow := 1; lHigh := 12; end;
      else
        begin lPart := lPlan.Day_of_the_Week; lLow := 0; lHigh := 6; end;
      end;
      lWidth := lHigh - lLow + 1;
      for lFrom := lLow + 1 to lHigh do
      begin
        for lTo := lLow to lFrom - 1 do
        begin
          for lStep in cSteps do
          begin
            // Month names and both weekday numberings exercise replacement/normalization.
            for lName := 0 to Ord(lKind = 3) do
            begin
              for lDialect := 0 to Ord(lKind = 4) do
              begin
                lLeft := IntToStr(lFrom + lDialect);
                lRight := IntToStr(lTo + lDialect);
                if lName = 1 then
                begin
                  lLeft := cMonths[lFrom];
                  lRight := cMonths[lTo];
                end;
                lToken := lLeft + '-' + lRight + '/' + IntToStr(lStep);
                if lDialect = 1 then
                  lPlan.Dialect := cdQuartzSecondsFirst
                else
                  lPlan.Dialect := cdMaxCron;
                // Data parses through the public setter using the configured numbering.
                lPart.Data := lToken;
                for lValue := lLow to lHigh do lExpected[lValue] := False;
                if lKind = 4 then
                begin
                  // Preserve established weekday per-segment stepping.
                  for lValue := lLow to lHigh do
                    lExpected[lValue] := ((lValue >= lFrom) and ((lValue - lFrom) mod lStep = 0)) or
                      ((lValue <= lTo) and ((lValue - lLow) mod lStep = 0));
                end else begin
                  lSpan := lHigh - lFrom + 1 + lTo - lLow + 1;
                  lOffset := 0;
                  while lOffset < lSpan do
                  begin
                    lExpected[lLow + ((lFrom - lLow + lOffset) mod lWidth)] := True;
                    Inc(lOffset, lStep);
                  end;
                end;
                for lValue := lLow to lHigh do
                  Assert.AreEqual(lExpected[lValue], lPart.NextVal(lValue) = lValue, lToken + ' value ' + IntToStr(lValue));
                if (lKind = 4) and (lDialect = 0) and (lTo = 0) then
                begin
                  lPart.Data := IntToStr(lFrom) + '-7/' + IntToStr(lStep);
                  for lValue := lLow to lHigh do
                    Assert.AreEqual(lExpected[lValue], lPart.NextVal(lValue) = lValue, 'Sunday alias ' + lToken);
                end;
              end;
            end;
          end;
          lPlan.Dialect := cdMaxCron;
          lPart.Data := IntToStr(lFrom) + '-' + IntToStr(lTo) + '/' + IntToStr(lWidth + 1);
          for lValue := lLow to lHigh do
            Assert.AreEqual((lValue = lFrom) or ((lKind = 4) and (lValue = lLow)),
              lPart.NextVal(lValue) = lValue, 'width+1');
        end;
      end;
    end;
    lPlan.Parse('0 22-2/2147483647 * * *');
    for lValue := 0 to 23 do Assert.AreEqual(lValue = 22, lPlan.Hour.NextVal(lValue) = lValue);
    CheckError('0 0 25-5 * *', 'Invalid cron range');
    CheckError('0 0 1 * * 2030-2026', 'Invalid cron range');
    CheckError('0 H(22-2) * * *', 'Cron value out of range');
    // The 7 alias and the 0-7 meaning remain unchanged.
    lPlan.Parse('0 0 * * 0-7');
    for lValue := 0 to 6 do Assert.AreEqual(lValue = 0, lPlan.Day_of_the_Week.NextVal(lValue) = lValue);
    lPlan.Parse('0 0 * * 1-7/4');
    for lValue := 0 to 6 do Assert.AreEqual(lValue in [0, 1, 5], lPlan.Day_of_the_Week.NextVal(lValue) = lValue);
  finally
    lPlan.Free;
  end;
end;

procedure TTestCronParsing.Parse_InvalidIntegerGrammar_UsesParseException;
const
  cAtoms: array[0..11] of string = ('1', 'W', 'BAD', '2147483648', 'L-2', 'LW',
    '15W', 'MON', 'H(1-5)', '?', '*', '');
var
  lDialect: TmaxCronDialect;
  lPlan: TCronSchedulePlan;
  lFields: TArray<string>;
  lLeft, lRight, lToken, lText, lClass, lMessage, lFailures: string;
  lField, lForm, lIndex, lLeaks, lRejected: Integer;
begin
  lLeaks := 0;
  lRejected := 0;
  lFailures := '';
  for lDialect := Low(TmaxCronDialect) to High(TmaxCronDialect) do
  begin
    case lDialect of
      cdStandard: lFields := ['0', '0', '1', '1', '1'];
      cdMaxCron: lFields := ['0', '0', '1', '1', '1', '2025', '0', '0'];
    else
      lFields := ['0', '0', '0', '1', '1', '1', '2025'];
    end;
    for lField := 0 to Length(lFields) - 1 do
      for lLeft in cAtoms do
        for lRight in cAtoms do
          for lForm := 0 to 4 do
          begin
            case lForm of
              0: lToken := lLeft + ',' + lRight;
              1: lToken := lLeft + '-' + lRight;
              2: lToken := lLeft + '/' + lRight;
              3: lToken := 'H(' + lLeft + '-' + lRight + ')';
            else
              lToken := lLeft + ',15,' + lRight;
            end;
            lText := '';
            for lIndex := 0 to Length(lFields) - 1 do
            begin
              if lIndex > 0 then lText := lText + ' ';
              if lIndex = lField then lText := lText + lToken
              else lText := lText + lFields[lIndex];
            end;
            lClass := '';
            lMessage := '';
            lPlan := TCronSchedulePlan.Create;
            try
              lPlan.Dialect := lDialect;
              try
                lPlan.Parse(lText);
              except
                on E: Exception do
                begin
                  lClass := E.ClassName;
                  lMessage := E.Message;
                end;
              end;
            finally
              lPlan.Free;
            end;
            if lClass <> '' then
            begin
              Inc(lRejected);
              if lClass <> 'Exception' then
              begin
                Inc(lLeaks);
                if lLeaks <= 10 then
                  lFailures := lFailures + lText + ': ' + lClass + '|' + lMessage + sLineBreak;
              end;
            end;
          end;
  end;
  Assert.IsTrue(lRejected > 0, 'Generated invalid expressions must reach the parser');
  Assert.AreEqual(0, lLeaks, lFailures);
end;

procedure TTestCronParsing.Parse_MonthEndOffsetLists_ErrorPrecedence;
const
  cOffsets: array[0..5] of string = ('0', '2', '30', '31', '2147483648', '99999999999');
var
  lDialect: TmaxCronDialect;
  lOffset, lToken, lFailures: string;
  lForm, lChecked: Integer;

  procedure Check(const aToken, aExpected: string);
  var
    lPlan: TCronSchedulePlan;
    lText, lClass, lMessage: string;
  begin
    Inc(lChecked);
    if lDialect = cdQuartzSecondsFirst then lText := '0 0 0 ' + aToken + ' * ?'
    else lText := '0 0 ' + aToken + ' * *';
    lClass := '';
    lMessage := '';
    lPlan := TCronSchedulePlan.Create;
    try
      lPlan.Dialect := lDialect;
      try
        lPlan.Parse(lText);
      except
        on E: Exception do
        begin
          lClass := E.ClassName;
          lMessage := E.Message;
        end;
      end;
    finally
      lPlan.Free;
    end;
    if (lClass <> 'Exception') or (lMessage <> aExpected) then
      lFailures := lFailures + IntToStr(Ord(lDialect)) + '|' + lText + ': expected Exception|' +
        aExpected + ', got ' + lClass + '|' + lMessage + sLineBreak;
  end;

begin
  lChecked := 0;
  lFailures := '';
  for lDialect := Low(TmaxCronDialect) to High(TmaxCronDialect) do
  begin
    for lForm := 0 to 2 do
    begin
      for lOffset in cOffsets do
      begin
        case lForm of
          0: lToken := 'L-' + lOffset;
          1: lToken := 'LW-' + lOffset;
        else lToken := 'L-' + lOffset + 'W';
        end;
        Check(lToken + ',15', 'Invalid cron token');
        Check('15,' + lToken, 'Invalid cron token');
      end;
      case lForm of
        0: lToken := 'L-31';
        1: lToken := 'LW-31';
      else lToken := 'L-31W';
      end;
      // Existing nW validation still wins when it appears before the new token.
      Check('0W,' + lToken, 'Cron value out of range');
      Check(lToken + ',0W', 'Invalid cron token');
    end;
    Check('0W,15', 'Cron value out of range');
    Check('15,0W', 'Cron value out of range');
    Check('32W,15', 'Cron value out of range');
    Check('15,32W', 'Cron value out of range');
  end;
  Assert.AreEqual(138, lChecked, 'All forms, offsets, orders and dialects must be exercised');
  Assert.AreEqual('', lFailures, lFailures);
end;

procedure TTestCronParsing.Parse_MonthEndOffsets_LaterFieldDiagnostics;
const
  cForms: array[0..5] of string = ('L-2', 'LW-2', 'L-2W', 'l-0', 'lw-30', 'l-030w');
var
  lDialect: TmaxCronDialect;
  lToken, lLater, lText, lExpectedClass, lExpectedMessage: string;
  lChecked: Integer;

  procedure Diagnostic(const aText: string; out aClass, aMessage: string);
  var
    lPlan: TCronSchedulePlan;
  begin
    aClass := '';
    aMessage := '';
    lPlan := TCronSchedulePlan.Create;
    try
      lPlan.Dialect := lDialect;
      try
        lPlan.Parse(aText);
      except
        on E: Exception do
        begin
          aClass := E.ClassName;
          aMessage := E.Message;
        end;
      end;
    finally
      lPlan.Free;
    end;
  end;

  procedure Check(const aText, aClass, aMessage: string);
  var
    lClass, lMessage: string;
  begin
    Inc(lChecked);
    Diagnostic(aText, lClass, lMessage);
    Assert.AreEqual(aClass, lClass, aText);
    Assert.AreEqual(aMessage, lMessage, aText);
  end;

begin
  lChecked := 0;
  for lDialect := Low(TmaxCronDialect) to High(TmaxCronDialect) do
  begin
    for lToken in cForms do
    begin
      for lLater in ['13,15', 'W,15', 'BAD,15', '13-15', 'JAN-GARBAGE', 'nov,13', '2/0'] do
      begin
        if lDialect = cdQuartzSecondsFirst then lText := '0 0 0 1 ' + lLater + ' ?'
        else lText := '0 0 1 ' + lLater + ' *';
        Diagnostic(lText, lExpectedClass, lExpectedMessage);
        Assert.IsTrue(lExpectedClass <> '', 'Legacy-valid DOM must expose invalid month');
        if lDialect = cdQuartzSecondsFirst then lText := '0 0 0 ' + lToken + ' ' + lLater + ' ?'
        else lText := '0 0 ' + lToken + ' ' + lLater + ' *';
        Check(lText, lExpectedClass, lExpectedMessage);
      end;
      if lDialect = cdQuartzSecondsFirst then
      begin
        Check('0 0 0 ' + lToken + ' 13,15 ?', 'Exception', 'Cron value out of range');
        Check('0 0 0 ' + lToken + ' * 8', 'Exception', 'Cron value out of range');
        Check('0 0 0 ' + lToken + ' * ? 2030-2026', 'Exception', 'Invalid cron range');
      end else begin
        Check('0 0 ' + lToken + ' 13,15 *', 'Exception', 'Cron value out of range');
        Check('0 0 ' + lToken + ' * 8', 'Exception', 'Cron value out of range');
        if lDialect = cdMaxCron then
        begin
          Check('0 0 ' + lToken + ' * * 2030-2026', 'Exception', 'Invalid cron range');
          Check('0 0 ' + lToken + ' * * * 60', 'Exception', 'Cron value out of range');
          Check('0 0 ' + lToken + ' * * * 0 -1', 'Exception', 'Cron value out of range');
        end;
      end;
    end;
  end;
  Assert.AreEqual(186, lChecked, 'All dialects/forms/month errors and later fields');
end;

end.

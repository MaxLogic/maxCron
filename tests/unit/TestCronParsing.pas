unit TestCronParsing;

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  maxCron;

type
  [TestFixture]
  TTestCronParsing = class
  private
    procedure AssertParses(const aExpr: string);
    procedure AssertRaisesOnParse(const aExpr: string);
    procedure AssertParsesDialect(const aExpr: string; const aDialect: TmaxCronDialect);
    procedure AssertRaisesOnParseDialect(const aExpr: string; const aDialect: TmaxCronDialect);
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
    procedure Parse_Macros;

    [Test]
    procedure Parse_CommentsAndWhitespace;

    [Test]
    procedure Parse_QuartzModifiers;

    [Test]
    procedure Parse_RebootMacro_SetsExecutionLimit;

    [Test]
    procedure Parse_Dialect_Standard_Exact5;

    [Test]
    procedure Parse_Dialect_QuartzSecondsFirst_FieldOrder;
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
    AssertRaisesOnParseDialect('0 0 * * *', cdQuartzSecondsFirst);
    AssertRaisesOnParseDialect('0 0 1 2 3 4 5 6', cdQuartzSecondsFirst);
  finally
    Plan.Free;
  end;
end;

end.

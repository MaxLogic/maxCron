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
  end;

implementation

procedure TTestCronParsing.AssertParses(const aExpr: string);
var
  Plan: TCronSchedulePlan;
begin
  Plan := TCronSchedulePlan.Create;
  try
    Plan.Parse(aExpr);
  finally
    Plan.Free;
  end;
end;

procedure TTestCronParsing.AssertRaisesOnParse(const aExpr: string);
begin
  try
    AssertParses(aExpr);
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

end.

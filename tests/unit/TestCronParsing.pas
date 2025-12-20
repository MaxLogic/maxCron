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
end;

end.

unit TestCronTextParity;
{$I maxCron.inc}
{$IFDEF FPC}{$WARN 4105 ERROR}{$ENDIF}

interface

uses
  {$IFDEF FPC}
  SysUtils,
  {$ELSE} System.SysUtils, {$ENDIF}
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestCronTextParity = class
  public
    [Test] procedure RejectsForeignNumericSyntax;
    [Test] procedure RejectsNonAsciiPlans;
    [Test] procedure ValidAsciiForms;
    [Test] procedure SplitEdges;
    [Test] procedure ReplaceAscii;
    [Test] procedure NumericHelpers;
    [Test] procedure SpecialFloatSpellings;
  end;

implementation

uses
  maxCron.Internal.Text, maxCron.Plan;

procedure RequireRejected(const s: string);
var
  lPlan: TCronSchedulePlan;
  lRejected: Boolean;
begin
  lPlan := TCronSchedulePlan.Create;
  try
    lRejected := False;
    try
      lPlan.Parse(s);
    except
      on E: Exception do lRejected := True;
    end;
    Assert.IsTrue(lRejected, 'Expected plan rejection: ' + s);
  finally
    lPlan.Free;
  end;
end;

procedure TTestCronTextParity.RejectsForeignNumericSyntax;
begin
  RequireRejected('0 0 %101 * *');
  RequireRejected('0 0 &12 * *');
  RequireRejected('0 0 * * * %11111101011');
  RequireRejected('0 0 * * * * &7');
  Assert.IsFalse(CronSameTextAscii('x', #$FF38));
end;

procedure TTestCronTextParity.RejectsNonAsciiPlans;
const
  cForeign: array[0..8] of string = (#$4E2D, #$FF11, #$0661, #$00B9, #$2009,
    #$FEFF, #$3000, #$FF0C, #$00A0);
var
  s: string;
  i: Integer;
begin
  for s in cForeign do
    for i := 0 to 4 do
      case i of
        0: RequireRejected(s + ' 0 * * *');
        1: RequireRejected('0 ' + s + ' * * *');
        2: RequireRejected('0 0 ' + s + ' * *');
        3: RequireRejected('0 0 * ' + s + ' *');
        4: RequireRejected('0 0 * * ' + s);
      end;
  RequireRejected('0 0 * * fr' + #$0131);
  RequireRejected('0 0 * * MO' + #$FF2E);
  RequireRejected('0 0 * J' + #$00C5 + 'N *');
end;

procedure TTestCronTextParity.ValidAsciiForms;
var
  lPlan: TCronSchedulePlan;
  s: string;
  lNext: TDateTime;
begin
  lPlan := TCronSchedulePlan.Create;
  try
    for s in ['$A', '0xA', '+5', '05'] do
    begin
      lPlan.Parse(s + ' 0 * * *');
      Assert.IsTrue(lPlan.FindNextScheduleDate(EncodeDate(2026, 1, 1), lNext));
    end;
    lPlan.Parse('0 0 * jan mon');
    Assert.IsTrue(lPlan.FindNextScheduleDate(EncodeDate(2026, 1, 1), lNext));
  finally
    lPlan.Free;
  end;
end;

procedure TTestCronTextParity.SplitEdges;
var
  lParts: TArray<string>;
begin
  Assert.AreEqual<NativeInt>(0, Length(CronSplitChar('', ',')));
  lParts := CronSplitChar(',a,,b,', ',');
  Assert.AreEqual<NativeInt>(4, Length(lParts));
  Assert.AreEqual<string>('', lParts[0]);
  Assert.AreEqual<string>('a', lParts[1]);
  Assert.AreEqual<string>('', lParts[2]);
  Assert.AreEqual<string>('b', lParts[3]);
  lParts := CronSplitWhitespace(' ' + #9 + 'a  b' + #13#10);
  Assert.AreEqual<NativeInt>(2, Length(lParts));
  Assert.AreEqual<string>('a', lParts[0]);
  Assert.AreEqual<string>('b', lParts[1]);
end;

procedure TTestCronTextParity.ReplaceAscii;
var
  s, p, r: string;
begin
  for s in ['', 'Monday', 'aAaAa', 'a,b,,c', 'JANfebJAN'] do
    for p in ['', 'a', 'Aa', 'JAN', ','] do
      for r in ['', 'a', 'AaA', ','] do
        Assert.AreEqual(StringReplace(s, p, r, [rfReplaceAll, rfIgnoreCase]),
          CronReplaceTextAscii(s, p, r));
end;

procedure TTestCronTextParity.NumericHelpers;
var
  lNumber: Integer;
  lFloat: Double;
  lRejected: Boolean;
begin
  Assert.IsFalse(CronTryStrToInt(#9 + '1', lNumber));
  Assert.IsFalse(CronTryStrToInt('%101', lNumber));
  Assert.IsFalse(CronTryStrToInt('&12', lNumber));
  Assert.IsFalse(CronTryStrToFloatInvariant('.', lFloat));
  Assert.IsFalse(CronTryStrToFloatInvariant('e+', lFloat));
  Assert.IsFalse(CronTryStrToFloatInvariant('1e', lFloat));
  Assert.IsTrue(CronTryStrToFloatInvariant(' -1.5e+2 ', lFloat));
  Assert.AreEqual<Double>(-150, lFloat);
  lRejected := False;
  try
    CronStrToInt('%101');
  except
    on E: EConvertError do
    begin
      lRejected := True;
      Assert.AreEqual<string>('''%101'' is not a valid integer value', CronExceptionText(E));
    end;
  end;
  Assert.IsTrue(lRejected, 'Numeric rejection must use EConvertError');
end;

procedure TTestCronTextParity.SpecialFloatSpellings;
const
  cPositiveInf: UInt64 = $7FF0000000000000;
  cNegativeInf: UInt64 = UInt64($FFF0000000000000);
  cQuietNan: UInt64 = UInt64($FFF8000000000000);
var
  lMask, i: Integer;
  lInf, lNan: string;

  procedure Check(const s: string; const aAccepted: Boolean; const aBits: UInt64);
  var
    lValue: Double;
    lBits: UInt64;
  begin
    Assert.AreEqual<Boolean>(aAccepted, CronTryStrToFloatInvariant(s, lValue), s);
    if aAccepted then
    begin
      Move(lValue, lBits, SizeOf(lBits));
      Assert.AreEqual<UInt64>(aBits, lBits, s);
    end;
  end;

begin
  // Characterized against Delphi's invariant RTL conversion, including NaN bits.
  for lMask := 0 to 7 do
  begin
    lInf := 'INF';
    lNan := 'NAN';
    for i := 1 to 3 do
      if (lMask and (1 shl (i - 1))) <> 0 then
      begin
        lInf[i] := Char(Ord(lInf[i]) + 32);
        lNan[i] := Char(Ord(lNan[i]) + 32);
      end;
    Check(lInf, True, cPositiveInf);
    Check('  ' + lInf, True, cPositiveInf);
    Check('+' + lInf, True, cPositiveInf);
    Check('  -' + lInf, True, cNegativeInf);
    Check(lNan, True, cQuietNan);
    Check('  ' + lNan, True, cQuietNan);
    Check('+' + lNan, False, 0);
    Check('-' + lNan, False, 0);
    Check(lInf + ' ', False, 0);
    Check(lNan + ' ', False, 0);
    Check(#9 + lInf, False, 0);
    Check(lNan + #9, False, 0);
  end;
  Check('INFINITY', False, 0);
  Check('NAN(1)', False, 0);
  Check('1.#INF', False, 0);
  Check('+ INF', False, 0);
end;

end.

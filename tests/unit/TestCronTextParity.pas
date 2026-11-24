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
    [Test] procedure DecimalIntegerHelpers;
    [Test] procedure ExcludedDateRejectsHex;
    [Test] procedure AutoIntegerEnvironmentUsesDecimal;
    [Test] procedure LongDecimalPadding;
    [Test] procedure AutoIntegerEnvironmentLongDecimalPadding;
    [Test] procedure SpecialFloatSpellings;
  end;

implementation

uses
  {$IFDEF FPC} Windows, {$ELSE} Winapi.Windows, {$ENDIF}
  maxCron, maxCron.Internal.Text, maxCron.Plan;

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
  lNext: TDateTime;
begin
  lPlan := TCronSchedulePlan.Create;
  try
    lPlan.Parse('05 0 * * *');
    Assert.IsTrue(lPlan.FindNextScheduleDate(EncodeDate(2026, 1, 1), lNext));
    Assert.AreEqual<TDateTime>(EncodeDate(2026, 1, 1) + EncodeTime(0, 5, 0, 0), lNext);
    lPlan.Parse('00 0 1 1 *');
    Assert.IsTrue(lPlan.FindNextScheduleDate(EncodeDate(2025, 12, 31), lNext));
    Assert.AreEqual<TDateTime>(EncodeDate(2026, 1, 1), lNext);
    lPlan.Parse('0 0 15W * *');
    Assert.IsTrue(lPlan.FindNextScheduleDate(EncodeDate(2026, 8, 1), lNext));
    Assert.AreEqual<TDateTime>(EncodeDate(2026, 8, 14), lNext);
    lPlan.Parse('0 0 L-3 * * * 0 10');
    Assert.IsTrue(lPlan.FindNextScheduleDate(EncodeDate(2026, 1, 1), lNext));
    Assert.AreEqual<TDateTime>(EncodeDate(2026, 1, 28), lNext);
    Assert.AreEqual<LongWord>(10, lPlan.ExecutionLimit);
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

procedure TTestCronTextParity.DecimalIntegerHelpers;
const
  cInvalid: array[0..13] of string = ('', '$A', '0xA', 'xA', '+10', '-10',
    '1-0', ' 10', '10 ', '1 0', #9 + '10', '10' + #9, #$FF11, '999999999999999999999999');
var
  s, lFailures: string;
  lInt: Integer;
  lInt64: Int64;
  lRejected: Boolean;
begin
  for s in cInvalid do
  begin
    if CronTryStrToInt(s, lInt) then
      lFailures := lFailures + 'TryStrToInt accepted [' + s + ']' + sLineBreak;
    if CronTryStrToInt64(s, lInt64) then
      lFailures := lFailures + 'TryStrToInt64 accepted [' + s + ']' + sLineBreak;
    if CronStrToIntDef(s, -1) <> -1 then
      lFailures := lFailures + 'StrToIntDef accepted [' + s + ']' + sLineBreak;
    lRejected := False;
    try
      CronStrToInt(s);
    except
      on E: EConvertError do lRejected := True;
    end;
    if not lRejected then
      lFailures := lFailures + 'StrToInt accepted [' + s + ']' + sLineBreak;
    lRejected := False;
    try
      CronStrToInt64(s);
    except
      on E: EConvertError do lRejected := True;
    end;
    if not lRejected then
      lFailures := lFailures + 'StrToInt64 accepted [' + s + ']' + sLineBreak;
  end;
  Assert.AreEqual<string>('', lFailures, lFailures);
  Assert.AreEqual<Integer>(0, CronStrToInt('0'));
  Assert.AreEqual<Integer>(0, CronStrToIntDef('00', -1));
  Assert.AreEqual<Integer>(High(Integer), CronStrToInt('02147483647'));
  Assert.AreEqual<Int64>(High(Int64), CronStrToInt64('09223372036854775807'));
  Assert.IsFalse(CronTryStrToInt('2147483648', lInt));
  Assert.IsFalse(CronTryStrToInt64('9223372036854775808', lInt64));
end;

procedure TTestCronTextParity.ExcludedDateRejectsHex;
var
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lDiagnostic: string;

  function Diagnostic(const s: string): string;
  begin
    Result := '';
    try
      lEvent.ExcludedDatesCsv := s;
    except
      on E: EConvertError do Result := CronExceptionText(E);
    end;
  end;

begin
  lCron := TmaxCron.Create(ctPortable);
  try
    lEvent := lCron.Add('ExcludedDateDecimal');
    lEvent.ExcludedDatesCsv := '2026-12-01';
    Assert.AreEqual<string>('2026-12-01', lEvent.ExcludedDatesCsv);
    lDiagnostic := Diagnostic('ZZZZ-12-01');
    Assert.IsTrue(lDiagnostic <> '', 'Non-numeric date must raise EConvertError');
    Assert.AreEqual<string>(StringReplace(lDiagnostic, 'ZZZZ', '$7EA', []), Diagnostic('$7EA-12-01'));
  finally
    lCron.Free;
  end;
end;

procedure TTestCronTextParity.AutoIntegerEnvironmentUsesDecimal;
const
  cEnvName = 'MAXCRON_GLOBAL_MAX_CONCURRENT';
var
  lPrevious: string;
  lHadPrevious: Boolean;
  c: Char;

  procedure Check(const s: string; const aExpected: Integer);
  var
    lCron: TmaxCron;
  begin
    Assert.IsTrue(SetEnvironmentVariableW(cEnvName, PChar(s)));
    lCron := TmaxCron.Create(ctPortable);
    try
      Assert.AreEqual<Integer>(aExpected, lCron.GlobalMaxConcurrentCallbacks, '[' + s + ']');
    finally
      lCron.Free;
    end;
  end;

begin
  SetLastError(0);
  lHadPrevious := (GetEnvironmentVariableW(cEnvName, @c, 1) <> 0) or
    (GetLastError <> ERROR_ENVVAR_NOT_FOUND);
  lPrevious := {$IFDEF FPC}SysUtils{$ELSE}System.SysUtils{$ENDIF}.GetEnvironmentVariable(cEnvName);
  try
    Check('019', 19);
    Check('19', 19);
    Check('invalid', 0);
    Check('0x13', 0);
    Check('+19', 0);
    Check(' 19 ', 19);
    Check('19' + #9, 19);
  finally
    if lHadPrevious then
      SetEnvironmentVariableW(cEnvName, PChar(lPrevious))
    else
      SetEnvironmentVariableW(cEnvName, nil);
  end;
end;

procedure TTestCronTextParity.LongDecimalPadding;
var
  lInt: Integer;
  lInt64: Int64;
  lPadding: string;
  i: Integer;
begin
  for i := 255 to 256 do
  begin
    lPadding := StringOfChar('0', i);
    Assert.AreEqual<Integer>(7, CronStrToInt(lPadding + '7'));
    Assert.AreEqual<Int64>(7, CronStrToInt64(lPadding + '7'));
    Assert.AreEqual<Integer>(High(Integer), CronStrToInt(lPadding + '2147483647'));
    Assert.AreEqual<Int64>(High(Int64), CronStrToInt64(lPadding + '9223372036854775807'));
    Assert.IsFalse(CronTryStrToInt(lPadding + '2147483648', lInt));
    Assert.IsFalse(CronTryStrToInt64(lPadding + '9223372036854775808', lInt64));
  end;
  lPadding := StringOfChar('0', 300);
  Assert.AreEqual<Integer>(0, CronStrToInt(lPadding));
  Assert.AreEqual<Int64>(0, CronStrToInt64(lPadding));
end;

procedure TTestCronTextParity.AutoIntegerEnvironmentLongDecimalPadding;
const
  cEnvName = 'MAXCRON_GLOBAL_MAX_CONCURRENT';
var
  lPrevious: string;
  lHadPrevious: Boolean;
  lCron: TmaxCron;
  c: Char;
begin
  SetLastError(0);
  lHadPrevious := (GetEnvironmentVariableW(cEnvName, @c, 1) <> 0) or
    (GetLastError <> ERROR_ENVVAR_NOT_FOUND);
  lPrevious := {$IFDEF FPC}SysUtils{$ELSE}System.SysUtils{$ENDIF}.GetEnvironmentVariable(cEnvName);
  Assert.IsTrue(SetEnvironmentVariableW(cEnvName, PChar(StringOfChar('0', 256) + '19')));
  try
    lCron := TmaxCron.Create(ctPortable);
    try
      Assert.AreEqual<Integer>(19, lCron.GlobalMaxConcurrentCallbacks);
    finally
      lCron.Free;
    end;
  finally
    if lHadPrevious then
      SetEnvironmentVariableW(cEnvName, PChar(lPrevious))
    else
      SetEnvironmentVariableW(cEnvName, nil);
  end;
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

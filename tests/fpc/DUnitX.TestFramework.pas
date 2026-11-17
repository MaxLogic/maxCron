unit DUnitX.TestFramework;
{$I maxCron.inc}
// FPC-only assertion surface for the unchanged DUnitX test logic.
interface
uses Generics.Defaults, Math, Rtti, SysUtils;
type
  ETestFailure = class(Exception);
  TestFixtureAttribute = class(TCustomAttribute) public constructor Create; end;
  TestAttribute = class(TCustomAttribute) public constructor Create; end;
  TestCaseAttribute = class(TCustomAttribute)
  public
    constructor Create(const aName, aValues: string);
  end;
  Assert = class
  public
    class procedure Fail(const aMessage: string = '');
    class procedure IsTrue(const aCondition: Boolean; const aMessage: string = '');
    class procedure IsFalse(const aCondition: Boolean; const aMessage: string = '');
    class procedure AreEqual<T>(const aExpected, aActual: T; const aMessage: string = ''); overload;
    class procedure AreEqual(const aExpected, aActual: string; const aMessage: string = ''); overload;
    class procedure AreEqual(const aExpected, aActual: Double; const aMessage: string = ''); overload;
    class procedure AreEqual(const aExpected, aActual: Integer; const aMessage: string = ''); overload;
    class procedure AreEqual(const aExpected, aActual: Int64; const aMessage: string = ''); overload;
    class procedure AreEqual(const aExpected, aActual: Cardinal; const aMessage: string = ''); overload;
    class procedure AreEqual(const aExpected, aActual: Word; const aMessage: string = ''); overload;
    class procedure AreEqual(const aExpected, aActual: Boolean; const aMessage: string = ''); overload;
    class procedure AreNotEqual(const aExpected, aActual: string; const aMessage: string = ''); overload;
    class procedure AreNotEqual(const aExpected, aActual: Double; const aMessage: string = ''); overload;
    class procedure AreNotEqual(const aExpected, aActual: Integer; const aMessage: string = ''); overload;
    class procedure AreNotEqual(const aExpected, aActual: Int64; const aMessage: string = ''); overload;
    class procedure AreNotEqual(const aExpected, aActual: Cardinal; const aMessage: string = ''); overload;
    class procedure AreNotEqual(const aExpected, aActual: Word; const aMessage: string = ''); overload;
    class procedure AreNotEqual(const aExpected, aActual: Boolean; const aMessage: string = ''); overload;
    class procedure AreEqual(const aExpected, aActual: Double; const aTolerance: Double; const aMessage: string = ''); overload;
  end;
implementation
constructor TestFixtureAttribute.Create;
begin
  inherited Create;
end;
constructor TestAttribute.Create;
begin
  inherited Create;
end;
constructor TestCaseAttribute.Create(const aName, aValues: string);
begin
  inherited Create;
end;
class procedure Assert.Fail(const aMessage: string);
begin
  raise ETestFailure.Create(aMessage);
end;
class procedure Assert.IsTrue(const aCondition: Boolean; const aMessage: string);
begin
  if not aCondition then Fail('Expected True but got False: ' + aMessage);
end;
class procedure Assert.IsFalse(const aCondition: Boolean; const aMessage: string);
begin
  if aCondition then Fail('Expected False but got True: ' + aMessage);
end;
class procedure Assert.AreEqual<T>(const aExpected, aActual: T; const aMessage: string);
var
  lComparer: IEqualityComparer<T>;
  lExpected, lActual: TValue;
begin
  lComparer := TEqualityComparer<T>.Default;
  if not lComparer.Equals(aExpected, aActual) then
  begin
    lExpected := TValue.From<T>(aExpected);
    lActual := TValue.From<T>(aActual);
    Fail('Expected <' + string(lExpected.ToString) + '> but got <' + string(lActual.ToString) + '>: ' + aMessage);
  end;
end;
class procedure Assert.AreEqual(const aExpected, aActual: string; const aMessage: string);
begin
  if aExpected <> aActual then
    Fail('Expected <' + aExpected + '> but got <' + aActual + '>: ' + aMessage);
end;
class procedure Assert.AreEqual(const aExpected, aActual: Double; const aMessage: string);
begin
  AreEqual(aExpected, aActual, Double(0), aMessage);
end;
class procedure Assert.AreEqual(const aExpected, aActual: Integer; const aMessage: string);
begin
  if aExpected <> aActual then
    Fail('Expected <' + string(IntToStr(aExpected)) + '> but got <' + string(IntToStr(aActual)) + '>: ' + aMessage);
end;
class procedure Assert.AreEqual(const aExpected, aActual: Int64; const aMessage: string);
begin
  if aExpected <> aActual then
    Fail('Expected <' + string(IntToStr(aExpected)) + '> but got <' + string(IntToStr(aActual)) + '>: ' + aMessage);
end;
class procedure Assert.AreEqual(const aExpected, aActual: Cardinal; const aMessage: string);
begin
  if aExpected <> aActual then
    Fail('Expected <' + string(IntToStr(aExpected)) + '> but got <' + string(IntToStr(aActual)) + '>: ' + aMessage);
end;
class procedure Assert.AreEqual(const aExpected, aActual: Word; const aMessage: string);
begin
  if aExpected <> aActual then
    Fail('Expected <' + string(IntToStr(aExpected)) + '> but got <' + string(IntToStr(aActual)) + '>: ' + aMessage);
end;
class procedure Assert.AreEqual(const aExpected, aActual: Boolean; const aMessage: string);
begin
  if aExpected <> aActual then
    Fail('Expected <' + string(BoolToStr(aExpected, True)) + '> but got <' + string(BoolToStr(aActual, True)) + '>: ' + aMessage);
end;
class procedure Assert.AreNotEqual(const aExpected, aActual: string; const aMessage: string);
begin
  if aExpected = aActual then
    Fail('Expected <' + aExpected + '> but got <' + aActual + '>: ' + aMessage);
end;
class procedure Assert.AreNotEqual(const aExpected, aActual: Double; const aMessage: string);
begin
  if SameValue(aExpected, aActual, Double(0)) then
    Fail('Expected <' + string(FloatToStr(aExpected, TFormatSettings.Invariant)) + '> but got <' + string(FloatToStr(aActual, TFormatSettings.Invariant)) + '>: ' + aMessage);
end;
class procedure Assert.AreNotEqual(const aExpected, aActual: Integer; const aMessage: string);
begin
  if aExpected = aActual then
    Fail('Expected <' + string(IntToStr(aExpected)) + '> but got <' + string(IntToStr(aActual)) + '>: ' + aMessage);
end;
class procedure Assert.AreNotEqual(const aExpected, aActual: Int64; const aMessage: string);
begin
  if aExpected = aActual then
    Fail('Expected <' + string(IntToStr(aExpected)) + '> but got <' + string(IntToStr(aActual)) + '>: ' + aMessage);
end;
class procedure Assert.AreNotEqual(const aExpected, aActual: Cardinal; const aMessage: string);
begin
  if aExpected = aActual then
    Fail('Expected <' + string(IntToStr(aExpected)) + '> but got <' + string(IntToStr(aActual)) + '>: ' + aMessage);
end;
class procedure Assert.AreNotEqual(const aExpected, aActual: Word; const aMessage: string);
begin
  if aExpected = aActual then
    Fail('Expected <' + string(IntToStr(aExpected)) + '> but got <' + string(IntToStr(aActual)) + '>: ' + aMessage);
end;
class procedure Assert.AreNotEqual(const aExpected, aActual: Boolean; const aMessage: string);
begin
  if aExpected = aActual then
    Fail('Expected <' + string(BoolToStr(aExpected, True)) + '> but got <' + string(BoolToStr(aActual, True)) + '>: ' + aMessage);
end;
class procedure Assert.AreEqual(const aExpected, aActual: Double; const aTolerance: Double; const aMessage: string);
begin
  // DUnitX delegates to SameValue, including its relative epsilon when tolerance is zero.
  if not SameValue(aExpected, aActual, aTolerance) then
    Fail('Expected <' + string(FloatToStr(aExpected, TFormatSettings.Invariant)) + '> but got <' +
      string(FloatToStr(aActual, TFormatSettings.Invariant)) + '>: ' + aMessage);
end;
end.

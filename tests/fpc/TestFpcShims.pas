unit TestFpcShims;
{$I maxCron.inc}

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestFpcShims = class
  public
    [Test] procedure LifetimeLifo;
    [Test] procedure AssertionsRejectUnequal;
    [Test] procedure FloatToleranceMatchesDUnitX;
  end;

implementation

uses
  SysUtils, AutoFree;

type
  TRecordedObject = class
  private
    fValue: Integer;
  public
    constructor Create(const aValue: Integer);
    destructor Destroy; override;
  end;
var
  gOrder: string;

constructor TRecordedObject.Create(const aValue: Integer);
begin
  inherited Create;
  fValue := aValue;
end;

destructor TRecordedObject.Destroy;
begin
  gOrder := gOrder + string(IntToStr(fValue));
  inherited;
end;

procedure MakeOwnedObjects;
var
  g: TGarbos;
  lFirst, lSecond: TRecordedObject;
begin
  GC(lFirst, TRecordedObject.Create(1), g);
  lSecond := TRecordedObject.Create(2);
  GC(lSecond, g);
  Assert.AreEqual('', gOrder);
end;

procedure TTestFpcShims.LifetimeLifo;
begin
  gOrder := '';
  MakeOwnedObjects;
  Assert.AreEqual('21', gOrder);
end;

procedure TTestFpcShims.AssertionsRejectUnequal;
var
  i, lCaught: Integer;
begin
  lCaught := 0;
  for i := 0 to 8 do
    try
      case i of
        0: Assert.AreEqual('a', 'b');
        1: Assert.AreEqual(Integer(0), Integer(1));
        2: Assert.AreEqual(Int64(0), Int64(1) shl 32);
        3: Assert.AreEqual(Cardinal(0), High(Cardinal));
        4: Assert.AreEqual(Word(0), High(Word));
        5: Assert.AreEqual(False, True);
        6: Assert.AreEqual(Double(0), Double(1), Double(0.5));
        7: Assert.AreEqual<Integer>(1, 2);
        8: Assert.AreNotEqual('a', 'a');
      end;
    except
      on E: ETestFailure do Inc(lCaught);
    end;
  Assert.AreEqual(9, lCaught);
end;

procedure TTestFpcShims.FloatToleranceMatchesDUnitX;
var
  i, lCaught: Integer;
begin
  // Values and boundary outcomes characterized with the real Delphi DUnitX assertion overloads.
  Assert.AreEqual(Double(46025.479166666664), Double(46025.47916666667), Double(0));
  Assert.AreEqual(Double(1), Double(1.0000000000001));
  Assert.AreEqual(Double(1), Double(1.25), Double(0.25));
  Assert.AreNotEqual(Double(1), Double(1.00000000001));
  lCaught := 0;
  for i := 0 to 2 do
    try
      case i of
        0: Assert.AreEqual(Double(1), Double(1.00000000001));
        1: Assert.AreEqual(Double(1), Double(1.250001), Double(0.25));
        2: Assert.AreNotEqual(Double(1), Double(1.0000000000001));
      end;
    except
      on E: ETestFailure do Inc(lCaught);
    end;
  Assert.AreEqual(3, lCaught);
end;

end.

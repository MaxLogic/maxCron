unit TestLocalOverlapStress;
{$I maxCron.inc}
interface
uses DUnitX.TestFramework;
type
  [TestFixture]
  TTestLocalOverlapStress = class
  public
    [TestCase('scan', 'scan')]
    [TestCase('heap', 'heap')]
    [TestCase('shadow', 'shadow')]
    procedure Generated(const aEngine: string);
  end;
implementation
uses TestLocalOverlap;
procedure TTestLocalOverlapStress.Generated(const aEngine: string);
begin
  RunOverlapGeneratedMatrix(aEngine, False);
end;
end.

unit AutoFree;
{$I maxCron.inc}
// FPC-only stand-in for the shared tests. Not on any Delphi search path.

interface

type
  TGarbos = record
  private
    fItems: array of TObject;
  public
    procedure Add(const aObj: TObject);
    procedure Clear;
    class operator Initialize(var aGarbos: TGarbos);
    class operator Finalize(var aGarbos: TGarbos);
  end;

procedure GC<T: class>(out aInstance: T; aObj: T; var aGarbos: TGarbos); overload;
procedure GC(var aInstance; aObj: TObject; var aGarbos: TGarbos); overload;
procedure GC(aObj: TObject; var aGarbos: TGarbos); overload;

implementation

procedure TGarbos.Add(const aObj: TObject);
var
  lCount: Integer;
begin
  lCount := Length(fItems);
  SetLength(fItems, lCount + 1);
  fItems[lCount] := aObj;
end;

procedure TGarbos.Clear;
var
  i: Integer;
begin
  for i := High(fItems) downto 0 do fItems[i].Free;
  fItems := nil;
end;

class operator TGarbos.Initialize(var aGarbos: TGarbos);
begin
  aGarbos.fItems := nil;
end;

class operator TGarbos.Finalize(var aGarbos: TGarbos);
begin
  aGarbos.Clear;
end;

procedure GC<T>(out aInstance: T; aObj: T; var aGarbos: TGarbos);
begin
  aInstance := aObj;
  aGarbos.Add(aObj);
end;

procedure GC(aObj: TObject; var aGarbos: TGarbos);
begin
  aGarbos.Add(aObj);
end;

procedure GC(var aInstance; aObj: TObject; var aGarbos: TGarbos);
begin
  TObject(aInstance) := aObj;
  aGarbos.Add(aObj);
end;

end.

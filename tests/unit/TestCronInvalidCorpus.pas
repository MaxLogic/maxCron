unit TestCronInvalidCorpus;
{$I maxCron.inc}

interface

uses
  {$IFDEF FPC}
  Classes, SysUtils,
  DUnitX.TestFramework,
  maxCron
  {$ELSE}
  System.SysUtils, System.Classes,
  DUnitX.TestFramework,
  maxCron
  {$ENDIF};

type
  [TestFixture]
  TTestCronInvalidCorpus = class
  private
    function FindRepoRootDir: string;
    function LoadCorpusLines: TStringList;
  public
    [Test]
    procedure InvalidCorpus_RejectsAll;
  end;

implementation

function TTestCronInvalidCorpus.FindRepoRootDir: string;
var
  lDir: string;
  i: Integer;
begin
  lDir := ExcludeTrailingPathDelimiter({$IFDEF FPC}SysUtils.{$ENDIF}GetEnvironmentVariable('MAXCRON_TEST_ROOT'));
  if lDir <> '' then
  begin
    if not FileExists(lDir + PathDelim + 'maxCron.pas') or not FileExists(lDir + PathDelim + 'README.md') then
      raise Exception.Create('Invalid MAXCRON_TEST_ROOT (expected maxCron.pas + README.md).');
    Exit(lDir);
  end;
  lDir := ExcludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)));
  for i := 0 to 8 do
  begin
    if FileExists(lDir + PathDelim + 'maxCron.pas') and FileExists(lDir + PathDelim + 'README.md') then
      Exit(lDir);
    lDir := ExcludeTrailingPathDelimiter(ExtractFileDir(lDir));
  end;

  lDir := ExcludeTrailingPathDelimiter(GetCurrentDir);
  for i := 0 to 8 do
  begin
    if FileExists(lDir + PathDelim + 'maxCron.pas') and FileExists(lDir + PathDelim + 'README.md') then
      Exit(lDir);
    lDir := ExcludeTrailingPathDelimiter(ExtractFileDir(lDir));
  end;

  raise Exception.Create('Unable to locate repo root (expected maxCron.pas + README.md).');
end;

function TTestCronInvalidCorpus.LoadCorpusLines: TStringList;
var
  lFileName: string;
begin
  lFileName := FindRepoRootDir + PathDelim + 'tests' + PathDelim + 'data' + PathDelim + 'cron-invalid.txt';
  Result := TStringList.Create;
  Result.StrictDelimiter := True;
  Result.LineBreak := sLineBreak;
  Result.LoadFromFile(lFileName);
end;

procedure TTestCronInvalidCorpus.InvalidCorpus_RejectsAll;
var
  Lines: TStringList;
  i: Integer;
  Expr: string;
  Plan: TCronSchedulePlan;
  Raised: Boolean;
begin
  Lines := LoadCorpusLines;
  try
    Plan := TCronSchedulePlan.Create;
    try
      for i := 0 to Lines.Count - 1 do
      begin
        Expr := Trim(Lines[i]);
        if (Expr = '') or Expr.StartsWith('#') then
          Continue;

        Raised := False;
        try
          Plan.Parse(Expr);
        except
          on Exception do
            Raised := True;
        end;

        if not Raised then
          Assert.Fail(Format('Expected parse failure at line %d: %s', [i + 1, Expr]));
      end;
    finally
      Plan.Free;
    end;
  finally
    Lines.Free;
  end;
end;

end.


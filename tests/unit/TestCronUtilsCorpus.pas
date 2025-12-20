unit TestCronUtilsCorpus;

interface

uses
  System.DateUtils, System.SysUtils, System.Classes,
  DUnitX.TestFramework,
  maxCron;

type
  [TestFixture]
  TTestCronUtilsCorpus = class
  private
    function FindRepoRootDir: string;
    function LoadCorpusLines: TStringList;
    function IsNoNextScheduleExpr(const aExpr: string): Boolean;
  public
    [Test]
    procedure CronUtils_Unix5Field_Parses;

    [Test]
    procedure CronUtils_Unix5Field_NextSchedule_Sanity;
  end;

implementation

function TTestCronUtilsCorpus.FindRepoRootDir: string;
var
  lDir: string;
  i: Integer;
begin
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

function TTestCronUtilsCorpus.LoadCorpusLines: TStringList;
var
  lFileName: string;
begin
  lFileName := FindRepoRootDir + PathDelim + 'tests' + PathDelim + 'data' + PathDelim + 'cron-utils-unix-5field.txt';
  Result := TStringList.Create;
  Result.StrictDelimiter := True;
  Result.LineBreak := sLineBreak;
  Result.LoadFromFile(lFileName);
end;

function TTestCronUtilsCorpus.IsNoNextScheduleExpr(const aExpr: string): Boolean;
begin
  // Feb 30/31 never exists, and our year range is finite (<= 3000), so there is no next run.
  Result := (aExpr = '0 0 30 2 *') or (aExpr = '0 0 31 2 *');
end;

procedure TTestCronUtilsCorpus.CronUtils_Unix5Field_Parses;
var
  Lines: TStringList;
  i: Integer;
  Expr: string;
  Plan: TCronSchedulePlan;
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

        try
          Plan.Parse(Expr);
        except
          on E: Exception do
            Assert.Fail(Format('Corpus parse failed at line %d: %s (%s: %s)', [i + 1, Expr, E.ClassName, E.Message]));
        end;
      end;
    finally
      Plan.Free;
    end;
  finally
    Lines.Free;
  end;
end;

procedure TTestCronUtilsCorpus.CronUtils_Unix5Field_NextSchedule_Sanity;
var
  Lines: TStringList;
  i: Integer;
  Expr: string;
  Plan: TCronSchedulePlan;
  BaseDt: TDateTime;
  NextDt: TDateTime;
  HasNext: Boolean;
begin
  BaseDt := EncodeDateTime(2025, 1, 1, 0, 0, 0, 0);

  Lines := LoadCorpusLines;
  try
    Plan := TCronSchedulePlan.Create;
    try
      for i := 0 to Lines.Count - 1 do
      begin
        Expr := Trim(Lines[i]);
        if (Expr = '') or Expr.StartsWith('#') then
          Continue;

        Plan.Parse(Expr);
        HasNext := Plan.FindNextScheduleDate(BaseDt, NextDt);

        if IsNoNextScheduleExpr(Expr) then
          Assert.IsFalse(HasNext, 'Expected no next schedule: ' + Expr)
        else
        begin
          Assert.IsTrue(HasNext, 'Expected next schedule: ' + Expr);
          Assert.IsTrue(NextDt > BaseDt, 'Expected NextDt > BaseDt for: ' + Expr);
        end;
      end;
    finally
      Plan.Free;
    end;
  finally
    Lines.Free;
  end;
end;

end.

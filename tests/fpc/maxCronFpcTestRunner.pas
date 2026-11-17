unit maxCronFpcTestRunner;
{$I maxCron.inc}

interface

type
  TFpcTestProc = procedure;

procedure RegisterFixture(const aFixture: TObject);
procedure RegisterTest(const aName, aFixture: string; const aProc: TFpcTestProc);
function RunTests(const aExpectedCount: Integer): Integer;

implementation

uses
  SysUtils, DUnitX.TestFramework;

type
  TFpcTest = record
    Name, Fixture: string;
    Proc: TFpcTestProc;
  end;
var
  gTests: array of TFpcTest;
  gFixtures: array of TObject;

procedure RegisterFixture(const aFixture: TObject);
var
  i: Integer;
begin
  i := Length(gFixtures);
  SetLength(gFixtures, i + 1);
  gFixtures[i] := aFixture;
end;

procedure RegisterTest(const aName, aFixture: string; const aProc: TFpcTestProc);
var
  i: Integer;
begin
  if not Assigned(aProc) then raise Exception.Create('Missing test procedure');
  i := Length(gTests);
  SetLength(gTests, i + 1);
  gTests[i].Name := aName;
  gTests[i].Fixture := aFixture;
  gTests[i].Proc := aProc;
end;

procedure Summary(const aFound, aPassed, aFailed, aErrored: Integer);
begin
  WriteLn('Tests Found   : ', aFound);
  WriteLn('Tests Ignored : 0');
  WriteLn('Tests Passed  : ', aPassed);
  WriteLn('Tests Leaked  : not measured (heaptrc checks the process at exit)');
  WriteLn('Tests Failed  : ', aFailed);
  WriteLn('Tests Errored : ', aErrored);
end;

function RunTests(const aExpectedCount: Integer): Integer;
var
  i, lPassed, lFailed, lErrored, lFixtureCount, lFixturePassed: Integer;
  lFixture: string;
begin
  lPassed := 0;
  lFailed := 0;
  lErrored := 0;
  lFixtureCount := 0;
  lFixturePassed := 0;
  lFixture := '';
  try
    for i := 0 to High(gTests) do
    begin
      if gTests[i].Fixture <> lFixture then
      begin
        if lFixture <> '' then
          WriteLn('FIXTURE ', lFixture, ' found=', lFixtureCount, ' passed=', lFixturePassed);
        lFixture := gTests[i].Fixture;
        lFixtureCount := 0;
        lFixturePassed := 0;
      end;
      Inc(lFixtureCount);
      try
        gTests[i].Proc;
        Inc(lPassed);
        Inc(lFixturePassed);
      except
        on E: ETestFailure do
        begin
          Inc(lFailed);
          WriteLn('FAIL  ', gTests[i].Name, ': ', string(E.Message));
        end;
        on E: Exception do
        begin
          Inc(lErrored);
          WriteLn('ERROR ', gTests[i].Name, ': ', string(E.ClassName), ': ', string(E.Message));
        end;
      end;
    end;
    if lFixture <> '' then
      WriteLn('FIXTURE ', lFixture, ' found=', lFixtureCount, ' passed=', lFixturePassed);
    Summary(Length(gTests), lPassed, lFailed, lErrored);
    if (Length(gTests) = 0) or (Length(gTests) <> aExpectedCount) or (lPassed <> Length(gTests)) then
      Result := 1
    else
      Result := 0;
  except
    on E: Exception do
    begin
      WriteLn('RUNNER ERROR ', string(E.ClassName), ': ', string(E.Message));
      Result := 2;
    end;
  end;
end;

procedure FreeFixtures;
var
  i: Integer;
begin
  for i := High(gFixtures) downto 0 do gFixtures[i].Free;
  gFixtures := nil;
  gTests := nil;
end;

finalization
  FreeFixtures;
end.

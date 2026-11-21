unit DelphiRoster;

interface

uses
  DUnitX.TestFramework;

function ExecuteRoster(const aRunner: ITestRunner): IRunResults;

implementation

uses
  System.Classes, System.SysUtils,
  DUnitX.Extensibility,
  TestRoster;

procedure CollectNames(const aFixture: ITestFixture; const aNames: TStrings);
var
  lChild: ITestFixture;
  lTest: ITest;
begin
  for lTest in aFixture.Tests do aNames.Add(lTest.FullName);
  for lChild in aFixture.Children do CollectNames(lChild, aNames);
end;

function ExecuteRoster(const aRunner: ITestRunner): IRunResults;
var
  lFixture: ITestFixture;
  lFixtures: ITestFixtureList;
  lNames: TStringList;
  lResult: ITestResult;
begin
  lNames := TStringList.Create;
  try
    lFixtures := aRunner.BuildFixtures as ITestFixtureList;
    for lFixture in lFixtures do CollectNames(lFixture, lNames);
    lFixture := nil;
    lFixtures := nil;
    CheckRosterNames(lNames.ToStringArray);
  finally
    lNames.Free;
  end;
  Result := aRunner.Execute;
  for lResult in Result.GetAllTestResults do RecordRosterTest(lResult.Test.FullName);
  if Result.MemoryLeakCount <> 0 then raise Exception.Create('Test roster has memory leaks');
  EndRoster(Result.TestCount, Result.PassCount, Result.FailureCount, Result.ErrorCount, Result.IgnoredCount);
end;

end.

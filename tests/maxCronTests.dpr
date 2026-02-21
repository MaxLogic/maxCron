program maxCronTests;

{$APPTYPE CONSOLE}

{$DEFINE MAXCRON_TESTS}

uses
  System.SysUtils,
  DUnitX.TestFramework,
  DUnitX.Loggers.Console,
  DUnitX.RunResults,
  maxCron in '..\maxCron.pas',
  TestCronInvalidCorpus in 'unit\TestCronInvalidCorpus.pas',
  TestCronParsing in 'unit\TestCronParsing.pas',
  TestCronUtilsCorpus in 'unit\TestCronUtilsCorpus.pas',
  TestCalendarTimeZone in 'unit\TestCalendarTimeZone.pas',
  TestDispatchStartFailures in 'unit\TestDispatchStartFailures.pas',
  TestExecutionLimit in 'unit\TestExecutionLimit.pas',
  TestHashJitter in 'unit\TestHashJitter.pas',
  TestInvokeModes in 'unit\TestInvokeModes.pas',
  TestLifecycle in 'unit\TestLifecycle.pas',
  TestMisfirePolicy in 'unit\TestMisfirePolicy.pas',
  TestMaxCron in 'unit\TestMaxCron.pas',
  TestRobustCoverage in 'unit\TestRobustCoverage.pas',
  TestReviewFindings in 'unit\TestReviewFindings.pas',
  TestScheduleNext in 'unit\TestScheduleNext.pas',
  TestStress in 'unit\TestStress.pas',
  TestValidRange in 'unit\TestValidRange.pas';

var
  Runner: ITestRunner;
  Results: IRunResults;
begin
  ReportMemoryLeaksOnShutdown := True;
  try
    TDUnitX.CheckCommandLine;
    TDUnitX.RegisterTestFixture(TTestCronInvalidCorpus);
    TDUnitX.RegisterTestFixture(TTestCronParsing);
    TDUnitX.RegisterTestFixture(TTestCronUtilsCorpus);
    TDUnitX.RegisterTestFixture(TTestCalendarTimeZone);
    TDUnitX.RegisterTestFixture(TTestDispatchStartFailures);
    TDUnitX.RegisterTestFixture(TTestExecutionLimit);
    TDUnitX.RegisterTestFixture(TTestHashJitter);
    TDUnitX.RegisterTestFixture(TTestInvokeModes);
    TDUnitX.RegisterTestFixture(TTestLifecycle);
    TDUnitX.RegisterTestFixture(TTestMisfirePolicy);
    TDUnitX.RegisterTestFixture(TTestMaxCron);
    TDUnitX.RegisterTestFixture(TTestRobustCoverage);
    TDUnitX.RegisterTestFixture(TTestReviewFindings);
    TDUnitX.RegisterTestFixture(TTestScheduleNext);
    TDUnitX.RegisterTestFixture(TTestStress);
    TDUnitX.RegisterTestFixture(TTestValidRange);
    Runner := TDUnitX.CreateRunner;
    Runner.UseRTTI := True;
    Runner.AddLogger(TDUnitXConsoleLogger.Create(True));
    Results := Runner.Execute;
    if not Results.AllPassed then
      ExitCode := 1;
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      ExitCode := 2;
    end;
  end;
end.

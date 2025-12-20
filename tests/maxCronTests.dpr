program maxCronTests;

{$APPTYPE CONSOLE}

{$DEFINE MAXCRON_TESTS}

uses
  System.SysUtils,
  DUnitX.TestFramework,
  DUnitX.Loggers.Console,
  DUnitX.RunResults,
  maxCron in '..\maxCron.pas',
  TestCronParsing in 'unit\TestCronParsing.pas',
  TestCronUtilsCorpus in 'unit\TestCronUtilsCorpus.pas',
  TestExecutionLimit in 'unit\TestExecutionLimit.pas',
  TestInvokeModes in 'unit\TestInvokeModes.pas',
  TestLifecycle in 'unit\TestLifecycle.pas',
  TestMaxCron in 'unit\TestMaxCron.pas',
  TestScheduleNext in 'unit\TestScheduleNext.pas',
  TestValidRange in 'unit\TestValidRange.pas';

var
  Runner: ITestRunner;
  Results: IRunResults;
begin
  ReportMemoryLeaksOnShutdown := True;
  try
    TDUnitX.CheckCommandLine;
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

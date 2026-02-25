program maxCronStressTests;

{$APPTYPE CONSOLE}

{$DEFINE MAXCRON_TESTS}

uses
  System.SysUtils,
  DUnitX.TestFramework,
  DUnitX.Loggers.Console,
  DUnitX.RunResults,
  maxCron in '..\maxCron.pas',
  TestGlobalLimits in 'unit\TestGlobalLimits.pas',
  TestHeavyStress in 'unit\TestHeavyStress.pas',
  TestHeavyStressMixed in 'unit\TestHeavyStressMixed.pas',
  TestLongSoak24h in 'unit\TestLongSoak24h.pas',
  TestWatchdogDiagnostics in 'unit\TestWatchdogDiagnostics.pas';

var
  Runner: ITestRunner;
  Results: IRunResults;
begin
  ReportMemoryLeaksOnShutdown := True;
  try
    TDUnitX.CheckCommandLine;
    TDUnitX.RegisterTestFixture(TTestGlobalLimits);
    TDUnitX.RegisterTestFixture(TTestHeavyStress);
    TDUnitX.RegisterTestFixture(TTestHeavyStressMixed);
    TDUnitX.RegisterTestFixture(TTestLongSoak24h);
    TDUnitX.RegisterTestFixture(TTestWatchdogDiagnostics);
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

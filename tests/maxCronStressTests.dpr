program maxCronStressTests;

{$APPTYPE CONSOLE}

{$DEFINE MAXCRON_TESTS}

uses
  System.SysUtils,
  DUnitX.TestFramework,
  DUnitX.Loggers.Console,
  DUnitX.RunResults,
  maxCron.Internal.DeadlineQueue in '..\maxCron.Internal.DeadlineQueue.pas',
  maxCron.Internal.Platform in '..\maxCron.Internal.Platform.pas',
  maxCron.Internal.Text in '..\maxCron.Internal.Text.pas',
  maxCron.Internal.TimeZone in '..\maxCron.Internal.TimeZone.pas',
  maxCron.Internal.TZif in '..\maxCron.Internal.TZif.pas',
  maxCron.Plan in '..\maxCron.Plan.pas',
  maxCron in '..\maxCron.pas',
  TestGlobalLimits in 'unit\TestGlobalLimits.pas',
  TestHeavyStress in 'unit\TestHeavyStress.pas',
  TestHeavyStressMixed in 'unit\TestHeavyStressMixed.pas',
  TestLongSoak24h in 'unit\TestLongSoak24h.pas',
  TestWatchdogDiagnostics in 'unit\TestWatchdogDiagnostics.pas',
  TestCronPhaseDifferential in 'unit\TestCronPhaseDifferential.pas',
  TestDeadlineTimerStress in 'unit\TestDeadlineTimerStress.pas';

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
    TDUnitX.RegisterTestFixture(TTestCronPhaseDifferential);
    TDUnitX.RegisterTestFixture(TTestDeadlineTimerStress);
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

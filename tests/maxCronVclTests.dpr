program maxCronVclTests;

{$APPTYPE GUI}

uses
  Vcl.Forms,
  System.SysUtils,
  DUnitX.Loggers.Console,
  DUnitX.RunResults,
  DUnitX.TestFramework,
  DelphiRoster in 'DelphiRoster.pas',
  TestRoster in 'TestRoster.pas',
  maxCron.Internal.DeadlineQueue in '..\maxCron.Internal.DeadlineQueue.pas',
  maxCron.Internal.Platform in '..\maxCron.Internal.Platform.pas',
  maxCron.Internal.Text in '..\maxCron.Internal.Text.pas',
  maxCron.Internal.TimeZone in '..\maxCron.Internal.TimeZone.pas',
  maxCron.Internal.TZif in '..\maxCron.Internal.TZif.pas',
  maxCron.Plan in '..\maxCron.Plan.pas',
  maxCron in '..\maxCron.pas',
  TestVclBackend in 'unit\TestVclBackend.pas',
  TestVclDeadline in 'unit\TestVclDeadline.pas';

var
  Runner: ITestRunner;
  Results: IRunResults;
begin
  ReportMemoryLeaksOnShutdown := True;
  Application.Initialize;
  try
    BeginRoster('DelphiVcl');
    TDUnitX.CheckCommandLine;
    TDUnitX.RegisterTestFixture(TTestVclBackend);
    TDUnitX.RegisterTestFixture(TTestVclDeadline);
    Runner := TDUnitX.CreateRunner;
    Runner.UseRTTI := True;
    Runner.AddLogger(TDUnitXConsoleLogger.Create(True));
    Results := ExecuteRoster(Runner);
    if not Results.AllPassed then
      ExitCode := 1;
  except
    on E: Exception do
    begin
      // no console by default; still useful when run as a console-hosted process in CI/IDE
      ExitCode := ReportRosterFailure(E);
    end;
  end;
end.

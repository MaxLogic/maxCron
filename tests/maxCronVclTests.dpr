program maxCronVclTests;

{$APPTYPE GUI}

uses
  Vcl.Forms,
  System.SysUtils,
  DUnitX.TestFramework,
  DUnitX.Loggers.Console,
  DUnitX.RunResults,
  maxCron in '..\maxCron.pas',
  TestVclBackend in 'unit\TestVclBackend.pas';

var
  Runner: ITestRunner;
  Results: IRunResults;
begin
  ReportMemoryLeaksOnShutdown := True;
  Application.Initialize;
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
      // no console by default; still useful when run as a console-hosted process in CI/IDE
      Writeln(E.ClassName, ': ', E.Message);
      ExitCode := 2;
    end;
  end;
end.


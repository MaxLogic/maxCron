program CronDemo;

uses
  Vcl.Forms,
  CronDemoMainForm in 'CronDemoMainForm.pas' {Form2},
  maxCron.Internal.DeadlineQueue in '..\maxCron.Internal.DeadlineQueue.pas',
  maxCron.Internal.Platform in '..\maxCron.Internal.Platform.pas',
  maxCron.Internal.Text in '..\maxCron.Internal.Text.pas',
  maxCron.Internal.TimeZone in '..\maxCron.Internal.TimeZone.pas',
  maxCron.Internal.TZif in '..\maxCron.Internal.TZif.pas',
  maxCron.Plan in '..\maxCron.Plan.pas',
  maxCron in '..\maxCron.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TForm2, Form2);
  Application.Run;
end.

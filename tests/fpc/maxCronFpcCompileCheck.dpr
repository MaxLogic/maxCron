program maxCronFpcCompileCheck;
{$I maxCron.inc}

uses
  {$IFDEF UNIX}cthreads, cwstring,{$ENDIF}
  maxCron in '..\..\maxCron.pas',
  maxCron.Internal.DeadlineQueue in '..\..\maxCron.Internal.DeadlineQueue.pas',
  maxCron.Internal.Platform in '..\..\maxCron.Internal.Platform.pas',
  maxCron.Internal.Text in '..\..\maxCron.Internal.Text.pas',
  maxCron.Internal.TimeZone in '..\..\maxCron.Internal.TimeZone.pas',
  maxCron.Internal.TZif in '..\..\maxCron.Internal.TZif.pas',
  maxCron.Plan in '..\..\maxCron.Plan.pas';

begin
  WriteLn('maxCron FPC compile check');
end.

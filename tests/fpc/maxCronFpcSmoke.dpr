program maxCronFpcSmoke;
{$I maxCron.inc}

uses
  Classes, SyncObjs, System.Diagnostics, SysUtils,
  maxCron,
  TestRoster in '..\TestRoster.pas';

var
  gFound, gPassed: Integer;

procedure Check(const aCondition: Boolean; const aName: string);
begin
  RecordRosterTest('smoke.' + aName);
  Inc(gFound);
  if aCondition then Inc(gPassed)
  else WriteLn('FAIL  smoke.', aName);
end;

procedure PumpFor(const aMilliseconds: Int64);
var
  lWatch: TStopwatch;
begin
  lWatch := TStopwatch.StartNew;
  while lWatch.ElapsedMilliseconds < aMilliseconds do CheckSynchronize(10);
end;

procedure SmokeMode(const aMode: TmaxCronInvokeMode);
var
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lCallback, lIntervalCallback: TmaxCronNotifyProc;
  lCount, lIntervals, lAfterFree: Integer;
  lPrefix: string;
begin
  lCount := 0;
  lIntervals := 0;
  lPrefix := string(IntToStr(Ord(aMode))) + '.';
  lCallback := procedure(aSender: IMaxCronEvent)
    begin
      TInterlocked.Increment(lCount);
    end;
  lIntervalCallback := procedure(aSender: IMaxCronEvent)
    begin
      TInterlocked.Increment(lIntervals);
    end;
  lCron := TmaxCron.Create(ctPortable);
  try
    lEvent := lCron.Add('cron', '* * * * * * *', lCallback);
    lEvent.InvokeMode := aMode;
    lEvent.Run;
    lEvent := lCron.AddInterval('interval', 50, lIntervalCallback);
    lEvent.InvokeMode := aMode;
    lEvent.Run;
    PumpFor(3500);
    Check(TInterlocked.CompareExchange(lCount, 0, 0) >= 2, lPrefix + 'cron-fires');
    Check(TInterlocked.CompareExchange(lIntervals, 0, 0) >= 40, lPrefix + 'interval-fires');
    Check(lCron.Shutdown(5000), lPrefix + 'shutdown');
    lEvent := nil;
  finally
    lCron.Free;
  end;
  lAfterFree := TInterlocked.CompareExchange(lCount, 0, 0) + TInterlocked.CompareExchange(lIntervals, 0, 0);
  PumpFor(300);
  Check(lAfterFree = TInterlocked.CompareExchange(lCount, 0, 0) +
    TInterlocked.CompareExchange(lIntervals, 0, 0), lPrefix + 'post-free-silence');
  lCallback := nil;
  lIntervalCallback := nil;
  WriteLn('MODE ', Ord(aMode), ' cron=', lCount, ' interval=', lIntervals);
end;

begin
  try
    {$IFDEF MAXCRON_FPC_SMOKE_NOPOOL}
    BeginRoster('FpcSmokeHeap');
    {$ELSE}
    BeginRoster('FpcSmoke');
    {$ENDIF}
    SmokeMode(imMainThread);
    {$IFNDEF MAXCRON_FPC_SMOKE_NOPOOL}
    SmokeMode(imMaxAsync);
    SmokeMode(imTTask);
    {$ENDIF}
    SmokeMode(imThread);
  except
    on E: Exception do
    begin
      Halt(ReportRosterFailure(E));
    end;
  end;
  WriteLn('Tests Found   : ', gFound);
  WriteLn('Tests Ignored : 0');
  WriteLn('Tests Passed  : ', gPassed);
  WriteLn('Tests Leaked  : not measured (heaptrc checks the process at exit)');
  WriteLn('Tests Failed  : ', gFound - gPassed);
  WriteLn('Tests Errored : 0');
  try
    EndRoster(gFound, gPassed, gFound - gPassed, 0, 0);
  except
    on E: Exception do
    begin
      Halt(ReportRosterFailure(E));
    end;
  end;
  if (gFound = 0) or (gFound <> gPassed) then ExitCode := 1;
end.

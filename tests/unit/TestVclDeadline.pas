unit TestVclDeadline;

interface

uses
  System.Classes, System.DateUtils, System.Diagnostics, System.SysUtils,
  Winapi.Windows,
  Vcl.Forms,
  DUnitX.TestFramework,
  maxCron, maxCron.Internal.Platform;

type
  [TestFixture]
  TTestVclDeadline = class
  public
    [Test] procedure AlignedMainThread;
    [Test] procedure IntervalMainThread;
    [Test] procedure BlockedMainThreadDoesNotSpin;
  end;

implementation

function CpuUs: Int64;
var lCreated, lExited, lKernel, lUser: TFileTime;
begin
  if not GetProcessTimes(GetCurrentProcess, lCreated, lExited, lKernel, lUser) then RaiseLastOSError;
  Result := (Int64(lKernel.dwHighDateTime) shl 32 or lKernel.dwLowDateTime) div 10 +
    (Int64(lUser.dwHighDateTime) shl 32 or lUser.dwLowDateTime) div 10;
end;

procedure TTestVclDeadline.AlignedMainThread;
var
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lCount: Integer;
  lBad: Boolean;
  lClock: TStopwatch;
begin
  lCount := 0; lBad := False;
  lCron := TmaxCron.Create(ctVcl);
  try
    lEvent := lCron.Add('aligned-vcl', '* * * * * * * 1',
      procedure(aSender: IMaxCronEvent)
      var lDelay: Double;
      begin
        lDelay := (CronPreciseLocalNowUs / Double(86400000000.0) - aSender.LastExecution) * MSecsPerDay;
        lBad := (TThread.CurrentThread.ThreadID <> MainThreadID) or (lDelay < 0) or (lDelay >= 250);
        Inc(lCount);
      end);
    lEvent.InvokeMode := imMainThread; lEvent.Run;
    lClock := TStopwatch.StartNew;
    while (lCount = 0) and (lClock.ElapsedMilliseconds < 2500) do
    begin
      Application.ProcessMessages;
      CheckSynchronize(0);
      TThread.Sleep(1);
    end;
    Assert.AreEqual(1, lCount);
    Assert.IsFalse(lBad, 'Aligned callback on main thread');
  finally lCron.Free;
    end;
end;

procedure TTestVclDeadline.BlockedMainThreadDoesNotSpin;
var
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lStartedUs, lCpu: Int64;
  lCount: Integer;
begin
  lCount := 0;
  lCron := TmaxCron.Create(ctVcl);
  try
    lEvent := lCron.Add('blocked-vcl', '* * * * * * * 0',
      procedure(aSender: IMaxCronEvent) begin Inc(lCount); end);
    lEvent.InvokeMode := imMainThread; lEvent.Run;
    // Reach a due boundary without pumping the main thread. The queued tick stays pending.
    lStartedUs := CronPreciseLocalNowUs;
    TThread.Sleep(Cardinal(1100 - (lStartedUs mod 1000000) div 1000));
    lCpu := CpuUs;
    TThread.Sleep(500);
    lCpu := CpuUs - lCpu;
    Assert.AreEqual(0, lCount, 'No callback without pump');
    Assert.IsTrue(lCpu < 50000, 'Queued tick must not spin while main thread is blocked');
    Application.ProcessMessages; CheckSynchronize(0);
    Assert.IsTrue(lCount > 0, 'Queued tick delivered when pumping resumes');
  finally lCron.Free;
    end;
end;

procedure TTestVclDeadline.IntervalMainThread;
var
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lCount: Integer;
  lBad: Boolean;
  lWatch: TStopwatch;
  lCpu: Int64;
begin
  lCron := TmaxCron.Create(ctVcl); lCount := 0; lBad := False;
  try
    lEvent := lCron.AddInterval('interval vcl',50,
      procedure(aSender: IMaxCronEvent)
      begin
        Inc(lCount);
        if TThread.CurrentThread.ThreadID<>MainThreadID then lBad := True;
      end);
    lEvent.InvokeMode := imMainThread; lEvent.Run;
    lWatch := TStopwatch.StartNew;
    while lWatch.ElapsedMilliseconds<1000 do
    begin
      Application.ProcessMessages; CheckSynchronize(0); TThread.Sleep(1);
    end;
    lEvent.Stop;
    Assert.IsFalse(lBad);
    Assert.IsTrue((lCount>=15) and (lCount<=21),'VCL interval count '+IntToStr(lCount));
    lEvent.Run; TThread.Sleep(100); lCpu := CpuUs;
    TThread.Sleep(500); lCpu := CpuUs-lCpu;
    Assert.IsTrue(lCpu<50000,'due interval must not spin behind queued VCL tick');
    lEvent.Stop;
  finally lEvent := nil; lCron.Free; end;
end;

end.

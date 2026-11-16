unit TestDeadlineTimer;

interface

uses
  System.Classes, System.DateUtils, System.Diagnostics, System.SyncObjs, System.SysUtils,
  Winapi.Windows,
  DUnitX.TestFramework,
  maxCron, maxCron.Internal.Platform;

type
  [TestFixture]
  TTestDeadlineTimer = class
  public
    [TestCase('high', 'high,10')]
    [TestCase('period', 'period,10')]
    [TestCase('default', 'default,40')]
    procedure CronAlignment(const aMode: string; const aMedianBound: Integer);
    [Test] procedure PreciseResetAndTickAt;
    [Test] procedure WallJumps;

  end;

implementation

procedure TTestDeadlineTimer.CronAlignment(const aMode: string; const aMedianBound: Integer);
var
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lDone: TEvent;
  lCount, lBad: Integer;
  lSamples: array[0..2] of Double;
  lOldMode: string;
  lTicks, lSpin, lExceptions: UInt64;
  lTemp: Double;
  i, j: Integer;
  lWatch: TStopwatch;
begin
  // Deliberately start the old one-second timer far from a second boundary.
  lWatch := TStopwatch.StartNew;
  while (MilliSecondOf(Now) < 450) or (MilliSecondOf(Now) > 550) do
  begin
    TThread.Sleep(1);
    Assert.IsTrue(lWatch.ElapsedMilliseconds < 2000, 'Could not select start phase');
  end;
  lOldMode := GetEnvironmentVariable('MAXCRON_TIMER_RESOLUTION');
  Winapi.Windows.SetEnvironmentVariable('MAXCRON_TIMER_RESOLUTION', PChar(aMode));
  lCron := TmaxCron.Create(ctPortable);
  lDone := TEvent.Create(nil, True, False, '');
  lCount := 0;
  lBad := 0;
  try
    lEvent := lCron.Add('alignment', '* * * * * * * 3',
      procedure(aSender: IMaxCronEvent)
      var
        lDelay: Double;
      begin
        lDelay := (CronPreciseLocalNowUs / Double(86400000000.0) - aSender.LastExecution) * MSecsPerDay;
        if (lDelay < 0) or (lDelay >= 250) then
          TInterlocked.Exchange(lBad, 1);
        lSamples[lCount] := lDelay;
        if TInterlocked.Increment(lCount) = 3 then
          lDone.SetEvent;
      end);
    lEvent.InvokeMode := imTTask;
    lEvent.Run;
    lCron.StartTimerForTests(1000);
    Assert.AreEqual(wrSignaled, lDone.WaitFor(5000), 'Three cron callbacks');
    Assert.IsTrue(lCron.Shutdown(3000), 'Callbacks drained');
    Assert.AreEqual(0, TInterlocked.CompareExchange(lBad, 0, 0), 'Cron callback must be in due second and <250ms late');
    Assert.AreEqual(3, lCount);
    for i := 0 to 1 do
      for j := i + 1 to 2 do
        if lSamples[j] < lSamples[i] then
        begin
          lTemp := lSamples[i]; lSamples[i] := lSamples[j]; lSamples[j] := lTemp;
        end;
    Assert.IsTrue(lSamples[1] <= aMedianBound, 'Median firing lateness');
    lCron.GetTimerDiagnosticsForTests(lTicks, lSpin, lExceptions);
    Assert.IsTrue(lTicks >= 3);
    Assert.AreEqual(UInt64(0), lSpin);
    Assert.AreEqual(UInt64(0), lExceptions);
    if aMode = 'high' then
      Assert.AreEqual(trHighResolution, lCron.ActiveTimerResolution)
    else if aMode = 'period' then
      Assert.AreEqual(trTimerPeriod, lCron.ActiveTimerResolution)
    else
      Assert.AreEqual(trSystemDefault, lCron.ActiveTimerResolution);
  finally
    lCron.Free;
    lDone.Free;
    Winapi.Windows.SetEnvironmentVariable('MAXCRON_TIMER_RESOLUTION', PChar(lOldMode));
  end;
end;

procedure TTestDeadlineTimer.PreciseResetAndTickAt;
var
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lWallUs: Int64;
  lCount: Integer;
begin
  lWallUs := Round(EncodeDateTime(2026, 6, 15, 10, 0, 0, 0) * 86400000000.0) + 5000;
  SetMaxCronWallClockHook(function: Int64 begin Result := lWallUs; end);
  lCron := nil;
  try
    lCron := TmaxCron.Create(ctPortable);
    lCount := 0;
    lEvent := lCron.Add('precise', '* * * * * * * 0',
      procedure(aSender: IMaxCronEvent) begin Inc(lCount); end);
    lEvent.InvokeMode := imMainThread;
    lEvent.Run;
    Assert.AreEqual(EncodeDateTime(2026, 6, 15, 10, 0, 1, 0), lEvent.NextSchedule, 0.0);
    lCron.TickAt(EncodeDateTime(2026, 6, 15, 10, 0, 1, 0));
    Assert.AreEqual(1, lCount, 'TickAt remains an explicit cron pass');
  finally
    lCron.Free;
    SetMaxCronWallClockHook(nil);
  end;
end;

function DatedPlan(const aAfterUs: Int64): string;
var lDue: TDateTime;
begin
  lDue := (CronPreciseLocalNowUs + aAfterUs) / Double(86400000000.0);
  Result := Format('%d %d %d %d * %d %d 1', [MinuteOf(lDue), HourOf(lDue),
    DayOf(lDue), MonthOf(lDue), YearOf(lDue), SecondOf(lDue)]);
end;

procedure TTestDeadlineTimer.WallJumps;
var
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lOffsetUs: Int64;
  lDone: TEvent;
  lTicks, lSpin, lExceptions: UInt64;
begin
  lOffsetUs := 0;
  SetMaxCronWallClockHook(function: Int64
    begin Result := CronPreciseLocalNowUs + TInterlocked.Read(lOffsetUs); end);
  lCron := nil;
  lDone := TEvent.Create(nil, True, False, '');
  try
    lCron := TmaxCron.Create(ctPortable);
    lCron.DefaultMisfirePolicy := TmaxCronMisfirePolicy.mpCatchUpAll;
    lEvent := lCron.Add('jumps', DatedPlan(2000000),
      procedure(aSender: IMaxCronEvent) begin lDone.SetEvent; end);
    lEvent.InvokeMode := imTTask;
    lEvent.Run;
    lCron.StartTimerForTests(1000);
    // A backwards wall jump must postpone the occurrence, regardless of QPC.
    TInterlocked.Exchange(lOffsetUs, -Int64(3600) * 1000000);
    Assert.AreEqual(wrTimeout, lDone.WaitFor(3000), 'No fire during backwards jump');
    TInterlocked.Exchange(lOffsetUs, 0);
    Assert.AreEqual(wrSignaled, lDone.WaitFor(1500), 'Returning wall time resumes cron');
    Assert.IsTrue(lCron.Shutdown(3000));
    lCron.Free;
    lCron := nil;
    lDone.ResetEvent;
    lCron := TmaxCron.Create(ctPortable);
    lCron.DefaultMisfirePolicy := TmaxCronMisfirePolicy.mpCatchUpAll;
    lEvent := lCron.Add('forward', DatedPlan(3000000),
      procedure(aSender: IMaxCronEvent) begin lDone.SetEvent; end);
    lEvent.InvokeMode := imTTask;
    lEvent.Run;
    lCron.StartTimerForTests(1000);
    TInterlocked.Exchange(lOffsetUs, Int64(3600) * 1000000);
    Assert.AreEqual(wrSignaled, lDone.WaitFor(1500), 'Forward jump noticed within bounded sleep');
    Assert.IsTrue(lCron.Shutdown(3000));
    lCron.GetTimerDiagnosticsForTests(lTicks, lSpin, lExceptions);
    Assert.AreEqual(UInt64(0), lSpin);
    Assert.AreEqual(UInt64(0), lExceptions);
  finally
    lCron.Free;
    lDone.Free;
    SetMaxCronWallClockHook(nil);
  end;
end;


end.

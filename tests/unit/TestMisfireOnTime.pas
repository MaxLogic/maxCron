unit TestMisfireOnTime;

interface

uses
  System.DateUtils, System.SysUtils,
  Winapi.Windows,
  AutoFree, DUnitX.TestFramework,
  maxCron;

type
  [TestFixture]
  TTestMisfireOnTime = class
  public
    [TestCase('scan early', 'scan,-1,0,0')]
    [TestCase('scan due', 'scan,0,1,0')]
    [TestCase('scan phase', 'scan,700,1,0')]
    [TestCase('scan 999ms', 'scan,999,1,0')]
    [TestCase('scan 1000ms', 'scan,1000,0,0')]
    [TestCase('scan 1001ms', 'scan,1001,0,0')]
    [TestCase('scan overdue', 'scan,10000,0,0')]
    [TestCase('scan one shot', 'scan,700,1,1')]
    [TestCase('heap early', 'heap,-1,0,0')]
    [TestCase('heap due', 'heap,0,1,0')]
    [TestCase('heap phase', 'heap,700,1,0')]
    [TestCase('heap 999ms', 'heap,999,1,0')]
    [TestCase('heap 1000ms', 'heap,1000,0,0')]
    [TestCase('heap 1001ms', 'heap,1001,0,0')]
    [TestCase('heap overdue', 'heap,10000,0,0')]
    [TestCase('heap one shot', 'heap,700,1,1')]
    procedure DueSecondBoundary(const aEngine: string; const aLatenessMs, aExpectedFires, aLimit: Integer);
    [TestCase('scan generated 999ms', 'scan,999,1')]
    [TestCase('scan generated 1000ms', 'scan,1000,0')]
    [TestCase('heap generated 999ms', 'heap,999,1')]
    [TestCase('heap generated 1000ms', 'heap,1000,0')]
    procedure GeneratedDueInstants(const aEngine: string; const aLatenessMs, aExpectedFires: Integer);
  end;

implementation

procedure TTestMisfireOnTime.DueSecondBoundary(const aEngine: string;
  const aLatenessMs, aExpectedFires, aLimit: Integer);
var
  g: TGarbos;
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lDue, lTick: TDateTime;
  lCount: Integer;
  lOldEngine: string;
begin
  lOldEngine := GetEnvironmentVariable('MAXCRON_ENGINE');
  Winapi.Windows.SetEnvironmentVariable('MAXCRON_ENGINE', PChar(aEngine));
  try
    GC(lCron, TmaxCron.Create(ctPortable), g);
    lCron.DefaultMisfirePolicy := TmaxCronMisfirePolicy.mpSkip;
    lCount := 0;
    lEvent := lCron.Add('DueSecondBoundary');
    lEvent.EventPlan := '* * * * * * * ' + IntToStr(aLimit);
    lEvent.InvokeMode := imMainThread;
    lEvent.OnScheduleProc :=
      procedure(aSender: IMaxCronEvent)
      begin
        Inc(lCount);
      end;
    lEvent.Run;
    lDue := lEvent.NextSchedule;
    lTick := IncMilliSecond(lDue, aLatenessMs);
    lCron.TickAt(lTick);

    Assert.AreEqual(aExpectedFires, lCount, 'mpSkip due-second dispatch count');
    if aExpectedFires > 0 then
      Assert.AreEqual(lDue, lEvent.LastExecution, 'LastExecution must retain the due time');
    if aLatenessMs < 0 then
      Assert.AreEqual(lDue, lEvent.NextSchedule, 'An early tick must not advance the schedule')
    else if aLimit = 0 then
      Assert.IsTrue(lEvent.NextSchedule > lTick, 'The schedule must advance past the processed tick');

    lCron.TickAt(lTick);
    Assert.AreEqual(aExpectedFires, lCount, 'The same occurrence must not dispatch twice');
    if aLimit > 0 then
    begin
      lCron.TickAt(lEvent.NextSchedule);
      Assert.AreEqual(aExpectedFires, lCount, 'The execution limit must prevent the next callback');
      Assert.IsFalse(lEvent.Enabled, 'The one-shot execution limit still applies');
    end;
  finally
    g.Clear;
    Winapi.Windows.SetEnvironmentVariable('MAXCRON_ENGINE', PChar(lOldEngine));
  end;
end;

procedure TTestMisfireOnTime.GeneratedDueInstants(const aEngine: string;
  const aLatenessMs, aExpectedFires: Integer);
const
  cSamples = 4096;
var
  g: TGarbos;
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lDue, lTick, lRequestedDue, lFloatBoundary: TDateTime;
  lStamp: TTimeStamp;
  lCount, lFailures, lSecond: Integer;
  lOldEngine, lFirstFailure: string;
begin
  lOldEngine := GetEnvironmentVariable('MAXCRON_ENGINE');
  Winapi.Windows.SetEnvironmentVariable('MAXCRON_ENGINE', PChar(aEngine));
  try
    GC(lCron, TmaxCron.Create(ctPortable), g);
    lCron.DefaultMisfirePolicy := TmaxCronMisfirePolicy.mpSkip;
    lEvent := lCron.Add('GeneratedDueInstants');
    lEvent.EventPlan := '* * * * * * *';
    lEvent.InvokeMode := imMainThread;
    lEvent.OnScheduleProc :=
      procedure(aSender: IMaxCronEvent)
      begin
        Inc(lCount);
      end;
    lFailures := 0;
    lFirstFailure := '';
    for var i := 0 to cSamples - 1 do
    begin
      // Include day/year rollovers and varied binary day fractions, independent of Now.
      lSecond := (i * 7919) mod 86400;
      if (i mod 8) = 0 then
        lSecond := 86399;
      lRequestedDue := EncodeDate(2030 + (i mod 400), 1 + (i mod 12), 1 + (i mod 28));
      lRequestedDue := IncSecond(lRequestedDue, lSecond);
      lEvent.Stop;
      lEvent.ValidFrom := lRequestedDue;
      lEvent.Run;
      lDue := lEvent.NextSchedule;
      lStamp := DateTimeToTimeStamp(lDue);
      Assert.IsTrue(lDue >= lRequestedDue, 'Generated due must respect ValidFrom');
      Assert.AreEqual(0, lStamp.Time mod 1000, 'Generated due must be a whole second');
      lTick := IncMilliSecond(lDue, aLatenessMs);
      lCount := 0;
      lCron.TickAt(lTick);
      if lCount <> aExpectedFires then
      begin
        Inc(lFailures);
        if lFirstFailure = '' then
        begin
          lFloatBoundary := lDue + (1.0 / 86400.0);
          lFirstFailure := Format('sample=%d due=%s tick=%.17g due+1s=%.17g count=%d',
            [i, FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', lDue), lTick, lFloatBoundary, lCount]);
        end;
      end;
      lCron.TickAt(lTick);
      Assert.IsTrue(lCount <= 1, 'A repeated tick must never dispatch the same occurrence twice');
    end;
    Assert.AreEqual(0, lFailures, Format('%d generated instants; %s', [cSamples, lFirstFailure]));
  finally
    g.Clear;
    Winapi.Windows.SetEnvironmentVariable('MAXCRON_ENGINE', PChar(lOldEngine));
  end;
end;

end.

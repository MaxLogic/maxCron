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

end.

unit TestExecutionLimit;

interface

uses
  System.DateUtils, System.Diagnostics, System.SysUtils, System.SyncObjs, System.Classes,
  DUnitX.TestFramework,
  maxCron;

type
  [TestFixture]
  TTestExecutionLimit = class
  public
    [Test]
    procedure ExecutionLimit_StopsAfterN;
  end;

implementation

procedure TTestExecutionLimit.ExecutionLimit_StopsAfterN;
var
  Cron: TmaxCron;
  Evt: TmaxCronEvent;
  Count: Integer;
  Sw: TStopwatch;
begin
  Count := 0;
  Cron := TmaxCron.Create(ctPortable);
  try
    Evt := Cron.Add('Limit');
    Evt.EventPlan := '* * * * * * * 2'; // execution limit = 2
    Evt.InvokeMode := imThread;
    Evt.OverlapMode := omAllowOverlap;
    Evt.OnScheduleProc :=
      procedure(Sender: TmaxCronEvent)
      begin
        TInterlocked.Increment(Count);
      end;
    Evt.Run;

    Cron.TickAt(Evt.NextSchedule);
    Cron.TickAt(IncSecond(Evt.NextSchedule, 10));
    Cron.TickAt(IncSecond(Evt.NextSchedule, 20));

    Sw := TStopwatch.StartNew;
    while (TInterlocked.CompareExchange(Count, 0, 0) < 2) and (Sw.ElapsedMilliseconds < 3000) do
      TThread.Sleep(10);

    Assert.AreEqual(2, TInterlocked.CompareExchange(Count, 0, 0));
  finally
    Cron.Free;
  end;
end;

end.

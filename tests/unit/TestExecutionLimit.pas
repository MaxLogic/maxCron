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

    [Test]
    procedure ExecutionCount_SkipIfRunning_OnlyCountsExecutions;
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

procedure TTestExecutionLimit.ExecutionCount_SkipIfRunning_OnlyCountsExecutions;
var
  lCron: TmaxCron;
  lEvt: TmaxCronEvent;
  lStarted: TEvent;
  lGate: TEvent;
  lWaitRes: TWaitResult;
begin
  lCron := TmaxCron.Create(ctPortable);
  try
    lStarted := TEvent.Create(nil, True, False, '');
    lGate := TEvent.Create(nil, True, False, '');
    try
      lEvt := lCron.Add('SkipCount');
      lEvt.EventPlan := '* * * * * * * 0';
      lEvt.InvokeMode := imThread;
      lEvt.OverlapMode := omSkipIfRunning;
      lEvt.OnScheduleProc :=
        procedure(Sender: TmaxCronEvent)
        begin
          lStarted.SetEvent;
          lGate.WaitFor(3000);
        end;
      lEvt.Run;

      lCron.TickAt(lEvt.NextSchedule);
      lWaitRes := lStarted.WaitFor(2000);
      Assert.AreEqual(TWaitResult.wrSignaled, lWaitRes);

      lCron.TickAt(lEvt.NextSchedule);
      Assert.AreEqual(1, Integer(lEvt.NumOfExecutionsPerformed));

      lGate.SetEvent;
    finally
      lGate.Free;
      lStarted.Free;
    end;
  finally
    lCron.Free;
  end;
end;

end.

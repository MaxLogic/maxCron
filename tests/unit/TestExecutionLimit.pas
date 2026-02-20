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

    [Test]
    procedure ExecutionLimit_SkipIfRunning_CountsExecutions;
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

procedure TTestExecutionLimit.ExecutionLimit_SkipIfRunning_CountsExecutions;
var
  lCron: TmaxCron;
  lEvt: TmaxCronEvent;
  lStarted: TEvent;
  lFinished: TEvent;
  lGate: TEvent;
  lWaitRes: TWaitResult;
  lCount: Integer;
  lStartTick: TDateTime;
  lSw: TStopwatch;
begin
  lCount := 0;
  lCron := TmaxCron.Create(ctPortable);
  try
    lStarted := TEvent.Create(nil, True, False, '');
    lFinished := TEvent.Create(nil, True, False, '');
    lGate := TEvent.Create(nil, True, False, '');
    try
      lEvt := lCron.Add('LimitSkip');
      lEvt.EventPlan := '* * * * * * * 2';
      lEvt.InvokeMode := imThread;
      lEvt.OverlapMode := omSkipIfRunning;
      lEvt.OnScheduleProc :=
        procedure(Sender: TmaxCronEvent)
        begin
          TInterlocked.Increment(lCount);
          lStarted.SetEvent;
          lGate.WaitFor(3000);
          lFinished.SetEvent;
        end;
      lEvt.Run;

      lStartTick := lEvt.NextSchedule;
      lCron.TickAt(lStartTick);
      lWaitRes := lStarted.WaitFor(2000);
      Assert.AreEqual(TWaitResult.wrSignaled, lWaitRes);

      lCron.TickAt(IncSecond(lStartTick, 1));
      lCron.TickAt(IncSecond(lStartTick, 2));

      lGate.SetEvent;
      lWaitRes := lFinished.WaitFor(2000);
      Assert.AreEqual(TWaitResult.wrSignaled, lWaitRes);

      lSw := TStopwatch.StartNew;
      while (TInterlocked.CompareExchange(lCount, 0, 0) < 2) and (lSw.ElapsedMilliseconds < 3000) do
      begin
        lCron.TickAt(IncSecond(lStartTick, 3 + (lSw.ElapsedMilliseconds div 250)));
        TThread.Sleep(10);
      end;

      Assert.AreEqual(2, TInterlocked.CompareExchange(lCount, 0, 0));
    finally
      lGate.Free;
      lFinished.Free;
      lStarted.Free;
    end;
  finally
    lCron.Free;
  end;
end;

end.

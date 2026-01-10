unit TestInvokeModes;

interface

uses
  System.DateUtils, System.Diagnostics, System.SysUtils, System.SyncObjs, System.Classes,
  DUnitX.TestFramework,
  maxCron;

type
  [TestFixture]
  TTestInvokeModes = class
  public
    [Test]
    procedure Invoke_MainThread_QueuedFromWorker;

    [Test]
    procedure Invoke_TTask_Runs;

    [Test]
    procedure Invoke_MaxAsync_Runs;
  end;

implementation

procedure TTestInvokeModes.Invoke_MainThread_QueuedFromWorker;
var
  Cron: TmaxCron;
  Evt: TmaxCronEvent;
  Fired: TEvent;
  ThreadId: TThreadID;
  Worker: TThread;
  Sw: TStopwatch;
  WaitRes: TWaitResult;
begin
  ThreadId := 0;
  Cron := TmaxCron.Create(ctPortable);
  try
    Fired := TEvent.Create(nil, True, False, '');
    try
      Evt := Cron.Add('MainQueued');
      Evt.EventPlan := '* * * * * * * 0';
      Evt.InvokeMode := imMainThread;
      Evt.OverlapMode := omAllowOverlap;
      Evt.OnScheduleProc :=
        procedure(Sender: TmaxCronEvent)
        begin
          ThreadId := TThread.CurrentThread.ThreadID;
          Fired.SetEvent;
        end;
      Evt.Run;

      Worker := TThread.CreateAnonymousThread(
        procedure
        begin
          Cron.TickAt(Evt.NextSchedule);
        end);
      Worker.FreeOnTerminate := False;
      try
        Worker.Start;
        Worker.WaitFor;
      finally
        Worker.Free;
      end;

      Sw := TStopwatch.StartNew;
      repeat
        WaitRes := Fired.WaitFor(0);
        if WaitRes = wrSignaled then Break;
        CheckSynchronize(10);
      until Sw.ElapsedMilliseconds >= 2000;

      Assert.AreEqual(TWaitResult.wrSignaled, Fired.WaitFor(0));
      Assert.AreEqual(MainThreadID, ThreadId);
    finally
      Fired.Free;
    end;
  finally
    Cron.Free;
  end;
end;

procedure TTestInvokeModes.Invoke_TTask_Runs;
var
  Cron: TmaxCron;
  Evt: TmaxCronEvent;
  Fired: TEvent;
  WaitRes: TWaitResult;
begin
  Cron := TmaxCron.Create(ctPortable);
  try
    Fired := TEvent.Create(nil, True, False, '');
    try
      Evt := Cron.Add('TTask');
      Evt.EventPlan := '* * * * * * * 0';
      Evt.InvokeMode := imTTask;
      Evt.OverlapMode := omAllowOverlap;
      Evt.OnScheduleProc := procedure(Sender: TmaxCronEvent) begin Fired.SetEvent; end;
      Evt.Run;

      Cron.TickAt(Evt.NextSchedule);
      WaitRes := Fired.WaitFor(3000);
      Assert.AreEqual(TWaitResult.wrSignaled, WaitRes);
    finally
      Fired.Free;
    end;
  finally
    Cron.Free;
  end;
end;

procedure TTestInvokeModes.Invoke_MaxAsync_Runs;
var
  Cron: TmaxCron;
  Evt: TmaxCronEvent;
  Fired: TEvent;
  WaitRes: TWaitResult;
begin
  Cron := TmaxCron.Create(ctPortable);
  try
    Fired := TEvent.Create(nil, True, False, '');
    try
      Evt := Cron.Add('MaxAsync');
      Evt.EventPlan := '* * * * * * * 0';
      Evt.InvokeMode := imMaxAsync;
      Evt.OverlapMode := omAllowOverlap;
      Evt.OnScheduleProc := procedure(Sender: TmaxCronEvent) begin Fired.SetEvent; end;
      Evt.Run;

      Cron.TickAt(Evt.NextSchedule);
      WaitRes := Fired.WaitFor(3000);
      Assert.AreEqual(TWaitResult.wrSignaled, WaitRes);

      // allow any queued synced callbacks (keep-alive release) to run
      CheckSynchronize(50);
    finally
      Fired.Free;
    end;
  finally
    Cron.Free;
  end;
end;

end.

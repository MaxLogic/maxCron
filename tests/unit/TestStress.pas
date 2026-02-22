unit TestStress;

interface

uses
  System.DateUtils, System.Diagnostics, System.SysUtils, System.SyncObjs, System.Classes,
  DUnitX.TestFramework,
  maxCron;

type
  [TestFixture]
  TTestStress = class
  public
    [Test]
    procedure Invoke_MainThread_QueuedFromWorker;

    [Test]
    procedure SerializeCoalesce_BurstBacklogCapped;

    [Test]
    procedure DeleteQueuedCallback_DoesNotCrash;

    [Test]
    procedure Perf_Sanity_BoundedTicks;
  end;

implementation

procedure TTestStress.Invoke_MainThread_QueuedFromWorker;
var
  Cron: TmaxCron;
  Evt: IMaxCronEvent;
  CalledOnMain: Boolean;
  WorkerId: Cardinal;
  Called: TEvent;
  Started: TEvent;
  NextAt: TDateTime;
  Sw: TStopwatch;
begin
  CalledOnMain := False;
  WorkerId := 0;

  Called := TEvent.Create(nil, True, False, '');
  Started := TEvent.Create(nil, True, False, '');
  try
    Cron := TmaxCron.Create(ctPortable);
    try
      Evt := Cron.Add('MainThread');
      Evt.EventPlan := '* * * * * * * 0';
      Evt.InvokeMode := imMainThread;
      Evt.OnScheduleProc :=
        procedure(Sender: IMaxCronEvent)
        begin
          CalledOnMain := (TThread.CurrentThread.ThreadID = MainThreadID);
          Called.SetEvent;
        end;
      Evt.Run;
      NextAt := Evt.NextSchedule;

      TThread.CreateAnonymousThread(
        procedure
        begin
          WorkerId := TThread.CurrentThread.ThreadID;
          Started.SetEvent;
          Cron.TickAt(NextAt);
        end
        ).Start;

      Assert.AreEqual(TWaitResult.wrSignaled, Started.WaitFor(3000), 'Worker did not start');
      Assert.IsTrue(WorkerId <> MainThreadID, 'Expected worker thread');

      Sw := TStopwatch.StartNew;
      while (Called.WaitFor(0) <> TWaitResult.wrSignaled) and (Sw.ElapsedMilliseconds < 5000) do
        CheckSynchronize(25);

      Assert.AreEqual(TWaitResult.wrSignaled, Called.WaitFor(0), 'Expected queued callback');
      Assert.IsTrue(CalledOnMain, 'Expected callback on main thread');
    finally
      Cron.Free;
    end;
  finally
    Started.Free;
    Called.Free;
  end;
end;

procedure TTestStress.SerializeCoalesce_BurstBacklogCapped;
var
  Cron: TmaxCron;
  Evt: IMaxCronEvent;
  ExecCount: Integer;
  StartAt: TDateTime;
  Sw: TStopwatch;
  i: Integer;
begin
  ExecCount := 0;

  Cron := TmaxCron.Create(ctPortable);
  try
    Evt := Cron.Add('Coalesce');
    Evt.EventPlan := '* * * * * * * 0';
    Evt.InvokeMode := imThread;
    Evt.OverlapMode := omSerializeCoalesce;
    Evt.OnScheduleProc :=
      procedure(Sender: IMaxCronEvent)
      begin
        TInterlocked.Increment(ExecCount);
        TThread.Sleep(250);
      end;
    Evt.Run;

    StartAt := Evt.NextSchedule;
    for i := 0 to 25 do
      Cron.TickAt(IncSecond(StartAt, i)); // burst of due ticks while callback is still running

    Sw := TStopwatch.StartNew;
    while (TInterlocked.CompareExchange(ExecCount, 0, 0) < 1) and (Sw.ElapsedMilliseconds < 5000) do
      TThread.Sleep(10);

    // give time for a possible coalesced second run
    TThread.Sleep(800);

    Assert.IsTrue(TInterlocked.CompareExchange(ExecCount, 0, 0) <= 2, 'Expected backlog capped to <= 1 pending run');
  finally
    Cron.Free;
  end;
end;

procedure TTestStress.DeleteQueuedCallback_DoesNotCrash;
var
  Cron: TmaxCron;
  Evt: IMaxCronEvent;
  Done: TEvent;
  NextAt: TDateTime;
  Worker: TThread;
begin
  Cron := TmaxCron.Create(ctPortable);
  Done := TEvent.Create(nil, True, False, '');
  try
    Evt := Cron.Add('QueuedDelete');
    Evt.EventPlan := '* * * * * * * 0';
    Evt.InvokeMode := imMainThread;
    Evt.OnScheduleProc :=
      procedure(Sender: IMaxCronEvent)
      begin
        // our queued target should be safe even if the event is deleted before this runs
      end;
    Evt.Run;
    NextAt := Evt.NextSchedule;

    Worker := TThread.CreateAnonymousThread(
      procedure
      begin
        Cron.TickAt(NextAt);
        Done.SetEvent;
      end);
    Worker.FreeOnTerminate := False;
    Worker.Start;
    try
      Assert.AreEqual(TWaitResult.wrSignaled, Done.WaitFor(2000), 'Worker did not finish');
      Assert.IsTrue(Cron.Delete(Evt));
      CheckSynchronize(200);
    finally
      Worker.Free;
    end;
  finally
    Done.Free;
    Cron.Free;
  end;
end;

procedure TTestStress.Perf_Sanity_BoundedTicks;
const
  EventCount = 250;
  TickCount = 200;
  MaxMs = 5000;
var
  Cron: TmaxCron;
  i: Integer;
  Evt: IMaxCronEvent;
  Sw: TStopwatch;
  Base: TDateTime;
begin
  if GetEnvironmentVariable('MAXCRON_STRESS') = '' then
    Exit;

  Cron := TmaxCron.Create(ctPortable);
  try
    for i := 0 to EventCount - 1 do
    begin
      Evt := Cron.Add('Perf' + IntToStr(i));
      Evt.EventPlan := '* * * * * * * 0';
      Evt.Run;
    end;

    Base := Now;
    Sw := TStopwatch.StartNew;
    for i := 0 to TickCount - 1 do
      Cron.TickAt(IncSecond(Base, i));
    Assert.IsTrue(Sw.ElapsedMilliseconds <= MaxMs, 'Perf sanity exceeded budget');
  finally
    Cron.Free;
  end;
end;

end.

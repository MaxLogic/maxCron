unit TestStress;

interface

uses
  System.Diagnostics, System.SysUtils, System.SyncObjs, System.Classes,
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
  end;

implementation

procedure TTestStress.Invoke_MainThread_QueuedFromWorker;
var
  Cron: TmaxCron;
  Evt: TmaxCronEvent;
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
      Evt := Cron.Add('MainThread', '* * * * * * * 0');
      Evt.InvokeMode := imMainThread;
      Evt.OnScheduleProc :=
        procedure(Sender: TmaxCronEvent)
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
  Evt: TmaxCronEvent;
  ExecCount: Integer;
  StartAt: TDateTime;
  Sw: TStopwatch;
  i: Integer;
begin
  ExecCount := 0;

  Cron := TmaxCron.Create(ctPortable);
  try
    Evt := Cron.Add('Coalesce', '* * * * * * * 0');
    Evt.InvokeMode := imThread;
    Evt.OverlapMode := omSerializeCoalesce;
    Evt.OnScheduleProc :=
      procedure(Sender: TmaxCronEvent)
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

end.


unit TestInvokeModes;

interface

uses
  System.Classes, System.DateUtils, System.Diagnostics, System.Generics.Collections, System.SyncObjs, System.SysUtils,
  Winapi.Windows,
  DUnitX.TestFramework,
  maxCron;

type
  [TestFixture]
  TTestInvokeModes = class
  private
    procedure SetEnvVar(const aName, aValue: string; out aPreviousValue: string; out aHadPrevious: Boolean);
    procedure RestoreEnvVar(const aName, aPreviousValue: string; const aHadPrevious: Boolean);
  public
    [Test]
    procedure Invoke_MainThread_QueuedFromWorker;

    [Test]
    procedure Invoke_TTask_Runs;

    [Test]
    procedure Invoke_MaxAsync_Runs;

    [Test]
    procedure Invoke_MaxAsync_FallbackOnNil;

    [Test]
    procedure Invoke_MaxAsync_FallbackOnException;

    [Test]
    procedure DefaultInvokeMode_ImDefault_NormalizesToMainThread;

    [Test]
    procedure Invoke_ThreadDispatchPool_ReusesWorkers;
  end;

implementation

procedure TTestInvokeModes.SetEnvVar(const aName, aValue: string; out aPreviousValue: string;
  out aHadPrevious: Boolean);
begin
  aPreviousValue := GetEnvironmentVariable(aName);
  aHadPrevious := aPreviousValue <> '';
  Winapi.Windows.SetEnvironmentVariable(PChar(aName), PChar(aValue));
end;

procedure TTestInvokeModes.RestoreEnvVar(const aName, aPreviousValue: string; const aHadPrevious: Boolean);
begin
  if aHadPrevious then
    Winapi.Windows.SetEnvironmentVariable(PChar(aName), PChar(aPreviousValue))
  else
    Winapi.Windows.SetEnvironmentVariable(PChar(aName), nil);
end;

procedure TTestInvokeModes.Invoke_MainThread_QueuedFromWorker;
var
  Cron: TmaxCron;
  Evt: IMaxCronEvent;
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
        procedure(Sender: IMaxCronEvent)
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
  Evt: IMaxCronEvent;
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
      Evt.OnScheduleProc := procedure(Sender: IMaxCronEvent) begin Fired.SetEvent; end;
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
  Evt: IMaxCronEvent;
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
      Evt.OnScheduleProc := procedure(Sender: IMaxCronEvent) begin Fired.SetEvent; end;
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

procedure TTestInvokeModes.Invoke_MaxAsync_FallbackOnNil;
var
  Cron: TmaxCron;
  Evt: IMaxCronEvent;
  Fired: TEvent;
  WaitRes: TWaitResult;
begin
  SetMaxCronAsyncCallHook(
    function(const aProc: TThreadProcedure; const aTaskName: string): IInterface
    begin
      Result := nil;
    end);
  try
    Cron := TmaxCron.Create(ctPortable);
    try
      Fired := TEvent.Create(nil, True, False, '');
      try
        Evt := Cron.Add('MaxAsyncNil');
        Evt.EventPlan := '* * * * * * * 0';
        Evt.InvokeMode := imMaxAsync;
        Evt.OverlapMode := omAllowOverlap;
        Evt.OnScheduleProc := procedure(Sender: IMaxCronEvent) begin Fired.SetEvent; end;
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
  finally
    SetMaxCronAsyncCallHook(nil);
  end;
end;

procedure TTestInvokeModes.Invoke_MaxAsync_FallbackOnException;
var
  Cron: TmaxCron;
  Evt: IMaxCronEvent;
  Fired: TEvent;
  WaitRes: TWaitResult;
begin
  SetMaxCronAsyncCallHook(
    function(const aProc: TThreadProcedure; const aTaskName: string): IInterface
    begin
      raise Exception.Create('forced async failure');
    end);
  try
    Cron := TmaxCron.Create(ctPortable);
    try
      Fired := TEvent.Create(nil, True, False, '');
      try
        Evt := Cron.Add('MaxAsyncException');
        Evt.EventPlan := '* * * * * * * 0';
        Evt.InvokeMode := imMaxAsync;
        Evt.OverlapMode := omAllowOverlap;
        Evt.OnScheduleProc := procedure(Sender: IMaxCronEvent) begin Fired.SetEvent; end;
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
  finally
    SetMaxCronAsyncCallHook(nil);
  end;
end;

procedure TTestInvokeModes.DefaultInvokeMode_ImDefault_NormalizesToMainThread;
var
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lFired: TEvent;
  lWorkerDone: TEvent;
  lWorker: TThread;
  lSw: TStopwatch;
  lWaitRes: TWaitResult;
  lCallbackThreadId: TThreadID;
begin
  lCallbackThreadId := 0;
  lCron := TmaxCron.Create(ctPortable);
  lFired := TEvent.Create(nil, True, False, '');
  lWorkerDone := TEvent.Create(nil, True, False, '');
  try
    lCron.DefaultInvokeMode := imDefault;

    lEvent := lCron.Add('DefaultInvokeImDefault');
    lEvent.EventPlan := '* * * * * * * 1';
    lEvent.OnScheduleProc :=
      procedure(aSender: IMaxCronEvent)
      begin
        lCallbackThreadId := TThread.CurrentThread.ThreadID;
        lFired.SetEvent;
      end;
    lEvent.Run;

    lWorker := TThread.CreateAnonymousThread(
      procedure
      begin
        lCron.TickAt(lEvent.NextSchedule);
        lWorkerDone.SetEvent;
      end);
    lWorker.FreeOnTerminate := False;
    try
      lWorker.Start;
      Assert.AreEqual(TWaitResult.wrSignaled, lWorkerDone.WaitFor(2000),
        'Worker TickAt did not finish');
      lWorker.WaitFor;
    finally
      lWorker.Free;
    end;

    lSw := TStopwatch.StartNew;
    repeat
      lWaitRes := lFired.WaitFor(0);
      if lWaitRes = wrSignaled then
        Break;
      CheckSynchronize(10);
    until lSw.ElapsedMilliseconds >= 2000;

    Assert.AreEqual(TWaitResult.wrSignaled, lFired.WaitFor(0), 'Callback did not fire');
    Assert.AreEqual(MainThreadID, lCallbackThreadId,
      'Default invoke mode should resolve to main-thread dispatch');
  finally
    lWorkerDone.Free;
    lFired.Free;
    lCron.Free;
  end;
end;

procedure TTestInvokeModes.Invoke_ThreadDispatchPool_ReusesWorkers;
const
  cEventCount = 128;
var
  lCron: TmaxCron;
  lDone: TEvent;
  lLock: TCriticalSection;
  lThreadIds: TDictionary<TThreadID, Byte>;
  lEvent: IMaxCronEvent;
  lTickAt: TDateTime;
  lCompleted: Integer;
  lUniqueCount: Integer;
  lIndex: Integer;
  lPreviousValue: string;
  lHadPrevious: Boolean;
begin
  lCompleted := 0;
  lTickAt := Now;
  SetEnvVar('MAXCRON_THREAD_DISPATCH_POOL', '1', lPreviousValue, lHadPrevious);
  try
    lCron := TmaxCron.Create(ctPortable);
    lDone := TEvent.Create(nil, True, False, '');
    lLock := TCriticalSection.Create;
    lThreadIds := TDictionary<TThreadID, Byte>.Create;
    try
      for lIndex := 0 to cEventCount - 1 do
      begin
        lEvent := lCron.Add('PoolDispatch_' + IntToStr(lIndex));
        lEvent.EventPlan := '* * * * * * * 0';
        lEvent.InvokeMode := imThread;
        lEvent.OnScheduleProc :=
          procedure(aSender: IMaxCronEvent)
          begin
            lLock.Acquire;
            try
              if not lThreadIds.ContainsKey(TThread.CurrentThread.ThreadID) then
                lThreadIds.Add(TThread.CurrentThread.ThreadID, 0);
            finally
              lLock.Release;
            end;

            TThread.Sleep(20);
            if TInterlocked.Increment(lCompleted) = cEventCount then
              lDone.SetEvent;
          end;
        lEvent.Run;
        if lIndex = 0 then
          lTickAt := lEvent.NextSchedule;
      end;

      lCron.TickAt(lTickAt);

      Assert.AreEqual(TWaitResult.wrSignaled, lDone.WaitFor(10000),
        'Expected pooled thread dispatch callbacks to complete');
      lLock.Acquire;
      try
        lUniqueCount := lThreadIds.Count;
      finally
        lLock.Release;
      end;
      Assert.IsTrue(lUniqueCount <= 64,
        Format('Expected pooled dispatch to reuse worker threads (unique workers=%d)', [lUniqueCount]));
    finally
      lThreadIds.Free;
      lLock.Free;
      lDone.Free;
      lCron.Free;
    end;
  finally
    RestoreEnvVar('MAXCRON_THREAD_DISPATCH_POOL', lPreviousValue, lHadPrevious);
  end;
end;

end.

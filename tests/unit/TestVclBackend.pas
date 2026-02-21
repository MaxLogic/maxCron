unit TestVclBackend;

interface

uses
  System.Diagnostics, System.SysUtils, System.Classes, System.SyncObjs,
  Vcl.Forms,
  DUnitX.TestFramework,
  maxCron;

type
  [TestFixture]
  TTestVclBackend = class
  public
    [Test]
    procedure AutoBackend_ChoosesVclOnVclThread;

    [Test]
    procedure VclTimer_Fires_OnMainThread;

    [Test]
    procedure CreateCtVcl_OnWorkerThread_Raises;
  end;

implementation

procedure TTestVclBackend.AutoBackend_ChoosesVclOnVclThread;
var
  Cron: TmaxCron;
begin
  Cron := TmaxCron.Create(ctAuto);
  try
    Assert.AreEqual(TmaxCronTimerBackend.ctVcl, Cron.ActiveTimerBackend);
  finally
    Cron.Free;
  end;
end;

procedure TTestVclBackend.VclTimer_Fires_OnMainThread;
var
  Cron: TmaxCron;
  Evt: TmaxCronEvent;
  Count: Integer;
  BadThread: Integer;
  Sw: TStopwatch;
begin
  Count := 0;
  BadThread := 0;

  Cron := TmaxCron.Create(ctVcl);
  try
    Assert.AreEqual(TmaxCronTimerBackend.ctVcl, Cron.ActiveTimerBackend);

    Evt := Cron.Add('VclTick');
    Evt.EventPlan := '* * * * * * * 0'; // every second
    Evt.InvokeMode := imMainThread;
    Evt.OverlapMode := omAllowOverlap;
    Evt.OnScheduleProc :=
      procedure(Sender: TmaxCronEvent)
      begin
        if TThread.CurrentThread.ThreadID <> MainThreadID then
          TInterlocked.Exchange(BadThread, 1);
        TInterlocked.Increment(Count);
      end;
    Evt.Run;

    Sw := TStopwatch.StartNew;
    while (TInterlocked.CompareExchange(Count, 0, 0) = 0) and (Sw.ElapsedMilliseconds < 5000) do
    begin
      Application.ProcessMessages;
      TThread.Sleep(10);
    end;

    Assert.IsTrue(TInterlocked.CompareExchange(Count, 0, 0) > 0, 'Expected at least one timer fire');
    Assert.AreEqual(0, TInterlocked.CompareExchange(BadThread, 0, 0), 'Expected callback on main thread');
  finally
    Cron.Free;
  end;
end;

procedure TTestVclBackend.CreateCtVcl_OnWorkerThread_Raises;
var
  lDone: TEvent;
  lRaised: Integer;
  lThread: TThread;
begin
  lDone := TEvent.Create(nil, True, False, '');
  lRaised := 0;
  try
    lThread := TThread.CreateAnonymousThread(
      procedure
      var
        lCron: TmaxCron;
      begin
        lCron := nil;
        try
          try
            lCron := TmaxCron.Create(ctVcl);
          except
            on Exception do
              TInterlocked.Exchange(lRaised, 1);
          end;
        finally
          lCron.Free;
          lDone.SetEvent;
        end;
      end);
    lThread.FreeOnTerminate := True;
    lThread.Start;

    Assert.AreEqual(TWaitResult.wrSignaled, lDone.WaitFor(3000), 'Worker did not complete');
    Assert.AreEqual(1, TInterlocked.CompareExchange(lRaised, 0, 0),
      'Expected ctVcl creation off the main thread to fail');
  finally
    lDone.Free;
  end;
end;

end.

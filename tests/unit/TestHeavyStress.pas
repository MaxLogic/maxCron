unit TestHeavyStress;

interface

uses
  System.DateUtils, System.Diagnostics, System.SysUtils, System.SyncObjs, System.Classes,
  DUnitX.TestFramework,
  maxCron;

type
  [TestFixture]
  TTestHeavyStress = class
  private
    procedure SetError(const aLock: TCriticalSection; var aErrorText: string;
      const aWhere, aText: string);
  public
    [Test]
    procedure ManyEvents_ManyTicks_30s;
  end;

implementation

procedure TTestHeavyStress.SetError(const aLock: TCriticalSection; var aErrorText: string;
  const aWhere, aText: string);
begin
  aLock.Acquire;
  try
    if aErrorText = '' then
      aErrorText := aWhere + ': ' + aText;
  finally
    aLock.Release;
  end;
end;

procedure TTestHeavyStress.ManyEvents_ManyTicks_30s;
const
  ThreadCount = 4;
  EventCount = 80;
  DurationMs = 30000;
var
  Cron: TmaxCron;
  ErrLock: TCriticalSection;
  ErrorText: string;
  Fires: Integer;
  Threads: array [0 .. ThreadCount - 1] of TThread;
  Started: array [0 .. ThreadCount - 1] of TEvent;
  i: Integer;
  EndStamp: Int64;
  Evt: IMaxCronEvent;

  function MakeWorker(const aIdx: Integer): TThread;
  begin
    Result := TThread.CreateAnonymousThread(
      procedure
      var
        LocalTick: Integer;
        NowDt: TDateTime;
        NowStamp: Int64;
      begin
        LocalTick := 0;
        Started[aIdx].SetEvent;
        while True do
        begin
          NowStamp := TStopwatch.GetTimeStamp;
          if NowStamp >= EndStamp then
            Break;
          try
            NowDt := Now;
            Cron.TickAt(NowDt);
          except
            on E: Exception do
            begin
              SetError(ErrLock, ErrorText, 'TickAt', E.ClassName + ': ' + E.Message);
              Exit;
            end;
          end;
          Inc(LocalTick);
          if (LocalTick and $F) = 0 then
            TThread.Yield;
          TThread.Sleep(10);
        end;
      end
      );
    Result.FreeOnTerminate := False;
  end;

begin
  Fires := 0;
  ErrorText := '';
  ErrLock := TCriticalSection.Create;
  try
    Cron := TmaxCron.Create(ctPortable);
    try
      for i := 0 to EventCount - 1 do
      begin
        Evt := Cron.Add('E' + IntToStr(i));
        Evt.EventPlan := '* * * * * * * 0';
        Evt.Tag := i;
        Evt.InvokeMode := imThread;
        if (i mod 4) = 0 then
          Evt.OverlapMode := omSerializeCoalesce
        else if (i mod 4) = 1 then
          Evt.OverlapMode := omSerialize
        else if (i mod 4) = 2 then
          Evt.OverlapMode := omSkipIfRunning
        else
          Evt.OverlapMode := omAllowOverlap;

        Evt.OnScheduleProc :=
          procedure(Sender: IMaxCronEvent)
          begin
            try
              TInterlocked.Increment(Fires);
              if (Sender.Tag mod 10) = 0 then
                TThread.Sleep(2);
            except
              on E: Exception do
                SetError(ErrLock, ErrorText, 'Callback', E.ClassName + ': ' + E.Message);
            end;
          end;
        Evt.Run;
      end;

      for i := 0 to ThreadCount - 1 do
        Started[i] := TEvent.Create(nil, True, False, '');
      try
        EndStamp := TStopwatch.GetTimeStamp + (Int64(DurationMs) * TStopwatch.Frequency) div 1000;
        for i := 0 to ThreadCount - 1 do
        begin
          Threads[i] := MakeWorker(i);
          Threads[i].Start;
        end;

        for i := 0 to ThreadCount - 1 do
          Assert.AreEqual(TWaitResult.wrSignaled, Started[i].WaitFor(3000), 'Worker did not start');

        for i := 0 to ThreadCount - 1 do
          Threads[i].WaitFor;

        ErrLock.Acquire;
        try
          if ErrorText <> '' then
            Assert.Fail(ErrorText);
        finally
          ErrLock.Release;
        end;

        Assert.IsTrue(TInterlocked.CompareExchange(Fires, 0, 0) > 0, 'Expected at least one callback');
      finally
        for i := 0 to ThreadCount - 1 do
          Started[i].Free;
        for i := 0 to ThreadCount - 1 do
          Threads[i].Free;
      end;
    finally
      Cron.Free;
    end;
  finally
    ErrLock.Free;
  end;
end;

end.

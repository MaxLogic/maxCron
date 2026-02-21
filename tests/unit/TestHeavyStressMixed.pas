unit TestHeavyStressMixed;

interface

uses
  System.Classes, System.DateUtils, System.Diagnostics, System.SyncObjs, System.SysUtils,
  DUnitX.TestFramework,
  maxCron;

type
  [TestFixture]
  TTestHeavyStressMixed = class
  private
    procedure SetError(const aLock: TCriticalSection; var aErrorText: string;
      const aWhere, aText: string);
  public
    [Test]
    procedure ManyMixedEvents_ManyTicks_30s;
  end;

implementation

procedure TTestHeavyStressMixed.SetError(const aLock: TCriticalSection; var aErrorText: string;
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

procedure TTestHeavyStressMixed.ManyMixedEvents_ManyTicks_30s;
const
  cThreadCount = 4;
  cEventCount = 96;
  cDurationMs = 30000;
var
  lCron: TmaxCron;
  lErrorLock: TCriticalSection;
  lErrorText: string;
  lFireCount: Integer;
  lThreads: array [0 .. cThreadCount - 1] of TThread;
  lStarted: array [0 .. cThreadCount - 1] of TEvent;
  lIndex: Integer;
  lEndStamp: Int64;
  lEvent: TmaxCronEvent;
  lTomorrow: TDateTime;

  function BuildExcludedCsv: string;
  begin
    Result := FormatDateTime('yyyy"-"mm"-"dd', lTomorrow);
  end;

  function MakeWorker(const aIndex: Integer): TThread;
  begin
    Result := TThread.CreateAnonymousThread(
      procedure
      var
        lLocalTick: Integer;
        lNowDateTime: TDateTime;
        lNowStamp: Int64;
      begin
        lLocalTick := 0;
        lStarted[aIndex].SetEvent;
        while True do
        begin
          lNowStamp := TStopwatch.GetTimeStamp;
          if lNowStamp >= lEndStamp then
            Break;

          try
            lNowDateTime := Now;
            lCron.TickAt(lNowDateTime);
            if (lLocalTick mod 20) = 0 then
              lCron.TickAt(IncSecond(lNowDateTime, 5));
          except
            on E: Exception do
            begin
              SetError(lErrorLock, lErrorText, 'TickAt', E.ClassName + ': ' + E.Message);
              Exit;
            end;
          end;

          Inc(lLocalTick);
          if (lLocalTick and $0F) = 0 then
            TThread.Yield;
          TThread.Sleep(10);
        end;
      end
      );
    Result.FreeOnTerminate := False;
  end;

begin
  lFireCount := 0;
  lErrorText := '';
  lTomorrow := IncDay(Date, 1);
  lErrorLock := TCriticalSection.Create;
  try
    lCron := TmaxCron.Create(ctPortable);
    try
      lCron.DefaultMisfireCatchUpLimit := 2;

      for lIndex := 0 to cEventCount - 1 do
      begin
        lEvent := lCron.Add('Mixed' + IntToStr(lIndex));

        if (lIndex mod 6) = 5 then
          lEvent.EventPlan := '* * * * * * H/10 0'
        else
          lEvent.EventPlan := '* * * * * * * 0';

        lEvent.Tag := lIndex;
        lEvent.InvokeMode := imThread;

        case (lIndex mod 4) of
          0:
            lEvent.OverlapMode := omSerializeCoalesce;
          1:
            lEvent.OverlapMode := omSerialize;
          2:
            lEvent.OverlapMode := omSkipIfRunning;
        else
          lEvent.OverlapMode := omAllowOverlap;
        end;

        case (lIndex mod 6) of
          0:
            lEvent.TimeZoneId := 'UTC';
          1:
            lEvent.TimeZoneId := 'UTC+02:00';
          2:
            lEvent.ExcludedDatesCsv := BuildExcludedCsv;
          3:
            begin
              lEvent.BlackoutStartTime := EncodeTime(12, 0, 0, 0);
              lEvent.BlackoutEndTime := EncodeTime(12, 0, 0, 0);
            end;
          4:
            lEvent.WeekdaysOnly := True;
        end;

        case (lIndex mod 3) of
          0:
            lEvent.MisfirePolicy := mpSkip;
          1:
            lEvent.MisfirePolicy := mpFireOnceNow;
        else
          lEvent.MisfirePolicy := mpCatchUpAll;
        end;

        lEvent.OnScheduleProc :=
          procedure(aSender: TmaxCronEvent)
          begin
            try
              TInterlocked.Increment(lFireCount);
              if (aSender.Tag mod 11) = 0 then
                TThread.Sleep(2);
            except
              on E: Exception do
                SetError(lErrorLock, lErrorText, 'Callback', E.ClassName + ': ' + E.Message);
            end;
          end;

        lEvent.ValidFrom := IncSecond(Now, -1);
        lEvent.Run;
      end;

      for lIndex := 0 to cThreadCount - 1 do
        lStarted[lIndex] := TEvent.Create(nil, True, False, '');
      try
        lEndStamp := TStopwatch.GetTimeStamp + (Int64(cDurationMs) * TStopwatch.Frequency) div 1000;
        for lIndex := 0 to cThreadCount - 1 do
        begin
          lThreads[lIndex] := MakeWorker(lIndex);
          lThreads[lIndex].Start;
        end;

        for lIndex := 0 to cThreadCount - 1 do
          Assert.AreEqual(TWaitResult.wrSignaled, lStarted[lIndex].WaitFor(3000), 'Worker did not start');

        for lIndex := 0 to cThreadCount - 1 do
          lThreads[lIndex].WaitFor;

        lErrorLock.Acquire;
        try
          if lErrorText <> '' then
            Assert.Fail(lErrorText);
        finally
          lErrorLock.Release;
        end;

        Assert.IsTrue(TInterlocked.CompareExchange(lFireCount, 0, 0) > 0, 'Expected at least one callback');
      finally
        for lIndex := 0 to cThreadCount - 1 do
          lStarted[lIndex].Free;
        for lIndex := 0 to cThreadCount - 1 do
          lThreads[lIndex].Free;
      end;
    finally
      lCron.Free;
    end;
  finally
    lErrorLock.Free;
  end;
end;

end.

unit TestMaxCron;

interface

uses
  System.DateUtils, System.Diagnostics, System.SysUtils, System.SyncObjs, System.Classes,
  DUnitX.TestFramework,
  maxCron;

type
  [TestFixture]
  TTestMaxCron = class
  public
    [Test]
    procedure MakePreview_ReturnsSortedDates;

    [Test]
    procedure Overlap_Serialize_CoalescesToOnePending;

    [Test]
    procedure Overlap_Serialize_QueuesAllPending;
  end;

implementation

procedure TTestMaxCron.MakePreview_ReturnsSortedDates;
var
  Dates: TDates;
  i: Integer;
begin
  Assert.IsTrue(MakePreview('* * * * * * * 0', Dates, 10));
  Assert.IsTrue(Length(Dates) > 0);
  for i := 1 to Length(Dates) - 1 do
    Assert.IsTrue(Dates[i] >= Dates[i - 1]);
end;

procedure TTestMaxCron.Overlap_Serialize_CoalescesToOnePending;
var
  Cron: TmaxCron;
  Evt: TmaxCronEvent;
  Started: TEvent;
  Gate: TEvent;
  Count: Integer;
  NowTick: TDateTime;
  WaitRes: TWaitResult;
  i: Integer;
  Sw: TStopwatch;
begin
  Count := 0;
  Cron := TmaxCron.Create(ctPortable);
  try
    Started := TEvent.Create(nil, True, False, '');
    Gate := TEvent.Create(nil, True, False, '');
    try
      Evt := Cron.Add('Coalesce');
      Evt.EventPlan := '* * * * * * * 0';
      Evt.InvokeMode := imThread;
      Evt.OverlapMode := omSerializeCoalesce;
      Evt.OnScheduleProc :=
        procedure(Sender: TmaxCronEvent)
        begin
          TInterlocked.Increment(Count);
          Started.SetEvent;
          Gate.WaitFor(5000);
        end;
      Evt.Run;

      NowTick := Evt.NextSchedule;
      Cron.TickAt(NowTick);

      WaitRes := Started.WaitFor(2000);
      Assert.AreEqual(TWaitResult.wrSignaled, WaitRes);

      for i := 1 to 5 do
        Cron.TickAt(IncSecond(Evt.NextSchedule, 10));

      Gate.SetEvent;

      Sw := TStopwatch.StartNew;
      while (TInterlocked.CompareExchange(Count, 0, 0) < 2) and (Sw.ElapsedMilliseconds < 5000) do
        TThread.Sleep(10);

      Assert.AreEqual(2, TInterlocked.CompareExchange(Count, 0, 0));
    finally
      Gate.Free;
      Started.Free;
    end;
  finally
    Cron.Free;
  end;
end;

procedure TTestMaxCron.Overlap_Serialize_QueuesAllPending;
var
  Cron: TmaxCron;
  Evt: TmaxCronEvent;
  Started: TEvent;
  Gate: TEvent;
  Count: Integer;
  WaitRes: TWaitResult;
  i: Integer;
  Sw: TStopwatch;
begin
  Count := 0;
  Cron := TmaxCron.Create(ctPortable);
  try
    Started := TEvent.Create(nil, True, False, '');
    Gate := TEvent.Create(nil, True, False, '');
    try
      Evt := Cron.Add('Serialize');
      Evt.EventPlan := '* * * * * * * 0';
      Evt.InvokeMode := imThread;
      Evt.OverlapMode := omSerialize;
      Evt.OnScheduleProc :=
        procedure(Sender: TmaxCronEvent)
        begin
          TInterlocked.Increment(Count);
          Started.SetEvent;
          Gate.WaitFor(5000);
        end;
      Evt.Run;

      Cron.TickAt(Evt.NextSchedule);
      WaitRes := Started.WaitFor(2000);
      Assert.AreEqual(TWaitResult.wrSignaled, WaitRes);

      for i := 1 to 3 do
        Cron.TickAt(IncSecond(Evt.NextSchedule, 10));

      Gate.SetEvent;

      Sw := TStopwatch.StartNew;
      while (TInterlocked.CompareExchange(Count, 0, 0) < 4) and (Sw.ElapsedMilliseconds < 5000) do
        TThread.Sleep(10);

      Assert.AreEqual(4, TInterlocked.CompareExchange(Count, 0, 0));
    finally
      Gate.Free;
      Started.Free;
    end;
  finally
    Cron.Free;
  end;
end;

end.

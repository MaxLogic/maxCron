unit TestValidRange;

interface

uses
  System.DateUtils, System.Diagnostics, System.SysUtils, System.SyncObjs,
  DUnitX.TestFramework,
  maxCron;

type
  [TestFixture]
  TTestValidRange = class
  public
    [Test]
    procedure ValidFromTo_StopsOutsideWindow;
  end;

implementation

procedure TTestValidRange.ValidFromTo_StopsOutsideWindow;
var
  Cron: TmaxCron;
  Evt: TmaxCronEvent;
  Count: Integer;
  StartAt: TDateTime;
  StopAt: TDateTime;
  Sw: TStopwatch;
begin
  Count := 0;
  Cron := TmaxCron.Create(ctPortable);
  try
    Evt := Cron.Add('Range', '* * * * * * * 0');
    Evt.InvokeMode := imThread;
    Evt.OverlapMode := omAllowOverlap;
    Evt.OnScheduleProc :=
      procedure(Sender: TmaxCronEvent)
      begin
        TInterlocked.Increment(Count);
      end;

    StartAt := EncodeDateTime(2025, 1, 1, 0, 0, 5, 0);
    StopAt := EncodeDateTime(2025, 1, 1, 0, 0, 7, 0);
    Evt.ValidFrom := StartAt;
    Evt.ValidTo := StopAt;
    Evt.Run;

    Cron.TickAt(EncodeDateTime(2025, 1, 1, 0, 0, 4, 0)); // before window
    Cron.TickAt(EncodeDateTime(2025, 1, 1, 0, 0, 5, 0)); // inside window
    Cron.TickAt(EncodeDateTime(2025, 1, 1, 0, 0, 6, 0)); // inside window
    Cron.TickAt(EncodeDateTime(2025, 1, 1, 0, 0, 8, 0)); // after window

    Sw := TStopwatch.StartNew;
    while (TInterlocked.CompareExchange(Count, 0, 0) < 2) and (Sw.ElapsedMilliseconds < 3000) do
      TThread.Sleep(10);

    Assert.IsTrue(TInterlocked.CompareExchange(Count, 0, 0) <= 2);
  finally
    Cron.Free;
  end;
end;

end.


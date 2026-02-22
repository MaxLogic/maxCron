unit TestMisfirePolicy;

interface

uses
  System.Classes, System.DateUtils, System.Diagnostics, System.SyncObjs, System.SysUtils,
  DUnitX.TestFramework,
  maxCron;

type
  [TestFixture]
  TTestMisfirePolicy = class
  public
    [Test]
    procedure Misfire_Skip_SkipsExecution;

    [Test]
    procedure Misfire_FireOnceNow_OverridesDefault;

    [Test]
    procedure Misfire_CatchUpAll_Bounded;

    [Test]
    procedure DefaultMisfirePolicy_ImDefault_NormalizesToCatchUpAll;

    [Test]
    procedure DefaultMisfirePolicy_ImDefault_UsesConfiguredCatchUpLimit;
  end;

implementation

procedure TTestMisfirePolicy.Misfire_Skip_SkipsExecution;
var
  lCron: TmaxCron;
  lEvt: TmaxCronEvent;
  lCount: Integer;
  lTickTime: TDateTime;
  lSw: TStopwatch;
begin
  lCount := 0;
  lCron := TmaxCron.Create(ctPortable);
  try
    lCron.DefaultMisfirePolicy := TmaxCronMisfirePolicy.mpSkip;

    lEvt := lCron.Add('MisfireSkip');
    lEvt.EventPlan := '* * * * * * * 0';
    lEvt.InvokeMode := imThread;
    lEvt.OnScheduleProc :=
      procedure(Sender: TmaxCronEvent)
      begin
        TInterlocked.Increment(lCount);
      end;
    lEvt.Run;

    lTickTime := IncSecond(lEvt.NextSchedule, 10);
    lCron.TickAt(lTickTime);

    lSw := TStopwatch.StartNew;
    while (lSw.ElapsedMilliseconds < 300) do
      TThread.Sleep(10);

    Assert.AreEqual(0, TInterlocked.CompareExchange(lCount, 0, 0));
    Assert.IsTrue(lEvt.NextSchedule > lTickTime);
  finally
    lCron.Free;
  end;
end;

procedure TTestMisfirePolicy.Misfire_FireOnceNow_OverridesDefault;
var
  lCron: TmaxCron;
  lEvt: TmaxCronEvent;
  lCount: Integer;
  lTickTime: TDateTime;
  lHit: TEvent;
  lWaitRes: TWaitResult;
begin
  lCount := 0;
  lCron := TmaxCron.Create(ctPortable);
  lHit := TEvent.Create(nil, True, False, '');
  try
    lCron.DefaultMisfirePolicy := TmaxCronMisfirePolicy.mpSkip;

    lEvt := lCron.Add('MisfireOnce');
    lEvt.EventPlan := '* * * * * * * 0';
    lEvt.InvokeMode := imThread;
    lEvt.MisfirePolicy := TmaxCronMisfirePolicy.mpFireOnceNow;
    lEvt.OnScheduleProc :=
      procedure(Sender: TmaxCronEvent)
      begin
        TInterlocked.Increment(lCount);
        lHit.SetEvent;
      end;
    lEvt.Run;

    lTickTime := IncSecond(lEvt.NextSchedule, 10);
    lCron.TickAt(lTickTime);

    lWaitRes := lHit.WaitFor(2000);
    Assert.AreEqual(TWaitResult.wrSignaled, lWaitRes);
    Assert.AreEqual(1, TInterlocked.CompareExchange(lCount, 0, 0));
    Assert.IsTrue(lEvt.NextSchedule > lTickTime);
  finally
    lHit.Free;
    lCron.Free;
  end;
end;

procedure TTestMisfirePolicy.Misfire_CatchUpAll_Bounded;
var
  lCron: TmaxCron;
  lEvt: TmaxCronEvent;
  lCount: Integer;
  lTickTime: TDateTime;
  lDone: TEvent;
  lWaitRes: TWaitResult;
begin
  lCount := 0;
  lCron := TmaxCron.Create(ctPortable);
  lDone := TEvent.Create(nil, True, False, '');
  try
    lCron.DefaultMisfirePolicy := TmaxCronMisfirePolicy.mpCatchUpAll;
    lCron.DefaultMisfireCatchUpLimit := 3;

    lEvt := lCron.Add('MisfireCatchUp');
    lEvt.EventPlan := '* * * * * * * 0';
    lEvt.InvokeMode := imThread;
    lEvt.OnScheduleProc :=
      procedure(Sender: TmaxCronEvent)
      begin
        if TInterlocked.Increment(lCount) >= 3 then
          lDone.SetEvent;
      end;
    lEvt.Run;

    lTickTime := IncSecond(lEvt.NextSchedule, 5);
    lCron.TickAt(lTickTime);

    lWaitRes := lDone.WaitFor(2000);
    Assert.AreEqual(TWaitResult.wrSignaled, lWaitRes);
    TThread.Sleep(200);
    Assert.AreEqual(3, TInterlocked.CompareExchange(lCount, 0, 0));
    Assert.IsTrue(lEvt.NextSchedule < lTickTime);
  finally
    lDone.Free;
    lCron.Free;
  end;
end;

procedure TTestMisfirePolicy.DefaultMisfirePolicy_ImDefault_NormalizesToCatchUpAll;
var
  lCron: TmaxCron;
begin
  lCron := TmaxCron.Create(ctPortable);
  try
    lCron.DefaultMisfirePolicy := TmaxCronMisfirePolicy.mpDefault;
    Assert.AreEqual(TmaxCronMisfirePolicy.mpCatchUpAll, lCron.DefaultMisfirePolicy);
  finally
    lCron.Free;
  end;
end;

procedure TTestMisfirePolicy.DefaultMisfirePolicy_ImDefault_UsesConfiguredCatchUpLimit;
var
  lCron: TmaxCron;
  lEvt: TmaxCronEvent;
  lCount: Integer;
  lTickTime: TDateTime;
begin
  lCount := 0;
  lCron := TmaxCron.Create(ctPortable);
  try
    lCron.DefaultMisfirePolicy := TmaxCronMisfirePolicy.mpDefault;
    lCron.DefaultMisfireCatchUpLimit := 3;

    lEvt := lCron.Add('MisfireDefaultPolicyNormalization');
    lEvt.EventPlan := '* * * * * * * 0';
    lEvt.InvokeMode := imMainThread;
    lEvt.OnScheduleProc :=
      procedure(aSender: TmaxCronEvent)
      begin
        Inc(lCount);
      end;
    lEvt.Run;

    lTickTime := IncSecond(lEvt.NextSchedule, 5);
    lCron.TickAt(lTickTime);

    Assert.AreEqual(3, lCount, 'Expected catch-up to honor DefaultMisfireCatchUpLimit after normalization');
    Assert.IsTrue(lEvt.NextSchedule < lTickTime);
  finally
    lCron.Free;
  end;
end;

end.

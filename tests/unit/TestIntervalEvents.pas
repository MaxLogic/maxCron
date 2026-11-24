unit TestIntervalEvents;
interface
uses
  System.Classes, System.SyncObjs, System.SysUtils, System.Threading,
  DUnitX.TestFramework,
  maxCron, TestEnvironment;
type
  [TestFixture]
  TTestIntervalEvents = class
  private
    procedure CheckCompletionOwnership(const aRoute, aMutation, aOrder, aIntervalMs: Integer;
      const aOverlap: TmaxCronOverlapMode);
  public
    [Test] procedure SerializedRestartOwnsCompletion;
    [Test] procedure RestoreOriginShiftInvariant;
    [Test] procedure CompletionOwnershipInvariant;
    [Test] procedure FixedRateIntegerModel;
    [Test] procedure ViewsLimitsAndPlanSwitch;
    [Test] procedure ValidityAndIgnoredCronProperties;
    [Test] procedure PersistenceProjection;
    [Test] procedure RestoreOverduePolicies;
    [Test] procedure PlanSwitchEngines;
    [Test] procedure IntervalDialectAfterCron;
    [Test] procedure FixedDelayCompletion;
    [Test] procedure FixedDelayIntegerModel;
    [Test] procedure CatchUpPacing;
    [Test] procedure FixedDelayExitPaths;
    [Test] procedure FixedDelayQueuedFailure;
    [Test] procedure DueBatchSurvivesDispatchFailure;
  end;
type
  TIntervalMemoryStore = class(TInterfacedObject, IMaxCronScheduleStore)
  public
    fStates: TArray<TMaxCronPersistedEvent>;
    procedure Save(const aEvents: TArray<TMaxCronPersistedEvent>);
    function TryLoad(out aEvents: TArray<TMaxCronPersistedEvent>): Boolean;
  end;
implementation

uses
  {$IFDEF MSWINDOWS} Winapi.Windows, {$ENDIF}
  maxCron.Internal.Platform;

function TestTickCount64: UInt64;
begin
  {$IFDEF MSWINDOWS}
  Result := GetTickCount64;
  {$ELSE}
  Result := UInt64(CronMonotonicNowUs div 1000);
  {$ENDIF}
end;
procedure TIntervalMemoryStore.Save(const aEvents: TArray<TMaxCronPersistedEvent>);
begin fStates := Copy(aEvents); end;
function TIntervalMemoryStore.TryLoad(out aEvents: TArray<TMaxCronPersistedEvent>): Boolean;
begin aEvents := Copy(fStates); Result := True; end;
procedure TTestIntervalEvents.FixedRateIntegerModel;
const
  cOffsets: array[0..14] of Int64 = (-1,0,1,499,500,999,1000,99999,100000,100001,
    150000,319999,320000,999999,1000000);
  cWall: Int64 = 4000000000000000;
var
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lPolicy: TmaxCronMisfirePolicy;
  lMono,lWall,lDue,lNext,lLast,lMissed: Int64;
  lFires,lExpected,lLimit,i: Integer;
begin
  lMono := 1000000; lWall := cWall;
  SetMaxCronMonotonicClockHook(function: Int64 begin Result := lMono; end);
  SetMaxCronWallClockHook(function: Int64 begin Result := lWall; end);
  try
    for lPolicy := mpSkip to mpCatchUpAll do
      for lLimit := 1 to 3 do
        for i := Low(cOffsets) to High(cOffsets) do
        begin
          lMono := 1000000; lWall := cWall; lFires := 0;
          lCron := TmaxCron.Create(ctPortable);
          try
            lCron.DefaultMisfirePolicy := lPolicy;
            lCron.DefaultMisfireCatchUpLimit := lLimit;
            lEvent := lCron.Add('model','@every 100ms',
              procedure(aSender: IMaxCronEvent) begin Inc(lFires); end);
            lEvent.InvokeMode := imMainThread;
            lEvent.Run;
            lDue := 1100000;
            lMono := lDue+cOffsets[i]; lWall := cWall+lMono-1000000;
            lExpected := 0; lNext := lDue; lLast := 0;
            if cOffsets[i]>=0 then
            begin
              lMissed := cOffsets[i] div 100000;
              if lMissed=0 then lExpected := 1
              else if lPolicy=mpFireOnceNow then lExpected := 1
              else if lPolicy=mpCatchUpAll then
              begin
                lExpected := Integer(lMissed+1);
                if lExpected>lLimit then lExpected := lLimit;
              end;
              if lPolicy=mpCatchUpAll then lNext := lDue+lExpected*100000
              else lNext := lDue+(lMissed+1)*100000;
              if lExpected>0 then
              begin
                if lPolicy=mpFireOnceNow then lLast := lDue+lMissed*100000
                else lLast := lDue+(lExpected-1)*100000;
              end;
            end;
            lCron.TickAtUs(lWall);
            Assert.AreEqual(lExpected,lFires,'fires offset '+IntToStr(cOffsets[i]));
            Assert.AreEqual<Int64>((cWall+lNext-1000000) div 1000,
              CronDateTimeToMs(lEvent.NextSchedule),'next');
            if lLast>0 then
              Assert.AreEqual<Int64>((cWall+lLast-1000000) div 1000,
                CronDateTimeToMs(lEvent.LastExecution),'last');
          finally
            lEvent := nil; lCron.Free;
          end;
        end;
  finally
    SetMaxCronMonotonicClockHook(nil); SetMaxCronWallClockHook(nil);
  end;
end;
procedure TTestIntervalEvents.ViewsLimitsAndPlanSwitch;
var
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lView: IMaxCronIntervalEvent;
  lMono,lWall: Int64;
  lCount,i: Integer;
begin
  lMono := 100000000; lWall := 4000000000000000; lCount := 0;
  SetMaxCronMonotonicClockHook(function: Int64 begin Result := lMono; end);
  SetMaxCronWallClockHook(function: Int64 begin Result := lWall; end);
  lCron := TmaxCron.Create(ctPortable);
  try
    Assert.WillRaiseWithMessage(procedure begin lCron.AddInterval('invalid',0); end,
      Exception,'Interval plan value out of range');
    Assert.AreEqual<NativeInt>(0,Length(lCron.Snapshot));
    lEvent := lCron.AddInterval('view',100,
      procedure(aSender: IMaxCronEvent) begin Inc(lCount); end);
    Assert.IsFalse(lEvent.Enabled);
    Assert.IsTrue(Supports(lEvent,IMaxCronIntervalEvent,lView));
    Assert.IsTrue(lView.IsInterval);
    Assert.AreEqual<Cardinal>(100,lView.IntervalMs);
    Assert.IsTrue(lView.IntervalMode=ivFixedRate);
    lEvent.EventPlan := '@every 100ms limit 3'; lEvent.InvokeMode := imMainThread; lEvent.Run;
    for i := 1 to 4 do
    begin
      Inc(lMono,100000); Inc(lWall,100000); lCron.TickAtUs(lWall);
    end;
    Assert.AreEqual(3,lCount); Assert.IsFalse(lEvent.Enabled);
    Assert.AreEqual<UInt64>(3,lEvent.NumOfExecutionsPerformed);
    lEvent.EventPlan := '* * * * * * *'; lEvent.Run;
    Assert.IsFalse(lView.IsInterval); Assert.AreEqual<Cardinal>(0,lView.IntervalMs);
    Assert.IsTrue(lView.IntervalMode=ivFixedRate);
    lEvent.EventPlan := '@every 1ms';
    Inc(lMono,1000); Inc(lWall,1000); lCron.TickAtUs(lWall);
    Assert.AreEqual(4,lCount);
    lEvent.Stop; Assert.AreEqual<TDateTime>(0,lEvent.NextSchedule);
    Assert.WillRaiseWithMessage(procedure begin lEvent.EventPlan := '@every5s'; end,
      Exception,'Unknown cron macro');
  finally
    lView := nil; lEvent := nil; lCron.Free;
    SetMaxCronMonotonicClockHook(nil); SetMaxCronWallClockHook(nil);
  end;
end;

procedure TTestIntervalEvents.ValidityAndIgnoredCronProperties;
const cWall: Int64 = 4000000000000000;
var
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lMono,lWall,lNext: Int64;
  lCount: Integer;
begin
  lMono := 100000000; lWall := cWall; lCount := 0;
  SetMaxCronMonotonicClockHook(function: Int64 begin Result := lMono; end);
  SetMaxCronWallClockHook(function: Int64 begin Result := lWall; end);
  lCron := TmaxCron.Create(ctPortable);
  try
    lEvent := lCron.AddInterval('valid',100,
      procedure(aSender: IMaxCronEvent) begin Inc(lCount); end);
    lEvent.InvokeMode := imMainThread; lEvent.ValidFrom := CronMsToDateTime(cWall div 1000+500);
    lEvent.ValidTo := CronMsToDateTime(cWall div 1000+600); lEvent.Run;
    lNext := CronDateTimeToMs(lEvent.NextSchedule);
    Assert.AreEqual<Int64>(cWall div 1000+500,lNext);
    lEvent.TimeZoneId := 'UTC+05:30'; lEvent.DstSpringPolicy := dspRunAtNextValidTime;
    lEvent.DstFallPolicy := dfpRunTwice; lEvent.WeekdaysOnly := True;
    lEvent.ExcludedDatesCsv := '2026-11-17'; lEvent.BlackoutStartTime := 0.25;
    lEvent.BlackoutEndTime := 0.75; lEvent.DayMatchMode := dmOr; lEvent.Dialect := cdStandard;
    Assert.AreEqual<Int64>(lNext,CronDateTimeToMs(lEvent.NextSchedule),'cron properties restarted phase');
    Inc(lMono,499999); Inc(lWall,499999); lCron.TickAtUs(lWall); Assert.AreEqual(0,lCount);
    Inc(lMono); Inc(lWall); lCron.TickAtUs(lWall); Assert.AreEqual(1,lCount);
    Inc(lMono,100000); Inc(lWall,100000); lCron.TickAtUs(lWall); Assert.AreEqual(2,lCount,'ValidTo equality');
    Inc(lMono,100000); Inc(lWall,100000); lCron.TickAtUs(lWall);
    Assert.AreEqual(2,lCount); Assert.IsFalse(lEvent.Enabled);
    lEvent.ValidTo := CronMsToDateTime(cWall div 1000); lEvent.Run; Assert.IsFalse(lEvent.Enabled);
    // A backwards wall jump projects the due before ValidFrom and re-keys without firing.
    lEvent.ValidTo := 0; lEvent.ValidFrom := CronMsToDateTime(lWall div 1000+100);
    lEvent.Run; Inc(lMono,100000); Dec(lWall,1000000); lCron.TickAtUs(lWall);
    Assert.AreEqual(2,lCount);
    Assert.AreEqual<Int64>(cWall div 1000+800,CronDateTimeToMs(lEvent.NextSchedule));
  finally
    lEvent := nil; lCron.Free;
    SetMaxCronMonotonicClockHook(nil); SetMaxCronWallClockHook(nil);
  end;
end;

procedure TTestIntervalEvents.PersistenceProjection;
const
  cWall: Int64 = 4000000000000000;
  cOffsets: array[0..3] of Integer = (2000,9000,-12000,0);
  cNext: array[0..3] of Integer = (2000,5000,-12000,5000);
var
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lView: IMaxCronIntervalEvent;
  lStoreObject: TIntervalMemoryStore;
  lStore: IMaxCronScheduleStore;
  lMono,lWall: Int64;
  i: Integer;
begin
  lMono := 100000000; lWall := cWall;
  SetMaxCronMonotonicClockHook(function: Int64 begin Result := lMono; end);
  SetMaxCronWallClockHook(function: Int64 begin Result := lWall; end);
  lStoreObject := TIntervalMemoryStore.Create; lStore := lStoreObject;
  lCron := TmaxCron.Create(ctPortable);
  try
    lCron.ScheduleStore := lStore;
    lEvent := lCron.Add('persist','@every 5s fixed-delay limit 3',
      procedure(aSender: IMaxCronEvent) begin end);
    lEvent.Run; Assert.AreEqual(1,lCron.SaveScheduleState);
    lStoreObject.fStates[0].NumOfExecutionsPerformed := 2;
    // Phase 6 design 5.1: zero selects the unchanged legacy NextSchedule path.
    // A positive checkpoint intentionally ignores the edited NextSchedule below.
    lStoreObject.fStates[0].CompletedThrough := 0;
    for i := 0 to 3 do
    begin
      if cOffsets[i]=0 then lStoreObject.fStates[0].NextSchedule := 0
      else lStoreObject.fStates[0].NextSchedule := CronMsToDateTime(cWall div 1000+cOffsets[i]);
      Assert.AreEqual(1,lCron.RestoreScheduleState);
      lEvent := lCron.Snapshot[0];
      Assert.IsTrue(Supports(lEvent,IMaxCronIntervalEvent,lView));
      Assert.IsTrue(lView.IntervalMode=ivFixedDelay);
      Assert.AreEqual<Cardinal>(5000,lView.IntervalMs);
      Assert.AreEqual<UInt64>(2,lEvent.NumOfExecutionsPerformed);
      Assert.AreEqual<Int64>(cWall div 1000+cNext[i],CronDateTimeToMs(lEvent.NextSchedule));
    end;
    lStoreObject.fStates[0].Enabled := False; lCron.RestoreScheduleState;
    lEvent := lCron.Snapshot[0]; Assert.IsFalse(lEvent.Enabled);
    Assert.AreEqual<TDateTime>(0,lEvent.NextSchedule);
  finally
    lView := nil; lEvent := nil; lCron.Free; lStore := nil;
    SetMaxCronMonotonicClockHook(nil); SetMaxCronWallClockHook(nil);
  end;
end;

procedure TTestIntervalEvents.FixedDelayCompletion;
const cWall: Int64 = 4000000000000000;
var
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lMono,lWall: Int64;
  lCount: Integer;
begin
  lMono := 100000000; lWall := cWall; lCount := 0;
  SetMaxCronMonotonicClockHook(function: Int64 begin Result := lMono; end);
  SetMaxCronWallClockHook(function: Int64 begin Result := lWall; end);
  lCron := TmaxCron.Create(ctPortable);
  try
    lEvent := lCron.AddInterval('delay',100,
      procedure(aSender: IMaxCronEvent)
      begin
        Assert.AreEqual<TDateTime>(0,aSender.NextSchedule,'awaiting completion');
        Inc(lCount); Inc(lMono,30000); Inc(lWall,30000);
      end,ivFixedDelay);
    lEvent.InvokeMode := imMainThread; lEvent.Run;
    Inc(lMono,100300); Inc(lWall,100300); lCron.TickAtUs(lWall);
    Assert.AreEqual(1,lCount);
    Assert.AreEqual<Int64>((cWall+230300) div 1000,CronDateTimeToMs(lEvent.NextSchedule));
  finally
    lEvent := nil; lCron.Free;
    SetMaxCronMonotonicClockHook(nil); SetMaxCronWallClockHook(nil);
  end;
end;

procedure TTestIntervalEvents.FixedDelayExitPaths;
const cWall: Int64 = 4000000000000000;
var
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lMono,lWall: Int64;
  lMode: TmaxCronOverlapMode;
  lCount,lAttempt: Integer;
begin
  lMono := 100000000; lWall := cWall;
  SetMaxCronMonotonicClockHook(function: Int64 begin Result := lMono; end);
  SetMaxCronWallClockHook(function: Int64 begin Result := lWall; end);
  lCron := TmaxCron.Create(ctPortable);
  try
    lCount := 0;
    lEvent := lCron.AddInterval('exit',100,
      procedure(aSender: IMaxCronEvent) begin Inc(lCount); end,ivFixedDelay);
    lEvent.InvokeMode := imMainThread;
    for lMode := omAllowOverlap to omSerializeCoalesce do
    begin
      lEvent.OverlapMode := lMode; lEvent.Run;
      SetMaxCronBeforeDispatchHook(procedure(const aMode: TmaxCronInvokeMode)
        begin raise Exception.Create('dispatch-start'); end);
      Inc(lMono,100000); Inc(lWall,100000);
      Assert.WillRaiseWithMessage(procedure begin lCron.TickAtUs(lWall); end,Exception,'dispatch-start');
      Assert.AreEqual<Int64>((lWall+100000) div 1000,CronDateTimeToMs(lEvent.NextSchedule),'rollback rearm');
      SetMaxCronBeforeDispatchHook(nil);
      Inc(lMono,99999); Inc(lWall,99999); lCron.TickAtUs(lWall);
      Assert.AreEqual(0,lCount,'never early');
      Inc(lMono); Inc(lWall); lCron.TickAtUs(lWall);
      Assert.AreEqual(1,lCount); lCount := 0;
    end;
    lEvent.OnScheduleProc := nil; lEvent.Run;
    Inc(lMono,100000); Inc(lWall,100000); lCron.TickAtUs(lWall);
    Assert.AreEqual<Int64>((lWall+100000) div 1000,CronDateTimeToMs(lEvent.NextSchedule),'no callbacks');
    lEvent.OnScheduleProc := procedure(aSender: IMaxCronEvent)
      begin Inc(lCount); raise Exception.Create('callback'); end;
    lEvent.RetryMaxAttempts := 2; lEvent.Run;
    Inc(lMono,100000); Inc(lWall,100000); lCron.TickAtUs(lWall);
    Assert.AreEqual(3,lCount,'retry policy');
    Assert.AreEqual<Int64>((lWall+100000) div 1000,CronDateTimeToMs(lEvent.NextSchedule),'exception rearm');
    lEvent.OnScheduleProc := procedure(aSender: IMaxCronEvent) begin aSender.Stop; end;
    Inc(lMono,100000); Inc(lWall,100000); lCron.TickAtUs(lWall);
    Assert.AreEqual<TDateTime>(0,lEvent.NextSchedule,'Stop during dispatch');
    // Restart while a skip-if-running callback is in flight. The synchronous nested tick is refused.
    lAttempt := 0; lEvent.RetryMaxAttempts := 0; lEvent.OverlapMode := omSkipIfRunning;
    lEvent.OnScheduleProc := procedure(aSender: IMaxCronEvent)
      begin
        Inc(lAttempt);
        if lAttempt=1 then
        begin
          aSender.Run;
          Inc(lMono,100000); Inc(lWall,100000); lCron.TickAtUs(lWall);
          Assert.AreEqual<Int64>((lWall+100000) div 1000,CronDateTimeToMs(aSender.NextSchedule),'overlap skip rearm');
        end;
      end;
    lEvent.Run; Inc(lMono,100000); Inc(lWall,100000); lCron.TickAtUs(lWall);
    Assert.AreEqual(1,lAttempt);
    Assert.AreEqual<Int64>((lWall+100000) div 1000,CronDateTimeToMs(lEvent.NextSchedule));
    // A reserved run rejected by the existing global permit path still completes.
    lCron.GlobalMaxConcurrentCallbacks := 1;
    lEvent.Run;
    SetMaxCronBeforeDispatchHook(procedure(const aMode: TmaxCronInvokeMode)
      begin lCron.Shutdown(0,spWait); end);
    Inc(lMono,100000); Inc(lWall,100000); lCron.TickAtUs(lWall);
    Assert.AreEqual(1,lAttempt,'shutdown/global permit rejection');
    Assert.AreEqual<Int64>((lWall+100000) div 1000,CronDateTimeToMs(lEvent.NextSchedule),'completion after rejected permit');
  finally
    SetMaxCronBeforeDispatchHook(nil);
    lEvent := nil; lCron.Free;
    SetMaxCronMonotonicClockHook(nil); SetMaxCronWallClockHook(nil);
  end;
end;

procedure TTestIntervalEvents.FixedDelayQueuedFailure;
const cWall: Int64 = 4000000000000000;
var
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lMono,lWall: Int64;
  lThread: TThread;
  lCount: Integer;
begin
  lMono := 100000000; lWall := cWall; lCount := 0;
  SetMaxCronMonotonicClockHook(function: Int64 begin Result := lMono; end);
  SetMaxCronWallClockHook(function: Int64 begin Result := lWall; end);
  lCron := TmaxCron.Create(ctPortable);
  try
    lEvent := lCron.AddInterval('queued',100,
      procedure(aSender: IMaxCronEvent) begin Inc(lCount); end,ivFixedDelay);
    lEvent.InvokeMode := imMainThread; lEvent.Run;
    SetMaxCronBeforeQueuedAcquireHook(procedure(const aEvent: IMaxCronEvent)
      begin raise Exception.Create('queued acquire'); end);
    Inc(lMono,100000); Inc(lWall,100000);
    lThread := TThread.CreateAnonymousThread(procedure begin lCron.TickAtUs(lWall); end);
    lThread.FreeOnTerminate := False;
    try
      lThread.Start; lThread.WaitFor;
      CheckSynchronize(0);
    finally lThread.Free; end;
    Assert.AreEqual(0,lCount);
    Assert.AreEqual<Int64>((lWall+100000) div 1000,CronDateTimeToMs(lEvent.NextSchedule),'queued failure rearm');
    SetMaxCronBeforeQueuedAcquireHook(nil);
    Inc(lMono,100000); Inc(lWall,100000); lCron.TickAtUs(lWall);
    Assert.AreEqual(1,lCount);
  finally
    SetMaxCronBeforeQueuedAcquireHook(nil);
    lEvent := nil; lCron.Free;
    SetMaxCronMonotonicClockHook(nil); SetMaxCronWallClockHook(nil);
  end;
end;

procedure TTestIntervalEvents.DueBatchSurvivesDispatchFailure;
var
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lMono,lWall: Int64;
  lCount: Integer;
begin
  lMono := 100000000; lWall := 4000000000000000; lCount := 0;
  SetMaxCronMonotonicClockHook(function: Int64 begin Result := lMono; end);
  SetMaxCronWallClockHook(function: Int64 begin Result := lWall; end);
  lCron := TmaxCron.Create(ctPortable);
  try
    lCron.DefaultInvokeMode := imMainThread;
    lCron.AddInterval('first',100,procedure(aSender: IMaxCronEvent) begin end,ivFixedDelay).Run;
    lEvent := lCron.AddInterval('second',100,
      procedure(aSender: IMaxCronEvent) begin Inc(lCount); end);
    lEvent.Run;
    SetMaxCronBeforeDispatchHook(procedure(const aMode: TmaxCronInvokeMode)
      begin raise Exception.Create('batch failure'); end);
    Inc(lMono,100000); Inc(lWall,100000);
    Assert.WillRaiseWithMessage(procedure begin lCron.TickAtUs(lWall); end,Exception,'batch failure');
    SetMaxCronBeforeDispatchHook(nil);
    lCron.TickAtUs(lWall);
    Assert.AreEqual(1,lCount,'second popped event must remain scheduled');
  finally
    SetMaxCronBeforeDispatchHook(nil);
    lEvent := nil; lCron.Free;
    SetMaxCronMonotonicClockHook(nil); SetMaxCronWallClockHook(nil);
  end;
end;

procedure TTestIntervalEvents.FixedDelayIntegerModel;
const
  cWall: Int64 = 4000000000000000;
  cOffsets: array[0..7] of Int64 = (-1,0,1,99999,100000,100001,319999,320000);
var
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lMono,lWall,lNext: Int64;
  lCount,lExpected,i: Integer;
  lPolicy: TmaxCronMisfirePolicy;
begin
  lMono := 100000000; lWall := cWall;
  SetMaxCronMonotonicClockHook(function: Int64 begin Result := lMono; end);
  SetMaxCronWallClockHook(function: Int64 begin Result := lWall; end);
  try
    for lPolicy := mpSkip to mpCatchUpAll do
      for i := Low(cOffsets) to High(cOffsets) do
      begin
        lMono := 100000000; lWall := cWall; lCount := 0;
        lCron := TmaxCron.Create(ctPortable);
        try
          lEvent := lCron.AddInterval('delay model',100,
            procedure(aSender: IMaxCronEvent)
            begin Inc(lCount); Inc(lMono,30000); Inc(lWall,30000); end,ivFixedDelay);
          lEvent.InvokeMode := imMainThread; lEvent.MisfirePolicy := lPolicy; lEvent.Run;
          Inc(lMono,100000+cOffsets[i]); Inc(lWall,100000+cOffsets[i]);
          lExpected := 0; lNext := cWall+100000;
          if cOffsets[i]>=0 then
          begin
            lNext := lWall+100000;
            if (lPolicy<>mpSkip) or (cOffsets[i]<100000) then
            begin lExpected := 1; Inc(lNext,30000); end;
          end;
          lCron.TickAtUs(lWall);
          Assert.AreEqual(lExpected,lCount,'delay offset '+IntToStr(cOffsets[i]));
          Assert.AreEqual<Int64>(lNext div 1000,CronDateTimeToMs(lEvent.NextSchedule),'delay next');
        finally lEvent := nil; lCron.Free; end;
      end;
  finally SetMaxCronMonotonicClockHook(nil); SetMaxCronWallClockHook(nil); end;
end;

procedure TTestIntervalEvents.CatchUpPacing;
const cWall: Int64 = 4000000000000000;
var
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lMono,lWall: Int64;
  lCount: Integer;
begin
  lMono := 100000000; lWall := cWall; lCount := 0;
  SetMaxCronMonotonicClockHook(function: Int64 begin Result := lMono; end);
  SetMaxCronWallClockHook(function: Int64 begin Result := lWall; end);
  lCron := TmaxCron.Create(ctPortable);
  try
    lCron.DefaultMisfirePolicy := mpCatchUpAll; lCron.DefaultMisfireCatchUpLimit := 3;
    lEvent := lCron.AddInterval('pace',100,
      procedure(aSender: IMaxCronEvent) begin Inc(lCount); end);
    lEvent.InvokeMode := imMainThread; lEvent.Run;
    Inc(lMono,420000); Inc(lWall,420000); lCron.TickAtUs(lWall); Assert.AreEqual(3,lCount);
    Assert.AreEqual<Int64>((cWall+400000) div 1000,CronDateTimeToMs(lEvent.NextSchedule));
    Inc(lMono,99999); Inc(lWall,99999); lCron.TickAtUs(lWall); Assert.AreEqual(3,lCount,'paced wake');
    Inc(lMono); Inc(lWall); lCron.TickAtUs(lWall); Assert.AreEqual(5,lCount);
    Assert.AreEqual<Int64>((cWall+600000) div 1000,CronDateTimeToMs(lEvent.NextSchedule));
  finally
    lEvent := nil; lCron.Free;
    SetMaxCronMonotonicClockHook(nil); SetMaxCronWallClockHook(nil);
  end;
end;

procedure TTestIntervalEvents.PlanSwitchEngines;
const cEngines: array[0..1] of string = ('heap','shadow');
var
  lEngine: string;
  lSavedEngine: TTestEnvSnapshot;
begin
  lSavedEngine := SaveTestEnvironmentVariable('MAXCRON_ENGINE');
  try
    for lEngine in cEngines do
    begin
      SetTestEnvironmentVariable('MAXCRON_ENGINE', lEngine);
      ViewsLimitsAndPlanSwitch;
    end;
  finally
    RestoreTestEnvironmentVariable(lSavedEngine);
  end;
end;

procedure TTestIntervalEvents.RestoreOverduePolicies;
const cWall: Int64 = 4000000000000000;
var
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lStoreObject: TIntervalMemoryStore;
  lStore: IMaxCronScheduleStore;
  lMono,lWall,lExpectedNext,lExpectedLast: Int64;
  lPolicy: TmaxCronMisfirePolicy;
  lCount,lExpected,i: Integer;
begin
  lMono := 100000000; lWall := cWall;
  SetMaxCronMonotonicClockHook(function: Int64 begin Result := lMono; end);
  SetMaxCronWallClockHook(function: Int64 begin Result := lWall; end);
  try
    for lPolicy := mpSkip to mpCatchUpAll do
      for i := 0 to 1 do
      begin
        lStoreObject := TIntervalMemoryStore.Create; lStore := lStoreObject;
        lCron := TmaxCron.Create(ctPortable); lCount := 0;
        try
          SetLength(lStoreObject.fStates,1);
          lStoreObject.fStates[0] := Default(TMaxCronPersistedEvent);
          lStoreObject.fStates[0].Name := 'restored overdue';
          if i=0 then lStoreObject.fStates[0].EventPlan := '@every 5s limit 3'
          else lStoreObject.fStates[0].EventPlan := '@every 5s fixed-delay limit 3';
          lStoreObject.fStates[0].Enabled := True;
          lStoreObject.fStates[0].InvokeMode := imMainThread;
          lStoreObject.fStates[0].Dialect := cdMaxCron;
          lStoreObject.fStates[0].TimeZoneId := 'LOCAL';
          lStoreObject.fStates[0].NextSchedule := CronMsToDateTime(cWall div 1000-12000);
          lStoreObject.fStates[0].NumOfExecutionsPerformed := 2;
          lCron.DefaultMisfirePolicy := lPolicy;
          lCron.DefaultMisfireCatchUpLimit := 3;
          lCron.ScheduleStore := lStore;
          Assert.AreEqual(1,lCron.RestoreScheduleState);
          lEvent := lCron.Snapshot[0];
          lEvent.OnScheduleProc := procedure(aSender: IMaxCronEvent) begin Inc(lCount); end;
          lCron.TickAtUs(lWall);
          if lPolicy=mpSkip then lExpected := 0 else lExpected := 1;
          Assert.AreEqual(lExpected,lCount,'restored policy');
          Assert.AreEqual<UInt64>(UInt64(2+lExpected),lEvent.NumOfExecutionsPerformed);
          if i=1 then lExpectedNext := cWall+5000000
          else if lPolicy=mpCatchUpAll then lExpectedNext := cWall+3000000
          else lExpectedNext := cWall+3000000;
          if (i=0) and (lPolicy=mpCatchUpAll) then
          begin
            // Three oldest occurrences were scheduled, but the unchanged limit admits only one.
            Assert.IsFalse(lEvent.Enabled);
            Assert.AreEqual<TDateTime>(0,lEvent.NextSchedule);
          end else
            Assert.AreEqual<Int64>(lExpectedNext div 1000,CronDateTimeToMs(lEvent.NextSchedule));
          if lExpected>0 then
          begin
            if (i=0) then lExpectedLast := cWall-2000000
            else lExpectedLast := cWall-12000000;
            Assert.AreEqual<Int64>(lExpectedLast div 1000,CronDateTimeToMs(lEvent.LastExecution));
          end;
        finally lEvent := nil; lCron.Free; lStore := nil; end;
      end;
  finally SetMaxCronMonotonicClockHook(nil); SetMaxCronWallClockHook(nil); end;
end;

procedure TTestIntervalEvents.IntervalDialectAfterCron;
const
  cPlans: array[TmaxCronDialect] of string =
    ('* * * * *', '* * * * * * * 0', '* * * * * *');
var
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lView: IMaxCronIntervalEvent;
  lSource, lTarget: TmaxCronDialect;
  lMono, lWall, lNext: Int64;
  lCount, i: Integer;
begin
  lMono := 100000000;
  lWall := 4000000000000000;
  SetMaxCronMonotonicClockHook(function: Int64 begin Result := lMono; end);
  SetMaxCronWallClockHook(function: Int64 begin Result := lWall; end);
  try
    for lSource := Low(TmaxCronDialect) to High(TmaxCronDialect) do
      for lTarget := Low(TmaxCronDialect) to High(TmaxCronDialect) do
        for i := 0 to 1 do
        begin
          lCron := TmaxCron.Create(ctPortable);
          try
            lCount := 0;
            lCron.DefaultDialect := lSource;
            lEvent := lCron.Add('dialect transition', cPlans[lSource],
              procedure(aSender: IMaxCronEvent) begin Inc(lCount); end);
            lEvent.InvokeMode := imMainThread;
            if i = 0 then
              lEvent.EventPlan := '@every 100ms'
            else
              lEvent.EventPlan := '@every 100ms fixed-delay';
            lEvent.Run;
            lNext := CronDateTimeToMs(lEvent.NextSchedule);
            lEvent.Dialect := lTarget;
            Assert.IsTrue(lEvent.Dialect = lTarget);
            Assert.AreEqual<Int64>(lNext, CronDateTimeToMs(lEvent.NextSchedule),
              'Dialect must preserve interval phase after a cron plan');
            Inc(lMono, 100000);
            Inc(lWall, 100000);
            lCron.TickAtUs(lWall);
            Assert.AreEqual(1, lCount);
            lEvent.EventPlan := cPlans[lTarget];
            Assert.IsTrue(Supports(lEvent, IMaxCronIntervalEvent, lView));
            Assert.IsFalse(lView.IsInterval);
            Assert.AreEqual(cPlans[lTarget], lEvent.EventPlan);
            Assert.IsTrue(lEvent.Enabled);
            Assert.IsTrue(lEvent.NextSchedule > 0);
          finally
            lView := nil;
            lEvent := nil;
            lCron.Free;
          end;
        end;
  finally
    SetMaxCronMonotonicClockHook(nil);
    SetMaxCronWallClockHook(nil);
  end;
end;


procedure TTestIntervalEvents.SerializedRestartOwnsCompletion;
const cWall: Int64 = 4000000000000000;
var
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lMono, lWall, lObserved: Int64;
  lCount: Integer;
begin
  lMono := 100000000; lWall := cWall; lCount := 0; lObserved := -1;
  SetMaxCronMonotonicClockHook(function: Int64 begin Result := lMono; end);
  SetMaxCronWallClockHook(function: Int64 begin Result := lWall; end);
  lCron := TmaxCron.Create(ctPortable);
  try
    lEvent := lCron.AddInterval('serialized restart',100,
      procedure(aSender: IMaxCronEvent)
      begin
        Inc(lCount);
        if lCount=1 then
        begin
          aSender.Run;
          Inc(lMono,100000); Inc(lWall,100000); lCron.TickAtUs(lWall);
        end else begin
          lObserved := CronDateTimeToMs(aSender.NextSchedule);
          Inc(lMono,30000); Inc(lWall,30000);
        end;
      end,ivFixedDelay);
    lEvent.InvokeMode := imMainThread; lEvent.OverlapMode := omSerialize; lEvent.Run;
    Inc(lMono,100000); Inc(lWall,100000); lCron.TickAtUs(lWall);
    Assert.AreEqual<TDateTime>(0,lEvent.NextSchedule,'older completion armed pending owner');
    CheckSynchronize(0);
    Assert.AreEqual(2,lCount);
    Assert.AreEqual<Int64>(0,lObserved,'new owner must remain awaiting during callback');
    Assert.AreEqual<Int64>((lWall+100000) div 1000,CronDateTimeToMs(lEvent.NextSchedule));
    Inc(lMono,70000); Inc(lWall,70000); lCron.TickAtUs(lWall);
    Assert.AreEqual(2,lCount,'100ms delay must not fire 70ms after owning completion');
  finally
    CheckSynchronize(0);
    lEvent := nil; lCron.Free;
    SetMaxCronMonotonicClockHook(nil); SetMaxCronWallClockHook(nil);
  end;
end;

procedure TTestIntervalEvents.RestoreOriginShiftInvariant;
const
  cWall: Int64 = 4000000000000000;
  cOrigins: array[0..7] of Int64 = (100000000,-1,0,1,-5000000,-10000000,-15000000,5000000);
  cOffsets: array[0..5] of Int64 = (0,5000000,10000000,15000000,20000000,25000000);
var
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lStoreObject: TIntervalMemoryStore;
  lStore: IMaxCronScheduleStore;
  lMono, lWall: Int64;
  lPolicy: TmaxCronMisfirePolicy;
  lMode: TmaxCronIntervalMode;
  lExpected: array[0..5,0..2] of Int64;
  lActual: array[0..2] of Int64;
  lCount, lOrigin, lStep, lLimit, i: Integer;
  lContext: string;
begin
  SetMaxCronMonotonicClockHook(function: Int64 begin Result := lMono; end);
  SetMaxCronWallClockHook(function: Int64 begin Result := lWall; end);
  try
    for lMode := ivFixedRate to ivFixedDelay do
      for lPolicy := mpSkip to mpCatchUpAll do
        for lLimit := 1 to 3 do
          for lOrigin := Low(cOrigins) to High(cOrigins) do
          begin
            lMono := 12000000+cOrigins[lOrigin]; lWall := cWall; lCount := 0;
            lCron := TmaxCron.Create(ctPortable);
            lStoreObject := TIntervalMemoryStore.Create; lStore := lStoreObject;
            try
              lCron.DefaultMisfirePolicy := lPolicy;
              lCron.DefaultMisfireCatchUpLimit := lLimit;
              SetLength(lStoreObject.fStates,1);
              lStoreObject.fStates[0] := Default(TMaxCronPersistedEvent);
              lStoreObject.fStates[0].Name := 'origin invariant';
              if lMode=ivFixedDelay then
                lStoreObject.fStates[0].EventPlan := '@every 5s fixed-delay'
              else lStoreObject.fStates[0].EventPlan := '@every 5s';
              lStoreObject.fStates[0].Enabled := True;
              lStoreObject.fStates[0].InvokeMode := imMainThread;
              lStoreObject.fStates[0].Dialect := cdMaxCron;
              lStoreObject.fStates[0].TimeZoneId := 'LOCAL';
              lStoreObject.fStates[0].NextSchedule := CronMsToDateTime((cWall-12000000) div 1000);
              lCron.ScheduleStore := lStore; lCron.RestoreScheduleState;
              lEvent := lCron.Snapshot[0];
              lEvent.OnScheduleProc := procedure(aSender: IMaxCronEvent) begin Inc(lCount); end;
              for lStep := Low(cOffsets) to High(cOffsets) do
              begin
                lMono := 12000000+cOrigins[lOrigin]+cOffsets[lStep];
                lWall := cWall+cOffsets[lStep];
                lCron.TickAtUs(lWall);
                lActual[0] := lCount;
                lActual[1] := CronDateTimeToMs(lEvent.NextSchedule);
                lActual[2] := CronDateTimeToMs(lEvent.LastExecution);
                lContext := Format('mode=%d policy=%d limit=%d origin=%d step=%d',
                  [Ord(lMode),Ord(lPolicy),lLimit,cOrigins[lOrigin],lStep]);
                if lOrigin=0 then
                  for i := 0 to 2 do lExpected[lStep,i] := lActual[i]
                else
                  for i := 0 to 2 do
                    Assert.AreEqual<Int64>(lExpected[lStep,i],lActual[i],lContext+' observation='+IntToStr(i));
                Assert.IsTrue(lEvent.NextSchedule<>0,'enabled restored event stalled: '+lContext);
              end;
              Assert.IsTrue(lCount>0,'no restored progress: '+lContext);
            finally
              lEvent := nil; lCron.Free; lStore := nil;
            end;
          end;
  finally
    SetMaxCronMonotonicClockHook(nil); SetMaxCronWallClockHook(nil);
  end;
end;

procedure TTestIntervalEvents.CheckCompletionOwnership(const aRoute, aMutation, aOrder,
  aIntervalMs: Integer; const aOverlap: TmaxCronOverlapMode);
const cWall: Int64 = 4000000000000000;
var
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lThread: TThread;
  lAStarted, lARelease, lAExited, lBStarted, lBRelease, lBExited, lCStarted: TEvent;
  lATask, lBTask, lCTask: ITask;
  lMono, lOrigin, lIntervalUs, lOwningEndUs, lDeadlineUs, lExpectedNext: Int64;
  lCount, lBadAwaiting, lIndex: Integer;
  lUntil: UInt64;
  lContext: string;
begin
  lOrigin := 100000000; lMono := lOrigin; lCount := 0; lBadAwaiting := 0;
  lIntervalUs := Int64(aIntervalMs)*1000; lOwningEndUs := 0;
  lContext := Format('route=%d mutation=%d order=%d interval=%d overlap=%d',
    [aRoute,aMutation,aOrder,aIntervalMs,Ord(aOverlap)]);
  lAStarted := TEvent.Create(nil,True,False,''); lARelease := TEvent.Create(nil,True,False,'');
  lAExited := TEvent.Create(nil,True,False,''); lBStarted := TEvent.Create(nil,True,False,'');
  lBRelease := TEvent.Create(nil,True,False,''); lBExited := TEvent.Create(nil,True,False,'');
  lCStarted := TEvent.Create(nil,True,False,'');
  SetMaxCronMonotonicClockHook(function: Int64 begin Result := TInterlocked.Read(lMono); end);
  SetMaxCronWallClockHook(function: Int64 begin Result := cWall+TInterlocked.Read(lMono)-lOrigin; end);
  if aRoute=1 then lCron := TmaxCron.Create(ctVcl) else lCron := TmaxCron.Create(ctPortable);
  try
    lEvent := lCron.AddInterval('ownership generator',aIntervalMs,
      procedure(aSender: IMaxCronEvent)
      var lRun: Integer;
      begin
        lRun := TInterlocked.Increment(lCount);
        if (lRun=2) and (aSender.NextSchedule<>0) then TInterlocked.Increment(lBadAwaiting);
        if lRun=1 then
        begin
          if aRoute>=2 then lATask := TTask.CurrentTask;
          lAStarted.SetEvent;
          if aRoute<2 then
          begin
            case aMutation of
              0: aSender.Run;
              1: begin aSender.EventPlan := '* * * * * * *'; aSender.EventPlan := '@every '+IntToStr(aIntervalMs)+'ms fixed-delay'; end;
              2: begin aSender.Enabled := False; aSender.Enabled := True; end;
            end;
            TInterlocked.Add(lMono,lIntervalUs);
            lCron.TickAtUs(cWall+TInterlocked.Read(lMono)-lOrigin);
          end else lARelease.WaitFor(5000);
          if aOrder=1 then TInterlocked.Add(lMono,lIntervalUs div 3);
          lAExited.SetEvent;
        end else if lRun=2 then
        begin
          if aRoute>=2 then lBTask := TTask.CurrentTask;
          lBStarted.SetEvent;
          if aRoute>=2 then lBRelease.WaitFor(5000);
          TInterlocked.Add(lMono,lIntervalUs div 3);
          TInterlocked.Exchange(lOwningEndUs,TInterlocked.Read(lMono));
          lBExited.SetEvent;
        end else if lRun=3 then
        begin
          if aRoute>=2 then lCTask := TTask.CurrentTask;
          lCStarted.SetEvent;
        end;
      end,ivFixedDelay);
    if aRoute=2 then lEvent.InvokeMode := imTTask
    else if aRoute=3 then lEvent.InvokeMode := imThread
    else lEvent.InvokeMode := imMainThread;
    lEvent.OverlapMode := aOverlap; lEvent.Run;
    TInterlocked.Add(lMono,lIntervalUs);
    if aRoute=1 then
    begin
      lThread := TThread.CreateAnonymousThread(procedure begin lCron.TickAtUs(cWall+TInterlocked.Read(lMono)-lOrigin); end);
      lThread.FreeOnTerminate := False;
      try lThread.Start; lThread.WaitFor; finally lThread.Free; end;
    end else lCron.TickAtUs(cWall+TInterlocked.Read(lMono)-lOrigin);
    if aRoute>=2 then
    begin
      Assert.IsTrue(lAStarted.WaitFor(5000)=wrSignaled,lContext+' A start');
      case aMutation of
        0: lEvent.Run;
        1: begin lEvent.EventPlan := '* * * * * * *'; lEvent.EventPlan := '@every '+IntToStr(aIntervalMs)+'ms fixed-delay'; end;
        2: begin lEvent.Enabled := False; lEvent.Enabled := True; end;
      end;
      TInterlocked.Add(lMono,lIntervalUs); lCron.TickAtUs(cWall+TInterlocked.Read(lMono)-lOrigin);
      if (aOverlap=omAllowOverlap) and (aOrder=1) then
      begin
        Assert.IsTrue(lBStarted.WaitFor(5000)=wrSignaled,lContext+' B start');
        lBRelease.SetEvent;
        Assert.IsTrue(lBExited.WaitFor(5000)=wrSignaled,lContext+' B end');
        Assert.IsTrue(lBTask<>nil,lContext+' B task');
        Assert.IsTrue(lBTask.Wait(5000),lContext+' B dispatch completion');
        lUntil := TestTickCount64+5000;
        while (lEvent.NextSchedule=0) and (TestTickCount64<lUntil) do TThread.Sleep(1);
        lExpectedNext := CronDateTimeToMs(lEvent.NextSchedule);
        Assert.IsTrue(lExpectedNext<>0,lContext+' B completion stalled');
        lARelease.SetEvent;
        Assert.IsTrue(lAExited.WaitFor(5000)=wrSignaled,lContext+' A end');
        Assert.IsTrue(lATask<>nil,lContext+' A task');
        Assert.IsTrue(lATask.Wait(5000),lContext+' A dispatch completion');
        Assert.AreEqual<Int64>(lExpectedNext,CronDateTimeToMs(lEvent.NextSchedule),lContext+' stale A changed B deadline');
      end else begin
        lARelease.SetEvent;
        Assert.IsTrue(lAExited.WaitFor(5000)=wrSignaled,lContext+' A end');
        // Callback-local signals precede FinalizeOverlap and CompleteIntervalRun.
        // Both asynchronous routes use TTask (route 3 explicitly enables the pool).
        // Join the dispatch before advancing the fake clock to its reset deadline.
        Assert.IsTrue(lATask<>nil,lContext+' A task');
        Assert.IsTrue(lATask.Wait(5000),lContext+' A dispatch completion');
        if aOverlap<>omSkipIfRunning then
        begin
          Assert.IsTrue(lBStarted.WaitFor(5000)=wrSignaled,lContext+' B start');
          Assert.AreEqual<TDateTime>(0,lEvent.NextSchedule,lContext+' stale A armed blocked B');
          lBRelease.SetEvent;
          Assert.IsTrue(lBExited.WaitFor(5000)=wrSignaled,lContext+' B end');
          Assert.IsTrue(lBTask<>nil,lContext+' B task');
          Assert.IsTrue(lBTask.Wait(5000),lContext+' B dispatch completion');
        end;
      end;
    end;
    lIndex := 2;
    if aOverlap=omSkipIfRunning then lIndex := 1;
    lUntil := TestTickCount64+5000;
    repeat
      CheckSynchronize(0);
      if (TInterlocked.CompareExchange(lCount,0,0)>=lIndex) and (lEvent.NextSchedule<>0) then Break;
      TThread.Sleep(1);
    until TestTickCount64>=lUntil;
    Assert.AreEqual(lIndex,TInterlocked.CompareExchange(lCount,0,0),lContext+' no stall or double-arm');
    Assert.AreEqual(0,lBadAwaiting,lContext+' B entered with deadline');
    lDeadlineUs := TInterlocked.Read(lOwningEndUs)+lIntervalUs;
    if aOverlap=omSkipIfRunning then lDeadlineUs := lOrigin+3*lIntervalUs;
    lExpectedNext := CronDateTimeToMs(lEvent.NextSchedule);
    Assert.IsTrue(lExpectedNext<>0,lContext+' missing rearm');
    Assert.AreEqual<Int64>((cWall+lDeadlineUs-lOrigin) div 1000,lExpectedNext,
      lContext+' owning completion deadline');
    // Advance to one microsecond before the owning deadline, then exactly to it.
    TInterlocked.Exchange(lMono,lDeadlineUs-1);
    lCron.TickAtUs(cWall+TInterlocked.Read(lMono)-lOrigin); CheckSynchronize(0);
    Assert.AreEqual(lIndex,TInterlocked.CompareExchange(lCount,0,0),lContext+' early start');
    lBRelease.SetEvent;
    TInterlocked.Increment(lMono); lCron.TickAtUs(cWall+TInterlocked.Read(lMono)-lOrigin);
    lUntil := TestTickCount64+5000;
    while (TInterlocked.CompareExchange(lCount,0,0)=lIndex) and (TestTickCount64<lUntil) do
    begin CheckSynchronize(0); TThread.Sleep(1); end;
    Assert.AreEqual(lIndex+1,TInterlocked.CompareExchange(lCount,0,0),lContext+' did not rearm exactly once');
    if aRoute>=2 then
      if lIndex=1 then
      begin
        Assert.IsTrue(lBStarted.WaitFor(5000)=wrSignaled,lContext+' rearm start');
        Assert.IsTrue(lBTask<>nil,lContext+' rearm task');
        Assert.IsTrue(lBTask.Wait(5000),lContext+' rearm dispatch completion');
      end else begin
        Assert.IsTrue(lCStarted.WaitFor(5000)=wrSignaled,lContext+' rearm start');
        Assert.IsTrue(lCTask<>nil,lContext+' rearm task');
        Assert.IsTrue(lCTask.Wait(5000),lContext+' rearm dispatch completion');
      end;
  finally
    lARelease.SetEvent; lBRelease.SetEvent;
    if lATask<>nil then lATask.Wait(5000);
    if lBTask<>nil then lBTask.Wait(5000);
    if lCTask<>nil then lCTask.Wait(5000);
    // Tasks retain the callback closure, which captures these task references.
    lATask := nil; lBTask := nil; lCTask := nil;
    lCron.Shutdown(5000,spWait); CheckSynchronize(0);
    lEvent := nil; lCron.Free;
    SetMaxCronMonotonicClockHook(nil); SetMaxCronWallClockHook(nil);
    lCStarted.Free;
    lBExited.Free; lBRelease.Free; lBStarted.Free; lAExited.Free; lARelease.Free; lAStarted.Free;
  end;
end;

procedure TTestIntervalEvents.CompletionOwnershipInvariant;
var
  lRoute, lMutation, lOrder, lInterval: Integer;
  lOverlap: TmaxCronOverlapMode;
  lSavedPool: TTestEnvSnapshot;
begin
  // Exhaustive bounded Cartesian generator. There is no random seed.
  lSavedPool := SaveTestEnvironmentVariable('MAXCRON_THREAD_DISPATCH_POOL');
  try
    SetTestEnvironmentVariable('MAXCRON_THREAD_DISPATCH_POOL', '1');
    for lRoute := 0 to 3 do
      for lOverlap := omAllowOverlap to omSerializeCoalesce do
        for lMutation := 0 to 2 do
          for lOrder := 0 to 1 do
            for lInterval in [10,100] do
              CheckCompletionOwnership(lRoute,lMutation,lOrder,lInterval,lOverlap);
  finally
    RestoreTestEnvironmentVariable(lSavedPool);
  end;
end;

end.

unit TestIntervalEvents;
interface
uses System.SysUtils, DUnitX.TestFramework, maxCron;
type
  [TestFixture]
  TTestIntervalEvents = class
  public
    [Test] procedure RestoreOriginShiftInvariant;
    [Test] procedure FixedRateIntegerModel;
    [Test] procedure ViewsLimitsAndPlanSwitch;
    [Test] procedure ValidityAndIgnoredCronProperties;
    [Test] procedure PersistenceProjection;
    [Test] procedure IntervalDialectAfterCron;
  end;
type
  TIntervalMemoryStore = class(TInterfacedObject, IMaxCronScheduleStore)
  public
    States: TArray<TMaxCronPersistedEvent>;
    procedure Save(const aEvents: TArray<TMaxCronPersistedEvent>);
    function TryLoad(out aEvents: TArray<TMaxCronPersistedEvent>): Boolean;
  end;
implementation
procedure TIntervalMemoryStore.Save(const aEvents: TArray<TMaxCronPersistedEvent>);
begin States := Copy(aEvents); end;
function TIntervalMemoryStore.TryLoad(out aEvents: TArray<TMaxCronPersistedEvent>): Boolean;
begin aEvents := Copy(States); Result := True; end;
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
    Assert.AreEqual(0,Length(lCron.Snapshot));
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
    lStoreObject.States[0].NumOfExecutionsPerformed := 2;
    for i := 0 to 3 do
    begin
      if cOffsets[i]=0 then lStoreObject.States[0].NextSchedule := 0
      else lStoreObject.States[0].NextSchedule := CronMsToDateTime(cWall div 1000+cOffsets[i]);
      Assert.AreEqual(1,lCron.RestoreScheduleState);
      lEvent := lCron.Snapshot[0];
      Assert.IsTrue(Supports(lEvent,IMaxCronIntervalEvent,lView));
      Assert.IsTrue(lView.IntervalMode=ivFixedDelay);
      Assert.AreEqual<Cardinal>(5000,lView.IntervalMs);
      Assert.AreEqual<UInt64>(2,lEvent.NumOfExecutionsPerformed);
      Assert.AreEqual<Int64>(cWall div 1000+cNext[i],CronDateTimeToMs(lEvent.NextSchedule));
    end;
    lStoreObject.States[0].Enabled := False; lCron.RestoreScheduleState;
    lEvent := lCron.Snapshot[0]; Assert.IsFalse(lEvent.Enabled);
    Assert.AreEqual<TDateTime>(0,lEvent.NextSchedule);
  finally
    lView := nil; lEvent := nil; lCron.Free; lStore := nil;
    SetMaxCronMonotonicClockHook(nil); SetMaxCronWallClockHook(nil);
  end;
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
        for i := 0 to 0 do
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
    for lMode := ivFixedRate to ivFixedRate do
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
              SetLength(lStoreObject.States,1);
              lStoreObject.States[0] := Default(TMaxCronPersistedEvent);
              lStoreObject.States[0].Name := 'origin invariant';
              if lMode=ivFixedDelay then
                lStoreObject.States[0].EventPlan := '@every 5s fixed-delay'
              else lStoreObject.States[0].EventPlan := '@every 5s';
              lStoreObject.States[0].Enabled := True;
              lStoreObject.States[0].InvokeMode := imMainThread;
              lStoreObject.States[0].Dialect := cdMaxCron;
              lStoreObject.States[0].TimeZoneId := 'LOCAL';
              lStoreObject.States[0].NextSchedule := CronMsToDateTime((cWall-12000000) div 1000);
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


end.

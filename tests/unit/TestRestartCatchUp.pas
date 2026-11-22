unit TestRestartCatchUp;
{$I maxCron.inc}

interface

uses
  {$IFDEF FPC}
  Classes, DateUtils, Generics.Collections, SyncObjs, SysUtils,
  Windows,
  {$ELSE}
  System.Classes, System.DateUtils, System.Generics.Collections, System.SyncObjs, System.SysUtils,
  Winapi.Windows,
  {$ENDIF}
  DUnitX.TestFramework,
  maxCron, maxCron.Internal.TimeZone, TestZoneFakes;

type
  TRestartStore = class(TInterfacedObject, IMaxCronScheduleStore)
  private
    fStates: TArray<TMaxCronPersistedEvent>;
    fAfterSave: TThreadProcedure;
  public
    property AfterSave: TThreadProcedure read fAfterSave write fAfterSave;
    procedure Save(const aEvents: TArray<TMaxCronPersistedEvent>);
    function TryLoad(out aEvents: TArray<TMaxCronPersistedEvent>): Boolean;
  end;

  [TestFixture]
  TTestRestartCatchUp = class
  private
    fNow, fMono, fBase: Int64;
    fCron: TmaxCron;
    fEvent: IMaxCronEvent;
    fStore: IMaxCronScheduleStore;
    procedure Start;
    procedure Finish;
    function Saved: TMaxCronPersistedEvent;
    procedure Advance(const aDelta: Int64);
    procedure PlainRestore(const aEngine: string);
    procedure CoherentSaveClockProperty(const aEngine: string);
    procedure SaveWideClockProperty(const aEngine: string);
    procedure SaveWideLegacyClockProperty(const aEngine: string);
  public
    [Test] procedure LedgerPrefixAndStaleTickets;
    [Test] procedure SavedDispatchWindow;
    [Test] procedure AutomaticDisableIntent;
    [Test] procedure RetryOutcomes;
    [Test] procedure IntervalCheckpoints;
    [Test] procedure RestoreAndBinder;
    [Test] procedure RestoreAutomaticReplay;
    [Test] procedure GeneratedPlainRestore;
    [Test] procedure IntervalRestoreMatrix;
    [Test] procedure LegacyAndDisabledRoundTrip;
    [Test] procedure PolicyLiveDifferential;
    [Test] procedure ConcurrentAndSerializedCrashWindows;
    [Test] procedure QueuedAndAbandonedWindows;
    [Test] procedure QuiescentEquivalence;
    [Test] procedure UtcOverlapCheckpoint;
    [Test] procedure IntervalBatchCrashWindow;
    [Test] procedure CheckpointBoundaryRepresentations;
    [Test] procedure IntervalBatchDispatchFailure;
    [Test] procedure RunCheckpointUsesSearchBase;
    [TestCase('scan', 'scan')]
    [TestCase('heap', 'heap')]
    [TestCase('shadow', 'shadow')]
    procedure IntervalProjectionPrefix(const aEngine: string);
    [TestCase('scan', 'scan')]
    [TestCase('heap', 'heap')]
    [TestCase('shadow', 'shadow')]
    procedure LegacyTwoRestarts(const aEngine: string);
    [TestCase('scan', 'scan')]
    [TestCase('heap', 'heap')]
    [TestCase('shadow', 'shadow')]
    procedure PositiveFiniteFold(const aEngine: string);
    [TestCase('scan', 'scan')]
    [TestCase('heap', 'heap')]
    [TestCase('shadow', 'shadow')]
    procedure PositiveIntervalOutcomes(const aEngine: string);
    [TestCase('scan', 'scan')]
    [TestCase('heap', 'heap')]
    [TestCase('shadow', 'shadow')]
    procedure ClockJumpRestartProperty(const aEngine: string);
  end;

implementation

procedure RecordOccurrence(const aList: TList<Int64>; const aCron: Boolean);
var
  lUtcUs, lMonoUs: Int64;
begin
  Assert.IsTrue(CurrentMaxCronOccurrenceForTests(lUtcUs, lMonoUs), 'real callback ticket identity');
  if aCron then aList.Add(lUtcUs) else aList.Add(lMonoUs);
end;

procedure AssertRecordedDelivery(const aLive, aReplay: TList<Int64>;
  const aIntervalUs: Int64; const aCron, aFixedDelay: Boolean; const aContext: string);
var
  lLiveId, lReplayId: Int64;
  lMatch: Integer;
  lFound: Boolean;
begin
  lMatch := 0;
  for lLiveId in aLive do
  begin
    lFound := False;
    while lMatch < aReplay.Count do
    begin
      lReplayId := aReplay[lMatch]; Inc(lMatch);
      // Match recorded dispatch tickets, never an inferred replay grid.
      // A restored interval can be conservatively rephased by flooring or
      // sampling latency; match each rate instance to a distinct callback
      // within its preceding interval. Fixed-delay has one outstanding run.
      if aCron then lFound := lReplayId = lLiveId
      else lFound := (lReplayId <= lLiveId) and
        (aFixedDelay or (lReplayId > lLiveId - aIntervalUs));
      if lFound then Break;
    end;
    Assert.IsTrue(lFound, aContext + ' missing callback identity ' + IntToStr(lLiveId));
  end;
  Assert.IsTrue(aReplay.Count >= aLive.Count, aContext + ' at least once');
end;

procedure TRestartStore.Save(const aEvents: TArray<TMaxCronPersistedEvent>);
begin
  fStates := Copy(aEvents);
  if Assigned(fAfterSave) then fAfterSave();
end;

function TRestartStore.TryLoad(out aEvents: TArray<TMaxCronPersistedEvent>): Boolean;
begin
  aEvents := Copy(fStates);
  Result := True;
end;

procedure TTestRestartCatchUp.Start;
begin
  fBase := CronDateTimeToInstantUs(EncodeDateTime(2026, 11, 21, 10, 0, 0, 0));
  fNow := fBase;
  fMono := 100000000;
  SetCronSystemTimeZoneForTests(TZoneAsSystemZone.Create(
    CreateCronZone('restart UTC host', TCronFixedZoneSource.Create(0))));
  SetMaxCronUtcClockHook(function: Int64 begin Result := fNow; end);
  SetMaxCronWallClockHook(function: Int64 begin Result := fNow; end);
  SetMaxCronMonotonicClockHook(function: Int64 begin Result := fMono; end);
  fStore := TRestartStore.Create;
  fCron := TmaxCron.Create(ctPortable);
  fCron.ScheduleStore := fStore;
  fEvent := fCron.Add('restart');
  fEvent.TimeZoneId := 'UTC';
  fEvent.EventPlan := '* * * * * * * 0';
  fEvent.InvokeMode := imMainThread;
end;

procedure TTestRestartCatchUp.Finish;
begin
  SetMaxCronBeforeDispatchHook(nil);
  SetMaxCronBeforeSaveEventHook(nil);
  fEvent := nil;
  FreeAndNil(fCron);
  fStore := nil;
  SetMaxCronUtcClockHook(nil);
  SetMaxCronWallClockHook(nil);
  SetMaxCronMonotonicClockHook(nil);
  SetCronSystemTimeZoneForTests(nil);
end;

function TTestRestartCatchUp.Saved: TMaxCronPersistedEvent;
var
  lStates: TArray<TMaxCronPersistedEvent>;
begin
  Assert.AreEqual(1, fCron.SaveScheduleState);
  Assert.IsTrue(fStore.TryLoad(lStates));
  Result := lStates[0];
end;

procedure TTestRestartCatchUp.Advance(const aDelta: Int64);
begin
  Inc(fNow, aDelta);
  Inc(fMono, aDelta);
  fCron.TickAtUtcUs(fNow);
end;

procedure TTestRestartCatchUp.LedgerPrefixAndStaleTickets;
var
  lA, lB, lOld: UInt64;
begin
  Start;
  try
    // Synthetic ledger instants precede the live unfinished occurrence.
    // R2 save bounds must not certify the fixture's unprocessed one-second due.
    fEvent.EventPlan := '0 0 1 1 * 2027 0 0';
    fEvent.Run;
    ResetMaxCronLedgerForTests(fEvent, fBase);
    lA := OpenMaxCronSettleTicketForTests(fEvent, fBase + 1000000);
    lB := OpenMaxCronSettleTicketForTests(fEvent, fBase + 2000000);
    SettleMaxCronTicketForTests(fEvent, lB);
    Assert.AreEqual<Int64>(fBase, CronDateTimeToInstantUs(Saved.CompletedThrough), 'B cannot cover A');
    MarkMaxCronSettledForTests(fEvent, fBase + 3000000);
    SettleMaxCronTicketForTests(fEvent, lA);
    Assert.AreEqual<Int64>(fBase + 3000000, CronDateTimeToInstantUs(Saved.CompletedThrough), 'drain prefix and mark');
    SettleMaxCronTicketForTests(fEvent, lA);
    SettleMaxCronTicketForTests(fEvent, 0);
    lOld := OpenMaxCronSettleTicketForTests(fEvent, fBase + 9000000);
    ResetMaxCronLedgerForTests(fEvent, fBase);
    SettleMaxCronTicketForTests(fEvent, lOld);
    Assert.AreEqual<Int64>(fBase, CronDateTimeToInstantUs(Saved.CompletedThrough), 'stale after reset');
    lA := OpenMaxCronSettleTicketForTests(fEvent, fBase + 2000000);
    lB := OpenMaxCronSettleTicketForTests(fEvent, fBase + 1000000);
    SettleMaxCronTicketForTests(fEvent, lA);
    SettleMaxCronTicketForTests(fEvent, lB);
    Assert.AreEqual<Int64>(fBase + 2000000, CronDateTimeToInstantUs(Saved.CompletedThrough), 'monotone through decrease');
    lA := OpenMaxCronSettleTicketForTests(fEvent, fBase + 3000000);
    lB := OpenMaxCronSettleTicketForTests(fEvent, fBase + 3000000);
    SettleMaxCronTicketForTests(fEvent, lB);
    Assert.AreEqual<Int64>(fBase + 2000000, CronDateTimeToInstantUs(Saved.CompletedThrough), 'equal-through open prefix');
    SettleMaxCronTicketForTests(fEvent, lA);
    Assert.AreEqual<Int64>(fBase + 3000000, CronDateTimeToInstantUs(Saved.CompletedThrough));
    lA := OpenMaxCronSettleTicketForTests(fEvent, 0, True);
    Inc(fNow, 4000123);
    SettleMaxCronTicketForTests(fEvent, lA);
    Assert.AreEqual<Int64>(fBase + 4000000, CronDateTimeToInstantUs(Saved.CompletedThrough), 'fixed-delay UTC floor ms');
  finally
    Finish;
  end;
end;

procedure TTestRestartCatchUp.SavedDispatchWindow;
var
  lBefore, lInside: TMaxCronPersistedEvent;
  lCalls: Integer;
begin
  Start;
  try
    lCalls := 0;
    fEvent.OnScheduleProc :=
      procedure(aSender: IMaxCronEvent)
      begin
        Inc(lCalls);
        lInside := Saved;
      end;
    fEvent.Run;
    SetMaxCronBeforeDispatchHook(
      procedure(const aMode: TmaxCronInvokeMode) begin lBefore := Saved; end);
    Advance(1000000);
    Assert.AreEqual(1, lCalls);
    Assert.AreEqual<Int64>(fBase, CronDateTimeToInstantUs(lBefore.CompletedThrough), 'W1 open');
    Assert.AreEqual<Int64>(fBase, CronDateTimeToInstantUs(lInside.CompletedThrough), 'W3 running');
    Assert.AreEqual<UInt64>(0, lInside.NumOfExecutionsPerformed, 'checkpoint execution count excludes running callback');
    Assert.AreEqual<Int64>(fNow, CronDateTimeToInstantUs(Saved.CompletedThrough), 'W4 settled');
    Assert.AreEqual<UInt64>(1, Saved.NumOfExecutionsPerformed);
  finally
    Finish;
  end;
end;

procedure TTestRestartCatchUp.AutomaticDisableIntent;
const
  cEngines: array[0..2] of string = ('scan', 'heap', 'shadow');
var
  lEngine, lOldEngine: string;
  lKind, lStop: Integer;
  lState: TMaxCronPersistedEvent;
begin
  lOldEngine := {$IFDEF FPC}SysUtils.{$ENDIF}GetEnvironmentVariable('MAXCRON_ENGINE');
  try
    for lEngine in cEngines do for lKind := 0 to 2 do for lStop := 0 to 1 do
    begin
      SetEnvironmentVariableW('MAXCRON_ENGINE', PChar(lEngine));
      Start;
      try
        case lKind of
          0: fEvent.EventPlan := '0 10 21 11 * 2026 1 0';
          1: fEvent.ValidTo := CronInstantUsToDateTime(fBase + 1000000);
          2: fEvent.EventPlan := '* * * * * * * 1';
        end;
        fEvent.OnScheduleProc := procedure(aSender: IMaxCronEvent) begin end;
        fEvent.Run;
        SetMaxCronBeforeDispatchHook(
          procedure(const aMode: TmaxCronInvokeMode)
          begin
            if lStop = 1 then fEvent.Stop;
            lState := Saved;
          end);
        Advance(1000000);
        Assert.AreEqual(lStop = 0, lState.Enabled, lEngine + ' save intent kind=' + IntToStr(lKind));
        Assert.AreEqual<UInt64>(0, lState.NumOfExecutionsPerformed, 'W1 count');
        if lKind = 2 then Advance(1000000);
        Assert.IsFalse(Saved.Enabled, 'settled exhausted or explicit stop');
      finally
        Finish;
      end;
    end;
  finally
    SetEnvironmentVariableW('MAXCRON_ENGINE', PChar(lOldEngine));
  end;
end;

procedure TTestRestartCatchUp.RetryOutcomes;
var
  lCalls, lDead: Integer;
begin
  Start;
  try
    lCalls := 0;
    lDead := 0;
    fEvent.RetryMaxAttempts := 2;
    fEvent.RetryInitialDelayMs := 0;
    fEvent.OnScheduleProc := procedure(aSender: IMaxCronEvent)
      begin Inc(lCalls); raise Exception.Create('expected retry'); end;
    fEvent.OnDeadLetterProc := procedure(aSender: IMaxCronEvent;
      const aError: string; const aAttempts: Integer) begin Inc(lDead); end;
    fEvent.Run;
    Advance(1000000);
    Assert.AreEqual(3, lCalls);
    Assert.AreEqual(1, lDead);
    Assert.AreEqual<Int64>(fNow, CronDateTimeToInstantUs(Saved.CompletedThrough), 'dead letter settles');
    fEvent.OnScheduleProc := nil;
    Advance(1000000);
    Assert.AreEqual<Int64>(fNow, CronDateTimeToInstantUs(Saved.CompletedThrough), 'no callbacks settles');
    fEvent.MisfirePolicy := mpSkip;
    Advance(10000000);
    Assert.AreEqual<Int64>(fNow, CronDateTimeToInstantUs(Saved.CompletedThrough), 'late skip marks pass');
  finally
    Finish;
  end;
end;

procedure TTestRestartCatchUp.IntervalCheckpoints;
var
  lInside: TMaxCronPersistedEvent;
  lDelay: Integer;
begin
  for lDelay := 0 to 1 do
  begin
    Start;
    try
      if lDelay = 0 then fEvent.EventPlan := '@every 100ms'
      else fEvent.EventPlan := '@every 100ms fixed-delay';
      fEvent.OnScheduleProc := procedure(aSender: IMaxCronEvent)
        begin lInside := Saved; Inc(fNow, 200123); Inc(fMono, 200123); end;
      fEvent.Run;
      Advance(100000);
      Assert.AreEqual<Int64>(fBase, CronDateTimeToInstantUs(lInside.CompletedThrough), 'interval in flight');
      if lDelay = 0 then
        Assert.AreEqual<Int64>(fBase + 100000, CronDateTimeToInstantUs(Saved.CompletedThrough), 'rate due')
      else
        Assert.AreEqual<Int64>(fBase + 300000, CronDateTimeToInstantUs(Saved.CompletedThrough), 'delay completion');
    finally
      Finish;
    end;
  end;
end;

procedure TTestRestartCatchUp.RestoreAndBinder;
var
  lRestored: TmaxCron;
  lCalls, lBound: Integer;
  lStates: TArray<TMaxCronPersistedEvent>;
  lRaised: Boolean;
begin
  Start;
  lRestored := nil;
  try
    fEvent.EventPlan := '*/15 * * * *';
    fEvent.Run;
    Saved;
    fStore.TryLoad(lStates);
    lStates[0].NextSchedule := CronInstantUsToDateTime(fBase + 3600000000);
    fStore.Save(lStates);
    Inc(fNow, 2850000000);
    lCalls := 0;
    lBound := 0;
    lRestored := TmaxCron.Create(ctPortable);
    lRestored.ScheduleStore := fStore;
    lRestored.DefaultMisfireCatchUpLimit := 3;
    lRestored.RestoreScheduleState(True,
      procedure(const aEvent: IMaxCronEvent; const aState: TMaxCronPersistedEvent)
      begin
        Assert.IsFalse(aEvent.Enabled, 'binder precedes enabling');
        Inc(lBound);
        aEvent.OnScheduleProc := procedure(aSender: IMaxCronEvent) begin Inc(lCalls); end;
      end);
    Assert.AreEqual(1, lBound, 'binder invoked');
    lRestored.TickAtUtcUs(fNow);
    Assert.AreEqual(3, lCalls, 'E3 ignores a later saved NextSchedule');
    Assert.AreEqual<Int64>(fBase + 3600000000,
      CronDateTimeToInstantUs(lRestored.Snapshot[0].NextSchedule));
    lRestored.Clear;
    lRaised := False;
    try
      lRestored.RestoreScheduleState(True,
        procedure(const aEvent: IMaxCronEvent; const aState: TMaxCronPersistedEvent)
        begin raise Exception.Create('binder failure'); end);
    except
      on E: Exception do lRaised := E.Message = 'binder failure';
    end;
    Assert.IsTrue(lRaised, 'binder exception propagates');
    Assert.IsFalse(lRestored.Snapshot[0].Enabled, 'throwing binder leaves event disabled');
    lRestored.RestoreScheduleState(True,
      procedure(const aEvent: IMaxCronEvent; const aState: TMaxCronPersistedEvent)
      begin aEvent.EventPlan := '0 * * * *'; end);
    Assert.AreEqual<Int64>(fBase + 3600000000,
      CronDateTimeToInstantUs(lRestored.Snapshot[0].NextSchedule), 'binder plan applies before search');
  finally
    lRestored.Free;
    Finish;
  end;
end;

procedure TTestRestartCatchUp.RestoreAutomaticReplay;
const
  cEngines: array[0..2] of string = ('scan', 'heap', 'shadow');
var
  lEngine, lOldEngine: string;
  lKind, lStop, lWindow, lCalls: Integer;
  lCapture: IMaxCronScheduleStore;
  lRestored: TmaxCron;
  lState: TMaxCronPersistedEvent;
begin
  lOldEngine := {$IFDEF FPC}SysUtils.{$ENDIF}GetEnvironmentVariable('MAXCRON_ENGINE');
  try
    for lEngine in cEngines do for lKind := 0 to 2 do
      for lStop := 0 to 1 do for lWindow := 0 to 1 do
    begin
      SetEnvironmentVariableW('MAXCRON_ENGINE', PChar(lEngine));
      Start;
      lRestored := nil;
      try
        lCapture := TRestartStore.Create;
        case lKind of
          0: fEvent.EventPlan := '0 10 21 11 * 2026 1 0';
          1: fEvent.ValidTo := CronInstantUsToDateTime(fBase + 1000000);
          2: fEvent.EventPlan := '* * * * * * * 1';
        end;
        fEvent.OnScheduleProc := procedure(aSender: IMaxCronEvent)
          begin
            if lWindow = 1 then
            begin
              if lStop = 1 then fEvent.Enabled := False;
              lState := Saved;
            end;
          end;
        fEvent.Run;
        SetMaxCronBeforeDispatchHook(procedure(const aMode: TmaxCronInvokeMode)
          begin
            if lWindow = 0 then
            begin
              if lStop = 1 then fEvent.Stop;
              lState := Saved;
            end;
          end);
        Advance(1000000);
        SetMaxCronBeforeDispatchHook(nil);
        lCapture.Save([lState]);
        Assert.AreEqual<UInt64>(0, lState.NumOfExecutionsPerformed, 'P6-01 count at both windows');
        lCalls := 0;
        lRestored := TmaxCron.Create(ctPortable);
        lRestored.ScheduleStore := lCapture;
        lRestored.RestoreScheduleState(True,
          procedure(const aEvent: IMaxCronEvent; const aState: TMaxCronPersistedEvent)
          begin aEvent.OnScheduleProc := procedure(aSender: IMaxCronEvent) begin Inc(lCalls); end; end);
        lRestored.TickAtUtcUs(fNow);
        Assert.AreEqual(1 - lStop, lCalls, lEngine + ' automatic replay kind=' + IntToStr(lKind));
        Inc(fNow, 1000000);
        lRestored.TickAtUtcUs(fNow);
        Assert.IsFalse(lRestored.Snapshot[0].Enabled, 'normal exhaustion after replay');
      finally
        lRestored.Free;
        lCapture := nil;
        Finish;
      end;
    end;
  finally
    SetEnvironmentVariableW('MAXCRON_ENGINE', PChar(lOldEngine));
  end;
end;

procedure TTestRestartCatchUp.GeneratedPlainRestore;
const
  cEngines: array[0..2] of string = ('scan', 'heap', 'shadow');
var
  lEngine, lOldEngine: string;
begin
  lOldEngine := {$IFDEF FPC}SysUtils.{$ENDIF}GetEnvironmentVariable('MAXCRON_ENGINE');
  try
    for lEngine in cEngines do
    begin
      SetEnvironmentVariableW('MAXCRON_ENGINE', PChar(lEngine));
      PlainRestore(lEngine);
    end;
  finally
    SetEnvironmentVariableW('MAXCRON_ENGINE', PChar(lOldEngine));
  end;
end;

procedure TTestRestartCatchUp.PlainRestore(const aEngine: string);
const
  cPlans: array[0..7] of string = ('* * * * * * * 0', '* * * * *', '0 * * * *',
    '0 0 * * *', '*/15 * * * *', '0 9 * * 1-5', '0 0 L * *', '0 9 15W * *');
  cOffsets: array[0..6] of Int64 = (-1000, -1, 0, 1, 999, 1000, 1001);
var
  lPlan: TCronSchedulePlan;
  lState: TMaxCronPersistedEvent;
  lDates: TDates;
  lRestored: TmaxCron;
  lPolicy: TmaxCronMisfirePolicy;
  lExpected: TArray<Int64>;
  lActual: TList<Int64>;
  lStart, lEnd, lCheckMs, lNowMs, lNextMs, lDueMs: Int64;
  lSeed: UInt64;
  lP, lN, lLimit, lExpectedCount, lPass, i, lRows: Integer;
begin
  Start;
  lPlan := TCronSchedulePlan.Create;
  lActual := TList<Int64>.Create;
  lRows := 0;
  lSeed := 20261117;
  try
    for lP := 0 to High(cPlans) do for lPolicy := mpSkip to mpCatchUpAll do
      for lLimit := 1 to 3 do for lN := 0 to High(cOffsets) do
    begin
      if lLimit = 2 then Continue;
      lSeed := (lSeed * 1664525 + 1013904223) and $FFFFFFFF;
      lCheckMs := fBase div 1000 + Int64(lSeed mod 86400) * 1000 + cOffsets[lN];
      {$IFDEF MAXCRON_LONG_TESTS}
      lNowMs := lCheckMs + Int64(lSeed mod 259201) * 1000;
      {$ELSE}
      lNowMs := lCheckMs + Int64(lSeed mod 121) * 1000;
      {$ENDIF}
      lPlan.Parse(cPlans[lP]);
      lStart := (CronFloorDiv(lCheckMs, 1000) + 1) * 1000;
      lEnd := lNowMs + 1;
      lPlan.GetOccurrencesBetween(CronMsToDateTime(lStart),
        CronMsToDateTime(lEnd), lDates, 300000);
      lExpected := nil;
      if lPolicy = mpCatchUpAll then
      begin
        SetLength(lExpected, Length(lDates));
        for i := 0 to High(lDates) do lExpected[i] := CronDateTimeToMs(lDates[i]);
      end else if Length(lDates) > 0 then
        if (lPolicy = mpFireOnceNow) or (lNowMs - CronDateTimeToMs(lDates[0]) < 1000) then
          lExpected := [CronDateTimeToMs(lDates[0])];
      lState := Default(TMaxCronPersistedEvent);
      lState.Dialect := cdMaxCron;
      lState.Name := 'generated'; lState.EventPlan := cPlans[lP]; lState.Enabled := True;
      lState.TimeZoneId := 'UTC'; lState.InvokeMode := imMainThread; lState.MisfirePolicy := mpDefault;
      lState.CompletedThrough := CronMsToDateTime(lCheckMs);
      // An intentionally wrong future saved due makes the checkpoint path observable.
      lState.NextSchedule := CronMsToDateTime(lNowMs + 86400000);
      fStore.Save([lState]);
      fNow := lNowMs * 1000;
      lActual.Clear;
      lRestored := TmaxCron.Create(ctPortable);
      try
        lRestored.ScheduleStore := fStore;
        lRestored.DefaultMisfirePolicy := lPolicy;
        lRestored.DefaultMisfireCatchUpLimit := lLimit;
        lRestored.RestoreScheduleState;
        lRestored.Snapshot[0].OnScheduleProc := procedure(aSender: IMaxCronEvent)
          begin lActual.Add(CronDateTimeToMs(aSender.LastExecution)); end;
        // Distinct pass keys with a fixed due window; catch-up drains bounded work.
        lPass := 0;
        repeat
          lExpectedCount := lActual.Count;
          lRestored.TickAtUtcUs(fNow);
          Assert.IsTrue(lActual.Count - lExpectedCount <= lLimit, 'per-pass limit');
          Inc(lPass);
          lDueMs := CronDateTimeToMs(lRestored.Snapshot[0].NextSchedule);
          if (lDueMs > lNowMs) or (lPolicy <> mpCatchUpAll) then Break;
          // TickAtUtcUs is one explicit pass; production clock pacing is separate.
          Assert.IsTrue(lPass < 300001, 'catch-up terminates');
        until False;
        Assert.AreEqual(Length(lExpected), lActual.Count,
          Format('seed=20261117 plan=%s policy=%d L=%d C=%d now=%d',
          [cPlans[lP], Ord(lPolicy), lLimit, lCheckMs, lNowMs]));
        for i := 0 to High(lExpected) do Assert.AreEqual<Int64>(lExpected[i], lActual[i], 'fire identity');
        lNextMs := lNowMs;
        if lPolicy = mpCatchUpAll then
        begin
          lNextMs := lCheckMs;
          if Length(lExpected) > 0 then lNextMs := lExpected[High(lExpected)];
        end;
        Assert.IsTrue(lPlan.FindNextScheduleDate(CronMsToDateTime(lNextMs), lState.NextSchedule));
        Assert.AreEqual<Int64>(CronDateTimeToMs(lState.NextSchedule), lDueMs, 'next independent query');
        Inc(lRows);
      finally
        lRestored.Free;
      end;
    end;
    System.WriteLn('RESTART_REFERENCE engine=', aEngine, ' rows=', lRows, ' seed=20261117');
  finally
    lActual.Free;
    lPlan.Free;
    Finish;
  end;
end;

procedure TTestRestartCatchUp.IntervalRestoreMatrix;
const
  cIntervals: array[0..2] of Integer = (1, 100, 5000);
  cDeltas: array[0..5] of Int64 = (-12300000, -5000000, -1, 0, 2000000, 60000000);
var
  lState: TMaxCronPersistedEvent;
  lRestored: TmaxCron;
  lInterval, lDelta, lDelay: Integer;
  lDue, lIntervalUs: Int64;
begin
  Start;
  try
    for lInterval := 0 to High(cIntervals) do for lDelta := 0 to High(cDeltas) do
      for lDelay := 0 to 1 do
    begin
      lState := Default(TMaxCronPersistedEvent);
      lState.Name := 'interval';
      lState.Enabled := True;
      lState.TimeZoneId := 'UTC';
      lState.EventPlan := '@every ' + IntToStr(cIntervals[lInterval]) + 'ms';
      if lDelay = 1 then lState.EventPlan := lState.EventPlan + ' fixed-delay';
      lState.CompletedThrough := CronInstantUsToDateTime(fNow + cDeltas[lDelta]);
      lState.NextSchedule := CronInstantUsToDateTime(fNow + 900000000);
      fStore.Save([lState]);
      lIntervalUs := Int64(cIntervals[lInterval]) * 1000;
      lDue := CronDateTimeToInstantUs(lState.CompletedThrough) + lIntervalUs;
      if lDue > fNow + lIntervalUs then lDue := fNow + lIntervalUs;
      lRestored := TmaxCron.Create(ctPortable);
      try
        lRestored.ScheduleStore := fStore;
        lRestored.RestoreScheduleState;
        Assert.AreEqual<Int64>(lDue div 1000, CronDateTimeToMs(lRestored.Snapshot[0].NextSchedule), 'R4 projection');
      finally
        lRestored.Free;
      end;
    end;
  finally
    Finish;
  end;
end;

procedure TTestRestartCatchUp.LegacyAndDisabledRoundTrip;
var
  lState, lSaved: TMaxCronPersistedEvent;
  lStates: TArray<TMaxCronPersistedEvent>;
  lRestored: TmaxCron;
  lVariant: Integer;
  lBits: UInt64;
begin
  Start;
  try
    for lVariant := 0 to 3 do
    begin
      lState := Default(TMaxCronPersistedEvent);
      lState.Dialect := cdMaxCron;
      lState.Name := 'legacy'; lState.TimeZoneId := 'UTC'; lState.Enabled := lVariant <> 2;
      lState.EventPlan := '* * * * * * * 0';
      lState.NextSchedule := CronInstantUsToDateTime(fBase + 1000000);
      if lVariant = 1 then lState.CompletedThrough := -1;
      if lVariant = 2 then lState.CompletedThrough := CronInstantUsToDateTime(fBase - 999000);
      if lVariant = 3 then
      begin
        lBits := $7FF8000000000000;
        Move(lBits, lState.CompletedThrough, SizeOf(lBits));
      end;
      lState.NextScheduleNeedsResolve := lVariant = 1;
      fStore.Save([lState]);
      lRestored := TmaxCron.Create(ctPortable);
      try
        lRestored.ScheduleStore := fStore;
        lRestored.RestoreScheduleState;
        if lVariant <> 2 then
          Assert.AreEqual<TDateTime>(lState.NextSchedule, lRestored.Snapshot[0].NextSchedule);
        lRestored.SaveScheduleState;
        fStore.TryLoad(lStates);
        lSaved := lStates[0];
        Assert.AreEqual(lState.NextScheduleNeedsResolve, lSaved.NextScheduleNeedsResolve, 'legacy needs-resolve state');
        if lVariant = 2 then
          Assert.AreEqual<TDateTime>(lState.CompletedThrough, lSaved.CompletedThrough, 'P3 disabled checkpoint');
      finally
        lRestored.Free;
      end;
    end;
  finally
    Finish;
  end;
end;

procedure TTestRestartCatchUp.PolicyLiveDifferential;
const
  cEngines: array[0..2] of string = ('scan', 'heap', 'shadow');
var
  lState: TMaxCronPersistedEvent;
  lRestored: TmaxCron;
  lPolicy: TmaxCronMisfirePolicy;
  lA, lB: TList<Int64>;
  lCallback: TmaxCronNotifyProc;
  lVariant, i: Integer;
  lEngine, lOldEngine: string;
  lGap: Int64;
begin
  lA := TList<Int64>.Create;
  lB := TList<Int64>.Create;
  lOldEngine := {$IFDEF FPC}SysUtils.{$ENDIF}GetEnvironmentVariable('MAXCRON_ENGINE');
  try
    for lEngine in cEngines do for lVariant := 0 to 10 do for lPolicy := mpSkip to mpCatchUpAll do
    begin
      SetEnvironmentVariableW('MAXCRON_ENGINE', PChar(lEngine));
      Start;
      lRestored := nil;
      try
        lA.Clear; lB.Clear;
        fEvent.EventPlan := '* * * * *';
        fEvent.MisfirePolicy := lPolicy;
        lGap := 120000000;
        case lVariant of
          0: fEvent.TimeZoneId := 'UTC+05:30';
          1: fEvent.WeekdaysOnly := True;
          2: fEvent.ExcludedDatesCsv := '2026-11-21';
          3: begin fEvent.BlackoutStartTime := EncodeTime(22,0,0,0);
               fEvent.BlackoutEndTime := EncodeTime(10,2,0,0); end;
          4: begin fEvent.ValidFrom := CronInstantUsToDateTime(fBase + 60000000);
               fEvent.ValidTo := CronInstantUsToDateTime(fBase + 180000000); end;
          5: fEvent.TimeZoneId := 'UTC-08:00';
          6..9:
            begin
              SetCronSystemTimeZoneForTests(TZoneAsSystemZone.Create(CreateCronZone('restart fall', FakeZoneSource(0))));
              fNow := ZoneMs(2026, 10, 25, 0, 29) * 1000;
              fEvent.TimeZoneId := 'LOCAL';
              fEvent.DstFallPolicy := TmaxCronDstFallPolicy(lVariant - 6);
              fEvent.EventPlan := '30 2 * * *';
              lGap := 7200000000;
            end;
          10:
            begin
              SetCronSystemTimeZoneForTests(TZoneAsSystemZone.Create(CreateCronZone('restart spring', FakeZoneSource(0))));
              fNow := ZoneMs(2026, 3, 29, 0, 59) * 1000;
              fEvent.TimeZoneId := 'LOCAL';
              fEvent.DstSpringPolicy := dspRunAtNextValidTime;
              fEvent.EventPlan := '30 2 * * *';
              lGap := 120000000;
            end;
        end;
        fEvent.OnScheduleProc := procedure(aSender: IMaxCronEvent)
          begin lA.Add(CronDateTimeToMs(aSender.LastExecution)); end;
        fEvent.Run;
        lState := Saved;
        Inc(fNow, lGap);
        lRestored := TmaxCron.Create(ctPortable);
        lRestored.ScheduleStore := fStore;
        lCallback := procedure(aSender: IMaxCronEvent)
          begin lB.Add(CronDateTimeToMs(aSender.LastExecution)); end;
        lRestored.RestoreScheduleState(True,
          procedure(const aEvent: IMaxCronEvent; const aSaved: TMaxCronPersistedEvent)
          begin aEvent.OnScheduleProc := lCallback; end);
        for i := 0 to 9 do
        begin
          fCron.TickAtUtcUs(fNow);
          lRestored.TickAtUtcUs(fNow);
          Assert.AreEqual<TDateTime>(fEvent.NextSchedule, lRestored.Snapshot[0].NextSchedule, 'R2 next');
          Inc(fNow, 1000000);
        end;
        Assert.AreEqual(lA.Count, lB.Count, 'R2 counts');
        for i := 0 to lA.Count - 1 do Assert.AreEqual<Int64>(lA[i], lB[i], 'R2 identities');
      finally
        lRestored.Free;
        Finish;
      end;
    end;
  finally
    // The binder captures lCallback in the callback's shared capture frame.
    // Break that reference cycle before releasing the captured lists.
    lCallback := nil;
    SetEnvironmentVariableW('MAXCRON_ENGINE', PChar(lOldEngine));
    lA.Free; lB.Free;
  end;
end;

procedure TTestRestartCatchUp.ConcurrentAndSerializedCrashWindows;
var
  lStarted, lRelease, lSecond: TEvent;
  lMode: TmaxCronOverlapMode;
  lCalls: Integer;
  lState: TMaxCronPersistedEvent;
  lDeadline: UInt64;
begin
  lStarted := TEvent.Create(nil, True, False, '');
  lRelease := TEvent.Create(nil, True, False, '');
  lSecond := TEvent.Create(nil, True, False, '');
  try
    for lMode := omAllowOverlap to omSerializeCoalesce do
    begin
      Start;
      try
        lCalls := 0;
        lStarted.ResetEvent; lRelease.ResetEvent; lSecond.ResetEvent;
        fEvent.OverlapMode := lMode;
        fEvent.InvokeMode := imThread;
        fEvent.OnScheduleProc := procedure(aSender: IMaxCronEvent)
          begin
            if TInterlocked.Increment(lCalls) = 1 then
            begin
              lStarted.SetEvent;
              if lRelease.WaitFor(5000) <> wrSignaled then raise Exception.Create('release timeout');
            end else lSecond.SetEvent;
          end;
        fEvent.Run;
        Advance(1000000);
        Assert.IsTrue(lStarted.WaitFor(2000) = wrSignaled, 'first callback entered');
        Advance(1000000);
        Advance(1000000);
        if lMode = omAllowOverlap then
          Assert.IsTrue(lSecond.WaitFor(2000) = wrSignaled, 'later callback finished before A');
        lState := Saved;
        Assert.AreEqual<Int64>(fBase, CronDateTimeToInstantUs(lState.CompletedThrough), 'W6-W8 prefix holds');
        Assert.AreEqual<UInt64>(0, lState.NumOfExecutionsPerformed, 'replay capacity covers unsettled suffix');
        lRelease.SetEvent;
        Assert.IsTrue(fCron.Shutdown(5000, spWait), 'callbacks drained');
        lDeadline := TThread.GetTickCount64 + 2000;
        while (CronDateTimeToInstantUs(Saved.CompletedThrough) < fBase + 3000000) and
          (TThread.GetTickCount64 < lDeadline) do TThread.Sleep(1);
        Assert.AreEqual<Int64>(fBase + 3000000, CronDateTimeToInstantUs(Saved.CompletedThrough), 'settled suffix drains');
        if lMode = omSkipIfRunning then Assert.AreEqual(1, lCalls)
        else if lMode = omSerializeCoalesce then Assert.AreEqual(2, lCalls)
        else Assert.AreEqual(3, lCalls);
      finally
        lRelease.SetEvent;
        Finish;
      end;
    end;
  finally
    lStarted.Free; lRelease.Free; lSecond.Free;
  end;
end;

procedure TTestRestartCatchUp.QueuedAndAbandonedWindows;
var
  lWorker: TThread;
  lTickDone: TEvent;
  lRaised: Boolean;
  lCalls, lVariant: Integer;
  lState: TMaxCronPersistedEvent;
  lRestored: TmaxCron;
  lCapture: IMaxCronScheduleStore;
begin
  for lVariant := 0 to 2 do
  begin
    Start;
    lRestored := nil;
    try
      lCalls := 0;
      fEvent.OnScheduleProc := procedure(aSender: IMaxCronEvent) begin Inc(lCalls); end;
      fEvent.Run;
      Inc(fNow, 1000000); Inc(fMono, 1000000);
      lTickDone := TEvent.Create(nil, True, False, '');
      lWorker := TThread.CreateAnonymousThread(procedure
        begin
          try fCron.TickAtUtcUs(fNow); finally lTickDone.SetEvent; end;
        end);
      lWorker.FreeOnTerminate := False;
      lWorker.Start;
      Assert.IsTrue(lTickDone.WaitFor(2000) = wrSignaled, 'worker tick complete without pumping');
      Assert.AreEqual(0, lCalls, 'queued main-thread callback unpumped');
      Assert.AreEqual<Int64>(fBase, CronDateTimeToInstantUs(Saved.CompletedThrough), 'W2 open');
      if lVariant = 1 then
      begin
        fCron.GlobalMaxConcurrentCallbacks := 1;
        Assert.IsTrue(fCron.Shutdown(0, spWait), 'queue has not acquired event execution');
      end;
      if lVariant = 2 then
        SetMaxCronBeforeQueuedAcquireHook(procedure(const aEvent: IMaxCronEvent)
          begin raise Exception.Create('abandoned queued acquisition'); end);
      CheckSynchronize(0);
      lWorker.WaitFor;
      lWorker.Free;
      lTickDone.Free;
      SetMaxCronBeforeQueuedAcquireHook(nil);
      if lVariant = 0 then
      begin
        Assert.AreEqual(1, lCalls);
        Assert.AreEqual<Int64>(fNow, CronDateTimeToInstantUs(Saved.CompletedThrough));
      end else begin
        Assert.AreEqual(0, lCalls);
        lState := Saved;
        Assert.AreEqual<Int64>(fBase, CronDateTimeToInstantUs(lState.CompletedThrough), 'W12 abandoned stays open');
        lCapture := TRestartStore.Create;
        lCapture.Save([lState]);
        lRestored := TmaxCron.Create(ctPortable);
        lRestored.ScheduleStore := lCapture;
        lRestored.RestoreScheduleState(True,
          procedure(const aEvent: IMaxCronEvent; const aSaved: TMaxCronPersistedEvent)
          begin aEvent.OnScheduleProc := procedure(aSender: IMaxCronEvent) begin Inc(lCalls); end; end);
        lRestored.TickAtUtcUs(fNow);
        Assert.AreEqual(1, lCalls, 'abandoned callback replays');
      end;
    finally
      SetMaxCronBeforeQueuedAcquireHook(nil);
      lRestored.Free;
      lCapture := nil;
      Finish;
    end;
  end;
  Start;
  try
    fEvent.OnScheduleProc := procedure(aSender: IMaxCronEvent) begin end;
    fEvent.Run;
    SetMaxCronBeforeDispatchHook(procedure(const aMode: TmaxCronInvokeMode)
      begin raise Exception.Create('start failure'); end);
    lRaised := False;
    try
      Advance(1000000);
    except
      on E: Exception do lRaised := E.Message = 'start failure';
    end;
    Assert.IsTrue(lRaised, 'start exception propagates');
    Assert.AreEqual<Int64>(fNow, CronDateTimeToInstantUs(Saved.CompletedThrough), 'W11 start failure settles');
  finally
    Finish;
  end;
end;

procedure TTestRestartCatchUp.QuiescentEquivalence;
const
  cPlans: array[0..3] of string = ('*/15 * * * *', '* * * * * * * 0',
    '@every 100ms', '@every 100ms fixed-delay');
var
  lPlan: string;
  lState: TMaxCronPersistedEvent;
  lA, lB: TmaxCron;
  lStoreA, lStoreB: IMaxCronScheduleStore;
  lFiresA, lFiresB: Integer;
  i: Integer;
begin
  for lPlan in cPlans do
  begin
    Start;
    lA := nil; lB := nil;
    try
      fEvent.EventPlan := lPlan;
      fEvent.OnScheduleProc := procedure(aSender: IMaxCronEvent) begin end;
      fEvent.Run;
      Advance(1000000);
      lState := Saved;
      lStoreA := TRestartStore.Create;
      lStoreB := TRestartStore.Create;
      lStoreA.Save([lState]);
      lState.CompletedThrough := 0;
      lStoreB.Save([lState]);
      lA := TmaxCron.Create(ctPortable); lB := TmaxCron.Create(ctPortable);
      lA.ScheduleStore := lStoreA; lB.ScheduleStore := lStoreB;
      lA.RestoreScheduleState; lB.RestoreScheduleState;
      lFiresA := 0; lFiresB := 0;
      lA.Snapshot[0].OnScheduleProc := procedure(aSender: IMaxCronEvent) begin Inc(lFiresA); end;
      lB.Snapshot[0].OnScheduleProc := procedure(aSender: IMaxCronEvent) begin Inc(lFiresB); end;
      for i := 0 to 9 do
      begin
        Assert.AreEqual<TDateTime>(lA.Snapshot[0].NextSchedule, lB.Snapshot[0].NextSchedule, 'R3 next');
        Inc(fNow, 1000000); Inc(fMono, 1000000);
        lA.TickAtUtcUs(fNow); lB.TickAtUtcUs(fNow);
        Assert.AreEqual(lFiresA, lFiresB, 'R3 fires');
      end;
    finally
      lA.Free; lB.Free;
      lStoreA := nil; lStoreB := nil;
      Finish;
    end;
  end;
end;

procedure TTestRestartCatchUp.UtcOverlapCheckpoint;
var
  lRestored: TmaxCron;
  lCalls: Integer;
  lState: TMaxCronPersistedEvent;
begin
  Start;
  lRestored := nil;
  try
    SetCronSystemTimeZoneForTests(TZoneAsSystemZone.Create(CreateCronZone('restart Warsaw', FakeZoneSource(0))));
    fNow := ZoneMs(2026, 10, 25, 0, 29) * 1000;
    fEvent.TimeZoneId := 'LOCAL';
    fEvent.DstFallPolicy := dfpRunTwice;
    fEvent.EventPlan := '30 2 * * *';
    fEvent.OnScheduleProc := procedure(aSender: IMaxCronEvent) begin end;
    fEvent.Run;
    fNow := ZoneMs(2026, 10, 25, 0, 30) * 1000;
    fCron.TickAtUtcUs(fNow);
    lState := Saved;
    Assert.AreEqual<Int64>(fNow, CronDateTimeToInstantUs(lState.CompletedThrough), 'checkpoint is first UTC instance');
    lRestored := TmaxCron.Create(ctPortable);
    lRestored.ScheduleStore := fStore;
    lCalls := 0;
    lRestored.RestoreScheduleState(True,
      procedure(const aEvent: IMaxCronEvent; const aSaved: TMaxCronPersistedEvent)
      begin aEvent.OnScheduleProc := procedure(aSender: IMaxCronEvent) begin Inc(lCalls); end; end);
    fNow := ZoneMs(2026, 10, 25, 1, 30) * 1000;
    lRestored.TickAtUtcUs(fNow);
    Assert.AreEqual(1, lCalls, 'second repeated-hour instance retained');
  finally
    lRestored.Free;
    Finish;
  end;
end;

procedure TTestRestartCatchUp.IntervalBatchCrashWindow;
var
  lInside: TMaxCronPersistedEvent;
  lCalls: Integer;
  lRestored: TmaxCron;
  lCapture: IMaxCronScheduleStore;
begin
  Start;
  lRestored := nil;
  try
    fCron.DefaultMisfireCatchUpLimit := 3;
    fEvent.EventPlan := '@every 100ms';
    lCalls := 0;
    fEvent.OnScheduleProc := procedure(aSender: IMaxCronEvent)
      begin Inc(lCalls); if lCalls = 2 then lInside := Saved; end;
    fEvent.Run;
    Advance(300000);
    Assert.AreEqual(3, lCalls);
    Assert.AreEqual<Int64>(fBase + 100000, CronDateTimeToInstantUs(lInside.CompletedThrough), 'W13 only first callback settled');
    Assert.AreEqual<UInt64>(1, lInside.NumOfExecutionsPerformed, 'only first execution covered');
    lCapture := TRestartStore.Create;
    lCapture.Save([lInside]);
    lRestored := TmaxCron.Create(ctPortable);
    lRestored.ScheduleStore := lCapture;
    lRestored.DefaultMisfireCatchUpLimit := 3;
    lCalls := 0;
    lRestored.RestoreScheduleState(True,
      procedure(const aEvent: IMaxCronEvent; const aSaved: TMaxCronPersistedEvent)
      begin aEvent.OnScheduleProc := procedure(aSender: IMaxCronEvent) begin Inc(lCalls); end; end);
    lRestored.TickAtUtcUs(fNow);
    Assert.AreEqual(2, lCalls, 'W13 replay second and third');
  finally
    lRestored.Free;
    lCapture := nil;
    Finish;
  end;
end;

procedure TTestRestartCatchUp.CheckpointBoundaryRepresentations;
var
  lState: TMaxCronPersistedEvent;
  lRestored: TmaxCron;
  lValue: TDateTime;
  lBits: UInt64;
  lVariant, lCalls, lNowOffset: Integer;
  lDueMs: Int64;
begin
  Start;
  try
    lDueMs := fBase div 1000 + 900000;
    for lVariant := 0 to 5 do for lNowOffset := -1 to 1 do
    begin
      lValue := CronMsToDateTime(lDueMs);
      case lVariant of
        0: lValue := CronMsToDateTime(lDueMs - 1);
        1: lValue := lValue - 0.4 / cCronMsPerDay;
        2: begin Move(lValue, lBits, SizeOf(lBits)); Dec(lBits); Move(lBits, lValue, SizeOf(lValue)); end;
        4: begin Move(lValue, lBits, SizeOf(lBits)); Inc(lBits); Move(lBits, lValue, SizeOf(lValue)); end;
        5: lValue := lValue + 0.4 / cCronMsPerDay;
      end;
      lState := Default(TMaxCronPersistedEvent);
      lState.Name := 'boundaries'; lState.EventPlan := '*/15 * * * *';
      lState.TimeZoneId := 'UTC'; lState.Dialect := cdMaxCron;
      lState.Enabled := True; lState.InvokeMode := imMainThread;
      lState.CompletedThrough := lValue;
      fStore.Save([lState]);
      fNow := lDueMs * 1000 + lNowOffset;
      lCalls := 0;
      lRestored := TmaxCron.Create(ctPortable);
      try
        lRestored.ScheduleStore := fStore;
        lRestored.RestoreScheduleState(True,
          procedure(const aEvent: IMaxCronEvent; const aSaved: TMaxCronPersistedEvent)
          begin aEvent.OnScheduleProc := procedure(aSender: IMaxCronEvent) begin Inc(lCalls); end; end);
        lRestored.TickAtUtcUs(fNow);
        Assert.AreEqual<Integer>(Ord((lVariant = 0) and (lNowOffset >= 0)), lCalls, 'checkpoint neighbour and precise now');
      finally
        lRestored.Free;
      end;
    end;
  finally
    Finish;
  end;
end;

procedure TTestRestartCatchUp.IntervalBatchDispatchFailure;
var
  lRaised: Boolean;
begin
  Start;
  try
    fCron.DefaultMisfireCatchUpLimit := 3;
    fEvent.EventPlan := '@every 100ms';
    fEvent.OnScheduleProc := procedure(aSender: IMaxCronEvent) begin end;
    fEvent.Run;
    SetMaxCronBeforeDispatchHook(procedure(const aMode: TmaxCronInvokeMode)
      begin raise Exception.Create('batch dispatch start failure'); end);
    lRaised := False;
    try
      Advance(300000);
    except
      on E: Exception do lRaised := E.Message = 'batch dispatch start failure';
    end;
    Assert.IsTrue(lRaised, 'batch failure remains reported');
    Assert.AreEqual<Int64>(fNow, CronDateTimeToInstantUs(Saved.CompletedThrough), 'reported batch start failure settles undispatched tickets');
  finally
    Finish;
  end;
end;

procedure TTestRestartCatchUp.RunCheckpointUsesSearchBase;
var
  lReads: Integer;
begin
  Start;
  try
    lReads := 0;
    SetMaxCronUtcClockHook(function: Int64
      begin
        Inc(lReads);
        if lReads = 1 then Result := fBase
        else Result := fBase + 1000000;
      end);
    fEvent.Run;
    Assert.AreEqual<Int64>(fBase + 1000000, CronDateTimeToInstantUs(fEvent.NextSchedule));
    Assert.AreEqual<Int64>(fBase, CronDateTimeToInstantUs(Saved.CompletedThrough),
      'Run checkpoint is the search base even if the clock crosses a second');
  finally
    Finish;
  end;
end;

procedure TTestRestartCatchUp.IntervalProjectionPrefix(const aEngine: string);
const
  cDelay: array[0..2] of Int64 = (0, 200000, 500000);
var
  lOldEngine: string;
  lLater: IMaxCronEvent;
  lCapture: IMaxCronScheduleStore;
  lRestored: TmaxCron;
  lStates: TArray<TMaxCronPersistedEvent>;
  lPolicy: TmaxCronMisfirePolicy;
  lMode, lLate, lDelay, lLimit, lBefore, lAfter, lExpected, lOwed, lTaken: Integer;
  lPass, lThrough, lNext, lCursor: Int64;
  lInject: Boolean;
begin
  lOldEngine := {$IFDEF FPC}SysUtils.{$ENDIF}GetEnvironmentVariable('MAXCRON_ENGINE');
  SetEnvironmentVariableW('MAXCRON_ENGINE', PChar(aEngine));
  try
    for lMode := 0 to 1 do for lPolicy := mpSkip to mpCatchUpAll do
      for lLate := 0 to 1 do for lDelay := 0 to High(cDelay) do for lLimit := 1 to 3 do
    begin
      if lLimit = 2 then Continue;
      Start;
      lRestored := nil;
      try
        fCron.DefaultMisfirePolicy := lPolicy;
        fCron.DefaultMisfireCatchUpLimit := lLimit;
        fEvent.EventPlan := '@every 100ms';
        fEvent.MisfirePolicy := mpFireOnceNow;
        fEvent.OnScheduleProc := procedure(aSender: IMaxCronEvent)
          begin Inc(fNow, cDelay[lDelay]); Inc(fMono, cDelay[lDelay]); end;
        lLater := fCron.Add('later');
        lLater.EventPlan := '@every 100ms';
        if lMode = 1 then lLater.EventPlan := '@every 100ms fixed-delay';
        lLater.InvokeMode := imMainThread;
        lBefore := 0; lAfter := 0;
        lLater.OnScheduleProc := procedure(aSender: IMaxCronEvent) begin Inc(lBefore); end;
        fEvent.Run; lLater.Run;
        lPass := fBase + 100000 + Int64(lLate) * 250000;
        fMono := fMono + (lPass - fNow); fNow := lPass;
        fCron.TickAtUtcUs(fNow);
        fCron.SaveScheduleState; fStore.TryLoad(lStates);
        // Independent grid enumeration for this pass, not fresh clock samples
        // after the earlier callback has delayed the rest of the due batch.
        lOwed := 0; lCursor := fBase + 100000;
        while lCursor <= lPass do
        begin
          Inc(lOwed); Inc(lCursor, 100000);
        end;
        lTaken := lOwed;
        if lTaken > lLimit then lTaken := lLimit;
        lExpected := 1;
        if (lPolicy = mpSkip) and (lOwed > 1) then lExpected := 0
        else if (lMode = 0) and (lPolicy = mpCatchUpAll) then lExpected := lTaken;
        Assert.AreEqual(lExpected, lBefore, 'same live pass outcomes');
        if lMode = 0 then
        begin
          if lPolicy = mpCatchUpAll then lThrough := fBase + Int64(lTaken) * 100000
          else lThrough := lCursor - 100000;
          lNext := lThrough + 100000;
        end else if lExpected = 0 then
        begin
          lThrough := lPass; lNext := lPass + 100000;
        end else begin
          lThrough := fNow; lNext := fNow + 100000;
        end;
        Assert.AreEqual<Int64>(lNext, CronDateTimeToInstantUs(lLater.NextSchedule), 'live next');
        Assert.IsTrue(CronDateTimeToInstantUs(lStates[1].CompletedThrough) < lNext,
          'MC-P6-R1-01: C cannot cover the earliest unfinished policy instance');
        Assert.AreEqual<Int64>(lThrough, CronDateTimeToInstantUs(lStates[1].CompletedThrough), 'settled grid prefix');
        lCapture := TRestartStore.Create; lCapture.Save([lStates[1]]);
        lRestored := TmaxCron.Create(ctPortable);
        lRestored.ScheduleStore := lCapture;
        lRestored.DefaultMisfirePolicy := lPolicy;
        lRestored.DefaultMisfireCatchUpLimit := lLimit;
        lRestored.RestoreScheduleState(True,
          procedure(const aEvent: IMaxCronEvent; const aSaved: TMaxCronPersistedEvent)
          begin aEvent.OnScheduleProc := procedure(aSender: IMaxCronEvent) begin Inc(lAfter); end; end);
        lOwed := 0; lCursor := lNext;
        while lCursor <= fNow do
        begin
          Inc(lOwed); Inc(lCursor, 100000);
        end;
        lExpected := 0;
        if lOwed > 0 then
        begin
          lExpected := 1;
          if (lPolicy = mpSkip) and (lOwed > 1) then lExpected := 0
          else if (lMode = 0) and (lPolicy = mpCatchUpAll) then
          begin lExpected := lOwed; if lExpected > lLimit then lExpected := lLimit; end;
        end;
        lRestored.TickAtUtcUs(fNow);
        Assert.AreEqual(lExpected, lAfter, 'unprocessed delayed instances remain owed');
      finally
        lLater := nil; lRestored.Free; lCapture := nil; Finish;
      end;
    end;
    Start;
    try
      lInject := False;
      SetMaxCronUtcClockHook(function: Int64
        begin
          if lInject then
          begin
            lInject := False; Inc(fNow,500000); Inc(fMono,500000);
          end;
          Result := fNow;
        end);
      fEvent.EventPlan := '@every 100ms fixed-delay';
      fEvent.OnScheduleProc := procedure(aSender: IMaxCronEvent) begin lInject := True; end;
      fEvent.Run;
      Advance(100000);
      Assert.IsTrue(CronDateTimeToInstantUs(Saved.CompletedThrough) < CronDateTimeToInstantUs(fEvent.NextSchedule),
        'completion UTC and rearm monotonic samples must share the same completion');
    finally
      Finish;
    end;
    Start;
    try
      fEvent.EventPlan := '@every 100ms fixed-delay';
      fEvent.OnScheduleProc := procedure(aSender: IMaxCronEvent)
        begin
          aSender.EventPlan := '@every 200ms fixed-delay';
          Inc(fNow,500000); Inc(fMono,500000);
        end;
      fEvent.Run;
      Advance(100000);
      Assert.IsTrue(CronDateTimeToInstantUs(Saved.CompletedThrough) < CronDateTimeToInstantUs(fEvent.NextSchedule),
        'an old completion cannot certify an unfinished replacement interval');
    finally
      Finish;
    end;
  finally
    SetEnvironmentVariableW('MAXCRON_ENGINE', PChar(lOldEngine));
  end;
end;

procedure TTestRestartCatchUp.LegacyTwoRestarts(const aEngine: string);
var
  lOldEngine: string;
  lOriginal, lRoundTrip: IMaxCronScheduleStore;
  lDirect, lMigrated: TmaxCron;
  lState: TMaxCronPersistedEvent;
  lStates: TArray<TMaxCronPersistedEvent>;
  lHost: ICronZoneRules;
  lPolicy: TmaxCronMisfirePolicy;
  lKind, lFold, i, lOneCalls, lTwoCalls: Integer;
  lFirst, lDueWall: Int64;
begin
  lOldEngine := {$IFDEF FPC}SysUtils.{$ENDIF}GetEnvironmentVariable('MAXCRON_ENGINE');
  SetEnvironmentVariableW('MAXCRON_ENGINE', PChar(aEngine));
  try
    for lKind := 0 to 2 do for lFold := 0 to 3 do for lPolicy := mpSkip to mpCatchUpAll do
    begin
      Start;
      lDirect := nil; lMigrated := nil;
      try
        if lFold = 0 then lHost := CreateCronZone('legacy UTC', TCronFixedZoneSource.Create(0))
        else lHost := CreateCronZone('legacy fold', FakeZoneSource(0));
        SetCronSystemTimeZoneForTests(TZoneAsSystemZone.Create(lHost));
        SetMaxCronWallClockHook(function: Int64
          begin Result := fNow + lHost.GetPeriod(fNow div 1000).OffsetMs * 1000; end);
        lState := Default(TMaxCronPersistedEvent);
        lState.Name := 'legacy'; lState.TimeZoneId := 'LOCAL'; lState.Dialect := cdMaxCron;
        lState.Enabled := True; lState.InvokeMode := imMainThread; lState.DstFallPolicy := dfpRunTwice;
        if lFold = 0 then
        begin
          lState.EventPlan := '* * * * * * * 0';
          fNow := fBase + 3000000; lDueWall := fBase + 1000000;
        end else begin
          lFirst := ZoneMs(2026, 10, 25, 0, 30) * 1000;
          lState.EventPlan := '30 2 25 10 * 2026 0 0';
          lDueWall := lFirst + 7200000000;
          if lFold = 1 then fNow := lFirst + 1200000000
          else fNow := lFirst + 4200000000;
          if lFold = 3 then lState.LastExecution := CronInstantUsToDateTime(lDueWall);
        end;
        if lKind = 1 then lState.EventPlan := '@every 1s';
        if lKind = 2 then lState.EventPlan := '@every 1s fixed-delay';
        lState.NextSchedule := CronInstantUsToDateTime(lDueWall);
        lOriginal := TRestartStore.Create; lRoundTrip := TRestartStore.Create;
        lOriginal.Save([lState]); lRoundTrip.Save([lState]);
        lDirect := TmaxCron.Create(ctPortable); lMigrated := TmaxCron.Create(ctPortable);
        lDirect.ScheduleStore := lOriginal; lMigrated.ScheduleStore := lRoundTrip;
        lDirect.DefaultMisfirePolicy := lPolicy; lDirect.DefaultMisfireCatchUpLimit := 3;
        lMigrated.RestoreScheduleState; lMigrated.SaveScheduleState;
        lRoundTrip.TryLoad(lStates);
        Assert.AreEqual<TDateTime>(0, lStates[0].CompletedThrough,
          'MC-P6-R1-02: a restore/save without a tick cannot certify the gap');
        lMigrated.Free; lMigrated := TmaxCron.Create(ctPortable);
        lMigrated.ScheduleStore := lRoundTrip;
        lMigrated.DefaultMisfirePolicy := lPolicy; lMigrated.DefaultMisfireCatchUpLimit := 3;
        lOneCalls := 0; lTwoCalls := 0;
        lDirect.RestoreScheduleState(True,
          procedure(const aEvent: IMaxCronEvent; const aSaved: TMaxCronPersistedEvent)
          begin aEvent.OnScheduleProc := procedure(aSender: IMaxCronEvent) begin Inc(lOneCalls); end; end);
        lMigrated.RestoreScheduleState(True,
          procedure(const aEvent: IMaxCronEvent; const aSaved: TMaxCronPersistedEvent)
          begin aEvent.OnScheduleProc := procedure(aSender: IMaxCronEvent) begin Inc(lTwoCalls); end; end);
        for i := 0 to 9 do
        begin
          Assert.AreEqual(lDirect.Snapshot[0].Enabled, lMigrated.Snapshot[0].Enabled, 'legacy enabled round-trip');
          Assert.AreEqual<TDateTime>(lDirect.Snapshot[0].NextSchedule, lMigrated.Snapshot[0].NextSchedule, 'legacy next round-trip');
          lDirect.TickAtUtcUs(fNow); lMigrated.TickAtUtcUs(fNow);
          Assert.AreEqual(lOneCalls, lTwoCalls, 'legacy owed instances survive a second restart');
          Inc(fNow, 1000000); Inc(fMono, 1000000);
        end;
      finally
        lDirect.Free; lMigrated.Free; lOriginal := nil; lRoundTrip := nil;
        Finish; lHost := nil;
      end;
    end;
  finally
    SetEnvironmentVariableW('MAXCRON_ENGINE', PChar(lOldEngine));
  end;
end;

procedure TTestRestartCatchUp.PositiveFiniteFold(const aEngine: string);
const
  cZones: array[0..3] of string = ('LOCAL', 'UTC', 'UTC+05:30', 'Test/RestartFinite');
var
  lOldEngine, lPlan, lContext: string;
  lState: TMaxCronPersistedEvent;
  lStates: TArray<TMaxCronPersistedEvent>;
  lRestored: TmaxCron;
  lDues, lPasses: TArray<Int64>;
  lFirst, lSecond, lWall, lCheck, lStartNow, lExpectedC, lDue, lFloorNow: Int64;
  lZone, lFall, lPolicy, lCheckpoint, lNowCase, lBounds, lLimit, lHistory, lCap, lSavedDue: Integer;
  lRows, lCases, lIndex, lCalls, lExpectedCalls, lThisPass, i: Integer;
  lEligible, lLocal, lAllowed: Boolean;
begin
  lOldEngine := {$IFDEF FPC}SysUtils.{$ENDIF}GetEnvironmentVariable('MAXCRON_ENGINE');
  SetEnvironmentVariableW('MAXCRON_ENGINE', PChar(aEngine));
  Start;
  try
    SetCronSystemTimeZoneForTests(TZoneAsSystemZone.Create(CreateCronZone('positive fold host', FakeZoneSource(0))));
    RegisterCronZoneForTests('Test/RestartFinite', FakeZoneSource(0));
    lFirst := ZoneMs(2026, 10, 25, 0, 30) * 1000;
    lSecond := lFirst + 3600000000;
    lWall := lFirst + 7200000000;
    lRows := 0; lCases := 0;
    // The reference is the two known UTC instances of this finite wall plan.
    // It does not call scheduler search, restore, or the live policy path.
    for lZone := 0 to 3 do for lFall := 0 to 3 do for lPolicy := 1 to 3 do
      for lCheckpoint := 0 to 4 do for lNowCase := 0 to 3 do for lBounds := 0 to 5 do
      for lLimit := 0 to 1 do for lHistory := 0 to 1 do for lCap := 1 to 3 do for lSavedDue := 0 to 1 do
    begin
      if (lCap = 2) or ((lCheckpoint = 0) and (lHistory = 1)) then Continue;
      Inc(lRows);
      {$IFNDEF MAXCRON_LONG_TESTS}
      if (lRows mod 383 <> 0) and not ((lCheckpoint = 0) and (lBounds = 0) and
        (lLimit = 0) and (lHistory = 0) and (lCap = 1) and (lSavedDue = 0)) then Continue;
      {$ENDIF}
      Inc(lCases);
      case lCheckpoint of
        0: lCheck := lFirst - 1000000;
        1: lCheck := lFirst;
        2: lCheck := lFirst + 1000;
        3: lCheck := lSecond - 1000;
      else lCheck := lSecond;
      end;
      case lNowCase of
        0: lStartNow := lFirst - 1;
        1: lStartNow := lFirst;
        2: lStartNow := lSecond - 1;
      else lStartNow := lSecond + 1000000;
      end;
      lState := Default(TMaxCronPersistedEvent);
      lState.Name := 'positive finite'; lState.Enabled := True;
      lState.TimeZoneId := cZones[lZone]; lState.Dialect := cdMaxCron; lState.InvokeMode := imMainThread;
      lState.DstFallPolicy := TmaxCronDstFallPolicy(lFall);
      lState.CompletedThrough := CronInstantUsToDateTime(lCheck);
      lState.NumOfExecutionsPerformed := lHistory;
      lLocal := (lZone = 0) or (lZone = 3);
      if lLocal then lPlan := '30 2' else if lZone = 1 then lPlan := '30 0,1' else lPlan := '0 6,7';
      lState.EventPlan := lPlan + ' 25 10 * 2026 0 ' + IntToStr(lLimit);
      case lBounds of
        1: lState.ValidFrom := CronInstantUsToDateTime(lWall);
        2: lState.ValidTo := CronInstantUsToDateTime(lWall);
        3: begin lState.ValidFrom := CronInstantUsToDateTime(lWall); lState.ValidTo := lState.ValidFrom; end;
        4: lState.ValidTo := CronInstantUsToDateTime(lWall - 1000);
        5: lState.ValidFrom := CronInstantUsToDateTime(lWall + 1000);
      end;
      if lSavedDue = 1 then lState.NextSchedule := CronInstantUsToDateTime(lSecond + 86400000000);
      lState.NextScheduleNeedsResolve := True; // both saved due fields must be ignored
      lDues := nil;
      lAllowed := lBounds < 4;
      if lAllowed and (lFirst > lCheck) and
        (not lLocal or (lFall <> Ord(dfpRunOncePreferSecondInstance))) then lDues := lDues + [lFirst];
      if lAllowed and (lSecond > lCheck) and
        (not lLocal or (lFall = Ord(dfpRunTwice)) or (lFall = Ord(dfpRunOncePreferSecondInstance))) then
        lDues := lDues + [lSecond];
      lEligible := (Length(lDues) > 0) and ((lLimit = 0) or (lHistory < lLimit));
      fStore.Save([lState]); fNow := lStartNow;
      lCalls := 0; lExpectedCalls := 0; lIndex := 0; lExpectedC := lCheck;
      lContext := Format('positive fold engine=%s zone=%d fall=%d policy=%d C=%d now=%d bounds=%d limit=%d history=%d L=%d saved=%d',
        [aEngine,lZone,lFall,lPolicy,lCheckpoint,lNowCase,lBounds,lLimit,lHistory,lCap,lSavedDue]);
      lRestored := TmaxCron.Create(ctPortable);
      try
        lRestored.ScheduleStore := fStore;
        lRestored.DefaultMisfirePolicy := TmaxCronMisfirePolicy(lPolicy);
        lRestored.DefaultMisfireCatchUpLimit := lCap;
        lRestored.RestoreScheduleState(True,
          procedure(const aEvent: IMaxCronEvent; const aSaved: TMaxCronPersistedEvent)
          begin aEvent.OnScheduleProc := procedure(aSender: IMaxCronEvent) begin Inc(lCalls); end; end);
        Assert.AreEqual(lEligible, lRestored.Snapshot[0].Enabled, lContext + ' enabled before pass');
        if lEligible then Assert.AreEqual<Int64>(lWall, CronDateTimeToInstantUs(lRestored.Snapshot[0].NextSchedule), lContext + ' next display');
        lPasses := [lStartNow, 0, 0, 0];
        lPasses[1] := lStartNow + 1000000; if lPasses[1] < lFirst then lPasses[1] := lFirst;
        lPasses[2] := lPasses[1] + 1000000; if lPasses[2] < lSecond then lPasses[2] := lSecond;
        lPasses[3] := lPasses[2] + 1000000;
        for i := 0 to High(lPasses) do
        begin
          fNow := lPasses[i]; lThisPass := 0;
          lFloorNow := CronFloorDiv(fNow, 1000000) * 1000000;
          if lEligible and (lIndex < Length(lDues)) and (lDues[lIndex] <= fNow) and
            ((lLimit = 0) or (lHistory + lExpectedCalls < lLimit)) then
          begin
            if lPolicy = Ord(mpCatchUpAll) then
            begin
              while (lIndex < Length(lDues)) and (lDues[lIndex] <= fNow) and (lThisPass < lCap) and
                ((lLimit = 0) or (lHistory + lExpectedCalls < lLimit)) do
              begin
                lExpectedC := lDues[lIndex]; Inc(lIndex); Inc(lThisPass); Inc(lExpectedCalls);
              end;
            end else begin
              lDue := lDues[lIndex];
              if (lPolicy = Ord(mpFireOnceNow)) or (fNow - lDue < 1000000) then Inc(lExpectedCalls);
              while (lIndex < Length(lDues)) and (lDues[lIndex] <= lFloorNow) do Inc(lIndex);
              if lFloorNow > lExpectedC then lExpectedC := lFloorNow;
            end;
          end;
          lRestored.TickAtUtcUs(fNow);
          Assert.AreEqual(lExpectedCalls, lCalls, lContext + ' occurrence outcomes pass=' + IntToStr(i));
          lRestored.SaveScheduleState; fStore.TryLoad(lStates);
          Assert.AreEqual<Int64>(lExpectedC, CronDateTimeToInstantUs(lStates[0].CompletedThrough), lContext + ' settled UTC prefix');
        end;
      finally
        lRestored.Free;
      end;
    end;
    System.WriteLn('POSITIVE_FINITE engine=',aEngine,' cases=',lCases,' full_rows=',lRows);
  finally
    Finish; ClearCronZonesForTests;
    SetEnvironmentVariableW('MAXCRON_ENGINE', PChar(lOldEngine));
  end;
end;

procedure TTestRestartCatchUp.PositiveIntervalOutcomes(const aEngine: string);
const
  cIntervals: array[0..2] of Int64 = (1000, 100000, 5000000);
var
  lOldEngine, lContext: string;
  lState: TMaxCronPersistedEvent;
  lStates: TArray<TMaxCronPersistedEvent>;
  lRestored: TmaxCron;
  lI, lDelta, lC, lDue, lWake, lExpectedC, lPersistedC, lFrom, lTo, lCursor, lLast, lThrough: Int64;
  lDues: TArray<Int64>;
  lSize, lMode, lPolicy, lOffset, lBounds, lCap, lStep, lCalls, lExpectedCalls, lTake, i, lCases: Integer;
  lEnabled: Boolean;
begin
  lOldEngine := {$IFDEF FPC}SysUtils.{$ENDIF}GetEnvironmentVariable('MAXCRON_ENGINE');
  SetEnvironmentVariableW('MAXCRON_ENGINE', PChar(aEngine));
  Start;
  try
    lCases := 0;
    for lSize := 0 to 2 do for lMode := 0 to 1 do for lPolicy := 1 to 3 do
      for lOffset := 0 to 5 do for lBounds := 0 to 5 do for lCap := 1 to 3 do
    begin
      if lCap = 2 then Continue;
      Inc(lCases); lI := cIntervals[lSize];
      fNow := fBase; fMono := 100000000;
      case lOffset of
        0: lDelta := -12300000;
        1: lDelta := -lI;
        2: lDelta := -1;
        3: lDelta := 0;
        4: lDelta := 2000000;
      else lDelta := 60000000;
      end;
      lState := Default(TMaxCronPersistedEvent);
      lState.Name := 'positive interval'; lState.Enabled := True;
      lState.TimeZoneId := 'UTC'; lState.Dialect := cdMaxCron; lState.InvokeMode := imMainThread;
      lState.EventPlan := '@every ' + IntToStr(lI div 1000) + 'ms';
      if lMode = 1 then lState.EventPlan := lState.EventPlan + ' fixed-delay';
      lState.CompletedThrough := CronInstantUsToDateTime(fNow + lDelta);
      lC := CronDateTimeToInstantUs(lState.CompletedThrough);
      lState.NextSchedule := CronInstantUsToDateTime(fNow + 900000000);
      lFrom := 0; lTo := 0;
      case lBounds of
        1: lFrom := fNow;
        2: lFrom := fNow - lI;
        3: lTo := fNow;
        4: lTo := fNow - lI;
        5: begin lFrom := fNow - lI; lTo := fNow; end;
      end;
      lState.ValidFrom := CronInstantUsToDateTime(lFrom);
      lState.ValidTo := CronInstantUsToDateTime(lTo);
      fStore.Save([lState]);
      lDue := lC + lI; if lDue > fNow + lI then lDue := fNow + lI;
      lWake := lDue; lExpectedC := lC; lExpectedCalls := 0; lCalls := 0; lLast := 0; lEnabled := True;
      lContext := Format('positive interval engine=%s I=%d mode=%d policy=%d delta=%d bounds=%d L=%d',
        [aEngine,lI,lMode,lPolicy,lOffset,lBounds,lCap]);
      lRestored := TmaxCron.Create(ctPortable);
      try
        lRestored.ScheduleStore := fStore;
        lRestored.DefaultMisfirePolicy := TmaxCronMisfirePolicy(lPolicy);
        lRestored.DefaultMisfireCatchUpLimit := lCap;
        lRestored.RestoreScheduleState(True,
          procedure(const aEvent: IMaxCronEvent; const aSaved: TMaxCronPersistedEvent)
          begin aEvent.OnScheduleProc := procedure(aSender: IMaxCronEvent) begin Inc(lCalls); end; end);
        for lStep := 0 to 3 do
        begin
          if lEnabled and (lWake <= fNow) then
          begin
            // Phase 2 4.8 gates the projected first due before choosing outcomes.
            if (lTo > 0) and (lDue > lTo) then lEnabled := False
            else if lDue < lFrom then
            begin
              lDue := lFrom; lWake := lFrom;
            end else begin
              lDues := nil; lCursor := lDue;
              while lCursor <= fNow do
              begin
                lDues := lDues + [lCursor]; Inc(lCursor,lI);
              end;
              lTake := Length(lDues);
              if lPolicy = Ord(mpSkip) then
              begin if lTake > 1 then lTake := 0; end
              else if lPolicy = Ord(mpFireOnceNow) then lTake := 1
              else if lTake > lCap then lTake := lCap;
              if lMode = 1 then
              begin
                if lTake > 0 then
                begin
                  lTake := 1; lLast := lDue;
                end;
                lThrough := fNow; lDue := fNow + lI;
              end else if lPolicy = Ord(mpCatchUpAll) then
              begin
                for i := 0 to lTake - 1 do lLast := lDues[i];
                lThrough := lDues[lTake - 1]; lDue := lThrough + lI;
              end else begin
                if lTake > 0 then
                  if lPolicy = Ord(mpFireOnceNow) then lLast := lDues[High(lDues)] else lLast := lDues[0];
                lThrough := lDues[High(lDues)]; lDue := lCursor;
              end;
              // A future checkpoint clamps the due to one interval but never
              // moves the already completed prefix backwards (ledger C1).
              if lThrough > lExpectedC then lExpectedC := lThrough;
              Inc(lExpectedCalls,lTake);
              lWake := lDue; if lWake <= fNow then lWake := fNow + lI;
            end;
          end;
          lRestored.TickAtUtcUs(fNow);
          Assert.AreEqual(lExpectedCalls,lCalls,lContext + ' reference outcomes');
          Assert.AreEqual(lEnabled,lRestored.Snapshot[0].Enabled,lContext + ' validity outcome');
          if lEnabled then Assert.AreEqual<Int64>(lDue div 1000,CronDateTimeToMs(lRestored.Snapshot[0].NextSchedule),lContext + ' next');
          if lExpectedCalls > 0 then Assert.AreEqual<Int64>(lLast div 1000,CronDateTimeToMs(lRestored.Snapshot[0].LastExecution),lContext + ' last outcome');
          lRestored.SaveScheduleState; fStore.TryLoad(lStates);
          // R2: save is bounded by the predecessor of the live due because
          // restore adds I. Ledger C1 still applies only to the in-memory C.
          lPersistedC := lExpectedC;
          if lEnabled and (lPersistedC > lDue - lI) then lPersistedC := lDue - lI;
          Assert.AreEqual<Int64>(lPersistedC,CronDateTimeToInstantUs(lStates[0].CompletedThrough),lContext + ' prefix');
          Inc(fNow,lI); Inc(fMono,lI);
        end;
      finally
        lRestored.Free;
      end;
    end;
    System.WriteLn('POSITIVE_INTERVAL engine=',aEngine,' cases=',lCases);
  finally
    Finish;
    SetEnvironmentVariableW('MAXCRON_ENGINE', PChar(lOldEngine));
  end;
end;


procedure TTestRestartCatchUp.SaveWideLegacyClockProperty(const aEngine: string);
var
  lStates, lSaved: TArray<TMaxCronPersistedEvent>;
  lChanges: array[0..0] of TZoneChange;
  lUtcReads, lWallReads, lMonoReads, lMode, i, lExpectedReads: Integer;
  lPairUtc, lPairMono, lExpectedNext, lExpectedLast, lExpectedC: Int64;
  lSaving, lStalled: Boolean;
  lContext: string;
begin
  // Six mixed records: two identical C=0 rate grids, two identical C=0
  // delay grids, UTC cron history, and a positive-checkpoint interval.
  for lMode := 0 to 3 do
  begin
    Start;
    try
      fNow := fBase+1350000; fMono := 101350000;
      lSaving := False; lStalled := False;
      SetLength(lStates,6);
      for i := 0 to 5 do
      begin
        lStates[i] := Default(TMaxCronPersistedEvent);
        lStates[i].Name := 'save legacy ' + IntToStr(i);
        lStates[i].EventPlan := '@every 100ms';
        if (i=2) or (i=3) then lStates[i].EventPlan := '@every 100ms fixed-delay';
        if i=4 then lStates[i].EventPlan := '* * * * * * * 0';
        lStates[i].Dialect := cdMaxCron; lStates[i].TimeZoneId := 'UTC';
        lStates[i].Enabled := True; lStates[i].InvokeMode := imMainThread;
        lStates[i].NumOfExecutionsPerformed := 1;
        lStates[i].LastExecution := CronInstantUsToDateTime(fBase+100000);
        lStates[i].NextSchedule := CronInstantUsToDateTime(fBase+200000);
        if i=4 then
        begin
          lStates[i].LastExecution := CronInstantUsToDateTime(fBase+1000000);
          lStates[i].NextSchedule := CronInstantUsToDateTime(fBase+2000000);
        end;
        if i=5 then lStates[i].CompletedThrough := CronInstantUsToDateTime(fBase+100000);
      end;
      fStore.Save(lStates); fEvent := nil;
      fCron.RestoreScheduleState(True);
      lUtcReads := 0; lWallReads := 0; lMonoReads := 0;
      SetMaxCronUtcClockHook(function: Int64
        begin
          if lSaving then Inc(lUtcReads);
          Result := fNow;
          if lSaving and (lMode=2) and Odd(lUtcReads) then Dec(fNow,5000);
          if lSaving and (lMode=3) and (lUtcReads=1) then
          begin
            lStalled := True; TThread.Sleep(1); Inc(fNow,750000); Inc(fMono,750000);
          end;
        end);
      SetMaxCronWallClockHook(function: Int64
        begin
          if lSaving then Inc(lWallReads);
          Result := fNow;
        end);
      SetMaxCronMonotonicClockHook(function: Int64
        begin
          if lSaving then
          begin
            Inc(lMonoReads);
            // The reviewer's original getter stall, which must be unreachable
            // once interval serialization has zero wall/monotonic getter reads.
            if (lMode=1) and (lWallReads=1) and not lStalled then
            begin
              lStalled := True; Inc(fMono,750000); Inc(fNow,750000);
            end;
          end;
          Result := fMono;
        end);
      lSaving := True;
      try fCron.SaveScheduleState; finally lSaving := False; end;
      fStore.TryLoad(lSaved);
      lContext := Format('save legacy engine=%s mode=%d',[aEngine,lMode]);
      for i := 0 to 5 do
        if i<>4 then
        begin
          Assert.AreEqual<Int64>(fNow+100200000-fMono,
            CronDateTimeToInstantUs(fCron.Snapshot[i].NextSchedule),'public next getter keeps live wall projection');
          Assert.AreEqual<Int64>(fBase+100000,
            CronDateTimeToInstantUs(fCron.Snapshot[i].LastExecution),'public historical last unchanged');
        end;
      lExpectedReads := 2; if lMode=2 then lExpectedReads := 16;
      Assert.AreEqual(lExpectedReads,lUtcReads,lContext+' one capture chain');
      Assert.AreEqual(0,lWallReads,lContext+' zero interval wall reads');
      Assert.AreEqual(lExpectedReads,lMonoReads,lContext+' zero per-event monotonic reads');
      if lMode=1 then Assert.IsFalse(lStalled,'getter stall is unreachable');
      if lMode=3 then Assert.IsTrue(lStalled,'capture stall exercised');
      for i := 0 to 3 do
        Assert.AreEqual<Int64>(0,CronDateTimeToInstantUs(lSaved[i].CompletedThrough),'legacy C stays absent before settlement');
      if lMode=2 then
      begin
        Assert.IsFalse(GetMaxCronPersistenceClockForTests(lPairUtc,lPairMono),'shared rejection');
        for i := 0 to 5 do
          if i<>4 then
          begin
            Assert.AreEqual<Int64>(1000,CronDateTimeToInstantUs(lSaved[i].NextSchedule),'shared safe legacy fallback');
            Assert.AreEqual<Int64>(0,CronDateTimeToInstantUs(lSaved[i].LastExecution),'fallback bypasses history projection');
          end;
      end else begin
        Assert.IsTrue(GetMaxCronPersistenceClockForTests(lPairUtc,lPairMono),'accepted shared pair');
        // Independently retained monotonic identities of the restored records.
        lExpectedNext := lPairUtc+100200000-lPairMono;
        // Historical LastExecution is copied unchanged under the same lock;
        // only live deadlines are projected through the shared save pair.
        lExpectedLast := fBase+100000;
        for i := 0 to 5 do
          if i<>4 then
          begin
            Assert.AreEqual<Int64>(lExpectedNext,CronDateTimeToInstantUs(lSaved[i].NextSchedule),lContext+' shared next');
            Assert.AreEqual<Int64>(lExpectedLast,CronDateTimeToInstantUs(lSaved[i].LastExecution),lContext+' shared last');
          end;
        lExpectedC := fBase+100000;
        if lExpectedC>lExpectedNext-100000 then lExpectedC := lExpectedNext-100000;
        Assert.AreEqual<Int64>(lExpectedC,CronDateTimeToInstantUs(lSaved[5].CompletedThrough),'positive checkpoint uses same frame');
      end;
      for i := 1 to 3 do
      begin
        Assert.AreEqual<Int64>(CronDateTimeToInstantUs(lSaved[0].NextSchedule),CronDateTimeToInstantUs(lSaved[i].NextSchedule),'identical legacy next');
        Assert.AreEqual<Int64>(CronDateTimeToInstantUs(lSaved[0].LastExecution),CronDateTimeToInstantUs(lSaved[i].LastExecution),'identical legacy last');
      end;
      Assert.AreEqual<Int64>(CronDateTimeToInstantUs(lStates[4].NextSchedule),CronDateTimeToInstantUs(lSaved[4].NextSchedule),'UTC cron deadline unchanged');
    finally
      lSaving := False; Finish;
    end;
  end;
  // Preserve the existing Wp(x)=Wall(sample)+(x-Mono(sample)) semantics.
  // A future offset change must not change an otherwise identical C=0 save.
  for lMode := -1 to 1 do
  begin
    if lMode=0 then Continue;
    Start;
    try
      fNow := fBase+400000;
      lChanges[0].UtcMs := (fBase+500000) div 1000;
      lChanges[0].OffsetMs := Int64(lMode)*3600000;
      SetCronSystemTimeZoneForTests(TZoneAsSystemZone.Create(CreateCronZone(
        'save legacy boundary '+IntToStr(lMode),TFakeZoneSource.Create(0,lChanges))));
      SetLength(lStates,2);
      for i := 0 to 1 do
      begin
        lStates[i] := Default(TMaxCronPersistedEvent);
        lStates[i].Name := 'legacy boundary '+IntToStr(i);
        lStates[i].EventPlan := '@every 100ms';
        if i=1 then lStates[i].EventPlan := '@every 100ms fixed-delay';
        lStates[i].Dialect := cdMaxCron; lStates[i].TimeZoneId := 'UTC';
        lStates[i].Enabled := True; lStates[i].InvokeMode := imMainThread;
        lStates[i].LastExecution := CronInstantUsToDateTime(fBase+300000);
        lStates[i].NextSchedule := CronInstantUsToDateTime(fBase+500000);
      end;
      fStore.Save(lStates); fEvent := nil; fCron.RestoreScheduleState(True);
      fCron.SaveScheduleState; fStore.TryLoad(lSaved);
      for i := 0 to 1 do
      begin
        Assert.AreEqual<Int64>(fBase+500000,CronDateTimeToInstantUs(fCron.Snapshot[i].NextSchedule),'public wall projection before transition');
        Assert.AreEqual<Int64>(fBase+500000,CronDateTimeToInstantUs(lSaved[i].NextSchedule),'saved wall projection uses sample offset');
        Assert.AreEqual<Int64>(fBase+300000,CronDateTimeToInstantUs(lSaved[i].LastExecution),'cached history before transition');
        Assert.AreEqual<Int64>(0,CronDateTimeToInstantUs(lSaved[i].CompletedThrough),'legacy absence at zone boundary');
      end;
    finally
      Finish;
    end;
  end;
  System.WriteLn('SAVE_WIDE_LEGACY engine=',aEngine,' cases=4 mixed_events=6 zone_boundaries=2');
end;

procedure TTestRestartCatchUp.SaveWideClockProperty(const aEngine: string);
const
  cJumps: array[0..4] of Int64 = (-2000000, -500000, 0, 500000, 2000000);
var
  lEvents: array[0..3] of IMaxCronEvent;
  lLiveIds, lReplayIds: array[0..3] of TList<Int64>;
  lStoreObject: TRestartStore;
  lStates: TArray<TMaxCronPersistedEvent>;
  lRestored: TmaxCron;
  lSeed, lSeeds, lPlace, lSize, lStallCase, lUtcReads, lWallReads, lMonoReads, lExpectedReads: Integer;
  lCases, lFallbacks, i, j: Integer;
  lInterval, lJump, lStall, lPairUtc, lPairMono, lDelta, lFirstMono, lExpected: Int64;
  lContext: string;
  lSaving, lArmed, lInitial, lCoherent: Boolean;
begin
  lSeeds := 1;
  if {$IFDEF FPC}SysUtils.{$ENDIF}GetEnvironmentVariable('MAXCRON_LONG_TESTS') = '1' then lSeeds := 8;
  lCases := 0; lFallbacks := 0;
  for lSeed := 0 to lSeeds - 1 do for lPlace := 0 to 6 do
    for lSize := 0 to High(cJumps) do for lStallCase := 0 to 1 do
  begin
    // Place 6 is one all-rejected save per seed, shared by every event.
    if (lPlace = 6) and ((lSize <> 0) or (lStallCase <> 0)) then Continue;
    for i := 0 to 3 do
    begin
      lLiveIds[i] := TList<Int64>.Create; lReplayIds[i] := TList<Int64>.Create;
    end;
    Start; lRestored := nil; lStoreObject := nil; lSaving := False;
    try
      if lPlace = 6 then
      begin
        fNow := 10000; Inc(lFallbacks);
      end else Inc(lCases);
      lStoreObject := TRestartStore.Create;
      fStore := lStoreObject; fCron.ScheduleStore := fStore;
      fCron.DefaultMisfireCatchUpLimit := 100000;
      lInterval := 100000;
      if (lSeed mod 3) = 1 then lInterval := 1000;
      if (lSeed mod 3) = 2 then lInterval := 5000000;
      lJump := cJumps[lSize] + Int64(lSeed) * 137;
      lStall := Int64(lStallCase) * 750000;
      lEvents[0] := fEvent;
      for i := 1 to 3 do lEvents[i] := fCron.Add('save-wide ' + IntToStr(i));
      lInitial := True;
      for i := 0 to 3 do
      begin
        lEvents[i].Tag := i;
        lEvents[i].InvokeMode := imMainThread; lEvents[i].TimeZoneId := 'UTC';
        lEvents[i].EventPlan := Format('@every %dms', [lInterval div 1000]);
        if i = 2 then lEvents[i].EventPlan := lEvents[i].EventPlan + ' fixed-delay';
        if i = 3 then lEvents[i].EventPlan := '* * * * * * * 0';
        lEvents[i].OnScheduleProc := procedure(aSender: IMaxCronEvent)
          begin
            if lInitial then
            begin
              if aSender.Tag = 0 then
              begin Inc(fMono,1250000); Inc(fNow,1250000); end;
            end else RecordOccurrence(lLiveIds[aSender.Tag], aSender.Tag = 3);
          end;
        lEvents[i].Run;
      end;
      Advance(lInterval); lInitial := False;
      lUtcReads := 0; lWallReads := 0; lMonoReads := 0; lArmed := True;
      lStoreObject.AfterSave := procedure
        begin
          // The array has already been copied into the store at this point.
          if lSaving and lArmed and (lPlace = 5) then
          begin
            lArmed := False; Inc(fMono,lStall); Inc(fNow,lStall+lJump);
          end;
        end;
      SetMaxCronBeforeSaveEventHook(procedure(const aEvent: IMaxCronEvent; const aIndex: Integer)
        begin
          // Explicit serialization seam keeps this placement exercised even
          // when saving no longer calls any clock-reading event getter.
          if lSaving and lArmed and (lPlace = 4) and (aIndex = 1) then
          begin
            lArmed := False; Inc(fMono,lStall); Inc(fNow,lStall+lJump);
          end;
        end);
      SetMaxCronWallClockHook(function: Int64
        begin
          if lSaving then Inc(lWallReads);
          Result := fNow;
        end);
      SetMaxCronMonotonicClockHook(function: Int64
        begin
          if lSaving then Inc(lMonoReads);
          Result := fMono;
        end);
      SetMaxCronUtcClockHook(function: Int64
        begin
          if lSaving then
          begin
            Inc(lUtcReads);
            if lArmed and (((lPlace = 0) and (lUtcReads = 1)) or
              ((lPlace = 2) and (lUtcReads = 2))) then
            begin
              lArmed := False;
              if lStall > 0 then TThread.Sleep(1);
              Inc(fMono,lStall); Inc(fNow,lStall+lJump);
            end;
          end;
          Result := fNow;
          if lSaving then
          begin
            if lPlace = 6 then
            begin
              if Odd(lUtcReads) then Dec(fNow,5000) else Inc(fNow,5000);
            end else if lArmed and (((lPlace = 1) and (lUtcReads = 1)) or
              ((lPlace = 3) and (lUtcReads = 2))) then
            begin
              lArmed := False;
              if lStall > 0 then TThread.Sleep(1);
              Inc(fMono,lStall); Inc(fNow,lStall+lJump);
            end;
          end;
        end);
      lSaving := True;
      try fCron.SaveScheduleState; finally lSaving := False; end;
      fStore.TryLoad(lStates);
      lContext := Format('save-wide seed=%d place=%d jump=%d stall=%d engine=%s',
        [lSeed,lPlace,lJump,lStall,aEngine]);
      lExpectedReads := 2;
      if ((lPlace = 1) or (lPlace = 2)) and
        ((lStall+lJump < 0) or (lStall+lJump > lStall+2000)) then lExpectedReads := 4;
      if lPlace = 6 then lExpectedReads := 16;
      Assert.AreEqual(lExpectedReads,lUtcReads,lContext + ' one capture result for all four events');
      Assert.AreEqual(0,lWallReads,lContext + ' zero wall reads');
      Assert.AreEqual(lExpectedReads,lMonoReads,lContext + ' only capture-chain monotonic reads');
      if lPlace <> 6 then Assert.IsFalse(lArmed,lContext + ' correction placement exercised');
      lCoherent := GetMaxCronPersistenceClockForTests(lPairUtc,lPairMono);
      Assert.AreEqual(lPlace <> 6,lCoherent,lContext + ' shared acceptance/fallback');
      Assert.AreEqual<Int64>(CronDateTimeToInstantUs(lStates[0].CompletedThrough),
        CronDateTimeToInstantUs(lStates[1].CompletedThrough),lContext + ' same pending grid, same C');
      if lPlace = 6 then
        for i := 0 to 3 do Assert.AreEqual<Int64>(0,CronDateTimeToInstantUs(lStates[i].CompletedThrough),'shared absent checkpoint')
      else if lPlace < 3 then
        Assert.IsTrue(lPairUtc-lPairMono <= fNow-fMono,lContext + ' conservative shared offset');
      lRestored := TmaxCron.Create(ctPortable); lRestored.ScheduleStore := fStore;
      lRestored.DefaultMisfireCatchUpLimit := 100000;
      lRestored.RestoreScheduleState(True,
        procedure(const aEvent: IMaxCronEvent; const aState: TMaxCronPersistedEvent)
        begin aEvent.OnScheduleProc := procedure(aSender: IMaxCronEvent)
          begin RecordOccurrence(lReplayIds[aSender.Tag],aSender.Tag=3); end; end);
      fCron.TickAtUtcUs(fNow); lRestored.TickAtUtcUs(fNow);
      for i := 0 to 3 do
      begin
        if (lPlace < 3) or (lPlace = 6) or (i = 3) then
          AssertRecordedDelivery(lLiveIds[i],lReplayIds[i],lInterval,i=3,i=2,lContext+' event='+IntToStr(i))
        else begin
          // After UTC2 (including between events/after persist) preserves
          // the documented saved-UTC translation, not the old monotonic grid.
          lDelta := CronDateTimeToInstantUs(lStates[i].CompletedThrough)+lInterval-fNow;
          if lDelta > lInterval then lDelta := lInterval;
          lFirstMono := fMono+lDelta; lExpected := 0;
          if lDelta <= 0 then
          begin
            lExpected := (-lDelta) div lInterval+1;
            if i = 2 then lExpected := 1;
          end;
          Assert.AreEqual<Int64>(lExpected,lReplayIds[i].Count,lContext+' out-of-scope outcomes');
          for j := 0 to lReplayIds[i].Count-1 do
            Assert.AreEqual<Int64>(lFirstMono+Int64(j)*lInterval,lReplayIds[i][j],lContext+' actual restored identity');
        end;
      end;
      if (lSeed=0) and (lPlace=2) and (lSize=1) and (lStallCase=0) then
      begin
        for i := 0 to 1 do
        begin
          Assert.AreEqual<Int64>(12,lLiveIds[i].Count,'multi-event reviewer owed count');
          Assert.IsTrue(lReplayIds[i].Count >= 12,'multi-event reviewer in-scope replay');
          System.WriteLn('SAVE_WIDE_LITERAL event=',i,' owed=',lLiveIds[i].Count,' restored=',lReplayIds[i].Count);
        end;
      end;
    finally
      lSaving := False;
      if lStoreObject <> nil then lStoreObject.AfterSave := nil;
      lRestored.Free;
      for i := 0 to 3 do lEvents[i] := nil;
      Finish;
      for i := 0 to 3 do
      begin lLiveIds[i].Free; lReplayIds[i].Free; end;
    end;
  end;
  SaveWideLegacyClockProperty(aEngine);
  System.WriteLn('SAVE_WIDE engine=',aEngine,' cases=',lCases,' shared_fallback=',lFallbacks);
end;

procedure TTestRestartCatchUp.CoherentSaveClockProperty(const aEngine: string);
const
  cJumps: array[0..4] of Int64 = (-2000000, -500000, 0, 500000, 2000000);
var
  lLiveIds, lReplayIds: TList<Int64>;
  lRestored: TmaxCron;
  lStates: TArray<TMaxCronPersistedEvent>;
  lSeed, lSeeds, lPlace, lDirection, lDelayCase, lKind, lUtcReads, i, lCases: Integer;
  lJump, lStall, lInterval, lAdvance, lFirstMono, lDelta, lExpected, lUtc, lMono: Int64;
  lContext: string;
  lArmed, lInitial, lUnstable: Boolean;


begin
  lSeeds := 1;
  if {$IFDEF FPC}SysUtils.{$ENDIF}GetEnvironmentVariable('MAXCRON_LONG_TESTS') = '1' then lSeeds := 8;
  lCases := 0;
  for lSeed := 0 to lSeeds - 1 do for lPlace := 0 to 3 do
    for lDirection := 0 to High(cJumps) do for lDelayCase := 0 to 1 do for lKind := 0 to 2 do
  begin
    Inc(lCases);
    lLiveIds := TList<Int64>.Create; lReplayIds := TList<Int64>.Create;
    Start; lRestored := nil;
    try
      lInterval := 100000;
      if (lSeed mod 3) = 1 then lInterval := 1000;
      if (lSeed mod 3) = 2 then lInterval := 5000000;
      lJump := cJumps[lDirection];
      if lSeed > 0 then lJump := lJump + Int64(lSeed) * 137;
      lStall := Int64(lDelayCase) * 750000;
      fCron.DefaultMisfireCatchUpLimit := 100000;
      fEvent.EventPlan := Format('@every %dms', [lInterval div 1000]);
      if lKind = 1 then fEvent.EventPlan := fEvent.EventPlan + ' fixed-delay';
      if lKind = 2 then fEvent.EventPlan := '* * * * * * * 0';
      lInitial := True;
      fEvent.OnScheduleProc := procedure(aSender: IMaxCronEvent)
        begin
          if lInitial then
          begin
            Inc(fMono, 1250000); Inc(fNow, 1250000);
          end else RecordOccurrence(lLiveIds, lKind = 2);
        end;
      fEvent.Run;
      lAdvance := lInterval;
      if lKind = 2 then lAdvance := 1000000;
      Advance(lAdvance); lInitial := False;
      lUtcReads := 0; lArmed := True;
      SetMaxCronUtcClockHook(function: Int64
        begin
          Inc(lUtcReads);
          if lArmed and (((lPlace = 0) and (lUtcReads = 1)) or
            ((lPlace = 2) and (lUtcReads = 2))) then
          begin
            lArmed := False;
            if lStall > 0 then TThread.Sleep(1);
            Inc(fMono, lStall); Inc(fNow, lStall + lJump);
          end;
          Result := fNow;
          if lArmed and (((lPlace = 1) and (lUtcReads = 1)) or
            ((lPlace = 3) and (lUtcReads = 2))) then
          begin
            lArmed := False;
            if lStall > 0 then TThread.Sleep(1);
            Inc(fMono, lStall); Inc(fNow, lStall + lJump);
          end;
        end);
      fCron.SaveScheduleState; fStore.TryLoad(lStates);
      Assert.IsFalse(lArmed, 'clock placement exercised');
      lContext := Format('coherent seed=%d place=%d jump=%d stall=%d kind=%d engine=%s',
        [lSeed,lPlace,lJump,lStall,lKind,aEngine]);
      Assert.IsTrue(GetMaxCronPersistenceClockForTests(lUtc, lMono), lContext + ' accepted pair');
      if lPlace < 3 then
        Assert.IsTrue(lUtc - lMono <= fNow - fMono,
          lContext + ' estimated offset <= actual offset after reads');
      lRestored := TmaxCron.Create(ctPortable); lRestored.ScheduleStore := fStore;
      lRestored.DefaultMisfireCatchUpLimit := 100000;
      lRestored.RestoreScheduleState(True,
        procedure(const aEvent: IMaxCronEvent; const aState: TMaxCronPersistedEvent)
        begin
          aEvent.OnScheduleProc := procedure(aSender: IMaxCronEvent)
            begin RecordOccurrence(lReplayIds, lKind = 2); end;
        end);
      // The after-UTC2 placement is deliberately outside the observed save
      // sample. Assert the existing UTC-to-monotonic restore rule explicitly.
      lFirstMono := 0;
      if (lPlace = 3) and (lKind <> 2) then
      begin
        lDelta := CronDateTimeToInstantUs(lStates[0].CompletedThrough) + lInterval - fNow;
        if lDelta > lInterval then lDelta := lInterval;
        lFirstMono := fMono + lDelta;
      end;
      fCron.TickAtUtcUs(fNow); lRestored.TickAtUtcUs(fNow);
      if (lPlace < 3) or (lKind = 2) then
        AssertRecordedDelivery(lLiveIds, lReplayIds, lInterval, lKind = 2, lKind = 1, lContext)
      else begin
        lExpected := 0;
        if lFirstMono <= fMono then
        begin
          lExpected := (fMono - lFirstMono) div lInterval + 1;
          if lKind = 1 then lExpected := 1;
        end;
        Assert.AreEqual<Int64>(lExpected, lReplayIds.Count, lContext + ' after-save restore outcomes');
        for i := 0 to lReplayIds.Count - 1 do
          Assert.AreEqual<Int64>(lFirstMono + Int64(i) * lInterval, lReplayIds[i],
            lContext + ' actual after-save callback identity');
      end;
      // Literal counts remain visible in retained logs, not only assertions.
      if (lSeed = 0) and (lPlace = 1) and (lKind = 0) and
        (((lDirection = 1) and (lDelayCase = 0)) or ((lDirection = 0) and (lDelayCase = 1))) then
      begin
        System.WriteLn('SAVE_RACE_LITERAL owed=',lLiveIds.Count,' restored=',lReplayIds.Count);
      end;
      if (lSeed = 0) and (lPlace = 2) and (lDirection = 1) and
        (lDelayCase = 1) and (lKind = 0) then
      begin
        Assert.AreEqual<Int64>(20, lLiveIds.Count, 'masked rollback reference');
        Assert.IsTrue(lReplayIds.Count >= 20, 'P6-02a masked rollback replay');
        System.WriteLn('MASKED_ROLLBACK owed=',lLiveIds.Count,' restored=',lReplayIds.Count);
      end;
    finally
      lRestored.Free; Finish; lLiveIds.Free; lReplayIds.Free;
    end;
  end;
  // Eight rejected attempts must never supply a projection. A near-epoch
  // clock makes the conservative absent-checkpoint fallback executable in one
  // pass, including a positive ValidFrom, instead of billions of duplicates.
  for lKind := 0 to 2 do
  begin
    lLiveIds := TList<Int64>.Create; lReplayIds := TList<Int64>.Create;
    Start; lRestored := nil;
    try
      fNow := 10000; fCron.DefaultMisfireCatchUpLimit := 100000;
      fEvent.EventPlan := '@every 100ms';
      if lKind = 1 then fEvent.EventPlan := '@every 100ms fixed-delay';
      if lKind = 2 then fEvent.ValidFrom := CronInstantUsToDateTime(500000);
      lInitial := True;
      fEvent.OnScheduleProc := procedure(aSender: IMaxCronEvent)
        begin
          if lInitial then
          begin Inc(fMono,1250000); Inc(fNow,1250000); end
          else RecordOccurrence(lLiveIds, False);
        end;
      fEvent.Run;
      lAdvance := 100000; if lKind = 2 then lAdvance := 490000;
      Advance(lAdvance); lInitial := False;
      lUtcReads := 0; lUnstable := True;
      SetMaxCronUtcClockHook(function: Int64
        begin
          Result := fNow;
          if lUnstable then
          begin
            Inc(lUtcReads);
            if Odd(lUtcReads) then Dec(fNow,5000) else Inc(fNow,5000);
          end;
        end);
      fCron.SaveScheduleState; fStore.TryLoad(lStates); lUnstable := False;
      Assert.AreEqual(16,lUtcReads,'eight rejected UTC1/UTC2 attempts');
      Assert.IsFalse(GetMaxCronPersistenceClockForTests(lUtc, lMono), 'no incoherent pair exposed');
      Assert.AreEqual<Int64>(0,CronDateTimeToInstantUs(lStates[0].CompletedThrough),'incoherent clock checkpoint absent');
      lRestored := TmaxCron.Create(ctPortable); lRestored.ScheduleStore := fStore;
      lRestored.DefaultMisfireCatchUpLimit := 100000;
      lRestored.RestoreScheduleState(True,
        procedure(const aEvent: IMaxCronEvent; const aState: TMaxCronPersistedEvent)
        begin aEvent.OnScheduleProc := procedure(aSender: IMaxCronEvent)
          begin RecordOccurrence(lReplayIds,False); end; end);
      fCron.TickAtUtcUs(fNow); lRestored.TickAtUtcUs(fNow);
      AssertRecordedDelivery(lLiveIds,lReplayIds,100000,False,lKind=1,'unstable clock fallback');
      // The observer reads a ticket recorded by actual callback dispatch.
      Assert.IsFalse(CurrentMaxCronOccurrenceForTests(lUtc,lMono),'observer context restored after dispatch');
    finally
      lUnstable := False; lRestored.Free; Finish; lLiveIds.Free; lReplayIds.Free;
    end;
  end;
  System.WriteLn('COHERENT_CLOCK engine=',aEngine,' cases=',lCases,' unstable=3');
end;

procedure TTestRestartCatchUp.ClockJumpRestartProperty(const aEngine: string);
const
  cIntervals: array[0..2] of Int64 = (1000, 100000, 5000000);
var
  lOldEngine, lContext: string;
  lEvents: array[0..3] of IMaxCronEvent;
  lLive, lReplay: array[0..3] of Integer;
  lLiveIds, lReplayIds: array[0..3] of TList<Int64>;
  lDue, lRestoredDue: array[0..3] of Int64;
  lStates: TArray<TMaxCronPersistedEvent>;
  lCapture: IMaxCronScheduleStore;
  lRestored: TmaxCron;
  lSeed, lSeeds, lStep, lSteps, i, j, lExpected, lKind: Integer;
  lRandom: UInt64;
  lInterval, lAdvance, lJump, lDelay, lDelayJump, lCursor: Int64;
  lOpenDue, lBound, lPrefix, lSample: Int64;
  lDelays, lSampleDelay, lCaptureOpen: Boolean;

  function Draw(const aBound: Cardinal): Cardinal;
  begin
    lRandom := (lRandom * 1664525 + 1013904223) and $FFFFFFFF;
    Result := Cardinal(lRandom mod aBound);
  end;

  procedure RestoreCapture;
  begin
    lRestored := TmaxCron.Create(ctPortable);
    lRestored.ScheduleStore := lCapture;
    lRestored.DefaultMisfireCatchUpLimit := 100000;
    lRestored.RestoreScheduleState(True,
      procedure(const aEvent: IMaxCronEvent; const aState: TMaxCronPersistedEvent)
      begin
        aEvent.OnScheduleProc := procedure(aSender: IMaxCronEvent)
          begin
            Inc(lReplay[aSender.Tag]);
            RecordOccurrence(lReplayIds[aSender.Tag], aSender.Tag = 3);
          end;
      end);
  end;

begin
  lOldEngine := {$IFDEF FPC}SysUtils.{$ENDIF}GetEnvironmentVariable('MAXCRON_ENGINE');
  SetEnvironmentVariableW('MAXCRON_ENGINE', PChar(aEngine));
  lSeeds := 12; lSteps := 8;
  if {$IFDEF FPC}SysUtils.{$ENDIF}GetEnvironmentVariable('MAXCRON_LONG_TESTS') = '1' then
  begin
    lSeeds := 256; lSteps := 32;
  end;
  try
    for lSeed := 0 to lSeeds - 1 do
    begin
      lRandom := UInt64($50602026) + UInt64(lSeed);
      for i := 0 to 3 do
      begin
        lLiveIds[i] := TList<Int64>.Create; lReplayIds[i] := TList<Int64>.Create;
      end;
      Start;
      lRestored := nil;
      try
        fCron.DefaultMisfireCatchUpLimit := 100000;
        lInterval := cIntervals[lSeed mod Length(cIntervals)];
        lEvents[0] := fEvent;
        lEvents[0].EventPlan := Format('@every %dms fixed-delay', [lInterval div 1000]);
        for i := 1 to 3 do
        begin
          lEvents[i] := fCron.Add('clock property ' + IntToStr(i));
          lEvents[i].InvokeMode := imMainThread;
          lEvents[i].TimeZoneId := 'UTC';
          lEvents[i].EventPlan := Format('@every %dms', [lInterval div 1000]);
        end;
        lEvents[2].EventPlan := Format('@every %dms fixed-delay', [lInterval div 1000]);
        lEvents[3].EventPlan := '* * * * * * * 0';
        for i := 0 to 3 do
        begin
          lEvents[i].Tag := i;
          lEvents[i].OnScheduleProc := procedure(aSender: IMaxCronEvent)
            begin
              Inc(lLive[aSender.Tag]);
              RecordOccurrence(lLiveIds[aSender.Tag], aSender.Tag = 3);
              if lDelays and (aSender.Tag = 0) then
              begin
                Inc(fMono, lDelay); Inc(fNow, lDelay + lDelayJump);
              end;
            end;
          lEvents[i].Run;
        end;
        lSampleDelay := False;
        SetMaxCronUtcClockHook(function: Int64
          begin
            Result := fNow;
            if lSampleDelay then
            begin
              lSampleDelay := False;
              TThread.Sleep(1);
              Inc(fMono, 750000); Inc(fNow, 750000);
            end;
          end);
        for lStep := 0 to lSteps - 1 do
        begin
          lContext := Format('seed=%d step=%d engine=%s I=%d', [lSeed, lStep, aEngine, lInterval]);
          lAdvance := (1 + Int64(Draw(9))) * lInterval;
          lJump := (Int64(Draw(11)) - 5) * lInterval;
          lDelay := (1 + Int64(Draw(16))) * lInterval;
          lDelayJump := (Int64(Draw(13)) - 6) * lInterval;
          // The reviewer's exact 500 ms rollback is part of the fixed seeds.
          if (lSeed = 1) and (lStep = 0) then
          begin
            lAdvance := 100000; lJump := 0;
            lDelay := 1250000; lDelayJump := -500000;
          end;
          Inc(fMono, lAdvance); Inc(fNow, lAdvance + lJump);
          lDelays := True;
          fCron.TickAtUtcUs(fNow);
          lDelays := False;
          // Trigger a real sleep and a simulated delay between clock samples.
          lSampleDelay := (lStep = 1) and ((lSeed mod 4) = 0);
          fCron.SaveScheduleState; fStore.TryLoad(lStates);
          for i := 0 to 3 do
          begin
            lDue[i] := CronDateTimeToInstantUs(lEvents[i].NextSchedule);
            lBound := lDue[i] - lInterval;
            if i = 3 then lBound := lDue[i] - 1000;
            lPrefix := CronDateTimeToInstantUs(lStates[i].CompletedThrough);
            Assert.IsTrue(lPrefix <= lBound, lContext + ' persisted predecessor ' + IntToStr(i));
            lLive[i] := 0; lReplay[i] := 0;
            lLiveIds[i].Clear; lReplayIds[i].Clear;
          end;
          lCapture := TRestartStore.Create; lCapture.Save(lStates);
          RestoreCapture;
          // Some points include a second crash before any resumed tick.
          if (lStep mod 3) = 0 then
          begin
            lRestored.SaveScheduleState;
            FreeAndNil(lRestored);
            RestoreCapture;
          end;
          for i := 0 to 3 do
          begin
            lRestoredDue[i] := CronDateTimeToInstantUs(lRestored.Snapshot[i].NextSchedule);
            Assert.IsTrue(lRestoredDue[i] <= lDue[i], lContext + ' first unfinished ' + IntToStr(i));
          end;
          fCron.TickAtUtcUs(fNow);
          lRestored.TickAtUtcUs(fNow);
          for i := 0 to 3 do
          begin
            // Independent occurrence enumeration at the frozen comparison
            // clock. Fixed-delay has one owed instance; rate/cron have grids.
            lExpected := 0; lCursor := lDue[i];
            lSample := lInterval;
            if i = 3 then lSample := 1000000;
            while lCursor <= fNow do
            begin
              Inc(lExpected);
              if (i = 0) or (i = 2) then Break;
              Inc(lCursor, lSample);
            end;
            Assert.AreEqual(lExpected, lLive[i], lContext + ' uninterrupted reference ' + IntToStr(i));
            Assert.IsTrue(lReplay[i] >= lExpected, lContext + ' at least once ' + IntToStr(i));
            Assert.AreEqual<Int64>(lLive[i], lLiveIds[i].Count, 'every live callback recorded');
            Assert.AreEqual<Int64>(lReplay[i], lReplayIds[i].Count, 'every replay callback recorded');
            AssertRecordedDelivery(lLiveIds[i], lReplayIds[i], lInterval, i = 3,
              (i = 0) or (i = 2), lContext + ' event=' + IntToStr(i));
          end;
          FreeAndNil(lRestored);
        end;
      finally
        lDelays := False;
        lRestored.Free; lCapture := nil;
        for j := 0 to 3 do lEvents[j] := nil;
        Finish;
        for j := 0 to 3 do
        begin
          lLiveIds[j].Free; lReplayIds[j].Free;
        end;
      end;
    end;
    // Save inside the callback, while its real dispatch ticket is open.
    // The final two cases force a nonpositive safe C with a positive due,
    // exercising the legacy saved-deadline fallback without changing restore.
    for lKind := 0 to 4 do
    begin
      for i := 0 to 3 do
      begin
        lLiveIds[i] := TList<Int64>.Create; lReplayIds[i] := TList<Int64>.Create;
      end;
      Start;
      lRestored := nil;
      try
        if lKind >= 3 then fNow := 10000;
        fEvent.EventPlan := '@every 100ms';
        if (lKind = 1) or (lKind = 4) then fEvent.EventPlan := '@every 100ms fixed-delay';
        if lKind = 2 then fEvent.EventPlan := '* * * * * * * 0';
        lOpenDue := fNow + 100000;
        if lKind = 2 then lOpenDue := fNow + 1000000;
        lCaptureOpen := True;
        fEvent.OnScheduleProc := procedure(aSender: IMaxCronEvent)
          begin
            if not lCaptureOpen then Exit;
            lCaptureOpen := False;
            if lKind >= 3 then Dec(fNow, 60000)
            else if lKind <> 2 then
            begin
              Inc(fMono, 1250000); Inc(fNow, 750000);
            end;
            fCron.SaveScheduleState; fStore.TryLoad(lStates);
          end;
        fEvent.Run;
        if lKind = 2 then Advance(1000000) else Advance(100000);
        lBound := lOpenDue - 1000;
        if lKind <> 2 then
        begin
          if lKind >= 3 then Dec(lOpenDue, 60000) else Dec(lOpenDue, 500000);
          lBound := lOpenDue - 100000;
        end;
        lPrefix := CronDateTimeToInstantUs(lStates[0].CompletedThrough);
        if lBound > 0 then Assert.IsTrue(lPrefix <= lBound, 'open ticket predecessor')
        else Assert.AreEqual<Int64>(0, lPrefix, 'no safe checkpoint is absent');
        lCapture := TRestartStore.Create; lCapture.Save(lStates);
        for i := 0 to 3 do lReplay[i] := 0;
        RestoreCapture;
        Assert.IsTrue(CronDateTimeToInstantUs(lRestored.Snapshot[0].NextSchedule) <= lOpenDue,
          'open occurrence must replay, including absent-C fallback');
        lRestored.TickAtUtcUs(fNow);
        Assert.IsTrue(lReplay[0] >= 1, 'open callback replayed at least once');
      finally
        lRestored.Free; lCapture := nil; Finish;
        for j := 0 to 3 do
        begin
          lLiveIds[j].Free; lReplayIds[j].Free;
        end;
      end;
    end;
    SaveWideClockProperty(aEngine);
    CoherentSaveClockProperty(aEngine);
    System.WriteLn('CLOCK_JUMP engine=', aEngine, ' seeds=', lSeeds, ' steps=', lSteps, ' open_windows=5');
  finally
    SetEnvironmentVariableW('MAXCRON_ENGINE', PChar(lOldEngine));
  end;
end;

end.

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
  public
    [Test] procedure LedgerPrefixAndStaleTickets;
    [Test] procedure RetryOutcomes;
    [Test] procedure IntervalCheckpoints;
    [Test] procedure IntervalBatchDispatchFailure;
    [Test] procedure RunCheckpointUsesSearchBase;
  end;

implementation

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

end.

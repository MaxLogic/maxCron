unit TestPersistenceRecovery;

interface

uses
  System.DateUtils, System.SysUtils,
  DUnitX.TestFramework,
  maxCron;

type
  TInMemoryScheduleStore = class(TInterfacedObject, IMaxCronScheduleStore)
  private
    fEvents: TArray<TMaxCronPersistedEvent>;
  public
    procedure Save(const aEvents: TArray<TMaxCronPersistedEvent>);
    function TryLoad(out aEvents: TArray<TMaxCronPersistedEvent>): Boolean;
  end;

  [TestFixture]
  TTestPersistenceRecovery = class
  private
    function FindEventByName(const aEvents: TArray<IMaxCronEvent>; const aName: string): IMaxCronEvent;
  public
    [Test]
    procedure Restart_RestoresEventsAndSchedules;
  end;

implementation

procedure TInMemoryScheduleStore.Save(const aEvents: TArray<TMaxCronPersistedEvent>);
var
  lIndex: Integer;
begin
  SetLength(fEvents, Length(aEvents));
  for lIndex := 0 to Length(aEvents) - 1 do
    fEvents[lIndex] := aEvents[lIndex];
end;

function TInMemoryScheduleStore.TryLoad(out aEvents: TArray<TMaxCronPersistedEvent>): Boolean;
var
  lIndex: Integer;
begin
  SetLength(aEvents, Length(fEvents));
  for lIndex := 0 to Length(fEvents) - 1 do
    aEvents[lIndex] := fEvents[lIndex];
  Result := Length(aEvents) > 0;
end;

function TTestPersistenceRecovery.FindEventByName(const aEvents: TArray<IMaxCronEvent>; const aName: string): IMaxCronEvent;
var
  lEvent: IMaxCronEvent;
  lIndex: Integer;
begin
  Result := nil;
  for lIndex := 0 to Length(aEvents) - 1 do
  begin
    lEvent := aEvents[lIndex];
    if (lEvent <> nil) and SameText(lEvent.Name, aName) then
      Exit(lEvent);
  end;
end;

procedure TTestPersistenceRecovery.Restart_RestoresEventsAndSchedules;
var
  lStore: IMaxCronScheduleStore;
  lCron: TmaxCron;
  lRestoredCron: TmaxCron;
  lPrimary: IMaxCronEvent;
  lSecondary: IMaxCronEvent;
  lBefore: TArray<IMaxCronEvent>;
  lAfter: TArray<IMaxCronEvent>;
  lBeforePrimary: IMaxCronEvent;
  lBeforeSecondary: IMaxCronEvent;
  lAfterPrimary: IMaxCronEvent;
  lAfterSecondary: IMaxCronEvent;
  lSavedCount: Integer;
  lRestoredCount: Integer;
begin
  lStore := TInMemoryScheduleStore.Create;

  lCron := TmaxCron.Create(ctPortable);
  try
    lCron.ScheduleStore := lStore;

    lPrimary := lCron.Add('PersistentPrimary');
    lPrimary.EventPlan := '* * * * * * * 0';
    lPrimary.InvokeMode := imMainThread;
    lPrimary.OverlapMode := omSerialize;
    lPrimary.TimeZoneId := 'UTC+01:00';
    lPrimary.RetryMaxAttempts := 2;
    lPrimary.RetryInitialDelayMs := 10;
    lPrimary.RetryBackoffMultiplier := 2.0;
    lPrimary.RetryMaxDelayMs := 40;
    lPrimary.Tag := 101;
    lPrimary.OnScheduleProc :=
      procedure(aSender: IMaxCronEvent)
      begin
      end;
    lPrimary.Run;

    lCron.TickAt(lPrimary.NextSchedule);
    Assert.AreEqual(UInt64(1), lPrimary.NumOfExecutionsPerformed,
      'Expected one execution before persisting');

    lSecondary := lCron.Add('PersistentSecondary');
    lSecondary.EventPlan := '0 0 1 1 * 2099 0 0';
    lSecondary.InvokeMode := imThread;
    lSecondary.OverlapMode := omSkipIfRunning;
    lSecondary.Tag := 202;
    lSecondary.Run;
    lSecondary.Stop;

    lBefore := lCron.Snapshot;
    lBeforePrimary := FindEventByName(lBefore, 'PersistentPrimary');
    lBeforeSecondary := FindEventByName(lBefore, 'PersistentSecondary');
    Assert.IsNotNull(lBeforePrimary, 'Expected primary event in pre-save snapshot');
    Assert.IsNotNull(lBeforeSecondary, 'Expected secondary event in pre-save snapshot');

    lSavedCount := lCron.SaveScheduleState;
    Assert.AreEqual(2, lSavedCount, 'Expected two events to be saved');
  finally
    lCron.Free;
  end;

  lRestoredCron := TmaxCron.Create(ctPortable);
  try
    lRestoredCron.ScheduleStore := lStore;
    lRestoredCount := lRestoredCron.RestoreScheduleState;
    Assert.AreEqual(2, lRestoredCount, 'Expected two events to be restored');

    lAfter := lRestoredCron.Snapshot;
    Assert.AreEqual(2, Length(lAfter), 'Expected restored scheduler to contain two events');

    lAfterPrimary := FindEventByName(lAfter, 'PersistentPrimary');
    lAfterSecondary := FindEventByName(lAfter, 'PersistentSecondary');
    Assert.IsNotNull(lAfterPrimary, 'Expected primary event after restore');
    Assert.IsNotNull(lAfterSecondary, 'Expected secondary event after restore');

    Assert.AreEqual(lBeforePrimary.EventPlan, lAfterPrimary.EventPlan, 'Primary plan should be restored');
    Assert.AreEqual(Integer(lBeforePrimary.InvokeMode), Integer(lAfterPrimary.InvokeMode),
      'Primary invoke mode should be restored');
    Assert.AreEqual(Integer(lBeforePrimary.OverlapMode), Integer(lAfterPrimary.OverlapMode),
      'Primary overlap mode should be restored');
    Assert.AreEqual(lBeforePrimary.TimeZoneId, lAfterPrimary.TimeZoneId, 'Primary timezone should be restored');
    Assert.AreEqual(lBeforePrimary.Tag, lAfterPrimary.Tag, 'Primary tag should be restored');
    Assert.AreEqual(lBeforePrimary.NumOfExecutionsPerformed, lAfterPrimary.NumOfExecutionsPerformed,
      'Primary execution counter should be restored');
    Assert.IsTrue(Abs(lAfterPrimary.NextSchedule - lBeforePrimary.NextSchedule) < (1 / (24 * 60 * 60)),
      'Primary next schedule should restore without drift');

    Assert.AreEqual(lBeforeSecondary.EventPlan, lAfterSecondary.EventPlan, 'Secondary plan should be restored');
    Assert.AreEqual(lBeforeSecondary.Tag, lAfterSecondary.Tag, 'Secondary tag should be restored');
    Assert.IsFalse(lAfterSecondary.Enabled, 'Secondary enabled-state should remain disabled after restore');
  finally
    lRestoredCron.Free;
  end;
end;

end.

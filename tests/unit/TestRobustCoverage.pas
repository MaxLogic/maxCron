unit TestRobustCoverage;

interface

uses
  System.Classes, System.DateUtils, System.SyncObjs, System.SysUtils,
  DUnitX.TestFramework,
  maxCron;

type
  [TestFixture]
  TTestRobustCoverage = class
  private
    procedure AssertRaises(const aProc: TProc; const aMessage: string = 'Expected exception');
    procedure NoopSchedule(aSender: TmaxCronEvent);
    function BuildOneShotPlan(const aDateTime: TDateTime): string;
    function FindNextForPlan(const aPlan: string; const aBase: TDateTime;
      const aDayMatchMode: TmaxCronDayMatchMode): TDateTime;
    function TryFindAmbiguousLocalTime(out aDateTime: TDateTime): Boolean;
  public
    [Test]
    procedure DstFallPolicy_RunOnceVariants;

    [Test]
    procedure TimeZoneId_ParsingAndNormalization;

    [Test]
    procedure TimeZoneId_InvalidValues_Raise;

    [Test]
    procedure ExcludedDatesCsv_DedupSortAndEmptyTokens;

    [Test]
    procedure ExcludedDatesCsv_InvalidDate_Raise;

    [Test]
    procedure Blackout_OvernightWindow_SkipsNightHours;

    [Test]
    procedure Blackout_EqualEndpoints_DisablesBlackout;

    [Test]
    procedure Blackout_InvalidValues_Raise;

    [Test]
    procedure HashToken_InvalidForms_Raise;

    [Test]
    procedure HashSeed_ChangesAfterNameUpdate;

    [Test]
    procedure FinalDispatch_FireOnceNow_WhenEventDisables;

    [Test]
    procedure FinalDispatch_DefaultCatchUp_WhenEventDisables;

    [Test]
    procedure DefaultDayMatchMode_PropagatesToDefaultEvents;

    [Test]
    procedure DefaultDialect_AppliesToNewEvents;

    [Test]
    procedure DefaultInvokeMode_AppliesToDefaultEvents;

    [Test]
    procedure DefaultMisfireCatchUpLimit_ClampsToOne;

    [Test]
    procedure MisfireCatchUp_MaxAttempts_DoesNotDisableSchedulableEvent;

    [Test]
    procedure AddOverloads_InvalidPlan_DoNotKeepPartiallyAddedEvents;
  end;

implementation

procedure TTestRobustCoverage.AssertRaises(const aProc: TProc; const aMessage: string);
var
  lRaised: Boolean;
begin
  lRaised := False;
  try
    aProc();
  except
    on Exception do
      lRaised := True;
  end;

  if not lRaised then
    Assert.Fail(aMessage);
end;

procedure TTestRobustCoverage.NoopSchedule(aSender: TmaxCronEvent);
begin
end;

function TTestRobustCoverage.BuildOneShotPlan(const aDateTime: TDateTime): string;
begin
  Result := Format('%d %d %d %d * %d 0 0',
    [MinuteOf(aDateTime), HourOf(aDateTime), DayOf(aDateTime), MonthOf(aDateTime), YearOf(aDateTime)]);
end;

function TTestRobustCoverage.FindNextForPlan(const aPlan: string; const aBase: TDateTime;
  const aDayMatchMode: TmaxCronDayMatchMode): TDateTime;
var
  lSchedulePlan: TCronSchedulePlan;
begin
  lSchedulePlan := TCronSchedulePlan.Create;
  try
    lSchedulePlan.Parse(aPlan);
    lSchedulePlan.DayMatchMode := aDayMatchMode;
    Assert.IsTrue(lSchedulePlan.FindNextScheduleDate(aBase, Result));
  finally
    lSchedulePlan.Free;
  end;
end;

function TTestRobustCoverage.TryFindAmbiguousLocalTime(out aDateTime: TDateTime): Boolean;
var
  lStart: TDateTime;
  lCursor: TDateTime;
  lLimit: TDateTime;
begin
  lStart := EncodeDate(YearOf(Now), 1, 1);
  lLimit := IncYear(lStart, 1);
  lCursor := lStart;
  while lCursor < lLimit do
  begin
    if TTimeZone.Local.IsAmbiguousTime(lCursor) then
    begin
      aDateTime := lCursor;
      Exit(True);
    end;
    lCursor := IncMinute(lCursor, 1);
  end;
  Result := False;
end;

procedure TTestRobustCoverage.DstFallPolicy_RunOnceVariants;
var
  lAmbiguous: TDateTime;
  lCron: TmaxCron;
  lPlan: string;
  lEventRunOnce: TmaxCronEvent;
  lEventPreferFirst: TmaxCronEvent;
  lEventPreferSecond: TmaxCronEvent;
  lOffsetFirstSeconds: Integer;
  lOffsetSecondSeconds: Integer;
  lDeltaSeconds: Integer;
begin
  if not TryFindAmbiguousLocalTime(lAmbiguous) then
    Exit;

  lOffsetFirstSeconds := Round(TTimeZone.Local.GetUtcOffset(lAmbiguous, False).TotalSeconds);
  lOffsetSecondSeconds := Round(TTimeZone.Local.GetUtcOffset(lAmbiguous, True).TotalSeconds);
  lDeltaSeconds := Abs(lOffsetFirstSeconds - lOffsetSecondSeconds);
  if lDeltaSeconds <= 0 then
    lDeltaSeconds := 3600;

  lPlan := BuildOneShotPlan(lAmbiguous);
  lCron := TmaxCron.Create(ctPortable);
  try
    lEventRunOnce := lCron.Add('FallRunOnce');
    lEventRunOnce.EventPlan := lPlan;
    lEventRunOnce.TimeZoneId := 'LOCAL';
    lEventRunOnce.DstFallPolicy := TmaxCronDstFallPolicy.dfpRunOnce;
    lEventRunOnce.ValidFrom := IncSecond(lAmbiguous, -1);
    lEventRunOnce.Run;

    lEventPreferFirst := lCron.Add('FallPreferFirst');
    lEventPreferFirst.EventPlan := lPlan;
    lEventPreferFirst.TimeZoneId := 'LOCAL';
    lEventPreferFirst.DstFallPolicy := TmaxCronDstFallPolicy.dfpRunOncePreferFirstInstance;
    lEventPreferFirst.ValidFrom := IncSecond(lAmbiguous, -1);
    lEventPreferFirst.Run;

    lEventPreferSecond := lCron.Add('FallPreferSecond');
    lEventPreferSecond.EventPlan := lPlan;
    lEventPreferSecond.TimeZoneId := 'LOCAL';
    lEventPreferSecond.DstFallPolicy := TmaxCronDstFallPolicy.dfpRunOncePreferSecondInstance;
    lEventPreferSecond.ValidFrom := IncSecond(lAmbiguous, -1);
    lEventPreferSecond.Run;

    Assert.AreEqual(lAmbiguous, lEventRunOnce.NextSchedule, 0.0);
    Assert.AreEqual(lAmbiguous, lEventPreferFirst.NextSchedule, 0.0);
    Assert.AreEqual(IncSecond(lAmbiguous, lDeltaSeconds), lEventPreferSecond.NextSchedule, 0.0);
  finally
    lCron.Free;
  end;
end;

procedure TTestRobustCoverage.TimeZoneId_ParsingAndNormalization;
var
  lCron: TmaxCron;
  lEvent: TmaxCronEvent;
begin
  lCron := TmaxCron.Create(ctPortable);
  try
    lEvent := lCron.Add('TimeZoneNormalization');

    lEvent.TimeZoneId := '';
    Assert.AreEqual('LOCAL', lEvent.TimeZoneId);

    lEvent.TimeZoneId := 'local';
    Assert.AreEqual('LOCAL', lEvent.TimeZoneId);

    lEvent.TimeZoneId := 'utc';
    Assert.AreEqual('UTC', lEvent.TimeZoneId);

    lEvent.TimeZoneId := 'z';
    Assert.AreEqual('UTC', lEvent.TimeZoneId);

    lEvent.TimeZoneId := 'UTC+2';
    Assert.AreEqual('UTC+02:00', lEvent.TimeZoneId);

    lEvent.TimeZoneId := 'UTC-5:30';
    Assert.AreEqual('UTC-05:30', lEvent.TimeZoneId);

    lEvent.TimeZoneId := 'UTC+2:3';
    Assert.AreEqual('UTC+02:03', lEvent.TimeZoneId);

    lEvent.TimeZoneId := 'UTC++2';
    Assert.AreEqual('UTC+02:00', lEvent.TimeZoneId);

    lEvent.TimeZoneId := 'UTC+14:00';
    Assert.AreEqual('UTC+14:00', lEvent.TimeZoneId);
  finally
    lCron.Free;
  end;
end;

procedure TTestRobustCoverage.TimeZoneId_InvalidValues_Raise;
const
  cInvalidValues: array [0 .. 7] of string = (
    'GMT',
    'UTC+',
    'UTC- ',
    'UTC+14:01',
    'UTC+15',
    'UTC+02:60',
    'UTC+AA',
    'UTC+02:00:10'
    );
var
  lCron: TmaxCron;
  lEvent: TmaxCronEvent;
  i: Integer;
  lValue: string;
begin
  lCron := TmaxCron.Create(ctPortable);
  try
    lEvent := lCron.Add('TimeZoneInvalids');

    for i := Low(cInvalidValues) to High(cInvalidValues) do
    begin
      lValue := cInvalidValues[i];
      AssertRaises(
        procedure
        begin
          lEvent.TimeZoneId := lValue;
        end,
        'Expected invalid timezone: ' + lValue);
    end;
  finally
    lCron.Free;
  end;
end;

procedure TTestRobustCoverage.ExcludedDatesCsv_DedupSortAndEmptyTokens;
var
  lCron: TmaxCron;
  lEvent: TmaxCronEvent;
begin
  lCron := TmaxCron.Create(ctPortable);
  try
    lEvent := lCron.Add('ExcludedCsvRobust');
    lEvent.EventPlan := '0 0 * * * * 0 0';
    lEvent.ExcludedDatesCsv := '2031-01-03,, 2031-01-02,2031-01-03, 2031-01-04,,';
    lEvent.ValidFrom := EncodeDate(2031, 1, 1);
    lEvent.Run;

    Assert.AreEqual(EncodeDateTime(2031, 1, 5, 0, 0, 0, 0), lEvent.NextSchedule, 0.0);
  finally
    lCron.Free;
  end;
end;

procedure TTestRobustCoverage.ExcludedDatesCsv_InvalidDate_Raise;
var
  lCron: TmaxCron;
  lEvent: TmaxCronEvent;
begin
  lCron := TmaxCron.Create(ctPortable);
  try
    lEvent := lCron.Add('ExcludedCsvInvalid');

    AssertRaises(
      procedure
      begin
        lEvent.ExcludedDatesCsv := '2031-1-02';
      end,
      'Expected YYYY-MM-DD validation failure');

    AssertRaises(
      procedure
      begin
        lEvent.ExcludedDatesCsv := '2031-02-30';
      end,
      'Expected invalid date failure');

    AssertRaises(
      procedure
      begin
        lEvent.ExcludedDatesCsv := 'not-a-date';
      end,
      'Expected parse failure for non-date token');
  finally
    lCron.Free;
  end;
end;

procedure TTestRobustCoverage.Blackout_OvernightWindow_SkipsNightHours;
var
  lCron: TmaxCron;
  lEvent: TmaxCronEvent;
begin
  lCron := TmaxCron.Create(ctPortable);
  try
    lEvent := lCron.Add('BlackoutOvernight');
    lEvent.EventPlan := '15 * * * * * 0 0';
    lEvent.BlackoutStartTime := EncodeTime(22, 0, 0, 0);
    lEvent.BlackoutEndTime := EncodeTime(6, 0, 0, 0);
    lEvent.ValidFrom := EncodeDateTime(2032, 2, 10, 21, 40, 0, 0);
    lEvent.Run;

    Assert.AreEqual(EncodeDateTime(2032, 2, 11, 6, 15, 0, 0), lEvent.NextSchedule, 0.0);
  finally
    lCron.Free;
  end;
end;

procedure TTestRobustCoverage.Blackout_EqualEndpoints_DisablesBlackout;
var
  lCron: TmaxCron;
  lEvent: TmaxCronEvent;
begin
  lCron := TmaxCron.Create(ctPortable);
  try
    lEvent := lCron.Add('BlackoutEqual');
    lEvent.EventPlan := '0 * * * * * 0 0';
    lEvent.BlackoutStartTime := EncodeTime(9, 0, 0, 0);
    lEvent.BlackoutEndTime := EncodeTime(9, 0, 0, 0);
    lEvent.ValidFrom := EncodeDateTime(2032, 2, 10, 8, 30, 0, 0);
    lEvent.Run;

    Assert.AreEqual(EncodeDateTime(2032, 2, 10, 9, 0, 0, 0), lEvent.NextSchedule, 0.0);
  finally
    lCron.Free;
  end;
end;

procedure TTestRobustCoverage.Blackout_InvalidValues_Raise;
var
  lCron: TmaxCron;
  lEvent: TmaxCronEvent;
begin
  lCron := TmaxCron.Create(ctPortable);
  try
    lEvent := lCron.Add('BlackoutInvalidValues');

    AssertRaises(
      procedure
      begin
        lEvent.BlackoutStartTime := -0.001;
      end,
      'Expected invalid negative start time');

    AssertRaises(
      procedure
      begin
        lEvent.BlackoutStartTime := 1.0;
      end,
      'Expected invalid start time >= 1 day');

    AssertRaises(
      procedure
      begin
        lEvent.BlackoutEndTime := -0.001;
      end,
      'Expected invalid negative end time');

    AssertRaises(
      procedure
      begin
        lEvent.BlackoutEndTime := 1.0;
      end,
      'Expected invalid end time >= 1 day');
  finally
    lCron.Free;
  end;
end;

procedure TTestRobustCoverage.HashToken_InvalidForms_Raise;
var
  lSchedulePlan: TCronSchedulePlan;
begin
  lSchedulePlan := TCronSchedulePlan.Create;
  try
    lSchedulePlan.Dialect := cdStandard;

    AssertRaises(
      procedure
      begin
        lSchedulePlan.Parse('H() * * * *');
      end,
      'Expected parse error for H()');

    AssertRaises(
      procedure
      begin
        lSchedulePlan.Parse('H(10) * * * *');
      end,
      'Expected parse error for missing range dash');

    AssertRaises(
      procedure
      begin
        lSchedulePlan.Parse('H(20-10) * * * *');
      end,
      'Expected parse error for descending range');

    AssertRaises(
      procedure
      begin
        lSchedulePlan.Parse('H(0-60) * * * *');
      end,
      'Expected parse error for out-of-range minute value');

    AssertRaises(
      procedure
      begin
        lSchedulePlan.Parse('H/0 * * * *');
      end,
      'Expected parse error for zero hash step');

    AssertRaises(
      procedure
      begin
        lSchedulePlan.Parse('H(10-20)/0 * * * *');
      end,
      'Expected parse error for zero step in hash range');

    AssertRaises(
      procedure
      begin
        lSchedulePlan.Parse('H(10-20)/-2 * * * *');
      end,
      'Expected parse error for negative step in hash range');

    AssertRaises(
      procedure
      begin
        lSchedulePlan.Parse('H(10-20)x * * * *');
      end,
      'Expected parse error for invalid hash suffix');
  finally
    lSchedulePlan.Free;
  end;
end;

procedure TTestRobustCoverage.HashSeed_ChangesAfterNameUpdate;
var
  lCron: TmaxCron;
  lEvent: TmaxCronEvent;
  lFirstSchedule: TDateTime;
  lSecondSchedule: TDateTime;
  lThirdSchedule: TDateTime;
begin
  lCron := TmaxCron.Create(ctPortable);
  try
    lEvent := lCron.Add('SeedA');
    lEvent.EventPlan := 'H H * * * * H 1';
    lEvent.ValidFrom := EncodeDateTime(2032, 1, 1, 0, 0, 0, 0);
    lEvent.Run;

    lFirstSchedule := lEvent.NextSchedule;

    lEvent.Name := 'SeedB';
    lSecondSchedule := lEvent.NextSchedule;

    lEvent.Name := 'SeedA';
    lThirdSchedule := lEvent.NextSchedule;

    Assert.AreNotEqual(lFirstSchedule, lSecondSchedule);
    Assert.AreEqual(lFirstSchedule, lThirdSchedule, 0.0);
  finally
    lCron.Free;
  end;
end;

procedure TTestRobustCoverage.FinalDispatch_FireOnceNow_WhenEventDisables;
var
  lCron: TmaxCron;
  lEvent: TmaxCronEvent;
  lCount: Integer;
  lFireAt: TDateTime;
  lTickAt: TDateTime;
begin
  lCount := 0;
  lFireAt := IncMinute(Now, 2);
  lFireAt := EncodeDateTime(YearOf(lFireAt), MonthOf(lFireAt), DayOf(lFireAt), HourOf(lFireAt), MinuteOf(lFireAt), 0, 0);

  lCron := TmaxCron.Create(ctPortable);
  try
    lEvent := lCron.Add('FinalDispatchOnceNow');
    lEvent.EventPlan := BuildOneShotPlan(lFireAt);
    lEvent.MisfirePolicy := TmaxCronMisfirePolicy.mpFireOnceNow;
    lEvent.InvokeMode := imMainThread;
    lEvent.OnScheduleProc :=
      procedure(aSender: TmaxCronEvent)
      begin
        TInterlocked.Increment(lCount);
      end;
    lEvent.ValidFrom := IncSecond(lFireAt, -1);
    lEvent.Run;

    lTickAt := IncSecond(lEvent.NextSchedule, 10);
    lCron.TickAt(lTickAt);

    Assert.AreEqual(1, TInterlocked.CompareExchange(lCount, 0, 0));
    Assert.IsFalse(lEvent.Enabled);
  finally
    lCron.Free;
  end;
end;

procedure TTestRobustCoverage.FinalDispatch_DefaultCatchUp_WhenEventDisables;
var
  lCron: TmaxCron;
  lEvent: TmaxCronEvent;
  lCount: Integer;
  lFireAt: TDateTime;
  lTickAt: TDateTime;
begin
  lCount := 0;
  lFireAt := IncMinute(Now, 2);
  lFireAt := EncodeDateTime(YearOf(lFireAt), MonthOf(lFireAt), DayOf(lFireAt), HourOf(lFireAt), MinuteOf(lFireAt), 0, 0);

  lCron := TmaxCron.Create(ctPortable);
  try
    lCron.DefaultMisfirePolicy := TmaxCronMisfirePolicy.mpCatchUpAll;
    lCron.DefaultMisfireCatchUpLimit := 3;

    lEvent := lCron.Add('FinalDispatchDefaultCatchUp');
    lEvent.EventPlan := BuildOneShotPlan(lFireAt);
    lEvent.MisfirePolicy := TmaxCronMisfirePolicy.mpDefault;
    lEvent.InvokeMode := imMainThread;
    lEvent.OnScheduleProc :=
      procedure(aSender: TmaxCronEvent)
      begin
        TInterlocked.Increment(lCount);
      end;
    lEvent.ValidFrom := IncSecond(lFireAt, -1);
    lEvent.Run;

    lTickAt := IncSecond(lEvent.NextSchedule, 10);
    lCron.TickAt(lTickAt);

    Assert.AreEqual(1, TInterlocked.CompareExchange(lCount, 0, 0));
    Assert.IsFalse(lEvent.Enabled);
  finally
    lCron.Free;
  end;
end;

procedure TTestRobustCoverage.DefaultDayMatchMode_PropagatesToDefaultEvents;
var
  lCron: TmaxCron;
  lEvent: TmaxCronEvent;
  lPlan: string;
  lBase: TDateTime;
  lExpectedAnd: TDateTime;
  lExpectedOr: TDateTime;
begin
  lPlan := '0 0 1 * 1 * 0 0';
  lBase := EncodeDateTime(2030, 1, 1, 23, 59, 59, 0);
  lExpectedAnd := FindNextForPlan(lPlan, lBase, TmaxCronDayMatchMode.dmAnd);
  lExpectedOr := FindNextForPlan(lPlan, lBase, TmaxCronDayMatchMode.dmOr);

  Assert.IsTrue(lExpectedOr <= lExpectedAnd);

  lCron := TmaxCron.Create(ctPortable);
  try
    lCron.DefaultDayMatchMode := TmaxCronDayMatchMode.dmAnd;

    lEvent := lCron.Add('DefaultDayMatchMode');
    lEvent.EventPlan := lPlan;
    lEvent.ValidFrom := lBase;
    lEvent.Run;

    Assert.AreEqual(lExpectedAnd, lEvent.NextSchedule, 0.0);

    lCron.DefaultDayMatchMode := TmaxCronDayMatchMode.dmOr;
    lEvent.ValidFrom := lBase;

    Assert.AreEqual(lExpectedOr, lEvent.NextSchedule, 0.0);
  finally
    lCron.Free;
  end;
end;

procedure TTestRobustCoverage.DefaultDialect_AppliesToNewEvents;
var
  lCron: TmaxCron;
  lEvent: TmaxCronEvent;
begin
  lCron := TmaxCron.Create(ctPortable);
  try
    lCron.DefaultDialect := cdStandard;

    lEvent := lCron.Add('DefaultDialectEvent');
    Assert.AreEqual(cdStandard, lEvent.Dialect);

    AssertRaises(
      procedure
      begin
        lEvent.EventPlan := '0 0 * * * *';
      end,
      'Expected 6-field plan to fail in cdStandard');

    lEvent.EventPlan := '0 0 * * *';
  finally
    lCron.Free;
  end;
end;

procedure TTestRobustCoverage.DefaultInvokeMode_AppliesToDefaultEvents;
var
  lCron: TmaxCron;
  lEvent: TmaxCronEvent;
  lSignal: TEvent;
  lThreadId: TThreadID;
  lWaitResult: TWaitResult;
begin
  lThreadId := MainThreadID;
  lSignal := TEvent.Create(nil, True, False, '');
  lCron := TmaxCron.Create(ctPortable);
  try
    lCron.DefaultInvokeMode := imThread;

    lEvent := lCron.Add('DefaultInvokeMode');
    lEvent.EventPlan := '* * * * * * * 1';
    lEvent.OnScheduleProc :=
      procedure(aSender: TmaxCronEvent)
      begin
        lThreadId := TThread.CurrentThread.ThreadID;
        lSignal.SetEvent;
      end;
    lEvent.Run;

    lCron.TickAt(lEvent.NextSchedule);
    lWaitResult := lSignal.WaitFor(3000);

    Assert.AreEqual(TWaitResult.wrSignaled, lWaitResult);
    Assert.AreNotEqual(MainThreadID, lThreadId);
  finally
    lCron.Free;
    lSignal.Free;
  end;
end;

procedure TTestRobustCoverage.DefaultMisfireCatchUpLimit_ClampsToOne;
var
  lCron: TmaxCron;
begin
  lCron := TmaxCron.Create(ctPortable);
  try
    lCron.DefaultMisfireCatchUpLimit := 0;
    Assert.AreEqual(1, Integer(lCron.DefaultMisfireCatchUpLimit));
  finally
    lCron.Free;
  end;
end;

procedure TTestRobustCoverage.MisfireCatchUp_MaxAttempts_DoesNotDisableSchedulableEvent;
var
  lCron: TmaxCron;
  lEvent: TmaxCronEvent;
begin
  lCron := TmaxCron.Create(ctPortable);
  try
    lCron.DefaultMisfirePolicy := TmaxCronMisfirePolicy.mpCatchUpAll;
    lCron.DefaultMisfireCatchUpLimit := 1;

    lEvent := lCron.Add('MaxAttemptsBlackout');
    lEvent.EventPlan := '* * * * * * * 0';
    lEvent.BlackoutStartTime := EncodeTime(0, 0, 0, 0);
    lEvent.BlackoutEndTime := EncodeTime(23, 0, 0, 0);
    lEvent.ValidFrom := EncodeDateTime(2032, 3, 20, 0, 0, 0, 0);
    lEvent.MisfirePolicy := TmaxCronMisfirePolicy.mpCatchUpAll;
    lEvent.Run;

    Assert.IsTrue(lEvent.Enabled, 'Event should remain enabled because 23:00:00 is schedulable');
    Assert.AreEqual(EncodeDateTime(2032, 3, 20, 23, 0, 0, 0), lEvent.NextSchedule, 0.0);
  finally
    lCron.Free;
  end;
end;

procedure TTestRobustCoverage.AddOverloads_InvalidPlan_DoNotKeepPartiallyAddedEvents;
var
  lCron: TmaxCron;
begin
  lCron := TmaxCron.Create(ctPortable);
  try
    AssertRaises(
      procedure
      begin
        lCron.Add('InvalidPlanProc', '0 0 0 * * *',
          procedure(aSender: TmaxCronEvent)
          begin
          end);
      end,
      'Expected parse failure for proc overload');
    Assert.AreEqual(0, lCron.Count, 'Proc overload must not keep partially-added events');

    AssertRaises(
      procedure
      begin
        lCron.Add('InvalidPlanEvent', '0 0 0 * * *', NoopSchedule);
      end,
      'Expected parse failure for event overload');
    Assert.AreEqual(0, lCron.Count, 'Event overload must not keep partially-added events');
  finally
    lCron.Free;
  end;
end;

end.

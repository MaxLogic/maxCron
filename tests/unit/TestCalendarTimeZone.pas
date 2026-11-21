unit TestCalendarTimeZone;
{$I maxCron.inc}

interface

uses
  {$IFDEF FPC}
  DateUtils, SysUtils,
  DUnitX.TestFramework,
  maxCron
  {$ELSE}
  System.DateUtils, System.SysUtils,
  DUnitX.TestFramework,
  maxCron
  {$ENDIF};

type
  [TestFixture]
  TTestCalendarTimeZone = class
  private
    function FindNextDayOfWeek(const aStart: TDateTime; const aDow: Integer): TDateTime;
    function TryFindInvalidLocalTime(out aDateTime: TDateTime): Boolean; overload;
    function TryFindInvalidLocalTime(const aNow: TDateTime; out aDateTime: TDateTime): Boolean; overload;
    function TryFindAmbiguousLocalTime(out aDateTime: TDateTime): Boolean; overload;
    function TryFindAmbiguousLocalTime(const aNow: TDateTime; out aDateTime: TDateTime): Boolean; overload;
  public
    [Test]
    procedure TransitionSelection_PreservesSchedulingMargin;

    [Test]
    procedure Exclusion_WeekdaysOnly_SkipsWeekend;

    [Test]
    procedure Exclusion_ExcludedDatesCsv_SkipsListedDays;

    [Test]
    procedure Exclusion_BlackoutWindow_SkipsBlockedHours;

    [Test]
    procedure TimeZone_Utc_UsesUtcMidnight;

    [Test]
    procedure TimeZone_FixedOffset_UsesOffsetMidnight;

    [Test]
    procedure DstSpringPolicy_SkipVsShift;

    [Test]
    procedure DstFallPolicy_RunTwice_QueuesSecondOccurrence;

    [Test]
    procedure DstFallPolicy_PreferSecond_WaitsForSecondOccurrence;
  end;

implementation

uses
  maxCron.Internal.TimeZone, TestZoneFakes;

procedure TTestCalendarTimeZone.TransitionSelection_PreservesSchedulingMargin;
var
  lTransition, lNow, lSelected: TDateTime;
begin
  if TryFindInvalidLocalTime(EncodeDate(2027, 1, 1), lTransition) then
  begin
    lNow := IncMilliSecond(lTransition, -1);
    Assert.IsTrue(TryFindInvalidLocalTime(lNow, lSelected));
    Assert.IsTrue(lSelected >= IncHour(lNow), 'Transition needs at least one hour of scheduling margin');
    lNow := EncodeDateTime(2027, 12, 31, 23, 59, 59, 999);
    Assert.IsTrue(TryFindInvalidLocalTime(lNow, lSelected));
    Assert.IsTrue(lSelected >= IncHour(lNow), 'Year rollover must preserve the scheduling margin');
    Assert.IsTrue(YearOf(lSelected) >= 2028);
  end;
  if TryFindAmbiguousLocalTime(EncodeDate(2027, 1, 1), lTransition) then
  begin
    lNow := IncMilliSecond(lTransition, -1);
    Assert.IsTrue(TryFindAmbiguousLocalTime(lNow, lSelected));
    Assert.IsTrue(lSelected >= IncHour(lNow), 'Transition needs at least one hour of scheduling margin');
    lNow := EncodeDateTime(2027, 12, 31, 23, 59, 59, 999);
    Assert.IsTrue(TryFindAmbiguousLocalTime(lNow, lSelected));
    Assert.IsTrue(lSelected >= IncHour(lNow), 'Year rollover must preserve the scheduling margin');
    Assert.IsTrue(YearOf(lSelected) >= 2028);
  end;
end;


function TTestCalendarTimeZone.FindNextDayOfWeek(const aStart: TDateTime; const aDow: Integer): TDateTime;
var
  lDate: TDateTime;
begin
  lDate := Trunc(aStart);
  while DayOfTheWeek(lDate) <> aDow do
    lDate := IncDay(lDate);
  Result := lDate;
end;

function TTestCalendarTimeZone.TryFindInvalidLocalTime(out aDateTime: TDateTime): Boolean;
begin
  Result := TryFindInvalidLocalTime(Now, aDateTime);
end;

function TTestCalendarTimeZone.TryFindInvalidLocalTime(const aNow: TDateTime; out aDateTime: TDateTime): Boolean;
var
  lStart: TDateTime;
  lCursor: TDateTime;
  lLimit: TDateTime;
begin
  // Leave at least one hour before Run, then round upward to a whole cron minute.
  lStart := RecodeSecond(RecodeMilliSecond(IncMinute(IncHour(aNow)), 0), 0);
  lLimit := IncYear(lStart, 2);
  lCursor := lStart;
  while lCursor < lLimit do
  begin
    if CronSystemTimeZone.IsInvalidTime(lCursor) then
    begin
      aDateTime := lCursor;
      Exit(True);
    end;
    lCursor := IncMinute(lCursor, 1);
  end;
  Result := False;
  Assert.Fail('No LOCAL transition found in the two-year search window');
end;

function TTestCalendarTimeZone.TryFindAmbiguousLocalTime(out aDateTime: TDateTime): Boolean;
begin
  Result := TryFindAmbiguousLocalTime(Now, aDateTime);
end;

function TTestCalendarTimeZone.TryFindAmbiguousLocalTime(const aNow: TDateTime; out aDateTime: TDateTime): Boolean;
var
  lStart: TDateTime;
  lCursor: TDateTime;
  lLimit: TDateTime;
begin
  // Leave at least one hour before Run, then round upward to a whole cron minute.
  lStart := RecodeSecond(RecodeMilliSecond(IncMinute(IncHour(aNow)), 0), 0);
  lLimit := IncYear(lStart, 2);
  lCursor := lStart;
  while lCursor < lLimit do
  begin
    if CronSystemTimeZone.IsAmbiguousTime(lCursor) then
    begin
      aDateTime := lCursor;
      Exit(True);
    end;
    lCursor := IncMinute(lCursor, 1);
  end;
  Result := False;
  Assert.Fail('No LOCAL transition found in the two-year search window');
end;

procedure TTestCalendarTimeZone.Exclusion_WeekdaysOnly_SkipsWeekend;
var
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lSaturday: TDateTime;
begin
  lCron := TmaxCron.Create(ctPortable);
  try
    lEvent := lCron.Add('WeekdaysOnly');
    lEvent.EventPlan := '0 0 * * * * 0 0';
    lEvent.WeekdaysOnly := True;
    lSaturday := FindNextDayOfWeek(EncodeDate(2030, 1, 1), 6);
    lEvent.ValidFrom := lSaturday;
    lEvent.Run;

    Assert.AreEqual(IncDay(lSaturday, 2), lEvent.NextSchedule, 0.0,
      'Saturday must advance to the following Monday');
  finally
    lCron.Free;
  end;
end;

procedure TTestCalendarTimeZone.Exclusion_ExcludedDatesCsv_SkipsListedDays;
var
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
begin
  lCron := TmaxCron.Create(ctPortable);
  try
    lEvent := lCron.Add('HolidayList');
    lEvent.EventPlan := '0 0 * * * * 0 0';
    lEvent.ExcludedDatesCsv := '2031-01-02,2031-01-03';
    lEvent.ValidFrom := EncodeDate(2031, 1, 1);
    lEvent.Run;

    Assert.AreEqual(EncodeDateTime(2031, 1, 1, 0, 0, 0, 0), lEvent.NextSchedule, 0.0,
      'ValidFrom is inclusive before the excluded dates');
    lCron.TickAt(lEvent.NextSchedule);
    Assert.AreEqual(EncodeDateTime(2031, 1, 4, 0, 0, 0, 0), lEvent.NextSchedule, 0.0);
  finally
    lCron.Free;
  end;
end;

procedure TTestCalendarTimeZone.Exclusion_BlackoutWindow_SkipsBlockedHours;
var
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
begin
  lCron := TmaxCron.Create(ctPortable);
  try
    lEvent := lCron.Add('BlackoutHours');
    lEvent.EventPlan := '0 * * * * * 0 0';
    lEvent.BlackoutStartTime := EncodeTime(9, 0, 0, 0);
    lEvent.BlackoutEndTime := EncodeTime(17, 0, 0, 0);
    lEvent.ValidFrom := EncodeDateTime(2032, 2, 10, 8, 30, 0, 0);
    lEvent.Run;

    Assert.AreEqual(EncodeDateTime(2032, 2, 10, 17, 0, 0, 0), lEvent.NextSchedule, 0.0);
  finally
    lCron.Free;
  end;
end;

procedure TTestCalendarTimeZone.TimeZone_Utc_UsesUtcMidnight;
var
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lStartAt: TDateTime;
  lUtcBase: TDateTime;
  lUtcMidnight: TDateTime;
  lExpected: TDateTime;
begin
  lCron := TmaxCron.Create(ctPortable);
  try
    lStartAt := EncodeDateTime(2033, 1, 15, 12, 34, 0, 0);
    lEvent := lCron.Add('UtcEvent');
    lEvent.EventPlan := '0 0 * * * * 0 1';
    lEvent.TimeZoneId := 'UTC';
    lEvent.ValidFrom := lStartAt;
    lEvent.Run;

    lUtcBase := CronSystemTimeZone.ToUniversalTime(lStartAt, False);
    lUtcMidnight := EncodeDateTime(YearOf(lUtcBase), MonthOf(lUtcBase), DayOf(lUtcBase), 0, 0, 0, 0);
    if lUtcMidnight <= lUtcBase then
      lUtcMidnight := IncDay(lUtcMidnight);
    lExpected := CronSystemTimeZone.ToLocalTime(lUtcMidnight);

    Assert.AreEqual(lExpected, lEvent.NextSchedule, 0.0);
  finally
    lCron.Free;
  end;
end;

procedure TTestCalendarTimeZone.TimeZone_FixedOffset_UsesOffsetMidnight;
var
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lStartAt: TDateTime;
  lUtcBase: TDateTime;
  lOffsetMinutes: Integer;
  lEventBase: TDateTime;
  lEventMidnight: TDateTime;
  lExpected: TDateTime;
begin
  lCron := TmaxCron.Create(ctPortable);
  try
    lStartAt := EncodeDateTime(2033, 1, 15, 12, 34, 0, 0);
    lOffsetMinutes := 150; // UTC+02:30
    lEvent := lCron.Add('OffsetEvent');
    lEvent.EventPlan := '0 0 * * * * 0 1';
    lEvent.TimeZoneId := 'UTC+02:30';
    lEvent.ValidFrom := lStartAt;
    lEvent.Run;

    lUtcBase := CronSystemTimeZone.ToUniversalTime(lStartAt, False);
    lEventBase := lUtcBase + (lOffsetMinutes / (24 * 60));
    lEventMidnight := EncodeDateTime(YearOf(lEventBase), MonthOf(lEventBase), DayOf(lEventBase), 0, 0, 0, 0);
    if lEventMidnight <= lEventBase then
      lEventMidnight := IncDay(lEventMidnight);
    lExpected := CronSystemTimeZone.ToLocalTime(lEventMidnight - (lOffsetMinutes / (24 * 60)));

    Assert.AreEqual(lExpected, lEvent.NextSchedule, 0.0);
  finally
    lCron.Free;
  end;
end;

procedure TTestCalendarTimeZone.DstSpringPolicy_SkipVsShift;
var
  lInvalid: TDateTime;
  lPlan: string;
  lCron: TmaxCron;
  lSkipEvent: IMaxCronEvent;
  lShiftEvent: IMaxCronEvent;
begin
  if not TryFindInvalidLocalTime(lInvalid) then
    Exit;

  lPlan := Format('%d %d %d %d * %d 0 1',
    [MinuteOf(lInvalid), HourOf(lInvalid), DayOf(lInvalid), MonthOf(lInvalid), YearOf(lInvalid)]);

  lCron := TmaxCron.Create(ctPortable);
  try
    lSkipEvent := lCron.Add('SpringSkip');
    lSkipEvent.EventPlan := lPlan;
    lSkipEvent.TimeZoneId := 'LOCAL';
    lSkipEvent.DstSpringPolicy := TmaxCronDstSpringPolicy.dspSkip;
    lSkipEvent.ValidFrom := IncSecond(lInvalid, -1);
    lSkipEvent.Run;
    Assert.IsFalse(lSkipEvent.Enabled);

    lShiftEvent := lCron.Add('SpringShift');
    lShiftEvent.EventPlan := lPlan;
    lShiftEvent.TimeZoneId := 'LOCAL';
    lShiftEvent.DstSpringPolicy := TmaxCronDstSpringPolicy.dspRunAtNextValidTime;
    lShiftEvent.ValidFrom := IncSecond(lInvalid, -1);
    lShiftEvent.Run;
    Assert.IsTrue(lShiftEvent.Enabled);
    Assert.IsTrue(lShiftEvent.NextSchedule > lInvalid);
  finally
    lCron.Free;
  end;
end;

procedure TTestCalendarTimeZone.DstFallPolicy_RunTwice_QueuesSecondOccurrence;
var
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lZone: ICronZoneRules;
  lFirstUs, lSecondUs, lUtcUs: Int64;
  lDisplay: TDateTime;
  lCount: Integer;
begin
  lZone := CreateCronZone('calendar overlap host', FakeZoneSource(0));
  lFirstUs := ZoneMs(2026, 10, 25, 0) * 1000;
  lSecondUs := ZoneMs(2026, 10, 25, 1) * 1000;
  lUtcUs := lFirstUs - 1000000;
  lDisplay := CronMsToDateTime(ZoneMs(2026, 10, 25, 2));
  lCount := 0;
  SetCronSystemTimeZoneForTests(TZoneAsSystemZone.Create(lZone));
  SetMaxCronUtcClockHook(function: Int64 begin Result := lUtcUs; end);
  SetMaxCronWallClockHook(function: Int64 begin Result := lUtcUs + lZone.GetPeriod(lUtcUs div 1000).OffsetMs * 1000; end);
  lCron := nil;
  try
    lCron := TmaxCron.Create(ctPortable);
    lEvent := lCron.Add('calendar overlap');
    lEvent.EventPlan := '0 2 25 10 * 2026 0 2';
    lEvent.TimeZoneId := 'LOCAL';
    lEvent.DstFallPolicy := TmaxCronDstFallPolicy.dfpRunTwice;
    lEvent.OnScheduleProc := procedure(aSender: IMaxCronEvent) begin Inc(lCount); end;
    lEvent.InvokeMode := imMainThread;
    lEvent.Run;
    Assert.AreEqual(lDisplay, lEvent.NextSchedule, 0.0);
    lCron.TickAtUtcUs(lFirstUs - 1000000);
    Assert.AreEqual(0, lCount);
    lCron.TickAtUtcUs(lFirstUs);
    Assert.AreEqual(1, lCount, 'first UTC instance');
    Assert.AreEqual(lDisplay, lEvent.NextSchedule, 0.0, 'next display still identifies the second instance');
    lCron.TickAtUtcUs(lFirstUs + 1000000);
    lCron.TickAtUtcUs(lSecondUs - 1);
    Assert.AreEqual(1, lCount, 'the second instance cannot run early');
    lCron.TickAtUtcUs(lSecondUs);
    Assert.AreEqual(2, lCount, 'second UTC instance');
    lCron.TickAtUtcUs(lSecondUs + 1000000);
    Assert.AreEqual(2, lCount, 'each policy instance runs once');
  finally
    lEvent := nil;
    lCron.Free;
    SetMaxCronUtcClockHook(nil);
    SetMaxCronWallClockHook(nil);
    SetCronSystemTimeZoneForTests(nil);
  end;
end;

procedure TTestCalendarTimeZone.DstFallPolicy_PreferSecond_WaitsForSecondOccurrence;
var
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lZone: ICronZoneRules;
  lFirstUs, lSecondUs, lUtcUs: Int64;
  lDisplay: TDateTime;
  lCount: Integer;
begin
  lZone := CreateCronZone('calendar overlap host', FakeZoneSource(0));
  lFirstUs := ZoneMs(2026, 10, 25, 0) * 1000;
  lSecondUs := ZoneMs(2026, 10, 25, 1) * 1000;
  lUtcUs := lFirstUs - 1000000;
  lDisplay := CronMsToDateTime(ZoneMs(2026, 10, 25, 2));
  lCount := 0;
  SetCronSystemTimeZoneForTests(TZoneAsSystemZone.Create(lZone));
  SetMaxCronUtcClockHook(function: Int64 begin Result := lUtcUs; end);
  SetMaxCronWallClockHook(function: Int64 begin Result := lUtcUs + lZone.GetPeriod(lUtcUs div 1000).OffsetMs * 1000; end);
  lCron := nil;
  try
    lCron := TmaxCron.Create(ctPortable);
    lEvent := lCron.Add('calendar overlap');
    lEvent.EventPlan := '0 2 25 10 * 2026 0 1';
    lEvent.TimeZoneId := 'LOCAL';
    lEvent.DstFallPolicy := TmaxCronDstFallPolicy.dfpRunOncePreferSecondInstance;
    lEvent.OnScheduleProc := procedure(aSender: IMaxCronEvent) begin Inc(lCount); end;
    lEvent.InvokeMode := imMainThread;
    lEvent.Run;
    Assert.AreEqual(lDisplay, lEvent.NextSchedule, 0.0);
    lCron.TickAtUtcUs(lFirstUs - 1000000);
    Assert.AreEqual(0, lCount);
    lCron.TickAtUtcUs(lFirstUs);
    Assert.AreEqual(0, lCount, 'first UTC instance');
    Assert.AreEqual(lDisplay, lEvent.NextSchedule, 0.0, 'next display still identifies the second instance');
    lCron.TickAtUtcUs(lFirstUs + 1000000);
    lCron.TickAtUtcUs(lSecondUs - 1);
    Assert.AreEqual(0, lCount, 'the second instance cannot run early');
    lCron.TickAtUtcUs(lSecondUs);
    Assert.AreEqual(1, lCount, 'second UTC instance');
    lCron.TickAtUtcUs(lSecondUs + 1000000);
    Assert.AreEqual(1, lCount, 'each policy instance runs once');
  finally
    lEvent := nil;
    lCron.Free;
    SetMaxCronUtcClockHook(nil);
    SetMaxCronWallClockHook(nil);
    SetCronSystemTimeZoneForTests(nil);
  end;
end;

end.


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
  maxCron.Internal.TimeZone;

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
  lAmbiguous: TDateTime;
  lPlan: string;
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lCount: Integer;
  lFirstNext: TDateTime;
  lSecondNext: TDateTime;
begin
  if not TryFindAmbiguousLocalTime(lAmbiguous) then
    Exit;

  lCount := 0;
  lPlan := Format('%d %d %d %d * %d 0 2',
    [MinuteOf(lAmbiguous), HourOf(lAmbiguous), DayOf(lAmbiguous), MonthOf(lAmbiguous), YearOf(lAmbiguous)]);

  lCron := TmaxCron.Create(ctPortable);
  try
    lEvent := lCron.Add('FallTwice');
    lEvent.EventPlan := lPlan;
    lEvent.TimeZoneId := 'LOCAL';
    lEvent.DstFallPolicy := TmaxCronDstFallPolicy.dfpRunTwice;
    lEvent.OnScheduleProc :=
      procedure(Sender: IMaxCronEvent)
      begin
        Inc(lCount);
      end;
    lEvent.ValidFrom := IncSecond(lAmbiguous, -1);
    lEvent.Run;

    lFirstNext := lEvent.NextSchedule;
    Assert.IsTrue(CronSystemTimeZone.IsAmbiguousTime(lFirstNext));
    lCron.TickAt(lFirstNext);
    Assert.AreEqual(1, lCount, 'First ambiguous instance should execute');
    lSecondNext := lEvent.NextSchedule;

    Assert.AreEqual(lFirstNext, lSecondNext, 0.0);
    Assert.IsTrue(CronSystemTimeZone.IsAmbiguousTime(lSecondNext));
    lCron.TickAt(lSecondNext);
    Assert.AreEqual(1, lCount, 'Second run must wait for the repeated wall-clock instance');
    lCron.TickAt(IncMinute(lSecondNext, -1)); // simulate fallback rollback (time moved back)
    lCron.TickAt(lSecondNext);
    Assert.AreEqual(2, lCount);
  finally
    lCron.Free;
  end;
end;

procedure TTestCalendarTimeZone.DstFallPolicy_PreferSecond_WaitsForSecondOccurrence;
var
  lAmbiguous: TDateTime;
  lPlan: string;
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lCount: Integer;
  lNextAt: TDateTime;
begin
  if not TryFindAmbiguousLocalTime(lAmbiguous) then
    Exit;

  lCount := 0;
  lPlan := Format('%d %d %d %d * %d 0 1',
    [MinuteOf(lAmbiguous), HourOf(lAmbiguous), DayOf(lAmbiguous), MonthOf(lAmbiguous), YearOf(lAmbiguous)]);

  lCron := TmaxCron.Create(ctPortable);
  try
    lEvent := lCron.Add('FallPreferSecond');
    lEvent.EventPlan := lPlan;
    lEvent.TimeZoneId := 'LOCAL';
    lEvent.DstFallPolicy := TmaxCronDstFallPolicy.dfpRunOncePreferSecondInstance;
    lEvent.OnScheduleProc :=
      procedure(Sender: IMaxCronEvent)
      begin
        Inc(lCount);
      end;
    lEvent.ValidFrom := IncSecond(lAmbiguous, -1);
    lEvent.Run;

    lNextAt := lEvent.NextSchedule;
    Assert.IsTrue(CronSystemTimeZone.IsAmbiguousTime(lNextAt));

    lCron.TickAt(lNextAt);
    Assert.AreEqual(0, lCount, 'Prefer-second must not fire at the first ambiguous instance');

    lCron.TickAt(IncMinute(lNextAt, -1)); // simulate fallback rollback (time moved back)
    lCron.TickAt(lNextAt);
    Assert.AreEqual(1, lCount, 'Prefer-second should fire at the repeated ambiguous instance');
  finally
    lCron.Free;
  end;
end;

end.


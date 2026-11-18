unit TestLocalZoneOs;
{$I maxCron.inc}

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestLocalZoneOs = class
  public
    [Test] procedure NativeRecordLayout;
    [Test] procedure SouthernHemisphere;
    [Test] procedure NoDaylightAndDisabled;
    [Test] procedure MidnightAndAbsoluteRules;
    {$IFNDEF FPC}
    [Test] procedure MatchesRtlLocal;
    {$ENDIF}
  end;

implementation

uses
  {$IFDEF FPC} DateUtils, SysUtils, {$ELSE} System.DateUtils, System.SysUtils, System.TimeSpan, {$ENDIF}
  maxCron.Internal.TimeZone, maxCron.Plan, TestWindowsZoneOracle;

function LocalMs(const aYear, aMonth, aDay, aHour: Word): Int64;
begin
  Result := CronDateTimeToMs(EncodeDateTime(aYear, aMonth, aDay, aHour, 0, 0, 0));
end;

function SouthernRule: TCronWindowsYearRule;
begin
  Result := Default(TCronWindowsYearRule);
  Result.Year := 2026;
  Result.Bias := -600;
  Result.DaylightBias := -60;
  Result.DaylightDate.wMonth := 10;
  Result.DaylightDate.wDay := 1;
  Result.DaylightDate.wHour := 2;
  Result.StandardDate.wMonth := 4;
  Result.StandardDate.wDay := 1;
  Result.StandardDate.wHour := 3;
end;

procedure TTestLocalZoneOs.NativeRecordLayout;
begin
  Assert.AreEqual(16, SizeOf(TCronWindowsSystemTime));
  Assert.AreEqual(172, SizeOf(TCronWindowsZoneInfo));
  Assert.AreEqual(432, SizeOf(TCronWindowsDynamicInfo));
end;

procedure TTestLocalZoneOs.SouthernHemisphere;
var
  lRule: TCronWindowsYearRule;
  lZone: ICronZoneRules;
  lMap: TCronLocalMapping;
begin
  lRule := SouthernRule;
  lZone := CreateCronZone('synthetic-south', CreateCronWindowsZoneSourceForTests(FakeWindowsOracle(39600000,
    [WindowsFakeChange(LocalMs(2026, 4, 4, 16), 36000000),
     WindowsFakeChange(LocalMs(2026, 10, 3, 16), 39600000)], [lRule])));
  Assert.AreEqual(Int64(39600000), lZone.GetPeriod(LocalMs(2026, 1, 1, 0)).OffsetMs);
  Assert.AreEqual(Int64(36000000), lZone.GetPeriod(LocalMs(2026, 7, 1, 0)).OffsetMs);
  Assert.AreEqual(Int64(39600000), lZone.GetPeriod(LocalMs(2027, 1, 1, 0)).OffsetMs);
  lMap := lZone.MapLocal(LocalMs(2026, 10, 4, 2));
  Assert.AreEqual<Integer>(Ord(clkGap), Ord(lMap.Kind));
  Assert.AreEqual(LocalMs(2026, 10, 3, 16), lMap.FirstUtcMs);
  lMap := lZone.MapLocal(LocalMs(2026, 4, 5, 2));
  Assert.AreEqual<Integer>(Ord(clkOverlap), Ord(lMap.Kind));
  Assert.AreEqual(LocalMs(2026, 4, 4, 15), lMap.FirstUtcMs);
  Assert.AreEqual(LocalMs(2026, 4, 4, 16), lMap.SecondUtcMs);
end;

procedure TTestLocalZoneOs.NoDaylightAndDisabled;
var
  lRule: TCronWindowsYearRule;
  lZone: ICronZoneRules;
begin
  lRule := Default(TCronWindowsYearRule);
  lRule.Year := 2026;
  lRule.Bias := -345;
  lZone := CreateCronZone('no-dst', CreateCronWindowsZoneSourceForTests(
    FakeWindowsOracle(20700000, [], [lRule])));
  Assert.AreEqual(Int64(20700000), lZone.GetPeriod(LocalMs(2026, 1, 1, 0)).OffsetMs);
  Assert.AreEqual(Int64(20700000), lZone.GetPeriod(LocalMs(2026, 7, 1, 0)).OffsetMs);

end;

procedure TTestLocalZoneOs.MidnightAndAbsoluteRules;
var
  lRule: TCronWindowsYearRule;
  lZone: ICronZoneRules;
  lTransition: Int64;
begin
  lRule := Default(TCronWindowsYearRule);
  lRule.Year := 2026;
  lRule.DaylightBias := -60;
  lRule.DaylightDate.wYear := 2026;
  lRule.DaylightDate.wMonth := 3;
  lRule.DaylightDate.wDay := 28;
  lRule.DaylightDate.wHour := 23;
  lRule.DaylightDate.wMinute := 59;
  lRule.DaylightDate.wSecond := 59;
  lRule.DaylightDate.wMilliseconds := 999;
  lRule.StandardDate.wYear := 2026;
  lRule.StandardDate.wMonth := 10;
  lRule.StandardDate.wDay := 25;
  lRule.StandardDate.wHour := 2;
  lZone := CreateCronZone('absolute-midnight', CreateCronWindowsZoneSourceForTests(FakeWindowsOracle(0,
    [WindowsFakeChange(LocalMs(2026, 3, 29, 0) - 1, 3600000),
     WindowsFakeChange(LocalMs(2026, 10, 25, 1), 0)], [lRule])));
  lTransition := LocalMs(2026, 3, 29, 0);
  Assert.AreEqual(Int64(0), lZone.GetPeriod(lTransition - 1).OffsetMs);
  Assert.AreEqual(Int64(3600000), lZone.GetPeriod(lTransition).OffsetMs);
  Assert.AreEqual<Integer>(Ord(clkGap), Ord(lZone.MapLocal(lTransition).Kind));
  Assert.AreEqual(Int64(3600000), lZone.GetPeriod(LocalMs(2026, 10, 25, 1) - 1).OffsetMs);
  Assert.AreEqual(Int64(0), lZone.GetPeriod(LocalMs(2026, 10, 25, 1)).OffsetMs);
end;

{$IFNDEF FPC}
procedure TTestLocalZoneOs.MatchesRtlLocal;
var
  lZone: ICronTimeZone;
  lCursor, lNext, lMinute: TDateTime;
  y: Integer;
begin
  lZone := CreateCronOsLocalTimeZoneForTests;
  for y := 2000 to 2040 do
  begin
    lCursor := EncodeDate(y, 1, 1);
    lNext := EncodeDate(y + 1, 1, 1);
    while lCursor < lNext do
    begin
      Assert.AreEqual(TTimeZone.Local.IsInvalidTime(lCursor), lZone.IsInvalidTime(lCursor));
      Assert.AreEqual(TTimeZone.Local.IsAmbiguousTime(lCursor), lZone.IsAmbiguousTime(lCursor));
      Assert.AreEqual(CronDateTimeToMs(TTimeZone.Local.ToLocalTime(lCursor)),
        CronDateTimeToMs(lZone.ToLocalTime(lCursor)));
      if not TTimeZone.Local.IsInvalidTime(lCursor) then
      begin
        Assert.AreEqual(CronDateTimeToMs(TTimeZone.Local.ToUniversalTime(lCursor, False)),
          CronDateTimeToMs(lZone.ToUniversalTime(lCursor, False)));
        Assert.AreEqual(CronDateTimeToMs(TTimeZone.Local.ToUniversalTime(lCursor, True)),
          CronDateTimeToMs(lZone.ToUniversalTime(lCursor, True)));
      end;
      if TTimeZone.Local.GetUtcOffset(lCursor) <> TTimeZone.Local.GetUtcOffset(IncHour(lCursor, 6)) then
      begin
        lMinute := IncHour(lCursor, -3);
        while lMinute <= IncHour(lCursor, 9) do
        begin
          Assert.AreEqual(TTimeZone.Local.IsInvalidTime(lMinute), lZone.IsInvalidTime(lMinute));
          Assert.AreEqual(TTimeZone.Local.IsAmbiguousTime(lMinute), lZone.IsAmbiguousTime(lMinute));
          Assert.AreEqual(CronDateTimeToMs(TTimeZone.Local.ToLocalTime(lMinute)),
            CronDateTimeToMs(lZone.ToLocalTime(lMinute)));
          if not TTimeZone.Local.IsInvalidTime(lMinute) then
          begin
            Assert.AreEqual(CronDateTimeToMs(TTimeZone.Local.ToUniversalTime(lMinute, False)),
              CronDateTimeToMs(lZone.ToUniversalTime(lMinute, False)));
            Assert.AreEqual(CronDateTimeToMs(TTimeZone.Local.ToUniversalTime(lMinute, True)),
              CronDateTimeToMs(lZone.ToUniversalTime(lMinute, True)));
          end;
          lMinute := IncMinute(lMinute);
        end;
      end;
      lCursor := IncHour(lCursor, 6);
    end;
  end;
end;
{$ENDIF}

end.

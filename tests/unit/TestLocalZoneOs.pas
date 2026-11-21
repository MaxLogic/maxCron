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

{$IFNDEF FPC}
type
  TRtlProbeHost = class(TInterfacedObject, ICronTimeZone)
  public
    function ToUniversalTime(const aLocal: TDateTime; const aForceDaylight: Boolean): TDateTime;
    function ToLocalTime(const aUtc: TDateTime): TDateTime;
    function IsAmbiguousTime(const aLocal: TDateTime): Boolean;
    function IsInvalidTime(const aLocal: TDateTime): Boolean;
  end;

function TRtlProbeHost.ToUniversalTime(const aLocal: TDateTime; const aForceDaylight: Boolean): TDateTime;
begin
  Result := TTimeZone.Local.ToUniversalTime(aLocal, aForceDaylight);
end;

function TRtlProbeHost.ToLocalTime(const aUtc: TDateTime): TDateTime;
begin
  Result := TTimeZone.Local.ToLocalTime(aUtc);
end;

function TRtlProbeHost.IsAmbiguousTime(const aLocal: TDateTime): Boolean;
begin
  Result := TTimeZone.Local.IsAmbiguousTime(aLocal);
end;

function TRtlProbeHost.IsInvalidTime(const aLocal: TDateTime): Boolean;
begin
  Result := TTimeZone.Local.IsInvalidTime(aLocal);
end;

procedure CheckRtlProbe(const aDirect, aProbe: ICronZoneRules; const aMs: Int64);
var
  lDirect, lProbe: TCronLocalMapping;
  k: Integer;
begin
  for k := -1 to 1 do
  begin
    Assert.AreEqual(aDirect.UtcToLocalMs(aMs+k), aProbe.UtcToLocalMs(aMs+k), 'RTL probe forward');
    lDirect := aDirect.MapLocal(aMs+k); lProbe := aProbe.MapLocal(aMs+k);
    Assert.AreEqual(Ord(lDirect.Kind), Ord(lProbe.Kind), 'RTL probe kind');
    Assert.AreEqual(lDirect.FirstUtcMs, lProbe.FirstUtcMs, 'RTL probe first');
    Assert.AreEqual(lDirect.SecondUtcMs, lProbe.SecondUtcMs, 'RTL probe second');
  end;
end;
{$ENDIF}

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
{$IFDEF MAXCRON_LONG_TESTS}
procedure TTestLocalZoneOs.MatchesRtlLocal;
var
  lZone: ICronTimeZone;
  lDirect, lProbe: ICronZoneRules;
  lCursor, lNext, lMinute: TDateTime;
  y: Integer;
begin
  lZone := CreateCronOsLocalTimeZoneForTests;
  lDirect := (lZone as ICronTimeZoneRules).GetRules;
  lProbe := CreateCronProbeZoneForTests(TRtlProbeHost.Create);
  for y := 2000 to 2040 do
  begin
    lCursor := EncodeDate(y, 1, 1);
    CheckRtlProbe(lDirect, lProbe, CronDateTimeToMs(lCursor));
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
          CheckRtlProbe(lDirect, lProbe, CronDateTimeToMs(lMinute));
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
{$ELSE}
function RtlOffsetMs(const aUtcMs: Int64): Int64;
begin
  Result := CronDateTimeToMs(TTimeZone.Local.ToLocalTime(CronMsToDateTime(aUtcMs))) - aUtcMs;
end;

procedure CheckRtlSubsetWall(const aZone: ICronTimeZone; const aDirect, aProbe: ICronZoneRules;
  const aLocalMs: Int64);
var
  lLocal: TDateTime;
  lDirectMap, lProbeMap: TCronLocalMapping;
begin
  lLocal := CronMsToDateTime(aLocalMs);
  lDirectMap := aDirect.MapLocal(aLocalMs);
  lProbeMap := aProbe.MapLocal(aLocalMs);
  Assert.AreEqual(Ord(lDirectMap.Kind), Ord(lProbeMap.Kind), 'RTL subset mapping kind');
  Assert.AreEqual(lDirectMap.FirstUtcMs, lProbeMap.FirstUtcMs, 'RTL subset mapping first');
  Assert.AreEqual(lDirectMap.SecondUtcMs, lProbeMap.SecondUtcMs, 'RTL subset mapping second');
  Assert.AreEqual(TTimeZone.Local.IsInvalidTime(lLocal), aZone.IsInvalidTime(lLocal));
  Assert.AreEqual(TTimeZone.Local.IsAmbiguousTime(lLocal), aZone.IsAmbiguousTime(lLocal));
  if not TTimeZone.Local.IsInvalidTime(lLocal) then
  begin
    Assert.AreEqual(CronDateTimeToMs(TTimeZone.Local.ToUniversalTime(lLocal, False)),
      CronDateTimeToMs(aZone.ToUniversalTime(lLocal, False)));
    Assert.AreEqual(CronDateTimeToMs(TTimeZone.Local.ToUniversalTime(lLocal, True)),
      CronDateTimeToMs(aZone.ToUniversalTime(lLocal, True)));
  end;
end;

procedure CheckRtlSubsetUtc(const aZone: ICronTimeZone; const aDirect, aProbe: ICronZoneRules;
  const aUtcMs: Int64);
var
  lUtc: TDateTime;
  lLocalMs: Int64;
begin
  lUtc := CronMsToDateTime(aUtcMs);
  lLocalMs := CronDateTimeToMs(TTimeZone.Local.ToLocalTime(lUtc));
  Assert.AreEqual(lLocalMs, CronDateTimeToMs(aZone.ToLocalTime(lUtc)));
  Assert.AreEqual(lLocalMs, aDirect.UtcToLocalMs(aUtcMs), 'RTL subset direct forward');
  Assert.AreEqual(lLocalMs, aProbe.UtcToLocalMs(aUtcMs), 'RTL subset probe forward');
end;

procedure CheckRtlSubsetTransition(const aZone: ICronTimeZone; const aDirect, aProbe: ICronZoneRules;
  const aUtcMs, aBefore, aAfter: Int64);
var
  lFirst, lSecond, lWall: Int64;
  lMapping: TCronLocalMapping;
  i: Integer;
begin
  for i := -1 to 1 do
  begin
    CheckRtlSubsetUtc(aZone, aDirect, aProbe, aUtcMs + Int64(i) * 1000);
    // Test each local gap/overlap edge in its own coordinate system.
    CheckRtlSubsetWall(aZone, aDirect, aProbe, aUtcMs + aBefore + Int64(i) * 1000);
    CheckRtlSubsetWall(aZone, aDirect, aProbe, aUtcMs + aAfter + Int64(i) * 1000);
  end;
  if aAfter < aBefore then
  begin
    lWall := aUtcMs + (aBefore + aAfter) div 2;
    lFirst := lWall - aBefore;
    lSecond := lWall - aAfter;
    CheckRtlSubsetUtc(aZone, aDirect, aProbe, lFirst);
    CheckRtlSubsetUtc(aZone, aDirect, aProbe, lSecond);
    Assert.AreEqual(lWall, aProbe.UtcToLocalMs(lFirst));
    Assert.AreEqual(lWall, aProbe.UtcToLocalMs(lSecond));
    CheckRtlSubsetWall(aZone, aDirect, aProbe, lWall);
    lMapping := aProbe.MapLocal(lWall);
    Assert.AreEqual(lFirst, lMapping.FirstUtcMs);
    Assert.AreEqual(lSecond, lMapping.SecondUtcMs);
  end;
end;

procedure TTestLocalZoneOs.MatchesRtlLocal;
const
  cDayMs = Int64(86400000);
  cScanMs = Int64(21600000);
var
  lZone: ICronTimeZone;
  lDirect, lProbe: ICronZoneRules;
  lDay, lEnd, lCursor, lNext, lLo, lHi, lMiddle, lBefore, lAfter, lSeed: Int64;
  lDays, lTransitions: Integer;
begin
  lZone := CreateCronOsLocalTimeZoneForTests;
  lDirect := (lZone as ICronTimeZoneRules).GetRules;
  lProbe := CreateCronProbeZoneForTests(TRtlProbeHost.Create);
  lDay := CronDateTimeToMs(EncodeDate(2000, 1, 1));
  lEnd := CronDateTimeToMs(EncodeDate(2041, 1, 1));
  lSeed := 20261118;
  lDays := 0; lTransitions := 0;
  // Period containment, identity and edge invalidation are tested separately.
  // Reuse the scheduler's bounded memo while this immutable host is sampled.
  CronBeginZonePeriodMemo;
  try
    lBefore := RtlOffsetMs(lDay - 1000); lAfter := RtlOffsetMs(lDay);
    if lBefore <> lAfter then
    begin
      CheckRtlSubsetTransition(lZone, lDirect, lProbe, lDay, lBefore, lAfter);
      Inc(lTransitions);
    end;
    while lDay < lEnd do
    begin
      lCursor := lDay;
      while lCursor < lDay + cDayMs do
      begin
        lNext := lCursor + cScanMs;
        lBefore := RtlOffsetMs(lCursor);
        lAfter := RtlOffsetMs(lNext);
        if lBefore <> lAfter then
        begin
          lLo := lCursor; lHi := lNext;
          while lHi - lLo > 1000 do
          begin
            lMiddle := ((lLo + lHi) div 2000) * 1000;
            if RtlOffsetMs(lMiddle) = lBefore then lLo := lMiddle
            else lHi := lMiddle;
          end;
          if lHi < lEnd then
          begin
            CheckRtlSubsetTransition(lZone, lDirect, lProbe, lHi, lBefore, lAfter);
            Inc(lTransitions);
          end;
        end;
        lCursor := lNext;
      end;
      lSeed := (lSeed * 48271) mod 2147483647;
      CheckRtlSubsetUtc(lZone, lDirect, lProbe, lDay + (lSeed mod 86400) * 1000);
      Inc(lDays); Inc(lDay, cDayMs);
    end;
  finally
    CronEndZonePeriodMemo;
  end;
  Assert.AreEqual(14976, lDays, 'one fixed-seed UTC sample per calendar day, 2000-2040');
  System.WriteLn('RTL_SUBSET days=', lDays, ' transitions=', lTransitions, ' seed=20261118');
end;
{$ENDIF}

{$ENDIF}

end.

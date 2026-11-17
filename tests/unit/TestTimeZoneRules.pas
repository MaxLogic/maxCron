unit TestTimeZoneRules;
{$I maxCron.inc}

interface

uses
  {$IFDEF FPC}
  DUnitX.TestFramework
  {$ELSE}
  DUnitX.TestFramework
  {$ENDIF};

type
  [TestFixture]
  TTestTimeZoneRules = class
  public
    [Test] procedure GeneratedNeighbourhoods;
    [Test] procedure MergeAndFixed;
    [Test] procedure PeriodRangesZ5;
    [Test] procedure SearchOracleZ6;
    [Test] procedure SyntaxAndResolution;
  end;

implementation

uses
  {$IFDEF FPC}
  SysUtils,
  maxCron.Internal.TimeZone, maxCron.Internal.TZif, TestZoneFakes
  {$ELSE}
  System.SysUtils,
  maxCron.Internal.TimeZone, maxCron.Internal.TZif, TestZoneFakes
  {$ENDIF};

procedure TTestTimeZoneRules.GeneratedNeighbourhoods;
var
  k: Integer;
  d: Int64;
  lInitial, lBefore, lLocal, lLeft, lRight, lStep: Int64;
  lChanges: TArray<TZoneChange>;
  lChange: TZoneChange;
  lZone: ICronZoneRules;
  lExpected, lActual: TCronLocalMapping;
  lContext: string;
begin
  for k := 0 to 5 do
  begin
    lChanges := FakeZoneChanges(k, lInitial);
    lZone := CreateCronZone('fake', FakeZoneSource(k));
    lBefore := lInitial;
    for lChange in lChanges do
    begin
      for d in TArray<Int64>.Create(-1001, -1000, -999, -1, 0, 1, 999, 1000, 1001) do
      begin
        if d < 0 then lExpected.FirstUtcMs := lBefore else lExpected.FirstUtcMs := lChange.OffsetMs;
        Assert.AreEqual(lExpected.FirstUtcMs, lZone.UtcToLocalMs(lChange.UtcMs + d) - lChange.UtcMs - d);
      end;
      lLeft := lChange.UtcMs + lBefore;
      lRight := lChange.UtcMs + lChange.OffsetMs;
      if lLeft > lRight then
      begin
        lLocal := lLeft; lLeft := lRight; lRight := lLocal;
      end;
      lLocal := lLeft - 2000;
      while lLocal <= lRight + 2000 do
      begin
        lExpected := ReferenceMapping(lInitial, lChanges, lLocal);
        lActual := lZone.MapLocal(lLocal);
        lContext := Format('fake=%d local=%d', [k, lLocal]);
        Assert.AreEqual(Ord(lExpected.Kind), Ord(lActual.Kind), lContext);
        Assert.AreEqual(lExpected.FirstUtcMs, lActual.FirstUtcMs, lContext);
        Assert.AreEqual(lExpected.SecondUtcMs, lActual.SecondUtcMs, lContext);
        lStep := 1000;
        if (lLocal <= lLeft + 2000) or (lLocal >= lRight - 2000) then lStep := 1;
        Inc(lLocal, lStep);
      end;
      lBefore := lChange.OffsetMs;
    end;
  end;
end;

procedure TTestTimeZoneRules.MergeAndFixed;
var
  lChanges: TArray<TZoneChange>;
  lZone: ICronZoneRules;
  lPeriod: TCronZonePeriod;
  lMap: TCronLocalMapping;
  lUtc: Int64;
begin
  lUtc := ZoneMs(2026, 1, 1, 0);
  SetLength(lChanges, 3);
  lChanges[0].UtcMs := lUtc - 1000; lChanges[0].OffsetMs := 3600000;
  lChanges[1].UtcMs := lUtc; lChanges[1].OffsetMs := 3600000;
  lChanges[2].UtcMs := lUtc + 1000; lChanges[2].OffsetMs := 7200000;
  lZone := CreateCronZone('merge', TFakeZoneSource.Create(3600000, lChanges));
  lPeriod := lZone.GetPeriod(lUtc);
  Assert.AreEqual(cCronZoneUnboundedStart, lPeriod.StartUtcMs);
  Assert.AreEqual(lUtc + 1000, lPeriod.EndUtcMs);
  Assert.AreEqual(Int64(3600000), CronZoneMinOffsetMs(lZone, lUtc, lUtc + 1000));
  Assert.AreEqual(Int64(7200000), CronZoneMaxOffsetMs(lZone, lUtc, lUtc + 1000));
  lZone := CreateCronZone('fixed', TCronFixedZoneSource.Create(-18000000));
  lMap := lZone.MapLocal(lUtc);
  Assert.AreEqual(Ord(TCronLocalKind.clkUnique), Ord(lMap.Kind));
  Assert.AreEqual(lUtc + 18000000, lMap.FirstUtcMs);
  lPeriod := lZone.GetPeriod(lUtc);
  Assert.AreEqual(cCronZoneUnboundedEnd, lPeriod.EndUtcMs);
end;

procedure TTestTimeZoneRules.SyntaxAndResolution;
var
  s: string;
  lZone: ICronZoneRules;
  lName, lError: string;
begin
  for s in ['../etc/passwd', '/Europe/Warsaw', 'Europe//Warsaw', 'Europe/Warsaw/',
    'Europe\Warsaw', 'Europe/ Warsaw', 'Europe/..'] do Assert.IsFalse(IsCronZoneNameSyntax(s), s);
  Assert.IsFalse(IsCronZoneNameSyntax(StringOfChar('x', 256)));
  Assert.IsTrue(IsCronZoneNameSyntax('UTC+15'));
  Assert.IsTrue(TryResolveCronZone('Etc/GMT+5', '', lZone, lName, lError), lError);
  Assert.AreEqual(Int64(-18000000), lZone.GetPeriod(0).OffsetMs);
  Assert.IsTrue(TryResolveCronZone('Etc/GMT-14', '', lZone, lName, lError), lError);
  Assert.AreEqual(Int64(50400000), lZone.GetPeriod(0).OffsetMs);
  Assert.IsTrue(TryResolveCronZone('europe/WARSAW', ZoneFixtureRoot, lZone, lName, lError), lError);
  Assert.AreEqual('Europe/Warsaw', lName);
  Assert.IsFalse(TryResolveCronZone('Europe/Nowhere', ZoneFixtureRoot, lZone, lName, lError));
  Assert.IsTrue(Pos('no TZif file', lError) > 0, lError);
end;

procedure RunZoneProperties(const aSearch: Boolean);
var
  k: Integer;
  lName: string;
  lSource: ICronZoneRuleSource;
  lZone: ICronZoneRules;
  lChanges: TArray<TZoneChange>;
  lInitial, lChecks, lFrom, lTo: Int64;
  lWindow, lCalls: Integer;
  lPath, lError: string;
begin
  lChecks := 0;
  if aSearch then CheckZoneSearchLimits;
  lFrom := ZoneMs(2018, 1, 1, 0);
  lTo := ZoneMs(2029, 1, 1, 0);
  for k := 0 to 5 do
  begin
    lSource := FakeZoneSource(k);
    lChanges := FakeZoneChanges(k, lInitial);
    lZone := CreateCronZone('fake' + IntToStr(k), lSource);
    if aSearch then CheckZoneSearch(lZone, lInitial, lChanges, lFrom, lTo, lChecks, lWindow, lCalls)
    else CheckZoneRanges(lZone, lFrom, lTo, lChecks);
  end;
  for lName in ['Europe/Warsaw', 'America/New_York', 'Australia/Sydney', 'Australia/Lord_Howe',
    'America/Sao_Paulo', 'Antarctica/Troll', 'US/Eastern', 'Asia/Calcutta', 'Etc/UTC',
    'Synthetic/Version1', 'Synthetic/Version2', 'Synthetic/Version3', 'Synthetic/Version4',
    'Synthetic/Version5', 'Synthetic/Fat', 'Synthetic/Julian', 'Synthetic/Ordinal',
    'Synthetic/AllYear', 'Synthetic/Signed', 'Synthetic/Southern'] do
  begin
    Assert.IsTrue(TryLoadCronTzifFile(ZoneFixtureRoot, lName, lSource, lPath, lError), lError);
    lZone := CreateCronZone(lName, lSource);
    // The explicit-period oracle is built from the raw provider, independently of range/search code.
    ZoneSourceModel(lSource, ZoneMs(2017, 1, 1, 0), ZoneMs(2030, 1, 1, 0), lInitial, lChanges);
    if aSearch then CheckZoneSearch(lZone, lInitial, lChanges, lFrom, lTo, lChecks, lWindow, lCalls)
    else CheckZoneRanges(lZone, lFrom, lTo, lChecks);
  end;
  if not aSearch then
  begin
    SetLength(lChanges, 3);
    lChanges[0].UtcMs := ZoneMs(2026, 1, 1, 0);
    lChanges[0].OffsetMs := cCronZoneMaxAbsOffsetMs;
    lChanges[1].UtcMs := lChanges[0].UtcMs + 3600000;
    lChanges[1].OffsetMs := -cCronZoneMaxAbsOffsetMs;
    lChanges[2].UtcMs := lChanges[1].UtcMs + 3600000;
    lChanges[2].OffsetMs := cCronZoneMaxAbsOffsetMs;
    lZone := CreateCronZone('intersecting-gaps', TFakeZoneSource.Create(-cCronZoneMaxAbsOffsetMs, lChanges));
    CheckZoneRanges(lZone, lFrom, lTo, lChecks);
  end;
  Assert.IsTrue(lChecks > 0);
  Writeln('zone_property search=', aSearch, ' checks=', lChecks);
end;

procedure TTestTimeZoneRules.PeriodRangesZ5;
begin
  RunZoneProperties(False);
end;

procedure TTestTimeZoneRules.SearchOracleZ6;
begin
  RunZoneProperties(True);
end;

end.

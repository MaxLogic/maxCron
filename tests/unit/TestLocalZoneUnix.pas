unit TestLocalZoneUnix;
{$I maxCron.inc}

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestLocalZoneUnix = class
  public
    [Test] procedure SystemLocalFollowsEnvironment;
    [Test] procedure LocaltimeSymlinkRetarget;
    [Test] procedure MatchesGlibcLocal;
  end;

implementation

uses
  {$IFDEF FPC}
  Classes, DateUtils, SysUtils, System.IOUtils,
  {$ELSE}
  System.Classes, System.DateUtils, System.IOUtils, System.SysUtils,
  Posix.Unistd,
  {$ENDIF}
  maxCron.Internal.Platform, maxCron.Internal.TimeZone, maxCron.Plan,
  TestEnvironment, TestZoneFakes;

const
  cZoneRoot = '/usr/share/zoneinfo';
  cLocaltimePath = '/etc/localtime';
  cZoneTable = cZoneRoot + '/zone1970.tab';
  cUnixEpochMs = Int64(25569) * 86400000;
  cPosixCases: array[0..8] of string = (
    'CET-1CEST,M3.5.0,M10.5.0/3', 'EST5EDT,M3.2.0,M11.1.0',
    'AEST-10AEDT,M10.1.0,M4.1.0/3', '<+0330>-3:30', 'JST-9', 'UTC0',
    'IST-1GMT0,M10.5.0,M3.5.0/1', '<-03>3<-02>,M3.5.0/-2,M10.5.0/-1', 'XXX-5:45');
  {$IFNDEF MAXCRON_LONG_TESTS}
  cDefaultZones: array[0..9] of string = (
    'Europe/Warsaw', 'America/New_York', 'Australia/Lord_Howe', 'Europe/Dublin',
    'Africa/Casablanca', 'America/Santiago', 'Pacific/Apia', 'Asia/Tehran',
    'America/St_Johns', 'Antarctica/Troll');
  {$ENDIF}
  cGlibcAcceptedDifferences: array of string = [];

function FixturePath(const aName: string): string;
begin
  Result := TPath.Combine(ZoneFixtureRoot, aName);
end;

procedure ApplyTz(const aWasSet: Boolean; const aValue: string);
begin
  if aWasSet then
    SetTestEnvironmentVariable('TZ', aValue)
  else
    UnsetTestEnvironmentVariable('TZ');
end;

procedure TTestLocalZoneUnix.SystemLocalFollowsEnvironment;
var
  lSavedTz: TTestEnvSnapshot;
  lRules: ICronZoneRules;
  lUtc, lLocal, lOffsetUs: Int64;
begin
  lSavedTz := SaveTestEnvironmentVariable('TZ');
  try
    SetTestEnvironmentVariable('TZ', ':' + FixturePath('Europe/Warsaw'));
    ForceCronLocalRecheckForTests;
    lRules := CronSystemZoneRules;
    Assert.AreEqual<Int64>(3600000, lRules.GetPeriod(ZoneMs(2026, 1, 15, 0)).OffsetMs);
    Assert.AreEqual<Int64>(7200000, lRules.GetPeriod(ZoneMs(2026, 7, 15, 0)).OffsetMs);
    lUtc := CronPreciseUtcNowUs;
    lLocal := CronPreciseLocalNowUs;
    lOffsetUs := lRules.GetPeriod(CronFloorDiv(lUtc, 1000)).OffsetMs * 1000;
    Assert.IsTrue(Abs(lLocal - lUtc - lOffsetUs) <= 1000000, 'Warsaw wall-clock offset');

    SetTestEnvironmentVariable('TZ', 'UTC0');
    ForceCronLocalRecheckForTests;
    Assert.AreEqual<Int64>(0, CronSystemZoneRules.GetPeriod(ZoneMs(2026, 7, 15, 0)).OffsetMs);
    lUtc := CronPreciseUtcNowUs;
    lLocal := CronPreciseLocalNowUs;
    Assert.IsTrue(Abs(lLocal - lUtc) <= 1000000, 'UTC wall-clock offset');
  finally
    RestoreTestEnvironmentVariable(lSavedTz);
    ForceCronLocalRecheckForTests;
    CronSystemZoneRules;
  end;
end;

procedure TTestLocalZoneUnix.LocaltimeSymlinkRetarget;
var
  lRoot, lLink: string;
  lZone: ICronTimeZone;
  lProvider: ICronTimeZoneRules;
  lBefore, lAfter: ICronZoneRules;
begin
  lRoot := TPath.Combine(TPath.GetTempPath, TPath.GetRandomFileName);
  TDirectory.CreateDirectory(lRoot);
  lLink := TPath.Combine(lRoot, 'localtime');
  try
    TestLibcSymlink(FixturePath('Europe/Warsaw'), lLink);
    lZone := CreateCronTzifLocalTimeZoneForTests(
      function: TCronLocalInputs
      begin
        Result.TzSet := False;
        Result.Tz := '';
        Result.ZoneRoot := cZoneRoot;
        Result.LocaltimePath := lLink;
      end, 0);
    lProvider := lZone as ICronTimeZoneRules;
    lBefore := lProvider.GetRules;
    Assert.AreEqual<Int64>(3600000, lBefore.GetPeriod(ZoneMs(2026, 1, 15, 0)).OffsetMs);
    Assert.IsTrue(lBefore = lProvider.GetRules, 'Unchanged symlink keeps rules identity');

    Assert.IsTrue(DeleteFile(lLink), 'Remove Warsaw symlink');
    TestLibcSymlink(FixturePath('America/New_York'), lLink);
    lAfter := lProvider.GetRules;
    Assert.AreEqual<Int64>(-18000000, lAfter.GetPeriod(ZoneMs(2026, 1, 15, 0)).OffsetMs);
    Assert.IsTrue(lBefore <> lAfter, 'Retargeted symlink changes rules identity');
  finally
    if FileExists(lLink) then
      Assert.IsTrue(DeleteFile(lLink), 'Remove localtime symlink');
    TDirectory.Delete(lRoot);
  end;
end;

procedure TTestLocalZoneUnix.MatchesGlibcLocal;
var
  lStart, lEnd, lChecks, lMismatches, lCases: Int64;
  lValue, lReport: string;
  lSavedTz: TTestEnvSnapshot;
  {$IFDEF MAXCRON_LONG_TESTS}
  lTable: TStringList;
  lLine, lZone: string;
  lFirstTab, lSecondTab, lThirdTab: Integer;
  {$ENDIF}

  procedure CompareCase(const aTzSet: Boolean; const aTz: string);
  var
    lRules: ICronZoneRules;
    lZone: ICronTimeZone;
    lAt, lBoundary: Int64;

    procedure CompareAt(const aAt: Int64);
    var
      lOurs, lGlibc: Int64;
      lCase, lMismatch, lAccepted: string;
    begin
      Inc(lChecks);
      lOurs := (lRules.UtcToLocalMs(aAt) - aAt) div 1000;
      lGlibc := TestLibcLocaltimeOffsetSeconds((aAt - cUnixEpochMs) div 1000);
      if lOurs = lGlibc then
        Exit;
      if aTzSet then
        lCase := QuotedStr(aTz)
      else
        lCase := 'TZ unset';
      lMismatch := Format('%s %s %d %d', [lCase,
        FormatDateTime('yyyy-mm-dd"T"hh:nn:ss"Z"', CronMsToDateTime(aAt)), lOurs, lGlibc]);
      for lAccepted in cGlibcAcceptedDifferences do
        if lMismatch = lAccepted then
          Exit;
      Inc(lMismatches);
      if lMismatches <= 20 then
        lReport := lReport + sLineBreak + lMismatch;
    end;

  begin
    Inc(lCases);
    ApplyTz(aTzSet, aTz);
    TestLibcTzset;
    lZone := CreateCronTzifLocalTimeZoneForTests(
      function: TCronLocalInputs
      begin
        Result.TzSet := aTzSet;
        Result.Tz := aTz;
        Result.ZoneRoot := cZoneRoot;
        Result.LocaltimePath := cLocaltimePath;
      end, 0);
    lRules := (lZone as ICronTimeZoneRules).GetRules;
    lAt := lStart;
    while lAt < lEnd do
    begin
      CompareAt(lAt);
      Inc(lAt, 900000);
    end;
    lBoundary := lRules.GetPeriod(lStart).StartUtcMs;
    if lBoundary < lStart then
      lBoundary := lRules.GetPeriod(lStart).EndUtcMs;
    while lBoundary < lEnd do
    begin
      CompareAt(lBoundary - 1000);
      CompareAt(lBoundary);
      lAt := lRules.GetPeriod(lBoundary).EndUtcMs;
      Assert.IsTrue(lAt > lBoundary, 'Zone periods must advance');
      lBoundary := lAt;
    end;
  end;

begin
  Assert.IsFalse(TryGetTestEnvironmentVariable('TZDIR', lValue), 'TZDIR must be unset');
  Assert.IsFalse(TryGetTestEnvironmentVariable('MAXCRON_TZDIR', lValue), 'MAXCRON_TZDIR must be unset');
  Assert.IsTrue(FileExists(cZoneTable), cZoneTable);
  Assert.IsTrue(FileExists(cLocaltimePath), cLocaltimePath);
  {$IFDEF MAXCRON_LONG_TESTS}
  lStart := ZoneMs(2000, 1, 1, 0);
  lEnd := ZoneMs(2041, 1, 1, 0);
  {$ELSE}
  lStart := ZoneMs(2024, 1, 1, 0);
  lEnd := ZoneMs(2029, 1, 1, 0);
  {$ENDIF}
  lChecks := 0;
  lMismatches := 0;
  lCases := 0;
  lSavedTz := SaveTestEnvironmentVariable('TZ');
  try
    CompareCase(False, '');
    CompareCase(True, ':' + cLocaltimePath);
    {$IFDEF MAXCRON_LONG_TESTS}
    lTable := TStringList.Create;
    try
      lTable.LoadFromFile(cZoneTable);
      for lLine in lTable do
      begin
        if (lLine = '') or (lLine[1] = '#') then
          Continue;
        lFirstTab := Pos(#9, lLine);
        lSecondTab := Pos(#9, lLine, lFirstTab + 1);
        Assert.IsTrue((lFirstTab > 0) and (lSecondTab > lFirstTab), 'Invalid zone1970.tab row');
        lThirdTab := Pos(#9, lLine, lSecondTab + 1);
        if lThirdTab = 0 then
          lThirdTab := Length(lLine) + 1;
        lZone := Copy(lLine, lSecondTab + 1, lThirdTab - lSecondTab - 1);
        Assert.IsTrue(lZone <> '', 'Empty zone1970.tab identity');
        CompareCase(True, lZone);
      end;
    finally
      lTable.Free;
    end;
    {$ELSE}
    for lValue in cDefaultZones do
      CompareCase(True, lValue);
    {$ENDIF}
    CompareCase(True, ':' + cZoneRoot + '/Asia/Kolkata');
    for lValue in cPosixCases do
      CompareCase(True, lValue);
    CompareCase(True, '');
  finally
    RestoreTestEnvironmentVariable(lSavedTz);
    TestLibcTzset;
  end;
  System.WriteLn(ErrOutput, Format('GLIBC_LOCAL cases=%d checks=%d mismatches=%d',
    [lCases, lChecks, lMismatches]));
  System.Flush(ErrOutput);
  Assert.AreEqual<Int64>(0, lMismatches, Format('%d mismatches%s', [lMismatches, lReport]));
end;

initialization
  TDUnitX.RegisterTestFixture(TTestLocalZoneUnix);

end.

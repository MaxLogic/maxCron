unit TestTimeZoneWindows;
{$I maxCron.inc}
{$IFDEF FPC}{$CODEPAGE UTF8}{$ENDIF}

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestTimeZoneWindows = class
  public
    [Test] procedure RealZoneTransitions;
    [Test] procedure OsRegressionInstants;
    [Test] procedure AllZonesFollowOs;
    [Test] procedure NamesAndProviderSelection;
    [Test] procedure UnknownNamePreservesEvent;
    [Test] procedure YearBoundaryPeriods;
    [TestCase('Casablanca2019', 'Africa/Casablanca,2019,0')]
    [TestCase('Barnaul2011', 'Asia/Barnaul,2011,21600000')]
    procedure JanuaryFirstTransitions(const aZoneName: string; const aYear, aOffsetMs: Integer);
  end;

implementation

uses
  {$IFDEF FPC}
  Classes, DateUtils, SysUtils,
  Windows,
  {$ELSE}
  System.Classes, System.DateUtils, System.SysUtils,
  Winapi.Windows,
  {$ENDIF}
  maxCron, maxCron.Internal.TimeZone, maxCron.Plan, TestZoneFakes;

{$I maxCron.Internal.TimeZoneNames.inc}

type
  TZoneRow = record
    Zone: Integer;
    UtcMs, OffsetMs: Int64;
  end;
  TZoneTransition = record
    Zone: Integer;
    UtcMs, BeforeMs, AfterMs: Int64;
  end;

{$I TestTimeZoneReference.inc}

const
  cZoneNames: array[0..4] of string = ('Europe/Warsaw', 'America/New_York', 'Australia/Sydney',
    'Australia/Lord_Howe', 'America/Sao_Paulo');

procedure TTestTimeZoneWindows.AllZonesFollowOs;
type
  TEnumZone = function(aIndex: DWORD; out aInfo: TCronWindowsDynamicInfo): DWORD; stdcall;
  TForward = function(const aInfo: TCronWindowsDynamicInfo; const aUtc: TCronWindowsSystemTime;
    out aLocal: TCronWindowsSystemTime): LongBool; stdcall;
var
  lEnum: TEnumZone;
  lForward: TForward;
  lInfo: TCronWindowsDynamicInfo;
  lSource: ICronZoneRuleSource;
  lStats: ICronWindowsZoneSourceStats;
  lZone: ICronZoneRules;
  lSeen: TStringList;
  lNormalized, lError: string;
  lIndex: DWORD;
  i, y, k: Integer;
  t, lEnd, lStart: Int64;
  lPeriod: TCronZonePeriod;
  procedure Probe(const aInstant: Int64);
  var
    lNative: TSystemTime;
    lUtc, lLocal: TCronWindowsSystemTime;
    lExpected: Int64;
  begin
    DateTimeToSystemTime(CronMsToDateTime(aInstant), lNative);
    Move(lNative, lUtc, SizeOf(lUtc));
    Assert.IsTrue(lForward(lInfo, lUtc, lLocal), cCronZoneNames[i].Name);
    lExpected := CronDateTimeToMs(EncodeDateTime(lLocal.wYear, lLocal.wMonth, lLocal.wDay,
      lLocal.wHour, lLocal.wMinute, lLocal.wSecond, lLocal.wMilliseconds)) - aInstant;
    Assert.AreEqual(lExpected, lSource.GetRawPeriod(aInstant).OffsetMs,
      cCronZoneNames[i].Name + ' UTC ms ' + IntToStr(aInstant));
  end;
begin
  lEnum := TEnumZone(GetProcAddress(GetModuleHandleW('advapi32.dll'), 'EnumDynamicTimeZoneInformation'));
  lForward := TForward(GetProcAddress(GetModuleHandleW('kernel32.dll'), 'SystemTimeToTzSpecificLocalTimeEx'));
  Assert.IsTrue(Assigned(lEnum) and Assigned(lForward), 'Windows conversion APIs');
  lSeen := TStringList.Create;
  try
    lSeen.Sorted := True;
    for i := 0 to High(cCronZoneNames) do
    begin
      Assert.IsTrue(TryResolveCronZone(cCronZoneNames[i].Name, '', lZone, lNormalized, lError), lError);
      Assert.AreEqual(cCronZoneNames[i].Name, lNormalized);
      if (cCronZoneNames[i].WindowsId = '') or (lSeen.IndexOf(cCronZoneNames[i].WindowsId) >= 0) then Continue;
      lSeen.Add(cCronZoneNames[i].WindowsId);
      lIndex := 0;
      repeat
        Assert.AreEqual<DWORD>(0, lEnum(lIndex, lInfo), cCronZoneNames[i].WindowsId);
        Inc(lIndex);
      until string(PWideChar(@lInfo.TimeZoneKeyName[0])) = cCronZoneNames[i].WindowsId;
      lInfo.DynamicDaylightTimeDisabled := 0;
      lSource := CreateCronNamedWindowsSourceForTests(cCronZoneNames[i].WindowsId);
      Assert.IsTrue(Supports(lSource, ICronWindowsZoneSourceStats, lStats));
      for y := 2000 to 2050 do
      begin
        lStart := CronDateTimeToMs(EncodeDate(y, 1, 1));
        lEnd := CronDateTimeToMs(EncodeDate(y + 1, 1, 1));
        t := lStart;
        repeat
          lPeriod := lSource.GetRawPeriod(t);
          Probe(t - 1000);
          Probe(t);
          t := lPeriod.EndUtcMs;
        until t >= lEnd;
        for k := 1 to 2 do
          Probe(lStart + ((Int64(20261117) + Int64(y) * 7919 * k) mod ((lEnd - lStart) div 1000)) * 1000);
        Assert.AreEqual(Int64(0), lStats.UnexpectedChanges,
          cCronZoneNames[i].Name + ' unexpected change, year ' + IntToStr(y));
      end;
    end;
  finally
    lSeen.Free;
  end;
end;

procedure TTestTimeZoneWindows.OsRegressionInstants;
type
  TEnumZone = function(aIndex: DWORD; out aInfo: TCronWindowsDynamicInfo): DWORD; stdcall;
  TForward = function(const aInfo: TCronWindowsDynamicInfo; const aUtc: TCronWindowsSystemTime;
    out aLocal: TCronWindowsSystemTime): LongBool; stdcall;
const
  cNames: array[0..3] of string = ('Africa/Cairo', 'America/Campo_Grande', 'Africa/Casablanca', 'Pacific/Apia');
  cIds: array[0..3] of string = ('Egypt Standard Time', 'Central Brazilian Standard Time',
    'Morocco Standard Time', 'Samoa Standard Time');
  cRows: array[0..9, 0..3] of Int64 = (
    (0, 19700924, 205959999, 10800000), (0, 19700924, 210000000, 7200000),
    (1, 19710101, 25959000, -10800000), (1, 19710101, 30000000, -14400000),
    (1, 19710107, 25959000, -14400000),
    (2, 20251231, 225959000, 3600000), (2, 20251231, 230000000, 0),
    (3, 20111231, 110000000, -36000000), (3, 20120101, 95959000, -36000000),
    (3, 20120101, 100000000, 50400000));
var
  lEnum: TEnumZone;
  lForward: TForward;
  lInfo: TCronWindowsDynamicInfo;
  lUtc, lLocal: TCronWindowsSystemTime;
  lNative: TSystemTime;
  lZone: ICronZoneRules;
  lNormalized, lError: string;
  lIndex: DWORD;
  i, d, t, z: Integer;
  lInstant, lSecond, lExpected: Int64;
begin
  lEnum := TEnumZone(GetProcAddress(GetModuleHandleW('advapi32.dll'), 'EnumDynamicTimeZoneInformation'));
  lForward := TForward(GetProcAddress(GetModuleHandleW('kernel32.dll'), 'SystemTimeToTzSpecificLocalTimeEx'));
  Assert.IsTrue(Assigned(lEnum) and Assigned(lForward), 'Windows 8 conversion APIs');
  for i := 0 to High(cRows) do
  begin
    z := cRows[i, 0]; d := cRows[i, 1]; t := cRows[i, 2];
    lInstant := CronDateTimeToMs(EncodeDateTime(d div 10000, d div 100 mod 100, d mod 100,
      t div 10000000, t div 100000 mod 100, t div 1000 mod 100, t mod 1000));
    lSecond := CronFloorDiv(lInstant, 1000) * 1000;
    lIndex := 0;
    repeat
      Assert.AreEqual<DWORD>(0, lEnum(lIndex, lInfo), cIds[z]);
      Inc(lIndex);
    until string(PWideChar(@lInfo.TimeZoneKeyName[0])) = cIds[z];
    lInfo.DynamicDaylightTimeDisabled := 0;
    DateTimeToSystemTime(CronMsToDateTime(lSecond), lNative);
    Move(lNative, lUtc, SizeOf(lUtc));
    Assert.IsTrue(lForward(lInfo, lUtc, lLocal));
    lExpected := CronDateTimeToMs(EncodeDateTime(lLocal.wYear, lLocal.wMonth, lLocal.wDay,
      lLocal.wHour, lLocal.wMinute, lLocal.wSecond, lLocal.wMilliseconds)) - lSecond;
    Assert.AreEqual(cRows[i, 3], lExpected, cNames[z] + ' OS row ' + IntToStr(i));
    Assert.IsTrue(TryResolveCronZone(cNames[z], '', lZone, lNormalized, lError), lError);
    Assert.AreEqual(lExpected, lZone.GetPeriod(lInstant).OffsetMs, cNames[z] + ' row ' + IntToStr(i));
  end;
end;

procedure TTestTimeZoneWindows.RealZoneTransitions;
var
  lZones: array[0..4] of ICronZoneRules;
  lName, lError: string;
  i: Integer;
begin
  ClearCronZonesForTests;
  for i := 0 to High(lZones) do
    Assert.IsTrue(TryResolveCronZone(cZoneNames[i], '', lZones[i], lName, lError), lError);
  for i := 0 to High(cZoneRows) do
    Assert.AreEqual(cZoneRows[i].OffsetMs, lZones[cZoneRows[i].Zone].GetPeriod(cZoneRows[i].UtcMs).OffsetMs,
      cZoneNames[cZoneRows[i].Zone] + ' probe ' + IntToStr(i));
  for i := 0 to High(cZoneTransitions) do
  begin
    Assert.AreEqual(cZoneTransitions[i].UtcMs,
      lZones[cZoneTransitions[i].Zone].GetPeriod(cZoneTransitions[i].UtcMs).StartUtcMs);
    Assert.AreEqual(cZoneTransitions[i].UtcMs,
      lZones[cZoneTransitions[i].Zone].GetPeriod(cZoneTransitions[i].UtcMs - 1).EndUtcMs);
  end;
end;

procedure TTestTimeZoneWindows.NamesAndProviderSelection;
var
  lZone: ICronZoneRules;
  lName, lError: string;
begin
  ClearCronZonesForTests;
  Assert.IsTrue(TryResolveCronZone('europe/warsaw', '', lZone, lName, lError), lError);
  Assert.AreEqual('Europe/Warsaw', lName);
  Assert.IsTrue(TryResolveCronZone('us/eastern', '', lZone, lName, lError), lError);
  Assert.AreEqual('US/Eastern', lName);
  Assert.IsTrue(TryResolveCronZone('asia/calcutta', '', lZone, lName, lError), lError);
  Assert.AreEqual('Asia/Calcutta', lName);
  Assert.IsTrue(TryResolveCronZone('etc/gmt+5', '', lZone, lName, lError), lError);
  Assert.AreEqual(Int64(-18000000), lZone.GetPeriod(4000000000000).OffsetMs);
  Assert.IsTrue(TryResolveCronZone('europe/warsaw', ZoneFixtureRoot, lZone, lName, lError), lError);
  Assert.AreEqual('Europe/Warsaw', lName);
  Assert.IsFalse(TryResolveCronZone('Europe/Warsaw', ZoneFixtureRoot + '-missing', lZone, lName, lError));
  Assert.IsFalse(TryResolveCronZone('Central European Standard Time', '', lZone, lName, lError));
end;

procedure TTestTimeZoneWindows.YearBoundaryPeriods;
var
  lZone: ICronZoneRules;
  lName, lError: string;
  lPeriod: TCronZonePeriod;
  lFuture: Int64;
begin
  Assert.IsTrue(TryResolveCronZone('Africa/Cairo', '', lZone, lName, lError), lError);
  lPeriod := lZone.GetPeriod(CronDateTimeToMs(EncodeDate(2012, 1, 1)) - 3600000);
  lFuture := CronDateTimeToMs(EncodeDate(2014, 7, 11));
  Assert.AreEqual(Int64(7200000), lPeriod.OffsetMs);
  Assert.AreEqual(Int64(10800000), lZone.GetPeriod(lFuture).OffsetMs);
  Assert.IsTrue(lPeriod.EndUtcMs <= lFuture, 'A no-DST year must not hide later rule changes');
end;

procedure TTestTimeZoneWindows.JanuaryFirstTransitions(const aZoneName: string;
  const aYear, aOffsetMs: Integer);
var
  lZone: ICronZoneRules;
  lName, lError: string;
  lStart: Int64;
begin
  Assert.IsTrue(TryResolveCronZone(aZoneName, '', lZone, lName, lError), lError);
  lStart := CronDateTimeToMs(EncodeDate(aYear, 1, 1));
  Assert.AreEqual(Int64(aOffsetMs), lZone.GetPeriod(lStart).OffsetMs, aZoneName + ' Jan 1');
  Assert.AreEqual(Int64(aOffsetMs), lZone.GetPeriod(lStart + 2 * cCronMsPerDay).OffsetMs,
    'The Jan 1 transition must take effect even when its UTC instant precedes the rule year');
end;

procedure TTestTimeZoneWindows.UnknownNamePreservesEvent;
var
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
begin
  lCron := TmaxCron.Create(ctPortable);
  try
    lEvent := lCron.Add('windows-zone');
    lEvent.TimeZoneId := 'Europe/Warsaw';
    try
      lEvent.TimeZoneId := 'Unknown/Zone';
      Assert.Fail('Unknown name must raise');
    except
      on E: Exception do
        Assert.IsTrue(Pos('Unknown timezone', E.Message) > 0, E.Message);
    end;
    Assert.AreEqual('Europe/Warsaw', lEvent.TimeZoneId);
    lEvent := nil;
  finally
    lCron.Free;
  end;
end;

end.

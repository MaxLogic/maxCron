unit TestLocalZoneTzif;
{$I maxCron.inc}

interface

uses
  DUnitX.TestFramework,
  maxCron.Internal.TimeZone;

type
  [TestFixture]
  TTestLocalZoneTzif = class
  private
    fInputs: TCronLocalInputs;
    fTemp: string;
    procedure PrepareFiles;
    procedure RemoveFiles;
    function LocalZone(const aRecheckUs: Int64 = 0): ICronTimeZone;
  public
    [Test] procedure UnsetTzUsesLocaltimeFile;
    [Test] procedure UnsetTzMissingOrInvalidLocaltimeIsUtc;
    [Test] procedure EmptyTzIsUtc;
    [Test] procedure AbsolutePathTz;
    [Test] procedure ZoneNameTzUnderRoot;
    [Test] procedure PosixTzStrings;
    [Test] procedure UnsupportedOrInvalidTzIsUtc;
    [Test] procedure RecheckDetectsChangesAndKeepsIdentity;
    [Test] procedure RecheckIsThrottled;
    [Test] procedure ConcurrentRecheckReturnsCachedRules;
    [Test] procedure RecheckRecoversAfterInputException;
    [Test] procedure GeneratedRecheckInterleavings;
    [Test] procedure GapOverlapMatchesNamedZone;
    [Test] procedure RestartCatchUpAcrossTransition;
  end;

implementation

uses
  {$IFDEF FPC}
  Classes, SyncObjs, System.IOUtils, SysUtils,
  {$ELSE}
  System.Classes, System.IOUtils, System.SyncObjs, System.SysUtils,
  {$IFDEF LINUX} Posix.Unistd, {$ENDIF}
  {$ENDIF}
  maxCron, TestRestartCatchUp, TestZoneFakes;

const
  cWarsaw = 'Europe/Warsaw';
  cNewYork = 'America/New_York';
  cHourMs = Int64(3600000);

function Rules(const aZone: ICronTimeZone): ICronZoneRules;
var
  lProvider: ICronTimeZoneRules;
begin
  Assert.IsTrue(Supports(aZone, ICronTimeZoneRules, lProvider));
  Result := lProvider.GetRules;
  Assert.AreEqual('LOCAL', Result.GetName);
end;

function NamedWarsaw(const aRoot: string): ICronZoneRules;
var
  lName, lError: string;
begin
  Assert.IsTrue(TryResolveCronZone(cWarsaw, aRoot, Result, lName, lError), lError);
end;

procedure CheckPeriod(const aExpected, aActual: TCronZonePeriod);
begin
  Assert.AreEqual<Int64>(aExpected.StartUtcMs, aActual.StartUtcMs);
  Assert.AreEqual<Int64>(aExpected.EndUtcMs, aActual.EndUtcMs);
  Assert.AreEqual<Int64>(aExpected.OffsetMs, aActual.OffsetMs);
end;

procedure CheckMapping(const aExpected, aActual: TCronLocalMapping);
begin
  Assert.AreEqual(Ord(aExpected.Kind), Ord(aActual.Kind));
  Assert.AreEqual<Int64>(aExpected.FirstUtcMs, aActual.FirstUtcMs);
  Assert.AreEqual<Int64>(aExpected.SecondUtcMs, aActual.SecondUtcMs);
end;

procedure CheckOffset(const aZone: ICronZoneRules; const aUtcMs, aOffsetMs: Int64);
begin
  Assert.AreEqual<Int64>(aOffsetMs, aZone.UtcToLocalMs(aUtcMs) - aUtcMs);
end;

procedure CheckWarsaw(const aZone: ICronZoneRules);
begin
  CheckOffset(aZone, ZoneMs(2026, 1, 15, 12), cHourMs);
  CheckOffset(aZone, ZoneMs(2026, 7, 15, 12), 2 * cHourMs);
end;

function UnderRoot(const aRoot, aName: string): string;
begin
  Result := TPath.Combine(aRoot, StringReplace(aName, '/', PathDelim, [rfReplaceAll]));
end;

procedure CopyFileBytes(const aFrom, aTo: string);
var
  lSource, lTarget: TFileStream;
begin
  lSource := TFileStream.Create(aFrom, fmOpenRead or fmShareDenyWrite);
  try
    lTarget := TFileStream.Create(aTo, fmCreate);
    try
      lTarget.CopyFrom(lSource, 0);
    finally
      lTarget.Free;
    end;
  finally
    lSource.Free;
  end;
end;

procedure TTestLocalZoneTzif.PrepareFiles;
var
  lId: TGUID;
  lDir, lRoot: string;
begin
  fInputs := Default(TCronLocalInputs);
  lRoot := ZoneFixtureRoot;
  CreateGUID(lId);
  lDir := TPath.Combine(TPath.GetTempPath, 'maxcron-local-' + GUIDToString(lId));
  if not CreateDir(lDir) then RaiseLastOSError;
  fTemp := lDir;
  fInputs.ZoneRoot := fTemp;
  fInputs.LocaltimePath := TPath.Combine(fTemp, 'localtime');
  Assert.IsTrue(CreateDir(TPath.Combine(fTemp, 'Europe')));
  CopyFileBytes(UnderRoot(lRoot, cWarsaw), UnderRoot(fTemp, cWarsaw));
  CopyFileBytes(UnderRoot(lRoot, cWarsaw), fInputs.LocaltimePath);
  CopyFileBytes(UnderRoot(lRoot, cNewYork), TPath.Combine(fTemp, 'New_York'));
  TFile.WriteAllBytes(TPath.Combine(fTemp, 'garbage'), TBytes.Create(1, 2, 3));
end;

procedure TTestLocalZoneTzif.RemoveFiles;
var
  lName: string;
begin
  if fTemp = '' then Exit;
  for lName in [cWarsaw, 'New_York', 'garbage', 'localtime', 'UTC0'] do
    if FileExists(UnderRoot(fTemp, lName)) then
      Assert.IsTrue(DeleteFile(UnderRoot(fTemp, lName)), lName);
  lName := TPath.Combine(fTemp, 'Europe');
  if DirectoryExists(lName) then Assert.IsTrue(RemoveDir(lName), lName);
  Assert.IsTrue(RemoveDir(fTemp), fTemp);
  fTemp := '';
end;

function TTestLocalZoneTzif.LocalZone(const aRecheckUs: Int64): ICronTimeZone;
begin
  Result := CreateCronTzifLocalTimeZoneForTests(
    function: TCronLocalInputs
    begin
      Result := fInputs;
    end, aRecheckUs);
end;

procedure TTestLocalZoneTzif.UnsetTzUsesLocaltimeFile;
var
  lZone: ICronTimeZone;
  lRules: ICronZoneRules;
begin
  try
    PrepareFiles;
    lZone := LocalZone;
    Assert.AreEqual('file:' + fInputs.LocaltimePath, CronTzifLocalOriginForTests(lZone));
    lRules := Rules(lZone);
    CheckWarsaw(lRules);
    Assert.AreEqual(Ord(clkGap), Ord(lRules.MapLocal(ZoneMs(2026, 3, 29, 2, 30)).Kind));
    Assert.AreEqual(Ord(clkOverlap), Ord(lRules.MapLocal(ZoneMs(2026, 10, 25, 2, 30)).Kind));
  finally
    RemoveFiles;
  end;
end;

procedure TTestLocalZoneTzif.UnsetTzMissingOrInvalidLocaltimeIsUtc;
var
  lZone: ICronTimeZone;
  lName: string;
begin
  try
    PrepareFiles;
    lZone := LocalZone;
    for lName in ['missing', 'garbage'] do
    begin
      fInputs.LocaltimePath := TPath.Combine(fTemp, lName);
      Assert.AreEqual('utc:no-localtime', CronTzifLocalOriginForTests(lZone));
      CheckOffset(Rules(lZone), ZoneMs(2026, 1, 15, 12), 0);
    end;
  finally
    RemoveFiles;
  end;
end;

procedure TTestLocalZoneTzif.EmptyTzIsUtc;
var
  lZone: ICronTimeZone;
  lTz: string;
begin
  fInputs := Default(TCronLocalInputs);
  fInputs.TzSet := True;
  lZone := LocalZone;
  for lTz in ['', ':'] do
  begin
    fInputs.Tz := lTz;
    Assert.AreEqual('utc:empty', CronTzifLocalOriginForTests(lZone));
    CheckOffset(Rules(lZone), ZoneMs(2026, 1, 15, 12), 0);
  end;
end;

procedure TTestLocalZoneTzif.AbsolutePathTz;
var
  lZone: ICronTimeZone;
  lPath, lTz: string;
  {$IFDEF MSWINDOWS}
  lPreviousDir: string;
  {$ENDIF}
begin
  try
    PrepareFiles;
    lPath := fInputs.LocaltimePath;
    {$IFDEF MSWINDOWS}
    // Slash-rooted paths use the current drive on Windows.
    lPreviousDir := GetCurrentDir;
    if not SetCurrentDir(fTemp) then RaiseLastOSError;
    try
      Delete(lPath, 1, Length(ExtractFileDrive(lPath)));
      lPath := StringReplace(lPath, PathDelim, '/', [rfReplaceAll]);
    {$ENDIF}
    fInputs.TzSet := True;
    fInputs.LocaltimePath := '';
    lZone := LocalZone;
    for lTz in [':' + lPath, lPath] do
    begin
      fInputs.Tz := lTz;
      Assert.AreEqual('file:' + lPath, CronTzifLocalOriginForTests(lZone));
      CheckWarsaw(Rules(lZone));
    end;
    {$IFDEF MSWINDOWS}
    finally
      if not SetCurrentDir(lPreviousDir) then RaiseLastOSError;
    end;
    {$ENDIF}
  finally
    RemoveFiles;
  end;
end;

procedure TTestLocalZoneTzif.ZoneNameTzUnderRoot;
var
  lZone: ICronTimeZone;
begin
  try
    PrepareFiles;
    fInputs.TzSet := True;
    fInputs.Tz := cWarsaw;
    lZone := LocalZone;
    Assert.AreEqual('zone:' + cWarsaw, CronTzifLocalOriginForTests(lZone));
    CheckWarsaw(Rules(lZone));

    fInputs.Tz := 'UTC0';
    Assert.AreEqual('posix:UTC0', CronTzifLocalOriginForTests(lZone));
    CopyFileBytes(TPath.Combine(fTemp, 'garbage'), TPath.Combine(fTemp, 'UTC0'));
    Assert.AreEqual('posix:UTC0', CronTzifLocalOriginForTests(lZone));
    CheckOffset(Rules(lZone), ZoneMs(2026, 1, 15, 12), 0);
    CopyFileBytes(UnderRoot(fTemp, cWarsaw), TPath.Combine(fTemp, 'UTC0'));
    Assert.AreEqual('zone:UTC0', CronTzifLocalOriginForTests(lZone));
    CheckWarsaw(Rules(lZone));
    fInputs.Tz := 'Europe/Missing';
    Assert.AreEqual('utc:invalid', CronTzifLocalOriginForTests(lZone));
  finally
    RemoveFiles;
  end;
end;

procedure TTestLocalZoneTzif.PosixTzStrings;
var
  lZone: ICronTimeZone;
  lRules, lWarsaw: ICronZoneRules;
  lPeriod: TCronZonePeriod;
  lAt, lWinter, lSummer: Int64;
  lCount: Integer;

  procedure CheckPosix(const aTz: string; const aWinter, aSummer: Int64);
  var
    lPosix: ICronZoneRules;
  begin
    fInputs.Tz := aTz;
    Assert.AreEqual('posix:' + aTz, CronTzifLocalOriginForTests(lZone));
    lPosix := Rules(lZone);
    CheckOffset(lPosix, lWinter, aWinter);
    CheckOffset(lPosix, lSummer, aSummer);
  end;

begin
  try
    PrepareFiles;
    fInputs.TzSet := True;
    lZone := LocalZone;
    lWinter := ZoneMs(2026, 1, 15, 12);
    lSummer := ZoneMs(2026, 7, 15, 12);
    CheckPosix('JST-9', 9 * cHourMs, 9 * cHourMs);
    CheckPosix('<+0330>-3:30', 7 * cHourMs div 2, 7 * cHourMs div 2);
    CheckPosix('UTC0', 0, 0);
    CheckPosix('IST-1GMT0,M10.5.0,M3.5.0/1', 0, cHourMs);
    fInputs.Tz := 'CET-1CEST,M3.5.0,M10.5.0/3';
    Assert.AreEqual('posix:' + fInputs.Tz, CronTzifLocalOriginForTests(lZone));
    lRules := Rules(lZone);
    lWarsaw := NamedWarsaw(fTemp);
    lAt := lWarsaw.GetPeriod(ZoneMs(2030, 1, 1, 0)).EndUtcMs;
    lCount := 0;
    while lAt < ZoneMs(2041, 1, 1, 0) do
    begin
      CheckOffset(lRules, lAt - 1000, lWarsaw.GetPeriod(lAt - 1000).OffsetMs);
      lPeriod := lWarsaw.GetPeriod(lAt);
      CheckOffset(lRules, lAt, lPeriod.OffsetMs);
      CheckOffset(lRules, lAt + 1000, lPeriod.OffsetMs);
      Inc(lCount);
      lAt := lPeriod.EndUtcMs;
    end;
    Assert.AreEqual(22, lCount);
  finally
    RemoveFiles;
  end;
end;

procedure TTestLocalZoneTzif.UnsupportedOrInvalidTzIsUtc;
var
  lZone: ICronTimeZone;
  lTz: string;
begin
  try
    PrepareFiles;
    fInputs.TzSet := True;
    lZone := LocalZone;
    for lTz in ['EST5EDT', 'not a zone!', 'Europe', ':garbage', 'UTC0' + #127, 'UTC0' + #1] do
    begin
      fInputs.Tz := lTz;
      Assert.AreEqual('utc:invalid', CronTzifLocalOriginForTests(lZone), lTz);
      CheckOffset(Rules(lZone), ZoneMs(2026, 1, 15, 12), 0);
    end;
    // This relative path would reach the Warsaw fixture without the syntax guard.
    fInputs.ZoneRoot := TPath.Combine(fTemp, 'Europe');
    fInputs.Tz := '../Europe/Warsaw';
    Assert.AreEqual('utc:invalid', CronTzifLocalOriginForTests(lZone), fInputs.Tz);
    CheckOffset(Rules(lZone), ZoneMs(2026, 1, 15, 12), 0);
  finally
    RemoveFiles;
  end;
end;

procedure TTestLocalZoneTzif.RecheckDetectsChangesAndKeepsIdentity;
var
  lZone: ICronTimeZone;
  lOriginal, lRewritten, lPosix: ICronZoneRules;
  lAt: Int64;
begin
  try
    PrepareFiles;
    lZone := LocalZone;
    lAt := ZoneMs(2026, 1, 15, 12);
    lOriginal := Rules(lZone);
    CheckWarsaw(lOriginal);
    Assert.IsTrue(lOriginal = Rules(lZone), 'unchanged file');
    CopyFileBytes(TPath.Combine(fTemp, 'New_York'), fInputs.LocaltimePath);
    lRewritten := Rules(lZone);
    Assert.IsTrue(lOriginal <> lRewritten, 'changed bytes at same path');
    CheckOffset(lRewritten, lAt, -5 * cHourMs);
    Assert.IsTrue(lRewritten = Rules(lZone), 'unchanged rewritten file');

    fInputs.TzSet := True;
    fInputs.Tz := 'JST-9';
    lPosix := Rules(lZone);
    Assert.IsTrue(lPosix <> lRewritten, 'changed TZ');
    CheckOffset(lPosix, lAt, 9 * cHourMs);
    Assert.IsTrue(lPosix = Rules(lZone), 'unchanged POSIX TZ');
  finally
    RemoveFiles;
  end;
end;

procedure TTestLocalZoneTzif.RecheckIsThrottled;
var
  lZone: ICronTimeZone;
  lBefore, lAfter: ICronZoneRules;
begin
  try
    PrepareFiles;
    lZone := LocalZone(cHourMs * 1000);
    lBefore := Rules(lZone);
    fInputs.TzSet := True;
    fInputs.Tz := 'UTC0';
    CopyFileBytes(TPath.Combine(fTemp, 'New_York'), fInputs.LocaltimePath);
    lAfter := Rules(lZone);
    Assert.IsTrue(lBefore = lAfter);
    Assert.AreEqual('file:' + fInputs.LocaltimePath, CronTzifLocalOriginForTests(lZone));
    CheckWarsaw(lAfter);
  finally
    RemoveFiles;
  end;
end;

procedure TTestLocalZoneTzif.ConcurrentRecheckReturnsCachedRules;
const
  cWaitMs = 5000;
var
  lZone: ICronTimeZone;
  lProvider: ICronTimeZoneRules;
  lCached, lOwnerRules, lContenderRules: ICronZoneRules;
  lOwnerEntered, lReadNew, lContenderReady, lReleaseOld: TEvent;
  lOwnerDone, lContenderDone: TEvent;
  lOwner, lContender: TThread;
  lReadCount, lReadsBeforeRace: Integer;
begin
  lOwnerEntered := nil;
  lReadNew := nil;
  lContenderReady := nil;
  lReleaseOld := nil;
  lOwnerDone := nil;
  lContenderDone := nil;
  lOwner := nil;
  lContender := nil;
  lReadCount := 0;
  lReadsBeforeRace := -1;
  try
    lOwnerEntered := TEvent.Create(nil, True, False, '');
    lReadNew := TEvent.Create(nil, True, False, '');
    lContenderReady := TEvent.Create(nil, True, False, '');
    lReleaseOld := TEvent.Create(nil, True, False, '');
    lOwnerDone := TEvent.Create(nil, True, False, '');
    lContenderDone := TEvent.Create(nil, True, False, '');

    lZone := CreateCronTzifLocalTimeZoneForTests(
      function: TCronLocalInputs
      begin
        Result := Default(TCronLocalInputs);
        Result.TzSet := True;
        Inc(lReadCount);
        if lReadsBeforeRace < 0 then
          Result.Tz := 'CST6'
        else if lReadCount = lReadsBeforeRace + 1 then
        begin
          lOwnerEntered.SetEvent;
          if lReadNew.WaitFor(2 * cWaitMs) <> wrSignaled then
            raise Exception.Create('Timed out waiting to read the new TZ');
          Result.Tz := 'JST-9';
        end else if lOwnerDone.WaitFor(0) = wrSignaled then
          Result.Tz := 'JST-9'
        else begin
          // On the old resolver the contender captures stale inputs here.
          Result.Tz := '::invalid';
          lContenderReady.SetEvent;
          if lReleaseOld.WaitFor(2 * cWaitMs) <> wrSignaled then
            raise Exception.Create('Timed out waiting to finish the stale read');
        end;
      end, 0);
    Assert.IsTrue(Supports(lZone, ICronTimeZoneRules, lProvider));
    lCached := lProvider.GetRules;
    CheckOffset(lCached, 0, -6 * cHourMs);
    lReadsBeforeRace := lReadCount;

    lOwner := TThread.CreateAnonymousThread(
      procedure
      begin
        try
          lOwnerRules := lProvider.GetRules;
        finally
          lOwnerDone.SetEvent;
        end;
      end);
    lOwner.FreeOnTerminate := False;
    lOwner.Start;
    Assert.IsTrue(lOwnerEntered.WaitFor(cWaitMs) = wrSignaled, 'Recheck owner did not enter the provider');

    lContender := TThread.CreateAnonymousThread(
      procedure
      begin
        try
          lContenderRules := lProvider.GetRules;
        finally
          lContenderDone.SetEvent;
          lContenderReady.SetEvent;
        end;
      end);
    lContender.FreeOnTerminate := False;
    lContender.Start;
    Assert.IsTrue(lContenderReady.WaitFor(cWaitMs) = wrSignaled, 'Contender blocked on the recheck');

    // Let the earlier entrant publish the new TZ before a stale read can finish.
    lReadNew.SetEvent;
    Assert.IsTrue(lOwnerDone.WaitFor(cWaitMs) = wrSignaled, 'Owner did not finish the recheck');
    lReleaseOld.SetEvent;
    Assert.IsTrue(lContenderDone.WaitFor(cWaitMs) = wrSignaled, 'Contender did not finish');
    Assert.IsTrue(lOwnerRules <> nil);
    Assert.IsTrue(lContenderRules <> nil);
    CheckOffset(lOwnerRules, 0, 9 * cHourMs);
    Assert.IsTrue(lContenderRules = lCached, 'Concurrent recheck replaced the cached rules');
    Assert.AreEqual(lReadsBeforeRace + 1, lReadCount, 'Contender called the input provider');
    Assert.IsTrue(lProvider.GetRules = lOwnerRules, 'Unchanged JST-9 rules lost their identity');
  finally
    if Assigned(lReadNew) then lReadNew.SetEvent;
    if Assigned(lReleaseOld) then lReleaseOld.SetEvent;
    lContender.Free;
    lOwner.Free;
    // The FPC closures share a frame that captures the provider.
    lProvider := nil;
    lZone := nil;
    lContenderDone.Free;
    lOwnerDone.Free;
    lReleaseOld.Free;
    lContenderReady.Free;
    lReadNew.Free;
    lOwnerEntered.Free;
  end;
end;

procedure TTestLocalZoneTzif.RecheckRecoversAfterInputException;
var
  lZone: ICronTimeZone;
  lBefore, lAfter: ICronZoneRules;
  lTz: string;
  lRaise: Boolean;
begin
  lTz := 'JST-9';
  lRaise := False;
  lZone := CreateCronTzifLocalTimeZoneForTests(
    function: TCronLocalInputs
    begin
      if lRaise then raise Exception.Create('Injected input failure');
      Result := Default(TCronLocalInputs);
      Result.TzSet := True;
      Result.Tz := lTz;
    end, 0);
  lBefore := Rules(lZone);
  CheckOffset(lBefore, 0, 9 * cHourMs);
  lRaise := True;
  Assert.IsTrue(Rules(lZone) = lBefore, 'Provider failure replaced the cached rules');

  lRaise := False;
  lTz := 'UTC0';
  lAfter := Rules(lZone);
  Assert.IsTrue(lAfter <> lBefore, 'Provider failure prevented the next recheck');
  CheckOffset(lAfter, 0, 0);
  Assert.IsTrue(lAfter = Rules(lZone), 'Unchanged UTC0 rules lost their identity');
end;

type
  TLocalZoneInputKind = (zikWarsaw, zikNewYork, zikPosix, zikInvalid, zikRaise);

  TLocalZoneInputsScript = class
  private
    fInputs: TCronLocalInputs;
    fLock: TCriticalSection;
    fReadEntered, fReleaseRead, fReadTimedOut: TEvent;
    fKind: TLocalZoneInputKind;
    fPause: Boolean;
    fReads: Integer;
  public
    constructor Create(const aInputs: TCronLocalInputs);
    destructor Destroy; override;
    procedure Stage(aKind: TLocalZoneInputKind; aPause: Boolean);
    function ReadInputs: TCronLocalInputs;
  end;

  PLocalZoneCall = ^TLocalZoneCall;
  TLocalZoneCall = record
    Done: TEvent;
    Worker: TThread;
    Rules: ICronZoneRules;
    Origin: string;
  end;

const
  cScheduleSeed = Cardinal($6B53A430);
  cScheduleCount = 24;
  cScheduleWaitMs = 5000;
  cScheduleOffset: array[zikWarsaw..zikInvalid] of Int64 =
    (cHourMs, -5 * cHourMs, 9 * cHourMs, 0);

constructor TLocalZoneInputsScript.Create(const aInputs: TCronLocalInputs);
begin
  inherited Create;
  fInputs := aInputs;
  fLock := TCriticalSection.Create;
  fReadEntered := TEvent.Create(nil, True, False, '');
  fReleaseRead := TEvent.Create(nil, True, False, '');
  fReadTimedOut := TEvent.Create(nil, True, False, '');
end;

destructor TLocalZoneInputsScript.Destroy;
begin
  fReadTimedOut.Free;
  fReleaseRead.Free;
  fReadEntered.Free;
  fLock.Free;
  inherited;
end;

procedure TLocalZoneInputsScript.Stage(aKind: TLocalZoneInputKind; aPause: Boolean);
begin
  fKind := aKind;
  fPause := aPause;
  fReadEntered.ResetEvent;
  fReleaseRead.ResetEvent;
end;

function TLocalZoneInputsScript.ReadInputs: TCronLocalInputs;
const
  cTz: array[zikWarsaw..zikInvalid] of string = (cWarsaw, 'New_York', 'JST-9', '::invalid');
var
  lKind: TLocalZoneInputKind;
begin
  fLock.Acquire;
  try
    Inc(fReads);
  finally
    fLock.Release;
  end;
  lKind := fKind;
  if fPause then
  begin
    fReadEntered.SetEvent;
    if fReleaseRead.WaitFor(2 * cScheduleWaitMs) <> wrSignaled then
    begin
      fReadTimedOut.SetEvent;
      raise Exception.Create('Timed out waiting to release the scripted input read');
    end;
  end;
  if lKind = zikRaise then
    raise Exception.Create('Scripted input failure');
  Result := fInputs;
  Result.TzSet := True;
  Result.Tz := cTz[lKind];
end;

function DrawScheduleValue(var aState: Cardinal; aLimit: Integer): Integer;
begin
  aState := aState xor (aState shl 13);
  aState := aState xor (aState shr 17);
  aState := aState xor (aState shl 5);
  Result := Integer(aState mod Cardinal(aLimit));
end;

procedure StartLocalZoneCall(aCall: PLocalZoneCall; const aProvider: ICronTimeZoneRules;
  const aZone: ICronTimeZone; aReadOrigin: Boolean);
var
  lProvider: ICronTimeZoneRules;
  lZone: ICronTimeZone;
begin
  // Keep strong references in the closure until the caller joins.
  lProvider := aProvider;
  lZone := aZone;
  aCall^.Done := TEvent.Create(nil, True, False, '');
  aCall^.Worker := TThread.CreateAnonymousThread(
    procedure
    begin
      try
        aCall^.Rules := lProvider.GetRules;
        if aReadOrigin then
          aCall^.Origin := CronTzifLocalOriginForTests(lZone);
      finally
        aCall^.Done.SetEvent;
      end;
    end);
  aCall^.Worker.FreeOnTerminate := False;
  aCall^.Worker.Start;
end;

procedure WaitForScheduleEvent(aEvent: TEvent; const aDescription: string);
begin
  Assert.IsTrue(aEvent.WaitFor(cScheduleWaitMs) = wrSignaled, aDescription);
end;

procedure CheckScheduledRules(const aRules: ICronZoneRules; aKind: TLocalZoneInputKind;
  const aDescription: string);
var
  lUtc: Int64;
begin
  Assert.IsTrue(aRules <> nil, aDescription + ' returned nil');
  Assert.AreEqual('LOCAL', aRules.GetName, aDescription);
  lUtc := ZoneMs(2026, 1, 15, 12);
  Assert.AreEqual<Int64>(cScheduleOffset[aKind], aRules.UtcToLocalMs(lUtc) - lUtc, aDescription);
end;

procedure RunLocalZoneWave(aScript: TLocalZoneInputsScript; const aProvider: ICronTimeZoneRules;
  const aZone: ICronTimeZone; aKind: TLocalZoneInputKind; aColdFallback: Boolean;
  var aPublishedKind: TLocalZoneInputKind; var aPublishedRules: ICronZoneRules;
  var aState: Cardinal; const aDescription: string);
var
  lCalls: array[0..3] of TLocalZoneCall;
  lCount, lOwner, lDirection, lSlot, lReadsBefore: Integer;
  i: Integer;
begin
  lCount := 2 + DrawScheduleValue(aState, 3);
  lOwner := DrawScheduleValue(aState, lCount);
  lDirection := 1 + DrawScheduleValue(aState, 2) * (lCount - 2);
  for i := 0 to lCount - 1 do
    lCalls[i] := Default(TLocalZoneCall);
  lReadsBefore := aScript.fReads;
  aScript.Stage(aKind, True);
  try
    StartLocalZoneCall(@lCalls[lOwner], aProvider, aZone, False);
    WaitForScheduleEvent(aScript.fReadEntered, aDescription + ': owner did not read inputs');

    for i := 1 to lCount - 1 do
    begin
      lSlot := (lOwner + i * lDirection) mod lCount;
      StartLocalZoneCall(@lCalls[lSlot], aProvider, aZone, aColdFallback and (i = 1));
    end;
    for i := 1 to lCount - 1 do
    begin
      lSlot := (lOwner + i * lDirection) mod lCount;
      WaitForScheduleEvent(lCalls[lSlot].Done, aDescription + ': contender blocked on the owner');
      CheckScheduledRules(lCalls[lSlot].Rules, aPublishedKind, aDescription + ': cached rules');
      if aColdFallback and (i = 1) then
        Assert.AreEqual('utc:invalid', lCalls[lSlot].Origin, aDescription + ': cold exception origin');
      if aPublishedRules = nil then
        aPublishedRules := lCalls[lSlot].Rules;
      Assert.IsTrue(lCalls[lSlot].Rules = aPublishedRules, aDescription + ': wrong cached instance');
    end;

    aScript.fReleaseRead.SetEvent;
    WaitForScheduleEvent(lCalls[lOwner].Done, aDescription + ': owner did not finish');
    Assert.IsTrue(aScript.fReadTimedOut.WaitFor(0) <> wrSignaled, aDescription + ': provider timed out');
    Assert.AreEqual(lReadsBefore + 1, aScript.fReads, aDescription + ': input-read sequence');
    if (aKind = zikRaise) or (aKind = aPublishedKind) then
      Assert.IsTrue(lCalls[lOwner].Rules = aPublishedRules, aDescription + ': lost instance identity')
    else begin
      Assert.IsTrue(lCalls[lOwner].Rules <> aPublishedRules, aDescription + ': expected a new publication');
      aPublishedKind := aKind;
    end;
    CheckScheduledRules(lCalls[lOwner].Rules, aPublishedKind, aDescription + ': owner rules');
    aPublishedRules := lCalls[lOwner].Rules;
  finally
    aScript.fReleaseRead.SetEvent;
    for i := 0 to lCount - 1 do
    begin
      lCalls[i].Worker.Free;
      lCalls[i].Done.Free;
    end;
  end;
end;

function CreateScriptedLocalZone(aScript: TLocalZoneInputsScript; aRecheckUs: Int64): ICronTimeZone;
begin
  Result := CreateCronTzifLocalTimeZoneForTests(
    function: TCronLocalInputs
    begin
      Result := aScript.ReadInputs;
    end, aRecheckUs);
end;

procedure RunLocalZoneSchedule(aScript: TLocalZoneInputsScript; var aState: Cardinal; aIndex: Integer);
var
  lZone: ICronTimeZone;
  lProvider: ICronTimeZoneRules;
  lPublishedRules: ICronZoneRules;
  lColdKind, lPublishedKind, lKind: TLocalZoneInputKind;
  lReadAtStart, lConstructionReads, lFirst, lStep: Integer;
  i: Integer;
  lDescription: string;
begin
  lColdKind := TLocalZoneInputKind(DrawScheduleValue(aState, 5));
  lPublishedKind := lColdKind;
  if lColdKind = zikRaise then
    lPublishedKind := zikInvalid;
  lReadAtStart := aScript.fReads;
  aScript.Stage(lColdKind, False);
  lZone := CreateScriptedLocalZone(aScript, 0);
  lConstructionReads := aScript.fReads - lReadAtStart;
  Assert.IsTrue(Supports(lZone, ICronTimeZoneRules, lProvider));

  // A rotation with a non-zero step visits all five scripted outcomes.
  lFirst := DrawScheduleValue(aState, 5);
  lStep := 1 + DrawScheduleValue(aState, 4);
  for i := 0 to 4 do
  begin
    lKind := TLocalZoneInputKind((lFirst + i * lStep) mod 5);
    lDescription := Format('seed %.8x schedule %d wave %d', [Integer(cScheduleSeed), aIndex, i]);
    RunLocalZoneWave(aScript, lProvider, lZone, lKind, (i = 0) and (lColdKind = zikRaise),
      lPublishedKind, lPublishedRules, aState, lDescription);
    if i = 0 then
      Assert.AreEqual(1, lConstructionReads, lDescription + ': initial resolution read count');
  end;
  aScript.Stage(lPublishedKind, False);
  Assert.IsTrue(lProvider.GetRules = lPublishedRules, lDescription + ': final publication lost');
end;

procedure CheckColdFallbackLeavesCheckDue(aScript: TLocalZoneInputsScript);
const
  cHourUs = Int64(3600000000);
var
  lZone: ICronTimeZone;
  lReads: Integer;
begin
  lReads := aScript.fReads;
  aScript.Stage(zikRaise, False);
  lZone := CreateScriptedLocalZone(aScript, cHourUs);
  aScript.Stage(zikPosix, False);
  CheckScheduledRules(Rules(lZone), zikPosix, 'Recovery during the first recheck interval');
  Assert.AreEqual(lReads + 2, aScript.fReads, 'Recovery must immediately retry the failed cold read');
end;

procedure TTestLocalZoneTzif.GeneratedRecheckInterleavings;
var
  lScript: TLocalZoneInputsScript;
  lState: Cardinal;
  i: Integer;
begin
  lScript := nil;
  try
    PrepareFiles;
    lScript := TLocalZoneInputsScript.Create(fInputs);
    lState := cScheduleSeed;
    for i := 1 to cScheduleCount do
      RunLocalZoneSchedule(lScript, lState, i);
    CheckColdFallbackLeavesCheckDue(lScript);
    Writeln(Format('LOCAL_INTERLEAVINGS seed=%.8x schedules=%d waves_per_schedule=5',
      [Integer(cScheduleSeed), cScheduleCount]));
  finally
    lScript.Free;
    RemoveFiles;
  end;
end;

procedure TTestLocalZoneTzif.GapOverlapMatchesNamedZone;
var
  lLocal, lNamed: ICronZoneRules;
  lBefore, lAfter: TCronZonePeriod;
  lAt, lLocalMs, lMidpoint, lOffset: Int64;
  lCount: Integer;
  i: Integer;
begin
  try
    PrepareFiles;
    lLocal := Rules(LocalZone);
    lNamed := NamedWarsaw(fTemp);
    lAt := lNamed.GetPeriod(ZoneMs(2000, 1, 1, 0)).EndUtcMs;
    lCount := 0;
    while lAt < ZoneMs(2041, 1, 1, 0) do
    begin
      for i := -1 to 1 do
      begin
        CheckPeriod(lNamed.GetPeriod(lAt + i * 1000), lLocal.GetPeriod(lAt + i * 1000));
        lLocalMs := lNamed.UtcToLocalMs(lAt + i * 1000);
        CheckMapping(lNamed.MapLocal(lLocalMs), lLocal.MapLocal(lLocalMs));
      end;
      lBefore := lNamed.GetPeriod(lAt - 1000);
      lAfter := lNamed.GetPeriod(lAt);
      for lOffset in [lBefore.OffsetMs, lAfter.OffsetMs] do
        for i := -1 to 1 do
        begin
          lLocalMs := lAt + lOffset + i * 1000;
          CheckMapping(lNamed.MapLocal(lLocalMs), lLocal.MapLocal(lLocalMs));
        end;
      lMidpoint := lAt + (lBefore.OffsetMs + lAfter.OffsetMs) div 2;
      CheckMapping(lNamed.MapLocal(lMidpoint), lLocal.MapLocal(lMidpoint));
      Inc(lCount);
      lAt := lAfter.EndUtcMs;
    end;
    Assert.AreEqual(82, lCount);
  finally
    RemoveFiles;
  end;
end;

procedure TTestLocalZoneTzif.RestartCatchUpAcrossTransition;
var
  lExpected: Integer;

  function RunWithZone(const aZone: ICronTimeZone): Integer;
  var
    lCron, lRestored: TmaxCron;
    lEvent: IMaxCronEvent;
    lStore: IMaxCronScheduleStore;
    lStates: TArray<TMaxCronPersistedEvent>;
    lNow: Int64;
    lCalls: Integer;
  begin
    lCron := nil;
    lRestored := nil;
    lCalls := 0;
    lNow := ZoneMs(2026, 10, 25, 0, 29) * 1000;
    SetCronSystemTimeZoneForTests(aZone);
    try
      SetMaxCronUtcClockHook(function: Int64 begin Result := lNow; end);
      SetMaxCronWallClockHook(function: Int64 begin Result := lNow; end);
      lStore := TRestartStore.Create;
      lCron := TmaxCron.Create(ctPortable);
      lCron.ScheduleStore := lStore;
      lEvent := lCron.Add('tzif restart');
      lEvent.InvokeMode := imMainThread;
      lEvent.TimeZoneId := 'LOCAL';
      lEvent.DstFallPolicy := dfpRunTwice;
      lEvent.EventPlan := '30 2 * * *';
      lEvent.OnScheduleProc := procedure(aSender: IMaxCronEvent) begin end;
      lEvent.Run;
      lNow := ZoneMs(2026, 10, 25, 0, 30) * 1000;
      lCron.TickAtUtcUs(lNow);
      Assert.AreEqual(1, lCron.SaveScheduleState);
      Assert.IsTrue(lStore.TryLoad(lStates));
      Assert.AreEqual<Int64>(lNow, CronDateTimeToInstantUs(lStates[0].CompletedThrough));

      lRestored := TmaxCron.Create(ctPortable);
      lRestored.ScheduleStore := lStore;
      lNow := ZoneMs(2026, 10, 25, 1, 30) * 1000;
      lRestored.RestoreScheduleState(True,
        procedure(const aEvent: IMaxCronEvent; const aSaved: TMaxCronPersistedEvent)
        begin
          aEvent.OnScheduleProc := procedure(aSender: IMaxCronEvent) begin Inc(lCalls); end;
        end);
      lRestored.TickAtUtcUs(lNow);
      Result := lCalls;
    finally
      lEvent := nil;
      lRestored.Free;
      lCron.Free;
      SetMaxCronWallClockHook(nil);
      SetMaxCronUtcClockHook(nil);
      SetCronSystemTimeZoneForTests(nil);
    end;
  end;

begin
  try
    PrepareFiles;
    lExpected := RunWithZone(TZoneAsSystemZone.Create(NamedWarsaw(fTemp)));
    Assert.AreEqual(1, lExpected, 'named Warsaw retains the second UTC occurrence');
    Assert.AreEqual(lExpected, RunWithZone(LocalZone));
  finally
    RemoveFiles;
  end;
end;

end.

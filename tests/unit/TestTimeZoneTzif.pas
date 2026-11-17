unit TestTimeZoneTzif;
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
  TTestTimeZoneTzif = class
  public
    [Test] procedure FooterCrossYearSeason;
    [Test]
    [TestCase('R1', 'Synthetic/CrossYear')]
    [TestCase('R2', 'Synthetic/Horizon-erased')]
    [TestCase('Footer02', 'Synthetic/Footer02')]
    [TestCase('Footer12', 'Synthetic/Footer12')]
    [TestCase('Footer18', 'Synthetic/Footer18')]
    [TestCase('ForwardSpill', 'Synthetic/Horizon-forward-spill')]
    [TestCase('Footer23', 'Synthetic/Footer23')]
    [TestCase('Footer051', 'Synthetic/Footer051')]
    [TestCase('Boundary-DstBelow', 'Synthetic/Boundary-DstBelow')]
    [TestCase('Boundary-StdBelow', 'Synthetic/Boundary-StdBelow')]
    [TestCase('Boundary-YearStartBelow', 'Synthetic/Boundary-YearStartBelow')]
    [TestCase('Boundary-YearEndBelow', 'Synthetic/Boundary-YearEndBelow')]
    [TestCase('Boundary-CrossStdBelow', 'Synthetic/Boundary-CrossStdBelow')]
    [TestCase('Boundary-CrossDstBelow', 'Synthetic/Boundary-CrossDstBelow')]
    procedure RejectedFooter(const aName: string);
    [Test]
    [TestCase('R1', 'Synthetic/CrossYear')]
    [TestCase('R2', 'Synthetic/Horizon-erased')]
    [TestCase('Footer02', 'Synthetic/Footer02')]
    [TestCase('Footer12', 'Synthetic/Footer12')]
    [TestCase('Footer18', 'Synthetic/Footer18')]
    [TestCase('ForwardSpill', 'Synthetic/Horizon-forward-spill')]
    [TestCase('Footer23', 'Synthetic/Footer23')]
    [TestCase('Footer051', 'Synthetic/Footer051')]
    [TestCase('Boundary-DstBelow', 'Synthetic/Boundary-DstBelow')]
    [TestCase('Boundary-StdBelow', 'Synthetic/Boundary-StdBelow')]
    [TestCase('Boundary-YearStartBelow', 'Synthetic/Boundary-YearStartBelow')]
    [TestCase('Boundary-YearEndBelow', 'Synthetic/Boundary-YearEndBelow')]
    [TestCase('Boundary-CrossStdBelow', 'Synthetic/Boundary-CrossStdBelow')]
    [TestCase('Boundary-CrossDstBelow', 'Synthetic/Boundary-CrossDstBelow')]
    procedure RejectedFooterSetter(const aName: string);
    [Test] procedure FooterAcceptedRegressions;
    [Test] procedure Footer06HistoricalPeriod;
    [Test]
    [TestCase('Boundary-DstAt', 'Synthetic/Boundary-DstAt')]
    [TestCase('Boundary-DstAbove', 'Synthetic/Boundary-DstAbove')]
    [TestCase('Boundary-StdAt', 'Synthetic/Boundary-StdAt')]
    [TestCase('Boundary-StdAbove', 'Synthetic/Boundary-StdAbove')]
    [TestCase('Boundary-YearStartAt', 'Synthetic/Boundary-YearStartAt')]
    [TestCase('Boundary-YearStartAbove', 'Synthetic/Boundary-YearStartAbove')]
    [TestCase('Boundary-YearEndAt', 'Synthetic/Boundary-YearEndAt')]
    [TestCase('Boundary-YearEndAbove', 'Synthetic/Boundary-YearEndAbove')]
    [TestCase('Boundary-CrossStdAt', 'Synthetic/Boundary-CrossStdAt')]
    [TestCase('Boundary-CrossStdAbove', 'Synthetic/Boundary-CrossStdAbove')]
    [TestCase('Boundary-CrossDstAt', 'Synthetic/Boundary-CrossDstAt')]
    [TestCase('Boundary-CrossDstAbove', 'Synthetic/Boundary-CrossDstAbove')]
    procedure AcceptedFooterBoundary(const aName: string);
    [Test] procedure FooterDomainProperty;

    [Test] procedure FooterDifferential;
    [Test] procedure IsolatedPythonReference;
    [Test] procedure GeneratedMappings;
    [Test] procedure FormatsAndFooters;
    [Test] procedure RejectionsAndTruncation;
  end;

implementation

uses
  {$IFDEF FPC}
  Windows,
  Classes, System.IOUtils, SysUtils, ZStream,
  maxCron, maxCron.Internal.TimeZone, maxCron.Internal.TZif, TestZoneFakes
  {$ELSE}
  System.Classes, System.IOUtils, System.SysUtils, System.ZLib,
  Winapi.Windows,
  maxCron, maxCron.Internal.TimeZone, maxCron.Internal.TZif, TestZoneFakes
  {$ENDIF};

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

function FixtureZone(const aName: string): ICronZoneRules;
var
  lSource: ICronZoneRuleSource;
  lPath, lError: string;
begin
  Assert.IsTrue(TryLoadCronTzifFile(ZoneFixtureRoot, aName, lSource, lPath, lError), lError);
  Result := CreateCronZone(aName, lSource);
end;

function FooterTable(const aName: string): TMemoryStream;
var
  lFile: TFileStream;
  lInflater: TDecompressionStream;
begin
  Result := TMemoryStream.Create;
  try
    lFile := TFileStream.Create(TPath.Combine(ExtractFileDir(ZoneFixtureRoot), aName),
      fmOpenRead or fmShareDenyWrite);
    try
      lInflater := TDecompressionStream.Create(lFile);
      try
        Result.CopyFrom(lInflater, 0);
        Result.Position := 0;
      finally
        lInflater.Free;
      end;
    finally
      lFile.Free;
    end;
  except
    Result.Free;
    raise;
  end;
end;

function FooterName(const aTable: TStream): string;
var
  lLength: Cardinal;
  lBytes: TBytes;
begin
  aTable.ReadBuffer(lLength, SizeOf(lLength));
  Assert.IsTrue((lLength > 0) and (lLength < 256), 'footer name length');
  SetLength(lBytes, lLength);
  aTable.ReadBuffer(lBytes[0], lLength);
  Result := TEncoding.ASCII.GetString(lBytes);
end;

function FooterYearStart(const aYear: Integer): Int64;
begin
  if aYear = 10000 then
    Result := ZoneMs(9600, 1, 1, 0) + Int64(146097) * 86400000
  else
    // Oracle dates include years before TDateTime zero; ZoneMs clamps them.
    Result := Trunc(EncodeDate(aYear, 1, 1)) * Int64(86400000);
end;

procedure TTestTimeZoneTzif.FooterCrossYearSeason;
begin
  RejectedFooter('Synthetic/CrossYear');
end;

procedure TTestTimeZoneTzif.RejectedFooter(const aName: string);
var
  lSource: ICronZoneRuleSource;
  lPath, lError: string;
begin
  lPath := TPath.Combine(ZoneFixtureRoot, StringReplace(aName, '/', PathDelim, [rfReplaceAll]));
  Assert.IsFalse(TryParseCronTzif(TFile.ReadAllBytes(lPath), lSource, lError), aName);
  Assert.IsTrue(lSource = nil, aName);
  Assert.AreEqual('Unsupported TZ footer rule: seasons overlap, invert, vanish or last a year or longer',
    lError, aName);
end;

procedure TTestTimeZoneTzif.RejectedFooterSetter(const aName: string);
var
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lPrevious, lPath: string;
  lRaised: Boolean;
begin
  lPrevious := {$IFDEF FPC}SysUtils.{$ENDIF}GetEnvironmentVariable('MAXCRON_TZDIR');
  SetEnvironmentVariableW('MAXCRON_TZDIR', PChar(ZoneFixtureRoot));
  lCron := TmaxCron.Create(ctPortable);
  try
    lEvent := lCron.Add('footer rejection');
    lEvent.TimeZoneId := 'UTC+02:00';
    lPath := TPath.Combine(ZoneFixtureRoot, StringReplace(aName, '/', PathDelim, [rfReplaceAll]));
    lRaised := False;
    try
      lEvent.TimeZoneId := aName;
    except
      on E: Exception do
      begin
        lRaised := True;
        Assert.IsTrue(E.ClassType = Exception, 'exception class');
        Assert.AreEqual('Unknown timezone "' + aName + '": invalid TZif data in ' + lPath +
          ': Unsupported TZ footer rule: seasons overlap, invert, vanish or last a year or longer',
          E.Message, aName);
      end;
    end;
    Assert.IsTrue(lRaised, aName);
    Assert.AreEqual('UTC+02:00', lEvent.TimeZoneId, 'previous zone retained');
  finally
    lEvent := nil;
    lCron.Free;
    SetEnvironmentVariableW('MAXCRON_TZDIR', PChar(lPrevious));
  end;
end;

procedure TTestTimeZoneTzif.FooterAcceptedRegressions;
var
  lYear: Int64;
  lOffset: Int64;
  lZone: ICronZoneRules;
  lUtc: Int64;
begin
  lZone := FixtureZone('Synthetic/AllYear');
  for lYear in TArray<Int64>.Create(1900, 2024, 2026, 2100, 2999, 9999) do
  begin
    lUtc := ZoneMs(lYear, 1, 1, 0);
    for lOffset in TArray<Int64>.Create(0, 17999999, 18000000) do
      Assert.AreEqual(Int64(-14400000), lZone.GetPeriod(lUtc + lOffset).OffsetMs, 'RFC all-year');
    Assert.AreEqual(Int64(-14400000), lZone.GetPeriod(ZoneMs(lYear, 7, 1, 0)).OffsetMs);
  end;
  lZone := FixtureZone('Synthetic/Real-Nuuk');
  lUtc := ZoneMs(2026, 3, 29, 1);
  Assert.AreEqual(Int64(-7200000), lZone.GetPeriod(lUtc - 1).OffsetMs, 'Nuuk signed start before');
  Assert.AreEqual(Int64(-3600000), lZone.GetPeriod(lUtc).OffsetMs, 'Nuuk signed start at');
  lUtc := ZoneMs(2026, 10, 25, 1);
  Assert.AreEqual(Int64(-3600000), lZone.GetPeriod(lUtc - 1).OffsetMs);
  Assert.AreEqual(Int64(-7200000), lZone.GetPeriod(lUtc).OffsetMs);
  lZone := FixtureZone('Synthetic/Real-Troll');
  Assert.AreEqual(Int64(0), lZone.GetPeriod(ZoneMs(2026, 1, 1, 0)).OffsetMs);
  Assert.AreEqual(Int64(7200000), lZone.GetPeriod(ZoneMs(2026, 7, 1, 0)).OffsetMs);
  lZone := FixtureZone('Synthetic/Real-LordHowe');
  Assert.AreEqual(Int64(39600000), lZone.GetPeriod(ZoneMs(2026, 1, 1, 0)).OffsetMs);
  Assert.AreEqual(Int64(37800000), lZone.GetPeriod(ZoneMs(2026, 7, 1, 0)).OffsetMs);
  lZone := FixtureZone('Synthetic/OrdinaryOrdinal');
  Assert.AreEqual(Int64(0), lZone.GetPeriod(ZoneMs(2026, 2, 28, 12)).OffsetMs);
  Assert.AreEqual(Int64(3600000), lZone.GetPeriod(ZoneMs(2026, 3, 1, 0)).OffsetMs);
end;

procedure TTestTimeZoneTzif.Footer06HistoricalPeriod;
var
  lZone: ICronZoneRules;
  lPeriod: TCronZonePeriod;
  lUtc: Int64;
begin
  // The oracle starts in 1800, before the scheduler's clamped date domain.
  lUtc := FooterYearStart(1800);
  Assert.AreEqual(Int64(-3155500800000), lUtc, 'signed oracle year start');
  lZone := FixtureZone('Synthetic/Footer06');
  lPeriod := lZone.GetPeriod(lUtc);
  Assert.AreEqual(Int64(-3163046400000), lPeriod.StartUtcMs, '1799-10-05 16:00Z');
  Assert.AreEqual(Int64(-3147321600000), lPeriod.EndUtcMs, '1800-04-05 16:00Z');
  Assert.AreEqual(Int64(39600000), lPeriod.OffsetMs, 'UTC+11 before April');
  lPeriod := lZone.GetPeriod(-3147321600001);
  Assert.AreEqual(Int64(-3147321600000), lPeriod.EndUtcMs, 'half-open end');
  Assert.AreEqual(Int64(39600000), lPeriod.OffsetMs);
  lPeriod := lZone.GetPeriod(-3147321600000);
  Assert.AreEqual(Int64(-3147321600000), lPeriod.StartUtcMs, 'inclusive start');
  Assert.AreEqual(Int64(-3131596800000), lPeriod.EndUtcMs, '1800-10-04 16:00Z');
  Assert.AreEqual(Int64(36000000), lPeriod.OffsetMs, 'UTC+10 at April change');
end;

procedure TTestTimeZoneTzif.AcceptedFooterBoundary(const aName: string);
var
  lZone: ICronZoneRules;
begin
  lZone := FixtureZone(aName);
  Assert.IsTrue(lZone <> nil, aName);
end;

procedure TTestTimeZoneTzif.FooterDomainProperty;
var
  lCase: Integer;
  lTable: TMemoryStream;
  lSource: ICronZoneRuleSource;
  lName, lPath, lError, lFirstError: string;
  lMagic, lCases: Cardinal;
  lExpected: Byte;
  lActual: Boolean;
  lAccepted, lRejected, lFailures: Integer;
begin
  lTable := FooterTable('footer-domain.bin.z');
  try
    lTable.ReadBuffer(lMagic, SizeOf(lMagic));
    Assert.AreEqual(Cardinal($31564446), lMagic, 'FDV1');
    lTable.ReadBuffer(lCases, SizeOf(lCases));
    lAccepted := 0; lRejected := 0; lFailures := 0; lFirstError := '';
    for lCase := 1 to lCases do
    begin
      lName := FooterName(lTable);
      lTable.ReadBuffer(lExpected, SizeOf(lExpected));
      lActual := TryLoadCronTzifFile(ZoneFixtureRoot, lName, lSource, lPath, lError);
      if lExpected = 1 then Inc(lAccepted) else Inc(lRejected);
      if (lActual <> (lExpected = 1)) or ((lExpected = 0) and
        not lError.EndsWith('Unsupported TZ footer rule: seasons overlap, invert, vanish or last a year or longer')) then
      begin
        Inc(lFailures);
        if lFirstError = '' then lFirstError := lName + ': ' + lError;
      end;
    end;
    Assert.AreEqual(lTable.Size, lTable.Position, 'trailing domain table');
    Assert.IsTrue((lAccepted > 0) and (lRejected > 0), 'both property populations required');
    Writeln(Format('DOMAIN accepted=%d rejected=%d failures=%d', [lAccepted, lRejected, lFailures]));
    Assert.AreEqual(0, lFailures, lFirstError);
  finally
    lTable.Free;
  end;
end;

type
  TFooterReferenceRow = packed record
    UtcMs: Int64;
    OffsetMs: Integer;
  end;

procedure TTestTimeZoneTzif.FooterDifferential;
var
  lCase: Integer;
  lTable: TMemoryStream;
  lSource: ICronZoneRuleSource;
  lZone: ICronZoneRules;
  lRows: TArray<TFooterReferenceRow>;
  lRaw, lPeriod: TCronZonePeriod;
  lName, lPath, lError: string;
  lMagic, lCases, lCount: Cardinal;
  lFirstYear, lLastYear, lOffset: Integer;
  lCursor, lLimit, lChecks: Int64;
  lIndex: Integer;
begin
  lTable := FooterTable('footer-model.bin.z');
  try
    lTable.ReadBuffer(lMagic, SizeOf(lMagic));
    Assert.AreEqual(Cardinal($33525446), lMagic, 'FTR3');
    lTable.ReadBuffer(lCases, SizeOf(lCases));
    Assert.IsTrue(lCases > 0, 'nonempty reference table');
    lChecks := 0;
    for lCase := 1 to lCases do
    begin
      lName := FooterName(lTable);
      lTable.ReadBuffer(lFirstYear, SizeOf(lFirstYear));
      lTable.ReadBuffer(lLastYear, SizeOf(lLastYear));
      lTable.ReadBuffer(lOffset, SizeOf(lOffset));
      lTable.ReadBuffer(lCount, SizeOf(lCount));
      SetLength(lRows, lCount);
      if lCount > 0 then lTable.ReadBuffer(lRows[0], lCount * SizeOf(TFooterReferenceRow));
      Assert.IsTrue(TryLoadCronTzifFile(ZoneFixtureRoot, lName, lSource, lPath, lError), lName + ': ' + lError);
      lZone := CreateCronZone(lName, lSource);
      lCursor := FooterYearStart(lFirstYear);
      lLimit := FooterYearStart(lLastYear + 1);
      lIndex := 0;
      repeat
        lPeriod := lZone.GetPeriod(lCursor);
        Assert.AreEqual(Int64(lOffset), lPeriod.OffsetMs, lName + ' merged offset at ' + IntToStr(lCursor));
        Assert.IsTrue((lPeriod.StartUtcMs <= lCursor) and (lPeriod.EndUtcMs > lCursor), lName + ' containment');
        if lPeriod.EndUtcMs >= lLimit then Break;
        if lIndex < Length(lRows) then
          Assert.IsTrue(lPeriod.EndUtcMs <= lRows[lIndex].UtcMs, lName + ' period crosses an expected change');
        lCursor := lPeriod.EndUtcMs;
        // GetPeriod merges equal offsets within its bounded lookup window;
        // it may return an earlier partition boundary with no offset change.
        if (lIndex < Length(lRows)) and (lCursor = lRows[lIndex].UtcMs) then
        begin
          lOffset := lRows[lIndex].OffsetMs;
          lRaw := lSource.GetRawPeriod(lCursor);
          Assert.AreEqual(lCursor, lRaw.StartUtcMs, lName + ' raw start');
          Assert.AreEqual(Int64(lOffset), lRaw.OffsetMs, lName + ' raw after offset');
          lRaw := lSource.GetRawPeriod(lCursor - 1);
          Assert.AreEqual(lCursor, lRaw.EndUtcMs, lName + ' raw end');
          Inc(lIndex); Inc(lChecks);
        end;
      until False;
      Assert.AreEqual(Int64(Length(lRows)), Int64(lIndex), lName + ' unconsumed changes');
      Writeln(Format('FOOTER_CASE|%s|years=%d..%d|changes=%d', [lName, lFirstYear, lLastYear, lIndex]));
    end;
    Assert.AreEqual(lTable.Size, lTable.Position, 'trailing reference table');
    Writeln(Format('FOOTER cases=%d changes=%d failures=0', [lCases, lChecks]));
  finally
    lTable.Free;
  end;
end;

procedure TTestTimeZoneTzif.IsolatedPythonReference;
var
  i: Integer;
  lZones: array[0..4] of ICronZoneRules;
  lRow: TZoneRow;
  lContext: string;
begin
  for i := 0 to 4 do lZones[i] := FixtureZone(cZoneNames[i]);
  for lRow in cZoneRows do
  begin
    lContext := Format('%s UTC ms=%d', [cZoneNames[lRow.Zone], lRow.UtcMs]);
    Assert.AreEqual(lRow.OffsetMs, lZones[lRow.Zone].UtcToLocalMs(lRow.UtcMs) - lRow.UtcMs, lContext);
  end;
end;

procedure TTestTimeZoneTzif.GeneratedMappings;
var
  lZone: ICronZoneRules;
  lTransition: TZoneTransition;
  lChanges: TArray<TZoneChange>;
  lExpected, lActual: TCronLocalMapping;
  lLocal, lLeft, lRight, lSwap, lStep: Int64;
  lContext: string;
begin
  SetLength(lChanges, 1);
  for lTransition in cZoneTransitions do
  begin
    lZone := FixtureZone(cZoneNames[lTransition.Zone]);
    lChanges[0].UtcMs := lTransition.UtcMs;
    lChanges[0].OffsetMs := lTransition.AfterMs;
    lLeft := lTransition.UtcMs + lTransition.BeforeMs;
    lRight := lTransition.UtcMs + lTransition.AfterMs;
    if lLeft > lRight then
    begin
      lSwap := lLeft; lLeft := lRight; lRight := lSwap;
    end;
    lLocal := lLeft - 2000;
    while lLocal <= lRight + 2000 do
    begin
      lExpected := ReferenceMapping(lTransition.BeforeMs, lChanges, lLocal);
      lActual := lZone.MapLocal(lLocal);
      lContext := Format('%s transition=%d local=%d',
        [cZoneNames[lTransition.Zone], lTransition.UtcMs, lLocal]);
      Assert.AreEqual(Ord(lExpected.Kind), Ord(lActual.Kind), lContext);
      Assert.AreEqual(lExpected.FirstUtcMs, lActual.FirstUtcMs, lContext);
      Assert.AreEqual(lExpected.SecondUtcMs, lActual.SecondUtcMs, lContext);
      lStep := 1000;
      if (lLocal <= lLeft + 2000) or (lLocal >= lRight - 2000) then lStep := 1;
      Inc(lLocal, lStep);
    end;
  end;
end;

procedure TTestTimeZoneTzif.FormatsAndFooters;
var
  i: Integer;
  y: Int64;
  m: Integer;
  lZone, lFat: ICronZoneRules;
  lSource: ICronZoneRuleSource;
  lPath, lRoot, lError: string;
  lUtc: Int64;
begin
  for i := 1 to 5 do
  begin
    lZone := FixtureZone('Synthetic/Version' + IntToStr(i));
    Assert.AreEqual(Int64(3600000), lZone.GetPeriod(ZoneMs(2100, 6, 1, 0)).OffsetMs);
  end;
  lZone := FixtureZone('Synthetic/Fat');
  Assert.AreEqual(Int64(3600000), lZone.GetPeriod(ZoneMs(2026, 1, 1, 0)).OffsetMs);
  Assert.AreEqual(Int64(7200000), lZone.GetPeriod(ZoneMs(2100, 7, 1, 0)).OffsetMs);
  lRoot := TPath.Combine(ExtractFileDir(ZoneFixtureRoot), 'tzif-fat');
  Assert.IsTrue(TryLoadCronTzifFile(lRoot, 'Europe/Warsaw', lSource, lPath, lError), lError);
  lFat := CreateCronZone('fat Warsaw', lSource);
  lZone := FixtureZone('Europe/Warsaw');
  for y := 1970 to 2100 do
    for m := 1 to 12 do
    begin
      lUtc := ZoneMs(y, m, 1, 0);
      Assert.AreEqual(lZone.GetPeriod(lUtc).OffsetMs, lFat.GetPeriod(lUtc).OffsetMs);
    end;
  lZone := FixtureZone('Synthetic/Julian');
  lUtc := ZoneMs(2024, 3, 1, 0);
  Assert.AreEqual(Int64(0), lZone.GetPeriod(lUtc - 1).OffsetMs);
  Assert.AreEqual(Int64(3600000), lZone.GetPeriod(lUtc).OffsetMs);
  lZone := FixtureZone('Synthetic/Ordinal');
  lUtc := ZoneMs(2024, 2, 29, 0);
  Assert.AreEqual(Int64(0), lZone.GetPeriod(lUtc - 1).OffsetMs);
  Assert.AreEqual(Int64(3600000), lZone.GetPeriod(lUtc).OffsetMs);
  lZone := FixtureZone('Synthetic/AllYear');
  for y in TArray<Int64>.Create(2024, 2025, 2026) do
  begin
    Assert.AreEqual(Int64(-14400000), lZone.GetPeriod(ZoneMs(y, 1, 1, 0)).OffsetMs);
    Assert.AreEqual(Int64(-14400000), lZone.GetPeriod(ZoneMs(y, 7, 1, 0)).OffsetMs);
  end;
  lZone := FixtureZone('Synthetic/Signed');
  Assert.AreEqual(Int64(-10800000), lZone.GetPeriod(ZoneMs(2026, 1, 1, 0)).OffsetMs);
  Assert.AreEqual(Int64(-7200000), lZone.GetPeriod(ZoneMs(2026, 7, 1, 0)).OffsetMs);
  lZone := FixtureZone('Synthetic/Southern');
  Assert.AreEqual(Int64(39600000), lZone.GetPeriod(ZoneMs(2026, 1, 1, 0)).OffsetMs);
  Assert.AreEqual(Int64(36000000), lZone.GetPeriod(ZoneMs(2026, 7, 1, 0)).OffsetMs);
end;

procedure TTestTimeZoneTzif.RejectionsAndTruncation;
const
  cNames: array[0..8] of string = ('Leap', 'Unsorted', 'Index', 'Offset', 'Mismatch',
    'BadFooter', 'BadMagic', 'Truncated', 'Counts');
  cReasons: array[0..8] of string = ('leap-second', 'increasing', 'index', '26 hours',
    'disagrees', 'footer', 'magic', 'footer', 'counts');
var
  i: Integer;
  lSource: ICronZoneRuleSource;
  lPath, lError: string;
  lBytes: TBytes;
begin
  for i := 0 to High(cNames) do
  begin
    Assert.IsFalse(TryLoadCronTzifFile(ZoneFixtureRoot, 'Synthetic/' + cNames[i], lSource, lPath, lError));
    Assert.IsTrue(lSource = nil);
    Assert.IsTrue(Pos(cReasons[i], lError) > 0, cNames[i] + ': ' + lError);
  end;
  lPath := TPath.Combine(ZoneFixtureRoot, 'Europe');
  lPath := TPath.Combine(lPath, 'Warsaw');
  lBytes := TFile.ReadAllBytes(lPath);
  for i := 0 to Length(lBytes) - 1 do
  begin
    Assert.IsFalse(TryParseCronTzif(Copy(lBytes, 0, i), lSource, lError), 'truncation=' + IntToStr(i));
    Assert.IsTrue(lError <> '');
  end;
  SetLength(lBytes, 1048577);
  Assert.IsFalse(TryParseCronTzif(lBytes, lSource, lError));
  Assert.IsTrue(Pos('1 MiB', lError) > 0, lError);
end;

end.

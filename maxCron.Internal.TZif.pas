unit maxCron.Internal.TZif;
{$I maxCron.inc}

interface

uses
  {$IFDEF FPC}
  SysUtils,
  {$ELSE}
  System.SysUtils,
  {$ENDIF}
  maxCron.Internal.TimeZone;

function TryParseCronTzif(const aBytes: TBytes; out aSource: ICronZoneRuleSource;
  out aError: string): Boolean;
function TryLoadCronTzifFile(const aRoot, aName: string; out aSource: ICronZoneRuleSource;
  out aPath, aError: string): Boolean;

implementation

uses
  {$IFDEF FPC}
  Classes, System.IOUtils,
  {$ELSE}
  System.Classes, System.IOUtils,
  {$ENDIF}
  maxCron.Internal.Text, maxCron.Plan;

const
  cMaxTzifSize = 1048576;
  cUnixEpochMs = Int64(25569) * cCronMsPerDay;

resourcestring
  rsUnsupportedFooter = 'Unsupported TZ footer rule: seasons overlap, invert, vanish or last a year or longer';

type
  TCronTzifChange = record
    UtcMs, OffsetMs: Int64;
  end;
  TCronTzifRule = record
    Kind: Char;
    Day, Month, Week, Weekday, Seconds: Integer;
  end;
  TCronTzifSource = class(TInterfacedObject, ICronZoneRuleSource)
  private
    fInitialOffset: Int64;
    fChanges: TArray<TCronTzifChange>;
    fHasFooter, fHasDst, fAllYearDst: Boolean;
    fStandardOffset, fDaylightOffset: Int64;
    fStartRule, fEndRule: TCronTzifRule;
    procedure ValidateFooter;
    function FooterPeriod(const aUtcMs: Int64): TCronZonePeriod;
  public
    function GetRawPeriod(const aUtcMs: Int64): TCronZonePeriod;
  end;
  TCronTzifReader = class
  private
    fBytes: TBytes;
    fPos: Integer;
    function ReadByte: Byte;
    function ReadUnsigned: UInt32;
    function ReadSigned(const aWidth: Integer): Int64;
    procedure Header(out aVersion: Byte; out aTimes, aTypes, aChars, aStd, aUtc: Integer);
    procedure Block(const aWidth, aTimes, aTypes, aChars, aStd, aUtc: Integer;
      const aSource: TCronTzifSource);
  public
    constructor Create(const aBytes: TBytes);
    procedure Parse(const aSource: TCronTzifSource);
  end;
  TCronFooterReader = class
  private
    fText: string;
    fPos: Integer;
    function Peek: Char;
    function Number(const aMaximum: Integer): Integer;
    procedure Name;
    function Clock(const aMaxHour: Integer): Integer;
    function Rule: TCronTzifRule;
  public
    constructor Create(const aText: string);
    procedure Parse(const aSource: TCronTzifSource);
  end;

function CivilDay(const aYear, aMonth, aDay: Int64): Int64;
var
  lYear, lMonth, lEra, lYearOfEra, lDayOfYear: Int64;
begin
  lYear := aYear;
  if aMonth <= 2 then Dec(lYear);
  lEra := CronFloorDiv(lYear, 400);
  lYearOfEra := lYear - lEra * 400;
  if aMonth > 2 then lMonth := aMonth - 3 else lMonth := aMonth + 9;
  lDayOfYear := (153 * lMonth + 2) div 5 + aDay - 1;
  Result := lEra * 146097 + lYearOfEra * 365 + lYearOfEra div 4 - lYearOfEra div 100 +
    lDayOfYear - 719468 + 25569;
end;

function CivilYear(const aDay: Int64): Int64;
var
  z, lEra, lDayOfEra, lYearOfEra, lDayOfYear, lMonth: Int64;
begin
  z := aDay - 25569 + 719468;
  lEra := CronFloorDiv(z, 146097);
  lDayOfEra := z - lEra * 146097;
  lYearOfEra := (lDayOfEra - lDayOfEra div 1460 + lDayOfEra div 36524 - lDayOfEra div 146096) div 365;
  Result := lYearOfEra + lEra * 400;
  lDayOfYear := lDayOfEra - (365 * lYearOfEra + lYearOfEra div 4 - lYearOfEra div 100);
  lMonth := (5 * lDayOfYear + 2) div 153;
  if lMonth >= 10 then Inc(Result);
end;

function RuleLocalMs(const aYear: Int64; const aRule: TCronTzifRule): Int64;
var
  lDay, lFirst, lWeekday: Int64;
  lLeap: Boolean;
begin
  lLeap := (aYear mod 4 = 0) and ((aYear mod 100 <> 0) or (aYear mod 400 = 0));
  if aRule.Kind = 'M' then
  begin
    lFirst := CivilDay(aYear, aRule.Month, 1);
    lWeekday := (lFirst + 6) mod 7;
    if lWeekday < 0 then Inc(lWeekday, 7);
    lDay := lFirst + (aRule.Weekday - lWeekday + 7) mod 7 + (aRule.Week - 1) * 7;
    if aRule.Month = 12 then lFirst := CivilDay(aYear + 1, 1, 1)
    else lFirst := CivilDay(aYear, aRule.Month + 1, 1);
    if lDay >= lFirst then Dec(lDay, 7);
  end else begin
    lDay := aRule.Day;
    if aRule.Kind = 'J' then
    begin
      Dec(lDay);
      if lLeap and (aRule.Day >= 60) then Inc(lDay);
    end;
    Inc(lDay, CivilDay(aYear, 1, 1));
  end;
  Result := lDay * cCronMsPerDay + Int64(aRule.Seconds) * 1000;
end;

procedure TCronTzifSource.ValidateFooter;
var
  lYear, lFirst, lLimit, lStart, lEnd, lStartUtc, lEndUtc, lPart, lAcross: Int64;
  lRegular, lAllYear: Boolean;
begin
  if not fHasDst then Exit;
  lRegular := True;
  lAllYear := True;
  // Gregorian rule dates repeat exactly after 400 years. Validate local
  // dates before converting their independently specified offsets to UTC.
  for lYear := 2000 to 2399 do
  begin
    lFirst := CivilDay(lYear, 1, 1) * cCronMsPerDay;
    lLimit := CivilDay(lYear + 1, 1, 1) * cCronMsPerDay;
    lStart := RuleLocalMs(lYear, fStartRule);
    lEnd := RuleLocalMs(lYear, fEndRule);
    lStartUtc := lStart - fStandardOffset;
    lEndUtc := lEnd - fDaylightOffset;
    // Check both elapsed parts, including the part crossing into next year.
    if lStartUtc < lEndUtc then
    begin
      lPart := lEndUtc - lStartUtc;
      lAcross := RuleLocalMs(lYear + 1, fStartRule) - fStandardOffset - lEndUtc;
    end else begin
      lPart := lStartUtc - lEndUtc;
      lAcross := RuleLocalMs(lYear + 1, fEndRule) - fDaylightOffset - lStartUtc;
    end;
    lRegular := lRegular and (lStart >= lFirst + 2 * cCronMsPerDay) and
      (lStart <= lLimit - 2 * cCronMsPerDay) and
      (lEnd >= lFirst + 2 * cCronMsPerDay) and (lEnd <= lLimit - 2 * cCronMsPerDay) and
      (lPart >= Int64(28) * cCronMsPerDay) and (lAcross >= Int64(28) * cCronMsPerDay);
    // RFC 9636 3.3.1: Jan 1 00:00 through Dec 31 24:00 + DST delta.
    lAllYear := lAllYear and (lStart = lFirst) and
      (lEnd = lLimit + fDaylightOffset - fStandardOffset);
  end;
  if not (lRegular or lAllYear) then
    raise Exception.Create(rsUnsupportedFooter);
  fAllYearDst := lAllYear;
end;

function TCronTzifSource.FooterPeriod(const aUtcMs: Int64): TCronZonePeriod;
var
  lYear, lStart, lEnd: Int64;
  lIndex: Integer;
begin
  Result.StartUtcMs := cCronZoneUnboundedStart;
  Result.EndUtcMs := cCronZoneUnboundedEnd;
  Result.OffsetMs := fStandardOffset;
  if fAllYearDst then Result.OffsetMs := fDaylightOffset;
  if not fHasDst or fAllYearDst or (fStandardOffset = fDaylightOffset) then Exit;
  lYear := CivilYear(CronFloorDiv(aUtcMs, cCronMsPerDay));
  // Validated local-year rules have two distinct transitions per year.
  // The latest UTC transition decides northern and southern seasons alike.
  // Adjacent UTC years can spill by the supported 26-hour offsets; two
  // neighbours also cover a pair of Jan 1 or Dec 31 transitions on one side.
  for lIndex := -2 to 2 do
  begin
    lStart := RuleLocalMs(lYear + lIndex, fStartRule) - fStandardOffset;
    lEnd := RuleLocalMs(lYear + lIndex, fEndRule) - fDaylightOffset;
    if (lStart <= aUtcMs) and (lStart > Result.StartUtcMs) then
    begin
      Result.StartUtcMs := lStart;
      Result.OffsetMs := fDaylightOffset;
    end;
    if (lEnd <= aUtcMs) and (lEnd > Result.StartUtcMs) then
    begin
      Result.StartUtcMs := lEnd;
      Result.OffsetMs := fStandardOffset;
    end;
    if (lStart > aUtcMs) and (lStart < Result.EndUtcMs) then Result.EndUtcMs := lStart;
    if (lEnd > aUtcMs) and (lEnd < Result.EndUtcMs) then Result.EndUtcMs := lEnd;
  end;
end;

function TCronTzifSource.GetRawPeriod(const aUtcMs: Int64): TCronZonePeriod;
var
  lLow, lHigh, lMid, lIndex: Integer;
begin
  lLow := 0;
  lHigh := Length(fChanges) - 1;
  while lLow <= lHigh do
  begin
    lMid := lLow + (lHigh - lLow) div 2;
    if fChanges[lMid].UtcMs <= aUtcMs then lLow := lMid + 1 else lHigh := lMid - 1;
  end;
  lIndex := lHigh;
  if fHasFooter and (lIndex = Length(fChanges) - 1) then
  begin
    Result := FooterPeriod(aUtcMs);
    if (lIndex >= 0) and (Result.StartUtcMs < fChanges[lIndex].UtcMs) then
      Result.StartUtcMs := fChanges[lIndex].UtcMs;
    Exit;
  end;
  Result.StartUtcMs := cCronZoneUnboundedStart;
  Result.EndUtcMs := cCronZoneUnboundedEnd;
  Result.OffsetMs := fInitialOffset;
  if lIndex >= 0 then
  begin
    Result.StartUtcMs := fChanges[lIndex].UtcMs;
    Result.OffsetMs := fChanges[lIndex].OffsetMs;
  end;
  if lLow < Length(fChanges) then Result.EndUtcMs := fChanges[lLow].UtcMs;
end;

constructor TCronFooterReader.Create(const aText: string);
begin
  inherited Create;
  fText := aText;
  fPos := 1;
end;

function TCronFooterReader.Peek: Char;
begin
  if fPos > Length(fText) then Result := #0 else Result := fText[fPos];
end;

function TCronFooterReader.Number(const aMaximum: Integer): Integer;
begin
  if not CharInSet(Peek, ['0'..'9']) then raise Exception.Create('invalid TZ footer number');
  Result := 0;
  while CharInSet(Peek, ['0'..'9']) do
  begin
    if Result > aMaximum div 10 then raise Exception.Create('TZ footer number out of range');
    Result := Result * 10 + Ord(Peek) - Ord('0');
    if Result > aMaximum then raise Exception.Create('TZ footer number out of range');
    Inc(fPos);
  end;
end;

procedure TCronFooterReader.Name;
var
  lStart: Integer;
begin
  if Peek = '<' then
  begin
    Inc(fPos);
    lStart := fPos;
    while CharInSet(Peek, ['A'..'Z', 'a'..'z', '0'..'9', '+', '-']) do Inc(fPos);
    if (Peek <> '>') or (fPos - lStart < 3) then raise Exception.Create('invalid quoted TZ footer name');
    Inc(fPos);
  end else begin
    lStart := fPos;
    while CharInSet(Peek, ['A'..'Z', 'a'..'z']) do Inc(fPos);
    if fPos - lStart < 3 then raise Exception.Create('invalid TZ footer name');
  end;
end;

function TCronFooterReader.Clock(const aMaxHour: Integer): Integer;
var
  lSign: Integer;
begin
  lSign := 1;
  if Peek = '-' then lSign := -1;
  if CharInSet(Peek, ['+', '-']) then Inc(fPos);
  Result := Number(aMaxHour) * 3600;
  if Peek = ':' then
  begin
    Inc(fPos);
    Inc(Result, Number(59) * 60);
    if Peek = ':' then
    begin
      Inc(fPos);
      Inc(Result, Number(59));
    end;
  end;
  Result := Result * lSign;
end;

function TCronFooterReader.Rule: TCronTzifRule;
begin
  Result := Default(TCronTzifRule);
  Result.Kind := Peek;
  if Peek = 'M' then
  begin
    Inc(fPos);
    Result.Month := Number(12);
    if (Result.Month = 0) or (Peek <> '.') then raise Exception.Create('invalid TZ footer month rule');
    Inc(fPos);
    Result.Week := Number(5);
    if (Result.Week = 0) or (Peek <> '.') then raise Exception.Create('invalid TZ footer week rule');
    Inc(fPos);
    Result.Weekday := Number(6);
  end else if Peek = 'J' then
  begin
    Inc(fPos);
    Result.Day := Number(365);
    if Result.Day = 0 then raise Exception.Create('invalid TZ footer Julian rule');
  end else begin
    Result.Kind := 'N';
    Result.Day := Number(365);
  end;
  Result.Seconds := 7200;
  if Peek = '/' then
  begin
    Inc(fPos);
    Result.Seconds := Clock(167);
  end;
end;

procedure TCronFooterReader.Parse(const aSource: TCronTzifSource);
begin
  Name;
  aSource.fStandardOffset := -Int64(Clock(26)) * 1000;
  aSource.fDaylightOffset := aSource.fStandardOffset + 3600000;
  aSource.fHasDst := Peek <> #0;
  if aSource.fHasDst then
  begin
    Name;
    if Peek <> ',' then aSource.fDaylightOffset := -Int64(Clock(26)) * 1000;
    if Peek <> ',' then raise Exception.Create('TZ footer DST needs explicit transition rules');
    Inc(fPos);
    aSource.fStartRule := Rule;
    if Peek <> ',' then raise Exception.Create('TZ footer end rule is missing');
    Inc(fPos);
    aSource.fEndRule := Rule;
  end;
  if Peek <> #0 then raise Exception.Create('trailing TZ footer data');
  if (Abs(aSource.fStandardOffset) > cCronZoneMaxAbsOffsetMs) or
    (aSource.fHasDst and (Abs(aSource.fDaylightOffset) > cCronZoneMaxAbsOffsetMs)) then
    raise Exception.Create('TZ footer offset exceeds 26 hours');
  aSource.ValidateFooter;
  aSource.fHasFooter := True;
end;

constructor TCronTzifReader.Create(const aBytes: TBytes);
begin
  inherited Create;
  fBytes := aBytes;
end;

function TCronTzifReader.ReadByte: Byte;
begin
  if fPos >= Length(fBytes) then raise Exception.Create('truncated TZif data');
  Result := fBytes[fPos];
  Inc(fPos);
end;

function TCronTzifReader.ReadUnsigned: UInt32;
var
  i: Integer;
begin
  Result := 0;
  for i := 1 to 4 do Result := (Result shl 8) or ReadByte;
end;

function TCronTzifReader.ReadSigned(const aWidth: Integer): Int64;
var
  lBits: UInt64;
  i: Integer;
begin
  lBits := ReadByte;
  if (lBits and $80) <> 0 then lBits := lBits or UInt64($FFFFFFFFFFFFFF00);
  for i := 2 to aWidth do lBits := (lBits shl 8) or ReadByte;
  Move(lBits, Result, SizeOf(Result));
end;

procedure TCronTzifReader.Header(out aVersion: Byte; out aTimes, aTypes, aChars, aStd, aUtc: Integer);
var
  i: Integer;
  lCounts: array[0..5] of UInt32;
begin
  if (ReadByte <> Ord('T')) or (ReadByte <> Ord('Z')) or (ReadByte <> Ord('i')) or
    (ReadByte <> Ord('f')) then raise Exception.Create('invalid TZif magic');
  aVersion := ReadByte;
  if (aVersion <> 0) and (aVersion < Ord('2')) then raise Exception.Create('unsupported TZif version');
  for i := 1 to 15 do
    if ReadByte <> 0 then raise Exception.Create('nonzero TZif reserved byte');
  for i := 0 to 5 do
  begin
    lCounts[i] := ReadUnsigned;
    if lCounts[i] > cMaxTzifSize then raise Exception.Create('TZif counts exceed file size');
  end;
  if lCounts[2] <> 0 then raise Exception.Create('leap-second tables are not supported');
  aUtc := lCounts[0]; aStd := lCounts[1]; aTimes := lCounts[3];
  aTypes := lCounts[4]; aChars := lCounts[5];
  if (aTypes < 1) or (aTypes > 256) then raise Exception.Create('invalid TZif type count');
  if aChars < 1 then raise Exception.Create('invalid TZif character count');
  if ((aStd <> 0) and (aStd <> aTypes)) or ((aUtc <> 0) and (aUtc <> aTypes)) then
    raise Exception.Create('invalid TZif indicator count');
end;

procedure TCronTzifReader.Block(const aWidth, aTimes, aTypes, aChars, aStd, aUtc: Integer;
  const aSource: TCronTzifSource);
var
  lTimes, lOffsets: TArray<Int64>;
  lIndices, lAbbreviations: TBytes;
  lCharStart, lCount, i, j: Integer;
  lSize, lSeconds: Int64;
begin
  lSize := Int64(aTimes) * (aWidth + 1) + Int64(aTypes) * 6 + aChars + aStd + aUtc;
  if lSize > Length(fBytes) - fPos then raise Exception.Create('TZif block counts exceed remaining data');
  SetLength(lTimes, aTimes);
  SetLength(lIndices, aTimes);
  SetLength(lOffsets, aTypes);
  SetLength(lAbbreviations, aTypes);
  for i := 0 to aTimes - 1 do
  begin
    lTimes[i] := ReadSigned(aWidth);
    if (i > 0) and (lTimes[i] <= lTimes[i - 1]) then
      raise Exception.Create('TZif transitions are not strictly increasing');
  end;
  for i := 0 to aTimes - 1 do
  begin
    lIndices[i] := ReadByte;
    if lIndices[i] >= aTypes then raise Exception.Create('TZif transition type index out of range');
  end;
  for i := 0 to aTypes - 1 do
  begin
    lSeconds := ReadSigned(4);
    if (lSeconds < -93600) or (lSeconds > 93600) then raise Exception.Create('TZif offset exceeds 26 hours');
    lOffsets[i] := lSeconds * 1000;
    if ReadByte > 1 then raise Exception.Create('invalid TZif daylight indicator');
    lAbbreviations[i] := ReadByte;
    if lAbbreviations[i] >= aChars then raise Exception.Create('TZif abbreviation index out of range');
  end;
  lCharStart := fPos;
  Inc(fPos, aChars);
  if fBytes[fPos - 1] <> 0 then raise Exception.Create('unterminated TZif abbreviation');
  for i := 0 to aTypes - 1 do
  begin
    j := lCharStart + lAbbreviations[i];
    while (j < fPos) and (fBytes[j] <> 0) do Inc(j);
    if j = fPos then raise Exception.Create('unterminated TZif abbreviation');
  end;
  for i := 1 to aStd + aUtc do
    if ReadByte > 1 then raise Exception.Create('invalid TZif standard/UTC indicator');
  aSource.fInitialOffset := lOffsets[0];
  SetLength(aSource.fChanges, aTimes);
  lCount := 0;
  for i := 0 to aTimes - 1 do
  begin
    // Compare in seconds before multiplication: fat TZif may start at -2^59.
    if lTimes[i] < (CivilDay(1800, 1, 1) - 25569) * cCronSecondsPerDay then
      aSource.fInitialOffset := lOffsets[lIndices[i]]
    else if lTimes[i] < (CivilDay(10000, 1, 1) - 25569) * cCronSecondsPerDay then
    begin
      aSource.fChanges[lCount].UtcMs := lTimes[i] * 1000 + cUnixEpochMs;
      aSource.fChanges[lCount].OffsetMs := lOffsets[lIndices[i]];
      Inc(lCount);
    end;
  end;
  SetLength(aSource.fChanges, lCount);
end;

procedure TCronTzifReader.Parse(const aSource: TCronTzifSource);
var
  lVersion, lSecondVersion: Byte;
  lTimes, lTypes, lChars, lStd, lUtc, lStart, lLast: Integer;
  lFooter: string;
  lReader: TCronFooterReader;
begin
  if Length(fBytes) > cMaxTzifSize then raise Exception.Create('TZif file exceeds 1 MiB');
  Header(lVersion, lTimes, lTypes, lChars, lStd, lUtc);
  Block(4, lTimes, lTypes, lChars, lStd, lUtc, aSource);
  if lVersion <> 0 then
  begin
    Header(lSecondVersion, lTimes, lTypes, lChars, lStd, lUtc);
    if lSecondVersion <> lVersion then raise Exception.Create('TZif header versions differ');
    Block(8, lTimes, lTypes, lChars, lStd, lUtc, aSource);
    if ReadByte <> 10 then raise Exception.Create('missing TZif footer newline');
    lStart := fPos;
    while (fPos < Length(fBytes)) and (fBytes[fPos] <> 10) do
    begin
      if (fBytes[fPos] < 32) or (fBytes[fPos] > 126) then raise Exception.Create('invalid TZif footer character');
      Inc(fPos);
    end;
    if fPos >= Length(fBytes) then raise Exception.Create('truncated TZif footer');
    SetLength(lFooter, fPos - lStart);
    for lLast := 1 to Length(lFooter) do lFooter[lLast] := Char(fBytes[lStart + lLast - 1]);
    Inc(fPos);
    if lFooter <> '' then
    begin
      lReader := TCronFooterReader.Create(lFooter);
      try
        lReader.Parse(aSource);
      finally
        lReader.Free;
      end;
      lLast := Length(aSource.fChanges) - 1;
      if (lLast >= 0) and
        (aSource.FooterPeriod(aSource.fChanges[lLast].UtcMs).OffsetMs <> aSource.fChanges[lLast].OffsetMs) then
        raise Exception.Create('TZif footer offset disagrees with last transition');
    end;
  end;
  if fPos <> Length(fBytes) then raise Exception.Create('trailing TZif data');
end;

function TryParseCronTzif(const aBytes: TBytes; out aSource: ICronZoneRuleSource;
  out aError: string): Boolean;
var
  lSource: TCronTzifSource;
  lReader: TCronTzifReader;
  lKeepAlive: ICronZoneRuleSource;
begin
  aSource := nil;
  aError := '';
  lSource := TCronTzifSource.Create;
  lKeepAlive := lSource;
  lReader := TCronTzifReader.Create(aBytes);
  try
    try
      lReader.Parse(lSource);
      aSource := lKeepAlive;
      Result := True;
    except
      on E: Exception do
      begin
        aError := CronExceptionText(E);
        Result := False;
      end;
    end;
  finally
    lReader.Free;
  end;
end;

function TryLoadCronTzifFile(const aRoot, aName: string; out aSource: ICronZoneRuleSource;
  out aPath, aError: string): Boolean;
var
  {$IFDEF FPC}
  lHandle: THandle;
  lStream: THandleStream;
  {$ELSE}
  lStream: TFileStream;
  {$ENDIF}
  lBytes: TBytes;
  lParts: TArray<string>;
  lPart, lMatch: string;
  {$IFDEF FPC} lSearch: TUnicodeSearchRec; {$ELSE} lSearch: TSearchRec; {$ENDIF}
begin
  aSource := nil;
  aError := '';
  aPath := aRoot;
  if not IsCronZoneNameSyntax(aName) then
  begin
    aError := 'invalid IANA name syntax';
    Exit(False);
  end;
  try
    // Resolve ASCII case without a CLDR table. Preserve the spelling on disk.
    lParts := CronSplitChar(aName, '/');
    for lPart in lParts do
    begin
      lMatch := '';
      if FindFirst({$IFDEF FPC}(IncludeTrailingPathDelimiter(aPath) + '*'){$ELSE}TPath.Combine(aPath, '*'){$ENDIF}, faAnyFile, lSearch) = 0 then
      begin
        try
          repeat
            if CronSameTextAscii(lSearch.Name, lPart) then
            begin
              lMatch := lSearch.Name;
              Break;
            end;
          until FindNext(lSearch) <> 0;
        finally
          FindClose(lSearch);
        end;
      end;
      if lMatch = '' then
      begin
        aPath := {$IFDEF FPC}(IncludeTrailingPathDelimiter(aRoot) + CronReplaceTextAscii(aName, '/', PathDelim)){$ELSE}TPath.Combine(aRoot, StringReplace(aName, '/', PathDelim, [rfReplaceAll])){$ENDIF};
        aError := 'no TZif file at ' + aPath;
        Exit(False);
      end;
      aPath := {$IFDEF FPC}(IncludeTrailingPathDelimiter(aPath) + lMatch){$ELSE}TPath.Combine(aPath, lMatch){$ENDIF};
    end;
    {$IFDEF FPC}
    lHandle := FileOpen(aPath, fmOpenRead or fmShareDenyWrite);
    if lHandle = THandle(-1) then RaiseLastOSError;
    lStream := THandleStream.Create(lHandle);
    {$ELSE}
    lStream := TFileStream.Create(aPath, fmOpenRead or fmShareDenyWrite);
    {$ENDIF}
    try
      if lStream.Size > cMaxTzifSize then raise Exception.Create('TZif file exceeds 1 MiB');
      SetLength(lBytes, lStream.Size);
      if Length(lBytes) > 0 then lStream.ReadBuffer(lBytes[0], Length(lBytes));
    finally
      lStream.Free;
      {$IFDEF FPC} FileClose(lHandle); {$ENDIF}
    end;
    Result := TryParseCronTzif(lBytes, aSource, aError);
    if not Result then aError := 'invalid TZif data in ' + aPath + ': ' + aError;
  except
    on E: Exception do
    begin
      aError := 'invalid TZif data in ' + aPath + ': ' + CronExceptionText(E);
      Result := False;
    end;
  end;
end;

end.

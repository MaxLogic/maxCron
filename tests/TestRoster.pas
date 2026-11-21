unit TestRoster;
{$I ..\maxCron.inc}

interface

uses
  {$IFDEF FPC}SysUtils{$ELSE}System.SysUtils{$ENDIF};

type
  ERosterViolation = class(Exception)
  private
    fReason: string;
  public
    constructor Create(const aReason, aDetail: string);
    property Reason: string read fReason;
  end;

function ReportRosterFailure(const aError: Exception): Integer;

procedure BeginRoster(const aEntry: string);
procedure CheckRosterNames(const aNames: TArray<string>);
procedure RecordRosterTest(const aName: string);
procedure EndRoster(const aFound, aPassed, aFailed, aErrored, aIgnored: Integer);
function ExpectedRosterCount: Integer;

implementation

uses
  {$IFDEF FPC}
  Classes, System.Hash;
  {$ELSE}
  System.Classes, System.Hash;
  {$ENDIF}

var
  gExpected, gExecuted: TArray<string>;
  gEntry: string;

constructor ERosterViolation.Create(const aReason, aDetail: string);
begin
  inherited Create({$IFDEF FPC}AnsiString(aDetail){$ELSE}aDetail{$ENDIF});
  fReason := aReason;
end;

function ReportRosterFailure(const aError: Exception): Integer;
var
  lDetail: string;
  i: Integer;
begin
  Result := 2;
  if aError is ERosterViolation then
  begin
    lDetail := string(aError.Message);
    for i := 1 to Length(lDetail) do
      if CharInSet(lDetail[i], [#13, #10]) then lDetail[i] := ' ';
    WriteLn('ROSTER_PHASE phase=roster name=', gEntry, ' native_exit=5');
    WriteLn('ROSTER_REJECTED reason=', ERosterViolation(aError).Reason, ' detail=', lDetail);
    Result := 5;
  end else begin
    WriteLn('ROSTER_ERROR ', aError.ClassName, ': ', aError.Message);
  end;
end;

function FsPath(const aValue: string): {$IFDEF FPC}AnsiString{$ELSE}string{$ENDIF};
{$IFDEF FPC}
var
  lChar: Char;
{$ENDIF}
begin
  {$IFDEF FPC}
  // Same documented path domain as the native FPC gate. Never lose a path
  // character through its RTL's ANSI filesystem API.
  for lChar in aValue do
    if Ord(lChar) > 127 then raise Exception.Create('FPC roster source paths must be ASCII');
  Result := AnsiString(aValue);
  {$ELSE}
  Result := aValue;
  {$ENDIF}
end;

procedure AppendName(var aNames: TArray<string>; const aName: string);
var
  lIndex: Integer;
begin
  lIndex := Length(aNames);
  SetLength(aNames, lIndex + 1);
  aNames[lIndex] := aName;
end;

function SortedNames(const aNames: TArray<string>): TArray<string>;
var
  i, j: Integer;
  lValue: string;
begin
  Result := Copy(aNames, 0, Length(aNames));
  for i := 1 to High(Result) do
  begin
    lValue := Result[i];
    j := i;
    while (j > 0) and (Result[j - 1] > lValue) do
    begin
      Result[j] := Result[j - 1];
      Dec(j);
    end;
    Result[j] := lValue;
  end;
end;

function ManifestRelativePath(const aEntry: string): string;
begin
  Result := 'tests' + PathDelim + 'rosters' + PathDelim + aEntry + '.txt';
end;

function FindRepository(const aEntry: string): string;
var
  lDirectory, lParent: string;
  i: Integer;
begin
  Result := string(GetEnvironmentVariable('MAXCRON_TEST_ROOT'));
  if Result <> '' then Exit(string(IncludeTrailingPathDelimiter(ExpandFileName(FsPath(Result)))));
  for i := 0 to 1 do
  begin
    if i = 0 then lDirectory := string(GetCurrentDir) else lDirectory := string(ExtractFilePath(FsPath(ParamStr(0))));
    repeat
      lDirectory := string(IncludeTrailingPathDelimiter(ExpandFileName(FsPath(lDirectory))));
      if FileExists(FsPath(lDirectory + ManifestRelativePath(aEntry))) then Exit(lDirectory);
      lParent := string(ExtractFileDir(ExcludeTrailingPathDelimiter(FsPath(lDirectory))));
      if SameText(FsPath(lParent), ExcludeTrailingPathDelimiter(FsPath(lDirectory))) then Break;
      lDirectory := lParent;
    until lDirectory = '';
  end;
  raise Exception.Create('Test roster manifest not found; set MAXCRON_TEST_ROOT to the source checkout');
end;

procedure BeginRoster(const aEntry: string);
var
  lStream: TFileStream;
  lBytes: TBytes;
  lRoot, lLine, lRawLine, lPath, lHash, lContents: string;
  lParts: TArray<string>;
  lStamps, i: Integer;
begin
  gEntry := aEntry;
  for i := 1 to ParamCount do
    if not ((Copy(aEntry, 1, 6) = 'Delphi') and
      (SameText(FsPath(ParamStr(i)), '-cm:Quiet') or SameText(FsPath(ParamStr(i)), '--cm:Quiet') or
      SameText(FsPath(ParamStr(i)), '--consolemode:quiet'))) then
      raise ERosterViolation.Create('count', 'Test entry points require the complete roster; test selection arguments are not accepted');
  gExpected := nil;
  gExecuted := nil;
  gEntry := aEntry;
  lRoot := FindRepository(aEntry);
  lStream := TFileStream.Create(FsPath(lRoot + ManifestRelativePath(aEntry)), fmOpenRead or fmShareDenyWrite);
  try
    if lStream.Size > MaxInt then raise Exception.Create('Test roster manifest is too large');
    SetLength(lBytes, NativeInt(lStream.Size));
    if Length(lBytes) > 0 then lStream.ReadBuffer(lBytes[0], Length(lBytes));
    lContents := TEncoding.UTF8.GetString(lBytes);
  finally
    lStream.Free;
  end;
  if (lContents <> '') and (Ord(lContents[1]) = $FEFF) then Delete(lContents, 1, 1);
  lStamps := 0;
  for lRawLine in lContents.Split([#10]) do
  begin
    lLine := lRawLine;
    if (lLine <> '') and (lLine[Length(lLine)] = #13) then Delete(lLine, Length(lLine), 1);
    if Copy(lLine, 1, 9) = '# SHA256 ' then
    begin
      lParts := lLine.Split([' ']);
      if Length(lParts) <> 4 then raise ERosterViolation.Create('stale', 'Invalid test roster source stamp');
      lPath := string(ExpandFileName(FsPath(lRoot + lParts[2])));
      if not SameText(FsPath(Copy(lPath, 1, Length(lRoot))), FsPath(lRoot)) then
        raise ERosterViolation.Create('stale', 'Test roster source escapes the checkout');
      lHash := THashSHA2.GetHashStringFromFile(FsPath(lPath));
      if not SameText(FsPath(lHash), FsPath(lParts[3])) then
        raise ERosterViolation.Create('stale', string(FsPath('Test roster manifest is stale: ' + lParts[2] + '; run tests/Export-TestRosters.ps1')));
      Inc(lStamps);
    end else if (lLine <> '') and (lLine[1] <> '#') then
      AppendName(gExpected, lLine);
  end;
  if (lStamps = 0) or (Length(gExpected) = 0) then raise ERosterViolation.Create('empty', 'Empty test roster manifest');
  gExpected := SortedNames(gExpected);
  for i := 1 to High(gExpected) do
    if gExpected[i] = gExpected[i - 1] then raise ERosterViolation.Create('duplicate', 'Duplicate identity in test roster manifest');
  WriteLn('ROSTER_PHASE phase=roster name=', gEntry, ' native_exit=0');
end;

procedure CheckRosterNames(const aNames: TArray<string>);
var
  lSorted: TArray<string>;
  i: Integer;
begin
  if Length(gExpected) = 0 then raise ERosterViolation.Create('empty', 'Test roster manifest was not loaded');
  lSorted := SortedNames(aNames);
  if Length(lSorted) = 0 then raise ERosterViolation.Create('empty', 'Empty actual test roster');
  for i := 1 to High(lSorted) do
    if lSorted[i] = lSorted[i - 1] then raise ERosterViolation.Create('duplicate', 'Duplicate actual test identity');
  if Length(lSorted) < Length(gExpected) then raise ERosterViolation.Create('missing', 'Missing test identities');
  if Length(lSorted) > Length(gExpected) then raise ERosterViolation.Create('extra', 'Extra test identities');
  for i := 0 to High(gExpected) do
    if lSorted[i] <> gExpected[i] then raise ERosterViolation.Create('renamed', 'Test roster identity differs');
  WriteLn('ROSTER_PHASE phase=roster name=', gEntry, ' native_exit=0');
end;

procedure RecordRosterTest(const aName: string);
begin
  AppendName(gExecuted, aName);
  WriteLn('ROSTER_TEST ', aName);
end;

procedure EndRoster(const aFound, aPassed, aFailed, aErrored, aIgnored: Integer);
begin
  if (aFound <= 0) or (aFound <> aPassed) or (aFailed <> 0) or
    (aErrored <> 0) or (aIgnored <> 0) then
    raise Exception.Create('Test roster result counts are incomplete or unsuccessful');
  if Length(gExecuted) <> aFound then raise ERosterViolation.Create('count', 'Test roster executed count differs from Found');
  CheckRosterNames(gExecuted);
  WriteLn('ROSTER_VERIFIED ', gEntry, ' expected=', Length(gExpected), ' found=', aFound, ' passed=', aPassed);
end;

function ExpectedRosterCount: Integer;
begin
  if Length(gExpected) = 0 then raise ERosterViolation.Create('empty', 'Test roster manifest was not loaded');
  Result := Length(gExpected);
end;

{$IFDEF FPC}
initialization
  SetTextCodePage(Output, 65001);
{$ENDIF}
end.

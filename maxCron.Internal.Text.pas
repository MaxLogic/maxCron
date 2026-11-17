unit maxCron.Internal.Text;
{$I maxCron.inc}

interface

uses
  {$IFDEF FPC} SysUtils; {$ELSE} System.SysUtils; {$ENDIF}

function CronTryStrToInt(const s: string; out aValue: Integer): Boolean;
function CronTryStrToInt64(const s: string; out aValue: Int64): Boolean;
function CronStrToInt(const s: string): Integer;
function CronStrToInt64(const s: string): Int64;
function CronStrToIntDef(const s: string; const aDefault: Integer): Integer;
function CronTryStrToFloatInvariant(const s: string; out aValue: Double): Boolean;
function CronIntToStr(const aValue: Int64): string;
function CronUIntToStr(const aValue: UInt64): string;
function CronUpperAscii(const s: string): string;
function CronLowerAscii(const s: string): string;
function CronSameTextAscii(const a, b: string): Boolean;
function CronReplaceTextAscii(const s, aPattern, aReplacement: string): string;
function CronSplitChar(const s: string; const aDelim: Char): TArray<string>;
function CronSplitWhitespace(const s: string): TArray<string>;
function CronExceptionText(const E: Exception): string;

implementation

{$IFDEF FPC}
const
  cCronInvalidIntegerText = '''%s'' is not a valid integer value';

function IsIntegerAlphabet(const s: string): Boolean;
var
  c: Char;
begin
  for c in s do
    if not CharInSet(c, [' ', '+', '-', '$', 'x', 'X', '0'..'9', 'A'..'F', 'a'..'f']) then
      Exit(False);
  Result := True;
end;

function TrySpecialFloat(const s: string; out aValue: Double): Boolean;
const
  cPositiveInf: UInt64 = $7FF0000000000000;
  cNegativeInf: UInt64 = UInt64($FFF0000000000000);
  cQuietNan: UInt64 = UInt64($FFF8000000000000);
var
  i: Integer;
  lText: string;
  lBits: UInt64;
begin
  i := 1;
  while (i <= Length(s)) and (s[i] = ' ') do Inc(i);
  lText := CronUpperAscii(Copy(s, i, MaxInt));
  // Delphi accepts leading spaces, signed INF and unsigned NAN, without a suffix.
  if (lText = 'INF') or (lText = '+INF') then lBits := cPositiveInf
  else if lText = '-INF' then lBits := cNegativeInf
  else if lText = 'NAN' then lBits := cQuietNan
  else Exit(False);
  Move(lBits, aValue, SizeOf(aValue));
  Result := True;
end;

function IsFloatSyntax(const s: string): Boolean;
var
  i, lDigits: Integer;
begin
  i := 1;
  while (i <= Length(s)) and (s[i] = ' ') do Inc(i);
  if (i <= Length(s)) and CharInSet(s[i], ['+', '-']) then Inc(i);
  lDigits := 0;
  while (i <= Length(s)) and CharInSet(s[i], ['0'..'9']) do
  begin
    Inc(i);
    Inc(lDigits);
  end;
  if (i <= Length(s)) and (s[i] = '.') then
  begin
    Inc(i);
    while (i <= Length(s)) and CharInSet(s[i], ['0'..'9']) do
    begin
      Inc(i);
      Inc(lDigits);
    end;
  end;
  if lDigits = 0 then Exit(False);
  if (i <= Length(s)) and CharInSet(s[i], ['e', 'E']) then
  begin
    Inc(i);
    if (i <= Length(s)) and CharInSet(s[i], ['+', '-']) then Inc(i);
    lDigits := 0;
    while (i <= Length(s)) and CharInSet(s[i], ['0'..'9']) do
    begin
      Inc(i);
      Inc(lDigits);
    end;
    if lDigits = 0 then Exit(False);
  end;
  while (i <= Length(s)) and (s[i] = ' ') do Inc(i);
  Result := i > Length(s);
end;
{$ENDIF}

function CronTryStrToInt(const s: string; out aValue: Integer): Boolean;
begin
  {$IFDEF FPC}
  aValue := 0;
  Result := IsIntegerAlphabet(s) and TryStrToInt(AnsiString(s), aValue);
  {$ELSE}
  Result := TryStrToInt(s, aValue);
  {$ENDIF}
end;

function CronTryStrToInt64(const s: string; out aValue: Int64): Boolean;
begin
  {$IFDEF FPC}
  aValue := 0;
  Result := IsIntegerAlphabet(s) and TryStrToInt64(AnsiString(s), aValue);
  {$ELSE}
  Result := TryStrToInt64(s, aValue);
  {$ENDIF}
end;

function CronStrToInt(const s: string): Integer;
begin
  {$IFDEF FPC}
  if not CronTryStrToInt(s, Result) then
    raise EConvertError.CreateFmt(cCronInvalidIntegerText, [s]);
  {$ELSE}
  Result := StrToInt(s);
  {$ENDIF}
end;

function CronStrToInt64(const s: string): Int64;
begin
  {$IFDEF FPC}
  if not CronTryStrToInt64(s, Result) then
    raise EConvertError.CreateFmt(cCronInvalidIntegerText, [s]);
  {$ELSE}
  Result := StrToInt64(s);
  {$ENDIF}
end;

function CronStrToIntDef(const s: string; const aDefault: Integer): Integer;
begin
  {$IFDEF FPC}
  if not CronTryStrToInt(s, Result) then Result := aDefault;
  {$ELSE}
  Result := StrToIntDef(s, aDefault);
  {$ENDIF}
end;

function CronTryStrToFloatInvariant(const s: string; out aValue: Double): Boolean;
{$IFDEF FPC}
var
  c: Char;
{$ENDIF}
begin
  {$IFDEF FPC}
  aValue := 0;
  if TrySpecialFloat(s, aValue) then Exit(True);
  for c in s do
    if not CharInSet(c, [' ', '+', '-', '.', 'e', 'E', '0'..'9']) then Exit(False);
  if not IsFloatSyntax(s) then Exit(False);
  Result := TryStrToFloat(AnsiString(s), aValue, TFormatSettings.Invariant);
  {$ELSE}
  Result := TryStrToFloat(s, aValue, TFormatSettings.Invariant);
  {$ENDIF}
end;

function CronIntToStr(const aValue: Int64): string;
begin
  Result := string(IntToStr(aValue));
end;

function CronUIntToStr(const aValue: UInt64): string;
begin
  Result := string(UIntToStr(aValue));
end;

function CronUpperAscii(const s: string): string;
var
  i: Integer;
begin
  Result := s;
  for i := 1 to Length(Result) do
    if (Result[i] >= 'a') and (Result[i] <= 'z') then
      Result[i] := Char(Ord(Result[i]) - 32);
end;

function CronLowerAscii(const s: string): string;
var
  i: Integer;
begin
  Result := s;
  for i := 1 to Length(Result) do
    if (Result[i] >= 'A') and (Result[i] <= 'Z') then
      Result[i] := Char(Ord(Result[i]) + 32);
end;

function CronSameTextAscii(const a, b: string): Boolean;
begin
  Result := CronUpperAscii(a) = CronUpperAscii(b);
end;

function CronReplaceTextAscii(const s, aPattern, aReplacement: string): string;
var
  i, lStart, lSize: Integer;
  lUpper, lPattern: string;
begin
  if aPattern = '' then Exit(s);
  lUpper := CronUpperAscii(s);
  lPattern := CronUpperAscii(aPattern);
  lSize := Length(aPattern);
  Result := '';
  lStart := 1;
  i := 1;
  while i <= Length(s) - lSize + 1 do
  begin
    if Copy(lUpper, i, lSize) = lPattern then
    begin
      Result := Result + Copy(s, lStart, i - lStart) + aReplacement;
      Inc(i, lSize);
      lStart := i;
    end else
      Inc(i);
  end;
  Result := Result + Copy(s, lStart, MaxInt);
end;

function CronSplitChar(const s: string; const aDelim: Char): TArray<string>;
var
  i, lStart, lCount: Integer;
begin
  Result := nil;
  lStart := 1;
  lCount := 0;
  for i := 1 to Length(s) do
    if s[i] = aDelim then
    begin
      SetLength(Result, lCount + 1);
      Result[lCount] := Copy(s, lStart, i - lStart);
      Inc(lCount);
      lStart := i + 1;
    end;
  if lStart <= Length(s) then
  begin
    SetLength(Result, lCount + 1);
    Result[lCount] := Copy(s, lStart, MaxInt);
  end;
end;

function CronSplitWhitespace(const s: string): TArray<string>;
var
  i, lStart, lCount: Integer;
begin
  Result := nil;
  i := 1;
  lCount := 0;
  while i <= Length(s) do
  begin
    if s[i] <= ' ' then
      Inc(i)
    else begin
      lStart := i;
      while (i <= Length(s)) and (s[i] > ' ') do Inc(i);
      SetLength(Result, lCount + 1);
      Result[lCount] := Copy(s, lStart, i - lStart);
      Inc(lCount);
    end;
  end;
end;

function CronExceptionText(const E: Exception): string;
begin
  Result := string(E.Message);
end;

end.

unit TestEnvironment;
{$I maxCron.inc}

interface

uses
  {$IFDEF FPC} SysUtils {$ELSE} System.SysUtils {$ENDIF};

type
  TTestEnvSnapshot = record
  private
    fName: string;
    {$IFDEF MSWINDOWS}
    fValue: string;
    {$ELSE}
    fValue: TBytes;
    {$ENDIF}
    fPresent: Boolean;
  end;

function GetTestEnvironmentVariable(const aName: string): string;
function TryGetTestEnvironmentVariable(const aName: string; out aValue: string): Boolean;
function SaveTestEnvironmentVariable(const aName: string): TTestEnvSnapshot;
procedure RestoreTestEnvironmentVariable(const aSnapshot: TTestEnvSnapshot);
procedure SetTestEnvironmentVariable(const aName, aValue: string);
procedure UnsetTestEnvironmentVariable(const aName: string);
{$IFNDEF MSWINDOWS}
procedure TestLibcTzset; cdecl;
function TestLibcLocaltimeOffsetSeconds(const aUnixSeconds: Int64): Int64;
procedure TestLibcSymlink(const aTarget, aLink: string);
{$ENDIF}

implementation

{$IFDEF MSWINDOWS}
uses
  {$IFDEF FPC} Windows {$ELSE} Winapi.Windows {$ENDIF};
{$ENDIF}

{$IFNDEF MSWINDOWS}
const
  cTestLibC = {$IFDEF FPC}'c'{$ELSE}'libc.so.6'{$ENDIF};

type
  // glibc struct tm on LP64.
  TTestLibcTm = record
    Sec, Min, Hour, MDay, Mon, Year, WDay, YDay, IsDst, Pad: Int32;
    GmtOff: Int64;
    Zone: PAnsiChar;
  end;
  PTestLibcTm = ^TTestLibcTm;

function TestLibcGetenv(aName: PAnsiChar): PAnsiChar; cdecl;
  external cTestLibC name 'getenv';
function TestLibcSetenv(aName, aValue: PAnsiChar; aOverwrite: Int32): Int32; cdecl;
  external cTestLibC name 'setenv';
function TestLibcUnsetenv(aName: PAnsiChar): Int32; cdecl;
  external cTestLibC name 'unsetenv';
procedure TestLibcTzset; cdecl;
  external cTestLibC name 'tzset';
function TestLibcLocaltimeR(const aUnixSeconds: PInt64; const aTm: PTestLibcTm): PTestLibcTm; cdecl;
  external cTestLibC name 'localtime_r';
function TestLibcCreateSymlink(aTarget, aLink: PAnsiChar): Int32; cdecl;
  external cTestLibC name 'symlink';

function TestLibcLocaltimeOffsetSeconds(const aUnixSeconds: Int64): Int64;
var
  lTm: TTestLibcTm;
begin
  if TestLibcLocaltimeR(@aUnixSeconds, @lTm) = nil then
    RaiseLastOSError;
  Result := lTm.GmtOff;
end;

procedure TestLibcSymlink(const aTarget, aLink: string);
begin
  if TestLibcCreateSymlink(PAnsiChar(UTF8String(aTarget)), PAnsiChar(UTF8String(aLink))) <> 0 then
    RaiseLastOSError;
end;
{$ENDIF}

function GetTestEnvironmentVariable(const aName: string): string;
begin
  {$IFDEF MSWINDOWS}
  Result := {$IFDEF FPC}SysUtils{$ELSE}System.SysUtils{$ENDIF}.GetEnvironmentVariable(aName);
  {$ELSE}
  TryGetTestEnvironmentVariable(aName, Result);
  {$ENDIF}
end;

function TryGetTestEnvironmentVariable(const aName: string; out aValue: string): Boolean;
{$IFDEF MSWINDOWS}
var
  lSize: DWORD;
begin
  SetLastError(ERROR_SUCCESS);
  lSize := GetEnvironmentVariableW(PWideChar(aName), nil, 0);
  Result := (lSize <> 0) or (GetLastError <> ERROR_ENVVAR_NOT_FOUND);
  SetLength(aValue, lSize);
  if lSize <> 0 then
    SetLength(aValue, GetEnvironmentVariableW(PWideChar(aName), PWideChar(aValue), lSize));
{$ELSE}
var
  lValue: PAnsiChar;
begin
  lValue := TestLibcGetenv(PAnsiChar(UTF8String(aName)));
  Result := lValue <> nil;
  aValue := '';
  if Result then
    aValue := UTF8ToString(lValue);
{$ENDIF}
end;

function SaveTestEnvironmentVariable(const aName: string): TTestEnvSnapshot;
{$IFNDEF MSWINDOWS}
var
  lValue: PAnsiChar;
  lLength: NativeInt;
{$ENDIF}
begin
  Result := Default(TTestEnvSnapshot);
  Result.fName := aName;
  {$IFDEF MSWINDOWS}
  Result.fPresent := TryGetTestEnvironmentVariable(aName, Result.fValue);
  {$ELSE}
  lValue := TestLibcGetenv(PAnsiChar(UTF8String(aName)));
  Result.fPresent := lValue <> nil;
  if Result.fPresent then
  begin
    lLength := 0;
    while lValue[lLength] <> #0 do
      Inc(lLength);
    SetLength(Result.fValue, lLength + 1);
    Move(lValue^, Result.fValue[0], lLength + 1);
  end;
  {$ENDIF}
end;

procedure RestoreTestEnvironmentVariable(const aSnapshot: TTestEnvSnapshot);
begin
  // A fixture setting several variables may exit before capturing all of them.
  if aSnapshot.fName = '' then
    Exit;
  if not aSnapshot.fPresent then
  begin
    UnsetTestEnvironmentVariable(aSnapshot.fName);
    Exit;
  end;
  {$IFDEF MSWINDOWS}
  SetTestEnvironmentVariable(aSnapshot.fName, aSnapshot.fValue);
  {$ELSE}
  if TestLibcSetenv(PAnsiChar(UTF8String(aSnapshot.fName)),
    PAnsiChar(@aSnapshot.fValue[0]), 1) <> 0 then
    RaiseLastOSError;
  {$ENDIF}
end;

procedure SetTestEnvironmentVariable(const aName, aValue: string);
{$IFDEF MSWINDOWS}
var
  c: WideChar;
begin
  // An empty value needs a non-nil pointer so it remains set.
  c := #0;
  if aValue = '' then
  begin
    if not SetEnvironmentVariableW(PWideChar(aName), @c) then
      RaiseLastOSError;
  end else if not SetEnvironmentVariableW(PWideChar(aName), PWideChar(aValue)) then
    RaiseLastOSError;
{$ELSE}
begin
  if TestLibcSetenv(PAnsiChar(UTF8String(aName)), PAnsiChar(UTF8String(aValue)), 1) <> 0 then
    RaiseLastOSError;
{$ENDIF}
end;

procedure UnsetTestEnvironmentVariable(const aName: string);
begin
  {$IFDEF MSWINDOWS}
  if not SetEnvironmentVariableW(PWideChar(aName), nil) then
    RaiseLastOSError;
  {$ELSE}
  if TestLibcUnsetenv(PAnsiChar(UTF8String(aName))) <> 0 then
    RaiseLastOSError;
  {$ENDIF}
end;

end.

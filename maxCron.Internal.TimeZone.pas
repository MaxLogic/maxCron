unit maxCron.Internal.TimeZone;
{$I maxCron.inc}

interface

uses
  System.SysUtils;

type
  ICronTimeZone = interface
    ['{F0CCDB2D-3702-41A6-B483-0522A41B7F8B}']
    function ToUniversalTime(const aLocal: TDateTime; const aForceDaylight: Boolean): TDateTime;
    function ToLocalTime(const aUtc: TDateTime): TDateTime;
    function IsAmbiguousTime(const aLocal: TDateTime): Boolean;
    function IsInvalidTime(const aLocal: TDateTime): Boolean;
  end;

// Re-reads the RTL system zone on every call, including its exception behavior.
function CronSystemTimeZone: ICronTimeZone;
{$IFDEF MAXCRON_TESTS}
// Set before creating a scheduler; nil restores the RTL zone. Tests run serially.
procedure SetCronSystemTimeZoneForTests(const aZone: ICronTimeZone);
{$ENDIF}

implementation

uses
  System.DateUtils;

type
  TCronRtlLocalTimeZone = class(TInterfacedObject, ICronTimeZone)
  public
    function ToUniversalTime(const aLocal: TDateTime; const aForceDaylight: Boolean): TDateTime;
    function ToLocalTime(const aUtc: TDateTime): TDateTime;
    function IsAmbiguousTime(const aLocal: TDateTime): Boolean;
    function IsInvalidTime(const aLocal: TDateTime): Boolean;
  end;

var
  gSystemTimeZone: ICronTimeZone;
{$IFDEF MAXCRON_TESTS}
  gTestTimeZone: ICronTimeZone;

procedure SetCronSystemTimeZoneForTests(const aZone: ICronTimeZone);
begin
  gTestTimeZone := aZone;
end;
{$ENDIF}

function CronSystemTimeZone: ICronTimeZone;
begin
{$IFDEF MAXCRON_TESTS}
  if Assigned(gTestTimeZone) then
    Exit(gTestTimeZone);
{$ENDIF}
  Result := gSystemTimeZone;
end;

function TCronRtlLocalTimeZone.ToUniversalTime(const aLocal: TDateTime;
  const aForceDaylight: Boolean): TDateTime;
begin
  Result := TTimeZone.Local.ToUniversalTime(aLocal, aForceDaylight);
end;

function TCronRtlLocalTimeZone.ToLocalTime(const aUtc: TDateTime): TDateTime;
begin
  Result := TTimeZone.Local.ToLocalTime(aUtc);
end;

function TCronRtlLocalTimeZone.IsAmbiguousTime(const aLocal: TDateTime): Boolean;
begin
  Result := TTimeZone.Local.IsAmbiguousTime(aLocal);
end;

function TCronRtlLocalTimeZone.IsInvalidTime(const aLocal: TDateTime): Boolean;
begin
  Result := TTimeZone.Local.IsInvalidTime(aLocal);
end;

initialization
  gSystemTimeZone := TCronRtlLocalTimeZone.Create;

finalization
  gSystemTimeZone := nil;

end.

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

function CronSystemTimeZone: ICronTimeZone;
begin
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

unit maxCron.Internal.Platform;
{$I maxCron.inc}

interface

uses
  System.Classes, System.SysUtils;

type
  {$SCOPEDENUMS ON}
  // Delivery thread; the factory preserves the existing timer implementations.
  TCronTickSourceKind = (tskMainThread, tskWorkerThread);
  {$SCOPEDENUMS OFF}

  ICronTickSource = interface
    ['{4F31A17D-83A7-4250-ACF5-6C38B49053A9}']
    procedure SetOnTick(const aHandler: TNotifyEvent);
    procedure Start(const aIntervalMs: Cardinal);
    procedure Stop;
  end;

function CreateCronTickSource(const aKind: TCronTickSourceKind): ICronTickSource;
function CronMaxAsyncCall(const aProc: TThreadProcedure; const aTaskName: string): IInterface;
procedure CronDebugOutput(const aText: string);
function CronGetEnvironmentVariable(const aName: string): string;

implementation

uses
  {$IFDEF MSWINDOWS} Winapi.Windows, {$ENDIF}
  Vcl.ExtCtrls,
  maxAsync, MaxLogic.PortableTimer;

type
  TCronVclTickSource = class(TInterfacedObject, ICronTickSource)
  private
    fTimer: Vcl.ExtCtrls.TTimer;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Start(const aIntervalMs: Cardinal);
    procedure Stop;
    procedure SetOnTick(const aHandler: TNotifyEvent);
  end;

  TCronPortableTickSource = class(TInterfacedObject, ICronTickSource)
  private
    fTimer: MaxLogic.PortableTimer.TPortableTimer;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Start(const aIntervalMs: Cardinal);
    procedure Stop;
    procedure SetOnTick(const aHandler: TNotifyEvent);
  end;

constructor TCronVclTickSource.Create;
begin
  inherited Create;
  fTimer := Vcl.ExtCtrls.TTimer.Create(nil);
end;

destructor TCronVclTickSource.Destroy;
begin
  fTimer.Free;
  inherited;
end;

procedure TCronVclTickSource.Start(const aIntervalMs: Cardinal);
begin
  fTimer.Interval := aIntervalMs;
  fTimer.Enabled := True;
end;

procedure TCronVclTickSource.Stop;
begin
  fTimer.Enabled := False;
end;

procedure TCronVclTickSource.SetOnTick(const aHandler: TNotifyEvent);
begin
  fTimer.OnTimer := aHandler;
end;

constructor TCronPortableTickSource.Create;
begin
  inherited Create;
  fTimer := MaxLogic.PortableTimer.TPortableTimer.Create;
end;

destructor TCronPortableTickSource.Destroy;
begin
  fTimer.Free;
  inherited;
end;

procedure TCronPortableTickSource.Start(const aIntervalMs: Cardinal);
begin
  fTimer.Start(aIntervalMs);
end;

procedure TCronPortableTickSource.Stop;
begin
  fTimer.Stop;
end;

procedure TCronPortableTickSource.SetOnTick(const aHandler: TNotifyEvent);
begin
  fTimer.OnTimer := aHandler;
end;

function CreateCronTickSource(const aKind: TCronTickSourceKind): ICronTickSource;
begin
  case aKind of
    TCronTickSourceKind.tskWorkerThread:
      Result := TCronPortableTickSource.Create;
  else
    Result := TCronVclTickSource.Create;
  end;
end;

function CronMaxAsyncCall(const aProc: TThreadProcedure; const aTaskName: string): IInterface;
begin
  Result := maxAsync.SimpleAsyncCall(aProc, aTaskName);
end;

procedure CronDebugOutput(const aText: string);
begin
  {$IFDEF MSWINDOWS}
  Winapi.Windows.OutputDebugString(PChar(aText));
  {$ENDIF}
end;

function CronGetEnvironmentVariable(const aName: string): string;
begin
  Result := System.SysUtils.GetEnvironmentVariable(aName);
end;

end.

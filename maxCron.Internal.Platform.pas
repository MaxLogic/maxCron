unit maxCron.Internal.Platform;
{$I maxCron.inc}

interface

uses
  {$IFDEF FPC}
  Classes, SysUtils
  {$ELSE}
  System.Classes, System.SysUtils
  {$ENDIF};

type
  {$SCOPEDENUMS ON}
  TCronWaitResolution = (HighResolution, TimerPeriod, SystemDefault);
  {$SCOPEDENUMS OFF}
  TCronTickDelayFunc = function: Int64 of object;
  TCronTickSourceDiagnostics = record
    TicksDelivered: UInt64;
    SpinGuardHits: UInt64;
    TickExceptions: UInt64;
  end;

  ICronTickSource = interface
    ['{7C53E039-BC5D-4F7A-953D-29602A8BB8FD}']
    procedure SetOnTick(const aHandler: TNotifyEvent);
    procedure SetDelayProvider(const aProvider: TCronTickDelayFunc);
    procedure Start(const aMaxSleepMs: Cardinal);
    procedure Stop;
    procedure Shutdown;
    procedure Wake;
    function GetResolution: TCronWaitResolution;
    function GetDiagnostics: TCronTickSourceDiagnostics;
  end;

function CreateCronTickSource(const aPreferred: TCronWaitResolution): ICronTickSource;
function CronMonotonicNowUs: Int64;
function CronPreciseLocalNowUs: Int64;
function CronPreciseUtcNowUs: Int64;
function CronMaxAsyncCall(const aProc: TThreadProcedure; const aTaskName: string): IInterface;
procedure CronDebugOutput(const aText: string);
function CronGetEnvironmentVariable(const aName: string): string;

implementation

uses
  {$IFDEF FPC}
  // Windows before SyncObjs: Windows.TCriticalSection would hide the class.
  {$IFDEF MSWINDOWS} MMSystem, Windows, {$ENDIF}
  Math, SyncObjs, System.Diagnostics, System.Threading,
  {$ELSE}
  System.Diagnostics, System.Math, System.SyncObjs,
  {$IFDEF MSWINDOWS} Winapi.MMSystem, Winapi.Windows, {$ENDIF}
  maxAsync,
  {$ENDIF}
  {$IFNDEF MSWINDOWS} Posix.Time, {$ENDIF}
  maxCron.Internal.Text;

{$IFDEF FPC}
function CreateWaitableTimerExW(aAttributes: Pointer; aName: PWideChar; aFlags, aAccess: DWORD): THandle;
  stdcall; external 'kernel32.dll' name 'CreateWaitableTimerExW';
{$ENDIF}

type
  TCronWaiter = class
  private
    fWake: TEvent;
    fResolution: TCronWaitResolution;
    {$IFDEF MSWINDOWS}
    fTimer: THandle;
    {$ENDIF}
  public
    constructor Create(const aPreferred: TCronWaitResolution);
    destructor Destroy; override;
    function Wait(const aDelayUs: Int64): Boolean;
    procedure Wake;
  end;

  TCronDeadlineTickSource = class;
  TCronDeadlineThread = class(TThread)
  private
    fSource: TCronDeadlineTickSource;
  protected
    procedure Execute; override;
  public
    constructor Create(const aSource: TCronDeadlineTickSource);
  end;

  TCronDeadlineTickSource = class(TInterfacedObject, ICronTickSource)
  private
    fLock: TCriticalSection;
    fWaiter: TCronWaiter;
    fThread: TCronDeadlineThread;
    fOnTick: TNotifyEvent;
    fProvider: TCronTickDelayFunc;
    fRunning: Integer;
    fMaxSleepMs: Integer;
    fTicksDelivered, fSpinGuardHits, fTickExceptions: Int64;
  public
    constructor Create(const aPreferred: TCronWaitResolution);
    destructor Destroy; override;
    procedure SetOnTick(const aHandler: TNotifyEvent);
    procedure SetDelayProvider(const aProvider: TCronTickDelayFunc);
    procedure Start(const aMaxSleepMs: Cardinal);
    procedure Stop;
    procedure Shutdown;
    procedure Wake;
    function GetResolution: TCronWaitResolution;
    function GetDiagnostics: TCronTickSourceDiagnostics;
  end;

{$IFDEF MSWINDOWS}
type
  TCronPreciseTimeProc = procedure(out aFileTime: TFileTime); stdcall;
var
  gCronPreciseTime: TCronPreciseTimeProc;
{$ENDIF}

function CronMonotonicNowUs: Int64;
var
  lTicks, lFrequency: Int64;
begin
  lTicks := TStopwatch.GetTimeStamp;
  lFrequency := TStopwatch.Frequency;
  Result := (lTicks div lFrequency) * 1000000 +
    ((lTicks mod lFrequency) * 1000000) div lFrequency;
end;

function CronPreciseUtcNowUs: Int64;
{$IFDEF MSWINDOWS}
var
  lUtc: TFileTime;
  lValue: UInt64;
begin
  if Assigned(gCronPreciseTime) then gCronPreciseTime(lUtc)
  else GetSystemTimeAsFileTime(lUtc);
  lValue := (UInt64(lUtc.dwHighDateTime) shl 32) or lUtc.dwLowDateTime;
  Result := Int64(lValue div 10) - Int64(109205) * 86400000000;
{$ELSE}
var
  lTime: timespec;
begin
  if clock_gettime(CLOCK_REALTIME, lTime) <> 0 then RaiseLastOSError;
  Result := Int64(lTime.tv_sec) * 1000000 + lTime.tv_nsec div 1000 + Int64(25569) * 86400000000;
{$ENDIF}
end;

function CronPreciseLocalNowUs: Int64;
{$IFDEF MSWINDOWS}
var
  lUtc, lLocal: TFileTime;
  lValue: UInt64;
begin
  if Assigned(gCronPreciseTime) then
    gCronPreciseTime(lUtc)
  else
    GetSystemTimeAsFileTime(lUtc);
  if not FileTimeToLocalFileTime(lUtc, lLocal) then
    RaiseLastOSError;
  lValue := (UInt64(lLocal.dwHighDateTime) shl 32) or lLocal.dwLowDateTime;
  Result := Int64(lValue div 10) - Int64(109205) * 86400000000;
{$ELSE}
begin
  Result := Round(Now * 86400000000.0);
{$ENDIF}
end;

constructor TCronWaiter.Create(const aPreferred: TCronWaitResolution);
{$IFDEF MSWINDOWS}
const
  cCreateWaitableTimerHighResolution = $00000002;
  cTimerAllAccess = $001F0003;
{$ENDIF}
begin
  inherited Create;
  fWake := TEvent.Create(nil, False, False, '');
  fResolution := TCronWaitResolution.SystemDefault;
  {$IFDEF MSWINDOWS}
  fResolution := aPreferred;
  if aPreferred = TCronWaitResolution.HighResolution then
  begin
    fTimer := CreateWaitableTimerExW(nil, nil, cCreateWaitableTimerHighResolution, cTimerAllAccess);
    if fTimer = 0 then
      fResolution := TCronWaitResolution.TimerPeriod;
  end;
  {$ENDIF}
end;

destructor TCronWaiter.Destroy;
begin
  {$IFDEF MSWINDOWS}
  if fTimer <> 0 then
    CloseHandle(fTimer);
  {$ENDIF}
  fWake.Free;
  inherited;
end;

procedure TCronWaiter.Wake;
begin
  fWake.SetEvent;
end;

function TCronWaiter.Wait(const aDelayUs: Int64): Boolean;
var
  lDelayUs: Int64;
  lStartedUs: Int64;
  lPeriodActive: Boolean;
  {$IFDEF MSWINDOWS}
  lDue: TLargeInteger;
  lHandles: array[0..1] of THandle;
  lResult: Cardinal;
  {$ENDIF}
begin
  // The source clamps waits to one second, including the spin guard.
  lDelayUs := EnsureRange(aDelayUs, Int64(1), Int64(1000000));
  {$IFDEF MSWINDOWS}
  if fResolution = TCronWaitResolution.HighResolution then
  begin
    lDue := -lDelayUs * 10;
    if SetWaitableTimer(fTimer, lDue, 0, nil, nil, False) then
    begin
      lHandles[0] := THandle(fWake.Handle);
      lHandles[1] := fTimer;
      lResult := WaitForMultipleObjects(2, @lHandles[0], False, Cardinal((lDelayUs + 999) div 1000) + 1000);
      if lResult = WAIT_FAILED then
        RaiseLastOSError;
      Exit(lResult = WAIT_OBJECT_0);
    end;
  end;
  if fResolution = TCronWaitResolution.TimerPeriod then
  begin
    lStartedUs := CronMonotonicNowUs;
    if lDelayUs > 20000 then
    begin
      if fWake.WaitFor(Cardinal((lDelayUs - 20000 + 999) div 1000)) = wrSignaled then
        Exit(True);
      lDelayUs := Max(Int64(1), aDelayUs - (CronMonotonicNowUs - lStartedUs));
    end;
    lPeriodActive := timeBeginPeriod(1) = TIMERR_NOERROR;
    try
      Result := fWake.WaitFor(Cardinal((lDelayUs + 999) div 1000)) = wrSignaled;
    finally
      if lPeriodActive then
        timeEndPeriod(1);
    end;
    Exit;
  end;
  {$ENDIF}
  Result := fWake.WaitFor(Cardinal((lDelayUs + 999) div 1000)) = wrSignaled;
end;

constructor TCronDeadlineThread.Create(const aSource: TCronDeadlineTickSource);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  fSource := aSource;
end;

procedure TCronDeadlineThread.Execute;
var
  lDelayUs: Int64;
  lZeroStreak: Integer;
  lHandler: TNotifyEvent;
  lProvider: TCronTickDelayFunc;
begin
  lZeroStreak := 0;
  while not Terminated do
  begin
    if TInterlocked.CompareExchange(fSource.fRunning, 0, 0) = 0 then
    begin
      fSource.fWaiter.Wait(1000000);
      Continue;
    end;
    fSource.fLock.Acquire;
    try
      lProvider := fSource.fProvider;
      lHandler := fSource.fOnTick;
    finally
      fSource.fLock.Release;
    end;
    lDelayUs := Int64(TInterlocked.CompareExchange(fSource.fMaxSleepMs, 0, 0)) * 1000;
    try
      if Assigned(lProvider) then
        lDelayUs := Min(lDelayUs, lProvider());
    except
      on E: Exception do
        CronDebugOutput('maxCron deadline provider: ' + CronExceptionText(E));
    end;
    if lDelayUs > 0 then
    begin
      lZeroStreak := 0;
      if fSource.fWaiter.Wait(lDelayUs) then
        Continue;
    end else begin
      Inc(lZeroStreak);
      if lZeroStreak > 64 then
      begin
        TInterlocked.Increment(fSource.fSpinGuardHits);
        fSource.fWaiter.Wait(1000);
        lZeroStreak := 0;
      end;
    end;
    if Terminated or (TInterlocked.CompareExchange(fSource.fRunning, 0, 0) = 0) then
      Continue;
    try
      if Assigned(lHandler) then
        lHandler(Self);
    except
      on E: Exception do
      begin
        TInterlocked.Increment(fSource.fTickExceptions);
        CronDebugOutput('maxCron deadline tick: ' + CronExceptionText(E));
      end;
    end;
    TInterlocked.Increment(fSource.fTicksDelivered);
  end;
end;

constructor TCronDeadlineTickSource.Create(const aPreferred: TCronWaitResolution);
begin
  inherited Create;
  fLock := TCriticalSection.Create;
  fWaiter := TCronWaiter.Create(aPreferred);
  fMaxSleepMs := 1000;
end;

destructor TCronDeadlineTickSource.Destroy;
begin
  Shutdown;
  fThread.Free;
  fWaiter.Free;
  fLock.Free;
  inherited;
end;

procedure TCronDeadlineTickSource.SetOnTick(const aHandler: TNotifyEvent);
begin
  fLock.Acquire;
  try
    fOnTick := aHandler;
  finally
    fLock.Release;
  end;
end;

procedure TCronDeadlineTickSource.SetDelayProvider(const aProvider: TCronTickDelayFunc);
begin
  fLock.Acquire;
  try
    fProvider := aProvider;
  finally
    fLock.Release;
  end;
end;

procedure TCronDeadlineTickSource.Start(const aMaxSleepMs: Cardinal);
begin
  fLock.Acquire;
  try
    TInterlocked.Exchange(fMaxSleepMs, Integer(EnsureRange(aMaxSleepMs, Cardinal(1), Cardinal(1000))));
    if (fThread <> nil) and fThread.Terminated then
      Exit;
    TInterlocked.Exchange(fRunning, 1);
    if fThread = nil then
    begin
      fThread := TCronDeadlineThread.Create(Self);
      fThread.Start;
    end;
    fWaiter.Wake;
  finally
    fLock.Release;
  end;
end;

procedure TCronDeadlineTickSource.Stop;
begin
  TInterlocked.Exchange(fRunning, 0);
  if fWaiter <> nil then
    fWaiter.Wake;
end;

procedure TCronDeadlineTickSource.Shutdown;
begin
  Stop;
  if fThread <> nil then
  begin
    fThread.Terminate;
    fWaiter.Wake;
    if TThread.CurrentThread.ThreadID <> fThread.ThreadID then
      fThread.WaitFor;
  end;
end;

procedure TCronDeadlineTickSource.Wake;
begin
  // Scheduler ticks already update their delay before the next wait.
  if (fThread <> nil) and (TThread.CurrentThread.ThreadID = fThread.ThreadID) then
    Exit;
  fWaiter.Wake;
end;

function TCronDeadlineTickSource.GetResolution: TCronWaitResolution;
begin
  Result := fWaiter.fResolution;
end;

function TCronDeadlineTickSource.GetDiagnostics: TCronTickSourceDiagnostics;
begin
  Result.TicksDelivered := UInt64(TInterlocked.Read(fTicksDelivered));
  Result.SpinGuardHits := UInt64(TInterlocked.Read(fSpinGuardHits));
  Result.TickExceptions := UInt64(TInterlocked.Read(fTickExceptions));
end;

function CreateCronTickSource(const aPreferred: TCronWaitResolution): ICronTickSource;
begin
  Result := TCronDeadlineTickSource.Create(aPreferred);
end;

function CronMaxAsyncCall(const aProc: TThreadProcedure; const aTaskName: string): IInterface;
begin
  {$IFDEF FPC}
  Result := TTask.Run(aProc);
  {$ELSE}
  Result := maxAsync.SimpleAsyncCall(aProc, aTaskName);
  {$ENDIF}
end;

procedure CronDebugOutput(const aText: string);
begin
  {$IFDEF MSWINDOWS}
  OutputDebugStringW(PWideChar(aText));
  {$ENDIF}
end;

function CronGetEnvironmentVariable(const aName: string): string;
begin
  Result := {$IFDEF FPC}SysUtils{$ELSE}System.SysUtils{$ENDIF}.GetEnvironmentVariable(aName);
end;

initialization
  {$IFDEF MSWINDOWS}
  gCronPreciseTime := GetProcAddress(GetModuleHandle('kernel32.dll'), 'GetSystemTimePreciseAsFileTime');
  {$ENDIF}
end.

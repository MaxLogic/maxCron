unit maxCron;
{

  Version: 2.2
 NOTE:
}

interface

// TThread.ForceQueue is not available in XE8 and older
{$IF CompilerVersion <= 29.0}
{$DEFINE ForceQueueNotAvailable}
{$ENDIF}

uses
  System.Classes, System.Generics.Collections, System.SysUtils, System.SyncObjs;

Type
  // forward declarations
  TmaxCron = class;
  TmaxCronEvent = class;
  TCronSchedulePlan = class;

  TmaxCronNotifyEvent = procedure(Sender: TmaxCronEvent) of object;
  TmaxCronNotifyProc = reference to procedure(Sender: TmaxCronEvent);

  TmaxCronInvokeMode = (
    imDefault,    // use scheduler DefaultInvokeMode
    imMainThread, // execute on VCL main thread (ForceQueue/Queue when needed)
    imMaxAsync,   // execute via MaxLogicFoundation maxAsync.SimpleAsyncCall
    imTTask,      // execute via System.Threading.TTask.Run
    imThread      // execute via TThread.CreateAnonymousThread
    );

  TmaxCronOverlapMode = (
    omAllowOverlap,    // schedule fires can overlap
    omSkipIfRunning,   // if previous execution is still running, skip this fire
    omSerialize,       // queue fires and run them one-by-one (per event)
    omSerializeCoalesce // like omSerialize, but coalesces backlog to max 1
    );

  // How to combine Day-of-Month (DOM) and Day-of-Week (DOW) when both are restricted (not '*').
  // - dmAnd: both must match (legacy maxCron behavior)
  // - dmOr:  either may match (crontab/Vixie-style behavior)
  TmaxCronDayMatchMode = (dmDefault, dmAnd, dmOr);

  TmaxCronTimerBackend = (ctAuto, ctVcl, ctPortable);

  ICronTimer = interface
    ['{4F3B81F6-57F0-4A98-9F65-6B8E7A7A0E41}']
    procedure Start(const aIntervalMs: Cardinal);
    procedure Stop;
    procedure SetOnTimer(const aValue: TNotifyEvent);
  end;

  TmaxCron = class(TObject)
  private
    fRequestedTimerBackend: TmaxCronTimerBackend;
    fActiveTimerBackend: TmaxCronTimerBackend;
    fDefaultInvokeMode: TmaxCronInvokeMode;
    fDefaultDayMatchMode: TmaxCronDayMatchMode;
    procedure SetDefaultDayMatchMode(const Value: TmaxCronDayMatchMode);
    fTimer: ICronTimer;
    fItems: TObjectList<TmaxCronEvent>;
    fItemsLock: TCriticalSection;
    fPendingFree: TList<TmaxCronEvent>;
    fTickDepth: Integer;
    fTickQueued: Integer;
    fQueueToken: IInterface;
    fAsyncKeepAlive: TList<IInterface>;
    fAsyncLock: TCriticalSection;
    function GetCount: integer;
    function GetEvents(index: integer): TmaxCronEvent;
    procedure TimerTimer(Sender: TObject);
    procedure CreateTimer(const aRequestedBackend: TmaxCronTimerBackend);
    procedure DoTick;
    procedure DoTickAt(const aNow: TDateTime);
    procedure QueueTick;
    procedure KeepAsyncAlive(const aAsync: IInterface);
    procedure ReleaseAsyncAlive(const aAsync: IInterface);
    procedure FlushPendingFree;
    procedure FlushPendingFreeLocked;

  public
    constructor Create; overload;
    constructor Create(const aTimerBackend: TmaxCronTimerBackend); overload;
    destructor Destroy; override;

    procedure Clear;

    Function Add(const aName: string): TmaxCronEvent; overload;
    Function Add(const aName, aEventPlan: string; const aOnScheduleEvent: TmaxCronNotifyEvent): TmaxCronEvent; overload;
    Function Add(const aName, aEventPlan: string; const aOnScheduleEvent: TmaxCronNotifyProc): TmaxCronEvent; overload;

    function Delete(index: integer): boolean; overload;
    function Delete(event: TmaxCronEvent): boolean; overload;
    function IndexOf(event: TmaxCronEvent): integer;

    property Count: integer read GetCount;
    property Events[index: integer]: TmaxCronEvent read GetEvents;
    property RequestedTimerBackend: TmaxCronTimerBackend read fRequestedTimerBackend;
    property ActiveTimerBackend: TmaxCronTimerBackend read fActiveTimerBackend;
    property DefaultInvokeMode: TmaxCronInvokeMode read fDefaultInvokeMode write fDefaultInvokeMode;
    property DefaultDayMatchMode: TmaxCronDayMatchMode read fDefaultDayMatchMode write SetDefaultDayMatchMode;

    {$IFDEF MAXCRON_TESTS}
    procedure TickAt(const aNow: TDateTime);
    {$ENDIF}
  end;

  TmaxCronEvent = class(TObject)
  private
    fCron: TmaxCron;
    fCronToken: IInterface;
    fScheduler: TCronSchedulePlan;
    FEventPlan: string;

    FName: string;
    FOnScheduleEvent: TmaxCronNotifyEvent;

    FTag: integer;
    FUserData: Pointer;
    FUserDataInterface: iInterface;

    FEnabled: boolean;
    fNextSchedule: TDateTime;
    FValidFrom: TDateTime;
    FValidTo: TDateTime;
    FOnScheduleProc: TmaxCronNotifyProc;
    fNumOfExecutions: uint64;
    fLastExecutionTime: TDateTime;
    fInvokeMode: TmaxCronInvokeMode;
    fLock: TCriticalSection;
    fEventToken: IInterface;
    fOverlapMode: TmaxCronOverlapMode;
    fDayMatchMode: TmaxCronDayMatchMode;
    fRunning: Integer;
    fPendingRuns: Integer;
    fExecDepth: Integer;
    fPendingDestroy: Boolean;
    procedure SetName(const Value: string);
    procedure SetOnScheduleEvent(const Value: TmaxCronNotifyEvent);
    procedure SetTag(const Value: integer);
    procedure SetUserData(const Value: Pointer);
    procedure SetEventPlan(const Value: string);
    procedure SetEnabled(const Value: boolean);
    procedure SetNumOfExecutions(const Value: uint64);
    procedure SetValidFrom(const Value: TDateTime);
    procedure SetValidTo(const Value: TDateTime);
    procedure SetUserDataInterface(const Value: iInterface);
    procedure SetOnScheduleProc(const Value: TmaxCronNotifyProc);
    procedure SetInvokeMode(const Value: TmaxCronInvokeMode);
    procedure SetOverlapMode(const Value: TmaxCronOverlapMode);
    procedure SetDayMatchMode(const Value: TmaxCronDayMatchMode);
    function GetEnabled: boolean;
    function GetNextSchedule: TDateTime;
    function GetLastExecution: TDateTime;
    function GetNumOfExecutionsPerformed: uint64;
    function GetEffectiveInvokeMode: TmaxCronInvokeMode;
    function GetOverlapMode: TmaxCronOverlapMode;
    function GetDayMatchMode: TmaxCronDayMatchMode;
    procedure DispatchCallbacks(const aInvokeMode: TmaxCronInvokeMode;
      const aOnEvent: TmaxCronNotifyEvent; const aOnProc: TmaxCronNotifyProc;
      const aOverlapMode: TmaxCronOverlapMode);
    function TryAcquireExecution: Boolean;
    procedure ReleaseExecution;
    procedure MarkPendingDestroy;
    function CanFreeNow: Boolean;

    // this is the main function that will be called by the TmaxCron in a timer
    procedure checkTimer(const aNow: TDateTime);
    procedure ResetSchedule;
  public
    constructor Create;
    destructor Destroy; override;

    function Run: TmaxCronEvent;
    procedure Stop;

    property EventPlan: string read FEventPlan write SetEventPlan;
    property NextSchedule: TDateTime read GetNextSchedule;
    property Name: string read FName write SetName;
    property LastExecution: TDateTime read GetLastExecution;

    // User data
    property Tag: integer read FTag write SetTag;
    property UserData: Pointer read FUserData write SetUserData;
    Property UserDataInterface: iInterface read FUserDataInterface write SetUserDataInterface;

    property OnScheduleEvent: TmaxCronNotifyEvent read FOnScheduleEvent write SetOnScheduleEvent;
    // you can use an anonymous method as well
    property OnScheduleProc: TmaxCronNotifyProc read FOnScheduleProc write SetOnScheduleProc;

    property Enabled: boolean read GetEnabled write SetEnabled;
    property InvokeMode: TmaxCronInvokeMode read fInvokeMode write SetInvokeMode;
    property OverlapMode: TmaxCronOverlapMode read GetOverlapMode write SetOverlapMode;
    property DayMatchMode: TmaxCronDayMatchMode read GetDayMatchMode write SetDayMatchMode;

    // tels how many times this event was executed
    property NumOfExecutionsPerformed: uint64 read GetNumOfExecutionsPerformed;

    Property ValidFrom: TDateTime read FValidFrom write SetValidFrom;
    property ValidTo: TDateTime read FValidTo write SetValidTo;
  end;

  // those are the parts as they appear in that order
  TPartKind = (
    ckMinute = 0,
    ckHour,
    ckDayOfTheMonth,
    ckMonth,
    ckDayOfTheWeek,
    ckYear,
    ckSecond
    // ckExecutionLimit  - this is not a part kind but it is a part of the schedule string
    );

  TPlan = record
  private
    function asString: String;
    procedure setText(const Value: string);
  public
    parts: array [0 .. 7] of string;

    property Minute: string read parts[0] write parts[0];
    property Hour: string read parts[1] write parts[1];
    property DayOfTheMonth: string read parts[2] write parts[2];
    property Month: string read parts[3] write parts[3];
    property DayOfTheWeek: string read parts[4] write parts[4];
    property Year: string read parts[5] write parts[5];
    property Second: string read parts[6] write parts[6];
    property ExecutionLimit: string read parts[7] write parts[7];

    property text: string read asString write setText;

    // resets all values to their defaults
    procedure reset;
  end;

  TCronPart = class(TObject)
  private
    FData: string;
    FValidFrom, FValidTo: word;
    fPartKind: TPartKind;
    fFullrange: boolean;
    fRange: array of word;
    FCount: integer;

    procedure Parse;
    procedure SetData(const Value: string);
    procedure ParsePart(const Value: string);
    function ReplaceMonthNames(const Value: string): string;
    function ReplaceDaynames(const Value: string): string;
    Procedure Add2Range(Value: word);
    function FindInRange(Value: word; out index: integer): boolean;

    function PushYear(var NextDate: TDateTime): boolean;
    function PushMonth(var NextDate: TDateTime): boolean;
    function PushDayOfMonth(var NextDate: TDateTime): boolean;
    function PushDayOfWeek(var NextDate: TDateTime): boolean;
    function PushHour(var NextDate: TDateTime): boolean;
    function PushMinute(var NextDate: TDateTime): boolean;
    function PushSecond(var NextDate: TDateTime): boolean;
    function GetFullrange: boolean;
  public
    constructor Create(aPartKind: TPartKind);
    destructor Destroy; override;

    procedure Clear;
    function NextVal(v: word): word;

    property Data: string read FData write SetData;
    property PartKind: TPartKind read fPartKind;
    property Fullrange: boolean read GetFullrange;
  end;

  // this is a helper class to calculate and parse the schedule plan
  TCronSchedulePlan = class
  private
    FSecond: TCronPart;
    FMinute: TCronPart;
    FHour: TCronPart;
    FMonth: TCronPart;
    FDayOfTheMonth: TCronPart;
    FDayOfTheWeek: TCronPart;
    FYear: TCronPart;
    fExecutionLimit: LongWord;
    fDayMatchMode: TmaxCronDayMatchMode;

    function GetParts(PartKind: TPartKind): TCronPart;
    procedure SetDayOfTheMonth(const Value: TCronPart);
    procedure SetDayOfTheWeek(const Value: TCronPart);
    procedure SetHour(const Value: TCronPart);
    procedure SetMinute(const Value: TCronPart);
    procedure SetMonth(const Value: TCronPart);
    procedure SetParts(PartKind: TPartKind; const Value: TCronPart);
    procedure SetSecond(const Value: TCronPart);
    procedure SetYear(const Value: TCronPart);
    function PushDomDow(var NextDate: TDateTime): boolean;
  public
    Constructor Create;
    Destructor Destroy; override;

    procedure Parse(const CronPlan: string);
    procedure Clear;

    function FindNextScheduleDate(const aBaseDate: TDateTime;
      out aNextDateTime: TDateTime;
      const aValidFrom: TDateTime = 0;
      const aValidTo: TDateTime = 0): boolean;

    property Second: TCronPart read FSecond write SetSecond;
    property Minute: TCronPart read FMinute write SetMinute;
    property Hour: TCronPart read FHour write SetHour;
    property Day_of_the_Month: TCronPart read FDayOfTheMonth write SetDayOfTheMonth;
    property Month: TCronPart read FMonth write SetMonth;
    property Day_of_the_Week: TCronPart read FDayOfTheWeek write SetDayOfTheWeek;
    property Year: TCronPart read FYear write SetYear;
    property parts[PartKind: TPartKind]: TCronPart read GetParts write SetParts;
    property ExecutionLimit: LongWord read fExecutionLimit;
    property DayMatchMode: TmaxCronDayMatchMode read fDayMatchMode write fDayMatchMode;
  end;

  TDates = array of TDateTime;

  // you can use this to show the user a preview ow what his schedule will look like.
function MakePreview(const SchedulePlan: string; out Dates: TDates; Limit: integer = 100): boolean;

implementation

uses
  System.DateUtils, System.Math, System.SyncObjs, System.Threading,
  Vcl.ExtCtrls,
  MaxLogic.PortableTimer, maxAsync;

type
  ICronQueueToken = interface
    ['{3F1D42F5-52B2-4B86-9E06-5ED517BD5E46}']
    procedure Detach;
    function TryGetOwner(out aOwner: TmaxCron): Boolean;
  end;

  TCronQueueToken = class(TInterfacedObject, ICronQueueToken)
  private
    fLock: TCriticalSection;
    fOwner: TmaxCron;
  public
    constructor Create(aOwner: TmaxCron);
    destructor Destroy; override;
    procedure Detach;
    function TryGetOwner(out aOwner: TmaxCron): Boolean;
  end;

  TVclCronTimer = class(TInterfacedObject, ICronTimer)
  private
    fTimer: Vcl.ExtCtrls.TTimer;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Start(const aIntervalMs: Cardinal);
    procedure Stop;
    procedure SetOnTimer(const aValue: TNotifyEvent);
  end;

  TPortableCronTimer = class(TInterfacedObject, ICronTimer)
  private
    fTimer: MaxLogic.PortableTimer.TPortableTimer;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Start(const aIntervalMs: Cardinal);
    procedure Stop;
    procedure SetOnTimer(const aValue: TNotifyEvent);
  end;

  ICronEventToken = interface
    ['{1AD0B7CE-0C85-4490-9B3E-3E0E1C6115E6}']
    procedure Detach;
    function TryGetEvent(out aEvent: TmaxCronEvent): Boolean;
  end;

  TCronEventToken = class(TInterfacedObject, ICronEventToken)
  private
    fLock: TCriticalSection;
    fEvent: TmaxCronEvent;
  public
    constructor Create(aEvent: TmaxCronEvent);
    destructor Destroy; override;
    procedure Detach;
    function TryGetEvent(out aEvent: TmaxCronEvent): Boolean;
  end;

const
  OneMinute = 1 / 24 / 60;
  OneSecond = OneMinute / 60;
  OneHour = 1 / 24;

const
  DayNames: array [1 .. 7] of string = (
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun');

const
  MonthNames: array [1 .. 12] of string = (
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec');

procedure Log(const msg: string);
begin
  // pawel1.AddToLogFile(msg, 's:\tmp\te.log');
end;

procedure SplitString(const s: string; delim: char; ts: TStrings);
var
  i: integer;
  t: string;
begin
  t := '';
  for i := 1 to length(s) do
  begin
    if (s[i] <> delim) then
      t := t + s[i]
    else
    begin
      ts.Add(t);
      t := '';
    end;
  end;

  if t <> '' then
    ts.Add(t);
end;

{ TCronSchedulePlan }

procedure TCronSchedulePlan.Clear;
var
  pk: TPartKind;
begin
  fExecutionLimit := 0;
  for pk := Low(TPartKind) to High(TPartKind) do
    parts[pk].Clear;
end;

constructor TCronSchedulePlan.Create;
var
  pk: TPartKind;
begin
  inherited;

  fDayMatchMode := TmaxCronDayMatchMode.dmAnd;
  for pk := Low(TPartKind) to High(TPartKind) do
    parts[pk] := TCronPart.Create(pk);
end;

destructor TCronSchedulePlan.Destroy;
var
  pk: TPartKind;
begin
  for pk := Low(TPartKind) to High(TPartKind) do
    parts[pk].Free;
  inherited;
end;

function TCronSchedulePlan.FindNextScheduleDate(const aBaseDate: TDateTime;
  out aNextDateTime: TDateTime;
  const aValidFrom,
  aValidTo: TDateTime): boolean;
var
  dc: word;
  v: word;
  StartDate: TDateTime;
  pk: TPartKind;
  h, m, s, ms: word;
begin
  Result := false;

  if (aBaseDate > aValidFrom) then
    StartDate := aBaseDate
  else
    StartDate := aValidFrom;

  // clear out milliseconds
  DecodeTime(StartDate, h, m, s, ms);
  StartDate := trunc(StartDate) +
    encodeTime(h, m, s, 0);
  StartDate := StartDate + OneSecond;

  aNextDateTime := StartDate;

  while True do
  begin
    if (aValidTo > 0) and (aNextDateTime > aValidTo) then
      Exit(false);



    // year
    if not FYear.PushYear(aNextDateTime) then
      Exit;

    if FMonth.PushMonth(aNextDateTime) then
      if PushDomDow(aNextDateTime) then
        if FHour.PushHour(aNextDateTime) then
          if FMinute.PushMinute(aNextDateTime) then
            if FSecond.PushSecond(aNextDateTime) then
            begin
              Exit(True);
            end;

  end;
end;

function TCronSchedulePlan.PushDomDow(var NextDate: TDateTime): boolean;
var
  lMode: TmaxCronDayMatchMode;
  lDomOk: Boolean;
  lDowOk: Boolean;
  lDomCandidate: TDateTime;
  lDowCandidate: TDateTime;
  lDom: Word;
  lDow: Word;
begin
  Result := True;

  lMode := fDayMatchMode;
  if lMode = TmaxCronDayMatchMode.dmDefault then
    lMode := TmaxCronDayMatchMode.dmAnd;

  // If either part is full range, "OR" reduces to the other constraint.
  if (lMode = TmaxCronDayMatchMode.dmAnd) or FDayOfTheMonth.Fullrange or FDayOfTheWeek.Fullrange then
  begin
    Result := FDayOfTheMonth.PushDayOfMonth(NextDate);
    if Result then
      Result := FDayOfTheWeek.PushDayOfWeek(NextDate);
    Exit;
  end;

  // OR mode and both are restricted: accept if either matches.
  lDom := DayOf(NextDate);
  // Cron-compatible: 0 = Sunday, 1 = Monday, ... 6 = Saturday.
  lDow := DayOfTheWeek(NextDate) mod 7;
  lDomOk := (FDayOfTheMonth.NextVal(lDom) = lDom);
  lDowOk := (FDayOfTheWeek.NextVal(lDow) = lDow);
  if lDomOk or lDowOk then
    Exit(True);

  // Otherwise, advance to the earliest next date that satisfies DOM or DOW.
  lDomCandidate := NextDate;
  lDowCandidate := NextDate;

  FDayOfTheMonth.PushDayOfMonth(lDomCandidate);
  FDayOfTheWeek.PushDayOfWeek(lDowCandidate);

  if lDomCandidate <= lDowCandidate then
    NextDate := lDomCandidate
  else
    NextDate := lDowCandidate;

  Result := False;
end;

function TCronSchedulePlan.GetParts(PartKind: TPartKind): TCronPart;
begin
  case PartKind of
    ckSecond:
      Result := FSecond;
    ckMinute:
      Result := FMinute;
    ckHour:
      Result := FHour;
    ckDayOfTheMonth:
      Result := FDayOfTheMonth;
    ckMonth:
      Result := FMonth;
    ckDayOfTheWeek:
      Result := FDayOfTheWeek;
  else
    // ckyear:
    Result := FYear;
  end;
end;

procedure TCronSchedulePlan.Parse(const CronPlan: string);
var
  plan: TPlan;
  s: string;
  pk: TPartKind;
begin
  Clear;
  plan.text := CronPlan;

  for pk := Low(TPartKind) to High(TPartKind) do
    parts[pk].Data := plan.parts[integer(pk)];

  fExecutionLimit := 0;
  if plan.ExecutionLimit <> '*' then
    fExecutionLimit := StrToIntDef(plan.ExecutionLimit, 0);
end;

procedure TCronSchedulePlan.SetDayOfTheMonth(const Value: TCronPart);
begin
  FDayOfTheMonth := Value;
end;

procedure TCronSchedulePlan.SetDayOfTheWeek(const Value: TCronPart);
begin
  FDayOfTheWeek := Value;
end;

procedure TCronSchedulePlan.SetHour(const Value: TCronPart);
begin
  FHour := Value;
end;

procedure TCronSchedulePlan.SetMinute(const Value: TCronPart);
begin
  FMinute := Value;
end;

procedure TCronSchedulePlan.SetMonth(const Value: TCronPart);
begin
  FMonth := Value;
end;

procedure TCronSchedulePlan.SetParts(PartKind: TPartKind; const Value: TCronPart);
begin
  case PartKind of
    ckSecond:
      FSecond := Value;
    ckMinute:
      FMinute := Value;
    ckHour:
      FHour := Value;
    ckDayOfTheMonth:
      FDayOfTheMonth := Value;
    ckMonth:
      FMonth := Value;
    ckDayOfTheWeek:
      FDayOfTheWeek := Value;
    ckYear:
      FYear := Value;
  end;
end;

procedure TCronSchedulePlan.SetSecond(const Value: TCronPart);
begin
  FSecond := Value;
end;

procedure TCronSchedulePlan.SetYear(const Value: TCronPart);
begin
  FYear := Value;
end;

{ TCronPart }

procedure TCronPart.Add2Range(Value: word);
var
  i: integer;
begin
  if Value >= FValidFrom then
    if Value <= FValidTo then
      if not self.FindInRange(Value, i) then
      begin
        SetLength(fRange, FCount + 1);
        if i < FCount then
          Move(fRange[i], fRange[i + 1], Sizeof(fRange[0]) * (FCount - i));
        fRange[i] := Value;
        inc(FCount);
      end;
end;

procedure TCronPart.Clear;
begin
  fFullrange := false;
  FCount := 0;
  fRange := NIL;
end;

constructor TCronPart.Create;
begin
  inherited Create;
  FCount := 0;
  fRange := NIL;
  fPartKind := aPartKind;

  Data := '*';

  case fPartKind of

    ckSecond,
      ckMinute:
      begin
        FValidFrom := 0;
        FValidTo := 59;
      end;
    ckHour:
      begin
        FValidFrom := 0;
        FValidTo := 23;
      end;
    ckDayOfTheMonth:
      begin
        FValidFrom := 1;
        FValidTo := 31;
      end;
    ckMonth:
      begin
        FValidFrom := 1;
        FValidTo := 12;
      end;
    ckDayOfTheWeek:
      begin
        // Cron-compatible: 0 = Sunday, 1 = Monday, ... 6 = Saturday. We also accept 7 as Sunday (normalized to 0).
        FValidFrom := 0;
        FValidTo := 6;
      end;
    ckYear:
      begin
        FValidFrom := 1900;
        FValidTo := 3000;
      end;

  end;
end;

destructor TCronPart.Destroy;
begin
  Clear;
  inherited;
end;

function TCronPart.FindInRange(Value: word; out index: integer): boolean;
var
  C, l, h, i: integer;
begin
  Result := false;
  l := 0;
  h := FCount - 1;
  while l <= h do
  begin
    i := (l + h) shr 1;

    IF fRange[i] > Value then
      C := 1
    else if fRange[i] < Value then
      C := -1
    else
      C := 0;

    if C < 0 then
      l := i + 1
    else
    begin
      h := i - 1;
      if C = 0 then
      Begin
        Result := True;
        Index := i;
        Exit;
      end;
    end;
  end;
  Index := l;
end;

function TCronPart.GetFullrange: boolean;
begin
  Result := fFullrange OR (FCount = 0)
end;

function TCronPart.NextVal(v: word): word;
var
  i: integer;
begin
  if Fullrange then
    Result := v
  else
  begin
    if FindInRange(v, i) then
      Result := v
    else
    begin
      if i < FCount then
        Result := fRange[i]
      else
        Result := fRange[0];
    end;
  end;

end;

procedure TCronPart.Parse;
var
  x: integer;
  l: TStringList;
begin
  Clear;

  if Trim(FData) = '' then
  begin
    fFullrange := True;
    fRange := NIL;
    FCount := 0;
    Exit;
  end;

  if FData = '*' then
  begin
    fFullrange := True;
    fRange := NIL;
    FCount := 0;
  end else begin

    l := TStringList.Create;
    try
      SplitString(FData, ',', l);
      for x := 0 to l.Count - 1 do
      begin
        if l[x] = '*' then
        begin
          fFullrange := True;
          fRange := NIL;
          FCount := 0;
        end
        else
          ParsePart(l[x]);
      end;
    finally
      l.Free;
    end;
  end;
end;

procedure TCronPart.ParsePart(const Value: string);
var
  iR: integer;
  RangeTo: Integer;
  RangeFrom: Integer;
  i: Integer;
  s: string;
  Repeater: integer;
  iS: Integer;

  function NormalizeDow(const aValue: Integer): Integer;
  begin
    if fPartKind <> ckDayOfTheWeek then
      Exit(aValue);
    if aValue = 7 then
      Exit(0);
    Exit(aValue);
  end;

  procedure AddRange(const aFrom, aTo, aStep: Integer);
  var
    v: Integer;
  begin
    v := aFrom;
    while v <= aTo do
    begin
      Add2Range(v);
      Inc(v, aStep);
    end;
  end;
begin

  s := Trim(Value);
  if s = '' then
    raise Exception.Create('Invalid cron token');
  case fPartKind of
    ckMonth:
      s := ReplaceMonthNames(s);
    ckDayOfTheWeek:
      s := ReplaceDaynames(s);
  end;

  iS := Pos('/', s);
  if iS > 0 then
  begin
    Repeater := StrToInt(Copy(s, iS + 1, MaxInt));
    if Repeater <= 0 then
      raise Exception.Create('Invalid cron step');
    s := Copy(s, 1, iS - 1);
  end else
    Repeater := 1;

  iR := Pos('-', s);
  if s = '*' then
  begin
    RangeFrom := FValidFrom;
    RangeTo := FValidTo;
  end else if iR > 0 then
  begin
    RangeFrom := StrToInt(Copy(s, 1, iR - 1));
    RangeTo := StrToInt(Copy(s, iR + 1, MaxInt));
  end else
  begin
    RangeFrom := StrToInt(s);
    if iS > 0 then
      RangeTo := FValidTo // n/k => n..max
    else
      RangeTo := RangeFrom;
  end;

  RangeFrom := NormalizeDow(RangeFrom);
  RangeTo := NormalizeDow(RangeTo);

  if (RangeFrom < FValidFrom) or (RangeFrom > FValidTo) then
    raise Exception.Create('Cron value out of range');
  if (RangeTo < FValidFrom) or (RangeTo > FValidTo) then
    raise Exception.Create('Cron value out of range');

  if (iR > 0) and (RangeTo < RangeFrom) then
  begin
    if fPartKind = ckDayOfTheWeek then
    begin
      AddRange(RangeFrom, FValidTo, Repeater);
      AddRange(FValidFrom, RangeTo, Repeater);
      Exit;
    end;
    raise Exception.Create('Invalid cron range');
  end;

  AddRange(RangeFrom, RangeTo, Repeater);
end;

function TCronPart.PushDayOfMonth(var NextDate: TDateTime): boolean;
var
  dc, v, i: word;
begin
  Result := True;
  if not Fullrange then
  begin
    v := DayOf(NextDate);
    i := NextVal(v);
    if i < v then
    begin
      NextDate := EncodeDateTime(YearOf(NextDate), MonthOf(NextDate), i, 0, 0, 0, 0);
      NextDate := IncMonth(NextDate);
      Result := false;
    end
    else if i > v then
    begin
      dc := dateUtils.DaysInMonth(NextDate);
      if i <= dc then
        NextDate := EncodeDateTime(YearOf(NextDate), MonthOf(NextDate), i, 0, 0, 0, 0)
      else
      begin
        NextDate := EncodeDateTime(YearOf(NextDate), MonthOf(NextDate), 1, 0, 0, 0, 0);
        NextDate := IncMonth(NextDate);
        Result := false;
      end;
    end;
  end;
end;

function TCronPart.PushDayOfWeek(var NextDate: TDateTime): boolean;
var
  v, i: word;
begin
  Result := True;
  if not Fullrange then
  begin
    // Cron-compatible: 0 = Sunday, 1 = Monday, ... 6 = Saturday.
    v := DayOfTheWeek(NextDate) mod 7;
    i := NextVal(v);
    if i <> v then
    begin
      Result := false;
      NextDate := trunc(NextDate); // reset hh:nn:ss to 00:00:00
      if i > v then
        NextDate := NextDate + (i - v)
      else
        NextDate := NextDate + (7 - v) + i;

    end;

  end;
end;

function TCronPart.PushHour(var NextDate: TDateTime): boolean;
var
  v, i: word;
begin
  Result := True;
  if not Fullrange then
  begin
    v := HourOf(NextDate);
    i := NextVal(v);
    if i < v then
    begin
      Result := false;
      NextDate := trunc(NextDate) + 1 + i * OneHour;
    end
    else if i > v then
      NextDate := trunc(NextDate) + i * OneHour;
  end;
end;

function TCronPart.PushMinute(var NextDate: TDateTime): boolean;
var
  h, v, i: word;
begin
  Result := True;
  if not Fullrange then
  begin
    v := MinuteOf(NextDate);
    i := NextVal(v);
    if i < v then
    begin
      Result := false;
      h := HourOf(NextDate);
      NextDate := trunc(NextDate) + (h + 1) * OneHour + i * OneMinute;
    end
    else if i > v then
    begin
      h := HourOf(NextDate);
      NextDate := trunc(NextDate) + h * OneHour + i * OneMinute;
    end;
  end;
end;

function TCronPart.PushMonth(var NextDate: TDateTime): boolean;
var
  v, i: word;
begin
  Result := True;
  if not Fullrange then
  begin
    v := MonthOf(NextDate);
    i := NextVal(v);
    if i < v then
    begin
      NextDate := EncodeDateTime(YearOf(NextDate) + 1, i, 1, 0, 0, 0, 0);
      Result := false;
    end
    else if i > v then
    begin
      NextDate := EncodeDateTime(YearOf(NextDate), i, 1, 0, 0, 0, 0)
    end;
  end;

end;

function TCronPart.PushSecond(var NextDate: TDateTime): boolean;
var
  h, m, v, i: word;
begin
  Result := True;
  if not Fullrange then
  begin
    v := SecondOf(NextDate);
    i := NextVal(v);
    if i < v then
    begin
      Result := false;
      h := HourOf(NextDate);
      m := MinuteOf(NextDate);
      NextDate := trunc(NextDate) + h * OneHour + (m + 1) * OneMinute + i * OneSecond;
    end
    else if i > v then
    begin
      h := HourOf(NextDate);
      m := MinuteOf(NextDate);
      NextDate := trunc(NextDate) + h * OneHour + m * OneMinute + i * OneSecond;
    end;
  end;

end;

function TCronPart.PushYear(var NextDate: TDateTime): boolean;
var
  v, i: word;
begin
  Result := True;
  v := YearOf(NextDate);
  if v > FValidTo then
  begin
    Result := false;
    Exit;
  end;

  if not Fullrange then
  begin
    i := self.NextVal(v);
    if i < v then
      Result := false
    else if i > v then
    begin
      NextDate := EncodeDateTime(i, 1, 1, 0, 0, 0, 0)
    end;
  end;
end;

function TCronPart.ReplaceDaynames(const Value: string): string;
var
  x: integer;
  s: string;
begin
  s := Value;
  for x := 1 to 7 do
  begin
    // Cron-compatible: Sun = 0 (also accept 7 as Sunday numerically in ParsePart)
    if x = 7 then
      s := StringReplace(s, DayNames[x], '0', [rfReplaceAll, rfIgnorecase])
    else
      s := StringReplace(s, DayNames[x], IntToStr(x), [rfReplaceAll, rfIgnorecase]);
  end;
  Result := s;
end;

function TCronPart.ReplaceMonthNames(const Value: string): string;
var
  x: integer;
  s: string;
begin
  s := Value;
  for x := 1 to 12 do
    s := StringReplace(s, MonthNames[x], IntToStr(x), [rfReplaceAll, rfIgnorecase]);
  Result := s;
end;

procedure TCronPart.SetData(const Value: string);
begin
  if FData <> Value then
  begin
    FData := Value;
    Parse;
  end;
end;

{ TScheduledEvent }

constructor TmaxCronEvent.Create;
begin
  inherited;
  fLock := TCriticalSection.Create;
  fEventToken := TCronEventToken.Create(Self);
  fInvokeMode := TmaxCronInvokeMode.imDefault;
  fOverlapMode := TmaxCronOverlapMode.omAllowOverlap;
  fDayMatchMode := TmaxCronDayMatchMode.dmDefault;
  fRunning := 0;
  fPendingRuns := 0;
  fExecDepth := 0;
  fPendingDestroy := False;
  FValidFrom := 0;
  FValidTo := 0;
  fScheduler := TCronSchedulePlan.Create;
  FEnabled := false;
end;

destructor TmaxCronEvent.Destroy;
var
  lToken: ICronEventToken;
begin
  if Supports(fEventToken, ICronEventToken, lToken) then
    lToken.Detach;

  fScheduler.Free;
  fLock.Free;

  inherited
end;

procedure TmaxCronEvent.ResetSchedule;
var
  dt: TDateTime;
begin
  if fLastExecutionTime = 0 then
    dt := now + OneSecond
  else
    dt := fLastExecutionTime + OneSecond;

  if not fScheduler.FindNextScheduleDate(dt,
    fNextSchedule,
    FValidFrom, FValidTo) then
    FEnabled := False;

end;

function TmaxCronEvent.Run: TmaxCronEvent;
begin
  Result := self;

  fLock.Acquire;
  try
    FEnabled := True;
    fNumOfExecutions := 0;
    fLastExecutionTime := 0;
    ResetSchedule;
  finally
    fLock.Release;
  end;
end;

procedure TmaxCronEvent.SetEnabled(const Value: boolean);
begin
  fLock.Acquire;
  try
    if FEnabled = Value then Exit;
    if Value then
    begin
      FEnabled := True;
      fNumOfExecutions := 0;
      fLastExecutionTime := 0;
      ResetSchedule;
    end else begin
      FEnabled := False;
    end;
  finally
    fLock.Release;
  end;
end;

procedure TmaxCronEvent.SetEventPlan(const Value: string);
begin
  fLock.Acquire;
  try
    if FEventPlan <> Value then
    begin
      FEventPlan := Value;
      fScheduler.Parse(Value);
      ResetSchedule;
    end;
  finally
    fLock.Release;
  end;
end;

procedure TmaxCronEvent.SetName(const Value: string);
begin
  FName := Value
end;

procedure TmaxCronEvent.SetOnScheduleEvent(const Value: TmaxCronNotifyEvent);
begin
  fLock.Acquire;
  try
    self.FOnScheduleEvent := Value;
  finally
    fLock.Release;
  end;
end;

procedure TmaxCronEvent.SetNumOfExecutions(const Value: uint64);
begin
  fLock.Acquire;
  try
    fNumOfExecutions := Value;
    if fScheduler.ExecutionLimit <> 0 then
      if fNumOfExecutions >= fScheduler.ExecutionLimit then
        FEnabled := False;
  finally
    fLock.Release;
  end;
end;

procedure TmaxCronEvent.SetTag(const Value: integer);
begin
  FTag := Value
end;

procedure TmaxCronEvent.SetUserData(const Value: Pointer);
begin
  FUserData := Value
end;

procedure TmaxCronEvent.SetUserDataInterface(const Value: iInterface);
begin
  FUserDataInterface := Value;
end;

procedure TmaxCronEvent.SetValidFrom(const Value: TDateTime);
begin
  FValidFrom := Value;
end;

procedure TmaxCronEvent.SetValidTo(const Value: TDateTime);
begin
  FValidTo := Value;
end;

procedure TmaxCronEvent.Stop;
begin
  fLock.Acquire;
  try
    FEnabled := False;
  finally
    fLock.Release;
  end;
end;

{ TSchEventList }

function TmaxCron.Add(const aName: string): TmaxCronEvent;
var
  event: TmaxCronEvent;
begin
  event := TmaxCronEvent.Create;
  event.fCron := Self;
  event.fCronToken := fQueueToken;
  event.fScheduler.DayMatchMode := fDefaultDayMatchMode;
  event.Name := aName;
  Result := event;
  fItemsLock.Acquire;
  try
    fItems.Add(event);
  finally
    fItemsLock.Release;
  end;
end;

procedure TmaxCron.Clear;
begin
  fItemsLock.Acquire;
  try
    Inc(fTickDepth);
    try
      while fItems.Count > 0 do
      begin
        fItems[0].MarkPendingDestroy;
        fPendingFree.Add(fItems.Extract(fItems[0]));
      end;
    finally
      Dec(fTickDepth);
      FlushPendingFreeLocked;
    end;
  finally
    fItemsLock.Release;
  end;
end;

constructor TmaxCron.Create;
begin
  Create(TmaxCronTimerBackend.ctAuto);
end;

constructor TCronQueueToken.Create(aOwner: TmaxCron);
begin
  inherited Create;
  fLock := TCriticalSection.Create;
  fOwner := aOwner;
end;

destructor TCronQueueToken.Destroy;
begin
  fLock.Free;
  inherited;
end;

procedure TCronQueueToken.Detach;
begin
  fLock.Acquire;
  try
    fOwner := nil;
  finally
    fLock.Release;
  end;
end;

function TCronQueueToken.TryGetOwner(out aOwner: TmaxCron): Boolean;
begin
  fLock.Acquire;
  try
    aOwner := fOwner;
    Result := (aOwner <> nil);
  finally
    fLock.Release;
  end;
end;

constructor TVclCronTimer.Create;
begin
  inherited Create;
  fTimer := Vcl.ExtCtrls.TTimer.Create(nil);
end;

destructor TVclCronTimer.Destroy;
begin
  fTimer.Free;
  inherited;
end;

procedure TVclCronTimer.Start(const aIntervalMs: Cardinal);
begin
  fTimer.Interval := aIntervalMs;
  fTimer.Enabled := True;
end;

procedure TVclCronTimer.Stop;
begin
  fTimer.Enabled := False;
end;

procedure TVclCronTimer.SetOnTimer(const aValue: TNotifyEvent);
begin
  fTimer.OnTimer := aValue;
end;

constructor TPortableCronTimer.Create;
begin
  inherited Create;
  fTimer := MaxLogic.PortableTimer.TPortableTimer.Create;
end;

destructor TPortableCronTimer.Destroy;
begin
  fTimer.Free;
  inherited;
end;

procedure TPortableCronTimer.Start(const aIntervalMs: Cardinal);
begin
  fTimer.Start(aIntervalMs);
end;

procedure TPortableCronTimer.Stop;
begin
  fTimer.Stop;
end;

procedure TPortableCronTimer.SetOnTimer(const aValue: TNotifyEvent);
begin
  fTimer.OnTimer := aValue;
end;

constructor TCronEventToken.Create(aEvent: TmaxCronEvent);
begin
  inherited Create;
  fLock := TCriticalSection.Create;
  fEvent := aEvent;
end;

destructor TCronEventToken.Destroy;
begin
  fLock.Free;
  inherited;
end;

procedure TCronEventToken.Detach;
begin
  fLock.Acquire;
  try
    fEvent := nil;
  finally
    fLock.Release;
  end;
end;

function TCronEventToken.TryGetEvent(out aEvent: TmaxCronEvent): Boolean;
begin
  fLock.Acquire;
  try
    aEvent := fEvent;
    Result := (aEvent <> nil);
  finally
    fLock.Release;
  end;
end;

constructor TmaxCron.Create(const aTimerBackend: TmaxCronTimerBackend);
begin
  inherited Create;

  fItems := TObjectList<TmaxCronEvent>.Create;
  fItemsLock := TCriticalSection.Create;
  fPendingFree := TList<TmaxCronEvent>.Create;
  fTickDepth := 0;
  fDefaultInvokeMode := TmaxCronInvokeMode.imMainThread;
  fDefaultDayMatchMode := TmaxCronDayMatchMode.dmAnd;
  fAsyncLock := TCriticalSection.Create;
  fAsyncKeepAlive := TList<IInterface>.Create;
  fTickQueued := 0;
  fQueueToken := TCronQueueToken.Create(Self);
  CreateTimer(aTimerBackend);
end;

procedure TmaxCron.SetDefaultDayMatchMode(const Value: TmaxCronDayMatchMode);
var
  x: Integer;
begin
  if Value = TmaxCronDayMatchMode.dmDefault then
    fDefaultDayMatchMode := TmaxCronDayMatchMode.dmAnd
  else
    fDefaultDayMatchMode := Value;

  fItemsLock.Acquire;
  try
    for x := 0 to fItems.Count - 1 do
      if fItems[x].fDayMatchMode = TmaxCronDayMatchMode.dmDefault then
        fItems[x].fScheduler.DayMatchMode := fDefaultDayMatchMode;
  finally
    fItemsLock.Release;
  end;
end;

procedure TmaxCron.KeepAsyncAlive(const aAsync: IInterface);
begin
  if aAsync = nil then Exit;
  fAsyncLock.Acquire;
  try
    fAsyncKeepAlive.Add(aAsync);
  finally
    fAsyncLock.Release;
  end;
end;

procedure TmaxCron.ReleaseAsyncAlive(const aAsync: IInterface);
var
  i: Integer;
begin
  if aAsync = nil then Exit;
  fAsyncLock.Acquire;
  try
    i := fAsyncKeepAlive.IndexOf(aAsync);
    if i >= 0 then
      fAsyncKeepAlive.Delete(i);
  finally
    fAsyncLock.Release;
  end;
end;

procedure TmaxCron.FlushPendingFree;
begin
  if fItemsLock = nil then Exit;
  fItemsLock.Acquire;
  try
    FlushPendingFreeLocked;
  finally
    fItemsLock.Release;
  end;
end;

procedure TmaxCron.FlushPendingFreeLocked;
var
  i: Integer;
  lEvent: TmaxCronEvent;
begin
  if (fTickDepth <> 0) then Exit;

  i := fPendingFree.Count - 1;
  while i >= 0 do
  begin
    lEvent := fPendingFree[i];
    if (lEvent <> nil) and lEvent.CanFreeNow then
    begin
      fPendingFree.Delete(i);
      lEvent.Free;
    end;
    Dec(i);
  end;
end;

procedure TmaxCron.CreateTimer(const aRequestedBackend: TmaxCronTimerBackend);
begin
  fRequestedTimerBackend := aRequestedBackend;
  fActiveTimerBackend := aRequestedBackend;

  if fActiveTimerBackend = TmaxCronTimerBackend.ctAuto then
  begin
    if TThread.CurrentThread.ThreadID = MainThreadID then
      fActiveTimerBackend := TmaxCronTimerBackend.ctVcl
    else
      fActiveTimerBackend := TmaxCronTimerBackend.ctPortable;
  end;

  case fActiveTimerBackend of
    TmaxCronTimerBackend.ctVcl:
      fTimer := TVclCronTimer.Create;
    TmaxCronTimerBackend.ctPortable:
      fTimer := TPortableCronTimer.Create;
  else
    fTimer := TVclCronTimer.Create;
    fActiveTimerBackend := TmaxCronTimerBackend.ctVcl;
  end;

  fTimer.SetOnTimer(TimerTimer);
  {$IFNDEF MAXCRON_TESTS}
  fTimer.Start(1000);
  {$ENDIF}
end;

function TmaxCron.Delete(index: integer): boolean;
var
  lEvent: TmaxCronEvent;
begin

  if (index >= 0) and (index < self.Count) then
  begin
    fItemsLock.Acquire;
    try
      if (index >= 0) and (index < fItems.Count) then
      begin
        lEvent := fItems.Extract(fItems[index]);
        if lEvent <> nil then
        begin
          lEvent.MarkPendingDestroy;
          fPendingFree.Add(lEvent);
        end;
        FlushPendingFreeLocked;
        Exit(True);
      end;
    finally
      fItemsLock.Release;
    end;
    Result := False;
  end
  else
    Result := false;
end;

function TmaxCron.Delete(event: TmaxCronEvent): boolean;
var
  i: integer;
begin
  Result := false;
  i := IndexOf(event);
  if i <> -1 then
    Result := Delete(i);
end;

destructor TmaxCron.Destroy;
var
  lToken: ICronQueueToken;
  lDone: Boolean;
begin
  if Supports(fQueueToken, ICronQueueToken, lToken) then
    lToken.Detach;

  if fTimer <> nil then
    fTimer.Stop;
  fTimer := nil;

  Clear;

  repeat
    FlushPendingFree;
    fItemsLock.Acquire;
    try
      lDone := (fPendingFree.Count = 0);
    finally
      fItemsLock.Release;
    end;

    if not lDone then
    begin
      if TThread.CurrentThread.ThreadID = MainThreadID then
        CheckSynchronize(10)
      else
        TThread.Sleep(10);
    end;
  until lDone;

  fItems.Free;
  fPendingFree.Free;
  fItemsLock.Free;
  fAsyncKeepAlive.Free;
  fAsyncLock.Free;
  inherited;
end;

function TmaxCron.GetCount: integer;
begin
  fItemsLock.Acquire;
  try
    Result := fItems.Count
  finally
    fItemsLock.Release;
  end;
end;

function TmaxCron.GetEvents(index: integer): TmaxCronEvent;
begin
  fItemsLock.Acquire;
  try
    Result := fItems[index]
  finally
    fItemsLock.Release;
  end;
end;

function TmaxCron.IndexOf(event: TmaxCronEvent): integer;
begin
  fItemsLock.Acquire;
  try
    Result := fItems.IndexOf(event);
  finally
    fItemsLock.Release;
  end;
end;

procedure TmaxCron.DoTick;
var
  lNow: TDateTime;
begin
  lNow := Now;
  DoTickAt(lNow);
end;

procedure TmaxCron.DoTickAt(const aNow: TDateTime);
var
  x: integer;
  lSnapshot: TArray<TmaxCronEvent>;
begin
  fItemsLock.Acquire;
  try
    Inc(fTickDepth);
    SetLength(lSnapshot, fItems.Count);
    for x := 0 to fItems.Count - 1 do
      lSnapshot[x] := fItems[x];
  finally
    fItemsLock.Release;
  end;

  try
    for x := 0 to Length(lSnapshot) - 1 do
      if (lSnapshot[x] <> nil) then
        lSnapshot[x].checkTimer(aNow);
  finally
    fItemsLock.Acquire;
    try
      Dec(fTickDepth);
      FlushPendingFreeLocked;
    finally
      fItemsLock.Release;
    end;
  end;
end;

{$IFDEF MAXCRON_TESTS}
procedure TmaxCron.TickAt(const aNow: TDateTime);
begin
  DoTickAt(aNow);
end;
{$ENDIF}

procedure TmaxCron.QueueTick;
var
  lToken: ICronQueueToken;
begin
  if TInterlocked.CompareExchange(fTickQueued, 1, 0) <> 0 then
    Exit;

  if not Supports(fQueueToken, ICronQueueToken, lToken) then
  begin
    TInterlocked.Exchange(fTickQueued, 0);
    Exit;
  end;

  {$IFDEF ForceQueueNotAvailable}
  TThread.Queue(nil,
  {$ELSE}
  TThread.ForceQueue(nil,
  {$ENDIF}
    procedure
    var
      Cron: TmaxCron;
    begin
      try
        if lToken.TryGetOwner(Cron) then
          Cron.DoTick;
      finally
        if lToken.TryGetOwner(Cron) then
          TInterlocked.Exchange(Cron.fTickQueued, 0);
      end;
    end);
end;

procedure TmaxCron.TimerTimer(Sender: TObject);
begin
  if TThread.CurrentThread.ThreadID = MainThreadID then
    DoTick
  else
    QueueTick;
end;

function MakePreview(const SchedulePlan: string; out Dates: TDates; Limit: integer = 100): boolean;
var
  C, x: integer;
  d: TDateTime;
  scheduler: TCronSchedulePlan;
begin
  Result := False;
  scheduler := TCronSchedulePlan.Create;
  try
    scheduler.Parse(SchedulePlan);
    SetLength(Dates, Limit);
    C := 0;
    d := Now;
    for x := 0 to Limit - 1 do
    begin
      if not scheduler.FindNextScheduleDate(d, d) then
        Break;

      Dates[x] := d;
      Inc(C);
    end;
    SetLength(Dates, C);
    Result := True;
  finally
    scheduler.Free;
  end;
end;

procedure TmaxCronEvent.SetOnScheduleProc(const Value: TmaxCronNotifyProc);
begin
  fLock.Acquire;
  try
    FOnScheduleProc := Value;
  finally
    fLock.Release;
  end;
end;

function TmaxCron.Add(const aName, aEventPlan: string;
  const aOnScheduleEvent: TmaxCronNotifyEvent): TmaxCronEvent;
begin
  Result := Add(aName);
  Result.EventPlan := aEventPlan;
  Result.OnScheduleEvent := aOnScheduleEvent;
end;

function TmaxCron.Add(const aName, aEventPlan: string;
  const aOnScheduleEvent: TmaxCronNotifyProc): TmaxCronEvent;
begin
  Result := Add(aName);
  Result.EventPlan := aEventPlan;
  Result.OnScheduleProc := aOnScheduleEvent;
end;

procedure TmaxCronEvent.SetInvokeMode(const Value: TmaxCronInvokeMode);
begin
  fLock.Acquire;
  try
    fInvokeMode := Value;
  finally
    fLock.Release;
  end;
end;

procedure TmaxCronEvent.SetOverlapMode(const Value: TmaxCronOverlapMode);
begin
  fLock.Acquire;
  try
    fOverlapMode := Value;
  finally
    fLock.Release;
  end;
end;

procedure TmaxCronEvent.SetDayMatchMode(const Value: TmaxCronDayMatchMode);
var
  lMode: TmaxCronDayMatchMode;
  lToken: ICronQueueToken;
  lCron: TmaxCron;
begin
  lMode := Value;
  if lMode = TmaxCronDayMatchMode.dmDefault then
    if Supports(fCronToken, ICronQueueToken, lToken) and lToken.TryGetOwner(lCron) then
      lMode := lCron.fDefaultDayMatchMode
    else
      lMode := TmaxCronDayMatchMode.dmAnd;

  fLock.Acquire;
  try
    fDayMatchMode := Value;
    fScheduler.DayMatchMode := lMode;
  finally
    fLock.Release;
  end;
end;

function TmaxCronEvent.GetEnabled: boolean;
begin
  fLock.Acquire;
  try
    Result := FEnabled;
  finally
    fLock.Release;
  end;
end;

function TmaxCronEvent.GetNextSchedule: TDateTime;
begin
  fLock.Acquire;
  try
    Result := fNextSchedule;
  finally
    fLock.Release;
  end;
end;

function TmaxCronEvent.GetLastExecution: TDateTime;
begin
  fLock.Acquire;
  try
    Result := fLastExecutionTime;
  finally
    fLock.Release;
  end;
end;

function TmaxCronEvent.GetNumOfExecutionsPerformed: uint64;
begin
  fLock.Acquire;
  try
    Result := fNumOfExecutions;
  finally
    fLock.Release;
  end;
end;

function TmaxCronEvent.GetEffectiveInvokeMode: TmaxCronInvokeMode;
var
  lToken: ICronQueueToken;
  lCron: TmaxCron;
begin
  Result := fInvokeMode;
  if Result <> TmaxCronInvokeMode.imDefault then Exit;
  if Supports(fCronToken, ICronQueueToken, lToken) and lToken.TryGetOwner(lCron) then
    Exit(lCron.fDefaultInvokeMode);
  Result := TmaxCronInvokeMode.imMainThread;
end;

function TmaxCronEvent.GetOverlapMode: TmaxCronOverlapMode;
begin
  fLock.Acquire;
  try
    Result := fOverlapMode;
  finally
    fLock.Release;
  end;
end;

function TmaxCronEvent.GetDayMatchMode: TmaxCronDayMatchMode;
begin
  fLock.Acquire;
  try
    Result := fDayMatchMode;
  finally
    fLock.Release;
  end;
end;

function TmaxCronEvent.TryAcquireExecution: Boolean;
begin
  fLock.Acquire;
  try
    if fPendingDestroy then
      Exit(False);
    Inc(fExecDepth);
    Result := True;
  finally
    fLock.Release;
  end;
end;

procedure TmaxCronEvent.ReleaseExecution;
begin
  fLock.Acquire;
  try
    Dec(fExecDepth);
    if fExecDepth < 0 then
      fExecDepth := 0;
  finally
    fLock.Release;
  end;
end;

procedure TmaxCronEvent.MarkPendingDestroy;
begin
  fLock.Acquire;
  try
    fPendingDestroy := True;
    FEnabled := False;
    fPendingRuns := 0;
  finally
    fLock.Release;
  end;
end;

function TmaxCronEvent.CanFreeNow: Boolean;
begin
  fLock.Acquire;
  try
    Result := (fExecDepth = 0);
  finally
    fLock.Release;
  end;
end;

procedure TmaxCronEvent.DispatchCallbacks(const aInvokeMode: TmaxCronInvokeMode;
  const aOnEvent: TmaxCronNotifyEvent; const aOnProc: TmaxCronNotifyProc;
  const aOverlapMode: TmaxCronOverlapMode);
var
  lToken: ICronEventToken;
  lOwnerToken: ICronQueueToken;
  lThread: TThread;
  lKeepAlive: IInterface;
  lCron: TmaxCron;

  type
    IAsyncKeepAliveEntry = interface
      ['{96E1F117-5C6E-4B10-8D9C-0B8E7B2B0BB2}']
      procedure AttachAsync(const aAsync: IInterface);
      procedure MarkDone;
    end;

    TAsyncKeepAliveEntry = class(TInterfacedObject, IAsyncKeepAliveEntry)
    private
      fLock: TCriticalSection;
      fOwnerToken: ICronQueueToken;
      fAsync: IInterface;
      fDone: Boolean;
    public
      constructor Create(const aOwnerToken: ICronQueueToken);
      destructor Destroy; override;
      procedure AttachAsync(const aAsync: IInterface);
      procedure MarkDone;
    end;

  procedure FinalizeOverlap;
  var
    lCron: TmaxCron;
    lPendingDestroy: Boolean;
  begin
    case aOverlapMode of
      TmaxCronOverlapMode.omSkipIfRunning:
        TInterlocked.Exchange(fRunning, 0);
      TmaxCronOverlapMode.omSerialize,
      TmaxCronOverlapMode.omSerializeCoalesce:
        begin
          lPendingDestroy := False;
          fLock.Acquire;
          try
            lPendingDestroy := fPendingDestroy;
          finally
            fLock.Release;
          end;

          if lPendingDestroy then
          begin
            TInterlocked.Exchange(fPendingRuns, 0);
            TInterlocked.Exchange(fRunning, 0);
            ReleaseExecution;
            Exit;
          end;

          if TInterlocked.CompareExchange(fPendingRuns, 0, 0) > 0 then
          begin
            TInterlocked.Decrement(fPendingRuns);
            if (aInvokeMode = TmaxCronInvokeMode.imMainThread) and (TThread.CurrentThread.ThreadID = MainThreadID) then
            begin
              {$IFDEF ForceQueueNotAvailable}
              TThread.Queue(nil, procedure begin DispatchCallbacks(aInvokeMode, aOnEvent, aOnProc, aOverlapMode); end);
              {$ELSE}
              TThread.ForceQueue(nil, procedure begin DispatchCallbacks(aInvokeMode, aOnEvent, aOnProc, aOverlapMode); end);
              {$ENDIF}
            end else begin
              DispatchCallbacks(aInvokeMode, aOnEvent, aOnProc, aOverlapMode);
            end;
            Exit; // keep execution acquired for the serialized chain
          end;

          TInterlocked.Exchange(fRunning, 0);
          ReleaseExecution;
          Exit;
        end;
    end;

    if Supports(fCronToken, ICronQueueToken, lOwnerToken) and lOwnerToken.TryGetOwner(lCron) then
      lCron.FlushPendingFree;
  end;

  procedure ExecuteOnce;
  var
    lEvent: TmaxCronEvent;
  begin
    try
      lEvent := nil;

      if not Supports(fEventToken, ICronEventToken, lToken) then Exit;
      if not lToken.TryGetEvent(lEvent) then Exit;

      if Assigned(aOnEvent) then
        aOnEvent(lEvent);
      if Assigned(aOnProc) then
        aOnProc(lEvent);
    finally
      if (aOverlapMode = TmaxCronOverlapMode.omAllowOverlap) or (aOverlapMode = TmaxCronOverlapMode.omSkipIfRunning) then
        ReleaseExecution;
      FinalizeOverlap;
    end;
  end;

  constructor TAsyncKeepAliveEntry.Create(const aOwnerToken: ICronQueueToken);
  begin
    inherited Create;
    fLock := TCriticalSection.Create;
    fOwnerToken := aOwnerToken;
    fAsync := nil;
    fDone := False;
  end;

  destructor TAsyncKeepAliveEntry.Destroy;
  begin
    fLock.Free;
    inherited;
  end;

  procedure TAsyncKeepAliveEntry.AttachAsync(const aAsync: IInterface);
  var
    lDone: Boolean;
    lCron: TmaxCron;
  begin
    fLock.Acquire;
    try
      fAsync := aAsync;
      lDone := fDone;
    finally
      fLock.Release;
    end;

    if lDone and (fOwnerToken <> nil) and fOwnerToken.TryGetOwner(lCron) then
      lCron.ReleaseAsyncAlive(Self);
  end;

  procedure TAsyncKeepAliveEntry.MarkDone;
  var
    lCanRelease: Boolean;
    lCron: TmaxCron;
  begin
    fLock.Acquire;
    try
      fDone := True;
      lCanRelease := (fAsync <> nil);
    finally
      fLock.Release;
    end;

    if lCanRelease and (fOwnerToken <> nil) and fOwnerToken.TryGetOwner(lCron) then
      lCron.ReleaseAsyncAlive(Self);
  end;

begin
  if (not Assigned(aOnEvent)) and (not Assigned(aOnProc)) then Exit;

  case aInvokeMode of
    TmaxCronInvokeMode.imMainThread:
      begin
        if TThread.CurrentThread.ThreadID = MainThreadID then
          ExecuteOnce
        else
        begin
          {$IFDEF ForceQueueNotAvailable}
          TThread.Queue(nil, procedure begin ExecuteOnce; end);
          {$ELSE}
          TThread.ForceQueue(nil, procedure begin ExecuteOnce; end);
          {$ENDIF}
        end;
      end;

    TmaxCronInvokeMode.imThread:
      begin
        lThread := TThread.CreateAnonymousThread(
          procedure
          begin
            ExecuteOnce;
          end);
        lThread.FreeOnTerminate := True;
        lThread.Start;
      end;

    TmaxCronInvokeMode.imTTask:
      begin
        TTask.Run(
          procedure
          begin
            ExecuteOnce;
          end);
      end;

    TmaxCronInvokeMode.imMaxAsync:
      begin
        if (not Supports(fCronToken, ICronQueueToken, lOwnerToken)) or (not lOwnerToken.TryGetOwner(lCron)) then
        begin
          DispatchCallbacks(TmaxCronInvokeMode.imTTask, aOnEvent, aOnProc, aOverlapMode);
          Exit;
        end;

        lKeepAlive := TAsyncKeepAliveEntry.Create(lOwnerToken);
        lCron.KeepAsyncAlive(lKeepAlive);

        IAsyncKeepAliveEntry(lKeepAlive).AttachAsync(SimpleAsyncCall(
          procedure
          begin
            ExecuteOnce;
          end,
          '',
          procedure
          begin
            IAsyncKeepAliveEntry(lKeepAlive).MarkDone;
          end));
      end;
  else
    ExecuteOnce;
  end;
end;

procedure TmaxCronEvent.checkTimer(const aNow: TDateTime);
var
  lOnEvent: TmaxCronNotifyEvent;
  lOnProc: TmaxCronNotifyProc;
  lInvokeMode: TmaxCronInvokeMode;
  lOverlap: TmaxCronOverlapMode;
  lOwnerToken: ICronQueueToken;
  lCron: TmaxCron;
begin
  lOnEvent := nil;
  lOnProc := nil;
  lInvokeMode := TmaxCronInvokeMode.imMainThread;
  lOverlap := TmaxCronOverlapMode.omAllowOverlap;

  fLock.Acquire;
  try
    if not FEnabled then Exit;
    if aNow < fNextSchedule then Exit;

    Inc(fNumOfExecutions);
    fLastExecutionTime := aNow;

    if fScheduler.ExecutionLimit <> 0 then
      if fNumOfExecutions >= fScheduler.ExecutionLimit then
        FEnabled := False;

    if FEnabled then
      ResetSchedule;

    lOnEvent := FOnScheduleEvent;
    lOnProc := FOnScheduleProc;
    lInvokeMode := fInvokeMode;
    lOverlap := fOverlapMode;
  finally
    fLock.Release;
  end;

  if (not Assigned(lOnEvent)) and (not Assigned(lOnProc)) then Exit;

  if lInvokeMode = TmaxCronInvokeMode.imDefault then
  begin
    if Supports(fCronToken, ICronQueueToken, lOwnerToken) and lOwnerToken.TryGetOwner(lCron) then
      lInvokeMode := lCron.fDefaultInvokeMode
    else
      lInvokeMode := TmaxCronInvokeMode.imMainThread;
  end;

  case lOverlap of
    TmaxCronOverlapMode.omAllowOverlap:
      begin
        if not TryAcquireExecution then Exit;
        DispatchCallbacks(lInvokeMode, lOnEvent, lOnProc, lOverlap);
      end;
    TmaxCronOverlapMode.omSkipIfRunning:
      begin
        if TInterlocked.CompareExchange(fRunning, 1, 0) <> 0 then Exit;
        if not TryAcquireExecution then
        begin
          TInterlocked.Exchange(fRunning, 0);
          Exit;
        end;
        DispatchCallbacks(lInvokeMode, lOnEvent, lOnProc, lOverlap);
      end;
    TmaxCronOverlapMode.omSerialize:
      begin
        if TInterlocked.CompareExchange(fRunning, 1, 0) = 0 then
        begin
          if not TryAcquireExecution then
          begin
            TInterlocked.Exchange(fRunning, 0);
            Exit;
          end;
          DispatchCallbacks(lInvokeMode, lOnEvent, lOnProc, lOverlap);
        end else
          TInterlocked.Increment(fPendingRuns);
      end;
    TmaxCronOverlapMode.omSerializeCoalesce:
      begin
        if TInterlocked.CompareExchange(fRunning, 1, 0) = 0 then
        begin
          if not TryAcquireExecution then
          begin
            TInterlocked.Exchange(fRunning, 0);
            Exit;
          end;
          DispatchCallbacks(lInvokeMode, lOnEvent, lOnProc, lOverlap);
        end else begin
          TInterlocked.CompareExchange(fPendingRuns, 1, 0); // keep backlog <= 1
        end;
      end;
  end;
end;

{ TPlan }

function TPlan.asString: String;
const
  sep = ' ';

  function process(const s: string; aDefault: char = '*'): string;
  begin
    Result := Trim(s);
    if Result = '' then
      Result := aDefault;
  end;

begin
  Result :=
    process(Minute) + sep +
    process(Hour) + sep +
    process(DayOfTheMonth) + sep +
    process(Month) + sep +
    process(DayOfTheWeek) + sep +
    process(Year) + sep +
    process(Second, '0') + sep +
    process(ExecutionLimit, '0');
end;

procedure TPlan.reset;
begin
  Minute := '';
  Hour := '';
  DayOfTheMonth := '';
  Month := '';
  DayOfTheWeek := '';
  Year := '';
  Second := '0';
  ExecutionLimit := '0';
end;

procedure TPlan.setText(const Value: string);
var
  l: TStringList;
  s: string;
  x: integer;
begin
  reset;

  s := Value;
  // preprocess the string
  s := StringReplace(s, '*', ' *', [rfReplaceAll]);
  s := StringReplace(s, ', ', ',', [rfReplaceAll]);
  s := StringReplace(s, '  ', ' ', [rfReplaceAll]);
  s := Trim(s);

  l := TStringList.Create;
  try
    l.Delimiter := ' ';
    l.StrictDelimiter := True;
    l.DelimitedText := s;

    for x := 0 to Min(Length(parts), l.Count) - 1 do
      parts[x] := l[x];
  finally
    l.Free;
  end;

end;

end.

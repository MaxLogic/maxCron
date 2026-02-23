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
  System.Classes, System.Generics.Collections, System.SysUtils, System.SyncObjs,
  Winapi.Windows,
  Vcl.ExtCtrls, MaxLogic.PortableTimer;

Type
  // forward declarations
  TmaxCron = class;
  IMaxCronEvent = interface;
  TCronSchedulePlan = class;

  TmaxCronNotifyEvent = procedure(Sender: IMaxCronEvent) of object;
  TmaxCronNotifyProc = reference to procedure(Sender: IMaxCronEvent);

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

  /// <summary>
  /// Misfire handling when the scheduler is delayed or the machine sleeps.
  /// </summary>
  TmaxCronMisfirePolicy = (
    mpDefault,      // use scheduler DefaultMisfirePolicy
    mpSkip,         // skip missed occurrences, advance to next after now
    mpFireOnceNow,  // fire once now, then skip to next after now
    mpCatchUpAll    // fire missed occurrences sequentially (bounded per tick)
    );

  TmaxCronDstSpringPolicy = (
    dspSkip,              // skip invalid local times during spring-forward
    dspRunAtNextValidTime // shift to the next valid local time
    );

  TmaxCronDstFallPolicy = (
    dfpRunOnce,                 // run once (earlier UTC instant)
    dfpRunTwice,                // run both ambiguous local-time instances
    dfpRunOncePreferFirstInstance,
    dfpRunOncePreferSecondInstance
    );

  /// <summary>
  /// How we combine Day-of-Month (DOM) and Day-of-Week (DOW) when both are restricted (not '*').
  /// dmAnd keeps our legacy maxCron behavior; dmOr matches classic crontab OR semantics.
  /// </summary>
  TmaxCronDayMatchMode = (dmDefault, dmAnd, dmOr);

  /// <summary>
  /// Cron parsing dialect. Use cdQuartzSecondsFirst for Quartz-style seconds-first 6/7-field plans
  /// and for expressions that use Quartz-style modifiers like ?, W, LW, or # to avoid field-order surprises.
  /// </summary>
  TmaxCronDialect = (cdStandard, cdMaxCron, cdQuartzSecondsFirst);

  TmaxCronTimerBackend = (ctAuto, ctVcl, ctPortable);

  TDates = array of TDateTime;
  TWordArray = array of Word;
  TFindNextScheduleResult = (fnsFound, fnsNotFound, fnsSearchLimitReached);

  IMaxCronEvent = interface
    ['{FA8F7A40-5E06-4C8A-B908-6CB2D9FC2C89}']
    function Run: IMaxCronEvent;
    procedure Stop;
    function GetEventPlan: string;
    procedure SetEventPlan(const aValue: string);
    function GetNextSchedule: TDateTime;
    function GetId: Int64;
    function GetName: string;
    function GetLastExecution: TDateTime;
    function GetTag: Integer;
    procedure SetTag(const aValue: Integer);
    function GetUserData: Pointer;
    procedure SetUserData(const aValue: Pointer);
    function GetUserDataInterface: IInterface;
    procedure SetUserDataInterface(const aValue: IInterface);
    function GetOnScheduleEvent: TmaxCronNotifyEvent;
    procedure SetOnScheduleEvent(const aValue: TmaxCronNotifyEvent);
    function GetOnScheduleProc: TmaxCronNotifyProc;
    procedure SetOnScheduleProc(const aValue: TmaxCronNotifyProc);
    function GetEnabled: Boolean;
    procedure SetEnabled(const aValue: Boolean);
    function GetInvokeMode: TmaxCronInvokeMode;
    procedure SetInvokeMode(const aValue: TmaxCronInvokeMode);
    function GetOverlapMode: TmaxCronOverlapMode;
    procedure SetOverlapMode(const aValue: TmaxCronOverlapMode);
    function GetDayMatchMode: TmaxCronDayMatchMode;
    procedure SetDayMatchMode(const aValue: TmaxCronDayMatchMode);
    function GetDialect: TmaxCronDialect;
    procedure SetDialect(const aValue: TmaxCronDialect);
    function GetMisfirePolicy: TmaxCronMisfirePolicy;
    procedure SetMisfirePolicy(const aValue: TmaxCronMisfirePolicy);
    function GetTimeZoneId: string;
    procedure SetTimeZoneId(const aValue: string);
    function GetDstSpringPolicy: TmaxCronDstSpringPolicy;
    procedure SetDstSpringPolicy(const aValue: TmaxCronDstSpringPolicy);
    function GetDstFallPolicy: TmaxCronDstFallPolicy;
    procedure SetDstFallPolicy(const aValue: TmaxCronDstFallPolicy);
    function GetWeekdaysOnly: Boolean;
    procedure SetWeekdaysOnly(const aValue: Boolean);
    function GetExcludedDatesCsv: string;
    procedure SetExcludedDatesCsv(const aValue: string);
    function GetBlackoutStartTime: TDateTime;
    procedure SetBlackoutStartTime(const aValue: TDateTime);
    function GetBlackoutEndTime: TDateTime;
    procedure SetBlackoutEndTime(const aValue: TDateTime);
    function GetNumOfExecutionsPerformed: UInt64;
    function GetValidFrom: TDateTime;
    procedure SetValidFrom(const aValue: TDateTime);
    function GetValidTo: TDateTime;
    procedure SetValidTo(const aValue: TDateTime);
    property EventPlan: string read GetEventPlan write SetEventPlan;
    property NextSchedule: TDateTime read GetNextSchedule;
    property Id: Int64 read GetId;
    property Name: string read GetName;
    property LastExecution: TDateTime read GetLastExecution;
    property Tag: Integer read GetTag write SetTag;
    property UserData: Pointer read GetUserData write SetUserData;
    property UserDataInterface: IInterface read GetUserDataInterface write SetUserDataInterface;
    property OnScheduleEvent: TmaxCronNotifyEvent read GetOnScheduleEvent write SetOnScheduleEvent;
    property OnScheduleProc: TmaxCronNotifyProc read GetOnScheduleProc write SetOnScheduleProc;
    property Enabled: Boolean read GetEnabled write SetEnabled;
    property InvokeMode: TmaxCronInvokeMode read GetInvokeMode write SetInvokeMode;
    property OverlapMode: TmaxCronOverlapMode read GetOverlapMode write SetOverlapMode;
    property DayMatchMode: TmaxCronDayMatchMode read GetDayMatchMode write SetDayMatchMode;
    property Dialect: TmaxCronDialect read GetDialect write SetDialect;
    property MisfirePolicy: TmaxCronMisfirePolicy read GetMisfirePolicy write SetMisfirePolicy;
    property TimeZoneId: string read GetTimeZoneId write SetTimeZoneId;
    property DstSpringPolicy: TmaxCronDstSpringPolicy read GetDstSpringPolicy write SetDstSpringPolicy;
    property DstFallPolicy: TmaxCronDstFallPolicy read GetDstFallPolicy write SetDstFallPolicy;
    property WeekdaysOnly: Boolean read GetWeekdaysOnly write SetWeekdaysOnly;
    property ExcludedDatesCsv: string read GetExcludedDatesCsv write SetExcludedDatesCsv;
    property BlackoutStartTime: TDateTime read GetBlackoutStartTime write SetBlackoutStartTime;
    property BlackoutEndTime: TDateTime read GetBlackoutEndTime write SetBlackoutEndTime;
    property NumOfExecutionsPerformed: UInt64 read GetNumOfExecutionsPerformed;
    property ValidFrom: TDateTime read GetValidFrom write SetValidFrom;
    property ValidTo: TDateTime read GetValidTo write SetValidTo;
  end;

  {$IFDEF MAXCRON_TESTS}
  TmaxCronAsyncCallHook = reference to function(const aProc: TThreadProcedure; const aTaskName: string): IInterface;
  TmaxCronBeforeQueuedAcquireHook = reference to procedure(const aEvent: IMaxCronEvent);
  TmaxCronBeforeDispatchHook = reference to procedure(const aInvokeMode: TmaxCronInvokeMode);
  {$ENDIF}

  ICronTimer = interface
    ['{4F3B81F6-57F0-4A98-9F65-6B8E7A7A0E41}']
    procedure Start(const aIntervalMs: Cardinal);
    procedure Stop;
    procedure SetOnTimer(const aValue: TNotifyEvent);
  end;

  TMaxCronAutoDiagnostics = record
    ConfiguredEngine: string;
    EffectiveEngine: string;
    AutoState: string;
    LastSwitchReason: string;
    SwitchCount: UInt64;
    EventCountEwma: Double;
    DueDensityEwma: Double;
    DirtyRateEwma: Double;
    ScanTickUsEwma: Double;
    HeapTickUsEwma: Double;
    ScanBaselineUs: Double;
    CooldownTicks: Integer;
    TrialFailLevel: Integer;
    TrialFailCooldownTicks: Integer;
    SwitchBudgetHits: Integer;
    SwitchBudgetCooldownTicks: Integer;
    SwitchBudgetRecentSwitches: Integer;
    SwitchBurstLevel: Integer;
    ScanSampleTicks: Integer;
    HeapSampleTicks: Integer;
    TicksSinceSwitch: Integer;
  end;

  TmaxCron = class(TObject)
  private
    type
      TSchedulerEngine = (seScan, seHeap, seShadow, seAuto);

      TAutoSchedulerState = (asDisabled, asScanStable, asHeapTrial, asHeapStable);

      TAutoControllerConfig = record
        EwmaAlpha: Double;
        EnterMinEvents: Integer;
        ExitMaxEvents: Integer;
        EnterMaxDueDensity: Double;
        ExitMinDueDensity: Double;
        EnterMaxDirtyRate: Double;
        ExitMinDirtyRate: Double;
        EnterHoldTicks: Integer;
        ExitHoldTicks: Integer;
        TrialTicks: Integer;
        CooldownTicks: Integer;
        TrialFailCooldownBaseTicks: Integer;
        SwitchBudgetWindowTicks: Integer;
        SwitchBudgetMaxSwitches: Integer;
        SwitchBudgetCooldownTicks: Integer;
        PromoteRatio: Double;
        DemoteRatio: Double;
        DiagLogIntervalTicks: Integer;
      end;

      TCronHeapEntry = record
        DueAt: TDateTime;
        EventId: Int64;
      end;
  private
    fRequestedTimerBackend: TmaxCronTimerBackend;
    fActiveTimerBackend: TmaxCronTimerBackend;
    fDefaultInvokeMode: TmaxCronInvokeMode;
    fDefaultDayMatchMode: TmaxCronDayMatchMode;
    fDefaultDialect: TmaxCronDialect;
    fDefaultMisfirePolicy: TmaxCronMisfirePolicy;
    fDefaultMisfireCatchUpLimit: Cardinal;
    fTimer: ICronTimer;
    fItems: TList<IMaxCronEvent>;
    fItemsById: TDictionary<Int64, Integer>;
    fItemsByName: TDictionary<string, Integer>;
    fHeapItems: TList<TCronHeapEntry>;
    fHeapDirty: Integer;
    fSchedulerEngine: TSchedulerEngine;
    fAutoEffectiveEngine: TSchedulerEngine;
    fAutoState: TAutoSchedulerState;
    fAutoLock: TCriticalSection;
    fAutoMutationCounter: Int64;
    fAutoMutationCursor: Int64;
    fAutoEnterHold: Integer;
    fAutoExitHold: Integer;
    fAutoTrialTicksRemaining: Integer;
    fAutoCooldownTicks: Integer;
    fAutoTrialFailLevel: Integer;
    fAutoTrialFailCooldownTicks: Integer;
    fAutoSwitchBudgetHits: Integer;
    fAutoControllerTick: UInt64;
    fAutoSwitchBudgetUntilTick: UInt64;
    fAutoSwitchHistory: TQueue<UInt64>;
    fAutoSwitchCount: UInt64;
    fAutoEventCountEwma: Double;
    fAutoDueDensityEwma: Double;
    fAutoDirtyRateEwma: Double;
    fAutoScanTickUsEwma: Double;
    fAutoHeapTickUsEwma: Double;
    fAutoScanBaselineUs: Double;
    fAutoScanSampleTicks: Integer;
    fAutoHeapSampleTicks: Integer;
    fAutoTicksSinceSwitch: Integer;
    fAutoSwitchBurstLevel: Integer;
    fAutoLastSwitchReason: string;
    fAutoDiagLogTicksUntilEmit: Integer;
    fAutoConfig: TAutoControllerConfig;
    fTickEventsVisited: UInt64;
    fHeapRebuildCount: UInt64;
    fItemsLock: TCriticalSection;
    fPendingFree: TList<IMaxCronEvent>;
    fNextId: Int64;
    fTickDepth: Integer;
    fTickQueued: Integer;
    fSharedState: IInterface;
    fAsyncKeepAlive: TList<IInterface>;
    fAsyncLock: TCriticalSection;
    function EventNameKey(const aName: string): string;
    function NormalizeEventName(const aName: string): string;
    function FindIndexByNameLocked(const aName: string): Integer;
    function FindIndexByIdLocked(const aId: Int64): Integer;
    function TryGetEventByIdLocked(const aId: Int64; out aEventItem: IMaxCronEvent): Boolean;
    procedure IndexEventLocked(const aEventItem: IMaxCronEvent; const aIndex: Integer);
    procedure RemoveEventIndexLocked(const aEventItem: IMaxCronEvent);
    procedure ReindexFromLocked(const aStartIndex: Integer);
    procedure ConfigureSchedulerEngine;
    procedure ConfigureAutoControllerSettings;
    function ClampAutoInt(const aValue, aMin, aMax: Integer): Integer;
    function ClampAutoFloat(const aValue, aMin, aMax: Double): Double;
    function TryReadAutoIntEnv(const aEnvName: string; out aValue: Integer): Boolean;
    function TryReadAutoFloatEnv(const aEnvName: string; out aValue: Double): Boolean;
    procedure MarkHeapDirty;
    function SchedulerEngineToText(const aEngine: TSchedulerEngine): string;
    function AutoStateToText(const aState: TAutoSchedulerState): string;
    function UpdateEwma(const aCurrent, aSample, aAlpha: Double): Double;
    procedure PruneAutoSwitchHistoryLocked(const aCurrentTick: UInt64; const aWindowTicks: Integer);
    function IsAutoSwitchBudgetExceededLocked(const aCurrentTick: UInt64; const aWindowTicks,
      aMaxSwitches: Integer): Boolean;
    function GetAutoSwitchBudgetCooldownTicksLocked(const aCurrentTick: UInt64): Integer;
    procedure ApplyAutoTrialFailureBackoff(const aBaseCooldownTicks: Integer);
    procedure SwitchAutoEffectiveEngine(const aEngine: TSchedulerEngine; const aReason: string);
    procedure EvaluateAutoController(const aEngineUsed: TSchedulerEngine; const aEventCount, aDueCount: Integer;
      const aElapsedMicroseconds: Int64);
    procedure RebuildHeapLocked;
    procedure HeapPushLocked(const aDueAt: TDateTime; const aEventId: Int64);
    function HeapPopLocked(out aEntry: TCronHeapEntry): Boolean;
    function HeapPeekLocked(out aEntry: TCronHeapEntry): Boolean;
    procedure HeapSiftUpLocked(const aIndex: Integer);
    procedure HeapSiftDownLocked(const aIndex: Integer);
    function HeapEntryLessThan(const aLeft, aRight: TCronHeapEntry): Boolean;
    procedure DoTickAtScan(const aNow: TDateTime; out aDueCount: Integer);
    procedure DoTickAtHeap(const aNow: TDateTime; out aDueCount: Integer);
    procedure ValidateShadowParity(const aNow: TDateTime);
    procedure CollectScanDueIdsLocked(const aNow: TDateTime; const aIds: TList<Int64>);
    procedure CollectHeapDueIdsLocked(const aNow: TDateTime; const aIds: TList<Int64>);
    function Int64ListToText(const aIds: TList<Int64>): string;
    function DeleteLocked(const aIndex: Integer): Boolean;
    procedure TimerTimer(Sender: TObject);
    procedure CreateTimer(const aRequestedBackend: TmaxCronTimerBackend);
    procedure DoTick;
    procedure DoTickAt(const aNow: TDateTime);
    procedure QueueTick;
    procedure KeepAsyncAlive(const aAsync: IInterface);
    procedure ReleaseAsyncAlive(const aAsync: IInterface);
    procedure FlushPendingFree;
    procedure FlushPendingFreeLocked;
    procedure SetDefaultInvokeMode(const aValue: TmaxCronInvokeMode);
    procedure SetDefaultDayMatchMode(const Value: TmaxCronDayMatchMode);
    procedure SetDefaultDialect(const Value: TmaxCronDialect);
    procedure SetDefaultMisfirePolicy(const aValue: TmaxCronMisfirePolicy);
    procedure SetDefaultMisfireCatchUpLimit(const Value: Cardinal);

  public
    constructor Create; overload;
    constructor Create(const aTimerBackend: TmaxCronTimerBackend); overload;
    destructor Destroy; override;

    procedure Clear;

    Function Add(const aName: string): IMaxCronEvent; overload;
    Function Add(const aName, aEventPlan: string; const aOnScheduleEvent: TmaxCronNotifyEvent): IMaxCronEvent; overload;
    Function Add(const aName, aEventPlan: string; const aOnScheduleEvent: TmaxCronNotifyProc): IMaxCronEvent; overload;

    function Delete(const aId: Int64): boolean; overload;
    function Delete(const aName: string): boolean; overload;
    function Delete(event: IMaxCronEvent): boolean; overload;
    function Snapshot: TArray<IMaxCronEvent>;
    function TryGetAutoDiagnostics(out aDiagnostics: TMaxCronAutoDiagnostics): Boolean;

    property RequestedTimerBackend: TmaxCronTimerBackend read fRequestedTimerBackend;
    property ActiveTimerBackend: TmaxCronTimerBackend read fActiveTimerBackend;
    property DefaultInvokeMode: TmaxCronInvokeMode read fDefaultInvokeMode write SetDefaultInvokeMode;
    property DefaultDayMatchMode: TmaxCronDayMatchMode read fDefaultDayMatchMode write SetDefaultDayMatchMode;
    property DefaultDialect: TmaxCronDialect read fDefaultDialect write SetDefaultDialect;
    property DefaultMisfirePolicy: TmaxCronMisfirePolicy read fDefaultMisfirePolicy write SetDefaultMisfirePolicy;
    property DefaultMisfireCatchUpLimit: Cardinal read fDefaultMisfireCatchUpLimit write SetDefaultMisfireCatchUpLimit;

    {$IFDEF MAXCRON_TESTS}
    procedure TickAt(const aNow: TDateTime);
    procedure StartTimerForTests(const aIntervalMs: Cardinal);
    procedure ResetTickMetricsForTests;
    procedure GetTickMetricsForTests(out aEventsVisited: UInt64; out aHeapRebuilds: UInt64);
    procedure GetEngineStateForTests(out aConfiguredEngine: string; out aEffectiveEngine: string;
      out aAutoState: string; out aSwitchCount: UInt64);
    {$ENDIF}
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

  /// <summary>
  /// Day-of-Month special modifiers (Quartz-style).
  /// </summary>
  TCronDomModifier = (
    cdmNone,
    cdmLastDay,
    cdmNearestWeekday,
    cdmLastWeekday
    );

  /// <summary>
  /// Day-of-Week special modifiers (Quartz-style).
  /// </summary>
  TCronDowModifier = (
    cdwNone,
    cdwLastWeekday,
    cdwNthWeekday
    );

  TPlan = record
  private
    fDialect: TmaxCronDialect;
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
    /// <summary>
    /// Controls how <c>Text</c> is parsed and emitted (standard 5-field, maxCron 5-8, or Quartz seconds-first).
    /// </summary>
    property Dialect: TmaxCronDialect read fDialect write fDialect;

    /// <summary>
    /// Gets or sets the cron text, respecting the current Dialect when reading or writing.
    /// </summary>
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
    fNeedsParse: Boolean;
    fNoSpec: Boolean;
    fDomModifier: TCronDomModifier;
    fDomValue: Word;
    fDowModifier: TCronDowModifier;
    fDowValue: Word;
    fDowNth: Word;
    fDowOneBased: Boolean;
    fHashSeed: string;

    procedure Parse;
    procedure SetData(const Value: string);
    procedure ParsePart(const Value: string);
    function ReplaceMonthNames(const Value: string): string;
    function ReplaceDaynames(const Value: string): string;
    Procedure Add2Range(Value: word);
    function FindInRange(Value: word; out index: integer): boolean;
    function HasSpecial: Boolean;
    function TryParseSpecialToken(const aToken: string): Boolean;
    function TryParseDomSpecial(const aToken: string): Boolean;
    function TryParseDowSpecial(const aToken: string): Boolean;
    function NormalizeDowValue(const aValue: Integer): Integer;
    function Hash32(const aValue: string): Cardinal;
    function TryParseHashedToken(const aValue: string): Boolean;
    function GetLastDayOfMonth(const aYear, aMonth: Word): Word;
    function GetLastWeekdayOfMonth(const aYear, aMonth: Word; out aDay: Word): Boolean;
    function GetNearestWeekdayTo(const aYear, aMonth, aDay: Word; out aNearestDay: Word): Boolean;
    function GetNthWeekdayOfMonth(const aYear, aMonth, aDow, aNth: Word; out aDay: Word): Boolean;
    function GetLastDowOfMonth(const aYear, aMonth, aDow: Word; out aDay: Word): Boolean;
    function TryGetDomSpecialDay(const aYear, aMonth: Word; out aDay: Word): Boolean;
    function TryGetDowSpecialDay(const aYear, aMonth: Word; out aDay: Word): Boolean;

    function PushYear(var NextDate: TDateTime): boolean;
    function PushMonth(var NextDate: TDateTime): boolean;
    /// <summary>
    /// Advances NextDate to the next matching DOM, including special modifiers (L/W/LW).
    /// If the month-relative target already passed, we move to the next month and recompute.
    /// </summary>
    function PushDayOfMonth(var NextDate: TDateTime): boolean;
    /// <summary>
    /// Advances NextDate to the next matching DOW, including special modifiers (nL/n#k).
    /// If the month-relative target already passed, we move to the next month and recompute.
    /// </summary>
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
    function IsAny: Boolean;
    function IsNoSpec: Boolean;
    function HasSpecialTokens: Boolean;
    function TryGetSingleValue(out aValue: Word): Boolean;
    function TryGetStep(out aStart, aStep: Word; out aCoversFullRange: Boolean): Boolean;
    function GetValues(out aValues: TWordArray): Boolean;
    function DescribeDomSpecial: string;

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
    fDialect: TmaxCronDialect;
    fLastPlan: string;
    fHashSeed: string;

    function GetParts(PartKind: TPartKind): TCronPart;
    function DomMatchesDate(const aDate: TDateTime): Boolean;
    function DowMatchesDate(const aDate: TDateTime): Boolean;
    procedure SetDayOfTheMonth(const Value: TCronPart);
    procedure SetDayOfTheWeek(const Value: TCronPart);
    procedure SetHour(const Value: TCronPart);
    procedure SetMinute(const Value: TCronPart);
    procedure SetMonth(const Value: TCronPart);
    procedure SetParts(PartKind: TPartKind; const Value: TCronPart);
    procedure SetSecond(const Value: TCronPart);
    procedure SetYear(const Value: TCronPart);
    procedure SetDialect(const Value: TmaxCronDialect);
    function PushDomDow(var NextDate: TDateTime): boolean;
    procedure ApplyDialectToParts;
  public
    Constructor Create;
    Destructor Destroy; override;

    procedure Parse(const CronPlan: string);
    procedure Clear;

    function FindNextScheduleDate(const aBaseDate: TDateTime;
      out aNextDateTime: TDateTime;
      const aValidFrom: TDateTime = 0;
      const aValidTo: TDateTime = 0): boolean;
    function GetNextOccurrences(const aCount: Integer; const aFromDate: TDateTime;
      out aDates: TDates; const aValidFrom: TDateTime = 0;
      const aValidTo: TDateTime = 0): Integer;
    function Describe: string;

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
    property Dialect: TmaxCronDialect read fDialect write SetDialect;
    property HashSeed: string read fHashSeed write fHashSeed;
  end;

  // you can use this to show the user a preview ow what his schedule will look like.
function MakePreview(const SchedulePlan: string; out Dates: TDates; Limit: integer = 100): boolean; overload;
function MakePreview(const SchedulePlan: string; const Dialect: TmaxCronDialect; out Dates: TDates;
  Limit: integer = 100): boolean; overload;

{$IFDEF MAXCRON_TESTS}
procedure SetMaxCronAsyncCallHook(const aHook: TmaxCronAsyncCallHook);
procedure SetMaxCronBeforeQueuedAcquireHook(const aHook: TmaxCronBeforeQueuedAcquireHook);
procedure SetMaxCronBeforeDispatchHook(const aHook: TmaxCronBeforeDispatchHook);
{$ENDIF}

implementation

uses
  System.DateUtils, System.Diagnostics, System.Math, System.StrUtils, System.Threading,
  maxAsync;

{$IFDEF MAXCRON_TESTS}
var
  gMaxCronAsyncCallHook: TmaxCronAsyncCallHook = nil;
  gMaxCronBeforeQueuedAcquireHook: TmaxCronBeforeQueuedAcquireHook = nil;
  gMaxCronBeforeDispatchHook: TmaxCronBeforeDispatchHook = nil;

procedure SetMaxCronAsyncCallHook(const aHook: TmaxCronAsyncCallHook);
begin
  gMaxCronAsyncCallHook := aHook;
end;

procedure SetMaxCronBeforeQueuedAcquireHook(const aHook: TmaxCronBeforeQueuedAcquireHook);
begin
  gMaxCronBeforeQueuedAcquireHook := aHook;
end;

procedure SetMaxCronBeforeDispatchHook(const aHook: TmaxCronBeforeDispatchHook);
begin
  gMaxCronBeforeDispatchHook := aHook;
end;
{$ENDIF}

threadvar
  gMaxCronExecutingCron: Pointer;

type
  ICronSharedState = interface
    ['{6A7A6429-48F6-4F7A-854A-55C8DFA7FC31}']
    procedure Detach;
    function IsAlive: Boolean;
    function TryGetDefaultInvokeMode(out aInvokeMode: TmaxCronInvokeMode): Boolean;
    function TryGetDefaultDayMatchMode(out aDayMatchMode: TmaxCronDayMatchMode): Boolean;
    function TryGetMisfireDefaults(out aMisfirePolicy: TmaxCronMisfirePolicy; out aCatchUpLimit: Cardinal): Boolean;
    function TryGetOwnerPointer(out aOwnerPointer: Pointer): Boolean;
    function GetInFlightCount: Integer;
    procedure IncrementCallbackDepth;
    procedure DecrementCallbackDepth;
    function GetCallbackDepth: Integer;
    procedure MarkHeapDirty;
    procedure KeepAsyncAlive(const aAsync: IInterface);
    procedure ReleaseAsyncAlive(const aAsync: IInterface);
    procedure FlushPendingFree;
    procedure ExecuteQueuedTick;
    procedure ResetTickQueued;
  end;

  TCronSharedState = class(TInterfacedObject, ICronSharedState)
  private
    fLock: TCriticalSection;
    fOwner: TmaxCron;
    fInFlight: Integer;
    fCallbackDepth: Integer;
    function TryAcquireOwner(out aOwner: TmaxCron): Boolean;
    procedure ReleaseOwner;
  public
    constructor Create(const aOwner: TmaxCron);
    destructor Destroy; override;
    procedure Detach;
    function IsAlive: Boolean;
    function TryGetDefaultInvokeMode(out aInvokeMode: TmaxCronInvokeMode): Boolean;
    function TryGetDefaultDayMatchMode(out aDayMatchMode: TmaxCronDayMatchMode): Boolean;
    function TryGetMisfireDefaults(out aMisfirePolicy: TmaxCronMisfirePolicy; out aCatchUpLimit: Cardinal): Boolean;
    function TryGetOwnerPointer(out aOwnerPointer: Pointer): Boolean;
    function GetInFlightCount: Integer;
    procedure IncrementCallbackDepth;
    procedure DecrementCallbackDepth;
    function GetCallbackDepth: Integer;
    procedure MarkHeapDirty;
    procedure KeepAsyncAlive(const aAsync: IInterface);
    procedure ReleaseAsyncAlive(const aAsync: IInterface);
    procedure FlushPendingFree;
    procedure ExecuteQueuedTick;
    procedure ResetTickQueued;
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

  TmaxCronEvent = class;

  ICronEventInternal = interface
    ['{E5E7D6F4-98F9-4E4B-8B5C-8A6F9026C8D4}']
    function AsEventObject: TmaxCronEvent;
  end;

  TmaxCronEvent = class(TInterfacedObject, IMaxCronEvent, ICronEventInternal)
  private
    type
      TCronTimeZoneKind = (ctzLocal, ctzUtc, ctzFixedOffset);
  private
    fSharedState: ICronSharedState;
    fScheduler: TCronSchedulePlan;
    FEventPlan: string;
    fId: Int64;

    FName: string;
    FOnScheduleEvent: TmaxCronNotifyEvent;

    FTag: Integer;
    FUserData: Pointer;
    FUserDataInterface: IInterface;

    FEnabled: Boolean;
    fNextSchedule: TDateTime;
    FValidFrom: TDateTime;
    FValidTo: TDateTime;
    FOnScheduleProc: TmaxCronNotifyProc;
    fNumOfExecutions: UInt64;
    fNumOfDue: UInt64;
    fLastExecutionTime: TDateTime;
    fInvokeMode: TmaxCronInvokeMode;
    fLock: TCriticalSection;
    fEventToken: IInterface;
    fOverlapMode: TmaxCronOverlapMode;
    fDayMatchMode: TmaxCronDayMatchMode;
    fDialect: TmaxCronDialect;
    fMisfirePolicy: TmaxCronMisfirePolicy;
    fTimeZoneId: string;
    fTimeZoneKind: TCronTimeZoneKind;
    fTimeZoneOffsetMinutes: Integer;
    fDstSpringPolicy: TmaxCronDstSpringPolicy;
    fDstFallPolicy: TmaxCronDstFallPolicy;
    fWeekdaysOnly: Boolean;
    fExcludedDatesCsv: string;
    fExcludedDateSerials: TArray<Integer>;
    fBlackoutStartTime: TDateTime;
    fBlackoutEndTime: TDateTime;
    fPendingDstSecondSchedule: TDateTime;
    fNextScheduleNeedsResolve: Boolean;
    fRunning: Integer;
    fPendingRuns: Integer;
    fExecDepth: Integer;
    fAllowDisabledDispatch: Integer;
    fPendingDestroy: Boolean;
    fAmbiguousSecondGateActive: Boolean;
    fAmbiguousSecondGatePassedTarget: Boolean;
    fAmbiguousSecondGateRollbackSeen: Boolean;

    function GetEventPlan: string;
    function GetId: Int64;
    function GetName: string;
    function GetTag: Integer;
    function GetUserData: Pointer;
    function GetUserDataInterface: IInterface;
    function GetOnScheduleEvent: TmaxCronNotifyEvent;
    function GetOnScheduleProc: TmaxCronNotifyProc;
    function GetInvokeMode: TmaxCronInvokeMode;
    function GetDialect: TmaxCronDialect;
    function GetTimeZoneId: string;
    function GetDstSpringPolicy: TmaxCronDstSpringPolicy;
    function GetDstFallPolicy: TmaxCronDstFallPolicy;
    function GetWeekdaysOnly: Boolean;
    function GetExcludedDatesCsv: string;
    function GetBlackoutStartTime: TDateTime;
    function GetBlackoutEndTime: TDateTime;
    function GetValidFrom: TDateTime;
    function GetValidTo: TDateTime;

    procedure SetOnScheduleEvent(const Value: TmaxCronNotifyEvent);
    procedure SetTag(const Value: Integer);
    procedure SetUserData(const Value: Pointer);
    procedure SetEventPlan(const Value: string);
    procedure SetEnabled(const Value: Boolean);
    procedure SetNumOfExecutions(const Value: UInt64);
    procedure SetValidFrom(const Value: TDateTime);
    procedure SetValidTo(const Value: TDateTime);
    procedure SetUserDataInterface(const Value: IInterface);
    procedure SetOnScheduleProc(const Value: TmaxCronNotifyProc);
    procedure SetInvokeMode(const Value: TmaxCronInvokeMode);
    procedure SetOverlapMode(const Value: TmaxCronOverlapMode);
    procedure SetDayMatchMode(const Value: TmaxCronDayMatchMode);
    procedure SetDialect(const Value: TmaxCronDialect);
    procedure SetMisfirePolicy(const Value: TmaxCronMisfirePolicy);
    procedure SetTimeZoneId(const Value: string);
    procedure SetDstSpringPolicy(const Value: TmaxCronDstSpringPolicy);
    procedure SetDstFallPolicy(const Value: TmaxCronDstFallPolicy);
    procedure SetWeekdaysOnly(const Value: Boolean);
    procedure SetExcludedDatesCsv(const Value: string);
    procedure SetBlackoutStartTime(const Value: TDateTime);
    procedure SetBlackoutEndTime(const Value: TDateTime);
    function GetEnabled: Boolean;
    function GetNextSchedule: TDateTime;
    function GetLastExecution: TDateTime;
    function GetNumOfExecutionsPerformed: UInt64;
    function GetEffectiveInvokeMode: TmaxCronInvokeMode;
    function GetOverlapMode: TmaxCronOverlapMode;
    function GetDayMatchMode: TmaxCronDayMatchMode;
    function GetMisfirePolicy: TmaxCronMisfirePolicy;
    procedure DispatchCallbacks(const aInvokeMode: TmaxCronInvokeMode;
      const aOnEvent: TmaxCronNotifyEvent; const aOnProc: TmaxCronNotifyProc;
      const aOverlapMode: TmaxCronOverlapMode);
    procedure FinalizeOverlap(const aInvokeMode: TmaxCronInvokeMode;
      const aOnEvent: TmaxCronNotifyEvent; const aOnProc: TmaxCronNotifyProc;
      const aOverlapMode: TmaxCronOverlapMode);
    procedure ExecuteOnce(const aInvokeMode: TmaxCronInvokeMode;
      const aOnEvent: TmaxCronNotifyEvent; const aOnProc: TmaxCronNotifyProc;
      const aOverlapMode: TmaxCronOverlapMode);
    function TryReserveExecution: Boolean;
    function TryAcquireExecution: Boolean;
    procedure ReleaseExecution;
    procedure RollbackReservedExecution;
    procedure HandleQueuedAcquireFailure(const aOverlapMode: TmaxCronOverlapMode);
    procedure RollbackDispatchStartFailure(const aOverlapMode: TmaxCronOverlapMode);
    procedure QueueMainThreadCallbacks(const aInvokeMode: TmaxCronInvokeMode;
      const aOnEvent: TmaxCronNotifyEvent; const aOnProc: TmaxCronNotifyProc;
      const aOverlapMode: TmaxCronOverlapMode);
    procedure DispatchScheduledCallbacks(const aInvokeMode: TmaxCronInvokeMode;
      const aOnEvent: TmaxCronNotifyEvent; const aOnProc: TmaxCronNotifyProc;
      const aOverlapMode: TmaxCronOverlapMode);
    procedure MarkPendingDestroy;
    function CanFreeNow: Boolean;
    function IsTimeInBlackout(const aEventLocalDateTime: TDateTime): Boolean;
    function IsOccurrenceExcluded(const aEventLocalDateTime: TDateTime): Boolean;
    function FindNextScheduleWithPolicies(const aBaseSystemLocal: TDateTime; out aNextSystemLocal: TDateTime): TFindNextScheduleResult;
    function SystemLocalToEventLocal(const aSystemLocal: TDateTime): TDateTime;
    function EventLocalToSystemLocal(const aEventLocal: TDateTime; out aSystemLocal: TDateTime): Boolean;
    function TryParseTimeZone(const aValue: string; out aKind: TCronTimeZoneKind;
      out aOffsetMinutes: Integer; out aNormalized: string): Boolean;
    procedure ParseExcludedDatesCsv(const aValue: string; out aDateSerials: TArray<Integer>);
    function GetHashSeed: string;
    function TryGetHeapScheduleSnapshot(out aId: Int64; out aDueAt: TDateTime): Boolean;
    function IsHeapScheduleCurrent(const aDueAt: TDateTime): Boolean;
    procedure ClearAmbiguousSecondGate;
    procedure ArmAmbiguousSecondGate(const aSchedule: TDateTime);
    function ProcessAmbiguousSecondGate(const aNow: TDateTime): Boolean;

    function AsEventObject: TmaxCronEvent;
    procedure checkTimer(const aNow: TDateTime);
    procedure ResetSchedule;
  public
    constructor Create;
    destructor Destroy; override;

    function Run: IMaxCronEvent;
    procedure Stop;

    property EventPlan: string read FEventPlan write SetEventPlan;
    property NextSchedule: TDateTime read GetNextSchedule;
    property Id: Int64 read GetId;
    property Name: string read GetName;
    property LastExecution: TDateTime read GetLastExecution;
    property Tag: Integer read FTag write SetTag;
    property UserData: Pointer read FUserData write SetUserData;
    property UserDataInterface: IInterface read FUserDataInterface write SetUserDataInterface;
    property OnScheduleEvent: TmaxCronNotifyEvent read FOnScheduleEvent write SetOnScheduleEvent;
    property OnScheduleProc: TmaxCronNotifyProc read FOnScheduleProc write SetOnScheduleProc;
    property Enabled: Boolean read GetEnabled write SetEnabled;
    property InvokeMode: TmaxCronInvokeMode read fInvokeMode write SetInvokeMode;
    property OverlapMode: TmaxCronOverlapMode read GetOverlapMode write SetOverlapMode;
    property DayMatchMode: TmaxCronDayMatchMode read GetDayMatchMode write SetDayMatchMode;
    property Dialect: TmaxCronDialect read fDialect write SetDialect;
    property MisfirePolicy: TmaxCronMisfirePolicy read GetMisfirePolicy write SetMisfirePolicy;
    property TimeZoneId: string read fTimeZoneId write SetTimeZoneId;
    property DstSpringPolicy: TmaxCronDstSpringPolicy read fDstSpringPolicy write SetDstSpringPolicy;
    property DstFallPolicy: TmaxCronDstFallPolicy read fDstFallPolicy write SetDstFallPolicy;
    property WeekdaysOnly: Boolean read fWeekdaysOnly write SetWeekdaysOnly;
    property ExcludedDatesCsv: string read fExcludedDatesCsv write SetExcludedDatesCsv;
    property BlackoutStartTime: TDateTime read fBlackoutStartTime write SetBlackoutStartTime;
    property BlackoutEndTime: TDateTime read fBlackoutEndTime write SetBlackoutEndTime;
    property NumOfExecutionsPerformed: UInt64 read GetNumOfExecutionsPerformed;
    property ValidFrom: TDateTime read FValidFrom write SetValidFrom;
    property ValidTo: TDateTime read FValidTo write SetValidTo;
  end;

  ICronEventToken = interface
    ['{1AD0B7CE-0C85-4490-9B3E-3E0E1C6115E6}']
    procedure Detach;
    function TryGetEvent(out aEvent: TmaxCronEvent): Boolean;
    function TryAcquireEvent(out aEvent: TmaxCronEvent): Boolean;
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
    function TryAcquireEvent(out aEvent: TmaxCronEvent): Boolean;
  end;

  IAsyncKeepAliveEntry = interface
    ['{96E1F117-5C6E-4B10-8D9C-0B8E7B2B0BB2}']
    procedure AttachAsync(const aAsync: IInterface);
    procedure MarkDone;
  end;

  TAsyncKeepAliveEntry = class(TInterfacedObject, IAsyncKeepAliveEntry)
  private
    fLock: TCriticalSection;
    fSharedState: ICronSharedState;
    fAsync: IInterface;
    fDone: Boolean;
  public
    constructor Create(const aSharedState: ICronSharedState);
    destructor Destroy; override;
    procedure AttachAsync(const aAsync: IInterface);
    procedure MarkDone;
  end;

procedure ExecuteQueuedMainThread(const aToken: ICronEventToken;
  const aInvokeMode: TmaxCronInvokeMode; const aOnEvent: TmaxCronNotifyEvent;
  const aOnProc: TmaxCronNotifyProc; const aOverlapMode: TmaxCronOverlapMode); forward;

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

function TryGetCronEvent(const aEvent: IMaxCronEvent; out aCronEvent: TmaxCronEvent): Boolean;
var
  lInternal: ICronEventInternal;
begin
  Result := Supports(aEvent, ICronEventInternal, lInternal);
  if Result then
    aCronEvent := lInternal.AsEventObject
  else
    aCronEvent := nil;
end;

function CallSimpleAsync(const aProc: TThreadProcedure; const aTaskName: string): IInterface;
begin
  {$IFDEF MAXCRON_TESTS}
  if Assigned(gMaxCronAsyncCallHook) then
    Exit(gMaxCronAsyncCallHook(aProc, aTaskName));
  {$ENDIF}
  Result := SimpleAsyncCall(aProc, aTaskName);
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

function StripCronComment(const aValue: string): string;
var
  i: Integer;
begin
  Result := aValue;
  for i := 1 to Length(Result) do
    if (Result[i] = '#') and ((i = 1) or (Result[i - 1] <= ' ')) then
    begin
      Result := Copy(Result, 1, i - 1);
      Break;
    end;
  Result := TrimRight(Result);
end;

procedure SplitByWhitespace(const aValue: string; aList: TStrings);
var
  i: Integer;
  lToken: string;
  c: Char;
begin
  aList.Clear;
  lToken := '';
  for i := 1 to Length(aValue) do
  begin
    c := aValue[i];
    if c <= ' ' then
    begin
      if lToken <> '' then
      begin
        aList.Add(lToken);
        lToken := '';
      end;
    end
    else
      lToken := lToken + c;
  end;

  if lToken <> '' then
    aList.Add(lToken);
end;

function NormalizeCommaWhitespace(const aValue: string): string;
var
  i: Integer;
  lResult: string;
  c: Char;
  lSkipWhitespace: Boolean;
begin
  lResult := '';
  lSkipWhitespace := False;
  for i := 1 to Length(aValue) do
  begin
    c := aValue[i];
    if lSkipWhitespace and (c <= ' ') then
      Continue;

    if c = ',' then
    begin
      while (Length(lResult) > 0) and (lResult[Length(lResult)] <= ' ') do
        Delete(lResult, Length(lResult), 1);
      lResult := lResult + c;
      lSkipWhitespace := True;
      Continue;
    end;

    lSkipWhitespace := False;
    lResult := lResult + c;
  end;
  Result := lResult;
end;

function TryApplyCronMacro(const aValue: string; var aPlan: TPlan): Boolean;
var
  lMacro: string;
begin
  lMacro := Trim(LowerCase(aValue));
  if (lMacro = '@yearly') or (lMacro = '@annually') then
  begin
    aPlan.Minute := '0';
    aPlan.Hour := '0';
    aPlan.DayOfTheMonth := '1';
    aPlan.Month := '1';
    aPlan.DayOfTheWeek := '*';
    Exit(True);
  end;

  if lMacro = '@monthly' then
  begin
    aPlan.Minute := '0';
    aPlan.Hour := '0';
    aPlan.DayOfTheMonth := '1';
    aPlan.Month := '*';
    aPlan.DayOfTheWeek := '*';
    Exit(True);
  end;

  if lMacro = '@weekly' then
  begin
    aPlan.Minute := '0';
    aPlan.Hour := '0';
    aPlan.DayOfTheMonth := '*';
    aPlan.Month := '*';
    if aPlan.Dialect = cdQuartzSecondsFirst then
      aPlan.DayOfTheWeek := '1'
    else
      aPlan.DayOfTheWeek := '0';
    Exit(True);
  end;

  if (lMacro = '@daily') or (lMacro = '@midnight') then
  begin
    aPlan.Minute := '0';
    aPlan.Hour := '0';
    aPlan.DayOfTheMonth := '*';
    aPlan.Month := '*';
    aPlan.DayOfTheWeek := '*';
    Exit(True);
  end;

  if lMacro = '@hourly' then
  begin
    aPlan.Minute := '0';
    aPlan.Hour := '*';
    aPlan.DayOfTheMonth := '*';
    aPlan.Month := '*';
    aPlan.DayOfTheWeek := '*';
    Exit(True);
  end;

  if lMacro = '@reboot' then
  begin
    if aPlan.Dialect <> cdMaxCron then
      Exit(False);
    aPlan.Minute := '*';
    aPlan.Hour := '*';
    aPlan.DayOfTheMonth := '*';
    aPlan.Month := '*';
    aPlan.DayOfTheWeek := '*';
    aPlan.Year := '*';
    aPlan.Second := '*';
    aPlan.ExecutionLimit := '1';
    Exit(True);
  end;

  Result := False;
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
  fDialect := cdMaxCron;
  fLastPlan := '';
  fHashSeed := '';
  for pk := Low(TPartKind) to High(TPartKind) do
    parts[pk] := TCronPart.Create(pk);
  ApplyDialectToParts;
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
  lMode: TmaxCronDayMatchMode;

  function HasLeapYearInRange: Boolean;
  var
    i: Integer;
    y: Word;
  begin
    if FYear.Fullrange then
      Exit(True);
    Result := False;
    for i := 0 to FYear.FCount - 1 do
    begin
      y := FYear.fRange[i];
      if IsLeapYear(y) then
        Exit(True);
    end;
  end;

  function MaxDaysForMonth(const aMonth: Word): Word;
  begin
    case aMonth of
      2:
        if HasLeapYearInRange then
          Result := 29
        else
          Result := 28;
      4, 6, 9, 11:
        Result := 30;
    else
      Result := 31;
    end;
  end;

  function HasValidDomForMonth(const aMonth: Word): Boolean;
  var
    i: Integer;
    lMax: Word;
    lVal: Word;
  begin
    if FDayOfTheMonth.fFullrange then
      Exit(True);
    if FDayOfTheMonth.FCount = 0 then
      Exit(False);
    lMax := MaxDaysForMonth(aMonth);
    for i := 0 to FDayOfTheMonth.FCount - 1 do
    begin
      lVal := FDayOfTheMonth.fRange[i];
      if (lVal >= 1) and (lVal <= lMax) then
        Exit(True);
    end;
    Result := False;
  end;

  function HasDomInAllowedMonths: Boolean;
  var
    i: Integer;
    lMonth: Word;
  begin
    if FDayOfTheMonth.fFullrange then
      Exit(True);
    if FMonth.fFullrange then
    begin
      for lMonth := 1 to 12 do
        if HasValidDomForMonth(lMonth) then
          Exit(True);
      Exit(False);
    end;
    if FMonth.FCount = 0 then
      Exit(False);
    for i := 0 to FMonth.FCount - 1 do
    begin
      lMonth := FMonth.fRange[i];
      if HasValidDomForMonth(lMonth) then
        Exit(True);
    end;
    Result := False;
  end;
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

  lMode := fDayMatchMode;
  if lMode = TmaxCronDayMatchMode.dmDefault then
    lMode := TmaxCronDayMatchMode.dmAnd;
  if (not FDayOfTheMonth.Fullrange) and (FDayOfTheMonth.fDomModifier = TCronDomModifier.cdmNone) and
    ((lMode = TmaxCronDayMatchMode.dmAnd) or FDayOfTheWeek.Fullrange) then
    if not HasDomInAllowedMonths then
      Exit(False);

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

function FormatTwo(const aValue: Word): string;
begin
  Result := Format('%.2d', [aValue]);
end;

function FormatTime(const aHour, aMinute, aSecond: Word; const aIncludeSeconds: Boolean): string;
begin
  if aIncludeSeconds then
    Result := FormatTwo(aHour) + ':' + FormatTwo(aMinute) + ':' + FormatTwo(aSecond)
  else
    Result := FormatTwo(aHour) + ':' + FormatTwo(aMinute);
end;

function FormatDowName(const aDow: Word): string;
var
  lIndex: Word;
begin
  if aDow = 0 then
    lIndex := 7
  else
    lIndex := aDow;

  if (lIndex >= 1) and (lIndex <= 7) then
    Result := DayNames[lIndex]
  else
    Result := IntToStr(aDow);
end;

function FormatMonthName(const aMonth: Word): string;
begin
  if (aMonth >= 1) and (aMonth <= 12) then
    Result := MonthNames[aMonth]
  else
    Result := IntToStr(aMonth);
end;

function JoinValues(const aValues: TWordArray; const aKind: TPartKind): string;
var
  i: Integer;
  s: string;
begin
  s := '';
  for i := 0 to Length(aValues) - 1 do
  begin
    if i > 0 then
      s := s + ',';
    case aKind of
      TPartKind.ckDayOfTheWeek:
        s := s + FormatDowName(aValues[i]);
      TPartKind.ckMonth:
        s := s + FormatMonthName(aValues[i]);
    else
      s := s + IntToStr(aValues[i]);
    end;
  end;
  Result := s;
end;

function TCronSchedulePlan.GetNextOccurrences(const aCount: Integer; const aFromDate: TDateTime;
  out aDates: TDates; const aValidFrom: TDateTime; const aValidTo: TDateTime): Integer;
var
  lCursor: TDateTime;
  lNext: TDateTime;
  lStall: Integer;
  lMaxStall: Integer;
begin
  Result := 0;
  SetLength(aDates, 0);
  if aCount <= 0 then
    Exit;

  SetLength(aDates, aCount);
  lCursor := aFromDate;
  lStall := 0;
  lMaxStall := Max(8, aCount * 4);

  while Result < aCount do
  begin
    if not FindNextScheduleDate(lCursor, lNext, aValidFrom, aValidTo) then
      Break;

    if lNext <= lCursor then
    begin
      Inc(lStall);
      if lStall > lMaxStall then
        Break;
      lCursor := lCursor + OneSecond;
      Continue;
    end;

    aDates[Result] := lNext;
    Inc(Result);
    lCursor := lNext;
    lStall := 0;
  end;

  SetLength(aDates, Result);
end;

function TCronSchedulePlan.Describe: string;
var
  lHour: Word;
  lMinute: Word;
  lSecond: Word;
  lMonth: Word;
  lDom: Word;
  lYear: Word;
  lHasHour: Boolean;
  lHasMinute: Boolean;
  lHasSecond: Boolean;
  lHasMonth: Boolean;
  lHasDom: Boolean;
  lHasYear: Boolean;
  lTime: string;
  lYearSuffix: string;
  lValues: TWordArray;
  lStepStart: Word;
  lStep: Word;
  lStepFull: Boolean;
  lDomText: string;
begin
  lHasHour := Hour.TryGetSingleValue(lHour);
  lHasMinute := Minute.TryGetSingleValue(lMinute);
  lHasSecond := Second.TryGetSingleValue(lSecond);
  lHasMonth := Month.TryGetSingleValue(lMonth);
  lHasDom := Day_of_the_Month.TryGetSingleValue(lDom);
  lHasYear := Year.TryGetSingleValue(lYear);

  lYearSuffix := '';
  if lHasYear then
    lYearSuffix := ' in ' + IntToStr(lYear);

  if Second.TryGetStep(lStepStart, lStep, lStepFull) and (lStep > 0) and
    (Minute.IsAny) and (Hour.IsAny) and (Day_of_the_Month.IsAny) and (Month.IsAny) and
    (Day_of_the_Week.IsAny) and (Year.IsAny) then
  begin
    if lStep = 1 then
      Exit('Every second' + lYearSuffix);
    if lStepStart = 0 then
      Exit(Format('Every %d seconds%s', [lStep, lYearSuffix]));
    Exit(Format('Every %d seconds starting at %d%s', [lStep, lStepStart, lYearSuffix]));
  end;

  if Minute.TryGetStep(lStepStart, lStep, lStepFull) and (lStep > 0) and
    (Hour.IsAny) and (Day_of_the_Month.IsAny) and (Month.IsAny) and (Day_of_the_Week.IsAny) and
    (Year.IsAny) and lHasSecond then
  begin
    if lSecond = 0 then
    begin
      if lStep = 1 then
        Exit('Every minute' + lYearSuffix);
      if lStepStart = 0 then
        Exit(Format('Every %d minutes%s', [lStep, lYearSuffix]));
      Exit(Format('Every %d minutes starting at minute %d%s', [lStep, lStepStart, lYearSuffix]));
    end;
  end;

  if Hour.TryGetStep(lStepStart, lStep, lStepFull) and (lStep > 0) and
    (Day_of_the_Month.IsAny) and (Month.IsAny) and (Day_of_the_Week.IsAny) and (Year.IsAny) and
    lHasMinute and lHasSecond then
  begin
    if (lMinute = 0) and (lSecond = 0) then
    begin
      if lStep = 1 then
        Exit('Every hour' + lYearSuffix);
      if lStepStart = 0 then
        Exit(Format('Every %d hours%s', [lStep, lYearSuffix]));
      Exit(Format('Every %d hours starting at hour %d%s', [lStep, lStepStart, lYearSuffix]));
    end;
  end;

  lTime := '';
  if lHasHour and lHasMinute and lHasSecond then
  begin
    if lSecond = 0 then
      lTime := FormatTime(lHour, lMinute, lSecond, False)
    else
      lTime := FormatTime(lHour, lMinute, lSecond, True);
  end;

  if (lTime <> '') and (Day_of_the_Month.IsAny) and (Month.IsAny) and (Day_of_the_Week.IsAny) and (Year.IsAny) then
    Exit('Every day at ' + lTime + lYearSuffix);

  if (lTime <> '') and (Day_of_the_Month.IsAny) and (Month.IsAny) and (Year.IsAny) and
    (not Day_of_the_Week.IsAny) and (not Day_of_the_Week.HasSpecialTokens) then
  begin
    if Day_of_the_Week.GetValues(lValues) then
      Exit('Every week on ' + JoinValues(lValues, TPartKind.ckDayOfTheWeek) + ' at ' + lTime + lYearSuffix);
  end;

  if (lTime <> '') and (Month.IsAny) and (Year.IsAny) and (Day_of_the_Week.IsAny) then
  begin
    lDomText := Day_of_the_Month.DescribeDomSpecial;
    if lDomText <> '' then
      Exit('Every month on ' + lDomText + ' at ' + lTime + lYearSuffix);
    if lHasDom then
      Exit(Format('Every month on day %d at %s%s', [lDom, lTime, lYearSuffix]));
  end;

  if (lTime <> '') and lHasMonth and (Year.IsAny) and (Day_of_the_Week.IsAny) then
  begin
    lDomText := Day_of_the_Month.DescribeDomSpecial;
    if lDomText <> '' then
      Exit('Every year on ' + FormatMonthName(lMonth) + ' ' + lDomText + ' at ' + lTime + lYearSuffix);
    if lHasDom then
      Exit(Format('Every year on %s %d at %s%s', [FormatMonthName(lMonth), lDom, lTime, lYearSuffix]));
  end;

  Result := 'Custom schedule';
end;

function TCronSchedulePlan.PushDomDow(var NextDate: TDateTime): boolean;
var
  lMode: TmaxCronDayMatchMode;
  lDomOk: Boolean;
  lDowOk: Boolean;
  lDomCandidate: TDateTime;
  lDowCandidate: TDateTime;
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
  lDomOk := DomMatchesDate(NextDate);
  lDowOk := DowMatchesDate(NextDate);
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

function TCronSchedulePlan.DomMatchesDate(const aDate: TDateTime): Boolean;
var
  lDay: Word;
  lYear: Word;
  lMonth: Word;
  lTarget: Word;
begin
  if FDayOfTheMonth.Fullrange then
    Exit(True);
  if FDayOfTheMonth.fDomModifier <> TCronDomModifier.cdmNone then
  begin
    DecodeDate(aDate, lYear, lMonth, lDay);
    if not FDayOfTheMonth.TryGetDomSpecialDay(lYear, lMonth, lTarget) then
      Exit(False);
    Exit(lTarget = lDay);
  end;

  lDay := DayOf(aDate);
  Result := (FDayOfTheMonth.NextVal(lDay) = lDay);
end;

function TCronSchedulePlan.DowMatchesDate(const aDate: TDateTime): Boolean;
var
  lDow: Word;
  lYear: Word;
  lMonth: Word;
  lDay: Word;
  lTarget: Word;
begin
  if FDayOfTheWeek.Fullrange then
    Exit(True);
  if FDayOfTheWeek.fDowModifier <> TCronDowModifier.cdwNone then
  begin
    DecodeDate(aDate, lYear, lMonth, lDay);
    if not FDayOfTheWeek.TryGetDowSpecialDay(lYear, lMonth, lTarget) then
      Exit(False);
    Exit(lTarget = lDay);
  end;

  lDow := DayOfTheWeek(aDate) mod 7;
  Result := (FDayOfTheWeek.NextVal(lDow) = lDow);
end;

procedure TCronSchedulePlan.Parse(const CronPlan: string);
var
  plan: TPlan;
  pk: TPartKind;
  lText: string;
  lNum: Int64;
begin
  Clear;
  plan.Dialect := fDialect;
  plan.text := CronPlan;

  for pk := Low(TPartKind) to High(TPartKind) do
  begin
    parts[pk].fHashSeed := fHashSeed;
    parts[pk].Data := plan.parts[integer(pk)];
  end;

  fExecutionLimit := 0;
  lText := Trim(plan.ExecutionLimit);
  if (lText <> '') and (lText <> '*') then
  begin
    if not TryStrToInt64(lText, lNum) then
      raise Exception.Create('Invalid cron token');
    if (lNum < 0) or (lNum > High(LongWord)) then
      raise Exception.Create('Cron value out of range');
    fExecutionLimit := LongWord(lNum);
  end;
  fLastPlan := CronPlan;
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

procedure TCronSchedulePlan.ApplyDialectToParts;
begin
  if FDayOfTheWeek <> nil then
    FDayOfTheWeek.fDowOneBased := (fDialect = cdQuartzSecondsFirst);
end;

procedure TCronSchedulePlan.SetDialect(const Value: TmaxCronDialect);
begin
  if fDialect = Value then
    Exit;
  fDialect := Value;
  ApplyDialectToParts;
  if fLastPlan <> '' then
    Parse(fLastPlan);
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
  fNeedsParse := True;
  fNoSpec := False;
  fDomModifier := TCronDomModifier.cdmNone;
  fDomValue := 0;
  fDowModifier := TCronDowModifier.cdwNone;
  fDowValue := 0;
  fDowNth := 0;
end;

constructor TCronPart.Create;
begin
  inherited Create;
  FCount := 0;
  fRange := NIL;
  fPartKind := aPartKind;
  fNeedsParse := False;
  fDowOneBased := False;

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
        // Internal DOW range: 0 = Sunday, 1 = Monday, ... 6 = Saturday (Quartz 1..7 is normalized when dialect is set).
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

function TCronPart.HasSpecial: Boolean;
begin
  Result := (fDomModifier <> TCronDomModifier.cdmNone) or (fDowModifier <> TCronDowModifier.cdwNone);
end;

function TCronPart.NormalizeDowValue(const aValue: Integer): Integer;
begin
  if fPartKind <> ckDayOfTheWeek then
    Exit(aValue);
  if fDowOneBased then
  begin
    if aValue = 0 then
      Exit(-1);
    if (aValue >= 1) and (aValue <= 7) then
    begin
      if aValue = 7 then
        Exit(6);
      Exit(aValue - 1);
    end;
    Exit(aValue);
  end;
  if aValue = 7 then
    Exit(0);
  Result := aValue;
end;

function TCronPart.Hash32(const aValue: string): Cardinal;
var
  lIndex: Integer;
  lHash: Cardinal;
begin
  lHash := 2166136261;
  for lIndex := 1 to Length(aValue) do
  begin
    lHash := lHash xor Ord(aValue[lIndex]);
    lHash := lHash * 16777619;
  end;
  Result := lHash;
end;

function TCronPart.TryParseHashedToken(const aValue: string): Boolean;
var
  lText: string;
  lRangeFrom: Integer;
  lRangeTo: Integer;
  lStep: Integer;
  lSlashPos: Integer;
  lOpenPos: Integer;
  lClosePos: Integer;
  lRangeText: string;
  lDashPos: Integer;
  lHashValue: Cardinal;
  lStart: Integer;
  lValue: Integer;
  lSeed: string;
  lHasExplicitRange: Boolean;
begin
  Result := False;
  lText := Trim(aValue);
  if lText = '' then
    Exit(False);
  if UpCase(lText[1]) <> 'H' then
    Exit(False);

  lRangeFrom := FValidFrom;
  lRangeTo := FValidTo;
  lStep := 0;
  lHasExplicitRange := False;

  lOpenPos := Pos('(', lText);
  lClosePos := Pos(')', lText);
  if (lOpenPos > 0) or (lClosePos > 0) then
  begin
    if (lOpenPos <> 2) or (lClosePos <= lOpenPos + 1) then
      raise Exception.Create('Invalid cron token');
    lRangeText := Copy(lText, lOpenPos + 1, lClosePos - lOpenPos - 1);
    lDashPos := Pos('-', lRangeText);
    if lDashPos <= 1 then
      raise Exception.Create('Invalid cron token');
    lRangeFrom := StrToInt(Copy(lRangeText, 1, lDashPos - 1));
    lRangeTo := StrToInt(Copy(lRangeText, lDashPos + 1, MaxInt));
    lHasExplicitRange := True;
    Delete(lText, lOpenPos, lClosePos - lOpenPos + 1);
  end;

  lSlashPos := Pos('/', lText);
  if lSlashPos > 0 then
  begin
    lStep := StrToInt(Copy(lText, lSlashPos + 1, MaxInt));
    if lStep <= 0 then
      raise Exception.Create('Invalid cron step');
    lText := Copy(lText, 1, lSlashPos - 1);
  end;

  if (lText <> 'H') and (lText <> 'h') then
    raise Exception.Create('Invalid cron token');

  if (fPartKind = ckDayOfTheWeek) and fDowOneBased then
  begin
    if not lHasExplicitRange then
    begin
      lRangeFrom := 1;
      lRangeTo := 7;
    end;

    if (lRangeFrom < 1) or (lRangeFrom > 7) then
      raise Exception.Create('Cron value out of range');
    if (lRangeTo < 1) or (lRangeTo > 7) or (lRangeTo < lRangeFrom) then
      raise Exception.Create('Cron value out of range');

    lRangeFrom := NormalizeDowValue(lRangeFrom);
    lRangeTo := NormalizeDowValue(lRangeTo);
  end else begin
    if (lRangeFrom < FValidFrom) or (lRangeFrom > FValidTo) then
      raise Exception.Create('Cron value out of range');
    if (lRangeTo < FValidFrom) or (lRangeTo > FValidTo) or (lRangeTo < lRangeFrom) then
      raise Exception.Create('Cron value out of range');
  end;

  lSeed := fHashSeed + '|' + IntToStr(Ord(fPartKind)) + '|' + aValue;
  lHashValue := Hash32(lSeed);
  lStart := lRangeFrom + Integer(lHashValue mod Cardinal(lRangeTo - lRangeFrom + 1));

  if lStep = 0 then
    Add2Range(lStart)
  else
  begin
    lValue := lStart;
    while lValue <= lRangeTo do
    begin
      Add2Range(lValue);
      Inc(lValue, lStep);
    end;
  end;

  Result := True;
end;

function TCronPart.TryParseSpecialToken(const aToken: string): Boolean;
var
  s: string;
begin
  Result := False;
  if not (fPartKind in [ckDayOfTheMonth, ckDayOfTheWeek]) then
    Exit(False);

  s := Trim(aToken);
  if s = '' then
    Exit(False);

  if s = '?' then
  begin
    fNoSpec := True;
    fFullrange := True;
    fRange := NIL;
    FCount := 0;
    Exit(True);
  end;

  if fPartKind = ckDayOfTheMonth then
    Result := TryParseDomSpecial(s)
  else
    Result := TryParseDowSpecial(s);
end;

function TCronPart.TryParseDomSpecial(const aToken: string): Boolean;
var
  s: string;
  lNum: Integer;
begin
  Result := False;
  s := UpperCase(Trim(aToken));

  if (Pos('L', s) = 0) and (Pos('W', s) = 0) then
    Exit(False);

  if (Pos('#', s) > 0) or (Pos('/', s) > 0) or (Pos('-', s) > 0) then
    raise Exception.Create('Invalid cron token');

  if s = 'L' then
  begin
    fDomModifier := TCronDomModifier.cdmLastDay;
    Exit(True);
  end;

  if s = 'LW' then
  begin
    fDomModifier := TCronDomModifier.cdmLastWeekday;
    Exit(True);
  end;

  if s[Length(s)] = 'W' then
  begin
    lNum := StrToIntDef(Copy(s, 1, Length(s) - 1), -1);
    if (lNum < FValidFrom) or (lNum > FValidTo) then
      raise Exception.Create('Cron value out of range');
    fDomModifier := TCronDomModifier.cdmNearestWeekday;
    fDomValue := lNum;
    Exit(True);
  end;

  raise Exception.Create('Invalid cron token');
end;

function TCronPart.TryParseDowSpecial(const aToken: string): Boolean;
var
  s: string;
  lHashPos: Integer;
  lLeft: string;
  lRight: string;
  lNum: Integer;
  lNth: Integer;
begin
  Result := False;
  s := ReplaceDaynames(Trim(aToken));
  s := UpperCase(s);

  if Pos('W', s) > 0 then
    raise Exception.Create('Invalid cron token');

  lHashPos := Pos('#', s);
  if lHashPos > 0 then
  begin
    if (Pos('L', s) > 0) or (Pos('/', s) > 0) or (Pos('-', s) > 0) then
      raise Exception.Create('Invalid cron token');
    lLeft := Copy(s, 1, lHashPos - 1);
    lRight := Copy(s, lHashPos + 1, MaxInt);
    if (lLeft = '') or (lRight = '') then
      raise Exception.Create('Invalid cron token');
    lNum := StrToIntDef(lLeft, -1);
    lNum := NormalizeDowValue(lNum);
    if (lNum < FValidFrom) or (lNum > FValidTo) then
      raise Exception.Create('Cron value out of range');
    lNth := StrToIntDef(lRight, 0);
    if (lNth < 1) or (lNth > 5) then
      raise Exception.Create('Invalid cron token');
    fDowModifier := TCronDowModifier.cdwNthWeekday;
    fDowValue := lNum;
    fDowNth := lNth;
    Exit(True);
  end;

  if (Length(s) > 1) and (s[Length(s)] = 'L') then
  begin
    if (Pos('/', s) > 0) or (Pos('-', s) > 0) then
      raise Exception.Create('Invalid cron token');
    lLeft := Copy(s, 1, Length(s) - 1);
    lNum := StrToIntDef(lLeft, -1);
    lNum := NormalizeDowValue(lNum);
    if (lNum < FValidFrom) or (lNum > FValidTo) then
      raise Exception.Create('Cron value out of range');
    fDowModifier := TCronDowModifier.cdwLastWeekday;
    fDowValue := lNum;
    Exit(True);
  end;

  if s = 'L' then
    raise Exception.Create('Invalid cron token');
end;

function TCronPart.GetLastDayOfMonth(const aYear, aMonth: Word): Word;
begin
  Result := DaysInMonth(EncodeDate(aYear, aMonth, 1));
end;

function TCronPart.GetLastWeekdayOfMonth(const aYear, aMonth: Word; out aDay: Word): Boolean;
var
  lLastDay: Word;
  lDow: Word;
begin
  lLastDay := GetLastDayOfMonth(aYear, aMonth);
  lDow := DayOfTheWeek(EncodeDate(aYear, aMonth, lLastDay)) mod 7;
  case lDow of
    0:
      aDay := lLastDay - 2; // Sunday -> Friday
    6:
      aDay := lLastDay - 1; // Saturday -> Friday
  else
    aDay := lLastDay;
  end;
  Result := aDay >= 1;
end;

function TCronPart.GetNearestWeekdayTo(const aYear, aMonth, aDay: Word; out aNearestDay: Word): Boolean;
var
  lLastDay: Word;
  lDow: Word;
begin
  lLastDay := GetLastDayOfMonth(aYear, aMonth);
  if (aDay < 1) or (aDay > lLastDay) then
    Exit(False);

  lDow := DayOfTheWeek(EncodeDate(aYear, aMonth, aDay)) mod 7;
  case lDow of
    0:
      if aDay = lLastDay then
        aNearestDay := aDay - 2
      else
        aNearestDay := aDay + 1;
    6:
      if aDay = 1 then
        aNearestDay := aDay + 2
      else
        aNearestDay := aDay - 1;
  else
    aNearestDay := aDay;
  end;

  Result := (aNearestDay >= 1) and (aNearestDay <= lLastDay);
end;

function TCronPart.GetNthWeekdayOfMonth(const aYear, aMonth, aDow, aNth: Word; out aDay: Word): Boolean;
var
  lFirstDow: Word;
  lDelta: Integer;
  lDay: Integer;
  lLastDay: Word;
begin
  lLastDay := GetLastDayOfMonth(aYear, aMonth);
  lFirstDow := DayOfTheWeek(EncodeDate(aYear, aMonth, 1)) mod 7;
  lDelta := (7 + aDow - lFirstDow) mod 7;
  lDay := 1 + lDelta + (Integer(aNth) - 1) * 7;
  if lDay > lLastDay then
    Exit(False);
  aDay := lDay;
  Result := True;
end;

function TCronPart.GetLastDowOfMonth(const aYear, aMonth, aDow: Word; out aDay: Word): Boolean;
var
  lLastDay: Word;
  lLastDow: Word;
  lDelta: Integer;
begin
  lLastDay := GetLastDayOfMonth(aYear, aMonth);
  lLastDow := DayOfTheWeek(EncodeDate(aYear, aMonth, lLastDay)) mod 7;
  lDelta := (7 + lLastDow - aDow) mod 7;
  aDay := lLastDay - lDelta;
  Result := aDay >= 1;
end;

function TCronPart.TryGetDomSpecialDay(const aYear, aMonth: Word; out aDay: Word): Boolean;
begin
  Result := False;
  case fDomModifier of
    TCronDomModifier.cdmLastDay:
      begin
        aDay := GetLastDayOfMonth(aYear, aMonth);
        Result := True;
      end;
    TCronDomModifier.cdmLastWeekday:
      Result := GetLastWeekdayOfMonth(aYear, aMonth, aDay);
    TCronDomModifier.cdmNearestWeekday:
      Result := GetNearestWeekdayTo(aYear, aMonth, fDomValue, aDay);
  end;
end;

function TCronPart.TryGetDowSpecialDay(const aYear, aMonth: Word; out aDay: Word): Boolean;
begin
  Result := False;
  case fDowModifier of
    TCronDowModifier.cdwLastWeekday:
      Result := GetLastDowOfMonth(aYear, aMonth, fDowValue, aDay);
    TCronDowModifier.cdwNthWeekday:
      Result := GetNthWeekdayOfMonth(aYear, aMonth, fDowValue, fDowNth, aDay);
  end;
end;

function TCronPart.GetFullrange: boolean;
begin
  if fNoSpec then
    Exit(True);
  if HasSpecial then
    Exit(False);
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

function TCronPart.IsAny: Boolean;
begin
  Result := Fullrange or fNoSpec;
end;

function TCronPart.IsNoSpec: Boolean;
begin
  Result := fNoSpec;
end;

function TCronPart.HasSpecialTokens: Boolean;
begin
  Result := HasSpecial;
end;

function TCronPart.TryGetSingleValue(out aValue: Word): Boolean;
begin
  if fNoSpec then
    Exit(False);
  if HasSpecial then
    Exit(False);
  if (not fFullrange) and (FCount = 1) then
  begin
    aValue := fRange[0];
    Exit(True);
  end;
  Result := False;
end;

function TCronPart.TryGetStep(out aStart, aStep: Word; out aCoversFullRange: Boolean): Boolean;
var
  i: Integer;
  lStep: Integer;
begin
  aStart := 0;
  aStep := 0;
  aCoversFullRange := False;

  if fNoSpec then
    Exit(False);
  if HasSpecial then
    Exit(False);

  if fFullrange then
  begin
    aStart := FValidFrom;
    aStep := 1;
    aCoversFullRange := True;
    Exit(True);
  end;

  if FCount = 0 then
    Exit(False);

  aStart := fRange[0];
  if FCount = 1 then
  begin
    aStep := 0;
    Exit(True);
  end;

  lStep := fRange[1] - fRange[0];
  if lStep <= 0 then
    Exit(False);

  for i := 2 to FCount - 1 do
    if (fRange[i] - fRange[i - 1]) <> lStep then
      Exit(False);

  aStep := lStep;
  if (aStart = FValidFrom) and (fRange[FCount - 1] = FValidTo) then
    aCoversFullRange := ((FValidTo - FValidFrom) div aStep + 1) = FCount;

  Result := True;
end;

function TCronPart.GetValues(out aValues: TWordArray): Boolean;
begin
  SetLength(aValues, 0);
  if fNoSpec then
    Exit(False);
  if HasSpecial then
    Exit(False);
  if fFullrange then
    Exit(False);
  if FCount = 0 then
    Exit(False);

  SetLength(aValues, FCount);
  if FCount > 0 then
    Move(fRange[0], aValues[0], SizeOf(fRange[0]) * FCount);
  Result := True;
end;

function TCronPart.DescribeDomSpecial: string;
begin
  case fDomModifier of
    TCronDomModifier.cdmLastDay:
      Result := 'the last day';
    TCronDomModifier.cdmLastWeekday:
      Result := 'the last weekday';
    TCronDomModifier.cdmNearestWeekday:
      Result := Format('the nearest weekday to %d', [fDomValue]);
  else
    Result := '';
  end;
end;

procedure TCronPart.Parse;
var
  x: integer;
  l: TStringList;
  lToken: string;
  lHasSpecial: Boolean;
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
  end
  else
  begin
    if (Length(FData) > 0) and ((FData[1] = ',') or (FData[Length(FData)] = ',') or (Pos(',,', FData) > 0)) then
      raise Exception.Create('Invalid cron token');

    l := TStringList.Create;
    try
      SplitString(FData, ',', l);
      if l.Count > 1 then
        for x := 0 to l.Count - 1 do
          if Trim(l[x]) = '*' then
            raise Exception.Create('Invalid cron token');
      lHasSpecial := False;
      for x := 0 to l.Count - 1 do
      begin
        lToken := Trim(l[x]);
        if lToken = '' then
          raise Exception.Create('Invalid cron token');
        if TryParseSpecialToken(lToken) then
        begin
          if (l.Count > 1) or lHasSpecial then
            raise Exception.Create('Invalid cron token');
          lHasSpecial := True;
        end;
      end;

      if lHasSpecial then
        Exit;

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
  iSlash: Integer;
  lIsStar: Boolean;

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
  if TryParseHashedToken(s) then
    Exit;
  if Pos('?', s) > 0 then
    raise Exception.Create('Invalid cron token');
  case fPartKind of
    ckMonth:
      s := ReplaceMonthNames(s);
    ckDayOfTheWeek:
      s := ReplaceDaynames(s);
  end;

  iSlash := Pos('/', s);
  if iSlash > 0 then
  begin
    Repeater := StrToInt(Copy(s, iSlash + 1, MaxInt));
    if Repeater <= 0 then
      raise Exception.Create('Invalid cron step');
    s := Copy(s, 1, iSlash - 1);
  end else
    Repeater := 1;

  iR := Pos('-', s);
  lIsStar := (s = '*');
  if lIsStar then
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
    if iSlash > 0 then
    begin
      if (fPartKind = ckDayOfTheWeek) and fDowOneBased then
        RangeTo := 7
      else
        RangeTo := FValidTo; // n/k => n..max
    end
    else
      RangeTo := RangeFrom;
  end;

  if not (lIsStar and (fPartKind = ckDayOfTheWeek) and fDowOneBased) then
  begin
    RangeFrom := NormalizeDowValue(RangeFrom);
    RangeTo := NormalizeDowValue(RangeTo);
  end;

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
  lYear, lMonth, lDay: Word;
  lTarget: Word;
begin
  Result := True;
  if fNoSpec then
    Exit(True);

  if fDomModifier <> TCronDomModifier.cdmNone then
  begin
    DecodeDate(NextDate, lYear, lMonth, lDay);
    if not TryGetDomSpecialDay(lYear, lMonth, lTarget) then
    begin
      NextDate := EncodeDateTime(lYear, lMonth, 1, 0, 0, 0, 0);
      NextDate := IncMonth(NextDate);
      Result := False;
      Exit;
    end;

    if lTarget < lDay then
    begin
      NextDate := EncodeDateTime(lYear, lMonth, 1, 0, 0, 0, 0);
      NextDate := IncMonth(NextDate);
      Result := False;
      Exit;
    end;

    if lTarget > lDay then
      NextDate := EncodeDateTime(lYear, lMonth, lTarget, 0, 0, 0, 0);
    Exit;
  end;

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
      dc := DaysInMonth(NextDate);
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
  lYear, lMonth, lDay: Word;
  lTarget: Word;
begin
  Result := True;
  if fNoSpec then
    Exit(True);

  if fDowModifier <> TCronDowModifier.cdwNone then
  begin
    DecodeDate(NextDate, lYear, lMonth, lDay);
    if not TryGetDowSpecialDay(lYear, lMonth, lTarget) then
    begin
      NextDate := EncodeDateTime(lYear, lMonth, 1, 0, 0, 0, 0);
      NextDate := IncMonth(NextDate);
      Result := False;
      Exit;
    end;

    if lTarget < lDay then
    begin
      NextDate := EncodeDateTime(lYear, lMonth, 1, 0, 0, 0, 0);
      NextDate := IncMonth(NextDate);
      Result := False;
      Exit;
    end;

    if lTarget > lDay then
    begin
      Result := False;
      NextDate := EncodeDateTime(lYear, lMonth, lTarget, 0, 0, 0, 0);
      Exit;
    end;

    Exit(True);
  end;

  if not Fullrange then
  begin
    // Internal DOW: 0 = Sunday, 1 = Monday, ... 6 = Saturday.
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
    if fDowOneBased then
    begin
      // Quartz-compatible: Sun = 1, Mon = 2, ... Sat = 7
      if x = 7 then
        s := StringReplace(s, DayNames[x], '1', [rfReplaceAll, rfIgnorecase])
      else
        s := StringReplace(s, DayNames[x], IntToStr(x + 1), [rfReplaceAll, rfIgnorecase]);
    end else
    begin
      // Cron-compatible: Sun = 0 (also accept 7 as Sunday numerically in ParsePart)
      if x = 7 then
        s := StringReplace(s, DayNames[x], '0', [rfReplaceAll, rfIgnorecase])
      else
        s := StringReplace(s, DayNames[x], IntToStr(x), [rfReplaceAll, rfIgnorecase]);
    end;
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
  if (FData <> Value) or fNeedsParse then
  begin
    FData := Value;
    Parse;
    fNeedsParse := False;
  end;
end;

{ TScheduledEvent }

constructor TmaxCronEvent.Create;
begin
  inherited;
  fLock := TCriticalSection.Create;
  fEventToken := TCronEventToken.Create(Self);
  fId := 0;
  fInvokeMode := TmaxCronInvokeMode.imDefault;
  fOverlapMode := TmaxCronOverlapMode.omAllowOverlap;
  fDayMatchMode := TmaxCronDayMatchMode.dmDefault;
  fDialect := cdMaxCron;
  fMisfirePolicy := TmaxCronMisfirePolicy.mpDefault;
  fTimeZoneId := 'LOCAL';
  fTimeZoneKind := TCronTimeZoneKind.ctzLocal;
  fTimeZoneOffsetMinutes := 0;
  fDstSpringPolicy := TmaxCronDstSpringPolicy.dspSkip;
  fDstFallPolicy := TmaxCronDstFallPolicy.dfpRunOnce;
  fWeekdaysOnly := False;
  fExcludedDatesCsv := '';
  SetLength(fExcludedDateSerials, 0);
  fBlackoutStartTime := 0;
  fBlackoutEndTime := 0;
  fPendingDstSecondSchedule := 0;
  fNextScheduleNeedsResolve := False;
  fRunning := 0;
  fPendingRuns := 0;
  fExecDepth := 0;
  fAllowDisabledDispatch := 0;
  fPendingDestroy := False;
  fAmbiguousSecondGateActive := False;
  fAmbiguousSecondGatePassedTarget := False;
  fAmbiguousSecondGateRollbackSeen := False;
  FValidFrom := 0;
  FValidTo := 0;
  fScheduler := TCronSchedulePlan.Create;
  fScheduler.Dialect := fDialect;
  fScheduler.HashSeed := '';
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

function TmaxCronEvent.AsEventObject: TmaxCronEvent;
begin
  Result := Self;
end;

procedure TmaxCronEvent.ResetSchedule;
var
  lBase: TDateTime;
  lFindResult: TFindNextScheduleResult;
begin
  fPendingDstSecondSchedule := 0;
  ClearAmbiguousSecondGate;

  if fLastExecutionTime = 0 then
    lBase := now
  else
    lBase := fLastExecutionTime;

  lFindResult := FindNextScheduleWithPolicies(lBase, fNextSchedule);
  case lFindResult of
    TFindNextScheduleResult.fnsFound:
      fNextScheduleNeedsResolve := False;
    TFindNextScheduleResult.fnsNotFound:
      begin
        fNextScheduleNeedsResolve := False;
        FEnabled := False;
      end;
    TFindNextScheduleResult.fnsSearchLimitReached:
      fNextScheduleNeedsResolve := True;
  end;

  if fSharedState <> nil then
    fSharedState.MarkHeapDirty;
end;

function TmaxCronEvent.Run: IMaxCronEvent;
begin
  Result := self;

  fLock.Acquire;
  try
    FEnabled := True;
    fNumOfExecutions := 0;
    fNumOfDue := 0;
    fLastExecutionTime := 0;
    ResetSchedule;
  finally
    fLock.Release;
  end;
end;

procedure TmaxCronEvent.SetEnabled(const Value: boolean);
var
  lChanged: Boolean;
begin
  lChanged := False;
  fLock.Acquire;
  try
    if FEnabled = Value then Exit;
    lChanged := True;
    if Value then
    begin
      FEnabled := True;
      fNumOfExecutions := 0;
      fNumOfDue := 0;
      fLastExecutionTime := 0;
      ResetSchedule;
    end else begin
      FEnabled := False;
    end;
  finally
    fLock.Release;
  end;

  if lChanged and (fSharedState <> nil) then
    fSharedState.MarkHeapDirty;
end;

procedure TmaxCronEvent.SetEventPlan(const Value: string);
var
  lValidator: TCronSchedulePlan;
begin
  fLock.Acquire;
  try
    if FEventPlan <> Value then
    begin
      lValidator := TCronSchedulePlan.Create;
      try
        lValidator.Dialect := fDialect;
        lValidator.HashSeed := GetHashSeed;
        lValidator.Parse(Value);
      finally
        lValidator.Free;
      end;

      if fScheduler.Dialect <> fDialect then
        fScheduler.Dialect := fDialect;
      fScheduler.HashSeed := GetHashSeed;
      fScheduler.Parse(Value);
      FEventPlan := Value;
      ResetSchedule;
    end;
  finally
    fLock.Release;
  end;
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
    fNumOfDue := Value;
    if fScheduler.ExecutionLimit <> 0 then
      if fNumOfDue >= fScheduler.ExecutionLimit then
      begin
        FEnabled := False;
        TInterlocked.Exchange(fPendingRuns, 0);
      end;
  finally
    fLock.Release;
  end;
end;

procedure TmaxCronEvent.SetTag(const Value: integer);
begin
  fLock.Acquire;
  try
    FTag := Value;
  finally
    fLock.Release;
  end;
end;

procedure TmaxCronEvent.SetUserData(const Value: Pointer);
begin
  fLock.Acquire;
  try
    FUserData := Value;
  finally
    fLock.Release;
  end;
end;

procedure TmaxCronEvent.SetUserDataInterface(const Value: iInterface);
begin
  fLock.Acquire;
  try
    FUserDataInterface := Value;
  finally
    fLock.Release;
  end;
end;

procedure TmaxCronEvent.SetValidFrom(const Value: TDateTime);
begin
  fLock.Acquire;
  try
    FValidFrom := Value;
    if FEnabled then
      ResetSchedule;
  finally
    fLock.Release;
  end;
end;

procedure TmaxCronEvent.SetValidTo(const Value: TDateTime);
begin
  fLock.Acquire;
  try
    FValidTo := Value;
    if FEnabled then
      ResetSchedule;
  finally
    fLock.Release;
  end;
end;

procedure TmaxCronEvent.Stop;
begin
  fLock.Acquire;
  try
    FEnabled := False;
  finally
    fLock.Release;
  end;

  if fSharedState <> nil then
    fSharedState.MarkHeapDirty;
end;

{ TSchEventList }

function TmaxCron.Add(const aName: string): IMaxCronEvent;
var
  lEvent: TmaxCronEvent;
  lEventInterface: IMaxCronEvent;
  lSharedState: ICronSharedState;
  lNormalizedName: string;
begin
  lNormalizedName := NormalizeEventName(aName);
  Result := nil;

  fItemsLock.Acquire;
  try
    if (lNormalizedName <> '') and (FindIndexByNameLocked(lNormalizedName) >= 0) then
      raise Exception.CreateFmt('Event name "%s" already exists', [lNormalizedName]);

    lEvent := TmaxCronEvent.Create;
    lEventInterface := lEvent as IMaxCronEvent;
    if Supports(fSharedState, ICronSharedState, lSharedState) then
      lEvent.fSharedState := lSharedState;
    lEvent.fScheduler.DayMatchMode := fDefaultDayMatchMode;
    lEvent.fDialect := fDefaultDialect;
    lEvent.fScheduler.Dialect := fDefaultDialect;
    lEvent.fId := TInterlocked.Increment(fNextId);
    lEvent.FName := lNormalizedName;
    lEvent.fScheduler.HashSeed := lEvent.GetHashSeed;
    fItems.Add(lEventInterface);
    try
      IndexEventLocked(lEventInterface, fItems.Count - 1);
    except
      fItems.Delete(fItems.Count - 1);
      raise;
    end;
    MarkHeapDirty;
    Result := lEventInterface;
  finally
    fItemsLock.Release;
  end;
end;

procedure TmaxCron.Clear;
var
  lEvent: TmaxCronEvent;
  lEventItem: IMaxCronEvent;
begin
  fItemsLock.Acquire;
  try
    Inc(fTickDepth);
    try
      while fItems.Count > 0 do
      begin
        lEventItem := fItems[0];
        if TryGetCronEvent(lEventItem, lEvent) then
          lEvent.MarkPendingDestroy;
        RemoveEventIndexLocked(lEventItem);
        fPendingFree.Add(fItems.Extract(lEventItem));
      end;
      fItemsById.Clear;
      fItemsByName.Clear;
      MarkHeapDirty;
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

constructor TCronSharedState.Create(const aOwner: TmaxCron);
begin
  inherited Create;
  fLock := TCriticalSection.Create;
  fOwner := aOwner;
  fInFlight := 0;
  fCallbackDepth := 0;
end;

destructor TCronSharedState.Destroy;
begin
  fLock.Free;
  inherited;
end;

function TCronSharedState.TryAcquireOwner(out aOwner: TmaxCron): Boolean;
begin
  fLock.Acquire;
  try
    aOwner := fOwner;
    Result := (aOwner <> nil);
    if Result then
      Inc(fInFlight);
  finally
    fLock.Release;
  end;
end;

procedure TCronSharedState.ReleaseOwner;
begin
  fLock.Acquire;
  try
    if fInFlight > 0 then
      Dec(fInFlight);
  finally
    fLock.Release;
  end;
end;

procedure TCronSharedState.Detach;
begin
  fLock.Acquire;
  try
    fOwner := nil;
  finally
    fLock.Release;
  end;
end;

function TCronSharedState.IsAlive: Boolean;
begin
  fLock.Acquire;
  try
    Result := (fOwner <> nil);
  finally
    fLock.Release;
  end;
end;

function TCronSharedState.TryGetDefaultInvokeMode(out aInvokeMode: TmaxCronInvokeMode): Boolean;
var
  lOwner: TmaxCron;
begin
  Result := False;
  aInvokeMode := TmaxCronInvokeMode.imMainThread;
  if not TryAcquireOwner(lOwner) then
    Exit(False);
  try
    aInvokeMode := lOwner.fDefaultInvokeMode;
    Result := True;
  finally
    ReleaseOwner;
  end;
end;

function TCronSharedState.TryGetDefaultDayMatchMode(out aDayMatchMode: TmaxCronDayMatchMode): Boolean;
var
  lOwner: TmaxCron;
begin
  Result := False;
  aDayMatchMode := TmaxCronDayMatchMode.dmAnd;
  if not TryAcquireOwner(lOwner) then
    Exit(False);
  try
    aDayMatchMode := lOwner.fDefaultDayMatchMode;
    Result := True;
  finally
    ReleaseOwner;
  end;
end;

function TCronSharedState.TryGetMisfireDefaults(out aMisfirePolicy: TmaxCronMisfirePolicy;
  out aCatchUpLimit: Cardinal): Boolean;
var
  lOwner: TmaxCron;
begin
  Result := False;
  aMisfirePolicy := TmaxCronMisfirePolicy.mpCatchUpAll;
  aCatchUpLimit := 1;
  if not TryAcquireOwner(lOwner) then
    Exit(False);
  try
    aMisfirePolicy := lOwner.fDefaultMisfirePolicy;
    aCatchUpLimit := lOwner.fDefaultMisfireCatchUpLimit;
    Result := True;
  finally
    ReleaseOwner;
  end;
end;

function TCronSharedState.TryGetOwnerPointer(out aOwnerPointer: Pointer): Boolean;
var
  lOwner: TmaxCron;
begin
  Result := False;
  aOwnerPointer := nil;
  if not TryAcquireOwner(lOwner) then
    Exit(False);
  try
    aOwnerPointer := Pointer(lOwner);
    Result := True;
  finally
    ReleaseOwner;
  end;
end;

function TCronSharedState.GetInFlightCount: Integer;
begin
  fLock.Acquire;
  try
    Result := fInFlight;
  finally
    fLock.Release;
  end;
end;

procedure TCronSharedState.IncrementCallbackDepth;
begin
  TInterlocked.Increment(fCallbackDepth);
end;

procedure TCronSharedState.DecrementCallbackDepth;
begin
  TInterlocked.Decrement(fCallbackDepth);
end;

function TCronSharedState.GetCallbackDepth: Integer;
begin
  Result := TInterlocked.CompareExchange(fCallbackDepth, 0, 0);
end;

procedure TCronSharedState.MarkHeapDirty;
var
  lOwner: TmaxCron;
begin
  if not TryAcquireOwner(lOwner) then
    Exit;
  try
    lOwner.MarkHeapDirty;
  finally
    ReleaseOwner;
  end;
end;

procedure TCronSharedState.KeepAsyncAlive(const aAsync: IInterface);
var
  lOwner: TmaxCron;
begin
  if aAsync = nil then
    Exit;
  if not TryAcquireOwner(lOwner) then
    Exit;
  try
    lOwner.KeepAsyncAlive(aAsync);
  finally
    ReleaseOwner;
  end;
end;

procedure TCronSharedState.ReleaseAsyncAlive(const aAsync: IInterface);
var
  lOwner: TmaxCron;
begin
  if aAsync = nil then
    Exit;
  if not TryAcquireOwner(lOwner) then
    Exit;
  try
    lOwner.ReleaseAsyncAlive(aAsync);
  finally
    ReleaseOwner;
  end;
end;

procedure TCronSharedState.FlushPendingFree;
var
  lOwner: TmaxCron;
begin
  if not TryAcquireOwner(lOwner) then
    Exit;
  try
    lOwner.FlushPendingFree;
  finally
    ReleaseOwner;
  end;
end;

procedure TCronSharedState.ExecuteQueuedTick;
var
  lOwner: TmaxCron;
begin
  if not TryAcquireOwner(lOwner) then
    Exit;
  try
    try
      lOwner.DoTick;
    finally
      TInterlocked.Exchange(lOwner.fTickQueued, 0);
    end;
  finally
    ReleaseOwner;
  end;
end;

procedure TCronSharedState.ResetTickQueued;
var
  lOwner: TmaxCron;
begin
  if not TryAcquireOwner(lOwner) then
    Exit;
  try
    TInterlocked.Exchange(lOwner.fTickQueued, 0);
  finally
    ReleaseOwner;
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

function TCronEventToken.TryAcquireEvent(out aEvent: TmaxCronEvent): Boolean;
begin
  fLock.Acquire;
  try
    aEvent := fEvent;
    if aEvent = nil then
      Exit(False);

    Result := aEvent.TryAcquireExecution;
    if not Result then
      aEvent := nil;
  finally
    fLock.Release;
  end;
end;

constructor TAsyncKeepAliveEntry.Create(const aSharedState: ICronSharedState);
begin
  inherited Create;
  fLock := TCriticalSection.Create;
  fSharedState := aSharedState;
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
begin
  fLock.Acquire;
  try
    fAsync := aAsync;
    lDone := fDone;
  finally
    fLock.Release;
  end;

  if lDone and (fSharedState <> nil) then
  begin
    fSharedState.ReleaseAsyncAlive(Self);
    fLock.Acquire;
    try
      fAsync := nil;
    finally
      fLock.Release;
    end;
  end;
end;

procedure TAsyncKeepAliveEntry.MarkDone;
begin
  fLock.Acquire;
  try
    fDone := True;
    fAsync := nil; // break keep-alive cycle before we release
  finally
    fLock.Release;
  end;

  if fSharedState <> nil then
    fSharedState.ReleaseAsyncAlive(Self);
end;

constructor TmaxCron.Create(const aTimerBackend: TmaxCronTimerBackend);
begin
  inherited Create;

  fItems := TList<IMaxCronEvent>.Create;
  fItemsById := TDictionary<Int64, Integer>.Create;
  fItemsByName := TDictionary<string, Integer>.Create;
  fHeapItems := TList<TCronHeapEntry>.Create;
  fAutoSwitchHistory := TQueue<UInt64>.Create;
  fAutoLock := TCriticalSection.Create;
  fItemsLock := TCriticalSection.Create;
  fPendingFree := TList<IMaxCronEvent>.Create;
  fNextId := 0;
  fTickDepth := 0;
  fDefaultInvokeMode := TmaxCronInvokeMode.imMainThread;
  fDefaultDayMatchMode := TmaxCronDayMatchMode.dmAnd;
  fDefaultDialect := cdMaxCron;
  fDefaultMisfirePolicy := TmaxCronMisfirePolicy.mpCatchUpAll;
  fDefaultMisfireCatchUpLimit := 1;
  fAsyncLock := TCriticalSection.Create;
  fAsyncKeepAlive := TList<IInterface>.Create;
  fTickQueued := 0;
  fHeapDirty := 0;
  fAutoEffectiveEngine := TSchedulerEngine.seScan;
  fAutoState := TAutoSchedulerState.asDisabled;
  fAutoMutationCounter := 0;
  fAutoMutationCursor := 0;
  fAutoEnterHold := 0;
  fAutoExitHold := 0;
  fAutoTrialTicksRemaining := 0;
  fAutoCooldownTicks := 0;
  fAutoTrialFailLevel := 0;
  fAutoTrialFailCooldownTicks := 0;
  fAutoSwitchBudgetHits := 0;
  fAutoControllerTick := 0;
  fAutoSwitchBudgetUntilTick := 0;
  fAutoSwitchCount := 0;
  fAutoEventCountEwma := 0;
  fAutoDueDensityEwma := 0;
  fAutoDirtyRateEwma := 0;
  fAutoScanTickUsEwma := 0;
  fAutoHeapTickUsEwma := 0;
  fAutoScanBaselineUs := 0;
  fAutoScanSampleTicks := 0;
  fAutoHeapSampleTicks := 0;
  fAutoTicksSinceSwitch := 0;
  fAutoSwitchBurstLevel := 0;
  fAutoLastSwitchReason := '';
  fAutoDiagLogTicksUntilEmit := 0;
  fTickEventsVisited := 0;
  fHeapRebuildCount := 0;
  ConfigureSchedulerEngine;
  fSharedState := TCronSharedState.Create(Self);
  CreateTimer(aTimerBackend);
end;

function TmaxCron.ClampAutoInt(const aValue, aMin, aMax: Integer): Integer;
begin
  if aValue < aMin then
    Exit(aMin);
  if aValue > aMax then
    Exit(aMax);
  Result := aValue;
end;

function TmaxCron.ClampAutoFloat(const aValue, aMin, aMax: Double): Double;
begin
  if aValue < aMin then
    Exit(aMin);
  if aValue > aMax then
    Exit(aMax);
  Result := aValue;
end;

function TmaxCron.TryReadAutoIntEnv(const aEnvName: string; out aValue: Integer): Boolean;
var
  lText: string;
  lParsed: Int64;
begin
  Result := False;
  lText := Trim(GetEnvironmentVariable(aEnvName));
  if lText = '' then
    Exit;

  if not TryStrToInt64(lText, lParsed) then
    Exit;
  if (lParsed < Low(Integer)) or (lParsed > High(Integer)) then
    Exit;

  aValue := Integer(lParsed);
  Result := True;
end;

function TmaxCron.TryReadAutoFloatEnv(const aEnvName: string; out aValue: Double): Boolean;
var
  lText: string;
  lParsed: Double;
  lFormatSettings: TFormatSettings;
begin
  Result := False;
  lText := Trim(GetEnvironmentVariable(aEnvName));
  if lText = '' then
    Exit;

  lFormatSettings := TFormatSettings.Invariant;
  if not TryStrToFloat(lText, lParsed, lFormatSettings) then
    Exit;
  if IsNan(lParsed) or IsInfinite(lParsed) then
    Exit;

  aValue := lParsed;
  Result := True;
end;

procedure TmaxCron.ConfigureAutoControllerSettings;
const
  cDefaultEwmaAlpha = 0.125;
  cDefaultEnterMinEvents = 256;
  cDefaultExitMaxEvents = 160;
  cDefaultEnterMaxDueDensity = 0.25;
  cDefaultExitMinDueDensity = 0.60;
  cDefaultEnterMaxDirtyRate = 0.15;
  cDefaultExitMinDirtyRate = 0.40;
  cDefaultEnterHoldTicks = 3;
  cDefaultExitHoldTicks = 3;
  cDefaultTrialTicks = 32;
  cDefaultCooldownTicks = 128;
  cDefaultTrialFailCooldownBaseTicks = 16;
  cDefaultSwitchBudgetWindowTicks = 256;
  cDefaultSwitchBudgetMaxSwitches = 12;
  cDefaultSwitchBudgetCooldownTicks = 64;
  cDefaultPromoteRatio = 0.85;
  cDefaultDemoteRatio = 1.05;
  cDefaultDiagLogIntervalTicks = 0;

  cMinEnterEvents = 1;
  cMaxEnterEvents = 1000000;
  cMinExitEvents = 0;
  cMaxExitEvents = 1000000;
  cMinDueDensity = 0.0;
  cMaxDueDensity = 1.0;
  cMinDirtyRate = 0.0;
  cMaxDirtyRate = 1.0;
  cMinHoldTicks = 1;
  cMaxHoldTicks = 1024;
  cMinTrialTicks = 1;
  cMaxTrialTicks = 4096;
  cMinCooldownTicks = 0;
  cMaxCooldownTicks = 8192;
  cMinTrialFailCooldownBaseTicks = 0;
  cMaxTrialFailCooldownBaseTicks = 8192;
  cMinSwitchBudgetWindowTicks = 0;
  cMaxSwitchBudgetWindowTicks = 65536;
  cMinSwitchBudgetMaxSwitches = 0;
  cMaxSwitchBudgetMaxSwitches = 1024;
  cMinSwitchBudgetCooldownTicks = 0;
  cMaxSwitchBudgetCooldownTicks = 8192;
  cMinRatio = 0.25;
  cMaxRatio = 4.0;
  cMinRatioGap = 0.01;
  cMinDiagLogIntervalTicks = 0;
  cMaxDiagLogIntervalTicks = 1000000;
var
  lIntValue: Integer;
  lDoubleValue: Double;
begin
  fAutoConfig.EwmaAlpha := cDefaultEwmaAlpha;
  fAutoConfig.EnterMinEvents := cDefaultEnterMinEvents;
  fAutoConfig.ExitMaxEvents := cDefaultExitMaxEvents;
  fAutoConfig.EnterMaxDueDensity := cDefaultEnterMaxDueDensity;
  fAutoConfig.ExitMinDueDensity := cDefaultExitMinDueDensity;
  fAutoConfig.EnterMaxDirtyRate := cDefaultEnterMaxDirtyRate;
  fAutoConfig.ExitMinDirtyRate := cDefaultExitMinDirtyRate;
  fAutoConfig.EnterHoldTicks := cDefaultEnterHoldTicks;
  fAutoConfig.ExitHoldTicks := cDefaultExitHoldTicks;
  fAutoConfig.TrialTicks := cDefaultTrialTicks;
  fAutoConfig.CooldownTicks := cDefaultCooldownTicks;
  fAutoConfig.TrialFailCooldownBaseTicks := cDefaultTrialFailCooldownBaseTicks;
  fAutoConfig.SwitchBudgetWindowTicks := cDefaultSwitchBudgetWindowTicks;
  fAutoConfig.SwitchBudgetMaxSwitches := cDefaultSwitchBudgetMaxSwitches;
  fAutoConfig.SwitchBudgetCooldownTicks := cDefaultSwitchBudgetCooldownTicks;
  fAutoConfig.PromoteRatio := cDefaultPromoteRatio;
  fAutoConfig.DemoteRatio := cDefaultDemoteRatio;
  fAutoConfig.DiagLogIntervalTicks := cDefaultDiagLogIntervalTicks;

  if TryReadAutoIntEnv('MAXCRON_AUTO_ENTER_EVENTS', lIntValue) then
    fAutoConfig.EnterMinEvents := ClampAutoInt(lIntValue, cMinEnterEvents, cMaxEnterEvents);
  if TryReadAutoIntEnv('MAXCRON_AUTO_EXIT_EVENTS', lIntValue) then
    fAutoConfig.ExitMaxEvents := ClampAutoInt(lIntValue, cMinExitEvents, cMaxExitEvents);
  if TryReadAutoFloatEnv('MAXCRON_AUTO_ENTER_DUE_DENSITY', lDoubleValue) then
    fAutoConfig.EnterMaxDueDensity := ClampAutoFloat(lDoubleValue, cMinDueDensity, cMaxDueDensity);
  if TryReadAutoFloatEnv('MAXCRON_AUTO_EXIT_DUE_DENSITY', lDoubleValue) then
    fAutoConfig.ExitMinDueDensity := ClampAutoFloat(lDoubleValue, cMinDueDensity, cMaxDueDensity);
  if TryReadAutoFloatEnv('MAXCRON_AUTO_ENTER_DIRTY', lDoubleValue) then
    fAutoConfig.EnterMaxDirtyRate := ClampAutoFloat(lDoubleValue, cMinDirtyRate, cMaxDirtyRate);
  if TryReadAutoFloatEnv('MAXCRON_AUTO_EXIT_DIRTY', lDoubleValue) then
    fAutoConfig.ExitMinDirtyRate := ClampAutoFloat(lDoubleValue, cMinDirtyRate, cMaxDirtyRate);
  if TryReadAutoIntEnv('MAXCRON_AUTO_ENTER_HOLD', lIntValue) then
    fAutoConfig.EnterHoldTicks := ClampAutoInt(lIntValue, cMinHoldTicks, cMaxHoldTicks);
  if TryReadAutoIntEnv('MAXCRON_AUTO_EXIT_HOLD', lIntValue) then
    fAutoConfig.ExitHoldTicks := ClampAutoInt(lIntValue, cMinHoldTicks, cMaxHoldTicks);
  if TryReadAutoIntEnv('MAXCRON_AUTO_TRIAL_TICKS', lIntValue) then
    fAutoConfig.TrialTicks := ClampAutoInt(lIntValue, cMinTrialTicks, cMaxTrialTicks);
  if TryReadAutoIntEnv('MAXCRON_AUTO_COOLDOWN', lIntValue) then
    fAutoConfig.CooldownTicks := ClampAutoInt(lIntValue, cMinCooldownTicks, cMaxCooldownTicks);
  if TryReadAutoIntEnv('MAXCRON_AUTO_TRIAL_FAIL_COOLDOWN', lIntValue) then
    fAutoConfig.TrialFailCooldownBaseTicks :=
      ClampAutoInt(lIntValue, cMinTrialFailCooldownBaseTicks, cMaxTrialFailCooldownBaseTicks);
  if TryReadAutoIntEnv('MAXCRON_AUTO_SWITCH_BUDGET_WINDOW', lIntValue) then
    fAutoConfig.SwitchBudgetWindowTicks :=
      ClampAutoInt(lIntValue, cMinSwitchBudgetWindowTicks, cMaxSwitchBudgetWindowTicks);
  if TryReadAutoIntEnv('MAXCRON_AUTO_SWITCH_BUDGET_MAX', lIntValue) then
    fAutoConfig.SwitchBudgetMaxSwitches :=
      ClampAutoInt(lIntValue, cMinSwitchBudgetMaxSwitches, cMaxSwitchBudgetMaxSwitches);
  if TryReadAutoIntEnv('MAXCRON_AUTO_SWITCH_BUDGET_COOLDOWN', lIntValue) then
    fAutoConfig.SwitchBudgetCooldownTicks :=
      ClampAutoInt(lIntValue, cMinSwitchBudgetCooldownTicks, cMaxSwitchBudgetCooldownTicks);
  if TryReadAutoFloatEnv('MAXCRON_AUTO_PROMOTE_RATIO', lDoubleValue) then
    fAutoConfig.PromoteRatio := ClampAutoFloat(lDoubleValue, cMinRatio, cMaxRatio);
  if TryReadAutoFloatEnv('MAXCRON_AUTO_DEMOTE_RATIO', lDoubleValue) then
    fAutoConfig.DemoteRatio := ClampAutoFloat(lDoubleValue, cMinRatio, cMaxRatio);
  if TryReadAutoIntEnv('MAXCRON_AUTO_DIAG_LOG_INTERVAL', lIntValue) then
    fAutoConfig.DiagLogIntervalTicks := ClampAutoInt(lIntValue, cMinDiagLogIntervalTicks, cMaxDiagLogIntervalTicks);

  if fAutoConfig.ExitMaxEvents > fAutoConfig.EnterMinEvents then
    fAutoConfig.ExitMaxEvents := fAutoConfig.EnterMinEvents;
  if fAutoConfig.ExitMinDueDensity < fAutoConfig.EnterMaxDueDensity then
    fAutoConfig.ExitMinDueDensity := fAutoConfig.EnterMaxDueDensity;
  if fAutoConfig.ExitMinDirtyRate < fAutoConfig.EnterMaxDirtyRate then
    fAutoConfig.ExitMinDirtyRate := fAutoConfig.EnterMaxDirtyRate;
  if fAutoConfig.DemoteRatio <= fAutoConfig.PromoteRatio then
    fAutoConfig.DemoteRatio := ClampAutoFloat(fAutoConfig.PromoteRatio + cMinRatioGap, cMinRatio, cMaxRatio);
  if (fAutoConfig.SwitchBudgetWindowTicks > 0) and (fAutoConfig.SwitchBudgetMaxSwitches > 0) and
    (fAutoConfig.SwitchBudgetMaxSwitches > fAutoConfig.SwitchBudgetWindowTicks) then
    fAutoConfig.SwitchBudgetMaxSwitches := fAutoConfig.SwitchBudgetWindowTicks;
end;

procedure TmaxCron.ConfigureSchedulerEngine;
var
  lValue: string;
begin
  ConfigureAutoControllerSettings;

  lValue := LowerCase(Trim(GetEnvironmentVariable('MAXCRON_ENGINE')));
  if lValue = 'heap' then
    fSchedulerEngine := TSchedulerEngine.seHeap
  else if lValue = 'shadow' then
    fSchedulerEngine := TSchedulerEngine.seShadow
  else if lValue = 'auto' then
    fSchedulerEngine := TSchedulerEngine.seAuto
  else
    fSchedulerEngine := TSchedulerEngine.seScan;

  fAutoLock.Acquire;
  try
    fAutoEffectiveEngine := TSchedulerEngine.seScan;
    fAutoState := TAutoSchedulerState.asDisabled;
    fAutoMutationCounter := 0;
    fAutoMutationCursor := 0;
    fAutoEnterHold := 0;
    fAutoExitHold := 0;
    fAutoTrialTicksRemaining := 0;
    fAutoCooldownTicks := 0;
    fAutoTrialFailLevel := 0;
    fAutoTrialFailCooldownTicks := 0;
    fAutoSwitchBudgetHits := 0;
    fAutoControllerTick := 0;
    fAutoSwitchBudgetUntilTick := 0;
    fAutoSwitchHistory.Clear;
    fAutoSwitchCount := 0;
    fAutoEventCountEwma := 0;
    fAutoDueDensityEwma := 0;
    fAutoDirtyRateEwma := 0;
    fAutoScanTickUsEwma := 0;
    fAutoHeapTickUsEwma := 0;
    fAutoScanBaselineUs := 0;
    fAutoScanSampleTicks := 0;
    fAutoHeapSampleTicks := 0;
    fAutoTicksSinceSwitch := 0;
    fAutoSwitchBurstLevel := 0;
    fAutoLastSwitchReason := '';
    if fAutoConfig.DiagLogIntervalTicks > 0 then
      fAutoDiagLogTicksUntilEmit := fAutoConfig.DiagLogIntervalTicks
    else
      fAutoDiagLogTicksUntilEmit := 0;
    if fSchedulerEngine = TSchedulerEngine.seAuto then
      fAutoState := TAutoSchedulerState.asScanStable;
  finally
    fAutoLock.Release;
  end;

  if fSchedulerEngine = TSchedulerEngine.seScan then
    fHeapDirty := 0
  else
    fHeapDirty := 1;
end;

function TmaxCron.SchedulerEngineToText(const aEngine: TSchedulerEngine): string;
begin
  case aEngine of
    TSchedulerEngine.seHeap:
      Result := 'heap';
    TSchedulerEngine.seShadow:
      Result := 'shadow';
    TSchedulerEngine.seAuto:
      Result := 'auto';
  else
    Result := 'scan';
  end;
end;

function TmaxCron.AutoStateToText(const aState: TAutoSchedulerState): string;
begin
  case aState of
    TAutoSchedulerState.asScanStable:
      Result := 'scan-stable';
    TAutoSchedulerState.asHeapTrial:
      Result := 'heap-trial';
    TAutoSchedulerState.asHeapStable:
      Result := 'heap-stable';
  else
    Result := 'disabled';
  end;
end;

function TmaxCron.UpdateEwma(const aCurrent, aSample, aAlpha: Double): Double;
begin
  if aCurrent <= 0 then
    Exit(aSample);
  Result := (aCurrent * (1.0 - aAlpha)) + (aSample * aAlpha);
end;

procedure TmaxCron.PruneAutoSwitchHistoryLocked(const aCurrentTick: UInt64; const aWindowTicks: Integer);
var
  lCutoffTick: UInt64;
begin
  if aWindowTicks <= 0 then
  begin
    fAutoSwitchHistory.Clear;
    Exit;
  end;

  if aCurrentTick > UInt64(aWindowTicks) then
    lCutoffTick := aCurrentTick - UInt64(aWindowTicks)
  else
    lCutoffTick := 0;

  while fAutoSwitchHistory.Count > 0 do
    if fAutoSwitchHistory.Peek < lCutoffTick then
      fAutoSwitchHistory.Dequeue
    else
      Break;
end;

function TmaxCron.IsAutoSwitchBudgetExceededLocked(const aCurrentTick: UInt64; const aWindowTicks,
  aMaxSwitches: Integer): Boolean;
begin
  if (aWindowTicks <= 0) or (aMaxSwitches <= 0) then
    Exit(False);

  PruneAutoSwitchHistoryLocked(aCurrentTick, aWindowTicks);
  Result := (fAutoSwitchHistory.Count >= aMaxSwitches);
end;

function TmaxCron.GetAutoSwitchBudgetCooldownTicksLocked(const aCurrentTick: UInt64): Integer;
var
  lRemainingTicks: UInt64;
begin
  if fAutoSwitchBudgetUntilTick <= aCurrentTick then
    Exit(0);

  lRemainingTicks := fAutoSwitchBudgetUntilTick - aCurrentTick;
  if lRemainingTicks > UInt64(High(Integer)) then
    Exit(High(Integer));
  Result := Integer(lRemainingTicks);
end;

procedure TmaxCron.ApplyAutoTrialFailureBackoff(const aBaseCooldownTicks: Integer);
const
  cAutoMaxTrialFailureLevel = 6;
  cAutoMaxBackoffCooldown = 8192;
var
  lCooldownTicks: Int64;
begin
  if aBaseCooldownTicks <= 0 then
    Exit;

  if fAutoTrialFailLevel < cAutoMaxTrialFailureLevel then
    Inc(fAutoTrialFailLevel);

  lCooldownTicks := aBaseCooldownTicks;
  if fAutoTrialFailLevel > 1 then
    lCooldownTicks := lCooldownTicks shl (fAutoTrialFailLevel - 1);
  if lCooldownTicks > cAutoMaxBackoffCooldown then
    lCooldownTicks := cAutoMaxBackoffCooldown;

  if fAutoTrialFailCooldownTicks < lCooldownTicks then
    fAutoTrialFailCooldownTicks := Integer(lCooldownTicks);
end;

procedure TmaxCron.SwitchAutoEffectiveEngine(const aEngine: TSchedulerEngine; const aReason: string);
const
  cAutoMaxSwitchBurstLevel = 4;
  cAutoMaxBackoffCooldown = 8192;
var
  lBaseCooldown: Integer;
  lCooldownTicks: Integer;
  lFastSwitchThreshold: Integer;
begin
  if aEngine = TSchedulerEngine.seAuto then
    Exit;
  if fAutoEffectiveEngine = aEngine then
    Exit;

  lBaseCooldown := fAutoConfig.CooldownTicks;
  if lBaseCooldown < 0 then
    lBaseCooldown := 0;

  lFastSwitchThreshold := lBaseCooldown;
  if lFastSwitchThreshold < 8 then
    lFastSwitchThreshold := 8;

  if fAutoTicksSinceSwitch <= lFastSwitchThreshold then
    fAutoSwitchBurstLevel := ClampAutoInt(fAutoSwitchBurstLevel + 1, 0, cAutoMaxSwitchBurstLevel)
  else
    fAutoSwitchBurstLevel := 0;

  fAutoEffectiveEngine := aEngine;
  if fAutoConfig.SwitchBudgetWindowTicks > 0 then
  begin
    PruneAutoSwitchHistoryLocked(fAutoControllerTick, fAutoConfig.SwitchBudgetWindowTicks);
    fAutoSwitchHistory.Enqueue(fAutoControllerTick);
  end else
    fAutoSwitchHistory.Clear;
  Inc(fAutoSwitchCount);
  if aReason <> '' then
    fAutoLastSwitchReason := aReason
  else
    fAutoLastSwitchReason := 'unspecified';
  lCooldownTicks := lBaseCooldown * (1 + fAutoSwitchBurstLevel);
  fAutoCooldownTicks := ClampAutoInt(lCooldownTicks, 0, cAutoMaxBackoffCooldown);
  fAutoTicksSinceSwitch := 0;
  if aEngine = TSchedulerEngine.seHeap then
    fAutoHeapSampleTicks := 0
  else
    fAutoScanSampleTicks := 0;
  if aEngine = TSchedulerEngine.seHeap then
    TInterlocked.Exchange(fHeapDirty, 1);
end;

procedure TmaxCron.EvaluateAutoController(const aEngineUsed: TSchedulerEngine; const aEventCount, aDueCount: Integer;
  const aElapsedMicroseconds: Int64);
const
  cAutoMinPerfSamples = 8;
  cAutoDirtyDensityScale = 128.0;
  cAutoDiagLogFormat =
    'maxCron auto diag engineUsed=%s effective=%s state=%s events=%s due=%s dueEwma=%s dirtyEwma=%s scanUs=%s ' +
    'heapUs=%s baselineUs=%s switches=%s cooldown=%s trialFailLevel=%s trialFailCooldown=%s budgetHits=%s ' +
    'budgetCooldown=%s budgetRecent=%s burst=%s reason=%s';
var
  lConfig: TAutoControllerConfig;
  lBudgetUntilTick: UInt64;
  lDueDensitySample: Double;
  lDirtySample: Double;
  lEnterCandidate: Boolean;
  lExitCandidate: Boolean;
  lFormatSettings: TFormatSettings;
  lHasPerfSignal: Boolean;
  lLogLine: string;
  lMinPerfSamples: Integer;
  lMutationDelta: Int64;
  lMutationNow: Int64;
  lPromoteHeap: Boolean;
  lFastPromoteCandidate: Boolean;
  lSwitchBudgetBlocked: Boolean;
  lSwitchBudgetCooldownTicks: Integer;
  lSwitchBudgetEnabled: Boolean;
  lSwitchBudgetExceeded: Boolean;
begin
  if fSchedulerEngine <> TSchedulerEngine.seAuto then
    Exit;

  fAutoLock.Acquire;
  try
    lConfig := fAutoConfig;
    if fAutoControllerTick < High(UInt64) then
      Inc(fAutoControllerTick);
    PruneAutoSwitchHistoryLocked(fAutoControllerTick, lConfig.SwitchBudgetWindowTicks);
    lSwitchBudgetEnabled :=
      (lConfig.SwitchBudgetWindowTicks > 0) and
      (lConfig.SwitchBudgetMaxSwitches > 0) and
      (lConfig.SwitchBudgetCooldownTicks > 0);
    lMinPerfSamples := cAutoMinPerfSamples;
    if lConfig.TrialTicks < lMinPerfSamples then
      lMinPerfSamples := ClampAutoInt(lConfig.TrialTicks, 1, cAutoMinPerfSamples);
    if fAutoTicksSinceSwitch < High(Integer) then
      Inc(fAutoTicksSinceSwitch);

    if aEngineUsed = TSchedulerEngine.seScan then
    begin
      fAutoScanTickUsEwma := UpdateEwma(fAutoScanTickUsEwma, aElapsedMicroseconds, lConfig.EwmaAlpha);
      fAutoScanBaselineUs := UpdateEwma(fAutoScanBaselineUs, aElapsedMicroseconds, lConfig.EwmaAlpha);
      if fAutoScanSampleTicks < High(Integer) then
        Inc(fAutoScanSampleTicks);
    end else if aEngineUsed = TSchedulerEngine.seHeap then
    begin
      fAutoHeapTickUsEwma := UpdateEwma(fAutoHeapTickUsEwma, aElapsedMicroseconds, lConfig.EwmaAlpha);
      if fAutoHeapSampleTicks < High(Integer) then
        Inc(fAutoHeapSampleTicks);
    end;

    lMutationNow := TInterlocked.Read(fAutoMutationCounter);
    lMutationDelta := lMutationNow - fAutoMutationCursor;
    if lMutationDelta < 0 then
      lMutationDelta := 0;
    fAutoMutationCursor := lMutationNow;

    lDirtySample := 0.0;
    if aEventCount > 0 then
      lDirtySample := ClampAutoFloat((Double(lMutationDelta) / aEventCount) * cAutoDirtyDensityScale, 0.0, 1.0)
    else if lMutationDelta > 0 then
      lDirtySample := 1.0;
    lDueDensitySample := 0.0;
    if aEventCount > 0 then
      lDueDensitySample := ClampAutoFloat(aDueCount / aEventCount, 0.0, 1.0);

    fAutoEventCountEwma := UpdateEwma(fAutoEventCountEwma, aEventCount, lConfig.EwmaAlpha);
    fAutoDueDensityEwma := UpdateEwma(fAutoDueDensityEwma, lDueDensitySample, lConfig.EwmaAlpha);
    fAutoDirtyRateEwma := UpdateEwma(fAutoDirtyRateEwma, lDirtySample, lConfig.EwmaAlpha);

    if fAutoCooldownTicks > 0 then
      Dec(fAutoCooldownTicks);
    if fAutoTrialFailCooldownTicks > 0 then
      Dec(fAutoTrialFailCooldownTicks);
    lSwitchBudgetCooldownTicks := GetAutoSwitchBudgetCooldownTicksLocked(fAutoControllerTick);
    lSwitchBudgetBlocked := lSwitchBudgetEnabled and (lSwitchBudgetCooldownTicks > 0);

    if lConfig.DiagLogIntervalTicks > 0 then
    begin
      if fAutoDiagLogTicksUntilEmit <= 0 then
        fAutoDiagLogTicksUntilEmit := lConfig.DiagLogIntervalTicks;
      Dec(fAutoDiagLogTicksUntilEmit);
      if fAutoDiagLogTicksUntilEmit = 0 then
      begin
        lFormatSettings := TFormatSettings.Invariant;
        lLogLine := Format(cAutoDiagLogFormat,
          [
            SchedulerEngineToText(aEngineUsed),
            SchedulerEngineToText(fAutoEffectiveEngine),
            AutoStateToText(fAutoState),
            IntToStr(aEventCount),
            IntToStr(aDueCount),
            FloatToStrF(fAutoDueDensityEwma, ffFixed, 18, 6, lFormatSettings),
            FloatToStrF(fAutoDirtyRateEwma, ffFixed, 18, 6, lFormatSettings),
            FloatToStrF(fAutoScanTickUsEwma, ffFixed, 18, 2, lFormatSettings),
            FloatToStrF(fAutoHeapTickUsEwma, ffFixed, 18, 2, lFormatSettings),
            FloatToStrF(fAutoScanBaselineUs, ffFixed, 18, 2, lFormatSettings),
            IntToStr(Int64(fAutoSwitchCount)),
            IntToStr(fAutoCooldownTicks),
            IntToStr(fAutoTrialFailLevel),
            IntToStr(fAutoTrialFailCooldownTicks),
            IntToStr(fAutoSwitchBudgetHits),
            IntToStr(lSwitchBudgetCooldownTicks),
            IntToStr(fAutoSwitchHistory.Count),
            IntToStr(fAutoSwitchBurstLevel),
            fAutoLastSwitchReason
          ]);
        OutputDebugString(PChar(lLogLine));
        fAutoDiagLogTicksUntilEmit := lConfig.DiagLogIntervalTicks;
      end;
    end else
      fAutoDiagLogTicksUntilEmit := 0;

    case fAutoState of
      TAutoSchedulerState.asScanStable:
        begin
          lEnterCandidate :=
            (fAutoEventCountEwma >= lConfig.EnterMinEvents) and
            (fAutoDueDensityEwma <= lConfig.EnterMaxDueDensity) and
            (fAutoDirtyRateEwma <= lConfig.EnterMaxDirtyRate) and
            (fAutoCooldownTicks = 0) and
            (not lSwitchBudgetBlocked) and
            (fAutoTrialFailCooldownTicks = 0);

          if lEnterCandidate then
            Inc(fAutoEnterHold)
          else
            fAutoEnterHold := 0;

          if fAutoEnterHold >= lConfig.EnterHoldTicks then
          begin
            lSwitchBudgetExceeded := lSwitchBudgetEnabled and
              IsAutoSwitchBudgetExceededLocked(fAutoControllerTick, lConfig.SwitchBudgetWindowTicks,
              lConfig.SwitchBudgetMaxSwitches);
            if lSwitchBudgetExceeded then
            begin
              if fAutoSwitchBudgetHits < High(Integer) then
                Inc(fAutoSwitchBudgetHits);
              lBudgetUntilTick := fAutoControllerTick + UInt64(lConfig.SwitchBudgetCooldownTicks);
              if lBudgetUntilTick > fAutoSwitchBudgetUntilTick then
                fAutoSwitchBudgetUntilTick := lBudgetUntilTick;
              fAutoEnterHold := 0;
            end else begin
              fAutoEnterHold := 0;
              fAutoExitHold := 0;
              lFastPromoteCandidate :=
                (fAutoEventCountEwma >= (lConfig.EnterMinEvents * 2.0)) and
                (fAutoDueDensityEwma <= (lConfig.EnterMaxDueDensity * 0.5)) and
                (fAutoDirtyRateEwma <= (lConfig.EnterMaxDirtyRate * 0.5)) and
                (fAutoScanSampleTicks >= lMinPerfSamples);

              if lFastPromoteCandidate then
              begin
                fAutoTrialTicksRemaining := 0;
                fAutoHeapTickUsEwma := 0;
                fAutoState := TAutoSchedulerState.asHeapStable;
                fAutoTrialFailLevel := 0;
                fAutoTrialFailCooldownTicks := 0;
                SwitchAutoEffectiveEngine(TSchedulerEngine.seHeap, 'scan-fast-promote');
              end else begin
                fAutoTrialTicksRemaining := lConfig.TrialTicks;
                fAutoHeapTickUsEwma := 0;
                fAutoState := TAutoSchedulerState.asHeapTrial;
                SwitchAutoEffectiveEngine(TSchedulerEngine.seHeap, 'scan-enter-trial');
              end;
            end;
          end;
        end;

      TAutoSchedulerState.asHeapTrial:
        begin
          lExitCandidate :=
            (fAutoEventCountEwma <= lConfig.ExitMaxEvents) or
            (fAutoDueDensityEwma >= lConfig.ExitMinDueDensity) or
            (fAutoDirtyRateEwma >= lConfig.ExitMinDirtyRate);

          if lExitCandidate then
          begin
            ApplyAutoTrialFailureBackoff(lConfig.TrialFailCooldownBaseTicks);
            fAutoEnterHold := 0;
            fAutoExitHold := 0;
            fAutoTrialTicksRemaining := 0;
            fAutoState := TAutoSchedulerState.asScanStable;
            if fAutoDueDensityEwma >= lConfig.ExitMinDueDensity then
              SwitchAutoEffectiveEngine(TSchedulerEngine.seScan, 'heap-trial-exit-density')
            else
              SwitchAutoEffectiveEngine(TSchedulerEngine.seScan, 'heap-trial-exit-churn');
            Exit;
          end;

          if fAutoTrialTicksRemaining > 0 then
            Dec(fAutoTrialTicksRemaining);

          if fAutoTrialTicksRemaining = 0 then
          begin
            lHasPerfSignal := (fAutoScanSampleTicks >= lMinPerfSamples) and
              (fAutoHeapSampleTicks >= lMinPerfSamples);
            lPromoteHeap :=
              lHasPerfSignal and
              (fAutoScanBaselineUs > 0) and
              (fAutoHeapTickUsEwma > 0) and
              (fAutoHeapTickUsEwma <= (fAutoScanBaselineUs * lConfig.PromoteRatio));

            if lPromoteHeap then
            begin
              fAutoState := TAutoSchedulerState.asHeapStable;
              fAutoExitHold := 0;
              fAutoTrialFailLevel := 0;
              fAutoTrialFailCooldownTicks := 0;
            end else begin
              ApplyAutoTrialFailureBackoff(lConfig.TrialFailCooldownBaseTicks);
              fAutoState := TAutoSchedulerState.asScanStable;
              SwitchAutoEffectiveEngine(TSchedulerEngine.seScan, 'heap-trial-fallback-perf');
            end;
          end;
        end;

      TAutoSchedulerState.asHeapStable:
        begin
          lHasPerfSignal := (fAutoScanSampleTicks >= lMinPerfSamples) and
            (fAutoHeapSampleTicks >= lMinPerfSamples);
          lExitCandidate :=
            (fAutoEventCountEwma <= lConfig.ExitMaxEvents) or
            (fAutoDueDensityEwma >= lConfig.ExitMinDueDensity) or
            (fAutoDirtyRateEwma >= lConfig.ExitMinDirtyRate) or
            (lHasPerfSignal and (fAutoScanBaselineUs > 0) and
            (fAutoHeapTickUsEwma > (fAutoScanBaselineUs * lConfig.DemoteRatio)));

          if lExitCandidate then
            Inc(fAutoExitHold)
          else
            fAutoExitHold := 0;

          if fAutoExitHold >= lConfig.ExitHoldTicks then
          begin
            fAutoExitHold := 0;
            fAutoState := TAutoSchedulerState.asScanStable;
            if fAutoDueDensityEwma >= lConfig.ExitMinDueDensity then
              SwitchAutoEffectiveEngine(TSchedulerEngine.seScan, 'heap-stable-exit-density')
            else
              SwitchAutoEffectiveEngine(TSchedulerEngine.seScan, 'heap-stable-exit');
          end;
        end;
    else
      fAutoState := TAutoSchedulerState.asScanStable;
    end;

    if (aEngineUsed = TSchedulerEngine.seScan) and (fAutoEffectiveEngine = TSchedulerEngine.seHeap) then
      TInterlocked.Exchange(fHeapDirty, 1);
  finally
    fAutoLock.Release;
  end;
end;

procedure TmaxCron.SetDefaultInvokeMode(const aValue: TmaxCronInvokeMode);
begin
  if aValue = TmaxCronInvokeMode.imDefault then
    fDefaultInvokeMode := TmaxCronInvokeMode.imMainThread
  else
    fDefaultInvokeMode := aValue;
end;

procedure TmaxCron.SetDefaultDayMatchMode(const Value: TmaxCronDayMatchMode);
var
  x: Integer;
  lEvent: IMaxCronEvent;
begin
  if Value = TmaxCronDayMatchMode.dmDefault then
    fDefaultDayMatchMode := TmaxCronDayMatchMode.dmAnd
  else
    fDefaultDayMatchMode := Value;

  fItemsLock.Acquire;
  try
    for x := 0 to fItems.Count - 1 do
    begin
      lEvent := fItems[x];
      if (lEvent <> nil) and (lEvent.DayMatchMode = TmaxCronDayMatchMode.dmDefault) then
        lEvent.DayMatchMode := TmaxCronDayMatchMode.dmDefault;
    end;
  finally
    fItemsLock.Release;
  end;
end;

procedure TmaxCron.SetDefaultDialect(const Value: TmaxCronDialect);
begin
  fDefaultDialect := Value;
end;

procedure TmaxCron.SetDefaultMisfirePolicy(const aValue: TmaxCronMisfirePolicy);
begin
  if aValue = TmaxCronMisfirePolicy.mpDefault then
    fDefaultMisfirePolicy := TmaxCronMisfirePolicy.mpCatchUpAll
  else
    fDefaultMisfirePolicy := aValue;
end;

procedure TmaxCron.SetDefaultMisfireCatchUpLimit(const Value: Cardinal);
begin
  if Value = 0 then
    fDefaultMisfireCatchUpLimit := 1
  else
    fDefaultMisfireCatchUpLimit := Value;
end;

function TmaxCron.NormalizeEventName(const aName: string): string;
begin
  Result := Trim(aName);
end;

function TmaxCron.EventNameKey(const aName: string): string;
begin
  Result := UpperCase(aName);
end;

procedure TmaxCron.IndexEventLocked(const aEventItem: IMaxCronEvent; const aIndex: Integer);
var
  lEvent: TmaxCronEvent;
begin
  if (aEventItem = nil) or (aIndex < 0) then
    Exit;

  if TryGetCronEvent(aEventItem, lEvent) then
  begin
    fItemsById.AddOrSetValue(lEvent.fId, aIndex);
    if lEvent.FName <> '' then
      fItemsByName.AddOrSetValue(EventNameKey(lEvent.FName), aIndex);
    Exit;
  end;

  fItemsById.AddOrSetValue(aEventItem.Id, aIndex);
  if aEventItem.Name <> '' then
    fItemsByName.AddOrSetValue(EventNameKey(aEventItem.Name), aIndex);
end;

procedure TmaxCron.RemoveEventIndexLocked(const aEventItem: IMaxCronEvent);
var
  lEvent: TmaxCronEvent;
begin
  if aEventItem = nil then
    Exit;

  if TryGetCronEvent(aEventItem, lEvent) then
  begin
    fItemsById.Remove(lEvent.fId);
    if lEvent.FName <> '' then
      fItemsByName.Remove(EventNameKey(lEvent.FName));
    Exit;
  end;

  fItemsById.Remove(aEventItem.Id);
  if aEventItem.Name <> '' then
    fItemsByName.Remove(EventNameKey(aEventItem.Name));
end;

procedure TmaxCron.ReindexFromLocked(const aStartIndex: Integer);
var
  i: Integer;
begin
  if aStartIndex < 0 then
    Exit;

  for i := aStartIndex to fItems.Count - 1 do
    IndexEventLocked(fItems[i], i);
end;

function TmaxCron.FindIndexByNameLocked(const aName: string): Integer;
begin
  if aName = '' then
    Exit(-1);

  if not fItemsByName.TryGetValue(EventNameKey(aName), Result) then
    Result := -1
  else if (Result < 0) or (Result >= fItems.Count) then
    Result := -1;
end;

function TmaxCron.FindIndexByIdLocked(const aId: Int64): Integer;
begin
  if aId <= 0 then
    Exit(-1);

  if not fItemsById.TryGetValue(aId, Result) then
    Result := -1
  else if (Result < 0) or (Result >= fItems.Count) then
    Result := -1;
end;

function TmaxCron.TryGetEventByIdLocked(const aId: Int64; out aEventItem: IMaxCronEvent): Boolean;
var
  lIndex: Integer;
begin
  aEventItem := nil;
  lIndex := FindIndexByIdLocked(aId);
  if lIndex < 0 then
    Exit(False);

  aEventItem := fItems[lIndex];
  if (aEventItem = nil) or (aEventItem.Id <> aId) then
    Exit(False);

  Result := True;
end;

procedure TmaxCron.MarkHeapDirty;
begin
  if fSchedulerEngine = TSchedulerEngine.seScan then
    Exit;
  TInterlocked.Exchange(fHeapDirty, 1);
  if fSchedulerEngine = TSchedulerEngine.seAuto then
    TInterlocked.Increment(fAutoMutationCounter);
end;

function TmaxCron.HeapEntryLessThan(const aLeft, aRight: TCronHeapEntry): Boolean;
begin
  if aLeft.DueAt < aRight.DueAt then
    Exit(True);
  if aLeft.DueAt > aRight.DueAt then
    Exit(False);
  Result := aLeft.EventId < aRight.EventId;
end;

procedure TmaxCron.HeapSiftUpLocked(const aIndex: Integer);
var
  lChildIndex: Integer;
  lParentIndex: Integer;
  lTemp: TCronHeapEntry;
begin
  lChildIndex := aIndex;
  while lChildIndex > 0 do
  begin
    lParentIndex := (lChildIndex - 1) shr 1;
    if not HeapEntryLessThan(fHeapItems[lChildIndex], fHeapItems[lParentIndex]) then
      Break;
    lTemp := fHeapItems[lChildIndex];
    fHeapItems[lChildIndex] := fHeapItems[lParentIndex];
    fHeapItems[lParentIndex] := lTemp;
    lChildIndex := lParentIndex;
  end;
end;

procedure TmaxCron.HeapSiftDownLocked(const aIndex: Integer);
var
  lCount: Integer;
  lParentIndex: Integer;
  lLeftIndex: Integer;
  lRightIndex: Integer;
  lSmallestIndex: Integer;
  lTemp: TCronHeapEntry;
begin
  lCount := fHeapItems.Count;
  lParentIndex := aIndex;
  while True do
  begin
    lLeftIndex := (lParentIndex shl 1) + 1;
    lRightIndex := lLeftIndex + 1;
    lSmallestIndex := lParentIndex;

    if (lLeftIndex < lCount) and HeapEntryLessThan(fHeapItems[lLeftIndex], fHeapItems[lSmallestIndex]) then
      lSmallestIndex := lLeftIndex;
    if (lRightIndex < lCount) and HeapEntryLessThan(fHeapItems[lRightIndex], fHeapItems[lSmallestIndex]) then
      lSmallestIndex := lRightIndex;

    if lSmallestIndex = lParentIndex then
      Break;

    lTemp := fHeapItems[lParentIndex];
    fHeapItems[lParentIndex] := fHeapItems[lSmallestIndex];
    fHeapItems[lSmallestIndex] := lTemp;
    lParentIndex := lSmallestIndex;
  end;
end;

procedure TmaxCron.HeapPushLocked(const aDueAt: TDateTime; const aEventId: Int64);
var
  lEntry: TCronHeapEntry;
begin
  lEntry.DueAt := aDueAt;
  lEntry.EventId := aEventId;
  fHeapItems.Add(lEntry);
  HeapSiftUpLocked(fHeapItems.Count - 1);
end;

function TmaxCron.HeapPeekLocked(out aEntry: TCronHeapEntry): Boolean;
begin
  Result := (fHeapItems.Count > 0);
  if Result then
    aEntry := fHeapItems[0];
end;

function TmaxCron.HeapPopLocked(out aEntry: TCronHeapEntry): Boolean;
var
  lLastIndex: Integer;
begin
  Result := (fHeapItems.Count > 0);
  if not Result then
    Exit(False);

  aEntry := fHeapItems[0];
  lLastIndex := fHeapItems.Count - 1;
  if lLastIndex = 0 then
  begin
    fHeapItems.Delete(lLastIndex);
    Exit(True);
  end;

  fHeapItems[0] := fHeapItems[lLastIndex];
  fHeapItems.Delete(lLastIndex);
  HeapSiftDownLocked(0);
end;

procedure TmaxCron.RebuildHeapLocked;
var
  lCount: Integer;
  lEntry: TCronHeapEntry;
  lIndex: Integer;
  lEvent: TmaxCronEvent;
begin
  fHeapItems.Clear;
  Inc(fHeapRebuildCount);
  Inc(fTickEventsVisited, fItems.Count);

  for lIndex := 0 to fItems.Count - 1 do
  begin
    if not TryGetCronEvent(fItems[lIndex], lEvent) then
      Continue;
    if lEvent.TryGetHeapScheduleSnapshot(lEntry.EventId, lEntry.DueAt) then
      fHeapItems.Add(lEntry);
  end;

  lCount := fHeapItems.Count;
  if lCount <= 1 then
    Exit;

  for lIndex := (lCount shr 1) - 1 downto 0 do
  begin
    HeapSiftDownLocked(lIndex);
  end;
end;

procedure TmaxCron.CollectScanDueIdsLocked(const aNow: TDateTime; const aIds: TList<Int64>);
var
  lIndex: Integer;
  lEvent: TmaxCronEvent;
  lId: Int64;
  lDueAt: TDateTime;
begin
  aIds.Clear;
  for lIndex := 0 to fItems.Count - 1 do
  begin
    if not TryGetCronEvent(fItems[lIndex], lEvent) then
      Continue;
    if lEvent.TryGetHeapScheduleSnapshot(lId, lDueAt) and (lDueAt <= aNow) then
      aIds.Add(lId);
  end;
  aIds.Sort;
end;

procedure TmaxCron.CollectHeapDueIdsLocked(const aNow: TDateTime; const aIds: TList<Int64>);
var
  lIndex: Integer;
  lEntry: TCronHeapEntry;
  lEventItem: IMaxCronEvent;
  lEvent: TmaxCronEvent;
begin
  aIds.Clear;
  for lIndex := 0 to fHeapItems.Count - 1 do
  begin
    lEntry := fHeapItems[lIndex];
    if lEntry.DueAt > aNow then
      Continue;
    if not TryGetEventByIdLocked(lEntry.EventId, lEventItem) then
      Continue;
    if not TryGetCronEvent(lEventItem, lEvent) then
      Continue;
    if not lEvent.IsHeapScheduleCurrent(lEntry.DueAt) then
      Continue;
    if aIds.IndexOf(lEntry.EventId) < 0 then
      aIds.Add(lEntry.EventId);
  end;
  aIds.Sort;
end;

function TmaxCron.Int64ListToText(const aIds: TList<Int64>): string;
var
  lIndex: Integer;
  lBuilder: TStringBuilder;
begin
  lBuilder := TStringBuilder.Create;
  try
    lBuilder.Append('[');
    for lIndex := 0 to aIds.Count - 1 do
    begin
      if lIndex > 0 then
        lBuilder.Append(',');
      lBuilder.Append(IntToStr(aIds[lIndex]));
    end;
    lBuilder.Append(']');
    Result := lBuilder.ToString;
  finally
    lBuilder.Free;
  end;
end;

procedure TmaxCron.ValidateShadowParity(const aNow: TDateTime);
var
  lScanIds: TList<Int64>;
  lHeapIds: TList<Int64>;
  lIndex: Integer;
begin
  lScanIds := TList<Int64>.Create;
  lHeapIds := TList<Int64>.Create;
  try
    fItemsLock.Acquire;
    try
      if TInterlocked.Exchange(fHeapDirty, 0) = 1 then
        RebuildHeapLocked;
      CollectScanDueIdsLocked(aNow, lScanIds);
      CollectHeapDueIdsLocked(aNow, lHeapIds);
    finally
      fItemsLock.Release;
    end;

    if lScanIds.Count <> lHeapIds.Count then
      raise Exception.CreateFmt('MAXCRON_ENGINE=shadow divergence at %.8f scan=%s heap=%s',
        [aNow, Int64ListToText(lScanIds), Int64ListToText(lHeapIds)]);

    for lIndex := 0 to lScanIds.Count - 1 do
      if lScanIds[lIndex] <> lHeapIds[lIndex] then
        raise Exception.CreateFmt('MAXCRON_ENGINE=shadow divergence at %.8f scan=%s heap=%s',
          [aNow, Int64ListToText(lScanIds), Int64ListToText(lHeapIds)]);
  finally
    lHeapIds.Free;
    lScanIds.Free;
  end;
end;

function TmaxCron.DeleteLocked(const aIndex: Integer): Boolean;
var
  lEvent: TmaxCronEvent;
  lEventItem: IMaxCronEvent;
begin
  if (aIndex < 0) or (aIndex >= fItems.Count) then
    Exit(False);

  lEventItem := fItems[aIndex];
  RemoveEventIndexLocked(lEventItem);
  fItems.Delete(aIndex);
  ReindexFromLocked(aIndex);
  if TryGetCronEvent(lEventItem, lEvent) then
    lEvent.MarkPendingDestroy;
  fPendingFree.Add(lEventItem);
  MarkHeapDirty;
  FlushPendingFreeLocked;
  Result := True;
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
  lEventItem: IMaxCronEvent;
begin
  if (fTickDepth <> 0) then Exit;

  i := fPendingFree.Count - 1;
  while i >= 0 do
  begin
    lEventItem := fPendingFree[i];
    if TryGetCronEvent(lEventItem, lEvent) and lEvent.CanFreeNow then
    begin
      fPendingFree.Delete(i);
    end;
    Dec(i);
  end;
end;

procedure TmaxCron.CreateTimer(const aRequestedBackend: TmaxCronTimerBackend);
begin
  if (aRequestedBackend = TmaxCronTimerBackend.ctVcl) and
    (TThread.CurrentThread.ThreadID <> MainThreadID) then
    raise Exception.Create('ctVcl backend requires creation on the VCL main thread');

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

function TmaxCron.Delete(const aId: Int64): boolean;
var
  lIndex: Integer;
  lEvent: IMaxCronEvent;
begin
  lIndex := -1;
  fItemsLock.Acquire;
  try
    lIndex := FindIndexByIdLocked(aId);
    if (lIndex >= 0) and (lIndex < fItems.Count) then
    begin
      lEvent := fItems[lIndex];
      if (lEvent = nil) or (lEvent.Id <> aId) then
        lIndex := -1;
    end;
    Result := DeleteLocked(lIndex);
  finally
    fItemsLock.Release;
  end;
end;

function TmaxCron.Delete(const aName: string): boolean;
var
  lName: string;
  lIndex: Integer;
  lEvent: IMaxCronEvent;
begin
  lName := NormalizeEventName(aName);
  if lName = '' then
    Exit(False);

  fItemsLock.Acquire;
  try
    lIndex := FindIndexByNameLocked(lName);
    if (lIndex >= 0) and (lIndex < fItems.Count) then
    begin
      lEvent := fItems[lIndex];
      if (lEvent = nil) or (not SameText(lEvent.Name, lName)) then
        lIndex := -1;
    end;
    Result := DeleteLocked(lIndex);
  finally
    fItemsLock.Release;
  end;
end;

function TmaxCron.Delete(event: IMaxCronEvent): boolean;
var
  lIndex: Integer;
  lCronEvent: TmaxCronEvent;
begin
  if event = nil then
    Exit(False);

  lIndex := -1;
  fItemsLock.Acquire;
  try
    if TryGetCronEvent(event, lCronEvent) then
    begin
      lIndex := FindIndexByIdLocked(lCronEvent.fId);
      if (lIndex >= 0) and (lIndex < fItems.Count) and (fItems[lIndex] = event) then
      begin
        Result := DeleteLocked(lIndex);
        Exit;
      end;
    end;

    for lIndex := 0 to fItems.Count - 1 do
      if fItems[lIndex] = event then
      begin
        Result := DeleteLocked(lIndex);
        Exit;
      end;
    Result := False;
  finally
    fItemsLock.Release;
  end;
end;

destructor TmaxCron.Destroy;
const
  cCallbackDrainGraceMs = 75;
var
  lSharedState: ICronSharedState;
  lDone: Boolean;
  lWait: TStopwatch;
begin
  lSharedState := nil;
  Supports(fSharedState, ICronSharedState, lSharedState);

  if Pointer(Self) = gMaxCronExecutingCron then
    raise Exception.Create('TmaxCron.Free cannot be called from one of its own callbacks');

  if lSharedState <> nil then
  begin
    lSharedState.Detach;

    if (lSharedState.GetInFlightCount > 0) or (lSharedState.GetCallbackDepth > 0) then
    begin
      lWait := TStopwatch.StartNew;
      while ((lSharedState.GetInFlightCount > 0) or (lSharedState.GetCallbackDepth > 0)) and
        (lWait.ElapsedMilliseconds < cCallbackDrainGraceMs) do
      begin
        if TThread.CurrentThread.ThreadID = MainThreadID then
          CheckSynchronize(1)
        else
          TThread.Sleep(1);
      end;

      if (lSharedState.GetInFlightCount > 0) or (lSharedState.GetCallbackDepth > 0) then
        raise Exception.Create('TmaxCron.Free cannot be called from one of its own callbacks');
    end;
  end;

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
  fItemsById.Free;
  fItemsByName.Free;
  fHeapItems.Free;
  fAutoSwitchHistory.Free;
  fAutoLock.Free;
  fPendingFree.Free;
  fItemsLock.Free;
  fAsyncKeepAlive.Free;
  fAsyncLock.Free;
  inherited;
end;

function TmaxCron.Snapshot: TArray<IMaxCronEvent>;
var
  i: Integer;
begin
  fItemsLock.Acquire;
  try
    SetLength(Result, fItems.Count);
    for i := 0 to fItems.Count - 1 do
      Result[i] := fItems[i];
  finally
    fItemsLock.Release;
  end;
end;

function TmaxCron.TryGetAutoDiagnostics(out aDiagnostics: TMaxCronAutoDiagnostics): Boolean;
var
  lAutoState: TAutoSchedulerState;
  lEffectiveEngine: TSchedulerEngine;
begin
  aDiagnostics := Default(TMaxCronAutoDiagnostics);
  aDiagnostics.ConfiguredEngine := SchedulerEngineToText(fSchedulerEngine);
  lEffectiveEngine := fSchedulerEngine;
  lAutoState := TAutoSchedulerState.asDisabled;
  Result := False;

  fAutoLock.Acquire;
  try
    if fSchedulerEngine = TSchedulerEngine.seAuto then
    begin
      Result := True;
      lEffectiveEngine := fAutoEffectiveEngine;
      lAutoState := fAutoState;
      aDiagnostics.LastSwitchReason := fAutoLastSwitchReason;
      aDiagnostics.SwitchCount := fAutoSwitchCount;
      aDiagnostics.EventCountEwma := fAutoEventCountEwma;
      aDiagnostics.DueDensityEwma := fAutoDueDensityEwma;
      aDiagnostics.DirtyRateEwma := fAutoDirtyRateEwma;
      aDiagnostics.ScanTickUsEwma := fAutoScanTickUsEwma;
      aDiagnostics.HeapTickUsEwma := fAutoHeapTickUsEwma;
      aDiagnostics.ScanBaselineUs := fAutoScanBaselineUs;
      aDiagnostics.CooldownTicks := fAutoCooldownTicks;
      aDiagnostics.TrialFailLevel := fAutoTrialFailLevel;
      aDiagnostics.TrialFailCooldownTicks := fAutoTrialFailCooldownTicks;
      PruneAutoSwitchHistoryLocked(fAutoControllerTick, fAutoConfig.SwitchBudgetWindowTicks);
      aDiagnostics.SwitchBudgetHits := fAutoSwitchBudgetHits;
      aDiagnostics.SwitchBudgetCooldownTicks := GetAutoSwitchBudgetCooldownTicksLocked(fAutoControllerTick);
      aDiagnostics.SwitchBudgetRecentSwitches := fAutoSwitchHistory.Count;
      aDiagnostics.SwitchBurstLevel := fAutoSwitchBurstLevel;
      aDiagnostics.ScanSampleTicks := fAutoScanSampleTicks;
      aDiagnostics.HeapSampleTicks := fAutoHeapSampleTicks;
      aDiagnostics.TicksSinceSwitch := fAutoTicksSinceSwitch;
    end;
  finally
    fAutoLock.Release;
  end;

  aDiagnostics.EffectiveEngine := SchedulerEngineToText(lEffectiveEngine);
  aDiagnostics.AutoState := AutoStateToText(lAutoState);
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
  lElapsedMicroseconds: Int64;
  lElapsedTicks: Int64;
  lEngineUsed: TSchedulerEngine;
  lEventCount: Integer;
  lDueCount: Integer;
  lStartTicks: Int64;
begin
  if fSchedulerEngine = TSchedulerEngine.seAuto then
  begin
    fAutoLock.Acquire;
    try
      lEngineUsed := fAutoEffectiveEngine;
    finally
      fAutoLock.Release;
    end;

    fItemsLock.Acquire;
    try
      lEventCount := fItems.Count;
    finally
      fItemsLock.Release;
    end;

    lStartTicks := TStopwatch.GetTimeStamp;
    case lEngineUsed of
      TSchedulerEngine.seHeap:
        DoTickAtHeap(aNow, lDueCount);
    else
      DoTickAtScan(aNow, lDueCount);
    end;

    lElapsedTicks := TStopwatch.GetTimeStamp - lStartTicks;
    if lElapsedTicks < 0 then
      lElapsedTicks := 0;
    if TStopwatch.Frequency > 0 then
      lElapsedMicroseconds := (lElapsedTicks * 1000000) div TStopwatch.Frequency
    else
      lElapsedMicroseconds := 0;

    EvaluateAutoController(lEngineUsed, lEventCount, lDueCount, lElapsedMicroseconds);
    Exit;
  end;

  case fSchedulerEngine of
    TSchedulerEngine.seHeap:
      DoTickAtHeap(aNow, lDueCount);
    TSchedulerEngine.seShadow:
      begin
        ValidateShadowParity(aNow);
        DoTickAtHeap(aNow, lDueCount);
      end;
    TSchedulerEngine.seAuto:
      DoTickAtScan(aNow, lDueCount);
  else
    DoTickAtScan(aNow, lDueCount);
  end;
end;

procedure TmaxCron.DoTickAtScan(const aNow: TDateTime; out aDueCount: Integer);
var
  x: Integer;
  lSnapshot: TArray<IMaxCronEvent>;
  lDepthIncreased: Boolean;
  lEvent: TmaxCronEvent;
begin
  aDueCount := 0;
  lDepthIncreased := False;
  try
    fItemsLock.Acquire;
    try
      Inc(fTickDepth);
      lDepthIncreased := True;
      SetLength(lSnapshot, fItems.Count);
      for x := 0 to fItems.Count - 1 do
        lSnapshot[x] := fItems[x];
      Inc(fTickEventsVisited, Length(lSnapshot));
    finally
      fItemsLock.Release;
    end;

    for x := 0 to Length(lSnapshot) - 1 do
      if TryGetCronEvent(lSnapshot[x], lEvent) then
      begin
        if lEvent.Enabled and (lEvent.NextSchedule > 0) and (lEvent.NextSchedule <= aNow) then
          Inc(aDueCount);
        lEvent.checkTimer(aNow);
      end;
  finally
    if lDepthIncreased then
    begin
      fItemsLock.Acquire;
      try
        Dec(fTickDepth);
        FlushPendingFreeLocked;
      finally
        fItemsLock.Release;
      end;
    end;
  end;
end;

procedure TmaxCron.DoTickAtHeap(const aNow: TDateTime; out aDueCount: Integer);
var
  lDepthIncreased: Boolean;
  lDueEvents: TList<TmaxCronEvent>;
  lReschedules: TList<TCronHeapEntry>;
  lEntry: TCronHeapEntry;
  lRescheduleEntry: TCronHeapEntry;
  lEventItem: IMaxCronEvent;
  lEvent: TmaxCronEvent;
  lDueEvent: TmaxCronEvent;
  lIndex: Integer;
  lId: Int64;
  lDueAt: TDateTime;
begin
  aDueCount := 0;
  lDepthIncreased := False;
  lDueEvents := TList<TmaxCronEvent>.Create;
  lReschedules := TList<TCronHeapEntry>.Create;
  try
    fItemsLock.Acquire;
    try
      Inc(fTickDepth);
      lDepthIncreased := True;
      if TInterlocked.Exchange(fHeapDirty, 0) = 1 then
        RebuildHeapLocked;

      while HeapPeekLocked(lEntry) and (lEntry.DueAt <= aNow) do
      begin
        HeapPopLocked(lEntry);
        Inc(fTickEventsVisited);
        if not TryGetEventByIdLocked(lEntry.EventId, lEventItem) then
          Continue;
        if not TryGetCronEvent(lEventItem, lEvent) then
          Continue;
        if not lEvent.IsHeapScheduleCurrent(lEntry.DueAt) then
          Continue;
        lDueEvents.Add(lEvent);
      end;
    finally
      fItemsLock.Release;
    end;

    for lIndex := 0 to lDueEvents.Count - 1 do
    begin
      Inc(aDueCount);
      lDueEvent := lDueEvents[lIndex];
      lDueEvent.checkTimer(aNow);
      if not lDueEvent.TryGetHeapScheduleSnapshot(lId, lDueAt) then
        Continue;

      lRescheduleEntry.EventId := lId;
      lRescheduleEntry.DueAt := lDueAt;
      lReschedules.Add(lRescheduleEntry);
    end;

    if lReschedules.Count > 0 then
    begin
      fItemsLock.Acquire;
      try
        for lIndex := 0 to lReschedules.Count - 1 do
        begin
          lRescheduleEntry := lReschedules[lIndex];
          if not TryGetEventByIdLocked(lRescheduleEntry.EventId, lEventItem) then
            Continue;
          if not TryGetCronEvent(lEventItem, lEvent) then
            Continue;
          if lEvent.IsHeapScheduleCurrent(lRescheduleEntry.DueAt) then
            HeapPushLocked(lRescheduleEntry.DueAt, lRescheduleEntry.EventId);
        end;
      finally
        fItemsLock.Release;
      end;
    end;
  finally
    lReschedules.Free;
    lDueEvents.Free;
    if lDepthIncreased then
    begin
      fItemsLock.Acquire;
      try
        Dec(fTickDepth);
        FlushPendingFreeLocked;
      finally
        fItemsLock.Release;
      end;
    end;
  end;
end;

{$IFDEF MAXCRON_TESTS}
procedure TmaxCron.TickAt(const aNow: TDateTime);
begin
  DoTickAt(aNow);
end;

procedure TmaxCron.StartTimerForTests(const aIntervalMs: Cardinal);
begin
  if fTimer <> nil then
    fTimer.Start(aIntervalMs);
end;

procedure TmaxCron.ResetTickMetricsForTests;
begin
  fTickEventsVisited := 0;
  fHeapRebuildCount := 0;
end;

procedure TmaxCron.GetTickMetricsForTests(out aEventsVisited: UInt64; out aHeapRebuilds: UInt64);
begin
  aEventsVisited := fTickEventsVisited;
  aHeapRebuilds := fHeapRebuildCount;
end;

procedure TmaxCron.GetEngineStateForTests(out aConfiguredEngine: string; out aEffectiveEngine: string;
  out aAutoState: string; out aSwitchCount: UInt64);
var
  lEffectiveEngine: TSchedulerEngine;
  lAutoState: TAutoSchedulerState;
begin
  aConfiguredEngine := SchedulerEngineToText(fSchedulerEngine);
  lEffectiveEngine := fSchedulerEngine;
  lAutoState := TAutoSchedulerState.asDisabled;
  aSwitchCount := 0;

  fAutoLock.Acquire;
  try
    if fSchedulerEngine = TSchedulerEngine.seAuto then
    begin
      lEffectiveEngine := fAutoEffectiveEngine;
      lAutoState := fAutoState;
      aSwitchCount := fAutoSwitchCount;
    end;
  finally
    fAutoLock.Release;
  end;

  aEffectiveEngine := SchedulerEngineToText(lEffectiveEngine);
  aAutoState := AutoStateToText(lAutoState);
end;
{$ENDIF}

procedure TmaxCron.QueueTick;
var
  lSharedState: ICronSharedState;
begin
  if TInterlocked.CompareExchange(fTickQueued, 1, 0) <> 0 then
    Exit;

  if not Supports(fSharedState, ICronSharedState, lSharedState) then
  begin
    TInterlocked.Exchange(fTickQueued, 0);
    Exit;
  end;

  try
    // WARNING: queued main-thread dispatch requires an active main-thread message pump.
    {$IFDEF ForceQueueNotAvailable}
    TThread.Queue(nil,
    {$ELSE}
    TThread.ForceQueue(nil,
    {$ENDIF}
      procedure
      begin
        lSharedState.ExecuteQueuedTick;
      end);
  except
    lSharedState.ResetTickQueued;
    raise;
  end;
end;

procedure TmaxCron.TimerTimer(Sender: TObject);
begin
  if fActiveTimerBackend = TmaxCronTimerBackend.ctPortable then
  begin
    DoTick;
    Exit;
  end;

  if TThread.CurrentThread.ThreadID = MainThreadID then
    DoTick
  else
    QueueTick;
end;

function MakePreview(const SchedulePlan: string; out Dates: TDates; Limit: integer = 100): boolean;
begin
  Result := MakePreview(SchedulePlan, cdMaxCron, Dates, Limit);
end;

function MakePreview(const SchedulePlan: string; const Dialect: TmaxCronDialect; out Dates: TDates;
  Limit: integer = 100): boolean;
var
  scheduler: TCronSchedulePlan;
begin
  Result := False;
  scheduler := TCronSchedulePlan.Create;
  try
    scheduler.Dialect := Dialect;
    scheduler.Parse(SchedulePlan);
    scheduler.GetNextOccurrences(Limit, Now, Dates);
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
  const aOnScheduleEvent: TmaxCronNotifyEvent): IMaxCronEvent;
begin
  Result := Add(aName);
  try
    Result.EventPlan := aEventPlan;
    Result.OnScheduleEvent := aOnScheduleEvent;
  except
    Delete(Result);
    raise;
  end;
end;

function TmaxCron.Add(const aName, aEventPlan: string;
  const aOnScheduleEvent: TmaxCronNotifyProc): IMaxCronEvent;
begin
  Result := Add(aName);
  try
    Result.EventPlan := aEventPlan;
    Result.OnScheduleProc := aOnScheduleEvent;
  except
    Delete(Result);
    raise;
  end;
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
begin
  lMode := Value;
  if lMode = TmaxCronDayMatchMode.dmDefault then
    if (fSharedState = nil) or (not fSharedState.TryGetDefaultDayMatchMode(lMode)) then
      lMode := TmaxCronDayMatchMode.dmAnd;

  fLock.Acquire;
  try
    fDayMatchMode := Value;
    fScheduler.DayMatchMode := lMode;
    if FEnabled then
      ResetSchedule;
  finally
    fLock.Release;
  end;
end;

procedure TmaxCronEvent.SetMisfirePolicy(const Value: TmaxCronMisfirePolicy);
begin
  fLock.Acquire;
  try
    fMisfirePolicy := Value;
  finally
    fLock.Release;
  end;
end;

procedure TmaxCronEvent.ParseExcludedDatesCsv(const aValue: string; out aDateSerials: TArray<Integer>);
var
  lItems: TStringList;
  lDates: TList<Integer>;
  lIndex: Integer;
  lToken: string;
  lYear: Integer;
  lMonth: Integer;
  lDay: Integer;
  lDash1: Integer;
  lDash2: Integer;
  lDate: TDateTime;
  lSerial: Integer;
begin
  SetLength(aDateSerials, 0);
  if Trim(aValue) = '' then
    Exit;

  lItems := TStringList.Create;
  lDates := TList<Integer>.Create;
  try
    SplitString(aValue, ',', lItems);
    for lIndex := 0 to lItems.Count - 1 do
    begin
      lToken := Trim(lItems[lIndex]);
      if lToken = '' then
        Continue;
      lDash1 := Pos('-', lToken);
      lDash2 := LastDelimiter('-', lToken);
      if (Length(lToken) <> 10) or (lDash1 <> 5) or (lDash2 <> 8) then
        raise Exception.Create('Invalid excluded date; expected YYYY-MM-DD');
      lYear := StrToInt(Copy(lToken, 1, 4));
      lMonth := StrToInt(Copy(lToken, 6, 2));
      lDay := StrToInt(Copy(lToken, 9, 2));
      lDate := EncodeDate(lYear, lMonth, lDay);
      lSerial := Trunc(lDate);
      if lDates.IndexOf(lSerial) < 0 then
        lDates.Add(lSerial);
    end;
    lDates.Sort;
    SetLength(aDateSerials, lDates.Count);
    for lIndex := 0 to lDates.Count - 1 do
      aDateSerials[lIndex] := lDates[lIndex];
  finally
    lDates.Free;
    lItems.Free;
  end;
end;

procedure TmaxCronEvent.ClearAmbiguousSecondGate;
begin
  fAmbiguousSecondGateActive := False;
  fAmbiguousSecondGatePassedTarget := False;
  fAmbiguousSecondGateRollbackSeen := False;
end;

procedure TmaxCronEvent.ArmAmbiguousSecondGate(const aSchedule: TDateTime);
begin
  if (fTimeZoneKind = TCronTimeZoneKind.ctzLocal) and TTimeZone.Local.IsAmbiguousTime(aSchedule) then
  begin
    fAmbiguousSecondGateActive := True;
    fAmbiguousSecondGatePassedTarget := False;
    fAmbiguousSecondGateRollbackSeen := False;
  end else
    ClearAmbiguousSecondGate;
end;

function TmaxCronEvent.ProcessAmbiguousSecondGate(const aNow: TDateTime): Boolean;
begin
  Result := True;
  if not fAmbiguousSecondGateActive then
    Exit;

  if not fAmbiguousSecondGatePassedTarget then
  begin
    if aNow < fNextSchedule then
      Exit(False);

    fAmbiguousSecondGatePassedTarget := True;
    if (aNow > fNextSchedule) and (not TTimeZone.Local.IsAmbiguousTime(aNow)) then
      ClearAmbiguousSecondGate
    else
      Exit(False);
  end else if not fAmbiguousSecondGateRollbackSeen then
  begin
    if aNow < fNextSchedule then
    begin
      fAmbiguousSecondGateRollbackSeen := True;
      Exit(False);
    end;

    if (aNow > fNextSchedule) and (not TTimeZone.Local.IsAmbiguousTime(aNow)) then
      ClearAmbiguousSecondGate
    else
      Exit(False);
  end else begin
    if aNow < fNextSchedule then
      Exit(False);
    ClearAmbiguousSecondGate;
  end;
end;

function TmaxCronEvent.TryParseTimeZone(const aValue: string; out aKind: TCronTimeZoneKind;
  out aOffsetMinutes: Integer; out aNormalized: string): Boolean;
var
  lText: string;
  lSign: Integer;
  lOffsetText: string;
  lColonPos: Integer;
  lSecondColonPos: Integer;
  lHoursText: string;
  lMinutesText: string;
  lHours: Integer;
  lMinutes: Integer;
  lIndex: Integer;
begin
  Result := False;
  lText := UpperCase(Trim(aValue));
  if (lText = '') or (lText = 'LOCAL') then
  begin
    aKind := TCronTimeZoneKind.ctzLocal;
    aOffsetMinutes := 0;
    aNormalized := 'LOCAL';
    Exit(True);
  end;

  if (lText = 'UTC') or (lText = 'Z') then
  begin
    aKind := TCronTimeZoneKind.ctzUtc;
    aOffsetMinutes := 0;
    aNormalized := 'UTC';
    Exit(True);
  end;

  if (Copy(lText, 1, 3) <> 'UTC') or (Length(lText) < 5) then
    Exit(False);

  if lText[4] = '+' then
    lSign := 1
  else if lText[4] = '-' then
    lSign := -1
  else
    Exit(False);

  lOffsetText := Copy(lText, 5, MaxInt);
  lColonPos := Pos(':', lOffsetText);
  if lColonPos > 0 then
  begin
    lSecondColonPos := PosEx(':', lOffsetText, lColonPos + 1);
    if lSecondColonPos > 0 then
      Exit(False);

    lHoursText := Copy(lOffsetText, 1, lColonPos - 1);
    lMinutesText := Copy(lOffsetText, lColonPos + 1, MaxInt);
    if (Length(lHoursText) < 1) or (Length(lHoursText) > 2) then
      Exit(False);
    if Length(lMinutesText) <> 2 then
      Exit(False);

    for lIndex := 1 to Length(lHoursText) do
      if (lHoursText[lIndex] < '0') or (lHoursText[lIndex] > '9') then
        Exit(False);
    for lIndex := 1 to Length(lMinutesText) do
      if (lMinutesText[lIndex] < '0') or (lMinutesText[lIndex] > '9') then
        Exit(False);

    lHours := StrToInt(lHoursText);
    lMinutes := StrToInt(lMinutesText);
  end else begin
    if (Length(lOffsetText) < 1) or (Length(lOffsetText) > 2) then
      Exit(False);
    for lIndex := 1 to Length(lOffsetText) do
      if (lOffsetText[lIndex] < '0') or (lOffsetText[lIndex] > '9') then
        Exit(False);

    lHours := StrToInt(lOffsetText);
    lMinutes := 0;
  end;

  if (lHours < 0) or (lHours > 14) then
    Exit(False);
  if (lMinutes < 0) or (lMinutes > 59) then
    Exit(False);
  if (lHours = 14) and (lMinutes <> 0) then
    Exit(False);

  aKind := TCronTimeZoneKind.ctzFixedOffset;
  aOffsetMinutes := lSign * (lHours * 60 + lMinutes);
  aNormalized := Format('UTC%s%.2d:%.2d', [IfThen(lSign >= 0, '+', '-'), lHours, lMinutes]);
  Result := True;
end;

procedure TmaxCronEvent.SetTimeZoneId(const Value: string);
var
  lKind: TCronTimeZoneKind;
  lOffsetMinutes: Integer;
  lNormalized: string;
begin
  if not TryParseTimeZone(Value, lKind, lOffsetMinutes, lNormalized) then
    raise Exception.Create('Invalid timezone; expected LOCAL, UTC, or UTC+/-HH[:MM]');

  fLock.Acquire;
  try
    if fTimeZoneId = lNormalized then
      Exit;
    fTimeZoneId := lNormalized;
    fTimeZoneKind := lKind;
    fTimeZoneOffsetMinutes := lOffsetMinutes;
    fPendingDstSecondSchedule := 0;
    ClearAmbiguousSecondGate;
    if FEnabled then
      ResetSchedule;
  finally
    fLock.Release;
  end;
end;

procedure TmaxCronEvent.SetDstSpringPolicy(const Value: TmaxCronDstSpringPolicy);
begin
  fLock.Acquire;
  try
    fDstSpringPolicy := Value;
    if FEnabled then
      ResetSchedule;
  finally
    fLock.Release;
  end;
end;

procedure TmaxCronEvent.SetDstFallPolicy(const Value: TmaxCronDstFallPolicy);
begin
  fLock.Acquire;
  try
    fDstFallPolicy := Value;
    fPendingDstSecondSchedule := 0;
    ClearAmbiguousSecondGate;
    if FEnabled then
      ResetSchedule;
  finally
    fLock.Release;
  end;
end;

procedure TmaxCronEvent.SetWeekdaysOnly(const Value: Boolean);
begin
  fLock.Acquire;
  try
    fWeekdaysOnly := Value;
    if FEnabled then
      ResetSchedule;
  finally
    fLock.Release;
  end;
end;

procedure TmaxCronEvent.SetExcludedDatesCsv(const Value: string);
var
  lDates: TArray<Integer>;
  lIndex: Integer;
begin
  ParseExcludedDatesCsv(Value, lDates);
  fLock.Acquire;
  try
    fExcludedDatesCsv := Trim(Value);
    SetLength(fExcludedDateSerials, Length(lDates));
    for lIndex := 0 to Length(lDates) - 1 do
      fExcludedDateSerials[lIndex] := lDates[lIndex];
    if FEnabled then
      ResetSchedule;
  finally
    fLock.Release;
  end;
end;

procedure TmaxCronEvent.SetBlackoutStartTime(const Value: TDateTime);
begin
  if (Value < 0) or (Value >= 1) then
    raise Exception.Create('BlackoutStartTime must be in [00:00, 23:59:59]');
  fLock.Acquire;
  try
    fBlackoutStartTime := Frac(Value);
    if FEnabled then
      ResetSchedule;
  finally
    fLock.Release;
  end;
end;

procedure TmaxCronEvent.SetBlackoutEndTime(const Value: TDateTime);
begin
  if (Value < 0) or (Value >= 1) then
    raise Exception.Create('BlackoutEndTime must be in [00:00, 23:59:59]');
  fLock.Acquire;
  try
    fBlackoutEndTime := Frac(Value);
    if FEnabled then
      ResetSchedule;
  finally
    fLock.Release;
  end;
end;

function TmaxCronEvent.SystemLocalToEventLocal(const aSystemLocal: TDateTime): TDateTime;
var
  lUtc: TDateTime;
begin
  lUtc := TTimeZone.Local.ToUniversalTime(aSystemLocal);
  case fTimeZoneKind of
    TCronTimeZoneKind.ctzUtc:
      Result := lUtc;
    TCronTimeZoneKind.ctzFixedOffset:
      Result := lUtc + (fTimeZoneOffsetMinutes / (24 * 60));
  else
    Result := TTimeZone.Local.ToLocalTime(lUtc);
  end;
end;

function TmaxCronEvent.EventLocalToSystemLocal(const aEventLocal: TDateTime; out aSystemLocal: TDateTime): Boolean;
var
  lUseLocal: TDateTime;
  lUtc: TDateTime;
begin
  lUseLocal := aEventLocal;
  case fTimeZoneKind of
    TCronTimeZoneKind.ctzLocal:
      begin
        if TTimeZone.Local.IsInvalidTime(lUseLocal) then
        begin
          if fDstSpringPolicy = TmaxCronDstSpringPolicy.dspSkip then
            Exit(False);
          while TTimeZone.Local.IsInvalidTime(lUseLocal) do
            lUseLocal := IncMinute(lUseLocal, 1);
        end;

        if TTimeZone.Local.IsAmbiguousTime(lUseLocal) then
        begin
          case fDstFallPolicy of
            TmaxCronDstFallPolicy.dfpRunOncePreferSecondInstance:
              begin
                // Keep the same wall-clock time and select the standard-time instance.
                lUtc := TTimeZone.Local.ToUniversalTime(lUseLocal, False);
                lUseLocal := TTimeZone.Local.ToLocalTime(lUtc);
                ArmAmbiguousSecondGate(lUseLocal);
              end;
            TmaxCronDstFallPolicy.dfpRunTwice:
              if fPendingDstSecondSchedule = 0 then
                fPendingDstSecondSchedule := lUseLocal;
          end;
        end;

        aSystemLocal := lUseLocal;
        Result := True;
      end;
    TCronTimeZoneKind.ctzUtc:
      begin
        aSystemLocal := TTimeZone.Local.ToLocalTime(aEventLocal);
        Result := True;
      end;
  else
    begin
      lUtc := aEventLocal - (fTimeZoneOffsetMinutes / (24 * 60));
      aSystemLocal := TTimeZone.Local.ToLocalTime(lUtc);
      Result := True;
    end;
  end;
end;

function TmaxCronEvent.IsTimeInBlackout(const aEventLocalDateTime: TDateTime): Boolean;
var
  lTimeOnly: TDateTime;
begin
  if (fBlackoutStartTime = 0) and (fBlackoutEndTime = 0) then
    Exit(False);
  if fBlackoutStartTime = fBlackoutEndTime then
    Exit(False);
  lTimeOnly := Frac(aEventLocalDateTime);
  if fBlackoutStartTime < fBlackoutEndTime then
    Exit((lTimeOnly >= fBlackoutStartTime) and (lTimeOnly < fBlackoutEndTime));
  Result := (lTimeOnly >= fBlackoutStartTime) or (lTimeOnly < fBlackoutEndTime);
end;

function TmaxCronEvent.IsOccurrenceExcluded(const aEventLocalDateTime: TDateTime): Boolean;
var
  lDow: Integer;
  lDateSerial: Integer;
  lLow: Integer;
  lHigh: Integer;
  lMid: Integer;
begin
  if fWeekdaysOnly then
  begin
    lDow := DayOfTheWeek(aEventLocalDateTime);
    if (lDow = 1) or (lDow = 7) then
      Exit(True);
  end;

  lDateSerial := Trunc(aEventLocalDateTime);
  lLow := 0;
  lHigh := Length(fExcludedDateSerials) - 1;
  while lLow <= lHigh do
  begin
    lMid := (lLow + lHigh) shr 1;
    if fExcludedDateSerials[lMid] < lDateSerial then
      lLow := lMid + 1
    else if fExcludedDateSerials[lMid] > lDateSerial then
      lHigh := lMid - 1
    else
      Exit(True);
  end;

  Result := IsTimeInBlackout(aEventLocalDateTime);
end;

function TmaxCronEvent.FindNextScheduleWithPolicies(const aBaseSystemLocal: TDateTime; out aNextSystemLocal: TDateTime): TFindNextScheduleResult;
const
  cMaxAttempts = 4096;
var
  lEventBase: TDateTime;
  lEventCursor: TDateTime;
  lEventNext: TDateTime;
  lEventValidFrom: TDateTime;
  lEventValidTo: TDateTime;
  lAttempt: Integer;
  lDateSerial: Integer;
  lLow: Integer;
  lHigh: Integer;
  lMid: Integer;
  lDow: Integer;
  lWeekendExcluded: Boolean;
  lDateExcluded: Boolean;
  lBlackoutExcluded: Boolean;
  lAdvanceCursor: TDateTime;
  lDateBase: TDateTime;
  lTimeOnly: TDateTime;
  lBlackoutEnd: TDateTime;
begin
  Result := TFindNextScheduleResult.fnsNotFound;
  if fPendingDstSecondSchedule > 0 then
  begin
    aNextSystemLocal := fPendingDstSecondSchedule;
    fPendingDstSecondSchedule := 0;
    if (fTimeZoneKind = TCronTimeZoneKind.ctzLocal) and (fDstFallPolicy = TmaxCronDstFallPolicy.dfpRunTwice) then
      ArmAmbiguousSecondGate(aNextSystemLocal)
    else
      ClearAmbiguousSecondGate;
    Exit(TFindNextScheduleResult.fnsFound);
  end;

  lEventBase := SystemLocalToEventLocal(aBaseSystemLocal);
  lEventValidFrom := 0;
  lEventValidTo := 0;
  if FValidFrom > 0 then
    lEventValidFrom := SystemLocalToEventLocal(FValidFrom);
  if FValidTo > 0 then
    lEventValidTo := SystemLocalToEventLocal(FValidTo);
  lEventCursor := lEventBase;

  for lAttempt := 1 to cMaxAttempts do
  begin
    if fPendingDstSecondSchedule > 0 then
    begin
      aNextSystemLocal := fPendingDstSecondSchedule;
      fPendingDstSecondSchedule := 0;
      if (fTimeZoneKind = TCronTimeZoneKind.ctzLocal) and (fDstFallPolicy = TmaxCronDstFallPolicy.dfpRunTwice) then
        ArmAmbiguousSecondGate(aNextSystemLocal)
      else
        ClearAmbiguousSecondGate;
      Exit(TFindNextScheduleResult.fnsFound);
    end;

    if not fScheduler.FindNextScheduleDate(lEventCursor, lEventNext, lEventValidFrom, lEventValidTo) then
      Exit(TFindNextScheduleResult.fnsNotFound);

    lWeekendExcluded := False;
    if fWeekdaysOnly then
    begin
      lDow := DayOfTheWeek(lEventNext);
      lWeekendExcluded := (lDow = 1) or (lDow = 7);
    end;

    lDateExcluded := False;
    if not lWeekendExcluded then
    begin
      lDateSerial := Trunc(lEventNext);
      lLow := 0;
      lHigh := Length(fExcludedDateSerials) - 1;
      while lLow <= lHigh do
      begin
        lMid := (lLow + lHigh) shr 1;
        if fExcludedDateSerials[lMid] < lDateSerial then
          lLow := lMid + 1
        else if fExcludedDateSerials[lMid] > lDateSerial then
          lHigh := lMid - 1
        else
        begin
          lDateExcluded := True;
          Break;
        end;
      end;
    end;

    lBlackoutExcluded := False;
    if (not lWeekendExcluded) and (not lDateExcluded) then
      lBlackoutExcluded := IsTimeInBlackout(lEventNext);

    if lWeekendExcluded or lDateExcluded or lBlackoutExcluded then
    begin
      lAdvanceCursor := lEventNext;

      if lWeekendExcluded or lDateExcluded then
        lAdvanceCursor := Trunc(lEventNext) + 1 - OneSecond
      else if lBlackoutExcluded then
      begin
        lDateBase := Trunc(lEventNext);
        if fBlackoutStartTime < fBlackoutEndTime then
          lBlackoutEnd := lDateBase + fBlackoutEndTime
        else begin
          lTimeOnly := Frac(lEventNext);
          if lTimeOnly >= fBlackoutStartTime then
            lBlackoutEnd := lDateBase + 1 + fBlackoutEndTime
          else
            lBlackoutEnd := lDateBase + fBlackoutEndTime;
        end;
        lAdvanceCursor := lBlackoutEnd - OneSecond;
      end;

      if lAdvanceCursor <= lEventNext then
        lAdvanceCursor := lEventNext;

      lEventCursor := lAdvanceCursor;
      Continue;
    end;

    if not EventLocalToSystemLocal(lEventNext, aNextSystemLocal) then
    begin
      lEventCursor := lEventNext;
      Continue;
    end;
    Exit(TFindNextScheduleResult.fnsFound);
  end;

  aNextSystemLocal := IncSecond(aBaseSystemLocal, 1);
  Result := TFindNextScheduleResult.fnsSearchLimitReached;
end;

procedure TmaxCronEvent.SetDialect(const Value: TmaxCronDialect);
var
  lValidator: TCronSchedulePlan;
begin
  fLock.Acquire;
  try
    if fDialect = Value then
      Exit;
    if FEventPlan <> '' then
    begin
      lValidator := TCronSchedulePlan.Create;
      try
        lValidator.Dialect := Value;
        lValidator.HashSeed := GetHashSeed;
        lValidator.Parse(FEventPlan);
      finally
        lValidator.Free;
      end;
    end;

    fDialect := Value;
    fScheduler.Dialect := Value;
    fScheduler.HashSeed := GetHashSeed;
    if FEventPlan <> '' then
    begin
      fScheduler.Parse(FEventPlan);
      ResetSchedule;
    end;
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

function TmaxCronEvent.GetEventPlan: string;
begin
  fLock.Acquire;
  try
    Result := FEventPlan;
  finally
    fLock.Release;
  end;
end;

function TmaxCronEvent.GetId: Int64;
begin
  fLock.Acquire;
  try
    Result := fId;
  finally
    fLock.Release;
  end;
end;

function TmaxCronEvent.GetHashSeed: string;
begin
  if FName <> '' then
    Exit(FName);
  Result := '#' + IntToStr(fId);
end;

function TmaxCronEvent.TryGetHeapScheduleSnapshot(out aId: Int64; out aDueAt: TDateTime): Boolean;
begin
  fLock.Acquire;
  try
    aId := fId;
    aDueAt := fNextSchedule;
    Result := (not fPendingDestroy) and FEnabled and (fNextSchedule > 0);
  finally
    fLock.Release;
  end;
end;

function TmaxCronEvent.IsHeapScheduleCurrent(const aDueAt: TDateTime): Boolean;
begin
  fLock.Acquire;
  try
    Result := (not fPendingDestroy) and FEnabled and (fNextSchedule > 0) and (fNextSchedule = aDueAt);
  finally
    fLock.Release;
  end;
end;

function TmaxCronEvent.GetName: string;
begin
  fLock.Acquire;
  try
    Result := FName;
  finally
    fLock.Release;
  end;
end;

function TmaxCronEvent.GetTag: Integer;
begin
  fLock.Acquire;
  try
    Result := FTag;
  finally
    fLock.Release;
  end;
end;

function TmaxCronEvent.GetUserData: Pointer;
begin
  fLock.Acquire;
  try
    Result := FUserData;
  finally
    fLock.Release;
  end;
end;

function TmaxCronEvent.GetUserDataInterface: IInterface;
begin
  fLock.Acquire;
  try
    Result := FUserDataInterface;
  finally
    fLock.Release;
  end;
end;

function TmaxCronEvent.GetOnScheduleEvent: TmaxCronNotifyEvent;
begin
  fLock.Acquire;
  try
    Result := FOnScheduleEvent;
  finally
    fLock.Release;
  end;
end;

function TmaxCronEvent.GetOnScheduleProc: TmaxCronNotifyProc;
begin
  fLock.Acquire;
  try
    Result := FOnScheduleProc;
  finally
    fLock.Release;
  end;
end;

function TmaxCronEvent.GetInvokeMode: TmaxCronInvokeMode;
begin
  fLock.Acquire;
  try
    Result := fInvokeMode;
  finally
    fLock.Release;
  end;
end;

function TmaxCronEvent.GetDialect: TmaxCronDialect;
begin
  fLock.Acquire;
  try
    Result := fDialect;
  finally
    fLock.Release;
  end;
end;

function TmaxCronEvent.GetTimeZoneId: string;
begin
  fLock.Acquire;
  try
    Result := fTimeZoneId;
  finally
    fLock.Release;
  end;
end;

function TmaxCronEvent.GetDstSpringPolicy: TmaxCronDstSpringPolicy;
begin
  fLock.Acquire;
  try
    Result := fDstSpringPolicy;
  finally
    fLock.Release;
  end;
end;

function TmaxCronEvent.GetDstFallPolicy: TmaxCronDstFallPolicy;
begin
  fLock.Acquire;
  try
    Result := fDstFallPolicy;
  finally
    fLock.Release;
  end;
end;

function TmaxCronEvent.GetWeekdaysOnly: Boolean;
begin
  fLock.Acquire;
  try
    Result := fWeekdaysOnly;
  finally
    fLock.Release;
  end;
end;

function TmaxCronEvent.GetExcludedDatesCsv: string;
begin
  fLock.Acquire;
  try
    Result := fExcludedDatesCsv;
  finally
    fLock.Release;
  end;
end;

function TmaxCronEvent.GetBlackoutStartTime: TDateTime;
begin
  fLock.Acquire;
  try
    Result := fBlackoutStartTime;
  finally
    fLock.Release;
  end;
end;

function TmaxCronEvent.GetBlackoutEndTime: TDateTime;
begin
  fLock.Acquire;
  try
    Result := fBlackoutEndTime;
  finally
    fLock.Release;
  end;
end;

function TmaxCronEvent.GetValidFrom: TDateTime;
begin
  fLock.Acquire;
  try
    Result := FValidFrom;
  finally
    fLock.Release;
  end;
end;

function TmaxCronEvent.GetValidTo: TDateTime;
begin
  fLock.Acquire;
  try
    Result := FValidTo;
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
begin
  Result := fInvokeMode;
  if Result <> TmaxCronInvokeMode.imDefault then
    Exit;
  if (fSharedState <> nil) and fSharedState.TryGetDefaultInvokeMode(Result) then
    Exit;
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

function TmaxCronEvent.GetMisfirePolicy: TmaxCronMisfirePolicy;
begin
  fLock.Acquire;
  try
    Result := fMisfirePolicy;
  finally
    fLock.Release;
  end;
end;

function TmaxCronEvent.TryReserveExecution: Boolean;
begin
  fLock.Acquire;
  try
    if fPendingDestroy then
      Exit(False);
    if not FEnabled then
      if TInterlocked.CompareExchange(fAllowDisabledDispatch, 0, 0) = 0 then
        Exit(False);
    if (fScheduler.ExecutionLimit <> 0) and (fNumOfDue >= fScheduler.ExecutionLimit) then
    begin
      FEnabled := False;
      Exit(False);
    end;

    Inc(fNumOfDue);
    Result := True;
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

procedure TmaxCronEvent.RollbackReservedExecution;
begin
  fLock.Acquire;
  try
    if fNumOfDue > 0 then
      Dec(fNumOfDue);
  finally
    fLock.Release;
  end;
end;

procedure TmaxCronEvent.HandleQueuedAcquireFailure(const aOverlapMode: TmaxCronOverlapMode);
begin
  RollbackReservedExecution;

  case aOverlapMode of
    TmaxCronOverlapMode.omSkipIfRunning:
      TInterlocked.Exchange(fRunning, 0);
    TmaxCronOverlapMode.omSerialize,
    TmaxCronOverlapMode.omSerializeCoalesce:
      begin
        TInterlocked.Exchange(fPendingRuns, 0);
        TInterlocked.Exchange(fRunning, 0);
      end;
  end;

  if fSharedState <> nil then
    fSharedState.FlushPendingFree;
end;

procedure TmaxCronEvent.RollbackDispatchStartFailure(const aOverlapMode: TmaxCronOverlapMode);
begin
  RollbackReservedExecution;

  case aOverlapMode of
    TmaxCronOverlapMode.omAllowOverlap:
      ReleaseExecution;
    TmaxCronOverlapMode.omSkipIfRunning:
      begin
        TInterlocked.Exchange(fRunning, 0);
        ReleaseExecution;
      end;
    TmaxCronOverlapMode.omSerialize,
    TmaxCronOverlapMode.omSerializeCoalesce:
      begin
        TInterlocked.Exchange(fRunning, 0);
        ReleaseExecution;
      end;
  end;

  if fSharedState <> nil then
    fSharedState.FlushPendingFree;
end;

procedure TmaxCronEvent.QueueMainThreadCallbacks(const aInvokeMode: TmaxCronInvokeMode;
  const aOnEvent: TmaxCronNotifyEvent; const aOnProc: TmaxCronNotifyProc;
  const aOverlapMode: TmaxCronOverlapMode);
var
  lToken: ICronEventToken;
begin
  if not Supports(fEventToken, ICronEventToken, lToken) then
  begin
    HandleQueuedAcquireFailure(aOverlapMode);
    Exit;
  end;

  try
    {$IFDEF ForceQueueNotAvailable}
    TThread.Queue(nil,
      procedure
      begin
        ExecuteQueuedMainThread(lToken, aInvokeMode, aOnEvent, aOnProc, aOverlapMode);
      end);
    {$ELSE}
    TThread.ForceQueue(nil,
      procedure
      begin
        ExecuteQueuedMainThread(lToken, aInvokeMode, aOnEvent, aOnProc, aOverlapMode);
      end);
    {$ENDIF}
  except
    HandleQueuedAcquireFailure(aOverlapMode);
    raise;
  end;
end;

procedure TmaxCronEvent.MarkPendingDestroy;
begin
  fLock.Acquire;
  try
    fPendingDestroy := True;
    FEnabled := False;
    fPendingRuns := 0;
    fPendingDstSecondSchedule := 0;
    ClearAmbiguousSecondGate;
    FOnScheduleEvent := nil;
    FOnScheduleProc := nil;
    FUserDataInterface := nil;
  finally
    fLock.Release;
  end;

  if fSharedState <> nil then
    fSharedState.MarkHeapDirty;
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

procedure TmaxCronEvent.FinalizeOverlap(const aInvokeMode: TmaxCronInvokeMode;
  const aOnEvent: TmaxCronNotifyEvent; const aOnProc: TmaxCronNotifyProc;
  const aOverlapMode: TmaxCronOverlapMode);
var
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
          try
            if (aInvokeMode = TmaxCronInvokeMode.imMainThread) and (TThread.CurrentThread.ThreadID = MainThreadID) then
            begin
              {$IFDEF ForceQueueNotAvailable}
              TThread.Queue(nil,
                procedure
                begin
                  try
                    DispatchCallbacks(aInvokeMode, aOnEvent, aOnProc, aOverlapMode);
                  except
                    RollbackDispatchStartFailure(aOverlapMode);
                    raise;
                  end;
                end);
              {$ELSE}
              TThread.ForceQueue(nil,
                procedure
                begin
                  try
                    DispatchCallbacks(aInvokeMode, aOnEvent, aOnProc, aOverlapMode);
                  except
                    RollbackDispatchStartFailure(aOverlapMode);
                    raise;
                  end;
                end);
              {$ENDIF}
            end else begin
              DispatchCallbacks(aInvokeMode, aOnEvent, aOnProc, aOverlapMode);
            end;
          except
            RollbackDispatchStartFailure(aOverlapMode);
            raise;
          end;
          Exit; // keep execution acquired for the serialized chain
        end;

        TInterlocked.Exchange(fRunning, 0);
        ReleaseExecution;
        Exit;
      end;
  end;

  if fSharedState <> nil then
    fSharedState.FlushPendingFree;
end;

procedure TmaxCronEvent.ExecuteOnce(const aInvokeMode: TmaxCronInvokeMode;
  const aOnEvent: TmaxCronNotifyEvent; const aOnProc: TmaxCronNotifyProc;
  const aOverlapMode: TmaxCronOverlapMode);
var
  lToken: ICronEventToken;
  lEvent: TmaxCronEvent;
  lOwnerPointer: Pointer;
  lPreviousCron: Pointer;
begin
  try
    lEvent := nil;

    if not Supports(fEventToken, ICronEventToken, lToken) then Exit;
    if not lToken.TryGetEvent(lEvent) then Exit;

    fLock.Acquire;
    try
      Inc(fNumOfExecutions);
    finally
      fLock.Release;
    end;

    if fSharedState <> nil then
      fSharedState.IncrementCallbackDepth;

    lOwnerPointer := nil;
    if fSharedState <> nil then
      fSharedState.TryGetOwnerPointer(lOwnerPointer);

    lPreviousCron := gMaxCronExecutingCron;
    gMaxCronExecutingCron := lOwnerPointer;
    try
      if Assigned(aOnEvent) then
        aOnEvent(lEvent);
      if Assigned(aOnProc) then
        aOnProc(lEvent);
    finally
      gMaxCronExecutingCron := lPreviousCron;
      if fSharedState <> nil then
        fSharedState.DecrementCallbackDepth;
    end;
  finally
    if (aOverlapMode = TmaxCronOverlapMode.omAllowOverlap) or (aOverlapMode = TmaxCronOverlapMode.omSkipIfRunning) then
      ReleaseExecution;
    FinalizeOverlap(aInvokeMode, aOnEvent, aOnProc, aOverlapMode);
  end;
end;

procedure ExecuteQueuedMainThread(const aToken: ICronEventToken;
  const aInvokeMode: TmaxCronInvokeMode; const aOnEvent: TmaxCronNotifyEvent;
  const aOnProc: TmaxCronNotifyProc; const aOverlapMode: TmaxCronOverlapMode);
var
  lEvent: TmaxCronEvent;
begin
  if aToken = nil then Exit;
  if not aToken.TryGetEvent(lEvent) then Exit;
  {$IFDEF MAXCRON_TESTS}
  if Assigned(gMaxCronBeforeQueuedAcquireHook) then
  begin
    try
      gMaxCronBeforeQueuedAcquireHook(lEvent);
    except
      if aToken.TryGetEvent(lEvent) and (lEvent <> nil) then
        lEvent.HandleQueuedAcquireFailure(aOverlapMode);
      Exit;
    end;
  end;
  {$ENDIF}
  if not aToken.TryAcquireEvent(lEvent) then
  begin
    if aToken.TryGetEvent(lEvent) and (lEvent <> nil) then
      lEvent.HandleQueuedAcquireFailure(aOverlapMode);
    Exit;
  end;

  lEvent.ExecuteOnce(aInvokeMode, aOnEvent, aOnProc, aOverlapMode);
end;

procedure TmaxCronEvent.DispatchCallbacks(const aInvokeMode: TmaxCronInvokeMode;
  const aOnEvent: TmaxCronNotifyEvent; const aOnProc: TmaxCronNotifyProc;
  const aOverlapMode: TmaxCronOverlapMode);
var
  lThread: TThread;
  lKeepAlive: IInterface;
  lKeepAliveEntry: IAsyncKeepAliveEntry;
  lAsync: IInterface;
begin
  if (not Assigned(aOnEvent)) and (not Assigned(aOnProc)) then Exit;
  {$IFDEF MAXCRON_TESTS}
  if Assigned(gMaxCronBeforeDispatchHook) then
    gMaxCronBeforeDispatchHook(aInvokeMode);
  {$ENDIF}

  case aInvokeMode of
    TmaxCronInvokeMode.imMainThread:
      begin
        // WARNING: imMainThread requires a running main-thread message pump (VCL context).
        // In non-UI/service hosts this queue path may never execute.
        if TThread.CurrentThread.ThreadID = MainThreadID then
          ExecuteOnce(aInvokeMode, aOnEvent, aOnProc, aOverlapMode)
        else
        begin
          {$IFDEF ForceQueueNotAvailable}
          TThread.Queue(nil, procedure begin ExecuteOnce(aInvokeMode, aOnEvent, aOnProc, aOverlapMode); end);
          {$ELSE}
          TThread.ForceQueue(nil, procedure begin ExecuteOnce(aInvokeMode, aOnEvent, aOnProc, aOverlapMode); end);
          {$ENDIF}
        end;
      end;

    TmaxCronInvokeMode.imThread:
      begin
        lThread := TThread.CreateAnonymousThread(
          procedure
          begin
            ExecuteOnce(aInvokeMode, aOnEvent, aOnProc, aOverlapMode);
          end);
        lThread.FreeOnTerminate := True;
        lThread.Start;
      end;

    TmaxCronInvokeMode.imTTask:
      begin
        TTask.Run(
          procedure
          begin
            ExecuteOnce(aInvokeMode, aOnEvent, aOnProc, aOverlapMode);
          end);
      end;

    TmaxCronInvokeMode.imMaxAsync:
      begin
        if (fSharedState = nil) or (not fSharedState.IsAlive) then
        begin
          DispatchCallbacks(TmaxCronInvokeMode.imTTask, aOnEvent, aOnProc, aOverlapMode);
          Exit;
        end;

        lKeepAliveEntry := TAsyncKeepAliveEntry.Create(fSharedState);
        lKeepAlive := lKeepAliveEntry as IInterface;
        fSharedState.KeepAsyncAlive(lKeepAlive);

        try
          lAsync := CallSimpleAsync(
            procedure
            begin
              try
                ExecuteOnce(aInvokeMode, aOnEvent, aOnProc, aOverlapMode);
              finally
                lKeepAliveEntry.MarkDone;
              end;
            end,
            '');
        except
          on E: Exception do
          begin
            lKeepAliveEntry.MarkDone;
            DispatchCallbacks(TmaxCronInvokeMode.imTTask, aOnEvent, aOnProc, aOverlapMode);
            Exit;
          end;
        end;

        if lAsync = nil then
        begin
          lKeepAliveEntry.MarkDone;
          DispatchCallbacks(TmaxCronInvokeMode.imTTask, aOnEvent, aOnProc, aOverlapMode);
          Exit;
        end;

        lKeepAliveEntry.AttachAsync(lAsync);
      end;
  else
    ExecuteOnce(aInvokeMode, aOnEvent, aOnProc, aOverlapMode);
  end;
end;

procedure TmaxCronEvent.DispatchScheduledCallbacks(const aInvokeMode: TmaxCronInvokeMode;
  const aOnEvent: TmaxCronNotifyEvent; const aOnProc: TmaxCronNotifyProc;
  const aOverlapMode: TmaxCronOverlapMode);
var
  lQueueMain: Boolean;
begin
  if (not Assigned(aOnEvent)) and (not Assigned(aOnProc)) then Exit;

  lQueueMain := (aInvokeMode = TmaxCronInvokeMode.imMainThread) and
    (TThread.CurrentThread.ThreadID <> MainThreadID);

  case aOverlapMode of
    TmaxCronOverlapMode.omAllowOverlap:
      begin
        if not TryReserveExecution then
          Exit;
        if lQueueMain then
        begin
          QueueMainThreadCallbacks(aInvokeMode, aOnEvent, aOnProc, aOverlapMode);
          Exit;
        end;
        if not TryAcquireExecution then Exit;
        try
          DispatchCallbacks(aInvokeMode, aOnEvent, aOnProc, aOverlapMode);
        except
          RollbackDispatchStartFailure(aOverlapMode);
          raise;
        end;
      end;
    TmaxCronOverlapMode.omSkipIfRunning:
      begin
        if TInterlocked.CompareExchange(fRunning, 1, 0) <> 0 then Exit;
        if not TryReserveExecution then
        begin
          TInterlocked.Exchange(fRunning, 0);
          Exit;
        end;
        if lQueueMain then
        begin
          QueueMainThreadCallbacks(aInvokeMode, aOnEvent, aOnProc, aOverlapMode);
          Exit;
        end;
        if not TryAcquireExecution then
        begin
          TInterlocked.Exchange(fRunning, 0);
          Exit;
        end;
        try
          DispatchCallbacks(aInvokeMode, aOnEvent, aOnProc, aOverlapMode);
        except
          RollbackDispatchStartFailure(aOverlapMode);
          raise;
        end;
      end;
    TmaxCronOverlapMode.omSerialize:
      begin
        if TInterlocked.CompareExchange(fRunning, 1, 0) = 0 then
        begin
          if not TryReserveExecution then
          begin
            TInterlocked.Exchange(fRunning, 0);
            Exit;
          end;
          if lQueueMain then
          begin
            QueueMainThreadCallbacks(aInvokeMode, aOnEvent, aOnProc, aOverlapMode);
            Exit;
          end;
          if not TryAcquireExecution then
          begin
            TInterlocked.Exchange(fRunning, 0);
            Exit;
          end;
          try
            DispatchCallbacks(aInvokeMode, aOnEvent, aOnProc, aOverlapMode);
          except
            RollbackDispatchStartFailure(aOverlapMode);
            raise;
          end;
        end else begin
          if not TryReserveExecution then
            Exit;
          TInterlocked.Increment(fPendingRuns);
        end;
      end;
    TmaxCronOverlapMode.omSerializeCoalesce:
      begin
        if TInterlocked.CompareExchange(fRunning, 1, 0) = 0 then
        begin
          if not TryReserveExecution then
          begin
            TInterlocked.Exchange(fRunning, 0);
            Exit;
          end;
          if lQueueMain then
          begin
            QueueMainThreadCallbacks(aInvokeMode, aOnEvent, aOnProc, aOverlapMode);
            Exit;
          end;
          if not TryAcquireExecution then
          begin
            TInterlocked.Exchange(fRunning, 0);
            Exit;
          end;
          try
            DispatchCallbacks(aInvokeMode, aOnEvent, aOnProc, aOverlapMode);
          except
            RollbackDispatchStartFailure(aOverlapMode);
            raise;
          end;
        end else begin
          if TInterlocked.CompareExchange(fPendingRuns, 1, 0) = 0 then
          begin
            if not TryReserveExecution then
            begin
              TInterlocked.Exchange(fPendingRuns, 0);
              Exit;
            end;
          end;
        end;
      end;
  end;
end;

procedure TmaxCronEvent.checkTimer(const aNow: TDateTime);
var
  lOnEvent: TmaxCronNotifyEvent;
  lOnProc: TmaxCronNotifyProc;
  lInvokeMode: TmaxCronInvokeMode;
  lOverlap: TmaxCronOverlapMode;
  lMisfire: TmaxCronMisfirePolicy;
  lFireAt: TDateTime;
  lHasCallbacks: Boolean;
  lCatchUpLimit: Cardinal;
  lCatchUpCount: Cardinal;
  lAllowDisabledDispatch: Boolean;
  lFindResult: TFindNextScheduleResult;
begin
  lOnEvent := nil;
  lOnProc := nil;
  lInvokeMode := TmaxCronInvokeMode.imMainThread;
  lOverlap := TmaxCronOverlapMode.omAllowOverlap;
  lMisfire := TmaxCronMisfirePolicy.mpDefault;
  lCatchUpLimit := 1;
  lFindResult := TFindNextScheduleResult.fnsNotFound;

  fLock.Acquire;
  try
    if not FEnabled then Exit;
    if fNextScheduleNeedsResolve then
    begin
      if aNow < fNextSchedule then Exit;
      lFindResult := FindNextScheduleWithPolicies(aNow, fNextSchedule);
      case lFindResult of
        TFindNextScheduleResult.fnsFound:
          fNextScheduleNeedsResolve := False;
        TFindNextScheduleResult.fnsNotFound:
          begin
            fNextScheduleNeedsResolve := False;
            FEnabled := False;
          end;
        TFindNextScheduleResult.fnsSearchLimitReached:
          fNextScheduleNeedsResolve := True;
      end;
      Exit;
    end;
    if not ProcessAmbiguousSecondGate(aNow) then Exit;
    if aNow < fNextSchedule then Exit;

    if fScheduler.ExecutionLimit <> 0 then
      if fNumOfDue >= fScheduler.ExecutionLimit then
      begin
        FEnabled := False;
        Exit;
      end;

    lOnEvent := FOnScheduleEvent;
    lOnProc := FOnScheduleProc;
    lInvokeMode := fInvokeMode;
    lOverlap := fOverlapMode;
    lMisfire := fMisfirePolicy;
  finally
    fLock.Release;
  end;

  lHasCallbacks := Assigned(lOnEvent) or Assigned(lOnProc);

  if lInvokeMode = TmaxCronInvokeMode.imDefault then
  begin
    if (fSharedState = nil) or (not fSharedState.TryGetDefaultInvokeMode(lInvokeMode)) then
      lInvokeMode := TmaxCronInvokeMode.imMainThread;
  end;

  if lMisfire = TmaxCronMisfirePolicy.mpDefault then
  begin
    if (fSharedState = nil) or (not fSharedState.TryGetMisfireDefaults(lMisfire, lCatchUpLimit)) then
    begin
      lMisfire := TmaxCronMisfirePolicy.mpCatchUpAll;
      lCatchUpLimit := 1;
    end
  end;

  if lMisfire <> TmaxCronMisfirePolicy.mpCatchUpAll then
    lCatchUpLimit := 1
  else if lCatchUpLimit = 0 then
    lCatchUpLimit := 1;

  lCatchUpCount := 0;
  while True do
  begin
    lAllowDisabledDispatch := False;
    fLock.Acquire;
    try
      if not FEnabled then Exit;
      if fNextScheduleNeedsResolve then
      begin
        if aNow < fNextSchedule then Exit;
        lFindResult := FindNextScheduleWithPolicies(aNow, fNextSchedule);
        case lFindResult of
          TFindNextScheduleResult.fnsFound:
            fNextScheduleNeedsResolve := False;
          TFindNextScheduleResult.fnsNotFound:
            begin
              fNextScheduleNeedsResolve := False;
              FEnabled := False;
            end;
          TFindNextScheduleResult.fnsSearchLimitReached:
            fNextScheduleNeedsResolve := True;
        end;
        Exit;
      end;
      if not ProcessAmbiguousSecondGate(aNow) then Exit;
      if aNow < fNextSchedule then Exit;

      if fScheduler.ExecutionLimit <> 0 then
        if fNumOfDue >= fScheduler.ExecutionLimit then
        begin
          FEnabled := False;
          Exit;
        end;

      case lMisfire of
        TmaxCronMisfirePolicy.mpSkip:
          begin
            lFindResult := FindNextScheduleWithPolicies(aNow, fNextSchedule);
            case lFindResult of
              TFindNextScheduleResult.fnsFound:
                fNextScheduleNeedsResolve := False;
              TFindNextScheduleResult.fnsNotFound:
                begin
                  fNextScheduleNeedsResolve := False;
                  FEnabled := False;
                end;
              TFindNextScheduleResult.fnsSearchLimitReached:
                fNextScheduleNeedsResolve := True;
            end;
            Exit;
          end;
        TmaxCronMisfirePolicy.mpFireOnceNow:
          begin
            lFireAt := fNextSchedule;
            fLastExecutionTime := lFireAt;
            if FEnabled then
            begin
              lFindResult := FindNextScheduleWithPolicies(aNow, fNextSchedule);
              case lFindResult of
                TFindNextScheduleResult.fnsFound:
                  fNextScheduleNeedsResolve := False;
                TFindNextScheduleResult.fnsNotFound:
                  begin
                    fNextScheduleNeedsResolve := False;
                    FEnabled := False;
                    lAllowDisabledDispatch := True;
                  end;
                TFindNextScheduleResult.fnsSearchLimitReached:
                  fNextScheduleNeedsResolve := True;
              end;
            end;
          end;
      else
        begin
          lFireAt := fNextSchedule;
          fLastExecutionTime := lFireAt;
          if FEnabled then
          begin
            lFindResult := FindNextScheduleWithPolicies(fLastExecutionTime, fNextSchedule);
            case lFindResult of
              TFindNextScheduleResult.fnsFound:
                fNextScheduleNeedsResolve := False;
              TFindNextScheduleResult.fnsNotFound:
                begin
                  fNextScheduleNeedsResolve := False;
                  FEnabled := False;
                  lAllowDisabledDispatch := True;
                end;
              TFindNextScheduleResult.fnsSearchLimitReached:
                fNextScheduleNeedsResolve := True;
            end;
          end;
        end;
      end;
    finally
      fLock.Release;
    end;

    if not lHasCallbacks then
      Exit;

    if lAllowDisabledDispatch then
      TInterlocked.Exchange(fAllowDisabledDispatch, 1);
    try
      DispatchScheduledCallbacks(lInvokeMode, lOnEvent, lOnProc, lOverlap);
    finally
      if lAllowDisabledDispatch then
        TInterlocked.Exchange(fAllowDisabledDispatch, 0);
    end;

    Inc(lCatchUpCount);
    if lMisfire <> TmaxCronMisfirePolicy.mpCatchUpAll then
      Exit;
    if lCatchUpCount >= lCatchUpLimit then
      Exit;
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

var
  lYear: string;
begin
  case fDialect of
    cdStandard:
      Result :=
        process(Minute) + sep +
        process(Hour) + sep +
        process(DayOfTheMonth) + sep +
        process(Month) + sep +
        process(DayOfTheWeek);
    cdQuartzSecondsFirst:
      begin
        lYear := Trim(Year);
        Result :=
          process(Second, '0') + sep +
          process(Minute) + sep +
          process(Hour) + sep +
          process(DayOfTheMonth) + sep +
          process(Month) + sep +
          process(DayOfTheWeek);
        if (lYear <> '') and (lYear <> '*') then
          Result := Result + sep + lYear;
      end;
  else
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
end;

procedure TPlan.reset;
begin
  fDialect := cdMaxCron;
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
  lDialect: TmaxCronDialect;
begin
  lDialect := fDialect;
  reset;
  fDialect := lDialect;

  s := StripCronComment(Value);
  s := NormalizeCommaWhitespace(s);
  s := Trim(s);
  if s = '' then
  begin
    case fDialect of
      cdStandard:
        raise Exception.Create('Cron plan must have exactly 5 fields');
      cdQuartzSecondsFirst:
        raise Exception.Create('Cron plan must have 6 or 7 fields');
    else
      raise Exception.Create('Cron plan must have at least 5 fields');
    end;
  end;
  if s[1] = '@' then
  begin
    if not TryApplyCronMacro(s, Self) then
      raise Exception.Create('Unknown cron macro');
    Exit;
  end;

  l := TStringList.Create;
  try
    SplitByWhitespace(s, l);

    case fDialect of
      cdStandard:
        if l.Count <> 5 then
          raise Exception.Create('Cron plan must have exactly 5 fields');
      cdQuartzSecondsFirst:
        if (l.Count < 6) or (l.Count > 7) then
          raise Exception.Create('Cron plan must have 6 or 7 fields');
    else
      begin
        if l.Count < 5 then
          raise Exception.Create('Cron plan must have at least 5 fields');
        if l.Count > Length(parts) then
          raise Exception.Create('Cron plan has too many fields');
      end;
    end;

    for x := 0 to l.Count - 1 do
      if (Length(l[x]) > 0) and ((l[x][1] = ',') or (l[x][Length(l[x])] = ',') or (Pos(',,', l[x]) > 0)) then
        raise Exception.Create('Invalid cron token');

    case fDialect of
      cdStandard:
        begin
          Minute := l[0];
          Hour := l[1];
          DayOfTheMonth := l[2];
          Month := l[3];
          DayOfTheWeek := l[4];
        end;
      cdQuartzSecondsFirst:
        begin
          Second := l[0];
          Minute := l[1];
          Hour := l[2];
          DayOfTheMonth := l[3];
          Month := l[4];
          DayOfTheWeek := l[5];
          if l.Count > 6 then
            Year := l[6];
        end;
    else
      for x := 0 to Min(Length(parts), l.Count) - 1 do
        parts[x] := l[x];
    end;
  finally
    l.Free;
  end;

end;

end.

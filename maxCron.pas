unit maxCron;
{$I maxCron.inc}
{

  Version: 2.3
 NOTE:
}

interface


uses
  System.Classes, System.Generics.Collections, System.SyncObjs, System.SysUtils,
  maxCron.Internal.Platform, maxCron.Plan;

type
  TmaxCronDayMatchMode = maxCron.Plan.TmaxCronDayMatchMode;
  TmaxCronDialect = maxCron.Plan.TmaxCronDialect;
  TDates = maxCron.Plan.TDates;
  TWordArray = maxCron.Plan.TWordArray;
  TPartKind = maxCron.Plan.TPartKind;
  TCronDomModifier = maxCron.Plan.TCronDomModifier;
  TCronDowModifier = maxCron.Plan.TCronDowModifier;
  TPlan = maxCron.Plan.TPlan;
  TCronPart = maxCron.Plan.TCronPart;
  TCronSchedulePlan = maxCron.Plan.TCronSchedulePlan;

const
  dmDefault = maxCron.Plan.dmDefault;
  dmAnd = maxCron.Plan.dmAnd;
  dmOr = maxCron.Plan.dmOr;
  cdStandard = maxCron.Plan.cdStandard;
  cdMaxCron = maxCron.Plan.cdMaxCron;
  cdQuartzSecondsFirst = maxCron.Plan.cdQuartzSecondsFirst;
  ckMinute = maxCron.Plan.ckMinute;
  ckHour = maxCron.Plan.ckHour;
  ckDayOfTheMonth = maxCron.Plan.ckDayOfTheMonth;
  ckMonth = maxCron.Plan.ckMonth;
  ckDayOfTheWeek = maxCron.Plan.ckDayOfTheWeek;
  ckYear = maxCron.Plan.ckYear;
  ckSecond = maxCron.Plan.ckSecond;
  cdmNone = maxCron.Plan.cdmNone;
  cdmLastDay = maxCron.Plan.cdmLastDay;
  cdmNearestWeekday = maxCron.Plan.cdmNearestWeekday;
  cdmLastWeekday = maxCron.Plan.cdmLastWeekday;
  cdwNone = maxCron.Plan.cdwNone;
  cdwLastWeekday = maxCron.Plan.cdwLastWeekday;
  cdwNthWeekday = maxCron.Plan.cdwNthWeekday;

type
  // forward declarations
  TmaxCron = class;
  IMaxCronEvent = interface;

  TmaxCronNotifyEvent = procedure(Sender: IMaxCronEvent) of object;
  TmaxCronNotifyProc = reference to procedure(Sender: IMaxCronEvent);
  TmaxCronDeadLetterEvent = procedure(Sender: IMaxCronEvent; const aErrorText: string;
    const aAttemptCount: Integer) of object;
  TmaxCronDeadLetterProc = reference to procedure(Sender: IMaxCronEvent; const aErrorText: string;
    const aAttemptCount: Integer);

  TmaxCronShutdownPolicy = (spWait, spCancel, spForce);

  TmaxCronInvokeMode = (
    imDefault,    // use scheduler DefaultInvokeMode
    imMainThread, // execute on VCL main thread (ForceQueue/Queue when needed)
    imMaxAsync,   // execute via the internal async dispatcher
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

  TmaxCronTimerBackend = (ctAuto, ctVcl, ctPortable);

  TFindNextScheduleResult = (fnsFound, fnsNotFound, fnsSearchLimitReached);

  TMaxCronPersistedEvent = record
    Name: string;
    EventPlan: string;
    Enabled: Boolean;
    InvokeMode: TmaxCronInvokeMode;
    OverlapMode: TmaxCronOverlapMode;
    DayMatchMode: TmaxCronDayMatchMode;
    Dialect: TmaxCronDialect;
    MisfirePolicy: TmaxCronMisfirePolicy;
    TimeZoneId: string;
    DstSpringPolicy: TmaxCronDstSpringPolicy;
    DstFallPolicy: TmaxCronDstFallPolicy;
    WeekdaysOnly: Boolean;
    ExcludedDatesCsv: string;
    BlackoutStartTime: TDateTime;
    BlackoutEndTime: TDateTime;
    ValidFrom: TDateTime;
    ValidTo: TDateTime;
    Tag: Integer;
    NumOfExecutionsPerformed: UInt64;
    LastExecution: TDateTime;
    NextSchedule: TDateTime;
    NextScheduleNeedsResolve: Boolean;
    RetryMaxAttempts: Integer;
    RetryInitialDelayMs: Cardinal;
    RetryBackoffMultiplier: Double;
    RetryMaxDelayMs: Cardinal;
  end;

  IMaxCronScheduleStore = interface
    ['{502728E8-EFA0-4FE3-AC8D-2F3C7BF8B2D8}']
    procedure Save(const aEvents: TArray<TMaxCronPersistedEvent>);
    function TryLoad(out aEvents: TArray<TMaxCronPersistedEvent>): Boolean;
  end;

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
    function GetRetryMaxAttempts: Integer;
    procedure SetRetryMaxAttempts(const aValue: Integer);
    function GetRetryInitialDelayMs: Cardinal;
    procedure SetRetryInitialDelayMs(const aValue: Cardinal);
    function GetRetryBackoffMultiplier: Double;
    procedure SetRetryBackoffMultiplier(const aValue: Double);
    function GetRetryMaxDelayMs: Cardinal;
    procedure SetRetryMaxDelayMs(const aValue: Cardinal);
    function GetOnDeadLetterEvent: TmaxCronDeadLetterEvent;
    procedure SetOnDeadLetterEvent(const aValue: TmaxCronDeadLetterEvent);
    function GetOnDeadLetterProc: TmaxCronDeadLetterProc;
    procedure SetOnDeadLetterProc(const aValue: TmaxCronDeadLetterProc);
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
    property RetryMaxAttempts: Integer read GetRetryMaxAttempts write SetRetryMaxAttempts;
    property RetryInitialDelayMs: Cardinal read GetRetryInitialDelayMs write SetRetryInitialDelayMs;
    property RetryBackoffMultiplier: Double read GetRetryBackoffMultiplier write SetRetryBackoffMultiplier;
    property RetryMaxDelayMs: Cardinal read GetRetryMaxDelayMs write SetRetryMaxDelayMs;
    property OnDeadLetterEvent: TmaxCronDeadLetterEvent read GetOnDeadLetterEvent write SetOnDeadLetterEvent;
    property OnDeadLetterProc: TmaxCronDeadLetterProc read GetOnDeadLetterProc write SetOnDeadLetterProc;
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

  TMaxCronWatchdogDiagnostics = record
    TickLagMs: Cardinal;
    QueueDepth: Integer;
    InFlightCallbacks: Integer;
    SwitchChurn: Integer;
    LastTickElapsedUs: Int64;
    MaxTickLagMs: Cardinal;
    MaxQueueDepth: Integer;
    MaxInFlightCallbacks: Integer;
    MaxSwitchChurn: Integer;
    TickLagBreached: Boolean;
    QueueDepthBreached: Boolean;
    InFlightCallbacksBreached: Boolean;
    SwitchChurnBreached: Boolean;
    AnyThresholdBreached: Boolean;
  end;

  TMaxCronMetricsSnapshot = record
    CapturedAtUtc: TDateTime;
    ConfiguredEngine: string;
    EffectiveEngine: string;
    AutoState: string;
    AutoSwitchCount: UInt64;
    TickEventsVisited: UInt64;
    HeapRebuildCount: UInt64;
    Watchdog: TMaxCronWatchdogDiagnostics;
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
        DueAtUnits: Int64;
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
    fDefaultsLock: TCriticalSection;
    fUsePooledThreadDispatch: Boolean;
    fTimer: ICronTickSource;
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
    fWatchdogLock: TCriticalSection;
    fWatchdogMaxTickLagMs: Cardinal;
    fWatchdogMaxQueueDepth: Integer;
    fWatchdogMaxInFlightCallbacks: Integer;
    fWatchdogMaxSwitchChurn: Integer;
    fWatchdogSwitchWindowTicks: Integer;
    fWatchdogTickLagMs: Cardinal;
    fWatchdogLastTickElapsedUs: Int64;
    fGlobalDispatchLock: TCriticalSection;
    fGlobalMaxConcurrentCallbacks: Integer;
    fGlobalMaxDispatchPerSecond: Integer;
    fGlobalActiveCallbacks: Integer;
    fGlobalRateWindowStartTick: UInt64;
    fGlobalRateWindowDispatches: Integer;
    fShutdownRequested: Integer;
    fItemsLock: TCriticalSection;
    fPendingFree: TList<IMaxCronEvent>;
    fNextId: Int64;
    fTickDepth: Integer;
    fTickQueued: Integer;
    fSharedState: IInterface;
    fScheduleStore: IMaxCronScheduleStore;
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
    procedure ConfigureWatchdogSettings;
    procedure ConfigureAutoControllerSettings;
    function ClampAutoInt(const aValue, aMin, aMax: Integer): Integer;
    function ClampAutoFloat(const aValue, aMin, aMax: Double): Double;
    function TryReadAutoIntEnv(const aEnvName: string; out aValue: Integer): Boolean;
    function TryReadAutoFloatEnv(const aEnvName: string; out aValue: Double): Boolean;
    procedure MarkHeapDirty;
    function SchedulerEngineToText(const aEngine: TSchedulerEngine): string;
    function AutoStateToText(const aState: TAutoSchedulerState): string;
    function UpdateEwma(const aCurrent, aSample, aAlpha: Double): Double;
    function IsShutdownRequested: Boolean;
    function HasDispatchLimits: Boolean;
    function TryAcquireDispatchPermit(const aTimeoutMs: Cardinal): Boolean;
    procedure ReleaseDispatchPermit;
    function GetWatchdogSwitchChurn: Integer;
    procedure UpdateWatchdogAfterTick(const aTickNow, aWallNow: TDateTime; const aElapsedMicroseconds: Int64);
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
    function GetScheduleStore: IMaxCronScheduleStore;
    procedure SetScheduleStore(const aStore: IMaxCronScheduleStore);
    function GetGlobalMaxConcurrentCallbacks: Integer;
    procedure SetGlobalMaxConcurrentCallbacks(const aValue: Integer);
    function GetGlobalMaxDispatchPerSecond: Integer;
    procedure SetGlobalMaxDispatchPerSecond(const aValue: Integer);

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
    function TryGetWatchdogDiagnostics(out aDiagnostics: TMaxCronWatchdogDiagnostics): Boolean;
    function GetMetricsSnapshot: TMaxCronMetricsSnapshot;
    function SaveScheduleState: Integer;
    function RestoreScheduleState(const aReplaceExisting: Boolean = True): Integer;
    function Shutdown(const aTimeoutMs: Cardinal; const aPolicy: TmaxCronShutdownPolicy = spWait): Boolean;

    property RequestedTimerBackend: TmaxCronTimerBackend read fRequestedTimerBackend;
    property ActiveTimerBackend: TmaxCronTimerBackend read fActiveTimerBackend;
    property DefaultInvokeMode: TmaxCronInvokeMode read fDefaultInvokeMode write SetDefaultInvokeMode;
    property DefaultDayMatchMode: TmaxCronDayMatchMode read fDefaultDayMatchMode write SetDefaultDayMatchMode;
    property DefaultDialect: TmaxCronDialect read fDefaultDialect write SetDefaultDialect;
    property DefaultMisfirePolicy: TmaxCronMisfirePolicy read fDefaultMisfirePolicy write SetDefaultMisfirePolicy;
    property DefaultMisfireCatchUpLimit: Cardinal read fDefaultMisfireCatchUpLimit write SetDefaultMisfireCatchUpLimit;
    property ScheduleStore: IMaxCronScheduleStore read GetScheduleStore write SetScheduleStore;
    property GlobalMaxConcurrentCallbacks: Integer read GetGlobalMaxConcurrentCallbacks
      write SetGlobalMaxConcurrentCallbacks;
    property GlobalMaxDispatchPerSecond: Integer read GetGlobalMaxDispatchPerSecond
      write SetGlobalMaxDispatchPerSecond;

    {$IFDEF MAXCRON_TESTS}
    procedure TickAt(const aNow: TDateTime);
    procedure StartTimerForTests(const aIntervalMs: Cardinal);
    procedure ResetTickMetricsForTests;
    procedure GetTickMetricsForTests(out aEventsVisited: UInt64; out aHeapRebuilds: UInt64);
    procedure GetEngineStateForTests(out aConfiguredEngine: string; out aEffectiveEngine: string;
      out aAutoState: string; out aSwitchCount: UInt64);
    {$ENDIF}
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
  maxCron.Internal.TimeZone;

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
    procedure Attach(const aOwner: TmaxCron);
    procedure MarkHeapDirty;
    procedure KeepAsyncAlive(const aAsync: IInterface);
    procedure ReleaseAsyncAlive(const aAsync: IInterface);
    procedure FlushPendingFree;
    procedure ExecuteQueuedTick;
    procedure ResetTickQueued;
    function ShouldUsePooledThreadDispatch: Boolean;
    function HasDispatchLimits: Boolean;
    function AcquireDispatchPermit(const aTimeoutMs: Cardinal): Boolean;
    procedure ReleaseDispatchPermit;
    function IsShutdownRequested: Boolean;
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
    procedure Attach(const aOwner: TmaxCron);
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
    function ShouldUsePooledThreadDispatch: Boolean;
    function HasDispatchLimits: Boolean;
    function AcquireDispatchPermit(const aTimeoutMs: Cardinal): Boolean;
    procedure ReleaseDispatchPermit;
    function IsShutdownRequested: Boolean;
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
    FOnDeadLetterEvent: TmaxCronDeadLetterEvent;
    FOnDeadLetterProc: TmaxCronDeadLetterProc;
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
    fRetryMaxAttempts: Integer;
    fRetryInitialDelayMs: Cardinal;
    fRetryBackoffMultiplier: Double;
    fRetryMaxDelayMs: Cardinal;
    fSystemTimeZone: ICronTimeZone;
    fTimeZoneId: string;
    fTimeZoneKind: TCronTimeZoneKind;
    fTimeZoneOffsetMinutes: Integer;
    fTimeZoneOffsetDayFraction: Double;
    fUtcToLocalCacheHourKey: Int64;
    fUtcToLocalCacheOffsetDays: Double;
    fUtcToLocalCacheStable: Boolean;
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
    function GetOnDeadLetterEvent: TmaxCronDeadLetterEvent;
    function GetOnDeadLetterProc: TmaxCronDeadLetterProc;
    function GetInvokeMode: TmaxCronInvokeMode;
    function GetDialect: TmaxCronDialect;
    function GetRetryMaxAttempts: Integer;
    function GetRetryInitialDelayMs: Cardinal;
    function GetRetryBackoffMultiplier: Double;
    function GetRetryMaxDelayMs: Cardinal;
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
    procedure SetOnDeadLetterEvent(const Value: TmaxCronDeadLetterEvent);
    procedure SetTag(const Value: Integer);
    procedure SetUserData(const Value: Pointer);
    procedure SetEventPlan(const Value: string);
    procedure SetEnabled(const Value: Boolean);
    procedure SetValidFrom(const Value: TDateTime);
    procedure SetValidTo(const Value: TDateTime);
    procedure SetUserDataInterface(const Value: IInterface);
    procedure SetOnScheduleProc(const Value: TmaxCronNotifyProc);
    procedure SetOnDeadLetterProc(const Value: TmaxCronDeadLetterProc);
    procedure SetInvokeMode(const Value: TmaxCronInvokeMode);
    procedure SetOverlapMode(const Value: TmaxCronOverlapMode);
    procedure SetDayMatchMode(const Value: TmaxCronDayMatchMode);
    procedure SetDialect(const Value: TmaxCronDialect);
    procedure SetMisfirePolicy(const Value: TmaxCronMisfirePolicy);
    procedure SetRetryMaxAttempts(const Value: Integer);
    procedure SetRetryInitialDelayMs(const Value: Cardinal);
    procedure SetRetryBackoffMultiplier(const Value: Double);
    procedure SetRetryMaxDelayMs(const Value: Cardinal);
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
    function FindNextScheduleWithPolicies(const aBaseSystemLocal: TDateTime; out aNextSystemLocal: TDateTime): TFindNextScheduleResult;
    function SystemLocalToEventLocal(const aSystemLocal: TDateTime): TDateTime;
    function EventLocalToSystemLocal(const aEventLocal: TDateTime; out aSystemLocal: TDateTime): Boolean;
    function TryGetStableLocalOffsetForUtc(const aUtc: TDateTime; out aOffsetDays: Double): Boolean;
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
    property OnDeadLetterEvent: TmaxCronDeadLetterEvent read GetOnDeadLetterEvent write SetOnDeadLetterEvent;
    property OnDeadLetterProc: TmaxCronDeadLetterProc read GetOnDeadLetterProc write SetOnDeadLetterProc;
    property Enabled: Boolean read GetEnabled write SetEnabled;
    property InvokeMode: TmaxCronInvokeMode read fInvokeMode write SetInvokeMode;
    property OverlapMode: TmaxCronOverlapMode read GetOverlapMode write SetOverlapMode;
    property DayMatchMode: TmaxCronDayMatchMode read GetDayMatchMode write SetDayMatchMode;
    property Dialect: TmaxCronDialect read fDialect write SetDialect;
    property MisfirePolicy: TmaxCronMisfirePolicy read GetMisfirePolicy write SetMisfirePolicy;
    property RetryMaxAttempts: Integer read GetRetryMaxAttempts write SetRetryMaxAttempts;
    property RetryInitialDelayMs: Cardinal read GetRetryInitialDelayMs write SetRetryInitialDelayMs;
    property RetryBackoffMultiplier: Double read GetRetryBackoffMultiplier write SetRetryBackoffMultiplier;
    property RetryMaxDelayMs: Cardinal read GetRetryMaxDelayMs write SetRetryMaxDelayMs;
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
  cTickUnitsPerDay = 24.0 * 60.0 * 60.0 * 1000.0;

function DateTimeToTickUnits(const aValue: TDateTime): Int64;
var
  lScaled: Double;
begin
  lScaled := aValue * cTickUnitsPerDay;
  if IsNan(lScaled) then
    Exit(0);
  if lScaled > High(Int64) then
    Exit(High(Int64));
  if lScaled < Low(Int64) then
    Exit(Low(Int64));
  Result := Round(lScaled);
end;

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

function CallSimpleAsync(const aProc: TThreadProcedure; const aTaskName: string): IInterface;
begin
  {$IFDEF MAXCRON_TESTS}
  if Assigned(gMaxCronAsyncCallHook) then
    Exit(gMaxCronAsyncCallHook(aProc, aTaskName));
  {$ENDIF}
  Result := CronMaxAsyncCall(aProc, aTaskName);
end;

{ TScheduledEvent }

constructor TmaxCronEvent.Create;
begin
  inherited;
  fSystemTimeZone := CronSystemTimeZone;
  fLock := TCriticalSection.Create;
  fEventToken := TCronEventToken.Create(Self);
  fId := 0;
  fInvokeMode := TmaxCronInvokeMode.imDefault;
  fOverlapMode := TmaxCronOverlapMode.omAllowOverlap;
  fDayMatchMode := TmaxCronDayMatchMode.dmDefault;
  fDialect := cdMaxCron;
  fMisfirePolicy := TmaxCronMisfirePolicy.mpDefault;
  fRetryMaxAttempts := 0;
  fRetryInitialDelayMs := 0;
  fRetryBackoffMultiplier := 2.0;
  fRetryMaxDelayMs := 30000;
  fTimeZoneId := 'LOCAL';
  fTimeZoneKind := TCronTimeZoneKind.ctzLocal;
  fTimeZoneOffsetMinutes := 0;
  fTimeZoneOffsetDayFraction := 0;
  fUtcToLocalCacheHourKey := Low(Int64);
  fUtcToLocalCacheOffsetDays := 0;
  fUtcToLocalCacheStable := False;
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

procedure TmaxCronEvent.SetOnDeadLetterEvent(const Value: TmaxCronDeadLetterEvent);
begin
  fLock.Acquire;
  try
    FOnDeadLetterEvent := Value;
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
  lDefaultDayMatchMode: TmaxCronDayMatchMode;
  lDefaultDialect: TmaxCronDialect;
begin
  lNormalizedName := NormalizeEventName(aName);
  Result := nil;
  if IsShutdownRequested then
    raise Exception.Create('Scheduler is shut down');

  fDefaultsLock.Acquire;
  try
    lDefaultDayMatchMode := fDefaultDayMatchMode;
    lDefaultDialect := fDefaultDialect;
  finally
    fDefaultsLock.Release;
  end;

  fItemsLock.Acquire;
  try
    if (lNormalizedName <> '') and (FindIndexByNameLocked(lNormalizedName) >= 0) then
      raise Exception.CreateFmt('Event name "%s" already exists', [lNormalizedName]);

    lEvent := TmaxCronEvent.Create;
    lEventInterface := lEvent as IMaxCronEvent;
    if Supports(fSharedState, ICronSharedState, lSharedState) then
      lEvent.fSharedState := lSharedState;
    lEvent.fScheduler.DayMatchMode := lDefaultDayMatchMode;
    lEvent.fDialect := lDefaultDialect;
    lEvent.fScheduler.Dialect := lDefaultDialect;
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

procedure TCronSharedState.Attach(const aOwner: TmaxCron);
begin
  fLock.Acquire;
  try
    fOwner := aOwner;
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
  aInvokeMode := TmaxCronInvokeMode.imMainThread;
  if not TryAcquireOwner(lOwner) then
    Exit(False);
  try
    lOwner.fDefaultsLock.Acquire;
    try
      aInvokeMode := lOwner.fDefaultInvokeMode;
    finally
      lOwner.fDefaultsLock.Release;
    end;
    Result := True;
  finally
    ReleaseOwner;
  end;
end;

function TCronSharedState.TryGetDefaultDayMatchMode(out aDayMatchMode: TmaxCronDayMatchMode): Boolean;
var
  lOwner: TmaxCron;
begin
  aDayMatchMode := TmaxCronDayMatchMode.dmAnd;
  if not TryAcquireOwner(lOwner) then
    Exit(False);
  try
    lOwner.fDefaultsLock.Acquire;
    try
      aDayMatchMode := lOwner.fDefaultDayMatchMode;
    finally
      lOwner.fDefaultsLock.Release;
    end;
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
  aMisfirePolicy := TmaxCronMisfirePolicy.mpCatchUpAll;
  aCatchUpLimit := 1;
  if not TryAcquireOwner(lOwner) then
    Exit(False);
  try
    lOwner.fDefaultsLock.Acquire;
    try
      aMisfirePolicy := lOwner.fDefaultMisfirePolicy;
      aCatchUpLimit := lOwner.fDefaultMisfireCatchUpLimit;
    finally
      lOwner.fDefaultsLock.Release;
    end;
    Result := True;
  finally
    ReleaseOwner;
  end;
end;

function TCronSharedState.TryGetOwnerPointer(out aOwnerPointer: Pointer): Boolean;
var
  lOwner: TmaxCron;
begin
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

function TCronSharedState.ShouldUsePooledThreadDispatch: Boolean;
var
  lOwner: TmaxCron;
begin
  Result := False;
  if not TryAcquireOwner(lOwner) then
    Exit;
  try
    Result := lOwner.fUsePooledThreadDispatch;
  finally
    ReleaseOwner;
  end;
end;

function TCronSharedState.HasDispatchLimits: Boolean;
var
  lOwner: TmaxCron;
begin
  Result := False;
  if not TryAcquireOwner(lOwner) then
    Exit;
  try
    Result := lOwner.HasDispatchLimits;
  finally
    ReleaseOwner;
  end;
end;

function TCronSharedState.AcquireDispatchPermit(const aTimeoutMs: Cardinal): Boolean;
var
  lOwner: TmaxCron;
begin
  Result := False;
  if not TryAcquireOwner(lOwner) then
    Exit;
  try
    Result := lOwner.TryAcquireDispatchPermit(aTimeoutMs);
  finally
    ReleaseOwner;
  end;
end;

procedure TCronSharedState.ReleaseDispatchPermit;
var
  lOwner: TmaxCron;
begin
  if not TryAcquireOwner(lOwner) then
    Exit;
  try
    lOwner.ReleaseDispatchPermit;
  finally
    ReleaseOwner;
  end;
end;

function TCronSharedState.IsShutdownRequested: Boolean;
var
  lOwner: TmaxCron;
begin
  Result := True;
  if not TryAcquireOwner(lOwner) then
    Exit;
  try
    Result := lOwner.IsShutdownRequested;
  finally
    ReleaseOwner;
  end;
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
var
  lIntValue: Integer;
begin
  inherited Create;

  fItems := TList<IMaxCronEvent>.Create;
  fItemsById := TDictionary<Int64, Integer>.Create;
  fItemsByName := TDictionary<string, Integer>.Create;
  fHeapItems := TList<TCronHeapEntry>.Create;
  fAutoSwitchHistory := TQueue<UInt64>.Create;
  fAutoLock := TCriticalSection.Create;
  fWatchdogLock := TCriticalSection.Create;
  fGlobalDispatchLock := TCriticalSection.Create;
  fItemsLock := TCriticalSection.Create;
  fDefaultsLock := TCriticalSection.Create;
  fPendingFree := TList<IMaxCronEvent>.Create;
  fNextId := 0;
  fTickDepth := 0;
  fDefaultInvokeMode := TmaxCronInvokeMode.imMainThread;
  fDefaultDayMatchMode := TmaxCronDayMatchMode.dmAnd;
  fDefaultDialect := cdMaxCron;
  fDefaultMisfirePolicy := TmaxCronMisfirePolicy.mpCatchUpAll;
  fDefaultMisfireCatchUpLimit := 1;
  fUsePooledThreadDispatch := SameText(Trim(CronGetEnvironmentVariable('MAXCRON_THREAD_DISPATCH_POOL')), '1') or
    SameText(Trim(CronGetEnvironmentVariable('MAXCRON_THREAD_DISPATCH_POOL')), 'true');
  fGlobalMaxConcurrentCallbacks := 0;
  fGlobalMaxDispatchPerSecond := 0;
  fGlobalActiveCallbacks := 0;
  fGlobalRateWindowStartTick := 0;
  fGlobalRateWindowDispatches := 0;
  fShutdownRequested := 0;
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
  fWatchdogTickLagMs := 0;
  fWatchdogLastTickElapsedUs := 0;
  fWatchdogMaxTickLagMs := 2500;
  fWatchdogMaxQueueDepth := 1;
  fWatchdogMaxInFlightCallbacks := 128;
  fWatchdogMaxSwitchChurn := 8;
  fWatchdogSwitchWindowTicks := 256;
  if TryReadAutoIntEnv('MAXCRON_GLOBAL_MAX_CONCURRENT', lIntValue) then
    fGlobalMaxConcurrentCallbacks := ClampAutoInt(lIntValue, 0, High(Integer));
  if TryReadAutoIntEnv('MAXCRON_GLOBAL_MAX_DISPATCH_PER_SECOND', lIntValue) then
    fGlobalMaxDispatchPerSecond := ClampAutoInt(lIntValue, 0, High(Integer));
  ConfigureWatchdogSettings;
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
  lText := Trim(CronGetEnvironmentVariable(aEnvName));
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
  lText := Trim(CronGetEnvironmentVariable(aEnvName));
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

procedure TmaxCron.ConfigureWatchdogSettings;
const
  cDefaultMaxTickLagMs = 2500;
  cDefaultMaxQueueDepth = 1;
  cDefaultMaxInFlightCallbacks = 128;
  cDefaultMaxSwitchChurn = 8;
  cDefaultSwitchWindowTicks = 256;
var
  lIntValue: Integer;
begin
  fWatchdogMaxTickLagMs := cDefaultMaxTickLagMs;
  fWatchdogMaxQueueDepth := cDefaultMaxQueueDepth;
  fWatchdogMaxInFlightCallbacks := cDefaultMaxInFlightCallbacks;
  fWatchdogMaxSwitchChurn := cDefaultMaxSwitchChurn;
  fWatchdogSwitchWindowTicks := cDefaultSwitchWindowTicks;

  if TryReadAutoIntEnv('MAXCRON_WATCHDOG_MAX_TICK_LAG_MS', lIntValue) then
    fWatchdogMaxTickLagMs := Cardinal(ClampAutoInt(lIntValue, 0, High(Integer)));
  if TryReadAutoIntEnv('MAXCRON_WATCHDOG_MAX_QUEUE_DEPTH', lIntValue) then
    fWatchdogMaxQueueDepth := ClampAutoInt(lIntValue, 0, High(Integer));
  if TryReadAutoIntEnv('MAXCRON_WATCHDOG_MAX_INFLIGHT', lIntValue) then
    fWatchdogMaxInFlightCallbacks := ClampAutoInt(lIntValue, 0, High(Integer));
  if TryReadAutoIntEnv('MAXCRON_WATCHDOG_MAX_SWITCH_CHURN', lIntValue) then
    fWatchdogMaxSwitchChurn := ClampAutoInt(lIntValue, 0, High(Integer));
  if TryReadAutoIntEnv('MAXCRON_WATCHDOG_SWITCH_WINDOW', lIntValue) then
    fWatchdogSwitchWindowTicks := ClampAutoInt(lIntValue, 1, High(Integer));
end;

procedure TmaxCron.ConfigureSchedulerEngine;
var
  lValue: string;
begin
  ConfigureAutoControllerSettings;

  lValue := LowerCase(Trim(CronGetEnvironmentVariable('MAXCRON_ENGINE')));
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

function TmaxCron.IsShutdownRequested: Boolean;
begin
  Result := TInterlocked.CompareExchange(fShutdownRequested, 0, 0) <> 0;
end;

function TmaxCron.HasDispatchLimits: Boolean;
begin
  Result := (fGlobalMaxConcurrentCallbacks > 0) or (fGlobalMaxDispatchPerSecond > 0);
end;

function TmaxCron.TryAcquireDispatchPermit(const aTimeoutMs: Cardinal): Boolean;
var
  lStartTick: UInt64;
  lNowTick: UInt64;
  lElapsedTick: UInt64;
  lRemainingTick: UInt64;
  lWindowElapsed: UInt64;
  lWaitMs: Cardinal;
begin
  Result := False;
  if IsShutdownRequested then
    Exit;
  if not HasDispatchLimits then
    Exit(True);

  lStartTick := TThread.GetTickCount64;
  while True do
  begin
    if IsShutdownRequested then
      Exit(False);

    fGlobalDispatchLock.Acquire;
    try
      lNowTick := TThread.GetTickCount64;
      if fGlobalMaxDispatchPerSecond > 0 then
      begin
        lWindowElapsed := lNowTick - fGlobalRateWindowStartTick;
        if (fGlobalRateWindowStartTick = 0) or (lWindowElapsed >= 1000) then
        begin
          fGlobalRateWindowStartTick := lNowTick;
          fGlobalRateWindowDispatches := 0;
        end;
      end;

      if (fGlobalMaxConcurrentCallbacks > 0) and
        (fGlobalActiveCallbacks >= fGlobalMaxConcurrentCallbacks) then
        lWaitMs := 1
      else if (fGlobalMaxDispatchPerSecond > 0) and
        (fGlobalRateWindowDispatches >= fGlobalMaxDispatchPerSecond) then
      begin
        lWindowElapsed := lNowTick - fGlobalRateWindowStartTick;
        if lWindowElapsed >= 1000 then
        begin
          fGlobalRateWindowStartTick := lNowTick;
          fGlobalRateWindowDispatches := 0;
          lWaitMs := 0;
        end else
          lWaitMs := Cardinal(1000 - lWindowElapsed);
      end else
        lWaitMs := 0;

      if lWaitMs = 0 then
      begin
        Inc(fGlobalActiveCallbacks);
        if fGlobalMaxDispatchPerSecond > 0 then
          Inc(fGlobalRateWindowDispatches);
        Exit(True);
      end;
    finally
      fGlobalDispatchLock.Release;
    end;

    if aTimeoutMs <> High(Cardinal) then
    begin
      lNowTick := TThread.GetTickCount64;
      lElapsedTick := lNowTick - lStartTick;
      if lElapsedTick >= UInt64(aTimeoutMs) then
        Exit(False);
      lRemainingTick := UInt64(aTimeoutMs) - lElapsedTick;
      if UInt64(lWaitMs) > lRemainingTick then
        lWaitMs := Cardinal(lRemainingTick);
    end;

    if lWaitMs = 0 then
      lWaitMs := 1;
    TThread.Sleep(lWaitMs);
  end;
end;

procedure TmaxCron.ReleaseDispatchPermit;
begin
  fGlobalDispatchLock.Acquire;
  try
    if fGlobalActiveCallbacks > 0 then
      Dec(fGlobalActiveCallbacks);
  finally
    fGlobalDispatchLock.Release;
  end;
end;

function TmaxCron.GetWatchdogSwitchChurn: Integer;
var
  lWindowTicks: Integer;
begin
  Result := 0;
  if fSchedulerEngine <> TSchedulerEngine.seAuto then
    Exit;

  lWindowTicks := fWatchdogSwitchWindowTicks;
  if lWindowTicks < 1 then
    lWindowTicks := 1;

  fAutoLock.Acquire;
  try
    PruneAutoSwitchHistoryLocked(fAutoControllerTick, lWindowTicks);
    Result := fAutoSwitchHistory.Count;
  finally
    fAutoLock.Release;
  end;
end;

procedure TmaxCron.UpdateWatchdogAfterTick(const aTickNow, aWallNow: TDateTime;
  const aElapsedMicroseconds: Int64);
var
  lLagMs: Cardinal;
  lLagMsFloat: Double;
  lElapsedUs: Int64;
begin
  lLagMs := 0;
  if aTickNow < aWallNow then
  begin
    lLagMsFloat := (aWallNow - aTickNow) * 24.0 * 60.0 * 60.0 * 1000.0;
    if lLagMsFloat > High(Cardinal) then
      lLagMs := High(Cardinal)
    else if lLagMsFloat > 0 then
      lLagMs := Round(lLagMsFloat);
  end;

  lElapsedUs := aElapsedMicroseconds;
  if lElapsedUs < 0 then
    lElapsedUs := 0;

  fWatchdogLock.Acquire;
  try
    fWatchdogTickLagMs := lLagMs;
    fWatchdogLastTickElapsedUs := lElapsedUs;
  finally
    fWatchdogLock.Release;
  end;
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
        CronDebugOutput(lLogLine);
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
var
  lMode: TmaxCronInvokeMode;
begin
  if aValue = TmaxCronInvokeMode.imDefault then
    lMode := TmaxCronInvokeMode.imMainThread
  else
    lMode := aValue;

  fDefaultsLock.Acquire;
  try
    fDefaultInvokeMode := lMode;
  finally
    fDefaultsLock.Release;
  end;
end;

procedure TmaxCron.SetDefaultDayMatchMode(const Value: TmaxCronDayMatchMode);
var
  x: Integer;
  lEvent: IMaxCronEvent;
  lMode: TmaxCronDayMatchMode;
begin
  if Value = TmaxCronDayMatchMode.dmDefault then
    lMode := TmaxCronDayMatchMode.dmAnd
  else
    lMode := Value;

  fDefaultsLock.Acquire;
  try
    fDefaultDayMatchMode := lMode;
  finally
    fDefaultsLock.Release;
  end;

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
  fDefaultsLock.Acquire;
  try
    fDefaultDialect := Value;
  finally
    fDefaultsLock.Release;
  end;
end;

procedure TmaxCron.SetDefaultMisfirePolicy(const aValue: TmaxCronMisfirePolicy);
var
  lPolicy: TmaxCronMisfirePolicy;
begin
  if aValue = TmaxCronMisfirePolicy.mpDefault then
    lPolicy := TmaxCronMisfirePolicy.mpCatchUpAll
  else
    lPolicy := aValue;

  fDefaultsLock.Acquire;
  try
    fDefaultMisfirePolicy := lPolicy;
  finally
    fDefaultsLock.Release;
  end;
end;

procedure TmaxCron.SetDefaultMisfireCatchUpLimit(const Value: Cardinal);
var
  lLimit: Cardinal;
begin
  if Value = 0 then
    lLimit := 1
  else
    lLimit := Value;

  fDefaultsLock.Acquire;
  try
    fDefaultMisfireCatchUpLimit := lLimit;
  finally
    fDefaultsLock.Release;
  end;
end;

function TmaxCron.GetScheduleStore: IMaxCronScheduleStore;
begin
  fDefaultsLock.Acquire;
  try
    Result := fScheduleStore;
  finally
    fDefaultsLock.Release;
  end;
end;

procedure TmaxCron.SetScheduleStore(const aStore: IMaxCronScheduleStore);
begin
  fDefaultsLock.Acquire;
  try
    fScheduleStore := aStore;
  finally
    fDefaultsLock.Release;
  end;
end;

function TmaxCron.GetGlobalMaxConcurrentCallbacks: Integer;
begin
  fGlobalDispatchLock.Acquire;
  try
    Result := fGlobalMaxConcurrentCallbacks;
  finally
    fGlobalDispatchLock.Release;
  end;
end;

procedure TmaxCron.SetGlobalMaxConcurrentCallbacks(const aValue: Integer);
begin
  fGlobalDispatchLock.Acquire;
  try
    if aValue < 0 then
      fGlobalMaxConcurrentCallbacks := 0
    else
      fGlobalMaxConcurrentCallbacks := aValue;
  finally
    fGlobalDispatchLock.Release;
  end;
end;

function TmaxCron.GetGlobalMaxDispatchPerSecond: Integer;
begin
  fGlobalDispatchLock.Acquire;
  try
    Result := fGlobalMaxDispatchPerSecond;
  finally
    fGlobalDispatchLock.Release;
  end;
end;

procedure TmaxCron.SetGlobalMaxDispatchPerSecond(const aValue: Integer);
begin
  fGlobalDispatchLock.Acquire;
  try
    if aValue < 0 then
      fGlobalMaxDispatchPerSecond := 0
    else
      fGlobalMaxDispatchPerSecond := aValue;
    fGlobalRateWindowStartTick := 0;
    fGlobalRateWindowDispatches := 0;
  finally
    fGlobalDispatchLock.Release;
  end;
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
  lCronEvent: TmaxCronEvent;
begin
  aEventItem := nil;
  lIndex := FindIndexByIdLocked(aId);
  if lIndex < 0 then
    Exit(False);

  aEventItem := fItems[lIndex];
  if aEventItem = nil then
    Exit(False);

  if TryGetCronEvent(aEventItem, lCronEvent) then
  begin
    if lCronEvent.fId <> aId then
    begin
      aEventItem := nil;
      Exit(False);
    end;
    Exit(True);
  end;

  if aEventItem.Id <> aId then
  begin
    aEventItem := nil;
    Exit(False);
  end;

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
  if aLeft.DueAtUnits < aRight.DueAtUnits then
    Exit(True);
  if aLeft.DueAtUnits > aRight.DueAtUnits then
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
  lEntry.DueAtUnits := DateTimeToTickUnits(aDueAt);
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
    begin
      lEntry.DueAtUnits := DateTimeToTickUnits(lEntry.DueAt);
      fHeapItems.Add(lEntry);
    end;
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
  lNowUnits: Int64;
  lEvent: TmaxCronEvent;
  lId: Int64;
  lDueAt: TDateTime;
begin
  aIds.Clear;
  lNowUnits := DateTimeToTickUnits(aNow);
  for lIndex := 0 to fItems.Count - 1 do
  begin
    if not TryGetCronEvent(fItems[lIndex], lEvent) then
      Continue;
    if lEvent.TryGetHeapScheduleSnapshot(lId, lDueAt) and (DateTimeToTickUnits(lDueAt) <= lNowUnits) then
      aIds.Add(lId);
  end;
  aIds.Sort;
end;

procedure TmaxCron.CollectHeapDueIdsLocked(const aNow: TDateTime; const aIds: TList<Int64>);
var
  lIndex: Integer;
  lNowUnits: Int64;
  lEntry: TCronHeapEntry;
  lEventItem: IMaxCronEvent;
  lEvent: TmaxCronEvent;
begin
  aIds.Clear;
  lNowUnits := DateTimeToTickUnits(aNow);
  for lIndex := 0 to fHeapItems.Count - 1 do
  begin
    lEntry := fHeapItems[lIndex];
    if lEntry.DueAtUnits > lNowUnits then
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
      fTimer := CreateCronTickSource(TCronTickSourceKind.tskMainThread);
    TmaxCronTimerBackend.ctPortable:
      fTimer := CreateCronTickSource(TCronTickSourceKind.tskWorkerThread);
  else
    fTimer := CreateCronTickSource(TCronTickSourceKind.tskMainThread);
    fActiveTimerBackend := TmaxCronTimerBackend.ctVcl;
  end;

  fTimer.SetOnTick(TimerTimer);
  {$IFNDEF MAXCRON_TESTS}
  fTimer.Start(1000);
  {$ENDIF}
end;

function TmaxCron.Delete(const aId: Int64): boolean;
var
  lIndex: Integer;
  lEvent: IMaxCronEvent;
begin
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
  lDetachedSharedState: Boolean;
  lWait: TStopwatch;
begin
  lSharedState := nil;
  Supports(fSharedState, ICronSharedState, lSharedState);

  if (fActiveTimerBackend = TmaxCronTimerBackend.ctVcl) and
    (TThread.CurrentThread.ThreadID <> MainThreadID) then
    raise Exception.Create('TmaxCron.Free for ctVcl backend must be called on the main thread');

  if Pointer(Self) = gMaxCronExecutingCron then
    raise Exception.Create('TmaxCron.Free cannot be called from one of its own callbacks');

  TInterlocked.Exchange(fShutdownRequested, 1);

  if lSharedState <> nil then
  begin
    lSharedState.Detach;
    lDetachedSharedState := True;
    try
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
    except
      if lDetachedSharedState then
      begin
        lSharedState.Attach(Self);
      end;
      TInterlocked.Exchange(fShutdownRequested, 0);
      raise;
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
  fWatchdogLock.Free;
  fGlobalDispatchLock.Free;
  fPendingFree.Free;
  fItemsLock.Free;
  fDefaultsLock.Free;
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

function TmaxCron.SaveScheduleState: Integer;
var
  lStore: IMaxCronScheduleStore;
  lSnapshot: TArray<IMaxCronEvent>;
  lStates: TArray<TMaxCronPersistedEvent>;
  lState: TMaxCronPersistedEvent;
  lEvent: IMaxCronEvent;
  lCronEvent: TmaxCronEvent;
  lCount: Integer;
  lIndex: Integer;
begin
  Result := 0;
  lStore := GetScheduleStore;
  if lStore = nil then
    Exit;

  lSnapshot := Snapshot;
  SetLength(lStates, Length(lSnapshot));
  lCount := 0;
  for lIndex := 0 to Length(lSnapshot) - 1 do
  begin
    lEvent := lSnapshot[lIndex];
    if lEvent = nil then
      Continue;

    lState := Default(TMaxCronPersistedEvent);
    lState.Name := lEvent.Name;
    lState.EventPlan := lEvent.EventPlan;
    lState.Enabled := lEvent.Enabled;
    lState.InvokeMode := lEvent.InvokeMode;
    lState.OverlapMode := lEvent.OverlapMode;
    lState.DayMatchMode := lEvent.DayMatchMode;
    lState.Dialect := lEvent.Dialect;
    lState.MisfirePolicy := lEvent.MisfirePolicy;
    lState.TimeZoneId := lEvent.TimeZoneId;
    lState.DstSpringPolicy := lEvent.DstSpringPolicy;
    lState.DstFallPolicy := lEvent.DstFallPolicy;
    lState.WeekdaysOnly := lEvent.WeekdaysOnly;
    lState.ExcludedDatesCsv := lEvent.ExcludedDatesCsv;
    lState.BlackoutStartTime := lEvent.BlackoutStartTime;
    lState.BlackoutEndTime := lEvent.BlackoutEndTime;
    lState.ValidFrom := lEvent.ValidFrom;
    lState.ValidTo := lEvent.ValidTo;
    lState.Tag := lEvent.Tag;
    lState.NumOfExecutionsPerformed := lEvent.NumOfExecutionsPerformed;
    lState.LastExecution := lEvent.LastExecution;
    lState.NextSchedule := lEvent.NextSchedule;
    lState.RetryMaxAttempts := lEvent.RetryMaxAttempts;
    lState.RetryInitialDelayMs := lEvent.RetryInitialDelayMs;
    lState.RetryBackoffMultiplier := lEvent.RetryBackoffMultiplier;
    lState.RetryMaxDelayMs := lEvent.RetryMaxDelayMs;
    if TryGetCronEvent(lEvent, lCronEvent) then
    begin
      lCronEvent.fLock.Acquire;
      try
        lState.NextScheduleNeedsResolve := lCronEvent.fNextScheduleNeedsResolve;
      finally
        lCronEvent.fLock.Release;
      end;
    end;

    lStates[lCount] := lState;
    Inc(lCount);
  end;

  SetLength(lStates, lCount);
  lStore.Save(lStates);
  Result := lCount;
end;

function TmaxCron.RestoreScheduleState(const aReplaceExisting: Boolean): Integer;
var
  lStore: IMaxCronScheduleStore;
  lStates: TArray<TMaxCronPersistedEvent>;
  lState: TMaxCronPersistedEvent;
  lEvent: IMaxCronEvent;
  lCronEvent: TmaxCronEvent;
  lIndex: Integer;
begin
  Result := 0;
  lStore := GetScheduleStore;
  if lStore = nil then
    Exit;
  if not lStore.TryLoad(lStates) then
    Exit;

  if aReplaceExisting then
    Clear;

  for lIndex := 0 to Length(lStates) - 1 do
  begin
    lState := lStates[lIndex];
    if Trim(lState.Name) = '' then
      Continue;

    lEvent := Add(lState.Name);
    lEvent.InvokeMode := lState.InvokeMode;
    lEvent.OverlapMode := lState.OverlapMode;
    lEvent.DayMatchMode := lState.DayMatchMode;
    lEvent.Dialect := lState.Dialect;
    lEvent.MisfirePolicy := lState.MisfirePolicy;
    lEvent.RetryMaxAttempts := lState.RetryMaxAttempts;
    lEvent.RetryInitialDelayMs := lState.RetryInitialDelayMs;
    lEvent.RetryBackoffMultiplier := lState.RetryBackoffMultiplier;
    lEvent.RetryMaxDelayMs := lState.RetryMaxDelayMs;
    lEvent.TimeZoneId := lState.TimeZoneId;
    lEvent.DstSpringPolicy := lState.DstSpringPolicy;
    lEvent.DstFallPolicy := lState.DstFallPolicy;
    lEvent.WeekdaysOnly := lState.WeekdaysOnly;
    lEvent.ExcludedDatesCsv := lState.ExcludedDatesCsv;
    lEvent.BlackoutStartTime := lState.BlackoutStartTime;
    lEvent.BlackoutEndTime := lState.BlackoutEndTime;
    lEvent.ValidFrom := lState.ValidFrom;
    lEvent.ValidTo := lState.ValidTo;
    lEvent.Tag := lState.Tag;
    if Trim(lState.EventPlan) <> '' then
      lEvent.EventPlan := lState.EventPlan;

    if lState.Enabled then
    begin
      lEvent.Run;
      if TryGetCronEvent(lEvent, lCronEvent) then
      begin
        lCronEvent.fLock.Acquire;
        try
          lCronEvent.fNumOfExecutions := lState.NumOfExecutionsPerformed;
          lCronEvent.fNumOfDue := lState.NumOfExecutionsPerformed;
          lCronEvent.fLastExecutionTime := lState.LastExecution;
          if lState.NextSchedule > 0 then
            lCronEvent.fNextSchedule := lState.NextSchedule;
          lCronEvent.fNextScheduleNeedsResolve := lState.NextScheduleNeedsResolve;
        finally
          lCronEvent.fLock.Release;
        end;
      end;
    end else
      lEvent.Stop;

    Inc(Result);
  end;
end;

function TmaxCron.Shutdown(const aTimeoutMs: Cardinal; const aPolicy: TmaxCronShutdownPolicy): Boolean;
var
  lSharedState: ICronSharedState;
  lWait: TStopwatch;
begin
  TInterlocked.Exchange(fShutdownRequested, 1);
  if fTimer <> nil then
    fTimer.Stop;

  if (aPolicy = TmaxCronShutdownPolicy.spCancel) or (aPolicy = TmaxCronShutdownPolicy.spForce) then
    Clear;

  if not Supports(fSharedState, ICronSharedState, lSharedState) then
    Exit(True);

  if aPolicy = TmaxCronShutdownPolicy.spForce then
    Exit((lSharedState.GetInFlightCount = 0) and (lSharedState.GetCallbackDepth = 0));

  lWait := TStopwatch.StartNew;
  while (lSharedState.GetInFlightCount > 0) or (lSharedState.GetCallbackDepth > 0) do
  begin
    if lWait.ElapsedMilliseconds >= aTimeoutMs then
      Exit(False);
    if TThread.CurrentThread.ThreadID = MainThreadID then
      CheckSynchronize(1)
    else
      TThread.Sleep(1);
  end;

  Result := True;
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

function TmaxCron.TryGetWatchdogDiagnostics(out aDiagnostics: TMaxCronWatchdogDiagnostics): Boolean;
var
  lSharedState: ICronSharedState;
begin
  aDiagnostics := Default(TMaxCronWatchdogDiagnostics);

  fWatchdogLock.Acquire;
  try
    aDiagnostics.TickLagMs := fWatchdogTickLagMs;
    aDiagnostics.LastTickElapsedUs := fWatchdogLastTickElapsedUs;
    aDiagnostics.MaxTickLagMs := fWatchdogMaxTickLagMs;
    aDiagnostics.MaxQueueDepth := fWatchdogMaxQueueDepth;
    aDiagnostics.MaxInFlightCallbacks := fWatchdogMaxInFlightCallbacks;
    aDiagnostics.MaxSwitchChurn := fWatchdogMaxSwitchChurn;
  finally
    fWatchdogLock.Release;
  end;

  aDiagnostics.QueueDepth := TInterlocked.CompareExchange(fTickQueued, 0, 0);
  if Supports(fSharedState, ICronSharedState, lSharedState) then
    aDiagnostics.InFlightCallbacks := lSharedState.GetCallbackDepth
  else
    aDiagnostics.InFlightCallbacks := 0;
  aDiagnostics.SwitchChurn := GetWatchdogSwitchChurn;

  aDiagnostics.TickLagBreached := aDiagnostics.TickLagMs > aDiagnostics.MaxTickLagMs;
  aDiagnostics.QueueDepthBreached := aDiagnostics.QueueDepth > aDiagnostics.MaxQueueDepth;
  aDiagnostics.InFlightCallbacksBreached := aDiagnostics.InFlightCallbacks > aDiagnostics.MaxInFlightCallbacks;
  aDiagnostics.SwitchChurnBreached := aDiagnostics.SwitchChurn > aDiagnostics.MaxSwitchChurn;
  aDiagnostics.AnyThresholdBreached :=
    aDiagnostics.TickLagBreached or
    aDiagnostics.QueueDepthBreached or
    aDiagnostics.InFlightCallbacksBreached or
    aDiagnostics.SwitchChurnBreached;

  Result := True;
end;

function TmaxCron.GetMetricsSnapshot: TMaxCronMetricsSnapshot;
var
  lAutoDiagnostics: TMaxCronAutoDiagnostics;
begin
  Result := Default(TMaxCronMetricsSnapshot);
  Result.CapturedAtUtc := CronSystemTimeZone.ToUniversalTime(Now, False);
  Result.ConfiguredEngine := SchedulerEngineToText(fSchedulerEngine);
  Result.EffectiveEngine := Result.ConfiguredEngine;
  Result.AutoState := AutoStateToText(TAutoSchedulerState.asDisabled);

  if TryGetAutoDiagnostics(lAutoDiagnostics) then
  begin
    Result.EffectiveEngine := lAutoDiagnostics.EffectiveEngine;
    Result.AutoState := lAutoDiagnostics.AutoState;
    Result.AutoSwitchCount := lAutoDiagnostics.SwitchCount;
  end;

  fItemsLock.Acquire;
  try
    Result.TickEventsVisited := fTickEventsVisited;
    Result.HeapRebuildCount := fHeapRebuildCount;
  finally
    fItemsLock.Release;
  end;

  TryGetWatchdogDiagnostics(Result.Watchdog);
end;

procedure TmaxCron.DoTick;
var
  lNow: TDateTime;
begin
  if IsShutdownRequested then
    Exit;
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
  lWallNow: TDateTime;
begin
  if IsShutdownRequested then
    Exit;

  lDueCount := 0;
  lEventCount := 0;
  lWallNow := Now;

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
  end else
    lEngineUsed := fSchedulerEngine;

  lStartTicks := TStopwatch.GetTimeStamp;

  case fSchedulerEngine of
    TSchedulerEngine.seHeap:
      DoTickAtHeap(aNow, lDueCount);
    TSchedulerEngine.seShadow:
      begin
        ValidateShadowParity(aNow);
        DoTickAtHeap(aNow, lDueCount);
        lEngineUsed := TSchedulerEngine.seHeap;
      end;
    TSchedulerEngine.seAuto:
      case lEngineUsed of
        TSchedulerEngine.seHeap:
          DoTickAtHeap(aNow, lDueCount);
      else
        DoTickAtScan(aNow, lDueCount);
      end;
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

  UpdateWatchdogAfterTick(aNow, lWallNow, lElapsedMicroseconds);

  if fSchedulerEngine = TSchedulerEngine.seAuto then
    EvaluateAutoController(lEngineUsed, lEventCount, lDueCount, lElapsedMicroseconds);
end;

procedure TmaxCron.DoTickAtScan(const aNow: TDateTime; out aDueCount: Integer);
var
  x: Integer;
  lSnapshot: TArray<IMaxCronEvent>;
  lDepthIncreased: Boolean;
  lDueAtUnits: Int64;
  lEvent: TmaxCronEvent;
  lId: Int64;
  lDueAt: TDateTime;
  lNowUnits: Int64;
begin
  aDueCount := 0;
  lDepthIncreased := False;
  lNowUnits := DateTimeToTickUnits(aNow);
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
        if lEvent.TryGetHeapScheduleSnapshot(lId, lDueAt) then
        begin
          lDueAtUnits := DateTimeToTickUnits(lDueAt);
          if lDueAtUnits <= lNowUnits then
            Inc(aDueCount);
        end;
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
type
  THeapRescheduleEntry = record
    Event: TmaxCronEvent;
    EventId: Int64;
    DueAt: TDateTime;
  end;
var
  lDepthIncreased: Boolean;
  lDueEvents: TArray<TmaxCronEvent>;
  lDueEventCount: Integer;
  lReschedules: TArray<THeapRescheduleEntry>;
  lRescheduleCount: Integer;
  lEntry: TCronHeapEntry;
  lRescheduleEntry: THeapRescheduleEntry;
  lEventItem: IMaxCronEvent;
  lEvent: TmaxCronEvent;
  lDueEvent: TmaxCronEvent;
  lIndex: Integer;
  lId: Int64;
  lDueAt: TDateTime;
  lCurrentLength: Integer;
  lNowUnits: Int64;

  procedure EnsureDueEventsCapacity;
  begin
    if lDueEventCount < Length(lDueEvents) then
      Exit;

    lCurrentLength := Length(lDueEvents);
    if lCurrentLength = 0 then
      SetLength(lDueEvents, 16)
    else
      SetLength(lDueEvents, lCurrentLength * 2);
  end;

  procedure EnsureReschedulesCapacity;
  begin
    if lRescheduleCount < Length(lReschedules) then
      Exit;

    lCurrentLength := Length(lReschedules);
    if lCurrentLength = 0 then
      SetLength(lReschedules, 16)
    else
      SetLength(lReschedules, lCurrentLength * 2);
  end;
begin
  aDueCount := 0;
  lDepthIncreased := False;
  lDueEventCount := 0;
  lRescheduleCount := 0;
  lNowUnits := DateTimeToTickUnits(aNow);
  try
    fItemsLock.Acquire;
    try
      Inc(fTickDepth);
      lDepthIncreased := True;
      if TInterlocked.Exchange(fHeapDirty, 0) = 1 then
        RebuildHeapLocked;

      while HeapPeekLocked(lEntry) and (lEntry.DueAtUnits <= lNowUnits) do
      begin
        HeapPopLocked(lEntry);
        Inc(fTickEventsVisited);
        if not TryGetEventByIdLocked(lEntry.EventId, lEventItem) then
          Continue;
        if not TryGetCronEvent(lEventItem, lEvent) then
          Continue;
        if not lEvent.IsHeapScheduleCurrent(lEntry.DueAt) then
          Continue;
        EnsureDueEventsCapacity;
        lDueEvents[lDueEventCount] := lEvent;
        Inc(lDueEventCount);
      end;
    finally
      fItemsLock.Release;
    end;

    for lIndex := 0 to lDueEventCount - 1 do
    begin
      Inc(aDueCount);
      lDueEvent := lDueEvents[lIndex];
      lDueEvent.checkTimer(aNow);
      if not lDueEvent.TryGetHeapScheduleSnapshot(lId, lDueAt) then
        Continue;

      lRescheduleEntry.Event := lDueEvent;
      lRescheduleEntry.EventId := lId;
      lRescheduleEntry.DueAt := lDueAt;
      EnsureReschedulesCapacity;
      lReschedules[lRescheduleCount] := lRescheduleEntry;
      Inc(lRescheduleCount);
    end;

    if lRescheduleCount > 0 then
    begin
      fItemsLock.Acquire;
      try
        for lIndex := 0 to lRescheduleCount - 1 do
        begin
          lRescheduleEntry := lReschedules[lIndex];
          lEvent := lRescheduleEntry.Event;
          if lEvent = nil then
            Continue;
          if lEvent.IsHeapScheduleCurrent(lRescheduleEntry.DueAt) then
            HeapPushLocked(lRescheduleEntry.DueAt, lRescheduleEntry.EventId);
        end;
      finally
        fItemsLock.Release;
      end;
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
  if IsShutdownRequested then
    Exit;

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
  if IsShutdownRequested then
    Exit;

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

procedure TmaxCronEvent.SetOnDeadLetterProc(const Value: TmaxCronDeadLetterProc);
begin
  fLock.Acquire;
  try
    FOnDeadLetterProc := Value;
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

procedure TmaxCronEvent.SetRetryMaxAttempts(const Value: Integer);
begin
  fLock.Acquire;
  try
    if Value < 0 then
      fRetryMaxAttempts := 0
    else if Value > 1024 then
      fRetryMaxAttempts := 1024
    else
      fRetryMaxAttempts := Value;
  finally
    fLock.Release;
  end;
end;

procedure TmaxCronEvent.SetRetryInitialDelayMs(const Value: Cardinal);
begin
  fLock.Acquire;
  try
    fRetryInitialDelayMs := Value;
  finally
    fLock.Release;
  end;
end;

procedure TmaxCronEvent.SetRetryBackoffMultiplier(const Value: Double);
begin
  fLock.Acquire;
  try
    if Value < 1.0 then
      fRetryBackoffMultiplier := 1.0
    else if Value > 16.0 then
      fRetryBackoffMultiplier := 16.0
    else
      fRetryBackoffMultiplier := Value;
  finally
    fLock.Release;
  end;
end;

procedure TmaxCronEvent.SetRetryMaxDelayMs(const Value: Cardinal);
begin
  fLock.Acquire;
  try
    fRetryMaxDelayMs := Value;
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
  if (fTimeZoneKind = TCronTimeZoneKind.ctzLocal) and fSystemTimeZone.IsAmbiguousTime(aSchedule) then
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
    if (aNow > fNextSchedule) and (not fSystemTimeZone.IsAmbiguousTime(aNow)) then
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

    if (aNow > fNextSchedule) and (not fSystemTimeZone.IsAmbiguousTime(aNow)) then
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
    fTimeZoneOffsetDayFraction := lOffsetMinutes / (24 * 60);
    fUtcToLocalCacheHourKey := Low(Int64);
    fUtcToLocalCacheOffsetDays := 0;
    fUtcToLocalCacheStable := False;
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

function TmaxCronEvent.TryGetStableLocalOffsetForUtc(const aUtc: TDateTime; out aOffsetDays: Double): Boolean;
var
  lHourKey: Int64;
  lHourStartUtc: TDateTime;
  lHourEndUtc: TDateTime;
  lStartOffsetDays: Double;
  lEndOffsetDays: Double;
begin
  Result := False;
  aOffsetDays := 0;
  lHourKey := Trunc(aUtc * 24.0);

  if fUtcToLocalCacheStable and (fUtcToLocalCacheHourKey = lHourKey) then
  begin
    aOffsetDays := fUtcToLocalCacheOffsetDays;
    Exit(True);
  end;

  lHourStartUtc := lHourKey / 24.0;
  lHourEndUtc := lHourStartUtc + OneHour - OneSecond;
  lStartOffsetDays := fSystemTimeZone.ToLocalTime(lHourStartUtc) - lHourStartUtc;
  lEndOffsetDays := fSystemTimeZone.ToLocalTime(lHourEndUtc) - lHourEndUtc;

  fUtcToLocalCacheHourKey := lHourKey;
  if Abs(lStartOffsetDays - lEndOffsetDays) <= (1 / cTickUnitsPerDay) then
  begin
    fUtcToLocalCacheOffsetDays := lStartOffsetDays;
    fUtcToLocalCacheStable := True;
    aOffsetDays := lStartOffsetDays;
    Result := True;
  end else begin
    fUtcToLocalCacheStable := False;
  end;
end;

function TmaxCronEvent.SystemLocalToEventLocal(const aSystemLocal: TDateTime): TDateTime;
var
  lUtc: TDateTime;
begin
  case fTimeZoneKind of
    TCronTimeZoneKind.ctzLocal:
      Result := aSystemLocal;
    TCronTimeZoneKind.ctzUtc:
      Result := fSystemTimeZone.ToUniversalTime(aSystemLocal, False);
    TCronTimeZoneKind.ctzFixedOffset:
      begin
        lUtc := fSystemTimeZone.ToUniversalTime(aSystemLocal, False);
        Result := lUtc + fTimeZoneOffsetDayFraction;
      end;
  else
    Result := aSystemLocal;
  end;
end;

function TmaxCronEvent.EventLocalToSystemLocal(const aEventLocal: TDateTime; out aSystemLocal: TDateTime): Boolean;
var
  lUseLocal: TDateTime;
  lUtc: TDateTime;
  lOffsetDays: Double;
begin
  lUseLocal := aEventLocal;
  case fTimeZoneKind of
    TCronTimeZoneKind.ctzLocal:
      begin
        if fSystemTimeZone.IsInvalidTime(lUseLocal) then
        begin
          if fDstSpringPolicy = TmaxCronDstSpringPolicy.dspSkip then
            Exit(False);
          while fSystemTimeZone.IsInvalidTime(lUseLocal) do
            lUseLocal := IncMinute(lUseLocal, 1);
        end;

        if fSystemTimeZone.IsAmbiguousTime(lUseLocal) then
        begin
          case fDstFallPolicy of
            TmaxCronDstFallPolicy.dfpRunOncePreferSecondInstance:
              begin
                // Keep the same wall-clock time and select the standard-time instance.
                lUtc := fSystemTimeZone.ToUniversalTime(lUseLocal, False);
                lUseLocal := fSystemTimeZone.ToLocalTime(lUtc);
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
        lUtc := aEventLocal;
        if TryGetStableLocalOffsetForUtc(lUtc, lOffsetDays) then
          aSystemLocal := lUtc + lOffsetDays
        else
          aSystemLocal := fSystemTimeZone.ToLocalTime(lUtc);
        Result := True;
      end;
  else
    begin
      lUtc := aEventLocal - fTimeZoneOffsetDayFraction;
      if TryGetStableLocalOffsetForUtc(lUtc, lOffsetDays) then
        aSystemLocal := lUtc + lOffsetDays
      else
        aSystemLocal := fSystemTimeZone.ToLocalTime(lUtc);
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

function TmaxCronEvent.GetOnDeadLetterEvent: TmaxCronDeadLetterEvent;
begin
  fLock.Acquire;
  try
    Result := FOnDeadLetterEvent;
  finally
    fLock.Release;
  end;
end;

function TmaxCronEvent.GetOnDeadLetterProc: TmaxCronDeadLetterProc;
begin
  fLock.Acquire;
  try
    Result := FOnDeadLetterProc;
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

function TmaxCronEvent.GetRetryMaxAttempts: Integer;
begin
  fLock.Acquire;
  try
    Result := fRetryMaxAttempts;
  finally
    fLock.Release;
  end;
end;

function TmaxCronEvent.GetRetryInitialDelayMs: Cardinal;
begin
  fLock.Acquire;
  try
    Result := fRetryInitialDelayMs;
  finally
    fLock.Release;
  end;
end;

function TmaxCronEvent.GetRetryBackoffMultiplier: Double;
begin
  fLock.Acquire;
  try
    Result := fRetryBackoffMultiplier;
  finally
    fLock.Release;
  end;
end;

function TmaxCronEvent.GetRetryMaxDelayMs: Cardinal;
begin
  fLock.Acquire;
  try
    Result := fRetryMaxDelayMs;
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
  lRetryMaxAttempts: Integer;
  lAttemptIndex: Integer;
  lAttemptCount: Integer;
  lCurrentDelayMs: Cardinal;
  lMaxDelayMs: Cardinal;
  lNextDelayMs: Cardinal;
  lBackoffMultiplier: Double;
  lErrorText: string;
  lDeadLetterEvent: TmaxCronDeadLetterEvent;
  lDeadLetterProc: TmaxCronDeadLetterProc;
  lDispatchLimitsActive: Boolean;
  lPermitAcquired: Boolean;
  lInvocationSucceeded: Boolean;
  lOwnerPointer: Pointer;
  lPreviousCron: Pointer;
begin
  try
    lEvent := nil;
    lErrorText := '';
    lAttemptCount := 0;
    lDeadLetterEvent := nil;
    lDeadLetterProc := nil;
    lDispatchLimitsActive := False;
    lInvocationSucceeded := False;
    lPermitAcquired := True;

    if not Supports(fEventToken, ICronEventToken, lToken) then Exit;
    if not lToken.TryGetEvent(lEvent) then Exit;

    fLock.Acquire;
    try
      Inc(fNumOfExecutions);
      lRetryMaxAttempts := fRetryMaxAttempts;
      lCurrentDelayMs := fRetryInitialDelayMs;
      lMaxDelayMs := fRetryMaxDelayMs;
      lBackoffMultiplier := fRetryBackoffMultiplier;
      lDeadLetterEvent := FOnDeadLetterEvent;
      lDeadLetterProc := FOnDeadLetterProc;
    finally
      fLock.Release;
    end;

    if fSharedState <> nil then
      lDispatchLimitsActive := fSharedState.HasDispatchLimits;
    if lDispatchLimitsActive then
    begin
      lPermitAcquired := fSharedState.AcquireDispatchPermit(High(Cardinal));
      if not lPermitAcquired then
        Exit;
    end;

    if fSharedState <> nil then
      fSharedState.IncrementCallbackDepth;

    lOwnerPointer := nil;
    if fSharedState <> nil then
      fSharedState.TryGetOwnerPointer(lOwnerPointer);

    lPreviousCron := gMaxCronExecutingCron;
    gMaxCronExecutingCron := lOwnerPointer;
    try
      for lAttemptIndex := 0 to lRetryMaxAttempts do
      begin
        Inc(lAttemptCount);
        try
          if Assigned(aOnEvent) then
            aOnEvent(lEvent);
          if Assigned(aOnProc) then
            aOnProc(lEvent);
          lInvocationSucceeded := True;
          Break;
        except
          on E: Exception do
          begin
            lErrorText := E.ClassName + ': ' + E.Message;
            if lAttemptIndex >= lRetryMaxAttempts then
              Break;

            if lCurrentDelayMs > 0 then
              TThread.Sleep(lCurrentDelayMs);

            if lBackoffMultiplier > 1.0 then
              lNextDelayMs := Round(lCurrentDelayMs * lBackoffMultiplier)
            else
              lNextDelayMs := lCurrentDelayMs;

            if lNextDelayMs < lCurrentDelayMs then
              lNextDelayMs := High(Cardinal);
            if (lMaxDelayMs > 0) and (lNextDelayMs > lMaxDelayMs) then
              lNextDelayMs := lMaxDelayMs;
            lCurrentDelayMs := lNextDelayMs;
          end;
        end;
      end;
    finally
      gMaxCronExecutingCron := lPreviousCron;
      if fSharedState <> nil then
        fSharedState.DecrementCallbackDepth;
      if lDispatchLimitsActive and lPermitAcquired and (fSharedState <> nil) then
        fSharedState.ReleaseDispatchPermit;
    end;

    if (not lInvocationSucceeded) and (lAttemptCount > 0) then
    begin
      try
        if Assigned(lDeadLetterEvent) then
          lDeadLetterEvent(lEvent, lErrorText, lAttemptCount);
        if Assigned(lDeadLetterProc) then
          lDeadLetterProc(lEvent, lErrorText, lAttemptCount);
      except
        // dead-letter hook failures are intentionally isolated from scheduler execution flow
      end;
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
        if (fSharedState <> nil) and fSharedState.ShouldUsePooledThreadDispatch then
        begin
          TTask.Run(
            procedure
            begin
              ExecuteOnce(aInvokeMode, aOnEvent, aOnProc, aOverlapMode);
            end);
        end else begin
          lThread := TThread.CreateAnonymousThread(
            procedure
            begin
              ExecuteOnce(aInvokeMode, aOnEvent, aOnProc, aOverlapMode);
            end);
          lThread.FreeOnTerminate := True;
          lThread.Start;
        end;
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
  lMisfire := TmaxCronMisfirePolicy.mpDefault;
  lCatchUpLimit := 1;

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

end.

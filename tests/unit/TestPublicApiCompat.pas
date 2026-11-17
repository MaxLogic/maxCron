unit TestPublicApiCompat;

interface

uses
  System.Generics.Collections, System.SysUtils, System.TypInfo,
  DUnitX.TestFramework,
  maxCron;

type
  [TestFixture]
  TTestPublicApiCompat = class
  public
    [Test] procedure EnumSourceCompatibility;
    [Test] procedure EnumValueExportCompleteness;
    [Test] procedure TypeIdentityAndRtti;
    [Test] procedure CalculationAndPreview;
    [Test] procedure ExecutionLimitBoundary;
    [Test] procedure QueryApiAlias;
  end;

implementation

type
  // A consumer implementing the pre-interval interface must continue to compile.
  // Keep these declarations at the Phase 1 contract; interval metadata has its own interface.
  TLegacyCronEventContract = class abstract(TInterfacedObject, IMaxCronEvent)
  public
    function Run: IMaxCronEvent; virtual; abstract;
    procedure Stop; virtual; abstract;
    function GetEventPlan: string; virtual; abstract;
    procedure SetEventPlan(const aValue: string); virtual; abstract;
    function GetNextSchedule: TDateTime; virtual; abstract;
    function GetId: Int64; virtual; abstract;
    function GetName: string; virtual; abstract;
    function GetLastExecution: TDateTime; virtual; abstract;
    function GetTag: Integer; virtual; abstract;
    procedure SetTag(const aValue: Integer); virtual; abstract;
    function GetUserData: Pointer; virtual; abstract;
    procedure SetUserData(const aValue: Pointer); virtual; abstract;
    function GetUserDataInterface: IInterface; virtual; abstract;
    procedure SetUserDataInterface(const aValue: IInterface); virtual; abstract;
    function GetOnScheduleEvent: TmaxCronNotifyEvent; virtual; abstract;
    procedure SetOnScheduleEvent(const aValue: TmaxCronNotifyEvent); virtual; abstract;
    function GetOnScheduleProc: TmaxCronNotifyProc; virtual; abstract;
    procedure SetOnScheduleProc(const aValue: TmaxCronNotifyProc); virtual; abstract;
    function GetEnabled: Boolean; virtual; abstract;
    procedure SetEnabled(const aValue: Boolean); virtual; abstract;
    function GetInvokeMode: TmaxCronInvokeMode; virtual; abstract;
    procedure SetInvokeMode(const aValue: TmaxCronInvokeMode); virtual; abstract;
    function GetOverlapMode: TmaxCronOverlapMode; virtual; abstract;
    procedure SetOverlapMode(const aValue: TmaxCronOverlapMode); virtual; abstract;
    function GetDayMatchMode: TmaxCronDayMatchMode; virtual; abstract;
    procedure SetDayMatchMode(const aValue: TmaxCronDayMatchMode); virtual; abstract;
    function GetDialect: TmaxCronDialect; virtual; abstract;
    procedure SetDialect(const aValue: TmaxCronDialect); virtual; abstract;
    function GetMisfirePolicy: TmaxCronMisfirePolicy; virtual; abstract;
    procedure SetMisfirePolicy(const aValue: TmaxCronMisfirePolicy); virtual; abstract;
    function GetRetryMaxAttempts: Integer; virtual; abstract;
    procedure SetRetryMaxAttempts(const aValue: Integer); virtual; abstract;
    function GetRetryInitialDelayMs: Cardinal; virtual; abstract;
    procedure SetRetryInitialDelayMs(const aValue: Cardinal); virtual; abstract;
    function GetRetryBackoffMultiplier: Double; virtual; abstract;
    procedure SetRetryBackoffMultiplier(const aValue: Double); virtual; abstract;
    function GetRetryMaxDelayMs: Cardinal; virtual; abstract;
    procedure SetRetryMaxDelayMs(const aValue: Cardinal); virtual; abstract;
    function GetOnDeadLetterEvent: TmaxCronDeadLetterEvent; virtual; abstract;
    procedure SetOnDeadLetterEvent(const aValue: TmaxCronDeadLetterEvent); virtual; abstract;
    function GetOnDeadLetterProc: TmaxCronDeadLetterProc; virtual; abstract;
    procedure SetOnDeadLetterProc(const aValue: TmaxCronDeadLetterProc); virtual; abstract;
    function GetTimeZoneId: string; virtual; abstract;
    procedure SetTimeZoneId(const aValue: string); virtual; abstract;
    function GetDstSpringPolicy: TmaxCronDstSpringPolicy; virtual; abstract;
    procedure SetDstSpringPolicy(const aValue: TmaxCronDstSpringPolicy); virtual; abstract;
    function GetDstFallPolicy: TmaxCronDstFallPolicy; virtual; abstract;
    procedure SetDstFallPolicy(const aValue: TmaxCronDstFallPolicy); virtual; abstract;
    function GetWeekdaysOnly: Boolean; virtual; abstract;
    procedure SetWeekdaysOnly(const aValue: Boolean); virtual; abstract;
    function GetExcludedDatesCsv: string; virtual; abstract;
    procedure SetExcludedDatesCsv(const aValue: string); virtual; abstract;
    function GetBlackoutStartTime: TDateTime; virtual; abstract;
    procedure SetBlackoutStartTime(const aValue: TDateTime); virtual; abstract;
    function GetBlackoutEndTime: TDateTime; virtual; abstract;
    procedure SetBlackoutEndTime(const aValue: TDateTime); virtual; abstract;
    function GetNumOfExecutionsPerformed: UInt64; virtual; abstract;
    function GetValidFrom: TDateTime; virtual; abstract;
    procedure SetValidFrom(const aValue: TDateTime); virtual; abstract;
    function GetValidTo: TDateTime; virtual; abstract;
    procedure SetValidTo(const aValue: TDateTime); virtual; abstract;
  end;


function Pick(const aValue: TmaxCronDialect): string; overload;
begin
  Result := GetEnumName(TypeInfo(TmaxCronDialect), Ord(aValue));
end;

function Pick(const aValue: Integer): string; overload;
begin
  Result := IntToStr(aValue);
end;

function DefaultDialect(const aValue: TmaxCronDialect = cdMaxCron): TmaxCronDialect;
begin
  Result := aValue;
end;

procedure TTestPublicApiCompat.EnumSourceCompatibility;
const
  cDialects: array[0..2] of TmaxCronDialect = (cdStandard, cdMaxCron, cdQuartzSecondsFirst);
var
  lPlan: TCronSchedulePlan;
  lMode: TmaxCronDayMatchMode;
  lMatched: Boolean;
begin
  lPlan := TCronSchedulePlan.Create;
  try
    lMatched := False;
    case lPlan.Dialect of
      cdStandard: lMatched := False;
      cdMaxCron: lMatched := True;
      cdQuartzSecondsFirst: lMatched := False;
    end;
    Assert.IsTrue(lMatched);
    lMode := lPlan.DayMatchMode;
    Assert.IsTrue(lMode in [dmAnd, dmOr]);
    Assert.IsTrue(lMode = dmAnd);
    Assert.AreEqual('cdQuartzSecondsFirst', Pick(cdQuartzSecondsFirst));
    Assert.IsTrue(DefaultDialect = cdMaxCron);
    Assert.IsTrue(cDialects[2] = cdQuartzSecondsFirst);
    Assert.IsTrue(TmaxCronDayMatchMode.dmOr = dmOr);
    Assert.IsTrue(Succ(dmAnd) = dmOr);
    Assert.AreEqual(0, Ord(Low(TmaxCronDialect)));
    Assert.IsTrue(ckSecond = High(TPartKind), 'TPartKind re-export guard');
    Assert.IsTrue(cdmLastWeekday = High(TCronDomModifier), 'TCronDomModifier re-export guard');
    Assert.IsTrue(cdwNthWeekday = High(TCronDowModifier), 'TCronDowModifier re-export guard');
    Assert.IsTrue(dmOr = High(TmaxCronDayMatchMode), 'TmaxCronDayMatchMode re-export guard');
    Assert.IsTrue(cdQuartzSecondsFirst = High(TmaxCronDialect), 'TmaxCronDialect re-export guard');
  finally
    lPlan.Free;
  end;
end;

procedure TTestPublicApiCompat.EnumValueExportCompleteness;
const
  // Every re-exported value is named unqualified, so a missing const in maxCron.pas fails to compile.
  cIntervalModes: array[TmaxCronIntervalMode] of TmaxCronIntervalMode = (ivFixedRate, ivFixedDelay);
  cDayMatchModes: array[TmaxCronDayMatchMode] of TmaxCronDayMatchMode = (dmDefault, dmAnd, dmOr);
  cDialects: array[TmaxCronDialect] of TmaxCronDialect = (cdStandard, cdMaxCron, cdQuartzSecondsFirst);
  cPartKinds: array[TPartKind] of TPartKind = (ckMinute, ckHour, ckDayOfTheMonth, ckMonth,
    ckDayOfTheWeek, ckYear, ckSecond);
  cDomModifiers: array[TCronDomModifier] of TCronDomModifier = (cdmNone, cdmLastDay,
    cdmNearestWeekday, cdmLastWeekday);
  cDowModifiers: array[TCronDowModifier] of TCronDowModifier = (cdwNone, cdwLastWeekday, cdwNthWeekday);
var
  lIntervalMode: TmaxCronIntervalMode;
  lIntervalPlan: TCronIntervalPlan;
  lDayMatchMode: TmaxCronDayMatchMode;
  lDialect: TmaxCronDialect;
  lPartKind: TPartKind;
  lDomModifier: TCronDomModifier;
  lDowModifier: TCronDowModifier;
begin
  lIntervalPlan := Default(TCronIntervalPlan);
  Assert.AreEqual<Cardinal>(0,lIntervalPlan.IntervalMs);
  for lIntervalMode := Low(TmaxCronIntervalMode) to High(TmaxCronIntervalMode) do
    Assert.IsTrue(cIntervalModes[lIntervalMode] = lIntervalMode, 'TmaxCronIntervalMode export order');
  for lDayMatchMode := Low(TmaxCronDayMatchMode) to High(TmaxCronDayMatchMode) do
    Assert.IsTrue(cDayMatchModes[lDayMatchMode] = lDayMatchMode, 'TmaxCronDayMatchMode export order');
  for lDialect := Low(TmaxCronDialect) to High(TmaxCronDialect) do
    Assert.IsTrue(cDialects[lDialect] = lDialect, 'TmaxCronDialect export order');
  for lPartKind := Low(TPartKind) to High(TPartKind) do
    Assert.IsTrue(cPartKinds[lPartKind] = lPartKind, 'TPartKind export order');
  for lDomModifier := Low(TCronDomModifier) to High(TCronDomModifier) do
    Assert.IsTrue(cDomModifiers[lDomModifier] = lDomModifier, 'TCronDomModifier export order');
  for lDowModifier := Low(TCronDowModifier) to High(TCronDowModifier) do
    Assert.IsTrue(cDowModifiers[lDowModifier] = lDowModifier, 'TCronDowModifier export order');
end;

procedure TTestPublicApiCompat.TypeIdentityAndRtti;
var
  lObject: TObject;
  lPlan: TCronSchedulePlan;
  lParts: TList<TCronPart>;
begin
  Assert.AreEqual('dmOr', GetEnumName(TypeInfo(TmaxCronDayMatchMode), Ord(dmOr)));
  Assert.AreEqual('TmaxCronDialect', string(PTypeInfo(TypeInfo(TmaxCronDialect))^.Name));
  Assert.AreEqual('maxCron.Plan', TCronSchedulePlan.UnitName);
  lObject := TCronSchedulePlan.Create;
  lParts := TList<TCronPart>.Create;
  try
    Assert.IsTrue(lObject is TCronSchedulePlan);
    lPlan := lObject as TCronSchedulePlan;
    lParts.Add(lPlan.Minute);
    Assert.IsTrue(lParts[0] = lPlan.Minute);
  finally
    lParts.Free;
    lObject.Free;
  end;
end;

procedure TTestPublicApiCompat.CalculationAndPreview;
var
  lPlan: TCronSchedulePlan;
  lTextPlan: TPlan;
  lDates: TDates;
  lNext: TDateTime;
  i: Integer;
  lYear, lMonth, lDay: Word;
begin
  lPlan := TCronSchedulePlan.Create;
  try
    lPlan.Parse('*/15 * * * *');
    Assert.IsTrue(lPlan.FindNextScheduleDate(EncodeDate(2026, 11, 15) + EncodeTime(10, 7, 30, 500), lNext));
    Assert.AreEqual(Double(EncodeDate(2026, 11, 15) + EncodeTime(10, 15, 0, 0)), Double(lNext));
  finally
    lPlan.Free;
  end;
  Assert.IsTrue(MakePreview('0 0 1 1 *', lDates, 3));
  Assert.AreEqual(3, Integer(Length(lDates)));
  for i := 0 to High(lDates) do
  begin
    DecodeDate(lDates[i], lYear, lMonth, lDay);
    Assert.AreEqual(1, Integer(lMonth));
    Assert.AreEqual(1, Integer(lDay));
    Assert.AreEqual(Double(EncodeDate(lYear, 1, 1)), Double(lDates[i]));
    if i > 0 then
    begin
      Assert.IsTrue(lDates[i] > lDates[i - 1]);
    end;
  end;
  lTextPlan.Dialect := cdMaxCron;
  lTextPlan.Text := '1 2 3 4 5';
  Assert.AreEqual('1', lTextPlan.Minute);
  Assert.AreEqual('5', lTextPlan.DayOfTheWeek);
end;

procedure TTestPublicApiCompat.ExecutionLimitBoundary;
var
  lPlan: TCronSchedulePlan;

  procedure Reject(const aText, aMessage: string);
  var
    lRaised: Boolean;
  begin
    lRaised := False;
    try
      lPlan.Parse(aText);
    except
      on E: Exception do
      begin
        lRaised := True;
        Assert.IsTrue(E.ClassType = Exception);
        Assert.AreEqual(aMessage, E.Message);
      end;
    end;
    Assert.IsTrue(lRaised);
  end;

begin
  lPlan := TCronSchedulePlan.Create;
  try
    lPlan.Parse('* * * * * * * 4294967295');
    Assert.AreEqual(UInt64(4294967295), UInt64(lPlan.ExecutionLimit));
    Reject('* * * * * * * 4294967296', 'Cron value out of range');
    Reject('* * * * * * * x', 'Invalid cron token');
  finally
    lPlan.Free;
  end;
end;

procedure TTestPublicApiCompat.QueryApiAlias;
var
  lPlan: TCronSchedulePlan;
  lDates: TDates;
begin
  Assert.AreEqual(10000, cCronQueryDefaultLimit);
  lPlan := TCronSchedulePlan.Create;
  try
    lPlan.Parse('* * * * * * *');
    Assert.AreEqual(10000, lPlan.GetOccurrencesBetween(EncodeDate(2026, 1, 1),
      EncodeDate(2026, 1, 2), lDates));
    Assert.AreEqual(10000, Integer(Length(lDates)));
  finally
    lPlan.Free;
  end;
end;

end.

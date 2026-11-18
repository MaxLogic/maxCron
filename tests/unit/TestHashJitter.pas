unit TestHashJitter;
{$I maxCron.inc}

interface

uses
  {$IFDEF FPC}
  DateUtils, SysUtils,
  DUnitX.TestFramework,
  maxCron
  {$ELSE}
  System.DateUtils, System.SysUtils,
  DUnitX.TestFramework,
  maxCron
  {$ENDIF};

type
  [TestFixture]
  TTestHashJitter = class
  private
    function Hash32(const aValue: string): Cardinal;
  public
    [TestCase('minute-standard', '0,0')]
    [TestCase('minute-maxcron', '0,1')]
    [TestCase('minute-quartz', '0,2')]
    [TestCase('hour-standard', '1,0')]
    [TestCase('hour-maxcron', '1,1')]
    [TestCase('hour-quartz', '1,2')]
    [TestCase('dom-standard', '2,0')]
    [TestCase('dom-maxcron', '2,1')]
    [TestCase('dom-quartz', '2,2')]
    [TestCase('month-standard', '3,0')]
    [TestCase('month-maxcron', '3,1')]
    [TestCase('month-quartz', '3,2')]
    [TestCase('dow-standard', '4,0')]
    [TestCase('dow-maxcron', '4,1')]
    [TestCase('dow-quartz', '4,2')]
    [TestCase('year-standard', '5,0')]
    [TestCase('year-maxcron', '5,1')]
    [TestCase('year-quartz', '5,2')]
    [TestCase('second-standard', '6,0')]
    [TestCase('second-maxcron', '6,1')]
    [TestCase('second-quartz', '6,2')]
    procedure HashToken_LargeSteps_AllFields(const aField, aDialect: Integer);
    [Test]
    procedure HashToken_SingleValue_UsesSeed;

    [Test]
    procedure HashToken_StepRange_StartsFromSeededValue;

    [Test]
    procedure HashToken_DifferentEventNames_ChangeSchedule;
  end;

implementation

procedure TTestHashJitter.HashToken_LargeSteps_AllFields(const aField, aDialect: Integer);
const
  cLows: array[TPartKind] of Integer = (0, 0, 1, 1, 0, 1900, 0);
  cHighs: array[TPartKind] of Integer = (59, 23, 31, 12, 6, 3000, 59);
var
  lPlan: TCronSchedulePlan;
  lPart: TCronPart;
  lKind: TPartKind;
  lSeed, lToken, lInitial: string;
  lLow, lHigh, lStart, lFrom, lTo, lExpected, lForm, lBase, v: Integer;
begin
  lKind := TPartKind(aField);
  lLow := cLows[lKind];
  lHigh := cHighs[lKind];
  lBase := 0;
  if (lKind = ckDayOfTheWeek) and (TmaxCronDialect(aDialect) = cdQuartzSecondsFirst) then
  begin
    lBase := 1;
    Inc(lLow);
    Inc(lHigh);
  end;
  lPlan := TCronSchedulePlan.Create;
  try
    lPlan.Dialect := TmaxCronDialect(aDialect);
    case lPlan.Dialect of
      cdStandard: lInitial := '* * * * *';
      cdMaxCron: lInitial := '* * * * * * * 0';
    else
      lInitial := '* * * ? * * *';
    end;
    for lSeed in ['', 'job-a', 'EventAlpha'] do
    begin
      lPlan.HashSeed := lSeed;
      lPlan.Parse(lInitial);
      lPart := lPlan.parts[lKind];
      for lForm := 0 to 3 do
      begin
        lFrom := lLow + 1;
        lTo := lFrom;
        if lForm in [1, 3] then lTo := lHigh;
        lToken := 'H(' + IntToStr(lFrom) + '-' + IntToStr(lTo) + ')';
        if lForm = 2 then
        begin
          lFrom := lLow;
          lTo := lHigh;
          lToken := 'H';
        end;
        if lForm = 3 then lToken := lToken + '/2147483646'
        else lToken := lToken + '/2147483647';
        lStart := lFrom - lBase;
        lExpected := lStart + Integer(Hash32(lSeed + '|' + IntToStr(aField) + '|' + lToken) mod
          Cardinal(lTo - lFrom + 1));
        lPart.Data := lToken;
        for v := cLows[lKind] to cHighs[lKind] do
          Assert.AreEqual(v = lExpected, lPart.NextVal(v) = v, lToken + ' value ' + IntToStr(v));
      end;
    end;
  finally
    lPlan.Free;
  end;
end;

function TTestHashJitter.Hash32(const aValue: string): Cardinal;
var
  lIndex: Integer;
  lHash: Cardinal;
  lWork: UInt64;
begin
  lHash := 2166136261;
  for lIndex := 1 to Length(aValue) do
  begin
    lWork := UInt64(lHash xor Cardinal(Ord(aValue[lIndex])));
    lWork := (lWork * UInt64(16777619)) and UInt64($FFFFFFFF);
    lHash := Cardinal(lWork);
  end;
  Result := lHash;
end;

procedure TTestHashJitter.HashToken_SingleValue_UsesSeed;
var
  lPlan: TCronSchedulePlan;
  lExpected: Word;
  lActual: Word;
begin
  lPlan := TCronSchedulePlan.Create;
  try
    lPlan.Dialect := cdStandard;
    lPlan.HashSeed := 'EventAlpha';
    lPlan.Parse('H * * * *');

    lExpected := Word(Hash32('EventAlpha|0|H') mod 60);
    Assert.IsTrue(lPlan.Minute.TryGetSingleValue(lActual));
    Assert.AreEqual(lExpected, lActual);
  finally
    lPlan.Free;
  end;
end;

procedure TTestHashJitter.HashToken_StepRange_StartsFromSeededValue;
var
  lPlan: TCronSchedulePlan;
  lValues: TWordArray;
  lExpectedStart: Word;
  lIndex: Integer;
begin
  lPlan := TCronSchedulePlan.Create;
  try
    lPlan.Dialect := cdStandard;
    lPlan.HashSeed := 'EventBeta';
    lPlan.Parse('H(10-20)/3 * * * *');

    lExpectedStart := 10 + Word(Hash32('EventBeta|0|H(10-20)/3') mod 11);
    Assert.IsTrue(lPlan.Minute.GetValues(lValues));
    Assert.IsTrue(Length(lValues) > 0);
    Assert.AreEqual(lExpectedStart, lValues[0]);
    for lIndex := 1 to Length(lValues) - 1 do
      Assert.AreEqual(3, Integer(lValues[lIndex] - lValues[lIndex - 1]));
  finally
    lPlan.Free;
  end;
end;

procedure TTestHashJitter.HashToken_DifferentEventNames_ChangeSchedule;
var
  lCron: TmaxCron;
  lEventA: IMaxCronEvent;
  lEventB: IMaxCronEvent;
begin
  lCron := TmaxCron.Create(ctPortable);
  try
    lEventA := lCron.Add('HashA');
    lEventA.EventPlan := 'H H * * * * 0 1';
    lEventA.ValidFrom := EncodeDateTime(2032, 1, 1, 0, 0, 0, 0);
    lEventA.Run;

    lEventB := lCron.Add('HashB');
    lEventB.EventPlan := 'H H * * * * 0 1';
    lEventB.ValidFrom := EncodeDateTime(2032, 1, 1, 0, 0, 0, 0);
    lEventB.Run;

    Assert.AreNotEqual(lEventA.NextSchedule, lEventB.NextSchedule);
  finally
    lCron.Free;
  end;
end;

end.


unit TestHashJitter;

interface

uses
  System.DateUtils, System.SysUtils,
  DUnitX.TestFramework,
  maxCron;

type
  [TestFixture]
  TTestHashJitter = class
  private
    function Hash32(const aValue: string): Cardinal;
  public
    [Test]
    procedure HashToken_SingleValue_UsesSeed;

    [Test]
    procedure HashToken_StepRange_StartsFromSeededValue;

    [Test]
    procedure HashToken_DifferentEventNames_ChangeSchedule;
  end;

implementation

function TTestHashJitter.Hash32(const aValue: string): Cardinal;
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
  lEventA: TmaxCronEvent;
  lEventB: TmaxCronEvent;
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


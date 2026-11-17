unit TestCronPhaseDifferential;
{$I maxCron.inc}

interface

uses
  {$IFDEF FPC}
  Windows,
  DateUtils, Generics.Collections, SysUtils,
  DUnitX.TestFramework,
  maxCron
  {$ELSE}
  System.DateUtils, System.Generics.Collections, System.SysUtils,
  Winapi.Windows,
  DUnitX.TestFramework,
  maxCron
  {$ENDIF};

type
  [TestFixture]
  TTestCronPhaseDifferential = class
  private
    function PickToken(const aTokens: array of string): string;
    function BuildPlanText(const aDialect: TmaxCronDialect; const aDayMatchMode: TmaxCronDayMatchMode): string;
  public
    [TestCase('scan skip', 'scan,0,1')]
    [TestCase('heap skip', 'heap,0,1')]
    [TestCase('scan once', 'scan,1,1')]
    [TestCase('heap once', 'heap,1,1')]
    [TestCase('scan catch1', 'scan,2,1')]
    [TestCase('heap catch1', 'heap,2,1')]
    [TestCase('scan catch3', 'scan,2,3')]
    [TestCase('heap catch3', 'heap,2,3')]
    procedure ComparePhases(const aEngine: string; const aPolicy, aLimit: Integer);
  end;

implementation

function TTestCronPhaseDifferential.PickToken(const aTokens: array of string): string;
begin
  Result := aTokens[Random(Length(aTokens))];
end;

function TTestCronPhaseDifferential.BuildPlanText(const aDialect: TmaxCronDialect;
  const aDayMatchMode: TmaxCronDayMatchMode): string;
var
  lDowRestricted: string;
  lSecond: string;
  lMinute: string;
  lHour: string;
  lDom: string;
  lMonth: string;
  lDow: string;
  lYear: string;
begin
  lSecond := PickToken(['0', '*/10', '*/15', '0,30']);
  lMinute := PickToken(['*', '*/5', '*/10', '0,15,30,45']);
  lHour := PickToken(['*', '*/2', '*/6', '0,12']);
  lMonth := '*';
  lYear := '*';

  if aDialect = cdQuartzSecondsFirst then
    lDowRestricted := PickToken(['1,3,5', '2,4,6', '7'])
  else
    lDowRestricted := PickToken(['1,3,5', '2,4,6', '0']);

  if (aDayMatchMode = dmAnd) or (aDayMatchMode = dmDefault) then
  begin
    lDom := '*';
    if Random(3) = 0 then
      lDow := '*'
    else
      lDow := lDowRestricted;
  end else begin
    lDom := PickToken(['*/2', '1,15', '*']);
    lDow := lDowRestricted;
  end;

  case aDialect of
    cdStandard:
      Result := lMinute + ' ' + lHour + ' ' + lDom + ' ' + lMonth + ' ' + lDow;
    cdQuartzSecondsFirst:
      Result := lSecond + ' ' + lMinute + ' ' + lHour + ' ' + lDom + ' ' + lMonth + ' ' + lDow + ' ' + lYear;
  else
    Result := lMinute + ' ' + lHour + ' ' + lDom + ' ' + lMonth + ' ' + lDow + ' ' + lYear + ' ' + lSecond + ' 0';
  end;
end;


procedure AddObserved(const aCron: TmaxCron; const aPlan: string; const aDialect: TmaxCronDialect;
  const aMode: TmaxCronDayMatchMode; const aRows: TList<TDateTime>; out aEvent: IMaxCronEvent);
begin
  aEvent := aCron.Add('');
  aEvent.Dialect := aDialect;
  aEvent.DayMatchMode := aMode;
  aEvent.EventPlan := aPlan;
  aEvent.InvokeMode := imMainThread;
  aEvent.OnScheduleProc := procedure(aSender: IMaxCronEvent) begin aRows.Add(aSender.LastExecution);
    end;
  aEvent.Run;
end;

procedure TTestCronPhaseDifferential.ComparePhases(const aEngine: string; const aPolicy, aLimit: Integer);
var
  lA, lB: TmaxCron;
  lEventsA, lEventsB: array[0..99] of IMaxCronEvent;
  lRowsA, lRowsB: array[0..99] of TList<TDateTime>;
  lStalls: array[0..3599] of Boolean;
  lWallUs: Int64;
  lBase: TDateTime;
  lDialect: TmaxCronDialect;
  lMode: TmaxCronDayMatchMode;
  lPlan, lOldEngine: string;
  lOldSeed, i, j, k, lStart, lLength: Integer;
begin
  lOldEngine := {$IFDEF FPC}SysUtils.{$ENDIF}GetEnvironmentVariable('MAXCRON_ENGINE');
  SetEnvironmentVariableW('MAXCRON_ENGINE', PChar(aEngine));
  lOldSeed := RandSeed;
  RandSeed := 20261115;
  lBase := EncodeDateTime(2026, 6, 15, 0, 0, 0, 0);
  lWallUs := Round(lBase * 86400000000.0);
  SetMaxCronWallClockHook(function: Int64 begin Result := lWallUs; end);
  lA := nil; lB := nil;
  for i := 0 to 99 do
    begin
      lRowsA[i] := nil; lRowsB[i] := nil;
    end;
  try
    lA := TmaxCron.Create(ctPortable); lB := TmaxCron.Create(ctPortable);
    case aPolicy of
      0: begin lA.DefaultMisfirePolicy := TmaxCronMisfirePolicy.mpSkip; lB.DefaultMisfirePolicy := TmaxCronMisfirePolicy.mpSkip;
    end;
      1: begin lA.DefaultMisfirePolicy := TmaxCronMisfirePolicy.mpFireOnceNow; lB.DefaultMisfirePolicy := TmaxCronMisfirePolicy.mpFireOnceNow;
    end;
      2: begin lA.DefaultMisfirePolicy := TmaxCronMisfirePolicy.mpCatchUpAll; lB.DefaultMisfirePolicy := TmaxCronMisfirePolicy.mpCatchUpAll;
    end;
    end;
    lA.DefaultMisfireCatchUpLimit := aLimit; lB.DefaultMisfireCatchUpLimit := aLimit;
    for i := 0 to 99 do
    begin
      lDialect := TmaxCronDialect(i mod 3);
      if i mod 2 = 0 then lMode := dmAnd else lMode := dmOr;
      lPlan := BuildPlanText(lDialect, lMode);
      lRowsA[i] := TList<TDateTime>.Create; lRowsB[i] := TList<TDateTime>.Create;
      AddObserved(lA, lPlan, lDialect, lMode, lRowsA[i], lEventsA[i]);
      AddObserved(lB, lPlan, lDialect, lMode, lRowsB[i], lEventsB[i]);
    end;
    FillChar(lStalls, SizeOf(lStalls), 0);
    for i := 1 to 10 do
    begin
      lStart := 1 + Random(3500); lLength := 5 + Random(26);
      for j := lStart to lStart + lLength - 1 do lStalls[j] := True;
    end;
    for i := 0 to 3599 do
      if not lStalls[i] then
      begin
        lWallUs := Round(lBase * 86400000000.0) + Int64(i) * 1000000;
        lA.TickAt((lWallUs + 700000) / Double(86400000000.0));
        lB.TickAt((lWallUs + 200) / Double(86400000000.0));
      end;
    k := 0;
    for i := 0 to 99 do
    begin
      Assert.AreEqual(lRowsA[i].Count, lRowsB[i].Count, 'fire count plan ' + IntToStr(i));
      for j := 0 to lRowsA[i].Count - 1 do
        Assert.AreEqual(lRowsA[i][j], lRowsB[i][j], 0.0, 'LastExecution sequence');
      Assert.AreEqual(lEventsA[i].NextSchedule, lEventsB[i].NextSchedule, 0.0, 'NextSchedule');
      Inc(k, lRowsA[i].Count);
    end;
    Assert.IsTrue(k > 0, 'Generator must exercise dispatch');
  finally
    lA.Free; lB.Free;
    for i := 0 to 99 do
    begin
      lRowsA[i].Free; lRowsB[i].Free;
    end;
    SetMaxCronWallClockHook(nil);
    RandSeed := lOldSeed;
    SetEnvironmentVariableW('MAXCRON_ENGINE', PChar(lOldEngine));
  end;
end;

end.

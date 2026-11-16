unit TestTimeBoundaries;

interface

uses
  System.DateUtils, System.Math, System.SysUtils,
  Winapi.Windows,
  AutoFree, DUnitX.TestFramework,
  maxCron;

type
  [TestFixture]
  TTestTimeBoundaries = class
  private
    procedure CheckWindows(const aEngine: string; const aPolicy, aLimit: Integer; const aCarrier: Boolean);
  public
    [TestCase('scan-0-1', 'scan,0,1')]
    [TestCase('scan-1-1', 'scan,1,1')]
    [TestCase('scan-2-1', 'scan,2,1')]
    [TestCase('scan-2-3', 'scan,2,3')]
    [TestCase('heap-0-1', 'heap,0,1')]
    [TestCase('heap-1-1', 'heap,1,1')]
    [TestCase('heap-2-1', 'heap,2,1')]
    [TestCase('heap-2-3', 'heap,2,3')]
    [TestCase('shadow-0-1', 'shadow,0,1')]
    [TestCase('shadow-1-1', 'shadow,1,1')]
    [TestCase('shadow-2-1', 'shadow,2,1')]
    [TestCase('shadow-2-3', 'shadow,2,3')]
    procedure PreciseWindows(const aEngine: string; const aPolicy, aLimit: Integer);
    [TestCase('scan-0-1', 'scan,0,1')]
    [TestCase('scan-1-1', 'scan,1,1')]
    [TestCase('scan-2-1', 'scan,2,1')]
    [TestCase('scan-2-3', 'scan,2,3')]
    [TestCase('heap-0-1', 'heap,0,1')]
    [TestCase('heap-1-1', 'heap,1,1')]
    [TestCase('heap-2-1', 'heap,2,1')]
    [TestCase('heap-2-3', 'heap,2,3')]
    [TestCase('shadow-0-1', 'shadow,0,1')]
    [TestCase('shadow-1-1', 'shadow,1,1')]
    [TestCase('shadow-2-1', 'shadow,2,1')]
    [TestCase('shadow-2-3', 'shadow,2,3')]
    procedure CarrierWindows(const aEngine: string; const aPolicy, aLimit: Integer);
    [TestCase('scan', 'scan')]
    [TestCase('heap', 'heap')]
    [TestCase('shadow', 'shadow')]
    procedure RunBases(const aEngine: string);
    [TestCase('scan', 'scan')]
    [TestCase('heap', 'heap')]
    procedure HistoricalSubMs(const aEngine: string);
    [Test] procedure HistoricalHourlyRun;
    [Test] procedure WatchdogMicrosecondThreshold;
  end;

implementation

const
  cUsPerSecond: Int64 = 1000000;
  cUsPerDay: Double = 86400000000.0;
  cPeriods: array[0..3] of Integer = (1, 60, 3600, 86400);
  cPlans: array[0..3] of string = ('* * * * * * *', '* * * * *', '0 * * * *', '0 0 * * *');
  cOffsets: array[0..34] of Integer = (-1000000, -999999, -500001, -500000, -499999,
    -1001, -1000, -999, -501, -500, -499, -1, 0, 1, 200, 499, 500, 501, 999, 1000, 1001,
    999000, 999400, 999499, 999500, 999501, 999600, 999900, 999999, 1000000, 1000001,
    1000500, 1999999, 2000000, 2000001);

function GridMs(const aValue: TDateTime): Int64;
var
  lStamp: TTimeStamp;
begin
  if aValue = 0 then
    Exit(0);
  lStamp := DateTimeToTimeStamp(aValue);
  Result := (Int64(lStamp.Date) - DateDelta) * MSecsPerDay + lStamp.Time;
end;

// Independent carrier interpretation, without the production conversion.
function CarrierUs(const aValue: TDateTime): Int64;
var
  lDay, lWhole: Int64;
  lPart, lRemainder: Double;
begin
  lDay := Trunc(aValue);
  lPart := (aValue - lDay) * 86400000.0;
  lWhole := Trunc(lPart);
  lRemainder := lPart - lWhole;
  if (lRemainder > 0.5) or ((lRemainder = 0.5) and Odd(lWhole)) then
    Inc(lWhole);
  Result := (lDay * MSecsPerDay + lWhole) * 1000;
end;

function Neighbour(const aValue: TDateTime; const aDistance: Integer): TDateTime;
var
  lBits: Int64;
begin
  Move(aValue, lBits, SizeOf(lBits));
  Inc(lBits, aDistance);
  Move(lBits, Result, SizeOf(Result));
end;

function DueSecond(const aSample, aPeriod: Integer): Int64;
var
  lDate: TDateTime;
  lYear: Word;
  lSecond: Int64;
begin
  // Explicit leap day, month/year ends, binades, and seeded spread to year 2999.
  case aSample mod 8 of
    0: lDate := EncodeDate(1990 + (aSample * 37 mod 1010), 12, 31);
    1: lDate := EncodeDate(2000 + (aSample mod 24) * 4, 2, 29);
    2: lDate := EncodeDate(2079, 6, 5);
    3: lDate := EncodeDate(2258, 11, 10);
    4: lDate := EncodeDate(2617, 9, 21);
    5: lDate := EncodeDate(2999, 12, 31);
  else
    lYear := 1990 + (aSample * 7919 mod 1010);
    lDate := EncodeDate(lYear, 1 + (aSample mod 12), 1 + (aSample mod 28));
  end;
  lSecond := GridMs(lDate) div 1000 + (aSample * 7919 mod 86400);
  if aSample mod 8 = 0 then
    lSecond := GridMs(lDate) div 1000 + 86399;
  Result := (lSecond div aPeriod) * aPeriod;
end;

procedure TTestTimeBoundaries.CheckWindows(const aEngine: string; const aPolicy, aLimit: Integer;
  const aCarrier: Boolean);
var
  g: TGarbos;
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lWallUs, lDueUs, lTickUs, lModelUs, lNextUs, lLastUs, lPeriodUs: Int64;
  lCount, lExpected, lFailures, lChecks, lOffset, lVariant, lDistance: Integer;
  lSeed: Cardinal;
  lDue, lTick, lOriginal: TDateTime;
  lOldEngine, lFirst: string;
begin
  lOldEngine := GetEnvironmentVariable('MAXCRON_ENGINE');
  Winapi.Windows.SetEnvironmentVariable('MAXCRON_ENGINE', PChar(aEngine));
  lWallUs := GridMs(EncodeDate(1989, 1, 1)) * 1000;
  SetMaxCronWallClockHook(function: Int64 begin Result := lWallUs; end);
  lFailures := 0;
  lChecks := 0;
  lFirst := '';
  lSeed := 20261116;
  try
    GC(lCron, TmaxCron.Create(ctPortable), g);
    lCron.DefaultMisfirePolicy := TmaxCronMisfirePolicy(Ord(TmaxCronMisfirePolicy.mpSkip) + aPolicy);
    lCron.DefaultMisfireCatchUpLimit := aLimit;
    lEvent := lCron.Add('integer-model');
    lEvent.InvokeMode := imMainThread;
    lEvent.OnScheduleProc := procedure(aSender: IMaxCronEvent) begin Inc(lCount); end;
    for var p := 0 to 3 do
    begin
      lEvent.Stop;
      lEvent.EventPlan := cPlans[p];
      lPeriodUs := Int64(cPeriods[p]) * cUsPerSecond;
      for var i := 0 to 63 do
      begin
        lDueUs := DueSecond(i, cPeriods[p]) * cUsPerSecond;
        lWallUs := lDueUs - cUsPerSecond;
        lDue := IncSecond(EncodeDate(1899, 12, 30), lDueUs div cUsPerSecond);
        lEvent.Stop;
        lEvent.ValidFrom := IncSecond(lDue, -1);
        for var j := 0 to High(cOffsets) + 8 do
        begin
          if j <= High(cOffsets) then
            lOffset := cOffsets[j]
          else begin
            lSeed := (UInt64(lSeed) * 1664525 + 1013904223) and $FFFFFFFF;
            lOffset := Integer(lSeed mod 5000001) - 2000000;
          end;
          lTickUs := lDueUs + lOffset;
          if aCarrier then
            lVariant := 1
          else
            lVariant := 0;
          for var v := 0 to lVariant do
          begin
            if v = 0 then
              lOriginal := lTickUs / cUsPerDay
            else
              lOriginal := IncMilliSecond(lDue, lOffset div 1000);
            if aCarrier then
              lDistance := 4
            else
              lDistance := 0;
            for var k := -lDistance to lDistance do
            begin
              lTick := Neighbour(lOriginal, k);
              if aCarrier then
                lModelUs := CarrierUs(lTick)
              else
                lModelUs := lTickUs;
              lEvent.Stop;
              lEvent.Run;
              Assert.AreEqual(lDueUs div 1000, GridMs(lEvent.NextSchedule), 'Generator setup due');
              lCount := 0;
              lExpected := 0;
              lNextUs := lDueUs;
              lLastUs := 0;
              if lModelUs >= lDueUs then
              begin
                if aPolicy = 2 then
                begin
                  lExpected := Min(Int64(aLimit), (lModelUs - lDueUs) div lPeriodUs + 1);
                  lNextUs := lDueUs + lExpected * lPeriodUs;
                  lLastUs := lNextUs - lPeriodUs;
                end else begin
                  lNextUs := (lModelUs div lPeriodUs + 1) * lPeriodUs;
                  if (aPolicy = 1) or (lModelUs - lDueUs < cUsPerSecond) then
                  begin
                    lExpected := 1;
                    lLastUs := lDueUs;
                  end;
                end;
              end;
              if aCarrier then
                lCron.TickAt(lTick)
              else
                lCron.TickAtUs(lTickUs);
              Inc(lChecks);
              if (lCount <> lExpected) or (GridMs(lEvent.NextSchedule) <> lNextUs div 1000) or
                (GridMs(lEvent.LastExecution) <> lLastUs div 1000) then
              begin
                Inc(lFailures);
                if lFirst = '' then
                  lFirst := Format('seed=20261116 due=%d offset=%d now=%d engine=%s policy=%d limit=%d plan=%s variant=%d ulp=%d fires=%d expected=%d nextMs=%d expectedNextMs=%d lastMs=%d expectedLastMs=%d',
                    [lDueUs, lOffset, lModelUs, aEngine, aPolicy, aLimit, cPlans[p], v, k, lCount,
                    lExpected, GridMs(lEvent.NextSchedule), lNextUs div 1000, GridMs(lEvent.LastExecution), lLastUs div 1000]);
              end;
            end;
          end;
        end;
        // Existing Double-addition forms, including both ulp neighbours, stay covered.
        if aCarrier then
          for var k := 0 to 2 do
          begin
            lOriginal := lDue + k * (1.0 / 24 / 60 / 60);
            for var j := -4 to 4 do
            begin
              lTick := Neighbour(lOriginal, j);
              lEvent.Stop;
              lEvent.Run;
              lCount := 0;
              lCron.TickAt(lTick);
              lExpected := 1;
              lModelUs := CarrierUs(lTick);
              lNextUs := (lModelUs div lPeriodUs + 1) * lPeriodUs;
              lLastUs := lDueUs;
              if (aPolicy = 0) and (k >= 1) then
              begin
                lExpected := 0;
                lLastUs := 0;
              end;
              if aPolicy = 2 then
              begin
                lExpected := Min(Int64(aLimit), (Int64(k) * cUsPerSecond) div lPeriodUs + 1);
                lNextUs := lDueUs + lExpected * lPeriodUs;
                lLastUs := lNextUs - lPeriodUs;
              end;
              Inc(lChecks);
              if (lCount <> lExpected) or (GridMs(lEvent.NextSchedule) <> lNextUs div 1000) or
                (GridMs(lEvent.LastExecution) <> lLastUs div 1000) then
              begin
                Inc(lFailures);
                if lFirst = '' then
                  lFirst := Format('Double addition due=%d k=%d ulp=%d engine=%s policy=%d plan=%s fires=%d expected=%d nextMs=%d expectedNextMs=%d lastMs=%d expectedLastMs=%d',
                    [lDueUs, k, j, aEngine, aPolicy, cPlans[p], lCount, lExpected,
                    GridMs(lEvent.NextSchedule), lNextUs div 1000, GridMs(lEvent.LastExecution), lLastUs div 1000]);
              end;
            end;
          end;
      end;
    end;
    Writeln(Format('G1 carrier=%s engine=%s policy=%d limit=%d checks=%d failures=%d first=%s',
      [BoolToStr(aCarrier, True), aEngine, aPolicy, aLimit, lChecks, lFailures, lFirst]));
    Assert.AreEqual(0, lFailures, lFirst);
  finally
    g.Clear;
    SetMaxCronWallClockHook(nil);
    Winapi.Windows.SetEnvironmentVariable('MAXCRON_ENGINE', PChar(lOldEngine));
  end;
end;

procedure TTestTimeBoundaries.PreciseWindows(const aEngine: string; const aPolicy, aLimit: Integer);
begin
  CheckWindows(aEngine, aPolicy, aLimit, False);
end;

procedure TTestTimeBoundaries.CarrierWindows(const aEngine: string; const aPolicy, aLimit: Integer);
begin
  CheckWindows(aEngine, aPolicy, aLimit, True);
end;

procedure TTestTimeBoundaries.RunBases(const aEngine: string);
const
  cDeltas: array[0..13] of Integer = (-1, -100, -400, -499, -500, -501, -999, -1000, -999999,
    0, 1, 499, 500, 999999);
var
  g: TGarbos;
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lWallUs, lDueUs, lExpected: Int64;
  lFailures, lChecks: Integer;
  lOldEngine, lFirst: string;
begin
  lOldEngine := GetEnvironmentVariable('MAXCRON_ENGINE');
  Winapi.Windows.SetEnvironmentVariable('MAXCRON_ENGINE', PChar(aEngine));
  lWallUs := GridMs(EncodeDate(1989, 1, 1)) * 1000;
  SetMaxCronWallClockHook(function: Int64 begin Result := lWallUs; end);
  lFailures := 0;
  lChecks := 0;
  lFirst := '';
  try
    GC(lCron, TmaxCron.Create(ctPortable), g);
    lEvent := lCron.Add('run-base');
    for var p := 0 to 3 do
    begin
      lEvent.Stop;
      lEvent.EventPlan := cPlans[p];
      for var i := 0 to 63 do
      begin
        lDueUs := DueSecond(i, cPeriods[p]) * cUsPerSecond;
        for var d in cDeltas do
        begin
          lWallUs := lDueUs + d;
          lEvent.Stop;
          lEvent.Run;
          lExpected := lDueUs;
          if d >= 0 then
            Inc(lExpected, Int64(cPeriods[p]) * cUsPerSecond);
          Inc(lChecks);
          if GridMs(lEvent.NextSchedule) <> lExpected div 1000 then
          begin
            Inc(lFailures);
            if lFirst = '' then
              lFirst := Format('due=%d offset=%d engine=%s plan=%s nextMs=%d expectedMs=%d',
                [lDueUs, d, aEngine, cPlans[p], GridMs(lEvent.NextSchedule), lExpected div 1000]);
          end;
        end;
      end;
    end;
    Writeln(Format('G2 checks=%d failures=%d first=%s', [lChecks, lFailures, lFirst]));
    Assert.AreEqual(0, lFailures, lFirst);
  finally
    g.Clear;
    SetMaxCronWallClockHook(nil);
    Winapi.Windows.SetEnvironmentVariable('MAXCRON_ENGINE', PChar(lOldEngine));
  end;
end;

procedure TTestTimeBoundaries.HistoricalSubMs(const aEngine: string);
const
  cLate: array[0..2] of Integer = (999600, 999900, 1000000);
var
  g: TGarbos;
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lWallUs, lDueUs: Int64;
  lCount, lExpected: Integer;
  lOldEngine: string;
begin
  lOldEngine := GetEnvironmentVariable('MAXCRON_ENGINE');
  Winapi.Windows.SetEnvironmentVariable('MAXCRON_ENGINE', PChar(aEngine));
  lDueUs := GridMs(EncodeDateTime(2026, 11, 16, 11, 0, 0, 0)) * 1000;
  lWallUs := lDueUs - cUsPerSecond;
  SetMaxCronWallClockHook(function: Int64 begin Result := lWallUs; end);
  try
    GC(lCron, TmaxCron.Create(ctPortable), g);
    lCron.DefaultMisfirePolicy := TmaxCronMisfirePolicy.mpSkip;
    lEvent := lCron.Add('R4', cPlans[0], procedure(aSender: IMaxCronEvent) begin Inc(lCount); end);
    lEvent.InvokeMode := imMainThread;
    for var d in cLate do
    begin
      lEvent.Stop;
      lEvent.Run;
      lCount := 0;
      lCron.TickAtUs(lDueUs + d);
      lExpected := Ord(d < 1000000);
      Assert.AreEqual(lExpected, lCount, 'R4 due + ' + IntToStr(d));
      Assert.AreEqual((lDueUs div 1000) + 1000 * (1 + Ord(d = 1000000)), GridMs(lEvent.NextSchedule));
    end;
  finally
    g.Clear;
    SetMaxCronWallClockHook(nil);
    Winapi.Windows.SetEnvironmentVariable('MAXCRON_ENGINE', PChar(lOldEngine));
  end;
end;

procedure TTestTimeBoundaries.HistoricalHourlyRun;
var
  g: TGarbos;
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lWallUs: Int64;
begin
  lWallUs := GridMs(EncodeDateTime(2026, 11, 16, 11, 0, 0, 0)) * 1000 - 400;
  SetMaxCronWallClockHook(function: Int64 begin Result := lWallUs; end);
  try
    GC(lCron, TmaxCron.Create(ctPortable), g);
    lEvent := lCron.Add('R5');
    lEvent.EventPlan := '0 * * * *';
    lEvent.Run;
    Assert.AreEqual(EncodeDateTime(2026, 11, 16, 11, 0, 0, 0), lEvent.NextSchedule, 0.0,
      'R5 hourly Run at 10:59:59.999600');
  finally
    g.Clear;
    SetMaxCronWallClockHook(nil);
  end;
end;

procedure TTestTimeBoundaries.WatchdogMicrosecondThreshold;
const
  cOffsets: array[0..8] of Integer = (-501, -500, -499, -1, 0, 1, 499, 500, 501);
  cTickUs: Int64 = 4000000000000000;
var
  g: TGarbos;
  lCron: TmaxCron;
  lWallUs: Int64;
  lDiagnostics: TMaxCronWatchdogDiagnostics;
begin
  lWallUs := cTickUs;
  SetMaxCronWallClockHook(function: Int64 begin Result := lWallUs; end);
  try
    GC(lCron, TmaxCron.Create(ctPortable), g);
    Assert.IsTrue(lCron.TryGetWatchdogDiagnostics(lDiagnostics));
    for var d in cOffsets do
    begin
      lWallUs := cTickUs + Int64(lDiagnostics.MaxTickLagMs) * 1000 + d;
      lCron.TickAtUs(cTickUs);
      Assert.IsTrue(lCron.TryGetWatchdogDiagnostics(lDiagnostics));
      Assert.AreEqual(d > 0, lDiagnostics.TickLagBreached, 'Watchdog offset us=' + IntToStr(d));
      Assert.AreEqual(Cardinal((lWallUs - cTickUs + 500) div 1000), lDiagnostics.TickLagMs,
        'Reported lag rounds independently of threshold');
    end;
  finally
    g.Clear;
    SetMaxCronWallClockHook(nil);
  end;
end;

end.

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
    [TestCase('second', '0')]
    [TestCase('minute', '1')]
    [TestCase('hour', '2')]
    [TestCase('day', '3')]
    procedure CalculationApiContract(const aPeriodIndex: Integer);
    [Test] procedure CalculationValidityRepresentation;
    [Test] procedure ExactMsReference;
    [Test] procedure ExactMsQueries;
    [Test] procedure WeekdaysDocumentedContract;
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

type
  TExactMsRow = record
    Bits: Int64;
    Ms: Int64;
  end;

{$I TestTimeBoundariesExactMs.inc}

function GridMs(const aValue: TDateTime): Int64;
var
  lStamp: TTimeStamp;
begin
  if aValue = 0 then
    Exit(0);
  lStamp := DateTimeToTimeStamp(aValue);
  Result := (Int64(lStamp.Date) - DateDelta) * MSecsPerDay + lStamp.Time;
end;

// Independent exact carrier interpretation, without the production conversion and without
// Double arithmetic: the 128-bit product of the integer mantissa and 86400000 is shifted by
// the binary exponent and rounded on its guard and sticky bits (nearest, ties to even).
function CarrierMs(const aValue: TDateTime): Int64;
const
  cMask32: UInt64 = $FFFFFFFF;
var
  lBits, lMantissa, lLowPart, lHighPart, lMiddle, lLo, lHi, lQuotient: UInt64;
  lExponent, lShift: Integer;
  lGuard, lSticky: Boolean;
begin
  if IsNan(aValue) or not (aValue > 0) then
    Exit(0);
  if aValue >= 2958466 then
    Exit(Int64(2958466) * MSecsPerDay);
  Move(aValue, lBits, SizeOf(lBits));
  lExponent := Integer((lBits shr 52) and $7FF);
  lMantissa := lBits and (UInt64(1) shl 52 - 1);
  if lExponent = 0 then
    lExponent := 1
  else
    lMantissa := lMantissa or (UInt64(1) shl 52);
  // aValue * 86400000 = (lHi:lLo) / 2^lShift with (lHi:lLo) = lMantissa * 86400000 < 2^80.
  lShift := 1075 - lExponent;
  lLowPart := (lMantissa and cMask32) * 86400000;
  lHighPart := (lMantissa shr 32) * 86400000;
  // Limb 1 collects the upper half of the low product and the lower half of the high product.
  lMiddle := (lLowPart shr 32) + (lHighPart and cMask32);
  lLo := (lLowPart and cMask32) or ((lMiddle and cMask32) shl 32);
  lHi := (lHighPart shr 32) + (lMiddle shr 32);
  if lShift >= 82 then
    Exit(0);
  if lShift >= 64 then
  begin
    lQuotient := lHi shr (lShift - 64);
    if lShift = 64 then
      lGuard := (lLo shr 63) <> 0
    else
      lGuard := ((lHi shr (lShift - 65)) and 1) <> 0;
    if lShift = 64 then
      lSticky := (lLo and (UInt64(1) shl 63 - 1)) <> 0
    else
      lSticky := (lLo <> 0) or ((lHi and (UInt64(1) shl (lShift - 65) - 1)) <> 0);
  end else begin
    lQuotient := (lLo shr lShift) or (lHi shl (64 - lShift));
    lGuard := ((lLo shr (lShift - 1)) and 1) <> 0;
    lSticky := (lLo and (UInt64(1) shl (lShift - 1) - 1)) <> 0;
  end;
  if lGuard and (lSticky or ((lQuotient and 1) <> 0)) then
    Inc(lQuotient);
  Result := Int64(lQuotient);
end;

function CarrierUs(const aValue: TDateTime): Int64;
begin
  Result := CarrierMs(aValue) * 1000;
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


procedure TTestTimeBoundaries.CalculationApiContract(const aPeriodIndex: Integer);
const
  cOffsetsMs: array[0..6] of Integer = (-1001, -1000, -1, 0, 1, 999, 1000);
var
  g: TGarbos;
  lPlan: TCronSchedulePlan;
  lDates: TDates;
  lSeed: UInt64;
  lDueMs, lPeriodMs, lInputMs, lExpectedNext, lExpectedPrevious, lFirst, lLast: Int64;
  lBase, lEnd, lNext, lPrevious: TDateTime;
  lVariant, lOffset, lNeighbour, lExpectedCount: Integer;
  lHint: string;
begin
  GC(lPlan, TCronSchedulePlan.Create, g);
  lPlan.Parse(cPlans[aPeriodIndex]);
  lSeed := 20261116;
  lPeriodMs := Int64(cPeriods[aPeriodIndex]) * 1000;
  // i 0..63 keep the original 2000..2999 dues; i 64..95 add the early domain from 1900-01-06.
  for var i := 0 to 95 do
  begin
    lSeed := (lSeed * 1664525 + 1013904223) and $FFFFFFFF;
    if i < 64 then
      lDueMs := (Int64(36526) + Int64(lSeed mod 365000)) * MSecsPerDay
    else
      lDueMs := (Int64(7) + Int64(lSeed mod 36519)) * MSecsPerDay;
    lDueMs := lDueMs + (Int64(lSeed mod 86400) * 1000 div lPeriodMs) * lPeriodMs;
    for lOffset in cOffsetsMs do
      for lVariant := 0 to 3 do
        for lNeighbour := -4 to 4 do
        begin
          case lVariant of
            0: lBase := CronInstantUsToDateTime((lDueMs + lOffset) * 1000);
            1: lBase := IncMilliSecond(CronInstantUsToDateTime(lDueMs * 1000), lOffset);
            2: lBase := (lDueMs + lOffset - 0.4999) / 86400000.0;
          else
            lBase := (lDueMs + lOffset + 0.4999) / 86400000.0;
          end;
          lBase := Neighbour(lBase, lNeighbour);
          lInputMs := CarrierUs(lBase) div 1000;
          lExpectedNext := (lInputMs div lPeriodMs + 1) * lPeriodMs;
          lExpectedPrevious := ((lInputMs + lPeriodMs - 1) div lPeriodMs - 1) * lPeriodMs;
          lHint := Format('G7 seed=20261116 i=%d plan=%s dueMs=%d offset=%d variant=%d ulp=%d inputMs=%d',
            [i, cPlans[aPeriodIndex], lDueMs, lOffset, lVariant, lNeighbour, lInputMs]);
          Assert.IsTrue(lPlan.FindNextScheduleDate(lBase, lNext), lHint + ' next found');
          Assert.AreEqual(lExpectedNext, GridMs(lNext), lHint + ' next');
          Assert.IsTrue(lPlan.FindPreviousScheduleDate(lBase, lPrevious), lHint + ' previous found');
          Assert.AreEqual(lExpectedPrevious, GridMs(lPrevious), lHint + ' previous');
          Assert.AreEqual(3, lPlan.GetNextOccurrences(3, lBase, lDates), lHint + ' next page count');
          for var j := 0 to 2 do
            Assert.AreEqual(lExpectedNext + j * lPeriodMs, GridMs(lDates[j]), lHint + ' next page');
          Assert.AreEqual(3, lPlan.GetPreviousOccurrences(3, lBase, lDates), lHint + ' previous page count');
          for var j := 0 to 2 do
            Assert.AreEqual(lExpectedPrevious - j * lPeriodMs, GridMs(lDates[j]), lHint + ' previous page');
          lEnd := CronInstantUsToDateTime((lInputMs + 2 * lPeriodMs) * 1000);
          lFirst := ((lInputMs + lPeriodMs - 1) div lPeriodMs) * lPeriodMs;
          lLast := ((CarrierUs(lEnd) div 1000 + lPeriodMs - 1) div lPeriodMs - 1) * lPeriodMs;
          lExpectedCount := (lLast - lFirst) div lPeriodMs + 1;
          Assert.AreEqual(lExpectedCount, lPlan.GetOccurrencesBetween(lBase, lEnd, lDates), lHint + ' range count');
          for var j := 0 to lExpectedCount - 1 do
            Assert.AreEqual(lFirst + j * lPeriodMs, GridMs(lDates[j]), lHint + ' range member');
          Assert.AreEqual(lExpectedCount, lPlan.CountBetween(lBase, lEnd), lHint + ' count');
          Assert.IsTrue(lPlan.HasOccurrenceBetween(lBase, lEnd), lHint + ' has');
        end;
  end;
end;

procedure TTestTimeBoundaries.CalculationValidityRepresentation;
var
  g: TGarbos;
  lPlan: TCronSchedulePlan;
  lDue, lBase, lNext: TDateTime;
  lDueMs: Int64;
begin
  GC(lPlan, TCronSchedulePlan.Create, g);
  lPlan.Parse('* * * * * * *');
  for var y in [1900, 2000, 2026, 2079, 2100, 2500, 2999] do
  begin
    lDue := EncodeDateTime(y, 11, 16, 10, 0, 0, 0);
    lDueMs := GridMs(lDue);
    lBase := IncSecond(lDue, -1);
    Assert.IsTrue(lPlan.FindNextScheduleDate(lBase, lNext, 0, Neighbour(lDue, -1)),
      'P1 nearest-ms equality year=' + IntToStr(y));
    Assert.AreEqual(lDueMs, GridMs(lNext));
    Assert.IsTrue(lPlan.FindNextScheduleDate(IncSecond(lDue, -10), lNext, lDue, 0));
    Assert.AreEqual(lDueMs + 1000, GridMs(lNext), 'Q4 exclusive ValidFrom stays');
    lPlan.Parse('0 23 * * *');
    Assert.IsTrue(lPlan.FindNextScheduleDate(lBase, lNext, 0, lDue));
    Assert.AreEqual(GridMs(EncodeDateTime(y, 11, 16, 23, 0, 0, 0)), GridMs(lNext),
      'Q4 ValidTo overshoot stays');
    lPlan.Parse('* * * * * * *');
  end;
end;

procedure TTestTimeBoundaries.ExactMsReference;
var
  lValue: TDateTime;
  lFailures, lCarrierFailures: Integer;
  lFirst: string;
begin
  lFailures := 0;
  lCarrierFailures := 0;
  lFirst := '';
  for var i := Low(cExactMsRows) to High(cExactMsRows) do
  begin
    Move(cExactMsRows[i].Bits, lValue, SizeOf(lValue));
    if CarrierMs(lValue) <> cExactMsRows[i].Ms then
      Inc(lCarrierFailures);
    if (CronDateTimeToMs(lValue) <> cExactMsRows[i].Ms) or
      (CronDateTimeToInstantUs(lValue) <> cExactMsRows[i].Ms * cCronUsPerMs) then
    begin
      Inc(lFailures);
      if lFirst = '' then
        lFirst := Format('row=%d bits=%s expectedMs=%d actualMs=%d',
          [i, IntToHex(cExactMsRows[i].Bits, 16), cExactMsRows[i].Ms, CronDateTimeToMs(lValue)]);
    end;
  end;
  Assert.AreEqual(0, lCarrierFailures, 'Test carrier reference disagrees with the exact rational table');
  Assert.AreEqual(0, lFailures, Format('Exact ms conversion failures=%d of %d; first %s',
    [lFailures, Length(cExactMsRows), lFirst]));
end;

procedure TTestTimeBoundaries.ExactMsQueries;
const
  // Review r1 inputs within 2^-35 ms of a half millisecond: bits, previous ms, next ms.
  cReview: array[0..5, 0..2] of Int64 = (
    ($400015DAD5EBA115, 173722000, 173723000),
    ($40001A252A145EEB, 173902000, 173903000),
    ($405900CDF0186B11, 8641086000, 8641087000),
    ($405901320FE794EF, 8641613000, 8641614000),
    ($4076D64C474E8B07, 31570009000, 31570010000),
    ($4076D653B8B174F9, 31570165000, 31570166000));
var
  g: TGarbos;
  lPlan: TCronSchedulePlan;
  lValue, lResult, lEnd: TDateTime;
  lDates: TDates;
  lMs, lFloor, lCeil, lMinMs, lMaxMs: Int64;
  lCount, lChecked: Integer;
  lHint: string;
begin
  GC(lPlan, TCronSchedulePlan.Create, g);
  lPlan.Parse('* * * * * * *');
  for var r := 0 to 5 do
  begin
    Move(cReview[r, 0], lValue, SizeOf(lValue));
    lHint := 'review r1 bits=' + IntToHex(cReview[r, 0], 16);
    Assert.IsTrue(lPlan.FindPreviousScheduleDate(lValue, lResult), lHint);
    Assert.AreEqual(cReview[r, 1], GridMs(lResult), lHint + ' previous');
    Assert.IsTrue(lPlan.FindNextScheduleDate(lValue, lResult), lHint);
    Assert.AreEqual(cReview[r, 2], GridMs(lResult), lHint + ' next');
  end;
  lMinMs := GridMs(EncodeDate(1900, 1, 3));
  lMaxMs := GridMs(EncodeDate(3000, 12, 29));
  lChecked := 0;
  for var i := Low(cExactMsRows) to High(cExactMsRows) do
  begin
    lMs := cExactMsRows[i].Ms;
    if (lMs < lMinMs) or (lMs > lMaxMs) then
      Continue;
    Move(cExactMsRows[i].Bits, lValue, SizeOf(lValue));
    Inc(lChecked);
    lFloor := (lMs div 1000) * 1000;
    lCeil := ((lMs + 999) div 1000) * 1000;
    lHint := Format('bits=%s exactMs=%d', [IntToHex(cExactMsRows[i].Bits, 16), lMs]);
    Assert.IsTrue(lPlan.FindNextScheduleDate(lValue, lResult), lHint);
    Assert.AreEqual(lFloor + 1000, GridMs(lResult), lHint + ' next');
    Assert.IsTrue(lPlan.FindPreviousScheduleDate(lValue, lResult), lHint);
    Assert.AreEqual(lCeil - 1000, GridMs(lResult), lHint + ' previous');
    // Inclusive start: [value, floor + 2.5 s).
    lEnd := CronMsToDateTime(lFloor + 2500);
    lCount := (lFloor + 2000 - lCeil) div 1000 + 1;
    Assert.AreEqual(lCount, lPlan.GetOccurrencesBetween(lValue, lEnd, lDates), lHint + ' range count');
    for var j := 0 to lCount - 1 do
      Assert.AreEqual(lCeil + j * 1000, GridMs(lDates[j]), lHint + ' range member');
    Assert.AreEqual(lCount, lPlan.CountBetween(lValue, lEnd), lHint + ' count');
    Assert.IsTrue(lPlan.HasOccurrenceBetween(lValue, lEnd), lHint + ' has');
    // Exclusive end: [floor - 2 s, value).
    lCount := (lCeil - lFloor + 1000) div 1000 + 1;
    Assert.AreEqual(lCount, lPlan.GetOccurrencesBetween(CronMsToDateTime(lFloor - 2000), lValue, lDates),
      lHint + ' end count');
    Assert.AreEqual(lCeil - 1000, GridMs(lDates[lCount - 1]), lHint + ' last before end');
    // Validity inputs: ValidFrom stays exclusive and ValidTo admits nearest-ms equality.
    Assert.IsTrue(lPlan.FindNextScheduleDate(CronMsToDateTime(lFloor - 5000), lResult, lValue, 0),
      lHint + ' valid from');
    Assert.AreEqual(lFloor + 1000, GridMs(lResult), lHint + ' valid from next');
    Assert.AreEqual(lCeil = lMs, lPlan.FindNextScheduleDate(CronMsToDateTime(lCeil - 1000), lResult, 0, lValue),
      lHint + ' valid to');
    if lCeil = lMs then
      Assert.AreEqual(lMs, GridMs(lResult), lHint + ' valid to equality');
  end;
  Assert.IsTrue(lChecked > 2000, 'Exact query rows checked=' + IntToStr(lChecked));
end;

procedure TTestTimeBoundaries.WeekdaysDocumentedContract;
var
  g: TGarbos;
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lWallUs, lMondayMs, lDayMs, lExpectedMs: Int64;
  lFires: Integer;
begin
  lMondayMs := GridMs(EncodeDate(2030, 1, 7));
  lWallUs := lMondayMs * 1000;
  SetMaxCronWallClockHook(function: Int64 begin Result := lWallUs; end);
  try
    GC(lCron, TmaxCron.Create(ctPortable), g);
    lEvent := lCron.Add('weekdays-contract');
    lEvent.EventPlan := '* * * * * * *';
    lEvent.WeekdaysOnly := True;
    lEvent.InvokeMode := imMainThread;
    lEvent.OnScheduleProc := procedure(aSender: IMaxCronEvent) begin Inc(lFires); end;
    for var i := 0 to 6 do
    begin
      lEvent.Stop;
      lDayMs := lMondayMs + Int64(i) * MSecsPerDay;
      lWallUs := lDayMs * 1000 - 1000;
      lEvent.Run;
      lExpectedMs := lDayMs;
      if i >= 5 then
        lExpectedMs := lMondayMs + Int64(7) * MSecsPerDay;
      Assert.AreEqual(lExpectedMs, GridMs(lEvent.NextSchedule), 'ISO weekday=' + IntToStr(i + 1));
    end;
    lEvent.Stop;
    lDayMs := lMondayMs + Int64(5) * MSecsPerDay;
    lWallUs := lDayMs * 1000 - 1000001;
    lEvent.Run;
    lFires := 0;
    lCron.TickAtUs(lDayMs * 1000 - 1000); // Friday 23:59:59.999, due less than 1 s ago.
    Assert.AreEqual(1, lFires, 'Friday remains allowed through its last millisecond');
    lCron.TickAtUs(lDayMs * 1000); // Saturday 00:00:00.000.
    Assert.AreEqual(1, lFires, 'Saturday midnight is excluded');
    Assert.AreEqual(lMondayMs + Int64(7) * MSecsPerDay, GridMs(lEvent.NextSchedule));
  finally
    g.Clear;
    SetMaxCronWallClockHook(nil);
  end;
end;

end.

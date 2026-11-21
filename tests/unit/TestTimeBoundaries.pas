unit TestTimeBoundaries;
{$I maxCron.inc}

interface

uses
  {$IFDEF FPC}
  Windows,
  DateUtils, Math, SysUtils,
  AutoFree, DUnitX.TestFramework,
  maxCron, maxCron.Internal.TimeZone, TestZoneFakes
  {$ELSE}
  System.DateUtils, System.Math, System.SysUtils,
  Winapi.Windows,
  AutoFree, DUnitX.TestFramework,
  maxCron, maxCron.Internal.TimeZone, TestZoneFakes
  {$ENDIF};

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
    [TestCase('LOCAL-scan', 'LOCAL,scan')]
    [TestCase('LOCAL-heap', 'LOCAL,heap')]
    [TestCase('LOCAL-shadow', 'LOCAL,shadow')]
    [TestCase('Q4-Fixed-scan', 'Q4/Fixed,scan')]
    [TestCase('Q4-Fixed-heap', 'Q4/Fixed,heap')]
    [TestCase('Q4-Fixed-shadow', 'Q4/Fixed,shadow')]
    procedure CronValidityToStopsDispatch(const aZone, aEngine: string);
    [TestCase('LOCAL-scan', 'LOCAL,scan')]
    [TestCase('LOCAL-heap', 'LOCAL,heap')]
    [TestCase('LOCAL-shadow', 'LOCAL,shadow')]
    [TestCase('Q4-Fixed-scan', 'Q4/Fixed,scan')]
    [TestCase('Q4-Fixed-heap', 'Q4/Fixed,heap')]
    [TestCase('Q4-Fixed-shadow', 'Q4/Fixed,shadow')]
    procedure CronValidityInclusiveDispatch(const aZone, aEngine: string);
    [TestCase('LOCAL-scan', 'LOCAL,scan')]
    [TestCase('LOCAL-heap', 'LOCAL,heap')]
    [TestCase('LOCAL-shadow', 'LOCAL,shadow')]
    [TestCase('Q4-Fixed-scan', 'Q4/Fixed,scan')]
    [TestCase('Q4-Fixed-heap', 'Q4/Fixed,heap')]
    [TestCase('Q4-Fixed-shadow', 'Q4/Fixed,shadow')]
    procedure CronValidityExclusionAdvances(const aZone, aEngine: string);
    [TestCase('LOCAL-scan', 'LOCAL,scan')]
    [TestCase('LOCAL-heap', 'LOCAL,heap')]
    [TestCase('LOCAL-shadow', 'LOCAL,shadow')]
    [TestCase('Q4-Fixed-scan', 'Q4/Fixed,scan')]
    [TestCase('Q4-Fixed-heap', 'Q4/Fixed,heap')]
    [TestCase('Q4-Fixed-shadow', 'Q4/Fixed,shadow')]
    procedure CronValidityRestoreAndReschedule(const aZone, aEngine: string);
    [Test] procedure CronValidityPlanGenerated;
    [Test] procedure CronValidityPlanToOvershoot;
    [Test] procedure CronValidityAfterDstConversion;
    [Test] procedure CalculationValidityRepresentation;
    [Test] procedure CarrierDomainContracts;
    [Test] procedure ExactMsReference;
    [Test] procedure ExactMsQueries;
    [Test] procedure WeekdaysDocumentedContract;
    [Test] procedure HistoricalBlackoutStart;
    [Test] procedure HistoricalBlackoutEnd;
    [Test] procedure GeneratedBlackoutWindows;
    [Test] procedure BlackoutPreciseTicks;
    [Test] procedure GeneratedExcludedDates;
    [Test] procedure FakeDstPolicies;
    [Test] procedure GeneratedUtcOffsetHours;
    [Test] procedure GeneratedDstSearchEdges;
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

// Zone oracles use signed calendar carriers; the rational table above describes
// the scheduler conversion's clamped domain. Keep those two contracts separate.
function CalendarCarrierMs(const aValue: TDateTime): Int64;
begin
  // As in Phase 7, classify NaN before any ordered comparison under FPC.
  if IsNan(aValue) then
    Exit(0);
  if not (aValue < 0) then
    Exit(CarrierMs(aValue));
  // Negative infinity is outside the calendar domain. Never pass it to Trunc:
  // Delphi masks that invalid operation, while FPC raises EInvalidOp.
  if IsInfinite(aValue) then
    Exit(0);
  Result := 2 * Trunc(aValue) * MSecsPerDay + CarrierMs(-aValue);
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
  p: Integer;
  i: Integer;
  j: Integer;
  v: Integer;
  k: Integer;
  g: TGarbos;
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lWallUs, lDueUs, lTickUs, lModelUs, lNextUs, lLastUs, lPeriodUs: Int64;
  lCount, lExpected, lFailures, lChecks, lOffset, lVariant, lDistance: Integer;
  lSeed: Cardinal;
  lDue, lTick, lOriginal: TDateTime;
  lOldEngine, lFirst: string;
begin
  lOldEngine := {$IFDEF FPC}SysUtils.{$ENDIF}GetEnvironmentVariable('MAXCRON_ENGINE');
  SetEnvironmentVariableW('MAXCRON_ENGINE', PChar(aEngine));
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
    for p := 0 to 3 do
    begin
      lEvent.Stop;
      lEvent.EventPlan := cPlans[p];
      lPeriodUs := Int64(cPeriods[p]) * cUsPerSecond;
      for i := 0 to 63 do
      begin
        lDueUs := DueSecond(i, cPeriods[p]) * cUsPerSecond;
        lWallUs := lDueUs - cUsPerSecond;
        lDue := IncSecond(EncodeDate(1899, 12, 30), lDueUs div cUsPerSecond);
        lEvent.Stop;
        lEvent.ValidFrom := IncSecond(lDue, -1);
        for j := 0 to High(cOffsets) + 8 do
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
          for v := 0 to lVariant do
          begin
            if v = 0 then
              lOriginal := lTickUs / cUsPerDay
            else
              lOriginal := IncMilliSecond(lDue, lOffset div 1000);
            if aCarrier then
              lDistance := 4
            else
              lDistance := 0;
            for k := -lDistance to lDistance do
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
          for k := 0 to 2 do
          begin
            lOriginal := lDue + k * (1.0 / 24 / 60 / 60);
            for j := -4 to 4 do
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
    SetEnvironmentVariableW('MAXCRON_ENGINE', PChar(lOldEngine));
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
  p: Integer;
  i: Integer;
  d: Int64;
  g: TGarbos;
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lWallUs, lDueUs, lExpected: Int64;
  lFailures, lChecks: Integer;
  lOldEngine, lFirst: string;
begin
  lOldEngine := {$IFDEF FPC}SysUtils.{$ENDIF}GetEnvironmentVariable('MAXCRON_ENGINE');
  SetEnvironmentVariableW('MAXCRON_ENGINE', PChar(aEngine));
  lWallUs := GridMs(EncodeDate(1989, 1, 1)) * 1000;
  SetMaxCronWallClockHook(function: Int64 begin Result := lWallUs; end);
  lFailures := 0;
  lChecks := 0;
  lFirst := '';
  try
    GC(lCron, TmaxCron.Create(ctPortable), g);
    lEvent := lCron.Add('run-base');
    for p := 0 to 3 do
    begin
      lEvent.Stop;
      lEvent.EventPlan := cPlans[p];
      for i := 0 to 63 do
      begin
        lDueUs := DueSecond(i, cPeriods[p]) * cUsPerSecond;
        for d in cDeltas do
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
    SetEnvironmentVariableW('MAXCRON_ENGINE', PChar(lOldEngine));
  end;
end;

procedure TTestTimeBoundaries.HistoricalSubMs(const aEngine: string);
const
  cLate: array[0..2] of Integer = (999600, 999900, 1000000);
var
  d: Int64;
  g: TGarbos;
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lWallUs, lDueUs: Int64;
  lCount, lExpected: Integer;
  lOldEngine: string;
begin
  lOldEngine := {$IFDEF FPC}SysUtils.{$ENDIF}GetEnvironmentVariable('MAXCRON_ENGINE');
  SetEnvironmentVariableW('MAXCRON_ENGINE', PChar(aEngine));
  lDueUs := GridMs(EncodeDateTime(2026, 11, 16, 11, 0, 0, 0)) * 1000;
  lWallUs := lDueUs - cUsPerSecond;
  SetMaxCronWallClockHook(function: Int64 begin Result := lWallUs; end);
  try
    GC(lCron, TmaxCron.Create(ctPortable), g);
    lCron.DefaultMisfirePolicy := TmaxCronMisfirePolicy.mpSkip;
    lEvent := lCron.Add('R4', cPlans[0], procedure(aSender: IMaxCronEvent) begin Inc(lCount); end);
    lEvent.InvokeMode := imMainThread;
    for d in cLate do
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
    SetEnvironmentVariableW('MAXCRON_ENGINE', PChar(lOldEngine));
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
  d: Int64;
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
    for d in cOffsets do
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
  i: Integer;
  j: Integer;
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
  for i := 0 to 95 do
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
          for j := 0 to 2 do
            Assert.AreEqual(lExpectedNext + j * lPeriodMs, GridMs(lDates[j]), lHint + ' next page');
          Assert.AreEqual(3, lPlan.GetPreviousOccurrences(3, lBase, lDates), lHint + ' previous page count');
          for j := 0 to 2 do
            Assert.AreEqual(lExpectedPrevious - j * lPeriodMs, GridMs(lDates[j]), lHint + ' previous page');
          lEnd := CronInstantUsToDateTime((lInputMs + 2 * lPeriodMs) * 1000);
          lFirst := ((lInputMs + lPeriodMs - 1) div lPeriodMs) * lPeriodMs;
          lLast := ((CarrierUs(lEnd) div 1000 + lPeriodMs - 1) div lPeriodMs - 1) * lPeriodMs;
          lExpectedCount := (lLast - lFirst) div lPeriodMs + 1;
          Assert.AreEqual(lExpectedCount, lPlan.GetOccurrencesBetween(lBase, lEnd, lDates), lHint + ' range count');
          for j := 0 to lExpectedCount - 1 do
            Assert.AreEqual(lFirst + j * lPeriodMs, GridMs(lDates[j]), lHint + ' range member');
          Assert.AreEqual(lExpectedCount, lPlan.CountBetween(lBase, lEnd), lHint + ' count');
          Assert.IsTrue(lPlan.HasOccurrenceBetween(lBase, lEnd), lHint + ' has');
        end;
  end;
end;


type
  TValidityStore = class(TInterfacedObject, IMaxCronScheduleStore)
  private
    fStates: TArray<TMaxCronPersistedEvent>;
  public
    procedure Save(const aEvents: TArray<TMaxCronPersistedEvent>);
    function TryLoad(out aEvents: TArray<TMaxCronPersistedEvent>): Boolean;
  end;

procedure TValidityStore.Save(const aEvents: TArray<TMaxCronPersistedEvent>);
begin
  fStates := Copy(aEvents);
end;

function TValidityStore.TryLoad(out aEvents: TArray<TMaxCronPersistedEvent>): Boolean;
begin
  aEvents := Copy(fStates);
  Result := True;
end;

procedure TTestTimeBoundaries.CronValidityToStopsDispatch(const aZone, aEngine: string);
var
  g: TGarbos;
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lWallUs, lDueMs: Int64;
  lFires: Integer;
  lOldEngine: string;
begin
  lOldEngine := {$IFDEF FPC}SysUtils.{$ENDIF}GetEnvironmentVariable('MAXCRON_ENGINE');
  SetEnvironmentVariableW('MAXCRON_ENGINE', PChar(aEngine));
  SetCronSystemTimeZoneForTests(TZoneAsSystemZone.Create(CreateCronZone('UTC', TCronFixedZoneSource.Create(0))));
  RegisterCronZoneForTests('Q4/Fixed', TCronFixedZoneSource.Create(7200000));
  lDueMs := ZoneMs(2026, 11, 16, 10);
  lWallUs := (lDueMs - 1800000) * cCronUsPerMs;
  lFires := 0;
  SetMaxCronWallClockHook(function: Int64 begin Result := lWallUs; end);
  try
    GC(lCron, TmaxCron.Create(ctPortable), g);
    lEvent := lCron.Add('valid-to-dispatch');
    lEvent.TimeZoneId := aZone;
    if aZone = 'LOCAL' then
      lEvent.EventPlan := '0 10 * * *'
    else
      lEvent.EventPlan := '0 12 * * *';
    lEvent.InvokeMode := imMainThread;
    lEvent.OnScheduleProc := procedure(aSender: IMaxCronEvent) begin Inc(lFires); end;
    lEvent.ValidTo := CronMsToDateTime(lDueMs - 900000);
    lEvent.Run;
    lWallUs := lDueMs * cCronUsPerMs;
    lCron.TickAtUs(lWallUs);
    // Tick before asserting disabled: the old implementation really dispatches at 10:00.
    Assert.AreEqual(0, lFires, 'A cron event fired after ValidTo');
    Assert.IsFalse(lEvent.Enabled, 'An exhausted validity window must disable the event');
  finally
    lEvent := nil;
    g.Clear;
    SetMaxCronWallClockHook(nil);
    SetCronSystemTimeZoneForTests(nil);
    ClearCronZonesForTests;
    SetEnvironmentVariableW('MAXCRON_ENGINE', PChar(lOldEngine));
  end;
end;

procedure TTestTimeBoundaries.CronValidityInclusiveDispatch(const aZone, aEngine: string);
var
  g: TGarbos;
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lWallUs, lDueMs: Int64;
  lFires, k: Integer;
  lOldEngine: string;
begin
  lOldEngine := {$IFDEF FPC}SysUtils.{$ENDIF}GetEnvironmentVariable('MAXCRON_ENGINE');
  SetEnvironmentVariableW('MAXCRON_ENGINE', PChar(aEngine));
  SetCronSystemTimeZoneForTests(TZoneAsSystemZone.Create(CreateCronZone('UTC', TCronFixedZoneSource.Create(0))));
  RegisterCronZoneForTests('Q4/Fixed', TCronFixedZoneSource.Create(7200000));
  lDueMs := ZoneMs(2026, 11, 16, 10);
  lWallUs := (lDueMs - 1800000) * cCronUsPerMs;
  SetMaxCronWallClockHook(function: Int64 begin Result := lWallUs; end);
  try
    GC(lCron, TmaxCron.Create(ctPortable), g);
    lEvent := lCron.Add('inclusive-validity');
    lEvent.TimeZoneId := aZone;
    lEvent.EventPlan := '0 * * * *';
    lEvent.InvokeMode := imMainThread;
    lEvent.OnScheduleProc := procedure(aSender: IMaxCronEvent) begin Inc(lFires); end;
    for k := -1 to 1 do
    begin
      lFires := 0;
      lWallUs := (lDueMs - 1800000) * cCronUsPerMs;
      lEvent.Stop;
      lEvent.ValidFrom := Neighbour(CronMsToDateTime(lDueMs), k);
      lEvent.ValidTo := Neighbour(CronMsToDateTime(lDueMs), -k);
      lEvent.Run;
      Assert.IsTrue(lEvent.Enabled, 'The single-point validity window has an occurrence');
      Assert.AreEqual(lDueMs, CronDateTimeToMs(lEvent.NextSchedule));
      lCron.TickAtUs(lWallUs);
      Assert.AreEqual(0, lFires, 'Do not fire before ValidFrom');
      lWallUs := lDueMs * cCronUsPerMs;
      lCron.TickAtUs(lWallUs);
      Assert.AreEqual(1, lFires, 'Both bounds include nearest-ms equality');
      lWallUs := (lDueMs + 3600000) * cCronUsPerMs;
      lCron.TickAtUs(lWallUs);
      Assert.AreEqual(1, lFires, 'Do not fire after ValidTo');
      Assert.IsFalse(lEvent.Enabled);
      // Strict-after-base still wins when base equals ValidFrom.
      lWallUs := lDueMs * cCronUsPerMs;
      lEvent.Run;
      Assert.IsFalse(lEvent.Enabled);
    end;
  finally
    lEvent := nil;
    g.Clear;
    SetMaxCronWallClockHook(nil);
    SetCronSystemTimeZoneForTests(nil);
    ClearCronZonesForTests;
    SetEnvironmentVariableW('MAXCRON_ENGINE', PChar(lOldEngine));
  end;
end;

procedure TTestTimeBoundaries.CronValidityExclusionAdvances(const aZone, aEngine: string);
var
  g: TGarbos;
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lWallUs, lDueMs: Int64;
  lFires, i: Integer;
  lOldEngine: string;
begin
  lOldEngine := {$IFDEF FPC}SysUtils.{$ENDIF}GetEnvironmentVariable('MAXCRON_ENGINE');
  SetEnvironmentVariableW('MAXCRON_ENGINE', PChar(aEngine));
  SetCronSystemTimeZoneForTests(TZoneAsSystemZone.Create(CreateCronZone('UTC', TCronFixedZoneSource.Create(0))));
  RegisterCronZoneForTests('Q4/Fixed', TCronFixedZoneSource.Create(7200000));
  SetMaxCronWallClockHook(function: Int64 begin Result := lWallUs; end);
  try
    GC(lCron, TmaxCron.Create(ctPortable), g);
    lEvent := lCron.Add('validity-advance');
    lEvent.TimeZoneId := aZone;
    lEvent.EventPlan := '0 * * * *';
    lEvent.InvokeMode := imMainThread;
    lEvent.OnScheduleProc := procedure(aSender: IMaxCronEvent) begin Inc(lFires); end;
    for i := 0 to 2 do
    begin
      lEvent.Stop;
      lEvent.WeekdaysOnly := False;
      lEvent.ExcludedDatesCsv := '';
      lEvent.BlackoutStartTime := 0;
      lEvent.BlackoutEndTime := 0;
      lDueMs := ZoneMs(2026, 11, 16, 10);
      case i of
        0: lEvent.ExcludedDatesCsv := '2026-11-16';
        1:
          begin
            lDueMs := ZoneMs(2026, 11, 21, 10);
            lEvent.WeekdaysOnly := True;
          end;
        2:
          begin
            lEvent.BlackoutStartTime := EncodeTime(10, 0, 0, 0);
            lEvent.BlackoutEndTime := EncodeTime(13, 0, 0, 0);
          end;
      end;
      lWallUs := (lDueMs - 1800000) * cCronUsPerMs;
      lEvent.ValidFrom := CronMsToDateTime(lDueMs);
      lEvent.ValidTo := CronMsToDateTime(lDueMs + 1800000);
      lFires := 0;
      lEvent.Run;
      lWallUs := (lDueMs + 3 * cCronMsPerDay) * cCronUsPerMs;
      lCron.TickAtUs(lWallUs);
      Assert.AreEqual(0, lFires, 'Exclusion advance crossed ValidTo, kind=' + IntToStr(i));
      Assert.IsFalse(lEvent.Enabled);
    end;
  finally
    lEvent := nil;
    g.Clear;
    SetMaxCronWallClockHook(nil);
    SetCronSystemTimeZoneForTests(nil);
    ClearCronZonesForTests;
    SetEnvironmentVariableW('MAXCRON_ENGINE', PChar(lOldEngine));
  end;
end;

procedure TTestTimeBoundaries.CronValidityRestoreAndReschedule(const aZone, aEngine: string);
var
  g: TGarbos;
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lStore: IMaxCronScheduleStore;
  lStates: TArray<TMaxCronPersistedEvent>;
  lWallUs, lDueMs: Int64;
  lFires: Integer;
  lOldEngine: string;
begin
  lOldEngine := {$IFDEF FPC}SysUtils.{$ENDIF}GetEnvironmentVariable('MAXCRON_ENGINE');
  SetEnvironmentVariableW('MAXCRON_ENGINE', PChar(aEngine));
  SetCronSystemTimeZoneForTests(TZoneAsSystemZone.Create(CreateCronZone('UTC', TCronFixedZoneSource.Create(0))));
  RegisterCronZoneForTests('Q4/Fixed', TCronFixedZoneSource.Create(7200000));
  lDueMs := ZoneMs(2026, 11, 16, 10);
  lWallUs := (lDueMs - 1800000) * cCronUsPerMs;
  lFires := 0;
  SetMaxCronWallClockHook(function: Int64 begin Result := lWallUs; end);
  try
    GC(lCron, TmaxCron.Create(ctPortable), g);
    lStore := TValidityStore.Create;
    lCron.ScheduleStore := lStore;
    lEvent := lCron.Add('validity-restore');
    lEvent.TimeZoneId := aZone;
    lEvent.EventPlan := '0 * * * *';
    lEvent.InvokeMode := imMainThread;
    lEvent.Run;
    lEvent.ValidFrom := CronMsToDateTime(lDueMs);
    Assert.AreEqual(lDueMs, CronDateTimeToMs(lEvent.NextSchedule), 'Reschedule includes ValidFrom');
    lEvent.ValidTo := CronMsToDateTime(lDueMs);
    Assert.IsTrue(lEvent.Enabled);
    Assert.AreEqual(1, lCron.SaveScheduleState);
    Assert.IsTrue(lStore.TryLoad(lStates));
    // A persisted next value from the old overshoot behaviour must be recomputed.
    lStates[0].NextSchedule := CronMsToDateTime(lDueMs + 3600000);
    lStore.Save(lStates);
    lEvent := nil;
    Assert.AreEqual(1, lCron.RestoreScheduleState(True));
    lEvent := lCron.Snapshot[0];
    lEvent.OnScheduleProc := procedure(aSender: IMaxCronEvent) begin Inc(lFires); end;
    Assert.AreEqual(lDueMs, CronDateTimeToMs(lEvent.NextSchedule), 'Restore rejects out-of-window next');
    lWallUs := lDueMs * cCronUsPerMs;
    lCron.TickAtUs(lWallUs);
    Assert.AreEqual(1, lFires);
    lWallUs := (lDueMs + 3600000) * cCronUsPerMs;
    lCron.TickAtUs(lWallUs);
    Assert.AreEqual(1, lFires);
    Assert.IsFalse(lEvent.Enabled);
  finally
    lEvent := nil;
    g.Clear;
    SetMaxCronWallClockHook(nil);
    SetCronSystemTimeZoneForTests(nil);
    ClearCronZonesForTests;
    SetEnvironmentVariableW('MAXCRON_ENGINE', PChar(lOldEngine));
  end;
end;

procedure TTestTimeBoundaries.CronValidityPlanToOvershoot;
var
  g: TGarbos;
  lPlan: TCronSchedulePlan;
  lNext: TDateTime;
  lDates: TDates;
begin
  GC(lPlan, TCronSchedulePlan.Create, g);
  lPlan.Parse('0 10 * * *');
  Assert.IsFalse(lPlan.FindNextScheduleDate(EncodeDateTime(2026, 11, 16, 9, 30, 0, 0),
    lNext, 0, EncodeDateTime(2026, 11, 16, 9, 45, 0, 0)), 'Hour push must recheck ValidTo');
  Assert.AreEqual(0, lPlan.GetNextOccurrences(20, EncodeDateTime(2026, 11, 16, 9, 30, 0, 0),
    lDates, 0, EncodeDateTime(2026, 11, 16, 9, 45, 0, 0)), 'Preview must recheck ValidTo');
end;

procedure TTestTimeBoundaries.CronValidityPlanGenerated;
const
  cYears: array[0..4] of Word = (1900, 2026, 2079, 2500, 2999);
  cDeltaMs: array[0..4] of Integer = (-1001, -1, 0, 1, 1001);
var
  g: TGarbos;
  lPlan: TCronSchedulePlan;
  lNext, lFrom, lTo: TDateTime;
  lDates: TDates;
  lDueMs, lFromMs, lToMs, lExpectedMs: Int64;
  lYear: Word;
  p, i, j, k: Integer;
  lFound, lExpectedFound: Boolean;
  lHint: string;
begin
  GC(lPlan, TCronSchedulePlan.Create, g);
  for lYear in cYears do
    for p := 0 to 3 do
    begin
      lPlan.Parse(cPlans[p]);
      lDueMs := GridMs(EncodeDateTime(lYear, 11, 16, 0, 0, 0, 0));
      for i := Low(cDeltaMs) to High(cDeltaMs) do
        for j := Low(cDeltaMs) to High(cDeltaMs) do
          for k := -1 to 1 do
          begin
            lFrom := Neighbour(CronMsToDateTime(lDueMs + cDeltaMs[i]), k);
            lTo := Neighbour(CronMsToDateTime(lDueMs + cDeltaMs[j]), -k);
            lFromMs := CarrierMs(lFrom);
            lToMs := CarrierMs(lTo);
            lExpectedMs := CronCeilDiv(lFromMs, Int64(cPeriods[p]) * 1000) * cPeriods[p] * 1000;
            lExpectedFound := lExpectedMs <= lToMs;
            lFound := lPlan.FindNextScheduleDate(CronMsToDateTime(lDueMs - 5000), lNext, lFrom, lTo);
            lHint := Format('year=%d period=%d from=%d to=%d ulp=%d', [lYear, cPeriods[p], lFromMs, lToMs, k]);
            Assert.AreEqual(lExpectedFound, lFound, lHint);
            if lFound then
              Assert.AreEqual(lExpectedMs, CarrierMs(lNext), lHint);
            Assert.AreEqual(Integer(Ord(lExpectedFound)), lPlan.GetNextOccurrences(1,
              CronMsToDateTime(lDueMs - 5000), lDates, lFrom, lTo), lHint + ' preview');
          end;
      // Original base is exclusive even when it is also the lower bound.
      Assert.IsFalse(lPlan.FindNextScheduleDate(CronMsToDateTime(lDueMs), lNext,
        CronMsToDateTime(lDueMs), CronMsToDateTime(lDueMs)));
      Assert.IsFalse(lPlan.FindNextScheduleDate(CronMsToDateTime(lDueMs + 1), lNext,
        CronMsToDateTime(lDueMs), CronMsToDateTime(lDueMs)));
    end;
end;

procedure TTestTimeBoundaries.CalculationValidityRepresentation;
var
  y: Int64;
  g: TGarbos;
  lPlan: TCronSchedulePlan;
  lDue, lBase, lNext: TDateTime;
  lDueMs: Int64;
begin
  GC(lPlan, TCronSchedulePlan.Create, g);
  lPlan.Parse('* * * * * * *');
  for y in TArray<Int64>.Create(1900, 2000, 2026, 2079, 2100, 2500, 2999) do
  begin
    lDue := EncodeDateTime(y, 11, 16, 10, 0, 0, 0);
    lDueMs := GridMs(lDue);
    lBase := IncSecond(lDue, -1);
    Assert.IsTrue(lPlan.FindNextScheduleDate(lBase, lNext, 0, Neighbour(lDue, -1)),
      'P1 nearest-ms equality year=' + IntToStr(y));
    Assert.AreEqual(lDueMs, GridMs(lNext));
    Assert.IsTrue(lPlan.FindNextScheduleDate(IncSecond(lDue, -10), lNext, lDue, 0));
    Assert.AreEqual(lDueMs, GridMs(lNext), 'Q4 inclusive ValidFrom');
    lPlan.Parse('0 23 * * *');
    Assert.IsFalse(lPlan.FindNextScheduleDate(lBase, lNext, 0, lDue),
      'Q4 no result after ValidTo');
    lPlan.Parse('* * * * * * *');
  end;
end;

procedure TTestTimeBoundaries.ExactMsReference;
var
  i: Integer;
  lValue: TDateTime;
  lFailures, lCarrierFailures: Integer;
  lFirst: string;
begin
  lFailures := 0;
  lCarrierFailures := 0;
  lFirst := '';
  for i := Low(cExactMsRows) to High(cExactMsRows) do
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
  r: Integer;
  i: Integer;
  j: Integer;
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
  for r := 0 to 5 do
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
  for i := Low(cExactMsRows) to High(cExactMsRows) do
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
    for j := 0 to lCount - 1 do
      Assert.AreEqual(lCeil + j * 1000, GridMs(lDates[j]), lHint + ' range member');
    Assert.AreEqual(lCount, lPlan.CountBetween(lValue, lEnd), lHint + ' count');
    Assert.IsTrue(lPlan.HasOccurrenceBetween(lValue, lEnd), lHint + ' has');
    // Exclusive end: [floor - 2 s, value).
    lCount := (lCeil - lFloor + 1000) div 1000 + 1;
    Assert.AreEqual(lCount, lPlan.GetOccurrencesBetween(CronMsToDateTime(lFloor - 2000), lValue, lDates),
      lHint + ' end count');
    Assert.AreEqual(lCeil - 1000, GridMs(lDates[lCount - 1]), lHint + ' last before end');
    // Validity inputs: both bounds admit nearest-ms equality.
    Assert.IsTrue(lPlan.FindNextScheduleDate(CronMsToDateTime(lFloor - 5000), lResult, lValue, 0),
      lHint + ' valid from');
    Assert.AreEqual(lCeil, GridMs(lResult), lHint + ' valid from next');
    Assert.AreEqual(lCeil = lMs, lPlan.FindNextScheduleDate(CronMsToDateTime(lCeil - 1000), lResult, 0, lValue),
      lHint + ' valid to');
    if lCeil = lMs then
      Assert.AreEqual(lMs, GridMs(lResult), lHint + ' valid to equality');
  end;
  Assert.IsTrue(lChecked > 2000, 'Exact query rows checked=' + IntToStr(lChecked));
end;

procedure TTestTimeBoundaries.WeekdaysDocumentedContract;
var
  i: Integer;
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
    for i := 0 to 6 do
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

// All references below use integer calendar arithmetic and CarrierMs, independently
// checked against Python Fraction fixtures by ExactMsReference. No production helper
// participates in the expected blackout, exclusion or timezone decisions.
function PolicyGrid(const aMs: Int64): TDateTime;
begin
  Result := IncMilliSecond(EncodeDate(1899, 12, 30), aMs);
end;

function ModelBlocked(const aMs, aStart, aEnd: Int64): Boolean;
var
  lTime: Int64;
begin
  if aStart = aEnd then
    Exit(False);
  lTime := aMs mod MSecsPerDay;
  if aStart < aEnd then
    Exit((lTime >= aStart) and (lTime < aEnd));
  Result := (lTime >= aStart) or (lTime < aEnd);
end;

function ModelBlackoutNext(const aBaseUs, aStart, aEnd, aPeriodSeconds: Int64): Int64;
var
  lSecond: Int64;
begin
  lSecond := (aBaseUs div (aPeriodSeconds * 1000000) + 1) * aPeriodSeconds;
  while ModelBlocked(lSecond * 1000, aStart, aEnd) do
    Inc(lSecond, aPeriodSeconds);
  Result := lSecond * 1000;
end;

type
  TBoundaryZone = class(TInterfacedObject, ICronTimeZone)
  private
    fSpringMs, fFallMs: Int64;
  public
    constructor Create;
    function ToUniversalTime(const aLocal: TDateTime; const aForceDaylight: Boolean): TDateTime;
    function ToLocalTime(const aUtc: TDateTime): TDateTime;
    function IsAmbiguousTime(const aLocal: TDateTime): Boolean;
    function IsInvalidTime(const aLocal: TDateTime): Boolean;
  end;

constructor TBoundaryZone.Create;
begin
  inherited;
  fSpringMs := GridMs(EncodeDate(2075, 3, 31));
  fFallMs := GridMs(EncodeDate(2075, 10, 27));
end;

function TBoundaryZone.ToUniversalTime(const aLocal: TDateTime;
  const aForceDaylight: Boolean): TDateTime;
var
  lMs, lOffset: Int64;
begin
  lMs := CalendarCarrierMs(aLocal);
  lOffset := 3600000;
  if (lMs >= fSpringMs + 10800000) and (lMs < fFallMs + 7200000) then
    lOffset := 7200000;
  if IsAmbiguousTime(aLocal) and aForceDaylight then
    lOffset := 7200000;
  Result := PolicyGrid(lMs - lOffset);
end;

function TBoundaryZone.ToLocalTime(const aUtc: TDateTime): TDateTime;
var
  lMs, lOffset: Int64;
begin
  lMs := CalendarCarrierMs(aUtc);
  lOffset := 3600000;
  if (lMs >= fSpringMs + 3600000) and (lMs < fFallMs + 3600000) then
    lOffset := 7200000;
  Result := PolicyGrid(lMs + lOffset);
end;

function TBoundaryZone.IsAmbiguousTime(const aLocal: TDateTime): Boolean;
var
  lMs: Int64;
begin
  lMs := CalendarCarrierMs(aLocal);
  Result := (lMs >= fFallMs + 7200000) and (lMs < fFallMs + 10800000);
end;

function TBoundaryZone.IsInvalidTime(const aLocal: TDateTime): Boolean;
var
  lMs: Int64;
begin
  lMs := CalendarCarrierMs(aLocal);
  Result := (lMs >= fSpringMs + 7200000) and (lMs < fSpringMs + 10800000);
end;

procedure TTestTimeBoundaries.CarrierDomainContracts;
const
  cSignedMs: array[0..8] of Int64 = (-172800001, -172800000, -86400001,
    -86400000, -86399999, -1001, -1, 0, 1);
  cClampedBits: array[0..2] of Int64 = (Int64($BFF0000000000000),
    Int64($C146924100000000), Int64($FFF0000000000000));
var
  lZone: ICronTimeZone;
  lValue, lLocal: TDateTime;
  lMs: Int64;
  i: Integer;
begin
  lZone := TBoundaryZone.Create;
  for lMs in cSignedMs do
  begin
    lValue := IncMilliSecond(EncodeDate(1899, 12, 30), lMs);
    lLocal := lZone.ToLocalTime(lValue);
    Assert.AreEqual(lMs + 3600000, GridMs(lLocal), 'signed fake UTC-to-local');
    Assert.AreEqual(lMs, GridMs(lZone.ToUniversalTime(lLocal, False)),
      'signed fake local-to-UTC');
  end;
  for i := Low(cClampedBits) to High(cClampedBits) do
  begin
    Move(cClampedBits[i], lValue, SizeOf(lValue));
    Assert.AreEqual(Int64(0), CarrierMs(lValue),
      'clamped carrier bits=' + IntToHex(cClampedBits[i], 16));
  end;
end;

procedure CheckHistoricalBlackout(const aStart: Boolean);
var
  g: TGarbos;
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lWallUs, lDayMs, lExpectedMs: Int64;
begin
  lDayMs := GridMs(EncodeDate(2075, 1, 2));
  lWallUs := (lDayMs + 21 * 3600000) * 1000;
  SetMaxCronWallClockHook(function: Int64 begin Result := lWallUs; end);
  try
    GC(lCron, TmaxCron.Create(ctPortable), g);
    lEvent := lCron.Add('blackout-22-regression');
    lEvent.EventPlan := '0 22 * * *';
    if aStart then
    begin
      lEvent.BlackoutStartTime := EncodeTime(22, 0, 0, 0);
      lEvent.BlackoutEndTime := EncodeTime(23, 0, 0, 0);
      // Every 22:00 is excluded, use every hour to observe the first allowed time.
      lEvent.EventPlan := '0 * * * *';
      lExpectedMs := lDayMs + 23 * 3600000;
    end else begin
      lEvent.BlackoutStartTime := EncodeTime(21, 0, 0, 0);
      lEvent.BlackoutEndTime := EncodeTime(22, 0, 0, 0);
      lExpectedMs := lDayMs + 22 * 3600000;
    end;
    lEvent.Run;
    Assert.AreEqual(lExpectedMs, CarrierMs(lEvent.NextSchedule), '22:00 inclusive start/exclusive end');
  finally
    g.Clear;
    SetMaxCronWallClockHook(nil);
  end;
end;

procedure TTestTimeBoundaries.HistoricalBlackoutStart;
begin
  CheckHistoricalBlackout(True);
end;

procedure TTestTimeBoundaries.HistoricalBlackoutEnd;
begin
  CheckHistoricalBlackout(False);
end;

procedure TTestTimeBoundaries.GeneratedBlackoutWindows;
const
  cYears: array[0..2] of Word = (2026, 2075, 2500);
var
  y: Integer;
  i: Integer;
  d: Integer;
  k: Integer;
  g: TGarbos;
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lWallUs, lDayMs, lStart, lEnd, lExpected, lBaseMs: Int64;
  lFailures, lChecks: Integer;
  lSeed: Cardinal;
  lFirst: string;
begin
  lSeed := 20261116;
  lWallUs := 0;
  lFailures := 0;
  lFirst := '';
  lChecks := 0;
  SetMaxCronWallClockHook(function: Int64 begin Result := lWallUs; end);
  try
    GC(lCron, TmaxCron.Create(ctPortable), g);
    lEvent := lCron.Add('generated-blackout');
    lEvent.EventPlan := '* * * * * * */15';
    for y := 0 to High(cYears) do
    begin
      lDayMs := GridMs(EncodeDate(cYears[y], 6, 5));
      for i := 0 to 47 do
        for d := -1 to 1 do
          for k := -4 to 4 do
          begin
            lEvent.Stop;
            lStart := Int64(i) * 1800000;
            lEnd := (lStart + 3600000) mod MSecsPerDay;
            if d = 1 then
              lEnd := (lStart + 3600500) mod MSecsPerDay;
            // d=-1 tests the end-at-T form, including wrapping across midnight.
            if d = -1 then
            begin
              lEnd := lStart;
              lStart := (lEnd + MSecsPerDay - 3600000) mod MSecsPerDay;
            end;
            // Zero has no negative finite neighbour in the allowed time-of-day domain.
            if lStart = 0 then
              lEvent.BlackoutStartTime := 0
            else
              lEvent.BlackoutStartTime := Neighbour(PolicyGrid(lStart), k);
            if lEnd = 0 then
              lEvent.BlackoutEndTime := 0
            else
              lEvent.BlackoutEndTime := Neighbour(PolicyGrid(lEnd), -k);
            lStart := CarrierMs(lEvent.BlackoutStartTime);
            lEnd := CarrierMs(lEvent.BlackoutEndTime);
            lBaseMs := lDayMs + lStart - 1;
            lWallUs := lBaseMs * 1000;
            lExpected := ModelBlackoutNext(lWallUs, lStart, lEnd, 15);
            lEvent.Run;
            Inc(lChecks);
            if CarrierMs(lEvent.NextSchedule) <> lExpected then
            begin
              Inc(lFailures);
              if lFirst = '' then
                lFirst := Format('year=%d T=%d form=%d ulp=%d baseMs=%d start=%d end=%d observed=%d expected=%d',
                  [cYears[y], i, d, k, lBaseMs, lStart, lEnd, CarrierMs(lEvent.NextSchedule), lExpected]);
            end;
          end;
    end;
    for i := 0 to 511 do
    begin
      lEvent.Stop;
      lSeed := (UInt64(lSeed) * 1664525 + 1013904223) and $FFFFFFFF;
      lStart := lSeed mod MSecsPerDay;
      lSeed := (UInt64(lSeed) * 1664525 + 1013904223) and $FFFFFFFF;
      lEnd := (lStart + 1 + lSeed mod (MSecsPerDay - 1)) mod MSecsPerDay;
      lEvent.BlackoutStartTime := PolicyGrid(lStart);
      lEvent.BlackoutEndTime := PolicyGrid(lEnd);
      lDayMs := GridMs(EncodeDate(cYears[i mod 3], 6, 5));
      lWallUs := (lDayMs + lStart - 1) * 1000;
      lExpected := ModelBlackoutNext(lWallUs, lStart, lEnd, 15);
      lEvent.Run;
      Inc(lChecks);
      if CarrierMs(lEvent.NextSchedule) <> lExpected then
      begin
        Inc(lFailures);
        if lFirst = '' then
          lFirst := Format('random=%d start=%d end=%d observed=%d expected=%d',
            [i, lStart, lEnd, CarrierMs(lEvent.NextSchedule), lExpected]);
      end;
    end;
    Assert.AreEqual(0, lFailures, Format('seed=20261116 checks=%d failures=%d first=%s',
      [lChecks, lFailures, lFirst]));
  finally
    g.Clear;
    SetMaxCronWallClockHook(nil);
  end;
end;

procedure TTestTimeBoundaries.BlackoutPreciseTicks;
const
  cEdges: array[0..3] of Integer = (6, 9, 17, 22);
  cDelta: array[0..8] of Integer = (-1000001, -1000, -400, -1, 0, 1, 400, 1000, 999999);
var
  w: Integer;
  i: Integer;
  j: Integer;
  g: TGarbos;
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lWallUs, lTickUs, lDueMs, lDayMs, lStart, lEnd, lExpectedMs: Int64;
  lFires, lExpectedFires: Integer;
begin
  lDayMs := GridMs(EncodeDate(2500, 12, 31));
  SetMaxCronWallClockHook(function: Int64 begin Result := lWallUs; end);
  try
    GC(lCron, TmaxCron.Create(ctPortable), g);
    lEvent := lCron.Add('precise-blackout');
    lEvent.EventPlan := '* * * * * * *';
    lEvent.InvokeMode := imMainThread;
    lEvent.OnScheduleProc := procedure(aSender: IMaxCronEvent) begin Inc(lFires); end;
    for w := 0 to 1 do
    begin
      if w = 0 then
      begin
        lStart := 9 * 3600000;
        lEnd := 17 * 3600000;
      end else begin
        lStart := 22 * 3600000;
        lEnd := 6 * 3600000;
      end;
      for i := 0 to High(cEdges) do
        for j := 0 to High(cDelta) do
        begin
          lEvent.Stop;
          lEvent.BlackoutStartTime := PolicyGrid(lStart);
          lEvent.BlackoutEndTime := PolicyGrid(lEnd);
          lTickUs := (lDayMs + Int64(cEdges[i]) * 3600000) * 1000 + cDelta[j];
          lDueMs := (lTickUs div 1000000) * 1000;
          lWallUs := lDueMs * 1000 - 1;
          lEvent.Run;
          lFires := 0;
          lCron.TickAtUs(lTickUs);
          lExpectedFires := 1;
          if ModelBlocked(lDueMs, lStart, lEnd) then
            lExpectedFires := 0;
          Assert.AreEqual(lExpectedFires, lFires, Format('window=%d edge=%d deltaUs=%d', [w, cEdges[i], cDelta[j]]));
          lExpectedMs := ModelBlackoutNext(lTickUs, lStart, lEnd, 1);
          Assert.AreEqual(lExpectedMs, CarrierMs(lEvent.NextSchedule));
        end;
    end;
  finally
    g.Clear;
    SetMaxCronWallClockHook(nil);
  end;
end;

procedure TTestTimeBoundaries.GeneratedExcludedDates;
var
  i: Integer;
  g: TGarbos;
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lWallUs, lDayMs: Int64;
  lFires: Integer;
  lDate: TDateTime;
begin
  SetMaxCronWallClockHook(function: Int64 begin Result := lWallUs; end);
  try
    GC(lCron, TmaxCron.Create(ctPortable), g);
    lEvent := lCron.Add('excluded-midnights');
    lEvent.EventPlan := '* * * * * * *';
    lEvent.InvokeMode := imMainThread;
    lEvent.OnScheduleProc := procedure(aSender: IMaxCronEvent) begin Inc(lFires); end;
    for i := 0 to 63 do
    begin
      lEvent.Stop;
      lDate := EncodeDate(2026 + i * 7, 1 + i mod 12, 1 + i mod 28);
      lDayMs := GridMs(lDate);
      lEvent.ExcludedDatesCsv := FormatDateTime('yyyy-mm-dd', lDate);
      lWallUs := lDayMs * 1000 - 1000001;
      lEvent.Run;
      lFires := 0;
      lCron.TickAtUs(lDayMs * 1000 - 1000);
      Assert.AreEqual(1, lFires, '23:59:59.999 of previous date runs');
      lCron.TickAtUs(lDayMs * 1000);
      Assert.AreEqual(1, lFires, '00:00:00 of excluded date does not run');
      Assert.AreEqual(lDayMs + MSecsPerDay, CarrierMs(lEvent.NextSchedule));
    end;
  finally
    g.Clear;
    SetMaxCronWallClockHook(nil);
  end;
end;

procedure TTestTimeBoundaries.FakeDstPolicies;
const
  cDelta: array[0..8] of Integer = (-999999, -500, -499, -1, 0, 1, 499, 500, 999999);
var
  p: Integer;
  i: Integer;
  k: Integer;
  g: TGarbos;
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lZone: ICronTimeZone;
  lWallUs, lSpringMs, lFallMs, lDueUs, lExpectedMs, lUtcUs: Int64;
  lFires, lExpectedFirst, lExpectedSecond: Integer;
begin
  lZone := TBoundaryZone.Create;
  lSpringMs := GridMs(EncodeDate(2075, 3, 31));
  lFallMs := GridMs(EncodeDate(2075, 10, 27));
  SetCronSystemTimeZoneForTests(lZone);
  SetMaxCronWallClockHook(function: Int64 begin Result := lWallUs; end);
  try
    GC(lCron, TmaxCron.Create(ctPortable), g);
    lEvent := lCron.Add('fake-dst');
    lEvent.EventPlan := '0 2 * * *';
    lEvent.InvokeMode := imMainThread;
    lEvent.OnScheduleProc := procedure(aSender: IMaxCronEvent) begin Inc(lFires); end;
    for p := 0 to 1 do
      for i := 0 to High(cDelta) do
      begin
        lEvent.Stop;
        lEvent.DstSpringPolicy := TmaxCronDstSpringPolicy(p);
        lWallUs := (lSpringMs + 7200000) * 1000 - 1000000;
        lEvent.Run;
        lExpectedMs := lSpringMs + MSecsPerDay + 7200000;
        if p = Ord(TmaxCronDstSpringPolicy.dspRunAtNextValidTime) then
          lExpectedMs := lSpringMs + 10800000;
        Assert.AreEqual(lExpectedMs, CarrierMs(lEvent.NextSchedule), 'spring policy=' + IntToStr(p));
        lFires := 0;
        lCron.TickAtUs((lSpringMs + 10800000) * 1000 + cDelta[i]);
        lExpectedFirst := 0;
        if (p = Ord(TmaxCronDstSpringPolicy.dspRunAtNextValidTime)) and (cDelta[i] >= 0) then
          lExpectedFirst := 1;
        Assert.AreEqual(lExpectedFirst, lFires, 'spring precise edge');
      end;
    SetMaxCronUtcClockHook(function: Int64 begin Result := lUtcUs; end);
    try
      for p := Ord(Low(TmaxCronDstFallPolicy)) to Ord(High(TmaxCronDstFallPolicy)) do
        for i := 0 to High(cDelta) do
        begin
          lEvent.Stop;
          lEvent.DstFallPolicy := TmaxCronDstFallPolicy(p);
          // Local02:00: first instance at00:00Z, second at01:00Z.
          lDueUs := lFallMs * 1000;
          lUtcUs := lDueUs - 1000000;
          lEvent.Run;
          lFires := 0;
          lCron.TickAtUtcUs(lDueUs + cDelta[i]);
          lExpectedFirst := 0;
          if (cDelta[i] >= 0) and (p <> Ord(TmaxCronDstFallPolicy.dfpRunOncePreferSecondInstance)) then
            lExpectedFirst := 1;
          Assert.AreEqual(lExpectedFirst, lFires, 'fall first instance');
          lCron.TickAtUtcUs(lDueUs + 999999);
          lCron.TickAtUtcUs(lDueUs + 3600000000 + cDelta[i]);
          lExpectedSecond := 1;
          if p = Ord(TmaxCronDstFallPolicy.dfpRunOncePreferSecondInstance) then
            lExpectedSecond := 0;
          if cDelta[i] >= 0 then
          begin
            lExpectedSecond := 1;
            if p = Ord(TmaxCronDstFallPolicy.dfpRunTwice) then
              lExpectedSecond := 2;
          end;
          Assert.AreEqual(lExpectedSecond, lFires, 'fall repeated instance');
        end;
    finally
      SetMaxCronUtcClockHook(nil);
    end;
    // The fake-zone boundary classifier itself follows exact-ms carrier semantics at ulp neighbours.
    for k := -8 to 8 do
      for i := 0 to 3 do
      begin
        lExpectedMs := lSpringMs + 7200000;
        case i of
          1: lExpectedMs := lSpringMs + 10800000;
          2: lExpectedMs := lFallMs + 7200000;
          3: lExpectedMs := lFallMs + 10800000;
        end;
        Assert.AreEqual(i = 0, lZone.IsInvalidTime(Neighbour(PolicyGrid(lExpectedMs), k)));
        Assert.AreEqual(i = 2, lZone.IsAmbiguousTime(Neighbour(PolicyGrid(lExpectedMs), k)));
      end;
  finally
    g.Clear;
    SetMaxCronWallClockHook(nil);
    SetCronSystemTimeZoneForTests(nil);
  end;
end;

procedure TTestTimeBoundaries.GeneratedUtcOffsetHours;
var
  d: Integer;
  z: Integer;
  h: Integer;
  k: Integer;
  g: TGarbos;
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lZone: ICronTimeZone;
  lWallUs, lDayMs, lUtcMs, lExpectedMs, lOffset, lEventMs: Int64;
begin
  lZone := TBoundaryZone.Create;
  SetCronSystemTimeZoneForTests(lZone);
  SetMaxCronWallClockHook(function: Int64 begin Result := lWallUs; end);
  try
    GC(lCron, TmaxCron.Create(ctPortable), g);
    lEvent := lCron.Add('utc-offset-hours');
    for d := 0 to 1 do
    begin
      lDayMs := GridMs(EncodeDate(2075, 3, 31));
      if d = 1 then
        lDayMs := GridMs(EncodeDate(2075, 10, 27));
      for z := 0 to 1 do
      begin
        lOffset := 0;
        if z = 1 then
          lOffset := 19800000;
        for h := -24 to 47 do
          for k := -4 to 4 do
          begin
            lEvent.Stop;
            lEvent.TimeZoneId := 'UTC';
            if z = 1 then
              lEvent.TimeZoneId := 'UTC+05:30';
            lUtcMs := lDayMs + Int64(h) * 3600000;
            lEventMs := lUtcMs + lOffset;
            lEvent.EventPlan := Format('%d %d * * *', [MinuteOf(PolicyGrid(lEventMs)), HourOf(PolicyGrid(lEventMs))]);
            // Begin two system-local days earlier to avoid ambiguity when deriving the search base.
            lWallUs := (lDayMs - 2 * MSecsPerDay) * 1000;
            lEvent.ValidFrom := Neighbour(lZone.ToLocalTime(PolicyGrid(lUtcMs - 1000)), k);
            lEvent.Run;
            lExpectedMs := lUtcMs + 3600000;
            if ((d = 0) and (h >= 1)) or ((d = 1) and (h < 1)) then
              lExpectedMs := lUtcMs + 7200000;
            // ValidFrom in the repeated system hour maps to standard time by the preserved policy.
            if (d = 1) and (h = 1) then
              lExpectedMs := lUtcMs + MSecsPerDay + 3600000;
            Assert.AreEqual(lExpectedMs, CarrierMs(lEvent.NextSchedule),
              Format('transition=%d zone=%d utcHour=%d ulp=%d', [d, z, h, k]));
          end;
      end;
    end;
  finally
    g.Clear;
    SetMaxCronWallClockHook(nil);
    SetCronSystemTimeZoneForTests(nil);
  end;
end;

function BoundaryGapReferenceNext(const aUtcUs, aDayMs: Int64;
  const aSpring: TmaxCronDstSpringPolicy): Int64;
var
  g: TGarbos;
  lPlan: TCronSchedulePlan;
  lChanges: TArray<TZoneChange>;
  lMap: TCronLocalMapping;
  lNext: TDateTime;
  lCursor, lLocal, lBase, lBest: Int64;
begin
  SetLength(lChanges, 1);
  lChanges[0].UtcMs := aDayMs + 3600000;
  lChanges[0].OffsetMs := 7200000;
  lBase := CronFloorDiv(aUtcUs, 1000000) * 1000;
  lBest := High(Int64);
  GC(lPlan, TCronSchedulePlan.Create, g);
  lPlan.Parse('* * * * * * *');
  lCursor := lBase + 3600000 - 1000;
  while lPlan.FindNextScheduleDate(PolicyGrid(lCursor), lNext) do
  begin
    lLocal := CarrierMs(lNext);
    if lLocal > lBase + 7200000 + 1000 then Break;
    lCursor := lLocal;
    lMap := ReferenceMapping(3600000, lChanges, lLocal);
    if ((lMap.Kind <> clkGap) or (aSpring = dspRunAtNextValidTime)) and
      (lMap.FirstUtcMs > lBase) and (lMap.FirstUtcMs < lBest) then lBest := lMap.FirstUtcMs;
  end;
  Assert.IsTrue(lBest < High(Int64), 'UTC gap reference found an instance');
  Result := lBest + 3600000;
  if lBest >= lChanges[0].UtcMs then Result := lBest + 7200000;
end;

procedure TTestTimeBoundaries.GeneratedDstSearchEdges;
const
  cDelta: array[0..8] of Integer = (-999999, -501, -500, -499, -1, 0, 1, 500, 999999);
var
  d: Integer;
  e: Integer;
  p: Integer;
  i: Integer;
  g: TGarbos;
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lZone: ICronTimeZone;
  lWallUs, lDayMs, lEdgeUs, lExpectedMs, lUtcUs: Int64;
begin
  lZone := TBoundaryZone.Create;
  SetCronSystemTimeZoneForTests(lZone);
  SetMaxCronWallClockHook(function: Int64 begin Result := lWallUs; end);
  try
    for d := 0 to 1 do
      for e := 2 to 3 do
        for p := 0 to 1 do
          for i := 0 to High(cDelta) + 17 do
          begin
            lDayMs := GridMs(EncodeDate(2075, 3, 31));
            if d = 1 then
              lDayMs := GridMs(EncodeDate(2075, 10, 27));
            lEdgeUs := (lDayMs + Int64(e) * 3600000) * 1000;
            if i <= High(cDelta) then
              lWallUs := lEdgeUs + cDelta[i]
            else
              lWallUs := CarrierUs(Neighbour(PolicyGrid(lEdgeUs div 1000), i - High(cDelta) - 9));
            lExpectedMs := (lWallUs div 1000000 + 1) * 1000;
            if (d = 0) and (lExpectedMs >= lDayMs + 7200000) and (lExpectedMs < lDayMs + 10800000) then
            begin
              if p = Ord(TmaxCronDstSpringPolicy.dspSkip) then
                lExpectedMs := lDayMs + 10800000
              else
                Inc(lExpectedMs, 3600000);
            end;
            if lZone.IsInvalidTime(PolicyGrid(CronFloorDiv(lWallUs, 1000))) then
            begin
              // Replace only nonexistent readings by real instants at the
              // same displacement from the UTC transition, retaining density.
              lUtcUs := (lDayMs + 3600000) * 1000 + lWallUs - lEdgeUs;
              SetMaxCronUtcClockHook(function: Int64 begin Result := lUtcUs; end);
              lExpectedMs := BoundaryGapReferenceNext(lUtcUs, lDayMs, TmaxCronDstSpringPolicy(p));
            end;
            try
              // Rows are independent histories; do not carry a previous
              // row's overlap high-water mark into the next clock sample.
              GC(lCron, TmaxCron.Create(ctPortable), g);
              lEvent := lCron.Add('dst-search-edges');
              lEvent.EventPlan := '* * * * * * *';
              lEvent.DstSpringPolicy := TmaxCronDstSpringPolicy(p);
              lEvent.Run;
              Assert.AreEqual(lExpectedMs, CarrierMs(lEvent.NextSchedule),
                Format('transition=%d edge=%d policy=%d variant=%d nowUs=%d', [d, e, p, i, lWallUs]));
            finally
              lEvent := nil;
              g.Clear;
              SetMaxCronUtcClockHook(nil);
            end;
          end;
  finally
    g.Clear;
    SetMaxCronWallClockHook(nil);
    SetCronSystemTimeZoneForTests(nil);
  end;
end;

procedure TTestTimeBoundaries.CronValidityAfterDstConversion;
var
  g: TGarbos;
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lWallUs, lDayMs: Int64;
  lFires: Integer;
begin
  lDayMs := GridMs(EncodeDate(2075, 3, 31));
  lWallUs := (lDayMs + 3600000) * cCronUsPerMs;
  lFires := 0;
  SetCronSystemTimeZoneForTests(TBoundaryZone.Create);
  SetMaxCronWallClockHook(function: Int64 begin Result := lWallUs; end);
  try
    GC(lCron, TmaxCron.Create(ctPortable), g);
    lEvent := lCron.Add('validity-shift');
    lEvent.EventPlan := '30 2 * * *';
    lEvent.DstSpringPolicy := dspRunAtNextValidTime;
    lEvent.ValidTo := CronMsToDateTime(lDayMs + 9900000); // 02:45, inside the gap.
    lEvent.InvokeMode := imMainThread;
    lEvent.OnScheduleProc := procedure(aSender: IMaxCronEvent) begin Inc(lFires); end;
    lEvent.Run;
    lWallUs := (lDayMs + 10800000) * cCronUsPerMs;
    lCron.TickAtUs(lWallUs);
    Assert.AreEqual(0, lFires, 'Shifted 03:00 result is past ValidTo 02:45');
    Assert.IsFalse(lEvent.Enabled);
  finally
    lEvent := nil;
    g.Clear;
    SetMaxCronWallClockHook(nil);
    SetCronSystemTimeZoneForTests(nil);
  end;
end;

end.

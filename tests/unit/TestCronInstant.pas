unit TestCronInstant;
{$I maxCron.inc}

interface

uses
  {$IFDEF FPC}
  DateUtils, Math, SysUtils,
  DUnitX.TestFramework,
  maxCron
  {$ELSE}
  System.DateUtils, System.Math, System.SysUtils,
  DUnitX.TestFramework,
  maxCron
  {$ENDIF};

type
  [TestFixture]
  TTestCronInstant = class
  private
    procedure CheckRecovery(const aMs: Int64);
  public
    [Test] procedure RecoveryAndNeighbours;
    [Test] procedure ExactTies;
    [Test] procedure RtlAgreementAwayFromTies;
    [Test] procedure SignedDivision;
    [Test] procedure Domain;
    [Test] procedure WholeSecondBits;
    [Test] procedure PublicReexports;
  end;

implementation

function SeedNext(var aSeed: Cardinal): Cardinal;
begin
  aSeed := (UInt64(aSeed) * 1664525 + 1013904223) and $FFFFFFFF;
  Result := aSeed;
end;

function DoubleBits(const aValue: Double): Int64;
begin
  Move(aValue, Result, SizeOf(Result));
end;

function FromBits(const aValue: Int64): Double;
begin
  Move(aValue, Result, SizeOf(Result));
end;

procedure TTestCronInstant.CheckRecovery(const aMs: Int64);
var
  i: Integer;
  lValue, lDate: TDateTime;
  lYear, lMonth, lDay, lHour, lMinute, lSecond, lMilli: Word;
  lKey, lPrevious: Int64;
begin
  lValue := CronMsToDateTime(aMs);
  Assert.AreEqual(aMs, CronDateTimeToMs(lValue), 'H1 ms=' + IntToStr(aMs));
  Assert.AreEqual(aMs * 1000, CronDateTimeToInstantUs(lValue));
  lPrevious := Low(Int64);
  for i := -8 to 8 do
  begin
    lKey := CronDateTimeToMs(FromBits(DoubleBits(lValue) + i));
    Assert.IsTrue(lKey >= lPrevious, 'H2 monotone ms=' + IntToStr(aMs));
    Assert.AreEqual(aMs, lKey, 'H2 recovery ms=' + IntToStr(aMs));
    lPrevious := lKey;
  end;
  DecodeDateTime(lValue, lYear, lMonth, lDay, lHour, lMinute, lSecond, lMilli);
  Assert.AreEqual(aMs, CronDateTimeToMs(EncodeDateTime(lYear, lMonth, lDay, lHour, lMinute, lSecond, lMilli)), 'H1 EncodeDateTime');
  lDate := EncodeDate(lYear, lMonth, lDay);
  Assert.AreEqual(aMs, CronDateTimeToMs(IncMilliSecond(lDate,
    Int64(lHour) * 3600000 + lMinute * 60000 + lSecond * 1000 + lMilli)), 'H1 IncMilliSecond');
  lValue := lDate + lHour * (1.0 / 24) + lMinute * (1.0 / 24 / 60) +
    lSecond * (1.0 / 24 / 60 / 60) + lMilli / 86400000.0;
  Assert.AreEqual(aMs, CronDateTimeToMs(lValue), 'H1 Push expressions');
  lValue := CronMsToDateTime(aMs - 1000) + (1.0 / 24 / 60 / 60);
  Assert.AreEqual(aMs, CronDateTimeToMs(lValue), 'H1 due + OneSecond');
end;

procedure TTestCronInstant.RecoveryAndNeighbours;
const
  cDates: array[0..10] of Integer = (19000101, 19000301, 20000229, 20261116, 20790604, 20790605,
    22581109, 22581110, 26170920, 26170921, 30001231);
var
  d: Int64;
  i: Integer;
  lMs, lLower, lUpper: Int64;
  lSeed: Cardinal;
begin
  for d in cDates do
  begin
    lMs := Trunc(EncodeDate(d div 10000, d div 100 mod 100, d mod 100)) * cCronMsPerDay;
    for i := -2000 to 2000 do
      CheckRecovery(lMs + i);
  end;
  lLower := Trunc(EncodeDate(1900, 1, 1)) * cCronMsPerDay;
  lUpper := Trunc(EncodeDate(3001, 1, 1)) * cCronMsPerDay;
  lSeed := 20261116;
  for i := 1 to 100000 do
  begin
    lMs := Int64(SeedNext(lSeed)) * 65536 + (SeedNext(lSeed) and $FFFF);
    lMs := lLower + (lMs mod (lUpper - lLower));
    CheckRecovery(lMs);
  end;
  Writeln('H1/H2 seed=20261116: 144011 ms values; 2448187 ulp neighbours; 4 construction forms each');
end;

procedure TTestCronInstant.ExactTies;
const
  cDays: array[0..2] of Integer = (2, 46000, 402133);
var
  d: Int64;
begin
  for d in cDays do
  begin
    Assert.AreEqual(Int64(d) * cCronMsPerDay + 42188, CronDateTimeToMs(d + 1 / 2048.0), 'H3 odd floor rounds up');
    Assert.AreEqual(Int64(d) * cCronMsPerDay + 126562, CronDateTimeToMs(d + 3 / 2048.0), 'H3 even floor stays');
  end;
end;

procedure TTestCronInstant.RtlAgreementAwayFromTies;
var
  lValue: TDateTime;
  lProduct, lRemainder: Double;
  lStamp: TTimeStamp;
  lSeed: Cardinal;
  lCount: Integer;
  lExpected: Int64;
begin
  lSeed := 20261116;
  lCount := 0;
  while lCount < 100000 do
  begin
    lValue := 2 + (SeedNext(lSeed) mod 402131) + SeedNext(lSeed) / 4294967296.0;
    lProduct := lValue * 86400000.0;
    lRemainder := lProduct - Trunc(lProduct);
    if Abs(lRemainder - 0.5) < 0.001 then
      Continue;
    lStamp := DateTimeToTimeStamp(lValue);
    lExpected := (Int64(lStamp.Date) - DateDelta) * cCronMsPerDay + lStamp.Time;
    Assert.AreEqual(lExpected, CronDateTimeToMs(lValue), 'H4 x=' + FloatToStr(lValue));
    Inc(lCount);
  end;
end;

procedure TTestCronInstant.SignedDivision;
const
  cValues: array[0..8] of Int64 = (Low(Int64), Low(Int64) + 1, -1000001, -1000000, -1,
    0, 1, High(Int64) - 1, High(Int64));
  cDivisors: array[0..4] of Int64 = (1, 2, 1000, 1000000, High(Int64));
var
  v: Int64;
  d: Int64;
  lFloor, lCeil, lTruncated: Int64;
begin
  for v in cValues do
    for d in cDivisors do
    begin
      lTruncated := v div d;
      lFloor := lTruncated;
      lCeil := lTruncated;
      if (v < 0) and (v mod d <> 0) then
        Dec(lFloor);
      if (v > 0) and (v mod d <> 0) then
        Inc(lCeil);
      Assert.AreEqual(lFloor, CronFloorDiv(v, d), 'H5 floor');
      Assert.AreEqual(lCeil, CronCeilDiv(v, d), 'H5 ceil');
      if d = 1000000 then
        Assert.AreEqual(lFloor, CronInstantFloorSecond(v), 'H5 instant');
    end;
end;

procedure TTestCronInstant.Domain;
begin
  Assert.AreEqual(Int64(0), CronDateTimeToMs(NaN));
  Assert.AreEqual(Int64(0), CronDateTimeToMs(-1));
  Assert.AreEqual(Int64(0), CronDateTimeToMs(0));
  Assert.AreEqual(Int64(2958466) * cCronMsPerDay, CronDateTimeToMs(2958466));
  Assert.AreEqual(Int64(2958466) * cCronMsPerDay, CronDateTimeToMs(1e300));
  Assert.AreEqual(CronMsToDateTime(1234), CronInstantUsToDateTime(1234999), 0.0, 'Display floors ms');
  Assert.AreEqual(CronMsToDateTime(-1), CronInstantUsToDateTime(-1), 0.0, 'Display floors negative ms');
end;

procedure TTestCronInstant.WholeSecondBits;
var
  i: Integer;
  lSeed: Cardinal;
  lSecond, lLower, lUpper: Int64;
  lValue: TDateTime;
  lYear, lMonth, lDay, lHour, lMinute, lSec, lMilli: Word;
begin
  lSeed := 20261116;
  lLower := Trunc(EncodeDate(1900, 1, 1)) * 86400;
  lUpper := Trunc(EncodeDate(3001, 1, 1)) * 86400;
  for i := 1 to 100000 do
  begin
    lSecond := lLower + (Int64(SeedNext(lSeed)) * 65536 + (SeedNext(lSeed) and $FFFF)) mod (lUpper - lLower);
    lValue := CronSecondToDateTime(lSecond);
    Assert.AreEqual(lSecond * 1000, CronDateTimeToMs(lValue), 'H7 recovery');
    DecodeDateTime(lValue, lYear, lMonth, lDay, lHour, lMinute, lSec, lMilli);
    Assert.AreEqual(DoubleBits(EncodeDateTime(lYear, lMonth, lDay, lHour, lMinute, lSec, 0)), DoubleBits(lValue), 'H7 bit equality');
  end;
end;

procedure TTestCronInstant.PublicReexports;
var
  lInstant: TCronInstantUs;
begin
  // This entire fixture imports maxCron alone: all helpers/constants must resolve through it.
  lInstant := CronDateTimeToInstantUs(CronSecondToDateTime(2));
  Assert.AreEqual(Int64(2) * cCronUsPerSecond, lInstant);
  Assert.AreEqual(Int64(cCronUsPerMs), CronDateTimeToInstantUs(CronMsToDateTime(1)));
  Assert.AreEqual(Int64(1000), Int64(cCronMsPerSecond));
  Assert.AreEqual(Int64(86400), Int64(cCronSecondsPerDay));
end;

end.

unit TestIntervalPlan;
interface
uses System.SysUtils, DUnitX.TestFramework, maxCron.Plan;
type
  [TestFixture]
  TTestIntervalPlan = class
  public
    [Test] procedure GrammarTables;
    [Test] procedure FormatDescribeAndGeneratedRoundTrips;
  end;
implementation
procedure TTestIntervalPlan.GrammarTables;
const
  cValid: array[0..8] of string = ('@every 5s', '@EVERY 250MS', '  @every   5 s   # poll',
    '@every 1h fixed-delay limit 3', '@every 5s fixed-rate', '@every 5s limit 0',
    '@every 1ms', '@every 4294967295ms', '@every 1193h');
  cMs: array[0..8] of Cardinal = (5000,250,5000,3600000,5000,5000,1,4294967295,4294800000);
  cInvalid: array[0..10] of string = ('@every','@every 5','@every 5x','@every 5d',
    '@every -5s','@every 1.5s','@every 1h30m','@every 5s extra','@every 5s limit',
    '@every 5s fixed-delay fixed-rate','@every 5s limit 3 fixed-delay');
  cRange: array[0..4] of string = ('@every 0ms','@every 4294968s','@every 1194h',
    '@every 5s limit 4294967296','@every 9999999999999999999999999999999999999999h');
var
  lPlan: TCronIntervalPlan;
  lError: string;
  i: Integer;
begin
  for i := Low(cValid) to High(cValid) do
  begin
    Assert.IsTrue(IsCronIntervalPlan(cValid[i]), cValid[i]);
    Assert.IsTrue(TryParseCronIntervalPlan(cValid[i], lPlan, lError), cValid[i]+': '+lError);
    Assert.AreEqual<UInt64>(cMs[i], lPlan.IntervalMs, cValid[i]);
    Assert.AreEqual(i=3, lPlan.FixedDelay, cValid[i]);
    if i=3 then Assert.AreEqual<UInt64>(3, lPlan.ExecutionLimit);
  end;
  for i := Low(cInvalid) to High(cInvalid) do
  begin
    Assert.IsFalse(TryParseCronIntervalPlan(cInvalid[i],lPlan,lError),cInvalid[i]);
    Assert.AreEqual('Invalid interval plan',lError,cInvalid[i]);
  end;
  for i := Low(cRange) to High(cRange) do
  begin
    Assert.IsFalse(TryParseCronIntervalPlan(cRange[i],lPlan,lError),cRange[i]);
    Assert.AreEqual('Interval plan value out of range',lError,cRange[i]);
  end;
  Assert.IsFalse(IsCronIntervalPlan('@every5s'));
  Assert.IsFalse(IsCronIntervalPlan('@everyday'));
end;
procedure TTestIntervalPlan.FormatDescribeAndGeneratedRoundTrips;
const
  cMs: array[0..8] of Cardinal = (1,250,1000,5000,90000,60000,3600000,7200000,1500);
  cCanonical: array[0..8] of string = ('@every 1ms','@every 250ms','@every 1s','@every 5s',
    '@every 90s','@every 1m','@every 1h','@every 2h','@every 1500ms');
  cDescription: array[0..8] of string = ('Every millisecond','Every 250 milliseconds',
    'Every second','Every 5 seconds','Every 90 seconds','Every minute','Every hour',
    'Every 2 hours','Every 1500 milliseconds');
var
  lPlan,lParsed: TCronIntervalPlan;
  lError,lText: string;
  lSeed: UInt64;
  i: Integer;
begin
  lPlan := Default(TCronIntervalPlan);
  for i := 0 to High(cMs) do
  begin
    lPlan.IntervalMs := cMs[i];
    Assert.AreEqual(cCanonical[i],FormatCronIntervalPlan(lPlan));
    Assert.AreEqual(cDescription[i],DescribeCronIntervalPlan(lPlan));
  end;
  lPlan.IntervalMs := 7200000; lPlan.FixedDelay := True; lPlan.ExecutionLimit := 2;
  Assert.AreEqual('@every 2h fixed-delay limit 2',FormatCronIntervalPlan(lPlan));
  Assert.AreEqual('Every 2 hours (fixed delay)',DescribeCronIntervalPlan(lPlan));
  lSeed := 20261115;
  for i := 1 to 200 do
  begin
    lSeed := (lSeed * 1664525 + 1013904223) and $FFFFFFFF;
    lPlan.IntervalMs := Cardinal(lSeed or 1);
    lPlan.FixedDelay := (i mod 2)=0;
    lPlan.ExecutionLimit := Cardinal(i mod 7);
    lText := FormatCronIntervalPlan(lPlan);
    Assert.IsTrue(TryParseCronIntervalPlan(lText,lParsed,lError),lText);
    Assert.AreEqual<UInt64>(lPlan.IntervalMs,lParsed.IntervalMs);
    Assert.AreEqual(lPlan.FixedDelay,lParsed.FixedDelay);
    Assert.AreEqual<UInt64>(lPlan.ExecutionLimit,lParsed.ExecutionLimit);
    Assert.AreEqual(lText,FormatCronIntervalPlan(lParsed));
  end;
end;
end.

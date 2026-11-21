program maxCronTests;

{$APPTYPE CONSOLE}

{$DEFINE MAXCRON_TESTS}

uses
  System.SysUtils,
  DUnitX.Loggers.Console,
  DUnitX.RunResults,
  DUnitX.TestFramework,
  DelphiRoster in 'DelphiRoster.pas',
  TestRoster in 'TestRoster.pas',
  maxCron.Internal.DeadlineQueue in '..\maxCron.Internal.DeadlineQueue.pas',
  maxCron.Internal.Platform in '..\maxCron.Internal.Platform.pas',
  maxCron.Internal.Text in '..\maxCron.Internal.Text.pas',
  maxCron.Internal.TimeZone in '..\maxCron.Internal.TimeZone.pas',
  maxCron.Internal.TZif in '..\maxCron.Internal.TZif.pas',
  TestIntervalTiming in 'unit\TestIntervalTiming.pas',
  TestIntervalPlan in 'unit\TestIntervalPlan.pas',
  TestDeadlineQueue in 'unit\TestDeadlineQueue.pas',
  TestIntervalEvents in 'unit\TestIntervalEvents.pas',
  maxCron.Plan in '..\maxCron.Plan.pas',
  maxCron in '..\maxCron.pas',
  TestCronTextParity in 'unit\TestCronTextParity.pas',
  TestLocalZoneOs in 'unit\TestLocalZoneOs.pas',
  TestLocalOverlap in 'unit\TestLocalOverlap.pas',
  TestZoneFakes in 'unit\TestZoneFakes.pas',
  TestTimeZoneRules in 'unit\TestTimeZoneRules.pas',
  TestTimeZoneWindows in 'unit\TestTimeZoneWindows.pas',
  TestWindowsZoneOracle in 'unit\TestWindowsZoneOracle.pas',
  TestTimeZoneTzif in 'unit\TestTimeZoneTzif.pas',
  TestNamedTimeZones in 'unit\TestNamedTimeZones.pas',
  TestPublicApiCompat in 'unit\TestPublicApiCompat.pas',
  TestCronInvalidCorpus in 'unit\TestCronInvalidCorpus.pas',
  TestCronParsing in 'unit\TestCronParsing.pas',
  TestCronUtilsCorpus in 'unit\TestCronUtilsCorpus.pas',
  TestCalendarTimeZone in 'unit\TestCalendarTimeZone.pas',
  TestChaosFaultInjection in 'unit\TestChaosFaultInjection.pas',
  TestCronFuzzOracle in 'unit\TestCronFuzzOracle.pas',
  TestCronQuery in 'unit\TestCronQuery.pas',
  TestDispatchStartFailures in 'unit\TestDispatchStartFailures.pas',
  TestExecutionLimit in 'unit\TestExecutionLimit.pas',
  TestHashJitter in 'unit\TestHashJitter.pas',
  TestInvokeModes in 'unit\TestInvokeModes.pas',
  TestLifecycle in 'unit\TestLifecycle.pas',
  TestMisfirePolicy in 'unit\TestMisfirePolicy.pas',
  TestMisfireOnTime in 'unit\TestMisfireOnTime.pas',
  TestCronInstant in 'unit\TestCronInstant.pas',
  TestTimeBoundaries in 'unit\TestTimeBoundaries.pas',
  TestDeadlineTimer in 'unit\TestDeadlineTimer.pas',
  TestMaxCron in 'unit\TestMaxCron.pas',
  TestMetricsSnapshot in 'unit\TestMetricsSnapshot.pas',
  TestPersistenceRecovery in 'unit\TestPersistenceRecovery.pas',
  TestRetryBackoff in 'unit\TestRetryBackoff.pas',
  TestRobustCoverage in 'unit\TestRobustCoverage.pas',
  TestGracefulShutdown in 'unit\TestGracefulShutdown.pas',
  TestReviewFindings in 'unit\TestReviewFindings.pas',
  TestScheduleNext in 'unit\TestScheduleNext.pas',
  TestStress in 'unit\TestStress.pas',
  TestValidityZones in 'unit\TestValidityZones.pas',
  TestValidRange in 'unit\TestValidRange.pas';


var
  Runner: ITestRunner;
  Results: IRunResults;
begin
  ReportMemoryLeaksOnShutdown := True;
  try
    {$IFDEF MAXCRON_LONG_TESTS}
    BeginRoster('DelphiLong');
    {$ELSE}
    BeginRoster('DelphiUnit');
    {$ENDIF}
    TDUnitX.CheckCommandLine;
    TDUnitX.RegisterTestFixture(TTestCronTextParity);
    TDUnitX.RegisterTestFixture(TTestLocalZoneOs);
    TDUnitX.RegisterTestFixture(TTestLocalOverlap);
    TDUnitX.RegisterTestFixture(TTestTimeZoneRules);
    TDUnitX.RegisterTestFixture(TTestTimeZoneWindows);
    TDUnitX.RegisterTestFixture(TTestWindowsZoneOracle);
    TDUnitX.RegisterTestFixture(TTestTimeZoneTzif);
    TDUnitX.RegisterTestFixture(TTestNamedTimeZones);
    TDUnitX.RegisterTestFixture(TTestPublicApiCompat);
    TDUnitX.RegisterTestFixture(TTestCronInvalidCorpus);
    TDUnitX.RegisterTestFixture(TTestCronParsing);
    TDUnitX.RegisterTestFixture(TTestCronUtilsCorpus);
    TDUnitX.RegisterTestFixture(TTestCalendarTimeZone);
    TDUnitX.RegisterTestFixture(TTestChaosFaultInjection);
    TDUnitX.RegisterTestFixture(TTestCronFuzzOracle);
    TDUnitX.RegisterTestFixture(TTestCronQuery);
    TDUnitX.RegisterTestFixture(TTestDispatchStartFailures);
    TDUnitX.RegisterTestFixture(TTestExecutionLimit);
    TDUnitX.RegisterTestFixture(TTestHashJitter);
    TDUnitX.RegisterTestFixture(TTestInvokeModes);
    TDUnitX.RegisterTestFixture(TTestLifecycle);
    TDUnitX.RegisterTestFixture(TTestMisfirePolicy);
    TDUnitX.RegisterTestFixture(TTestMisfireOnTime);
    TDUnitX.RegisterTestFixture(TTestCronInstant);
    TDUnitX.RegisterTestFixture(TTestTimeBoundaries);
    TDUnitX.RegisterTestFixture(TTestDeadlineTimer);
    TDUnitX.RegisterTestFixture(TTestMaxCron);
    TDUnitX.RegisterTestFixture(TTestMetricsSnapshot);
    TDUnitX.RegisterTestFixture(TTestPersistenceRecovery);
    TDUnitX.RegisterTestFixture(TTestRetryBackoff);
    TDUnitX.RegisterTestFixture(TTestRobustCoverage);
    TDUnitX.RegisterTestFixture(TTestGracefulShutdown);
    TDUnitX.RegisterTestFixture(TTestReviewFindings);
    TDUnitX.RegisterTestFixture(TTestScheduleNext);
    TDUnitX.RegisterTestFixture(TTestStress);
    TDUnitX.RegisterTestFixture(TTestValidityZones);
    TDUnitX.RegisterTestFixture(TTestValidRange);
    TDUnitX.RegisterTestFixture(TTestIntervalPlan);
    TDUnitX.RegisterTestFixture(TTestDeadlineQueue);
    TDUnitX.RegisterTestFixture(TTestIntervalEvents);
    TDUnitX.RegisterTestFixture(TTestIntervalTiming);
    Runner := TDUnitX.CreateRunner;
    Runner.UseRTTI := True;
    Runner.AddLogger(TDUnitXConsoleLogger.Create(True));
    Results := ExecuteRoster(Runner);
    if not Results.AllPassed or (Results.TestCount <= 0) or
      (Results.PassCount <> Results.TestCount) or (Results.FailureCount <> 0) or
      (Results.ErrorCount <> 0) or (Results.IgnoredCount <> 0) or (Results.MemoryLeakCount <> 0) then
      ExitCode := 1;
    {$IFDEF MAXCRON_LONG_TESTS}
    Writeln('LONG_ROSTER expected=', ExpectedRosterCount, ' found=', Results.TestCount, ' passed=', Results.PassCount);
    {$ENDIF}
  except
    on E: Exception do
    begin
      ExitCode := ReportRosterFailure(E);
    end;
  end;
end.

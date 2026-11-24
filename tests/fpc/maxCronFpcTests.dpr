program maxCronFpcTests;
{$I maxCron.inc}

uses
  {$IFDEF UNIX}cthreads, cwstring,{$ENDIF}
  SysUtils,
  AutoFree in 'AutoFree.pas',
  DUnitX.TestFramework in 'DUnitX.TestFramework.pas',
  maxCronFpcTestRunner in 'maxCronFpcTestRunner.pas',
  TestCalendarTimeZone in '..\unit\TestCalendarTimeZone.pas',
  TestCronFuzzOracle in '..\unit\TestCronFuzzOracle.pas',
  TestCronInstant in '..\unit\TestCronInstant.pas',
  TestCronInvalidCorpus in '..\unit\TestCronInvalidCorpus.pas',
  TestCronParsing in '..\unit\TestCronParsing.pas',
  TestCronPhaseDifferential in '..\unit\TestCronPhaseDifferential.pas',
  TestCronQuery in '..\unit\TestCronQuery.pas',
  TestCronTextParity in '..\unit\TestCronTextParity.pas',
  TestCronUtilsCorpus in '..\unit\TestCronUtilsCorpus.pas',
  TestDeadlineQueue in '..\unit\TestDeadlineQueue.pas',
  TestFpcShims in 'TestFpcShims.pas',
  TestHashJitter in '..\unit\TestHashJitter.pas',
  TestIntervalPlan in '..\unit\TestIntervalPlan.pas',
  {$IFDEF MSWINDOWS}
  TestLocalZoneOs in '..\unit\TestLocalZoneOs.pas',
  {$ELSE}
  TestEnvironment in '../unit/TestEnvironment.pas',
  TestLocalZoneUnix in '../unit/TestLocalZoneUnix.pas',
  {$ENDIF}
  TestLocalOverlap in '..\unit\TestLocalOverlap.pas',
  TestMisfireOnTime in '..\unit\TestMisfireOnTime.pas',
  TestNamedTimeZones in '..\unit\TestNamedTimeZones.pas',
  TestLocalZoneTzif in '..\unit\TestLocalZoneTzif.pas',
  TestRestartCatchUp in '..\unit\TestRestartCatchUp.pas',
  TestRoster in '..\TestRoster.pas',
  TestScheduleNext in '..\unit\TestScheduleNext.pas',
  TestTimeBoundaries in '..\unit\TestTimeBoundaries.pas',
  TestTimeZoneRules in '..\unit\TestTimeZoneRules.pas',
  TestTimeZoneTzif in '..\unit\TestTimeZoneTzif.pas',
  {$IFDEF MSWINDOWS}
  TestTimeZoneWindows in '..\unit\TestTimeZoneWindows.pas',
  TestWindowsZoneOracle in '..\unit\TestWindowsZoneOracle.pas',
  {$ENDIF}
  TestValidityZones in '..\unit\TestValidityZones.pas',
  TestZoneFakes in '..\unit\TestZoneFakes.pas';

{$I maxCronFpcRegistry.inc}

begin
  try
    {$IFDEF MAXCRON_LONG_TESTS}
    BeginRoster({$IFDEF LINUX}'FpcLinuxLong'{$ELSE}'FpcLong'{$ENDIF});
    {$ELSE}
    BeginRoster({$IFDEF LINUX}'FpcLinux'{$ELSE}'FpcDefault'{$ENDIF});
    {$ENDIF}
    if ParamCount <> 0 then raise Exception.Create('The FPC runner currently accepts no test filters');
    RegisterGeneratedTests;
    ExitCode := RunTests(cGeneratedTestCount);
  except
    on E: Exception do
    begin
      ExitCode := ReportRosterFailure(E);
    end;
  end;
end.

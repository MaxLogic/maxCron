program maxCronFpcTests;
{$I maxCron.inc}

uses
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
  TestLocalZoneOs in '..\unit\TestLocalZoneOs.pas',
  TestMisfireOnTime in '..\unit\TestMisfireOnTime.pas',
  TestNamedTimeZones in '..\unit\TestNamedTimeZones.pas',
  TestScheduleNext in '..\unit\TestScheduleNext.pas',
  TestTimeBoundaries in '..\unit\TestTimeBoundaries.pas',
  TestTimeZoneRules in '..\unit\TestTimeZoneRules.pas',
  TestTimeZoneTzif in '..\unit\TestTimeZoneTzif.pas',
  TestZoneFakes in '..\unit\TestZoneFakes.pas';

{$I maxCronFpcRegistry.inc}

begin
  try
    if ParamCount <> 0 then raise Exception.Create('The FPC runner currently accepts no test filters');
    RegisterGeneratedTests;
    ExitCode := RunTests(cGeneratedTestCount);
  except
    on E: Exception do
    begin
      WriteLn('RUNNER ERROR ', string(E.ClassName), ': ', string(E.Message));
      ExitCode := 2;
    end;
  end;
end.

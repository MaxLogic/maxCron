program maxCronBenchmarks;

{$APPTYPE CONSOLE}
{$DEFINE MAXCRON_TESTS}

uses
  System.Classes, System.DateUtils, System.Diagnostics, System.Generics.Collections, System.IOUtils, System.Math,
  System.StrUtils, System.SyncObjs, System.SysUtils,
  {$IFDEF MSWINDOWS}
  Winapi.Windows,
  {$ELSE}
  Posix.Stdlib, Posix.Time,
  {$ENDIF}
  AutoFree,
  maxCron.Internal.DeadlineQueue in '..\maxCron.Internal.DeadlineQueue.pas',
  maxCron.Internal.Platform in '..\maxCron.Internal.Platform.pas',
  maxCron.Internal.Text in '..\maxCron.Internal.Text.pas',
  maxCron.Internal.TimeZone in '..\maxCron.Internal.TimeZone.pas',
  maxCron.Internal.TZif in '..\maxCron.Internal.TZif.pas',
  maxCron.Plan in '..\maxCron.Plan.pas',
  maxCron in '..\maxCron.pas';

type
  TBenchmarkProfile = (bpBaseline, bpSparseAuto, bpAdversarialAuto);

  TBenchmarkScenario = record
    GroupName: string;
    ScenarioName: string;
    Engine: string;
    Profile: TBenchmarkProfile;
    EnableBudget: Boolean;
    EventCount: Integer;
    TickCount: Integer;
    TickStepSeconds: Integer;
    Plan: string;
  end;

  TBenchmarkSample = record
    GroupName: string;
    ScenarioName: string;
    Engine: string;
    Iteration: Integer;
    EventCount: Integer;
    TickCount: Integer;
    TickStepSeconds: Integer;
    ElapsedUs: Int64;
    EventsVisited: UInt64;
    HeapRebuilds: UInt64;
    SwitchCount: UInt64;
    BudgetHits: Integer;
    ConfiguredEngine: string;
    EffectiveEngine: string;
    AutoState: string;
  end;

  TScenarioSummary = record
    GroupName: string;
    ScenarioName: string;
    Engine: string;
    Iterations: Integer;
    MeanElapsedUs: Double;
    MedianElapsedUs: Double;
    P95ElapsedUs: Double;
    P99ElapsedUs: Double;
    StdDevElapsedUs: Double;
    MinElapsedUs: Int64;
    MaxElapsedUs: Int64;
    MeanVisited: Double;
    MinVisited: UInt64;
    MaxVisited: UInt64;
    MeanRebuilds: Double;
    MeanSwitches: Double;
    MeanBudgetHits: Double;
  end;

  TEnvBackup = record
    Name: string;
    {$IFDEF MSWINDOWS}
    PreviousValue: string;
    {$ELSE}
    PreviousValue: RawByteString;
    {$ENDIF}
    HadPrevious: Boolean;
  end;

  TBenchmarkOptions = record
    Iterations: Integer;
    WarmupIterations: Integer;
    OutDir: string;
    CsvPath: string;
    MdPath: string;
    CompareCsvPath: string;
    Quiet: Boolean;
    Mode: string;
    EventCount: Integer;
    Seconds: Integer;
    Fires: Integer;
    IntervalMs: Integer;
    IntervalDuration: Boolean;
  end;

const
  cDefaultIterations = 9;
  cDefaultWarmupIterations = 2;
  cIdleWarmupMs = 35000;

{$IFNDEF MSWINDOWS}
const
  cLibC = 'libc.so.6';

function BenchmarkSetenv(aName, aValue: PAnsiChar; aOverwrite: Integer): Integer; cdecl;
  external cLibC name 'setenv';
function BenchmarkUnsetenv(aName: PAnsiChar): Integer; cdecl;
  external cLibC name 'unsetenv';
{$ENDIF}

procedure SetEnvVar(const aName, aValue: string; const aBackups: TList<TEnvBackup>);
var
  lBackup: TEnvBackup;
  {$IFNDEF MSWINDOWS}
  lName: UTF8String;
  lPrevious: PAnsiChar;
  {$ENDIF}
begin
  lBackup.Name := aName;
  {$IFDEF MSWINDOWS}
  lBackup.PreviousValue := GetEnvironmentVariable(aName);
  lBackup.HadPrevious := lBackup.PreviousValue <> '';
  aBackups.Add(lBackup);
  Winapi.Windows.SetEnvironmentVariable(PChar(aName), PChar(aValue));
  {$ELSE}
  lName := UTF8String(aName);
  lPrevious := getenv(PAnsiChar(lName));
  lBackup.HadPrevious := lPrevious <> nil;
  if lBackup.HadPrevious then
    lBackup.PreviousValue := lPrevious;
  aBackups.Add(lBackup);
  if BenchmarkSetenv(PAnsiChar(lName), PAnsiChar(UTF8String(aValue)), 1) <> 0 then
    RaiseLastOSError;
  {$ENDIF}
end;

procedure RestoreEnvVars(const aBackups: TList<TEnvBackup>);
var
  lIndex: Integer;
  lBackup: TEnvBackup;
  {$IFNDEF MSWINDOWS}
  lName: UTF8String;
  lStatus: Integer;
  {$ENDIF}
begin
  for lIndex := aBackups.Count - 1 downto 0 do
  begin
    lBackup := aBackups[lIndex];
    {$IFDEF MSWINDOWS}
    if lBackup.HadPrevious then
      Winapi.Windows.SetEnvironmentVariable(PChar(lBackup.Name), PChar(lBackup.PreviousValue))
    else
      Winapi.Windows.SetEnvironmentVariable(PChar(lBackup.Name), nil);
    {$ELSE}
    lName := UTF8String(lBackup.Name);
    if lBackup.HadPrevious then
      lStatus := BenchmarkSetenv(PAnsiChar(lName), PAnsiChar(lBackup.PreviousValue), 1)
    else
      lStatus := BenchmarkUnsetenv(PAnsiChar(lName));
    if lStatus <> 0 then
      RaiseLastOSError;
    {$ENDIF}
  end;
end;

function ToInvariantFloat(const aValue: Double): string;
var
  lFormat: TFormatSettings;
begin
  lFormat := TFormatSettings.Invariant;
  Result := FloatToStr(aValue, lFormat);
end;

function ElapsedUsToMs(const aValue: Int64): Double;
begin
  Result := aValue / 1000.0;
end;

function CsvQuote(const aValue: string): string;
var
  lValue: string;
begin
  lValue := StringReplace(aValue, '"', '""', [rfReplaceAll]);
  Result := '"' + lValue + '"';
end;

function ParseIntOption(const aName, aValue: string; const aMinValue: Integer): Integer;
begin
  if not TryStrToInt(aValue, Result) then
    raise Exception.CreateFmt('Invalid %s value: %s', [aName, aValue]);
  if Result < aMinValue then
    raise Exception.CreateFmt('%s must be >= %d', [aName, aMinValue]);
end;

procedure ParseOptions(var aOptions: TBenchmarkOptions);
var
  lArg: string;
  lIndex: Integer;
  {$IFNDEF MSWINDOWS}
  lSecondsSpecified, lFiresSpecified: Boolean;
  {$ENDIF}
begin
  aOptions.Iterations := cDefaultIterations;
  aOptions.WarmupIterations := cDefaultWarmupIterations;
  aOptions.OutDir := '';
  aOptions.CsvPath := '';
  aOptions.MdPath := '';
  aOptions.CompareCsvPath := '';
  aOptions.Quiet := False;
  aOptions.Mode := 'ticks';
  aOptions.EventCount := 1000;
  aOptions.Seconds := 60;
  aOptions.Fires := 60;
  aOptions.IntervalMs := 10;
  aOptions.IntervalDuration := False;
  {$IFNDEF MSWINDOWS}
  lSecondsSpecified := False;
  lFiresSpecified := False;
  {$ENDIF}

  for lIndex := 1 to ParamCount do
  begin
    lArg := ParamStr(lIndex);
    if StartsText('--mode=', lArg) then
      aOptions.Mode := LowerCase(Copy(lArg, 8, MaxInt))
    else if StartsText('--events=', lArg) then
      aOptions.EventCount := ParseIntOption('events', Copy(lArg, 10, MaxInt), 1)
    else if StartsText('--seconds=', lArg) then
    begin
      aOptions.Seconds := ParseIntOption('seconds', Copy(lArg, 11, MaxInt), 1);
      {$IFNDEF MSWINDOWS}
      lSecondsSpecified := True;
      {$ENDIF}
    end else if StartsText('--interval-ms=', lArg) then
      aOptions.IntervalMs := ParseIntOption('interval-ms', Copy(lArg, 15, MaxInt), 1)
    else if StartsText('--fires=', lArg) then
    begin
      aOptions.Fires := ParseIntOption('fires', Copy(lArg, 9, MaxInt), 1);
      {$IFNDEF MSWINDOWS}
      lFiresSpecified := True;
      {$ENDIF}
    end else if SameText(lArg, '--quiet') then
      aOptions.Quiet := True
    else if StartsText('--iterations=', lArg) then
      aOptions.Iterations := ParseIntOption('iterations', Copy(lArg, Length('--iterations=') + 1, MaxInt), 1)
    else if StartsText('--warmup=', lArg) then
      aOptions.WarmupIterations := ParseIntOption('warmup', Copy(lArg, Length('--warmup=') + 1, MaxInt), 0)
    else if StartsText('--out-dir=', lArg) then
      aOptions.OutDir := Copy(lArg, Length('--out-dir=') + 1, MaxInt)
    else if StartsText('--csv=', lArg) then
      aOptions.CsvPath := Copy(lArg, Length('--csv=') + 1, MaxInt)
    else if StartsText('--md=', lArg) then
      aOptions.MdPath := Copy(lArg, Length('--md=') + 1, MaxInt)
    else if StartsText('--compare=', lArg) then
      aOptions.CompareCsvPath := Copy(lArg, Length('--compare=') + 1, MaxInt)
    else if SameText(lArg, '--help') or SameText(lArg, '-h') or SameText(lArg, '/?') then
      raise Exception.Create(
        'Usage: maxCronBenchmarks.exe [--iterations=N] [--warmup=N] [--out-dir=PATH] [--csv=FILE] [--md=FILE] ' +
        '[--compare=FILE] [--quiet] [--mode=ticks|idle|latency|interval|selftest] [--interval-ms=N] [--events=N] [--seconds=N] [--fires=N]')
    else
      raise Exception.CreateFmt('Unknown option: %s', [lArg]);
  end;
  if not MatchText(aOptions.Mode, ['ticks', 'idle', 'latency', 'interval', 'selftest']) then
    raise Exception.Create('mode must be ticks, idle, latency, interval or selftest');
  if (aOptions.Seconds > 86400) or (aOptions.Fires > 86400) then
    raise Exception.Create('seconds and fires must be <= 86400');
  if (aOptions.Mode <> 'ticks') and (aOptions.CompareCsvPath <> '') then
    raise Exception.Create('--compare is supported only by ticks mode');
  {$IFNDEF MSWINDOWS}
  aOptions.IntervalDuration := (aOptions.Mode = 'interval') and lSecondsSpecified and not lFiresSpecified;
  if aOptions.IntervalDuration then
    aOptions.Fires := (aOptions.Seconds * 1000) div aOptions.IntervalMs;
  {$ENDIF}
end;

function BuildScenarios: TArray<TBenchmarkScenario>;
begin
  SetLength(Result, 5);

  Result[0].GroupName := 'sparse_high_n';
  Result[0].ScenarioName := 'sparse_high_n_scan';
  Result[0].Engine := 'scan';
  Result[0].Profile := bpBaseline;
  Result[0].EnableBudget := False;
  Result[0].EventCount := 1200;
  Result[0].TickCount := 96;
  Result[0].TickStepSeconds := 0;
  Result[0].Plan := '0 0 1 1 * 2099 0 1';

  Result[1].GroupName := 'sparse_high_n';
  Result[1].ScenarioName := 'sparse_high_n_heap';
  Result[1].Engine := 'heap';
  Result[1].Profile := bpBaseline;
  Result[1].EnableBudget := False;
  Result[1].EventCount := 1200;
  Result[1].TickCount := 96;
  Result[1].TickStepSeconds := 0;
  Result[1].Plan := '0 0 1 1 * 2099 0 1';

  Result[2].GroupName := 'sparse_high_n';
  Result[2].ScenarioName := 'sparse_high_n_auto';
  Result[2].Engine := 'auto';
  Result[2].Profile := bpSparseAuto;
  Result[2].EnableBudget := False;
  Result[2].EventCount := 1200;
  Result[2].TickCount := 96;
  Result[2].TickStepSeconds := 0;
  Result[2].Plan := '0 0 1 1 * 2099 0 1';

  Result[3].GroupName := 'adversarial_auto';
  Result[3].ScenarioName := 'adversarial_auto_no_budget';
  Result[3].Engine := 'auto';
  Result[3].Profile := bpAdversarialAuto;
  Result[3].EnableBudget := False;
  Result[3].EventCount := 360;
  Result[3].TickCount := 180;
  Result[3].TickStepSeconds := 1;
  Result[3].Plan := '* * * * * * * 0';

  Result[4].GroupName := 'adversarial_auto';
  Result[4].ScenarioName := 'adversarial_auto_budget';
  Result[4].Engine := 'auto';
  Result[4].Profile := bpAdversarialAuto;
  Result[4].EnableBudget := True;
  Result[4].EventCount := 360;
  Result[4].TickCount := 180;
  Result[4].TickStepSeconds := 1;
  Result[4].Plan := '* * * * * * * 0';
end;

procedure ConfigureScenarioEnv(const aScenario: TBenchmarkScenario; const aBackups: TList<TEnvBackup>);
begin
  SetEnvVar('MAXCRON_ENGINE', aScenario.Engine, aBackups);

  case aScenario.Profile of
    bpSparseAuto:
    begin
      SetEnvVar('MAXCRON_AUTO_ENTER_EVENTS', '128', aBackups);
      SetEnvVar('MAXCRON_AUTO_EXIT_EVENTS', '64', aBackups);
      SetEnvVar('MAXCRON_AUTO_ENTER_DUE_DENSITY', '1.00', aBackups);
      SetEnvVar('MAXCRON_AUTO_EXIT_DUE_DENSITY', '1.00', aBackups);
      SetEnvVar('MAXCRON_AUTO_ENTER_DIRTY', '1.00', aBackups);
      SetEnvVar('MAXCRON_AUTO_EXIT_DIRTY', '1.00', aBackups);
      SetEnvVar('MAXCRON_AUTO_ENTER_HOLD', '1', aBackups);
      SetEnvVar('MAXCRON_AUTO_EXIT_HOLD', '4', aBackups);
      SetEnvVar('MAXCRON_AUTO_TRIAL_TICKS', '1', aBackups);
      SetEnvVar('MAXCRON_AUTO_COOLDOWN', '0', aBackups);
      SetEnvVar('MAXCRON_AUTO_TRIAL_FAIL_COOLDOWN', '0', aBackups);
      SetEnvVar('MAXCRON_AUTO_PROMOTE_RATIO', '3.00', aBackups);
      SetEnvVar('MAXCRON_AUTO_DEMOTE_RATIO', '4.00', aBackups);
      SetEnvVar('MAXCRON_AUTO_SWITCH_BUDGET_WINDOW', '0', aBackups);
      SetEnvVar('MAXCRON_AUTO_SWITCH_BUDGET_MAX', '0', aBackups);
      SetEnvVar('MAXCRON_AUTO_SWITCH_BUDGET_COOLDOWN', '0', aBackups);
    end;

    bpAdversarialAuto:
    begin
      SetEnvVar('MAXCRON_AUTO_ENTER_EVENTS', '128', aBackups);
      SetEnvVar('MAXCRON_AUTO_EXIT_EVENTS', '96', aBackups);
      SetEnvVar('MAXCRON_AUTO_ENTER_DUE_DENSITY', '1.00', aBackups);
      SetEnvVar('MAXCRON_AUTO_EXIT_DUE_DENSITY', '1.00', aBackups);
      SetEnvVar('MAXCRON_AUTO_ENTER_DIRTY', '1.00', aBackups);
      SetEnvVar('MAXCRON_AUTO_EXIT_DIRTY', '1.00', aBackups);
      SetEnvVar('MAXCRON_AUTO_ENTER_HOLD', '1', aBackups);
      SetEnvVar('MAXCRON_AUTO_EXIT_HOLD', '1', aBackups);
      SetEnvVar('MAXCRON_AUTO_TRIAL_TICKS', '2', aBackups);
      SetEnvVar('MAXCRON_AUTO_COOLDOWN', '0', aBackups);
      SetEnvVar('MAXCRON_AUTO_TRIAL_FAIL_COOLDOWN', '0', aBackups);
      SetEnvVar('MAXCRON_AUTO_PROMOTE_RATIO', '0.25', aBackups);
      SetEnvVar('MAXCRON_AUTO_DEMOTE_RATIO', '0.50', aBackups);
      if aScenario.EnableBudget then
      begin
        SetEnvVar('MAXCRON_AUTO_SWITCH_BUDGET_WINDOW', '48', aBackups);
        SetEnvVar('MAXCRON_AUTO_SWITCH_BUDGET_MAX', '2', aBackups);
        SetEnvVar('MAXCRON_AUTO_SWITCH_BUDGET_COOLDOWN', '20', aBackups);
      end else begin
        SetEnvVar('MAXCRON_AUTO_SWITCH_BUDGET_WINDOW', '0', aBackups);
        SetEnvVar('MAXCRON_AUTO_SWITCH_BUDGET_MAX', '0', aBackups);
        SetEnvVar('MAXCRON_AUTO_SWITCH_BUDGET_COOLDOWN', '0', aBackups);
      end;
    end;
  end;
end;

function RunScenarioIteration(const aScenario: TBenchmarkScenario; const aIteration: Integer): TBenchmarkSample;
var
  lBackups: TList<TEnvBackup>;
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lIndex: Integer;
  lTickAt: TDateTime;
  lStopwatch: TStopwatch;
  lDiagnostics: TMaxCronAutoDiagnostics;
begin
  Result := Default(TBenchmarkSample);
  Result.GroupName := aScenario.GroupName;
  Result.ScenarioName := aScenario.ScenarioName;
  Result.Engine := aScenario.Engine;
  Result.Iteration := aIteration;
  Result.EventCount := aScenario.EventCount;
  Result.TickCount := aScenario.TickCount;
  Result.TickStepSeconds := aScenario.TickStepSeconds;

  lBackups := TList<TEnvBackup>.Create;
  try
    ConfigureScenarioEnv(aScenario, lBackups);

    lCron := TmaxCron.Create(ctPortable);
    try
      for lIndex := 0 to aScenario.EventCount - 1 do
      begin
        lEvent := lCron.Add('Bench_' + aScenario.ScenarioName + '_' + IntToStr(lIndex));
        lEvent.EventPlan := aScenario.Plan;
        lEvent.Run;
      end;

      lCron.ResetTickMetricsForTests;
      lTickAt := Now;
      lStopwatch := TStopwatch.StartNew;
      for lIndex := 0 to aScenario.TickCount - 1 do
      begin
        lCron.TickAt(lTickAt);
        if aScenario.TickStepSeconds <> 0 then
          lTickAt := IncSecond(lTickAt, aScenario.TickStepSeconds);
      end;

      Result.ElapsedUs := Round((lStopwatch.ElapsedTicks * 1000000.0) / TStopwatch.Frequency);
      lCron.GetTickMetricsForTests(Result.EventsVisited, Result.HeapRebuilds);
      if lCron.TryGetAutoDiagnostics(lDiagnostics) then
      begin
        Result.SwitchCount := lDiagnostics.SwitchCount;
        Result.BudgetHits := lDiagnostics.SwitchBudgetHits;
        Result.ConfiguredEngine := lDiagnostics.ConfiguredEngine;
        Result.EffectiveEngine := lDiagnostics.EffectiveEngine;
        Result.AutoState := lDiagnostics.AutoState;
      end;
    finally
      lCron.Free;
    end;
  finally
    RestoreEnvVars(lBackups);
    lBackups.Free;
  end;
end;

procedure SortInt64Array(var aValues: TArray<Int64>);
begin
  TArray.Sort<Int64>(aValues);
end;

function CalculateMedianFromSorted(const aValues: TArray<Int64>): Double;
var
  lCount: Integer;
  lMiddle: Integer;
begin
  lCount := Length(aValues);
  if lCount = 0 then
    Exit(0.0);

  lMiddle := lCount div 2;
  if Odd(lCount) then
    Exit(aValues[lMiddle]);

  Result := (aValues[lMiddle - 1] + aValues[lMiddle]) / 2.0;
end;

function CalculateNearestRankPercentile(const aValues: TArray<Int64>; const aPercentile: Double): Double;
var
  lRank: Integer;
begin
  if Length(aValues) = 0 then
    Exit(0.0);

  lRank := Ceil((aPercentile / 100.0) * Length(aValues));
  if lRank < 1 then
    lRank := 1
  else if lRank > Length(aValues) then
    lRank := Length(aValues);

  Result := aValues[lRank - 1];
end;

function CalculateStdDev(const aValues: TArray<Int64>; const aMean: Double): Double;
var
  lIndex: Integer;
  lDelta: Double;
  lVarianceTotal: Double;
begin
  if Length(aValues) = 0 then
    Exit(0.0);

  lVarianceTotal := 0.0;
  for lIndex := 0 to High(aValues) do
  begin
    lDelta := aValues[lIndex] - aMean;
    lVarianceTotal := lVarianceTotal + (lDelta * lDelta);
  end;

  Result := Sqrt(lVarianceTotal / Length(aValues));
end;

function SummarizeScenario(const aScenario: TBenchmarkScenario;
  const aSamples: TList<TBenchmarkSample>): TScenarioSummary;
var
  lIndex: Integer;
  lSample: TBenchmarkSample;
  lElapsedUsSamples: TArray<Int64>;
  lElapsedSampleCount: Integer;
  lElapsedUsTotal: Double;
  lVisitedTotal: Double;
  lRebuildTotal: Double;
  lSwitchTotal: Double;
  lBudgetHitsTotal: Double;
begin
  Result := Default(TScenarioSummary);
  Result.GroupName := aScenario.GroupName;
  Result.ScenarioName := aScenario.ScenarioName;
  Result.Engine := aScenario.Engine;
  Result.MinElapsedUs := High(Int64);
  Result.MinVisited := High(UInt64);

  lElapsedUsTotal := 0;
  lVisitedTotal := 0;
  lRebuildTotal := 0;
  lSwitchTotal := 0;
  lBudgetHitsTotal := 0;
  SetLength(lElapsedUsSamples, 0);
  lElapsedSampleCount := 0;

  for lIndex := 0 to aSamples.Count - 1 do
  begin
    lSample := aSamples[lIndex];
    if not SameText(lSample.ScenarioName, aScenario.ScenarioName) then
      Continue;

    if lElapsedSampleCount >= Length(lElapsedUsSamples) then
      SetLength(lElapsedUsSamples, lElapsedSampleCount + 16);
    lElapsedUsSamples[lElapsedSampleCount] := lSample.ElapsedUs;
    Inc(lElapsedSampleCount);

    Inc(Result.Iterations);
    lElapsedUsTotal := lElapsedUsTotal + lSample.ElapsedUs;
    lVisitedTotal := lVisitedTotal + lSample.EventsVisited;
    lRebuildTotal := lRebuildTotal + lSample.HeapRebuilds;
    lSwitchTotal := lSwitchTotal + lSample.SwitchCount;
    lBudgetHitsTotal := lBudgetHitsTotal + lSample.BudgetHits;

    if lSample.ElapsedUs < Result.MinElapsedUs then
      Result.MinElapsedUs := lSample.ElapsedUs;
    if lSample.ElapsedUs > Result.MaxElapsedUs then
      Result.MaxElapsedUs := lSample.ElapsedUs;
    if lSample.EventsVisited < Result.MinVisited then
      Result.MinVisited := lSample.EventsVisited;
    if lSample.EventsVisited > Result.MaxVisited then
      Result.MaxVisited := lSample.EventsVisited;
  end;

  if Result.Iterations = 0 then
    raise Exception.CreateFmt('No samples found for scenario %s', [aScenario.ScenarioName]);

  SetLength(lElapsedUsSamples, lElapsedSampleCount);
  SortInt64Array(lElapsedUsSamples);

  Result.MeanElapsedUs := lElapsedUsTotal / Result.Iterations;
  Result.MedianElapsedUs := CalculateMedianFromSorted(lElapsedUsSamples);
  Result.P95ElapsedUs := CalculateNearestRankPercentile(lElapsedUsSamples, 95.0);
  Result.P99ElapsedUs := CalculateNearestRankPercentile(lElapsedUsSamples, 99.0);
  Result.StdDevElapsedUs := CalculateStdDev(lElapsedUsSamples, Result.MeanElapsedUs);
  Result.MeanVisited := lVisitedTotal / Result.Iterations;
  Result.MeanRebuilds := lRebuildTotal / Result.Iterations;
  Result.MeanSwitches := lSwitchTotal / Result.Iterations;
  Result.MeanBudgetHits := lBudgetHitsTotal / Result.Iterations;
end;

function BuildSummaries(const aScenarios: TArray<TBenchmarkScenario>;
  const aSamples: TList<TBenchmarkSample>): TArray<TScenarioSummary>;
var
  lIndex: Integer;
begin
  SetLength(Result, Length(aScenarios));
  for lIndex := 0 to High(aScenarios) do
    Result[lIndex] := SummarizeScenario(aScenarios[lIndex], aSamples);
end;

function FindSummary(const aSummaries: TArray<TScenarioSummary>; const aScenarioName: string;
  out aSummary: TScenarioSummary): Boolean;
var
  lIndex: Integer;
begin
  for lIndex := 0 to High(aSummaries) do
  begin
    if SameText(aSummaries[lIndex].ScenarioName, aScenarioName) then
    begin
      aSummary := aSummaries[lIndex];
      Exit(True);
    end;
  end;

  aSummary := Default(TScenarioSummary);
  Result := False;
end;

function SafePercentReduction(const aBaseline, aCandidate: Double): Double;
begin
  if aBaseline = 0 then
    Exit(0);
  Result := ((aBaseline - aCandidate) / aBaseline) * 100;
end;

function SafeSpeedup(const aBaseline, aCandidate: Double): Double;
begin
  if aCandidate = 0 then
    Exit(0);
  Result := aBaseline / aCandidate;
end;

function SafePercentDelta(const aBaseline, aCurrent: Double): Double;
begin
  if aBaseline = 0 then
    Exit(0);
  Result := ((aCurrent - aBaseline) / aBaseline) * 100.0;
end;

function ToSignedInvariantFloat(const aValue: Double): string;
begin
  Result := ToInvariantFloat(aValue);
  if aValue > 0 then
    Result := '+' + Result;
end;

procedure WriteCsv(const aPath: string; const aRunTimestampUtc, aMachineName: string;
  const aSamples: TList<TBenchmarkSample>);
var
  lCsv: TStringList;
  lIndex: Integer;
  lSample: TBenchmarkSample;
begin
  lCsv := TStringList.Create;
  try
    lCsv.Add('run_timestamp_utc,machine_name,scenario_group,scenario_name,engine,iteration,event_count,tick_count,' +
      'tick_step_seconds,elapsed_us,elapsed_ms,events_visited,heap_rebuilds,switch_count,budget_hits,' +
      'configured_engine,effective_engine,auto_state');

    for lIndex := 0 to aSamples.Count - 1 do
    begin
      lSample := aSamples[lIndex];
      lCsv.Add(
        CsvQuote(aRunTimestampUtc) + ',' +
        CsvQuote(aMachineName) + ',' +
        CsvQuote(lSample.GroupName) + ',' +
        CsvQuote(lSample.ScenarioName) + ',' +
        CsvQuote(lSample.Engine) + ',' +
        IntToStr(lSample.Iteration) + ',' +
        IntToStr(lSample.EventCount) + ',' +
        IntToStr(lSample.TickCount) + ',' +
        IntToStr(lSample.TickStepSeconds) + ',' +
        IntToStr(lSample.ElapsedUs) + ',' +
        ToInvariantFloat(ElapsedUsToMs(lSample.ElapsedUs)) + ',' +
        UIntToStr(lSample.EventsVisited) + ',' +
        UIntToStr(lSample.HeapRebuilds) + ',' +
        UIntToStr(lSample.SwitchCount) + ',' +
        IntToStr(lSample.BudgetHits) + ',' +
        CsvQuote(lSample.ConfiguredEngine) + ',' +
        CsvQuote(lSample.EffectiveEngine) + ',' +
        CsvQuote(lSample.AutoState));
    end;

    lCsv.SaveToFile(aPath, TEncoding.UTF8);
  finally
    lCsv.Free;
  end;
end;

function NormalizeCsvHeaderName(const aHeaderName: string): string;
begin
  Result := Trim(aHeaderName);
  if (Result <> '') and (Result[1] = #$FEFF) then
    Delete(Result, 1, 1);
end;

function SplitCsvLine(const aLine: string): TArray<string>;
var
  lValues: TList<string>;
  lBuilder: TStringBuilder;
  lChar: Char;
  lInQuotes: Boolean;
  lIndex: Integer;
begin
  lValues := TList<string>.Create;
  lBuilder := TStringBuilder.Create;
  try
    lInQuotes := False;
    lIndex := 1;
    while lIndex <= Length(aLine) do
    begin
      lChar := aLine[lIndex];
      if lChar = '"' then
      begin
        if lInQuotes and (lIndex < Length(aLine)) and (aLine[lIndex + 1] = '"') then
        begin
          lBuilder.Append('"');
          Inc(lIndex);
        end
        else
          lInQuotes := not lInQuotes;
      end else if (lChar = ',') and (not lInQuotes) then
      begin
        lValues.Add(lBuilder.ToString);
        lBuilder.Clear;
      end
      else
        lBuilder.Append(lChar);

      Inc(lIndex);
    end;

    lValues.Add(lBuilder.ToString);
    Result := lValues.ToArray;
  finally
    lBuilder.Free;
    lValues.Free;
  end;
end;

function FindCsvColumnIndex(const aHeaders: TArray<string>; const aColumnName: string): Integer;
var
  lIndex: Integer;
begin
  for lIndex := 0 to High(aHeaders) do
  begin
    if SameText(NormalizeCsvHeaderName(aHeaders[lIndex]), aColumnName) then
      Exit(lIndex);
  end;

  raise Exception.CreateFmt('CSV missing required column: %s', [aColumnName]);
end;

function ReadCsvField(const aFields: TArray<string>; const aColumnIndex: Integer; const aColumnName: string): string;
begin
  if (aColumnIndex < 0) or (aColumnIndex > High(aFields)) then
    raise Exception.CreateFmt('CSV row missing column "%s" at index %d', [aColumnName, aColumnIndex]);
  Result := Trim(aFields[aColumnIndex]);
end;

function ParseCsvInt64Field(const aFieldValue, aFieldName: string): Int64;
begin
  if not TryStrToInt64(Trim(aFieldValue), Result) then
    raise Exception.CreateFmt('Invalid Int64 in column %s: %s', [aFieldName, aFieldValue]);
end;

function ParseCsvUInt64Field(const aFieldValue, aFieldName: string): UInt64;
begin
  if not TryStrToUInt64(Trim(aFieldValue), Result) then
    raise Exception.CreateFmt('Invalid UInt64 in column %s: %s', [aFieldName, aFieldValue]);
end;

function ParseCsvIntegerField(const aFieldValue, aFieldName: string): Integer;
begin
  if not TryStrToInt(Trim(aFieldValue), Result) then
    raise Exception.CreateFmt('Invalid Integer in column %s: %s', [aFieldName, aFieldValue]);
end;

function LoadSamplesFromCsv(const aPath: string): TList<TBenchmarkSample>;
var
  lLines: TStringList;
  lHeader: TArray<string>;
  lFields: TArray<string>;
  lLineIndex: Integer;
  lSample: TBenchmarkSample;
  lGroupNameIndex: Integer;
  lScenarioNameIndex: Integer;
  lEngineIndex: Integer;
  lIterationIndex: Integer;
  lEventCountIndex: Integer;
  lTickCountIndex: Integer;
  lTickStepSecondsIndex: Integer;
  lElapsedUsIndex: Integer;
  lVisitedIndex: Integer;
  lRebuildsIndex: Integer;
  lSwitchCountIndex: Integer;
  lBudgetHitsIndex: Integer;
begin
  if not TFile.Exists(aPath) then
    raise Exception.CreateFmt('Baseline CSV does not exist: %s', [aPath]);

  lLines := TStringList.Create;
  try
    lLines.LoadFromFile(aPath, TEncoding.UTF8);
    if lLines.Count < 2 then
      raise Exception.CreateFmt('CSV has no data rows: %s', [aPath]);

    lHeader := SplitCsvLine(lLines[0]);
    lGroupNameIndex := FindCsvColumnIndex(lHeader, 'scenario_group');
    lScenarioNameIndex := FindCsvColumnIndex(lHeader, 'scenario_name');
    lEngineIndex := FindCsvColumnIndex(lHeader, 'engine');
    lIterationIndex := FindCsvColumnIndex(lHeader, 'iteration');
    lEventCountIndex := FindCsvColumnIndex(lHeader, 'event_count');
    lTickCountIndex := FindCsvColumnIndex(lHeader, 'tick_count');
    lTickStepSecondsIndex := FindCsvColumnIndex(lHeader, 'tick_step_seconds');
    lElapsedUsIndex := FindCsvColumnIndex(lHeader, 'elapsed_us');
    lVisitedIndex := FindCsvColumnIndex(lHeader, 'events_visited');
    lRebuildsIndex := FindCsvColumnIndex(lHeader, 'heap_rebuilds');
    lSwitchCountIndex := FindCsvColumnIndex(lHeader, 'switch_count');
    lBudgetHitsIndex := FindCsvColumnIndex(lHeader, 'budget_hits');

    Result := TList<TBenchmarkSample>.Create;
    try
      for lLineIndex := 1 to lLines.Count - 1 do
      begin
        if Trim(lLines[lLineIndex]) = '' then
          Continue;

        lFields := SplitCsvLine(lLines[lLineIndex]);
        lSample := Default(TBenchmarkSample);
        lSample.GroupName := ReadCsvField(lFields, lGroupNameIndex, 'scenario_group');
        lSample.ScenarioName := ReadCsvField(lFields, lScenarioNameIndex, 'scenario_name');
        lSample.Engine := ReadCsvField(lFields, lEngineIndex, 'engine');
        lSample.Iteration := ParseCsvIntegerField(ReadCsvField(lFields, lIterationIndex, 'iteration'), 'iteration');
        lSample.EventCount := ParseCsvIntegerField(ReadCsvField(lFields, lEventCountIndex, 'event_count'),
          'event_count');
        lSample.TickCount := ParseCsvIntegerField(ReadCsvField(lFields, lTickCountIndex, 'tick_count'), 'tick_count');
        lSample.TickStepSeconds := ParseCsvIntegerField(
          ReadCsvField(lFields, lTickStepSecondsIndex, 'tick_step_seconds'), 'tick_step_seconds');
        lSample.ElapsedUs := ParseCsvInt64Field(ReadCsvField(lFields, lElapsedUsIndex, 'elapsed_us'), 'elapsed_us');
        lSample.EventsVisited := ParseCsvUInt64Field(ReadCsvField(lFields, lVisitedIndex, 'events_visited'),
          'events_visited');
        lSample.HeapRebuilds := ParseCsvUInt64Field(ReadCsvField(lFields, lRebuildsIndex, 'heap_rebuilds'),
          'heap_rebuilds');
        lSample.SwitchCount := ParseCsvUInt64Field(ReadCsvField(lFields, lSwitchCountIndex, 'switch_count'),
          'switch_count');
        lSample.BudgetHits := ParseCsvIntegerField(ReadCsvField(lFields, lBudgetHitsIndex, 'budget_hits'),
          'budget_hits');
        Result.Add(lSample);
      end;
    except
      Result.Free;
      raise;
    end;
  finally
    lLines.Free;
  end;
end;

function LoadSummariesFromCsv(const aPath: string): TArray<TScenarioSummary>;
var
  lScenarios: TArray<TBenchmarkScenario>;
  lSamples: TList<TBenchmarkSample>;
begin
  lScenarios := BuildScenarios;
  lSamples := LoadSamplesFromCsv(aPath);
  try
    Result := BuildSummaries(lScenarios, lSamples);
  finally
    lSamples.Free;
  end;
end;

procedure AppendSummaryRow(const aLines: TStringList; const aSummary: TScenarioSummary);
begin
  aLines.Add('| ' + aSummary.ScenarioName + ' | ' + aSummary.Engine + ' | ' + IntToStr(aSummary.Iterations) +
    ' | ' + ToInvariantFloat(aSummary.MeanElapsedUs / 1000.0) + ' | ' +
    ToInvariantFloat(aSummary.MedianElapsedUs / 1000.0) + ' | ' +
    ToInvariantFloat(aSummary.P95ElapsedUs / 1000.0) + ' | ' +
    ToInvariantFloat(aSummary.P99ElapsedUs / 1000.0) + ' | ' +
    ToInvariantFloat(aSummary.StdDevElapsedUs / 1000.0) + ' | ' +
    ToInvariantFloat(ElapsedUsToMs(aSummary.MinElapsedUs)) + ' | ' +
    ToInvariantFloat(ElapsedUsToMs(aSummary.MaxElapsedUs)) + ' | ' + ToInvariantFloat(aSummary.MeanVisited) +
    ' | ' + UIntToStr(aSummary.MinVisited) + ' | ' + UIntToStr(aSummary.MaxVisited) +
    ' | ' + ToInvariantFloat(aSummary.MeanRebuilds) + ' | ' + ToInvariantFloat(aSummary.MeanSwitches) +
    ' | ' + ToInvariantFloat(aSummary.MeanBudgetHits) + ' |');
end;

procedure WriteMarkdown(const aPath: string; const aRunTimestampUtc, aMachineName: string;
  const aOptions: TBenchmarkOptions; const aSummaries, aBaselineSummaries: TArray<TScenarioSummary>;
  const aBaselineCsvPath: string);
var
  lLines: TStringList;
  lIndex: Integer;
  lScanSummary: TScenarioSummary;
  lHeapSummary: TScenarioSummary;
  lAutoSummary: TScenarioSummary;
  lNoBudgetSummary: TScenarioSummary;
  lBudgetSummary: TScenarioSummary;
  lBaselineSummary: TScenarioSummary;
  lCurrentSummary: TScenarioSummary;
  lValue: Double;
begin
  lLines := TStringList.Create;
  try
    lLines.Add('# maxCron benchmark report');
    lLines.Add('');
    lLines.Add('- Generated (UTC): ' + aRunTimestampUtc);
    lLines.Add('- Machine: ' + aMachineName);
    lLines.Add('- Iterations: ' + IntToStr(aOptions.Iterations));
    lLines.Add('- Warmup iterations: ' + IntToStr(aOptions.WarmupIterations));
    lLines.Add('');

    lLines.Add('## Scenario summary (means over measured iterations)');
    lLines.Add('');
    lLines.Add('| Scenario | Engine | Iterations | Elapsed ms mean | Elapsed ms median | Elapsed ms p95 | Elapsed ms p99 | ' +
      'Elapsed ms stddev | Elapsed ms min | Elapsed ms max | Visited mean | Visited min | Visited max | ' +
      'Rebuilds mean | Switches mean | Budget hits mean |');
    lLines.Add('| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |');
    for lIndex := 0 to High(aSummaries) do
      AppendSummaryRow(lLines, aSummaries[lIndex]);
    lLines.Add('');

    lLines.Add('## Comparative evaluation');
    lLines.Add('');

    if FindSummary(aSummaries, 'sparse_high_n_scan', lScanSummary) and
      FindSummary(aSummaries, 'sparse_high_n_heap', lHeapSummary) and
      FindSummary(aSummaries, 'sparse_high_n_auto', lAutoSummary) then
    begin
      lValue := SafePercentReduction(lScanSummary.MeanVisited, lHeapSummary.MeanVisited);
      lLines.Add('- Sparse high-N (`heap` vs `scan`) visited reduction: ' + ToInvariantFloat(lValue) + '%.');
      lValue := SafeSpeedup(lScanSummary.MeanElapsedUs, lHeapSummary.MeanElapsedUs);
      lLines.Add('- Sparse high-N (`heap` vs `scan`) elapsed speedup: ' + ToInvariantFloat(lValue) + 'x.');

      lValue := SafePercentReduction(lScanSummary.MeanVisited, lAutoSummary.MeanVisited);
      lLines.Add('- Sparse high-N (`auto` vs `scan`) visited reduction: ' + ToInvariantFloat(lValue) + '%.');
      lValue := SafeSpeedup(lScanSummary.MeanElapsedUs, lAutoSummary.MeanElapsedUs);
      lLines.Add('- Sparse high-N (`auto` vs `scan`) elapsed speedup: ' + ToInvariantFloat(lValue) + 'x.');
      lLines.Add('');
    end;

    if FindSummary(aSummaries, 'adversarial_auto_no_budget', lNoBudgetSummary) and
      FindSummary(aSummaries, 'adversarial_auto_budget', lBudgetSummary) then
    begin
      lValue := SafePercentReduction(lNoBudgetSummary.MeanSwitches, lBudgetSummary.MeanSwitches);
      lLines.Add('- Adversarial churn (budget vs no-budget) switch reduction: ' + ToInvariantFloat(lValue) + '%.');
      lValue := SafePercentReduction(lNoBudgetSummary.MeanRebuilds, lBudgetSummary.MeanRebuilds);
      lLines.Add('- Adversarial churn (budget vs no-budget) rebuild reduction: ' + ToInvariantFloat(lValue) + '%.');
      lValue := SafePercentReduction(lNoBudgetSummary.MeanVisited, lBudgetSummary.MeanVisited);
      lLines.Add('- Adversarial churn (budget vs no-budget) visited reduction: ' + ToInvariantFloat(lValue) + '%.');
      lValue := SafeSpeedup(lNoBudgetSummary.MeanElapsedUs, lBudgetSummary.MeanElapsedUs);
      lLines.Add('- Adversarial churn (budget vs no-budget) elapsed speedup: ' + ToInvariantFloat(lValue) + 'x.');
      lLines.Add('');
    end;

    if (aBaselineCsvPath <> '') and (Length(aBaselineSummaries) > 0) then
    begin
      lLines.Add('## Baseline comparison (current vs reference)');
      lLines.Add('');
      lLines.Add('- Baseline CSV: `' + aBaselineCsvPath + '`');
      lLines.Add('');
      lLines.Add('| Scenario | Baseline elapsed ms mean | Current elapsed ms mean | Elapsed delta % | ' +
        'Visited delta % | Rebuild delta % | Switch delta % |');
      lLines.Add('| --- | --- | --- | --- | --- | --- | --- |');
      for lIndex := 0 to High(aSummaries) do
      begin
        lCurrentSummary := aSummaries[lIndex];
        if not FindSummary(aBaselineSummaries, lCurrentSummary.ScenarioName, lBaselineSummary) then
          Continue;

        lLines.Add('| ' + lCurrentSummary.ScenarioName +
          ' | ' + ToInvariantFloat(lBaselineSummary.MeanElapsedUs / 1000.0) +
          ' | ' + ToInvariantFloat(lCurrentSummary.MeanElapsedUs / 1000.0) +
          ' | ' + ToSignedInvariantFloat(SafePercentDelta(lBaselineSummary.MeanElapsedUs, lCurrentSummary.MeanElapsedUs)) +
          ' | ' + ToSignedInvariantFloat(SafePercentDelta(lBaselineSummary.MeanVisited, lCurrentSummary.MeanVisited)) +
          ' | ' + ToSignedInvariantFloat(SafePercentDelta(lBaselineSummary.MeanRebuilds, lCurrentSummary.MeanRebuilds)) +
          ' | ' + ToSignedInvariantFloat(SafePercentDelta(lBaselineSummary.MeanSwitches, lCurrentSummary.MeanSwitches)) +
          ' |');
      end;
      lLines.Add('');
    end;

    lLines.SaveToFile(aPath, TEncoding.UTF8);
  finally
    lLines.Free;
  end;
end;

procedure EnsureOutputPaths(var aOptions: TBenchmarkOptions; out aRunTimestampUtc: string);
var
  lFileStamp: string;
begin
  aRunTimestampUtc := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss"Z"', TTimeZone.Local.ToUniversalTime(Now),
    TFormatSettings.Invariant);
  lFileStamp := FormatDateTime('yyyymmdd-hhnnss', Now);

  if aOptions.OutDir = '' then
    aOptions.OutDir := TPath.Combine(ExtractFilePath(ParamStr(0)), 'results');
  aOptions.OutDir := ExpandFileName(aOptions.OutDir);

  if aOptions.CsvPath = '' then
    aOptions.CsvPath := TPath.Combine(aOptions.OutDir, 'maxcron-benchmarks-' + lFileStamp + '.csv')
  else
    aOptions.CsvPath := ExpandFileName(aOptions.CsvPath);

  if aOptions.MdPath = '' then
    aOptions.MdPath := TPath.Combine(aOptions.OutDir, 'maxcron-benchmarks-' + lFileStamp + '.md')
  else
    aOptions.MdPath := ExpandFileName(aOptions.MdPath);

  if aOptions.CompareCsvPath <> '' then
    aOptions.CompareCsvPath := ExpandFileName(aOptions.CompareCsvPath);

  ForceDirectories(ExtractFilePath(aOptions.CsvPath));
  ForceDirectories(ExtractFilePath(aOptions.MdPath));
end;

procedure PrintBaselineComparison(const aCurrentSummaries, aBaselineSummaries: TArray<TScenarioSummary>;
  const aBaselineCsvPath: string);
var
  lIndex: Integer;
  lCurrentSummary: TScenarioSummary;
  lBaselineSummary: TScenarioSummary;
begin
  Writeln('');
  Writeln('Baseline deltas (current vs baseline):');
  Writeln('  baseline=' + aBaselineCsvPath);
  for lIndex := 0 to High(aCurrentSummaries) do
  begin
    lCurrentSummary := aCurrentSummaries[lIndex];
    if not FindSummary(aBaselineSummaries, lCurrentSummary.ScenarioName, lBaselineSummary) then
    begin
      Writeln('  ' + lCurrentSummary.ScenarioName + ': missing from baseline, skipped.');
      Continue;
    end;

    Writeln(Format('  %s: elapsedDeltaPct=%s visitedDeltaPct=%s rebuildDeltaPct=%s switchDeltaPct=%s',
      [lCurrentSummary.ScenarioName,
       ToSignedInvariantFloat(SafePercentDelta(lBaselineSummary.MeanElapsedUs, lCurrentSummary.MeanElapsedUs)),
       ToSignedInvariantFloat(SafePercentDelta(lBaselineSummary.MeanVisited, lCurrentSummary.MeanVisited)),
       ToSignedInvariantFloat(SafePercentDelta(lBaselineSummary.MeanRebuilds, lCurrentSummary.MeanRebuilds)),
       ToSignedInvariantFloat(SafePercentDelta(lBaselineSummary.MeanSwitches, lCurrentSummary.MeanSwitches))]));
  end;
end;

procedure RunBenchmarks(const aOptions: TBenchmarkOptions);
var
  lScenarios: TArray<TBenchmarkScenario>;
  lSamples: TList<TBenchmarkSample>;
  lSummaries: TArray<TScenarioSummary>;
  lBaselineSummaries: TArray<TScenarioSummary>;
  lScenarioIndex: Integer;
  lIteration: Integer;
  lSample: TBenchmarkSample;
  lRunTimestampUtc: string;
  lMachineName: string;
  lOptions: TBenchmarkOptions;
  lSummaryIndex: Integer;
begin
  lOptions := aOptions;
  EnsureOutputPaths(lOptions, lRunTimestampUtc);

  lMachineName := GetEnvironmentVariable('COMPUTERNAME');
  if lMachineName = '' then
    lMachineName := 'unknown-machine';

  SetLength(lBaselineSummaries, 0);
  if lOptions.CompareCsvPath <> '' then
  begin
    lBaselineSummaries := LoadSummariesFromCsv(lOptions.CompareCsvPath);
  end;

  lScenarios := BuildScenarios;
  lSamples := TList<TBenchmarkSample>.Create;
  try
    for lScenarioIndex := 0 to High(lScenarios) do
    begin
      if not lOptions.Quiet then
        Writeln('Scenario: ' + lScenarios[lScenarioIndex].ScenarioName);

      for lIteration := 1 to lOptions.WarmupIterations do
        RunScenarioIteration(lScenarios[lScenarioIndex], -lIteration);

      for lIteration := 1 to lOptions.Iterations do
      begin
        lSample := RunScenarioIteration(lScenarios[lScenarioIndex], lIteration);
        lSamples.Add(lSample);

        if not lOptions.Quiet then
          Writeln(Format('  iteration=%d elapsedUs=%d elapsedMs=%s visited=%s rebuilds=%s switches=%s budgetHits=%d',
            [lIteration, lSample.ElapsedUs, ToInvariantFloat(ElapsedUsToMs(lSample.ElapsedUs)),
            UIntToStr(lSample.EventsVisited), UIntToStr(lSample.HeapRebuilds), UIntToStr(lSample.SwitchCount),
            lSample.BudgetHits]));
      end;
    end;

    lSummaries := BuildSummaries(lScenarios, lSamples);
    WriteCsv(lOptions.CsvPath, lRunTimestampUtc, lMachineName, lSamples);
    WriteMarkdown(lOptions.MdPath, lRunTimestampUtc, lMachineName, lOptions, lSummaries, lBaselineSummaries,
      lOptions.CompareCsvPath);

    Writeln('');
    Writeln('Benchmark summaries:');
    for lSummaryIndex := 0 to High(lSummaries) do
    begin
      Writeln(Format(
        '  %s: elapsedMeanMs=%s elapsedMedianMs=%s elapsedP95Ms=%s elapsedStdDevMs=%s visitedMean=%s rebuildMean=%s switchMean=%s budgetHitsMean=%s',
        [lSummaries[lSummaryIndex].ScenarioName,
         ToInvariantFloat(lSummaries[lSummaryIndex].MeanElapsedUs / 1000.0),
         ToInvariantFloat(lSummaries[lSummaryIndex].MedianElapsedUs / 1000.0),
         ToInvariantFloat(lSummaries[lSummaryIndex].P95ElapsedUs / 1000.0),
         ToInvariantFloat(lSummaries[lSummaryIndex].StdDevElapsedUs / 1000.0),
         ToInvariantFloat(lSummaries[lSummaryIndex].MeanVisited),
         ToInvariantFloat(lSummaries[lSummaryIndex].MeanRebuilds),
         ToInvariantFloat(lSummaries[lSummaryIndex].MeanSwitches),
         ToInvariantFloat(lSummaries[lSummaryIndex].MeanBudgetHits)]));
    end;

    if Length(lBaselineSummaries) > 0 then
      PrintBaselineComparison(lSummaries, lBaselineSummaries, lOptions.CompareCsvPath);

    Writeln('');
    Writeln('CSV report: ' + lOptions.CsvPath);
    Writeln('Markdown report: ' + lOptions.MdPath);
  finally
    lSamples.Free;
  end;
end;


type
  TLatencyRecorder = class
  private
    fLock: TCriticalSection;
    fDone: TEvent;
    fTarget: Integer;
    fSamples: TList<Int64>;
    fRows: TStringList;
  public
    constructor Create(const aTarget: Integer);
    destructor Destroy; override;
    procedure Capture(const aDue, aNow: TDateTime);
  end;

constructor TLatencyRecorder.Create(const aTarget: Integer);
begin
  inherited Create;
  fTarget := aTarget;
  fLock := TCriticalSection.Create;
  fDone := TEvent.Create(nil, True, False, '');
  fSamples := TList<Int64>.Create;
  fRows := TStringList.Create;
  fRows.Add('fire,due_local,callback_local,latency_ms');
end;

destructor TLatencyRecorder.Destroy;
begin
  fRows.Free;
  fSamples.Free;
  fDone.Free;
  fLock.Free;
  inherited;
end;

procedure TLatencyRecorder.Capture(const aDue, aNow: TDateTime);
var
  lLatency: Double;
begin
  fLock.Acquire;
  try
    if fSamples.Count >= fTarget then
      Exit;
    // The callback owns its immutable due time, independent of worker arrival order.
    lLatency := (aNow - aDue) * MSecsPerDay;
    fSamples.Add(Round(lLatency * 1000));
    fRows.Add(Format('%d,%s,%s,%s', [fSamples.Count,
      FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz', aDue),
      FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz', aNow), ToInvariantFloat(lLatency)]));
    if fSamples.Count = fTarget then
      fDone.SetEvent;
  finally
    fLock.Release;
  end;
end;

procedure AddLatencyOccurrence(const aCron: TmaxCron; const aRecorder: TLatencyRecorder;
  const aDue: TDateTime);
var
  lEvent: IMaxCronEvent;
begin
  // Each invocation of this helper creates a distinct closure and one-shot plan.
  lEvent := aCron.Add('Latency' + FormatDateTime('hhnnss', aDue),
    Format('%d %d %d %d * %d %d 0', [MinuteOf(aDue), HourOf(aDue),
      DayOf(aDue), MonthOf(aDue), YearOf(aDue), SecondOf(aDue)]),
    procedure(aSender: IMaxCronEvent)
    begin
      aRecorder.Capture(aDue, CronPreciseLocalNowUs / Double(86400000000.0));
    end);
  lEvent.Run;
  if Abs(lEvent.NextSchedule - aDue) * MSecsPerDay > 0.5 then
    raise Exception.Create('Latency occurrence expired during setup');
end;

function ProcessCpuMs: Double;
{$IFDEF MSWINDOWS}
var
  lCreated, lExited, lKernel, lUser: TFileTime;
begin
  if not GetProcessTimes(GetCurrentProcess, lCreated, lExited, lKernel, lUser) then
    RaiseLastOSError;
  Result := ((UInt64(lKernel.dwHighDateTime) shl 32) + lKernel.dwLowDateTime +
    (UInt64(lUser.dwHighDateTime) shl 32) + lUser.dwLowDateTime) / 10000.0;
{$ELSE}
var
  lTime: timespec;
begin
  if clock_gettime(CLOCK_PROCESS_CPUTIME_ID, @lTime) <> 0 then
    RaiseLastOSError;
  Result := lTime.tv_sec * 1000.0 + lTime.tv_nsec / 1000000.0;
{$ENDIF}
end;

procedure RunRealtimeBenchmark(const aOptions: TBenchmarkOptions);
var
  g, lCronGarbo, lRecorderGarbo: TGarbos;
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lRecorder: TLatencyRecorder;
  lOptions: TBenchmarkOptions;
  lStamp: string;
  lLines, lReport: TStringList;
  lClock: TStopwatch;
  lCpuStart, lCpuMs, lElapsedMs: Double;
  lValues: TArray<Int64>;
  lMetrics: TMaxCronMetricsSnapshot;
  lIteration, i: Integer;
  lUnexpectedFires: Integer;
  lFirstDue: TDateTime;
begin
  lOptions := aOptions;
  // Separate filenames and schemas from the historical simulated-tick reports.
  if lOptions.OutDir = '' then
    lOptions.OutDir := TPath.Combine(ExtractFilePath(ParamStr(0)), 'results');
  if lOptions.CsvPath = '' then
    lOptions.CsvPath := TPath.Combine(lOptions.OutDir, 'maxcron-' + lOptions.Mode + '-' +
      FormatDateTime('yyyymmdd-hhnnss', Now) + '.csv');
  if lOptions.MdPath = '' then
    lOptions.MdPath := ChangeFileExt(lOptions.CsvPath, '.md');
  EnsureOutputPaths(lOptions, lStamp);
  GC(lLines, TStringList.Create, g);
  GC(lReport, TStringList.Create, g);
  try
    lReport.Add('# maxCron ' + lOptions.Mode + ' benchmark');
    lReport.Add('');
    lReport.Add('UTC: ' + lStamp + '; machine: ' + GetEnvironmentVariable('COMPUTERNAME'));
    lReport.Add('Portable timer; imThread; engine selected by MAXCRON_ENGINE.');
    if lOptions.Mode = 'idle' then
      lReport.Add(Format('Idle warmup %d seconds; use the same warmup for baseline comparisons.',
        [cIdleWarmupMs div 1000]))
    else
      lReport.Add('Latency warmup 2 seconds.');
    if lOptions.Mode = 'idle' then
      lLines.Add('iteration,events,configured_engine,effective_engine,elapsed_ms,cpu_ms,cpu_one_core_pct')
    else
      lLines.Add('iteration,fires,configured_engine,effective_engine,median_ms,p95_ms,max_ms');
    for lIteration := 1 to lOptions.Iterations do
    begin
      GC(lCron, TmaxCron.Create(TmaxCronTimerBackend.ctPortable), lCronGarbo);
      lRecorder := nil;
      lUnexpectedFires := 0;
      try
        lCron.DefaultInvokeMode := TmaxCronInvokeMode.imThread;
        if lOptions.Mode = 'idle' then
        begin
          lCron.StartTimerForTests(1000);
          for i := 1 to lOptions.EventCount do
          begin
            lEvent := lCron.Add('Idle' + IntToStr(i), '0 0 1 1 * 2099 0 0',
              procedure(aSender: IMaxCronEvent)
              begin
                // The far-future schedule must not fire in the measurement window.
                TInterlocked.Increment(lUnexpectedFires);
              end);
            lEvent.Run;
          end;
          // Keep the native startup pool's observed 30-second retirement outside the CPU window.
          Sleep(cIdleWarmupMs);
          lCpuStart := ProcessCpuMs;
          lClock := TStopwatch.StartNew;
          Sleep(Cardinal(lOptions.Seconds) * 1000);
          lElapsedMs := lClock.Elapsed.TotalMilliseconds;
          lCpuMs := ProcessCpuMs - lCpuStart;
          if TInterlocked.CompareExchange(lUnexpectedFires, 0, 0) <> 0 then
            raise Exception.Create('Far-future event fired during the idle window');
          lMetrics := lCron.GetMetricsSnapshot;
          lLines.Add(Format('%d,%d,%s,%s,%s,%s,%s', [lIteration, lOptions.EventCount,
            lMetrics.ConfiguredEngine, lMetrics.EffectiveEngine, ToInvariantFloat(lElapsedMs),
            ToInvariantFloat(lCpuMs), ToInvariantFloat(lCpuMs / lElapsedMs * 100)]));
        end else begin
          GC(lRecorder, TLatencyRecorder.Create(lOptions.Fires), lRecorderGarbo);
          Sleep(2000);
          // MAXCRON_TESTS keeps the timer stopped until every due time is captured.
          lFirstDue := RecodeMilliSecond(IncSecond(Now, 2), 0);
          for i := 0 to lOptions.Fires - 1 do
            AddLatencyOccurrence(lCron, lRecorder, IncSecond(lFirstDue, i));
          // Setup must finish before the earliest due time, or the stopped timer would count as lateness.
          if Now >= lFirstDue then
            raise Exception.Create('Latency setup outlived the first due time');
          lCron.StartTimerForTests(1000);
          if lRecorder.fDone.WaitFor(Cardinal(lOptions.Fires + 15) * 2000) <> wrSignaled then
            raise Exception.Create('Latency benchmark did not receive all callbacks');
          if not lCron.Shutdown(10000) then
            raise Exception.Create('Latency benchmark shutdown timed out');
          lValues := lRecorder.fSamples.ToArray;
          SortInt64Array(lValues);
          lMetrics := lCron.GetMetricsSnapshot;
          lLines.Add(Format('%d,%d,%s,%s,%s,%s,%s', [lIteration, Length(lValues),
            lMetrics.ConfiguredEngine, lMetrics.EffectiveEngine,
            ToInvariantFloat(CalculateMedianFromSorted(lValues) / 1000.0), ToInvariantFloat(CalculateNearestRankPercentile(lValues, 95.0) / 1000.0),
            ToInvariantFloat(lValues[High(lValues)] / 1000.0)]));
          lRecorder.fRows.SaveToFile(ChangeFileExt(lOptions.CsvPath, '') + '-fires-' +
            IntToStr(lIteration) + '.csv', TEncoding.UTF8);
        end;
        Writeln(lLines[lLines.Count - 1]);
      finally
        lEvent := nil;
        lCronGarbo.Clear;
        lRecorderGarbo.Clear;
      end;
    end;
    lLines.SaveToFile(lOptions.CsvPath, TEncoding.UTF8);
    lReport.Add('');
    lReport.Add('```csv');
    lReport.AddStrings(lLines);
    lReport.Add('```');
    lReport.Add('CPU percent is relative to one logical CPU, not the whole machine.');
    lReport.Add('Latency median averages the middle pair; p95 uses nearest rank; raw due/callback times are retained.');
    lReport.SaveToFile(lOptions.MdPath, TEncoding.UTF8);
    Writeln('CSV report: ' + lOptions.CsvPath);
  finally
    g.Clear;
  end;
end;

type
  TIntervalSample = record
    CallbackUs, DueUs: Int64;
  end;

  TIntervalAnalysis = record
    Missed, Duplicates: Int64;
    MedianUs, P95Us, P99Us: Double;
    MaxUs, LastCallbackUs: Int64;
    DueSlots: TArray<Int64>;
    HasMedianBound, Passed: Boolean;
  end;

TIntervalMedianBound = record
    PeriodMs, MedianUs: Integer;
  end;

const
  cIntervalMedianBounds: array[0..1] of TIntervalMedianBound = (
    (PeriodMs: 10; MedianUs: 1500),
    (PeriodMs: 100; MedianUs: 1500)
  );

function AnalyzeIntervalSamples(const aSamples: TArray<TIntervalSample>;
  const aStartUs, aPeriodUs, aNominalSlots: Int64): TIntervalAnalysis;
var
  lCoveredSlots: THashSet<Int64>;
  lBound: TIntervalMedianBound;
  lMedianLimitUs, lDeltaUs, lSlot, lRemainderUs: Int64;
  lValues: TArray<Int64>;
  i: Integer;
begin
  Result := Default(TIntervalAnalysis);
  Result.Missed := aNominalSlots;
  lMedianLimitUs := 0;
  for lBound in cIntervalMedianBounds do
    if Int64(lBound.PeriodMs) * 1000 = aPeriodUs then
    begin
      Result.HasMedianBound := True;
      lMedianLimitUs := lBound.MedianUs;
      Break;
    end;
  // There is no median to qualify when no callbacks arrived.
  if Length(aSamples) = 0 then
    Exit;

  SetLength(Result.DueSlots, Length(aSamples));
  SetLength(lValues, Length(aSamples));
  lCoveredSlots := THashSet<Int64>.Create;
  try
    for i := 0 to High(aSamples) do
    begin
      lDeltaUs := aSamples[i].DueUs - aStartUs;
      lSlot := lDeltaUs div aPeriodUs;
      lRemainderUs := lDeltaUs mod aPeriodUs;
      // Start at the preceding slot, then round to the nearest. Ties go forward.
      if lRemainderUs < 0 then
      begin
        Dec(lSlot);
        Inc(lRemainderUs, aPeriodUs);
      end;
      if lRemainderUs >= aPeriodUs - lRemainderUs then
        Inc(lSlot);
      Result.DueSlots[i] := lSlot;
      if (lSlot >= 1) and (lSlot <= aNominalSlots) then
        lCoveredSlots.Add(lSlot);

      lValues[i] := aSamples[i].CallbackUs - aSamples[i].DueUs;
      if (i = 0) or (aSamples[i].CallbackUs > Result.LastCallbackUs) then
        Result.LastCallbackUs := aSamples[i].CallbackUs;
    end;
    Result.Missed := aNominalSlots - lCoveredSlots.Count;
    Result.Duplicates := Length(aSamples) - lCoveredSlots.Count;
  finally
    lCoveredSlots.Free;
  end;

  SortInt64Array(lValues);
  Result.MedianUs := CalculateMedianFromSorted(lValues);
  Result.P95Us := CalculateNearestRankPercentile(lValues, 95.0);
  Result.P99Us := CalculateNearestRankPercentile(lValues, 99.0);
  Result.MaxUs := lValues[High(lValues)];
  Result.Passed := Result.HasMedianBound and (Result.Missed = 0) and (Result.Duplicates = 0) and
    (Result.MedianUs <= lMedianLimitUs);
end;

function ReferenceIntervalAnalysis(const aSamples: TArray<TIntervalSample>;
  const aStartUs, aPeriodUs, aNominalSlots: Int64): TIntervalAnalysis;
var
  lSeen: TArray<Boolean>;
  lLateness: TArray<Int64>;
  lBound: TIntervalMedianBound;
  lMedianLimitUs, lValue: Int64;
  lCount, i, j: Integer;
begin
  Result := Default(TIntervalAnalysis);
  Result.Missed := aNominalSlots;
  lMedianLimitUs := 0;
  for lBound in cIntervalMedianBounds do
    if Int64(lBound.PeriodMs) * 1000 = aPeriodUs then
    begin
      Result.HasMedianBound := True;
      lMedianLimitUs := lBound.MedianUs;
    end;

  lCount := Length(aSamples);
  SetLength(lSeen, aNominalSlots);
  SetLength(lLateness, lCount);
  SetLength(Result.DueSlots, lCount);
  for i := 0 to lCount - 1 do
  begin
    lValue := Floor((aSamples[i].DueUs - aStartUs) / aPeriodUs + 0.5);
    Result.DueSlots[i] := lValue;
    if (lValue < 1) or (lValue > aNominalSlots) then
      Inc(Result.Duplicates)
    else if lSeen[lValue - 1] then
      Inc(Result.Duplicates)
    else begin
      lSeen[lValue - 1] := True;
      Dec(Result.Missed);
    end;
    if (i = 0) or (aSamples[i].CallbackUs > Result.LastCallbackUs) then
      Result.LastCallbackUs := aSamples[i].CallbackUs;

    // Insertion sort keeps the reference independent of the report's statistics helpers.
    lValue := aSamples[i].CallbackUs - aSamples[i].DueUs;
    j := i;
    while j > 0 do
    begin
      if lLateness[j - 1] <= lValue then
        Break;
      lLateness[j] := lLateness[j - 1];
      Dec(j);
    end;
    lLateness[j] := lValue;
  end;

  if lCount = 0 then
    Exit;
  Result.MedianUs := (lLateness[(lCount - 1) div 2] + lLateness[lCount div 2]) / 2;
  Result.P95Us := lLateness[(95 * lCount - 1) div 100];
  Result.P99Us := lLateness[(99 * lCount - 1) div 100];
  Result.MaxUs := lLateness[lCount - 1];
  Result.Passed := Result.HasMedianBound and (Result.Missed = 0) and (Result.Duplicates = 0) and
    (Result.MedianUs <= lMedianLimitUs);
end;

procedure RunIntervalSelfTest;
const
  cStartUs = 1000000;
  cPeriodUs = 10000;
  cCasesPerSeed = 4096;
  cSeeds: array[0..2] of Cardinal = ($00000001, $13579BDF, $C0FFEE01);
var
  lSamples: TArray<TIntervalSample>;
  lNamedCount, lFailures, lPropertyFailures, lTrial, lSeedFailures, i: Integer;
  lSeed, lRandomState: Cardinal;
  lStartUs, lPeriodUs, lSlots: Int64;

  procedure SetSample(const aIndex: Integer; const aDueOffsetUs, aArrivalOffsetUs: Int64);
  begin
    lSamples[aIndex].DueUs := lStartUs + aDueOffsetUs;
    lSamples[aIndex].CallbackUs := lStartUs + aArrivalOffsetUs;
  end;

  procedure CheckCase(const aName: string; const aSlots, aMissed, aDuplicates: Int64;
    const aMedianUs, aMaxUs: Double; const aHasMedianBound, aPassed: Boolean);
  var
    lActual: TIntervalAnalysis;
  begin
    Inc(lNamedCount);
    try
      lActual := AnalyzeIntervalSamples(lSamples, lStartUs, lPeriodUs, aSlots);
      Writeln(Format('%s: fires=%d missed=%d duplicates=%d median_us=%s max_us=%d bounded=%s passed=%s',
        [aName, Length(lSamples), lActual.Missed, lActual.Duplicates,
        ToInvariantFloat(lActual.MedianUs), lActual.MaxUs, BoolToStr(lActual.HasMedianBound, True),
        BoolToStr(lActual.Passed, True)]));
      if (lActual.Missed = aMissed) and (lActual.Duplicates = aDuplicates) and
        (lActual.MedianUs = aMedianUs) and (lActual.MaxUs = aMaxUs) and
        (lActual.HasMedianBound = aHasMedianBound) and (lActual.Passed = aPassed) then
        Exit;
    except
      on E: Exception do
        Writeln(aName + ': ' + E.Message);
    end;
    Inc(lFailures);
    Writeln(aName + ': FAIL');
  end;

  function Draw(const aLimit: Cardinal): Integer;
  begin
    lRandomState := lRandomState xor (lRandomState shl 13);
    lRandomState := lRandomState xor (lRandomState shr 17);
    lRandomState := lRandomState xor (lRandomState shl 5);
    Result := lRandomState mod aLimit;
  end;

  procedure Generate(const aTrial: Integer);
  const
    cPeriodsUs: array[0..3] of Integer = (10000, 100000, 1000, 10001);
  var
    lScenario, lCount, lIndex, lDueSlot, lRepeatedSlot: Integer;
    lDueOffsetUs, lArrivalOffsetUs, lLateUs: Int64;
  begin
    lScenario := aTrial mod 9;
    lStartUs := 1000000000000 + Draw(1000000);
    lPeriodUs := cPeriodsUs[Draw(Length(cPeriodsUs))];
    lSlots := 2 + Draw(24);
    lCount := lSlots;
    case lScenario of
      3, 4:
        begin
          lPeriodUs := cPeriodsUs[Draw(2)];
          lSlots := 2 * (1 + Draw(12));
          lCount := lSlots;
        end;
      5:
        begin
          lSlots := 0;
          lCount := Draw(4);
        end;
      6:
        begin
          lSlots := 1;
          lCount := Draw(4);
        end;
      8:
        lCount := Draw(2 * lSlots + 1);
    end;
    SetLength(lSamples, lCount);
    lRepeatedSlot := 1 + Draw(lSlots + 1);
    for lIndex := 0 to lCount - 1 do
    begin
      lDueSlot := lIndex + 1;
      lDueOffsetUs := lDueSlot * lPeriodUs;
      lLateUs := Draw(3003) - 1501;
      case lScenario of
        0: // Due ticks and arrivals around half-period and delivery boundaries.
          lDueOffsetUs := lDueOffsetUs + lPeriodUs div 2 + Draw(3) - 1;
        1: // A stall followed by a catch-up burst at the end of the run.
          lLateUs := (lSlots - lDueSlot) * lPeriodUs + Draw(901);
        2: // Duplicate a due slot while spreading arrivals across the nominal windows.
          if lIndex < 2 then
            lDueOffsetUs := lRepeatedSlot * lPeriodUs;
        3, 4: // The average of the even middle pair is exactly 1500 or 1501 us.
          begin
            lLateUs := 1500 + lScenario - 3;
            if Odd(lIndex) then
              Inc(lLateUs)
            else
              Dec(lLateUs);
          end;
        5, 6, 8: // Missing, repeated and out-of-range due slots, including negative offsets.
          lDueOffsetUs := (Draw(lSlots + 5) - 2) * lPeriodUs + Draw(3) - 1;
      end;
      lArrivalOffsetUs := lDueOffsetUs + lLateUs;
      if lScenario = 0 then
        lArrivalOffsetUs := lDueSlot * lPeriodUs + Draw(3) - 1
      else if lScenario = 2 then
        lArrivalOffsetUs := lDueSlot * lPeriodUs + Draw(901);
      SetSample(lIndex, lDueOffsetUs, lArrivalOffsetUs);
    end;
  end;

  procedure CompareWithReference(const aTrial: Integer; const aReportMismatch: Boolean);
  var
    lActual, lExpected: TIntervalAnalysis;
    lIndex: Integer;
    lSample: TIntervalSample;

    procedure Check(const aMatches: Boolean; const aField: string);
    begin
      if not aMatches then
        raise Exception.Create('interval result differs in ' + aField);
    end;

  begin
    try
      lExpected := ReferenceIntervalAnalysis(lSamples, lStartUs, lPeriodUs, lSlots);
      lActual := AnalyzeIntervalSamples(lSamples, lStartUs, lPeriodUs, lSlots);
      Check(lActual.Missed = lExpected.Missed, 'Missed');
      Check(lActual.Duplicates = lExpected.Duplicates, 'Duplicates');
      Check(lActual.MedianUs = lExpected.MedianUs, 'MedianUs');
      Check(lActual.P95Us = lExpected.P95Us, 'P95Us');
      Check(lActual.P99Us = lExpected.P99Us, 'P99Us');
      Check(lActual.MaxUs = lExpected.MaxUs, 'MaxUs');
      Check(lActual.LastCallbackUs = lExpected.LastCallbackUs, 'LastCallbackUs');
      Check(lActual.HasMedianBound = lExpected.HasMedianBound, 'HasMedianBound');
      Check(lActual.Passed = lExpected.Passed, 'Passed');
      Check(Length(lActual.DueSlots) = Length(lExpected.DueSlots), 'DueSlots length');
      for lIndex := 0 to High(lExpected.DueSlots) do
        Check(lActual.DueSlots[lIndex] = lExpected.DueSlots[lIndex], 'DueSlots');
    except
      on E: Exception do
      begin
        Inc(lSeedFailures);
        if aReportMismatch then
        begin
          Writeln(Format('seed=%s trial=%d start_us=%d period_us=%d nominal=%d: %s',
            [IntToHex(lSeed, 8), aTrial, lStartUs, lPeriodUs, lSlots, E.Message]));
          for lSample in lSamples do
            Writeln(Format('  due_offset_us=%d arrival_offset_us=%d',
              [lSample.DueUs - lStartUs, lSample.CallbackUs - lStartUs]));
        end;
      end;
    end;
  end;

begin
  lNamedCount := 0;
  lFailures := 0;
  lPropertyFailures := 0;
  lStartUs := cStartUs;
  lPeriodUs := cPeriodUs;

  SetLength(lSamples, 6000);
  for i := 0 to High(lSamples) do
    if i < 3600 then
      SetSample(i, (i + 1) * cPeriodUs, (i + 1) * cPeriodUs + 10500)
    else
      SetSample(i, (i + 1) * cPeriodUs, (i + 1) * cPeriodUs + 600);
  CheckCase('backlog', 6000, 0, 0, 10500, 10500, True, False);

  SetLength(lSamples, 2);
  SetSample(0, 10000, 10500);
  SetSample(1, 20000, 20750);
  CheckCase('clean', 2, 0, 0, 625, 750, True, True);

  SetSample(1, 20000, 20000);
  CheckCase('boundary', 2, 0, 0, 250, 500, True, True);

  lSamples := nil;
  CheckCase('zero callbacks', 3, 3, 0, 0, 0, True, False);
  CheckCase('interval exceeds window', 0, 0, 0, 0, 0, True, False);

  SetLength(lSamples, 3);
  SetSample(0, 10000, 10500);
  SetSample(1, 10000, 20500);
  SetSample(2, 30000, 30500);
  CheckCase('duplicate due and empty middle', 3, 1, 1, 500, 10500, True, False);

  for i := 0 to High(lSamples) do
    SetSample(i, (i + 1) * cPeriodUs, (i + 1) * cPeriodUs + 1501);
  CheckCase('median above bound', 3, 0, 0, 1501, 1501, True, False);

  for i := 0 to High(lSamples) do
    SetSample(i, (i + 1) * cPeriodUs, (i + 1) * cPeriodUs + 1500);
  CheckCase('median equal to bound', 3, 0, 0, 1500, 1500, True, True);

  SetLength(lSamples, 4);
  SetSample(0, 14999, 15000);
  SetSample(1, 25000, 25000);
  SetSample(2, 34999, 35000);
  SetSample(3, 44999, 45000);
  CheckCase('due half-boundary tie', 4, 1, 1, 1, 1, True, False);

  lPeriodUs := 1000;
  SetLength(lSamples, 1);
  SetSample(0, 1000, 1050);
  CheckCase('unbounded interval', 1, 0, 0, 50, 50, False, False);

  for lSeed in cSeeds do
  begin
    lRandomState := lSeed;
    lSeedFailures := 0;
    for lTrial := 0 to cCasesPerSeed - 1 do
    begin
      Generate(lTrial);
      CompareWithReference(lTrial, lSeedFailures = 0);
    end;
    Inc(lPropertyFailures, lSeedFailures);
    Writeln(Format('Interval property seed %s: %d/%d passed',
      [IntToHex(lSeed, 8), cCasesPerSeed - lSeedFailures, cCasesPerSeed]));
  end;

  Writeln(Format('Interval self-test: %d/%d named, %d/%d generated passed',
    [lNamedCount - lFailures, lNamedCount, Length(cSeeds) * cCasesPerSeed - lPropertyFailures,
    Length(cSeeds) * cCasesPerSeed]));
  if (lFailures <> 0) or (lPropertyFailures <> 0) then
    raise Exception.Create('Interval self-test failed');
end;

type
  TIntervalRecorder = class
  public
    fLock: TCriticalSection;
    fDone: TEvent;
    fSamples: TList<TIntervalSample>;
    fStartUs, fWindowUs: Int64;
    fTarget: Integer;
    fMissingDue: Boolean;
    constructor Create(const aTarget: Integer; const aWindowUs: Int64);
    destructor Destroy; override;
    procedure Capture(aSender: IMaxCronEvent);
  end;

constructor TIntervalRecorder.Create(const aTarget: Integer; const aWindowUs: Int64);
begin
  inherited Create;
  fLock := TCriticalSection.Create;
  fDone := TEvent.Create(nil, True, False, '');
  fSamples := TList<TIntervalSample>.Create;
  fTarget := aTarget;
  fWindowUs := aWindowUs;
end;

destructor TIntervalRecorder.Destroy;
begin
  fSamples.Free;
  fDone.Free;
  fLock.Free;
  inherited;
end;

procedure TIntervalRecorder.Capture(aSender: IMaxCronEvent);
var
  lSample: TIntervalSample;
  lUnusedUtcUs: Int64;
  lHasDue: Boolean;
begin
  lSample.CallbackUs := CronMonotonicNowUs;
  lHasDue := CurrentMaxCronOccurrenceForTests(lUnusedUtcUs, lSample.DueUs);
  fLock.Acquire;
  try
    if fWindowUs > 0 then
    begin
      if lSample.CallbackUs - fStartUs >= fWindowUs then
        Exit;
    end else if fSamples.Count >= fTarget then
      Exit;
    fMissingDue := fMissingDue or not lHasDue;
    fSamples.Add(lSample);
    if (fWindowUs = 0) and (fSamples.Count = fTarget) then
      fDone.SetEvent;
  finally
    fLock.Release;
  end;
end;

function RunIntervalBenchmark(const aOptions: TBenchmarkOptions): Boolean;
var
  g, lIterationGarbo: TGarbos;
  lOptions: TBenchmarkOptions;
  lLines, lRaw: TStringList;
  lCron: TmaxCron;
  lEvent: IMaxCronEvent;
  lRecorder: TIntervalRecorder;
  lAnalysis: TIntervalAnalysis;
  lSamples: TArray<TIntervalSample>;
  lSample: TIntervalSample;
  lCpuStart, lCpuMs, lElapsedMs: Double;
  lPeriodUs, lWindowUs, lEndUs: Int64;
  lStamp, lPassed: string;
  lTicks, lSpin, lExceptions: UInt64;
  lIteration, i: Integer;
begin
  Result := True;
  lOptions := aOptions;
  if lOptions.CsvPath = '' then
    lOptions.CsvPath := TPath.Combine(lOptions.OutDir, 'maxcron-interval-' +
      FormatDateTime('yyyymmdd-hhnnss', Now) + '.csv');
  if lOptions.MdPath = '' then
    lOptions.MdPath := ChangeFileExt(lOptions.CsvPath, '.md');
  EnsureOutputPaths(lOptions, lStamp);
  GC(lLines, TStringList.Create, g);
  GC(lRaw, TStringList.Create, g);
  lLines.Add('iteration,interval_ms,fires,median_ms,p95_ms,p99_ms,max_ms,missed,elapsed_ms,cpu_ms,cpu_one_core_pct,duplicates,passed');
  lPeriodUs := Int64(lOptions.IntervalMs) * 1000;
  lWindowUs := 0;
  if lOptions.IntervalDuration then
  begin
    // Observe the entire delivery window of the last nominal slot.
    if lOptions.Fires > 0 then
      lWindowUs := (Int64(lOptions.Fires) + 1) * lPeriodUs
    else
      lWindowUs := Int64(lOptions.Seconds) * 1000000;
  end;

  for lIteration := 1 to lOptions.Iterations do
  begin
    GC(lRecorder, TIntervalRecorder.Create(lOptions.Fires, lWindowUs), lIterationGarbo);
    GC(lCron, TmaxCron.Create(ctPortable), lIterationGarbo);
    try
      lCron.DefaultInvokeMode := imTTask;
      lEvent := lCron.AddInterval('interval benchmark', Cardinal(lOptions.IntervalMs), lRecorder.Capture);
      // Keep task-pool initialization outside the measurement, as in latency mode.
      TThread.Sleep(2000);
      lCpuStart := ProcessCpuMs;
      lRecorder.fStartUs := CronMonotonicNowUs;
      lEndUs := lRecorder.fStartUs + lWindowUs;
      lEvent.Run;
      lCron.StartTimerForTests(1000);
      if lOptions.IntervalDuration then
      begin
        TThread.Sleep(Cardinal((Max(0, lEndUs - CronMonotonicNowUs) + 999) div 1000));
      end else if lRecorder.fDone.WaitFor(Cardinal((Int64(lOptions.Fires) *
        lOptions.IntervalMs) div 1000 + 15) * 1000) <> wrSignaled then
        raise Exception.Create('Interval benchmark did not receive all callbacks');
      lEvent.Stop;
      if not lCron.Shutdown(10000) then
        raise Exception.Create('Interval benchmark shutdown timed out');
      lCpuMs := ProcessCpuMs - lCpuStart;
      if lRecorder.fMissingDue then
        raise Exception.Create('Interval callback has no scheduled due time');
      lSamples := lRecorder.fSamples.ToArray;
      lAnalysis := AnalyzeIntervalSamples(lSamples, lRecorder.fStartUs, lPeriodUs, lOptions.Fires);
      if not lOptions.IntervalDuration then
        lEndUs := lAnalysis.LastCallbackUs;
      lElapsedMs := (lEndUs - lRecorder.fStartUs) / 1000.0;

      lCron.GetTimerDiagnosticsForTests(lTicks, lSpin, lExceptions);
      if (lSpin <> 0) or (lExceptions <> 0) then
        raise Exception.Create('Interval timer spin or exception');
      lPassed := '';
      if lAnalysis.HasMedianBound then
        lPassed := LowerCase(BoolToStr(lAnalysis.Passed, True));
      lLines.Add(Format('%d,%d,%d,%s,%s,%s,%s,%d,%s,%s,%s,%d,%s',
        [lIteration, lOptions.IntervalMs, Length(lSamples),
        ToInvariantFloat(lAnalysis.MedianUs / 1000.0),
        ToInvariantFloat(lAnalysis.P95Us / 1000.0),
        ToInvariantFloat(lAnalysis.P99Us / 1000.0),
        ToInvariantFloat(lAnalysis.MaxUs / 1000.0), lAnalysis.Missed,
        ToInvariantFloat(lElapsedMs), ToInvariantFloat(lCpuMs), ToInvariantFloat(lCpuMs / lElapsedMs * 100),
        lAnalysis.Duplicates, lPassed]));
      lRaw.Clear;
      lRaw.Add('iteration,callback_mono_us,elapsed_us,lateness_us,due_slot,due_mono_us');
      for i := 0 to High(lSamples) do
      begin
        lSample := lSamples[i];
        lRaw.Add(Format('%d,%d,%d,%d,%d,%d', [i + 1, lSample.CallbackUs,
          lSample.CallbackUs - lRecorder.fStartUs, lSample.CallbackUs - lSample.DueUs,
          lAnalysis.DueSlots[i], lSample.DueUs]));
      end;
      lRaw.SaveToFile(ChangeFileExt(lOptions.CsvPath, '') + '-fires-' + IntToStr(lIteration) + '.csv', TEncoding.UTF8);
      Writeln(lLines[lLines.Count - 1]);
      lLines.SaveToFile(lOptions.CsvPath, TEncoding.UTF8);
      Result := Result and (Length(lSamples) > 0) and (not lAnalysis.HasMedianBound or lAnalysis.Passed);
    finally
      lEvent := nil;
      lIterationGarbo.Clear;
    end;
  end;
end;

var
  lOptions: TBenchmarkOptions;
begin
  try
    ExitCode := 0;
    ParseOptions(lOptions);
    if lOptions.Mode = 'interval' then
    begin
      if not RunIntervalBenchmark(lOptions) then
        ExitCode := 1;
    end else if lOptions.Mode = 'selftest' then
      RunIntervalSelfTest
    else if lOptions.Mode = 'ticks' then
      RunBenchmarks(lOptions)
    else
      RunRealtimeBenchmark(lOptions);
  except
    on E: Exception do
    begin
      Writeln(E.ClassName + ': ' + E.Message);
      ExitCode := 2;
    end;
  end;
end.

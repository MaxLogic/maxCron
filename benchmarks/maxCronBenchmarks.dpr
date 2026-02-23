program maxCronBenchmarks;

{$APPTYPE CONSOLE}
{$DEFINE MAXCRON_TESTS}

uses
  System.Classes, System.DateUtils, System.Diagnostics, System.Generics.Collections, System.IOUtils, System.Math,
  System.StrUtils, System.SysUtils,
  Winapi.Windows,
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
    PreviousValue: string;
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
  end;

const
  cDefaultIterations = 9;
  cDefaultWarmupIterations = 2;

procedure SetEnvVar(const aName, aValue: string; const aBackups: TList<TEnvBackup>);
var
  lBackup: TEnvBackup;
begin
  lBackup.Name := aName;
  lBackup.PreviousValue := GetEnvironmentVariable(aName);
  lBackup.HadPrevious := lBackup.PreviousValue <> '';
  aBackups.Add(lBackup);
  Winapi.Windows.SetEnvironmentVariable(PChar(aName), PChar(aValue));
end;

procedure RestoreEnvVars(const aBackups: TList<TEnvBackup>);
var
  lIndex: Integer;
  lBackup: TEnvBackup;
begin
  for lIndex := aBackups.Count - 1 downto 0 do
  begin
    lBackup := aBackups[lIndex];
    if lBackup.HadPrevious then
      Winapi.Windows.SetEnvironmentVariable(PChar(lBackup.Name), PChar(lBackup.PreviousValue))
    else
      Winapi.Windows.SetEnvironmentVariable(PChar(lBackup.Name), nil);
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
begin
  aOptions.Iterations := cDefaultIterations;
  aOptions.WarmupIterations := cDefaultWarmupIterations;
  aOptions.OutDir := '';
  aOptions.CsvPath := '';
  aOptions.MdPath := '';
  aOptions.CompareCsvPath := '';
  aOptions.Quiet := False;

  for lIndex := 1 to ParamCount do
  begin
    lArg := ParamStr(lIndex);
    if SameText(lArg, '--quiet') then
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
        '[--compare=FILE] [--quiet]')
    else
      raise Exception.CreateFmt('Unknown option: %s', [lArg]);
  end;
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
    lLines.Add('| Scenario | Engine | Iterations | Elapsed ms mean | Elapsed ms median | Elapsed ms p95 | ' +
      'Elapsed ms stddev | Elapsed ms min | Elapsed ms max | Visited mean | Visited min | Visited max | ' +
      'Rebuilds mean | Switches mean | Budget hits mean |');
    lLines.Add('| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |');
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

var
  lOptions: TBenchmarkOptions;
begin
  try
    ParseOptions(lOptions);
    RunBenchmarks(lOptions);
    ExitCode := 0;
  except
    on E: Exception do
    begin
      Writeln(E.ClassName + ': ' + E.Message);
      ExitCode := 2;
    end;
  end;
end.

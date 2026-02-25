unit TestLongSoak24h;

interface

uses
  System.Classes, System.DateUtils, System.Math, System.SyncObjs, System.SysUtils,
  Winapi.Windows,
  DUnitX.TestFramework,
  maxCron;

type
  [TestFixture]
  TTestLongSoak24h = class
  private
    procedure SetEnvVar(const aName, aValue: string; out aPreviousValue: string; out aHadPrevious: Boolean);
    procedure RestoreEnvVar(const aName, aPreviousValue: string; const aHadPrevious: Boolean);
    function IsSupportedMode(const aMode: string): Boolean;
    function ParseModes(const aValue: string): TArray<string>;
  public
    [Test]
    procedure EngineModes_LogicalSoak_NoMisses;
  end;

implementation

procedure TTestLongSoak24h.SetEnvVar(const aName, aValue: string; out aPreviousValue: string;
  out aHadPrevious: Boolean);
begin
  aPreviousValue := GetEnvironmentVariable(aName);
  aHadPrevious := aPreviousValue <> '';
  Winapi.Windows.SetEnvironmentVariable(PChar(aName), PChar(aValue));
end;

procedure TTestLongSoak24h.RestoreEnvVar(const aName, aPreviousValue: string; const aHadPrevious: Boolean);
begin
  if aHadPrevious then
    Winapi.Windows.SetEnvironmentVariable(PChar(aName), PChar(aPreviousValue))
  else
    Winapi.Windows.SetEnvironmentVariable(PChar(aName), nil);
end;

function TTestLongSoak24h.IsSupportedMode(const aMode: string): Boolean;
begin
  Result := (aMode = 'scan') or (aMode = 'heap') or (aMode = 'auto');
end;

function TTestLongSoak24h.ParseModes(const aValue: string): TArray<string>;
var
  lItems: TStringList;
  lMode: string;
  lIndex: Integer;
  lResultIndex: Integer;
  lExists: Boolean;
begin
  SetLength(Result, 0);
  lItems := TStringList.Create;
  try
    lItems.StrictDelimiter := True;
    lItems.Delimiter := ',';
    lItems.DelimitedText := aValue;
    for lIndex := 0 to lItems.Count - 1 do
    begin
      lMode := LowerCase(Trim(lItems[lIndex]));
      if lMode = '' then
        Continue;
      Assert.IsTrue(IsSupportedMode(lMode), 'Unsupported MAXCRON_LONG_SOAK_MODES entry: ' + lMode);
      if Length(Result) = 0 then
      begin
        SetLength(Result, 1);
        Result[0] := lMode;
      end else begin
        lExists := False;
        for lResultIndex := 0 to Length(Result) - 1 do
          if Result[lResultIndex] = lMode then
          begin
            lExists := True;
            Break;
          end;
        if not lExists then
        begin
          SetLength(Result, Length(Result) + 1);
          Result[High(Result)] := lMode;
        end;
      end;
    end;
  finally
    lItems.Free;
  end;
end;

procedure TTestLongSoak24h.EngineModes_LogicalSoak_NoMisses;
const
  cFarFuturePlan = '0 0 1 1 * 2099 0 1';
  cMinTicksPerMode = 300;
  cSparseEventCount = 96;
  cBurstEventCount = 144;
var
  lHoursText: string;
  lModesText: string;
  lHours: Double;
  lModes: TArray<string>;
  lMode: string;
  lPreviousEngineValue: string;
  lPreviousEnterEventsValue: string;
  lPreviousExitEventsValue: string;
  lPreviousEnterDueDensityValue: string;
  lPreviousExitDueDensityValue: string;
  lPreviousEnterDirtyValue: string;
  lPreviousExitDirtyValue: string;
  lPreviousEnterHoldValue: string;
  lPreviousExitHoldValue: string;
  lPreviousTrialTicksValue: string;
  lPreviousCooldownValue: string;
  lPreviousPromoteRatioValue: string;
  lPreviousDemoteRatioValue: string;
  lHadEngineValue: Boolean;
  lHadEnterEventsValue: Boolean;
  lHadExitEventsValue: Boolean;
  lHadEnterDueDensityValue: Boolean;
  lHadExitDueDensityValue: Boolean;
  lHadEnterDirtyValue: Boolean;
  lHadExitDirtyValue: Boolean;
  lHadEnterHoldValue: Boolean;
  lHadExitHoldValue: Boolean;
  lHadTrialTicksValue: Boolean;
  lHadCooldownValue: Boolean;
  lHadPromoteRatioValue: Boolean;
  lHadDemoteRatioValue: Boolean;
  lTotalTicks: Integer;
  lTicksPerMode: Integer;
  lTickAt: TDateTime;
  lCallbackCount: Integer;
  lObservedCount: Integer;
  lModeIndex: Integer;
  lTickIndex: Integer;
  lBurstStartTick: Integer;
  lBurstEndTick: Integer;
  lEventIndex: Integer;
  lHeartbeatEvent: IMaxCronEvent;
  lChurnEvent: IMaxCronEvent;
  lEvent: IMaxCronEvent;
  lCron: TmaxCron;
  lDiag: TMaxCronAutoDiagnostics;
begin
  lHoursText := Trim(GetEnvironmentVariable('MAXCRON_LONG_SOAK_HOURS'));
  if lHoursText = '' then
    Exit;

  if not TryStrToFloat(lHoursText, lHours, TFormatSettings.Invariant) then
    Assert.Fail('MAXCRON_LONG_SOAK_HOURS must be numeric');
  Assert.IsTrue(lHours > 0, 'MAXCRON_LONG_SOAK_HOURS must be > 0');

  lModesText := Trim(GetEnvironmentVariable('MAXCRON_LONG_SOAK_MODES'));
  if lModesText = '' then
    lModesText := 'scan,heap,auto';
  lModes := ParseModes(lModesText);
  Assert.IsTrue(Length(lModes) > 0, 'MAXCRON_LONG_SOAK_MODES did not resolve to any mode');

  lTotalTicks := Ceil(lHours * 3600.0);
  if lTotalTicks < cMinTicksPerMode then
    lTotalTicks := cMinTicksPerMode;
  lTicksPerMode := Ceil(lTotalTicks / Length(lModes));
  lBurstStartTick := lTicksPerMode div 3;
  lBurstEndTick := (lTicksPerMode * 2) div 3;

  for lModeIndex := 0 to Length(lModes) - 1 do
  begin
    lMode := lModes[lModeIndex];
    SetEnvVar('MAXCRON_ENGINE', lMode, lPreviousEngineValue, lHadEngineValue);
    try
      if lMode = 'auto' then
      begin
        SetEnvVar('MAXCRON_AUTO_ENTER_EVENTS', '128', lPreviousEnterEventsValue, lHadEnterEventsValue);
        SetEnvVar('MAXCRON_AUTO_EXIT_EVENTS', '96', lPreviousExitEventsValue, lHadExitEventsValue);
        SetEnvVar('MAXCRON_AUTO_ENTER_DUE_DENSITY', '0.20', lPreviousEnterDueDensityValue, lHadEnterDueDensityValue);
        SetEnvVar('MAXCRON_AUTO_EXIT_DUE_DENSITY', '0.55', lPreviousExitDueDensityValue, lHadExitDueDensityValue);
        SetEnvVar('MAXCRON_AUTO_ENTER_DIRTY', '0.10', lPreviousEnterDirtyValue, lHadEnterDirtyValue);
        SetEnvVar('MAXCRON_AUTO_EXIT_DIRTY', '0.25', lPreviousExitDirtyValue, lHadExitDirtyValue);
        SetEnvVar('MAXCRON_AUTO_ENTER_HOLD', '2', lPreviousEnterHoldValue, lHadEnterHoldValue);
        SetEnvVar('MAXCRON_AUTO_EXIT_HOLD', '2', lPreviousExitHoldValue, lHadExitHoldValue);
        SetEnvVar('MAXCRON_AUTO_TRIAL_TICKS', '8', lPreviousTrialTicksValue, lHadTrialTicksValue);
        SetEnvVar('MAXCRON_AUTO_COOLDOWN', '4', lPreviousCooldownValue, lHadCooldownValue);
        SetEnvVar('MAXCRON_AUTO_PROMOTE_RATIO', '1.20', lPreviousPromoteRatioValue, lHadPromoteRatioValue);
        SetEnvVar('MAXCRON_AUTO_DEMOTE_RATIO', '1.45', lPreviousDemoteRatioValue, lHadDemoteRatioValue);
      end;

      lCallbackCount := 0;
      lCron := TmaxCron.Create(ctPortable);
      try
        lHeartbeatEvent := lCron.Add('LongSoak24hHeartbeat_' + lMode);
        lHeartbeatEvent.EventPlan := '* * * * * * * 0';
        lHeartbeatEvent.InvokeMode := imMainThread;
        lHeartbeatEvent.OnScheduleProc :=
          procedure(aSender: IMaxCronEvent)
          begin
            TInterlocked.Increment(lCallbackCount);
          end;
        lHeartbeatEvent.Run;
        lTickAt := lHeartbeatEvent.NextSchedule;

        lChurnEvent := lCron.Add('LongSoak24hChurn_' + lMode);
        lChurnEvent.EventPlan := cFarFuturePlan;
        lChurnEvent.Run;

        for lEventIndex := 0 to cSparseEventCount - 1 do
        begin
          lEvent := lCron.Add('LongSoak24hSparse_' + lMode + '_' + IntToStr(lEventIndex));
          lEvent.EventPlan := cFarFuturePlan;
          lEvent.Run;
        end;

        for lEventIndex := 0 to cBurstEventCount - 1 do
        begin
          lEvent := lCron.Add('LongSoak24hBurst_' + lMode + '_' + IntToStr(lEventIndex));
          lEvent.EventPlan := '* * * * * * * 0';
          lEvent.ValidFrom := IncSecond(lTickAt, lBurstStartTick);
          lEvent.ValidTo := IncSecond(lTickAt, lBurstEndTick);
          lEvent.Run;
        end;

        for lTickIndex := 0 to lTicksPerMode - 1 do
        begin
          if (lTickIndex >= lBurstStartTick) and (lTickIndex < lBurstEndTick) and ((lTickIndex and $0F) = 0) then
          begin
            lChurnEvent.Stop;
            lChurnEvent.Run;
          end;
          lCron.TickAt(IncSecond(lTickAt, lTickIndex));
          CheckSynchronize(0);
        end;

        lObservedCount := TInterlocked.CompareExchange(lCallbackCount, 0, 0);
        Assert.IsTrue(lObservedCount >= (lTicksPerMode - 1),
          Format('Soak should not lose due callbacks for mode %s (expected >= %d observed=%d)',
            [lMode, lTicksPerMode - 1, lObservedCount]));
        Assert.IsTrue(lObservedCount <= lTicksPerMode,
          Format('Soak should not duplicate due callbacks for mode %s (expected <= %d observed=%d)',
            [lMode, lTicksPerMode, lObservedCount]));

        if lMode = 'auto' then
        begin
          Assert.IsTrue(lCron.TryGetAutoDiagnostics(lDiag), 'Diagnostics should be available in auto mode');
          Assert.IsTrue(lDiag.SwitchCount >= 1,
            Format('Auto soak should produce at least one switch (observed=%d)', [Int64(lDiag.SwitchCount)]));
          Assert.IsTrue(lDiag.SwitchCount <= 128,
            Format('Auto soak switch-rate envelope exceeded (observed=%d)', [Int64(lDiag.SwitchCount)]));
        end else begin
          Assert.IsFalse(lCron.TryGetAutoDiagnostics(lDiag), 'Diagnostics should be unavailable outside auto mode');
        end;
      finally
        lCron.Free;
      end;
    finally
      if lMode = 'auto' then
      begin
        RestoreEnvVar('MAXCRON_AUTO_DEMOTE_RATIO', lPreviousDemoteRatioValue, lHadDemoteRatioValue);
        RestoreEnvVar('MAXCRON_AUTO_PROMOTE_RATIO', lPreviousPromoteRatioValue, lHadPromoteRatioValue);
        RestoreEnvVar('MAXCRON_AUTO_COOLDOWN', lPreviousCooldownValue, lHadCooldownValue);
        RestoreEnvVar('MAXCRON_AUTO_TRIAL_TICKS', lPreviousTrialTicksValue, lHadTrialTicksValue);
        RestoreEnvVar('MAXCRON_AUTO_EXIT_HOLD', lPreviousExitHoldValue, lHadExitHoldValue);
        RestoreEnvVar('MAXCRON_AUTO_ENTER_HOLD', lPreviousEnterHoldValue, lHadEnterHoldValue);
        RestoreEnvVar('MAXCRON_AUTO_EXIT_DIRTY', lPreviousExitDirtyValue, lHadExitDirtyValue);
        RestoreEnvVar('MAXCRON_AUTO_ENTER_DIRTY', lPreviousEnterDirtyValue, lHadEnterDirtyValue);
        RestoreEnvVar('MAXCRON_AUTO_EXIT_DUE_DENSITY', lPreviousExitDueDensityValue, lHadExitDueDensityValue);
        RestoreEnvVar('MAXCRON_AUTO_ENTER_DUE_DENSITY', lPreviousEnterDueDensityValue, lHadEnterDueDensityValue);
        RestoreEnvVar('MAXCRON_AUTO_EXIT_EVENTS', lPreviousExitEventsValue, lHadExitEventsValue);
        RestoreEnvVar('MAXCRON_AUTO_ENTER_EVENTS', lPreviousEnterEventsValue, lHadEnterEventsValue);
      end;
      RestoreEnvVar('MAXCRON_ENGINE', lPreviousEngineValue, lHadEngineValue);
    end;
  end;
end;

end.

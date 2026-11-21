[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Pester container data is read in isolated test blocks.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Pester BeforeAll state is consumed by tests.')]
param(
    [Parameter(Mandatory = $true)][string]$ScratchRoot,
    [Parameter(Mandatory = $true)][string]$Compiler,
    [string]$Repository = (Split-Path -Parent $PSScriptRoot),
    [switch]$SourceContractOnly
)

BeforeAll {
    . (Join-Path $Repository 'tests/RosterManifest.ps1')
    if (-not $SourceContractOnly) {
        [void][IO.Directory]::CreateDirectory($ScratchRoot)
        $source = Join-Path $ScratchRoot 'RosterHang.dpr'
        $fixture = @'
program RosterHang;
{$APPTYPE CONSOLE}
uses System.Classes, System.IOUtils, System.SysUtils, Winapi.Windows;
var
  lStartup: TStartupInfo;
  lChild: TProcessInformation;
  lCommand: string;
  i, lCount: Integer;

procedure Spawn(const aMode, aFile: string);
begin
  FillChar(lStartup, SizeOf(lStartup), 0);
  lStartup.cb := SizeOf(lStartup);
  lStartup.dwFlags := STARTF_USESTDHANDLES;
  lStartup.hStdInput := GetStdHandle(STD_INPUT_HANDLE);
  lStartup.hStdOutput := GetStdHandle(STD_OUTPUT_HANDLE);
  lStartup.hStdError := GetStdHandle(STD_ERROR_HANDLE);
  lCommand := '"' + ParamStr(0) + '" ' + aMode + ' "' + aFile + '"';
  if not CreateProcess(nil, PChar(lCommand), nil, nil, True, CREATE_NO_WINDOW, nil, nil, lStartup, lChild) then
    RaiseLastOSError;
  TFile.AppendAllText(aFile, IntToStr(lChild.dwProcessId) + sLineBreak, TEncoding.UTF8);
  CloseHandle(lChild.hThread);
end;

begin
  if ParamStr(1) = 'child' then
  begin
    Sleep(120000);
    Exit;
  end;
  if ParamStr(1) = 'intermediate' then
  begin
    Spawn('child', ParamStr(2));
    CloseHandle(lChild.hProcess);
    Exit;
  end;
  if (ParamStr(1) = 'orphan') or (ParamStr(1) = 'orphan-live') or (ParamStr(1) = 'fanout') then
  begin
    TFile.WriteAllText(ParamStr(2), IntToStr(GetCurrentProcessId) + sLineBreak, TEncoding.UTF8);
    lCount := 1;
    if ParamStr(1) = 'fanout' then
      lCount := 96;
    for i := 1 to lCount do
    begin
      if ParamStr(1) = 'fanout' then
        Spawn('child', ParamStr(2))
      else
        Spawn('intermediate', ParamStr(2));
      if ParamStr(1) <> 'fanout' then
        if WaitForSingleObject(lChild.hProcess, 5000) <> WAIT_OBJECT_0 then
          Halt(17);
      CloseHandle(lChild.hProcess);
    end;
    if ParamStr(1) = 'orphan' then
      Exit;
    Sleep(120000);
    Exit;
  end;
  if (ParamStr(1)='spawn') or (ParamStr(1)='pipe') then
  begin
    FillChar(lStartup, SizeOf(lStartup), 0);
    lStartup.cb:=SizeOf(lStartup);
    lStartup.dwFlags:=STARTF_USESTDHANDLES;
    lStartup.hStdInput:=GetStdHandle(STD_INPUT_HANDLE);
    lStartup.hStdOutput:=GetStdHandle(STD_OUTPUT_HANDLE);
    lStartup.hStdError:=GetStdHandle(STD_ERROR_HANDLE);
    lCommand:='"'+ParamStr(0)+'" child';
    if not CreateProcess(nil, PChar(lCommand), nil, nil, True, CREATE_NO_WINDOW, nil, nil, lStartup, lChild) then RaiseLastOSError;
    TFile.WriteAllText(ParamStr(2), IntToStr(lChild.dwProcessId), TEncoding.UTF8);
    CloseHandle(lChild.hThread);
    CloseHandle(lChild.hProcess);
    if ParamStr(1)='pipe' then Exit;
  end;
  Sleep(10000);
end.
'@
        [IO.File]::WriteAllText($source, ($fixture -split '\r?\n' -join [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
        $buildOutput = @(& $Compiler '-B' '-Q' '-NSSystem;Winapi' ('-N0'+$ScratchRoot) ('-E'+$ScratchRoot) $source 2>&1)
        if ($LASTEXITCODE -ne 0) { throw ('Timeout fixture must compile successfully: ' + ($buildOutput -join [Environment]::NewLine)) }
        $hangExe = Join-Path $ScratchRoot 'RosterHang.exe'
    }
}

Describe 'Production wrappers bind finite phase deadlines' {
    It '<Relative> explicitly binds a timeout policy' -Tag DeadlineWiring -ForEach @(
        @{ Relative='tests/Run-DefaultRoster.ps1' },
        @{ Relative='tests/Run-LongRoster.ps1' },
        @{ Relative='tests/Run-DelphiRosters.ps1' },
        @{ Relative='tests/fpc/Run-FpcGate.ps1' }
    ) {
        $tokens=$null; $parseErrors=$null
        $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $Repository $Relative), [ref]$tokens, [ref]$parseErrors)
        $parseErrors.Count | Should -Be 0
        $calls=@($ast.FindAll({param($node) $node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -in 'Invoke-RosterChild','Wait-RosterProcess','Invoke-GateProcess'}, $true))
        $calls.Count | Should -BeGreaterThan 0
        foreach($call in $calls) {
            $parameters=@($call.CommandElements | Where-Object { $_ -is [Management.Automation.Language.CommandParameterAst] } | ForEach-Object { $_.ParameterName })
            if($call.GetCommandName() -eq 'Invoke-GateProcess') {
                $parameters | Should -Contain Phase
                $parameters | Should -Contain Name
            } else { $parameters | Should -Contain TimeoutMs }
        }
        if($Relative -like '*Run-FpcGate*') { $ast.Extent.Text | Should -Match 'Wait-RosterProcess.+Get-RosterPhaseTimeout' }
    }

    It 'contains no unbounded production Process.WaitForExit call' -Tag DeadlineWiring {
        foreach($relative in 'tests/RosterManifest.ps1','tests/fpc/Run-FpcGate.ps1','tests/Run-DelphiRosters.ps1') {
            $tokens=$null; $parseErrors=$null
            $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $Repository $relative), [ref]$tokens, [ref]$parseErrors)
            $calls=@($ast.FindAll({param($node) $node -is [Management.Automation.Language.InvokeMemberExpressionAst] -and $node.Member.Value -eq 'WaitForExit'}, $true))
            foreach($call in $calls) { $call.Arguments.Count | Should -Be 1 -Because $call.Extent.Text }
        }
    }

    It '<Phase>/<Name> uses the documented deadline' -ForEach @(
        @{ Phase='tool'; Name='version'; Expected=120000 },
        @{ Phase='build'; Name='compiler'; Expected=1800000 },
        @{ Phase='generator'; Name='registry'; Expected=600000 },
        @{ Phase='parity'; Name='fixture-parity'; Expected=600000 },
        @{ Phase='runner'; Name='DelphiUnit'; Expected=7200000 },
        @{ Phase='runner'; Name='smoke'; Expected=600000 },
        @{ Phase='runner'; Name='DelphiLong'; Expected=172800000 },
        @{ Phase='roster-check'; Name='long-preflight'; Expected=600000 },
        @{ Phase='roster-check'; Name='DelphiDefaultGate'; Expected=28800000 }
    ) {
        Get-RosterPhaseTimeout -Phase $Phase -Name $Name | Should -Be $Expected
    }

    It 'selects 48 hours for FPC long tests and 10 minutes for their smoke' {
        $saved=$env:MAXCRON_LONG_TESTS
        try {
            $env:MAXCRON_LONG_TESTS='1'
            Get-RosterPhaseTimeout runner tests | Should -Be 172800000
            Get-RosterPhaseTimeout runner smoke-heaptrc | Should -Be 600000
        } finally { $env:MAXCRON_LONG_TESTS=$saved }
    }
}

Describe 'Native deadline expiry is infrastructure status 124' {
    It '<Mode> expires and reaps its owned child tree' -ForEach @(@{ Mode='hang' }, @{ Mode='spawn' }, @{ Mode='pipe' }) {
        $pidFile=Join-Path $ScratchRoot ($Mode+'-child.txt')
        $status=0
        try {
            $null=Invoke-RosterChild -Executable $hangExe -ArgumentList @($Mode,$pidFile) -WorkingDirectory $ScratchRoot -Phase runner -Name timeout-fixture -TimeoutMs 250
        } catch { $status=Complete-RosterFailure $_.Exception }
        $status | Should -Be 124
        if($Mode -ne 'hang') {
            Test-Path -LiteralPath $pidFile | Should -BeTrue
            $childId=[int](Get-Content -Encoding UTF8 -LiteralPath $pidFile)
            Get-Process -Id $childId -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        }
    }
}

Describe 'Timeout ownership survives exited intermediate parents and fan-out' {
    It '<Mode> returns 124, closes both streams and leaves no owned process' -Tag JobLifetime -ForEach @(
        @{ Mode='orphan'; ExpectedCount=3; Limit=1500 },
        @{ Mode='orphan-live'; ExpectedCount=3; Limit=1500 },
        @{ Mode='fanout'; ExpectedCount=97; Limit=2500 }
    ) {
        $pidFile=Join-Path $ScratchRoot ($Mode+'-pids.txt')
        $status=0
        $timeout=$null
        try {
            try {
                $null=Invoke-RosterChild -Executable $hangExe -ArgumentList @($Mode,$pidFile) -WorkingDirectory $ScratchRoot -Phase runner -Name job-lifetime -TimeoutMs $Limit
            } catch {
                $status=Complete-RosterFailure $_.Exception
                $timeout=$_.Exception
                while($timeout -and $timeout -isnot [TimeoutException]) { $timeout=$timeout.InnerException }
            }
            $status | Should -Be 124
            $owned=@(Get-Content -Encoding UTF8 -LiteralPath $pidFile | ForEach-Object { [int]$_ })
            $owned.Count | Should -Be $ExpectedCount -Because 'the full regression workload must have started'
            foreach($childId in $owned) {
                Get-Process -Id $childId -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
            }
            $timeout.Data['StdoutComplete'] | Should -BeTrue
            $timeout.Data['StderrComplete'] | Should -BeTrue
            $timeout.Data['ActiveProcesses'] | Should -Be 0
        } finally {
            # Test-only recovery of precisely the fixture PIDs if the RED version leaks.
            if(Test-Path -LiteralPath $pidFile) {
                foreach($childId in @(Get-Content -Encoding UTF8 -LiteralPath $pidFile)) {
                    Stop-Process -Id ([int]$childId) -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }
}


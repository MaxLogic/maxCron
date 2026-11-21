[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Pester container parameters are read in isolated test blocks.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'BeforeAll variables are consumed by Pester test blocks and AfterAll.')]
param(
    [Parameter(Mandatory = $true)][string]$ScratchRoot,
    [string]$Repository = (Split-Path -Parent $PSScriptRoot)
)

BeforeAll {
    $savedEnvironment = @{}
    foreach ($name in 'DAK_EXE', 'MAXCRON_FPC', 'MAXCRON_FPC_OUT', 'MAXCRON_FPC_ARGS', 'WSLENV') {
        $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name)
    }
    $env:DAK_EXE = Join-Path $ScratchRoot 'missing-build-tool.exe'
    $env:MAXCRON_FPC = Join-Path $ScratchRoot 'missing-compiler.exe'
    $env:MAXCRON_FPC_OUT = Join-Path $ScratchRoot 'must-not-be-created'
    $env:MAXCRON_FPC_ARGS = ''
    $env:WSLENV = ($env:WSLENV, 'DAK_EXE', 'MAXCRON_FPC', 'MAXCRON_FPC_OUT') -join ':'

    function Invoke-LongSelection {
        param([string]$Entry, [string]$Mode, [string]$Selector)
        $arguments = @()
        if ($Mode -eq 'FPC') { $arguments += 'fpc' }
        $arguments += $Selector
        $previousPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            if ($Entry -eq 'BAT') {
                $scriptPath = Join-Path $Repository 'build-and-run-tests-long.bat'
                $output = @(& $env:ComSpec /d /c $scriptPath @arguments 2>&1)
            } else {
                $scriptPath = Join-Path $Repository 'build-and-run-tests-long.sh'
                $posixPath = (& wsl.exe --exec wslpath -a -u $scriptPath).Trim()
                if ($LASTEXITCODE -ne 0) { throw 'Could not translate the long entry point path' }
                $output = @(& wsl.exe --exec bash $posixPath @arguments 2>&1)
            }
            $nativeExit = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $previousPreference
        }
        [pscustomobject]@{ ExitCode = $nativeExit; Text = ($output -join "`n") }
    }
}

Describe 'Long qualification rejects test selection before invoking tools' {
    It '<Entry> <Mode> <Selector>' -ForEach @(
        @{ Entry = 'BAT'; Mode = 'Delphi'; Selector = '--run:NoSuchF1Fixture.NoSuchF1Test' },
        @{ Entry = 'SH'; Mode = 'Delphi'; Selector = '--run:NoSuchF1Fixture.NoSuchF1Test' },
        @{ Entry = 'BAT'; Mode = 'FPC'; Selector = '--run:NoSuchF1Fixture.NoSuchF1Test' },
        @{ Entry = 'SH'; Mode = 'FPC'; Selector = '--run:NoSuchF1Fixture.NoSuchF1Test' },
        @{ Entry = 'BAT'; Mode = 'Delphi'; Selector = '--run:TestLocalOverlap.TTestLocalOverlap.ConstructorDoesNotReadStoppedClock' },
        @{ Entry = 'SH'; Mode = 'Delphi'; Selector = '--run:TestLocalOverlap.TTestLocalOverlap.ConstructorDoesNotReadStoppedClock' },
        @{ Entry = 'BAT'; Mode = 'FPC'; Selector = '--run:TestLocalOverlap.TTestLocalOverlap.ConstructorDoesNotReadStoppedClock' },
        @{ Entry = 'SH'; Mode = 'FPC'; Selector = '--run:TestLocalOverlap.TTestLocalOverlap.ConstructorDoesNotReadStoppedClock' }
    ) {
        $result = Invoke-LongSelection -Entry $Entry -Mode $Mode -Selector $Selector
        $result.ExitCode | Should -Be 5
        $result.Text | Should -Match '(?m)^ROSTER_REJECTED reason=count detail='
        Test-Path -LiteralPath $env:MAXCRON_FPC_OUT | Should -BeFalse
    }
}

AfterAll {
    foreach ($name in $savedEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name])
    }
}

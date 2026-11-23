[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Pester container data is consumed inside test blocks.')]
param(
    [Parameter(Mandatory = $true)][string]$ScratchRoot,
    [Parameter(Mandatory = $true)][string]$Compiler,
    [Parameter(Mandatory = $true)][string]$DUnitXSource,
    [string]$Repository = (Split-Path -Parent $PSScriptRoot)
)

Describe 'Roster matrix cannot use encoding corruption or build failure as proof' {
    It 'preserves BOM identities under a non-UTF8 locale and requires exact rejection phases' {
        & python -X utf8=0 (Join-Path $Repository 'tests/roster_regression_contract_tests.py') --scratch (Join-Path $ScratchRoot 'unit')
        $LASTEXITCODE | Should -Be 0
    }

    It 'fails the actual matrix after <Phase> exits 37' -ForEach @(@{ Phase='compiler' }, @{ Phase='generator' }, @{ Phase='parity' }) {
        [string[]]$injection = if ($Phase -eq 'compiler') { @('--inject-compiler-failure') } else { @('--inject-phase', $Phase) }
        $lines = @(& python -X utf8=0 (Join-Path $Repository 'tests/roster_contract_regression.py') --repository $Repository --scratch (Join-Path $ScratchRoot ('injected-'+$Phase)) --compiler $Compiler --dunitx $DUnitXSource --routes fpc-long-bat @injection 2>&1)
        $nativeExit = $LASTEXITCODE
        [IO.Directory]::CreateDirectory($ScratchRoot) | Out-Null
        [IO.File]::WriteAllLines((Join-Path $ScratchRoot ('injected-'+$Phase+'.log')), [string[]]$lines, [Text.UTF8Encoding]::new($true))
        $text = $lines -join "`n"
        $nativeExit | Should -Be 4
        $text | Should -Match '(?m)^ROSTER_PHASE phase=roster name=DelphiLong native_exit=0'
        $text | Should -Match '(?m)^ROSTER_PHASE phase=(build|generator|parity) name=\S+ native_exit=37'
        $text | Should -Match '(?m)^MATRIX_INFRASTRUCTURE_FAILURE Subprocess failure:'
    }
    It 'requires MAXCRON_FPC before allocating gate output' -Tag FpcConfiguration {
        $savedCompiler = $env:MAXCRON_FPC
        $savedOutput = $env:MAXCRON_FPC_OUT
        try {
            $env:MAXCRON_FPC = $null
            # The checkout is forbidden as an output root even if the gate
            # mistakenly proceeds past the missing compiler.
            $env:MAXCRON_FPC_OUT = $Repository
            $gate = Join-Path $Repository 'tests/fpc/Run-FpcGate.ps1'
            $messages = @(& powershell.exe -NoProfile -NonInteractive -File $gate 2>&1)
            $LASTEXITCODE | Should -Be 2
            ($messages -join "`n") | Should -Match 'Set MAXCRON_FPC to the path to fpc\.exe'
            ($messages -join "`n") | Should -Not -Match 'FPC OUTPUT|ROSTER_PHASE'
        } finally {
            $env:MAXCRON_FPC = $savedCompiler
            $env:MAXCRON_FPC_OUT = $savedOutput
        }
    }

    It 'rejects all 24 actual subprocess phase failures' {
        & python -X utf8=0 (Join-Path $Repository 'tests/roster_phase_faults.py') --scratch (Join-Path $ScratchRoot 'phase-faults') --compiler $Compiler
        $LASTEXITCODE | Should -Be 0
        $rows = @(Get-Content -Encoding UTF8 -Raw -LiteralPath (Join-Path $ScratchRoot 'phase-faults/results.json') | ConvertFrom-Json)
        $rows.Count | Should -Be 24
        @($rows | Where-Object { $_.rejected -or $_.matrix_exit -eq 0 }).Count | Should -Be 0
    }

}

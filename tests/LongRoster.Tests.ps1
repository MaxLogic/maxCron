[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Pester parameters are consumed in isolated test blocks.')]
param(
    [Parameter(Mandatory = $true)][string]$ScratchRoot,
    [Parameter(Mandatory = $true)][string]$Compiler,
    [Parameter(Mandatory = $true)][string]$DUnitXSource,
    [string]$Repository = (Split-Path -Parent $PSScriptRoot)
)

BeforeAll {
    $matrixRoot = Join-Path $ScratchRoot 'native-matrix'
    & python (Join-Path $Repository 'tests/long_roster_regression.py') --repository $Repository --scratch $matrixRoot --compiler $Compiler --dunitx $DUnitXSource
    # The assertions below retain the individual failing routes on a RED run.
    $matrix = @(Get-Content -LiteralPath (Join-Path $matrixRoot 'results.json') -Raw | ConvertFrom-Json)
    $matrix.Count | Should -Be 24
}

Describe 'Long qualification rejects incomplete identities through every native entry point' {
    It '<Route> <Variant>' -ForEach @(
        foreach ($route in 'delphi-bat', 'delphi-sh', 'fpc-bat', 'fpc-sh') {
            foreach ($variant in 'unknown-selector', 'partial-selector', 'renamed-fixture', 'removed-test', 'removed-import', 'extra-test') {
                @{ Route = $route; Variant = $variant }
            }
        }
    ) {
        $row = @($matrix | Where-Object { $_.route -eq $Route -and $_.variant -eq $Variant })
        $row.Count | Should -Be 1
        $row[0].exit | Should -Not -Be 0 -Because $row[0].log
        $row[0].reason | Should -BeTrue -Because 'a compiler or tool failure is not a manifest rejection'
        if ($Variant -notlike '*selector') {
            $row[0].identity_exit | Should -Not -Be 0 -Because $row[0].identity_log
            $row[0].identity_reason | Should -BeTrue -Because 'refreshing source stamps must not hide renamed or reduced identities'
        }
    }
}

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Pester parameters are consumed in isolated test blocks.')]
param(
    [Parameter(Mandatory = $true)][string]$ScratchRoot,
    [Parameter(Mandatory = $true)][string]$Compiler,
    [Parameter(Mandatory = $true)][string]$DUnitXSource,
    [string]$Repository = (Split-Path -Parent $PSScriptRoot)
)

BeforeAll {
    $native = Join-Path $ScratchRoot 'native-matrix'
    & python -X utf8=0 (Join-Path $Repository 'tests/roster_contract_regression.py') --repository $Repository --scratch $native --compiler $Compiler --dunitx $DUnitXSource
    $matrixExit = $LASTEXITCODE
    if ($matrixExit -notin 0, 1) { throw ('Matrix setup/build failure, exit ' + $matrixExit) }
    $matrix = @(Get-Content -Encoding UTF8 -LiteralPath (Join-Path $native 'results.json') -Raw | ConvertFrom-Json)
    $matrix.Count | Should -Be 180
}

Describe 'Every native test entry seals shared and FPC-only membership' {
    It '<Route> <Family> <Variant>' -ForEach @(
        foreach ($route in 'unit', 'stress', 'vcl', 'default-bat', 'default-sh', 'stress-bat', 'stress-sh', 'long-bat', 'long-sh', 'fpc-bat', 'fpc-sh', 'fpc-long-bat', 'fpc-long-sh', 'smoke', 'smoke-heap') {
            foreach ($family in 'shared', 'fpc-only') {
                foreach ($variant in 'unknown-selector', 'partial-selector', 'renamed-fixture', 'removed-test', 'removed-import', 'extra-test') {
                    @{ Route = $route; Family = $family; Variant = $variant }
                }
            }
        }
    ) {
        $rows = @($matrix | Where-Object { $_.route -eq $Route -and $_.family -eq $Family -and $_.variant -eq $Variant })
        $rows.Count | Should -Be 1
        $rows[0].exit | Should -Be $rows[0].expected_exit -Because $rows[0].log
        $rows[0].reason | Should -BeTrue -Because 'a build/tool failure is not roster proof'
        if ($Variant -notlike '*selector') {
            $rows[0].identity_exit | Should -Be $rows[0].identity_expected_exit -Because $rows[0].identity_log
            $rows[0].identity_reason | Should -BeTrue -Because 'source-stamp refresh must not change expected identities'
        }
    }
}

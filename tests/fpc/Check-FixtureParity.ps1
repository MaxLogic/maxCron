param(
    [Parameter(Mandatory = $true)][string]$Registry,
    [string]$DelphiNames,
    [string]$Repository
)

$ErrorActionPreference = 'Stop'
try {
    # Inherited PSModulePath can place PowerShell 7's Utility ahead of Windows
    # PowerShell's. Bind hash and comparison cmdlets to this host's own module.
    Import-Module (Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Utility\Microsoft.PowerShell.Utility.psd1') -ErrorAction Stop
    if (-not $DelphiNames) { $DelphiNames = Join-Path $PSScriptRoot 'DelphiSharedTests.txt' }
    if (-not $Repository) { $Repository = Join-Path $PSScriptRoot '..\..' }
    $generated = @([regex]::Matches([IO.File]::ReadAllText($Registry), "RegisterTest\('([^']+)',") |
        ForEach-Object { $_.Groups[1].Value })
    $manifest = @(Get-Content -LiteralPath $DelphiNames)
    $sources = @($manifest | Where-Object { $_.StartsWith('# SHA256 ') })
    if ($sources.Count -eq 0) { throw 'Missing Delphi source identities' }
    foreach ($source in $sources) {
        if ($source -cnotmatch '^# SHA256 (tests/unit/[A-Za-z0-9]+\.pas) ([a-f0-9]{64})$') {
            throw 'Invalid Delphi source identity'
        }
        $sourcePath = Join-Path $Repository $Matches[1]
        if ((Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash -ine $Matches[2]) {
            throw ('Delphi test-name snapshot is stale: ' + $Matches[1] + '; export it again with Delphi DUnitX')
        }
    }
    $expected = @($manifest | Where-Object { $_ -and -not $_.StartsWith('#') })
    $sourceUnits = @($sources | ForEach-Object { ($_ -split ' ')[2].Replace('tests/unit/', '').Replace('.pas', '') })
    foreach ($name in $expected) {
        if ($sourceUnits -cnotcontains ($name -split '\.')[0]) { throw ('Missing source identity for ' + $name) }
    }
    # These are the only intentional differences in the declared shared roster.
    $delphiOnly = 'TestLocalZoneOs.TTestLocalZoneOs.MatchesRtlLocal'
    if ($expected.Count -eq 0 -or $generated.Count -eq 0 -or $expected -notcontains $delphiOnly) {
        throw 'Empty or incomplete Delphi/FPC name list'
    }
    $shared = @($generated | Where-Object { -not $_.StartsWith('TestFpcShims.') })
    $expected = @($expected | Where-Object { $_ -cne $delphiOnly })
    if (@($shared | Sort-Object -Unique).Count -ne $shared.Count -or
        @($expected | Sort-Object -Unique).Count -ne $expected.Count) { throw 'Duplicate test name' }
    $difference = @(Compare-Object -ReferenceObject $expected -DifferenceObject $shared -CaseSensitive)
    if ($difference.Count -gt 0) {
        throw ('Delphi/FPC test names differ: ' + (($difference | ForEach-Object { $_.SideIndicator + ' ' + $_.InputObject }) -join '; '))
    }
    Write-Output ('Fixture name parity: {0} shared tests in {1} fixtures; 1 Delphi-only LOCAL test' -f
        $shared.Count, @($shared | ForEach-Object { ($_ -split '\.')[0..1] -join '.' } | Sort-Object -Unique).Count)
    exit 0
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 3
}

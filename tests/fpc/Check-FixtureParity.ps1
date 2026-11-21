param(
    [Parameter(Mandatory = $true)][string]$Registry,
    [string]$DelphiNames,
    [string]$Repository,
    [string]$FpcOnlyNames
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\RosterManifest.ps1')
try {
    # Inherited PSModulePath can place PowerShell 7's Utility ahead of Windows
    # PowerShell's. Bind hash and comparison cmdlets to this host's own module.
    Import-Module (Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Utility\Microsoft.PowerShell.Utility.psd1') -ErrorAction Stop
    if (-not $DelphiNames) { $DelphiNames = Join-Path $PSScriptRoot 'DelphiSharedTests.txt' }
    if (-not $Repository) { $Repository = Join-Path $PSScriptRoot '..\..' }
    if (-not $FpcOnlyNames) { $FpcOnlyNames = Join-Path $PSScriptRoot '..\rosters\FpcOnly.txt' }
    $generated = @([regex]::Matches([IO.File]::ReadAllText($Registry), "RegisterTest\('([^']+)',") |
        ForEach-Object { $_.Groups[1].Value })
    $onlyManifest = @(Get-Content -Encoding UTF8 -LiteralPath $FpcOnlyNames)
    $onlyNames = @($onlyManifest | Where-Object { $_ -and -not $_.StartsWith('#') })
    if ($onlyNames.Count -eq 0) { throw (New-RosterViolation empty 'Empty independent FPC-only list' fixture-parity) }
    $manifest = @(Get-Content -Encoding UTF8 -LiteralPath $DelphiNames) + $onlyManifest
    $sources = @($manifest | Where-Object { $_.StartsWith('# SHA256 ') })
    if ($sources.Count -eq 0) { throw (New-RosterViolation stale 'Missing Delphi source identities' fixture-parity) }
    foreach ($source in $sources) {
        if ($source -cnotmatch '^# SHA256 ([A-Za-z0-9_./+\-]+) ([a-f0-9]{64})$') {
            throw (New-RosterViolation stale 'Invalid Delphi source identity' fixture-parity)
        }
        $sourcePath = Join-Path $Repository $Matches[1]
        if ((Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash -ine $Matches[2]) {
            throw (New-RosterViolation stale ('Delphi test-name snapshot is stale: ' + $Matches[1] + '; export it again with Delphi DUnitX') fixture-parity)
        }
    }
    $expected = @($manifest | Where-Object { $_ -and -not $_.StartsWith('#') })
    $sourceUnits = @($sources | ForEach-Object { [IO.Path]::GetFileNameWithoutExtension(($_ -split ' ')[2]) })
    foreach ($name in $expected) {
        if ($sourceUnits -cnotcontains ($name -split '\.')[0]) { throw (New-RosterViolation stale ('Missing source identity for ' + $name) fixture-parity) }
    }
    # These are the only intentional differences in the declared shared roster.
    $delphiOnly = 'TestLocalZoneOs.TTestLocalZoneOs.MatchesRtlLocal'
    if ($expected.Count -eq 0 -or $generated.Count -eq 0 -or $expected -notcontains $delphiOnly) {
        throw (New-RosterViolation empty 'Empty or incomplete Delphi/FPC name list' fixture-parity)
    }
    $shared = $generated
    $expected = @($expected | Where-Object { $_ -cne $delphiOnly })
    if (@($shared | Sort-Object -Unique).Count -ne $shared.Count -or
        @($expected | Sort-Object -Unique).Count -ne $expected.Count) { throw (New-RosterViolation duplicate 'Duplicate test name' fixture-parity) }
    Assert-RosterIdentity -Expected $expected -Actual $shared -Name fixture-parity
    Write-Output ('Fixture name parity: {0} FPC identities, including {1} explicitly listed FPC-only tests; 1 Delphi-only LOCAL test' -f
        $shared.Count, $onlyNames.Count)
    exit 0
} catch {
    exit (Complete-RosterFailure $_.Exception)
}

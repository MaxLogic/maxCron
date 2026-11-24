param(
    [Parameter(Mandatory = $true)][string]$Compiler,
    [Parameter(Mandatory = $true)][string]$DUnitXSource,
    [Parameter(Mandatory = $true)][string]$OutputRoot,
    [string]$FpcCompiler = $env:MAXCRON_FPC
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'RosterManifest.ps1')
$fpc = Get-FpcToolchain -Compiler $FpcCompiler
Import-Module (Join-Path $PSHOME 'Modules/Microsoft.PowerShell.Utility/Microsoft.PowerShell.Utility.psd1') -ErrorAction Stop
$repository = Split-Path -Parent $PSScriptRoot
$OutputRoot = & (Join-Path $PSScriptRoot 'fpc/Check-OutputPath.ps1') -Repository $repository -OutputPath $OutputRoot -CreateRun -InProcess
if (-not [IO.Directory]::Exists($OutputRoot)) { throw 'Could not allocate roster discovery output' }
Push-Location -LiteralPath $OutputRoot
try {
$destination = Join-Path $PSScriptRoot 'rosters'
[void][IO.Directory]::CreateDirectory($destination)
$initial = @{}
Get-ChildItem -LiteralPath $PSScriptRoot -Recurse -File | Where-Object {
    $_.Extension -in '.pas', '.dpr', '.ps1', '.inc' -or
    ($_.Extension -eq '.txt' -and $_.DirectoryName -eq (Join-Path $PSScriptRoot 'linux')) -or
    $_.FullName.StartsWith((Join-Path $PSScriptRoot 'data') + '\', [StringComparison]::OrdinalIgnoreCase)
} | ForEach-Object {
    $initial[$_.FullName] = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
}
Get-ChildItem -LiteralPath $repository -File -Filter '*.inc' | ForEach-Object {
    $initial[$_.FullName] = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
}
Get-ChildItem -LiteralPath $repository -File | Where-Object { $_.Name -like 'build-and-run-tests*.bat' -or $_.Name -like 'build-and-run-tests*.sh' } | ForEach-Object {
    $initial[$_.FullName] = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Write-TestRoster {
    param([string]$File, [string[]]$Sources, [string[]]$Names,
        [string]$Header = '# Native test roster; regenerate explicitly with tests/Export-TestRosters.ps1.')
    if ($Names.Count -le 0 -or @($Names | Sort-Object -Unique).Count -ne $Names.Count) { throw ('Invalid discovery names: ' + $File) }
    $stamps = @($Sources | Sort-Object -Unique | ForEach-Object {
        $path = [IO.Path]::GetFullPath((Join-Path $repository $_))
        if (-not $initial.ContainsKey($path)) { throw ('Unbound test source: ' + $_) }
        if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ine $initial[$path]) { throw ('Test source changed during discovery: ' + $_) }
        '# SHA256 ' + $_ + ' ' + $initial[$path]
    })
    [IO.File]::WriteAllLines($File, @($Header) + $stamps + @($Names | Sort-Object), [Text.UTF8Encoding]::new($true))
    Write-Output ('ROSTER {0} {1}' -f ([IO.Path]::GetFileName($File)), $Names.Count)
}

$helperSources = @('tests/TestRoster.pas', 'tests/DelphiRoster.pas') | Where-Object { Test-Path -LiteralPath (Join-Path $repository $_) }
$unitSources = @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'unit') -Recurse -File | Where-Object { $_.Extension -in '.pas', '.inc' } | ForEach-Object {
    'tests/unit/' + $_.FullName.Substring((Join-Path $PSScriptRoot 'unit').Length + 1).Replace('\', '/')
})
$assets = @(Get-ChildItem -LiteralPath $repository -File -Filter '*.inc' | ForEach-Object { $_.Name }) +
@(Get-ChildItem -LiteralPath $PSScriptRoot -Recurse -File -Filter '*.inc' | ForEach-Object {
    $_.FullName.Substring($repository.Length + 1).Replace('\', '/')
}) + @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'data') -Recurse -File | Where-Object {
    $_.Extension -notin '.pyc', '.pyo' -and $_.FullName.Replace('\', '/') -notmatch '/__pycache__/'
} | ForEach-Object {
    $_.FullName.Substring($repository.Length + 1).Replace('\', '/')
})
$unitSources += $assets
foreach ($entry in @(
    @{ Name = 'DelphiUnit'; Runner = 'maxCronTests'; Long = $false },
    @{ Name = 'DelphiLong'; Runner = 'maxCronTests'; Long = $true },
    @{ Name = 'DelphiStress'; Runner = 'maxCronStressTests'; Long = $false },
    @{ Name = 'DelphiVcl'; Runner = 'maxCronVclTests'; Long = $false }
)) {
    $runnerPath = Join-Path $PSScriptRoot ($entry.Runner + '.dpr')
    $runner = [IO.File]::ReadAllText($runnerPath)
    $useRtti = 'True'
    if ($entry.Name -eq 'DelphiStress') {
        $mode = [regex]::Matches($runner, '(?mi)^[ \t]*Runner\.UseRTTI[ \t]*:=[ \t]*(True|False);[ \t]*\r?$')
        if ($mode.Count -ne 1 -or $mode[0].Groups[1].Value -ine 'False') {
            throw ('DelphiStress must disable RTTI fixture discovery and register its fixtures explicitly: ' + $runnerPath)
        }
        $useRtti = 'False'
    }
    $uses = [regex]::Match($runner, '(?s)\buses\s+.*?;').Value
    $uses = [regex]::Replace($uses, " in '([^']+)'", {
        param($match)
        " in '" + [IO.Path]::GetFullPath((Join-Path $PSScriptRoot $match.Groups[1].Value)) + "'"
    })
    # Discovery uses actual native DUnitX RTTI and registrations, never a parser
    # that guesses method/case identities.
    $registrations = @([regex]::Matches($runner, '(?m)^\s*TDUnitX\.RegisterTestFixture\([^;]+;') | ForEach-Object { $_.Value })
    if ($registrations.Count -eq 0) { throw ('Empty runner: ' + $runnerPath) }
    if ($uses -notmatch 'DUnitX.Extensibility') { $uses = $uses.Replace('uses', 'uses DUnitX.Extensibility,') }
    $source = "program RosterDiscovery;`r`n" + $uses + @'

procedure PrintFixture(const aFixture: ITestFixture);
var lTest: ITest; lChild: ITestFixture;
begin
  for lTest in aFixture.Tests do WriteLn(lTest.FullName);
  for lChild in aFixture.Children do PrintFixture(lChild);
end;
var lRunner: ITestRunner; lFixture: ITestFixture;
begin
  TDUnitX.CheckCommandLine;
'@ + ($registrations -join "`r`n") + @'

  lRunner := TDUnitX.CreateRunner;
  lRunner.UseRTTI := True;
  for lFixture in (lRunner.BuildFixtures as ITestFixtureList) do PrintFixture(lFixture);
end.
'@
    $source = $source.Replace('lRunner.UseRTTI := True;', "lRunner.UseRTTI := $useRtti;")
    $out = Join-Path $OutputRoot $entry.Name
    [void][IO.Directory]::CreateDirectory($out)
    $path = Join-Path $out 'RosterDiscovery.dpr'
    [IO.File]::WriteAllText($path, ($source -replace '\r?\n', "`r`n"))
    $studio = Split-Path -Parent (Split-Path -Parent $Compiler)
    $paths = @($repository, $PSScriptRoot, (Join-Path $PSScriptRoot 'unit'), (Join-Path $repository 'lib/MaxLogicFoundation'), $DUnitXSource, (Join-Path $studio 'lib/win64/release')) -join ';'
    $defines = 'RELEASE;MAXCRON_TESTS;CONSOLE;NeverUninstall;NeverSleepOnMMThreadContention;UseSwitchToThread;UseReleaseStack'
    if ($entry.Long) { $defines += ';MAXCRON_LONG_TESTS' }
    $includes = @($repository, (Join-Path $repository 'lib/MaxLogicFoundation')) -join ';'
    & $Compiler '-B' '-Q' "-D$defines" '-NSSystem;Xml;Data;Winapi;System.Win' "-U$paths" "-I$includes" "-N0$out" "-E$out" $path > (Join-Path $out 'build.log') 2>&1
    if ($LASTEXITCODE -ne 0) { throw ('Native discovery build failed: ' + $out) }
    $names = @(& (Join-Path $out 'RosterDiscovery.exe') | Where-Object { $_ -match '^Test\w+\.\w+\.' })
    if ($LASTEXITCODE -ne 0) { throw ('Native discovery failed: ' + $out) }
    # Stamp all test units conservatively, including indirect test helpers.
    $sources = @('tests/' + $entry.Runner + '.dpr') + $helperSources + $unitSources
    Write-TestRoster -File (Join-Path $destination ($entry.Name + '.txt')) -Sources $sources -Names $names
}
# Keep the established long path as an exact compatibility copy, not a second
# expectation generated by a gate.
Copy-Item -LiteralPath (Join-Path $destination 'DelphiLong.txt') -Destination (Join-Path $PSScriptRoot 'LongTests.txt')

& (Join-Path $PSScriptRoot 'fpc/Export-DelphiTestNames.ps1') -Compiler $Compiler -DUnitXSource $DUnitXSource -OutputRoot (Join-Path $OutputRoot 'shared')
if ($LASTEXITCODE -ne 0) { throw 'Native shared discovery failed' }
$shared = @(Get-Content -Encoding UTF8 -LiteralPath (Join-Path $PSScriptRoot 'fpc/DelphiSharedTests.txt') | Where-Object { $_ -and -not $_.StartsWith('#') -and $_ -cne 'TestLocalZoneOs.TTestLocalZoneOs.MatchesRtlLocal' })
$fpcArgs = @('-n', ('@' + $fpc.Config), ('-FD' + $fpc.Bin), ('-Fu' + $fpc.UnitSearchPath),
    ('-Fu' + $repository), ('-Fu' + $PSScriptRoot), ('-Fi' + $repository), '-O2', '-gl')
$gen = Join-Path $OutputRoot 'fpc-gen'
[void][IO.Directory]::CreateDirectory($gen)
& $fpc.Compiler @fpcArgs ('-FU' + $gen) ('-FE' + $gen) '-Sew' '-vm4104,4105' (Join-Path $PSScriptRoot 'fpc/maxCronFpcRegistryGen.dpr') > (Join-Path $gen 'build.log') 2>&1
if ($LASTEXITCODE -ne 0) { throw ('FPC registry build failed: ' + $gen) }
$registry = Join-Path $gen 'registry.inc'
& (Join-Path $gen 'maxCronFpcRegistryGen.exe') $repository $registry
if ($LASTEXITCODE -ne 0) { throw 'Native FPC registry discovery failed' }
$registered = @([regex]::Matches([IO.File]::ReadAllText($registry), "RegisterTest\('([^']+)',") | ForEach-Object { $_.Groups[1].Value })
$only = @($registered | Where-Object { $shared -cnotcontains $_ })
if (@($shared | Where-Object { $registered -cnotcontains $_ }).Count) { throw 'FPC discovery lost a shared test' }
$fpcSources = @(@('tests/TestRoster.pas') | Where-Object { Test-Path -LiteralPath (Join-Path $repository $_) })
$fpcSources += @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'fpc') -File | Where-Object { $_.Extension -in '.pas', '.dpr', '.inc' } | ForEach-Object { 'tests/fpc/' + $_.Name })
$fpcSources += @(Get-Content -Encoding UTF8 -LiteralPath (Join-Path $PSScriptRoot 'fpc/DelphiSharedTests.txt') | Where-Object { $_.StartsWith('# SHA256 ') } | ForEach-Object { ($_ -split ' ')[2] })
$fpcSources += @('tests/unit/TestZoneFakes.pas')
$fpcSources += $unitSources
$onlySources = @($only | ForEach-Object { ($_ -split '\.')[0] } | Sort-Object -Unique | ForEach-Object {
    $unit = $_
    $paths = @(('tests/fpc/' + $unit + '.pas'), ('tests/unit/' + $unit + '.pas'))
    $path = @($paths | Where-Object { Test-Path -LiteralPath (Join-Path $repository $_) })
    if ($path.Count -eq 0) { throw ('Missing FPC-only source: ' + $unit) }
    $path[0]
})
Write-TestRoster -File (Join-Path $destination 'FpcOnly.txt') -Sources ($onlySources + $unitSources) -Names $only
Write-TestRoster -File (Join-Path $destination 'FpcDefault.txt') -Sources $fpcSources -Names $registered
Write-TestRoster -File (Join-Path $destination 'FpcLong.txt') -Sources $fpcSources -Names $registered

foreach ($heap in $false, $true) {
    $name = if ($heap) { 'FpcSmokeHeap' } else { 'FpcSmoke' }
    $out = Join-Path $OutputRoot $name
    [void][IO.Directory]::CreateDirectory($out)
    $source = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'fpc/maxCronFpcSmoke.dpr'))
    # This separately compiled export copy runs the real smoke checks, but
    # prints their identities without consulting an existing expectation.
    $source = [regex]::Replace($source, '(?m)^\s*(?:BeginRoster|EndRoster)\([^;]+;', '')
    if ($source -notmatch 'RecordRosterTest\(') { $source = [regex]::new('(?m)^  Inc\(gFound\);').Replace($source, "  WriteLn('ROSTER_TEST smoke.', aName);`r`n  Inc(gFound);", 1) }
    $path = Join-Path $out 'SmokeDiscovery.dpr'
    $source = $source.Replace("in '..\TestRoster.pas'", "in '" + (Join-Path $PSScriptRoot 'TestRoster.pas') + "'")
    [IO.File]::WriteAllText($path, ($source -replace '\r?\n', "`r`n"))
    $defines = @()
    if ($heap) { $defines += '-dMAXCRON_FPC_SMOKE_NOPOOL' }
    & $fpc.Compiler @fpcArgs @defines ('-FU' + $out) ('-FE' + $out) '-Sew' $path > (Join-Path $out 'build.log') 2>&1
    if ($LASTEXITCODE -ne 0) { throw ('Smoke discovery build failed: ' + $out) }
    $lines = @(& (Join-Path $out 'SmokeDiscovery.exe'))
    if ($LASTEXITCODE -ne 0) { throw ('Smoke discovery failed: ' + $out) }
    $names = @($lines | Where-Object { $_.StartsWith('ROSTER_TEST ') } | ForEach-Object { $_.Substring(12) })
    $sources = @(@('tests/fpc/maxCronFpcSmoke.dpr', 'tests/TestRoster.pas') | Where-Object { Test-Path -LiteralPath (Join-Path $repository $_) }) + $unitSources
    Write-TestRoster -File (Join-Path $destination ($name + '.txt')) -Sources $sources -Names $names
}
$cohorts = @(
    @{ Name = 'DelphiDefaultGate'; Entries = @('DelphiStress', 'DelphiUnit', 'DelphiVcl') },
    @{ Name = 'FpcDefaultGate'; Entries = @('FpcDefault', 'FpcSmoke', 'FpcSmokeHeap') },
    @{ Name = 'FpcLongGate'; Entries = @('FpcLong', 'FpcSmoke', 'FpcSmokeHeap') }
)
foreach ($cohort in $cohorts) {
    $sources = @()
    $names = @()
    foreach ($entry in $cohort.Entries) {
        $lines = @(Get-Content -Encoding UTF8 -LiteralPath (Join-Path $destination ($entry + '.txt')))
        $sources += @($lines | Where-Object { $_.StartsWith('# SHA256 ') } | ForEach-Object { ($_ -split ' ')[2] })
        $names += @($lines | Where-Object { $_ -and -not $_.StartsWith('#') } | ForEach-Object { $entry + '::' + $_ })
    }
    $sources += @($initial.Keys | Where-Object { $_.EndsWith('.ps1') -or $_.EndsWith('.bat') -or $_.EndsWith('.sh') } | ForEach-Object { $_.Substring($repository.Length + 1).Replace('\', '/') })
    Write-TestRoster -File (Join-Path $destination ($cohort.Name + '.txt')) -Sources $sources -Names $names
}

# Derive Linux identities from the independently discovered Windows rosters.
$linuxLists = @('tests/linux/LinuxExcluded.txt', 'tests/linux/LinuxOnly.txt')
$excluded = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$linuxOnly = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($line in (Get-Content -Encoding UTF8 -LiteralPath (Join-Path $repository $linuxLists[0]))) {
    if (-not $line -or $line.StartsWith('#')) { continue }
    $identity, $reason = $line -split '\s+\|\s+', 2
    if (-not $identity -or -not $reason -or -not $excluded.Add($identity)) {
        throw ('Invalid Linux exclusion: ' + $line)
    }
}
foreach ($identity in (Get-Content -Encoding UTF8 -LiteralPath (Join-Path $repository $linuxLists[1]))) {
    if (-not $identity -or $identity.StartsWith('#')) { continue }
    if ($excluded.Contains($identity) -or -not $linuxOnly.Add($identity)) {
        throw ('Invalid Linux-only identity: ' + $identity)
    }
}
$linuxEntries = @(
    @{ Name = 'DelphiLinuxUnit'; Base = 'DelphiUnit'; AddLinuxOnly = $true },
    @{ Name = 'DelphiLinuxLong'; Base = 'DelphiLong'; AddLinuxOnly = $true },
    @{ Name = 'DelphiLinuxStress'; Base = 'DelphiStress'; AddLinuxOnly = $false },
    @{ Name = 'FpcLinux'; Base = 'FpcDefault'; AddLinuxOnly = $true },
    @{ Name = 'FpcLinuxLong'; Base = 'FpcLong'; AddLinuxOnly = $true }
)
$usedExclusions = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($entry in $linuxEntries) {
    $lines = @(Get-Content -Encoding UTF8 -LiteralPath (Join-Path $destination ($entry.Base + '.txt')))
    $entry.Sources = $linuxLists + @($lines | Where-Object { $_.StartsWith('# SHA256 ') } | ForEach-Object { ($_ -split ' ')[2] })
    $entry.Names = @(foreach ($identity in $lines) {
        if (-not $identity -or $identity.StartsWith('#')) { continue }
        if ($linuxOnly.Contains($identity)) { throw ('Linux-only identity appears in ' + $entry.Base + ': ' + $identity) }
        if ($excluded.Contains($identity)) {
            [void]$usedExclusions.Add($identity)
        } else {
            $identity
        }
    })
    if ($entry.AddLinuxOnly) { $entry.Names += @($linuxOnly | ForEach-Object { $_ }) }
}
foreach ($identity in $excluded) {
    if (-not $usedExclusions.Contains($identity)) { throw ('Stale Linux exclusion: ' + $identity) }
}
foreach ($entry in $linuxEntries) {
    Write-TestRoster -File (Join-Path $destination ($entry.Name + '.txt')) -Sources $entry.Sources -Names $entry.Names `
        -Header ('# Linux test roster derived by tests/Export-TestRosters.ps1 from ' + $entry.Base + '.')
}
} finally {
    Pop-Location
}

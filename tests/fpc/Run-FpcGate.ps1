[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Console entry point: emit native logs without mixing them into function result objects.')]
param()

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\RosterManifest.ps1')
$repository = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$step = 1
$failureExit = 2
$childNumber = 0
$executedGateIdentities = @()

function ConvertTo-NativeArgument {
    param([AllowEmptyString()][string]$Value)
    # Serialize argv for CreateProcess, never a shell. Double backslashes before
    # quotes, including the closing quote, as required by Windows argv parsing.
    $builder = [Text.StringBuilder]::new()
    [void]$builder.Append('"')
    $slashes = 0
    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq '\') { $slashes++; continue }
        if ($character -eq '"') {
            [void]$builder.Append('\', (2 * $slashes + 1))
        } else {
            [void]$builder.Append('\', $slashes)
        }
        [void]$builder.Append($character)
        $slashes = 0
    }
    [void]$builder.Append('\', (2 * $slashes))
    [void]$builder.Append('"')
    return $builder.ToString()
}

function Invoke-GateProcess {
    param([string]$Executable, [string[]]$ArgumentList, [string]$LogPath, [string]$Phase, [string]$Name)
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $Executable
    $start.Arguments = (($ArgumentList | ForEach-Object { ConvertTo-NativeArgument $_ }) -join ' ')
    $start.WorkingDirectory = $script:runOutput
    $start.UseShellExecute = $false
    $start.EnvironmentVariables.Clear()
    foreach ($key in $script:childEnvironment.Keys) { $start.EnvironmentVariables[$key] = $script:childEnvironment[$key] }
    $script:childNumber++
    $heapName = 'child-' + $script:childNumber + '.heaptrc.log'
    $heapPath = Join-Path $script:runOutput $heapName
    # The RTL splits HEAPTRC options at spaces. A gate-owned relative basename
    # remains inside WorkingDirectory even when the absolute run path has spaces.
    $start.EnvironmentVariables['HEAPTRC'] = 'log=' + $heapName
    $auditEnvironment = @{}
    foreach ($key in $start.EnvironmentVariables.Keys) { $auditEnvironment[$key] = $start.EnvironmentVariables[$key] }
    $audit = [ordered]@{ executable = $Executable; arguments = $ArgumentList; working_directory = $start.WorkingDirectory; environment = $auditEnvironment }
    [IO.File]::AppendAllText((Join-Path $script:runOutput 'child-processes.jsonl'), (ConvertTo-Json $audit -Compress) + [Environment]::NewLine)
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $process = Start-RosterProcess -StartInfo $start
    try {
        $stdout = $process.Stdout
        $stderr = $process.Stderr
        Wait-RosterProcess -Process $process -Stdout $stdout -Stderr $stderr -TimeoutMs (Get-RosterPhaseTimeout -Phase $Phase -Name $Name) -Phase $Phase -Name $Name
        $text = $stdout.Result + $stderr.Result
        if ($LogPath) { [IO.File]::WriteAllText($LogPath, $text) }
        [Console]::Write($text)
        return [pscustomobject]@{ ExitCode = $process.ExitCode; Text = $text; HeapPath = $heapPath }
    } finally {
        $process.Dispose()
    }
}

function Invoke-GateBuild {
    param([string]$Name, [string]$Source, [string[]]$Options)
    $destination = Join-Path $script:runOutput $Name
    [void][IO.Directory]::CreateDirectory($destination)
    $arguments = $script:common + @('-vw', ('-FU' + $destination), ('-FE' + $destination)) + $Options + @((Join-Path $repository $Source))
    $result = Invoke-GateProcess $script:compiler $arguments (Join-Path $destination 'build.log') -Phase build -Name $Name
    Write-RosterPhase build $Name $result.ExitCode
    if ($result.ExitCode -ne 0) { throw "Compiler failed for $Name (native exit $($result.ExitCode))" }
}

function Invoke-GateTest {
    param([string]$Name, [string]$Program, [string[]]$TestArguments, [switch]$Heap)
    $result = Invoke-GateProcess (Join-Path $script:runOutput "$Name\$Program.exe") $TestArguments (Join-Path $script:runOutput "$Name\last-run.log") -Phase runner -Name $Name
    Write-RosterPhase runner $Name $result.ExitCode
    if ($result.ExitCode -ne 0) {
        if ($result.ExitCode -eq 124) { exit 124 }
        if (Test-RosterRejection $result.ExitCode $result.Text) { exit 5 }
        throw "Runner failed for $Name (native exit $($result.ExitCode))"
    }
    $counts = @{}
    foreach ($kind in 'Found', 'Passed', 'Ignored', 'Failed', 'Errored') {
        $summaries = [regex]::Matches($result.Text, ('(?m)^Tests ' + $kind + '\s*:\s*(\d+)\s*$'))
        if ($summaries.Count -ne 1) { throw "Missing or ambiguous Tests $kind summary for $Name" }
        $counts[$kind] = [int]$summaries[0].Groups[1].Value
    }
    if ($counts.Found -le 0 -or $counts.Passed -ne $counts.Found -or
        $counts.Ignored -ne 0 -or $counts.Failed -ne 0 -or $counts.Errored -ne 0) { throw "Invalid test counts for $Name" }
    # Each native runner checks source stamps and executed identities itself.
    # Independently check its transcript against the checked-in expectation too.
    $entry = switch ($Name) {
        'tests' { if ($env:MAXCRON_LONG_TESTS -eq '1') { 'FpcLong' } else { 'FpcDefault' } }
        'smoke' { 'FpcSmoke' }
        'smoke-heaptrc' { 'FpcSmokeHeap' }
        default { throw ('Unknown test entry: ' + $Name) }
    }
    $executed = @([regex]::Matches($result.Text, '(?m)^ROSTER_TEST ([^\r\n]+)\r?$') | ForEach-Object { $_.Groups[1].Value })
    $expected = (Read-RosterManifest -Repository $repository -Entry $entry).Names
    if ($executed.Count -ne $counts.Found) { throw (New-RosterViolation count 'Executed count differs from Found' $entry) }
    Assert-RosterIdentity -Expected $expected -Actual $executed -Name $entry
    $script:executedGateIdentities += @($executed | ForEach-Object { $entry + '::' + $_ })
    if ($Heap) {
        if (-not [IO.File]::Exists($result.HeapPath)) { throw "Missing heaptrc log for $Name" }
        $heapText = [IO.File]::ReadAllText($result.HeapPath)
        [Console]::Write($heapText)
        if ($heapText -notmatch '(?m)^0 unfreed memory blocks(?:\s*:\s*0)?\s*$') { throw "Missing zero-unfreed heaptrc summary for $Name" }
    }
    return $counts.Found
}

try {
    Import-Module (Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Utility\Microsoft.PowerShell.Utility.psd1') -ErrorAction Stop
    $outputRoot = Get-RosterOutputRoot -Override $env:MAXCRON_FPC_OUT -Suite 'fpc'
    # FPC's path handling and the supported IPC are ASCII only. Validate the
    # literal setting before normalization, allocation or any child process.
    if ($outputRoot -cmatch '[^A-Za-z0-9 \\:. _+\-]' -or $outputRoot -match '(?<!^[A-Za-z]):') {
        throw 'FPC output rejected: supported characters are ASCII letters, digits, space and \ : . _ - + only'
    }
    foreach ($component in ($outputRoot -split '[\\/]')) {
        if ($component.EndsWith(' ') -or ($component.EndsWith('.') -and $component -notin '.', '..')) {
            throw 'FPC output rejected: path components must not end in a space or dot'
        }
    }
    $outputRoot = [IO.Path]::GetFullPath($outputRoot)
    $testArguments = @()
    if ($env:MAXCRON_FPC_ARGS) {
        # Keep zero/one-element arrays intact in Windows PowerShell 5.1.
        $decoded = (ConvertFrom-Json -InputObject ('{"arguments":' + $env:MAXCRON_FPC_ARGS + '}')).arguments
        if ($decoded -isnot [array] -or @($decoded | Where-Object { $_ -isnot [string] }).Count -gt 0) { throw 'MAXCRON_FPC_ARGS must be a JSON array of strings' }
        $testArguments = [string[]]$decoded
    }
    if ($testArguments.Count -ne 0) {
        throw (New-RosterViolation count 'FPC qualification requires the complete roster; test selection arguments are not accepted.' arguments)
    }
    $fpc = Get-FpcToolchain
    $compiler = $fpc.Compiler
    $bin = $fpc.Bin
    if ($env:MAXCRON_LONG_TESTS -eq '1') {
        $failureExit = 3
        $preflight = Invoke-RosterChild -Executable (Join-Path $PSHOME 'powershell.exe') -ArgumentList @('-NoProfile','-NonInteractive','-File',(Join-Path $PSScriptRoot '..\Test-LongManifest.ps1')) -WorkingDirectory $repository -Phase roster-check -Name long-preflight -TimeoutMs (Get-RosterPhaseTimeout -Phase roster-check -Name long-preflight)
        if ($preflight.ExitCode -ne 0) {
            if ($preflight.ExitCode -eq 124) { exit 124 }
            if (Test-RosterRejection $preflight.ExitCode $preflight.Text) { exit 5 }
            throw ('Long preflight failed, native exit ' + $preflight.ExitCode)
        }
    }
    # Allocation uses in-memory Win32 declarations and starts no child/compiler.
    $runOutput = & (Join-Path $PSScriptRoot 'Check-OutputPath.ps1') -Repository $repository -OutputPath $outputRoot -CreateRun -InProcess
    if (-not [IO.Directory]::Exists($runOutput)) { throw 'Missing fresh output directory' }
    [Console]::WriteLine('FPC OUTPUT ' + $runOutput)
    $temporary = Join-Path $runOutput 'temp'
    [void][IO.Directory]::CreateDirectory($temporary)
    $windows = [Environment]::GetFolderPath([Environment+SpecialFolder]::Windows)
    $childEnvironment = @{
        SystemRoot = $windows; windir = $windows; TEMP = $temporary; TMP = $temporary
        PATH = ($bin, (Join-Path $windows 'System32'), $windows, $PSHOME) -join ';'
        # This absolute directory has already passed the Win32 identity check.
        # Test data is read here; process cwd and all outputs remain run-local.
        MAXCRON_TEST_ROOT = $repository
    }
    $version = Invoke-GateProcess $compiler @('-iV') -Phase tool -Name version
    $cpu = Invoke-GateProcess $compiler @('-iTP') -Phase tool -Name cpu
    $target = Invoke-GateProcess $compiler @('-iTO') -Phase tool -Name target
    Write-RosterPhase tool version $version.ExitCode
    Write-RosterPhase tool cpu $cpu.ExitCode
    Write-RosterPhase tool target $target.ExitCode
    [Console]::WriteLine("FPC $($version.Text.Trim()) $($cpu.Text.Trim())-$($target.Text.Trim()) at $compiler")
    if ($version.ExitCode -ne 0 -or $cpu.ExitCode -ne 0 -or $target.ExitCode -ne 0 -or
        $version.Text.Trim() -ne '3.3.1' -or $cpu.Text.Trim() -ne 'x86_64' -or $target.Text.Trim() -ne 'win64' -or
        -not [IO.File]::Exists($fpc.Config)) { throw 'Requires FPC 3.3.1 x86_64-win64 and fpc.cfg' }
    $powershell = Join-Path $PSHOME 'powershell.exe'
    $optimization = @('-O2', '-gl')
    if ($env:MAXCRON_DEBUG_SAFETY -eq '1') { $optimization = @('-O-', '-gl', '-Cr', '-Co', '-Ct', '-Ci', '-Sa') }
    $common = @('-n', ('@' + $fpc.Config), ('-FD' + (Join-Path $bin '.')),
        ('-Fu' + $fpc.UnitSearchPath), ('-Fu' + $repository),
        ('-Fu' + (Join-Path $repository 'tests')), ('-Fi' + $repository)) + $optimization
    # Same exhaustive test loops as Delphi's --define MAXCRON_LONG_TESTS.
    if ($env:MAXCRON_LONG_TESTS -eq '1') { $common += '-dMAXCRON_LONG_TESTS' }
    $step = 3; $failureExit = 3
    Invoke-GateBuild 'check-public' 'tests\fpc\maxCronFpcCompileCheck.dpr' @('-Sew')
    Invoke-GateBuild 'check-tests' 'tests\fpc\maxCronFpcCompileCheck.dpr' @('-Sew', '-dMAXCRON_TESTS')
    $step = 4
    Invoke-GateBuild 'gen' 'tests\fpc\maxCronFpcRegistryGen.dpr' @('-Sew', '-vm4104,4105')
    $registry = Join-Path $runOutput 'gen\maxCronFpcRegistry.inc'
    $generated = Invoke-GateProcess (Join-Path $runOutput 'gen\maxCronFpcRegistryGen.exe') @($repository, $registry) -Phase generator -Name registry
    Write-RosterPhase generator registry $generated.ExitCode
    if ($generated.ExitCode -eq 124) { exit 124 }
    if ($generated.ExitCode -ne 0) { throw 'Registry generator failed' }
    $parity = Invoke-GateProcess $powershell @('-NoProfile', '-NonInteractive', '-File', (Join-Path $PSScriptRoot 'Check-FixtureParity.ps1'), '-Registry', $registry) -Phase parity -Name fixture-parity
    Write-RosterPhase parity fixture-parity $parity.ExitCode
    if ($parity.ExitCode -ne 0) {
        if ($parity.ExitCode -eq 124) { exit 124 }
        if (Test-RosterRejection $parity.ExitCode $parity.Text) { exit 5 }
        throw 'Fixture parity failed'
    }
    $gateEntry = if ($env:MAXCRON_LONG_TESTS -eq '1') { 'FpcLongGate' } else { 'FpcDefaultGate' }
    $gateExpected = (Read-RosterManifest -Repository $repository -Entry $gateEntry).Names
    $step = 5
    Invoke-GateBuild 'tests' 'tests\fpc\maxCronFpcTests.dpr' @('-Sew', '-dMAXCRON_TESTS', '-gh', '-vm4104,4105', ('-Fu' + $PSScriptRoot), ('-Fu' + (Join-Path $repository 'tests\unit')), ('-Fi' + (Join-Path $runOutput 'gen')))
    $failureExit = 1
    $testCount = Invoke-GateTest 'tests' 'maxCronFpcTests' $testArguments -Heap
    $step = 6; $failureExit = 3
    Invoke-GateBuild 'smoke' 'tests\fpc\maxCronFpcSmoke.dpr' @('-Sew')
    $failureExit = 1
    [void](Invoke-GateTest 'smoke' 'maxCronFpcSmoke' @())
    $failureExit = 3
    Invoke-GateBuild 'smoke-heaptrc' 'tests\fpc\maxCronFpcSmoke.dpr' @('-Sew', '-gh', '-dMAXCRON_FPC_SMOKE_NOPOOL')
    $failureExit = 1
    [void](Invoke-GateTest 'smoke-heaptrc' 'maxCronFpcSmoke' @() -Heap)
    Assert-RosterIdentity -Expected $gateExpected -Actual $executedGateIdentities -Name $gateEntry
    [Console]::WriteLine('ROSTER_GATE_VERIFIED ' + $gateEntry + ' ' + $executedGateIdentities.Count)
    [Console]::WriteLine("FPC GATE PASSED ($testCount tests, compiler 3.3.1 x86_64-win64 at $compiler)")
    exit 0
} catch {
    $nativeExit = Complete-RosterFailure $_.Exception -InfrastructureExit $failureExit
    if ($nativeExit -ne 5) { [Console]::Error.WriteLine("FPC GATE FAILED at step $step (exit $nativeExit)") }
    exit $nativeExit
}

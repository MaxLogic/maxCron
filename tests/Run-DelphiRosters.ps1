[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Console entry emits native logs without mixing function result objects.')]
param()

$ErrorActionPreference = 'Stop'
$testArguments = [string[]]$args
$repository = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'RosterManifest.ps1')


try {
    $expected = (Read-RosterManifest -Repository $repository -Entry 'DelphiDefaultGate').Names
    $executed = @()
    $output = $env:MAXCRON_ROSTER_OUT
    if (-not $output) {
        $output = if ([IO.Directory]::Exists('F:\dev-artifacts')) { 'F:\dev-artifacts\builds\maxCron-main\roster-gates' }
        else { Join-Path ([IO.Path]::GetTempPath()) 'maxCron-roster-gates' }
    }
    $run = & (Join-Path $PSScriptRoot 'fpc/Check-OutputPath.ps1') -Repository $repository -OutputPath $output -CreateRun -InProcess
    if (-not [IO.Directory]::Exists($run)) { throw 'Could not allocate roster gate output' }
    [Console]::WriteLine('ROSTER_GATE_OUTPUT ' + $run)
    # The independent manifest drives which runners execute. Removing a build
    # or invocation cannot silently shrink the gate's expected work.
    $entries = @($expected | ForEach-Object { ($_ -split '::')[0] } | Sort-Object -Unique)
    foreach ($entry in $entries) {
        $target = switch ($entry) {
            'DelphiUnit' { 'maxCronTests' }
            'DelphiStress' { 'maxCronStressTests' }
            'DelphiVcl' { 'maxCronVclTests' }
            default { throw ('Unknown Delphi roster entry: ' + $entry) }
        }
        $start = [Diagnostics.ProcessStartInfo]::new()
        $start.FileName = Join-Path $PSScriptRoot ($target + '.exe')
        $start.Arguments = (($testArguments | ForEach-Object { ConvertTo-RosterArgument $_ }) -join ' ')
        $start.WorkingDirectory = $repository
        $start.UseShellExecute = $false
        $start.CreateNoWindow = $true
        $start.RedirectStandardOutput = $true
        $start.RedirectStandardError = $true
        $start.EnvironmentVariables['MAXCRON_TEST_ROOT'] = $repository
        $process = Start-RosterProcess -StartInfo $start
        try {
            $stdout = $process.Stdout
            $stderr = $process.Stderr
            Wait-RosterProcess -Process $process -Stdout $stdout -Stderr $stderr -TimeoutMs (Get-RosterPhaseTimeout -Phase runner -Name $entry) -Phase runner -Name $entry
            $text = $stdout.Result + $stderr.Result
            [IO.File]::WriteAllText((Join-Path $run ($entry + '.log')), $text)
            [Console]::Write($text)
            Write-RosterPhase runner $entry $process.ExitCode
            if ($process.ExitCode -ne 0) {
                if ($process.ExitCode -eq 124) { exit 124 }
                if (Test-RosterRejection $process.ExitCode $text) { exit 5 }
                throw ('Runner failure: ' + $entry + ' native exit ' + $process.ExitCode)
            }
            $counts = @{}
            foreach ($kind in 'Found', 'Passed', 'Failed', 'Errored', 'Ignored') {
                $summaryMatches = [regex]::Matches($text, ('(?m)^Tests ' + $kind + '\s*:\s*(\d+)\s*$'))
                if ($summaryMatches.Count -ne 1) { throw ('Missing or ambiguous test summary: ' + $kind) }
                $counts[$kind] = [int]$summaryMatches[0].Groups[1].Value
            }
            if ($counts.Found -le 0 -or $counts.Found -ne $counts.Passed -or
                $counts.Failed -ne 0 -or $counts.Errored -ne 0 -or $counts.Ignored -ne 0) { throw 'Incomplete or unsuccessful test result counts' }
            $names = @([regex]::Matches($text, '(?m)^ROSTER_TEST ([^\r\n]+)\r?$') | ForEach-Object { $_.Groups[1].Value })
            if ($names.Count -ne $counts.Found) { throw 'Test roster executed count differs from Found' }
            Assert-RosterIdentity -Expected (Read-RosterManifest -Repository $repository -Entry $entry).Names -Actual $names -Name $entry
            $executed += @($names | ForEach-Object { $entry + '::' + $_ })
        } finally {
            $process.Dispose()
        }
    }
    Assert-RosterIdentity -Expected $expected -Actual $executed -Name DelphiDefaultGate
    [Console]::WriteLine('ROSTER_GATE_VERIFIED DelphiDefaultGate ' + $executed.Count)
    exit 0
} catch {
    exit (Complete-RosterFailure $_.Exception)
}

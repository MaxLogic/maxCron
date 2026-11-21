param()
$ErrorActionPreference = 'Stop'
$testArguments = [string[]]$args
. (Join-Path $PSScriptRoot 'RosterManifest.ps1')
$repository = Split-Path -Parent $PSScriptRoot
try {
    $compiler = $env:DAK_EXE
    if (-not $compiler) { $compiler = (Get-Command DelphiAIKit.exe -CommandType Application -ErrorAction SilentlyContinue).Source }
    if (-not $compiler) { $compiler = Join-Path $repository '..\..\DelphiAiKit\bin\DelphiAIKit.exe' }
    $config = if ($env:MAXCRON_DEBUG_SAFETY -eq '1') { 'debug' } else { 'release' }
    foreach ($project in 'demo\CronDemo.dproj','tests\maxCronStressTests.dproj','tests\maxCronTests.dproj','tests\maxCronVclTests.dproj') {
        $name = [IO.Path]::GetFileNameWithoutExtension($project)
        $result = Invoke-RosterChild -Executable $compiler -ArgumentList @('build','--project',$project,'--delphi','23.0','--platform','Win32','--config',$config,'--show-warnings','--show-hints','--max-findings','1000') -WorkingDirectory $repository -Phase build -Name $name -TimeoutMs (Get-RosterPhaseTimeout -Phase build -Name $name)
        if ($result.ExitCode -ne 0) { throw ('Build failed for ' + $name + ', native exit ' + $result.ExitCode) }
    }
    $hostExe = Join-Path $PSHOME 'powershell.exe'
    $result = Invoke-RosterChild -Executable $hostExe -ArgumentList (@('-NoProfile','-NonInteractive','-File',(Join-Path $PSScriptRoot 'Run-DelphiRosters.ps1')) + $testArguments) -WorkingDirectory $repository -Phase roster-check -Name DelphiDefaultGate -TimeoutMs (Get-RosterPhaseTimeout -Phase roster-check -Name DelphiDefaultGate)
    if ($result.ExitCode -ne 0) {
        if ($result.ExitCode -eq 124) { exit 124 }
        if (Test-RosterRejection $result.ExitCode $result.Text) { exit 5 }
        throw ('Roster helper failed, native exit ' + $result.ExitCode)
    }
    exit 0
} catch { exit (Complete-RosterFailure $_.Exception) }

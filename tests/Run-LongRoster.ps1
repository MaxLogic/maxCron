param()
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'RosterManifest.ps1')
$repository = Split-Path -Parent $PSScriptRoot
try {
    $null = Read-RosterManifest -Repository $repository -Entry DelphiLong
    $compiler = $env:DAK_EXE
    if (-not $compiler) { $compiler = (Get-Command DelphiAIKit.exe -CommandType Application -ErrorAction SilentlyContinue).Source }
    if (-not $compiler) { $compiler = Join-Path $repository '..\..\DelphiAiKit\bin\DelphiAIKit.exe' }
    $platform = if ($env:MAXCRON_LONG_PLATFORM) { $env:MAXCRON_LONG_PLATFORM } else { 'Win32' }
    $output = $env:MAXCRON_LONG_OUT
    if (-not $output) { $output = if ([IO.Directory]::Exists('F:\dev-artifacts')) { 'F:\dev-artifacts\builds\maxCron-main\long' } else { Join-Path ([IO.Path]::GetTempPath()) 'maxCron-long' } }
    $output = Join-Path $output $platform
    $config = if ($env:MAXCRON_DEBUG_SAFETY -eq '1') { 'Debug' } else { 'Release' }
    $build = Invoke-RosterChild -Executable $compiler -ArgumentList @('build','--project','tests\maxCronTests.dproj','--delphi','23.0','--platform',$platform,'--config',$config,'--rebuild','--define','MAXCRON_LONG_TESTS','--test-output-dir',$output,'--show-warnings','--show-hints','--max-findings','1000') -WorkingDirectory $repository -Phase build -Name maxCronTests -TimeoutMs (Get-RosterPhaseTimeout -Phase build -Name maxCronTests)
    if ($build.ExitCode -ne 0) { throw ('Compiler failure, native exit ' + $build.ExitCode) }
    $runner = Invoke-RosterChild -Executable (Join-Path $output 'maxCronTests.exe') -WorkingDirectory $repository -Phase runner -Name DelphiLong -TimeoutMs (Get-RosterPhaseTimeout -Phase runner -Name DelphiLong)
    if ($runner.ExitCode -ne 0) {
        if ($runner.ExitCode -eq 124) { exit 124 }
        if (Test-RosterRejection $runner.ExitCode $runner.Text) { exit 5 }
        throw ('Runner failure, native exit ' + $runner.ExitCode)
    }
    exit 0
} catch { exit (Complete-RosterFailure $_.Exception) }

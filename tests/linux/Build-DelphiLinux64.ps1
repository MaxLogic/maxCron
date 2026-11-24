param([string[]]$Projects)

# The diagnostic check trusts the checkout, submodule and toolchain, including the absence of planted links or junctions.
$ErrorActionPreference = 'Stop'
trap {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 3
}
$tests = Split-Path -Parent $PSScriptRoot
$repo = Split-Path -Parent $tests
. (Join-Path $tests 'RosterManifest.ps1')

$compiler = $env:MAXCRON_DCCLINUX64
if (-not $compiler) {
    $compiler = Join-Path ${env:ProgramFiles(x86)} 'Embarcadero\Studio\23.0\bin\dcclinux64.exe'
}
$sdk = $env:MAXCRON_LINUX_SDK
if (-not $sdk) {
    $sdk = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Embarcadero\Studio\SDKs\ubuntu22.04.sdk'
}
if (-not [IO.File]::Exists($compiler) -or -not [IO.Directory]::Exists($sdk)) {
    [Console]::Error.WriteLine('Delphi Linux64 requires dcclinux64.exe and the Linux SDK.')
    exit 2
}
$compiler = [IO.Path]::GetFullPath($compiler)
$sdk = [IO.Path]::GetFullPath($sdk)
$studio = Split-Path -Parent (Split-Path -Parent $compiler)
$rtl = Join-Path $studio 'lib\linux64\release'
$dunitx = Join-Path $studio 'source\DunitX'
$gccRoot = Join-Path $sdk 'usr\lib\gcc\x86_64-linux-gnu'
$gcc = Get-ChildItem -LiteralPath $gccRoot -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^\d+(\.\d+)*$' } |
    Sort-Object { if ($_.Name.Contains('.')) { [version]$_.Name } else { [version]($_.Name + '.0') } } -Descending |
    Select-Object -First 1
if (-not $gcc -or -not [IO.Directory]::Exists($rtl) -or -not [IO.Directory]::Exists($dunitx)) {
    [Console]::Error.WriteLine('Delphi Linux64 SDK GCC libraries, Linux64 RTL and DUnitX sources are required.')
    exit 2
}

$long = $env:MAXCRON_LONG_TESTS -eq '1'
if (-not $Projects) {
    $Projects = @('tests\maxCronTests.dpr')
    if (-not $long) { $Projects += 'tests\maxCronStressTests.dpr' }
}
if ($env:MAXCRON_DEBUG_SAFETY -eq '1') {
    $config = 'debug'
    $defines = 'DEBUG;MAXCRON_TESTS;CONSOLE'
    $switches = @('-$O-', '-$W+', '-$R+', '-$Q+')
} else {
    $config = 'release'
    $defines = 'RELEASE;MAXCRON_TESTS;CONSOLE'
    $switches = @('-$D0', '-$L-')
}
if ($long) {
    $config += '-long'
    $defines += ';MAXCRON_LONG_TESTS'
}

$foundation = Join-Path $repo 'lib\MaxLogicFoundation'
$foundationRoot = [IO.Path]::GetFullPath($foundation).TrimEnd('\') + '\'
$unitPath = @($repo, $tests, (Join-Path $tests 'unit'), $foundation, $dunitx, $rtl) -join ';'
$includePath = @($repo, $foundation) -join ';'
$linkPath = @($gcc.FullName, (Join-Path $sdk 'usr\lib\x86_64-linux-gnu'),
    (Join-Path $sdk 'lib\x86_64-linux-gnu'), (Join-Path $sdk 'lib64'), $rtl) -join ';'
$runRoot = Join-Path (Get-RosterOutputRoot -Suite 'linux64') ('run-' + [Guid]::NewGuid().ToString('N'))
$buildRoot = Join-Path $runRoot $config

$outputs = [Collections.Generic.List[string]]::new()
foreach ($project in $Projects) {
    $source = if ([IO.Path]::IsPathRooted($project)) { $project } else { Join-Path $repo $project }
    if (-not [IO.File]::Exists($source)) {
        [Console]::Error.WriteLine("Missing Delphi project: $source")
        exit 2
    }
    $name = [IO.Path]::GetFileNameWithoutExtension($source)
    $out = Join-Path $buildRoot ('{0}-{1}' -f $outputs.Count, $name)
    try {
        [void][IO.Directory]::CreateDirectory($out)
        $binaryPath = Join-Path $out $name
        $dccArgs = @('-B', '-Q', "-D$defines") + $switches + @('-NSSystem;Xml;Data;Posix',
            "-U$unitPath", "-I$includePath", "-N0$out", "-E$out", "--syslibroot:$sdk",
            "--libpath:$linkPath", $source)
        $build = Invoke-RosterChild -Executable $compiler -ArgumentList $dccArgs -WorkingDirectory $out -Phase build -Name $name
        $hasBinary = Test-Path -LiteralPath $binaryPath -PathType Leaf
        $warnings = $build.Text -match 'Warning: W\d+'
        $outsideHints = @($build.Text -split '\r?\n' | Where-Object {
            if ($_ -notmatch 'Hint: H\d+') { return $false }
            if ($_ -notmatch '^\s*(?<source>.+?)\(\d+(?:[:,]\d+)?\)\s+Hint: H\d+\b') { return $true }
            $hintSource = [IO.Path]::GetFullPath([IO.Path]::Combine($repo, $Matches.source))
            return -not $hintSource.StartsWith($foundationRoot, [StringComparison]::OrdinalIgnoreCase)
        })
        if ($build.ExitCode -ne 0 -or -not $hasBinary -or $warnings -or $outsideHints.Count -gt 0) {
            [Console]::Error.WriteLine("Delphi Linux64 build failed its output or diagnostics check: $name")
            exit 3
        }
        $outputs.Add($out)
    } catch [TimeoutException] {
        exit 124
    }
}
foreach ($out in $outputs) {
    "LINUX64_OUTPUT $out"
}

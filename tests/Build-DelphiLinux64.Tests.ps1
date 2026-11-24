Describe 'Delphi Linux64 build wrapper' {
    BeforeAll {
        $studio = Join-Path $TestDrive 'studio'
        $sdk = Join-Path $TestDrive 'sdk'
        $compiler = Join-Path $studio 'bin/dcclinux64.exe'
        foreach ($directory in @('bin', 'lib/linux64/release', 'source/DUnitX')) {
            [void][IO.Directory]::CreateDirectory((Join-Path $studio $directory))
        }
        [void][IO.Directory]::CreateDirectory((Join-Path $sdk 'usr/lib/gcc/x86_64-linux-gnu/12'))
        $stub = Join-Path $TestDrive 'StubCompiler.cs'
        @'
using System;
using System.IO;
using System.Linq;
using System.Threading;

static class StubCompiler
{
    static int Main(string[] args)
    {
        var output = args.Single(arg => arg.StartsWith("-E", StringComparison.Ordinal)).Substring(2);
        var project = Path.GetFileNameWithoutExtension(args.Last());
        var binary = Path.Combine(output, project);
        if (project == Environment.GetEnvironmentVariable("MAXCRON_STUB_FAIL_PROJECT")) return 1;
        var barrier = Environment.GetEnvironmentVariable("MAXCRON_STUB_BARRIER");
        if (!String.IsNullOrEmpty(barrier))
        {
            using (var ready = EventWaitHandle.OpenExisting(barrier + ".ready"))
            using (var release = EventWaitHandle.OpenExisting(barrier + ".release"))
            {
                ready.Set();
                if (!release.WaitOne(TimeSpan.FromSeconds(60)))
                {
                    Console.Error.WriteLine("Timed out waiting for the other compiler.");
                    return 99;
                }
            }
        }
        switch (Environment.GetEnvironmentVariable("MAXCRON_STUB_ARTIFACT"))
        {
            case "file":
                File.WriteAllText(binary, "stub");
                break;
            case "backdated":
                File.WriteAllText(binary, "stub");
                File.SetLastWriteTimeUtc(binary, DateTime.UtcNow.AddDays(-1));
                break;
            case "directory":
                Directory.CreateDirectory(binary);
                break;
        }
        var diagnostic = Environment.GetEnvironmentVariable("MAXCRON_STUB_DIAGNOSTIC");
        if (!String.IsNullOrEmpty(diagnostic)) Console.WriteLine(diagnostic);
        return Int32.Parse(Environment.GetEnvironmentVariable("MAXCRON_STUB_EXIT"));
    }
}
'@ | Set-Content -LiteralPath $stub -Encoding UTF8
        $csc = Join-Path $env:SystemRoot 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
        & $csc /nologo /target:exe "/out:$compiler" $stub
        if ($LASTEXITCODE -ne 0) { throw 'Could not compile the Delphi compiler stub.' }

        $repository = Split-Path -Parent $PSScriptRoot
        $wrapper = Join-Path $repository 'tests/linux/Build-DelphiLinux64.ps1'

        function Get-WrapperStartInfo {
            param([string]$BuildRoot, [string]$Artifact, [string]$Project)

            $start = [Diagnostics.ProcessStartInfo]::new()
            $start.FileName = Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
            $start.UseShellExecute = $false
            $start.CreateNoWindow = $true
            $start.RedirectStandardOutput = $true
            $start.RedirectStandardError = $true
            foreach ($argument in @('-NoProfile', '-NonInteractive', '-File', $wrapper)) {
                $start.ArgumentList.Add($argument)
            }
            if ($Project) {
                $start.ArgumentList.Add('-Projects')
                $start.ArgumentList.Add($Project)
            }
            $start.Environment['MAXCRON_DCCLINUX64'] = $compiler
            $start.Environment['MAXCRON_LINUX_SDK'] = $sdk
            $start.Environment['MAXCRON_BUILD_ROOT'] = $BuildRoot
            $start.Environment['MAXCRON_LONG_TESTS'] = '0'
            $start.Environment['MAXCRON_DEBUG_SAFETY'] = '0'
            $start.Environment['MAXCRON_STUB_ARTIFACT'] = $Artifact
            $start.Environment['MAXCRON_STUB_EXIT'] = '0'
            $start.Environment['MAXCRON_STUB_DIAGNOSTIC'] = ''
            $start.Environment['MAXCRON_STUB_FAIL_PROJECT'] = ''
            $start.Environment['MAXCRON_STUB_BARRIER'] = ''
            return $start
        }

        function Receive-WrapperResult {
            param([Diagnostics.Process]$Process)

            $stdout = $Process.StandardOutput.ReadToEndAsync()
            $stderr = $Process.StandardError.ReadToEndAsync()
            if (-not $Process.WaitForExit(90000)) {
                $Process.Kill($true)
                $Process.WaitForExit()
                throw 'Timed out waiting for the build wrapper.'
            }
            [pscustomobject]@{ ExitCode = $Process.ExitCode; Output = $stdout.Result + $stderr.Result }
        }
    }

    It '<Name> returns <Expected> with receipt=<Receipt>' -ForEach @(
        @{ Name = 'clean build'; Artifact = 'file'; Expected = 0; Receipt = $true }
        @{ Name = 'compiler exit 1'; Artifact = 'file'; CompilerExit = 1; Expected = 3; Receipt = $false }
        @{ Name = 'compiler warning'; Artifact = 'file'; Diagnostic = 'maxCron.pas(7) Warning: W1000 test'; Expected = 3; Receipt = $false }
        @{ Name = 'outside hint'; Artifact = 'file'; Diagnostic = 'tests\unit\TestEnvironment.pas(7) Hint: H1054 test'; Expected = 3; Receipt = $false }
        @{ Name = 'outside hint naming Foundation'; Artifact = 'file'; Diagnostic = 'tests\unit\TestEnvironment.pas(7) Hint: H1054 This hint names .\lib\MaxLogicFoundation\ in the message'; Expected = 3; Receipt = $false }
        @{ Name = 'Foundation hint'; Artifact = 'file'; Diagnostic = 'lib\MaxLogicFoundation\maxAsync.pas(7) Hint: H2164 test'; Expected = 0; Receipt = $true }
        @{ Name = 'Foundation lookalike path'; Artifact = 'file'; Diagnostic = 'tests\lib\MaxLogicFoundation\maxAsync.pas(7) Hint: H1054 test'; Expected = 3; Receipt = $false }
        @{ Name = 'Foundation parent traversal'; Artifact = 'file'; Diagnostic = 'lib\MaxLogicFoundation\..\other.pas(7) Hint: H1054 test'; Expected = 3; Receipt = $false }
        @{ Name = 'hint without source'; Artifact = 'file'; Diagnostic = 'Hint: H1054 test'; Expected = 3; Receipt = $false }
        @{ Name = 'missing binary'; Artifact = 'missing'; Expected = 3; Receipt = $false }
        @{ Name = 'directory at binary path'; Artifact = 'directory'; Expected = 3; Receipt = $false }
        @{ Name = 'new backdated binary'; Artifact = 'backdated'; Expected = 0; Receipt = $true }
        @{ Name = 'future-dated leftover'; Artifact = 'missing'; Seed = $true; Expected = 3; Receipt = $false }
        @{ Name = 'locked leftover'; Artifact = 'missing'; Seed = $true; Lock = $true; Expected = 3; Receipt = $false }
        @{ Name = 'missing compiler'; Artifact = 'file'; Missing = 'compiler'; Expected = 2; Receipt = $false }
        @{ Name = 'missing SDK'; Artifact = 'file'; Missing = 'sdk'; Expected = 2; Receipt = $false }
        @{ Name = 'missing GCC'; Artifact = 'file'; Missing = 'gcc'; Expected = 2; Receipt = $false }
        @{ Name = 'missing RTL'; Artifact = 'file'; Missing = 'rtl'; Expected = 2; Receipt = $false }
        @{ Name = 'missing DUnitX'; Artifact = 'file'; Missing = 'dunitx'; Expected = 2; Receipt = $false }
        @{ Name = 'missing project'; Artifact = 'file'; Missing = 'project'; Expected = 2; Receipt = $false }
        @{ Name = 'output-root exception'; Artifact = 'file'; InvalidRoot = $true; Expected = 3; Receipt = $false }
    ) {
        $project = if ($Missing -eq 'project') { Join-Path $TestDrive 'missing.dpr' } else { 'tests\maxCronTests.dpr' }
        $buildRoot = Join-Path $TestDrive $Name
        $testCompiler = $compiler
        $testSdk = $sdk
        if ($Missing -eq 'gcc') {
            $testSdk = Join-Path $buildRoot 'sdk-without-gcc'
            [void][IO.Directory]::CreateDirectory($testSdk)
        }
        if ($Missing -in 'rtl', 'dunitx') {
            $testStudio = Join-Path $buildRoot 'studio'
            $testCompiler = Join-Path $testStudio 'bin/dcclinux64.exe'
            $available = if ($Missing -eq 'rtl') { 'source/DUnitX' } else { 'lib/linux64/release' }
            [void][IO.Directory]::CreateDirectory((Join-Path $testStudio 'bin'))
            [void][IO.Directory]::CreateDirectory((Join-Path $testStudio $available))
            [IO.File]::Copy($compiler, $testCompiler)
        }
        $start = Get-WrapperStartInfo -BuildRoot $buildRoot -Artifact $Artifact -Project $project
        $start.Environment['MAXCRON_DCCLINUX64'] = if ($Missing -eq 'compiler') { Join-Path $TestDrive 'missing.exe' } else { $testCompiler }
        $start.Environment['MAXCRON_LINUX_SDK'] = if ($Missing -eq 'sdk') { Join-Path $TestDrive 'missing-sdk' } else { $testSdk }
        $start.Environment['MAXCRON_BUILD_ROOT'] = if ($InvalidRoot) { "$buildRoot|invalid" } else { $buildRoot }
        $start.Environment['MAXCRON_STUB_EXIT'] = [string][int]$CompilerExit
        $start.Environment['MAXCRON_STUB_DIAGNOSTIC'] = if ($Diagnostic -and $Diagnostic -notmatch '^Hint:') {
            Join-Path $repository $Diagnostic
        } else {
            [string]$Diagnostic
        }

        $lockedFile = $null
        $process = $null
        try {
            if ($Seed) {
                $destination = Join-Path $buildRoot 'linux64/release/maxCronTests/maxCronTests'
                [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination))
                [IO.File]::WriteAllText($destination, 'predates compilation')
                [IO.File]::SetLastWriteTimeUtc($destination, [DateTime]::UtcNow.AddDays(1))
                if ($Lock) {
                    $lockedFile = [IO.File]::Open($destination, 'Open', 'Read', 'Read')
                }
            }
            $process = [Diagnostics.Process]::Start($start)
            $result = Receive-WrapperResult $process
            $output = $result.Output
            $result.ExitCode | Should -Be $Expected -Because $output
            ($output -match '(?m)^LINUX64_OUTPUT ') | Should -Be $Receipt -Because $output
            if ($Seed) {
                $output | Should -Match '(?m)^ROSTER_PHASE phase=build name=maxCronTests native_exit=0\b'
                [IO.File]::ReadAllText($destination) | Should -Be 'predates compilation'
            }
        } finally {
            if ($process) { $process.Dispose() }
            if ($lockedFile) { $lockedFile.Dispose() }
        }
    }

    It 'rejects a missing binary even when an overlapping invocation writes its own' {
        $buildRoot = Join-Path $TestDrive 'overlapping'
        $project = 'tests\maxCronTests.dpr'
        $barrier = 'maxCron.wrapper.' + [Guid]::NewGuid().ToString('N')
        $ready = [Threading.EventWaitHandle]::new($false, 'ManualReset', "$barrier.ready")
        $release = [Threading.EventWaitHandle]::new($false, 'ManualReset', "$barrier.release")
        $first = $null
        $second = $null
        try {
            $start = Get-WrapperStartInfo -BuildRoot $buildRoot -Artifact missing -Project $project
            $start.Environment['MAXCRON_STUB_BARRIER'] = $barrier
            $first = [Diagnostics.Process]::Start($start)
            $ready.WaitOne([TimeSpan]::FromSeconds(30)) | Should -BeTrue -Because 'the first compiler must be running before the second starts'

            $start = Get-WrapperStartInfo -BuildRoot $buildRoot -Artifact file -Project $project
            $second = [Diagnostics.Process]::Start($start)
            $built = Receive-WrapperResult $second
            [void]$release.Set()
            $missingBinary = Receive-WrapperResult $first
            $built.ExitCode | Should -Be 0 -Because $built.Output
            $receipt = [regex]::Match($built.Output, '(?m)^LINUX64_OUTPUT (?<dir>[^\r\n]+)')
            $receipt.Success | Should -BeTrue -Because $built.Output
            [IO.File]::ReadAllText((Join-Path $receipt.Groups['dir'].Value 'maxCronTests')) | Should -Be 'stub'
            $missingBinary.Output | Should -Match '(?m)^ROSTER_PHASE phase=build name=maxCronTests native_exit=0\b'
            $missingBinary.ExitCode | Should -Be 3 -Because $missingBinary.Output
            $missingBinary.Output | Should -Not -Match '(?m)^LINUX64_OUTPUT '
        } finally {
            [void]$release.Set()
            if ($first) {
                if (-not $first.HasExited -and -not $first.WaitForExit(30000)) {
                    $first.Kill($true)
                    $first.WaitForExit()
                }
                $first.Dispose()
            }
            if ($second) { $second.Dispose() }
            $ready.Dispose()
            $release.Dispose()
        }
    }

    It 'publishes no receipts when the second default project fails' {
        $start = Get-WrapperStartInfo -BuildRoot (Join-Path $TestDrive 'batch-failure') -Artifact file
        $start.Environment['MAXCRON_STUB_FAIL_PROJECT'] = 'maxCronStressTests'
        $process = [Diagnostics.Process]::Start($start)
        try {
            $result = Receive-WrapperResult $process
            $result.Output | Should -Match '(?m)^ROSTER_PHASE phase=build name=maxCronTests native_exit=0\b'
            $result.Output | Should -Match '(?m)^ROSTER_PHASE phase=build name=maxCronStressTests native_exit=1\b'
            $result.ExitCode | Should -Be 3 -Because $result.Output
            $result.Output | Should -Not -Match '(?m)^LINUX64_OUTPUT '
        } finally {
            $process.Dispose()
        }
    }
}

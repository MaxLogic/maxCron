[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Native protocol receipts must go directly to the console, outside PowerShell result objects.')]
param()

function Get-FpcToolchain {
    param([string]$Compiler = $env:MAXCRON_FPC)

    if ([string]::IsNullOrWhiteSpace($Compiler)) { throw 'Set MAXCRON_FPC to the path to fpc.exe.' }
    if (-not [IO.File]::Exists($Compiler)) { throw "FPC compiler does not exist: $Compiler. Set MAXCRON_FPC to the path to fpc.exe." }
    $Compiler = [IO.Path]::GetFullPath($Compiler)
    if ([IO.Path]::GetExtension($Compiler) -ine '.exe') { throw 'FPC compiler must be a native .exe. Set MAXCRON_FPC to the path to fpc.exe.' }
    $bin = [IO.Path]::GetDirectoryName($Compiler)
    $root = [IO.Path]::GetFullPath((Join-Path $bin '..\..'))
    return [pscustomobject]@{
        Compiler = $Compiler
        Bin = $bin
        Config = Join-Path $bin 'fpc.cfg'
        UnitSearchPath = Join-Path $root 'units\x86_64-win64\*'
    }
}

function Get-RosterOutputRoot {
    param([string]$Override, [string]$Suite)

    if ($Override) { return $Override }
    if ($env:MAXCRON_BUILD_ROOT) { return [IO.Path]::Combine($env:MAXCRON_BUILD_ROOT, $Suite) }
    return Join-Path ([IO.Path]::GetTempPath()) ('maxCron-' + $Suite)
}

if (-not ('MaxCron.RosterViolation' -as [type])) {
    Add-Type -TypeDefinition 'namespace MaxCron { public sealed class RosterViolation : System.Exception { public readonly string Reason; public readonly string PhaseName; public RosterViolation(string reason, string detail, string name) : base(detail) { Reason = reason; PhaseName = name; } } }'
}

if (-not ('MaxCron.RosterProcess' -as [type])) {
    # CreateProcess starts suspended: assignment to the kill-on-close job is
    # complete before ANY child code can run. Job membership outlives parents.
    Add-Type -TypeDefinition @'
using System;
using System.Collections;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Win32.SafeHandles;

namespace MaxCron {
    public sealed class RosterProcess : IDisposable {
        [StructLayout(LayoutKind.Sequential)] struct Security {
            public int Length; public IntPtr Descriptor; public int Inherit;
        }
        [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] struct Startup {
            public int Size; public string Reserved, Desktop, Title;
            public int X, Y, XSize, YSize, XCount, YCount, Fill, Flags;
            public short Show, ReservedSize; public IntPtr ReservedBytes, Input, Output, Error;
        }
        [StructLayout(LayoutKind.Sequential)] struct StartupEx { public Startup Info; public IntPtr Attributes; }
        [StructLayout(LayoutKind.Sequential)] struct ProcessInfo { public IntPtr Process, Thread; public int Id, ThreadId; }
        [StructLayout(LayoutKind.Sequential)] struct BasicLimits {
            public long ProcessTime, JobTime; public uint Flags;
            public UIntPtr MinWorkingSet, MaxWorkingSet;
            public uint ActiveLimit; public UIntPtr Affinity; public uint Priority, Scheduling;
        }
        [StructLayout(LayoutKind.Sequential)] struct IoCounters { public ulong A, B, C, D, E, F; }
        [StructLayout(LayoutKind.Sequential)] struct ExtendedLimits {
            public BasicLimits Basic; public IoCounters Io;
            public UIntPtr ProcessMemory, JobMemory, PeakProcessMemory, PeakJobMemory;
        }
        [StructLayout(LayoutKind.Sequential)] struct Accounting {
            public long User, Kernel, PeriodUser, PeriodKernel;
            public uint Faults, TotalProcesses, ActiveProcesses, TerminatedProcesses;
        }
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern IntPtr CreateJobObject(IntPtr security, string name);
        [DllImport("kernel32.dll", SetLastError=true)] static extern bool SetInformationJobObject(IntPtr job, int kind, ref ExtendedLimits data, uint size);
        [DllImport("kernel32.dll", SetLastError=true)] static extern bool QueryInformationJobObject(IntPtr job, int kind, out Accounting data, uint size, IntPtr returned);
        [DllImport("kernel32.dll", SetLastError=true)] static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
        [DllImport("kernel32.dll", SetLastError=true)] static extern bool TerminateJobObject(IntPtr job, uint code);
        [DllImport("kernel32.dll", SetLastError=true)] static extern bool CreatePipe(out IntPtr read, out IntPtr write, ref Security security, uint size);
        [DllImport("kernel32.dll", SetLastError=true)] static extern bool SetHandleInformation(IntPtr handle, uint mask, uint flags);
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern IntPtr CreateFile(string name, uint access, uint share, ref Security security, uint disposition, uint flags, IntPtr template);
        [DllImport("kernel32.dll", SetLastError=true)] static extern bool InitializeProcThreadAttributeList(IntPtr list, int count, int flags, ref IntPtr size);
        [DllImport("kernel32.dll", SetLastError=true)] static extern bool UpdateProcThreadAttribute(IntPtr list, uint flags, IntPtr attribute, IntPtr value, IntPtr size, IntPtr previous, IntPtr returned);
        [DllImport("kernel32.dll")] static extern void DeleteProcThreadAttributeList(IntPtr list);
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool CreateProcess(string application, StringBuilder command, IntPtr processSecurity, IntPtr threadSecurity, bool inherit, uint flags, IntPtr environment, string directory, ref StartupEx startup, out ProcessInfo info);
        [DllImport("kernel32.dll", SetLastError=true)] static extern uint ResumeThread(IntPtr thread);
        [DllImport("kernel32.dll", SetLastError=true)] static extern bool TerminateProcess(IntPtr process, uint code);
        [DllImport("kernel32.dll", SetLastError=true)] static extern uint WaitForSingleObject(IntPtr handle, uint milliseconds);
        [DllImport("kernel32.dll", SetLastError=true)] static extern bool GetExitCodeProcess(IntPtr process, out uint code);
        [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);

        IntPtr job, process;
        public int Id { get; private set; }
        public StreamReader StandardOutput { get; private set; }
        public StreamReader StandardError { get; private set; }
        public Task<string> Stdout { get; private set; }
        public Task<string> Stderr { get; private set; }
        static void Check(bool ok) { if (!ok) throw new Win32Exception(Marshal.GetLastWin32Error()); }
        static void Close(ref IntPtr handle) { if (handle != IntPtr.Zero && handle != new IntPtr(-1)) CloseHandle(handle); handle=IntPtr.Zero; }
        public bool HasExited { get { return WaitForExit(0); } }
        public int ExitCode { get { uint code; Check(GetExitCodeProcess(process, out code)); return unchecked((int)code); } }
        public uint ActiveProcesses {
            get { Accounting data; Check(QueryInformationJobObject(job, 1, out data, (uint)Marshal.SizeOf(typeof(Accounting)), IntPtr.Zero)); return data.ActiveProcesses; }
        }
        public bool WaitForExit(int milliseconds) {
            if (milliseconds < 0) throw new ArgumentOutOfRangeException("milliseconds");
            uint result=WaitForSingleObject(process, (uint)milliseconds);
            if (result == 0xffffffff) throw new Win32Exception(Marshal.GetLastWin32Error());
            return result == 0;
        }
        public void Terminate() { Check(TerminateJobObject(job, 124)); }
        public bool WaitForEmpty(int milliseconds) {
            Stopwatch clock=Stopwatch.StartNew();
            do { if (ActiveProcesses == 0) return true; Thread.Sleep(10); } while (clock.ElapsedMilliseconds < milliseconds);
            return ActiveProcesses == 0;
        }
        public static RosterProcess Start(ProcessStartInfo start) {
            RosterProcess owner=new RosterProcess();
            IntPtr readOut=IntPtr.Zero, writeOut=IntPtr.Zero, readError=IntPtr.Zero, writeError=IntPtr.Zero;
            IntPtr input=IntPtr.Zero, environment=IntPtr.Zero, handles=IntPtr.Zero;
            StartupEx startup=new StartupEx(); ProcessInfo info=new ProcessInfo(); bool assigned=false, attributesReady=false;
            try {
                owner.job=CreateJobObject(IntPtr.Zero, null); Check(owner.job != IntPtr.Zero);
                ExtendedLimits limits=new ExtendedLimits(); limits.Basic.Flags=0x2000; // KILL_ON_JOB_CLOSE, no breakaway
                Check(SetInformationJobObject(owner.job, 9, ref limits, (uint)Marshal.SizeOf(typeof(ExtendedLimits))));
                Security security=new Security(); security.Length=Marshal.SizeOf(typeof(Security)); security.Inherit=1;
                Check(CreatePipe(out readOut, out writeOut, ref security, 0));
                Check(CreatePipe(out readError, out writeError, ref security, 0));
                Check(SetHandleInformation(readOut, 1, 0)); Check(SetHandleInformation(readError, 1, 0));
                input=CreateFile("NUL", 0x80000000, 3, ref security, 3, 0, IntPtr.Zero); Check(input != new IntPtr(-1));
                startup.Info.Size=Marshal.SizeOf(typeof(StartupEx)); startup.Info.Flags=0x100;
                startup.Info.Input=input; startup.Info.Output=writeOut; startup.Info.Error=writeError;
                IntPtr size=IntPtr.Zero; InitializeProcThreadAttributeList(IntPtr.Zero, 1, 0, ref size);
                startup.Attributes=Marshal.AllocHGlobal(size); Check(InitializeProcThreadAttributeList(startup.Attributes, 1, 0, ref size)); attributesReady=true;
                handles=Marshal.AllocHGlobal(3*IntPtr.Size);
                Marshal.WriteIntPtr(handles, 0, input); Marshal.WriteIntPtr(handles, IntPtr.Size, writeOut); Marshal.WriteIntPtr(handles, 2*IntPtr.Size, writeError);
                Check(UpdateProcThreadAttribute(startup.Attributes, 0, new IntPtr(0x20002), handles, new IntPtr(3*IntPtr.Size), IntPtr.Zero, IntPtr.Zero));
                SortedDictionary<string,string> variables=new SortedDictionary<string,string>(StringComparer.OrdinalIgnoreCase);
                foreach (DictionaryEntry entry in start.EnvironmentVariables) variables[(string)entry.Key]=(string)entry.Value;
                StringBuilder block=new StringBuilder();
                foreach (KeyValuePair<string,string> entry in variables) block.Append(entry.Key).Append('=').Append(entry.Value).Append('\0');
                block.Append('\0'); if (variables.Count == 0) block.Append('\0');
                environment=Marshal.StringToHGlobalUni(block.ToString());
                string executable=start.FileName;
                if (!Path.IsPathRooted(executable)) {
                    string resolved=null;
                    foreach (string folder in (Environment.GetEnvironmentVariable("PATH") ?? "").Split(Path.PathSeparator)) {
                        string candidate=Path.Combine(folder.Trim('"'), executable);
                        if (File.Exists(candidate)) { resolved=candidate; break; }
                        if (File.Exists(candidate+".exe")) { resolved=candidate+".exe"; break; }
                    }
                    if (resolved != null) executable=resolved;
                }
                StringBuilder command=new StringBuilder("\""+executable+"\" "+start.Arguments);
                Check(CreateProcess(executable, command, IntPtr.Zero, IntPtr.Zero, true, 0x08080404, environment,
                    String.IsNullOrEmpty(start.WorkingDirectory) ? null : start.WorkingDirectory, ref startup, out info));
                owner.process=info.Process; owner.Id=info.Id;
                Check(AssignProcessToJobObject(owner.job, info.Process)); assigned=true;
                owner.StandardOutput=new StreamReader(new FileStream(new SafeFileHandle(readOut, true), FileAccess.Read), start.StandardOutputEncoding ?? Encoding.UTF8); readOut=IntPtr.Zero;
                owner.StandardError=new StreamReader(new FileStream(new SafeFileHandle(readError, true), FileAccess.Read), start.StandardErrorEncoding ?? Encoding.UTF8); readError=IntPtr.Zero;
                owner.Stdout=owner.StandardOutput.ReadToEndAsync(); owner.Stderr=owner.StandardError.ReadToEndAsync();
                Check(ResumeThread(info.Thread) != 0xffffffff);
                return owner;
            } catch {
                // Even a failed assignment leaves a suspended process. Never run it outside ownership.
                if (info.Process != IntPtr.Zero) { if (assigned) TerminateJobObject(owner.job, 124); else TerminateProcess(info.Process, 124); }
                owner.Dispose(); throw;
            } finally {
                Close(ref info.Thread); Close(ref writeOut); Close(ref writeError); Close(ref readOut); Close(ref readError); Close(ref input);
                if (attributesReady) DeleteProcThreadAttributeList(startup.Attributes);
                if (startup.Attributes != IntPtr.Zero) Marshal.FreeHGlobal(startup.Attributes);
                if (handles != IntPtr.Zero) Marshal.FreeHGlobal(handles);
                if (environment != IntPtr.Zero) Marshal.FreeHGlobal(environment);
            }
        }
        public void Dispose() {
            Close(ref job); // All remaining members die, including orphaned descendants.
            Close(ref process);
            // A foreign handle owner (for example the WSL VM) can outlive the
            // Windows job. Never turn a bounded drain into an unbounded Dispose.
            if (StandardOutput != null) {
                if (Stdout == null || Stdout.IsCompleted) StandardOutput.Dispose();
                else Stdout.ContinueWith(t => StandardOutput.Dispose());
            }
            if (StandardError != null) {
                if (Stderr == null || Stderr.IsCompleted) StandardError.Dispose();
                else Stderr.ContinueWith(t => StandardError.Dispose());
            }
        }
    }
}
'@
}

function New-RosterViolation {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'New-RosterViolation only constructs an exception object; it changes no external state.')]
    param([ValidateSet('missing','extra','renamed','duplicate','stale','empty','count')][string]$Reason, [string]$Detail, [string]$Name = 'identity')
    return [MaxCron.RosterViolation]::new($Reason, $Detail, $Name)
}

function Write-RosterPhase {
    param([string]$Phase, [string]$Name, [int]$NativeExit)
    [Console]::WriteLine('ROSTER_PHASE phase=' + $Phase + ' name=' + $Name + ' native_exit=' + $NativeExit)
}

function Complete-RosterFailure {
    param([Exception]$ErrorObject, [int]$InfrastructureExit = 3)
    $cause = $ErrorObject
    while ($cause) {
        if ($cause -is [MaxCron.RosterViolation]) {
            Write-RosterPhase roster $cause.PhaseName 5
            [Console]::WriteLine('ROSTER_REJECTED reason=' + $cause.Reason + ' detail=' + ($cause.Message -replace '[\r\n]', ' '))
            return 5
        }
        if ($cause -is [TimeoutException]) {
            [Console]::Error.WriteLine($cause.Message)
            return 124
        }
        $cause = $cause.InnerException
    }
    [Console]::Error.WriteLine($ErrorObject.Message)
    return $InfrastructureExit
}

function Test-RosterRejection {
    param([int]$NativeExit, [string]$Text)
    if ($NativeExit -ne 5) { return $false }
    $lines = @($Text.TrimEnd() -split '\r?\n')
    $verdicts = @($lines | Where-Object { $_ -cmatch '^ROSTER_REJECTED reason=(missing|extra|renamed|duplicate|stale|empty|count) detail=.+$' })
    $checks = [regex]::Matches($Text, '(?m)^ROSTER_PHASE phase=roster name=\S+ native_exit=5\r?$')
    if ($verdicts.Count -ne 1 -or $checks.Count -ne 1) { return $false }
    $phases = [regex]::Matches($Text, '(?m)^ROSTER_PHASE phase=(\S+) name=\S+ native_exit=(-?\d+)\r?$')
    foreach ($phase in $phases) {
        $code = [int]$phase.Groups[2].Value
        if ($code -notin 0, 5) { return $false }
        if ($code -eq 5 -and $phase.Groups[1].Value -notin 'roster','runner','parity','roster-check') { return $false }
        if ($phase.Index -lt $checks[0].Index -and $code -ne 0) { return $false }
    }
    $index = [Array]::IndexOf($lines, $verdicts[0])
    for ($position = $index + 1; $position -lt $lines.Count; $position++) {
        if ($lines[$position] -cnotmatch '^ROSTER_PHASE phase=(runner|parity|roster-check) name=\S+ native_exit=5$') { return $false }
    }
    return $true
}

function ConvertTo-RosterArgument {
    param([AllowEmptyString()][string]$Value)
    $result = [Text.StringBuilder]::new()
    [void]$result.Append('"')
    $slashes = 0
    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq '\') { $slashes++; continue }
        if ($character -eq '"') { [void]$result.Append('\', (2 * $slashes + 1)) }
        else { [void]$result.Append('\', $slashes) }
        [void]$result.Append($character)
        $slashes = 0
    }
    [void]$result.Append('\', (2 * $slashes))
    [void]$result.Append('"')
    return $result.ToString()
}

function Get-RosterPhaseTimeout {
    param([ValidateSet('build','tool','generator','parity','runner','roster-check')][string]$Phase, [string]$Name)
    switch ($Phase) {
        'build' { return 1800000 }
        'tool' { return 120000 }
        'runner' {
            if ($Name -like 'smoke*') { return 600000 }
            if ($Name -eq 'DelphiLong' -or ($Name -eq 'tests' -and $env:MAXCRON_LONG_TESTS -eq '1')) { return 172800000 }
            return 7200000
        }
        'roster-check' { if ($Name -eq 'DelphiDefaultGate') { return 28800000 }; return 600000 }
        default { return 600000 }
    }
}

function Start-RosterProcess {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Starts only the requested hidden child suspended in an owned kill-on-close job.')]
    param([Diagnostics.ProcessStartInfo]$StartInfo)
    return [MaxCron.RosterProcess]::Start($StartInfo)
}

function Wait-RosterProcess {
    param([MaxCron.RosterProcess]$Process, [Threading.Tasks.Task]$Stdout, [Threading.Tasks.Task]$Stderr, [int]$TimeoutMs, [string]$Phase, [string]$Name)
    if ($TimeoutMs -le 0) { throw 'A positive phase timeout is required' }
    $clock = [Diagnostics.Stopwatch]::StartNew()
    $completed = $Process.WaitForExit($TimeoutMs)
    if ($completed) {
        $remaining = [int][Math]::Max(1, $TimeoutMs - $clock.ElapsedMilliseconds)
        $completed = [Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($Stdout, $Stderr), $remaining)
    }
    if (-not $completed) {
        $diagnostics = @()
        $active = -1
        try {
            $Process.Terminate()
            if (-not $Process.WaitForEmpty(10000)) { $diagnostics += 'job termination incomplete' }
            $active = $Process.ActiveProcesses
        } catch { $diagnostics += ('job termination error: ' + $_.Exception.Message) }
        try {
            if (-not [Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($Stdout, $Stderr), 5000)) {
                $diagnostics += 'redirected stream drain incomplete after 5000ms'
            }
        } catch { $diagnostics += ('redirected stream drain error: ' + $_.Exception.Message) }
        $outComplete = $Stdout.Status -eq [Threading.Tasks.TaskStatus]::RanToCompletion
        $errComplete = $Stderr.Status -eq [Threading.Tasks.TaskStatus]::RanToCompletion
        if ($outComplete) { [Console]::Write($Stdout.Result) }
        if ($errComplete) { [Console]::Error.Write($Stderr.Result) }
        [Console]::Error.WriteLine('ROSTER_TIMEOUT name=' + $Name + ' active_processes=' + $active + ' stdout_complete=' + $outComplete + ' stderr_complete=' + $errComplete)
        foreach ($diagnostic in $diagnostics) { [Console]::Error.WriteLine('ROSTER_TIMEOUT_INCOMPLETE ' + $diagnostic) }
        $nativeExit = if ($Process.HasExited) { $Process.ExitCode } else { 124 }
        Write-RosterPhase $Phase $Name $nativeExit
        $failure = [TimeoutException]::new('Subprocess timeout: ' + $Name + ' limit=' + $TimeoutMs + 'ms')
        $failure.Data['StdoutComplete'] = $outComplete
        $failure.Data['StderrComplete'] = $errComplete
        $failure.Data['ActiveProcesses'] = $active
        $failure.Data['Diagnostics'] = $diagnostics
        throw $failure
    }
}

function Invoke-RosterChild {
    param([string]$Executable, [string[]]$ArgumentList, [string]$WorkingDirectory, [string]$Phase, [string]$Name, [int]$TimeoutMs = -1)
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $Executable
    $start.Arguments = (($ArgumentList | ForEach-Object { ConvertTo-RosterArgument $_ }) -join ' ')
    $start.WorkingDirectory = $WorkingDirectory
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.StandardOutputEncoding = [Text.Encoding]::UTF8
    $start.StandardErrorEncoding = [Text.Encoding]::UTF8
    $process = Start-RosterProcess -StartInfo $start
    try {
        $stdout = $process.Stdout
        $stderr = $process.Stderr
        if ($TimeoutMs -le 0) { $TimeoutMs = Get-RosterPhaseTimeout -Phase $Phase -Name $Name }
        Wait-RosterProcess -Process $process -Stdout $stdout -Stderr $stderr -TimeoutMs $TimeoutMs -Phase $Phase -Name $Name
        $text = $stdout.Result + $stderr.Result
        [Console]::Write($text)
        Write-RosterPhase $Phase $Name $process.ExitCode
        return [pscustomobject]@{ ExitCode = $process.ExitCode; Text = $text }
    } finally { $process.Dispose() }
}

function Read-RosterManifest {
    param([string]$Repository, [string]$Entry)
    Import-Module (Join-Path $PSHOME 'Modules/Microsoft.PowerShell.Utility/Microsoft.PowerShell.Utility.psd1') -ErrorAction Stop
    $root = [IO.Path]::GetFullPath($Repository).TrimEnd('\') + '\'
    $lines = @(Get-Content -Encoding UTF8 -LiteralPath (Join-Path $root ('tests/rosters/' + $Entry + '.txt')))
    $names = @($lines | Where-Object { $_ -and -not $_.StartsWith('#') })
    $stamps = @($lines | Where-Object { $_.StartsWith('# SHA256 ') })
    if ($names.Count -eq 0 -or $stamps.Count -eq 0) { throw (New-RosterViolation empty ('Empty test roster manifest: ' + $Entry) $Entry) }
    foreach ($stamp in $stamps) {
        if ($stamp -cnotmatch '^# SHA256 ([A-Za-z0-9_./+\-]+) ([a-f0-9]{64})$') { throw (New-RosterViolation stale 'Invalid test roster source stamp' $Entry) }
        $relative = $Matches[1]
        $hash = $Matches[2]
        $path = [IO.Path]::GetFullPath((Join-Path $root $relative))
        if (-not $path.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) { throw (New-RosterViolation stale 'Test roster source escapes the checkout' $Entry) }
        if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ine $hash) {
            throw (New-RosterViolation stale ('Test roster manifest is stale: ' + $relative + '; run tests/Export-TestRosters.ps1') $Entry)
        }
    }
    $unique = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($name in $names) { if (-not $unique.Add($name)) { throw (New-RosterViolation duplicate 'Duplicate identity in test roster manifest' $Entry) } }
    Write-RosterPhase roster $Entry 0
    return [pscustomobject]@{ Names = [string[]]$names }
}

function Assert-RosterIdentity {
    param([string[]]$Expected, [AllowEmptyCollection()][string[]]$Actual, [string]$Name = 'identity')
    if ($Expected.Count -le 0 -or $Actual.Count -le 0) { throw (New-RosterViolation empty 'Empty test roster' $Name) }
    $remaining = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($identity in $Expected) { if (-not $remaining.Add($identity)) { throw (New-RosterViolation duplicate 'Duplicate expected identity' $Name) } }
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($identity in $Actual) { if (-not $seen.Add($identity)) { throw (New-RosterViolation duplicate 'Duplicate actual identity' $Name) } }
    if ($Actual.Count -lt $Expected.Count) { throw (New-RosterViolation missing 'Test roster manifest count differs: missing identities' $Name) }
    if ($Actual.Count -gt $Expected.Count) { throw (New-RosterViolation extra 'Test roster manifest count differs: extra identities' $Name) }
    foreach ($identity in $Actual) { if (-not $remaining.Remove($identity)) { throw (New-RosterViolation renamed ('Test roster manifest identity differs: ' + $identity) $Name) } }
    Write-RosterPhase roster $Name 0
}

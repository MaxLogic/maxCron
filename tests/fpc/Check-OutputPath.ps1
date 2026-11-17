param(
    [Parameter(Mandatory = $true)][string]$Repository,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [switch]$CreateRun,
    [switch]$InProcess
)

$ErrorActionPreference = 'Stop'
try {
    # Open directories without OPEN_REPARSE_POINT: the handle identifies the target.
    # Volume GUID paths also normalize SUBST drives, short names and mount points.
    # Emit only P/Invoke declarations in memory. Add-Type on Windows PowerShell
    # would start csc.exe and write temporary files before a run is allocated.
    if (-not ('MaxCronPathNative' -as [type])) {
        $assemblyName = [Reflection.AssemblyName]::new('MaxCronPathNative')
        $assembly = if ($PSVersionTable.PSEdition -eq 'Core') {
            [Reflection.Emit.AssemblyBuilder]::DefineDynamicAssembly($assemblyName, [Reflection.Emit.AssemblyBuilderAccess]::Run)
        } else {
            [AppDomain]::CurrentDomain.DefineDynamicAssembly($assemblyName, [Reflection.Emit.AssemblyBuilderAccess]::Run)
        }
        $type = $assembly.DefineDynamicModule('Native').DefineType('MaxCronPathNative', [Reflection.TypeAttributes]'Public, Abstract, Sealed')
        $declarations = @(
            @{ Name = 'CreateDirectory'; Entry = 'CreateDirectoryW'; Result = [bool]; Arguments = [type[]]@([string], [IntPtr]) },
            @{ Name = 'CreateFile'; Entry = 'CreateFileW'; Result = [IntPtr]; Arguments = [type[]]@([string], [uint32], [uint32], [IntPtr], [uint32], [uint32], [IntPtr]) },
            @{ Name = 'GetFinalPathNameByHandle'; Entry = 'GetFinalPathNameByHandleW'; Result = [uint32]; Arguments = [type[]]@([IntPtr], [Text.StringBuilder], [uint32], [uint32]) },
            @{ Name = 'CloseHandle'; Entry = 'CloseHandle'; Result = [bool]; Arguments = [type[]]@([IntPtr]) }
        )
        foreach ($declaration in $declarations) {
            $method = $type.DefinePInvokeMethod($declaration.Name, 'kernel32.dll', $declaration.Entry,
                [Reflection.MethodAttributes]'Public, Static, PinvokeImpl', [Reflection.CallingConventions]::Standard,
                $declaration.Result, $declaration.Arguments, [Runtime.InteropServices.CallingConvention]::Winapi,
                [Runtime.InteropServices.CharSet]::Unicode)
            $method.SetImplementationFlags([Reflection.MethodImplAttributes]::PreserveSig)
        }
        [void]$type.CreateType()
    }
    function Get-DirectoryIdentity {
        param([string]$Path)
        $handle = [MaxCronPathNative]::CreateFile($Path, 0, 7, [IntPtr]::Zero, 3, 0x02000000, [IntPtr]::Zero)
        if ($handle -eq [IntPtr]::new(-1)) { throw "Cannot open directory identity: $Path" }
        try {
            $result = [Text.StringBuilder]::new(32768)
            $length = [MaxCronPathNative]::GetFinalPathNameByHandle($handle, $result, $result.Capacity, 1)
            if ($length -eq 0 -or $length -ge $result.Capacity) { throw "Cannot resolve directory identity: $Path" }
            return $result.ToString().TrimEnd('\')
        } finally { [void][MaxCronPathNative]::CloseHandle($handle) }
    }
    $repositoryIdentity = Get-DirectoryIdentity ([IO.Path]::GetFullPath($Repository))
    $root = [IO.Path]::GetFullPath($OutputPath)
    $ancestor = $root
    # Reject a source ancestor even if an outbound link later leaves it. Do
    # this before creating anything. No pre-existing child is ever reused.
    while ($ancestor) {
        if ([IO.Directory]::Exists($ancestor)) {
            $identity = Get-DirectoryIdentity $ancestor
            if ($identity.Equals($repositoryIdentity, [StringComparison]::OrdinalIgnoreCase) -or
                $identity.StartsWith($repositoryIdentity + '\', [StringComparison]::OrdinalIgnoreCase)) {
                throw 'FPC output must not traverse the source tree'
            }
        }
        $parent = [IO.Path]::GetDirectoryName($ancestor)
        if ($parent -eq $ancestor) { break }
        $ancestor = $parent
    }
    if ($CreateRun) {
        [void][IO.Directory]::CreateDirectory($root)
        $run = Join-Path $root ('run-' + [Guid]::NewGuid().ToString('N'))
        # Unlike Directory.CreateDirectory, this fails if the name exists.
        if (-not [MaxCronPathNative]::CreateDirectory($run, [IntPtr]::Zero)) { throw 'Cannot create a fresh run directory' }
        $outputIdentity = Get-DirectoryIdentity $run
        if ($outputIdentity.Equals($repositoryIdentity, [StringComparison]::OrdinalIgnoreCase) -or
            $outputIdentity.StartsWith($repositoryIdentity + '\', [StringComparison]::OrdinalIgnoreCase)) {
            throw 'FPC output must be outside the source tree'
        }
        # Threat model excludes a concurrent malicious directory replacement.
        # All writers now receive only this freshly created, validated child.
        Write-Output $run
    }
    if (-not $InProcess) { exit 0 }
} catch {
    if ($InProcess) { throw }
    [Console]::Error.WriteLine('FPC output rejected: ' + $_.Exception.Message)
    exit 2
}

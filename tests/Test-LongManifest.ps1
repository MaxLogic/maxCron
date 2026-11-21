param()

$ErrorActionPreference = 'Stop'
try {
    Import-Module (Join-Path $PSHOME 'Modules/Microsoft.PowerShell.Utility/Microsoft.PowerShell.Utility.psd1') -ErrorAction Stop
    $repository = Split-Path -Parent $PSScriptRoot
    . (Join-Path $PSScriptRoot 'RosterManifest.ps1')
    $names = (Read-RosterManifest -Repository $repository -Entry 'DelphiLong').Names
    Write-Output ('Long source manifest current: {0} identities' -f $names.Count)
    exit 0
} catch {
    exit (Complete-RosterFailure $_.Exception)
}

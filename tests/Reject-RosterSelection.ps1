param()
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'RosterManifest.ps1')
try {
    throw (New-RosterViolation count 'Test selection arguments are not accepted; the complete roster is required' arguments)
} catch { exit (Complete-RosterFailure $_.Exception) }

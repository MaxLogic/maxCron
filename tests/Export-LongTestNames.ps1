param(
    [Parameter(Mandatory = $true)][string]$Compiler,
    [Parameter(Mandatory = $true)][string]$DUnitXSource,
    [Parameter(Mandatory = $true)][string]$OutputRoot,
    [string]$Destination
)

$ErrorActionPreference = 'Stop'
# Compatibility entry for explicit regeneration. Gates never call exporters.
& (Join-Path $PSScriptRoot 'Export-TestRosters.ps1') -Compiler $Compiler -DUnitXSource $DUnitXSource -OutputRoot $OutputRoot
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
if ($Destination) { Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'LongTests.txt') -Destination $Destination }

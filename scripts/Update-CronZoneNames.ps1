#Requires -Version 5.1
<#
.SYNOPSIS
Generates the compiled IANA to Windows name table from an unpacked CLDR common directory.
.DESCRIPTION
Reads data only. External XML entities and DTD processing are disabled. The CLDR
archive's LICENSE must be beside common/. Verify the official archive checksum
before unpacking. Output is deterministic UTF-8 with BOM and CRLF.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $CldrCommon,
    [string] $OutputPath = (Join-Path $PSScriptRoot '../maxCron.Internal.TimeZoneNames.inc')
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-CldrXml([string] $Path) {
    $settings = New-Object System.Xml.XmlReaderSettings
    $settings.DtdProcessing = [System.Xml.DtdProcessing]::Ignore
    $settings.XmlResolver = $null
    $settings.MaxCharactersInDocument = 16777216
    $reader = [System.Xml.XmlReader]::Create($Path, $settings)
    try {
        $document = New-Object System.Xml.XmlDocument
        $document.XmlResolver = $null
        $document.Load($reader)
        return ,$document
    } finally { $reader.Dispose() }
}

function Assert-ZoneName([string] $Name) {
    if ($Name -cnotmatch '\A[A-Za-z][A-Za-z0-9_+./-]{0,254}\z' -or
        $Name -match '(?:\A|/)\.{0,2}(?:/|\z)') {
        throw 'Invalid CLDR zone name: expected 1-255 ASCII letters, digits, _ + . - and valid slash-separated components'
    }
}

function Assert-WindowsId([string] $WindowsId, [bool] $AllowEmpty = $false) {
    if ($AllowEmpty -and $WindowsId.Length -eq 0) { return }
    if ($WindowsId -cnotmatch '\A[A-Za-z0-9][A-Za-z0-9 .()+-]{0,126}\z') {
        throw 'Invalid CLDR Windows id: expected 1-127 ASCII letters, digits, spaces, . ( ) + or -'
    }
}

$common = (Get-Item -LiteralPath $CldrCommon).FullName
$dtd = [IO.File]::ReadAllText((Join-Path $common 'dtd/ldml.dtd'))
$releaseMatches = [regex]::Matches($dtd, '<!ATTLIST\s+version\s+cldrVersion\s+CDATA\s+#FIXED\s+"([^"]*)"')
if ($releaseMatches.Count -ne 1) { throw 'Expected one CLDR release declaration in dtd/ldml.dtd' }
$release = $releaseMatches[0].Groups[1].Value
if ($release -cnotmatch '\A[0-9]{1,3}(?:\.[0-9]{1,3}){0,2}\z') {
    throw 'Invalid CLDR release: expected one to three numeric components of 1-3 ASCII digits'
}
try {
    $licenseText = [IO.File]::ReadAllText((Join-Path (Split-Path $common -Parent) 'LICENSE'), [Text.UTF8Encoding]::new($false, $true))
} catch { throw 'Invalid CLDR license text: cannot read valid UTF-8 text' }
# CR/LF are the only supported line terminators. Other controls, invisible format
# characters and Unicode line separators must never reach generated Pascal.
$invalidLicense = [regex]::Match($licenseText, '[\x00-\x09\x0B\x0C\x0E-\x1F\x7F-\x9F\p{Cf}\p{Cs}\p{Zl}\p{Zp}]')
if ($invalidLicense.Success) {
    throw ('Invalid CLDR license text: unsupported character U+{0:X4}' -f [int]$invalidLicense.Value[0])
}
if ($licenseText -notmatch 'UNICODE LICENSE V3') { throw 'Expected Unicode License v3' }
$windows = Read-CldrXml (Join-Path $common 'supplemental/windowsZones.xml')
$aliases = Read-CldrXml (Join-Path $common 'bcp47/timezone.xml')
$entries = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)

function Add-ZoneName([string] $Name, [string] $WindowsId, [int] $Offset = 0, [bool] $Fixed = $false) {
    Assert-ZoneName $Name
    Assert-WindowsId -WindowsId $WindowsId -AllowEmpty $Fixed
    if ($entries.ContainsKey($Name)) {
        $old = $entries[$Name]
        if ($old.Name -cne $Name) { throw "Case-insensitive collision: $Name / $($old.Name)" }
        if (-not $Fixed -and $old.WindowsId -cne $WindowsId) { throw "Conflicting mapping: $Name" }
    }
    $entries[$Name] = [pscustomobject]@{Name = $Name; WindowsId = $WindowsId; Offset = $Offset}
}

foreach ($row in $windows.SelectNodes('//mapZone')) {
    Assert-WindowsId $row.GetAttribute('other')
    foreach ($name in $row.GetAttribute('type').Split(' ', [StringSplitOptions]::RemoveEmptyEntries)) {
        Add-ZoneName $name $row.GetAttribute('other')
    }
}
foreach ($row in $aliases.SelectNodes('//key[@name="tz"]/type[@alias]')) {
    $names = $row.GetAttribute('alias').Split(' ', [StringSplitOptions]::RemoveEmptyEntries)
    # Validate even aliases whose group has no Windows mapping.
    foreach ($name in $names) { Assert-ZoneName $name }
    $mapped = @($names | Where-Object { $entries.ContainsKey($_) } | ForEach-Object { $entries[$_].WindowsId } | Select-Object -Unique)
    if ($mapped.Count -gt 1) { throw "Conflicting alias group: $($names -join ' ')" }
    if ($mapped.Count -eq 1) { foreach ($name in $names) { Add-ZoneName $name $mapped[0] } }
}
# Fixed forms and all bcp47 aliases of them are independent of the OS database.
$zero = @('Etc/UTC','Etc/UCT','Etc/Universal','Etc/Zulu','Etc/GMT','Etc/GMT0',
    'Etc/GMT+0','Etc/GMT-0','Etc/Greenwich','GMT','UTC','UCT','Zulu','Universal','Greenwich','GMT0','GMT+0','GMT-0')
foreach ($name in $zero) { Add-ZoneName -Name $name -WindowsId '' -Offset 0 -Fixed $true }
foreach ($row in $aliases.SelectNodes('//key[@name="tz"]/type[@alias]')) {
    $names = $row.GetAttribute('alias').Split(' ', [StringSplitOptions]::RemoveEmptyEntries)
    if (@($names | Where-Object { $_ -cin $zero }).Count) {
        foreach ($name in $names) { Add-ZoneName -Name $name -WindowsId '' -Offset 0 -Fixed $true }
    }
}
foreach ($name in @($entries.Keys)) {
    if ($name -cmatch '^Etc/GMT([+-])([0-9]+)$') {
        $offset = [int]$Matches[2] * 3600
        if ($Matches[1] -eq '+') { $offset = -$offset }
        Add-ZoneName -Name $name -WindowsId '' -Offset $offset -Fixed $true
    }
}
$keys = [string[]]@($entries.Keys)
[Array]::Sort($keys, [StringComparer]::OrdinalIgnoreCase)
$lines = [Collections.Generic.List[string]]::new()
$lines.Add("// Generated by scripts/Update-CronZoneNames.ps1 from CLDR $release.")
$lines.Add('// Sources: supplemental/windowsZones.xml and bcp47/timezone.xml. Do not edit.')
foreach ($line in [regex]::Split($licenseText, '\r\n|\r|\n')) { $lines.Add('// ' + $line) }
$lines.Add('type')
$lines.Add('  TCronZoneNameEntry = record')
$lines.Add('    Name, WindowsId: string;')
$lines.Add('    FixedOffsetSeconds: Integer;')
$lines.Add('  end;')
$lines.Add('const')
$lines.Add(('  cCronZoneNames: array[0..{0}] of TCronZoneNameEntry = (' -f ($keys.Count - 1).ToString([Globalization.CultureInfo]::InvariantCulture)))
for ($i = 0; $i -lt $keys.Count; $i++) {
    $row = $entries[$keys[$i]]
    $suffix = if ($i -eq $keys.Count - 1) { ');' } else { ',' }
    $lines.Add(("    (Name: '{0}'; WindowsId: '{1}'; FixedOffsetSeconds: {2}){3}" -f $row.Name, $row.WindowsId, $row.Offset.ToString([Globalization.CultureInfo]::InvariantCulture), $suffix))
}
[IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath), ($lines -join "`r`n") + "`r`n", [Text.UTF8Encoding]::new($true))
Write-Output "CLDR $release : $($keys.Count) names written to $OutputPath"

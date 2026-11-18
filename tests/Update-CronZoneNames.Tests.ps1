#Requires -Version 5.1
# Supply Generator, Compiler, an owned external ScratchRoot and an external BuildRoot.
# Fixtures are retained below ScratchRoot for the caller to inspect and clean.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Pester container parameters are consumed in isolated BeforeAll and test blocks.')]
param(
    [Parameter(Mandatory = $true)] [string] $ScratchRoot,
    [Parameter(Mandatory = $true)] [string] $Compiler,
    [Parameter(Mandatory = $true)] [string] $BuildRoot,
    [Parameter(Mandatory = $true)] [string] $Generator
)

BeforeAll {
    # Bind native Utility cmdlets even if PSModulePath was inherited from the other host.
    Import-Module (Join-Path $PSHOME 'Modules/Microsoft.PowerShell.Utility/Microsoft.PowerShell.Utility.psd1') -ErrorAction Stop
    Test-Path -LiteralPath $Generator -PathType Leaf | Should -BeTrue -Because 'negative cases must run the actual generator'
    Test-Path -LiteralPath $Compiler -PathType Leaf | Should -BeTrue
    $script:generatorPath = [IO.Path]::GetFullPath($Generator)
    $script:compilerPath = [IO.Path]::GetFullPath($Compiler)
    $script:buildParent = [IO.Path]::GetFullPath($BuildRoot)
    $script:fixtureParent = [IO.Path]::GetFullPath($ScratchRoot)
    $script:utf8 = [Text.UTF8Encoding]::new($false, $true)
    $script:directive = '{$MESSAGE ERROR ''UNTRUSTED_CLDR_TEXT_EXECUTED''}'

    function ConvertTo-XmlAttribute([string] $Value) {
        return [Security.SecurityElement]::Escape($Value).Replace("`r", '&#13;').Replace("`n", '&#10;').Replace("`t", '&#9;')
    }

    function New-CldrFixture {
        [CmdletBinding(SupportsShouldProcess = $true)]
        param(
        [string] $License = 'UNICODE LICENSE V3',
        [string] $Release = '49',
        [string] $Name = 'Test/Zone',
        [string] $WindowsId = 'One',
        [string] $Aliases = 'Test/Zone Test/Alias'
        )
        $root = Join-Path $fixtureParent ([Guid]::NewGuid().ToString('N'))
        if (-not $PSCmdlet.ShouldProcess($root, 'Create disposable CLDR test fixture')) { return }
        $common = Join-Path $root 'common'
        foreach ($child in 'dtd', 'bcp47', 'supplemental') {
            [IO.Directory]::CreateDirectory((Join-Path $common $child)) | Out-Null
        }
        [IO.File]::WriteAllText((Join-Path $root 'LICENSE'), $License, $utf8)
        [IO.File]::WriteAllText((Join-Path $common 'dtd/ldml.dtd'), ('<!ATTLIST version cldrVersion CDATA #FIXED "{0}">' -f $Release), $utf8)
        [IO.File]::WriteAllText((Join-Path $common 'supplemental/windowsZones.xml'),
            ('<supplementalData><mapZone other="{0}" type="{1}"/><mapZone other="One" type="Etc/GMT+5"/></supplementalData>' -f
                (ConvertTo-XmlAttribute $WindowsId), (ConvertTo-XmlAttribute $Name)), $utf8)
        [IO.File]::WriteAllText((Join-Path $common 'bcp47/timezone.xml'),
            ('<ldmlBCP47><key name="tz"><type name="test" alias="{0}"/></key></ldmlBCP47>' -f (ConvertTo-XmlAttribute $Aliases)), $utf8)
        return [pscustomobject]@{Root = $root; Common = $common; Output = (Join-Path $root 'generated.inc')}
    }

    function Assert-RejectedFixture($Fixture) {
        { & $generatorPath -CldrCommon $Fixture.Common -OutputPath $Fixture.Output } | Should -Throw
        Test-Path -LiteralPath $Fixture.Output | Should -BeFalse
        # Rejection must also leave an existing output unchanged.
        $existing = Join-Path $Fixture.Root 'existing.inc'
        [IO.File]::WriteAllText($existing, 'preserved output', $utf8)
        { & $generatorPath -CldrCommon $Fixture.Common -OutputPath $existing } | Should -Throw
        [IO.File]::ReadAllText($existing, $utf8) | Should -BeExactly 'preserved output'
    }

    function Assert-InertLicense($Fixture, [string] $License) {
        & $generatorPath -CldrCommon $Fixture.Common -OutputPath $Fixture.Output
        $text = [IO.File]::ReadAllText($Fixture.Output, $utf8)
        $text.Replace("`r`n", '') | Should -Not -Match '[\r\n]'
        foreach ($line in [regex]::Split($License, '\r\n|\r|\n')) {
            $text.Contains('// ' + $line + "`r`n") | Should -BeTrue -Because 'every license line must have its own line-comment prefix'
        }
        $program = Join-Path $Fixture.Root 'LicenseProbe.dpr'
        [IO.File]::WriteAllText($program, ('program LicenseProbe;{0}{{$APPTYPE CONSOLE}}{0}{{$I generated.inc}}{0}begin{0}  if Length(cCronZoneNames) = 0 then Halt(1);{0}end.{0}' -f "`r`n"), $utf8)
        $build = Join-Path $buildParent (Split-Path $Fixture.Root -Leaf)
        [IO.Directory]::CreateDirectory($build) | Out-Null
        $messages = & $compilerPath '-B' '-Q' ("-N0" + $build) ("-E" + $build) $program 2>&1
        $LASTEXITCODE | Should -Be 0 -Because ($messages -join ' ')
    }
}

Describe 'License text remains inert Pascal attribution' {
    It '<Label>' -ForEach @(
        @{Label = 'bare CR'; Kind = 'cr'},
        @{Label = 'lone LF'; Kind = 'lf'},
        @{Label = 'CRLF'; Kind = 'crlf'},
        @{Label = 'mixed CR LF and CRLF'; Kind = 'mixed'},
        @{Label = 'Pascal comment closers and quotes'; Kind = 'closers'}
    ) {
        $license = switch ($Kind) {
            'cr' { 'UNICODE LICENSE V3' + "`r" + $directive + "`r" }
            'lf' { 'UNICODE LICENSE V3' + "`n" + $directive + "`n" }
            'crlf' { 'UNICODE LICENSE V3' + "`r`n" + $directive + "`r`n" }
            'mixed' { 'UNICODE LICENSE V3' + "`r" + '}' + "`n" + '*)' + "`r`n" + $directive + "`r" }
            'closers' { 'UNICODE LICENSE V3 } *) ' + $directive }
        }
        Assert-InertLicense (New-CldrFixture -License $license) $license
    }

    It 'rejects unsupported license character U+<Hex>' -ForEach @(
        @{Hex = '0000'; Code = 0}, @{Hex = '0001'; Code = 1}, @{Hex = '0009'; Code = 9},
        @{Hex = '000B'; Code = 11}, @{Hex = '000C'; Code = 12}, @{Hex = '001F'; Code = 31},
        @{Hex = '007F'; Code = 127}, @{Hex = '0085'; Code = 133}, @{Hex = '009F'; Code = 159},
        @{Hex = '2028'; Code = 8232}, @{Hex = '2029'; Code = 8233}, @{Hex = '202E'; Code = 8238}
    ) {
        $fixture = New-CldrFixture -License ('UNICODE LICENSE V3' + [char]$Code + $directive)
        { & $generatorPath -CldrCommon $fixture.Common -OutputPath $fixture.Output } | Should -Throw '*license*'
        Test-Path -LiteralPath $fixture.Output | Should -BeFalse
        Assert-RejectedFixture $fixture
    }
}

Describe 'Every emitted metadata field has a bounded ASCII alphabet' {
    It 'rejects <Label> in <Field>' -ForEach @(
        @{Field = 'Name'; Label = 'single quote'; Value = "Test/Z'one"},
        @{Field = 'Name'; Label = 'double quote'; Value = 'Test/Z"one'},
        @{Field = 'Name'; Label = 'trailing LF'; Value = "Test/Zone`n"},
        @{Field = 'Name'; Label = 'trailing CR'; Value = "Test/Zone`r"},
        @{Field = 'Name'; Label = 'tab'; Value = "Test/Zone`t"},
        @{Field = 'Name'; Label = 'comment closer'; Value = 'Test/Zone}'},
        @{Field = 'Name'; Label = 'star comment closer'; Value = 'Test/Zone*)'},
        @{Field = 'Name'; Label = 'non ASCII'; Value = ('Test/Z' + [char]0xF3 + 'ne')},
        @{Field = 'Name'; Label = 'overlong'; Value = ('Test/' + ('A' * 251))},
        @{Field = 'WindowsId'; Label = 'single quote'; Value = "O'ne"},
        @{Field = 'WindowsId'; Label = 'double quote'; Value = 'O"ne'},
        @{Field = 'WindowsId'; Label = 'trailing LF'; Value = "One`n"},
        @{Field = 'WindowsId'; Label = 'trailing CR'; Value = "One`r"},
        @{Field = 'WindowsId'; Label = 'comment closer'; Value = 'One}'},
        @{Field = 'WindowsId'; Label = 'star comment closer'; Value = 'One*)'},
        @{Field = 'WindowsId'; Label = 'overlong'; Value = ('A' * 128)},
        @{Field = 'WindowsId'; Label = 'non ASCII'; Value = ('O' + [char]0xF3 + 'ne')},
        @{Field = 'Aliases'; Label = 'quoted mapped alias'; Value = "Test/Zone Q'uote"},
        @{Field = 'Aliases'; Label = 'quoted unmapped alias'; Value = "Unknown/Zone Q'uote"},
        @{Field = 'Aliases'; Label = 'trailing LF'; Value = "Test/Zone Test/Alias`n"},
        @{Field = 'Aliases'; Label = 'comment closer'; Value = 'Test/Zone Test/Alias}'},
        @{Field = 'Aliases'; Label = 'non ASCII unmapped alias'; Value = ('Unknown/Z' + [char]0xF3 + 'ne')},
        @{Field = 'Release'; Label = 'overlong'; Value = ('4' * 64)},
        @{Field = 'Release'; Label = 'non ASCII'; Value = ([string][char]0xFF14 + [char]0xFF19)},
        @{Field = 'Release'; Label = 'extra components'; Value = '49.0.0.0'},
        @{Field = 'Release'; Label = 'trailing LF'; Value = "49`n"}
    ) {
        $parameters = @{}; $parameters[$Field] = $Value
        Assert-RejectedFixture (New-CldrFixture @parameters)
    }
}

Describe 'Valid CLDR behavior and XML safety' {
    It 'preserves aliases, fixed signs, release and notice deterministically' {
        $fixture = New-CldrFixture
        & $generatorPath -CldrCommon $fixture.Common -OutputPath $fixture.Output
        $hash = (Get-FileHash -LiteralPath $fixture.Output).Hash
        $text = [IO.File]::ReadAllText($fixture.Output, $utf8)
        $text | Should -Match "Name: 'Test/Alias'; WindowsId: 'One'"
        $text | Should -Match "Name: 'Etc/GMT\+5'; WindowsId: ''; FixedOffsetSeconds: -18000"
        $text | Should -Match 'CLDR 49'
        $text | Should -Match '// UNICODE LICENSE V3'
        & $generatorPath -CldrCommon $fixture.Common -OutputPath $fixture.Output
        (Get-FileHash -LiteralPath $fixture.Output).Hash | Should -BeExactly $hash
    }

    It 'rejects conflicting mappings and case collisions' {
        foreach ($name in 'Test/Zone', 'test/zone') {
            $fixture = New-CldrFixture
            $path = Join-Path $fixture.Common 'supplemental/windowsZones.xml'
            [IO.File]::WriteAllText($path, ('<root><mapZone other="One" type="Test/Zone"/><mapZone other="Two" type="{0}"/></root>' -f $name), $utf8)
            Assert-RejectedFixture $fixture
        }
    }

    It 'does not expand external XML entities' {
        $fixture = New-CldrFixture
        $uri = ([uri](Join-Path $fixture.Root 'LICENSE')).AbsoluteUri
        [IO.File]::WriteAllText((Join-Path $fixture.Common 'supplemental/windowsZones.xml'),
            ('<!DOCTYPE root [<!ENTITY probe SYSTEM "{0}">]><root><mapZone type="&probe;" other="One"/></root>' -f $uri), $utf8)
        Assert-RejectedFixture $fixture
    }
}

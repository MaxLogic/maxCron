[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Pester container parameters are read in isolated test blocks.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'BeforeAll values are consumed by separate Pester It and AfterAll blocks.')]
param(
    [Parameter(Mandatory = $true)][string]$Generator,
    [Parameter(Mandatory = $true)][string]$ScratchRoot,
    [string]$Gate = (Join-Path $PSScriptRoot '..\..\build-and-run-tests-fpc.bat')
)

BeforeAll {
    $ErrorActionPreference = 'Stop'
    $units = 'TestCronInstant', 'TestCronParsing', 'TestCronInvalidCorpus', 'TestCronUtilsCorpus',
        'TestCronFuzzOracle', 'TestCronQuery', 'TestIntervalPlan', 'TestDeadlineQueue', 'TestTimeZoneRules',
        'TestTimeZoneTzif', 'TestCronTextParity', 'TestFpcShims', 'TestScheduleNext', 'TestHashJitter',
        'TestCalendarTimeZone', 'TestNamedTimeZones', 'TestLocalZoneTzif', 'TestTimeBoundaries', 'TestMisfireOnTime',
        'TestCronPhaseDifferential', 'TestLocalZoneOs', 'TestTimeZoneWindows', 'TestWindowsZoneOracle',
        'TestValidityZones', 'TestLocalOverlap', 'TestRestartCatchUp'
    $repo = Join-Path $ScratchRoot 'registry-source'
    New-Item -ItemType Directory -Path (Join-Path $repo 'tests\unit'), (Join-Path $repo 'tests\fpc') -Force | Out-Null
    foreach ($unit in $units) {
        $subdir = if ($unit -eq 'TestFpcShims') { 'fpc' } else { 'unit' }
        [IO.File]::WriteAllText((Join-Path $repo "tests\$subdir\$unit.pas"), @"
unit $unit;
interface
type
  [TestFixture]
  TBase = class
    [Test] procedure Base;
  end;
implementation
end.
"@)
    }
    $target = Join-Path $repo 'tests\unit\TestCronInstant.pas'
    $original = [IO.File]::ReadAllText($target)
}

Describe 'Registration must consume active fixture and test declarations' {
    It '<Name>' -ForEach @(
        @{ Name = 'ELSE branch of IFNDEF'; Extra = "[TestFixture]`nTExtra = class`n[Test] procedure Control;`n{`$IFNDEF FPC}`n[Test] procedure DelphiOnly;`n{`$ELSE}`n[Test] procedure Extra;`n{`$ENDIF}`nend;"; Expected = 0 },
        @{ Name = 'inline fixture'; Extra = "[TestFixture] TExtra = class`n[Test] procedure Extra;`nend;"; Expected = 0 },
        @{ Name = 'nested branches'; Extra = "{`$IFDEF FPC}`n{`$IFNDEF FPC}`n[TestFixture] TWrong = class`n[Test] procedure Wrong;`nend;`n{`$ELSE}`n[TestFixture] TExtra = class`n{`$IFDEF FPC}`n[Test] procedure Extra;`n{`$ELSE}`n[Test] procedure Wrong;`n{`$ENDIF}`nend;`n{`$ENDIF}`n{`$ENDIF}"; Expected = 0 },
        @{ Name = 'directives on same line'; Extra = "{`$IFNDEF FPC}[TestFixture] TWrong = class{`$ELSE}[TestFixture] TExtra = class{`$ENDIF}`n[Test] procedure Extra;`nend;"; Expected = 0 },
        @{ Name = 'comments are not attributes'; Extra = "// [TestFixture] TWrong = class`n(* [Test] procedure Wrong; *)`n[TestFixture] TExtra = class`n[Test] procedure Extra; // [Test] Wrong`nend;"; Expected = 0 },
        @{ Name = 'unsupported fixture declaration'; Extra = '[TestFixture] TExtra = record end;'; Expected = 3 },
        @{ Name = 'test outside fixture'; Extra = '[Test] procedure Extra;'; Expected = 3 },
        @{ Name = 'unsupported test function'; Extra = "[TestFixture] TExtra = class`n[Test] function Extra: Boolean;`n[Test] procedure Other;`nend;"; Expected = 3 },
        @{ Name = 'unknown conditional'; Extra = "{`$IFDEF SOMETHING_UNKNOWN}`n[TestFixture] TExtra = class`n[Test] procedure Extra;`nend;`n{`$ENDIF}"; Expected = 3 },
        @{ Name = 'duplicate ELSE'; Extra = "{`$IFDEF FPC}`n{`$ELSE}`n{`$ELSE}`n{`$ENDIF}"; Expected = 3 },
        @{ Name = 'dangling fixture'; Extra = '[TestFixture]'; Expected = 3 }
    ) {
        $output = Join-Path $ScratchRoot ($Name.Replace(' ', '-') + '.inc')
        [IO.File]::WriteAllText($target, $original.Replace('implementation', $Extra + "`nimplementation"))
        $messages = & $Generator $repo $output 2>&1
        $LASTEXITCODE | Should -Be $Expected -Because ($messages -join ' ')
        if ($Expected -eq 0) {
            $registry = [IO.File]::ReadAllText($output)
            $registry | Should -Match "RegisterTest\('TestCronInstant.TExtra.Extra',"
            $registry | Should -Not -Match 'TWrong|\.Wrong|DelphiOnly'
            $count = $units.Count + $(if ($Name -eq 'ELSE branch of IFNDEF') { 2 } else { 1 })
            $registry | Should -Match "cGeneratedTestCount = $count;"
        } else {
            Test-Path -LiteralPath $output | Should -BeFalse
        }
    }
}

Describe 'The gate rejects output aliases before writing' {
    BeforeAll {
        $source = Join-Path $ScratchRoot 'path-source'
        $helperDir = Join-Path $source 'tests\fpc'
        New-Item -ItemType Directory -Path $helperDir -Force | Out-Null
        Copy-Item -LiteralPath $Gate -Destination (Join-Path $source 'build-and-run-tests-fpc.bat')
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Check-OutputPath.ps1') -Destination $helperDir
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Run-FpcGate.ps1') -Destination $helperDir
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\RosterManifest.ps1') -Destination (Join-Path $source 'tests\RosterManifest.ps1')
        [IO.File]::WriteAllText((Join-Path $helperDir 'maxCronFpcCompileCheck.dpr'), 'program Broken; begin invalid syntax end.')
        $junction = Join-Path $ScratchRoot 'source-junction'
        New-Item -ItemType Junction -Path $junction -Target $source | Out-Null
        $oldOutput = $env:MAXCRON_FPC_OUT
    }
    AfterAll { $env:MAXCRON_FPC_OUT = $oldOutput }
    It 'rejects <Name> and creates no output' -ForEach @(
        @{ Name = 'direct child'; Alias = 'direct'; Child = $true },
        @{ Name = 'junction itself'; Alias = 'junction'; Child = $false },
        @{ Name = 'junction child'; Alias = 'junction'; Child = $true }
    ) {
        $destination = if ($Alias -eq 'direct') { $source } else { $junction }
        if ($Child) { $destination = Join-Path $destination 'forbidden-output\child' }
        $env:MAXCRON_FPC_OUT = $destination
        $messages = & $env:ComSpec /d /c (Join-Path $source 'build-and-run-tests-fpc.bat') 2>&1
        $LASTEXITCODE | Should -Be 2 -Because ($messages -join ' ')
        Test-Path -LiteralPath (Join-Path $source 'forbidden-output') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $source 'check-public') | Should -BeFalse
    }
    It 'rejects a symbolic link to source and its missing child' {
        $link = Join-Path $ScratchRoot 'source-symlink'
        New-Item -ItemType SymbolicLink -Path $link -Target $source | Out-Null
        foreach ($destination in @($link, (Join-Path $link 'symlink-output\child'))) {
            $env:MAXCRON_FPC_OUT = $destination
            $messages = & $env:ComSpec /d /c (Join-Path $source 'build-and-run-tests-fpc.bat') 2>&1
            $LASTEXITCODE | Should -Be 2 -Because ($messages -join ' ')
        }
        Test-Path -LiteralPath (Join-Path $source 'symlink-output') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $source 'check-public') | Should -BeFalse
    }
    It 'rejects a SUBST alias and its missing child' {
        $drive = @('Z:', 'Y:', 'X:', 'W:') | Where-Object { -not (Test-Path -LiteralPath ($_ + '\')) } | Select-Object -First 1
        $drive | Should -Not -BeNullOrEmpty
        & subst.exe $drive $source
        $LASTEXITCODE | Should -Be 0
        try {
            foreach ($destination in @(($drive + '\'), ($drive + '\subst-output\child'))) {
                $env:MAXCRON_FPC_OUT = $destination
                $messages = & $env:ComSpec /d /c (Join-Path $source 'build-and-run-tests-fpc.bat') 2>&1
                $LASTEXITCODE | Should -Be 2 -Because ($messages -join ' ')
            }
        } finally { & subst.exe $drive /d }
        Test-Path -LiteralPath (Join-Path $source 'subst-output') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $source 'check-public') | Should -BeFalse
    }
    It 'checks the available short-path spelling and its child' {
        $shortPath = (& $env:ComSpec /d /c "for %I in (`"$source`") do @echo %~sI" | Out-String).Trim()
        $shortPath | Should -Not -BeNullOrEmpty
        [IO.File]::WriteAllText((Join-Path $ScratchRoot 'short-path.txt'), "Long=$source`r`nShort=$shortPath`r`n")
        foreach ($destination in @($shortPath, (Join-Path $shortPath 'short-output\child'))) {
            $env:MAXCRON_FPC_OUT = $destination
            $messages = & $env:ComSpec /d /c (Join-Path $source 'build-and-run-tests-fpc.bat') 2>&1
            $LASTEXITCODE | Should -Be 2 -Because ($messages -join ' ')
        }
        Test-Path -LiteralPath (Join-Path $source 'short-output') | Should -BeFalse
    }
    It 'allows an external junction destination' {
        $external = Join-Path $ScratchRoot 'external-output'
        New-Item -ItemType Directory -Path $external -Force | Out-Null
        $externalAlias = Join-Path $ScratchRoot 'external-junction'
        New-Item -ItemType Junction -Path $externalAlias -Target $external | Out-Null
        $env:MAXCRON_FPC_OUT = Join-Path $externalAlias 'allowed-output'
        $messages = & $env:ComSpec /d /c (Join-Path $source 'build-and-run-tests-fpc.bat') 2>&1
        # The deliberate compile error proves the safe destination was accepted.
        $LASTEXITCODE | Should -Be 3 -Because ($messages -join ' ')
        $runs = @(Get-ChildItem -LiteralPath (Join-Path $external 'allowed-output') -Directory)
        $runs.Count | Should -Be 1
        $runs[0].Name | Should -Match '^run-[a-f0-9]{32}$'
        Test-Path -LiteralPath (Join-Path $runs[0].FullName 'check-public\build.log') | Should -BeTrue
    }
}

Describe 'Fixture parity compares names and binds the Delphi source snapshot' {
    BeforeAll {
        $parityRepo = Join-Path $ScratchRoot 'parity-source'
        New-Item -ItemType Directory -Path (Join-Path $parityRepo 'tests\unit') -Force | Out-Null
        $paritySource = Join-Path $parityRepo 'tests\unit\TestLocalZoneOs.pas'
        [IO.File]::WriteAllText($paritySource, 'source as exported by Delphi')
        $sourceHash = (Get-FileHash -LiteralPath $paritySource -Algorithm SHA256).Hash.ToLowerInvariant()
        $manifest = Join-Path $ScratchRoot 'delphi-names.txt'
        [IO.File]::WriteAllLines($manifest, @(
            ('# SHA256 tests/unit/TestLocalZoneOs.pas ' + $sourceHash),
            'TestLocalZoneOs.TTestLocalZoneOs.Shared',
            'TestLocalZoneOs.TTestLocalZoneOs.MatchesRtlLocal'
        ), [Text.UTF8Encoding]::new($true))
        New-Item -ItemType Directory -Path (Join-Path $parityRepo 'tests\fpc') -Force | Out-Null
        $shimSource = Join-Path $parityRepo 'tests\fpc\TestFpcShims.pas'
        [IO.File]::WriteAllText($shimSource, 'independently exported FPC-only source')
        $shimHash = (Get-FileHash -LiteralPath $shimSource -Algorithm SHA256).Hash.ToLowerInvariant()
        $shimManifest = Join-Path $ScratchRoot 'fpc-only-names.txt'
        [IO.File]::WriteAllLines($shimManifest, @(
            ('# SHA256 tests/fpc/TestFpcShims.pas ' + $shimHash),
            'TestFpcShims.TTestFpcShims.Probe'
        ), [Text.UTF8Encoding]::new($true))
        $parityCheck = Join-Path $PSScriptRoot 'Check-FixtureParity.ps1'
        $windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    }
    It '<Name>' -ForEach @(
        @{ Name = 'accepts matching names'; Names = @('TestLocalZoneOs.TTestLocalZoneOs.Shared', 'TestFpcShims.TTestFpcShims.Probe'); Stale = $false; Expected = 0 },
        @{ Name = 'rejects an omitted test'; Names = @('TestFpcShims.TTestFpcShims.Probe'); Stale = $false; Expected = 5 },
        @{ Name = 'rejects equal counts with different names'; Names = @('TestLocalZoneOs.TTestLocalZoneOs.Wrong', 'TestFpcShims.TTestFpcShims.Probe'); Stale = $false; Expected = 5 },
        @{ Name = 'rejects a stale source snapshot'; Names = @('TestLocalZoneOs.TTestLocalZoneOs.Shared', 'TestFpcShims.TTestFpcShims.Probe'); Stale = $true; Expected = 5 },
        @{ Name = 'rejects an omitted FPC-only test'; Names = @('TestLocalZoneOs.TTestLocalZoneOs.Shared'); Stale = $false; Expected = 5 },
        @{ Name = 'rejects a renamed FPC-only test'; Names = @('TestLocalZoneOs.TTestLocalZoneOs.Shared', 'TestFpcShims.TTestFpcShims.Renamed'); Stale = $false; Expected = 5 },
        @{ Name = 'rejects an extra FPC-only test'; Names = @('TestLocalZoneOs.TTestLocalZoneOs.Shared', 'TestFpcShims.TTestFpcShims.Probe', 'TestFpcShims.TTestFpcShims.Extra'); Stale = $false; Expected = 5 }
    ) {
        [IO.File]::WriteAllText($paritySource, $(if ($Stale) { 'changed after Delphi export' } else { 'source as exported by Delphi' }))
        $registry = Join-Path $ScratchRoot ($Name.Replace(' ', '-') + '-registry.inc')
        [IO.File]::WriteAllLines($registry, @($Names | ForEach-Object { "RegisterTest('$_', 'fixture', @Test);" }), [Text.UTF8Encoding]::new($true))
        $messages = & $windowsPowerShell -NoProfile -NonInteractive -File $parityCheck -Registry $registry -DelphiNames $manifest -FpcOnlyNames $shimManifest -Repository $parityRepo 2>&1
        $LASTEXITCODE | Should -Be $Expected -Because ($messages -join ' ')
    }
}

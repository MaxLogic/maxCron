"""Guard-removal mutation for negative matrix case copies only.

Remove only roster source/identity/selection/positive-count guards. Keep the
actual fixtures, registration, compilation, execution, ordinary assertion
failures, subprocess exits, receipts, timeouts and matrix classifier intact.
"""
from pathlib import Path


def write(path, text):
    Path(path).write_bytes(text.replace('\r\n', '\n').replace('\n', '\r\n').encode('utf-8'))


def disable_contract(work):
    work = Path(work)
    if work.name == 'template':
        raise RuntimeError('Contract mutation cannot modify discovery or positive-control inputs')
    marker = work / 'CONTRACT-DISABLED-FOR-RED.txt'
    if marker.exists():
        return
    path = work / 'tests/TestRoster.pas'
    source = path.read_text(encoding='utf-8-sig')
    start = source.index('procedure BeginRoster(', source.index('implementation'))
    end = source.index('procedure RecordRosterTest(', start)
    source = source[:start] + '''procedure BeginRoster(const aEntry: string);
begin
  gEntry := aEntry;
  gExpected := nil;
  gExecuted := nil;
end;

procedure CheckRosterNames(const aNames: TArray<string>);
begin
  gExpected := Copy(aNames, 0, Length(aNames));
end;

''' + source[end:]
    start = source.index('procedure EndRoster(', source.index('implementation'))
    end = source.index('{$IFDEF FPC}\ninitialization', start)
    source = source[:start] + '''procedure EndRoster(const aFound, aPassed, aFailed, aErrored, aIgnored: Integer);
begin
end;

function ExpectedRosterCount: Integer;
begin
  Result := Length(gExecuted);
end;

''' + source[end:]
    write(path, source)

    path = work / 'tests/RosterManifest.ps1'
    source = path.read_text(encoding='utf-8-sig')
    start = source.index('function Read-RosterManifest {')
    source = source[:start] + '''function Read-RosterManifest {
    param([string]$Repository, [string]$Entry)
    $lines = @(Get-Content -Encoding UTF8 -LiteralPath (Join-Path $Repository ('tests/rosters/' + $Entry + '.txt')))
    return [pscustomobject]@{ Names = [string[]]@($lines | Where-Object { $_ -and -not $_.StartsWith('#') }) }
}

function Assert-RosterIdentity {
    param([string[]]$Expected, [AllowEmptyCollection()][string[]]$Actual, [string]$Name = 'identity')
}
'''
    write(path, source)
    path = work / 'tests/fpc/Check-FixtureParity.ps1'
    write(path, '''param([string]$Registry, [string]$DelphiNames, [string]$Repository, [string]$FpcOnlyNames)
exit 0
''')
    path = work / 'tests/Reject-RosterSelection.ps1'
    write(path, 'param()\nexit 0\n')
    path = work / 'tests/fpc/Run-FpcGate.ps1'
    source = path.read_text(encoding='utf-8-sig')
    original = """    if ($testArguments.Count -ne 0) {
        throw (New-RosterViolation count 'FPC qualification requires the complete roster; test selection arguments are not accepted.' arguments)
    }"""
    if original not in source:
        raise RuntimeError('Cannot locate exact FPC selection contract to remove')
    source = source.replace(original, '    $testArguments = @()')
    source = source.replace('$counts.Found -le 0 -or ', '')
    write(path, source)
    path = work / 'tests/Run-DelphiRosters.ps1'
    source = path.read_text(encoding='utf-8-sig').replace('$counts.Found -le 0 -or ', '')
    write(path, source)
    for target in ['maxCronTests', 'maxCronStressTests', 'maxCronVclTests']:
        path = work / 'tests' / (target + '.dpr')
        source = path.read_text(encoding='utf-8-sig')
        source = source.replace(' or (Results.TestCount <= 0)', '')
        write(path, source)
    marker.write_text('Only independent roster, source, argument and empty-selection guards removed.\n'
                      'Ordinary assertions, builds, process exits and classifier unchanged.\n', encoding='utf-8')

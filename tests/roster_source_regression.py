"""Exhaustive stale include/data checks through the actual native/PS loaders."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--repository', required=True, type=Path)
    parser.add_argument('--scratch', required=True, type=Path)
    args = parser.parse_args()
    repo, out = args.repository.resolve(), args.scratch.resolve()
    if out.exists() or out == repo or repo in out.parents:
        raise RuntimeError('Use a fresh external scratch root')
    out.mkdir(parents=True)
    source = out / 'source'
    source.mkdir()
    for path in repo.glob('*.inc'):
        shutil.copyfile(path, source / path.name)
    for path in repo.glob('build-and-run-tests*'):
        if path.is_file():
            shutil.copy2(path, source / path.name)
    def ignore_outputs(directory, names):
        if Path(directory).is_relative_to(repo / 'tests/data'):
            return [name for name in names if name == '__pycache__' or Path(name).suffix in ('.pyc', '.pyo')]
        return shutil.ignore_patterns('Win32', 'Win64', 'matrix-dcu', '__pycache__', '__recovery', '*.exe', '*.dcu', '*.ppu', '*.o')(directory, names)
    shutil.copytree(repo / 'tests', source / 'tests', ignore=ignore_outputs)
    assets = sorted(list(source.glob('*.inc')) + list((source / 'tests').rglob('*.inc')) + [p for p in (source / 'tests/data').rglob('*') if p.is_file()])
    relative = [path.relative_to(source).as_posix() for path in assets]
    (out / 'assets.txt').write_text('\n'.join(relative), encoding='utf-8')
    (out / 'assets.json').write_text(json.dumps({name: hashlib.sha256((source / name).read_bytes()).hexdigest() for name in relative}, indent=2))
    env = os.environ.copy()
    env['MAXCRON_TEST_ROOT'] = str(source)
    env['ROSTER_ASSET_LIST'] = str(out / 'assets.txt')

    def run(label, command):
        with (out / (label + '.log')).open('wb') as log:
            result = subprocess.run(list(map(str, command)), cwd=out, env=env, stdout=log,
                                    stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW, check=False)
        text = (out / (label + '.log')).read_text(errors='replace')
        return dict(exit=result.returncode, log=str(out / (label + '.log')), text=text)

    bds = Path(r'C:\Program Files (x86)\Embarcadero\Studio\23.0')
    rows = []
    for platform in ('Win32', 'Win64', 'FPC'):
        entries = ['FpcDefault', 'FpcLong', 'FpcSmoke', 'FpcSmokeHeap'] if platform == 'FPC' else ['DelphiUnit', 'DelphiLong', 'DelphiStress', 'DelphiVcl']
        build = out / platform
        build.mkdir()
        declaration = ', '.join("'" + name + "'" for name in entries)
        program = r"""program SourceProbe;
{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ELSE}{$APPTYPE CONSOLE}{$ENDIF}
uses Classes, SysUtils, TestRoster in 'COMMON';
const cEntries: array[0..3] of string = (ENTRIES);
var
  lAssets: TStringList;
  lAsset, lEntry, lRoot: string;
  lStream: TFileStream;
  lSize: Int64;
  lByte: Byte;
  lRejected, lAccepted: Integer;
begin
  lRejected := 0; lAccepted := 0;
  lRoot := IncludeTrailingPathDelimiter(GetEnvironmentVariable('MAXCRON_TEST_ROOT'));
  lAssets := TStringList.Create;
  try
    lAssets.LoadFromFile(GetEnvironmentVariable('ROSTER_ASSET_LIST'));
    for lEntry in cEntries do BeginRoster({$IFDEF FPC}UnicodeString({$ENDIF}lEntry{$IFDEF FPC}){$ENDIF});
    for lAsset in lAssets do
    begin
      lStream := TFileStream.Create(lRoot + lAsset, fmOpenReadWrite);
      lSize := lStream.Size;
      try
        lStream.Position := lSize;
        lByte := 0;
        lStream.WriteBuffer(lByte, 1);
      finally
        lStream.Free;
      end;
      try
        for lEntry in cEntries do
        begin
          try
            BeginRoster({$IFDEF FPC}UnicodeString({$ENDIF}lEntry{$IFDEF FPC}){$ENDIF});
            Inc(lAccepted);
            WriteLn('ACCEPTED ', lEntry, ' ', lAsset);
          except
            on E: Exception do
              if Pos('stale', LowerCase(E.Message)) > 0 then Inc(lRejected)
              else raise;
          end;
        end;
      finally
        lStream := TFileStream.Create(lRoot + lAsset, fmOpenReadWrite);
        try lStream.Size := lSize; finally lStream.Free; end;
      end;
    end;
    WriteLn('SOURCE_BINDING rejected=', lRejected, ' accepted=', lAccepted, ' expected=', lAssets.Count * 4);
    if lAccepted <> 0 then ExitCode := 1;
  finally
    lAssets.Free;
  end;
end.
""".replace('COMMON', str(source / 'tests/TestRoster.pas')).replace('ENTRIES', declaration)
        path = build / 'SourceProbe.dpr'
        path.write_bytes(program.replace('\n', '\r\n').encode())
        if platform == 'FPC':
            binpath = Path(r'F:\Tools\fpc-trunk\bin\x86_64-win64')
            command = [binpath / 'fpc.exe', '-n', '@' + str(binpath / 'fpc.cfg'), '-FD' + str(binpath), r'-FuF:\Tools\fpc-trunk\units\x86_64-win64\*', '-Fu' + str(source), '-Fi' + str(source), '-FU' + str(build), '-FE' + str(build), '-O2', '-Sew', path]
        else:
            command = [bds / ('bin/dcc32.exe' if platform == 'Win32' else 'bin/dcc64.exe'), '-B', '-Q', '-NSSystem;Winapi;System.Win', '-I' + str(source), '-N0' + str(build), '-E' + str(build), path]
        compiled = run(platform + '-build', command)
        if compiled['exit'] != 0:
            raise RuntimeError('A compiler failure is not stale-source proof: ' + compiled['log'])
        result = run(platform + '-run', [build / 'SourceProbe.exe'])
        if result['exit'] not in (0, 1) or 'SOURCE_BINDING ' not in result['text']:
            raise RuntimeError('Native source binding control failed: ' + result['log'])
        rows.append(dict(platform=platform, **result))
    ps = out / 'source-check.ps1'
    ps.write_text(r"""$ErrorActionPreference='Stop'
. 'HELPER'
$root='SOURCE'
$entries=@('DelphiDefaultGate','FpcDefaultGate','FpcLongGate','FpcOnly')
$assets=@(Get-Content -LiteralPath 'ASSETS')
$rejected=0;$accepted=0
foreach($entry in $entries){$null=Read-RosterManifest -Repository $root -Entry $entry}
foreach($asset in $assets){
  $path=Join-Path $root $asset
  $stream=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite)
  $size=$stream.Length
  try{$stream.Position=$size;$stream.WriteByte(0)}finally{$stream.Dispose()}
  try{
    foreach($entry in $entries){
      try{$null=Read-RosterManifest -Repository $root -Entry $entry;$accepted++;Write-Output ('ACCEPTED '+$entry+' '+$asset)}
      catch{if($_.Exception.Message -match 'stale'){$rejected++}else{throw}}
    }
  }finally{$stream=[IO.File]::OpenWrite($path);try{$stream.SetLength($size)}finally{$stream.Dispose()}}
}
Write-Output ('SOURCE_BINDING rejected='+$rejected+' accepted='+$accepted+' expected='+($assets.Count*4))
if($accepted){exit 1}
""".replace('HELPER', str(source / 'tests/RosterManifest.ps1')).replace('SOURCE', str(source)).replace('ASSETS', str(out / 'assets.txt')))
        # Preserve the diagnostic label after replacing the SOURCE placeholder.
    ps.write_text(ps.read_text().replace(str(source) + '_BINDING', 'SOURCE_BINDING'))
    result = run('PS-run', ['powershell.exe', '-NoProfile', '-NonInteractive', '-File', ps])
    if result['exit'] not in (0, 1) or 'SOURCE_BINDING ' not in result['text']:
        raise RuntimeError('PowerShell source binding control failed: ' + result['log'])
    rows.append(dict(platform='PS', **result))
    restored = all(hashlib.sha256((source / name).read_bytes()).hexdigest() == digest for name, digest in json.loads((out / 'assets.json').read_text()).items())
    if not restored:
        raise RuntimeError('Mutated source asset was not restored')
    (out / 'results.json').write_text(json.dumps(dict(assets=len(assets), rows=rows, restored=True), indent=2))
    return 0 if all(row['exit'] == 0 for row in rows) else 1


if __name__ == '__main__':
    raise SystemExit(main())

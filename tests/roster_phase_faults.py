"""Native phase-boundary failure table; invokes the actual PowerShell child runner."""
import argparse
import json
import os
import re
from pathlib import Path
import subprocess
from roster_regression_contract import Rejection, classify_rejection, MatrixInfrastructureError


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--scratch', type=Path, required=True)
    parser.add_argument('--compiler', type=Path, required=True)
    args = parser.parse_args()
    out = args.scratch.resolve()
    out.mkdir(parents=True, exist_ok=False)
    repo = Path(__file__).resolve().parent.parent
    source = out / 'PhaseFault.dpr'
    source.write_text("""program PhaseFault;
{$APPTYPE CONSOLE}
uses System.SysUtils, Winapi.Windows;
var lPointer: PInteger;
begin
  SetErrorMode(SEM_FAILCRITICALERRORS or SEM_NOGPFAULTERRORBOX);
  if ParamStr(1)='timeout' then Sleep(10000)
  else if ParamStr(1)='crash' then begin lPointer:=nil; lPointer^:=17; end
  else if ParamStr(1)='misleading' then begin
    WriteLn('Delphi/FPC test names differ: misleading output');
    WriteLn('ROSTER_PHASE phase=roster name=Probe native_exit=5');
    WriteLn('ROSTER_REJECTED reason=renamed detail=misleading output');
    Halt(0);
  end else Halt(37);
end.
""", encoding='utf-8', newline='\r\n')
    with (out / 'build.log').open('wb') as log:
        result = subprocess.run([str(args.compiler), '-B', '-Q', '-NSSystem;Winapi', '-N0' + str(out), '-E' + str(out), str(source)], stdout=log, stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW)
    if result.returncode:
        raise RuntimeError('Fault fixture compiler failure is not proof')
    rows = []
    for process in ('compiler','linker','generator','parity','runner','roster-helper'):
        for mode in ('nonzero','crash','timeout','misleading'):
            phase = 'build' if process in ('compiler','linker') else 'roster-check' if process == 'roster-helper' else process
            name = process
            ps = out / (process + '-' + mode + '.ps1')
            ps.write_text("$ErrorActionPreference='Stop'\n. '" + str(repo / 'tests/RosterManifest.ps1') + "'\ntry {\n$result=Invoke-RosterChild -Executable '" + str(out / 'PhaseFault.exe') + "' -ArgumentList @('" + mode + "') -WorkingDirectory '" + str(out) + "' -Phase '" + phase + "' -Name '" + name + "' -TimeoutMs 500\nif($result.ExitCode -ne 0){if(Test-RosterRejection $result.ExitCode $result.Text){exit 5};throw ('Child failed '+$result.ExitCode)}\nexit 0\n} catch {exit (Complete-RosterFailure $_.Exception)}\n", encoding='utf-8-sig')
            command = ['powershell.exe','-NoProfile','-NonInteractive','-File',str(ps)]
            with (out / (process + '-' + mode + '.log')).open('wb') as log:
                result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW)
            text = (out / (process + '-' + mode + '.log')).read_text(encoding='utf-8', errors='replace')
            completions = re.findall(r'(?m)^ROSTER_PHASE phase=' + re.escape(phase) + r' name=' + re.escape(name) + r' native_exit=(-?\d+)\r?$', text)
            if len(completions) != 1 or (mode != 'misleading' and int(completions[0]) == 0):
                raise AssertionError('Injected fault did not produce a native failure: ' + text)
            if mode == 'nonzero' and int(completions[0]) != 37:
                raise AssertionError('Fault exit37 was changed: ' + text)
            if mode == 'misleading' and (int(completions[0]) != 0 or 'ROSTER_REJECTED reason=renamed' not in text):
                raise AssertionError('Misleading success was not observed: ' + text)
            if (mode == 'timeout') != ('Subprocess timeout:' in text):
                raise AssertionError('Fault mode was not observed: ' + text)
            try:
                rejected = classify_rejection(result.returncode, text, Rejection(5,'renamed',(),'runtime','Probe'))
                matrix_exit = 0 if rejected else 1
            except MatrixInfrastructureError:
                rejected, matrix_exit = False, 4
            if rejected or matrix_exit == 0 or 'ROSTER_PHASE phase=' + phase + ' name=' + name + ' native_exit=' not in text:
                raise AssertionError((process,mode,result.returncode,text))
            rows.append(dict(process=process,mode=mode,native_exit=int(completions[0]),wrapper_exit=result.returncode,matrix_exit=matrix_exit,rejected=rejected,log=str(out/(process+'-'+mode+'.log'))))
            (out/'results.json').write_text(json.dumps(rows,indent=2),encoding='utf-8')
    print('PHASE_FAILURE_TABLE passed=' + str(len(rows)) + ' expected=24')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

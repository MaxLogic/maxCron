"""Exercise actual runners/wrappers with small native membership controls."""
import argparse
from fpc_toolchain import get_fpc_command
import hashlib
import json
import os
import locale
import sys
from roster_regression_contract import (MatrixInfrastructureError, expected_rejection,
    classify_rejection, instrument_builds, refresh_stamps, build_records,
    DEFAULT_BUILDS, FPC_ALL_BUILDS)
from pathlib import Path
from roster_contract_mutation import disable_contract
import re
import shutil
import subprocess
import time


def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(text.replace('\r\n', '\n').replace('\n', '\r\n').encode('utf-8'))


def append_runner_receipt(log, text, route, code):
    # Native stdout/stderr need not end with a newline (heaptrc can truncate
    # its final trace). Keep our completion receipt on a separate line.
    receipt = '\nROSTER_PHASE phase=runner name=' + route + ' native_exit=' + str(code) + '\n'
    with Path(log).open('ab') as output:
        output.write(receipt.encode('utf-8'))
    return text + receipt


def add_unlisted_test(source, fixture_name):
    source, count = re.subn(r'(\[TestFixture\]\s*' + re.escape(fixture_name) + r'\s*=\s*class\s*\n\s*public\n)',
                            r'\g<1>    [Test] procedure Unlisted;\n', source, count=1)
    if count != 1:
        raise MatrixInfrastructureError('Cannot locate fixture declaration for extra-test variant')
    # A unit's implementation uses/type/var sections precede method bodies.
    # Insert before initialization (if any), otherwise before the unit end.
    ending = re.search(r'(?m)^(?:initialization|finalization|end\.)\s*$', source)
    if ending is None:
        raise MatrixInfrastructureError('Cannot locate unit ending for extra-test variant')
    return source[:ending.start()] + 'procedure ' + fixture_name + '.Unlisted;\nbegin\nend;\n\n' + source[ending.start():]


def prepare_case(template, scratch, route, family, variant):
    label = route + '-' + family + '-' + variant
    work = scratch / label
    shutil.copytree(template, work, ignore=shutil.ignore_patterns('*.exe', '*.dcu', '*.ppu', '*.o'))
    fpc = route.startswith('fpc-')
    smoke_route = route.startswith('smoke')
    partial = 'TestSharedRoster.TTestSharedRoster.Plain'
    if family == 'fpc-only':
        partial = 'TestFpcShims.TTestFpcShims.LifetimeLifo' if fpc else 'TestFpcShims.TTestFpcShims.Plain'
    if smoke_route:
        partial = 'smoke.0.' + ('cron-fires' if family == 'shared' else 'interval-fires')
    selector = ['--run:NoSuchFixture.NoSuchTest'] if variant == 'unknown-selector' else ['--run:' + partial] if variant == 'partial-selector' else []
    if smoke_route:
        path = work / 'tests/fpc/maxCronFpcSmoke.dpr'
        source = path.read_text(encoding='utf-8-sig')
        name = 'cron-fires' if family == 'shared' else 'interval-fires'
        if variant == 'renamed-fixture':
            source = source.replace("lPrefix + '" + name + "'", "lPrefix + 'renamed-" + name + "'")
        elif variant == 'removed-test':
            source = source.replace("  Check(True, lPrefix + '" + name + "');\n", '')
        elif variant == 'removed-import':
            source = source.replace('    SmokeMode(imThread);\n', '')
        elif variant == 'extra-test':
            source = source.replace("  Check(True, lPrefix + '" + name + "');", "  Check(True, lPrefix + '" + name + "');\n  Check(True, lPrefix + 'extra-" + name + "');")
        write(path, source)
    else:
        unit = 'TestSharedRoster' if family == 'shared' else 'TestFpcShims'
        path = work / ('tests/fpc/' if fpc and family == 'fpc-only' else 'tests/unit/') / (unit + '.pas')
        source = path.read_text(encoding='utf-8-sig')
        fixture_name = re.search(r'\[TestFixture\]\s*(\w+)\s*=\s*class', source).group(1)
        if variant == 'renamed-fixture':
            source = source.replace(fixture_name, fixture_name + 'Renamed')
            if not fpc:
                for runner in ('maxCronTests', 'maxCronStressTests', 'maxCronVclTests'):
                    path_runner = work / 'tests' / (runner + '.dpr')
                    write(path_runner, path_runner.read_text(encoding='utf-8-sig').replace('RegisterTestFixture(' + fixture_name + ')', 'RegisterTestFixture(' + fixture_name + 'Renamed)'))
        elif variant == 'removed-test':
            source = re.sub(r'\[Test\]', '', source, count=1)
        elif variant == 'extra-test':
            source = add_unlisted_test(source, fixture_name)
        elif variant == 'removed-import':
            if fpc:
                runner = work / 'tests/fpc/maxCronFpcTests.dpr'
                content = runner.read_text(encoding='utf-8-sig')
                content = re.sub(r'(?m)^  ' + unit + r" in '[^']+'[,;]\n", '', content)
                content = re.sub(r',\s*\n(?=\{\$I maxCronFpcRegistry.inc\})', ';\n', content)
                write(runner, content)
                gen = work / 'tests/fpc/maxCronFpcRegistryGen.dpr'
                content = gen.read_text(encoding='utf-8-sig').replace('array[0..2]', 'array[0..1]')
                content = content.replace("'" + unit + "', ", '').replace(", '" + unit + "'", '')
                write(gen, content)
            else:
                for target in ('maxCronTests', 'maxCronStressTests', 'maxCronVclTests'):
                    runner = work / 'tests' / (target + '.dpr')
                    content = re.sub(r'(?m)^  ' + unit + r" in '[^']+',\n", '', runner.read_text(encoding='utf-8-sig'))
                    write(runner, content.replace('    TDUnitX.RegisterTestFixture(' + fixture_name + ');\n', ''))
        write(path, source)
    return work, selector


def main():
    parser = argparse.ArgumentParser()
    for name in ('repository', 'scratch', 'compiler', 'dunitx'):
        parser.add_argument('--' + name, required=True, type=Path)
    parser.add_argument('--routes', nargs='*', choices=['unit','stress','vcl','default-bat','default-sh','stress-bat','stress-sh','long-bat','long-sh','fpc-bat','fpc-sh','fpc-long-bat','fpc-long-sh','smoke','smoke-heap'])
    parser.add_argument('--inject-compiler-failure', action='store_true')
    parser.add_argument('--controls-only', action='store_true')
    parser.add_argument('--setup-only', action='store_true', help='Discover, validate controls and compile all distinct fixture variants without running negative cases')
    parser.add_argument('--contract-variant', choices=['enabled', 'disabled'], default='enabled', help='Disabled is a negative-case-only guard-removal mutation; setup and positive controls stay enabled')
    parser.add_argument('--inject-phase', choices=['generator','parity'])
    args = parser.parse_args()
    fpc_command = get_fpc_command()
    repo, scratch = args.repository.resolve(), args.scratch.resolve()
    if scratch.exists() or repo == scratch or repo in scratch.parents:
        raise RuntimeError('Use a fresh external scratch root')
    scratch.mkdir(parents=True)
    env = {k: v for k, v in os.environ.items() if not k.startswith('MAXCRON_')}
    env['MAXLOGIC_MADEXCEPT_AI'] = '1'
    env['MAXCRON_FPC'] = fpc_command[0]
    env['WSLENV'] = env.get('WSLENV', '') + ':DAK_EXE:MAXCRON_FPC:MAXCRON_LONG_OUT:MAXCRON_FPC_OUT:MAXCRON_TEST_ROOT:MAXCRON_ROSTER_OUT'
    results = []
    controls = []
    if sys.flags.utf8_mode or locale.getencoding().lower().replace('-', '') == 'utf8':
        raise RuntimeError('Run this regression under a non-UTF8 locale: python -X utf8=0')
    (scratch / 'locale.json').write_text(json.dumps(dict(encoding=locale.getencoding(), utf8_mode=sys.flags.utf8_mode)), encoding='utf-8')

    def run(label, command, cwd, extra=None):
        settings = {**env, **(extra or {}), 'MAXCRON_TEST_ROOT': str(cwd)}
        log = scratch / (label + '.log')
        started = time.perf_counter()
        receipt = dict(label=label, command=list(map(str, command)), cwd=str(cwd), state='running', native_exit=None, log=str(log))
        receipt_path = scratch / 'subprocesses.jsonl'
        with receipt_path.open('a', encoding='utf-8') as records:
            records.write(json.dumps(receipt) + '\n')
        with log.open('wb') as output:
            proc = subprocess.run(list(map(str, command)), cwd=cwd, env=settings, stdout=output,
                                  stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW, check=False)
        receipt.update(state='completed', native_exit=proc.returncode, duration_seconds=time.perf_counter()-started)
        with receipt_path.open('a', encoding='utf-8') as records:
            records.write(json.dumps(receipt) + '\n')
        return proc.returncode, log.read_text(encoding='utf-8', errors='replace'), str(log)

    template = scratch / 'template'
    template.mkdir()
    for pattern in ('*.pas', '*.inc', 'build-and-run-tests*.bat', 'build-and-run-tests*.sh'):
        for path in repo.glob(pattern):
            shutil.copy2(path, template / path.name)
    shutil.copytree(repo / 'tests', template / 'tests', ignore=shutil.ignore_patterns('Win32', 'Win64', '__pycache__', '__recovery', '*.exe', '*.ppu', '*.dcu', '*.o'))
    fixture = """unit UNITNAME;
{$I maxCron.inc}
interface
uses DUnitX.TestFramework;
type
  [TestFixture]
  CLASSNAME = class
  public
    [Test] procedure Plain;
    [TestCase('one', '1')]
    [TestCase('two', '2')]
    procedure Number(const aValue: Integer);
  end;
implementation
procedure CLASSNAME.Plain;
begin
  Assert.IsTrue(True);
end;
procedure CLASSNAME.Number(const aValue: Integer);
begin
  Assert.IsTrue(aValue > 0);
end;
end.
"""
    write(template / 'tests/unit/TestSharedRoster.pas', fixture.replace('UNITNAME', 'TestSharedRoster').replace('CLASSNAME', 'TTestSharedRoster'))
    # Same fixture identity is used in the Delphi control only; the FPC route
    # retains the actual TestFpcShims implementation from the product tree.
    write(template / 'tests/unit/TestFpcShims.pas', fixture.replace('UNITNAME', 'TestFpcShims').replace('CLASSNAME', 'TTestFpcShims'))
    write(template / 'tests/unit/TestLocalZoneOs.pas', """unit TestLocalZoneOs;
{$I maxCron.inc}
interface
uses DUnitX.TestFramework;
type
  [TestFixture]
  TTestLocalZoneOs = class
  public
    [Test] procedure Shared;
    {$IFNDEF FPC}
    [Test] procedure MatchesRtlLocal;
    {$ENDIF}
  end;
implementation
procedure TTestLocalZoneOs.Shared;
begin
end;
{$IFNDEF FPC}
procedure TTestLocalZoneOs.MatchesRtlLocal;
begin
end;
{$ENDIF}
end.
""")
    for target in ('maxCronTests', 'maxCronStressTests', 'maxCronVclTests'):
        path = template / 'tests' / (target + '.dpr')
        body = path.read_text(encoding='utf-8-sig')
        uses = "uses\n  System.Classes, System.SysUtils, Vcl.Forms,\n  DUnitX.Extensibility, DUnitX.Loggers.Console, DUnitX.RunResults, DUnitX.TestFramework,\n"
        if (template / 'tests/TestRoster.pas').exists():
            uses += "  TestRoster in 'TestRoster.pas', DelphiRoster in 'DelphiRoster.pas',\n"
        uses += "  TestSharedRoster in 'unit\\TestSharedRoster.pas',\n  TestFpcShims in 'unit\\TestFpcShims.pas',\n  TestLocalZoneOs in 'unit\\TestLocalZoneOs.pas';"
        body = re.sub(r'(?s)\buses\s+.*?;', lambda _: uses, body, count=1)
        body = body.replace('{$APPTYPE GUI}', '{$APPTYPE CONSOLE}')
        body = re.sub(r'(?m)^\s*TDUnitX.RegisterTestFixture\([^;]+;\n?', '', body)
        body = body.replace('    Runner := TDUnitX.CreateRunner;', '    TDUnitX.RegisterTestFixture(TTestSharedRoster);\n    TDUnitX.RegisterTestFixture(TTestFpcShims);\n    TDUnitX.RegisterTestFixture(TTestLocalZoneOs);\n    Runner := TDUnitX.CreateRunner;')
        write(path, body)
    fpc_runner = template / 'tests/fpc/maxCronFpcTests.dpr'
    body = fpc_runner.read_text(encoding='utf-8-sig')
    start, end = body.index('uses\n'), body.index('\n{$I maxCronFpcRegistry.inc}')
    uses = "uses SysUtils, DUnitX.TestFramework, maxCronFpcTestRunner,\n"
    if (template / 'tests/TestRoster.pas').exists():
        uses += "  TestRoster in '..\\TestRoster.pas',\n"
    uses += "  TestSharedRoster in '..\\unit\\TestSharedRoster.pas',\n  TestLocalZoneOs in '..\\unit\\TestLocalZoneOs.pas',\n  TestFpcShims in 'TestFpcShims.pas';\n"
    write(fpc_runner, body[:start] + uses + body[end:])
    generator = template / 'tests/fpc/maxCronFpcRegistryGen.dpr'
    write(generator, re.sub(r'(?s)cUnits: array\[.*?\)\s*;', "cUnits: array[0..2] of string = ('TestSharedRoster', 'TestLocalZoneOs', 'TestFpcShims');", generator.read_text(encoding='utf-8-sig'), count=1))
    smoke = template / 'tests/fpc/maxCronFpcSmoke.dpr'
    body = smoke.read_text(encoding='utf-8-sig')
    start, end = body.index('procedure SmokeMode('), body.index('\nbegin\n  try', body.index('procedure SmokeMode('))
    cheap = """procedure SmokeMode(const aMode: TmaxCronInvokeMode);
var lPrefix: string;
begin
  lPrefix := string(IntToStr(Ord(aMode))) + '.';
  Check(True, lPrefix + 'cron-fires');
  Check(True, lPrefix + 'interval-fires');
  Check(True, lPrefix + 'shutdown');
  Check(True, lPrefix + 'post-free-silence');
end;
"""
    write(smoke, body[:start] + cheap + body[end:])
    demo = template / 'demo'
    demo.mkdir()
    write(demo / 'CronDemo.dpr', 'program CronDemo;\nbegin\nend.\n')
    project = (template / 'tests/maxCronTests.dproj').read_text(encoding='utf-8-sig').replace('maxCronTests', 'CronDemo')
    write(demo / 'CronDemo.dproj', project)
    for path in list((template / 'tests').glob('*.dproj')) + [demo / 'CronDemo.dproj']:
        project = re.sub(r'<CfgDependentOn>.*?</CfgDependentOn>', '', path.read_text(encoding='utf-8-sig'))
        project = project.replace('</Project>', '<PropertyGroup><DCC_DcuOutput>.\\matrix-dcu\\$(Platform)\\$(Config)\\$(ProjectName)</DCC_DcuOutput></PropertyGroup></Project>')
        write(path, project)
        for platform in ('Win32', 'Win64'):
            for config in ('Release', 'Debug'):
                (path.parent / 'matrix-dcu' / platform / config / path.stem).mkdir(parents=True, exist_ok=True)
    instrument_builds(template)
    code, text, log = run('manifest-export', ['powershell.exe', '-NoProfile', '-NonInteractive', '-File', template / 'tests/Export-TestRosters.ps1', '-Compiler', args.compiler, '-DUnitXSource', args.dunitx, '-OutputRoot', scratch / 'discovery'], template)
    if code:
        raise RuntimeError('Native control discovery failed: ' + log)

    routes = args.routes or ['unit', 'stress', 'vcl', 'default-bat', 'default-sh', 'stress-bat', 'stress-sh', 'long-bat', 'long-sh', 'fpc-bat', 'fpc-sh', 'fpc-long-bat', 'fpc-long-sh', 'smoke', 'smoke-heap']
    variants = ['unknown-selector', 'partial-selector', 'renamed-fixture', 'removed-test', 'removed-import', 'extra-test']

    def execute(work, route, label, selector, overrides=None):
        direct_builds = []
        extra = {'MAXCRON_LONG_OUT': str(scratch / (label + '-long')), 'MAXCRON_FPC_OUT': str(scratch / (label + '-fpc')), 'MAXCRON_ROSTER_OUT': str(scratch / (label + '-rosters'))}
        extra.update(overrides or {})
        if route in ('unit', 'stress', 'vcl'):
            target = {'unit': 'maxCronTests', 'stress': 'maxCronStressTests', 'vcl': 'maxCronVclTests'}[route]
            out = scratch / (label + '-native')
            out.mkdir(exist_ok=True)
            paths = ';'.join(map(str, [work, work / 'tests', work / 'tests/unit', args.dunitx]))
            code, text, log = run(label + '-build', [args.compiler, '-B', '-Q', '-DRELEASE;MAXCRON_TESTS', '-NSSystem;Xml;Data;Winapi;System.Win', '-U' + paths, '-I' + str(work), '-N0' + str(out), '-E' + str(out), work / 'tests' / (target + '.dpr')], work)
            if code:
                raise RuntimeError('Native build failure is not RED: ' + log)
            direct_builds.append(('native-build', code))
            command = [out / (target + '.exe')] + selector
        elif route in ('smoke', 'smoke-heap'):
            out = scratch / (label + '-native')
            out.mkdir(exist_ok=True)
            flags = ['-Fu' + str(work), '-Fu' + str(work / 'tests'), '-Fi' + str(work),
                     '-O2', '-Sew', '-FU' + str(out), '-FE' + str(out)]
            if route == 'smoke-heap':
                flags += ['-dMAXCRON_FPC_SMOKE_NOPOOL', '-gh']
            code, text, log = run(label + '-build', fpc_command + flags + [work / 'tests/fpc/maxCronFpcSmoke.dpr'], work)
            if code:
                raise RuntimeError('Native build failure is not RED: ' + log)
            direct_builds.append(('native-build', code))
            command = [out / 'maxCronFpcSmoke.exe'] + selector
        else:
            name = 'build-and-run-tests'
            if route.startswith('stress-'):
                name += '-stress'
            elif 'long' in route:
                name += '-long'
            elif route.startswith('fpc-'):
                name += '-fpc'
            path = work / (name + ('.sh' if route.endswith('-sh') else '.bat'))
            if route.endswith('-sh'):
                windows = str(path)
                command = ['wsl.exe', '--exec', 'bash', '/mnt/' + windows[0].lower() + windows[2:].replace('\\', '/')]
            else:
                command = [os.environ['COMSPEC'], '/d', '/c', path]
            command += (['fpc'] if route.startswith('fpc-long-') else []) + selector
        code, text, log = run(label, command, work, extra)
        if direct_builds:
            text = append_runner_receipt(log, text, route, code)
        return code, text, log, direct_builds

    def positive(route, label):
        code, text, log, direct = execute(template, route, label, [])
        found = re.findall(r'(?m)^Tests Found\s*:\s*(\d+)\s*$', text)
        passed = re.findall(r'(?m)^Tests Passed\s*:\s*(\d+)\s*$', text)
        zero = [re.findall(r'(?m)^Tests ' + kind + r'\s*:\s*(\d+)\s*$', text) for kind in ('Failed', 'Errored', 'Ignored')]
        builds = list(direct) + build_records(text)
        expected = (('native-build',) if route in ('unit', 'stress', 'vcl', 'smoke', 'smoke-heap') else
                    FPC_ALL_BUILDS if route.startswith('fpc-') else
                    ('maxCronTests',) if route.startswith('long-') else DEFAULT_BUILDS)
        if code or not found or found != passed or any(int(n) <= 0 for n in found) or any(len(k) != len(found) or any(int(n) for n in k) for k in zero) or tuple(name for name, _ in builds) != expected or any(code != 0 for _, code in builds):
            raise MatrixInfrastructureError('Positive control must build and execute a complete passing roster: ' + log)
        controls.append(dict(route=route, label=label, exit=code, found=found, passed=passed, builds=builds, log=log))
        (scratch / 'controls.json').write_text(json.dumps(controls, indent=2), encoding='utf-8')

    if args.setup_only:
        started = time.perf_counter()
        # Keep the discovery/positive template pristine for BOTH variants.
        # Different transports compile these same six native source forms.
        source_suffixes = {'.pas', '.dpr', '.dproj', '.ps1', '.py', '.inc', '.txt', '.json', '.jsonl', '.bat', '.sh'}
        def template_inputs():
            return {p.relative_to(template).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
                    for p in template.rglob('*') if p.is_file() and p.suffix in source_suffixes}
        inputs_before = template_inputs()
        positive('unit', 'setup-positive-unit')
        positive('fpc-bat', 'setup-positive-fpc')
        code, text, log = run('setup-wsl', ['wsl.exe', '--exec', 'bash', '-c', 'echo roster-setup-ok'], template)
        if code or text.strip() != 'roster-setup-ok':
            raise MatrixInfrastructureError('WSL transport setup failed: ' + log)
        cases = []
        summary = scratch / 'setup.json'
        for backend in ('unit', 'stress', 'vcl', 'fpc-bat', 'smoke', 'smoke-heap'):
            for family in ('shared', 'fpc-only'):
                for variant in variants:
                    label = 'setup-' + backend + '-' + family + '-' + variant
                    work, _ = prepare_case(template, scratch, backend, family, variant)
                    if args.contract_variant == 'disabled':
                        disable_contract(work)
                    destination = scratch / (label + '-build')
                    destination.mkdir()
                    if backend in ('unit', 'stress', 'vcl'):
                        target = {'unit':'maxCronTests', 'stress':'maxCronStressTests', 'vcl':'maxCronVclTests'}[backend]
                        paths = ';'.join(map(str, [work, work/'tests', work/'tests/unit', args.dunitx]))
                        commands = []
                        for compiler in (args.compiler.parent/'dcc32.exe', args.compiler.parent/'dcc64.exe'):
                            platform_output = destination/compiler.stem
                            platform_output.mkdir()
                            commands.append((compiler.stem, [compiler, '-B', '-Q', '-DRELEASE;MAXCRON_TESTS', '-NSSystem;Xml;Data;Winapi;System.Win',
                                             '-U'+paths, '-I'+str(work), '-N0'+str(platform_output), '-E'+str(platform_output), work/'tests'/(target+'.dpr')]))
                    else:
                        common = fpc_command + ['-Fu'+str(work), '-Fu'+str(work/'tests'),
                                  '-Fi'+str(work), '-O2', '-Sew', '-FU'+str(destination), '-FE'+str(destination)]
                        if backend == 'fpc-bat':
                            code, _, log = run(label+'-generator-build', common+['-vm4104,4105', work/'tests/fpc/maxCronFpcRegistryGen.dpr'], work)
                            if code:
                                raise MatrixInfrastructureError('Setup generator build failed: '+log)
                            code, _, log = run(label+'-generator', [destination/'maxCronFpcRegistryGen.exe', work, destination/'maxCronFpcRegistry.inc'], work)
                            if code:
                                raise MatrixInfrastructureError('Setup registry generation failed: '+log)
                            command = common + ['-dMAXCRON_TESTS', '-gh', '-vm4104,4105', '-Fu'+str(work/'tests/fpc'),
                                                '-Fu'+str(work/'tests/unit'), '-Fi'+str(destination), work/'tests/fpc/maxCronFpcTests.dpr']
                        else:
                            flags = ['-gh', '-dMAXCRON_FPC_SMOKE_NOPOOL'] if backend == 'smoke-heap' else []
                            command = common + flags + [work/'tests/fpc/maxCronFpcSmoke.dpr']
                        commands = [('FPC', command)]
                    builds = []
                    for compiler_name, command in commands:
                        code, output, log = run(label+'-compile-'+compiler_name, command, work)
                        if code or re.search(r'(?m)^.*(?:\bW\d{4}\b|\bWarning:)', output):
                            raise MatrixInfrastructureError('Setup fixture compile failed or warned: '+log)
                        builds.append(dict(compiler=compiler_name, native_exit=code, log=log))
                    cases.append(dict(backend=backend, family=family, variant=variant, native_exit=0, builds=builds))
                    summary.write_text(json.dumps(dict(state='running', variant=args.contract_variant, cases=cases), indent=2), encoding='utf-8')
        parser = scratch/'setup-parse.ps1'
        parser.write_text("param([string]$Root)\n$ErrorActionPreference='Stop'\nforeach($f in @(Get-ChildItem -LiteralPath $Root -Recurse -File -Filter '*.ps1')){ $t=$null;$e=$null;$null=[Management.Automation.Language.Parser]::ParseFile($f.FullName,[ref]$t,[ref]$e);if($e.Count){throw ('Invalid setup script '+$f.FullName+': '+($e -join '; '))}}\n", encoding='utf-8-sig')
        code, _, log = run('setup-script-parse', ['powershell.exe','-NoProfile','-NonInteractive','-File',parser,'-Root',scratch], template)
        if code:
            raise MatrixInfrastructureError('Setup script parsing failed: '+log)
        unchanged = inputs_before == template_inputs()
        if not unchanged:
            raise MatrixInfrastructureError('Negative-case mutation modified discovery or positive-control inputs')
        summary.write_text(json.dumps(dict(state='completed', native_exit=0, variant=args.contract_variant, cases=cases,
                           positive_controls=len(controls), template_unchanged=unchanged, elapsed_seconds=time.perf_counter()-started), indent=2), encoding='utf-8')
        print('MATRIX_SETUP_OK variant='+args.contract_variant+' cases='+str(len(cases))+' positive_controls='+str(len(controls)), flush=True)
        return 0

    for route in routes:
        positive(route, route + '-complete')
        # This is intentionally under the process's non-UTF8 locale. The
        # unchanged roster must still pass after the exact stamp refresh used
        # by negatives, with its header and identities preserved.
        refresh_stamps(template)
        positive(route, route + '-current-stamps-positive')
        if args.inject_compiler_failure:
            if route != 'fpc-long-bat':
                raise RuntimeError('Injection uses --routes fpc-long-bat')
            failed = scratch / 'failed-compiler/bin/x86_64-win64'
            failed.mkdir(parents=True)
            source = failed / 'FailedCompiler.dpr'
            write(source, """program FailedCompiler;
{$APPTYPE CONSOLE}
begin
  if ParamStr(1)='-iV' then WriteLn('3.3.1')
  else if ParamStr(1)='-iTP' then WriteLn('x86_64')
  else if ParamStr(1)='-iTO' then WriteLn('win64')
  else begin WriteLn('Injected compiler process failure');Halt(37);end;
end.
""")
            (failed / 'fpc.cfg').write_text('', encoding='utf-8')
            code, _, log = run('injected-compiler-build', [args.compiler, '-B', '-Q', '-N0' + str(failed), '-E' + str(failed), source], template)
            if code:
                raise MatrixInfrastructureError('Could not build injection control: ' + log)
            code, text, log, direct = execute(template, route, 'injected-compiler-failure', [], {'MAXCRON_FPC': str(failed / 'FailedCompiler.exe')})
            print(text, flush=True)
            expectation = expected_rejection(template, route, 'renamed-fixture', current=True)
            classify_rejection(code, text, expectation, direct)
            raise AssertionError('Injected compiler failure did not fail the matrix')
        if args.inject_phase:
            if route != 'fpc-long-bat':
                raise RuntimeError('Native phase injection uses --routes fpc-long-bat')
            if args.inject_phase == 'generator':
                write(template / 'tests/fpc/maxCronFpcRegistryGen.dpr', """program maxCronFpcRegistryGen;
{$I maxCron.inc}
begin
  WriteLn('Delphi/FPC test names differ: misleading generator output');
  WriteLn('ROSTER_PHASE phase=roster name=fixture-parity native_exit=5');
  WriteLn('ROSTER_REJECTED reason=renamed detail=misleading generator output');
  Halt(37);
end.
""")
            else:
                shared = template / 'tests/unit/TestSharedRoster.pas'
                write(shared, shared.read_text(encoding='utf-8-sig').replace('TTestSharedRoster', 'TTestSharedRosterRenamed'))
                parity = template / 'tests/fpc/Check-FixtureParity.ps1'
                body = parity.read_text(encoding='utf-8-sig')
                target = 'exit (Complete-RosterFailure $_.Exception)'
                if body.count(target) != 1:
                    raise RuntimeError('Cannot inject actual parity-native exit')
                write(parity, body.replace(target, '$code = Complete-RosterFailure $_.Exception; if ($code -eq 5) { exit 37 }; exit $code'))
            refresh_stamps(template)
            code, text, log, direct = execute(template, route, 'injected-' + args.inject_phase, [])
            print(text, flush=True)
            expectation = expected_rejection(template, route, 'renamed-fixture', current=True)
            classify_rejection(code, text, expectation, direct)
            raise AssertionError('Injected helper failure did not fail the matrix')
        if args.controls_only:
            continue
        for family in ('shared', 'fpc-only'):
            for variant in variants:
                label = route + '-' + family + '-' + variant
                work, selector = prepare_case(template, scratch, route, family, variant)
                expectation = expected_rejection(work, route, variant)
                if args.contract_variant == 'disabled':
                    disable_contract(work)
                code, text, log, direct = execute(work, route, label, selector)
                rejected = classify_rejection(code, text, expectation, direct)
                row = dict(route=route, family=family, variant=variant, exit=code, expected_exit=expectation.exit_code,
                           diagnostic=expectation.diagnostic, phase=expectation.phase, builds=list(direct) + build_records(text),
                           reason=rejected, log=log, rejected=rejected)
                if not selector:
                    refresh_stamps(work)
                    exact_expectation = expected_rejection(work, route, variant, current=True)
                    exact, exact_text, exact_log, exact_direct = execute(work, route, label + '-current-stamps', selector)
                    exact_reason = classify_rejection(exact, exact_text, exact_expectation, exact_direct)
                    row.update(identity_exit=exact, identity_expected_exit=exact_expectation.exit_code,
                               identity_diagnostic=exact_expectation.diagnostic, identity_log=exact_log,
                               identity_builds=list(exact_direct) + build_records(exact_text), identity_reason=exact_reason)
                    row['rejected'] = row['rejected'] and exact_reason
                results.append(row)
                (scratch / 'results.json').write_text(json.dumps(results, indent=2), encoding='utf-8')
                print(json.dumps(row), flush=True)
    return 0 if all(x['rejected'] for x in results) else 1


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (MatrixInfrastructureError, RuntimeError, OSError) as error:
        print('MATRIX_INFRASTRUCTURE_FAILURE ' + str(error), flush=True)
        raise SystemExit(4)

"""Generated Windows gate/discovery invariants. All fixtures stay in --out.

Run with Python 3.12+ on Windows; retain receipts, then clean --out with the bounded
storage helper's AllowLinkFixtures option. No fixture is created in the checkout.
"""
import argparse
import ctypes
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import time

UNITS = ('TestCronInstant TestCronParsing TestCronInvalidCorpus TestCronUtilsCorpus '
         'TestCronFuzzOracle TestCronQuery TestIntervalPlan TestDeadlineQueue '
         'TestTimeZoneRules TestTimeZoneTzif TestCronTextParity TestFpcShims '
         'TestScheduleNext TestHashJitter TestCalendarTimeZone TestNamedTimeZones '
         'TestTimeBoundaries TestMisfireOnTime TestCronPhaseDifferential TestLocalZoneOs '
         'TestTimeZoneWindows TestWindowsZoneOracle TestValidityZones TestLocalOverlap').split()


def run(out, label, args, cwd, env=None):
    out.mkdir(parents=True, exist_ok=True)
    start = time.perf_counter()
    with (out / (label + '.log')).open('wb') as log:
        result = subprocess.run(list(map(str, args)), cwd=cwd, env=env,
                                stdout=log, stderr=subprocess.STDOUT,
                                creationflags=subprocess.CREATE_NO_WINDOW)
    receipt = dict(command=list(map(str, args)), cwd=str(cwd), exit=result.returncode,
                   seconds=time.perf_counter() - start, log=str(out / (label + '.log')))
    (out / (label + '.json')).write_text(json.dumps(receipt, indent=2))
    return receipt


def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(text.replace('\r\n', '\n').replace('\n', '\r\n').encode('ascii'))


def inventory(root):
    result = {}
    for path in root.iterdir():
        if path.is_symlink() or path.is_junction():
            continue
        if path.is_dir():
            result[str(path.relative_to(root)) + '/'] = 'directory'
            result.update({path.name + '/' + k: v
                           for k, v in inventory(path).items()})
        else:
            result[path.name] = hashlib.sha256(path.read_bytes()).hexdigest()
    return result


def install_roster_control(source, gate_source):
    """Keep filesystem probes complete under the independent roster contract."""
    helper = gate_source / 'tests/RosterManifest.ps1'
    if not helper.exists():
        return
    shutil.copyfile(helper, source / 'tests/RosterManifest.ps1')
    stamps = ['# SHA256 ' + path.relative_to(source).as_posix() + ' ' + hashlib.sha256(path.read_bytes()).hexdigest()
              for path in sorted(source.rglob('*')) if path.is_file() and path.suffix in ('.dpr', '.ps1')]
    for entry in ['FpcDefault', 'FpcLong', 'FpcSmoke', 'FpcSmokeHeap']:
        write(source / 'tests/rosters' / (entry + '.txt'), '\n'.join(stamps + ['Control.Probe']) + '\n')
    for gate, core in [('FpcDefaultGate', 'FpcDefault'), ('FpcLongGate', 'FpcLong')]:
        names = [entry + '::Control.Probe' for entry in [core, 'FpcSmoke', 'FpcSmokeHeap']]
        write(source / 'tests/rosters' / (gate + '.txt'), '\n'.join(stamps + names) + '\n')


def link(out, path, target, kind):
    path.parent.mkdir(parents=True, exist_ok=True)
    receipt = run(out, 'link-' + path.name, ['cmd.exe', '/d', '/c', 'mklink',
                                          '/J' if kind == 'junction' else '/D', path, target], out)
    if receipt['exit'] != 0:
        raise RuntimeError(receipt)


def containment(args):
    out = args.out
    source = out / 'source'
    source.mkdir(parents=True)
    shutil.copyfile(args.gate_source / 'build-and-run-tests-fpc.bat', source / 'build-and-run-tests-fpc.bat')
    shutil.copyfile(args.gate_source / 'tests/fpc/Check-OutputPath.ps1', out / 'helper.ps1')
    shutil.copyfile(out / 'helper.ps1', source / 'tests-helper.ps1')
    helpers = source / 'tests/fpc'
    helpers.mkdir(parents=True)
    gate_script = args.gate_source / 'tests/fpc/Run-FpcGate.ps1'
    if gate_script.exists():
        shutil.copyfile(gate_script, helpers / gate_script.name)
    shutil.copyfile(out / 'helper.ps1', helpers / 'Check-OutputPath.ps1')
    # These small compiler inputs isolate the real batch's output writes. The
    # parity shim is deliberately irrelevant to this filesystem invariant.
    write(helpers / 'Check-FixtureParity.ps1', 'exit 0\n')
    summary = ("WriteLn('ROSTER_TEST Control.Probe'); WriteLn('Tests Found   : 1'); WriteLn('Tests Passed  : 1'); "
               "WriteLn('Tests Ignored : 0'); WriteLn('Tests Failed  : 0'); WriteLn('Tests Errored : 0'); "
               "WriteLn('0 unfreed memory blocks');")
    write(helpers / 'maxCronFpcCompileCheck.dpr', 'program Check; begin end.\n')
    write(helpers / 'maxCronFpcRegistryGen.dpr', 'program Gen; begin end.\n')
    write(helpers / 'maxCronFpcTests.dpr', 'program Tests; begin ' + summary + ' end.\n')
    write(helpers / 'maxCronFpcSmoke.dpr', 'program Smoke; begin ' + summary + ' end.\n')
    install_roster_control(source, args.gate_source)
    rows = []
    # Cross product: root spelling/alias, an alias in the middle of the path,
    # and poisoned pre-existing write children. Each case has a fresh root.
    children = ['check-public'] if args.red_case else ['check-public', 'check-tests', 'gen', 'tests', 'smoke', 'smoke-heaptrc']
    roots = ['junction'] if args.red_case else ['direct', 'junction', 'symlink', 'subst']
    for root_kind in roots:
        for middle in ([0] if args.red_case else [0, 1, 2]):
            for child in children:
                label = root_kind + '-' + str(int(middle)) + '-' + child
                case = out / label
                actual = case / 'actual'
                actual.mkdir(parents=True)
                link(out, actual / child, source, 'junction' if child in ['check-public', 'gen', 'smoke'] else 'symlink')
                configured = actual
                drive = None
                try:
                    if middle:
                        ancestor = case / ('outer/ancestor' if middle == 2 else 'ancestor')
                        link(out, ancestor, case, 'junction' if root_kind in ['direct', 'junction'] else 'symlink')
                        configured = ancestor / 'actual'
                    if root_kind in ['junction', 'symlink']:
                        link(out, case / 'alias', configured, root_kind)
                        configured = case / 'alias'
                    elif root_kind == 'subst':
                        drive = next((chr(i + 65) + ':' for i in reversed(range(26))
                                      if not ctypes.windll.kernel32.GetLogicalDrives() & (1 << i)), None)
                        if drive is None:
                            raise RuntimeError('No free drive for SUBST fixture')
                        assert run(out, label + '-subst', ['subst.exe', drive, configured], out)['exit'] == 0
                        configured = Path(drive + '\\')
                    before = inventory(source)
                    env = {k: v for k, v in os.environ.items() if not k.startswith('MAXCRON_') or k == 'MAXCRON_FPC'}
                    env['MAXCRON_FPC_OUT'] = str(configured).swapcase() + '\\.'
                    receipt = run(out, label, ['cmd.exe', '/d', '/c', source / 'build-and-run-tests-fpc.bat'], source, env)
                    after = inventory(source)
                    fresh = list(actual.glob('run-*'))
                    safe = before == after
                    good = safe and receipt['exit'] == 0 and len(fresh) == 1 and 'FPC GATE PASSED (' in Path(receipt['log']).read_text(errors='replace')
                    rows.append(dict(case=label, source_unchanged=safe, expected_exit=0, actual_exit=receipt['exit'],
                                     fresh_runs=[str(x) for x in fresh], passed=good, receipt=receipt))
                finally:
                    if drive:
                        assert run(out, label + '-unsubst', ['subst.exe', drive, '/d'], out)['exit'] == 0
    if not args.red_case:
        external = out / 'outbound-target'
        external.mkdir()
        link(out, source / 'outbound', external, 'junction')
        invalid = [source, source / 'missing/child', source / 'outbound/missing']
        link(out, out / 'source-junction', source, 'junction')
        link(out, out / 'source-symlink', source, 'symlink')
        invalid += [out / 'source-junction/missing', out / 'source-symlink/missing']
        for i, configured in enumerate(invalid):
            before = inventory(source)
            external_before = inventory(external)
            env = dict(os.environ, MAXCRON_FPC_OUT=str(configured).swapcase() + '\\.')
            receipt = run(out, 'invalid-' + str(i), ['cmd.exe', '/d', '/c', source / 'build-and-run-tests-fpc.bat'], source, env)
            safe = before == inventory(source) and external_before == inventory(external)
            rows.append(dict(case='invalid-' + str(i), expected_exit=2, actual_exit=receipt['exit'],
                             source_unchanged=safe, passed=safe and receipt['exit'] == 2, receipt=receipt))
    (out / 'results.json').write_text(json.dumps(dict(kind='containment', cases=rows, passed=all(x['passed'] for x in rows)), indent=2))
    return all(x['passed'] for x in rows)


def path_text(args):
    """Exercise the real launcher with literal environment strings, never shell text."""
    out = args.out
    source = out / 'source'
    helpers = source / 'tests/fpc'
    helpers.mkdir(parents=True)
    shutil.copyfile(args.gate_source / 'build-and-run-tests-fpc.bat', source / 'build-and-run-tests-fpc.bat')
    for name in ['Check-OutputPath.ps1', 'Run-FpcGate.ps1']:
        original = args.gate_source / 'tests/fpc' / name
        if original.exists():
            shutil.copyfile(original, helpers / name)
    write(helpers / 'Check-FixtureParity.ps1', 'exit 0\n')
    summary = ("WriteLn('ROSTER_TEST Control.Probe'); WriteLn('Tests Found   : 1'); WriteLn('Tests Passed  : 1'); "
               "WriteLn('Tests Ignored : 0'); WriteLn('Tests Failed  : 0'); WriteLn('Tests Errored : 0'); "
               "WriteLn('0 unfreed memory blocks');")
    for name, body in [('CompileCheck', ''), ('RegistryGen', ''), ('Tests', summary), ('Smoke', summary)]:
        write(helpers / ('maxCronFpc' + name + '.dpr'), 'program Probe; begin ' + body + ' end.\n')
    install_roster_control(source, args.gate_source)
    rows = []
    variants = []
    # Three positions, both direct text and percent/delayed environment references.
    for char in 'Az09 _-+.%!&|<>^()"\';/#@=[]{}$`,~*?:\t\x01\x7f' + '\u017c\u00e9\u8f93\U0001f600':
        for position in ['prefix', 'middle', 'suffix']:
            for mode in ['literal', 'percent-reference', 'delayed-reference']:
                variants.append((char, position, mode, char))
    injections = ['& mkdir R3_OUTSIDE & rem tail', '!bang!', '(parens)', '& echo R3_MARK & rem tail']
    attack_cases = [('expansion', 'middle', 'percent-reference', value) for value in injections]
    variants = [('\u8f93', 'middle', 'literal', '\u8f93')] if args.red_case else variants + attack_cases + [
        ('\\', 'middle', 'literal', '\\')]
    for index, (char, position, mode, value) in enumerate(variants):
        case = out / ('case-' + str(index))
        case.mkdir()
        token = char if mode == 'literal' else ('%R3_VALUE%' if mode == 'percent-reference' else '!R3_VALUE!')
        leaf = dict(prefix=token + 'out', middle='out' + token + 'put', suffix='out' + token)[position]
        configured = case / leaf
        configured_text = str(case) + '\\' + leaf
        # The oracle is assigned before launching, independently of its exit.
        # References are literal filename text, so '%' and '!' are unsupported.
        supported = bool(re.fullmatch(r'[A-Za-z0-9 ._+\\-]+', leaf)) and not leaf.endswith((' ', '.'))
        expected_exit = 0 if supported else 2
        env = {k: v for k, v in os.environ.items() if not k.startswith('MAXCRON_') or k == 'MAXCRON_FPC'}
        env.update(MAXCRON_FPC_OUT=configured_text, R3_VALUE=value, bang='EXPANDED')
        before_source, before_case = inventory(source), inventory(case)
        receipt = run(out, 'path-' + str(index), ['cmd.exe', '/d', '/c', source / 'build-and-run-tests-fpc.bat'], source, env)
        log = Path(receipt['log']).read_text(errors='replace')
        after_case = inventory(case)
        match = re.search(r'^FPC OUTPUT (.+)$', log, re.M)
        run_path = Path(match[1].strip()) if match else None
        source_safe = before_source == inventory(source)
        if expected_exit == 2:
            good = receipt['exit'] == 2 and source_safe and before_case == after_case and run_path is None
        elif receipt['exit'] == 0 and run_path is not None:
            # Literalness matters: expansion to another location cannot satisfy containment.
            good = source_safe and run_path.parent == configured and bool(re.fullmatch(r'run-[0-9a-f]{32}', run_path.name)) and 'FPC GATE PASSED (' in log
            relative_output = str(configured.relative_to(case)).replace('\\', '/')
            parts = relative_output.split('/')
            allowed = {'/'.join(parts[:i]) + '/' for i in range(1, len(parts) + 1)} | {relative_output + '/' + run_path.name + '/'}
            good = good and all(key in allowed or key.startswith(relative_output + '/' + run_path.name + '/')
                                for key in after_case.keys() - before_case.keys())
            good = good and list(configured.glob('run-*')) == [run_path]
        else:
            good = False
        rows.append(dict(character=char, position=position, mode=mode, variable=value,
                         configured=configured_text, expected_exit=expected_exit, exit=receipt['exit'], source_unchanged=source_safe,
                         per_run=str(run_path) if run_path else None, passed=good, receipt=receipt))
        (out / 'results.json').write_text(json.dumps(dict(kind='path-text', seed='exhaustive-v2-ascii-contract',
            bounds='ASCII allowed and omitted punctuation/control/Unicode classes x 3 positions x 3 literal/reference forms + 4 injections',
            cases=rows, passed=all(row['passed'] for row in rows)), indent=2))
    return all(row['passed'] for row in rows)


def child_environment(args):
    """Use real heaptrc, relative writes and launcher audit to check every child."""
    out = args.out
    source = out / 'source'
    helpers = source / 'tests/fpc'
    helpers.mkdir(parents=True)
    shutil.copyfile(args.gate_source / 'build-and-run-tests-fpc.bat', source / 'build-and-run-tests-fpc.bat')
    for name in ['Run-FpcGate.ps1', 'Check-OutputPath.ps1']:
        shutil.copyfile(args.gate_source / 'tests/fpc' / name, helpers / name)
    write(helpers / 'Check-FixtureParity.ps1',
          "if ($env:R4_ENV_POISON) { exit 9 }\n"
          "[IO.File]::WriteAllText((Join-Path ([Environment]::CurrentDirectory) 'helper-relative.txt'), 'helper')\nexit 0\n")
    summary = ("WriteLn('ROSTER_TEST Control.Probe'); WriteLn('Tests Found   : 1'); WriteLn('Tests Passed  : 1'); "
               "WriteLn('Tests Ignored : 0'); WriteLn('Tests Failed  : 0'); WriteLn('Tests Errored : 0');")
    for name, body in [('CompileCheck', ''), ('RegistryGen', ''), ('Tests', summary), ('Smoke', summary)]:
        # Every binary makes a relative write, including the generator and smoke.
        write(helpers / ('maxCronFpc' + name + '.dpr'),
              'program Probe; uses SysUtils; var f: Text; begin '
              "if GetEnvironmentVariable('R4_ENV_POISON') <> '' then Halt(9); "
              "Assign(f, '" + name + "-relative.txt'); Rewrite(f); WriteLn(f, GetCurrentDir); Close(f); " + body + ' end.\n')
    install_roster_control(source, args.gate_source)
    rows = []
    for label in ['relative', 'absolute']:
        case = out / label
        case.mkdir()
        inherited = 'inherited-heap.log' if label == 'relative' else str(case / 'outside-heap.log')
        configured = case / 'output with space +09'
        env = {k: v for k, v in os.environ.items() if not k.startswith('MAXCRON_') or k == 'MAXCRON_FPC'}
        env.update(MAXCRON_FPC_OUT=str(configured), MAXCRON_TEST_ROOT=str(case / 'wrong-root'), HEAPTRC='log=' + inherited,
                   R4_ENV_POISON='must not reach children')
        before = inventory(source)
        receipt = run(out, label, ['cmd.exe', '/d', '/c', source / 'build-and-run-tests-fpc.bat'], source, env)
        after = inventory(source)
        (out / (label + '-source-before.json')).write_text(json.dumps(before, indent=2))
        (out / (label + '-source-after.json')).write_text(json.dumps(after, indent=2))
        text = Path(receipt['log']).read_text(errors='replace')
        match = re.search(r'^FPC OUTPUT (.+)$', text, re.M)
        run_path = Path(match[1].strip()) if match else None
        audit = run_path / 'child-processes.jsonl' if run_path else out / 'missing'
        children = [json.loads(line) for line in audit.read_text().splitlines()] if audit.is_file() else []
        allowed = {'SystemRoot', 'windir', 'TEMP', 'TMP', 'PATH', 'HEAPTRC', 'MAXCRON_TEST_ROOT'}
        isolated = bool(children) and all(Path(c['working_directory']) == run_path and
            set(c['environment']) == allowed and
            Path(c['environment']['MAXCRON_TEST_ROOT']) == source and
            Path(c['environment']['TEMP']).is_relative_to(run_path) and
            Path(c['environment']['TMP']).is_relative_to(run_path) and
            bool(re.fullmatch(r'log=child-\d+\.heaptrc\.log', c['environment']['HEAPTRC']))
            for c in children)
        writes = bool(run_path) and all((run_path / (name + '-relative.txt')).is_file() and
            (run_path / (name + '-relative.txt')).read_text().strip() == str(run_path)
            for name in ['RegistryGen', 'Tests', 'Smoke'])
        writes = writes and (run_path / 'helper-relative.txt').is_file() if run_path else False
        safe = before == after and not (case / 'outside-heap.log').exists()
        good = receipt['exit'] == 0 and safe and isolated and writes and text.count('0 unfreed memory blocks') == 2
        rows.append(dict(case=label, inherited_heaptrc=env['HEAPTRC'], expected_exit=0,
                         actual_exit=receipt['exit'], source_unchanged=before == after,
                         no_inherited_absolute_log=not (case / 'outside-heap.log').exists(),
                         children=children, children_isolated=isolated, relative_writes_in_run=writes,
                         passed=good, receipt=receipt))
    (out / 'results.json').write_text(json.dumps(dict(kind='child-environment', cases=rows,
        passed=all(row['passed'] for row in rows)), indent=2))
    return all(row['passed'] for row in rows)


def path_sensitivity(args):
    """Both blanket rejection and blanket acceptance must fail the same oracle."""
    rows = []
    for label, code in [('reject-everything', 2), ('accept-everything', 0)]:
        mutant = args.out / label
        mutant.mkdir()
        write(mutant / 'build-and-run-tests-fpc.bat', '@echo off\nexit /b ' + str(code) + '\n')
        evidence = args.out / (label + '-proof')
        receipt = run(args.out, label, [os.sys.executable, '-I', Path(__file__), 'path-text',
            '--out', evidence, '--gate-source', mutant], args.out)
        result = json.loads((evidence / 'results.json').read_text())
        failed_supported = sum(not c['passed'] and c['expected_exit'] == 0 for c in result['cases'])
        failed_unsupported = sum(not c['passed'] and c['expected_exit'] == 2 for c in result['cases'])
        good = receipt['exit'] == 1 and not result['passed'] and (
            failed_supported > 0 if code == 2 else failed_unsupported > 0)
        rows.append(dict(mutant=label, expected_exit=1, actual_exit=receipt['exit'],
                         failed_supported=failed_supported, failed_unsupported=failed_unsupported,
                         passed=good, receipt=receipt))
    (args.out / 'results.json').write_text(json.dumps(dict(kind='path-sensitivity', cases=rows,
        passed=all(row['passed'] for row in rows)), indent=2))
    return all(row['passed'] for row in rows)


def registry(args):
    out = args.out
    repo = out / 'source'
    declarations = []
    rows = []
    for unit in UNITS:
        path = repo / ('tests/fpc/' if unit == 'TestFpcShims' else 'tests/unit/') / (unit + '.pas')
        extra = ''
        if unit == UNITS[0]:
            for i, gap in enumerate([' ', '\t', '\n', ' {comment}\n ', ' (*comment*) ', '\n//comment\n']):
                for case in [False, True]:
                    n = len(rows)
                    fixture = 'testfixture' if case else 'TestFixture'
                    test = 'test' if case else 'Test'
                    testcase = 'testcase' if case else 'TestCase'
                    extra += ('[' + gap + fixture + gap + '] TLayout' + str(n) + ' = class\n'
                              '[' + gap + test + gap + '] procedure Extra;\n'
                              '[' + gap + testcase + gap + "('one]case', '7')" + gap + '] '
                              '[' + gap + testcase + gap + "('two', '9')" + gap + ']\n'
                              'procedure Value(aNumber: Integer);\nend;\n')
                    rows.append(dict(fixture=unit + '.TLayout' + str(n), gap=gap, lowercase=case))
                    declarations += [unit + '.TLayout' + str(n)]
        base = ('unit ' + unit + ';\ninterface\nuses DUnitX.TestFramework;\ntype\n'
                '[TestFixture] TBaseline = class\n[Test] procedure Base;\nend;\n' + extra + '\nimplementation\n'
                'procedure TBaseline.Base; begin end;\n')
        if unit == UNITS[0]:
            for i in range(len(rows)):
                base += ('procedure TLayout' + str(i) + '.Extra; begin end;\n'
                         'procedure TLayout' + str(i) + '.Value(aNumber: Integer); begin end;\n')
        write(path, base + '\nend.\n')
        declarations += [unit + '.TBaseline']
    memberships = []
    for unit in UNITS:
        p = repo / ('tests/fpc/' if unit == 'TestFpcShims' else 'tests/unit/') / (unit + '.pas')
        memberships += [unit + " in '" + str(p) + "'"]
    program = ('program LayoutDiscovery;\n{$APPTYPE CONSOLE}\nuses System.SysUtils, DUnitX.TestFramework, DUnitX.Extensibility,\n' + ',\n'.join(memberships) + ';\n'
               'procedure PrintFixture(const aFixture: ITestFixture);\nvar lTest: ITest; lChild: ITestFixture;\nbegin\n'
               'for lTest in aFixture.Tests do WriteLn(lTest.FullName);\nfor lChild in aFixture.Children do PrintFixture(lChild);\nend;\n'
               'var lRunner: ITestRunner; lFixture: ITestFixture;\nbegin\nTDUnitX.CheckCommandLine;\n' +
               '\n'.join('TDUnitX.RegisterTestFixture(' + x + ');' for x in declarations) + '\n'
               'lRunner := TDUnitX.CreateRunner; lRunner.UseRTTI := True;\n'
               'for lFixture in (lRunner.BuildFixtures as ITestFixtureList) do PrintFixture(lFixture);\nend.\n')
    src = out / 'LayoutDiscovery.dpr'
    write(src, program)
    studio = args.delphi.parent.parent
    paths = ';'.join([str(args.dunitx), str(studio / 'lib/win64/release')])
    build = run(out, 'delphi-build', [args.delphi, '-B', '-Q', '-NSSystem;Winapi', '-U' + paths,
                                     '-N0' + str(out), '-E' + str(out), src], out)
    if build['exit']:
        raise RuntimeError(build)
    discovery = run(out, 'delphi-discovery', [out / 'LayoutDiscovery.exe'], out)
    assert discovery['exit'] == 0
    expected = sorted(re.findall(r'^Test\w+\.\w+\.[^\r\n]+', Path(discovery['log']).read_text(), re.M))
    generated = run(out, 'generator', [args.generator, repo, out / 'registry.inc'], out)
    actual = sorted(re.findall(r"RegisterTest\('([^']+)'", (out / 'registry.inc').read_text(encoding='utf-8-sig'))) if generated['exit'] == 0 else []
    good = generated['exit'] == 0 and expected == actual and len(expected) == 60
    rejected = []
    if not args.red_case:
        target = repo / 'tests/unit/TestCronInstant.pas'
        original = target.read_bytes()
        for i, attribute in enumerate(['[ Ignore ]', '[ Test , Ignore ]', '[ TestFixture ( 1 ) ]']):
            target.write_bytes(original.replace(b'[TestFixture] TBaseline', attribute.encode() + b' TBaseline'))
            negative = run(out, 'unsupported-' + str(i), [args.generator, repo, out / ('unsupported-' + str(i) + '.inc')], out)
            rejected.append(dict(attribute=attribute, exit=negative['exit'], passed=negative['exit'] == 3))
        target.write_bytes(original)
        good = good and all(x['passed'] for x in rejected)
    (out / 'results.json').write_text(json.dumps(dict(kind='attribute-layout', variants=rows, expected=expected,
                                                    actual=actual, rejected=rejected, generator_exit=generated['exit'], passed=good), indent=2))
    return good


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('kind', choices=['containment', 'registry', 'path-text', 'child-environment', 'path-sensitivity'])
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--gate-source', type=Path)
    parser.add_argument('--generator', type=Path)
    parser.add_argument('--delphi', type=Path)
    parser.add_argument('--dunitx', type=Path)
    parser.add_argument('--red-case', action='store_true')
    arguments = parser.parse_args()
    arguments.out.mkdir(parents=True, exist_ok=False)
    raise SystemExit(0 if {'containment': containment, 'registry': registry, 'path-text': path_text,
                         'child-environment': child_environment, 'path-sensitivity': path_sensitivity}[arguments.kind](arguments) else 1)

"""Encoding and phase-specific verdicts for the executable roster regression."""
from dataclasses import dataclass
import hashlib
from pathlib import Path
import re


class MatrixInfrastructureError(RuntimeError):
    pass


def read_manifest(path):
    return Path(path).read_text(encoding='utf-8-sig')


def write_manifest(path, text):
    Path(path).write_text(text.replace('\r\n', '\n'), encoding='utf-8-sig', newline='\r\n')


def refresh_stamps(work):
    manifests = sorted(set(list((work / 'tests').glob('*.txt')) +
                           list((work / 'tests/fpc').glob('*.txt')) +
                           list((work / 'tests/rosters').glob('*.txt'))))
    for path in manifests:
        original = read_manifest(path)
        current = re.sub(r'(?m)^(# SHA256 (\S+) )[a-f0-9]{64}$',
                         lambda m: m[1] + hashlib.sha256((work / m[2]).read_bytes()).hexdigest(), original)
        write_manifest(path, current)
        before = [s for s in original.splitlines() if s and not s.startswith('#')]
        after = [s for s in read_manifest(path).splitlines() if s and not s.startswith('#')]
        if before != after or not read_manifest(path).startswith('#'):
            raise MatrixInfrastructureError('Stamp refresh changed manifest identities/header: ' + str(path))


def first_stale(work, entries):
    for entry in entries:
        path = work / ('tests/fpc/DelphiSharedTests.txt' if entry == 'shared' else
                       'tests/rosters/' + entry + '.txt')
        for line in read_manifest(path).splitlines():
            match = re.fullmatch(r'# SHA256 (\S+) ([a-f0-9]{64})', line)
            if match and hashlib.sha256((work / match[1]).read_bytes()).hexdigest() != match[2]:
                return match[1]
    return None


@dataclass(frozen=True)
class Rejection:
    exit_code: int
    diagnostic: str
    builds: tuple
    phase: str
    roster_name: str = 'fixture-parity'
    propagation: tuple = ()


DEFAULT_BUILDS = ('CronDemo', 'maxCronStressTests', 'maxCronTests', 'maxCronVclTests')
FPC_PARITY_BUILDS = ('check-public', 'check-tests', 'gen')
FPC_ALL_BUILDS = FPC_PARITY_BUILDS + ('tests', 'smoke', 'smoke-heaptrc')


def expected_rejection(work, route, variant, current=False):
    native = route in ('unit', 'stress', 'vcl', 'smoke', 'smoke-heap')
    fpc = route.startswith('fpc-')
    long = 'long-' in route
    builds = ('native-build',) if native else DEFAULT_BUILDS
    entry = {'unit': 'DelphiUnit', 'stress': 'DelphiStress', 'vcl': 'DelphiVcl',
             'smoke': 'FpcSmoke', 'smoke-heap': 'FpcSmokeHeap'}.get(route, 'DelphiLong' if long else 'DelphiDefaultGate')
    phase = 'runtime'
    if variant.endswith('selector'):
        reason = 'count'
        if long or fpc:
            builds, entry = (), 'arguments'
        elif not native:
            entry = 'DelphiStress'
        phase = 'arguments'
    else:
        stale = None if current else first_stale(work, [entry]) if not fpc or long else None
        if stale:
            reason, phase = 'stale', 'source-preflight'
            if long:
                builds = ()
        elif fpc:
            stale = None if current else first_stale(work, ['shared', 'FpcOnly'])
            reason = 'stale' if stale else 'renamed' if variant == 'renamed-fixture' else 'extra' if variant == 'extra-test' else 'missing'
            builds, entry, phase = FPC_PARITY_BUILDS, 'fixture-parity', 'parity'
        else:
            reason = 'renamed' if variant == 'renamed-fixture' else 'extra' if variant == 'extra-test' else 'missing'
            if long:
                builds = ('maxCronTests',)
            elif not native:
                entry = 'DelphiStress'
    if native:
        propagation = (('runner', route),)
    elif phase == 'parity':
        propagation = (('parity', 'fixture-parity'),)
    elif not fpc and not long:
        propagation = ((('runner', 'DelphiStress'),) if phase != 'source-preflight' else ()) + (('roster-check', 'DelphiDefaultGate'),)
    elif fpc and long and phase == 'source-preflight':
        propagation = (('roster-check', 'long-preflight'),)
    elif long and phase == 'runtime':
        propagation = (('runner', 'DelphiLong'),)
    else:
        propagation = ()
    return Rejection(5, reason, builds, phase, entry, propagation)


def phase_records(text):
    return [(m[1], m[2], int(m[3]), m.start()) for m in re.finditer(r'(?m)^ROSTER_PHASE phase=(\S+) name=(\S+) native_exit=(-?\d+)\r?$', text)]


def build_records(text):
    return [(name, code) for phase, name, code, _ in phase_records(text) if phase == 'build']


def classify_rejection(code, text, expectation, direct_builds=()):
    records = [('build', name, exit_code, -1) for name, exit_code in direct_builds] + phase_records(text)
    # Only the roster checker can originate exit5. These subprocess phases may
    # propagate it after the check; build/generator/tool failures never may.
    for phase, name, native_exit, _ in records:
        if native_exit not in (0, 5) or (native_exit == 5 and phase not in ('roster', 'runner', 'parity', 'roster-check')):
            raise MatrixInfrastructureError('Subprocess failure: ' + repr((phase, name, native_exit)))
    if code != 5:
        return False
    verdicts = list(re.finditer(r'(?m)^ROSTER_REJECTED reason=(missing|extra|renamed|duplicate|stale|empty|count) detail=([^\r\n]+)\r?$', text))
    failures = [r for r in records if r[0] == 'roster' and r[2] == 5]
    if len(verdicts) != 1 or len(failures) != 1:
        return False
    failure = failures[0]
    if verdicts[0][1] != expectation.diagnostic or failure[1] != expectation.roster_name:
        return False
    if failure[3] >= verdicts[0].start():
        return False
    if any(exit_code != 0 for _, _, exit_code, pos in records if pos < failure[3]):
        raise MatrixInfrastructureError('A phase before roster comparison did not succeed')
    # Every nonzero propagation must follow the one genuine typed check.
    if any(pos < failure[3] for phase, _, exit_code, pos in records if phase != 'roster' and exit_code == 5):
        raise MatrixInfrastructureError('Exit5 was not originated by roster comparison')
    builds = [(name, exit_code, pos) for phase, name, exit_code, pos in records if phase == 'build']
    if tuple(name for name, _, _ in builds) != expectation.builds or any(exit_code != 0 or pos >= failure[3] for _, exit_code, pos in builds):
        raise MatrixInfrastructureError('Missing, late or unexpected build completion receipts')
    propagated = tuple((phase, name) for phase, name, native_exit, pos in records if phase != 'roster' and native_exit == 5)
    required_propagation = expectation.propagation or ((('parity', 'fixture-parity'),) if expectation.phase == 'parity' else ())
    if propagated != required_propagation:
        raise MatrixInfrastructureError('Missing or unexpected native verdict propagation receipts')
    if any(native_exit == 0 and pos > failure[3] for _, _, native_exit, pos in records):
        raise MatrixInfrastructureError('A new phase completed after roster rejection')
    if expectation.phase == 'parity':
        generators = [r for r in records if r[0] == 'generator']
        parity = [r for r in records if r[0] == 'parity']
        if len(generators) != 1 or generators[0][1:3] != ('registry', 0) or generators[0][3] >= failure[3]:
            raise MatrixInfrastructureError('Registry generator did not complete successfully before parity')
        if len(parity) != 1 or parity[0][1:3] != ('fixture-parity', 5) or parity[0][3] <= verdicts[0].start():
            raise MatrixInfrastructureError('Parity native completion does not own the verdict')
    elif expectation.phase not in ('arguments', 'source-preflight', 'runtime'):
        raise MatrixInfrastructureError('Unknown rejection phase')
    if any(r[0] in ('generator','parity') for r in records) and expectation.phase != 'parity':
        raise MatrixInfrastructureError('Unexpected generator/parity phase for this check')
    # The line immediately before the verdict must be its own check receipt.
    preceding = text[:verdicts[0].start()].rstrip().splitlines()[-1:]
    if preceding != ['ROSTER_PHASE phase=roster name=' + expectation.roster_name + ' native_exit=5']:
        return False
    return True


def instrument_builds(work):
    # All production entry points now emit native phase completion themselves.
    # No copied-source instrumentation or message blacklist is used.
    return None

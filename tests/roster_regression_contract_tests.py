"""Executable checks for locale-safe stamps and fail-closed verdicts."""
import argparse
import locale
from pathlib import Path
import sys
import tempfile
import unittest
from roster_regression_contract import (read_manifest, write_manifest, refresh_stamps,
    Rejection, classify_rejection, MatrixInfrastructureError, FPC_PARITY_BUILDS, expected_rejection)
from roster_contract_regression import add_unlisted_test, append_runner_receipt

scratch = None


class RosterHarnessContract(unittest.TestCase):
    def test_extra_fixture_method_preserves_implementation_uses_order(self):
        source = (Path(__file__).parent / 'fpc/TestFpcShims.pas').read_text(encoding='utf-8-sig')
        changed = add_unlisted_test(source, 'TTestFpcShims')
        implementation = changed.index('implementation\n')
        self.assertLess(changed.index('uses\n', implementation), changed.index('procedure TTestFpcShims.Unlisted;'))
        self.assertEqual(changed.count('[Test] procedure Unlisted;'), 1)

    def test_native_completion_is_framed_after_unterminated_stderr(self):
        expectation = expected_rejection(Path('.'), 'smoke-heap', 'unknown-selector')
        verdict = ('ROSTER_PHASE phase=roster name=FpcSmokeHeap native_exit=5\n'
                   'ROSTER_REJECTED reason=count detail=complete roster required\n')
        for tail in ('', 'truncated heaptrc tail', 'tail\r', 'tail\n', 'tail\r\n'):
            with self.subTest(tail=repr(tail)):
                text = verdict + tail
                log = scratch / 'native-output.log'
                log.write_bytes(text.encode('utf-8'))
                framed = append_runner_receipt(log, text, 'smoke-heap', 5)
                self.assertEqual(log.read_bytes().decode('utf-8'), framed)
                self.assertTrue(classify_rejection(5, framed, expectation, [('native-build', 0)]))

    def test_unchanged_utf8_bom_manifest_under_non_utf8_locale(self):
        self.assertFalse(sys.flags.utf8_mode)
        self.assertNotEqual(locale.getencoding().lower().replace('-', ''), 'utf8')
        work = Path(tempfile.mkdtemp(prefix='encoding-', dir=scratch))
        (work / 'tests/rosters').mkdir(parents=True)
        (work / 'tests/fpc').mkdir()
        source = work / 'tests/Fixture.pas'
        source.write_bytes(b'unchanged source')
        import hashlib
        path = work / 'tests/rosters/Test.txt'
        text = '# Native roster\n# SHA256 tests/Fixture.pas ' + hashlib.sha256(source.read_bytes()).hexdigest() + '\nFixture.Case.\u017c\u00f3\u0142\u0107\n'
        write_manifest(path, text)
        before = path.read_bytes()
        refresh_stamps(work)
        self.assertEqual(path.read_bytes(), before)
        self.assertEqual(read_manifest(path).splitlines()[-1], 'Fixture.Case.\u017c\u00f3\u0142\u0107')
        self.assertEqual(path.read_bytes().count(b'\xef\xbb\xbf'), 1)

    def test_default_runtime_rejection_belongs_to_first_child(self):
        for route in ('default-bat','default-sh','stress-bat','stress-sh'):
            for variant in ('renamed-fixture','removed-test','removed-import','extra-test'):
                self.assertEqual(expected_rejection(Path('.'),route,variant,current=True).roster_name, 'DelphiStress')

    def test_invalid_route_is_rejected_before_any_fixture_build(self):
        import subprocess
        target = scratch / 'must-not-be-created'
        command = [sys.executable, '-X', 'utf8=0', str(Path(__file__).with_name('roster_contract_regression.py')),
                   '--repository', str(Path(__file__).resolve().parent.parent), '--scratch', str(target),
                   '--compiler', 'unused.exe', '--dunitx', 'unused', '--routes', '-']
        result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        self.assertEqual(result.returncode, 2)
        self.assertFalse(target.exists())

    def test_runtime_rejection_requires_its_parent_native_completion(self):
        expectation = expected_rejection(Path('.'),'unit','renamed-fixture',current=True)
        text = 'ROSTER_PHASE phase=roster name=DelphiUnit native_exit=5\nROSTER_REJECTED reason=renamed detail=case differs\n'
        with self.assertRaises(MatrixInfrastructureError):
            classify_rejection(5,text,expectation,[('native-build',0)])
        self.assertTrue(classify_rejection(5,text+'ROSTER_PHASE phase=runner name=unit native_exit=5\n',expectation,[('native-build',0)]))

    def expectation(self):
        return Rejection(5, 'renamed', FPC_PARITY_BUILDS, 'parity', 'fixture-parity')

    def builds(self):
        return ''.join('ROSTER_PHASE phase=build name=' + name + ' native_exit=0\n' for name in FPC_PARITY_BUILDS)

    def good(self):
        return (self.builds() + 'ROSTER_PHASE phase=generator name=registry native_exit=0\n'
                'ROSTER_PHASE phase=roster name=fixture-parity native_exit=5\n'
                'ROSTER_REJECTED reason=renamed detail=fixture differs\n'
                'ROSTER_PHASE phase=parity name=fixture-parity native_exit=5\n')

    def test_exact_typed_rejection(self):
        self.assertTrue(classify_rejection(5, self.good(), self.expectation()))

    def test_no_arbitrary_outer_exit_becomes_roster_rejection(self):
        for code in (0, 1, 2, 3, 37, 124, -1073741819):
            with self.subTest(code=code):
                self.assertFalse(classify_rejection(code, self.good(), self.expectation()))

    def test_generator_misleading_parity_line_and_exit37(self):
        text = self.good().replace('phase=generator name=registry native_exit=0', 'phase=generator name=registry native_exit=37')
        with self.assertRaises(MatrixInfrastructureError):
            classify_rejection(5, text, self.expectation())

    def test_real_parity_verdict_with_native_exit37(self):
        text = self.good().replace('phase=parity name=fixture-parity native_exit=5', 'phase=parity name=fixture-parity native_exit=37')
        with self.assertRaises(MatrixInfrastructureError):
            classify_rejection(5, text, self.expectation())

    def test_failure_table_every_subprocess_and_mode(self):
        for process in ('compiler','linker','generator','parity','runner','roster-helper'):
            for mode in ('nonzero','crash','timeout','misleading'):
                with self.subTest(process=process, mode=mode):
                    phase = 'build' if process in ('compiler','linker') else 'roster-check' if process == 'roster-helper' else process
                    code = {'nonzero':37,'crash':-1073741819,'timeout':124,'misleading':37}[mode]
                    text = self.good() + 'ROSTER_PHASE phase=' + phase + ' name=' + process + ' native_exit=' + str(code) + '\n'
                    with self.assertRaises(MatrixInfrastructureError):
                        classify_rejection(5, text, self.expectation())

    def test_phase_and_verdict_ownership_cannot_shrink(self):
        for changed in (self.good().replace('phase=generator name=registry native_exit=0\n',''),
                        self.good().replace('phase=parity name=fixture-parity native_exit=5\n',''),
                        self.good().replace('phase=roster name=fixture-parity native_exit=5','phase=roster name=another native_exit=5'),
                        self.good().replace('reason=renamed','reason=stale')):
            try:
                result = classify_rejection(5, changed, self.expectation())
            except MatrixInfrastructureError:
                result = False
            self.assertFalse(result)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--scratch', type=Path, required=True)
    args, rest = parser.parse_known_args()
    scratch = args.scratch
    scratch.mkdir(parents=True, exist_ok=False)
    unittest.main(argv=[sys.argv[0]] + rest)

#!/usr/bin/env python3
"""No-network owned process fixtures; NOT acceptance of the public module itself."""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('published_consumer', ROOT / 'scripts/verify-published-consumer.py')
verifier = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(verifier)


class PublishedConsumerAudit(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='moonvcs-consumer-audit-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.prefix = self.root / 'tools'
        (self.prefix / 'bin').mkdir(parents=True)
        (self.prefix / 'lib/core').mkdir(parents=True)
        (self.prefix / 'lib/core/moon.mod').write_text('owned fixture')
        self.moon = self.prefix / 'bin/moon'
        shutil.copyfile(ROOT / 'tests/fixtures/published_moon.py', self.moon)
        self.moon.chmod(0o700)
        self.config = self.prefix / 'fixture.json'
        self.config.write_text('{}')
        with zipfile.ZipFile(self.prefix / 'payload.zip', 'w') as stream:
            stream.writestr('moon.mod', 'owned fixture, not published package')
        self.expected_hash = verifier.digest(self.prefix / 'payload.zip')
        self.work = self.root / 'acceptance'

    def run_fixture(self, options=None, **kwargs):
        self.config.write_text(json.dumps(options or {}))
        with patch.object(verifier, 'PACKAGE_SHA256', self.expected_hash):
            return verifier.verify(self.work, self.moon, **kwargs)

    def report(self):
        return json.loads((self.work / 'report.json').read_text())

    def test_owned_success_records_commands_versions_and_separate_scope(self):
        report = self.run_fixture()
        self.assertEqual((report['status'], report['exit'], report['consumer_tests_passed']), ('passed', 0, 2))
        self.assertTrue(report['readme_example_passed'] and report['registry_initially_absent'])
        self.assertFalse(report['current_source_regression_verified'] or report['github_actions_verified'])
        self.assertEqual(report['version'], '0.1.0')
        self.assertEqual(len(report['stages']), 8)
        self.assertTrue(all(stage['exit'] == 0 for stage in report['stages']))
        self.assertIn('FAKE', report['versions'])
        self.assertFalse((self.work / 'moon-home/credentials.json').exists())
        self.assertFalse((self.work / 'consumer/moon.work').exists())

    def test_download_failure_is_recorded_and_stops_before_tests(self):
        with self.assertRaises(RuntimeError):
            self.run_fixture({'fail': 'check'})
        report = self.report()
        self.assertEqual(report['status'], 'failed')
        self.assertEqual(report['stages'][-1]['exit'], 23)
        self.assertNotIn('test', [stage['name'] for stage in report['stages']])
        self.assertIn('owned fixture', (self.work / 'check.stderr.log').read_text())

    def test_nonzero_test_result_is_not_masked(self):
        with self.assertRaises(RuntimeError):
            self.run_fixture({'fail': 'test'})
        self.assertEqual(self.report()['stages'][-1]['name'], 'test')
        self.assertEqual(self.report()['exit'], 1)

    def test_wrong_test_count_and_wrong_readme_output_fail(self):
        for index, options in enumerate(({'summary': 'Total tests: 0, passed: 0, failed: 0.'},
                                         {'output': 'wrong fixture output'})):
            self.work = self.root / ('bad-' + str(index))
            with self.assertRaises(ValueError):
                self.run_fixture(options)
            self.assertEqual(self.report()['status'], 'failed')

    def test_registry_hash_mismatch_stops_before_test(self):
        self.expected_hash = '0' * 64
        with self.assertRaises(ValueError):
            self.run_fixture()
        self.assertEqual(self.report()['stages'][-1]['name'], 'check')
        self.assertIn('registry ZIP', self.report()['error'])

    def test_installed_content_and_symlink_overrides_are_rejected(self):
        self.run_fixture()
        home = self.work / 'moon-home'
        consumer = self.work / 'consumer'
        module = consumer / '.mooncakes' / verifier.MODULE / 'moon.mod'
        with patch.object(verifier, 'PACKAGE_SHA256', self.expected_hash):
            module.write_text('locally replaced fixture')
            with self.assertRaises(ValueError):
                verifier.verify_payload(home, consumer)
            module.unlink()
            module.symlink_to(self.prefix / 'lib/core/moon.mod')
            with self.assertRaises(ValueError):
                verifier.verify_payload(home, consumer)

    def test_existing_output_is_preserved_without_reuse(self):
        self.work.mkdir()
        (self.work / 'sentinel').write_text('keep')
        with self.assertRaises(FileExistsError):
            self.run_fixture()
        self.assertEqual([p.name for p in self.work.iterdir()], ['sentinel'])

    def test_surrounding_workspace_and_source_directory_are_rejected(self):
        (self.root / 'moon.work').write_text('owned local override fixture')
        with self.assertRaises(ValueError):
            self.run_fixture()
        self.assertFalse(self.work.exists())
        with self.assertRaises(ValueError):
            verifier.verify(ROOT / 'target/forbidden-consumer-fixture', self.moon)

    def test_anonymous_requirement_and_environment_overrides(self):
        with patch.dict(os.environ, {'MOON_HOME': '/nonexistent/private-home', 'MOON_UNSTABLE': 'fixture'}):
            self.run_fixture()
        self.work = self.root / 'authenticated-fixture'
        with self.assertRaises(ValueError):
            self.run_fixture({'identity': 'owned-fixture-user'})
        self.assertEqual(self.report()['stages'][-1]['name'], 'anonymous')

    def test_timeout_is_failed_and_evidence_is_retained(self):
        with self.assertRaises(RuntimeError):
            self.run_fixture({'stall': 'version'}, timeout=0.1)
        report = self.report()
        self.assertEqual((report['status'], report['stages'][-1]['exit']), ('failed', 124))
        self.assertTrue(report['stages'][-1]['timed_out'])

    def test_cli_failure_returns_nonzero_and_retains_report(self):
        self.config.write_text(json.dumps({'fail': 'check'}))
        result = subprocess.run([sys.executable, str(ROOT / 'scripts/verify-published-consumer.py'),
                                 '--moon', str(self.moon), '--workdir', str(self.work)],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)
        self.assertIn('Published consumer failed', result.stderr)
        self.assertEqual(self.report()['stages'][-1]['exit'], 23)

    def test_modified_module_cannot_introduce_local_override(self):
        source = self.root / 'owned-source'
        fixture = source / 'examples/released-consumer'
        shutil.copytree(ROOT / 'examples/released-consumer', fixture)
        with (fixture / 'moon.mod').open('a') as stream:
            stream.write('\n// owned fixture simulating a local override\n')
        with patch.object(verifier, 'ROOT', source), self.assertRaises(ValueError):
            self.run_fixture()
        self.assertIn('without overrides', self.report()['error'])
        self.assertEqual(self.report()['stages'], [])

    def test_fixture_keeps_the_two_original_tests_and_readme_code(self):
        current = ROOT / 'examples/released-consumer'
        # Recorded from the immutable release consumer. Tests must not require
        # historical evidence in the separately extracted clean SOURCE tree.
        for name, expected in {
            'consumer_test.mbt': '4710551652c61122911493af5f51780459f12854d06088f61fb4126a943d98f0',
            'cmd/readme/main.mbt': 'd85efb01a97e1aabe1e8551c831330916f3ff3f603de0c2e4d72b21a0bd6e886',
        }.items():
            self.assertEqual(verifier.digest(current / name), expected)
        self.assertEqual((current / 'moon.mod').read_text(), verifier.CONSUMER_MODULE)
        self.assertIn('for "test"', (current / 'moon.pkg').read_text())

    def test_manual_workflow_is_separate_read_only_pinned_and_archives_only_reports(self):
        text = (ROOT / '.github/workflows/published-consumer.yml').read_text()
        events = text.split('"on":', 1)[1].split('permissions:', 1)[0]
        self.assertEqual(events.strip(), 'workflow_dispatch:')
        for value in ('contents: read', 'persist-credentials: false', 'if: always()',
                      'retention-days: 14', 'verify-published-consumer.py', 'report.json'):
            self.assertIn(value, text)
        for value in ('secrets.', 'continue-on-error:', 'actions/cache', 'moon publish',
                      'scripts/verify.sh', 'moon -C vcs', '/registry/**', '/moon-home/**'):
            self.assertNotIn(value, text)
        actions = [line.split('uses: ')[1].split(' #')[0] for line in text.splitlines() if 'uses: ' in line]
        self.assertEqual(len(actions), 2)
        for action in actions:
            self.assertRegex(action, r'^actions/[a-z-]+@[0-9a-f]{40}$')


if __name__ == '__main__':
    unittest.main(verbosity=2)

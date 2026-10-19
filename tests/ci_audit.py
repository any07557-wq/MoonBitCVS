#!/usr/bin/env python3
"""CI contract and pinned installer regressions; owned fixtures, no network."""
import hashlib
import importlib.util
import io
from pathlib import Path
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
SPEC = importlib.util.spec_from_file_location('moonvcs_ci_install', ROOT / 'scripts/ci_install_moon.py')
installer = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(installer)


class CiAudit(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='moonvcs-ci-audit-')
        self.addCleanup(self.temporary.cleanup)
        self.work = Path(self.temporary.name)
        self.archives = self.work / 'archives'
        (self.archives / 'sha256').mkdir(parents=True)
        self.lock = {'version': 'harmless-fixture', 'archives': {}}
        self.fixture('moon', {'bin/moon': b'harmless fixture', 'bin/internal/tcc': b'harmless fixture'})
        self.fixture('core', {'core/moon.mod': b'name = "fixture/core"\n'})

    def fixture(self, name, files):
        data = io.BytesIO()
        with tarfile.open(fileobj=data, mode='w:gz') as stream:
            for path, content in files.items():
                info = tarfile.TarInfo(path)
                info.mode = 0o644
                info.size = len(content)
                stream.addfile(info, io.BytesIO(content))
        payload = data.getvalue()
        digest = hashlib.sha256(payload).hexdigest()
        self.lock['archives'][name] = {'url': 'https://cli.moonbitlang.com/fixture',
                                      'sha256': digest, 'bytes': len(payload)}
        (self.archives / 'sha256' / (digest + '.tar.gz')).write_bytes(payload)

    def install(self, destination):
        with patch.object(installer.toolchain_archives, 'load_lock', return_value=self.lock):
            return installer.install_moon(destination, self.archives)

    def test_workflow_is_read_only_pinned_and_runs_the_real_verifier(self):
        text = (ROOT / '.github/workflows/ci.yml').read_text()
        self.assertIn('contents: read', text)
        self.assertIn('persist-credentials: false', text)
        self.assertIn('pull_request:', text)
        self.assertIn('workflow_dispatch:', text)
        self.assertIn('runs-on: ubuntu-24.04', text)
        self.assertIn('run: ./scripts/verify.sh 2>&1 | tee', text)
        self.assertIn('if: always()', text)
        self.assertIn('scripts/ci_install_moon.py', text)
        # runner context is NOT available in jobs.<job>.env. Persist paths
        # from the RUNNER_TEMP shell variable for subsequent steps instead.
        self.assertNotIn('${{ runner.temp }}', text)
        self.assertIn('$RUNNER_TEMP/moonvcs-moon', text)
        self.assertIn('>> "$GITHUB_ENV"', text)
        self.assertNotIn('pull_request_target', text)
        self.assertNotIn('secrets.', text)
        self.assertNotIn('continue-on-error:', text)
        self.assertNotIn('target/**', text)
        actions = [line.split('uses: ', 1)[1].split(' #', 1)[0]
                   for line in text.splitlines() if 'uses: ' in line]
        self.assertEqual(len(actions), 2)
        for action in actions:
            self.assertRegex(action, r'^actions/[a-z-]+@[0-9a-f]{40}$')

    def test_source_delivery_and_clean_build_keep_the_workflow(self):
        for name in ('scripts/package-submission.sh', 'scripts/clean-build.sh', 'scripts/fresh-install.py'):
            self.assertIn('.github', (ROOT / name).read_text(), name)

    def test_install_verifies_archives_sets_permissions_and_does_not_claim_ci_pass(self):
        destination = self.work / 'moon'
        report = self.install(destination)
        self.assertEqual(report['status'], 'installed_not_tested')
        self.assertTrue(report['pinned_checksums_checked'])
        self.assertFalse(report['github_actions_verified'] or report['cold_install_verified'])
        self.assertTrue((destination / 'bin/moon').stat().st_mode & 0o111)
        self.assertTrue((destination / 'bin/internal/tcc').stat().st_mode & 0o111)
        self.assertEqual((destination / 'lib/core/moon.mod').read_bytes(), b'name = "fixture/core"\n')

    def test_corrupt_archive_fails_before_creating_a_prefix(self):
        entry = self.lock['archives']['core']
        path = self.archives / 'sha256' / (entry['sha256'] + '.tar.gz')
        path.write_bytes(b'x' * entry['bytes'])
        destination = self.work / 'moon'
        with self.assertRaises(RuntimeError):
            self.install(destination)
        self.assertFalse(destination.exists())

    def test_existing_prefix_is_preserved(self):
        destination = self.work / 'moon'
        destination.mkdir()
        sentinel = destination / 'operator-data'
        sentinel.write_text('preserve')
        with self.assertRaises(FileExistsError):
            self.install(destination)
        self.assertEqual(list(destination.iterdir()), [sentinel])
        self.assertEqual(sentinel.read_text(), 'preserve')

    def test_traversal_in_an_independently_verified_fixture_is_still_refused(self):
        self.fixture('core', {'../escape': b'harmless fixture'})
        with self.assertRaises(tarfile.FilterError):
            self.install(self.work / 'moon')
        self.assertFalse((self.work / 'escape').exists())


if __name__ == '__main__':
    unittest.main(verbosity=2)

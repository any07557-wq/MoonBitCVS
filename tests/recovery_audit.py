#!/usr/bin/env python3
"""Controlled process-death/read-only recovery checks. NOT power-loss tests."""
import hashlib
import json
import os
from pathlib import Path
import signal
import shutil
import subprocess
import tempfile
import unittest
from staging_concurrency import cli, index_paths, wait_file

ROOT = Path(__file__).resolve().parents[1]
BIN = ROOT / 'target/bin/moonvcs'


def snapshot(repo):
    result = {}
    for path in (repo / '.moonvcs').rglob('*'):
        if path.is_symlink():
            result[str(path.relative_to(repo))] = ('link', os.readlink(path))
        elif path.is_file():
            result[str(path.relative_to(repo))] = hashlib.sha256(path.read_bytes()).hexdigest()
    return result


class RecoveryAudit(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='moonvcs-recovery-test-')
        self.addCleanup(self.temp.cleanup)
        self.work = Path(self.temp.name)
        self.repo = self.work / 'repo'
        self.repo.mkdir()
        cli(self.repo, 'init')
        self.library = self.work / 'gate.so'
        subprocess.run(['cc', '-shared', '-fPIC', '-O2', '-std=c11', str(ROOT / 'tests/fixtures/crash-gate.c'),
                        '-ldl', '-o', str(self.library)], check=True)

    def inspect(self):
        before = snapshot(self.repo)
        report = json.loads(cli(self.repo, 'recover', '--check').stdout)
        self.assertEqual(snapshot(self.repo), before)
        self.assertTrue(report['read_only'])
        self.assertFalse(report['automatic_recovery'])
        self.assertFalse(report['power_loss_verified'])
        return report

    def gated(self, mode, *args):
        gate = self.work / mode
        gate.mkdir()
        environment = dict(os.environ)
        environment.update(LD_PRELOAD=str(self.library), MOONVCS_CRASH_GATE_MODE=mode,
                           MOONVCS_CRASH_GATE_DIR=str(gate), MOONVCS_CRASH_METADATA=str(self.repo / '.moonvcs'))
        child = subprocess.Popen([str(BIN), *map(str, args)], cwd=self.repo, env=environment,
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
        self.addCleanup(lambda: self.stop(child))
        wait_file(gate / 'entered')
        return child

    @staticmethod
    def stop(child):
        if child.poll() is None:
            os.killpg(child.pid, signal.SIGKILL)
        child.communicate(timeout=10)

    def test_kill_before_index_rename_preserves_old_index_and_reports_lock(self):
        (self.repo / 'safe.txt').write_text('safe\n')
        before = (self.repo / '.moonvcs/index').read_bytes()
        child = self.gated('index-before-publish', 'add', 'safe.txt')
        self.stop(child)
        self.assertEqual(child.returncode, -signal.SIGKILL)
        self.assertEqual((self.repo / '.moonvcs/index').read_bytes(), before)
        report = self.inspect()
        self.assertTrue(report['requires_attention'])
        self.assertTrue(any(f['path'] == '.moonvcs/index.lock' for f in report['findings']))
        self.assertFalse((self.repo / '.moonvcs/refs/heads/main').exists())

        # Manual runbook, only in this owned fixture after the writer is dead:
        # preserve metadata and retire exactly the identified pending index.
        shutil.copytree(self.repo / '.moonvcs', self.work / 'metadata-before-manual-action')
        pending = self.repo / '.moonvcs/index.lock'
        saved = self.work / 'preserved-index.lock'
        digest = hashlib.sha256(pending.read_bytes()).hexdigest()
        pending.rename(saved)
        cli(self.repo, 'add', 'safe.txt')
        self.assertEqual(index_paths(self.repo), ['safe.txt'])
        self.assertEqual(hashlib.sha256(saved.read_bytes()).hexdigest(), digest)

    def test_kill_after_index_rename_retains_complete_visible_index(self):
        (self.repo / 'safe.txt').write_text('safe\n')
        child = self.gated('index-after-rename', 'add', 'safe.txt')
        self.stop(child)
        self.assertEqual(index_paths(self.repo), ['safe.txt'])
        self.assertFalse((self.repo / '.moonvcs/index.lock').exists())
        report = self.inspect()
        self.assertTrue(any(f['state'] == 'idle_file_not_a_stale_lock' for f in report['findings']))
        self.assertFalse((self.repo / '.moonvcs/refs/heads/main').exists())

    def test_active_and_killed_quarantine_are_distinguished_without_publishing(self):
        client = self.work / 'client'
        client.mkdir()
        cli(client, 'init')
        (client / 'safe.txt').write_text('APP_MODE=demo\n')
        cli(client, 'add', 'safe.txt')
        cli(client, 'commit', '-m', 'safe test')
        bundle = self.work / 'candidate.rx'
        cli(client, 'bundle', str(bundle), 'refs/heads/main', 'none')
        cli(self.repo, 'receive-init')
        child = self.gated('quarantine-before-validation', 'receive', bundle)
        report = self.inspect()
        self.assertTrue(any(f['kind'] == 'quarantine' and f['state'] == 'active' for f in report['findings']))
        self.stop(child)
        report = self.inspect()
        self.assertTrue(any(f['state'] == 'inactive_lease_requires_inspection' for f in report['findings']))
        self.assertFalse((self.repo / '.moonvcs/refs/heads/main').exists())
        self.assertEqual(list((self.repo / '.moonvcs/objects').glob('*/*')), [])

        # No replay or direct promotion: retain the exact inactive request,
        # then submit the bundle through normal fresh server validation again.
        quarantines = list((self.repo / '.moonvcs/quarantine').iterdir())
        self.assertEqual(len(quarantines), 1)
        shutil.copytree(self.repo / '.moonvcs', self.work / 'metadata-before-receive-retry')
        saved = self.work / 'preserved-quarantine'
        quarantines[0].rename(saved)
        self.assertTrue((saved / 'active.lock').is_file())
        output = cli(self.repo, 'receive', str(bundle)).stdout
        self.assertIn(b'Push accepted', output)
        self.assertEqual((self.repo / '.moonvcs/refs/heads/main').read_bytes(),
                         (client / '.moonvcs/refs/heads/main').read_bytes())
        self.assertTrue(saved.exists())

    def test_unknown_quarantine_and_metadata_symlink_are_preserved(self):
        directory = self.repo / '.moonvcs/quarantine/unknown'
        directory.mkdir(parents=True)
        outside = self.work / 'mock-resource'
        outside.write_text('harmless mock resource\n')
        (self.repo / '.moonvcs/mock-link').symlink_to(outside)
        report = self.inspect()
        self.assertTrue(report['requires_attention'])
        self.assertTrue(any(f['state'] == 'unknown_owner_or_activity' for f in report['findings']))
        self.assertNotIn('harmless mock resource', json.dumps(report))
        self.assertTrue(directory.exists())
        # The metadata root itself must not be followed either.
        (self.repo / '.moonvcs').rename(self.work / 'saved-metadata')
        mock = self.work / 'mock-metadata-root'
        mock.mkdir()
        (mock / 'do-not-traverse').write_text('harmless root fixture\n')
        (self.repo / '.moonvcs').symlink_to(mock, target_is_directory=True)
        report = self.inspect()
        self.assertTrue(report['requires_attention'])
        self.assertTrue(any(f['path'] == '.moonvcs' and f['kind'] == 'metadata_root' for f in report['findings']))
        self.assertNotIn('do-not-traverse', json.dumps(report))

    def test_normal_add_syncs_object_bucket_and_metadata_directory(self):
        (self.repo / 'safe.txt').write_text('safe\n')
        trace = self.work / 'sync.txt'
        environment = dict(os.environ, LD_PRELOAD=str(self.library), MOONVCS_SYNC_TRACE=str(trace))
        result = subprocess.run([str(BIN), 'add', 'safe.txt'], cwd=self.repo, env=environment,
                                capture_output=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        paths = trace.read_text().splitlines()
        self.assertIn(str(self.repo / '.moonvcs'), paths)
        self.assertTrue(any(path.startswith(str(self.repo / '.moonvcs/objects/')) and Path(path).is_dir() for path in paths))
        self.inspect()

    def test_sync_failure_after_rename_reports_uncertain_publication(self):
        (self.repo / 'safe.txt').write_text('safe\n')
        environment = dict(os.environ, LD_PRELOAD=str(self.library),
                           MOONVCS_FAIL_DIR_SYNC=str(self.repo / '.moonvcs'))
        result = subprocess.run([str(BIN), 'add', 'safe.txt'], cwd=self.repo, env=environment,
                                capture_output=True, timeout=20)
        self.assertEqual(result.returncode, 16, result.stdout + result.stderr)
        self.assertIn(b'PublicationUncertain', result.stdout)
        self.assertEqual(index_paths(self.repo), ['safe.txt'])
        self.assertFalse((self.repo / '.moonvcs/index.lock').exists())
        self.inspect()
        published = (self.repo / '.moonvcs/index').read_bytes()
        # Worktree is unchanged; a deliberate normal re-add converges to the
        # same staged bytes. It is not a rollback or a generic replay command.
        cli(self.repo, 'add', 'safe.txt')
        self.assertEqual((self.repo / '.moonvcs/index').read_bytes(), published)

    def test_commit_exit_16_can_mean_ref_already_published_without_success_output(self):
        (self.repo / 'safe.txt').write_text('safe\n')
        cli(self.repo, 'add', 'safe.txt')
        index = (self.repo / '.moonvcs/index').read_bytes()
        environment = dict(os.environ, LD_PRELOAD=str(self.library),
                           MOONVCS_FAIL_DIR_SYNC=str(self.repo / '.moonvcs/refs/heads'))
        result = subprocess.run([str(BIN), 'commit', '-m', 'safe uncertain commit'],
                                cwd=self.repo, env=environment, capture_output=True, timeout=20)
        self.assertEqual(result.returncode, 16, result.stdout + result.stderr)
        self.assertIn(b'PublicationUncertain', result.stdout)
        self.assertNotIn(b'Commit created', result.stdout)
        head = (self.repo / '.moonvcs/refs/heads/main').read_text().strip()
        data = (self.repo / '.moonvcs/objects' / head[:2] / head[2:]).read_bytes()
        self.assertEqual(hashlib.sha256(data).hexdigest(), head)
        self.assertEqual(data[9], 3)  # typed Commit, not just a matching digest
        self.assertEqual((self.repo / '.moonvcs/index').read_bytes(), index)
        self.assertIn(head.encode(), cli(self.repo, 'log', '--max-count', '1', '--offline').stdout)
        self.assertIn(b'safe uncertain commit', cli(self.repo, 'show', 'HEAD', '--offline').stdout)
        self.inspect()
        # Inspecting is not an idempotency token; don't create another Commit.
        self.assertEqual((self.repo / '.moonvcs/refs/heads/main').read_text().strip(), head)


if __name__ == '__main__':
    unittest.main(verbosity=2)

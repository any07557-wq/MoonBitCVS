#!/usr/bin/env python3
"""Branch/checkout protection and failure tests. Temporary owned data only."""
from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time
import unittest

from diff_audit import inventory
from staging_concurrency import cli, wait_file
from system_audit import commit, object_bytes, oid, tree
from switch_recovery_drill import run_drill

ROOT = Path(__file__).resolve().parents[1]
BIN = ROOT / 'target/bin/moonvcs'


class BranchSwitchAudit(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tools = tempfile.TemporaryDirectory(prefix='moonvcs-switch-tools-')
        cls.addClassCleanup(cls.tools.cleanup)
        cls.library = Path(cls.tools.name) / 'switch-gate.so'
        cls.barrier = Path(cls.tools.name) / 'staging-barrier.so'
        for source, output in [('switch-gate.c', cls.library), ('staging-barrier.c', cls.barrier)]:
            subprocess.run(['cc', '-shared', '-fPIC', '-O2', '-std=c11',
                            str(ROOT / 'tests/fixtures' / source), '-ldl', '-o', str(output)], check=True)

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='moonvcs-branch-switch-')
        self.addCleanup(self.temp.cleanup)
        self.work = Path(self.temp.name)
        self.repo = self.work / 'repo'
        self.repo.mkdir()
        cli(self.repo, 'init')

    def write(self, name, content):
        path = self.repo / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
        return path

    def ref(self, name='main'):
        return self.repo / '.moonvcs/refs/heads' / name

    def fixture(self):
        self.write('a.txt', b'old\n')
        self.write('gone.txt', b'restored\n')
        self.write('same.txt', b'keep\n')
        cli(self.repo, 'add', '.')
        cli(self.repo, 'commit', '-m', 'safe old snapshot')
        cli(self.repo, 'branch', 'old')
        self.old_id = self.ref('old').read_text().strip()
        self.write('a.txt', b'new\n')
        self.write('b-new.txt', b'new branch file\n')
        (self.repo / 'gone.txt').unlink()
        cli(self.repo, 'add', '.')
        cli(self.repo, 'commit', '-m', 'safe new snapshot')
        self.main_id = self.ref().read_text().strip()

    def switch(self, name='old', expected=0):
        return cli(self.repo, 'switch', name, expected=expected).stdout.decode()

    def plan(self, name='old'):
        return json.loads(cli(self.repo, 'switch', '--dry-run', name).stdout)

    def put(self, data):
        ident = oid(data)
        path = self.repo / '.moonvcs/objects' / ident[:2] / ident[2:]
        path.parent.mkdir(exist_ok=True)
        path.write_bytes(data)
        return ident

    def state(self):
        return ((self.repo / '.moonvcs/HEAD').read_bytes(), (self.repo / '.moonvcs/index').read_bytes())

    def pending(self):
        return self.repo / '.moonvcs/switch-transaction'

    def inspect(self):
        before = inventory(self.repo)
        report = json.loads(cli(self.repo, 'recover', '--check').stdout)
        self.assertEqual(inventory(self.repo), before)
        return report

    def assert_clean_rejection(self, expected=1):
        before = inventory(self.repo)
        self.switch(expected=expected)
        after = inventory(self.repo)
        self.assertEqual(after, before)
        self.assertFalse(self.pending().exists())

    def gate(self, mode, eio=False):
        directory = self.work / ('gate-' + mode)
        directory.mkdir()
        environment = dict(os.environ, LD_PRELOAD=str(self.library), MOONVCS_SWITCH_GATE_MODE=mode,
                           MOONVCS_SWITCH_GATE_DIR=str(directory), MOONVCS_SWITCH_METADATA=str(self.repo / '.moonvcs'))
        if eio:
            environment['MOONVCS_SWITCH_GATE_EIO'] = '1'
        child = subprocess.Popen([str(BIN), 'switch', 'old'], cwd=self.repo, env=environment,
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.addCleanup(lambda: self.stop(child))
        wait_file(directory / 'entered', timeout=15)
        return child, directory

    @staticmethod
    def stop(child):
        if child.poll() is None:
            child.kill()
        child.communicate(timeout=15)

    def release(self, child, gate, expected=0):
        (gate / 'release').touch()
        stdout, stderr = child.communicate(timeout=20)
        self.assertEqual(child.returncode, expected, stdout + stderr)
        return stdout.decode()

    def manifest(self):
        return json.loads((self.pending() / 'manifest.json').read_text())

    def saved(self, path):
        manifest = self.manifest()
        index = next(i for i, change in enumerate(manifest['changes']) if change['path'] == path)
        return self.pending() / 'before' / str(index)

    def test_branch_lists_unborn_and_refuses_creation_from_it(self):
        self.assertEqual(cli(self.repo, 'branch').stdout, b'* main (unborn)\n')
        self.assertIn(b'unborn HEAD', cli(self.repo, 'branch', 'new', expected=1).stdout)
        self.assertFalse(self.ref('new').exists())

    def test_help_explains_retained_switch_backups_and_disk_growth(self):
        before = inventory(self.repo)
        output = cli(self.repo, '--help').stdout
        self.assertIn(b'.moonvcs/switch-history/<transaction-id>/before/', output)
        self.assertIn(b'disk usage grows', output)
        self.assertIn(b'No automatic cleanup', output)
        self.assertIn(b'.moonvcs/switch-transaction/', output)
        self.assertEqual(inventory(self.repo), before)

    def test_documented_manual_recovery_rebuilds_without_discarding_user_versions(self):
        report = run_drill(self.work / 'manual-drill', binary=BIN, library=self.library)
        self.assertTrue(report['original_unchanged_after_evidence_capture'])
        self.assertTrue(report['evidence_copy_verified'])
        self.assertTrue(report['rebuilt_clean_snapshot_verified'])
        self.assertTrue(report['all_user_versions_preserved'])
        self.assertFalse(report['automatic_recovery'])

    def test_create_from_current_head_preserves_working_index_and_head(self):
        self.fixture()
        before = self.state()
        self.write('a.txt', b'unstaged user work\n')
        cli(self.repo, 'branch', 'feature/security')
        self.assertEqual(self.ref('feature/security').read_text().strip(), self.main_id)
        self.assertEqual(self.state(), before)
        self.assertEqual((self.repo / 'a.txt').read_bytes(), b'unstaged user work\n')
        lines = cli(self.repo, 'branch').stdout.decode().splitlines()
        self.assertTrue(lines[0].startswith('  feature/security '), lines)
        self.assertTrue(lines[1].startswith('* main '), lines)
        self.assertTrue(lines[2].startswith('  old '), lines)

    def test_invalid_names_and_unimplemented_flags_never_create_refs(self):
        self.fixture()
        before = inventory(self.repo)
        for name in ('', 'HEAD', '-d', '/tmp/branch', '../x', 'x..y', 'a//b', 'x.lock', '.x', 'x.',
                     'x\\y', 'x\n', '月亮', 'x' * 65, 'a/b/c/d/e/f/g/h/i'):
            cli(self.repo, 'branch', name, expected=1)
        cli(self.repo, 'switch', '--force', 'old', expected=1)
        cli(self.repo, 'branch', '-d', 'old', expected=1)
        self.assertEqual(inventory(self.repo), before)

    def test_existing_ref_prefixes_and_symlinks_are_not_overwritten(self):
        self.fixture()
        for name in ('old', 'old/child', 'main'):
            cli(self.repo, 'branch', name, expected=1)
        cli(self.repo, 'branch', 'feature/child')
        cli(self.repo, 'branch', 'feature', expected=1)
        mock = self.work / 'mock-ref'
        mock.write_text(self.main_id + '\n')
        self.ref('link').symlink_to(mock)
        before = inventory(self.repo)
        cli(self.repo, 'branch', 'link', expected=1)
        self.assertEqual(inventory(self.repo), before)
        self.assertEqual(mock.read_text(), self.main_id + '\n')

    def test_two_branch_creators_cannot_clobber_one_another(self):
        self.fixture()
        def create(_):
            return subprocess.run([str(BIN), 'branch', 'racing'], cwd=self.repo, capture_output=True, timeout=20)
        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(create, range(2)))
        self.assertEqual(sorted(result.returncode for result in results), [0, 1])
        self.assertEqual(self.ref('racing').read_text().strip(), self.main_id)

    def test_dry_run_is_read_only_and_lists_precise_actions(self):
        self.fixture()
        self.write('untouched.bin', b'\xffuntracked')
        before = inventory(self.repo)
        plan = self.plan()
        self.assertEqual(plan['from_ref'], 'refs/heads/main')
        self.assertEqual(plan['target_ref'], 'refs/heads/old')
        self.assertEqual(plan['target_commit'], self.old_id)
        self.assertEqual(plan['additions'], ['gone.txt'])
        self.assertEqual(plan['replacements'], ['a.txt'])
        self.assertEqual(plan['deletions'], ['b-new.txt'])
        self.assertEqual(inventory(self.repo), before)

    def test_switch_round_trip_preserves_refs_untracked_and_backups(self):
        self.fixture()
        self.write('untracked.txt', b'user data\n')
        refs = (self.ref().read_bytes(), self.ref('old').read_bytes())
        original = (self.repo / 'a.txt').stat()
        self.switch()
        self.assertEqual((self.repo / 'a.txt').read_bytes(), b'old\n')
        self.assertEqual((self.repo / 'gone.txt').read_bytes(), b'restored\n')
        self.assertFalse((self.repo / 'b-new.txt').exists())
        self.assertEqual(cli(self.repo, 'diff').stdout, b'')
        self.assertEqual(cli(self.repo, 'diff', '--staged').stdout, b'')
        archives = list((self.repo / '.moonvcs/switch-history').iterdir())
        self.assertEqual(len(archives), 1)
        manifest = json.loads((archives[0] / 'manifest.json').read_text())
        index = next(i for i, change in enumerate(manifest['changes']) if change['path'] == 'a.txt')
        old_file = archives[0] / 'before' / str(index)
        self.assertEqual(old_file.read_bytes(), b'new\n')
        self.assertEqual(old_file.stat().st_ino, original.st_ino)
        self.assertFalse(self.pending().exists())
        self.switch('main')
        self.assertEqual((self.repo / 'a.txt').read_bytes(), b'new\n')
        self.assertEqual((self.repo / 'untracked.txt').read_bytes(), b'user data\n')
        self.assertEqual((self.ref().read_bytes(), self.ref('old').read_bytes()), refs)
        self.assertFalse(self.inspect()['requires_attention'])

    def test_current_branch_is_a_clean_noop_without_an_archive(self):
        self.fixture()
        before = inventory(self.repo)
        self.switch('main')
        self.assertEqual(inventory(self.repo), before)

    def test_dirty_index_is_refused(self):
        self.fixture()
        self.write('a.txt', b'staged user change\n')
        cli(self.repo, 'add', 'a.txt')
        self.assert_clean_rejection()

    def test_dirty_or_deleted_tracked_file_is_refused(self):
        self.fixture()
        self.write('same.txt', b'user work not changed by target\n')
        self.assert_clean_rejection()
        (self.repo / 'same.txt').unlink()
        self.assert_clean_rejection()

    def test_untracked_file_or_even_empty_directory_blocks_target(self):
        self.fixture()
        self.write('gone.txt', b'restored\n')  # Same bytes still not permission to overwrite.
        self.assert_clean_rejection()
        (self.repo / 'gone.txt').unlink()
        (self.repo / 'gone.txt').mkdir()
        self.assert_clean_rejection()

    def test_symlink_leaf_dangling_and_target_ancestor_are_refused(self):
        self.fixture()
        mock = self.work / 'mock-resource'
        mock.write_text('MOCK-NEVER-READ\n')
        (self.repo / 'a.txt').unlink()
        for target in (mock, self.work / 'absent-mock'):
            (self.repo / 'a.txt').symlink_to(target)
            self.assert_clean_rejection()
            (self.repo / 'a.txt').unlink()
        self.write('a.txt', b'new\n')
        (self.repo / 'gone.txt').symlink_to(mock)
        self.assert_clean_rejection()
        self.assertEqual(mock.read_text(), 'MOCK-NEVER-READ\n')

    def test_fifo_tracked_file_is_refused_without_opening_it(self):
        self.fixture()
        (self.repo / 'a.txt').unlink()
        os.mkfifo(self.repo / 'a.txt')
        self.assert_clean_rejection()

    def test_file_directory_transitions_are_refused_before_mutation(self):
        self.fixture()
        blob = self.put(object_bytes(1, b'safe\n'))
        nested = self.put(tree([('child.txt', 1, blob)]))
        empty = self.put(tree([]))
        for target_tree in (tree([('a.txt', 2, nested)]), tree([('empty-dir', 1, blob)]), tree([('a.txt', 2, empty)])):
            self.ref('old').write_text(self.put(commit(self.put(target_tree))) + '\n')
            (self.repo / 'empty-dir').mkdir(exist_ok=True)
            self.assert_clean_rejection()

    def test_missing_corrupt_or_wrong_type_target_objects_fail_closed(self):
        self.fixture()
        for ident, expected in [('0' * 64, 1), (self.put(object_bytes(1, b'not a commit')), 8),
                                (self.put(commit('1' * 64)), 1)]:
            self.ref('old').write_text(ident + '\n')
            self.assert_clean_rejection(expected)
        broken = self.put(commit(self.put(tree([]))))
        self.ref('old').write_text(broken + '\n')
        path = self.repo / '.moonvcs/objects' / broken[:2] / broken[2:]
        path.write_bytes(b'corrupt')
        self.assert_clean_rejection(8)

    def test_empty_root_snapshot_is_supported_without_dropping_untracked_files(self):
        self.fixture()
        self.write('untracked.txt', b'user data\n')
        target = self.put(commit(self.put(tree([]))))
        self.ref('old').write_text(target + '\n')
        self.assertEqual(self.plan()['deletions'], ['a.txt', 'b-new.txt', 'same.txt'])
        self.switch()
        self.assertEqual(cli(self.repo, 'diff', '--staged').stdout, b'')
        self.assertEqual((self.repo / 'untracked.txt').read_bytes(), b'user data\n')
        self.assertFalse((self.repo / 'a.txt').exists())
        self.assertTrue((self.repo / '.moonvcs/switch-history').is_dir())

    def test_malicious_tree_paths_never_materialize_metadata_or_escape(self):
        self.fixture()
        blob = self.put(object_bytes(1, b'harmless\n'))
        for name in ('.moonvcs', '..', 'a/b', 'a\\b'):
            # Hash-valid wire object; the decoder/path boundary must reject it.
            directory = self.put(tree([(name, 1, blob)]))
            self.ref('old').write_text(self.put(commit(directory)) + '\n')
            before = inventory(self.repo)
            result = subprocess.run([str(BIN), 'switch', 'old'], cwd=self.repo, capture_output=True, timeout=15)
            self.assertIn(result.returncode, (1, 8))
            self.assertEqual(inventory(self.repo), before)

    def test_missing_target_blob_does_not_fetch_or_start_a_transaction(self):
        self.fixture()
        ident = oid(object_bytes(1, b'old\n'))
        (self.repo / '.moonvcs/objects' / ident[:2] / ident[2:]).unlink()
        before = inventory(self.repo)
        output = self.switch(expected=1)
        self.assertIn(ident, output)
        self.assertIn('moonvcs show', output)
        self.assertEqual(inventory(self.repo), before)

    def test_empty_binary_and_unicode_paths_switch_without_reencoding(self):
        self.fixture()
        self.write('月亮/空文件', b'')
        self.write('月亮/data.bin', b'\x00\xff\x01')
        cli(self.repo, 'add', '.')
        cli(self.repo, 'commit', '-m', 'safe binary snapshot')
        self.switch()
        self.assertFalse((self.repo / '月亮/data.bin').exists())
        self.assertTrue((self.repo / '月亮').is_dir())  # Empty dirs never removed.
        self.switch('main')
        self.assertEqual((self.repo / '月亮/空文件').read_bytes(), b'')
        self.assertEqual((self.repo / '月亮/data.bin').read_bytes(), b'\x00\xff\x01')

    def test_hardlinks_and_unchanged_permissions_are_preserved(self):
        self.fixture()
        outside = self.work / 'mock-hardlink'
        os.link(self.repo / 'a.txt', outside)
        (self.repo / 'same.txt').chmod(0o750)
        same_inode = (self.repo / 'same.txt').stat().st_ino
        self.switch()
        self.assertEqual(outside.read_bytes(), b'new\n')
        self.assertEqual((self.repo / 'a.txt').stat().st_mode & 0o777, 0o600)
        self.assertEqual((self.repo / 'same.txt').stat().st_mode & 0o777, 0o750)
        self.assertEqual((self.repo / 'same.txt').stat().st_ino, same_inode)

    def test_pending_transaction_blocks_normal_cli_and_reports_unknown_state(self):
        self.fixture()
        cli(self.repo, 'receive-init')
        bundle = self.work / 'candidate.rx'
        cli(self.repo, 'bundle', str(bundle), 'refs/heads/received', 'none')
        self.pending().mkdir()
        before = inventory(self.repo)
        for args in [('add', 'a.txt'), ('commit', '-m', 'blocked'), ('branch', 'blocked'),
                     ('branch',), ('switch', 'old'), ('status',), ('diff',), ('log',), ('show', 'HEAD'),
                     ('receive', str(bundle))]:
            result = cli(self.repo, *args, expected=18)
            self.assertIn(b'recover --check', result.stdout)
        self.assertEqual(inventory(self.repo), before)
        report = self.inspect()
        self.assertTrue(report['requires_attention'])
        self.assertTrue(any(f['kind'] == 'switch_transaction' and 'unknown' in f['state'] for f in report['findings']))

    def test_unknown_or_symlink_pending_entry_is_never_removed_or_followed(self):
        self.fixture()
        mock = self.work / 'mock-pending'
        mock.write_text('private mock data\n')
        self.pending().symlink_to(mock)
        self.switch(expected=18)
        report = self.inspect()
        self.assertTrue(report['requires_attention'])
        self.assertTrue(self.pending().is_symlink())
        self.assertEqual(mock.read_text(), 'private mock data\n')

    def test_exclusive_locks_and_blocked_history_fail_before_worktree_changes(self):
        self.fixture()
        for name in ('index.lock', 'HEAD.lock', 'refs/heads/old.lock'):
            lock = self.repo / '.moonvcs' / name
            lock.write_text('mock pending writer\n')
            self.assert_clean_rejection()
            lock.unlink()
        (self.repo / '.moonvcs/switch-history').write_text('not a directory')
        self.assert_clean_rejection()

    def test_sigkill_after_preparation_preserves_original_worktree(self):
        self.fixture()
        before = self.state()
        child, _ = self.gate('prepared')
        self.stop(child)
        self.assertEqual(child.returncode, -signal.SIGKILL)
        self.assertEqual(self.state(), before)
        self.assertEqual((self.repo / 'a.txt').read_bytes(), b'new\n')
        self.assertTrue(self.pending().exists())
        self.assertTrue(self.inspect()['requires_attention'])

    def test_sigkill_after_backup_preserves_inode_and_identifies_target(self):
        self.fixture()
        inode = (self.repo / 'a.txt').stat().st_ino
        lock_inode = (self.repo / '.moonvcs/staging-transaction.lock').stat().st_ino
        old_state = self.state()
        child, _ = self.gate('backup')
        self.stop(child)
        self.assertFalse((self.repo / 'a.txt').exists())
        self.assertEqual(self.saved('a.txt').read_bytes(), b'new\n')
        self.assertEqual(self.saved('a.txt').stat().st_ino, inode)
        self.assertEqual(self.state(), old_state)
        self.assertEqual((self.repo / '.moonvcs/staging-transaction.lock').stat().st_ino, lock_inode)
        findings = self.inspect()['findings']
        info = next(f['state'] for f in findings if f['kind'] == 'switch_transaction')
        for value in ('phase=applying', 'refs/heads/main', 'refs/heads/old', self.old_id, self.manifest()['transaction']):
            self.assertIn(value, info)
        cli(self.repo, 'add', 'same.txt', expected=18)

    def test_sigkill_after_index_publish_reports_split_metadata(self):
        self.fixture()
        old_head, old_index = self.state()
        child, _ = self.gate('index')
        self.stop(child)
        head, index = self.state()
        self.assertEqual(head, old_head)
        self.assertNotEqual(index, old_index)
        self.assertEqual(index, (self.pending() / 'new-index').read_bytes())
        self.assertEqual((self.repo / 'a.txt').read_bytes(), b'old\n')
        report = self.inspect()
        self.assertTrue(report['requires_attention'])
        info = next(f['state'] for f in report['findings'] if f['kind'] == 'switch_transaction')
        self.assertIn('HEAD=old', info)
        self.assertIn('index=target', info)
        cli(self.repo, 'commit', '-m', 'blocked', expected=18)

    def test_sigkill_after_head_publish_does_not_pretend_nothing_changed(self):
        self.fixture()
        child, _ = self.gate('head')
        self.stop(child)
        self.assertEqual((self.repo / '.moonvcs/HEAD').read_bytes(), b'ref: refs/heads/old\n')
        self.assertEqual((self.repo / 'a.txt').read_bytes(), b'old\n')
        self.assertTrue(self.pending().exists())
        self.assertTrue(self.inspect()['requires_attention'])

    def test_head_sync_eio_returns_16_with_visible_target_and_preserved_evidence(self):
        self.fixture()
        child, _ = self.gate('head', eio=True)
        stdout, stderr = child.communicate(timeout=15)
        self.assertEqual(child.returncode, 16, stdout + stderr)
        self.assertIn(b'recover --check', stdout)
        self.assertEqual((self.repo / '.moonvcs/HEAD').read_bytes(), b'ref: refs/heads/old\n')
        self.assertTrue(self.pending().exists())
        self.assertEqual(self.saved('a.txt').read_bytes(), b'new\n')

        info = next(f['state'] for f in self.inspect()['findings'] if f['kind'] == 'switch_transaction')
        self.assertIn('HEAD=target', info)
        self.assertIn('index=target', info)

    def test_archive_sync_eio_returns_16_even_when_pending_has_moved(self):
        self.fixture()
        child, _ = self.gate('archive', eio=True)
        stdout, stderr = child.communicate(timeout=15)
        self.assertEqual(child.returncode, 16, stdout + stderr)
        self.assertFalse(self.pending().exists())
        archives = list((self.repo / '.moonvcs/switch-history').iterdir())
        self.assertEqual(len(archives), 1)
        self.assertEqual((archives[0] / 'phase').read_text(), 'completed\n')
        self.assertTrue(any(f['kind'] == 'switch_archive' for f in self.inspect()['findings']))

    def test_new_collision_after_backup_is_not_overwritten(self):
        self.fixture()
        child, gate = self.gate('backup')
        self.write('a.txt', b'late untracked user file\n')
        self.release(child, gate, expected=18)
        self.assertEqual((self.repo / 'a.txt').read_bytes(), b'late untracked user file\n')
        self.assertEqual(self.saved('a.txt').read_bytes(), b'new\n')
        self.assertEqual((self.repo / '.moonvcs/HEAD').read_bytes(), b'ref: refs/heads/main\n')

    def test_late_old_inode_write_is_kept_in_backup_without_auto_cleanup(self):
        self.fixture()
        with (self.repo / 'a.txt').open('r+b', buffering=0) as old_file:
            child, gate = self.gate('backup')
            old_file.seek(0)
            old_file.write(b'user late inode change\n')
            old_file.truncate()
            self.release(child, gate, expected=18)
        self.assertEqual(self.saved('a.txt').read_bytes(), b'user late inode change\n')
        self.assertTrue(self.pending().exists())

    def test_working_file_change_after_preflight_is_preserved(self):
        self.fixture()
        child, gate = self.gate('prepared')
        self.write('a.txt', b'editor changed after preflight\n')
        self.release(child, gate, expected=18)
        self.assertEqual((self.repo / 'a.txt').read_bytes(), b'editor changed after preflight\n')
        self.assertEqual((self.repo / '.moonvcs/HEAD').read_bytes(), b'ref: refs/heads/main\n')

    def test_target_ref_change_after_preflight_aborts_before_file_writes(self):
        self.fixture()
        child, gate = self.gate('prepared')
        self.ref('old').write_text(self.main_id + '\n')  # Simulated noncooperating writer.
        self.release(child, gate, expected=18)
        self.assertEqual((self.repo / 'a.txt').read_bytes(), b'new\n')
        self.assertEqual(self.ref('old').read_text().strip(), self.main_id)

    def test_add_and_switch_share_the_entire_transaction_lock(self):
        self.fixture()
        self.write('a.txt', b'staged by concurrent add\n')
        environment = dict(os.environ, LD_PRELOAD=str(self.barrier), MOONVCS_STAGE_TEST_DIR=str(self.work),
                           MOONVCS_STAGE_TEST_INDEX=str(self.repo / '.moonvcs/index'), MOONVCS_STAGE_TEST_ROLE='first')
        adding = subprocess.Popen([str(BIN), 'add', 'a.txt'], cwd=self.repo, env=environment,
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.addCleanup(lambda: self.stop(adding))
        wait_file(self.work / 'first.read')
        switching = subprocess.Popen([str(BIN), 'switch', 'old'], cwd=self.repo,
                                     stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.addCleanup(lambda: self.stop(switching))
        time.sleep(.15)
        self.assertIsNone(switching.poll())
        (self.work / 'first.release').touch()
        stdout, stderr = adding.communicate(timeout=15)
        self.assertEqual(adding.returncode, 0, stdout + stderr)
        stdout, stderr = switching.communicate(timeout=15)
        self.assertEqual(switching.returncode, 1, stdout + stderr)
        self.assertIn(b'staged changes', stdout)
        self.assertEqual((self.repo / 'a.txt').read_bytes(), b'staged by concurrent add\n')
        self.assertFalse(self.pending().exists())

    def test_unborn_current_branch_can_switch_to_an_existing_clean_snapshot(self):
        self.fixture()
        # Owned fixture: make a legitimate empty unborn working/index state.
        for name in ('a.txt', 'b-new.txt', 'same.txt'):
            (self.repo / name).unlink()
        cli(self.repo, 'add', '.')
        self.ref().unlink()
        self.switch()
        self.assertEqual((self.repo / 'a.txt').read_bytes(), b'old\n')
        self.assertEqual((self.repo / '.moonvcs/HEAD').read_bytes(), b'ref: refs/heads/old\n')

    def test_file_size_budget_refuses_before_a_transaction_starts(self):
        self.fixture()
        with (self.repo / 'a.txt').open('wb') as file:
            file.truncate(8388609)
        self.assert_clean_rejection()

    def test_target_index_must_fit_the_future_reader_and_recovery_budget(self):
        self.fixture()
        blob = self.put(object_bytes(1, b''))
        directory = self.put(tree([(f'f{i:04}', 1, blob) for i in range(1300)]))
        for _ in range(16):
            directory = self.put(tree([('d' * 200, 2, directory)]))
        self.ref('old').write_text(self.put(commit(directory)) + '\n')
        before = inventory(self.repo)
        output = self.switch(expected=1)
        self.assertIn('target index exceeds 4 MiB', output)
        self.assertEqual(inventory(self.repo), before)
        self.assertFalse(self.pending().exists())

    def test_prepared_phase_write_error_keeps_manifest_and_original_state(self):
        self.fixture()
        state = self.state()
        child, _ = self.gate('prepared', eio=True)
        stdout, stderr = child.communicate(timeout=15)
        self.assertEqual(child.returncode, 18, stdout + stderr)
        self.assertEqual(self.state(), state)
        self.assertEqual((self.repo / 'a.txt').read_bytes(), b'new\n')
        self.assertTrue((self.pending() / 'manifest.json').exists())
        self.assertTrue(self.inspect()['requires_attention'])


if __name__ == '__main__':
    unittest.main(verbosity=2)

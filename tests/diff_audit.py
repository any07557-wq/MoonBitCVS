#!/usr/bin/env python3
"""Real CLI diff regression. All data and symlink targets are owned fixtures."""
import hashlib
import os
from pathlib import Path
import random
import re
import stat
import subprocess
import tempfile
import unittest

from staging_concurrency import cli, wait_file
from system_audit import commit, object_bytes, oid, string, tree, u32

ROOT = Path(__file__).resolve().parents[1]
BIN = ROOT / 'target/bin/moonvcs'


def inventory(root):
    """No atime assertion: the OS may update access times on ordinary reads."""
    result = {}
    for directory, dirs, files in os.walk(root, followlinks=False):
        for name in dirs + files:
            path = Path(directory) / name
            info = path.lstat()
            payload = (hashlib.sha256(path.read_bytes()).hexdigest() if stat.S_ISREG(info.st_mode)
                       else os.readlink(path) if stat.S_ISLNK(info.st_mode) else None)
            result[str(path.relative_to(root))] = (info.st_mode, info.st_ino, info.st_mtime_ns,
                                                  info.st_ctime_ns, payload)
    return result


class DiffAudit(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='moonvcs-diff-')
        self.addCleanup(self.temp.cleanup)
        self.work = Path(self.temp.name)
        self.repo = self.work / 'repo'
        self.repo.mkdir()
        cli(self.repo, 'init')

    def write(self, name, data):
        path = self.repo / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        return path

    def diff(self, *args, cwd=None, expected=0):
        return cli(cwd or self.repo, 'diff', *args, expected=expected).stdout.decode()

    def baseline(self, files=None):
        for name, content in (files or {'file.txt': b'base\n'}).items():
            self.write(name, content)
        cli(self.repo, 'add', '.')
        cli(self.repo, 'commit', '-m', 'safe diff baseline')

    def put(self, data):
        ident = oid(data)
        path = self.repo / '.moonvcs/objects' / ident[:2] / ident[2:]
        path.parent.mkdir(exist_ok=True)
        path.write_bytes(data)
        return ident

    def set_index(self, entries):
        data = b'MOONIDX\0\x01' + u32(len(entries))
        data += b''.join(string(path) + ident.encode() for path, ident in sorted(entries))
        (self.repo / '.moonvcs/index').write_bytes(data)

    def test_three_views_use_distinct_snapshots(self):
        self.baseline()
        self.write('file.txt', b'staged\n')
        cli(self.repo, 'add', 'file.txt')
        self.write('file.txt', b'working\n')
        self.assertIn('-staged\n+working\n', self.diff())
        staged = self.diff('--staged')
        self.assertIn('-base\n+staged\n', staged)
        self.assertNotIn('working', staged)
        self.assertEqual(self.diff('--cached'), staged)
        self.assertIn('-base\n+working\n', self.diff('HEAD'))

    def test_unborn_head_and_untracked_files(self):
        self.write('untracked.txt', b'not part of a candidate\n')
        for args in ((), ('--staged',), ('HEAD',)):
            self.assertEqual(self.diff(*args), '')
        self.write('added.txt', b'new file\n')
        cli(self.repo, 'add', 'added.txt')
        self.assertEqual(self.diff(), '')
        for args in (('--staged',), ('HEAD',)):
            result = self.diff(*args)
            self.assertIn('change added\n--- /dev/null\n+++ b/added.txt\n', result)
            self.assertIn('+new file\n', result)
            self.assertNotIn('untracked', result)

    def test_unstaged_and_staged_deletion(self):
        self.baseline({'delete.txt': b'remove\n', 'keep.txt': b'keep\n'})
        (self.repo / 'delete.txt').unlink()
        self.assertIn('change deleted\n', self.diff())
        self.assertEqual(self.diff('--staged'), '')
        cli(self.repo, 'add', 'delete.txt')
        self.assertEqual(self.diff(), '')
        self.assertIn('--- a/delete.txt\n+++ /dev/null\n', self.diff('--staged'))
        self.assertIn('-remove\n', self.diff('HEAD'))
        # Recreated but still untracked by the index: HEAD compares actual bytes.
        self.write('delete.txt', b'remove\n')
        self.assertEqual(self.diff(), '')
        self.assertEqual(self.diff('HEAD'), '')
        self.assertIn('change deleted', self.diff('--staged'))

    def test_empty_unicode_and_no_newline(self):
        self.write('月亮.txt', b'')
        cli(self.repo, 'add', '月亮.txt')
        self.assertIn('change added\n', self.diff('--staged'))
        self.assertIn('b/月亮.txt', self.diff('--staged'))
        self.write('月亮.txt', '你好'.encode())
        self.assertIn('+你好\n\\ No newline at end of file\n', self.diff())

    def test_binary_add_modify_and_delete(self):
        self.baseline({'data.bin': b'\x00one'})
        self.write('data.bin', b'\x00two')
        output = self.diff()
        self.assertIn('Binary files a/data.bin (4 bytes) and b/data.bin (4 bytes) differ', output)
        self.assertNotIn('two', output)
        cli(self.repo, 'add', 'data.bin')
        self.assertIn('Binary files', self.diff('--staged'))
        (self.repo / 'data.bin').unlink()
        self.assertIn('b/data.bin', self.diff())
        self.assertIn('/dev/null (0 bytes)', self.diff())
        self.write('bad-utf8.bin', b'\xffpayload')
        cli(self.repo, 'add', 'bad-utf8.bin')
        output = self.diff('--staged', '--', 'bad-utf8.bin')
        self.assertIn('change added', output)
        self.assertIn('Binary files', output)
        self.assertNotIn('payload', output)

    def test_filters_are_literal_paths_relative_to_cwd(self):
        self.baseline({'nested/one.txt': b'old\n', 'nested2.txt': b'old\n'})
        self.write('nested/one.txt', b'new\n')
        self.write('nested2.txt', b'other\n')
        result = self.diff('--', 'nested')
        self.assertIn('b/nested/one.txt', result)
        self.assertNotIn('nested2', result)
        self.assertEqual(result, self.diff('--', '.', cwd=self.repo / 'nested'))
        self.assertEqual(result, self.diff('--', 'one.txt', cwd=self.repo / 'nested'))
        self.assertEqual(self.diff('--', 'absent.txt'), '')
        self.assertEqual(self.diff(), self.diff('--', '.'))

    def test_unknown_flags_and_unsafe_paths_fail(self):
        self.baseline()
        before = inventory(self.repo)
        for args in (('--wat',), ('HEAD', '--staged'), ('--staged', '--cached'), ('file.txt',),
                     ('--', '../outside'), ('--', '/tmp/outside'), ('--', '.moonvcs/HEAD')):
            self.diff(*args, expected=1)
        self.assertEqual(inventory(self.repo), before)

    def test_symlink_leaf_dangling_and_ancestor_are_rejected(self):
        self.baseline({'nested/file.txt': b'safe\n'})
        mock = self.work / 'mock-resource'
        mock.write_text('MOCK-DO-NOT-READ\n')
        tracked = self.repo / 'nested/file.txt'
        tracked.unlink()
        for target in (mock, self.work / 'missing-mock'):
            tracked.symlink_to(target)
            output = self.diff(expected=1)
            self.assertIn('symbolic link', output)
            self.assertNotIn('MOCK-DO-NOT-READ', output)
            # Staged diff does not need or read the working files at all.
            self.assertEqual(self.diff('--staged'), '')
            tracked.unlink()
        tracked.parent.rmdir()
        tracked.parent.symlink_to(self.work, target_is_directory=True)
        self.assertIn('symbolic link', self.diff(expected=1))

    def test_fifo_is_rejected_without_blocking(self):
        self.baseline()
        tracked = self.repo / 'file.txt'
        tracked.unlink()
        os.mkfifo(tracked)
        self.assertIn('regular file', self.diff(expected=1))

    def test_directory_file_replacements_preserve_tracked_semantics(self):
        self.baseline({'leaf': b'old leaf\n', 'dir/item.txt': b'old item\n'})
        (self.repo / 'leaf').unlink()
        self.write('leaf/child.txt', b'new child\n')
        (self.repo / 'dir/item.txt').unlink()
        (self.repo / 'dir').rmdir()
        self.write('dir', b'new parent\n')
        result = self.diff()
        self.assertEqual(result.count('change deleted\n'), 2)
        self.assertNotIn('new child', result)
        self.assertNotIn('new parent', result)
        cli(self.repo, 'add', '.')
        result = self.diff('--staged')
        self.assertEqual(result.count('change deleted\n'), 2)
        self.assertEqual(result.count('change added\n'), 2)

    def test_every_mode_preserves_files_metadata_and_locks(self):
        self.baseline()
        self.write('file.txt', b'stage\n')
        cli(self.repo, 'add', 'file.txt')
        self.write('file.txt', b'work\n')
        self.write('untracked.txt', b'untouched\n')
        before = inventory(self.repo)
        for args in ((), ('--staged',), ('HEAD',), ('--cached', '--', 'file.txt')):
            self.diff(*args)
            cli(self.repo, '--offline', 'diff', *args)
        self.assertEqual(inventory(self.repo), before)
        self.assertFalse((self.repo / '.moonvcs/lazy-fetch.lock').exists())

    def test_corrupt_blob_fails_even_when_both_ids_match(self):
        self.baseline()
        ident = oid(object_bytes(1, b'base\n'))
        path = self.repo / '.moonvcs/objects' / ident[:2] / ident[2:]
        path.chmod(0o600)
        path.write_bytes(b'corrupt fixture')
        before = inventory(self.repo)
        for args in ((), ('--staged',), ('HEAD',)):
            self.assertIn('ObjectCorrupt', self.diff(*args, expected=8))
        self.assertEqual(inventory(self.repo), before)

    def test_index_must_identify_blobs_and_cannot_contain_path_conflicts(self):
        wrong = self.put(tree([]))
        self.set_index([('file.txt', wrong)])
        self.assertIn('ObjectCorrupt', self.diff('--staged', expected=8))
        blob = self.put(object_bytes(1, b'safe\n'))
        self.set_index([('a', blob), ('a/b', blob)])
        self.diff(expected=1)

    def test_head_graph_hash_type_missing_tree_and_unsafe_name(self):
        ref = self.repo / '.moonvcs/refs/heads/main'
        blob = self.put(object_bytes(1, b'harmless\n'))
        ref.write_text(blob + '\n')
        self.diff('HEAD', expected=8)
        target = self.put(commit('0' * 64))
        ref.write_text(target + '\n')
        self.assertIn('missing local object ' + '0' * 64, self.diff('HEAD', expected=1))
        target = self.put(commit(blob))
        ref.write_text(target + '\n')
        self.diff('HEAD', expected=8)
        unsafe_tree = self.put(tree([('.moonvcs', 1, blob)]))
        target = self.put(commit(unsafe_tree))
        ref.write_text(target + '\n')
        self.diff('HEAD', expected=1)

    def test_metadata_symlinks_are_rejected_without_touching_mock_targets(self):
        self.baseline()
        index = self.repo / '.moonvcs/index'
        mock = self.work / 'mock-index'
        mock.write_bytes(index.read_bytes())
        index.unlink()
        index.symlink_to(mock)
        before = inventory(self.repo)
        self.assertIn('symbolic link', self.diff(expected=1))
        self.assertEqual(inventory(self.repo), before)
        index.unlink()
        index.write_bytes(mock.read_bytes())
        metadata = self.repo / '.moonvcs'
        saved = self.work / 'mock-metadata'
        metadata.rename(saved)
        metadata.symlink_to(saved, target_is_directory=True)
        self.assertIn('symbolic link', self.diff(expected=1))
        metadata.unlink()
        saved.rename(metadata)
        # A malformed Ref parent is corruption, not a legitimately unborn HEAD.
        heads = metadata / 'refs/heads'
        heads.rename(self.work / 'saved-heads')
        heads.write_text('not a directory\n')
        self.assertIn('special file', self.diff('--staged', expected=1))

    def test_partial_clone_cache_hit_and_miss_are_strictly_read_only(self):
        self.baseline()
        parent = (self.repo / '.moonvcs/refs/heads/main').read_text().strip()
        self.write('second.txt', b'another safe snapshot file\n')
        cli(self.repo, 'add', 'second.txt')
        cli(self.repo, 'commit', '-m', 'second safe snapshot')
        clone = self.work / 'clone'
        cli(self.work, 'clone', str(self.repo), str(clone))
        self.assertFalse((clone / '.moonvcs/objects' / parent[:2] / parent[2:]).exists())
        before = inventory(clone)
        for args in ((), ('--staged',), ('HEAD',)):
            self.assertEqual(self.diff(*args, cwd=clone), '')
        self.assertEqual(inventory(clone), before)
        ident = oid(object_bytes(1, b'base\n'))
        cached = clone / '.moonvcs/objects' / ident[:2] / ident[2:]
        cached.unlink()
        before = inventory(clone)
        output = self.diff('HEAD', cwd=clone, expected=1)
        self.assertIn('missing local object ' + ident, output)
        self.assertIn('moonvcs show ' + ident, output)
        self.assertEqual(inventory(clone), before)
        cli(clone, 'show', ident)
        self.assertEqual(self.diff('HEAD', cwd=clone), '')

    def test_input_limits_fail_explicitly_before_printing_any_patch(self):
        self.baseline()
        with (self.repo / 'file.txt').open('wb') as file:
            file.truncate(8388609)
        output = self.diff(expected=1)
        self.assertIn('size limit', output)
        self.assertNotIn('diff --moonvcs', output)
        self.write('file.txt', b'\n' * 100001)
        self.assertIn('100000 lines', self.diff(expected=1))

    def test_terminal_controls_in_paths_and_content_are_escaped(self):
        name = '月亮\x1b[31m\n.txt'
        self.write(name, 'hello\x1b[31m\u202e\r\n'.encode())
        cli(self.repo, 'add', name)
        output = self.diff('--staged')
        self.assertIn('月亮\\u{1b}[31m\\u{a}.txt', output)
        self.assertIn('+hello\\u{1b}[31m\\u{202e}\\r\n', output)
        self.assertNotIn('\x1b', output)
        self.assertNotIn('\u202e', output)

    def test_observed_index_and_ref_changes_abort_before_output(self):
        self.baseline()
        self.write('file.txt', b'working changes\n')
        library = self.work / 'barrier.so'
        subprocess.run(['cc', '-shared', '-fPIC', '-O2', '-std=c11',
                        str(ROOT / 'tests/fixtures/staging-barrier.c'), '-ldl', '-o', str(library)], check=True)
        for role in ('index', 'ref'):
            environment = dict(os.environ, LD_PRELOAD=str(library), MOONVCS_STAGE_TEST_DIR=str(self.work),
                               MOONVCS_STAGE_TEST_INDEX=str(self.repo / 'file.txt'), MOONVCS_STAGE_TEST_ROLE=role)
            child = subprocess.Popen([str(BIN), 'diff', 'HEAD'], cwd=self.repo, env=environment,
                                     stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            try:
                wait_file(self.work / (role + '.read'))
                if role == 'index':
                    self.write('new.txt', b'new staged file\n')
                    cli(self.repo, 'add', 'new.txt')
                else:
                    ref = self.repo / '.moonvcs/refs/heads/main'
                    ref.write_bytes(ref.read_bytes() + b'\n')
                (self.work / (role + '.release')).touch()
                stdout, stderr = child.communicate(timeout=15)
                self.assertEqual(child.returncode, 1, stdout + stderr)
                self.assertIn(b'changed during comparison', stdout)
                self.assertNotIn(b'diff --moonvcs', stdout)
            finally:
                if child.poll() is None:
                    child.kill()
                    child.communicate()

    def test_randomized_unified_hunks_reconstruct_the_working_file(self):
        rng = random.Random(405)
        for _ in range(40):
            old = [rng.choice('abc') + '\n' for _ in range(rng.randrange(40))]
            new = old.copy()
            for _ in range(rng.randrange(1, 8)):
                start = rng.randrange(len(new) + 1)
                new[start:start + rng.randrange(4)] = [rng.choice('xyz') + '\n' for _ in range(rng.randrange(4))]
            self.write('file.txt', ''.join(old).encode())
            cli(self.repo, 'add', 'file.txt')
            self.write('file.txt', ''.join(new).encode())
            output = self.diff()
            result = []
            consumed = 0
            patch = output.splitlines(keepends=True)
            i = 0
            while i < len(patch):
                match = re.fullmatch(r'@@ -(\d+),(\d+) \+(\d+),(\d+) @@\n', patch[i])
                if not match:
                    i += 1
                    continue
                old_start, old_count, new_start, new_count = map(int, match.groups())
                start = old_start - (1 if old_count else 0)
                result.extend(old[consumed:start])
                consumed = start
                self.assertEqual(len(result), new_start - (1 if new_count else 0))
                seen_old = seen_new = 0
                i += 1
                while i < len(patch) and not patch[i].startswith('@@ '):
                    line = patch[i]
                    self.assertIn(line[0], ' +-')
                    if line[0] in ' -':
                        self.assertEqual(line[1:], old[consumed])
                        consumed += 1
                        seen_old += 1
                    if line[0] in ' +':
                        result.append(line[1:])
                        seen_new += 1
                    i += 1
                self.assertEqual((seen_old, seen_new), (old_count, new_count))
            result.extend(old[consumed:])
            self.assertEqual(result, new, output)


if __name__ == '__main__':
    unittest.main(verbosity=2)

#!/usr/bin/env python3
"""Count real CLI logical reads; no production hooks or physical-IO claims."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from staging_concurrency import cli

ROOT = Path(__file__).resolve().parents[1]
BIN = ROOT / 'target/bin/moonvcs'


class LazyReadAudit(unittest.TestCase):
    def test_one_get_reads_a_verified_wide_tree_once_without_skipping_promises(self):
        with tempfile.TemporaryDirectory(prefix='moonvcs-lazy-read-') as temporary:
            work = Path(temporary)
            remote = work / 'remote'
            remote.mkdir()
            cli(remote, 'init')
            names = [f'file-{i:03}.txt' for i in range(32)]
            for i, name in enumerate(names):
                (remote / name).write_text(f'harmless lazy read fixture {i}\n')
            cli(remote, 'add', *names)
            cli(remote, 'commit', '-m', 'safe wide snapshot')
            clone = work / 'clone'
            cli(work, 'clone', str(remote), str(clone))
            head = (clone / '.moonvcs/refs/heads/main').read_text().strip()
            commit = (clone / '.moonvcs/objects' / head[:2] / head[2:]).read_bytes()
            tree = commit[18:82].decode()
            path = clone / '.moonvcs/objects' / tree[:2] / tree[2:]
            self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), tree)
            before = cli(clone, 'storage-stats').stdout
            library = work / 'probe.so'
            subprocess.run(['cc', '-shared', '-fPIC', '-O2', '-std=c11',
                            str(ROOT / 'tests/fixtures/storage-io-probe.c'), '-ldl', '-o', str(library)], check=True)
            report = work / 'io.json'
            environment = dict(os.environ, LD_PRELOAD=str(library), MOONVCS_PROFILE_IO_REPORT=str(report),
                               MOONVCS_PROFILE_SOURCE_OBJECT=str(path))
            result = subprocess.run([str(BIN), 'show', tree, '--offline'], cwd=clone, env=environment,
                                    capture_output=True, timeout=20)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            counts = json.loads(report.read_text())
            self.assertEqual(counts['same_tree_reads'], 1)
            self.assertEqual(counts['promise_read_calls'], 2 * (len(names) + 1))
            self.assertEqual(cli(clone, 'storage-stats').stdout, before)


if __name__ == '__main__':
    unittest.main(verbosity=2)

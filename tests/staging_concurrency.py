#!/usr/bin/env python3
"""Cross-process staging regression, with a deterministic old-index barrier."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import signal
import struct
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
BIN = ROOT / 'target/bin/moonvcs'


def index_paths(repo):
    data = (repo / '.moonvcs/index').read_bytes()
    assert data[:9] == b'MOONIDX\0\x01'
    count = struct.unpack('>I', data[9:13])[0]
    offset = 13
    paths = []
    for _ in range(count):
        size = struct.unpack('>I', data[offset:offset + 4])[0]
        offset += 4
        paths.append(data[offset:offset + size].decode())
        offset += size + 64
    assert offset == len(data)
    return paths


def wait_file(path, timeout=10):
    end = time.monotonic() + timeout
    while not path.exists():
        if time.monotonic() >= end:
            raise AssertionError('barrier not reached: ' + str(path))
        time.sleep(.005)


def cli(repo, *args, binary=None, expected=0):
    result = subprocess.run([str(binary or BIN), *args], cwd=repo, capture_output=True, timeout=40)
    assert result.returncode == expected, (args, result.returncode, result.stdout, result.stderr)
    return result


def barrier_run(work, binary, expect_loss=False, kill_first=False):
    repo = work / 'repo'
    repo.mkdir()
    cli(repo, 'init', binary=binary)
    for name in ('first.txt', 'second.txt'):
        (repo / name).write_text('harmless staging test\n')
    library = work / 'barrier.so'
    subprocess.run(['cc', '-shared', '-fPIC', '-O2', '-std=c11', str(ROOT / 'tests/fixtures/staging-barrier.c'),
                    '-ldl', '-o', str(library)], check=True)
    def start(role):
        environment = dict(os.environ)
        environment.update(LD_PRELOAD=str(library), MOONVCS_STAGE_TEST_DIR=str(work),
                           MOONVCS_STAGE_TEST_INDEX=str(repo / '.moonvcs/index'), MOONVCS_STAGE_TEST_ROLE=role)
        return subprocess.Popen([str(binary), 'add', role + '.txt'], cwd=repo,
                                env=environment, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    first = start('first')
    second = None
    try:
        wait_file(work / 'first.read')
        second = start('second')
        if expect_loss:
            wait_file(work / 'second.read')
        else:
            time.sleep(.2)
            assert not (work / 'second.read').exists(), 'second writer read a stale index while first transaction was held'
        if kill_first:
            first.send_signal(signal.SIGKILL)
        else:
            (work / 'first.release').touch()
        first.communicate(timeout=10)
        assert first.returncode == (-signal.SIGKILL if kill_first else 0)
        wait_file(work / 'second.read')
        (work / 'second.release').touch()
        second.communicate(timeout=10)
        assert second.returncode == 0
        paths = index_paths(repo)
        expected = ['second.txt'] if expect_loss or kill_first else ['first.txt', 'second.txt']
        assert paths == expected, (paths, expected)
        return {'paths': paths, 'first_exit': first.returncode, 'second_exit': second.returncode,
                'stale_snapshot_loss_reproduced': expect_loss}
    finally:
        for child in (first, second):
            if child is not None and child.poll() is None:
                child.kill()
                child.communicate()


class StagingConcurrency(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='moonvcs-staging-test-')
        self.addCleanup(self.temp.cleanup)
        self.work = Path(self.temp.name)

    def test_barrier_serializes_complete_read_modify_write(self):
        barrier_run(self.work, BIN)

    def test_process_death_releases_transaction_lock(self):
        barrier_run(self.work, BIN, kill_first=True)

    def test_eight_process_writers_preserve_all_entries(self):
        repo = self.work
        cli(repo, 'init')
        names = [f'writer-{i}.txt' for i in range(8)]
        for name in names:
            (repo / name).write_text('harmless writer\n')
        with ThreadPoolExecutor(max_workers=8) as pool:
            list(pool.map(lambda name: cli(repo, 'add', name), names))
        self.assertEqual(index_paths(repo), names)

    def test_failed_add_preserves_index_and_releases_lock(self):
        repo = self.work
        cli(repo, 'init')
        before = (repo / '.moonvcs/index').read_bytes()
        cli(repo, 'add', 'missing.txt', expected=1)
        self.assertEqual((repo / '.moonvcs/index').read_bytes(), before)
        (repo / 'safe.txt').write_text('safe\n')
        cli(repo, 'add', 'safe.txt')
        self.assertEqual(index_paths(repo), ['safe.txt'])


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--reproduce-old', type=Path)
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    if args.reproduce_old:
        with tempfile.TemporaryDirectory(prefix='moonvcs-old-staging-') as temporary:
            result = barrier_run(Path(temporary), args.reproduce_old.resolve(), expect_loss=True)
        print(json.dumps(result, indent=2))
        if args.report:
            args.report.parent.mkdir(parents=True, exist_ok=True)
            args.report.write_text(json.dumps(result, indent=2) + '\n')
    else:
        unittest.main(argv=[__file__], verbosity=2)

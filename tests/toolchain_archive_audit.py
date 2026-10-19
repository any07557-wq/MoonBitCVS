#!/usr/bin/env python3
"""No-network archive source/pin regression; never uses real credentials."""
import hashlib
import importlib.util
from pathlib import Path
import tempfile
import sys
import unittest
import urllib.error
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('moonvcs_archives', ROOT / 'scripts/toolchain_archives.py')
archives = importlib.util.module_from_spec(spec)
spec.loader.exec_module(archives)
fresh_spec = importlib.util.spec_from_file_location('moonvcs_fresh', ROOT / 'scripts/fresh-install.py')
fresh = importlib.util.module_from_spec(fresh_spec)
with patch.dict(sys.modules, {'toolchain_archives': archives}):
    fresh_spec.loader.exec_module(fresh)


class ToolchainArchiveAudit(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='moonvcs-archive-test-')
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.data = b'harmless simulated archive bytes'
        self.entry = {'sha256': hashlib.sha256(self.data).hexdigest(), 'bytes': len(self.data),
                      'url': 'https://cli.moonbitlang.com/fake-pinned-version'}
        self.path = archives.archive_path(self.directory, self.entry)
        self.path.parent.mkdir()

    def test_pins_use_official_version_paths_not_latest(self):
        lock = archives.load_lock()
        self.assertEqual(lock['version'], '0.10.15+943464bfa')
        for entry in lock['archives'].values():
            self.assertIn('0.10.15%2B943464bfa', entry['url'])
            self.assertNotIn('latest', entry['url'])

    def test_valid_local_archive_needs_no_network(self):
        self.path.write_bytes(self.data)
        with patch.object(archives.urllib.request, 'urlopen', side_effect=AssertionError('network forbidden')):
            data, metadata = archives.read_archive(self.entry, self.directory)
        self.assertEqual(data, self.data)
        self.assertEqual(metadata['kind'], 'operator-local-cas')
        self.assertFalse(metadata['publisher_signature_verified'])

    def test_missing_and_corrupt_local_archives_never_fall_back(self):
        with patch.object(archives.urllib.request, 'urlopen', side_effect=AssertionError('network forbidden')):
            with self.assertRaises(FileNotFoundError):
                archives.read_archive(self.entry, self.directory)
            for data in (b'x' * len(self.data), self.data + b'extra', b'short'):
                self.path.write_bytes(data)
                with self.assertRaises(RuntimeError):
                    archives.read_archive(self.entry, self.directory)

    def test_local_archive_symlink_is_rejected_without_reading_target(self):
        mock = self.directory / 'mock-resource'
        mock.write_bytes(self.data)
        self.path.symlink_to(mock)
        with patch.object(archives.urllib.request, 'urlopen', side_effect=AssertionError('network forbidden')):
            with self.assertRaises(RuntimeError):
                archives.read_archive(self.entry, self.directory)

    def test_registry_401_renews_once_and_retries_the_same_digest(self):
        url = 'https://registry-1.docker.io/v2/library/rust/blobs/sha256:' + '0' * 64
        headers = {'Authorization': 'Bearer harmless-old', 'Accept': 'immutable-image'}
        seen = []
        def response(request_url, request_headers):
            seen.append((request_url, dict(request_headers)))
            if len(seen) == 1:
                raise urllib.error.HTTPError(url, 401, 'simulated expired token', {}, None)
            return b'unchanged layer bytes'
        renewed = []
        def renew():
            renewed.append(True)
            return 'Bearer harmless-new'
        with patch.object(fresh, 'fetch', side_effect=response):
            self.assertEqual(fresh.registry_fetch(url, headers, renew), b'unchanged layer bytes')
        self.assertEqual(renewed, [True])
        self.assertEqual([entry[0] for entry in seen], [url, url])
        self.assertEqual(seen[0][1]['Authorization'], 'Bearer harmless-old')
        self.assertEqual(seen[1][1]['Authorization'], 'Bearer harmless-new')
        self.assertEqual(seen[1][1]['Accept'], 'immutable-image')

    def test_repeated_registry_401_fails_after_one_renewal(self):
        renewed = []
        def renew():
            renewed.append(True)
            return 'Bearer harmless-new'
        error = urllib.error.HTTPError('https://registry-1.docker.io/mock', 401, 'simulated denial', {}, None)
        with patch.object(fresh, 'fetch', side_effect=error) as request:
            with self.assertRaises(urllib.error.HTTPError):
                fresh.registry_fetch('https://registry-1.docker.io/mock', {}, renew)
        self.assertEqual(request.call_count, 2)
        self.assertEqual(renewed, [True])

    def test_registry_403_does_not_retry_or_change_authorization(self):
        renewed = []
        error = urllib.error.HTTPError('https://registry-1.docker.io/mock', 403, 'simulated forbidden', {}, None)
        with patch.object(fresh, 'fetch', side_effect=error) as request:
            with self.assertRaises(urllib.error.HTTPError):
                fresh.registry_fetch('https://registry-1.docker.io/mock', {}, lambda: renewed.append(True))
        self.assertEqual(request.call_count, 1)
        self.assertEqual(renewed, [])


if __name__ == '__main__':
    unittest.main(verbosity=2)

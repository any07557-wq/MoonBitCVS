#!/usr/bin/env python3
"""Owned, no-network package/reproduction guard fixtures; never run archive code."""
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tarfile
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('moonvcs_reproduction', ROOT / 'scripts/reproduce-submission.py')
reproduction = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(reproduction)


class SubmissionAudit(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='moonvcs-submission-audit-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)

    def archive(self, name, entries):
        path = self.root / name
        with tarfile.open(path, 'w:gz') as stream:
            for entry in entries:
                if isinstance(entry, str):
                    info = tarfile.TarInfo(entry)
                    info.size = 1
                    stream.addfile(info, io.BytesIO(b'x'))
                else:
                    stream.addfile(entry)
        return path

    def package(self):
        for name in reproduction.ARCHIVES:
            self.archive(name, ['scripts/test.sh' if 'source' in name else 'target/reports/safe.log'])
        (self.root / 'SHA256SUMS').write_text(''.join(
            hashlib.sha256((self.root / name).read_bytes()).hexdigest() + '  ' + name + '\n'
            for name in reproduction.ARCHIVES))

    def test_both_fixed_archive_hashes_are_required_and_checked(self):
        self.package()
        self.assertEqual(set(reproduction.package_digests(self.root)), set(reproduction.ARCHIVES))
        (self.root / reproduction.ARCHIVES[0]).write_bytes(b'corrupt fixture')
        with self.assertRaises(ValueError):
            reproduction.package_digests(self.root)

    def test_checksum_paths_duplicates_and_missing_entries_are_rejected(self):
        self.package()
        text = (self.root / 'SHA256SUMS').read_text()
        for value in (text + text, text.splitlines()[0] + '\n', text.replace('MoonVCS-source.tar.gz', '../escape')):
            (self.root / 'SHA256SUMS').write_text(value)
            with self.assertRaises(ValueError):
                reproduction.package_digests(self.root)

    def test_entire_archive_is_validated_before_any_extraction(self):
        for name in ('../escape', '/absolute', 'docs/../escape', 'docs//alias'):
            archive = self.archive('bad.tar.gz', ['safe.txt', name])
            destination = self.root / 'unpacked'
            with self.assertRaises(ValueError):
                reproduction.extract_archive(archive, destination, source=True)
            self.assertFalse(destination.exists())

    def test_links_special_files_and_source_outputs_are_rejected(self):
        for kind in (tarfile.SYMTYPE, tarfile.LNKTYPE, tarfile.FIFOTYPE):
            entry = tarfile.TarInfo('mock-link')
            entry.type = kind
            entry.linkname = '../harmless-mock'
            archive = self.archive('bad.tar.gz', [entry])
            with self.assertRaises(ValueError):
                reproduction.extract_archive(archive, self.root / 'unpacked', source=True)
        for name in ('host/target/cached', 'vcs/.mooncakes/cached', '.toolchains/cargo/bin/cargo', '.moonvcs/HEAD'):
            archive = self.archive('bad.tar.gz', [name])
            with self.assertRaises(ValueError):
                reproduction.extract_archive(archive, self.root / 'unpacked', source=True)

    def test_existing_workdir_is_preserved_and_failure_is_recorded(self):
        work = self.root / 'work'
        work.mkdir()
        sentinel = work / 'private-mock'
        sentinel.write_text('keep')
        with self.assertRaises(FileExistsError):
            reproduction.reproduce(self.root, work, self.root, self.root / 'moon')
        self.assertEqual(sentinel.read_text(), 'keep')
        fresh = self.root / 'fresh'
        with self.assertRaises(FileNotFoundError):
            reproduction.reproduce(self.root, fresh, self.root, self.root / 'moon')
        report = json.loads((fresh / 'report.json').read_text())
        self.assertEqual((report['status'], report['exit'], report['stages']), ('failed', 1, []))
        self.assertFalse(report['cold_install_verified'])

    def test_valid_archives_are_separated_and_extracted_content_is_bound(self):
        self.package()
        manifest = reproduction.extract_archive(self.root / reproduction.ARCHIVES[0], self.root / 'source', source=True)
        reproduction.extract_archive(self.root / reproduction.ARCHIVES[1], self.root / 'evidence')
        self.assertEqual(manifest['scripts/test.sh']['sha256'], hashlib.sha256(b'x').hexdigest())
        self.assertFalse((self.root / 'source/target').exists())
        self.assertEqual((self.root / 'evidence/target/reports/safe.log').read_bytes(), b'x')


if __name__ == '__main__':
    unittest.main(verbosity=2)

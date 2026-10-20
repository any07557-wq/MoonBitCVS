#!/usr/bin/env python3
"""Owned, no-network package/reproduction guard fixtures; never run archive code."""
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
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

    def durable(self):
        import submission_evidence
        records = {'evidence/ci/run/report.json': b'public CI fixture',
                   'evidence/mooncakes/0.1.0/core.zip': b'public module fixture'}
        for name, data in records.items():
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
        manifest = self.root / submission_evidence.MANIFEST
        manifest.write_text(''.join(hashlib.sha256(data).hexdigest() + '  ' + name + '\n'
                                    for name, data in sorted(records.items())))
        return submission_evidence, manifest, records

    def test_durable_selection_includes_reviewed_ci_and_mooncakes_not_neighbor_files(self):
        helper, _, records = self.durable()
        (self.root / 'evidence/ci/unreviewed-mock.txt').write_text('do not include')
        self.assertEqual(set(helper.selected_files(self.root)), set(records) | {helper.MANIFEST})

    def test_durable_corrupt_and_missing_files_fail_closed(self):
        helper, _, records = self.durable()
        path = self.root / next(iter(records))
        path.write_bytes(b'corrupted fixture')
        with self.assertRaises(ValueError):
            helper.selected_files(self.root)
        path.unlink()
        with self.assertRaises(ValueError):
            helper.selected_files(self.root)

    def test_durable_manifest_rejects_duplicates_escapes_unreviewed_namespaces_and_missing_categories(self):
        helper, manifest, records = self.durable()
        original = manifest.read_text()
        digest = '0' * 64
        for value in (original + original, '', 'invalid\n',
                      digest + '  ../escape\n', digest + '  /absolute\n',
                      digest + '  evidence/ci/../escape\n', digest + '  evidence/ci//alias\n',
                      digest + '  evidence/ci/.moonvcs/private\n',
                      digest + '  evidence/personal/private\n',
                      original.splitlines()[0] + '\n'):
            manifest.write_text(value)
            with self.assertRaises(ValueError):
                helper.selected_files(self.root)

    def test_durable_symlink_file_ancestor_and_manifest_are_rejected(self):
        helper, manifest, records = self.durable()
        path = self.root / next(iter(records))
        saved = self.root / 'retained-fixture'
        path.rename(saved)
        path.symlink_to(saved)
        with self.assertRaises(ValueError):
            helper.selected_files(self.root)
        path.unlink()
        saved.rename(path)
        parent = path.parent
        moved = self.root / 'retained-directory'
        parent.rename(moved)
        parent.symlink_to(moved, target_is_directory=True)
        with self.assertRaises(ValueError):
            helper.selected_files(self.root)
        parent.unlink()
        moved.rename(parent)
        content = manifest.read_bytes()
        manifest.unlink()
        saved.write_bytes(content)
        manifest.symlink_to(saved)
        with self.assertRaises(ValueError):
            helper.selected_files(self.root)

    def test_durable_budgets_bound_manifest_and_file_reads(self):
        helper, _, _ = self.durable()
        for key, value in [('MAX_ENTRIES', 1), ('MAX_FILE_BYTES', 1), ('MAX_TOTAL_BYTES', 1)]:
            with patch.object(helper, key, value), self.assertRaises(ValueError):
                helper.selected_files(self.root)

    def test_durable_evidence_extracts_separately_and_verifies_its_manifest(self):
        helper, manifest, records = self.durable()
        archive = self.root / 'durable.tar.gz'
        with tarfile.open(archive, 'w:gz') as stream:
            for name in [helper.MANIFEST, *records]:
                stream.add(self.root / name, arcname=name, recursive=False)
        dest = self.root / 'separate-evidence'
        reproduction.extract_archive(archive, dest)
        self.assertEqual((dest / helper.MANIFEST).read_bytes(), manifest.read_bytes())
        for name, data in records.items():
            self.assertEqual((dest / name).read_bytes(), data)

    def test_durable_extraction_rejects_extra_files_and_missing_manifest(self):
        helper, _, records = self.durable()
        for index, names in enumerate((list(records), [helper.MANIFEST, *records, 'evidence/ci/extra.txt'])):
            archive = self.root / ('bad-' + str(index) + '.tar.gz')
            with tarfile.open(archive, 'w:gz') as stream:
                for name in names:
                    payload = (self.root / name).read_bytes() if (self.root / name).exists() else b'unreviewed mock'
                    info = tarfile.TarInfo(name)
                    info.size = len(payload)
                    stream.addfile(info, io.BytesIO(payload))
            with self.assertRaises(ValueError):
                reproduction.extract_archive(archive, self.root / ('bad-output-' + str(index)))

    def test_durable_cli_is_wired_into_the_real_packager_and_errors_do_not_emit_partial_lists(self):
        helper, manifest, records = self.durable()
        self.assertIn('submission_evidence.py', (ROOT / 'scripts/package-submission.sh').read_text())
        command = [sys.executable, str(ROOT / 'scripts/submission_evidence.py'), '--root', str(self.root)]
        result = subprocess.run(command, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(set(result.stdout.splitlines()), set(records) | {helper.MANIFEST})
        manifest.write_text(manifest.read_text() + 'invalid\n')
        result = subprocess.run(command, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, '')

    def packager_fixture(self):
        """Run the actual packager against owned source/report placeholders only.

        Read its prerequisite lists rather than copying private workspace reports.
        The real shell still checks every prerequisite and runs real tar/sha256sum.
        """
        script = (ROOT / 'scripts/package-submission.sh').read_text()
        def words(value):
            return shlex.split(value.replace('\\\n', ' '))
        for variable in ('MOONVCS_SOURCE_ITEMS', 'MOONVCS_EVIDENCE_ITEMS'):
            block = re.search(variable + r'=\((.*?)\n\)', script, re.S)[1]
            for name in words(block):
                path = self.root / name
                if variable == 'MOONVCS_SOURCE_ITEMS' and '.' not in path.name and name != 'LICENSE':
                    path.mkdir(parents=True, exist_ok=True)
                else:
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_text('owned packaging fixture\n')
        for match in re.finditer(r'for MOONVCS_NAME in \\\n(.*?); do\n(.*?)\ndone', script, re.S):
            names, body = match.groups()
            if 'Missing ' not in body:
                continue
            template = re.search(r'MOONVCS_ITEM="([^"]+)"', body)[1]
            for name in words(names):
                path = self.root / template.replace('$MOONVCS_NAME', name)
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('owned historical report fixture\n')
        for name in ('package-submission.sh', 'submission_evidence.py'):
            shutil.copyfile(ROOT / 'scripts' / name, self.root / 'scripts' / name)
        return ['bash', str(self.root / 'scripts/package-submission.sh')]

    def packaged_roundtrip(self, command, helper, records):
        result = subprocess.run(command, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        packages = list((self.root / 'target/releases').iterdir())
        self.assertEqual(len(packages), 1)
        package = packages[0]
        reproduction.package_digests(package)
        for name in reproduction.ARCHIVES:
            with tarfile.open(package / name) as stream:
                self.assertFalse(any(member.islnk() or member.issym() for member in stream))
            destination = self.root / ('unpacked-' + name)
            reproduction.extract_archive(package / name, destination, source='source' in name)
            if 'evidence' in name:
                self.assertEqual(set(helper.selected_files(destination)), set(records) | {helper.MANIFEST})
                for path, data in records.items():
                    self.assertEqual((destination / path).read_bytes(), data)

    def test_real_packager_normal_files_roundtrip_with_reproducer(self):
        helper, _, records = self.durable()
        self.packaged_roundtrip(self.packager_fixture(), helper, records)

    def assert_hardlink_preflight_failure(self, manifest_link=False):
        helper, manifest, records = self.durable()
        command = self.packager_fixture()
        name = helper.MANIFEST if manifest_link else next(iter(records))
        (self.root / 'unlisted-hardlink').hardlink_to(self.root / name)
        with self.assertRaisesRegex(ValueError, re.escape(name)):
            helper.selected_files(self.root)
        result = subprocess.run(command, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('hard-linked', result.stderr)
        self.assertIn(name, result.stderr)
        self.assertEqual(result.stdout, '')
        self.assertFalse((self.root / 'target/releases').exists())

    def test_real_packager_rejects_hardlinked_evidence_before_output(self):
        self.assert_hardlink_preflight_failure()

    def test_real_packager_rejects_hardlinked_manifest_before_output(self):
        self.assert_hardlink_preflight_failure(manifest_link=True)

    def test_real_packager_rejects_hardlinked_historical_report_before_output(self):
        self.durable()
        command = self.packager_fixture()
        name = 'target/reports/phase7-verify.json'
        (self.root / 'unlisted-hardlink').hardlink_to(self.root / name)
        result = subprocess.run(command, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('hard-linked', result.stderr)
        self.assertIn(name, result.stderr)
        self.assertEqual(result.stdout, '')
        self.assertFalse((self.root / 'target/releases').exists())

    def test_real_packager_accepts_identical_independent_files(self):
        helper, manifest, records = self.durable()
        for name in records:
            records[name] = b'identical but independent fixture'
            (self.root / name).write_bytes(records[name])
        manifest.write_text(''.join(hashlib.sha256(data).hexdigest() + '  ' + name + '\n'
                                    for name, data in sorted(records.items())))
        paths = [self.root / name for name in records]
        self.assertNotEqual(paths[0].stat().st_ino, paths[1].stat().st_ino)
        self.assertTrue(all(path.stat().st_nlink == 1 for path in paths))
        self.packaged_roundtrip(self.packager_fixture(), helper, records)


if __name__ == '__main__':
    unittest.main(verbosity=2)

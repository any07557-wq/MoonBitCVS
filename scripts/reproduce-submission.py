#!/usr/bin/env python3
"""Verify our local source/evidence package, then rebuild in a NEW retained directory.

Uses installed tools/global registry caches, not a new rootfs or offline bootstrap.
Only source is executed; evidence is inspected separately, never used as build input.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import sys
import tarfile
import time

sys.path.insert(0, str(Path(__file__).resolve().parent))
from submission_evidence import durable_path, verify_extracted

ARCHIVES = ('MoonVCS-source.tar.gz', 'MoonVCS-evidence.tar.gz')
EXCLUDED = {'target', '_build', '.mooncakes', '.toolchains', '__pycache__', '.moonvcs', '.git'}


def sha256(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def package_digests(package):
    expected = {}
    for line in (package / 'SHA256SUMS').read_text().splitlines():
        match = re.fullmatch(r'([0-9a-f]{64})  (MoonVCS-(?:source|evidence)\.tar\.gz)', line)
        if not match or match[2] in expected:
            raise ValueError('invalid/duplicate package checksum entry')
        expected[match[2]] = match[1]
    if set(expected) != set(ARCHIVES):
        raise ValueError('source and evidence archive checksums are both required')
    for name, digest in expected.items():
        path = package / name
        if path.is_symlink() or not path.is_file() or sha256(path) != digest:
            raise ValueError('package hash mismatch or unsupported file: ' + name)
    return expected


def extract_archive(archive, destination, source=False):
    """Validate ALL members before extracting; only regular files and directories."""
    with tarfile.open(archive, 'r:gz') as stream:
        members = stream.getmembers()
        seen = set()
        total = 0
        for member in members:
            name = member.name.rstrip('/') if member.isdir() else member.name
            path = PurePosixPath(name)
            if (not name or not path.parts or name != str(path) or path.is_absolute() or '..' in path.parts
                    or '\\' in name or any(ord(char) < 32 for char in name)
                    or name in seen or not (member.isfile() or member.isdir())
                    or member.mode & 0o7000):
                raise ValueError('unsafe/duplicate archive member: ' + member.name)
            if source and any(part in EXCLUDED for part in path.parts):
                raise ValueError('source archive contains excluded build/state path: ' + name)
            if not source and not (name.startswith('target/') or (name == 'target' and member.isdir())
                                   or durable_path(name, directory=member.isdir())):
                raise ValueError('evidence outside its expected target/durable namespaces')
            total += member.size
            if len(seen) >= 20000 or total > 268435456 or member.size > 134217728:
                raise ValueError('archive exceeds reproduction budget')
            seen.add(name)
        destination.mkdir(mode=0o700)
        stream.extractall(destination, members=members, filter='data')
    if not source:
        verify_extracted(destination)
    return file_manifest(destination)


def file_manifest(root):
    result = {}
    for path in sorted(root.rglob('*')):
        if any(part in EXCLUDED for part in path.relative_to(root).parts):
            continue
        if path.is_symlink():
            raise ValueError('source contains a symlink')
        if path.is_file():
            result[str(path.relative_to(root))] = {
                'sha256': sha256(path), 'mode': path.stat().st_mode & 0o777,
            }
    return result


def reproduce(package, work, toolchains, moon):
    work.mkdir(mode=0o700)  # Refuse existing output, including earlier failed runs.
    report = {'schema': 1, 'status': 'running', 'started_utc': datetime.now(timezone.utc).isoformat(),
              'package': str(package), 'workdir': str(work), 'stages': [],
              'source_clean': None, 'copied_project_outputs': None,
              'shared_installed_toolchain': True, 'shared_global_dependency_caches': True,
              'cargo_offline': True, 'all_network_disabled': False,
              'new_rootfs': False, 'cold_install_verified': False, 'power_loss_verified': False}

    def save():
        (work / 'report.json').write_text(json.dumps(report, indent=2) + '\n')

    def stage(label, args, cwd, environment):
        print('Reproduction stage:', label, flush=True)
        started = time.monotonic()
        log = work / (label + '.log')
        with log.open('xb') as stream:
            result = subprocess.run(args, cwd=cwd, env=environment, stdout=stream, stderr=subprocess.STDOUT)
        report['stages'].append({'stage': label, 'argv': list(map(str, args)), 'cwd': str(cwd),
                                 'exit': result.returncode, 'seconds': time.monotonic() - started, 'log': log.name})
        save()
        if result.returncode:
            raise RuntimeError(label + ' failed; see ' + str(log))

    save()
    try:
        report['archives'] = package_digests(package)
        source = work / 'source'
        manifest = extract_archive(package / ARCHIVES[0], source, source=True)
        (work / 'source-manifest.json').write_text(json.dumps(manifest, sort_keys=True, indent=2) + '\n')
        report['source_files'] = len(manifest)
        report['source_manifest_sha256'] = sha256(work / 'source-manifest.json')
        extract_archive(package / ARCHIVES[1], work / 'evidence')
        # Evidence is kept outside source; it must not populate project caches/outputs.
        if not (source / 'scripts/test.sh').is_file() or any(
                path.name in EXCLUDED for path in source.rglob('*')):
            raise ValueError('missing regression entry or copied build/state path')
        report.update(source_clean=True, copied_project_outputs=False)
        environment = dict(os.environ)
        environment.update(CARGO_HOME=str(toolchains / 'cargo'), RUSTUP_HOME=str(toolchains / 'rustup'),
                           PATH=str(toolchains / 'cargo/bin') + os.pathsep + environment.get('PATH', ''),
                           MOONVCS_MOON=str(moon), CARGO_NET_OFFLINE='true',
                           CARGO_TARGET_DIR=str(source / 'host/target'), CARGO_BUILD_JOBS='2')
        # Rust temporary outputs must not fill a small RAM-backed /tmp.
        temporary = work / 'tmp'
        temporary.mkdir(mode=0o700)
        environment['TMPDIR'] = str(temporary)
        for name in ('cargo', 'wasm-tools', 'wit-bindgen'):
            tool = toolchains / 'cargo/bin' / name
            if not os.access(tool, os.X_OK):
                raise ValueError('installed tool unavailable: ' + str(tool))
        if not os.access(moon, os.X_OK):
            raise ValueError('installed moon unavailable: ' + str(moon))
        report['toolchain_directory'] = str(toolchains)
        report['moon'] = str(moon)
        save()
        stage('environment', ['python3', 'scripts/environment.py', '--output', str(work / 'environment.json')],
              source, environment)
        stage('regression', ['bash', 'scripts/test.sh'], source, environment)
        if file_manifest(source) != manifest:
            raise ValueError('packaged source files changed during build/tests')
        if package_digests(package) != report['archives']:
            raise ValueError('input package changed during reproduction')
        report['source_unchanged_after_build'] = True
        report['runtime'] = {str(path.relative_to(source)): sha256(path)
                             for path in sorted((source / 'target/bin').iterdir()) if path.is_file()}
        report['status'] = 'passed'
        report['exit'] = 0
    except Exception as error:
        report.update(status='failed', exit=1, error=str(error))
        raise
    finally:
        report['finished_utc'] = datetime.now(timezone.utc).isoformat()
        save()
        print('Reproduction report:', work / 'report.json', flush=True)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package-dir', required=True, type=Path)
    parser.add_argument('--workdir', required=True, type=Path, help='NEW retained directory; parent must exist')
    parser.add_argument('--toolchain-dir', required=True, type=Path, help='installed toolchain/global caches, not build outputs')
    parser.add_argument('--moon', type=Path, default=Path(os.environ.get('MOONVCS_MOON') or shutil.which('moon') or '/home/user/.moon/bin/moon'))
    args = parser.parse_args()
    reproduce(args.package_dir.resolve(strict=True), args.workdir.absolute(), args.toolchain_dir.resolve(strict=True),
              args.moon.absolute())
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

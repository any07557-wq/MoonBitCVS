#!/usr/bin/env python3
"""Obtain pinned versioned MoonBit archives or verify an operator-held CAS copy.

No latest fallback, global install, archive execution or external publication.
This is not a Rust/registry offline bundle or a publisher-signature verifier.
"""
import argparse
import hashlib
import json
from pathlib import Path
import stat
import urllib.request

LOCK = Path(__file__).with_name('moonbit-archives.lock.json')


def load_lock():
    lock = json.loads(LOCK.read_text())
    if lock['schema'] != 1 or lock['platform'] != 'linux-x86_64' or set(lock['archives']) != {'moon', 'core'}:
        raise RuntimeError('unsupported archive lock')
    for entry in lock['archives'].values():
        if len(entry['sha256']) != 64 or any(c not in '0123456789abcdef' for c in entry['sha256']):
            raise RuntimeError('invalid pinned archive digest')
        if not entry['url'].startswith('https://cli.moonbitlang.com/') or '/latest/' in entry['url'] or 'core-latest' in entry['url']:
            raise RuntimeError('only explicit official version URLs are accepted')
        if not 0 < entry['bytes'] <= 150 * 1024 * 1024:
            raise RuntimeError('invalid pinned archive length')
    return lock


def archive_path(directory, entry):
    return directory / 'sha256' / (entry['sha256'] + '.tar.gz')


def read_archive(entry, directory=None):
    if directory is None:
        with urllib.request.urlopen(entry['url'], timeout=120) as stream:
            if not stream.geturl().startswith('https://'):
                raise RuntimeError('archive redirect downgraded HTTPS')
            data = stream.read(entry['bytes'] + 1)
        origin = {'kind': 'official-version-url', 'url': entry['url']}
    else:
        path = archive_path(directory, entry)
        # Archive directories are operator-controlled; reject static symlinks.
        if directory.is_symlink() or (directory / 'sha256').is_symlink() or not stat.S_ISREG(path.lstat().st_mode):
            raise RuntimeError('archive path is not a regular file')
        with path.open('rb') as stream:
            data = stream.read(entry['bytes'] + 1)
        origin = {'kind': 'operator-local-cas', 'path': str(path)}
    if len(data) != entry['bytes'] or hashlib.sha256(data).hexdigest() != entry['sha256']:
        raise RuntimeError('archive length/digest mismatch; no fallback or repinning')
    return data, {**origin, 'sha256': entry['sha256'], 'bytes': len(data), 'pinned_checksum_checked': True,
                  'publisher_signature_verified': False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('download', 'verify'))
    parser.add_argument('--directory', type=Path, required=True)
    args = parser.parse_args()
    directory = args.directory.absolute()
    lock = load_lock()
    report = {'schema': 1, 'version': lock['version'], 'platform': lock['platform'], 'archives': {},
              'status': 'running', 'public_mirror_created': False, 'full_offline_install': False}
    if args.action == 'download':
        if directory.exists():
            parser.error('download requires a nonexistent directory; preserve old artifacts')
        (directory / 'sha256').mkdir(parents=True)
    try:
        for name, entry in lock['archives'].items():
            data, metadata = read_archive(entry, directory if args.action == 'verify' else None)
            if args.action == 'download':
                with archive_path(directory, entry).open('xb') as stream:
                    stream.write(data)
            report['archives'][name] = metadata
        report['status'] = 'verified'
    except Exception as error:
        report['status'] = 'failed'
        report['error'] = str(error)
        raise
    finally:
        # verify is strictly read-only, including when the directory is corrupt.
        if args.action == 'download':
            (directory / 'archive-report.json').write_text(json.dumps(report, indent=2) + '\n')
        print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()

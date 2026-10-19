#!/usr/bin/env python3
"""Install only the existing checksum-pinned MoonBit archives into a NEW prefix.

No latest fallback, Rust install, registry bootstrap, global install or CI-pass claim.
An optional operator-held CAS supports local validation without a network download.
"""
import argparse
import io
import json
from pathlib import Path
import tarfile

import toolchain_archives


def install_moon(directory, archive_directory=None):
    if directory.exists() or directory.is_symlink():
        raise FileExistsError('MoonBit prefix must not exist; preserve the previous installation')
    lock = toolchain_archives.load_lock()
    # Verify BOTH downloads before creating the destination. The archives are
    # trusted only by the operator-maintained lock, not by a claimed signature.
    verified = {name: toolchain_archives.read_archive(entry, archive_directory)
                for name, entry in lock['archives'].items()}
    directory.mkdir(mode=0o700)
    for name, destination in (('moon', directory), ('core', directory / 'lib')):
        destination.mkdir(parents=True, exist_ok=True)
        with tarfile.open(fileobj=io.BytesIO(verified[name][0]), mode='r:gz') as stream:
            stream.extractall(destination, filter='data')
    # Official tarballs require the same explicit executable step as the installer.
    for path in (directory / 'bin').iterdir():
        if path.is_file() and not path.is_symlink():
            path.chmod(path.stat().st_mode | 0o111)
    tcc = directory / 'bin/internal/tcc'
    tcc.chmod(tcc.stat().st_mode | 0o111)
    if not (directory / 'bin/moon').is_file() or not (directory / 'lib/core/moon.mod').is_file():
        raise RuntimeError('pinned archives did not provide the expected tool layout')
    return {'status': 'installed_not_tested', 'version': lock['version'],
            'directory': str(directory), 'archives': {name: value[1] for name, value in verified.items()},
            'pinned_checksums_checked': True, 'publisher_signature_verified': False,
            'registry_bootstrapped': False, 'full_verification_passed': False,
            'github_actions_verified': False, 'cold_install_verified': False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', required=True, type=Path)
    parser.add_argument('--report', required=True, type=Path)
    parser.add_argument('--archive-dir', type=Path)
    args = parser.parse_args()
    if args.report.exists() or args.report.is_symlink():
        parser.error('report already exists; preserve it and choose a new path')
    report = {'status': 'failed', 'full_verification_passed': False,
              'github_actions_verified': False, 'cold_install_verified': False}
    try:
        report = install_moon(args.directory.absolute(), args.archive_dir)
    except Exception as error:
        report['error'] = str(error)
        raise
    finally:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        with args.report.open('x') as stream:
            stream.write(json.dumps(report, indent=2) + '\n')
        print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()

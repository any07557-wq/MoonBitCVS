#!/usr/bin/env python3
"""Download a clean official Rust OCI rootfs, bootstrap tools, then verify a source copy.

No host Moon/Rust/registry directories are mounted. Requires Linux bwrap and
network access. Preparation is NOT reported as a completed installation test.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import posixpath
import shutil
import subprocess
import tarfile
import time
import urllib.error
import urllib.request
import toolchain_archives

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ('README.md', 'ARCHITECTURE.md', 'SECURITY.md', 'ROADMAP.md', 'DEMO.md',
          'TESTING.md', 'INSTALL.md', 'LICENSE', '.gitignore', '.github', 'BRANCH_SWITCH.md', 'docs', 'examples',
          'scripts', 'tests', 'vcs', 'plugins', 'wit', 'host')
IMAGE_DIGEST = 'sha256:5f29c3b4cb8ad8c6f10df979595582dd67dd146ffebc70718e24ff2e5b4a194d'


def fetch(url, headers=None):
    with urllib.request.urlopen(urllib.request.Request(url, headers=headers or {}), timeout=120) as stream:
        return stream.read()


def digest(data):
    return 'sha256:' + hashlib.sha256(data).hexdigest()


def registry_fetch(url, headers, renew_authorization):
    """Retry the same immutable registry request once after a 401 challenge."""
    try:
        return fetch(url, headers)
    except urllib.error.HTTPError as error:
        if error.code != 401:
            raise
        error.close()
    # Fixed anonymous pull scope; never follow a challenge to another realm,
    # retry indefinitely, change the requested digest or log bearer credentials.
    headers['Authorization'] = renew_authorization()
    return fetch(url, headers)


def unpack(archive, destination):
    # Keep absolute image links equivalent inside the rootfs, but safe during host extraction.
    def safe(member, target):
        if '..' in PurePosixPath(member.name).parts or member.name.startswith('/'):
            raise RuntimeError('unsafe archive path')
        if member.issym() and member.linkname.startswith('/'):
            member.linkname = posixpath.relpath(member.linkname.lstrip('/'), posixpath.dirname(member.name) or '.')
        if member.islnk():
            member.linkname = member.linkname.lstrip('/')
        return tarfile.data_filter(member, target)
    with tarfile.open(archive) as stream:
        members = stream.getmembers()
        # OCI whiteouts operate only inside this newly allocated, owned rootfs.
        for member in members:
            name = PurePosixPath(member.name)
            if name.name.startswith('.wh.'):
                parent = destination.joinpath(*name.parent.parts).resolve()
                if not parent.is_relative_to(destination.resolve()):
                    raise RuntimeError('unsafe whiteout')
                paths = list(parent.iterdir()) if name.name == '.wh..wh..opq' and parent.exists() else [parent / name.name[4:]]
                for path in paths:
                    if path.is_symlink() or path.is_file():
                        path.unlink()
                    elif path.is_dir():
                        shutil.rmtree(path)
        stream.extractall(destination, members=[m for m in members if not PurePosixPath(m.name).name.startswith('.wh.')], filter=safe)


def inside(work, report, label, command, timeout=2400):
    rootfs = work / 'rootfs'
    args = ['bwrap', '--die-with-parent', '--unshare-user', '--uid', '0', '--gid', '0',
            '--unshare-pid', '--bind', str(rootfs), '/', '--proc', '/proc', '--dev', '/dev',
            '--tmpfs', '/tmp', '--clearenv', '--setenv', 'PATH',
            '/opt/moon/bin:/usr/local/cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin',
            '--setenv', 'MOON_HOME', '/opt/moon', '--setenv', 'MOONVCS_MOON', '/opt/moon/bin/moon',
            '--setenv', 'CARGO_HOME', '/usr/local/cargo', '--setenv', 'RUSTUP_HOME', '/usr/local/rustup',
            '--setenv', 'CARGO_BUILD_JOBS', '2']
    # Pass only networking configuration, never dump environment values into reports.
    for key in ('HTTPS_PROXY', 'HTTP_PROXY', 'ALL_PROXY', 'NO_PROXY', 'https_proxy', 'http_proxy', 'no_proxy'):
        if key in os.environ:
            args += ['--setenv', key, os.environ[key]]
    args += ['--chdir', '/workspace', '--', '/bin/bash', '--noprofile', '--norc', '-euo', 'pipefail', '-c', command]
    print('Fresh environment stage:', label, flush=True)
    start = time.monotonic()
    log_name = label + '-' + str(len(report.get('stages', [])) + 1) + '.log'
    with (work / log_name).open('wb') as log:
        result = subprocess.run(args, stdout=log, stderr=subprocess.STDOUT, timeout=timeout)
    report.setdefault('stages', []).append({'stage': label, 'command': command,
        'exit': result.returncode, 'seconds': time.monotonic() - start, 'log': log_name})
    (work / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    if result.returncode:
        raise RuntimeError(label + ' failed; inspect ' + str(work / log_name))


def prepare(work, report, archive_directory=None):
    work.mkdir(parents=True, exist_ok=False)
    downloads = work / 'downloads'
    downloads.mkdir()
    rootfs = work / 'rootfs'
    rootfs.mkdir()
    token_url = 'https://auth.docker.io/token?service=registry.docker.io&scope=repository:library/rust:pull'
    report['registry_auth_refresh_attempts'] = 0
    def request_authorization():
        response = json.loads(fetch(token_url, {'Cache-Control': 'no-cache'}))
        report['registry_token_ttl_seconds'] = response.get('expires_in')
        return 'Bearer ' + response['token']
    def renew_authorization():
        report['registry_auth_refresh_attempts'] += 1
        return request_authorization()
    headers = {'Authorization': request_authorization(), 'Accept': ', '.join((
        'application/vnd.oci.image.index.v1+json', 'application/vnd.oci.image.manifest.v1+json',
        'application/vnd.docker.distribution.manifest.list.v2+json', 'application/vnd.docker.distribution.manifest.v2+json'))}
    manifest_url = 'https://registry-1.docker.io/v2/library/rust/manifests/'
    data = registry_fetch(manifest_url + IMAGE_DIGEST, headers, renew_authorization)
    if digest(data) != IMAGE_DIGEST:
        raise RuntimeError('image manifest digest mismatch')
    report['image'] = 'docker.io/library/rust@' + IMAGE_DIGEST
    report['layers'] = []
    for layer in json.loads(data)['layers']:
        print('Downloading image layer:', layer['digest'], flush=True)
        data = registry_fetch('https://registry-1.docker.io/v2/library/rust/blobs/' + layer['digest'], headers, renew_authorization)
        if digest(data) != layer['digest']:
            raise RuntimeError('image layer digest mismatch')
        path = downloads / (layer['digest'].split(':')[1] + '.tar.gz')
        path.write_bytes(data)
        report['layers'].append({'digest': layer['digest'], 'bytes': len(data)})
        unpack(path, rootfs)
    (rootfs / 'workspace').mkdir(exist_ok=True)
    (rootfs / 'opt/moon').mkdir(parents=True)
    lock = toolchain_archives.load_lock()
    for key, name, destination in (
        ('moon', 'moon.tar.gz', rootfs / 'opt/moon'),
        ('core', 'core.tar.gz', rootfs / 'opt/moon/lib'),
    ):
        data, metadata = toolchain_archives.read_archive(lock['archives'][key], archive_directory)
        path = downloads / name
        path.write_bytes(data)
        report.setdefault('moon_downloads', []).append(metadata)
        destination.mkdir(parents=True, exist_ok=True)
        unpack(path, destination)
    prepare_tools(work, report)


def prepare_tools(work, report):
    rootfs = work / 'rootfs'
    # Official MoonBit tarballs rely on the installer's explicit chmod step.
    for path in (rootfs / 'opt/moon/bin').iterdir():
        if path.is_file():
            path.chmod(path.stat().st_mode | 0o111)
    tcc = rootfs / 'opt/moon/bin/internal/tcc'
    tcc.chmod(tcc.stat().st_mode | 0o111)
    report['host_toolchain_or_registry_mounted'] = False
    report['installation_verified'] = False
    inside(work, report, 'toolchain-prepare', '''
test ! -e /home/user/.moon
test ! -e /home/user/MoonBit_Program
test ! -d /usr/local/cargo/registry/src
test ! -d /usr/local/cargo/registry/cache
moon version --all
moon version | grep -F '0.1.20261012'
moonc -v 2>&1 | grep -F '0.10.15'
rustc --version | grep -F '1.99.1'
cargo --version
rustup component add rustfmt
python3 --version
cc --version
moon -C /opt/moon/lib/core bundle --warn-list -a --all
moon -C /opt/moon/lib/core bundle --warn-list -a --target wasm-gc --quiet
cargo install --locked wit-bindgen-cli --version 0.63.0
cargo install --locked wasm-tools --version 1.262.0
''')
    report['status'] = 'tools_prepared_not_verified'


def verify(work, report):
    if report.get('installation_verified'):
        report.setdefault('previous_verified_sources', []).append({
            'source_manifest_sha256': report.get('source_manifest_sha256'),
            'source_files': report.get('source_files'), 'stage_count': len(report['stages'])})
    report['installation_verified'] = False
    report['status'] = 'verifying'
    (work / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    destination = work / 'rootfs/workspace'
    if destination.is_symlink() or not destination.resolve().is_relative_to(work):
        raise RuntimeError('unsafe source destination')
    if (destination / 'README.md').exists():
        previous = work / 'rootfs' / ('workspace-attempt-' + str(len(report['stages'])))
        if previous.exists():
            raise RuntimeError('previous source attempt already archived')
        destination.rename(previous)
        destination.mkdir()
        report.setdefault('previous_source_attempts', []).append(str(previous.relative_to(work)))
        manifest = work / 'source-manifest.json'
        if manifest.exists():
            manifest.rename(work / ('source-manifest-attempt-' + str(len(report['stages'])) + '.json'))
    for name in SOURCE:
        origin = ROOT / name
        target = destination / name
        if origin.is_dir():
            shutil.copytree(origin, target, ignore=shutil.ignore_patterns('target', '_build', '.mooncakes', '.toolchains', '__pycache__', '.moonvcs', '.git'))
        else:
            if target.exists():
                raise RuntimeError('source destination already populated; use a new environment')
            shutil.copy2(origin, target)
    manifest = {str(path.relative_to(destination)): hashlib.sha256(path.read_bytes()).hexdigest()
                for path in destination.rglob('*') if path.is_file() and not path.is_symlink()}
    manifest_bytes = (json.dumps(manifest, sort_keys=True, indent=2) + '\n').encode()
    (work / 'source-manifest.json').write_bytes(manifest_bytes)
    report['source_manifest_sha256'] = hashlib.sha256(manifest_bytes).hexdigest()
    report['source_files'] = len(manifest)
    inside(work, report, 'moon-registry-bootstrap', 'moon -C vcs update')
    inside(work, report, 'fresh-regression', './scripts/test.sh')
    inside(work, report, 'fresh-four-demos', 'python3 scripts/hackathon-demo.py prepare --workdir target/fresh-demo --commits 40\npython3 scripts/hackathon-demo.py run --workdir target/fresh-demo --only all')
    report['installation_verified'] = True
    report['status'] = 'passed'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('prepare', 'resume-tools', 'install-rustfmt', 'verify', 'resume-verify'))
    parser.add_argument('--workdir', type=Path, required=True)
    parser.add_argument('--archive-dir', type=Path, help='operator-held MoonBit CAS; missing/corrupt files fail without network fallback')
    args = parser.parse_args()
    work = args.workdir.resolve()
    if not work.is_relative_to(ROOT / 'target') or not work.name.startswith('roadmap-fresh-'):
        parser.error('use a dedicated target/roadmap-fresh-* directory')
    if args.action == 'prepare' and work.exists():
        parser.error('prepare refuses an existing directory; previous reports were not changed')
    if args.archive_dir is not None and args.action != 'prepare':
        parser.error('--archive-dir applies only to prepare')
    report = {'schema': 1, 'status': 'running', 'installation_verified': False,
              'kernel_shared_with_host': True, 'source': str(ROOT), 'stages': []}
    try:
        if args.action == 'prepare':
            prepare(work, report, args.archive_dir.absolute() if args.archive_dir is not None else None)
        else:
            report = json.loads((work / 'report.json').read_text())
            if args.action == 'install-rustfmt':
                if not report.get('image') or report.get('installation_verified'):
                    raise RuntimeError('only repair an owned incomplete installation')
                if 'error' in report:
                    report.setdefault('past_errors', []).append(report.pop('error'))
                inside(work, report, 'install-rustfmt', 'rustup component add rustfmt\ncargo fmt --version')
                report['status'] = 'tools_prepared_not_verified'
            elif args.action == 'resume-tools':
                if not report.get('image') or report.get('installation_verified') or (work / 'rootfs').is_symlink():
                    raise RuntimeError('only resume a previously owned incomplete image bootstrap')
                if 'error' in report:
                    report.setdefault('past_errors', []).append(report.pop('error'))
                prepare_tools(work, report)
            elif args.action == 'resume-verify':
                if report.get('installation_verified') or not any(
                    stage['stage'] == 'toolchain-prepare' and stage['exit'] == 0 for stage in report['stages']
                ):
                    raise RuntimeError('complete tool preparation before resuming verification')
                if 'error' in report:
                    report.setdefault('past_errors', []).append(report.pop('error'))
                verify(work, report)
            elif report['status'] not in ('tools_prepared_not_verified', 'passed'):
                raise RuntimeError('complete a fresh preparation first')
            else:
                verify(work, report)
    except Exception as error:
        report['status'] = 'failed'
        report['error'] = str(error)
        print('Fresh installation stopped:', error, flush=True)
        return 1
    finally:
        if work.is_dir():
            (work / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
        print('Fresh installation evidence:', work / 'report.json', flush=True)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

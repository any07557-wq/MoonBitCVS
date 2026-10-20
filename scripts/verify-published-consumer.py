#!/usr/bin/env python3
"""Accept the fixed public native library, NOT the current source/Host/CLI.

Requires installed MoonBit+core bundles and a C compiler. Only compiler binaries
and stdlib are shared; registry/index/cache, dependency sources and builds are new.
No login, publication, local-module override, version override or cached fallback.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import signal
import subprocess
import sys
import time
import zipfile

ROOT = Path(__file__).resolve().parents[1]
MODULE = 'any07557-wq/moonvcs'
VERSION = '0.1.0'
PACKAGE_SHA256 = '5006035f75de4f963213a92257bafa3a5d2f751bb117c803c49d9c09f21867d3'
EXPECTED_OUTPUT = '3f2f7192ae4599c2d0886683b3b2833896f695ed1a83af663117e49a894deaa7'
FIXTURE_FILES = ('moon.mod', 'moon.pkg', 'consumer_test.mbt',
                 'cmd/readme/moon.pkg', 'cmd/readme/main.mbt')
CONSUMER_MODULE = ('name = "publication-smoke/registry-consumer"\n\n'
                   'preferred_target = "native"\n\nimport {\n'
                   '  "any07557-wq/moonvcs@0.1.0",\n}\n')


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def verify_payload(home, consumer):
    """Require the new registry ZIP AND byte-identical installed dependency files."""
    archive = home / 'registry/cache' / MODULE / (VERSION + '.zip')
    if archive.is_symlink() or not archive.is_file() or digest(archive) != PACKAGE_SHA256:
        raise ValueError('registry ZIP missing or differs from the frozen public 0.1.0')
    installed = consumer / '.mooncakes' / MODULE
    files = {}
    with zipfile.ZipFile(archive) as stream:
        for info in stream.infolist():
            name = info.filename
            path = PurePosixPath(name)
            if (str(path) != name or path.is_absolute() or '..' in path.parts
                    or info.is_dir() or name in files):
                raise ValueError('unsupported public ZIP member: ' + name)
            target = installed / name
            if any(p.is_symlink() for p in [target, *target.parents]):
                raise ValueError('installed module must not contain links: ' + name)
            data = stream.read(info)
            if not target.is_file() or target.read_bytes() != data:
                raise ValueError('installed module differs from registry ZIP: ' + name)
            files[name] = hashlib.sha256(data).hexdigest()
    actual = set()
    for path in installed.rglob('*'):
        if path.is_symlink() or not (path.is_file() or path.is_dir()):
            raise ValueError('installed dependency contains links/special files')
        if path.is_file():
            actual.add(path.relative_to(installed).as_posix())
    if actual != set(files):
        raise ValueError('installed dependency contains unexpected/missing files')
    return {'sha256': PACKAGE_SHA256, 'bytes': archive.stat().st_size,
            'files': files, 'registry_cache': str(archive)}


def verify(work, moon, toolchain_home=None, timeout=300):
    # Reject surrounding projects/workspaces: no accidental local resolution.
    work = work.parent.resolve(strict=True) / work.name
    for parent in [work.parent, *work.parent.parents]:
        if any((parent / name).exists() for name in ('moon.work', 'moon.work.json', 'moon.mod', 'moon.mod.json')):
            raise ValueError('consumer workdir must be outside a MoonBit project/workspace')
    if work == ROOT or ROOT in work.parents:
        raise ValueError('consumer workdir must be outside the source checkout')
    work.mkdir(mode=0o700)  # Never overwrite/reuse a prior run, successful or failed.
    report = {'schema': 1, 'status': 'running', 'exit': None,
              'scope': 'published_native_library_only', 'module': MODULE, 'version': VERSION,
              'python_version': sys.version.split()[0],
              'registry_url': 'https://download.mooncakes.io/user/' + MODULE + '/' + VERSION + '.zip',
              'expected_package_sha256': PACKAGE_SHA256, 'stages': [],
              'started_utc': datetime.now(timezone.utc).isoformat(),
              'current_source_regression_verified': False, 'github_actions_verified': False,
              'cold_os_install_verified': False, 'shared_compiler_and_stdlib': True}

    def save():
        (work / 'report.json').write_text(json.dumps(report, indent=2) + '\n')

    def stage(label, arguments, cwd, environment):
        argv = list(map(str, arguments))
        entry = {'name': label, 'argv': argv, 'cwd': str(cwd), 'exit': None,
                 'stdout': label + '.stdout.log', 'stderr': label + '.stderr.log'}
        report['stages'].append(entry)
        save()
        print('Published consumer:', label, flush=True)
        started = time.monotonic()
        try:
            with (work / entry['stdout']).open('xb') as out, (work / entry['stderr']).open('xb') as err:
                process = subprocess.Popen(argv, cwd=cwd, env=environment, stdout=out, stderr=err,
                                           start_new_session=True)
                try:
                    entry['exit'] = process.wait(timeout=timeout)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
                    entry.update(exit=124, timed_out=True)
            if entry['exit']:
                raise RuntimeError(label + ' failed (exit ' + str(entry['exit']) + ')')
            return (work / entry['stdout']).read_text()
        except Exception as error:
            entry['error'] = str(error)
            raise
        finally:
            entry['seconds'] = time.monotonic() - started
            save()

    save()
    try:
        moon = moon.resolve(strict=True)
        toolchain_home = (toolchain_home or moon.parent.parent).resolve(strict=True)
        if moon != (toolchain_home / 'bin/moon').resolve(strict=True):
            raise ValueError('--moon must belong to the selected installed toolchain home')
        if not (toolchain_home / 'lib/core/moon.mod').is_file():
            raise ValueError('installed toolchain has no lib/core/moon.mod')
        home = work / 'moon-home'
        home.mkdir(mode=0o700)
        (home / 'lib').mkdir()
        (home / 'bin').symlink_to(toolchain_home / 'bin', target_is_directory=True)
        (home / 'lib/core').symlink_to(toolchain_home / 'lib/core', target_is_directory=True)
        consumer = work / 'consumer'
        consumer.mkdir()
        report.update(moon=str(moon), toolchain_home=str(toolchain_home),
                      isolated_moon_home=str(home), registry_initially_absent=not (home / 'registry').exists())
        for name in FIXTURE_FILES:
            source = ROOT / 'examples/released-consumer' / name
            destination = consumer / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, destination)
        report['consumer_inputs'] = {name: digest(consumer / name) for name in FIXTURE_FILES}
        report['verifier_sha256'] = digest(Path(__file__))
        if (consumer / 'moon.mod').read_text() != CONSUMER_MODULE:
            raise ValueError('consumer module must use the fixed registry dependency without overrides')
        (work / 'tmp').mkdir(mode=0o700)
        # Do not inherit MOON_* overrides, credentials or arbitrary build flags.
        # Do not read/copy the user's existing Moon home or authentication state.
        environment = {'PATH': str(home / 'bin') + os.pathsep + os.environ.get('PATH', ''),
                       'LANG': 'C.UTF-8', 'LC_ALL': 'C.UTF-8', 'NO_COLOR': '1',
                       'MOON_HOME': str(home), 'TMPDIR': str(work / 'tmp')}
        report['versions'] = stage('moon-version', [moon, 'version', '--all'], work, environment)
        report['c_compiler'] = stage('cc-version', ['cc', '--version'], work, environment)
        if stage('anonymous', [moon, 'whoami'], work, environment).strip() != 'Not logged in':
            raise ValueError('consumer must use an anonymous new Moon home')
        report['anonymous_registry_consumer'] = True
        stage('update', [moon, '-C', consumer, 'update'], work, environment)
        stage('check', [moon, '-C', consumer, 'check', '--target', 'native', '--deny-warn'], work, environment)
        report['package'] = verify_payload(home, consumer)
        report['resolved_dependencies'] = stage('tree', [moon, '-C', consumer, 'tree'], work, environment)
        stdout = stage('test', [moon, '-C', consumer, 'test', '--target', 'native', '--deny-warn', '--frozen'], work, environment)
        combined = stdout + (work / 'test.stderr.log').read_text()
        if len(re.findall(r'Total tests: 2, passed: 2, failed: 0\.', combined)) != 1:
            raise ValueError('expected exactly the two published consumer tests to pass')
        report['consumer_tests_passed'] = 2
        output = stage('readme', [moon, '-C', consumer, 'run', 'cmd/readme', '--target', 'native',
                                  '--deny-warn', '--frozen'], work, environment)
        if output.strip() != EXPECTED_OUTPUT:
            raise ValueError('README example output differs from the known empty-blob vector')
        report['readme_example_passed'] = True
        verify_payload(home, consumer)
        if any(digest(consumer / name) != value for name, value in report['consumer_inputs'].items()):
            raise ValueError('consumer input changed during acceptance')
        report.update(status='passed', exit=0)
    except Exception as error:
        report.update(status='failed', exit=1, error=str(error))
        raise
    finally:
        report['finished_utc'] = datetime.now(timezone.utc).isoformat()
        save()
        print('Published consumer report:', work / 'report.json', flush=True)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--workdir', required=True, type=Path, help='NEW directory outside the source checkout')
    parser.add_argument('--moon', type=Path, default=Path(os.environ.get('MOONVCS_MOON') or shutil.which('moon') or 'moon'))
    parser.add_argument('--toolchain-home', type=Path, help='installed compiler/core prefix, NOT a registry cache')
    parser.add_argument('--timeout-seconds', type=int, default=300, help='per-command timeout; no retry/fallback')
    args = parser.parse_args()
    if args.timeout_seconds <= 0:
        parser.error('timeout must be positive')
    try:
        verify(args.workdir.absolute(), args.moon, args.toolchain_home, args.timeout_seconds)
    except Exception as error:
        print('Published consumer failed: ' + str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

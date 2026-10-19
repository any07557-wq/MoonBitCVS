#!/usr/bin/env python3
"""Replay the manual recovery instructions on NEW owned fixtures, never an existing repo.

This is an operator exercise, not a moonvcs recovery command. Retains all artifacts
when invoked directly; the unittest caller uses its own temporary directory.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import stat
import subprocess

from diff_audit import inventory
from staging_concurrency import wait_file

ROOT = Path(__file__).resolve().parents[1]


def file_manifest(root):
    """Content/type/mode comparison across copies, not inode/atime identity."""
    result = {}
    for path in sorted(root.rglob('*')):
        info = path.lstat()
        if stat.S_ISREG(info.st_mode):
            value = {'kind': 'file', 'mode': stat.S_IMODE(info.st_mode),
                     'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
        elif stat.S_ISDIR(info.st_mode):
            value = {'kind': 'directory', 'mode': stat.S_IMODE(info.st_mode)}
        else:
            raise RuntimeError('unexpected fixture path kind: ' + str(path))
        result[str(path.relative_to(root))] = value
    return result


def run_drill(output, binary=ROOT / 'target/bin/moonvcs', library=None):
    output = Path(output).absolute()
    binary = Path(binary).resolve(strict=True)
    # Deliberately refuses existing output; never accepts a repository to recover.
    output.mkdir(mode=0o700)
    transcript = output / 'commands.jsonl'
    checks = []

    def event(value):
        with transcript.open('a', encoding='utf-8') as stream:
            stream.write(json.dumps(value, ensure_ascii=False) + '\n')

    def require(condition, name):
        event({'check': name, 'passed': bool(condition)})
        if not condition:
            raise RuntimeError(name)
        checks.append(name)

    def command(cwd, *args, expected=0):
        result = subprocess.run([str(binary), *map(str, args)], cwd=cwd,
                                capture_output=True, timeout=40)
        event({'cwd': str(cwd), 'argv': [str(binary), *map(str, args)],
               'exit': result.returncode, 'stdout': result.stdout.decode('utf-8', 'replace'),
               'stderr': result.stderr.decode('utf-8', 'replace')})
        if result.returncode != expected:
            raise RuntimeError('unexpected CLI result; see ' + str(transcript))
        return result.stdout

    original = output / 'interrupted'
    original.mkdir(mode=0o700)
    command(original, 'init')
    (original / 'a.txt').write_bytes(b'old snapshot\n')
    (original / 'same.txt').write_bytes(b'unchanged\n')
    command(original, 'add', '.')
    command(original, 'commit', '-m', 'safe recovery old snapshot')
    command(original, 'branch', 'old')
    (original / 'a.txt').write_bytes(b'published snapshot\n')
    command(original, 'add', 'a.txt')
    command(original, 'commit', '-m', 'safe recovery published snapshot')
    metadata = original / '.moonvcs'
    published = (metadata / 'refs/heads/main').read_text().strip()
    target = (metadata / 'refs/heads/old').read_text().strip()
    lock_inode = (metadata / 'staging-transaction.lock').stat().st_ino
    notes = '笔记.bin'
    (original / notes).write_bytes(b'\x00\xff harmless untracked user notes\n')
    if library is None:
        library = output / 'switch-gate.so'
        compile_args = ['cc', '-shared', '-fPIC', '-O2', '-std=c11', '-Wall', '-Wextra', '-Werror',
                        str(ROOT / 'tests/fixtures/switch-gate.c'), '-ldl', '-o', str(library)]
        compiled = subprocess.run(compile_args, capture_output=True, timeout=40)
        event({'argv': compile_args, 'exit': compiled.returncode,
               'stdout': compiled.stdout.decode(), 'stderr': compiled.stderr.decode()})
        require(compiled.returncode == 0, 'compile test-only fault gate')
    gate = output / 'gate'
    gate.mkdir(mode=0o700)
    environment = dict(os.environ, LD_PRELOAD=str(library), MOONVCS_SWITCH_GATE_MODE='backup',
                       MOONVCS_SWITCH_GATE_DIR=str(gate), MOONVCS_SWITCH_METADATA=str(metadata))
    # Keep an editor-like old fd across rename, then stop all fixture writers.
    late = b'published snapshot\nlate user edit on original inode\n'
    with (original / 'a.txt').open('ab', buffering=0) as editor:
        child = subprocess.Popen([str(binary), 'switch', 'old'], cwd=original, env=environment,
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            wait_file(gate / 'entered', timeout=15)
            editor.write(b'late user edit on original inode\n')
            os.fsync(editor.fileno())
        finally:
            if child.poll() is None:
                child.kill()
            stdout, stderr = child.communicate(timeout=15)
            event({'cwd': str(original), 'argv': [str(binary), 'switch', 'old'],
                   'fault': 'SIGKILL after first backup fsync; old-fd edit before stopping writers',
                   'exit': child.returncode, 'stdout': stdout.decode(), 'stderr': stderr.decode()})
    require(child.returncode == -signal.SIGKILL, 'interrupted switch process has exited')
    live = b'user recreated file after interruption\n'
    (original / 'a.txt').write_bytes(live)
    pending = metadata / 'switch-transaction'
    manifest = json.loads((pending / 'manifest.json').read_text())
    change = next(i for i, item in enumerate(manifest['changes']) if item['path'] == 'a.txt')
    require((pending / 'before' / str(change)).read_bytes() == late, 'late inode edit retained in before/')
    require((pending / 'after' / str(change)).read_bytes() == b'old snapshot\n', 'uninstalled target retained in after/')
    stopped = inventory(original)
    report_before = json.loads(command(original, 'recover', '--check'))
    (output / 'recover-before.json').write_text(json.dumps(report_before, indent=2) + '\n')
    require(report_before['requires_attention'], 'recovery check reports incomplete state')
    command(original, 'add', 'same.txt', expected=18)
    require(inventory(original) == stopped, 'diagnostics and blocked mutation do not change original')

    # Preserve the ENTIRE repository, including worktree, locks, journal and objects.
    evidence = output / 'evidence'
    shutil.copytree(original, evidence, symlinks=True)
    preserved_manifest = file_manifest(original)
    require(file_manifest(evidence) == preserved_manifest, 'independent full evidence copy matches bytes/types/modes')
    (output / 'evidence-manifest.json').write_text(json.dumps(preserved_manifest, sort_keys=True, indent=2) + '\n')

    # Only in a disposable inspection copy: preserve-move the exact active journal.
    inspection = output / 'inspection'
    shutil.copytree(evidence, inspection, symlinks=True)
    retired = output / 'inspection-transaction-preserved'
    shutil.move(str(inspection / '.moonvcs/switch-transaction'), str(retired))
    event({'manual_action': 'preserve exact journal outside inspection copy; original/evidence untouched',
           'from': str(inspection / '.moonvcs/switch-transaction'), 'to': str(retired)})
    shown = command(inspection, 'show', 'HEAD', '--offline')
    require(shown.startswith(('commit ' + published + '\n').encode()), 'published HEAD identified independently of phase')
    require((inspection / '.moonvcs/index').read_bytes() == (retired / 'old-index').read_bytes(), 'index is saved old index')
    require((inspection / '.moonvcs/HEAD').read_bytes() == (retired / 'old-HEAD').read_bytes(), 'HEAD is saved old HEAD')

    # Explicit operator choice: reconstruct the LAST PUBLISHED snapshot, not target.
    rebuilt = output / 'rebuilt'
    command(output, 'clone', inspection, rebuilt)
    require(command(rebuilt, 'show', 'HEAD', '--offline').startswith(('commit ' + published + '\n').encode()),
            'new directory has selected published commit')
    require(command(rebuilt, 'diff') == b'' and command(rebuilt, 'diff', '--staged') == b'',
            'rebuilt worktree/index/HEAD agree before reapplying user data')
    require((rebuilt / 'a.txt').read_bytes() == b'published snapshot\n' and
            (rebuilt / 'same.txt').read_bytes() == b'unchanged\n', 'reconstructed snapshot bytes match known fixture')

    # Operator reconciliation, not automatic conflict resolution or journal replay.
    versions = output / 'user-versions'
    versions.mkdir(mode=0o700)
    shutil.copy2(evidence / '.moonvcs/switch-transaction/before' / str(change), versions / 'a-late-inode.txt')
    shutil.copy2(evidence / '.moonvcs/switch-transaction/after' / str(change), versions / 'a-uninstalled-target.txt')
    shutil.copy2(rebuilt / 'a.txt', versions / 'a-published.txt')
    shutil.copy2(evidence / 'a.txt', rebuilt / 'a.txt')
    shutil.copy2(evidence / notes, rebuilt / notes)
    event({'manual_action': 'operator selects live user file; retains late-inode, published and target versions separately',
           'rebuilt': str(rebuilt), 'other_versions': str(versions)})
    require((rebuilt / 'a.txt').read_bytes() == live and
            (versions / 'a-late-inode.txt').read_bytes() == late and
            (versions / 'a-published.txt').read_bytes() == b'published snapshot\n' and
            (versions / 'a-uninstalled-target.txt').read_bytes() == b'old snapshot\n' and
            (rebuilt / notes).read_bytes() == (evidence / notes).read_bytes(), 'all distinct user/target/published bytes retained')
    require(command(rebuilt, 'diff', '--staged') == b'', 'recovery does not stage or commit user edits')
    working_diff = command(rebuilt, 'diff')
    require(b'+user recreated file after interruption' in working_diff, 'reapplied user edit is visible as unstaged change')
    command(rebuilt, '--offline', 'status')
    require(not json.loads(command(rebuilt, 'recover', '--check'))['requires_attention'], 'rebuilt repository has no pending state')
    require(inventory(original) == stopped, 'original worktree, metadata and stable lock inode remain untouched')
    require((metadata / 'staging-transaction.lock').stat().st_ino == lock_inode and pending.is_dir(),
            'original stable lock and incomplete transaction are preserved')
    require(file_manifest(evidence) == preserved_manifest, 'evidence copy remained unchanged')
    result = {'schema': 1, 'automatic_recovery': False, 'power_loss_verified': False,
              'binary': str(binary), 'binary_sha256': hashlib.sha256(binary.read_bytes()).hexdigest(),
              'selected_ref': 'refs/heads/main', 'selected_commit': published, 'interrupted_target': target,
              'transaction': manifest['transaction'], 'fault': 'SIGKILL after backup',
              'original_unchanged_after_evidence_capture': True, 'evidence_copy_verified': True,
              'rebuilt_clean_snapshot_verified': True, 'all_user_versions_preserved': True,
              'rebuilt_has_unstaged_user_edit': True, 'checks': checks,
              'commands': str(transcript), 'artifacts_retained': True}
    (output / 'result.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output-dir', required=True, type=Path, help='NEW private fixture directory; must not exist')
    args = parser.parse_args()
    print(json.dumps(run_drill(args.output_dir), ensure_ascii=False, indent=2))

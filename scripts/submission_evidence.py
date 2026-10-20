#!/usr/bin/env python3
"""Read-only selection of reviewed durable evidence; never recursively include a tree."""
import argparse
import hashlib
from pathlib import Path, PurePosixPath
import re
import stat
import sys

MANIFEST = 'evidence/SUBMISSION_MANIFEST.sha256'
PREFIXES = ('evidence/ci/', 'evidence/mooncakes/')
FORBIDDEN = {'target', '_build', '.mooncakes', '.toolchains', '__pycache__', '.moonvcs', '.git'}
MAX_ENTRIES = 4096
MAX_FILE_BYTES = 16 * 1024 * 1024
MAX_TOTAL_BYTES = 64 * 1024 * 1024


def durable_path(name, directory=False):
    path = PurePosixPath(name)
    if (not name or str(path) != name or path.is_absolute() or '..' in path.parts
            or '\\' in name or any(ord(c) < 32 or ord(c) == 127 for c in name)
            or FORBIDDEN.intersection(path.parts)):
        return False
    if directory and name in ('evidence', 'evidence/ci', 'evidence/mooncakes'):
        return True
    return name == MANIFEST or name.startswith(PREFIXES)


def regular_file(root, name):
    path = root
    parts = PurePosixPath(name).parts
    for index, part in enumerate(parts):
        path = path / part
        try:
            mode = path.lstat().st_mode
        except FileNotFoundError as error:
            raise ValueError('missing reviewed evidence: ' + name) from error
        if (stat.S_ISLNK(mode) or (index < len(parts) - 1 and not stat.S_ISDIR(mode))
                or (index == len(parts) - 1 and not stat.S_ISREG(mode))):
            raise ValueError('evidence links/special files are forbidden: ' + name)
    return path


def selected_files(root):
    """Verify all entries before returning any; unlisted workspace neighbors stay out."""
    root = Path(root)
    if root.is_symlink():
        raise ValueError('evidence root must not be a symlink')
    manifest = regular_file(root, MANIFEST)
    if manifest.stat().st_size > 1024 * 1024:
        raise ValueError('evidence manifest exceeds budget')
    names = []
    total = 0
    for line in manifest.read_text(encoding='utf-8').splitlines():
        match = re.fullmatch(r'([0-9a-f]{64})  (.+)', line)
        if not match or not durable_path(match[2]) or match[2] == MANIFEST or match[2] in names:
            raise ValueError('invalid/duplicate durable evidence manifest entry')
        if len(names) >= MAX_ENTRIES:
            raise ValueError('evidence count exceeds budget')
        path = regular_file(root, match[2])
        size = path.stat().st_size
        total += size
        if size > MAX_FILE_BYTES or total > MAX_TOTAL_BYTES:
            raise ValueError('evidence size exceeds budget')
        with path.open('rb') as stream:
            digest = hashlib.file_digest(stream, 'sha256').hexdigest()
        if digest != match[1]:
            raise ValueError('reviewed evidence hash mismatch: ' + match[2])
        names.append(match[2])
    if not all(any(name.startswith(prefix) for name in names) for prefix in PREFIXES):
        raise ValueError('reviewed CI and Mooncakes evidence are both required')
    return [MANIFEST, *names]


def verify_extracted(root):
    """Legacy target-only bundles remain valid; durable records require an exact manifest."""
    root = Path(root)
    if not (root / 'evidence').exists():
        return
    selected = set(selected_files(root))
    actual = {p.relative_to(root).as_posix() for p in (root / 'evidence').rglob('*') if p.is_file()}
    if actual != selected:
        raise ValueError('evidence archive contains unreviewed or missing durable files')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    try:
        names = selected_files(args.root)
    except (ValueError, OSError, UnicodeError) as error:
        print('Durable evidence validation failed: ' + str(error), file=sys.stderr)
        return 1
    print('\n'.join(names))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

#!/usr/bin/env python3
"""Paired real-CLI Tree miss/hit comparison using copies of a verified dataset."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import statistics
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]


def invoke(binary, repository, *args, environment=None):
    start = time.perf_counter_ns()
    result = subprocess.run([str(binary), *args], cwd=repository, env=environment,
                            capture_output=True, timeout=60)
    elapsed = (time.perf_counter_ns() - start) / 1_000_000
    if result.returncode:
        raise RuntimeError(result.stderr.decode(errors='replace') + result.stdout.decode(errors='replace'))
    return result.stdout, elapsed


def counters(binary, repository):
    return {key: int(value) for key, value in json.loads(invoke(binary, repository, 'storage-stats')[0]).items()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile', type=Path, required=True)
    parser.add_argument('--before', type=Path, required=True)
    parser.add_argument('--after', type=Path, default=ROOT / 'target/bin/moonvcs')
    parser.add_argument('--workdir', type=Path, required=True)
    args = parser.parse_args()
    work = args.workdir.resolve()
    if work.exists():
        parser.error('use a nonexistent workdir; preserve existing evidence')
    original = json.loads((args.profile / 'result.json').read_text())
    tree = original['tree']
    if len(tree) != 64 or any(c not in '0123456789abcdef' for c in tree):
        parser.error('invalid Tree ID')
    template = args.profile.resolve() / f"clone-{original['objects']}-1"
    work.mkdir(parents=True)
    binaries = {}
    for label, source in [('before', args.before), ('after', args.after)]:
        destination = work / ('bin-' + label)
        destination.mkdir()
        shutil.copy2(source, destination / 'moonvcs')
        binaries[label] = destination / 'moonvcs'
    report = {'schema': 1, 'status': 'running', 'platform': platform.platform(),
              'kind': 'paired CLI profiling comparison, not a new three-scale benchmark',
              'template': str(template), 'tree': tree, 'objects': original['objects'],
              'binary_sha256': {label: hashlib.sha256(path.read_bytes()).hexdigest() for label, path in binaries.items()},
              'trials': [], 'io': {}, 'summary': {}}
    try:
        outputs = {}
        for trial in range(3):
            for label in (('before', 'after') if trial % 2 == 0 else ('after', 'before')):
                binary = binaries[label]
                clone = work / f'{label}-{trial}'
                shutil.copytree(template, clone)
                target = clone / '.moonvcs/objects' / tree[:2] / tree[2:]
                data = target.read_bytes()
                if hashlib.sha256(data).hexdigest() != tree or data[9] != 2:
                    raise RuntimeError('template Tree integrity/type check failed')
                # Only this newly owned copy loses its target object. The source
                # dataset/promises stay untouched; this models one authorized miss.
                target.unlink()
                before = counters(binary, clone)
                output, miss = invoke(binary, clone, 'show', tree)
                after = counters(binary, clone)
                delta = {key: after[key] - before[key] for key in before}
                if delta['received_objects'] != 1 or delta['received_bytes'] != len(data):
                    raise RuntimeError('miss did not transfer exactly the verified Tree')
                outputs.setdefault('miss', hashlib.sha256(output).hexdigest())
                if outputs['miss'] != hashlib.sha256(output).hexdigest():
                    raise RuntimeError('before/after miss outputs differ')
                hits = []
                for _ in range(3):
                    output, elapsed = invoke(binary, clone, 'show', tree, '--offline')
                    outputs.setdefault('hit', hashlib.sha256(output).hexdigest())
                    if outputs['hit'] != hashlib.sha256(output).hexdigest():
                        raise RuntimeError('before/after cached outputs differ')
                    hits.append(elapsed)
                if counters(binary, clone) != after:
                    raise RuntimeError('cached/offline reads changed transfer counters')
                report['trials'].append({'binary': label, 'trial': trial, 'miss_ms': miss,
                                         'hit_ms': hits, 'miss_transfer_delta': delta, 'repeat_transfers': 0})
                print(label, trial, 'miss', round(miss, 2), 'hit median', round(statistics.median(hits), 2), flush=True)
        library = work / 'probe.so'
        subprocess.run(['cc', '-shared', '-fPIC', '-O2', '-std=c11',
                        str(ROOT / 'tests/fixtures/storage-io-probe.c'), '-ldl', '-o', str(library)], check=True)
        for label, binary in binaries.items():
            clone = work / f'{label}-0'
            destination = work / f'{label}-io.json'
            environment = dict(os.environ, LD_PRELOAD=str(library), MOONVCS_PROFILE_IO_REPORT=str(destination),
                MOONVCS_PROFILE_SOURCE_OBJECT=str(clone / '.moonvcs/objects' / tree[:2] / tree[2:]))
            before = counters(binary, clone)
            invoke(binary, clone, 'show', tree, '--offline', environment=environment)
            if counters(binary, clone) != before:
                raise RuntimeError('IO probe caused transfers')
            report['io'][label] = json.loads(destination.read_text())
            rows = [item for item in report['trials'] if item['binary'] == label]
            report['summary'][label] = {
                'miss_median_ms': statistics.median(item['miss_ms'] for item in rows),
                'hit_median_ms': statistics.median(ms for item in rows for ms in item['hit_ms']),
                'miss_samples': 3, 'hit_samples': 9}
        if report['io']['after']['same_tree_reads'] != 1:
            raise RuntimeError('optimized get reread its verified target Tree')
        if report['io']['after']['promise_read_calls'] != report['io']['before']['promise_read_calls']:
            raise RuntimeError('optimization skipped promise metadata reads')
        report['output_sha256'] = outputs
        report['status'] = 'passed'
    finally:
        (work / 'result.json').write_text(json.dumps(report, indent=2) + '\n')
        print('Evidence:', work / 'result.json', flush=True)


if __name__ == '__main__':
    main()

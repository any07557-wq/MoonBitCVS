#!/usr/bin/env python3
"""Profile real wide-Tree CLI cache reads; keep this separate from formal benchmarks."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import resource
import shutil
import subprocess
import time
import benchmark

ROOT = Path(__file__).resolve().parents[1]


def analyze(work, report):
    binary = work / 'bin/moonvcs'
    if hashlib.sha256(binary.read_bytes()).hexdigest() != report['binary_sha256']:
        raise RuntimeError('frozen profile executable changed')
    clone = work / f"clone-{report['objects']}-1"
    tree = report['tree']
    command = [str(binary), 'show', tree]
    before = subprocess.check_output([binary, 'storage-stats'], cwd=clone)
    log = work / 'cpu.er/log.xml'
    if log.exists() and 'itimer could not be set' in log.read_text(errors='replace'):
        report['gprofng_clock_sampling'] = 'unavailable: itimer could not be set; retained IO-only experiment'
    # CPU instruction attribution needs no forbidden sampling timer.
    with (work / 'callgrind.log').open('wb') as log, open(os.devnull, 'wb') as output:
        result = subprocess.run(['valgrind', '--tool=callgrind', '--cache-sim=no',
                                 '--callgrind-out-file=' + str(work / 'callgrind.out'), *command],
                                cwd=clone, stdout=output, stderr=log, timeout=600)
    report['cpu_profile'] = {'tool': 'Valgrind Callgrind', 'exit': result.returncode,
                            'metric': 'instruction counts, not native elapsed time or sampled CPU time'}
    if result.returncode:
        raise RuntimeError('Callgrind failed')
    with (work / 'cpu-instructions.txt').open('wb') as output:
        subprocess.run(['callgrind_annotate', '--inclusive=yes', str(work / 'callgrind.out')],
                       stdout=output, stderr=subprocess.STDOUT, check=True, timeout=60)
    library = work / 'io-probe.so'
    subprocess.run(['cc', '-shared', '-fPIC', '-O2', '-std=c11',
                    str(ROOT / 'tests/fixtures/storage-io-probe.c'), '-ldl', '-o', str(library)], check=True)
    environment = dict(os.environ)
    environment.update(LD_PRELOAD=str(library), MOONVCS_PROFILE_IO_REPORT=str(work / 'io-counts.json'),
                       MOONVCS_PROFILE_SOURCE_OBJECT=str(clone / '.moonvcs/objects' / tree[:2] / tree[2:]))
    usage_before = resource.getrusage(resource.RUSAGE_CHILDREN)
    start = time.monotonic()
    with open(os.devnull, 'wb') as output:
        subprocess.run(command, cwd=clone, env=environment, stdout=output, check=True, timeout=60)
    usage_after = resource.getrusage(resource.RUSAGE_CHILDREN)
    report['io_profile'] = json.loads((work / 'io-counts.json').read_text())
    report['io_profile'].update(wall_ms=(time.monotonic() - start) * 1000,
        user_cpu_ms=(usage_after.ru_utime - usage_before.ru_utime) * 1000,
        system_cpu_ms=(usage_after.ru_stime - usage_before.ru_stime) * 1000,
        note='logical pread counts with interposer overhead; not physical disk bytes or a new benchmark')
    if before != subprocess.check_output([binary, 'storage-stats'], cwd=clone):
        raise RuntimeError('profile performed additional transfers')
    report['repeat_transfers'] = 0
    report['status'] = 'profiled'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--workdir', type=Path, required=True)
    parser.add_argument('--objects', type=int, default=10000)
    parser.add_argument('--analyze-existing', action='store_true')
    args = parser.parse_args()
    work = args.workdir.resolve()
    if args.analyze_existing:
        if (work / 'io-counts.json').exists():
            parser.error('analysis already exists; preserve it and use a fresh workdir')
        report = json.loads((work / 'result.json').read_text())
        try:
            analyze(work, report)
        finally:
            (work / 'result.json').write_text(json.dumps(report, indent=2) + '\n')
        print('CPU/IO evidence:', work, flush=True)
        return 0
    if work.exists():
        parser.error('workdir must not exist')
    if args.objects < 60 or args.objects % 20:
        parser.error('objects must be a multiple of 20 and at least 60')
    work.mkdir(parents=True)
    runtime = work / 'bin'
    runtime.mkdir()
    # Freeze the executable/configuration so later native rebuilds cannot alter this profile.
    for name in ('moonvcs', 'moonvcs-default-policy.json'):
        shutil.copy2(ROOT / 'target/bin' / name, runtime / name)
    benchmark.BIN = runtime / 'moonvcs'
    report = {'schema': 1, 'status': 'running', 'kind': 'profiling, not a new formal benchmark',
              'binary_sha256': hashlib.sha256(benchmark.BIN.read_bytes()).hexdigest(),
              'objects': args.objects, 'snapshots': 20, 'cpu_profile': {}, 'io_profile': {}}
    try:
        case = benchmark.measure_case(work, args.objects, 1, 20)
        report['case'] = case
        if case['status'] != 'passed':
            raise RuntimeError(case.get('error', 'dataset preparation failed'))
        clone = work / f'clone-{args.objects}-1'
        head = (clone / '.moonvcs/refs/heads/main').read_text().strip()
        encoded = (clone / '.moonvcs/objects' / head[:2] / head[2:]).read_bytes()
        parent = encoded[86:150].decode('ascii')
        encoded = (clone / '.moonvcs/objects' / parent[:2] / parent[2:]).read_bytes()
        tree = encoded[18:82].decode('ascii')
        report['tree'] = tree
        def counters():
            return subprocess.check_output([benchmark.BIN, 'storage-stats'], cwd=clone)
        before = counters()
        command = ['gprofng', 'collect', 'app', '-O', str(work / 'cpu.er'), '-F', 'off',
                   '-i', 'on', '-S', 'off', str(benchmark.BIN), 'show', tree]
        start = time.monotonic()
        with (work / 'collector.log').open('wb') as log:
            result = subprocess.run(command, cwd=clone, stdout=log, stderr=subprocess.STDOUT, timeout=300)
        report['collector'] = {'exit': result.returncode, 'seconds': time.monotonic() - start}
        if result.returncode:
            raise RuntimeError('gprofng collection failed; see collector.log')
        for label, option in (('cpu', '-functions'), ('io', '-ioactivity')):
            with (work / (label + '.txt')).open('wb') as output:
                result = subprocess.run(['gprofng', 'display', 'text', option, str(work / 'cpu.er')],
                                        stdout=output, stderr=subprocess.STDOUT, timeout=60)
            report[label + '_profile'] = {'exit': result.returncode, 'report': label + '.txt'}
        if before != counters():
            raise RuntimeError('profiled cache hit performed extra transfers')
        report['repeat_transfers'] = 0
        report['status'] = 'collected_pending_interpretation'
        analyze(work, report)
    except Exception as error:
        report['status'] = 'failed'
        report['error'] = str(error)
        print('Profiling stopped:', error, flush=True)
        return 1
    finally:
        (work / 'result.json').write_text(json.dumps(report, indent=2) + '\n')
        print('Profile evidence:', work, flush=True)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

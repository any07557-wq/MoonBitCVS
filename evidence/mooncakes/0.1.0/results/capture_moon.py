"""Capture a release command without persisting raw authenticated CLI output."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parent
EXPECTED = '5006035f75de4f963213a92257bafa3a5d2f751bb117c803c49d9c09f21867d3'


def sanitize(text):
    text = re.sub(r'https?://[^\s\"\x27)]+', '[URL omitted]', text)
    text = re.sub(r'(?im)^.*(?:token|password|authorization|credential|api[_-]?key|secret).*$',
                  '[auth-related line omitted]', text)
    return re.sub(r'[A-Za-z0-9_+/.=-]{32,}', '[opaque value omitted]', text)


def publish_gate(cwd):
    ready = json.loads((ROOT / 'READY_TO_PUBLISH.json').read_text())
    assert ready['authorized'] and ready['project_verification_passed']
    assert ready['server_dry_run_accepted'] and ready['version_absent_before_publish']
    assert ready['sha256'] == EXPECTED
    assert ready['module'] == 'any07557-wq/moonvcs' and ready['version'] == '0.1.0'
    assert ready['account_username'] == 'any07557-wq'
    preflight = json.loads((ROOT / 'preflight-final.json').read_text())
    assert preflight['server_reported_dry_run_success'] and not preflight['actual_publish']
    assert preflight['server_statuses_reported_by_cli'] == [202] and not preflight['timed_out']
    preflight_zip = ROOT / 'preflight-final-build/publish/any07557-wq-moonvcs-0.1.0.zip'
    assert hashlib.sha256(preflight_zip.read_bytes()).hexdigest() == EXPECTED
    before = json.loads((ROOT / 'registry-before.json').read_text())
    assert before['status'] == 'failure' and any('404 Not Found' in m['message'] for m in before['messages'])
    report = json.loads((ROOT / 'source/target/reports/phase7-verify.json').read_text())
    assert report['exit'] == 0
    assert [(s['stage'], s['exit']) for s in report['stages']] == [
        ('regression', 0), ('environment', 0), ('repeat-smoke', 0)]
    archive = ROOT / 'source/evidence/mooncakes/0.1.0/any07557-wq-moonvcs-0.1.0.zip'
    assert hashlib.sha256(archive.read_bytes()).hexdigest() == EXPECTED
    with zipfile.ZipFile(archive) as z:
        assert len(z.namelist()) == 33 and z.testzip() is None
        assert all(z.read(n) == (cwd / n).read_bytes() for n in z.namelist())
    # A single coordinator invocation only; nonzero/timeout must be inspected,
    # never retried by re-running this command.
    with (ROOT / 'PUBLISH_INVOCATION.json').open('x') as stream:
        json.dump({'started_utc': datetime.now(timezone.utc).isoformat(),
                   'module': 'any07557-wq/moonvcs', 'version': '0.1.0',
                   'sha256': EXPECTED, 'retry_authorized': False}, stream, indent=2)


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--label', required=True)
    p.add_argument('--cwd', type=Path, required=True)
    p.add_argument('--timeout', type=int, default=180)
    p.add_argument('command', nargs=argparse.REMAINDER)
    a = p.parse_args()
    command = a.command[1:] if a.command[:1] == ['--'] else a.command
    assert command and re.fullmatch(r'[a-z0-9-]+', a.label)
    log, result = ROOT / (a.label + '.log'), ROOT / (a.label + '.json')
    assert not log.exists() and not result.exists()
    actual_publish = 'publish' in command and '--dry-run' not in command
    if actual_publish:
        publish_gate(a.cwd)
    started = datetime.now(timezone.utc).isoformat()
    child = subprocess.Popen(command, cwd=a.cwd, stdin=subprocess.DEVNULL,
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                             text=True, start_new_session=True)
    timed_out = False
    try:
        output, _ = child.communicate(timeout=a.timeout)
    except subprocess.TimeoutExpired:
        timed_out = True
        os.killpg(child.pid, signal.SIGTERM)
        output, _ = child.communicate(timeout=20)
    safe = sanitize(output)
    log.write_text(safe)
    record = {'started_utc': started, 'finished_utc': datetime.now(timezone.utc).isoformat(),
              'cwd': str(a.cwd), 'command': command, 'cli_exit': child.returncode,
              'timed_out': timed_out, 'actual_publish': actual_publish,
              'server_statuses_reported_by_cli': [int(x) for x in re.findall(r'Server status:\s*(\d+)', output)],
              'server_reported_dry_run_success': 'Dry run completed successfully. No changes were made.' in output,
              'raw_cli_output_preserved': False, 'sanitized_log': log.name}
    result.write_text(json.dumps(record, indent=2) + '\n')
    print(json.dumps(record, indent=2))
    print(safe[-5000:])
    return 0 if child.returncode == 0 else 1


if __name__ == '__main__':
    sys.exit(main())

#!/usr/bin/env python3
"""Owned subprocess fixture for verifier guards. NOT MoonBit or registry evidence."""
import json
import os
from pathlib import Path
import shutil
import sys
import time
import zipfile

prefix = Path(__file__).resolve().parents[1]
options = json.loads((prefix / 'fixture.json').read_text())
args = sys.argv[1:]
if args[0] == '-C':
    consumer = Path(args[1])
    args = args[2:]
command = args[0]
if command == options.get('stall'):
    time.sleep(5)
if command == options.get('fail'):
    print('owned fixture command failure', file=sys.stderr)
    sys.exit(23)
if command == 'version':
    print('FAKE owned-tool fixture, NOT real MoonBit')
elif command == 'whoami':
    print(options.get('identity', 'Not logged in'))
elif command == 'update':
    registry = Path(os.environ['MOON_HOME']) / 'registry'
    assert not registry.exists(), 'fixture expected an initially empty registry'
    registry.mkdir()
elif command == 'check':
    archive = Path(os.environ['MOON_HOME']) / 'registry/cache/any07557-wq/moonvcs/0.1.0.zip'
    archive.parent.mkdir(parents=True)
    shutil.copyfile(prefix / 'payload.zip', archive)
    with zipfile.ZipFile(archive) as stream:
        # Test-owned small, known-safe ZIP, not an untrusted archive extractor.
        stream.extractall(consumer / '.mooncakes/any07557-wq/moonvcs')
elif command == 'tree':
    print('FAKE dependency resolution fixture: any07557-wq/moonvcs@0.1.0')
elif command == 'test':
    print(options.get('summary', 'Total tests: 2, passed: 2, failed: 0.'))
elif command == 'run':
    print(options.get('output', '3f2f7192ae4599c2d0886683b3b2833896f695ed1a83af663117e49a894deaa7'))

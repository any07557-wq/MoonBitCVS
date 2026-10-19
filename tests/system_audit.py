#!/usr/bin/env python3
"""Independent CLI security/integrity regression. Never reads real credentials."""

import hashlib
import json
import os
from pathlib import Path
import random
import shlex
import shutil
import stat
import struct
import subprocess
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[1]
BIN = ROOT / "target/bin/moonvcs"
HOST = ROOT / "target/bin/moonvcs-policy-host"


def u32(number):
    return struct.pack(">I", number)


def string(value):
    data = value.encode()
    return u32(len(data)) + data


def object_bytes(kind, payload):
    return b"MOONVCS\0" + bytes([1, kind]) + struct.pack(">Q", len(payload)) + payload


def oid(data):
    return hashlib.sha256(data).hexdigest()


def tree(entries):
    entries = sorted(entries, key=lambda entry: entry[0].encode())
    return object_bytes(2, u32(len(entries)) + b"".join(
        bytes([kind]) + string(name) + target.encode() for name, kind, target in entries
    ))


def commit(tree_id, parents=(), message="safe audit"):
    return object_bytes(3, tree_id.encode() + u32(len(parents))
                        + b"".join(parent.encode() for parent in parents)
                        + string("Untrusted audit fixture") + struct.pack(">Q", 1)
                        + string(message))


def bundle(target, objects, ref="refs/heads/main"):
    return b"MOONRX\0\0\x01" + string(ref) + b"\0" + target.encode() + u32(len(objects)) + b"".join(
        claimed.encode() + u32(len(data)) + data for claimed, data in objects
    )


class SystemAudit(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="moonvcs-system-audit-")
        self.addCleanup(self.temporary.cleanup)
        self.work = Path(self.temporary.name)
        self.server = self.work / "server"
        self.server.mkdir()
        self.cli(self.server, "init")
        self.cli(self.server, "receive-init")
        self.server_policy = (self.server / ".moonvcs/receive-policies.json").read_bytes()

    def cli(self, cwd, *args, wire=None, expected=0, env=None):
        result = subprocess.run([str(BIN), *map(str, args)], cwd=cwd, input=wire,
                                capture_output=True, timeout=15, env=env)
        output = result.stdout.decode(errors="replace") + result.stderr.decode(errors="replace")
        self.assertEqual(result.returncode, expected, output[:2000])
        self.assertNotIn("harmless-audit-env-sentinel", output)
        return output

    def assert_unpublished(self):
        self.assertFalse((self.server / ".moonvcs/refs/heads/main").exists())
        self.assertEqual(list((self.server / ".moonvcs/objects").glob("*/*")), [])
        quarantine = self.server / ".moonvcs/quarantine"
        self.assertTrue(not quarantine.exists() or not list(quarantine.iterdir()))
        self.assertEqual((self.server / ".moonvcs/receive-policies.json").read_bytes(), self.server_policy)

    def receive_invalid(self, data, expected=14):
        output = self.cli(self.server, "receive", "--stdin", wire=data, expected=expected)
        self.assertLess(len(output), 4096)
        self.assert_unpublished()

    def candidate(self, name="safe.txt", content=b"APP_MODE=safe\n", parents=()):
        blob = object_bytes(1, content)
        directory = tree([(name, 1, oid(blob))])
        change = commit(oid(directory), parents)
        objects = [(oid(data), data) for data in (blob, directory, change)]
        return oid(change), objects

    def test_external_object_oracle_and_functional_smoke(self):
        client = self.work / "client"
        client.mkdir()
        self.cli(client, "init")
        fixtures = {"empty.bin": b"", "binary.bin": b"\x00\xff\x01", "月亮.txt": "hello 🌙\n".encode()}
        for name, content in fixtures.items():
            (client / name).write_bytes(content)
        self.cli(client, "add", ".")
        self.assertIn("staged", self.cli(client, "status"))
        self.assertIn("Commit created", self.cli(client, "commit", "-m", "audit smoke"))
        head = (client / ".moonvcs/refs/heads/main").read_text().strip()
        self.assertIn(head, self.cli(client, "log"))
        self.assertIn(head, self.cli(client, "show", "HEAD"))
        for content in fixtures.values():
            encoded = object_bytes(1, content)
            target = oid(encoded)
            path = client / ".moonvcs/objects" / target[:2] / target[2:]
            self.assertEqual(path.read_bytes(), encoded)
        for path in (client / ".moonvcs/objects").glob("*/*"):
            self.assertEqual(oid(path.read_bytes()), path.parent.name + path.name)
        self.assertIn("Push accepted", self.cli(client, "push", self.server, "refs/heads/main", "none"))
        self.assertEqual((self.server / ".moonvcs/refs/heads/main").read_text().strip(), head)

    def test_deterministic_malformed_protocol_corpus(self):
        valid_framing = bundle("f" * 64, [])
        corpus = [valid_framing[:length] for length in range(len(valid_framing))]
        corpus += [valid_framing + b"client_policy_result=Pass", b"", b"MOONRX\0\0\xff"]
        randomizer = random.Random(707)
        for _ in range(64):
            changed = bytearray(valid_framing)
            for _ in range(3):
                changed[randomizer.randrange(len(changed))] = randomizer.randrange(256)
            corpus.append(bytes(changed))
        corpus += [valid_framing[:-4] + u32(number) for number in (4097, 0x7fffffff, 0xffffffff)]
        for data in corpus:
            self.receive_invalid(data)

    def test_hash_canonical_missing_parent_and_edge_type_fail_closed(self):
        target, objects = self.candidate()
        self.receive_invalid(bundle(target, [("0" * 64, objects[0][1]), *objects[1:]]))
        malformed = object_bytes(99, b"audit-malformed-object")
        self.receive_invalid(bundle(oid(malformed), [(oid(malformed), malformed)]))
        # Correct hashes/encoding but incomplete Tree and missing Parent closures.
        self.receive_invalid(bundle(target, [objects[0], objects[2]]))
        missing, missing_objects = self.candidate(parents=["f" * 64])
        self.receive_invalid(bundle(missing, missing_objects))
        wrong_type = commit(oid(objects[0][1]))
        self.receive_invalid(bundle(oid(wrong_type), [objects[0], (oid(wrong_type), wrong_type)]))
        # Huge count has only 4 payload bytes; decoder must not preallocate by count.
        enormous_tree = object_bytes(2, u32(0x7fffffff))
        self.receive_invalid(bundle(oid(enormous_tree), [(oid(enormous_tree), enormous_tree)]))

    def test_paths_and_snapshot_configuration_are_not_authority(self):
        for name in ("../escape", "/absolute", "a\\b", ".moonvcs", "..", "a\0b"):
            target, objects = self.candidate(name=name, content=b'{"required":[]}')
            self.receive_invalid(bundle(target, objects))
        target, objects = self.candidate()
        for ref in ("refs/heads/../../receive-policies.json", "refs/heads/.hidden", "refs/heads/main.lock", "refs/heads/a\nb"):
            self.receive_invalid(bundle(target, objects, ref=ref))
        self.assertFalse((self.work / "escape").exists())

    def test_secret_client_bypass_rejected_without_formal_objects(self):
        target, objects = self.candidate(content=b"MOONVCS_API_KEY=harmless-audit-do-not-print\n")
        result = self.cli(self.server, "receive", "--stdin", wire=bundle(target, objects), expected=12)
        self.assertIn("Policy: secret-scanner", result)
        self.assertNotIn("harmless-audit-do-not-print", result)
        self.assert_unpublished()

    def wrapper(self, body):
        path = self.work / "trusted-test-wrapper"
        path.write_text("#!/bin/sh\n" + body + "\nexec " + shlex.quote(str(HOST)) + ' "$@"\n')
        path.chmod(0o700)
        config = json.loads(self.server_policy)
        config["host"] = str(path)
        policy_file = self.work / "trusted-policy.json"
        policy_file.write_text(json.dumps(config))
        self.cli(self.server, "receive-policy-install", policy_file)
        return config

    def test_native_children_do_not_inherit_simulated_sensitive_environment(self):
        marker = self.work / "clean-environment-observed"
        config = self.wrapper(
            'if [ "${MOONVCS_AUDIT_SECRET+present}" = present ] || '
            '[ "${AWS_SECRET_ACCESS_KEY+present}" = present ]; then exit 86; fi\n'
            + "printf 'clean\\n' >> " + shlex.quote(str(marker))
        )
        client = self.work / "client"
        client.mkdir()
        self.cli(client, "init")
        (client / ".moonvcs/policies.json").write_text(json.dumps(config))
        (client / "safe.txt").write_text("APP_MODE=safe\n")
        self.cli(client, "add", ".")
        environment = dict(os.environ, MOONVCS_AUDIT_SECRET="harmless-audit-env-sentinel",
                           AWS_SECRET_ACCESS_KEY="harmless-audit-env-sentinel")
        self.cli(client, "commit", "-m", "environment audit", env=environment)
        self.cli(client, "push", self.server, "refs/heads/main", "none", env=environment)
        self.assertEqual(marker.read_text().splitlines(), ["clean", "clean"])

    def test_quarantine_is_private_until_real_policy_returns(self):
        entered, release = self.work / "entered", self.work / "release"
        self.wrapper("touch " + shlex.quote(str(entered)) + "\nwhile [ ! -e "
                     + shlex.quote(str(release)) + " ]; do sleep 0.01; done")
        target, objects = self.candidate()
        wire_file = self.work / "candidate.rx"
        wire_file.write_bytes(bundle(target, objects))
        process = subprocess.Popen([str(BIN), "receive", str(wire_file)], cwd=self.server,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            deadline = time.monotonic() + 10
            while not entered.exists() and time.monotonic() < deadline:
                if process.poll() is not None:
                    self.fail("receive exited before entering real Host wrapper")
                time.sleep(0.01)
            self.assertTrue(entered.exists())
            roots = list((self.server / ".moonvcs/quarantine").iterdir())
            self.assertEqual(len(roots), 1)
            self.assertEqual(stat.S_IMODE(roots[0].stat().st_mode), 0o700)
            self.assertTrue(list((roots[0] / ".moonvcs/objects").glob("*/*")))
            self.assertEqual(list((self.server / ".moonvcs/objects").glob("*/*")), [])
            self.assertFalse((self.server / ".moonvcs/refs/heads/main").exists())
            release.touch()
            stdout, stderr = process.communicate(timeout=15)
            self.assertEqual(process.returncode, 0, (stdout + stderr).decode(errors="replace"))
            self.assertIn(b"Push accepted", stdout)
            self.assertEqual(list((self.server / ".moonvcs/quarantine").iterdir()), [])
        finally:
            release.touch(exist_ok=True)
            if process.poll() is None:
                process.kill()
                process.communicate(timeout=5)

    def test_all_real_components_still_have_no_imports(self):
        local = ROOT / ".toolchains/cargo/bin/wasm-tools"
        wasm_tools = os.environ.get("MOONVCS_WASM_TOOLS") or (
            str(local) if os.access(local, os.X_OK) else shutil.which("wasm-tools"))
        self.assertIsNotNone(wasm_tools, "wasm-tools was not found")
        for plugin in ("secret-scanner", "license-check", "hello-policy", "restricted-plugin", "adversarial-fixture"):
            result = subprocess.run([wasm_tools, "component", "wit", str(ROOT / f"target/components/{plugin}.component.wasm")],
                                    capture_output=True, check=True, text=True, timeout=10)
            self.assertNotIn("import ", result.stdout)
            self.assertIn("export moonvcs:policy/evaluator@0.1.0", result.stdout)

    def test_untrusted_display_fields_cannot_emit_terminal_control_sequences(self):
        client = self.work / "display-client"
        client.mkdir()
        self.cli(client, "init")
        name = "safe\x1b[31m.txt"
        content = b"safe\n\x1b[31mharmless-color-fixture\x1b[0m"
        (client / name).write_bytes(content)
        self.assertNotIn("\x1b", self.cli(client, "add", name))
        self.assertNotIn("\x1b", self.cli(client, "status"))
        environment = dict(os.environ, MOONVCS_AUTHOR="Audit\x1b[31m")
        self.cli(client, "commit", "-m", "safe\x1b[31m\nforged-line", env=environment)
        self.cli(client, "push", self.server, "refs/heads/main", "none")
        for command in (("log",), ("show", "HEAD")):
            output = self.cli(self.server, *command)
            self.assertNotIn("\x1b", output)
            self.assertIn("\\nforged-line", output)
        blob = object_bytes(1, content)
        directory = tree([(name, 1, oid(blob))])
        for target in (oid(blob), oid(directory)):
            self.assertNotIn("\x1b", self.cli(self.server, "show", target))
        target = oid(blob)
        self.assertEqual((self.server / ".moonvcs/objects" / target[:2] / target[2:]).read_bytes(), blob)


if __name__ == "__main__":
    unittest.main(verbosity=2)

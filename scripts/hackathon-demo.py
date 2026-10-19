#!/usr/bin/env python3
"""Four real prebuilt hackathon demos; preparation is explicitly off-stage."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[1]
BIN = ROOT / "target/bin/moonvcs"
HOST = ROOT / "target/bin/moonvcs-policy-host"
BYPASS = ROOT / "target/bin/moonvcs-bypass-client"
SENTINELS = ("harmless-stage8-do-not-log", "harmless-bypass-only-do-not-log")


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def inventory(repository):
    count, size = 0, 0
    kinds = {}
    for path in (repository / ".moonvcs/objects").glob("*/*"):
        data = path.read_bytes()
        require(hashlib.sha256(data).hexdigest() == path.parent.name + path.name, "object hash mismatch")
        require(data[:9] == b"MOONVCS\0\x01", "invalid object envelope")
        kinds[data[9]] = kinds.get(data[9], 0) + 1
        count += 1
        size += len(data)
    return {"objects": count, "encoded_bytes": size, "kinds": kinds}


def head(repository):
    path = repository / ".moonvcs/refs/heads/main"
    return path.read_text().strip() if path.exists() else None


class Demo:
    def __init__(self):
        self.lines = []
        self.commands = []
        self.results = {}

    def say(self, value):
        self.lines.append(value)
        print(value, flush=True)

    def command(self, cwd, *args, expected=0, visible=True):
        command = [str(arg) for arg in args]
        display = [Path(command[0]).name, *command[1:]]
        if visible:
            self.say("$ " + shlex.join(display))
        start = time.perf_counter()
        result = subprocess.run(command, cwd=cwd, capture_output=True, text=True, timeout=60)
        output = result.stdout + result.stderr
        require(not any(value in output for value in SENTINELS), "fixture value leaked in command output")
        self.commands.append({
            "argv": command, "cwd": str(cwd), "expected_exit": expected,
            "actual_exit": result.returncode, "elapsed_ms": (time.perf_counter() - start) * 1000,
        })
        if visible or result.returncode != expected:
            self.say(output.rstrip())
        require(result.returncode == expected, "unexpected command exit; demo stopped")
        return output

    def cli(self, cwd, *args, **kwargs):
        return self.command(cwd, BIN, *args, **kwargs)

    def secret(self, root):
        root.mkdir()
        self.say("\nDEMO 1 | Real MoonBit Wasm Secret Scanner -> Reject -> repair -> Pass")
        self.cli(root, "init")
        self.say("Write config.env with a harmless simulated API key; value intentionally not echoed.")
        (root / "config.env").write_text("MOONVCS_API_KEY=harmless-stage8-do-not-log\n")
        self.cli(root, "add", "config.env")
        index = (root / ".moonvcs/index").read_bytes()
        rejected = self.cli(root, "commit", "-m", "add config", expected=2)
        require("Policy: secret-scanner" in rejected, "real Scanner did not reject")
        require(head(root) is None, "rejected commit changed HEAD")
        require(inventory(root)["kinds"].get(3, 0) == 0, "rejected Commit object was written")
        require((root / ".moonvcs/index").read_bytes() == index, "rejection changed stage")
        self.say("Verified: HEAD is still unborn; staged data remains recoverable.")
        (root / "config.env").write_text("APP_MODE=demo\n")
        self.say("Replace the fixture with APP_MODE=demo, then re-stage.")
        self.cli(root, "add", "config.env")
        accepted = self.cli(root, "commit", "-m", "add safe config")
        require("Policy passed" in accepted and head(root), "repaired commit did not publish")
        self.cli(root, "log", "--max-count", "1")
        self.results["secret"] = {"rejected_exit": 2, "head_preserved": True, "repair_passed": True}

    def capability(self, root):
        root.mkdir()
        self.say("\nDEMO 2 | Same WIT v1, filtered request, actual CapabilityDenied")
        (root / "allowed.txt").write_bytes(b"harmless-allowed-content")
        component = ROOT / "target/components/restricted-plugin.component.wasm"
        manifest = ROOT / "plugins/restricted-plugin/plugin.toml"
        args = (HOST, "--component", component, "--manifest", manifest,
                "--message", "metadata-must-be-filtered", "--file", "allowed.txt")
        result = self.command(root, *args, "--policy", ROOT / "examples/repository-policy.toml")
        require(json.loads(result)["status"] == "pass", "restricted guest did not confirm filtered request")
        self.say("Guest verified: staged read only; commit metadata absent; no ambient imports.")
        denied = self.command(root, *args, "--policy", ROOT / "examples/repository-policy-deny-content.toml", expected=3)
        require("CapabilityDenied" in denied, "missing grant was not denied")
        extra = root / "overrequested.toml"
        original = manifest.read_text()
        expected = 'requested_capabilities = ["staged_content.read"]'
        require(expected in original, "unexpected Restricted manifest")
        extra.write_text(original.replace(expected, 'requested_capabilities = ["staged_content.read", "repository.secrets.read"]'))
        unsupported = self.command(root, HOST, "--component", component, "--manifest", extra,
                                   "--policy", ROOT / "examples/repository-policy.toml",
                                   "--file", "allowed.txt", expected=3)
        require("not provided by this host" in unsupported, "unsupported declaration did not fail")
        self.say("Denied before instantiation. repository.secrets.read is NOT an implemented callback.")
        self.results["capability"] = {"authorized_guest_passed": True, "missing_grant_exit": 3,
                                      "unsupported_request_exit": 3, "component_sha256": hashlib.sha256(component.read_bytes()).hexdigest()}

    def lazy(self, root, remote):
        self.say("\nDEMO 3 | Real partial clone -> lazy history -> verified cache -> offline flag")
        source = inventory(remote)
        self.say(f"Measured remote: {source['objects']} objects / {source['encoded_bytes']} encoded bytes")
        self.cli(root.parent, "clone", remote, root)
        initial = inventory(root)
        stats = json.loads(self.cli(root, "storage-stats"))
        require(initial["objects"] < source["objects"], "clone downloaded complete history")
        require(int(stats["received_objects"]) == initial["objects"], "clone object accounting mismatch")
        require(int(stats["received_bytes"]) == initial["encoded_bytes"], "clone byte accounting mismatch")
        self.say(f"Measured initial cache: {initial['objects']} objects / {initial['encoded_bytes']} encoded bytes")
        history = self.cli(root, "log", "--max-count", "4")
        require("[Fetch] Hash Verified" in history and "[Fetch] Cached" in history, "no real historical fetch")
        after = inventory(root)
        before_repeat = self.cli(root, "storage-stats", visible=False)
        repeated = self.cli(root, "log", "--max-count", "4")
        require("[Fetch]" not in repeated, "cache hit unexpectedly fetched")
        require(self.cli(root, "storage-stats", visible=False) == before_repeat, "repeat changed transfer counters")
        self.cli(root, "log", "--max-count", "4", "--offline")
        oldest = re.findall(r"^commit ([0-9a-f]{64})$", history, flags=re.MULTILINE)[-1]
        detail = self.cli(root, "show", oldest, visible=False)
        parent = re.search(r"^parent ([0-9a-f]{64})$", detail, flags=re.MULTILINE).group(1)
        unavailable = self.cli(root, "show", parent, "--offline", expected=4)
        require("ObjectUnavailableOffline" in unavailable, "offline miss did not fail explicitly")
        self.say(f"Measured history cache: {after['objects']} objects / {after['encoded_bytes']} encoded bytes; repeat transfers=0")
        self.results["lazy"] = {"source": source, "initial_cache": initial, "after_history": after,
                                "repeat_transfers": 0, "offline_uncached_exit": 4}

    def remote(self, root):
        self.say("\nDEMO 4 | Client bypasses local scanning; independent server still rejects")
        root.mkdir()
        client, server = root / "client", root / "server"
        client.mkdir()
        server.mkdir()
        self.cli(client, "init")
        (client / "safe.txt").write_text("APP_MODE=safe\n")
        self.cli(client, "add", "safe.txt")
        self.cli(client, "commit", "-m", "safe baseline")
        self.cli(server, "init")
        self.cli(server, "receive-init")
        self.cli(client, "push", server, "refs/heads/main", "none")
        base = head(server)
        before = inventory(server)
        policy = (server / ".moonvcs/receive-policies.json").read_bytes()
        wire = root / "unchecked.rx"
        output = self.command(root, BYPASS, client, wire, base, "secret")
        rejected_id = re.search(r"Unscanned candidate ([0-9a-f]{64})", output).group(1)
        rejected = self.cli(server, "receive", wire, expected=12)
        require("Policy: secret-scanner" in rejected, "server did not independently run Scanner")
        require(head(server) == base and head(client) == base, "bypass rejection changed Ref")
        require(inventory(server) == before, "rejected objects entered formal store")
        require((server / ".moonvcs/receive-policies.json").read_bytes() == policy, "client changed server authority")
        require(not list((server / ".moonvcs/quarantine").iterdir()), "quarantine not cleaned")
        require(self.cli(server, "storage-state", rejected_id).strip() == "Unknown", "rejected candidate became published")
        self.say("Verified: server HEAD/policy unchanged; no rejected formal objects; owned quarantine empty.")
        self.say("Filesystem/stdio prototype: shared OS account is NOT a production privilege boundary.")
        self.results["remote"] = {"bypass_rejected_exit": 12, "head_preserved": True,
                                  "formal_objects_preserved": True, "quarantine_empty": True}


def check_runtime():
    for executable in (BIN, HOST, BYPASS):
        require(executable.is_file(), "build first: scripts/build-vcs.sh")


def prepare(args, demo):
    destination = args.workdir.resolve()
    require(not destination.exists(), "prepare requires a nonexistent workdir; existing data was not changed")
    destination.mkdir(parents=True, mode=0o700)
    remote = destination / "history-remote"
    remote.mkdir()
    demo.say("OFF-STAGE PREPARATION | actual CLI commits; no canned objects or scan results")
    demo.cli(remote, "init", visible=False)
    for number in range(1, args.commits + 1):
        (remote / "history.txt").write_text(f"safe version {number:03d}\n")
        demo.cli(remote, "add", "history.txt", visible=False)
        demo.cli(remote, "commit", "-m", f"history-{number:03d}", visible=False)
        if number % 10 == 0:
            demo.say(f"Prepared {number} actual policy-gated commits")
    measured = inventory(remote)
    marker = {"schema": 1, "project": str(ROOT), "complete": True, "commits": args.commits,
              "head": head(remote), "inventory": measured}
    (destination / "demo-state.json").write_text(json.dumps(marker, indent=2) + "\n")
    demo.say(f"Prepared workdir: {destination}")
    demo.say(f"Measured dataset: {measured['objects']} objects / {measured['encoded_bytes']} encoded bytes")
    return destination, {"preparation": marker}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["prepare", "run"])
    parser.add_argument("--workdir", type=Path, required=True)
    parser.add_argument("--commits", type=int, default=40)
    parser.add_argument("--only", choices=["all", "secret", "capability", "lazy", "remote"], default="all")
    args = parser.parse_args()
    if not 6 <= args.commits <= 80:
        parser.error("commits must be between 6 and 80")
    demo = Demo()
    start = time.perf_counter()
    stamp = datetime.now(timezone.utc).isoformat()
    report = {"schema": 1, "started_utc": stamp, "action": args.action, "only": args.only,
              "status": "running", "results": {}, "commands": demo.commands}
    output_dir = ROOT / "target/reports"
    output_dir.mkdir(parents=True, exist_ok=True)
    artifact_root = Path(tempfile.mkdtemp(prefix="phase8-" + args.action + "-", dir=output_dir))
    code = 0
    try:
        check_runtime()
        if args.action == "prepare":
            _, report["results"] = prepare(args, demo)
        else:
            work = args.workdir.resolve()
            state = json.loads((work / "demo-state.json").read_text())
            require(state.get("schema") == 1 and state.get("complete") and state.get("project") == str(ROOT),
                    "prepare this workdir using the current runtime first")
            remote = work / "history-remote"
            require(head(remote) == state["head"] and inventory(remote) == {
                **state["inventory"], "kinds": {int(k): v for k, v in state["inventory"]["kinds"].items()}
            }, "prepared history changed; prepare a fresh workdir")
            (work / "runs").mkdir(exist_ok=True)
            run = Path(tempfile.mkdtemp(prefix="run-", dir=work / "runs"))
            report["run_directory"] = str(run)
            actions = {"secret": lambda: demo.secret(run / "secret"),
                       "capability": lambda: demo.capability(run / "capability"),
                       "lazy": lambda: demo.lazy(run / "lazy-clone", remote),
                       "remote": lambda: demo.remote(run / "remote")}
            for name, action in actions.items():
                if args.only in ("all", name):
                    action()
            report["results"] = demo.results
            demo.say(f"\nActual command time: {time.perf_counter() - start:.2f}s; narration/build/preparation are separate.")
            demo.say(f"Demo repositories retained: {run}")
        report["status"] = "passed"
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired, AttributeError, KeyError, IndexError) as error:
        code = 1
        report["status"] = "failed"
        report["error"] = str(error)
        demo.say("Demo stopped: " + str(error))
    finally:
        report["elapsed_seconds"] = time.perf_counter() - start
        (artifact_root / "result.json").write_text(json.dumps(report, indent=2) + "\n")
        (artifact_root / "terminal.txt").write_text("\n".join(demo.lines) + "\n")
        print(f"Evidence: {artifact_root}", flush=True)
    return code


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Real CLI benchmark; no external packages, synthetic safe data only.

Each scale has exactly N reachable objects: S flat snapshots, each with
N / S - 2 unique Blobs, one Tree and one actual policy-gated Commit.
No unchecked objects or empty policy lists are used to generate benchmark data.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import statistics
import struct
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone


ROOT = Path(__file__).resolve().parents[1]
BIN = ROOT / "target/bin/moonvcs"
HOST = ROOT / "target/bin/moonvcs-policy-host"


def run(command, cwd, operations, label, wire=None, expected=0):
    start = time.perf_counter_ns()
    try:
        result = subprocess.run(
            [str(arg) for arg in command], cwd=cwd, input=wire,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=300,
        )
    except subprocess.TimeoutExpired:
        operations.append({"operation": label, "ms": (time.perf_counter_ns() - start) / 1_000_000,
                           "exit": None, "timed_out": True, "timeout_seconds": 300})
        raise
    elapsed = (time.perf_counter_ns() - start) / 1_000_000
    operations.append({"operation": label, "ms": elapsed, "exit": result.returncode})
    if result.returncode != expected:
        raise RuntimeError(
            f"{label}: exit {result.returncode}, expected {expected}: "
            + result.stdout.decode(errors="replace")[:1500]
            + result.stderr.decode(errors="replace")[:1500]
        )
    return result.stdout.decode("utf-8"), elapsed


def inventory(repository):
    files = sorted((repository / ".moonvcs/objects").glob("*/*"))
    total = 0
    for file in files:
        data = file.read_bytes()
        if hashlib.sha256(data).hexdigest() != file.parent.name + file.name:
            raise RuntimeError("independent SHA-256 inventory check failed")
        total += len(data)
    return len(files), total


def blob_id(content):
    envelope = b"MOONVCS\0" + bytes([1, 1]) + struct.pack(">Q", len(content)) + content
    return hashlib.sha256(envelope).hexdigest()


def content(version, index):
    return f"v{version}:{index:06d}\n".encode()


def stats(repository, operations):
    text, _ = run([BIN, "storage-stats"], repository, operations, "read_stats")
    return {key: int(value) for key, value in json.loads(text).items()}


def measure_case(work, count, repeat, snapshots):
    case = {"objects_requested": count, "repeat": repeat, "status": "running", "operations": []}
    operations = case["operations"]
    source = work / f"source-{count}-{repeat}"
    clone = work / f"clone-{count}-{repeat}"
    source.mkdir()
    file_count = count // snapshots - 2
    case["files_per_snapshot"] = file_count
    case["snapshots"] = snapshots
    try:
        run([BIN, "init"], source, operations, "init")
        context = json.loads((source / ".moonvcs/policies.json").read_text())
        case["policy_limits"] = context["limits"]
        case["required_plugins"] = [
            {key: pin[key] for key in ("name", "version", "module_digest")}
            for pin in context["required"]
        ]
        old = None
        parent = None
        for version in range(snapshots):
            files = []
            for index in range(file_count):
                name = f"f{index:06d}.txt"
                data = content(version, index)
                (source / name).write_bytes(data)
                files.append({"path": name, "content": list(data)})
            run([BIN, "add", "."], source, operations, f"add_v{version}")
            # Real adapter-shaped request, same data and limits as the Commit.
            # This measures the entire Host process, including JIT, not pure guest CPU.
            pin = context["required"][0]
            transport = {
                "schema": 1,
                "expected_plugin": {key: pin[key] for key in ("name", "version", "module_digest")},
                "policy": {
                    "allowed_capabilities": pin["granted_capabilities"],
                    "limits": context["limits"], "custom_rules": context["custom_rules"],
                },
                "request": {
                    "hook": "on-commit", "policy_version": "1",
                    "commit_message": f"benchmark-v{version}", "parent_id": parent,
                    "tree_id": None, "files": files,
                },
            }
            if version == snapshots - 1:
                output, policy_ms = run(
                    [HOST, "--request-stdin", "--component", pin["component"], "--manifest", pin["manifest"]],
                    source, operations, f"policy_host_v{version}",
                    json.dumps(transport, separators=(",", ":")).encode(),
                )
                if json.loads(output)["status"] != "pass":
                    raise RuntimeError("benchmark policy did not actually Pass")
            output, commit_ms = run(
                [BIN, "commit", "-m", f"benchmark-v{version}"], source, operations, f"commit_v{version}"
            )
            if "Policy passed" not in output or "Commit created" not in output:
                raise RuntimeError("benchmark Commit skipped required policies")
            current = (source / ".moonvcs/refs/heads/main").read_text().strip()
            if version == snapshots - 2:
                old = current
            if version == snapshots - 1:
                case["commit_ms"] = commit_ms
                case["policy_host_ms"] = policy_ms
            parent = current
        actual, source_bytes = inventory(source)
        case.update(source_objects=actual, source_bytes=source_bytes)
        if actual != count:
            raise RuntimeError(f"fixture has {actual} objects, expected {count}")
        _, case["clone_ms"] = run([BIN, "clone", source, clone], work, operations, "clone")
        cached, cached_bytes = inventory(clone)
        initial = stats(clone, operations)
        case.update(initial_objects=cached, initial_bytes=cached_bytes)
        if cached != count // snapshots or cached_bytes != initial["received_bytes"]:
            raise RuntimeError("clone object/byte counters differ from actual inventory")
        if initial["received_objects"] != cached:
            raise RuntimeError("clone downloaded-object count mismatch")
        _, case["lazy_parent_miss_ms"] = run([BIN, "show", old], clone, operations, "lazy_parent_miss")
        encoded_parent = (source / ".moonvcs/objects" / old[:2] / old[2:]).read_bytes()
        old_tree = encoded_parent[18:82].decode("ascii")
        _, case["lazy_tree_miss_ms"] = run([BIN, "show", old_tree], clone, operations, "lazy_tree_miss")
        after_miss = stats(clone, operations)
        if after_miss["requests"] != initial["requests"] + 2:
            raise RuntimeError("expected exactly two real lazy cache misses")
        case["lazy_received_bytes"] = after_miss["received_bytes"] - initial["received_bytes"]
        hit_times = []
        for _ in range(3):
            _, elapsed = run([BIN, "show", old_tree], clone, operations, "same_tree_cache_hit")
            hit_times.append(elapsed)
        case["cache_hit_ms"] = statistics.median(hit_times)
        after_hit = stats(clone, operations)
        if after_hit != after_miss:
            raise RuntimeError("cache hit unexpectedly performed a remote transfer")
        case["repeat_transfers"] = 0
        disconnected = source.with_name(source.name + "-offline")
        source.rename(disconnected)
        try:
            _, case["offline_hit_ms"] = run(
                [BIN, "show", old_tree, "--offline"], clone, operations, "offline_cached_tree"
            )
            run(
                [BIN, "show", blob_id(content(snapshots - 2, 0)), "--offline"], clone, operations,
                "offline_uncached_blob", expected=4,
            )
        finally:
            disconnected.rename(source)
        case["status"] = "passed"
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired) as error:
        case["status"] = "failed"
        case["error"] = str(error)
    return case


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--objects", type=int, nargs="+", default=[100, 1000, 10000])
    parser.add_argument("--repeats", type=int, default=3)
    parser.add_argument("--snapshots", type=int, default=20)
    parser.add_argument("--output", type=Path, default=ROOT / "target/reports/phase7-benchmark.json")
    args = parser.parse_args()
    if args.repeats < 1 or args.snapshots < 2 or any(
        count > 10000 or count % args.snapshots or count // args.snapshots < 3 for count in args.objects
    ):
        parser.error("use positive repeats, >=2 snapshots and object counts <=10000 divisible by snapshots with >=1 file")
    (ROOT / "target").mkdir(exist_ok=True)
    report = {
        "schema": 1, "started_utc": datetime.now(timezone.utc).isoformat(),
        "environment": {
            "platform": platform.platform(), "machine": platform.machine(),
            "logical_cpus": os.cpu_count(), "python": platform.python_version(),
            "filesystem_device": (ROOT / "target").stat().st_dev,
            "storage": "local workspace filesystem; no network; no dropped OS caches",
            "host_build_profile": "Cargo dev/debug, matching the installed demo runtime",
        },
        "method": {
            "snapshots": args.snapshots, "files_per_snapshot": "objects / snapshots - 2",
            "content": "unique 10–11 byte safe text per file per version for the default 20 snapshots",
            "timing": "perf_counter_ns, full separate CLI processes, milliseconds",
            "policy_host": "startup + input + manifest/digest + JIT + Wasm + result; not pure guest CPU",
            "commit": "last Commit after add; includes full required-policy execution and publication",
            "clone": "HEAD Commit/Tree/Blobs plus checkout, promises and metadata; not full history",
            "lazy_miss": "one uncached parent Commit then its uncached full Tree",
            "hit": "median of 3 further reads of the same Tree; zero remote transfers required",
            "git_comparison": "not performed; no claim of superiority or production scalability",
        }, "cases": [], "summary": [],
    }
    environment_path = ROOT / "target/reports/phase7-environment.json"
    if environment_path.exists():
        report["environment"]["tool_versions"] = json.loads(environment_path.read_text())["tools"]
    with tempfile.TemporaryDirectory(prefix="phase7-bench-", dir=ROOT / "target") as temporary:
        for count in args.objects:
            for repeat in range(1, args.repeats + 1):
                case = measure_case(Path(temporary), count, repeat, args.snapshots)
                report["cases"].append(case)
                print(f"objects={count} repeat={repeat} status={case['status']} "
                      f"commit_ms={case.get('commit_ms')} clone_ms={case.get('clone_ms')}", flush=True)
                if case["status"] == "failed":
                    print(case["error"], flush=True)
                args.output.parent.mkdir(parents=True, exist_ok=True)
                args.output.write_text(json.dumps(report, indent=2) + "\n")
    keys = ["commit_ms", "clone_ms", "policy_host_ms", "lazy_parent_miss_ms", "lazy_tree_miss_ms", "cache_hit_ms", "offline_hit_ms"]
    for count in args.objects:
        cases = [case for case in report["cases"] if case["objects_requested"] == count and case["status"] == "passed"]
        item = {"objects": count, "successful_samples": len(cases), "attempted_samples": args.repeats}
        for key in keys:
            values = [case[key] for case in cases]
            if values:
                item[key] = {"median": statistics.median(values), "min": min(values), "max": max(values)}
        if cases:
            for key in ("files_per_snapshot", "source_bytes", "initial_objects", "initial_bytes", "lazy_received_bytes"):
                item[key] = cases[0][key]
        report["summary"].append(item)
    report["finished_utc"] = datetime.now(timezone.utc).isoformat()
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(f"Raw measurements: {args.output}")
    return 0 if all(case["status"] == "passed" for case in report["cases"]) else 1


if __name__ == "__main__":
    sys.exit(main())

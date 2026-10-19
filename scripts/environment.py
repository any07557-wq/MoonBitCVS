#!/usr/bin/env python3
"""Record reproducibility metadata without dumping environment variables."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[1]


def resolve_tool(name, override=None):
    explicit = os.environ.get(override) if override else None
    if explicit:
        return explicit
    local = ROOT / ".toolchains/cargo/bin" / name
    return str(local) if os.access(local, os.X_OK) else (shutil.which(name) or name)


def version(command, environment):
    try:
        result = subprocess.run(command, capture_output=True, text=True, env=environment, timeout=20)
        return {"exit": result.returncode, "text": (result.stdout + result.stderr).strip()}
    except (OSError, subprocess.TimeoutExpired) as error:
        return {"exit": None, "text": str(error)}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=ROOT / "target/reports/phase7-environment.json")
    args = parser.parse_args()
    environment = dict(os.environ)
    local = ROOT / ".toolchains/cargo/bin"
    if os.access(local / "cargo", os.X_OK):
        environment["CARGO_HOME"] = str(local.parent)
        environment["RUSTUP_HOME"] = str(ROOT / ".toolchains/rustup")
    moon = os.environ.get("MOONVCS_MOON") or shutil.which("moon") or "/home/user/.moon/bin/moon"
    commands = {
        "moon": [moon, "version", "--all"],
        "rustc": [resolve_tool("rustc"), "--version"],
        "cargo": [resolve_tool("cargo", "MOONVCS_CARGO"), "--version"],
        "wasm_tools": [resolve_tool("wasm-tools", "MOONVCS_WASM_TOOLS"), "--version"],
        "wit_bindgen": [resolve_tool("wit-bindgen", "MOONVCS_WIT_BINDGEN"), "--version"],
        "cc": ["cc", "--version"], "python": ["python3", "--version"],
    }
    tools = {key: version(command, environment) for key, command in commands.items()}
    report = {
        "schema": 1, "utc": datetime.now(timezone.utc).isoformat(),
        "platform": platform.platform(), "machine": platform.machine(), "logical_cpus": os.cpu_count(),
        "tools": tools, "files": {},
        "dependency_advisory_scan": "not performed: no advisory database was consulted; not a no-CVE claim",
    }
    for path in [ROOT / "host/Cargo.lock", ROOT / "wit/policy.wit", ROOT / "vcs/moon.mod", *sorted((ROOT / "target/components").glob("*.component.wasm"))]:
        report["files"][str(path.relative_to(ROOT))] = hashlib.sha256(path.read_bytes()).hexdigest()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
    return 0 if all(tool["exit"] == 0 for tool in tools.values()) else 1


if __name__ == "__main__":
    raise SystemExit(main())

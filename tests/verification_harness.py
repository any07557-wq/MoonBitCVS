#!/usr/bin/env python3
"""Test failure recording of the unified runner in disposable stub workspaces."""
import json
import errno
import importlib.util
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]


class VerificationHarness(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="moonvcs-runner-audit-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        (self.root / "scripts").mkdir()
        shutil.copy2(ROOT / "scripts/verify.sh", self.root / "scripts/verify.sh")
        self.script("test.sh", "exit 0")
        self.script("test-receive.sh", "exit 0")
        (self.root / "scripts/environment.py").write_text("raise SystemExit(0)\n")
        (self.root / "scripts/benchmark.py").write_text("raise SystemExit(0)\n")

    def script(self, name, body):
        path = self.root / "scripts" / name
        path.write_text("#!/usr/bin/env bash\n" + body + "\n")
        path.chmod(0o700)

    def verify(self, expected, *options):
        result = subprocess.run([str(self.root / "scripts/verify.sh"), *options],
                                capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
        report = json.loads((self.root / "target/reports/phase7-verify.json").read_text())
        self.assertEqual(report["exit"], expected)
        return report

    def test_failed_regression_is_recorded_and_stops_later_stages(self):
        self.script("test.sh", "exit 17")
        report = self.verify(17)
        self.assertEqual([(item["stage"], item["exit"]) for item in report["stages"]], [("regression", 17)])

    def test_first_failed_smoke_cannot_be_hidden_by_second_success(self):
        marker = self.root / "first-called"
        self.script("test-receive.sh", f'if [[ ! -e "{marker}" ]]; then touch "{marker}"; exit 29; fi\nexit 0')
        report = self.verify(29)
        self.assertEqual(report["stages"][-1]["stage"], "repeat-smoke")
        self.assertEqual(report["stages"][-1]["exit"], 29)

    def test_requested_benchmark_failure_is_not_reported_as_pass(self):
        (self.root / "scripts/benchmark.py").write_text("raise SystemExit(42)\n")
        report = self.verify(42, "--benchmark")
        self.assertTrue(report["benchmark_requested"])
        self.assertEqual(report["stages"][-1]["stage"], "benchmark")
        self.assertEqual(report["stages"][-1]["exit"], 42)

    def test_unrequested_optional_checks_are_explicit_not_fake_passes(self):
        report = self.verify(0)
        self.assertEqual(report["unrequested_optional_stages"], ["benchmark", "clean-build"])
        self.assertFalse(report["benchmark_requested"] or report["clean_build_requested"])

    def test_atomic_runtime_install_works_while_old_executable_is_running(self):
        source = Path(shutil.which("sleep"))
        # GNU multicall builds select their implementation from argv[0].
        target = self.root / "sleep"
        shutil.copy2(source, target)
        process = subprocess.Popen([str(target), "30"])
        try:
            # Reproduce the old direct-copy failure before testing the installer.
            try:
                shutil.copyfile(source, target)
            except OSError as error:
                self.assertEqual(error.errno, errno.ETXTBSY)
            else:
                self.fail("expected Linux ETXTBSY reproducer")
            subprocess.run([str(ROOT / "scripts/install-runtime-file.sh"), str(source), str(target), "0755"],
                           check=True, timeout=10)
            self.assertEqual(target.read_bytes(), source.read_bytes())
            self.assertIsNone(process.poll())
            subprocess.run([str(target), "0"], check=True, timeout=5)
            self.assertFalse(list(self.root.glob("*.install.*")))
        finally:
            process.terminate()
            process.wait(timeout=5)

    def test_tool_metadata_resolves_explicit_local_and_path_tools(self):
        spec = importlib.util.spec_from_file_location("moonvcs_environment", ROOT / "scripts/environment.py")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        module.ROOT = self.root
        local = self.root / ".toolchains/cargo/bin/wasm-tools"
        with patch.dict(module.os.environ, {}, clear=True), patch.object(module.shutil, "which", return_value="/path/bin/wasm-tools"):
            self.assertEqual(module.resolve_tool("wasm-tools", "MOONVCS_WASM_TOOLS"), "/path/bin/wasm-tools")
            local.parent.mkdir(parents=True)
            local.write_text("#!/bin/sh\nexit 0\n")
            local.chmod(0o755)
            self.assertEqual(module.resolve_tool("wasm-tools", "MOONVCS_WASM_TOOLS"), str(local))
            module.os.environ["MOONVCS_WASM_TOOLS"] = "/explicit/missing/wasm-tools"
            # An invalid explicit pin must be reported, never silently replaced.
            self.assertEqual(module.resolve_tool("wasm-tools", "MOONVCS_WASM_TOOLS"), "/explicit/missing/wasm-tools")


if __name__ == "__main__":
    unittest.main(verbosity=2)

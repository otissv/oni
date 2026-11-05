"""Failure/acceptance boundaries for the vector release artifact tooling."""
import contextlib
import hashlib
import io
import json
from pathlib import Path
import tempfile
import types
import unittest
from unittest.mock import patch

import vector_benchmark_artifacts as artifacts


class ArtifactTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.manifest = self.root / "manifest.toml"
        self.manifest.write_text("slots = 2\n")
        self.enterContext(patch.object(artifacts, "ROOT", self.root))
        self.enterContext(patch.object(artifacts, "MANIFEST", self.manifest))

    def test_changed_font_is_rejected_before_running(self):
        font = self.root / "font.ttf"
        font.write_bytes(b"frozen")
        digest = hashlib.sha256(font.read_bytes()).hexdigest()
        assets = "".join(f'[[asset]]\nfile="font.ttf"\nsha256="{digest}"\n' for _ in range(8))
        self.manifest.write_text(f'slots=2\nharness=[]\n{assets}[composition_asset]\nfile="font.ttf"\nsha256="{digest}"\n[[font]]\nfile="font.ttf"\nsha256="{digest}"\n')
        artifacts.verify()
        font.write_bytes(b"changed")
        with self.assertRaises(SystemExit):
            artifacts.verify()

    def test_smoke_failed_and_over_budget_runs_never_gain_acceptance(self):
        output = self.root / "build/test"
        output.mkdir(parents=True)
        (self.root / "main.odin").write_text("package main")

        def command(args, **kwargs):
            if "rev-parse" in args:
                return "revision\n"
            return b"main.odin\0" if "ls-files" in args else b""

        with patch.object(artifacts.subprocess, "check_output", side_effect=command), patch.object(artifacts.subprocess, "run", return_value=types.SimpleNamespace(stdout="fixed GPU", returncode=0)), contextlib.redirect_stdout(io.StringIO()):
            for frames, p95, status, mode, accepted in [(8, 3, 0, "full", False), (1800, 5, 0, "full", False), (1800, 3, 1, "full", False), (1800, 3, 0, "transform-only", False), (1800, 3, 0, "morph-only", False), (1800, 3, 0, "full", True)]:
                data = dict(frames=frames, warmup=120, completed_fps=60, cpu_p95_ms=p95, error="None", isolation=mode)
                (output / "vector-benchmark.json").write_text(json.dumps(data))
                artifacts.record("vector_dense_scene_benchmark", status, 0)
                latest = max((output / "vector-results").glob("*.json"), key=lambda p: p.stat().st_mtime_ns)
                self.assertEqual(json.loads(latest.read_text())["accepted"], accepted)

    def test_regression_requires_three_matching_runs_and_enforces_five_percent(self):
        baseline, candidate = self.root / "baseline", self.root / "candidate"
        baseline.mkdir()
        candidate.mkdir()
        data = dict(test="vector_ordinary_ui_baseline_benchmark", accepted=True, cpu_p95_ms=1, manifest_hash="same", os="same", vulkan_summary="same", build_flags="same", slots=2)
        with self.assertRaises(SystemExit):
            artifacts.compare(baseline, candidate)
        for i in range(3):
            (baseline / f"{i}.json").write_text(json.dumps(data))
            (candidate / f"{i}.json").write_text(json.dumps(dict(data, cpu_p95_ms=1.04)))
        with contextlib.redirect_stdout(io.StringIO()):
            artifacts.compare(baseline, candidate)
            for i in range(3):
                (candidate / f"{i}.json").write_text(json.dumps(dict(data, cpu_p95_ms=1.06)))
            with self.assertRaises(SystemExit):
                artifacts.compare(baseline, candidate)


if __name__ == "__main__":
    unittest.main()

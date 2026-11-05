#!/usr/bin/env python3
"""Validate the frozen corpus and preserve benchmark provenance and failures."""
import argparse
import hashlib
import json
import os
import platform
from pathlib import Path
import statistics
import subprocess
import tomllib
import time

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "fixtures/vector/benchmark/manifest.toml"


def verify():
    data = tomllib.loads(MANIFEST.read_text())
    for entry in [*data["asset"], data["composition_asset"], *data["harness"], *data["font"]]:
        base = ROOT if entry in data["harness"] or entry in data["font"] else MANIFEST.parent
        path = base / entry["file"]
        if hashlib.sha256(path.read_bytes()).hexdigest() != entry["sha256"]:
            raise SystemExit(f"Frozen benchmark content changed: {path}; regenerate the manifest and repeat acceptance")
    if len(data["asset"]) != 8 or data["slots"] != 2:
        raise SystemExit("Invalid benchmark corpus/slot contract")


def record(name, status, started, isolation="full"):
    files = {
        "vector_dense_scene_benchmark": "vector-benchmark.json",
        "vector_dense_scene_svg_benchmark": "vector-benchmark-m8.json",
        "vector_composition_dense_benchmark": "vector-benchmark-composition.json",
        "vector_ordinary_ui_baseline_benchmark": "vector-benchmark-ui-baseline.json",
    }
    source = ROOT / "build/test" / files[name]
    if isolation != "full":
        if isolation not in {"transform-only", "morph-only", "svg-prepare-only", "svg-paint-only"}:
            raise SystemExit("Unknown isolation mode")
        source = ROOT / "build/test" / f"vector-benchmark-{isolation}.json"
    report = json.loads(source.read_text()) if source.exists() and source.stat().st_mtime >= started else {}
    report.update(
        test=name, exit_status=status, accepted=status == 0 and isolation == "full" and report.get("isolation", "full") == "full" and report.get("frames", 0) >= 1800 and report.get("warmup", 0) >= 120,
        revision=subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
        working_tree_sha256=hashlib.sha256(subprocess.check_output(["git", "diff", "HEAD"], cwd=ROOT)).hexdigest(),
        manifest_hash=hashlib.sha256(MANIFEST.read_bytes()).hexdigest(),
        os=platform.platform(), build_flags="-vet -strict-style -o:speed -disable-assert", slots=2,
    )
    paths = subprocess.check_output(["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"], cwd=ROOT).split(b"\0")
    tree = hashlib.sha256()
    for raw in sorted(set(paths)):
        if not raw:
            continue
        path = ROOT / os.fsdecode(raw)
        if path.is_file() and path.suffix in {".odin", ".py", ".sh", ".vert", ".frag", ".toml", ".spv", ".ttf"}:
            tree.update(raw + b"\0" + hashlib.sha256(path.read_bytes()).digest())
        elif path.is_dir() and (path / ".git").exists():
            for source in sorted(path.rglob("*.odin")):
                tree.update(os.fsencode(source.relative_to(ROOT)) + b"\0" + hashlib.sha256(source.read_bytes()).digest())
    report["source_tree_sha256"] = tree.hexdigest()
    if name != "vector_ordinary_ui_baseline_benchmark":
        report["accepted"] &= report.get("completed_fps", 0) >= 60 and report.get("cpu_p95_ms", float("inf")) <= 4 and report.get("error", "None") == "None"
    gpu = subprocess.run(["vulkaninfo", "--summary"], capture_output=True, text=True)
    report["vulkan_summary"] = gpu.stdout
    directory = ROOT / os.environ.get("ONI_VECTOR_RESULT_DIR", "build/test/vector-results")
    directory.mkdir(parents=True, exist_ok=True)
    destination = directory / f"{time.time_ns()}-{name}-{isolation}.json"
    destination.write_text(json.dumps(report, indent=2) + "\n")
    print(destination)


def compare(baseline, candidate):
    def runs(directory):
        values = [json.loads(p.read_text()) for p in Path(directory).glob("*.json")]
        values = [v for v in values if v.get("test") == "vector_ordinary_ui_baseline_benchmark" and v.get("accepted")]
        if len(values) != 3:
            raise SystemExit("Regression acceptance requires exactly three successful baseline and candidate UI runs")
        return values
    before, after = runs(baseline), runs(candidate)
    for key in ("manifest_hash", "os", "vulkan_summary", "build_flags", "slots"):
        if len({json.dumps(v.get(key), sort_keys=True) for v in before + after}) != 1:
            raise SystemExit(f"Regression runs differ in {key}")
    ratio = statistics.median(v["cpu_p95_ms"] for v in after) / statistics.median(v["cpu_p95_ms"] for v in before)
    print(f"Ordinary UI median p95 ratio: {ratio:.6f} (maximum 1.05)")
    if ratio > 1.05:
        raise SystemExit(1)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("verify")
    rec = sub.add_parser("record")
    rec.add_argument("name")
    rec.add_argument("status", type=int)
    rec.add_argument("started", type=float)
    rec.add_argument("--isolation", default="full")
    regression = sub.add_parser("compare")
    regression.add_argument("baseline")
    regression.add_argument("candidate")
    args = parser.parse_args()
    if args.command == "verify": verify()
    elif args.command == "record": record(args.name, args.status, args.started, args.isolation)
    else: compare(args.baseline, args.candidate)

#!/usr/bin/env python3
"""Generate independent M6 references; never use Oni output as expected artwork."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
FIXTURES = ROOT / "fixtures/vector/m6"
NAMES = (
    "css-classes", "nested-viewports", "mask-stroke", "clip-union",
    "gradient-inheritance", "geometry-paths", "physical-lengths",
    "namespace-scope", "use-sizing", "opacity-paint-order",
    "namespace-prefixed", "symbol-instances",
    "stroke-properties",
)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Verify pinned source and image hashes without regenerating")
    args = parser.parse_args()
    if args.check:
        manifest = json.loads((FIXTURES / "references.json").read_text())
        if [record["source"] for record in manifest["fixtures"]] != [f"{name}.svg" for name in NAMES]:
            raise SystemExit("Reference manifest fixture set differs from the pinned corpus")
        for record in manifest["fixtures"]:
            for filename, expected in [(record["source"], record["sha256"])] + [
                (image["file"], image["sha256"]) for image in record["images"]
            ]:
                if hashlib.sha256((FIXTURES / filename).read_bytes()).hexdigest() != expected:
                    raise SystemExit(f"Reference hash mismatch: {filename}")
        print(f"Verified {len(NAMES)} SVG sources and {2 * len(NAMES)} independent references")
        return
    version = subprocess.check_output(["rsvg-convert", "--version"], text=True).strip()
    if not version.startswith("rsvg-convert version 2.63.4"):
        raise SystemExit("Reference renderer version differs from pinned librsvg 2.63.4")
    records = []
    for name in NAMES:
        source = FIXTURES / f"{name}.svg"
        images = []
        root = ET.parse(source).getroot()
        width, height = int(root.attrib["width"]), int(root.attrib["height"])
        for scale in (1, 2):
            target = FIXTURES / f"{name}-{scale}x.png"
            subprocess.run([
                "rsvg-convert", "--width", str(width * scale), "--height", str(height * scale),
                str(source), "--output", str(target),
            ], check=True)
            images.append({"file": target.name, "sha256": hashlib.sha256(target.read_bytes()).hexdigest()})
        records.append({
            "source": source.name,
            "width": width, "height": height,
            "sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
            "images": images,
        })
    (FIXTURES / "references.json").write_text(json.dumps({
        "renderer": version, "fixtures": records,
    }, indent=2) + "\n")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Generate frozen dense-scene benchmark SVG assets (8 variants × 4 paths)."""

from __future__ import annotations

import hashlib
import math
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "fixtures" / "vector" / "benchmark"
MANIFEST = OUT / "manifest.toml"
SEED_TAG = "0x4F4E49"


def circle_path(part: int, radius: float, variant: float) -> str:
    cx = 6 + (part % 2) * 12
    cy = 6 + (part // 2) * 12
    step = 2 * math.pi / 32
    lobes = 0.0 if int(variant) % 2 == 0 else 0.3
    vertical = 0.8 + variant * 0.025
    parts: list[str] = []
    for i in range(32):
        a = i * step
        b = (i + 1) * step
        ra = radius * (1 + lobes * math.cos(3 * a))
        rb = radius * (1 + lobes * math.cos(3 * b))
        da = -3 * radius * lobes * math.sin(3 * a)
        db = -3 * radius * lobes * math.sin(3 * b)
        pa_x = cx + ra * math.cos(a)
        pa_y = cy + vertical * ra * math.sin(a)
        pb_x = cx + rb * math.cos(b)
        pb_y = cy + vertical * rb * math.sin(b)
        ta_x = da * math.cos(a) - ra * math.sin(a)
        ta_y = vertical * (da * math.sin(a) + ra * math.cos(a))
        tb_x = db * math.cos(b) - rb * math.sin(b)
        tb_y = vertical * (db * math.sin(b) + rb * math.cos(b))
        c1x = pa_x + ta_x * (step / 3)
        c1y = pa_y + ta_y * (step / 3)
        c2x = pb_x - tb_x * (step / 3)
        c2y = pb_y - tb_y * (step / 3)
        if i == 0:
            parts.append(f"M {pa_x:.6f} {pa_y:.6f}")
        parts.append(
            f"C {c1x:.6f} {c1y:.6f} {c2x:.6f} {c2y:.6f} {pb_x:.6f} {pb_y:.6f}"
        )
    parts.append("Z")
    return " ".join(parts)


def write_svgs() -> dict[str, str]:
    OUT.mkdir(parents=True, exist_ok=True)
    hashes: dict[str, str] = {}
    for variant in range(8):
        paths = []
        for part in range(4):
            d = circle_path(part, 3.5, float(variant))
            paths.append(
                f'  <path id="p{part}" d="{d}" fill="#7788cc" fill-rule="nonzero"/>'
            )
        body = "\n".join(paths)
        svg = (
            '<?xml version="1.0"?>\n'
            '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">\n'
            f"{body}\n"
            "</svg>\n"
        )
        name = f"icon-{variant}.svg"
        path = OUT / name
        path.write_text(svg, encoding="utf-8")
        hashes[name] = hashlib.sha256(svg.encode("utf-8")).hexdigest()
    return hashes


def write_manifest(hashes: dict[str, str]) -> None:
    lines = [
        "# Frozen dense-scene benchmark manifest (M8 imported SVG gate).",
        f"seed = \"{SEED_TAG}\"",
        "viewport = \"24x24\"",
        "icons = 2048",
        "grid = \"64x32\"",
        "spacing = 28",
        "",
    ]
    for name, digest in sorted(hashes.items()):
        lines.append(f"[[asset]]")
        lines.append(f"file = \"{name}\"")
        lines.append(f"sha256 = \"{digest}\"")
        lines.append("")
    MANIFEST.write_text("\n".join(lines), encoding="utf-8")


def main() -> None:
    hashes = write_svgs()
    write_manifest(hashes)
    print(f"Wrote {len(hashes)} assets under {OUT}")


if __name__ == "__main__":
    main()

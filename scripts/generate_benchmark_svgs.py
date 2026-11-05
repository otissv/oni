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
    vertical = 0.8 + variant * 0.025
    lobes = 0.0 if int(variant) % 2 == 0 else 0.3
    def point(radius, angle):
        if part == 1:
            return (radius * math.cos(angle), vertical * radius * math.sin(2 * angle), -radius * math.sin(angle), 2 * vertical * radius * math.cos(2 * angle))
        r = radius * (1 + lobes * math.cos(3 * angle))
        d = -3 * radius * lobes * math.sin(3 * angle)
        return (r * math.cos(angle), vertical * r * math.sin(angle), d * math.cos(angle) - r * math.sin(angle), vertical * (d * math.sin(angle) + r * math.cos(angle)))
    parts = []
    contours = 2 if part == 0 else 1
    segments = 32 // contours
    for contour in range(contours):
        r = radius * (0.45 if contour else 1)
        step = (-1 if contour else 1) * 2 * math.pi / segments
        for i in range(segments):
            ax, ay, atx, aty = point(r, i * step)
            bx, by, btx, bty = point(r, (i + 1) * step)
            if i == 0:
                parts.append(f"M {cx + ax:.17g} {cy + ay:.17g}")
            parts.append(f"C {cx + ax + atx * step / 3:.17g} {cy + ay + aty * step / 3:.17g} {cx + bx - btx * step / 3:.17g} {cy + by - bty * step / 3:.17g} {cx + bx:.17g} {cy + by:.17g}")
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
        'framebuffer = "1920x1080"',
        "dpi = 1",
        "samples = 4",
        "slots = 2",
        "warmup = 120",
        "frames = 1800",
        'time = "frame_index / 60 seconds, including warmup"',
        'phase = "time + instance_index * 0.0137"',
        'transform = "rotate(phase) * scale(1+.25*sin(phase),1+.25*cos(.7*phase)), about (12,12), plus (2*sin(phase),2*cos(.7*phase))"',
        'colour = "rgb(120+100*sin(phase),120+100*cos(phase),220)"',
        'opacity = ".8+.2*sin(phase)"',
        'morph = "instances 1536..2047; each control/end point (x,y) += (.45*sin(phase+part*.17+y*.7),.45*cos((phase+part*.17)*.83+x*.7))"',
        'topology = "part 0: one hole (opposite winding); part 1: two-lobed self-intersection; parts 2/3: simple contours; 32 nondegenerate cubics each"',
        'control_points = "exact round-trip decimal control points in the hashed SVG files"',
        'ordinary_ui = "32 labelled 72x24 buttons at (16+(i%8)*80,16+(i/8)*28), Inter 14, Btn i; 96 120x18 labels at (720+(i%12)*96,16+(i/12)*20), Inter 12, Label i; UI submitted before vectors"',
        'composition = "256 instances,16x16,64x48 viewport,96x64 spacing,origin(208,36); composition.svg; phase=time+i*.03; alpha translate(2sin(p),2cos(p)); luma translate(2cos(.7p),2sin(.7p)); outer opacity .7+.2cos(.7p); inner opacity .6+.2sin(p)"',
        "",
    ]
    for name, digest in sorted(hashes.items()):
        lines.append(f"[[asset]]")
        lines.append(f"file = \"{name}\"")
        lines.append(f"sha256 = \"{digest}\"")
        lines.append("")
    composition = OUT / "composition.svg"
    lines.extend(['[composition_asset]', 'file = "composition.svg"', f'sha256 = "{hashlib.sha256(composition.read_bytes()).hexdigest()}"', ""])
    for name in ("vector_benchmark_test.odin", "vector_benchmark_m8_test.odin", "vector_benchmark_contract_test.odin", "vector_benchmark_isolation_test.odin"):
        lines.extend(["[[harness]]", f'file = "{name}"', f'sha256 = "{hashlib.sha256((ROOT / name).read_bytes()).hexdigest()}"', ""])
    font = "fixtures/fonts/Inter-VariableFont_opsz,wght.ttf"
    lines.extend(["[[font]]", f'file = "{font}"', f'sha256 = "{hashlib.sha256((ROOT / font).read_bytes()).hexdigest()}"', ""])
    MANIFEST.write_text("\n".join(lines), encoding="utf-8")


def main() -> None:
    hashes = write_svgs()
    write_manifest(hashes)
    print(f"Wrote {len(hashes)} assets under {OUT}")


if __name__ == "__main__":
    main()

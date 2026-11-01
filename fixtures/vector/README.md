# Vector references

Pinned PNGs were generated with the independent librsvg renderer (`rsvg-convert`); librsvg is development tooling and is not a runtime dependency. Regenerate from the framework root with:

```sh
rsvg-convert fixtures/vector/fills.svg -o fixtures/vector/fills-opaque-1x.png
rsvg-convert -w 256 -h 128 fixtures/vector/fills.svg -o fixtures/vector/fills-opaque-2x.png
rsvg-convert fixtures/vector/fills-translucent.svg -o fixtures/vector/fills-translucent-1x.png
rsvg-convert -w 256 -h 128 fixtures/vector/fills-translucent.svg -o fixtures/vector/fills-translucent-2x.png
rsvg-convert fixtures/vector/gradients.svg -o fixtures/vector/gradients-1x.png
rsvg-convert -w 384 -h 128 fixtures/vector/gradients.svg -o fixtures/vector/gradients-2x.png
```

## Fills

`fills.svg` contains an even-odd ring and star, cubic/quadratic curves, a self-intersecting bowtie, a half-pixel feature, and a reflected/sheared nonzero hole. All use a fractional translation. The GPU test reconstructs the paths through the native API, destroys their handles before submission, and compares alpha and premultiplied interior channels. It checks silhouette displacement within one physical pixel and integrated coverage in each 32×32 logical region within the larger of one physical pixel of area or 5%. The thin feature is checked independently of the other shapes. Actual and difference PNGs are written to `build/test/`; the corresponding references remain here.

## Gradients

`gradients.svg` (192×64) covers:

1. objectBoundingBox linear
2. centred objectBoundingBox radial
3. padded userSpaceOnUse linear band
4. objectBoundingBox linear with `gradientTransform="rotate(90 0.5 0.5)"`
5. translucent objectBoundingBox linear (`fill-opacity="0.5"`)
6. userSpaceOnUse linear with `spreadMethod="reflect"`
7. userSpaceOnUse linear with `spreadMethod="repeat"`
8. off-centre objectBoundingBox radial (`fx="0.2"`)

GPU tests reconstruct the same paints through `Linear_Paint` / `Radial_Paint`, destroy handles before submission, and compare silhouette, premultiplied interior channels (including half-opacity), and integrated coverage across 48×32 logical regions.

## SVG import (M6)

`m6/manifest.toml` pins 38 positive and negative document cases. Additional CPU tests cover individual syntax, styling, reference, ownership and resource-limit cases. The supported contract is documented in [SVG-SUPPORTED-PROFILE.md](../../docs/SVG-SUPPORTED-PROFILE.md).

Thirteen imported documents have independent librsvg references at 1× and 2× DPI: CSS classes, nested viewports, masks and strokes, clip unions, gradient inheritance, path geometry, physical lengths, namespace scope and prefixes, use sizing, symbol instances, paint order and opacity, and stroke properties. `m6/references.json` records source/image SHA-256 hashes, intrinsic dimensions and the renderer/library versions. Regeneration requires the pinned `rsvg-convert` 2.63.4; the verification command needs only Python:

```sh
python3 scripts/generate_svg_references.py
python3 scripts/generate_svg_references.py --check
bash scripts/test_all.sh --require-vector-gpu oni
```

The GPU comparisons check premultiplied flat interior channels within 2/255, silhouette displacement within one physical pixel, and integrated alpha coverage in each region within the larger of one physical pixel of area or 5%. Internal colour boundaries are excluded from flat-colour comparisons but retain silhouette and coverage checks. The references are generated only by librsvg, never from Oni output. Tests write `svg-<name>-<scale>x-actual.png` and `svg-<name>-<scale>x-difference.png` under `build/test/`; the standalone vector gallery reads those differences for its SVG/reference comparison panel. Missing artifacts produce a readable instruction to run the GPU suite.

## Dense-scene benchmark (M8)

Eight `benchmark/icon-*.svg` files (four cubic paths each, 24×24 viewport) mirror the M2 programmatic corpus. Regenerate sources and `benchmark/manifest.toml` SHA-256 entries with:

```sh
python3 scripts/generate_benchmark_svgs.py
```

Release timing uses `scripts/benchmark_vector.sh --m8` (imported SVG grid plus composition workload). Do not edit SVG control points or manifest hashes without repeating the affected performance gates.

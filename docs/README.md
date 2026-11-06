# Oni documentation

Oni is an immediate-mode, props-declared UI framework on SDL3 and SDL_GPU. A consumer owns its host, app state and runtime assets; this repository supplies the engine, widgets, templates and independent libraries. UI declarations run twice per rendered frame: Layout measures and solves, then Draw reads solved geometry, handles input and records paint.

Implementation guidance and feature status were checked against the source on 2026-11-06. A checked feature denotes implemented code; dated test/benchmark evidence retains its original date and does not imply a fresh runtime acceptance run.

## Reading guide

| Document | Use it for |
| --- | --- |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Controlled domain state, retained interaction state, config/props and frame lifecycle |
| [WIDGETS.md](WIDGETS.md) | Widget families, authoring patterns, composition and callback ownership |
| [Layout.md](Layout.md) | Flex/grid measure and solve, draw spaces, stacking, clipping and frame arenas |
| [attributes.md](attributes.md) | Typed style fields, `set.*` helpers and CSS differences |
| [DRAW.md](DRAW.md) | CPU recording, GPU batching, text, textures and vector frame integration |
| [ATLAS.md](ATLAS.md) | Glyph residency, recovery, multi-texture sampling and raster-worker ownership |
| [FRAME_MODES.md](FRAME_MODES.md) | Continuous, On_Demand and Focused pacing, wake units and present behavior |
| [VECTOR.md](VECTOR.md) | Paths, strokes, paints, composition, SVG assets/instances, widgets and release gates |
| [SVG-SUPPORTED-PROFILE.md](SVG-SUPPORTED-PROFILE.md) | Normative SVG syntax, limits, diagnostics and exclusions |
| [APP.md](APP.md) | Build/runtime requirements and current UI/HUD feature checklist |
| [ROAD_MAP.md](ROAD_MAP.md) | Remaining toolkit work, consumer gameplay, audio and editor sequencing |

## Consumer setup and builds

Place Oni under `<project>/oni`. Copy the hot-reload host from [`templates/main.odin`](../templates/main.odin), the app from [`templates/app/`](../templates/app/), and user settings from [`templates/settings.kdl`](../templates/settings.kdl). Product source declares `APP_TYPE` and `FRAME_MODE` in `app/globlas/global.odin`; settings hold user preferences. Long-lived app and engine state belong in the heap `Persistent` block. See [APP.md](APP.md) for dependencies.

From the consumer root:

```sh
./oni/scripts/build_hot_reload.sh run
./oni/scripts/build_hot_reload.sh build
./oni/scripts/build_hot_reload.sh restart
./oni/scripts/build_hot_reload.sh stop
./oni/scripts/build_production.sh build
./oni/scripts/build_production.sh smoke
./oni/scripts/build_production.sh package
```

Build scripts resolve the consumer as Oni's parent; use `env ONI_PROJECT_ROOT=/path/to/project ...` to override it. Development generates `build/hot_reload/app.so` and the host binary. Production statically links the app, stages assets/shared libraries under `build/production/` and supports `run` and `clean` as well. Missing `release/main.odin` is created from the release template. Keep generated output out of Git.

## Verification

From the framework root:

```sh
bash scripts/test_all.sh
bash scripts/test_all.sh vector oni widgets
bash scripts/test_all.sh --asan --require-vector-gpu
bash scripts/test_build_production.sh
bash scripts/test_vector_gallery.sh --smoke
```

The package runner covers `colors`, `tengu`, `vector`, `oni` and `widgets` with vet, strict style, debug info and allocation tracking. It keeps executables under `build/test/` and runs packages serially because concurrent GPU suites can hang or crash the driver. `--valgrind` reruns kept binaries; `--report-memory` prints memory use even without leaks. GPU-dependent tests may skip when no usable device/display exists unless `--require-vector-gpu` is supplied, which also includes the engine package.

The production contract script operates on the selected consumer: it clears `build/production/`, temporarily renames the development host and rebuilds/packages release output. The gallery uses an isolated temporary consumer instead. Gallery smoke needs a usable display/GPU. Vector correctness tests and short benchmark smoke runs do not establish the dense-scene release performance gate; use the full commands and provenance rules in [VECTOR.md](VECTOR.md). Dated results there are historical evidence, not a fresh validation of the current checkout.

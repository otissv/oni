# Oni

Oni is an immediate-mode, props-declared UI toolkit on **SDL3 + SDL_GPU** with engine-retained interaction state. Widgets are **controlled** (app owns domain values via props down / events up) and **fully composable** (nest via `child` / `Children`, not monolithic). Custom widgets, flex/grid layout, FreeType + HarfBuzz text (including LCD dual-source), and hot-reload for app code.

Oni is a **framework package** you vendor (usually as `./oni`). Your project owns the host (`main.odin`), hot-reload DLL (`app/`), and assets. Tengu (`libs/tengu`) is a standalone animation library with no Oni dependency.

## Requirements

| Dependency | Role |
| ---------- | ---- |
| [Odin](https://odin-lang.org/) | Compiler |
| `glslc` | Compiles UI shaders to SPIR-V |
| SDL3 | Window, input, SDL_GPU (pinned build: `third_party/sdl3/`) |
| SDL3_image | Texture loading |
| FreeType | Font rasterization |
| HarfBuzz | Text shaping |
| `inotify-tools` (Linux) | Hot-reload file watch |

Runtime needs a working **Vulkan ICD** (`vulkaninfo --summary`). Hybrid machines often need the iGPU ICD installed even when a discrete GPU is preferred. Build the pinned SDL with `./third_party/sdl3/build_sdl3.sh` (linked via `odin_collections.sh`).

## Consumer layout

```
<project>/                 # your project
  main.odin                # hot-reload host (see templates/main.odin)
  app/                     # hot-reload DLL (see templates/app/)
  assets/                  # runtime fonts / textures
  build/hot_reload/        # app.so + logs (generated)
  game_hot_reload          # host binary (generated)
  oni/                     # this framework
```

Set `APP_TYPE` and `FRAME_MODE` in `app/globlas/global.odin`. User prefs (window, DPI, fonts, shortcuts) live in `settings.kdl`.

## Build & run

From the consumer project (scripts resolve the project as the parent of `oni/`):

```bash
./oni/scripts/build_hot_reload.sh run      # build, start, watch app/ + oni/ + main.odin
./oni/scripts/build_hot_reload.sh build    # rebuild app.so only (hot-reloads if running)
./oni/scripts/build_hot_reload.sh restart  # fresh window
./oni/scripts/build_hot_reload.sh stop
```

Override root if needed: `ONI_PROJECT_ROOT=/path/to/project ./oni/scripts/build_hot_reload.sh run`.

In-app: **F5** force reload, **F6** force restart.

## Tests

```bash
./oni/scripts/test_all.sh                  # colors, tengu, oni, widgets
./oni/scripts/test_all.sh colors tengu     # subset
./oni/scripts/test_all.sh --asan           # AddressSanitizer + leaks
./oni/scripts/test_all.sh --valgrind       # Valgrind on kept binaries
./oni/scripts/test_all.sh --report-memory  # per-test memory usage
```

Uses `-vet -strict-style -debug` and tracking-allocator leak checks. Prefer `test_all.sh` over ad-hoc `odin test`.

## Framework layout

| Path | Role |
| ---- | ---- |
| `*.odin`, `widgets/`, `set/` | Engine: GPU, layout, draw, fonts, UI frame |
| `api.odin` | Public PascalCase engine API |
| `shaders/` | UI shaders (SPIR-V via `#load`) |
| `libs/colors`, `libs/tengu` | Standalone libs (`-collection:libs=...`) |
| `templates/` | Starter host + app |
| `scripts/` | Hot-reload build and test runners |
| `docs/` | Architecture, road map, feature checklists |

App code should prefer `api.odin` names (`o.Begin_Screen`, `o.Render`, `o.Load_Texture`, …). Import the engine as `o`, widgets as `w`, style helpers as `set`.

## Architecture (short)

Oni is an **immediate-mode, props-declared UI with engine-retained interaction state**: the app rebuilds the widget tree every frame from current state and declarative `*_Props` (config down; lifecycle on Layout; input `on_*` on Draw). Widgets are **controlled** and **fully composable** — not a retained object graph and not fully stateless. **App domain state** lives in `Persistent.app`; **engine UI chrome** lives in `State.widget` / `State.ui`.

**Config vs props:** `*_Config` holds data only (style + domain values) — no `proc` fields. `*_Props` is `config` plus procedures only (`child`, `on_*`, …). Non-procedure values belong on `config`.

Each frame, inside `present_frame`, `o.Render(main_ui)` runs the UI tree **twice**:

1. **Layout** — register nodes, measure, mount/unmount, solve flex/grid on space end
2. **Draw** — after `ui_end_layout_pass` (stack/hit/tab): hit-test / events, paint from `o.ui_layout_rect`; do not re-solve layout

Widgets branch on `o.ui_pass()`. Keep both passes’ tree structure identical for the same ids. Coordinates are logical design pixels; DPI scale is handled by the engine. The host keeps heap `Persistent` (`app/exports.odin`) across DLL swaps.

|Name|	Fit|
|-|-|
|Immediate-mode UI (IMGUI) | Core: rebuild every frame, no app-owned widget object graph|
|Controlled widgets | App owns domain values; widgets take value/config via props and report changes via `on_*`|
|Fully composable | Widgets nest via `child` / `Children`; build UIs from small widgets, not monoliths|
|Declarative configuration / props-driven	| Widgets declare look/behavior via *_Props + config (data on config; procs on props)|
|Unidirectional data flow (partial)	| App domain: props down, events up — like React’s data story, without a VDOM|
|Hybrid retained interaction state	| Engine keeps focus/scroll/caret/drags across frames — not “pure” IMGUI|

Full narrative: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Documentation

| Doc | Topic |
| --- | ----- |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Immediate-mode model, props/callbacks, state ownership |
| [docs/ROAD_MAP.md](docs/ROAD_MAP.md) | Product sequence and exit criteria |
| [docs/APP.md](docs/APP.md) | UI / HUD checklist vs codebase |
| [docs/ATLAS.md](docs/ATLAS.md) | Production glyph atlas |
| [docs/DRAW.md](docs/DRAW.md) | Draw / batch / present |
| [docs/Layout.md](docs/Layout.md) | Layout solve rules (flex + CSS-like grid) |
| [docs/FRAME_MODES.md](docs/FRAME_MODES.md) | Frame pacing |
| [docs/attributes.md](docs/attributes.md) | CSS ↔ style field map |
| [FONT.md](../FONT.md) | LCD / dual-source text |
| [libs/tengu/README.md](libs/tengu/README.md) | Tengu animation API |
| [AGENTS.md](AGENTS.md) | Contributor / agent conventions |

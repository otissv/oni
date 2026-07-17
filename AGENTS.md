# AGENTS.md

Oni is an Odin immediate mode UI toolkit on SDL3 + SDL_GPU. It is a **framework package** that a consumer project imports (typically as `./oni`). Tengu is a standalone animation package under `libs/tengu` with no Oni dependency.

## Consumer layout

```
<project>/                 # user-owned
  main.odin                # hot-reload host (see oni/templates/main.odin)
  app/                     # hot-reload DLL (see oni/templates/app/)
  assets/                  # runtime assets (fonts, textures)
  build/hot_reload/        # app.so + logs (generated)
  game_hot_reload          # host binary (generated)
  oni/                     # this framework
```

## Framework layout (`oni/`)

| Path | Role |
|------|------|
| `*.odin`, `widgets/`, `set/` | Engine: GPU, layout, draw, fonts, UI frame, hot-reload lifecycle |
| `api.odin` | Public PascalCase aliases for the engine API |
| `shaders/` | UI shaders (SPIR-V embedded via `#load`) |
| `libs/colors`, `libs/tengu` | Standalone libs via `-collection:libs=...` |
| `templates/main.odin` | Starter host |
| `templates/app/` | Starter app (routes, components, theme, exports) |
| `fixtures/` | Test-only assets (fonts) |
| `build_hot_reload.sh` | Build, run, watch, stop (operates on the **parent** project) |
| `test_all.sh` | Package test runner (debug + leak checks) |
| `odin_collections.sh` | Shared `-collection:libs=oni/libs` flags |

## Build & run

From the consumer project (or anywhere; the script resolves the project as the parent of `oni/`):

```bash
./oni/build_hot_reload.sh run      # build app.so + host, start, watch app/ + oni/ + main.odin
./oni/build_hot_reload.sh build    # rebuild app.so only (hot-reloads if running)
./oni/build_hot_reload.sh restart  # fresh window
./oni/build_hot_reload.sh stop
```

Override project root if needed: `ONI_PROJECT_ROOT=/path/to/project ./oni/build_hot_reload.sh run`.

Flags used by the build: `-vet -strict-style -debug`. Needs `odin`, `glslc`, SDL3, SDL3_image, FreeType, HarfBuzz; Linux watch needs `inotify-tools`.

In-app: **F5** force reload, **F6** force restart.

## Tests

Run from the framework root (`oni/`):

```bash
./test_all.sh                  # all packages: colors, tengu, oni, widgets
./test_all.sh colors tengu     # subset
./test_all.sh --asan           # AddressSanitizer (+ leak detection)
./test_all.sh --valgrind       # re-run kept binaries under Valgrind
./test_all.sh --report-memory  # always print per-test memory usage
odin test . -debug             # engine package only (manual)
```

Always enabled by `test_all.sh`: `-vet -strict-style -debug -keep-executable`, plus Odin tracking-allocator defines that report leaks and fail the suite on bad memory. Binaries land under `build/test/` (gitignored). `oni` / `widgets` link FreeType + HarfBuzz. Font tests use `fixtures/fonts/` (not the consumer `assets/`).

Tests live as `*_test.odin` next to the package under test. Prefer `./test_all.sh` over ad-hoc `odin test` so leak checks stay consistent.

## Architecture (do not reinvent)

**Hot reload:** App state lives in heap `Persistent` (`app/exports.odin`). Host keeps the pointer across DLL swaps. GPU/font/atlas live in engine state and are rebound on reload. Do not put long-lived UI state in package globals outside `Persistent` / engine state. Host CWD is the consumer project root (exe dir), so `build/hot_reload/app.so` and `assets/` resolve there.

**Coordinates:** Layout and widgets use logical design pixels; DPI scale is handled by the engine.

**App → engine:** Prefer `oni/api.odin` names (`o.Begin_Screen`, `o.Render`, `o.Load_Texture`, …). Import engine as `o`, widgets as `w`, set helpers as `set`.

## Layout / draw pass

Layout owns sizing/positioning and Draw paints only.

Each frame the UI tree runs **twice** via `o.Render(main_ui)` (`ui.odin`):

1. **Layout** — `ui_pass() == .Layout`: register nodes, measure intrinsics, run mount/unmount lifecycle, solve flex layout into rects
2. **Draw** — after `ui_end_layout_pass()`: same procs run again with `ui_pass() == .Draw`; read `ui_layout_rect(id)`, handle input/events, emit draw commands

Between passes the engine snapshots layout ids, prunes focus, processes tab order, and resets auto element ids / static id maps so both passes regenerate the same keys.

**Widget shape** (see `widgets/button.odin`):

```odin
if o.ui_pass() == .Layout {
	// lifecycle, Children(...), register tab order — then return
	return
}
// Draw: prepare, hit-test / events, Draw_*, Children(...)
```

Rules:

- Branch on `o.ui_pass()`; do not invent a separate draw walk
- Layout pass: build the tree (`Children` / layout nodes); avoid GPU draw calls
- Draw pass: use solved rects from `o.ui_layout_rect`; do not re-solve layout
- Keep both passes’ tree structure identical for the same ids (children order, conditional widgets)
- App code calls `o.Render(...)` once; only call `ui_end_layout_pass` / `ui_end_frame` manually if you are not using `Render`

Frame order around this: poll input → app tick → UI begin → layout pass → draw pass → UI end → present.



## Widget conventions

Follow existing widgets (`widgets/button.odin`, `table.odin`):

- `*_Config`, `*_State`, `*_Event`, `*_Props` types
- `*_Props` with `config`, optional `child`, mount/unmount, and input handlers
- Theme base via a private `*_theme_base` proc
- Style overrides through `set.*` helpers, not raw unset fields when a set helper exists
- Stable `config.id` strings for focus / `GetElementById` / `FocusElement`

Demo UI lives under the consumer `app/routes/` and `app/ui/` (templates ship under `templates/app/`); shared chrome under `app/components/`.

CSS ↔ style field mapping: see `docs/attributes.md`. Layout is flex-like (row/column), not CSS Grid.

## Tengu

Own state; pass `dt` in **seconds**; use `*_Params(T)` structs and `Animatable(T)` adapters. Import as `libs:tengu`. See `libs/tengu/README.md` and `libs/tengu/STABILITY.md` before changing public APIs.

## Coding norms

- Match surrounding Odin style; build already enforces `-vet` and `-strict-style`
- Prefer small, focused procs; document non-obvious exported/hot-reload entry points
- Keep shaders in `shaders/`; rebuild runs `glslc` via the build script
- Do not commit `build/`, `game_hot_reload`, or compiled `.so`/`.dll`/`.dylib`

## Boundaries

- Do not replace the custom widget system with Dear ImGui or another GUI library
- Do not break the hot-reload export surface in `app/exports.odin` / `templates/app/exports.odin` without updating the host (`host_lifecycle.odin` / reloader)
- Do not add Tengu → Oni coupling; Tengu must stay standalone
- Avoid drive-by refactors outside the requested change
- Do not put a demo `app/` inside the framework repo; consumers own `app/`

# AGENTS.md

Oni is an immediate-mode, props-declared UI toolkit on SDL3 + SDL_GPU with engine-retained interaction state. Widgets are **controlled** (app owns domain values via props down / events up) and **fully composable** (nest via `child` / `Children`, not monolithic). It is a **framework package** that a consumer project imports (typically as `./oni`). Tengu is a standalone animation package under `libs/tengu` with no Oni dependency.

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
| `assets/fonts/` | Engine default Inter faces (`#directory`; fallback when settings.kdl has no faces) |
| `libs/colors`, `libs/tengu` | Standalone libs via `-collection:libs=...` |
| `templates/main.odin` | Starter host |
| `templates/app/` | Starter app (routes, components, theme, exports) |
| `fixtures/` | Test-only assets (fonts) |
| `scripts/build_hot_reload.sh` | Build, run, watch, stop (operates on the **parent** project) |
| `scripts/test_all.sh` | Package test runner (debug + leak checks) |
| `odin_collections.sh` | Shared `-collection:libs=oni/libs` flags |

## Build & run

From the consumer project (or anywhere; the script resolves the project as the parent of `oni/`):

```bash
./oni/scripts/build_hot_reload.sh run      # build app.so + host, start, watch app/ + oni/ + main.odin
./oni/scripts/build_hot_reload.sh build    # rebuild app.so only (hot-reloads if running)
./oni/scripts/build_hot_reload.sh restart  # fresh window
./oni/scripts/build_hot_reload.sh stop
```

Override project root if needed: `ONI_PROJECT_ROOT=/path/to/project ./oni/scripts/build_hot_reload.sh run`.

Flags used by the build: `-vet -strict-style -debug`. Needs `odin`, `glslc`, SDL3, SDL3_image, FreeType, HarfBuzz; Linux watch needs `inotify-tools`.

In-app: **F5** force reload, **F6** force restart.

## Tests

Run from anywhere (the script `cd`s to the framework root):

```bash
./oni/scripts/test_all.sh                  # all packages: colors, tengu, oni, widgets
./oni/scripts/test_all.sh colors tengu     # subset
./oni/scripts/test_all.sh --asan           # AddressSanitizer (+ leak detection)
./oni/scripts/test_all.sh --valgrind       # re-run kept binaries under Valgrind
./oni/scripts/test_all.sh --report-memory  # always print per-test memory usage
odin test . -debug                         # engine package only (manual; from oni/)
```

Always enabled by `test_all.sh`: `-vet -strict-style -debug -keep-executable`, plus Odin tracking-allocator defines that report leaks and fail the suite on bad memory. Binaries land under `oni/build/test/` (gitignored). `oni` / `widgets` link FreeType + HarfBuzz. Font tests use `fixtures/fonts/` (not the consumer `assets/`).

Tests live as `*_test.odin` next to the package under test. Prefer `./oni/scripts/test_all.sh` over ad-hoc `odin test` so leak checks stay consistent.

## Memory

Every manual allocation must have a matching cleanup path — either explicit `delete`/`free` or bulk release via an arena. run tests after changes that allocate.

**Allocators in this codebase:**

| Allocator | Lifetime | Cleanup |
|-----------|----------|---------|
| `context.temp_allocator` | Current frame / proc scratch | Wiped by the engine each frame (`free_all`); do not `delete` |
| Layout frame arena (`layout_frame_allocator()`) | One layout frame | `layout_frame_arena_reset` each frame; destroyed on shutdown |
| `context.allocator` (heap) | Until explicitly freed | `delete` for slices/maps/strings; `free` for `new` |

**Rules:**

- Pick the allocator deliberately — do not heap-allocate ephemeral data and rely on process exit
- Long-lived maps, dynamic arrays, and copied strings need `delete` (or key `delete` when removing map entries) in shutdown, unmount, or resize paths — see `ui_shutdown`, `widget_shutdown`, `layout_shutdown`
- When the layout frame arena is active (`layout_uses_frame_arena()`), arena-owned slices must not be `delete`d individually; the arena reset frees them
- Temp-allocator strings/keys that must survive a frame wipe need explicit retention (e.g. `widget_retain_key` before storing in maps)
- Hot-reload `Persistent` is `free`d in `app_shutdown`; clear or `delete` any heap fields inside it before teardown
- In tests and short-lived procs, use `defer delete(...)` / `defer free(...)` for heap allocations made in the test body

## Performance

Immediate mode rebuilds the UI tree every frame — wins come from caching stable work and batching I/O, not from skipping layout/draw passes.

**Pre-compute**

Cache intermediates that stay valid until inputs change (theme swap, DPI/zoom, hot reload, text/content edit):

- Shaped text — HarfBuzz runs per call today; glyph raster is cached but shapes are not. Cache by face + text + spacing + wrap + direction; invalidate on DPI/zoom/reload
- Style resolve — `theme_widget_style()` and static `set.*` props are nearly constant; memoize theme styles and skip full `resolve_widget_config` when interaction state did not change
- Static UI ids — prehash/intern stable string labels instead of CRC32 every frame
- Already precomputed: shaders, palette, glyph atlas, font faces, texture path cache, ortho projection (resize/DPI), theme at init/reload

Must stay live: both UI passes, input-driven style procs, Tengu `dt` animation, hot-reload rebinds, window/DPI size.

**Bulk / batch**

Prefer one pass over many small submits or per-item work:

- GPU draw — quads already merge in `batch.odin` by texture/clip/stack; extend batching mindset to uploads, not just vertex emission
- Glyph/texture uploads — highest ROI gap: defer atlas misses and hot-reload texture re-uploads into shared copy passes instead of one GPU submit per glyph/texture
- Layout scratch — route wrap/flex/table solve temporaries through `context.temp_allocator` or the layout frame arena (see Memory); avoid per-node `[dynamic]` + `defer delete` on the heap each frame
- Text shaping — shape whole strings; collect shape jobs before measuring when redesigning wrap paths
- Build/test — independent packages and shader compiles can run in parallel (`test_all.sh`, `glslc`)

**Parallelism**

Safe to parallelize now: `test_all.sh` package runs, app+host builds after shaders, parallel `glslc`. Larger runtime wins need redesign: overlap CPU work with swapchain wait (double-buffered batches), parallel glyph rasterize before serial atlas pack/upload, parallel texture decode/reload on CPU (GPU register stays on engine thread).

Do not parallelize layout→draw ordering, flex measure/position, batch emit order, or the host input loop. Tengu `Parallel_*` is animation composition, not OS threads.

**Hoist invariants**

Recompute only when the driving state changes, not on every quad/widget/node:

- Draw/batch — cache running opacity product, current clip rect, view transform/zoom/pan while recording; compute `draw_mode_f32` once per quad
- Style resolve — cache `theme_widget_style()` until theme mutates; skip the second `resolve_widget_config` on Draw when interaction bits did not change
- Layout — reuse `layout_direction_info`, definite length results, and first-pass child sizes in wrap/flex paths
- Text — hoist face id, scale, and artboard zoom for a whole layout/draw subtree

**Cache-miss / separate-allocation patterns**

Distinguish true cache misses from repeated alloc-with-no-cache:

- Cache miss → heavier work: glyph atlas (`font_ensure_glyphs`), texture path map (`assets_load_texture`), widget map insert on first mount
- No cache, alloc every call: HarfBuzz shaping (`font_shape` — `[]Shaped_Glyph` per call); main heap churn besides layout scratch
- Frame scratch (not a lookup miss): layout wrap/flex/table `[dynamic]` + `defer delete` each frame — route to temp or the layout frame arena instead

See this section and `docs/APP.md` Section 12 / `docs/ROAD_MAP.md` §1.4 for polish priorities.

## Architecture (do not reinvent)

**Model:** Immediate-mode, proc-based UI with declarative `*_Props`. **`*_Config` is data only** (style + domain values; no procs); **`*_Props` is `config` plus procedures** (`child`, `on_*`, …). The app rebuilds the tree every frame; there is no retained app widget graph. **Config flows down; lifecycle hooks run on Layout; input `on_*` handlers run on Draw.** Widgets are **controlled** and **fully composable**, and not fully stateless: **domain state** lives in `Persistent.app`; **UI chrome** lives in `State.widget` (`Widget_Context`) and `State.ui` (scrollports, drag latches, mount map). Input callbacks do not trigger a second layout in the same frame. Full narrative: `docs/ARCHITECTURE.md`.

**Hot reload:** App + engine state live in heap `Persistent` (`app/exports.odin`). Host keeps the pointer across DLL swaps. GPU/font/atlas live in engine state and are rebound on reload. Do not put long-lived UI state in package globals outside `Persistent` / engine state. Host CWD is the consumer project root (exe dir), so `build/hot_reload/app.so` and `assets/` resolve there.

**Product config:** Set required `APP_TYPE` and `FRAME_MODE` in `app/globlas/global.odin` (`APP_TYPE` → shortcut pack; `FRAME_MODE` → pacing). Omitting `FRAME_MODE` is a compile error. Do not edit `exports.odin` for those values; do not put them in `settings.kdl` (user prefs only: window, DPI, fonts, shortcuts). See `docs/FRAME_MODES.md`.

**Coordinates:** Layout and widgets use logical design pixels; DPI scale is handled by the engine.

**App → engine:** Prefer `oni/api.odin` names (`o.Begin_Screen`, `o.Render`, `o.Load_Texture`, …). Import engine as `o`, widgets as `w`, set helpers as `set`.

|Name|	Fit|
|-|-|
|Immediate-mode UI (IMGUI) | Core: rebuild every frame, no app-owned widget object graph|
|Controlled widgets | App owns domain values; widgets take value/config via props and report changes via `on_*`|
|Fully composable | Widgets nest via `child` / `Children`; build UIs from small widgets, not monoliths|
|Declarative configuration / props-driven	| Widgets declare look/behavior via *_Props + config (data on config; procs on props)|
|Unidirectional data flow (partial)	| App domain: props down, events up — like React’s data story, without a VDOM|
|Hybrid retained interaction state	| Engine keeps focus/scroll/caret/drags across frames — not “pure” IMGUI|



## Layout / draw pass

Layout owns sizing/positioning and Draw paints only.

Each frame the UI tree runs **twice** via `o.Render(main_ui)` (`ui.odin`):

1. **Layout** — `ui_pass() == .Layout`: register nodes, measure intrinsics, run mount/unmount lifecycle, solve flex/grid on space end
2. **Draw** — after `ui_end_layout_pass()`: same procs run again with `ui_pass() == .Draw`; read `ui_layout_rect(id)`, handle input/events, emit draw commands

Between passes `ui_end_layout_pass` runs layer/anchor solve, stack order, pointer hit, focus/tab, and shortcuts, then resets auto/static id maps so Draw regenerates the same keys.

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
- Fully implement without backwards compatibility, legacy or temporary code
- Ensure defense-in-depth
- Cleaned up all manual memory
- Exit criteria wis when you can clearly and confidently say there are no gaps in the implementation

Frame order around this: poll input → `ui_begin_frame` → app tick → `present_frame` (`o.Render`: layout → `ui_end_layout_pass` → draw → `ui_end_frame`) → host `end_frame`.



## Widget conventions

Follow existing widgets (`widgets/button.odin`, `table.odin`). Full model: `docs/ARCHITECTURE.md`.

- `*_Config`, `*_State`, `*_Event`, `*_Props` types
- **Config vs props:** `*_Config` is data only (`Widget_Config` + domain values) — never `proc` fields. `*_Props` is `config` plus procedures only (`child`, `on_*`, formatters, matchers, …). Non-procedure values belong on `config`. Use `config.disabled` / `set.Disabled`, not a props-level `disabled: bool`
- Theme base via a private `*_theme_base` proc
- Style overrides through `set.*` helpers, not raw unset fields when a set helper exists
- Stable `config.id` strings for focus / `GetElementById` / `FocusElement`
- Controlled: domain values live in app state; pass them in via `config` and update through `on_*` handlers — do not hide app state inside the widget
- Fully composable: nest widgets via `child` / `Children`; prefer small composable pieces over monolithic widgets

Demo UI lives under the consumer `app/routes/` and `app/ui/` (templates ship under `templates/app/`); shared chrome under `app/components/`.

CSS ↔ style field mapping: see `docs/attributes.md`. Layout is flex-like (row/column ± wrap) plus CSS-like grid for `kind = .GRID` (`layout_grid.odin` / `w.Grid`).

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

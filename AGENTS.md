# AGENTS.md

Oni is an Odin desktop UI toolkit on SDL3 + SDL_GPU, with a hot-reload host and a demo `app` package. Tengu is a standalone animation package with no Oni dependency.

## Layout

| Path | Role |
|------|------|
| `main.odin` | Hot-reload host; loads `build/hot_reload/app.so` |
| `oni/` | Engine: GPU, layout, draw, fonts, UI frame, hot-reload lifecycle |
| `oni/widgets/` | Built-in widgets (`Button`, `Text`, `Rectangle`, `Table`, …) |
| `oni/set/` | Style helpers that wrap values in `Cfg(T)` |
| `oni/api.odin` | Public PascalCase aliases for the engine API |
| `oni/templates/` | Starter app/theme templates |
| `app/` | Demo app: routes, components, theme, exported DLL entry points |
| `tengu/` | Animation library (own README / STABILITY.md) |
| `assets/` | Runtime assets (textures, fonts) |
| `build_hot_reload.sh` | Build, run, watch, stop |

## Build & run

```bash
./build_hot_reload.sh run      # build app.so + host, start, watch oni/ and app/
./build_hot_reload.sh build    # rebuild app.so only (hot-reloads if running)
./build_hot_reload.sh restart  # fresh window
./build_hot_reload.sh stop
```

Flags used by the build: `-vet -strict-style -debug`. Needs `odin`, `glslc`, SDL3, SDL3_image, FreeType, HarfBuzz; Linux watch needs `inotify-tools`.

In-app: **F5** force reload, **F6** force restart.

Tests (when present): `odin test` on the relevant package (e.g. `oni`, `tengu`).

## Architecture (do not reinvent)

**Hot reload:** App state lives in heap `Persistent` (`app/exports.odin`). Host keeps the pointer across DLL swaps. GPU/font/atlas live in engine state and are rebound on reload. Do not put long-lived UI state in package globals outside `Persistent` / engine state.

**Coordinates:** Layout and widgets use logical design pixels; DPI scale is handled by the engine.

**App → engine:** Prefer `oni/api.odin` names (`o.Begin_Screen`, `o.Render`, `o.Load_Texture`, …). Import engine as `o`, widgets as `w`, set helpers as `set`.

## Layout / draw pass

Layout owns sizing/positioning and Draw paints only.

Each frame the UI tree runs **twice** via `o.Render(main_ui)` (`oni/ui.odin`):

1. **Layout** — `ui_pass() == .Layout`: register nodes, measure intrinsics, run mount/unmount lifecycle, solve flex layout into rects
2. **Draw** — after `ui_end_layout_pass()`: same procs run again with `ui_pass() == .Draw`; read `ui_layout_rect(id)`, handle input/events, emit draw commands

Between passes the engine snapshots layout ids, prunes focus, processes tab order, and resets auto element ids / static id maps so both passes regenerate the same keys.

**Widget shape** (see `oni/widgets/button.odin`):

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

Follow existing widgets (`oni/widgets/button.odin`, `table.odin`):

- `*_Config`, `*_State`, `*_Event`, `*_Props` types
- `*_Props` with `config`, optional `child`, mount/unmount, and input handlers
- Theme base via a private `*_theme_base` proc
- Style overrides through `set.*` helpers, not raw unset fields when a set helper exists
- Stable `config.id` strings for focus / `GetElementById` / `FocusElement`

Demo UI lives under `app/routes/` and `app/ui/`; shared chrome under `app/components/`.

CSS ↔ style field mapping: see `attributes.md`. Layout is flex-like (row/column), not CSS Grid.

## Tengu

Own state; pass `dt` in **seconds**; use `*_Params(T)` structs and `Animatable(T)` adapters. See `tengu/README.md` and `tengu/STABILITY.md` before changing public APIs.

## Coding norms

- Match surrounding Odin style; build already enforces `-vet` and `-strict-style`
- Prefer small, focused procs; document non-obvious exported/hot-reload entry points
- Keep shaders in `oni/shaders/`; rebuild runs `glslc` via the build script
- Do not commit `build/`, `game_hot_reload`, or compiled `.so`/`.dll`/`.dylib`

## Boundaries

- Do not replace the custom widget system with Dear ImGui or another GUI library
- Do not break the hot-reload export surface in `app/exports.odin` without updating the host (`oni/host_lifecycle.odin` / reloader)
- Do not add Tengu → Oni coupling; Tengu must stay standalone
- Avoid drive-by refactors outside the requested change

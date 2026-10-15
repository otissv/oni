# Oni Architecture

Oni is an **immediate-mode, proc-based UI** with **declarative configuration** and **callback-driven events**. The app rebuilds the widget tree every frame from current state and props. The engine co-owns presentation and interaction state (focus, scroll, text caret, drags) keyed by stable widget ids.

This page is the narrative model. Frame solve details live in [Layout.md](Layout.md); paint and batching in [DRAW.md](DRAW.md); frame pacing in [FRAME_MODES.md](FRAME_MODES.md).

## One-sentence model

Each frame the app re-enters UI procs with **config and callbacks down**; widgets emit appearance and detect input; **events flow up** through parent-supplied handlers so the app can update authoritative domain state; on the next frame that state flows back down through props — while the engine separately retains cross-frame UI chrome state.

## Immediate mode (not a retained widget graph)

There is no app-owned object tree of widget instances. App UI is ordinary Odin procedures (`main_ui`, route screens, …) that call widget procs every frame:

```odin
main_ui :: proc() {
	o.Begin_Screen()
	// call w.Button, w.Text_Input, Children, …
	o.End_Screen()
}

// Inside the host present callback (e.g. app_draw):
o.Render(main_ui)
```

Calling a widget **declares** that it exists this frame with the given props. Omitting it (or failing to touch its id) is how it leaves the tree; `render` calls `ui_end_frame` per builder to prune stale lifecycle entries. Host `run_frame` may call `end_frame` again after present (idempotent when maps are already pruned).

Children are **closures**, not VDOM nodes — typically `proc(frame_state: Button_State)` so nested UI can read merged style and interaction bits for the current frame.

## Declarative configuration

Widgets take a `*_Props` struct. Style and identity live in `config` (usually a `Widget_Config` / theme-merged style). Overrides use `set.*` helpers. Theme defaults come from a private `*_theme_base` proc merged with props each call.

| Piece | Role |
| ----- | ---- |
| `*_Config` | Identity (`id`), style fields, disabled / tabbable / visibility, … |
| `*_Props` | `config`, optional `child`, mount/unmount hooks, input handlers |
| `*_State` | Per-frame merged snapshot: interaction flags + resolved config (`Widget_Merged_State`) |
| `*_Event` | Handler payload: frame state plus optional input metadata |

Stable `config.id` strings matter: focus, scroll offsets, text-edit maps, and `GetElementById` / `FocusElement` all key off them (or engine-generated ids derived from them).

## Props down, callbacks up

**Down:** the parent passes the current value and look — text string, checked flag, selected index, colors, layout hints — through `config` and related props fields.

**Up:** the parent passes optional handlers. Split by pass:

| Kind | When | Examples |
| ---- | ---- | -------- |
| **Lifecycle** | Layout (`widget_run_layout_lifecycle`) | `on_mount`, `on_unmount` |
| **Input / interaction** | Draw (`widget_handle_interaction`, `widget_dispatch_events`) | `on_click`, `on_change`, `on_focus`, `on_blur`, pointer/key handlers |

Pattern (conceptual, domain state):

```
App state ──props/config──► Widget proc ──on_* callbacks──► App state
                 ▲                                  │
                 │         next frame               │
                 └──────────────────────────────────┘
```

Input callbacks run **while the Draw walk is still in progress**. There is no automatic second Layout solve in the same frame after `on_click` / `on_change`. Mutating app state in a handler affects **later widgets in this Draw pass** and the **next frame’s** full rebuild. Prefer treating domain updates as “apply now, paint consistently next frame” unless you intentionally read the new value later in the same tree.

## Two ownership domains

Widgets are **not** fully stateless or fully controlled. Split ownership deliberately:

| Owner | Lives in | Examples |
| ----- | -------- | -------- |
| **App (domain)** | `Persistent.app` / `Global_State` | Form field strings, route, selection models, game/sim data |
| **Engine (UI chrome)** | `State.widget` (`Widget_Context`) and `State.ui` (`UI_State`) | Focus / tab order / hover-press maps / `scroll_offsets` / text caret (`Widget_Context`); scrollport metrics, scrollbar/slider/color-picker drag latches, mount `widgets` map (`UI_State`) |

`Persistent` (consumer `app/exports.odin`) holds **both** `engine: o.State` and `app: …` so hot reload can keep one heap pointer. Naming does not mean “only app data”: engine UI state survives DLL swaps with that block.

### Controlled display vs engine interaction

- **Text fields:** display string typically comes from app `config` / props; caret, selection, and undo live in `w_ctx.text_edit_states` until `on_change` commits text back to the app.
- **Scrollports:** content is app-declared; offset lives in `scroll_offsets` (and related `UI_State.scrollports` / bar-drag maps).
- **Buttons / toggles:** click is an event; whether something is “selected” or “open” is usually app state passed back next frame as config.

Do not store long-lived UI or domain state in package globals outside `Persistent` / engine state.

## Frame pipeline

Ground truth is [`run_frame`](../runtime.odin) → [`present_frame`](../present.odin) → app draw → [`render`](../ui.odin):

```
run_frame                          oni/runtime.odin
  frame_wait_if_idle / pacing gates
  input_begin_frame
  poll_events (+ settings_poll)
  ui_begin_frame                   pass = Layout; layout reset
  tick(dt)
  run_init_once (first frame only)
  present_frame(draw)              may skip when on-demand idle
    draw_record_begin
    draw()                         typically app_draw → o.Render(main_ui)
      render(ui...)
        for each builder u:
          u()                      Layout: register, measure, lifecycle
            Begin_Screen / Artboard
              … End_* → layout_end_space   ★ primary flex/grid solve ★
          error_banner_ui?         same pass, after app UI
          ui_end_layout_pass       layer/anchor solve, stack, hit, tab, shortcuts → Draw
          u()                      Draw: hit-test, input on_*, paint
          error_banner_ui?
          ui_end_frame             prune widgets not seen this builder
    draw_record_end
    texture_uploads_flush
    GPU acquire / upload / flush / present
  frame_after_present
  end_frame                        ui_end_frame again (usually no-op after Render)
```

`o.Render` invokes each UI builder **twice** (Layout then Draw). Widgets branch on `o.ui_pass()`:

```odin
if o.ui_pass() == .Layout {
	// lifecycle, Children(...), tab order — return
	return
}
// Draw: prepare, interaction, Draw_*, Children(...)
```

Invariants:

1. **Same tree both passes** — same widgets, children order, conditionals, and ids.
2. **Layout solves; Draw paints** — primary solve is on space end (`End_Screen` / `End_Artboard`); `ui_end_layout_pass` then runs layer/anchor/stack/hit bookkeeping. Draw reads `ui_layout_rect`; it must not re-solve layout.
3. **Input interaction is Draw-side** — focus/hover and `on_*` input handlers update during Draw using layout-finalized hit targets. Mount/unmount run on Layout.

See [Layout.md](Layout.md) and [DRAW.md](DRAW.md) for solve timing, spaces (Screen / Artboard / Popover), batching, and present.

## Widget lifecycle

Beyond per-frame props, widgets can participate in mount/unmount via props (`on_mount`, `on_unmount`, `unmount`) and `UI_Widget_Entry` tracking in `UI_State.widgets`. Lifecycle runs primarily on Layout; Draw syncs via prepare helpers. Completed unmount or `visibility: NONE` can skip work for that id.

## What this is not

- **Not Dear ImGui-style** free-form `if (Button())` return-value primary API as the widget contract — Oni uses props + handlers (helpers like `FocusNext` may still return `bool`).
- **Not React** — no virtual DOM diff, no fiber, no automatic re-render scheduling; the host always runs the frame loop.
- **Not purely unidirectional** — engine UI state mutates without going through app callbacks; app callbacks are for **domain** updates (plus optional lifecycle hooks).
- **Not a single-pass “layout then style then draw”** — style merge can run on both passes where widgets refresh merged config; input interaction resolves on Draw.

## Related docs

| Doc | Topic |
| --- | ----- |
| [Layout.md](Layout.md) | Flex + CSS-like grid solve, spaces, frame arena, two-pass rules |
| [DRAW.md](DRAW.md) | Batch record, GPU flush, interaction during draw |
| [FRAME_MODES.md](FRAME_MODES.md) | Frame pacing |
| [attributes.md](attributes.md) | CSS ↔ style field map |
| [APP.md](APP.md) | UI / HUD feature checklist |
| [ROAD_MAP.md](ROAD_MAP.md) | Product sequence |
| [../FONT.md](../FONT.md) | LCD / dual-source text |
| [AGENTS.md](../AGENTS.md) | Contributor conventions (memory, widgets, boundaries) |

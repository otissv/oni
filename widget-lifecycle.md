# Widget lifecycle: `on_mount` and `on_unmount`

## Overview

Mount and unmount are **cooperative** and follow the normal game loop. There is **no lifecycle registry** — persistence comes from **app-level state** (e.g. `panel_state`) and the **existing layout tree** (`id_to_node` / `ui_layout_rect`).

Widgets stay in the tree until exit finishes. No frame diffing, snapshots, or ghost rendering.

---

## State model

### App state (durable)

Animation and lifecycle progress live in app structs:

```odin
panel_state: struct {
    opacity: f32,
    // ...
}
```

`on_mount` / `on_unmount` mutate app state. `Rectangle_State` is not durable.

### `Widget_Frame_State` flags (per call, engine-set)

Add to `Widget_Frame_State`:

`Mount :: enum {
	UNSET,
	RUNNING,
	COMPLETED,
}
`

| Field | Set by | Meaning |
|-------|--------|---------|
| `mounting` | Engine |  Result of last `on_mount` return value (`RUNNING` = still mounting) Mount not finished; block interaction events |
| `unmounting` | Engine | Result of last `on_unmount` return value (`RUNNING` = still exiting) |


### Props

| Prop | Purpose |
|------|---------|

| `on_mount: proc(state) -> Mount` | Run init logic; return value drives `mounting` |
| `on_unmount: proc(state) -> Mount` | Run exit logic; return value drives `unmounting` |
| `unmount: bool` | **Trigger only** — tells layout pass to call `on_unmount` |

---

## Frame flow

`Render(view)` runs `view()` twice per frame:

```
view()  →  Layout pass   (measure, on_mount / on_unmount)
view()  →  Draw pass     (draw, interaction events)
```

### Layout pass

```odin
if ui_pass() == .Layout {
    // 1. First time this id appears in layout tree → mounting = true
    // 2. If props.unmount → call on_unmount(state) → bool → state.unmounting
    // 3. If on_unmount returns true → skip layout registration (removed from tree)
    // 4. Else → Children(...) as normal
}
```

### Draw pass

```odin
// Re-read app state via config (values or proc fields)
// Draw chrome + children
// Interaction events only when !mounting && !unmounting && !disabled
```

---

## Mount

### Trigger

First frame a widget with a stable `id` registers in the layout tree → `mounting = .RUNNING`. Run `on_mount` proc until `on_mount` is `.COMPLETED`.

### Behavior

- **Layout**: widget registers normally; `mounting` is .RUNNING until mount completes.
- **App**: drives enter animation via app state (e.g. `panel_state.opacity` 0 → 1), read through `config` each `view()` call.
- **Mount complete**: when app criteria are met (e.g. `opacity >= 1`), `on_mount` returns `.COMPLETED` setting  `mounting` to `.COMPLETED`.

Mount completion can be:

- if no `on_mount` proc `mounting` is `.UNSET`.
- `on_mount` RETURN `.COMPLETE`

### Interaction during mount

if `can_interactive_during_mount` prop id=s `true` then `on_click`, hover, focus, keys do not run while `state.mounting == true`. Layout and draw still run.

---

## Unmount

### Trigger (explicit `unmount` prop)

App expresses intent in the builder — typically an else branch:

```odin
if show_panel {
    wg.Rectangle({ config = { id = "panel", ... } })
} else {
    wg.Rectangle({
        config = { id = "panel", ... },
        unmount = true,
        on_unmount = ...,
    })
}
```

`unmount = true` sets `state.unmounting = .RUNNING` triggering `on_unmount`.

### `on_unmount` contract

```odin
on_unmount :: proc(state: Rectangle_State) -> Mount
```

| Return | Engine | App |
|--------|--------|-----|
| `.UNSET` | `state.unmounting = .UNSET`; skip layout registration | Do not call else branch |
| `.RUNNING` | `state.unmounting = .RUNNING`; keep layout node | Keep calling else branch |
| `.COMPLETE` | `state.unmounting = .COMPLETE`; skip layout registration | Stop calling else branch |

### Interaction during unmount

Blocked while `state.unmounting == .RUNNING` (same as mount).

---

## Same-frame sync

1. **Layout pass** — `on_unmount` mutates `panel_state`.
2. **Draw pass** — `view()` runs again; `config` re-reads `panel_state`.
3. Draw shows updated values in the **same presented frame**.
panel_state
For values that affect layout size during animation, use **proc-based config** and resolve **after** `on_unmount` in the layout pass.


---

## `Rectangle` layout pass (sketch)

```odin
Rectangle :: proc(props: Rectangle_Props) {
	// Layout pass
	cfg := props.config
	key := oni.element_key(cfg.id)
	layout_label := cfg.id != "" ? cfg.id : key
	layout_id := oni.ui_id(layout_label)
    layout_rect := oni.ui_layout_rect(layout_id)
	rect := layout_rect

	was_focused := oni.w_ctx.focused_id == key
	should_auto_focus :=
		cfg.auto_focus.mode == .Value && cfg.auto_focus.value && oni.w_ctx.auto_focused_id != key

	if should_auto_focus {
		oni.w_ctx.focused_id = key
		oni.w_ctx.auto_focused_id = key
	}

	frame_state := Rectangle_State {
		is_disabled = cfg.disabled.mode == .Value && cfg.disabled.value,
		is_focused  = oni.w_ctx.focused_id == key,
	}

	event := rect_refresh_merged(props, &frame_state)
	config := frame_state.config
	child := props.child

	if oni.ui_pass() == .Layout {
		// Layout pass

		if props.on_mount != nil &&
		   frame_state.mounting == .UNSET &&
		   frame_state.mounting != .COMPLETED {
			frame_state.mounting = props.on_mount(frame_state)
		} else if props.on_unmount != nil &&
		   (props.unmount || frame_state.unmounting == .RUNNING) {
			frame_state.unmounting = props.on_unmount(frame_state)
		}

		oni.Children(child, layout_id, config, frame_state)
		return
	} else {
		// Draw pass

		draw_widget_rectangle(
			{
				frame_state = &frame_state,
				event = event,
				rect = rect,
				child = child,
				layout_id = layout_id,
			},
		)

		oni.Children(child, layout_id, config, frame_state)

		// TODO: remove from layout tree
		return

	}
```

---

## App usage example

```odin
panel_state := struct { opacity: f32 = 1 }

Panel :: proc() {
    if show_panel {
        wg.Rectangle({
            config = {
                id = "panel",
                background = panel_background(), // reads panel_state.opacity
            },
        })
    } else {
        wg.Rectangle({
            config = {
                id = "panel",
                background = panel_background(),
            },
            unmount = true,
            on_unmount = proc(_: wg.Rectangle_State) -> bool {
                panel_state.opacity -= 0.05
                if panel_state.opacity <= 0 do return .COMPLETED
                else do return .RUNNING
            },
        })
    }
}
```

---

## Summary table

| Topic | Decision |
|-------|----------|
| Mounting check | `state.mounting` |
| Unmounting check | `state.unmounting` (= `on_unmount` returned `.COMPLETED`) |
| `unmount` prop | Layout trigger only; not phase state |
| Registry | **None** — layout tree + app state |
| State mutations | App level, not `Rectangle_State` |
| Visual sync | Same frame via double `view()` |
| Events during mount/unmount | Blocked until `!mounting && !unmounting` |

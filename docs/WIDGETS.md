# Widget authoring guide

How to structure and implement widgets in `oni/widgets/`. Narrative model and ownership live in [ARCHITECTURE.md](ARCHITECTURE.md); style fields in [attributes.md](attributes.md); layout/draw passes in [Layout.md](Layout.md) and [DRAW.md](DRAW.md).

**Canonical templates**

| Pattern | Copy from | When |
| ------- | --------- | ---- |
| Simple interactive / chrome | [`button.odin`](../widgets/button.odin) | Default for almost every new widget |
| Layout-only container | [`grid.odin`](../widgets/grid.odin) | Same shell as Button; no domain value |
| Controlled domain value | [`checkbox.odin`](../widgets/checkbox.odin) | App-owned value on `config` + `on_*_change` |
| Compound (root + parts + shared ctx) | [`popover.odin`](../widgets/popover.odin) + `*_shared.odin` | Nested Trigger / Content / etc. that share open state |

## Model in one paragraph

Widgets are **controlled** and **fully composable**. The app owns domain values (`config` down, `on_*` up). The engine retains interaction chrome (focus, hover, scroll, caret) keyed by stable ids. There is no app-owned widget object graph — calling a widget proc each frame declares it. Nest via `child` / `Children`, not monoliths.

## Type quartet

Every public widget defines four types:

| Type | Role | Rule |
| ---- | ---- | ---- |
| `*_Config` | Identity, style, domain values | **Data only** — never `proc` fields |
| `*_State` | Per-frame merged snapshot | Interaction flags + resolved config (+ domain mirrors when needed) |
| `*_Event` | Handler payload | `o.Widget_Event(*_State)` |
| `*_Props` | Call surface | `config` + **procedures only** (`child`, `on_*`, formatters, …) |

### Config vs props (hard rule)

| Piece | May contain | Must not contain |
| ----- | ----------- | ---------------- |
| `*_Config` | `Widget_Config` fields (`id`, style, `disabled`, …) plus domain values (`open`, `checked`, text, …) | Any `proc` field |
| `*_Props` | `config` and procedures | Non-procedure domain / style values |

Disable with `config.disabled` / `set.Disabled`, not a props-level `disabled: bool`. Engine lifecycle bools `unmount` / `can_interactive_during_mount` remain on props; prefer not adding other non-proc fields there.

### Config shapes

**Alias** when there is no domain payload:

```odin
Widget_Config :: o.Widget_Config
```

**Embed** when the widget adds domain fields:

```odin
Popover_Config :: struct {
	using _: o.Widget_Config,
	open:    bool,
}
```

### State shapes

**Generic merge** (Button / Grid / Trigger parts):

```odin
Widget_State :: o.Widget_Merged_State(o.Widget_Frame_State, o.Resolved_Widget_Config)
```

**Custom** when domain fields must ride on frame state (Popover / Checkbox):

```odin
Widget_State :: struct {
	using frame_state: o.Widget_Frame_State,
	config:            o.Resolved_Widget_Config,
	open:              bool,
	disabled:          bool,
}
```

Custom state usually needs private `*_refresh_merged` / `*_refresh_merged_if_interaction_changed` instead of the generic helpers.

## Props checklist

Standard interactive props (copy from Button, swap the type names):

- `config`
- `child: proc(frame_state: *_State)`
- Lifecycle: `unmount`, `can_interactive_during_mount`, `on_mount`, `on_unmount`
- `on_scroll`
- Focus: `on_focus`, `on_blur`
- Pointer: `on_mouse_enter`, `on_mouse_leave`, `on_mouse_pressed`, `on_mouse_down`, `on_mouse_released`, `on_mouse_move`, `on_click`, `on_contextmenu`
- Keys: `on_key_pressed`, `on_key_down`, `on_key_released`

Add **domain** callbacks on props only (`on_open_change`, `on_checked_change`, `on_change`, …). Put the corresponding value on `config`.

## Theme base

Private `*_theme_base` returns defaults via `set.*` helpers. Always set `kind`. Callers override through props `config`.

```odin
@(private)
widget_theme_base :: proc(frame_state: ^Widget_State) -> Widget_Config {
	_ = frame_state
	return Widget {
		kind = .WIDGET,
		line_height = set.F32(1),
		border = set.Border(1),
		border_color = set.Border_color(o.Color.TRANSPARENT),
		width = set.Width(.FIT),
		wrap = set.Wrap(.NONE),
	}
}
```

Theme may read interaction / domain bits on `frame_state` (see Checkbox) when appearance depends on them.

## Main proc skeleton

Branch on `o.ui_pass()`. Keep the **same tree** (children order, conditionals, ids) on Layout and Draw. Layout solves; Draw paints and runs input handlers.

```odin
Foo :: proc(props: Foo_Props) {
	cfg := props.config
	key := o.element_key(cfg.id)
	layout_label := cfg.id != "" ? cfg.id : key
	layout_id := o.ui_id(layout_label)

	was_focused := widget_is_focused(key)

	frame_state := Foo_State {
		is_disabled = o.cfg_style_bool(cfg.disabled),
		is_focused  = was_focused,
		// domain mirrors if custom State
	}

	event := widget_refresh_merged(props, &frame_state, foo_theme_base)
	style_fp := widget_style_interaction_fp(&frame_state)
	config := frame_state.config
	handlers := widget_lifecycle_handlers(props, Foo_State)
	should_auto_focus := widget_should_auto_focus(config, key)

	if o.ui_pass() == .Layout {
		skip_layout, ran_unmount := widget_run_layout_lifecycle(
			handlers,
			layout_id,
			cfg.id != "",
			&frame_state,
			config.visibility,
		)

		if ran_unmount {
			event = widget_refresh_merged(props, &frame_state, foo_theme_base)
			config = frame_state.config
			should_auto_focus = widget_should_auto_focus(config, key)
		}

		if !skip_layout {
			can_interact := widget_can_interact(handlers, &frame_state)

			if can_interact && should_auto_focus {
				widget_apply_auto_focus(key, true)
				frame_state.is_focused = true
			}

			widget_register_tab_order(key, config.tabbable, can_interact)
			widget_children(
				props.child,
				layout_id,
				config,
				frame_state,
				key,
				props.config,
				props.on_scroll,
				frame_state.is_hovered,
			)
		}

		return
	}

	if !widget_prepare_draw(handlers, layout_id, &frame_state) do return

	frame_state.is_focused = widget_is_focused(key)
	rect := o.ui_layout_rect(layout_id)

	widget_handle_interaction(
		props,
		&frame_state,
		handlers,
		key,
		was_focused,
		config.tabbable,
		layout_id,
		rect,
		config,
	)
	widget_handle_scroll_wheel(layout_id, config, frame_state.is_hovered, key, props.on_scroll)
	scroll := o.widget_scroll_get(key)
	config.scroll_x = scroll.x
	config.scroll_y = scroll.y
	frame_state.config = config

	event, _ = widget_refresh_merged_if_interaction_changed(
		props,
		&frame_state,
		foo_theme_base,
		style_fp,
	)
	config = frame_state.config

	// focus / blur notifications when interactive…
	// resolve background / border / radius from config + frame_state + event…
	// Draw_Push_Opacity → background → children → border → dispatch_events
}
```

### Pass responsibilities

| Pass | Do | Do not |
| ---- | -- | ------ |
| **Layout** | Lifecycle, tab order, auto-focus, build children / layout nodes | GPU draw calls; treat as final paint |
| **Draw** | `ui_layout_rect`, interaction, `on_*` input, paint, children again | Re-solve flex/grid layout |

Input `on_*` handlers run **during** the Draw walk. There is no automatic second Layout in the same frame. Domain updates apply to later widgets this Draw and the next full frame.

## Shared helpers (use these)

Prefer the package helpers in `widget_*.odin` over reinventing:

| Helper | Role |
| ------ | ---- |
| `widget_refresh_merged` / `widget_refresh_merged_if_interaction_changed` | Theme + props → resolved config (generic State) |
| `widget_lifecycle_handlers` | Packs mount/unmount props |
| `widget_run_layout_lifecycle` | Mount / unmount on Layout |
| `widget_prepare_draw` | Skip draw when unmounted / invisible |
| `widget_can_interact` | Disabled + mount gating |
| `widget_register_tab_order` / focus helpers | Keyboard focus |
| `widget_handle_interaction` | Hover / press / click / keys into frame_state |
| `widget_handle_scroll_wheel` | Wheel → scroll offsets |
| `widget_children` | Begin layout node, run `child`, end |
| `widget_draw_box_background` / `widget_draw_box_border` | Standard chrome |
| `widget_dispatch_events` | Fire pointer/key props from frame_state edges |

Box paint helpers live in `widget_box.odin`; focus in `widget_focus.odin`; interaction in `widget_interaction.odin`; lifecycle in `widget_lifecycle.odin`.

## Controlled domain values

App owns the value. Pass it every frame on `config`; report intent only through callbacks.

```odin
// App
w.Checkbox({
	config = {
		id = "agree",
		checked = app.agree,           // domain on config
		disabled = set.Disabled(busy),
	},
	on_checked_change = proc(v: w.Checkbox_Value) {
		app.agree = v                  // update app; next frame flows down
	},
})
```

Do not mutate caller state inside the widget. Built-in chrome may read engine maps (caret, scroll); domain display still comes from props.

## Compound widgets

When parts must share live state within one declaration (Popover, Dialog, Select, Date_Picker, Tabs):

1. **Root** (`Popover`) — owns `config.open` / `on_open_change`, pushes a private ctx stack frame, runs the standard Layout/Draw shell, runs dismiss / domain logic on Draw.
2. **Parts** (`Popover_Trigger`, `Popover_Content`, …) — Button-like shells that read/write the ctx (`popover_toggle_open`, anchor rects, content child).
3. **Shared** (`popover_shared.odin`) — private `*_Ctx`, push/pop, shutdown hook, helpers. Clear stack depth in widget `Shutdown`.
4. **Test env** — register `*_shutdown` in [`test_helpers.odin`](../widgets/test_helpers.odin) `with_widget_env`: call it before `o.ui_init()` and again in the `defer` teardown (same pattern as `popover_shutdown`, `collapsible_shutdown`, …). Skipping this leaves ctx stack dirt across tests.

```
Popover(config.open, on_open_change)
  └─ child → Popover_Trigger + Popover_Content
       ctx stack ties open / trigger rect / dismiss
```

Use compound only when sibling parts need shared ephemeral context. A single controlled value with no parts stays a Checkbox-style widget.

### Custom merge (compound / domain State)

Generic `widget_refresh_merged` expects `Widget_Merged_State`. Custom State needs private refresh that still calls `o.resolve_widget_config(base, props.config, frame_state, event)` and returns `widget_event(frame_state^)`.

## File layout

| File | Contents |
| ---- | -------- |
| `foo.odin` | Types, theme_base, main `Foo` proc |
| `foo_trigger.odin` / `foo_content.odin` | Compound parts |
| `foo_shared.odin` | Private ctx, helpers, shutdown |
| `foo_test.odin` | Theme kind, merge, behavior |
| `test_helpers.odin` | Wire new `*_shutdown` into `with_widget_env` (setup + defer) |

Package is `oni_widgets`. Import engine as `o`, set helpers as `set`. App code imports widgets as `w` and prefers `oni/api.odin` for engine entry points.

## Ids and focus

- Stable `config.id` for focus, scroll, `GetElementById` / `FocusElement`, and text-edit maps.
- Empty id → engine auto key for the frame; prefer explicit ids for anything the app must address.
- Register tab order only when interactive (`widget_register_tab_order`).

## Style and paint

- Overrides through `set.*` when a helper exists — see [attributes.md](attributes.md).
- Resolve colors/borders/radius with `o.style_*` / `o.resolve_*` using `(config, &frame_state, event)` so interaction styles apply.
- Wrap paint in `o.Draw_Push_Opacity` / `Pop`; draw background → children → border (Button order).

## Testing

- Colocate `*_test.odin` in `widgets/`.
- Prefer `./oni/scripts/test_all.sh widgets` (keeps leak checks).
- Cover `theme_base` kind/defaults and any domain helpers (`Checkbox_Next_Value`, dismiss, merge).
- Compound / package-global ctx: add `foo_shutdown()` to [`test_helpers.odin`](../widgets/test_helpers.odin) `with_widget_env` — once before `o.ui_init()`, once in the `defer` block with the other `*_shutdown` calls.

## Checklist for a new widget

1. Pick template: Button (default), Checkbox (domain value), or Popover (compound).
2. Define `*_Config` / `*_State` / `*_Event` / `*_Props` with the config/props split.
3. Implement private `*_theme_base` with `kind` + `set.*` defaults.
4. Implement main proc with Layout lifecycle → children → return; Draw prepare → interaction → paint → children → dispatch.
5. Keep both passes’ tree identical for the same ids.
6. Domain: value on `config`, change via `on_*` only.
7. Compound: private ctx in `*_shared.odin`, push/pop on root, shutdown cleanup; register `*_shutdown` in `test_helpers.odin` `with_widget_env` (setup + defer).
8. Add tests; run `./oni/scripts/test_all.sh widgets`.

## Related docs

| Doc | Topic |
| --- | ----- |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Immediate mode, ownership, frame pipeline |
| [Layout.md](Layout.md) | Flex / grid solve, spaces, two-pass rules |
| [DRAW.md](DRAW.md) | Batching, interaction during draw |
| [attributes.md](attributes.md) | CSS ↔ style field map |
| [AGENTS.md](../AGENTS.md) | Contributor conventions |

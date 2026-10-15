package oni_widgets

import o ".."
import set "../set"

/*
Tabs root configuration.
*/
Tabs_Config :: struct {
	using _:     o.Widget_Config,
	value:       string,
	loop:        Tabs_Loop,
	orientation: Tabs_Orientation,
}

/*
Tabs root per-frame state.

`value` is the caller-owned selection. `loop` is true when arrow keys wrap.
*/
Tabs_State :: struct {
	using frame_state: o.Widget_Frame_State,
	config:            o.Resolved_Widget_Config,
	value:             string,
	loop:              bool,
	orientation:       Tabs_Orientation,
}

/*
Tabs root event snapshot.
*/
Tabs_Event :: o.Widget_Event(Tabs_State)

/*
Tabs root props.

`config.value` is owned by the caller and must be passed every frame. Choosing
a trigger reports the next value through `on_value_change` only — the widget
never writes caller state. An empty `config.value` means no panel is active.
`config.orientation` defaults to horizontal. `config.loop` defaults to wrapping.
*/
Tabs_Props :: struct {
	config:                       Tabs_Config,
	on_value_change:              proc(value: string),
	child:                        proc(frame_state: Tabs_State),
	unmount:                      bool,
	can_interactive_during_mount: bool,
	on_mount:                     proc(frame_state: Tabs_State) -> o.Mount,
	on_unmount:                   proc(frame_state: Tabs_State) -> o.Mount,
	on_scroll:                    proc(scroll_x, scroll_y: f32),
	on_focus:                     proc(event: Tabs_Event),
	on_blur:                      proc(event: Tabs_Event),
	on_mouse_enter:               proc(event: Tabs_Event),
	on_mouse_leave:               proc(event: Tabs_Event),
	on_mouse_pressed:             proc(event: Tabs_Event),
	on_mouse_down:                proc(event: Tabs_Event),
	on_mouse_released:            proc(event: Tabs_Event),
	on_mouse_move:                proc(event: Tabs_Event),
	on_click:                     proc(event: Tabs_Event),
	on_contextmenu:               proc(event: Tabs_Event),
	on_key_pressed:               proc(event: Tabs_Event),
	on_key_down:                  proc(event: Tabs_Event),
	on_key_released:              proc(event: Tabs_Event),
}

@(private)
tabs_theme_base :: proc(frame_state: ^Tabs_State) -> Tabs_Config {
	opacity := f32(1)
	direction := o.Direction_Layout.VERTICAL
	gap_x := u16(0)
	gap_y := u16(0)

	if frame_state.is_disabled {
		opacity = 0.5
	}

	// Vertical orientation places the list beside panels.
	if frame_state.orientation == .VERTICAL {
		direction = .HORIZONTAL
		gap_x = 0
		gap_y = 0
	}

	return Tabs_Config {
		kind = .TABS,
		tabbable = set.Tabbable(false),
		direction = set.Direction(direction),
		justify = set.Justify(o.Justify_Pos{x = .START, y = .START}),
		gap_x = set.Gap_X(gap_x),
		gap_y = set.Gap_Y(gap_y),
		opacity = set.F32(opacity),
		width = set.Width(.GROW),
	}
}

@(private)
tabs_refresh_merged :: proc(props: Tabs_Props, frame_state: ^Tabs_State) -> Tabs_Event {
	event := widget_event(frame_state^)
	base := tabs_theme_base(frame_state)
	frame_state.config = o.resolve_widget_config(base, props.config, frame_state, event)

	return widget_event(frame_state^)
}

/*
Renders a composable tabs root.

`Tabs_List` / `Tabs_Trigger` / `Tabs_Content` must be descendants. Tab moves to
the active enabled trigger, or the first enabled trigger when `value` matches
none. Arrow keys move focus; when the list sets `activate_on_focus`, they also
report a new value. Space and Enter activate the focused trigger.
*/
Tabs :: proc(props: Tabs_Props) {
	tabs_snapshots_begin_frame()

	cfg := props.config
	key := o.element_key(cfg.id)
	layout_label := cfg.id != "" ? cfg.id : key
	layout_id := o.ui_id(layout_label)
	was_focused := widget_is_focused(key)
	disabled := o.cfg_style_bool(cfg.disabled)
	orientation := tabs_orientation_normalize(cfg.orientation)
	loop := tabs_loop_enabled(cfg.loop)

	frame_state := Tabs_State {
		is_disabled = disabled,
		is_focused  = was_focused,
		value       = cfg.value,
		loop        = loop,
		orientation = orientation,
	}

	if disabled {
		cfg.disabled = set.Disabled(true)
	}

	resolved_props := props
	resolved_props.config = cfg
	event := tabs_refresh_merged(resolved_props, &frame_state)
	style_fp := widget_style_interaction_fp(&frame_state)
	config := frame_state.config
	handlers := widget_lifecycle_handlers(resolved_props, Tabs_State)
	should_auto_focus := config.auto_focus
	pushed := tabs_ctx_push(
		{
			key = key,
			value = cfg.value,
			disabled = disabled,
			loop = loop,
			orientation = orientation,
			activate_on_focus = false,
			variant = .DEFAULT,
			on_value_change = props.on_value_change,
		},
	)

	if pushed {
		tabs_ctx_apply_snapshot_policy(tabs_ctx_top())
	}

	defer {
		if pushed {
			tabs_ctx_pop()
		}
	}

	if o.ui_pass() == .Layout {
		skip_layout, ran_unmount := widget_run_layout_lifecycle(
			handlers,
			layout_id,
			cfg.id != "",
			&frame_state,
			config.visibility,
		)

		if ran_unmount {
			event = tabs_refresh_merged(resolved_props, &frame_state)
			config = frame_state.config
			should_auto_focus = config.auto_focus
		}

		if skip_layout {
			if pushed {
				tabs_snapshot_remove(key)
			}

			return
		}

		can_interact := widget_can_interact(handlers, &frame_state)
		widget_register_tab_order(key, config.tabbable, can_interact)
		widget_children(
			props.child,
			layout_id,
			config,
			frame_state,
			key,
			cfg,
			props.on_scroll,
			frame_state.is_hovered,
		)

		if pushed {
			ctx := tabs_ctx_top()
			tabs_snapshot_save(ctx)
			tabs_sync_tab_stop(ctx)
			tabs_apply_auto_focus(ctx, should_auto_focus && can_interact)
		}

		return
	}

	if !widget_prepare_draw(handlers, layout_id, &frame_state) {
		return
	}

	frame_state.is_focused = widget_is_focused(key)
	rect := o.ui_layout_rect(layout_id)
	widget_handle_interaction(
		resolved_props,
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

	if widget_style_interaction_fp(&frame_state) != style_fp {
		event = tabs_refresh_merged(resolved_props, &frame_state)
		config = frame_state.config
	}

	if widget_can_interact(handlers, &frame_state) {
		if widget_got_tab_focus(key) && props.on_focus != nil {
			props.on_focus(event)
		}

		if widget_lost_tab_focus(key) && props.on_blur != nil {
			props.on_blur(event)
		}
	}

	background: o.RGBA

	if resolved_background, ok := o.style_background_rgba(config, &frame_state, event); ok {
		background = resolved_background
	}

	border: o.Bd_px

	if resolved_border, ok := o.resolve_border(config.border, &frame_state, event); ok {
		border = resolved_border
	}

	border_color: o.RGBA

	if resolved_border_color, ok := o.style_border_color_rgba(config, &frame_state, event); ok {
		border_color = resolved_border_color
	}

	radius: o.Radius_px

	if resolved_radius, ok := o.resolve_radius(config.radius, &frame_state, event); ok {
		radius = resolved_radius
	}

	o.Draw_Push_Opacity(config.opacity)
	defer o.Draw_Pop_Opacity()

	// Move focus / selection before triggers paint so an earlier sibling shows
	// the new active state in this frame.
	if pushed && o.w_ctx != nil {
		tabs_handle_keyboard(o.w_ctx.focused_id)
	}

	widget_draw_box_background(layout_id, rect, background, radius)
	widget_children(
		props.child,
		layout_id,
		config,
		frame_state,
		key,
		cfg,
		props.on_scroll,
		frame_state.is_hovered,
	)

	if pushed {
		tabs_flush_arrow_focus(key)

		if tabs_arrow_blur_group == key {
			tabs_arrow_blur = ""
			tabs_arrow_blur_group = ""
		}
	}

	widget_draw_box_border(layout_id, rect, radius, border, border_color)
	widget_dispatch_events(resolved_props, &frame_state, handlers, event, key, was_focused)
}

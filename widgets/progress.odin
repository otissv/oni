package oni_widgets

import o ".."
import set "../set"

/*
Progress root configuration: caller-owned value plus optional range / track metrics.

`indeterminate` matches Base UI `value = null`. `inverted` fills from the trailing
edge (RTL-friendly). `track_thickness` defaults to `PROGRESS_DEFAULT_TRACK_THICKNESS`
when unset.
*/
Progress_Config :: struct {
	using _:         o.Widget_Config,
	value:           f32,
	min:             f32,
	max:             f32,
	indeterminate:   bool,
	inverted:        bool,
	track_thickness: o.Cfg(o.Style_F32),
}

/*
Progress root per-frame state with resolved style and domain mirrors.
*/
Progress_State :: struct {
	using frame_state: o.Widget_Frame_State,
	config:            o.Resolved_Widget_Config,
	value:             f32,
	min:               f32,
	max:               f32,
	ratio:             f32,
	indeterminate:     bool,
	inverted:          bool,
	status:            Progress_Status,
	disabled:          bool,
}

/*
Progress root event snapshot.
*/
Progress_Event :: o.Widget_Event(Progress_State)

/*
Progress root props: caller-owned `config.value` every frame.

Compose with `Progress_Label`, `Progress_Value`, `Progress_Track`, and
`Progress_Indicator` inside `child`. When `child` is nil,
`Progress_Default_Parts` renders track + indicator. Display-only — the app
updates `config.value`; there is no `on_value_change`.
*/
Progress_Props :: struct {
	config:                       Progress_Config,
	child:                        proc(frame_state: Progress_State),
	unmount:                      bool,
	can_interactive_during_mount: bool,
	on_mount:                     proc(frame_state: Progress_State) -> o.Mount,
	on_unmount:                   proc(frame_state: Progress_State) -> o.Mount,
	on_scroll:                    proc(scroll_x, scroll_y: f32),
	on_focus:                     proc(event: Progress_Event),
	on_blur:                      proc(event: Progress_Event),
	on_mouse_enter:               proc(event: Progress_Event),
	on_mouse_leave:               proc(event: Progress_Event),
	on_mouse_pressed:             proc(event: Progress_Event),
	on_mouse_down:                proc(event: Progress_Event),
	on_mouse_released:            proc(event: Progress_Event),
	on_mouse_move:                proc(event: Progress_Event),
	on_click:                     proc(event: Progress_Event),
	on_contextmenu:               proc(event: Progress_Event),
	on_key_pressed:               proc(event: Progress_Event),
	on_key_down:                  proc(event: Progress_Event),
	on_key_released:              proc(event: Progress_Event),
}

@(private)
progress_theme_base :: proc(frame_state: ^Progress_State) -> Progress_Config {
	opacity := f32(1)

	if frame_state.is_disabled {
		opacity = 0.5
	}

	return Progress_Config {
		kind = .PROGRESS,
		tabbable = set.Tabbable(false),
		direction = set.Direction(.VERTICAL),
		gap_y = set.Gap_Y(u16(8)),
		width = set.Width(PROGRESS_DEFAULT_WIDTH),
		opacity = set.F32(opacity),
		background = set.Background(o.Color.TRANSPARENT),
	}
}

@(private)
progress_refresh_merged :: proc(
	props: Progress_Props,
	frame_state: ^Progress_State,
) -> Progress_Event {
	event := widget_event(frame_state^)
	base := progress_theme_base(frame_state)
	frame_state.config = o.resolve_widget_config(base, props.config, frame_state, event)

	return widget_event(frame_state^)
}

@(private)
progress_refresh_merged_if_interaction_changed :: proc(
	props: Progress_Props,
	frame_state: ^Progress_State,
	prev_fp: u8,
) -> (
	event: Progress_Event,
	fp: u8,
) {
	fp = widget_style_interaction_fp(frame_state)

	if fp == prev_fp {
		return widget_event(frame_state^), fp
	}

	return progress_refresh_merged(props, frame_state), fp
}

/*
Default progress composition: track with nested indicator.

Used when `Progress.child` is nil.
*/
Progress_Default_Parts :: proc(frame_state: Progress_State) {
	_ = frame_state

	if !progress_ctx_ok() {
		return
	}

	ctx := progress_ctx_top()

	Progress_Track({
		config = {id = progress_part_id(ctx.parent_key, "track")},
		child = progress_default_track_child,
	})
}

@(private)
progress_default_track_child :: proc(_: Progress_Track_State) {
	Progress_Indicator({})
}

/*
Renders a composable progress root.

`config.value` / `config.indeterminate` are caller-owned. Parts share live state
through the private progress context stack.
*/
Progress :: proc(props: Progress_Props) {
	cfg := props.config
	key := o.element_key(cfg.id)
	layout_label := cfg.id != "" ? cfg.id : key
	layout_id := o.ui_id(layout_label)

	was_focused := widget_is_focused(key)
	disabled := o.cfg_style_bool(cfg.disabled)
	min_v, max_v := progress_resolve_bounds(cfg.min, cfg.max)
	indeterminate := cfg.indeterminate
	ratio := Progress_Ratio(cfg.value, min_v, max_v)
	status := Progress_Resolve_Status(cfg.value, min_v, max_v, indeterminate)
	track_thickness := progress_resolve_track_thickness(cfg)

	frame_state := Progress_State {
		is_disabled    = disabled,
		is_focused     = was_focused,
		value          = cfg.value,
		min            = min_v,
		max            = max_v,
		ratio          = ratio,
		indeterminate  = indeterminate,
		inverted       = cfg.inverted,
		status         = status,
		disabled       = disabled,
	}

	props_resolved := props
	props_resolved.config = cfg

	event := progress_refresh_merged(props_resolved, &frame_state)
	style_fp := widget_style_interaction_fp(&frame_state)
	config := frame_state.config
	handlers := widget_lifecycle_handlers(props_resolved, Progress_State)
	should_auto_focus := widget_should_auto_focus(config, key)
	child := props.child

	if child == nil {
		child = Progress_Default_Parts
	}

	progress_ctx_push(
		{
			value = cfg.value,
			min = min_v,
			max = max_v,
			ratio = ratio,
			indeterminate = indeterminate,
			inverted = cfg.inverted,
			disabled = disabled,
			status = status,
			track_thickness = track_thickness,
			parent_key = key,
		},
	)
	defer progress_ctx_pop()

	if o.ui_pass() == .Layout {
		skip_layout, ran_unmount := widget_run_layout_lifecycle(
			handlers,
			layout_id,
			cfg.id != "",
			&frame_state,
			config.visibility,
		)

		if ran_unmount {
			event = progress_refresh_merged(props_resolved, &frame_state)
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
				child,
				layout_id,
				config,
				frame_state,
				key,
				props_resolved.config,
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
		props_resolved,
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

	event, _ = progress_refresh_merged_if_interaction_changed(props_resolved, &frame_state, style_fp)
	config = frame_state.config

	if widget_can_interact(handlers, &frame_state) {
		if widget_got_tab_focus(key) && props.on_focus != nil {
			props.on_focus(event)
		}

		if widget_lost_tab_focus(key) && props.on_blur != nil {
			props.on_blur(event)
		}
	}

	if should_auto_focus &&
	   !was_focused &&
	   props.on_focus != nil &&
	   widget_can_interact(handlers, &frame_state) {
		props.on_focus(event)
	}

	background: o.RGBA

	if resolved_background, background_ok := o.style_background_rgba(config, &frame_state, event);
	   background_ok {
		background = resolved_background
	}

	border: o.Bd_px

	if resolved_border, border_ok := o.resolve_border(config.border, &frame_state, event);
	   border_ok {
		border = resolved_border
	}

	border_color: o.RGBA

	if resolved_border_color, border_color_ok := o.style_border_color_rgba(
		config,
		&frame_state,
		event,
	); border_color_ok {
		border_color = resolved_border_color
	}

	radius: o.Radius_px

	if resolved_radius, ok := o.resolve_radius(config.radius, &frame_state, event); ok {
		radius = resolved_radius
	}

	o.Draw_Push_Opacity(config.opacity)
	defer o.Draw_Pop_Opacity()

	widget_draw_box_background(layout_id, rect, background, radius)

	widget_children(
		child,
		layout_id,
		config,
		frame_state,
		key,
		props_resolved.config,
		props.on_scroll,
		frame_state.is_hovered,
	)

	widget_draw_box_border(layout_id, rect, radius, border, border_color)

	widget_dispatch_events(props_resolved, &frame_state, handlers, event, key, was_focused)
}

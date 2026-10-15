package oni_widgets

import o ".."
import set "../set"

/*
Progress track configuration.
*/
Progress_Track_Config :: o.Widget_Config

/*
Progress track per-frame state.
*/
Progress_Track_State :: o.Widget_Merged_State(o.Widget_Frame_State, o.Resolved_Widget_Config)

/*
Progress track event snapshot.
*/
Progress_Track_Event :: o.Widget_Event(Progress_Track_State)

/*
Progress track props: bar that hosts `Progress_Indicator`.
*/
Progress_Track_Props :: struct {
	config:                       Progress_Track_Config,
	child:                        proc(frame_state: Progress_Track_State),
	unmount:                      bool,
	can_interactive_during_mount: bool,
	on_mount:                     proc(frame_state: Progress_Track_State) -> o.Mount,
	on_unmount:                   proc(frame_state: Progress_Track_State) -> o.Mount,
	on_scroll:                    proc(scroll_x, scroll_y: f32),
	on_focus:                     proc(event: Progress_Track_Event),
	on_blur:                      proc(event: Progress_Track_Event),
	on_mouse_enter:               proc(event: Progress_Track_Event),
	on_mouse_leave:               proc(event: Progress_Track_Event),
	on_mouse_pressed:             proc(event: Progress_Track_Event),
	on_mouse_down:                proc(event: Progress_Track_Event),
	on_mouse_released:            proc(event: Progress_Track_Event),
	on_mouse_move:                proc(event: Progress_Track_Event),
	on_click:                     proc(event: Progress_Track_Event),
	on_contextmenu:               proc(event: Progress_Track_Event),
	on_key_pressed:               proc(event: Progress_Track_Event),
	on_key_down:                  proc(event: Progress_Track_Event),
	on_key_released:              proc(event: Progress_Track_Event),
}

/*
Progress indicator configuration.
*/
Progress_Indicator_Config :: o.Widget_Config

/*
Progress indicator props: paints the fill inside the active track.
*/
Progress_Indicator_Props :: struct {
	config: Progress_Indicator_Config,
}

@(private)
progress_track_theme_base :: proc(
	frame_state: ^Progress_Track_State,
	track_thickness: f32,
) -> Progress_Track_Config {
	_ = frame_state

	return Progress_Track_Config {
		kind = .PROGRESS_TRACK,
		tabbable = set.Tabbable(false),
		width = set.Width(.GROW),
		height = set.Height(track_thickness),
		background = set.Background(o.Color.MUTED),
		overflow_x = set.Overflow_X(.HIDDEN),
		overflow_y = set.Overflow_Y(.HIDDEN),
	}
}

@(private)
progress_indicator_theme_base :: proc(
	frame_state: ^Progress_Track_State,
	track_thickness: f32,
) -> Progress_Indicator_Config {
	_ = frame_state

	return Progress_Indicator_Config {
		kind = .PROGRESS_INDICATOR,
		tabbable = set.Tabbable(false),
		background = set.Background(o.Color.PRIMARY),
	}
}

@(private)
progress_track_refresh_merged :: proc(
	props: Progress_Track_Props,
	frame_state: ^Progress_Track_State,
	track_thickness: f32,
) -> Progress_Track_Event {
	event := widget_event(frame_state^)
	base := progress_track_theme_base(frame_state, track_thickness)
	frame_state.config = o.resolve_widget_config(base, props.config, frame_state, event)

	return widget_event(frame_state^)
}

@(private)
progress_draw_part_box :: proc(
	layout_id: o.UI_Id,
	rect: o.Rect,
	config: o.Resolved_Widget_Config,
	frame_state: ^$S,
	event: o.Widget_Event(S),
) {
	if o.ui_layout_paint_skip(layout_id) || rect.w <= 0 || rect.h <= 0 {
		return
	}

	background: o.RGBA

	if resolved_bg, ok := o.style_background_rgba(config, frame_state, event); ok {
		background = resolved_bg
	}

	border: o.Bd_px

	if resolved_border, ok := o.resolve_border(config.border, frame_state, event); ok {
		border = resolved_border
	}

	border_color: o.RGBA

	if resolved_bc, ok := o.style_border_color_rgba(config, frame_state, event); ok {
		border_color = resolved_bc
	}

	radius: o.Radius_px

	if resolved_radius, ok := o.resolve_radius(config.radius, frame_state, event); ok {
		radius = resolved_radius
	}

	o.Draw_Push_Opacity(config.opacity)
	defer o.Draw_Pop_Opacity()

	widget_draw_box_background(layout_id, rect, background, radius)
	widget_draw_box_border(layout_id, rect, radius, border, border_color)
}

/*
Renders the progress track bar.

Must be used inside `Progress`. Optional `child` typically nests `Progress_Indicator`.
*/
Progress_Track :: proc(props: Progress_Track_Props) {
	if !progress_ctx_ok() {
		return
	}

	ctx := progress_ctx_top()
	cfg := props.config

	if cfg.id == "" {
		cfg.id = progress_part_id(ctx.parent_key, "track")
	}

	if ctx.disabled {
		cfg.disabled = set.Disabled(true)
	}

	key := o.element_key(cfg.id)
	layout_label := cfg.id != "" ? cfg.id : key
	layout_id := o.ui_id(layout_label)

	was_focused := widget_is_focused(key)
	disabled := o.cfg_style_bool(cfg.disabled) || ctx.disabled

	frame_state := Progress_Track_State {
		is_disabled = disabled,
		is_focused  = was_focused,
	}

	props_resolved := props
	props_resolved.config = cfg

	event := progress_track_refresh_merged(props_resolved, &frame_state, ctx.track_thickness)
	style_fp := widget_style_interaction_fp(&frame_state)
	config := frame_state.config
	handlers := widget_lifecycle_handlers(props_resolved, Progress_Track_State)
	should_auto_focus := widget_should_auto_focus(config, key)
	child := props.child

	ctx.track_layout_id = layout_id

	if o.ui_pass() == .Layout {
		skip_layout, ran_unmount := widget_run_layout_lifecycle(
			handlers,
			layout_id,
			cfg.id != "",
			&frame_state,
			config.visibility,
		)

		if ran_unmount {
			event = progress_track_refresh_merged(
				props_resolved,
				&frame_state,
				ctx.track_thickness,
			)
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
	ctx.track_rect = rect
	ctx.track_layout_id = layout_id

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

	fp := widget_style_interaction_fp(&frame_state)

	if fp != style_fp {
		event = progress_track_refresh_merged(props_resolved, &frame_state, ctx.track_thickness)
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

/*
Paints the progress fill indicator inside the active `Progress_Track`.

Must be used inside `Progress` (typically as `Progress_Track.child`). Paint-only —
does not register its own layout node.
*/
Progress_Indicator :: proc(props: Progress_Indicator_Props) {
	if !progress_ctx_ok() {
		return
	}

	ctx := progress_ctx_top()
	cfg := props.config

	if cfg.id == "" {
		cfg.id = progress_part_id(ctx.parent_key, "indicator")
	}

	_ = o.element_key(cfg.id)

	if o.ui_pass() == .Layout {
		return
	}

	track_id := ctx.track_layout_id
	track := ctx.track_rect

	if track.w <= 0 || track.h <= 0 {
		if track_id != 0 {
			track = o.ui_layout_rect(track_id)
		}
	}

	indicator := Progress_Indicator_Rect(track, ctx.ratio, ctx.indeterminate, ctx.inverted)

	if indicator.w <= 0 || indicator.h <= 0 {
		return
	}

	parent_state := Progress_Track_State {
		is_disabled = ctx.disabled,
	}
	event := widget_event(parent_state)
	base := progress_indicator_theme_base(&parent_state, ctx.track_thickness)
	resolved := o.resolve_widget_config(base, cfg, &parent_state, event)

	if track_id == 0 {
		return
	}

	progress_draw_part_box(track_id, indicator, resolved, &parent_state, event)
}

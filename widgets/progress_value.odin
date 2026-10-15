package oni_widgets

import o ".."
import set "../set"

/*
Progress value configuration.
*/
Progress_Value_Config :: o.Widget_Config

/*
Progress value per-frame state with resolved display text.
*/
Progress_Value_State :: struct {
	using frame_state: o.Widget_Frame_State,
	config:            o.Resolved_Widget_Config,
	text:              string,
	value:             f32,
	min:               f32,
	max:               f32,
	indeterminate:     bool,
	status:            Progress_Status,
}

/*
Progress value event snapshot.
*/
Progress_Value_Event :: o.Widget_Event(Progress_Value_State)

/*
Progress value props: formatted value for the parent `Progress`.

`format` overrides `Progress_Format_Default`. When `child` is set it replaces
the default Text run.
*/
Progress_Value_Props :: struct {
	config:                       Progress_Value_Config,
	format:                       proc(value, min_v, max_v: f32, indeterminate: bool) -> string,
	child:                        proc(frame_state: Progress_Value_State),
	unmount:                      bool,
	can_interactive_during_mount: bool,
	on_mount:                     proc(frame_state: Progress_Value_State) -> o.Mount,
	on_unmount:                   proc(frame_state: Progress_Value_State) -> o.Mount,
	on_scroll:                    proc(scroll_x, scroll_y: f32),
	on_focus:                     proc(event: Progress_Value_Event),
	on_blur:                      proc(event: Progress_Value_Event),
	on_mouse_enter:               proc(event: Progress_Value_Event),
	on_mouse_leave:               proc(event: Progress_Value_Event),
	on_mouse_pressed:             proc(event: Progress_Value_Event),
	on_mouse_down:                proc(event: Progress_Value_Event),
	on_mouse_released:            proc(event: Progress_Value_Event),
	on_mouse_move:                proc(event: Progress_Value_Event),
	on_click:                     proc(event: Progress_Value_Event),
	on_contextmenu:               proc(event: Progress_Value_Event),
	on_key_pressed:               proc(event: Progress_Value_Event),
	on_key_down:                  proc(event: Progress_Value_Event),
	on_key_released:              proc(event: Progress_Value_Event),
}

@(private)
progress_value_theme_base :: proc(frame_state: ^Progress_Value_State) -> Progress_Value_Config {
	_ = frame_state

	return Progress_Value_Config {
		kind = .PROGRESS_VALUE,
		line_height = set.F32(1),
		tabbable = set.Tabbable(false),
		pointer_events = set.Pointer_Events(.NONE),
		color = set.Colors(o.Color.MUTED_FOREGROUND),
	}
}

@(private)
progress_value_refresh_merged :: proc(
	props: Progress_Value_Props,
	frame_state: ^Progress_Value_State,
) -> Progress_Value_Event {
	event := widget_event(frame_state^)
	base := progress_value_theme_base(frame_state)
	frame_state.config = o.resolve_widget_config(base, props.config, frame_state, event)

	return widget_event(frame_state^)
}

@(private)
progress_value_resolve_text :: proc(props: Progress_Value_Props) -> (
	text: string,
	value: f32,
	min_v: f32,
	max_v: f32,
	indeterminate: bool,
	status: Progress_Status,
) {
	if !progress_ctx_ok() {
		return "", 0, PROGRESS_DEFAULT_MIN, PROGRESS_DEFAULT_MAX, false, .PROGRESSING
	}

	ctx := progress_ctx_top()
	value = ctx.value
	min_v = ctx.min
	max_v = ctx.max
	indeterminate = ctx.indeterminate
	status = ctx.status

	if props.format != nil {
		text = props.format(value, min_v, max_v, indeterminate)
	} else {
		text = Progress_Format_Default(value, min_v, max_v, indeterminate)
	}

	return
}

@(private)
progress_value_text_child :: proc(fs: Progress_Value_State) {
	if fs.text == "" {
		return
	}

	Text({config = {text = fs.text, color = set.Colors(o.Color.MUTED_FOREGROUND)}})
}

/*
Renders the formatted value for the parent `Progress`.

Must be used inside `Progress`.
*/
Progress_Value :: proc(props: Progress_Value_Props) {
	if !progress_ctx_ok() {
		return
	}

	ctx := progress_ctx_top()
	cfg := props.config

	if cfg.id == "" {
		cfg.id = progress_part_id(ctx.parent_key, "value")
	}

	if ctx.disabled {
		cfg.disabled = set.Disabled(true)
	}

	key := o.element_key(cfg.id)
	layout_label := cfg.id != "" ? cfg.id : key
	layout_id := o.ui_id(layout_label)

	was_focused := widget_is_focused(key)
	disabled := o.cfg_style_bool(cfg.disabled) || ctx.disabled
	text, value, min_v, max_v, indeterminate, status := progress_value_resolve_text(props)

	frame_state := Progress_Value_State {
		is_disabled    = disabled,
		is_focused     = was_focused,
		text           = text,
		value          = value,
		min            = min_v,
		max            = max_v,
		indeterminate  = indeterminate,
		status         = status,
	}

	props_resolved := props
	props_resolved.config = cfg

	event := progress_value_refresh_merged(props_resolved, &frame_state)
	style_fp := widget_style_interaction_fp(&frame_state)
	config := frame_state.config
	handlers := widget_lifecycle_handlers(props_resolved, Progress_Value_State)
	should_auto_focus := widget_should_auto_focus(config, key)
	child := props.child

	if child == nil {
		child = progress_value_text_child
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
			event = progress_value_refresh_merged(props_resolved, &frame_state)
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

	fp := widget_style_interaction_fp(&frame_state)

	if fp != style_fp {
		event = progress_value_refresh_merged(props_resolved, &frame_state)
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

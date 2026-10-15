package oni_widgets

import o ".."
import set "../set"

/*
The three semantic values exposed by a Checkbox.
*/
Checkbox_Value :: enum {
	FALSE,
	TRUE,
	INDETERMINATE,
}

/*
Checkbox configuration.
*/
Checkbox_Config :: struct {
	using _:   o.Widget_Config,
	checked:   Checkbox_Value,
}

/*
Checkbox per-frame state, including its resolved three-state value.
*/
Checkbox_State :: struct {
	using frame_state: o.Widget_Frame_State,
	config:            o.Resolved_Widget_Config,
	checked:           Checkbox_Value,
}

/*
Checkbox event snapshot.
*/
Checkbox_Event :: o.Widget_Event(Checkbox_State)

/*
Checkbox props.

`config.checked` is owned by the caller and must be passed every frame. Activation
reports the next value through `on_checked_change` only — the widget never
mutates caller state. `child` replaces the built-in check/minus indicator and is
only called for TRUE and INDETERMINATE states.
*/
Checkbox_Props :: struct {
	config:                       Checkbox_Config,
	child:                        proc(frame_state: Checkbox_State),
	on_checked_change:            proc(checked: Checkbox_Value),
	unmount:                      bool,
	can_interactive_during_mount: bool,
	on_mount:                     proc(frame_state: Checkbox_State) -> o.Mount,
	on_unmount:                   proc(frame_state: Checkbox_State) -> o.Mount,
	on_scroll:                    proc(scroll_x, scroll_y: f32),
	on_focus:                     proc(event: Checkbox_Event),
	on_blur:                      proc(event: Checkbox_Event),
	on_mouse_enter:               proc(event: Checkbox_Event),
	on_mouse_leave:               proc(event: Checkbox_Event),
	on_mouse_pressed:             proc(event: Checkbox_Event),
	on_mouse_down:                proc(event: Checkbox_Event),
	on_mouse_released:            proc(event: Checkbox_Event),
	on_mouse_move:                proc(event: Checkbox_Event),
	on_click:                     proc(event: Checkbox_Event),
	on_contextmenu:               proc(event: Checkbox_Event),
	on_key_pressed:               proc(event: Checkbox_Event),
	on_key_down:                  proc(event: Checkbox_Event),
	on_key_released:              proc(event: Checkbox_Event),
}

@(private)
Checkbox_Action_Context :: struct {
	active:            bool,
	on_checked_change: proc(checked: Checkbox_Value),
	on_click:          proc(event: Checkbox_Event),
}

@(private)
checkbox_action_context: Checkbox_Action_Context

@(private)
checkbox_value_normalize :: proc(value: Checkbox_Value) -> Checkbox_Value {
	switch value {
	case .FALSE, .TRUE, .INDETERMINATE:
		return value
	case:
		return .FALSE
	}
}

/*
Returns the value produced by user activation.

An indeterminate checkbox becomes checked.
*/
Checkbox_Next_Value :: proc(value: Checkbox_Value) -> Checkbox_Value {
	switch checkbox_value_normalize(value) {
	case .FALSE:
		return .TRUE
	case .TRUE:
		return .FALSE
	case .INDETERMINATE:
		return .TRUE
	}

	return .FALSE
}

@(private)
checkbox_theme_base :: proc(frame_state: ^Checkbox_State) -> Checkbox_Config {
	active := frame_state.checked != .FALSE
	background := o.Colors(o.Color.BACKGROUND)
	border_color := o.Colors(o.Color.BORDER)

	if active {
		background = o.Color.PRIMARY
		border_color = o.Color.PRIMARY

		if frame_state.is_Pressed {
			background = o.Color.PRIMARY_PRESSED
		} else if frame_state.is_hovered {
			background = o.Color.PRIMARY_HOVER
		}
	}

	if frame_state.is_focused {
		border_color = o.Color.RING
	}

	opacity := f32(1)
	if frame_state.is_disabled {
		opacity = 0.5
	}

	return Checkbox_Config {
		kind = .CHECKBOX,
		tabbable = set.Tabbable(true),
		width = set.Width(f32(16)),
		height = set.Height(f32(16)),
		justify = set.Justify(o.Justify_Align.CENTER),
		border = set.Border(f32(1)),
		border_color = set.Border_color(border_color),
		radius = set.Radius(f32(4)),
		background = set.Background(background),
		color = set.Colors(o.Color.PRIMARY_FOREGROUND),
		opacity = set.F32(opacity),
		overflow_x = set.Overflow_X(.HIDDEN),
		overflow_y = set.Overflow_Y(.HIDDEN),
	}
}

@(private)
checkbox_refresh_merged :: proc(
	props: Checkbox_Props,
	frame_state: ^Checkbox_State,
) -> Checkbox_Event {
	event := widget_event(frame_state^)
	base := checkbox_theme_base(frame_state)
	frame_state.config = o.resolve_widget_config(base, props.config, frame_state, event)

	return widget_event(frame_state^)
}

@(private)
checkbox_on_click :: proc(event: Checkbox_Event) {
	ctx := &checkbox_action_context
	if !ctx.active do return
	if event.key == .RETURN do return

	next := Checkbox_Next_Value(event.frame_state.checked)

	if ctx.on_checked_change != nil {
		ctx.on_checked_change(next)
	}

	if ctx.on_click != nil {
		ctx.on_click(event)
	}
}

@(private)
checkbox_draw_indicator :: proc(
	layout_id: o.UI_Id,
	rect: o.Rect,
	checked: Checkbox_Value,
	color: o.RGBA,
) {
	if checked == .FALSE || o.ui_layout_paint_skip(layout_id) do return

	min_side := min(rect.w, rect.h)
	thickness := max(f32(1.5), min_side * 0.125)

	if checked == .INDETERMINATE {
		y := rect.y + rect.h * 0.5
		o.Draw_Line({rect.x + rect.w * 0.25, y}, {rect.x + rect.w * 0.75, y}, color, thickness)

		return
	}

	o.Draw_Line(
		{rect.x + rect.w * 0.2, rect.y + rect.h * 0.52},
		{rect.x + rect.w * 0.42, rect.y + rect.h * 0.72},
		color,
		thickness,
	)
	o.Draw_Line(
		{rect.x + rect.w * 0.42, rect.y + rect.h * 0.72},
		{rect.x + rect.w * 0.8, rect.y + rect.h * 0.28},
		color,
		thickness,
	)
}

/*
Renders a production three-state checkbox.

`checked` is caller-owned. Pointer release and Space report the next value via
`on_checked_change`; Enter is ignored. Disabled and mounting widgets cannot
focus or change value.
*/
Checkbox :: proc(props: Checkbox_Props) {
	cfg := props.config
	key := o.element_key(cfg.id)
	layout_label := cfg.id != "" ? cfg.id : key
	layout_id := o.ui_id(layout_label)

	checked := checkbox_value_normalize(cfg.checked)
	was_focused := widget_is_focused(key)
	disabled := o.cfg_style_bool(cfg.disabled)

	frame_state := Checkbox_State {
		is_disabled = disabled,
		is_focused  = was_focused,
		checked     = checked,
	}

	resolved_props := props
	resolved_props.config = cfg

	event := checkbox_refresh_merged(resolved_props, &frame_state)
	style_fp := widget_style_interaction_fp(&frame_state)
	config := frame_state.config
	handlers := widget_lifecycle_handlers(resolved_props, Checkbox_State)
	should_auto_focus := widget_should_auto_focus(config, key)
	indicator_child := props.child

	if checked == .FALSE {
		indicator_child = nil
	}

	previous_action_context := checkbox_action_context
	checkbox_action_context = {
		active            = true,
		on_checked_change = props.on_checked_change,
		on_click          = props.on_click,
	}
	defer checkbox_action_context = previous_action_context

	props_with_toggle := resolved_props
	props_with_toggle.on_click = checkbox_on_click

	if o.ui_pass() == .Layout {
		skip_layout, ran_unmount := widget_run_layout_lifecycle(
			handlers,
			layout_id,
			cfg.id != "",
			&frame_state,
			config.visibility,
		)

		if ran_unmount {
			event = checkbox_refresh_merged(resolved_props, &frame_state)
			config = frame_state.config
			should_auto_focus = widget_should_auto_focus(config, key)
		}

		if skip_layout {
			return
		}

		can_interact := widget_can_interact(handlers, &frame_state)

		if can_interact && should_auto_focus {
			widget_apply_auto_focus(key, true)
			frame_state.is_focused = true
		}

		widget_register_tab_order(key, config.tabbable, can_interact)

		widget_children(
			indicator_child,
			layout_id,
			config,
			frame_state,
			key,
			cfg,
			props.on_scroll,
			frame_state.is_hovered,
		)

		return
	}

	if !widget_prepare_draw(handlers, layout_id, &frame_state) do return

	frame_state.is_focused = widget_is_focused(key)
	rect := o.ui_layout_rect(layout_id)

	widget_handle_interaction(
		props_with_toggle,
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
		event = checkbox_refresh_merged(resolved_props, &frame_state)
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

	indicator_color: o.RGBA
	if resolved_color, ok := o.style_color_rgba(config, &frame_state, event); ok {
		indicator_color = resolved_color
	}

	o.Draw_Push_Opacity(config.opacity)
	defer o.Draw_Pop_Opacity()

	widget_draw_box_background(layout_id, rect, background, radius)

	widget_children(
		indicator_child,
		layout_id,
		config,
		frame_state,
		key,
		cfg,
		props.on_scroll,
		frame_state.is_hovered,
	)

	if indicator_child == nil {
		checkbox_draw_indicator(layout_id, rect, checked, indicator_color)
	}

	widget_draw_box_border(layout_id, rect, radius, border, border_color)

	widget_dispatch_events(props_with_toggle, &frame_state, handlers, event, key, was_focused)
}

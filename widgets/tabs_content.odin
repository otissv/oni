package oni_widgets

import o ".."
import set "../set"

/*
Tabs content configuration.

`value` selects which root value shows this panel. `force_mount` keeps inactive panels
in the tree with `HIDDEN` instead of removing them from layout (`visibility = NONE`).
*/
Tabs_Content_Config :: struct {
	using _:     o.Widget_Config,
	value:       string,
	force_mount: bool,
}

/*
Tabs content per-frame state.

`active` is true when this panel's `value` matches the root selection.
*/
Tabs_Content_State :: struct {
	using frame_state: o.Widget_Frame_State,
	config:            o.Resolved_Widget_Config,
	value:             string,
	active:            bool,
}

/*
Tabs content event snapshot.
*/
Tabs_Content_Event :: o.Widget_Event(Tabs_Content_State)

/*
Tabs content props.

Inactive panels use `visibility = NONE` (removed from layout) unless
`config.force_mount` keeps them in the tree with `HIDDEN`. Outside a `Tabs` root
the panel stays inert and hidden.
*/
Tabs_Content_Props :: struct {
	config:                       Tabs_Content_Config,
	child:                        proc(frame_state: Tabs_Content_State),
	unmount:                      bool,
	can_interactive_during_mount: bool,
	on_mount:                     proc(frame_state: Tabs_Content_State) -> o.Mount,
	on_unmount:                   proc(frame_state: Tabs_Content_State) -> o.Mount,
	on_scroll:                    proc(scroll_x, scroll_y: f32),
	on_focus:                     proc(event: Tabs_Content_Event),
	on_blur:                      proc(event: Tabs_Content_Event),
	on_mouse_enter:               proc(event: Tabs_Content_Event),
	on_mouse_leave:               proc(event: Tabs_Content_Event),
	on_mouse_pressed:             proc(event: Tabs_Content_Event),
	on_mouse_down:                proc(event: Tabs_Content_Event),
	on_mouse_released:            proc(event: Tabs_Content_Event),
	on_mouse_move:                proc(event: Tabs_Content_Event),
	on_click:                     proc(event: Tabs_Content_Event),
	on_contextmenu:               proc(event: Tabs_Content_Event),
	on_key_pressed:               proc(event: Tabs_Content_Event),
	on_key_down:                  proc(event: Tabs_Content_Event),
	on_key_released:              proc(event: Tabs_Content_Event),
}

@(private)
tabs_content_theme_base :: proc(frame_state: ^Tabs_Content_State) -> Tabs_Content_Config {
	visibility: o.Visibility = .VISIBLE

	if !frame_state.active {
		visibility = .NONE
	}

	return Tabs_Content_Config {
		kind = .TABS_CONTENT,
		tabbable = set.Tabbable(false),
		direction = set.Direction(.VERTICAL),
		justify = set.Justify(o.Justify_Pos{x = .START, y = .START}),
		padding = set.Padding(o.Pd_pos{x = 0, y = 8}),
		visibility = set.Visibility(visibility),
	}
}

@(private)
tabs_content_refresh_merged :: proc(
	props: Tabs_Content_Props,
	frame_state: ^Tabs_Content_State,
) -> Tabs_Content_Event {
	event := widget_event(frame_state^)
	base := tabs_content_theme_base(frame_state)

	if !frame_state.active && props.config.force_mount {
		base.visibility = set.Visibility(.HIDDEN)
	}

	frame_state.config = o.resolve_widget_config(base, props.config, frame_state, event)

	return widget_event(frame_state^)
}

@(private)
tabs_content_is_active :: proc(value: string) -> bool {
	if !tabs_ctx_ok() || value == "" {
		return false
	}

	current := tabs_ctx_top().value

	return current != "" && current == value
}

/*
Renders one tab panel inside a `Tabs` root.

Only the panel whose `value` matches the root selection lays out and draws its
children, unless `force_mount` keeps inactive panels in the tree as `HIDDEN`.
*/
Tabs_Content :: proc(props: Tabs_Content_Props) {
	cfg := props.config
	key := o.element_key(cfg.id)
	layout_label := cfg.id != "" ? cfg.id : key
	layout_id := o.ui_id(layout_label)
	was_focused := widget_is_focused(key)
	active := tabs_content_is_active(cfg.value)

	frame_state := Tabs_Content_State {
		is_disabled = o.cfg_style_bool(cfg.disabled),
		is_focused  = was_focused,
		value       = cfg.value,
		active      = active,
	}

	resolved_props := props
	resolved_props.config = cfg
	event := tabs_content_refresh_merged(resolved_props, &frame_state)
	style_fp := widget_style_interaction_fp(&frame_state)
	config := frame_state.config
	handlers := widget_lifecycle_handlers(resolved_props, Tabs_Content_State)
	child := props.child

	if !frame_state.active && !cfg.force_mount {
		child = nil
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
			event = tabs_content_refresh_merged(resolved_props, &frame_state)
			config = frame_state.config
		}

		if skip_layout {
			return
		}

		can_interact := widget_can_interact(handlers, &frame_state)
		widget_register_tab_order(key, config.tabbable, can_interact)
		widget_children(
			child,
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

	if !widget_prepare_draw(handlers, layout_id, &frame_state) {
		return
	}

	frame_state.is_focused = widget_is_focused(key)
	frame_state.active = tabs_content_is_active(cfg.value)
	rect := o.ui_layout_rect(layout_id)

	if !frame_state.active && !cfg.force_mount {
		return
	}

	if !frame_state.active {
		child = nil
	} else {
		child = props.child
	}

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
		event = tabs_content_refresh_merged(resolved_props, &frame_state)
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

	widget_draw_box_background(layout_id, rect, background, radius)
	widget_children(
		child,
		layout_id,
		config,
		frame_state,
		key,
		cfg,
		props.on_scroll,
		frame_state.is_hovered,
	)
	widget_draw_box_border(layout_id, rect, radius, border, border_color)
	widget_dispatch_events(resolved_props, &frame_state, handlers, event, key, was_focused)
}

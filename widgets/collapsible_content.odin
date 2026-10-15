package oni_widgets

import o ".."
import set "../set"

/*
Collapsible content configuration.

`force_mount` keeps closed panels in the tree with `HIDDEN` instead of removing
them from layout (`visibility = NONE`).
*/
Collapsible_Content_Config :: struct {
	using _:     o.Widget_Config,
	force_mount: bool,
}

/*
Collapsible content per-frame state.

`open` mirrors the parent `Collapsible` open flag.
*/
Collapsible_Content_State :: struct {
	using frame_state: o.Widget_Frame_State,
	config:            o.Resolved_Widget_Config,
	open:              bool,
}

/*
Collapsible content event snapshot.
*/
Collapsible_Content_Event :: o.Widget_Event(Collapsible_Content_State)

/*
Collapsible content props: in-flow panel shown while the parent root is open.

Closed panels use `visibility = NONE` (removed from layout) unless
`config.force_mount` keeps them in the tree with `HIDDEN`. Outside a
`Collapsible` root the panel stays inert and hidden.
*/
Collapsible_Content_Props :: struct {
	config:                       Collapsible_Content_Config,
	child:                        proc(frame_state: Collapsible_Content_State),
	unmount:                      bool,
	can_interactive_during_mount: bool,
	on_mount:                     proc(frame_state: Collapsible_Content_State) -> o.Mount,
	on_unmount:                   proc(frame_state: Collapsible_Content_State) -> o.Mount,
	on_scroll:                    proc(scroll_x, scroll_y: f32),
	on_focus:                     proc(event: Collapsible_Content_Event),
	on_blur:                      proc(event: Collapsible_Content_Event),
	on_mouse_enter:               proc(event: Collapsible_Content_Event),
	on_mouse_leave:               proc(event: Collapsible_Content_Event),
	on_mouse_pressed:             proc(event: Collapsible_Content_Event),
	on_mouse_down:                proc(event: Collapsible_Content_Event),
	on_mouse_released:            proc(event: Collapsible_Content_Event),
	on_mouse_move:                proc(event: Collapsible_Content_Event),
	on_click:                     proc(event: Collapsible_Content_Event),
	on_contextmenu:               proc(event: Collapsible_Content_Event),
	on_key_pressed:               proc(event: Collapsible_Content_Event),
	on_key_down:                  proc(event: Collapsible_Content_Event),
	on_key_released:              proc(event: Collapsible_Content_Event),
}

@(private)
collapsible_content_theme_base :: proc(
	frame_state: ^Collapsible_Content_State,
) -> Collapsible_Content_Config {
	visibility: o.Visibility = .VISIBLE

	if !frame_state.open {
		visibility = .NONE
	}

	return Collapsible_Content_Config {
		kind = .COLLAPSIBLE_CONTENT,
		tabbable = set.Tabbable(false),
		direction = set.Direction(.VERTICAL),
		justify = set.Justify(o.Justify_Pos{x = .START, y = .START}),
		visibility = set.Visibility(visibility),
	}
}

@(private)
collapsible_content_refresh_merged :: proc(
	props: Collapsible_Content_Props,
	frame_state: ^Collapsible_Content_State,
) -> Collapsible_Content_Event {
	event := widget_event(frame_state^)
	base := collapsible_content_theme_base(frame_state)

	if !frame_state.open && props.config.force_mount {
		base.visibility = set.Visibility(.HIDDEN)
	}

	frame_state.config = o.resolve_widget_config(base, props.config, frame_state, event)

	return widget_event(frame_state^)
}

@(private)
collapsible_content_is_open :: proc() -> bool {
	if !collapsible_ctx_ok() {
		return false
	}

	return collapsible_ctx_top().open
}

/*
Renders the in-flow panel inside a `Collapsible` root.

Only lays out and draws children while open, unless `force_mount` keeps the
closed panel in the tree as `HIDDEN`.
*/
Collapsible_Content :: proc(props: Collapsible_Content_Props) {
	cfg := props.config
	key := o.element_key(cfg.id)
	layout_label := cfg.id != "" ? cfg.id : key
	layout_id := o.ui_id(layout_label)
	was_focused := widget_is_focused(key)
	open := collapsible_content_is_open()

	frame_state := Collapsible_Content_State {
		is_disabled = o.cfg_style_bool(cfg.disabled),
		is_focused  = was_focused,
		open        = open,
	}

	resolved_props := props
	resolved_props.config = cfg
	event := collapsible_content_refresh_merged(resolved_props, &frame_state)
	style_fp := widget_style_interaction_fp(&frame_state)
	config := frame_state.config
	handlers := widget_lifecycle_handlers(resolved_props, Collapsible_Content_State)
	child := props.child

	if !frame_state.open && !cfg.force_mount {
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
			event = collapsible_content_refresh_merged(resolved_props, &frame_state)
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
	frame_state.open = collapsible_content_is_open()
	rect := o.ui_layout_rect(layout_id)

	if !frame_state.open && !cfg.force_mount {
		return
	}

	if !frame_state.open {
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
		event = collapsible_content_refresh_merged(resolved_props, &frame_state)
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

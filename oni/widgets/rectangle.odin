package widgets

import o ".."

/*
Rectangle widget configuration extending Widget_Config.
*/
Rectangle_Config :: o.Widget_Config

/*
Rectangle widget per-frame interaction frame_state merged with its fully resolved style config.
*/
Rectangle_State :: o.Widget_Merged_State(o.Widget_Frame_State, o.Resolved_Widget_Config)

/*
Rectangle widget event snapshot with frame_state and optional input metadata.
*/
Rectangle_Event :: o.Widget_Event(Rectangle_State)

/*
Rectangle widget props: config, child callback, and input event handlers.
*/
Rectangle_Props :: struct {
	config:                       Rectangle_Config,
	child:                        proc(frame_state: Rectangle_State),
	unmount:                      bool,
	can_interactive_during_mount: bool,
	on_mount:                     proc(frame_state: Rectangle_State) -> o.Mount,
	on_unmount:                   proc(frame_state: Rectangle_State) -> o.Mount,
	on_focus:                     proc(event: Rectangle_Event),
	on_blur:                      proc(event: Rectangle_Event),
	on_mouse_enter:               proc(event: Rectangle_Event),
	on_mouse_leave:               proc(event: Rectangle_Event),
	on_mouse_pressed:             proc(event: Rectangle_Event),
	on_mouse_down:                proc(event: Rectangle_Event),
	on_mouse_released:            proc(event: Rectangle_Event),
	on_mouse_move:                proc(event: Rectangle_Event),
	on_click:                     proc(event: Rectangle_Event),
	on_contextmenu:               proc(event: Rectangle_Event),
	on_key_pressed:               proc(event: Rectangle_Event),
	on_key_down:                  proc(event: Rectangle_Event),
	on_key_released:              proc(event: Rectangle_Event),
}

/*
Returns the default rectangle theme config, muted when the widget is disabled.
*/
rect_theme_base :: proc(frame_state: ^Rectangle_State) -> Rectangle_Config {
	color := o.Color.FOREGROUND

	if frame_state.is_disabled {
		color = o.Color.MUTED
	}

	return Rectangle_Config{kind = .RECT}
}

/*
Renders a styled rectangle container with full pointer and keyboard interaction.

Runs layout on the layout pass and draws chrome plus children on the draw pass.
*/
Rectangle :: proc(props: Rectangle_Props) {
	cfg := props.config
	key := o.element_key(cfg.id)

	was_focused := widget_is_focused(key)

	frame_state := Rectangle_State {
		is_disabled = cfg.disabled.mode == .Value && cfg.disabled.value,
		is_focused  = was_focused,
	}

	event := widget_refresh_merged(props, &frame_state, rect_theme_base)
	config := frame_state.config
	child := props.child
	handlers := widget_lifecycle_handlers(props, Rectangle_State)
	should_auto_focus := widget_should_auto_focus(config, key)

	layout_label := cfg.id != "" ? cfg.id : key
	layout_id := o.ui_id(layout_label)
	layout_rect := o.ui_layout_rect(layout_id)
	rect := layout_rect

	if o.ui_pass() == .Layout {
		skip_layout, ran_unmount := widget_run_layout_lifecycle(
			handlers,
			layout_id,
			cfg.id != "",
			&frame_state,
		)

		if ran_unmount {
			event = widget_refresh_merged(props, &frame_state, rect_theme_base)
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
			o.Children(child, layout_id, config, frame_state)
		}

		return
	}

	if !widget_prepare_draw(handlers, layout_id, &frame_state) do return

	frame_state.is_focused = widget_is_focused(key)

	got_focus, lost_focus := widget_handle_interaction(
		props,
		&frame_state,
		handlers,
		key,
		was_focused,
		config.tabbable,
		rect,
		config,
	)

	event = widget_refresh_merged(props, &frame_state, rect_theme_base)
	config = frame_state.config

	if widget_can_interact(handlers, &frame_state) {
		if widget_got_tab_focus(key) && props.on_focus != nil {
			props.on_focus(event)
		}

		if widget_lost_tab_focus(key) && props.on_blur != nil {
			props.on_blur(event)
		}
	}

	widget_dispatch_events(props, &frame_state, handlers, event, key, got_focus, lost_focus)

	if should_auto_focus &&
	   !was_focused &&
	   props.on_focus != nil &&
	   widget_can_interact(handlers, &frame_state) {
		props.on_focus(event)
	}

	draw_widget_rectangle(
		{
			frame_state = &frame_state,
			event = event,
			rect = rect,
			child = child,
			layout_id = layout_id,
		},
	)
}


@(private)
Draw_Widget_Rectangle :: struct {
	frame_state: ^Rectangle_State,
	event:       Rectangle_Event,
	rect:        o.Rect,
	child:       proc(frame_state: Rectangle_State),
	layout_id:   o.UI_Id,
}

@(private)
draw_widget_rectangle :: proc(props: Draw_Widget_Rectangle) {
	child := props.child
	event := props.event
	frame_state := props.frame_state
	layout_id := props.layout_id
	rect := props.rect

	config := frame_state.config

	background: o.RGBA
	if resolved_background, background_ok := o.to_rgba(config.background, frame_state, event);
	   background_ok {
		background = resolved_background
	}

	border: o.Bd
	if resolved_border, border_ok := o.resolve_border(config.border, frame_state, event);
	   border_ok {
		border = resolved_border
	}

	border_color: o.RGBA
	if resolved_border_color, border_color_ok := o.to_rgba(
		config.border_color,
		frame_state,
		event,
	); border_color_ok {
		border_color = resolved_border_color
	}

	radius: o.Radius_corners
	if resolved_radius, ok := o.resolve_radius(config.radius, frame_state, event); ok {
		radius = resolved_radius
	}

	o.Draw_Rectangle(rect, background, radius, border, border_color)

	o.Children(child, layout_id, config, frame_state^)
}

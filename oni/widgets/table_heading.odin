package widgets

import oni ".."
import set "../set"

/*
Table widget configuration extending Widget_Config.
*/
Table_Heading_Config :: oni.Widget_Config

/*
Table widget per-frame frame_state merged with its fully resolved style config.
*/
Table_Heading_State :: oni.Widget_Merged_State(oni.Widget_Frame_State, oni.Resolved_Widget_Config)

/*
Table widget event snapshot with frame_state and optional input metadata.
*/
Table_Heading_Event :: oni.Widget_Event(Table_Heading_State)


/*
Table widget props: config overrides, child callback, and input event handlers.
*/
Table_Heading_Props :: struct {
	config:                       Table_Heading_Config,
	child:                        proc(frame_state: Table_Heading_State),
	unmount:                      bool,
	can_interactive_during_mount: bool,
	on_mount:                     proc(frame_state: Table_Heading_State) -> oni.Mount,
	on_unmount:                   proc(frame_state: Table_Heading_State) -> oni.Mount,
	on_focus:                     proc(event: Table_Heading_Event),
	on_blur:                      proc(event: Table_Heading_Event),
	on_mouse_enter:               proc(event: Table_Heading_Event),
	on_mouse_leave:               proc(event: Table_Heading_Event),
	on_mouse_pressed:             proc(event: Table_Heading_Event),
	on_mouse_down:                proc(event: Table_Heading_Event),
	on_mouse_released:            proc(event: Table_Heading_Event),
	on_mouse_move:                proc(event: Table_Heading_Event),
	on_click:                     proc(event: Table_Heading_Event),
	on_contextmenu:               proc(event: Table_Heading_Event),
	on_key_pressed:               proc(event: Table_Heading_Event),
	on_key_down:                  proc(event: Table_Heading_Event),
	on_key_released:              proc(event: Table_Heading_Event),
}

/*
Returns the default table theme config, muted when the widget is disabled.
*/
@(private)
table_heading_theme_base :: proc(frame_state: ^Table_Heading_State) -> Table_Heading_Config {
	color := oni.Color.FOREGROUND

	if frame_state.is_disabled {
		color = oni.Color.MUTED
	}

	return Table_Heading_Config {
		kind = .TABLE_HEADING,
		font = set.Font(oni.theme.font_body),
		font_size = set.F32(oni.theme.font_body.size_px),
		color = set.Colors(color),
		line_height = set.F32(1),
		text_direction = set.Text_Direction(.LTR),
		space = set.Inherit_Space(),
		justify = set.Justify(oni.theme.justify),
		gap = set.Gap(oni.theme.gap),
	}
}

/*
Renders an interactive table with focus, pointer, and keyboard handling.

Runs layout on the layout pass and draws chrome plus children on the draw pass.
*/
Table_Heading :: proc(props: Table_Heading_Props) {
	cfg := props.config
	key := oni.element_key(cfg.id)
	layout_label := cfg.id != "" ? cfg.id : key
	layout_id := oni.ui_id(layout_label)

	was_focused := widget_is_focused(key)

	frame_state := Table_Heading_State {
		is_disabled = cfg.disabled.mode == .Value && cfg.disabled.value,
		is_focused  = was_focused,
	}

	event := widget_refresh_merged(props, &frame_state, table_heading_theme_base)
	config := frame_state.config
	child := props.child
	handlers := widget_lifecycle_handlers(props, Table_Heading_State)
	should_auto_focus := widget_should_auto_focus(config, key)

	if oni.ui_pass() == .Layout {
		skip_layout, ran_unmount := widget_run_layout_lifecycle(
			handlers,
			layout_id,
			cfg.id != "",
			&frame_state,
		)

		if ran_unmount {
			event = widget_refresh_merged(props, &frame_state, table_heading_theme_base)
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
			oni.Children(child, layout_id, config, frame_state)
		}

		return
	}

	if !widget_prepare_draw(handlers, layout_id, &frame_state) do return

	frame_state.is_focused = widget_is_focused(key)

	layout_rect := oni.ui_layout_rect(layout_id)
	rect := widget_resolve_hit_rect(layout_rect, config)

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

	event = widget_refresh_merged(props, &frame_state, table_heading_theme_base)
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

	background: oni.RGBA
	if resolved_background, background_ok := oni.to_rgba(config.background, &frame_state, event);
	   background_ok {
		background = resolved_background
	}

	border: oni.Bd
	if resolved_border, border_ok := oni.resolve_border(config.border, &frame_state, event);
	   border_ok {
		border = resolved_border
	}

	border_color: oni.RGBA
	if resolved_border_color, border_color_ok := oni.to_rgba(
		config.border_color,
		&frame_state,
		event,
	); border_color_ok {
		border_color = resolved_border_color
	}

	radius: oni.Radius_corners
	if resolved_radius, ok := oni.resolve_radius(config.radius, &frame_state, event); ok {
		radius = resolved_radius
	}

	oni.Draw_Rectangle(rect, background, radius, border, border_color)

	oni.Children(child, layout_id, config, frame_state)
}

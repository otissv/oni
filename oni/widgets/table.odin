package widgets

import o ".."
import set "../set"

/*
Table widget configuration extending Widget_Config.
*/
Table_Config :: struct {
	using _:         o.Widget_Config,
	border_collapse: o.Cfg(o.Border_Collapse),
}

/*
Table widget per-frame frame_state merged with its fully resolved style config.
*/
Table_State :: o.Widget_Merged_State(o.Widget_Frame_State, o.Resolved_Table_Config)

/*
Table widget event snapshot with frame_state and optional input metadata.
*/
Table_Event :: o.Widget_Event(Table_State)


/*
Table widget props: config overrides, child callback, and input event handlers.
*/
Table_Props :: struct {
	config:                       Table_Config,
	child:                        proc(frame_state: Table_State),
	unmount:                      bool,
	can_interactive_during_mount: bool,
	on_mount:                     proc(frame_state: Table_State) -> o.Mount,
	on_unmount:                   proc(frame_state: Table_State) -> o.Mount,
	on_focus:                     proc(event: Table_Event),
	on_blur:                      proc(event: Table_Event),
	on_mouse_enter:               proc(event: Table_Event),
	on_mouse_leave:               proc(event: Table_Event),
	on_mouse_pressed:             proc(event: Table_Event),
	on_mouse_down:                proc(event: Table_Event),
	on_mouse_released:            proc(event: Table_Event),
	on_mouse_move:                proc(event: Table_Event),
	on_click:                     proc(event: Table_Event),
	on_contextmenu:               proc(event: Table_Event),
	on_key_pressed:               proc(event: Table_Event),
	on_key_down:                  proc(event: Table_Event),
	on_key_released:              proc(event: Table_Event),
}

@(private)
table_theme_base :: proc(frame_state: ^Table_State) -> Table_Config {
	color := o.Color.FOREGROUND

	if frame_state.is_disabled {
		color = o.Color.MUTED
	}

	return Table_Config{kind = .TABLE, direction = set.Direction(.VERTICAL)}
}

@(private)
table_config :: proc(props: Table_Props, frame_state: ^Table_State) -> o.Resolved_Table_Config {
	event := widget_event(frame_state^)
	base := table_theme_base(frame_state)
	override := props.config
	widget := o.resolve_widget_config(base, override, frame_state, event)

	border_collapse := o.Border_Collapse.COLLAPSE

	if override.border_collapse.mode == .Value {
		border_collapse = override.border_collapse.value
	}

	if base.border_collapse.mode == .Value {
		border_collapse = base.border_collapse.value
	}

	return {widget = widget, border_collapse = border_collapse}
}

@(private)
table_refresh_merged :: proc(props: Table_Props, frame_state: ^Table_State) -> Table_Event {
	frame_state.config = table_config(props, frame_state)
	return widget_event(frame_state^)
}

/*
Renders an interactive table with focus, pointer, and keyboard handling.

Runs layout on the layout pass and draws chrome plus children on the draw pass.
*/
Table :: proc(props: Table_Props) {
	cfg := props.config
	key := o.element_key(cfg.id)
	layout_label := cfg.id != "" ? cfg.id : key
	layout_id := o.ui_id(layout_label)

	was_focused := widget_is_focused(key)

	frame_state := Table_State {
		is_disabled = cfg.disabled.mode == .Value && cfg.disabled.value,
		is_focused  = was_focused,
	}

	event := table_refresh_merged(props, &frame_state)
	config := frame_state.config
	child := props.child
	handlers := widget_lifecycle_handlers(props, Table_State)
	should_auto_focus := widget_should_auto_focus(config.widget, key)

	if o.ui_pass() == .Layout {
		skip_layout, ran_unmount := widget_run_layout_lifecycle(
			handlers,
			layout_id,
			cfg.id != "",
			&frame_state,
		)

		if ran_unmount {
			event = table_refresh_merged(props, &frame_state)
			config = frame_state.config
			should_auto_focus = widget_should_auto_focus(config.widget, key)
		}

		if !skip_layout {
			can_interact := widget_can_interact(handlers, &frame_state)
			if can_interact && should_auto_focus {
				widget_apply_auto_focus(key, true)
				frame_state.is_focused = true
			}
			widget_register_tab_order(key, config.widget.tabbable, can_interact)
			o.layout_table_register_border_collapse(layout_id, config.border_collapse)
			o.Children(child, layout_id, config.widget, frame_state)
		}

		return
	}

	if !widget_prepare_draw(handlers, layout_id, &frame_state) do return

	frame_state.is_focused = widget_is_focused(key)

	layout_rect := o.ui_layout_rect(layout_id)
	rect := widget_resolve_hit_rect(layout_rect, config.widget)

	got_focus, lost_focus := widget_handle_interaction(
		props,
		&frame_state,
		handlers,
		key,
		was_focused,
		config.widget.tabbable,
		rect,
		config.widget,
	)

	event = table_refresh_merged(props, &frame_state)
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

	table_widget_draw_chrome(layout_id, .TABLE, rect, config.widget, &frame_state, event)

	o.Children(child, layout_id, config.widget, frame_state)
}

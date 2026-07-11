package widgets

import o ".."
import set "../set"


/*
Text widget configuration extending Widget_Config with display text.
*/
Text_Config :: struct {
	using _: o.Widget_Config,
	text:    string,
}

/*
Text widget per-frame interaction frame_state for a text widget.
*/
Text_State :: struct {
	using _: o.Widget_Frame_State,
}

/*
Text widget per-frame frame_state merged with resolved style and display string.
*/
Text_Merged_State :: struct {
	using frame_state: Text_State,
	style:             o.Resolved_Widget_Config,
	text:              string,
}

/*
Text widget event snapshot with frame_state and optional input metadata.
*/
Text_Event :: o.Widget_Event(Text_Merged_State)

/*
Text widget props: config fields inlined plus input event handlers.
*/
Text_Props :: struct {
	config:                       Text_Config,
	unmount:                      bool,
	can_interactive_during_mount: bool,
	on_mount:                     proc(frame_state: Text_Merged_State) -> o.Mount,
	on_unmount:                   proc(frame_state: Text_Merged_State) -> o.Mount,
	on_focus:                     proc(event: Text_Event),
	on_blur:                      proc(event: Text_Event),
	on_mouse_enter:               proc(event: Text_Event),
	on_mouse_leave:               proc(event: Text_Event),
	on_mouse_pressed:             proc(event: Text_Event),
	on_mouse_down:                proc(event: Text_Event),
	on_mouse_released:            proc(event: Text_Event),
	on_mouse_move:                proc(event: Text_Event),
	on_click:                     proc(event: Text_Event),
	on_contextmenu:               proc(event: Text_Event),
	on_key_pressed:               proc(event: Text_Event),
	on_key_down:                  proc(event: Text_Event),
	on_key_released:              proc(event: Text_Event),
}

/*
Returns the default text widget theme config, muted when the widget is disabled.
*/
@(private)
text_widget_decl :: proc(frame_state: ^Text_Merged_State) -> Text_Config {
	color := o.Color.FOREGROUND

	if frame_state.is_disabled {
		color = o.Color.MUTED
	}

	return Text_Config{kind = .TEXT, line_height = set.F32(1.5)}
}

/*
Refreshes merged style and text on frame_state and returns a fresh event snapshot.
*/
@(private)
text_refresh_merged :: proc(props: Text_Props, frame_state: ^Text_Merged_State) -> Text_Event {
	event := widget_event(frame_state^)
	base := text_widget_decl(frame_state)
	override := props.config
	frame_state.style = o.resolve_widget_config(base, override, frame_state, event)
	frame_state.text = override.text

	return widget_event(frame_state^)
}

/*
Lays out and draws text. Layout owns wrap, size, and line positions; draw paints them.
*/
Text :: proc(props: Text_Props) -> o.Vec2 {
	config := props.config
	key := o.element_key(config.id)
	layout_label := config.id != "" ? config.id : key
	layout_id := o.ui_id(layout_label)

	was_focused := widget_is_focused(key)

	frame_state := Text_Merged_State {
		is_disabled = config.disabled.mode == .Value && config.disabled.value,
		is_focused  = was_focused,
	}

	event := text_refresh_merged(props, &frame_state)
	style := frame_state.style
	handlers := widget_lifecycle_handlers(props, Text_Merged_State)
	should_auto_focus := widget_should_auto_focus(style, key)

	if o.ui_pass() == .Layout {
		skip_layout, ran_unmount := widget_run_layout_lifecycle(
			handlers,
			layout_id,
			config.id != "",
			&frame_state,
		)

		if ran_unmount {
			event = text_refresh_merged(props, &frame_state)
			style = frame_state.style
			should_auto_focus = widget_should_auto_focus(style, key)
		}

		if skip_layout do return {}

		can_interact := widget_can_interact(handlers, &frame_state)

		if can_interact && should_auto_focus {
			widget_apply_auto_focus(key, true)
			frame_state.is_focused = true
		}

		widget_register_tab_order(key, style.tabbable, can_interact)

		node := o.layout_push_node(layout_id, style)
		o.layout_set_measure_text(node, frame_state.text, style.max_w)
		o.layout_pop_node()

		return {}
	}

	if !widget_prepare_draw(handlers, layout_id, &frame_state) do return {}

	frame_state.is_focused = widget_is_focused(key)

	layout_rect := o.ui_layout_rect(layout_id)

	got_focus, lost_focus := widget_handle_interaction(
		props,
		&frame_state,
		handlers,
		key,
		was_focused,
		style.tabbable,
		layout_rect,
		style,
	)

	event = text_refresh_merged(props, &frame_state)
	style = frame_state.style

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

	rgbaColor, color_ok := o.to_rgba(style.color, &frame_state, event)
	if !color_ok do return {}

	laid := o.layout_text_result(layout_id)
	if laid == nil do return {}

	deco_color := rgbaColor
	#partial switch c in style.text_decoration_color {
	case o.Color:
		if c != .INHERIT {
			if resolved, ok := o.to_rgba(style.text_decoration_color, &frame_state, event); ok {
				deco_color = resolved
			}
		}
	case:
		if resolved, ok := o.to_rgba(style.text_decoration_color, &frame_state, event); ok {
			deco_color = resolved
		}
	}

	return o.font_draw_layout_text(laid, rgbaColor, deco_color)
}

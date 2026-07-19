package oni_widgets

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

@(private)
text_refresh_merged_if_interaction_changed :: proc(
	props: Text_Props,
	frame_state: ^Text_Merged_State,
	prev_fp: u8,
) -> (
	event: Text_Event,
	fp: u8,
) {
	fp = widget_style_interaction_fp(frame_state)
	if fp == prev_fp {
		return widget_event(frame_state^), fp
	}
	return text_refresh_merged(props, frame_state), fp
}

/*
Lays out and draws text. Layout owns wrap, size, and line positions; draw paints them.
*/
Text :: proc(props: Text_Props) -> o.Vec2 {
	config := props.config
	key := o.element_key(config.id)
	was_focused := widget_is_focused(key)

	frame_state := Text_Merged_State {
		is_disabled = o.cfg_style_bool(config.disabled),
		is_focused  = was_focused,
	}

	return text_widget_core(
		props,
		&frame_state,
		{
			kind = .TEXT,
			measure_text = props.config.text,
			layout_runs = nil,
			rich = false,
		},
		text_refresh_merged,
		text_refresh_merged_if_interaction_changed,
	)
}

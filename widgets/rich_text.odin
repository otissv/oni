package oni_widgets

import o ".."
import set "../set"


/*
RichText widget configuration extending Widget_Config with tagged display text.
*/
Rich_Text_Config :: struct {
	using _: o.Widget_Config,
	text:    string,
}

/*
RichText widget per-frame interaction frame_state.
*/
Rich_Text_State :: struct {
	using _: o.Widget_Frame_State,
}

/*
RichText widget per-frame frame_state merged with resolved style and parsed runs.
*/
Rich_Text_Merged_State :: struct {
	using frame_state: Rich_Text_State,
	style:             o.Resolved_Widget_Config,
	text:              string,
	plain:             string,
	runs:              []o.Text_Run,
	layout_runs:       []o.Layout_Text_Run,
	diagnostics:       []o.Text_Tag_Diagnostic,
}

/*
RichText widget event snapshot with frame_state and optional input metadata.
*/
Rich_Text_Event :: o.Widget_Event(Rich_Text_Merged_State)

/*
RichText widget props: config fields inlined plus input event handlers.
*/
Rich_Text_Props :: struct {
	config:                       Rich_Text_Config,
	unmount:                      bool,
	can_interactive_during_mount: bool,
	on_mount:                     proc(frame_state: Rich_Text_Merged_State) -> o.Mount,
	on_unmount:                   proc(frame_state: Rich_Text_Merged_State) -> o.Mount,
	on_focus:                     proc(event: Rich_Text_Event),
	on_blur:                      proc(event: Rich_Text_Event),
	on_mouse_enter:               proc(event: Rich_Text_Event),
	on_mouse_leave:               proc(event: Rich_Text_Event),
	on_mouse_pressed:             proc(event: Rich_Text_Event),
	on_mouse_down:                proc(event: Rich_Text_Event),
	on_mouse_released:            proc(event: Rich_Text_Event),
	on_mouse_move:                proc(event: Rich_Text_Event),
	on_click:                     proc(event: Rich_Text_Event),
	on_contextmenu:               proc(event: Rich_Text_Event),
	on_key_pressed:               proc(event: Rich_Text_Event),
	on_key_down:                  proc(event: Rich_Text_Event),
	on_key_released:              proc(event: Rich_Text_Event),
}

/*
Returns the default rich text widget theme config.
*/
@(private)
rich_text_widget_decl :: proc(frame_state: ^Rich_Text_Merged_State) -> Rich_Text_Config {
	_ = frame_state

	return Rich_Text_Config{kind = .RICH_TEXT, line_height = set.F32(1.5)}
}

/*
Refreshes merged style, parsed runs, and layout ranges on frame_state.
*/
@(private)
rich_text_refresh_merged :: proc(
	props: Rich_Text_Props,
	frame_state: ^Rich_Text_Merged_State,
) -> Rich_Text_Event {
	event := widget_event(frame_state^)
	base := rich_text_widget_decl(frame_state)
	override := props.config
	frame_state.style = o.resolve_widget_config(base, override, frame_state, event)
	frame_state.text = override.text

	parsed := o.text_tags_parse(override.text, context.temp_allocator)
	frame_state.plain = parsed.plain
	frame_state.runs = parsed.runs
	frame_state.layout_runs = parsed.layout_runs
	frame_state.diagnostics = parsed.diagnostics

	for diagnostic in parsed.diagnostics {
		id_label := override.id != "" ? override.id : "RichText"
		o.error_reportf("RichText %q: %s", id_label, diagnostic.message)
	}

	if len(parsed.diagnostics) > 0 {
		frame_state.style.border = f32(1)
		frame_state.style.border_color = o.Color.DESTRUCTIVE
	}

	return widget_event(frame_state^)
}

@(private)
rich_text_refresh_merged_if_interaction_changed :: proc(
	props: Rich_Text_Props,
	frame_state: ^Rich_Text_Merged_State,
	prev_fp: u8,
) -> (
	event: Rich_Text_Event,
	fp: u8,
) {
	fp = widget_style_interaction_fp(frame_state)
	if fp == prev_fp {
		return widget_event(frame_state^), fp
	}
	return rich_text_refresh_merged(props, frame_state), fp
}

/*
Lays out and draws tagged rich text using the shared text widget core.
*/
RichText :: proc(props: Rich_Text_Props) -> o.Vec2 {
	config := props.config
	key := o.element_key(config.id)
	was_focused := widget_is_focused(key)

	frame_state := Rich_Text_Merged_State {
		is_disabled = o.cfg_style_bool(config.disabled),
		is_focused  = was_focused,
	}

	rich_text_refresh_merged(props, &frame_state)

	return text_widget_core(
		props,
		&frame_state,
		{
			kind = .RICH_TEXT,
			measure_text = frame_state.plain,
			layout_runs = frame_state.layout_runs,
			rich = len(frame_state.layout_runs) > 0,
		},
		rich_text_refresh_merged,
		rich_text_refresh_merged_if_interaction_changed,
	)
}

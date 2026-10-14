package oni_widgets

import o ".."
import set "../set"
import "core:mem"
import "core:strings"

/*
Date picker input configuration (editable formatted field + calendar trigger).
*/
Date_Picker_Input_Config :: struct {
	using _:     o.Widget_Config,
	placeholder: string,
	format:      string,
}

/*
Date picker input per-frame state with draft text.
*/
Date_Picker_Input_State :: struct {
	using frame_state: o.Widget_Frame_State,
	config:            o.Resolved_Widget_Config,
	text:              string,
	placeholder:       string,
	has_value:         bool,
}

/*
Date picker input event snapshot.
*/
Date_Picker_Input_Event :: o.Widget_Event(Date_Picker_Input_State)

/*
Date picker input props: text field for formatted dates that also opens the calendar.

Must be used inside `Date_Picker`. Acts as the popover anchor (like Trigger).
Typing a valid date for `config.format` updates the selection via `on_select`.
Focusing or clicking opens the calendar popover.
*/
Date_Picker_Input_Props :: struct {
	config:                       Date_Picker_Input_Config,
	unmount:                      bool,
	can_interactive_during_mount: bool,
	on_mount:                     proc(frame_state: Date_Picker_Input_State) -> o.Mount,
	on_unmount:                   proc(frame_state: Date_Picker_Input_State) -> o.Mount,
	on_change:                    proc(event: Date_Picker_Input_Event, text: string),
	on_submit:                    proc(event: Date_Picker_Input_Event),
	on_focus:                     proc(event: Date_Picker_Input_Event),
	on_blur:                      proc(event: Date_Picker_Input_Event),
	on_mouse_enter:               proc(event: Date_Picker_Input_Event),
	on_mouse_leave:               proc(event: Date_Picker_Input_Event),
	on_mouse_pressed:             proc(event: Date_Picker_Input_Event),
	on_mouse_down:                proc(event: Date_Picker_Input_Event),
	on_mouse_released:            proc(event: Date_Picker_Input_Event),
	on_mouse_move:                proc(event: Date_Picker_Input_Event),
	on_click:                     proc(event: Date_Picker_Input_Event),
	on_contextmenu:               proc(event: Date_Picker_Input_Event),
	on_key_pressed:               proc(event: Date_Picker_Input_Event),
	on_key_down:                  proc(event: Date_Picker_Input_Event),
	on_key_released:              proc(event: Date_Picker_Input_Event),
}

@(private)
date_picker_input_frame_props: Date_Picker_Input_Props

@(private)
date_picker_input_theme_base :: proc(
	frame_state: ^Date_Picker_Input_State,
) -> Date_Picker_Input_Config {
	_ = frame_state

	return Date_Picker_Input_Config{kind = .DATE_PICKER_INPUT, min_w = set.F32(f32(200))}
}

@(private)
date_picker_input_make_state :: proc(text: string) -> Date_Picker_Input_State {
	return Date_Picker_Input_State{text = text}
}

@(private)
date_picker_input_resolve_text :: proc(
	props: Date_Picker_Input_Props,
	picker_key: string,
) -> (
	text: string,
	has_value: bool,
) {
	_ = props

	if !date_picker_ctx_ok() {
		return "", false
	}

	ctx := date_picker_ctx_top()
	sel := date_picker_selection_from_ctx(ctx)
	has_value = date_picker_selection_has_value(sel)
	rt := date_picker_runtime_ensure(picker_key)
	format := date_picker_input_runtime_format(picker_key)

	if rt != nil && rt.input_editing {
		return rt.input_text, has_value
	}

	if !has_value {
		if rt != nil {
			date_picker_runtime_set_string(&rt.input_text, "")
		}

		return "", false
	}

	formatted: string

	switch date_picker_effective_mode(ctx.mode) {
	case .SINGLE:
		formatted = date_picker_input_format_date(sel.single, format)
	case .RANGE, .MULTIPLE, .NONE:
		formatted = Date_Picker_Format_Selection(sel, context.temp_allocator)
	}

	if rt != nil {
		date_picker_runtime_set_string(&rt.input_text, formatted)
	}

	return formatted, true
}

@(private)
date_picker_input_commit_text :: proc(text: string) -> bool {
	if !date_picker_ctx_ok() {
		return false
	}

	ctx := date_picker_ctx_top()
	mode := date_picker_effective_mode(ctx.mode)

	if mode != .SINGLE {
		return false
	}

	format := date_picker_input_runtime_format(ctx.picker_key)
	trimmed := strings.trim_space(text)

	if trimmed == "" {
		if ctx.required {
			return false
		}

		date_picker_apply_selection({mode = .SINGLE, has_single = false})

		return true
	}

	date, ok := date_picker_input_parse_date(trimmed, format)

	if !ok {
		return false
	}

	date_picker_apply_selection({mode = .SINGLE, single = date, has_single = true})

	return true
}

@(private)
date_picker_input_on_text_change :: proc(event: Text_Input_Event, text: string) {
	_ = event
	defer delete(text)

	if !date_picker_ctx_ok() {
		return
	}

	ctx := date_picker_ctx_top()
	rt := date_picker_runtime_ensure(ctx.picker_key)
	format := date_picker_input_runtime_format(ctx.picker_key)
	sanitized := date_picker_input_sanitize_text(text, format)

	if rt != nil {
		rt.input_editing = true
		date_picker_runtime_set_string(&rt.input_text, sanitized)
	}

	if date_picker_effective_mode(ctx.mode) == .SINGLE {
		if date, ok := date_picker_input_parse_date(sanitized, format); ok {
			date_picker_apply_selection({mode = .SINGLE, single = date, has_single = true})

			if rt != nil {
				rt.input_editing = true
				date_picker_runtime_set_string(&rt.input_text, sanitized)
			}
		}
	}

	if date_picker_input_frame_props.on_change != nil {
		date_picker_input_frame_props.on_change(
			widget_event(date_picker_input_make_state(sanitized)),
			sanitized,
		)
	}
}

@(private)
date_picker_input_on_text_submit :: proc(event: Text_Input_Event) {
	_ = event

	if !date_picker_ctx_ok() {
		return
	}

	ctx := date_picker_ctx_top()
	rt := date_picker_runtime_ensure(ctx.picker_key)
	text := rt != nil ? rt.input_text : ""
	_ = date_picker_input_commit_text(text)

	if rt != nil {
		rt.input_editing = false
	}

	if date_picker_input_frame_props.on_submit != nil {
		date_picker_input_frame_props.on_submit(widget_event(date_picker_input_make_state(text)))
	}
}

@(private)
date_picker_input_on_text_focus :: proc(event: Text_Input_Event) {
	if !date_picker_ctx_ok() {
		return
	}

	ctx := date_picker_ctx_top()
	rt := date_picker_runtime_ensure(ctx.picker_key)

	if rt != nil {
		rt.input_editing = true
	}

	date_picker_set_open(true)
	date_picker_input_bridge_event(date_picker_input_frame_props.on_focus, event)
}

@(private)
date_picker_input_on_text_blur :: proc(event: Text_Input_Event) {
	if !date_picker_ctx_ok() {
		return
	}

	ctx := date_picker_ctx_top()
	rt := date_picker_runtime_ensure(ctx.picker_key)
	text := rt != nil ? rt.input_text : ""
	format := date_picker_input_runtime_format(ctx.picker_key)

	if !date_picker_input_commit_text(text) && rt != nil {
		sel := date_picker_selection_from_ctx(ctx)

		if date_picker_selection_has_value(sel) &&
		   date_picker_effective_mode(ctx.mode) == .SINGLE {
			date_picker_runtime_set_string(
				&rt.input_text,
				date_picker_input_format_date(sel.single, format),
			)
		}

	}

	if rt != nil {
		rt.input_editing = false
	}

	date_picker_input_bridge_event(date_picker_input_frame_props.on_blur, event)
}

@(private)
date_picker_input_on_text_click :: proc(event: Text_Input_Event) {
	date_picker_note_pointer()
	date_picker_set_open(true)
	date_picker_input_bridge_event(date_picker_input_frame_props.on_click, event)
}

@(private)
date_picker_input_on_text_mouse_enter :: proc(event: Text_Input_Event) {
	date_picker_note_pointer()
	date_picker_input_bridge_event(date_picker_input_frame_props.on_mouse_enter, event)
}

@(private)
date_picker_input_bridge_event :: proc(
	user: proc(event: Date_Picker_Input_Event),
	_: Text_Input_Event,
) {
	if user == nil {
		return
	}

	text := ""

	if date_picker_ctx_ok() {
		rt := date_picker_runtime_ensure(date_picker_ctx_top().picker_key)
		text = rt != nil ? rt.input_text : ""
	}

	user(widget_event(date_picker_input_make_state(text)))
}

@(private)
date_picker_input_on_mouse_leave :: proc(event: Text_Input_Event) {
	date_picker_input_bridge_event(date_picker_input_frame_props.on_mouse_leave, event)
}

@(private)
date_picker_input_on_mouse_pressed :: proc(event: Text_Input_Event) {
	date_picker_input_bridge_event(date_picker_input_frame_props.on_mouse_pressed, event)
}

@(private)
date_picker_input_on_mouse_down :: proc(event: Text_Input_Event) {
	date_picker_input_bridge_event(date_picker_input_frame_props.on_mouse_down, event)
}

@(private)
date_picker_input_on_mouse_released :: proc(event: Text_Input_Event) {
	date_picker_input_bridge_event(date_picker_input_frame_props.on_mouse_released, event)
}

@(private)
date_picker_input_on_mouse_move :: proc(event: Text_Input_Event) {
	date_picker_input_bridge_event(date_picker_input_frame_props.on_mouse_move, event)
}

@(private)
date_picker_input_on_contextmenu :: proc(event: Text_Input_Event) {
	date_picker_input_bridge_event(date_picker_input_frame_props.on_contextmenu, event)
}

@(private)
date_picker_input_on_key_pressed :: proc(event: Text_Input_Event) {
	date_picker_input_bridge_event(date_picker_input_frame_props.on_key_pressed, event)
}

@(private)
date_picker_input_on_key_down :: proc(event: Text_Input_Event) {
	date_picker_input_bridge_event(date_picker_input_frame_props.on_key_down, event)
}

@(private)
date_picker_input_on_key_released :: proc(event: Text_Input_Event) {
	date_picker_input_bridge_event(date_picker_input_frame_props.on_key_released, event)
}

@(private)
date_picker_input_bridge_text :: proc() -> string {
	if !date_picker_ctx_ok() {
		return ""
	}

	rt := date_picker_runtime_ensure(date_picker_ctx_top().picker_key)

	return rt != nil ? rt.input_text : ""
}

@(private)
date_picker_input_on_mount :: proc(frame_state: Text_Input_State) -> o.Mount {
	_ = frame_state

	if date_picker_input_frame_props.on_mount == nil {
		return .COMPLETED
	}

	return date_picker_input_frame_props.on_mount(
		date_picker_input_make_state(date_picker_input_bridge_text()),
	)
}

@(private)
date_picker_input_on_unmount :: proc(frame_state: Text_Input_State) -> o.Mount {
	_ = frame_state

	if date_picker_input_frame_props.on_unmount == nil {
		return .COMPLETED
	}

	return date_picker_input_frame_props.on_unmount(
		date_picker_input_make_state(date_picker_input_bridge_text()),
	)
}

@(private)
date_picker_input_text_config :: proc(
	cfg: Date_Picker_Input_Config,
	text: string,
	placeholder: string,
	disabled: bool,
) -> Text_Input_Config {
	src := cfg
	out: Text_Input_Config
	mem.copy(rawptr(&out), rawptr(&src), size_of(o.Widget_Config))
	out.kind = .DATE_PICKER_INPUT
	out.text = text
	out.placeholder = placeholder

	if disabled {
		out.disabled = set.Disabled(true)
	}

	if out.min_w.mode == .UNSET {
		out.min_w = set.F32(f32(200))
	}

	return out
}

/*
Renders an editable formatted date field that opens the parent Date_Picker calendar.

Must be used inside `Date_Picker`. Prefer this instead of Trigger when the control
should accept typed date values. Composes `Text_Input` — does not reimplement input chrome.
*/
Date_Picker_Input :: proc(props: Date_Picker_Input_Props) {
	date_picker_input_frame_props = props
	cfg := props.config
	key := o.element_key(cfg.id)
	layout_label := cfg.id != "" ? cfg.id : key
	layout_id := o.ui_id(layout_label)

	disabled := o.cfg_style_bool(cfg.disabled)
	picker_key := ""

	if date_picker_ctx_ok() {
		ctx := date_picker_ctx_top()
		picker_key = ctx.picker_key

		if ctx.disabled {
			disabled = true
		}
	}

	date_picker_input_sync_runtime_format(picker_key, cfg.format)
	format := date_picker_input_runtime_format(picker_key)

	placeholder := cfg.placeholder

	if placeholder == "" {
		placeholder = format.pattern != "" ? format.pattern : DATE_PICKER_INPUT_DEFAULT_FORMAT
	}

	text, _ := date_picker_input_resolve_text(props, picker_key)
	ti_cfg := date_picker_input_text_config(cfg, text, placeholder, disabled)

	if popover_ctx_ok() && o.ui_pass() == .Layout {
		popover_set_trigger(key, layout_id, {})
	}

	Text_Input(
		{
			config = ti_cfg,
			unmount = props.unmount,
			can_interactive_during_mount = props.can_interactive_during_mount,
			on_mount = props.on_mount != nil ? date_picker_input_on_mount : nil,
			on_unmount = props.on_unmount != nil ? date_picker_input_on_unmount : nil,
			on_change = date_picker_input_on_text_change,
			on_submit = date_picker_input_on_text_submit,
			on_focus = date_picker_input_on_text_focus,
			on_blur = date_picker_input_on_text_blur,
			on_click = date_picker_input_on_text_click,
			on_mouse_enter = date_picker_input_on_text_mouse_enter,
			on_mouse_leave = props.on_mouse_leave != nil ? date_picker_input_on_mouse_leave : nil,
			on_mouse_pressed = props.on_mouse_pressed != nil ? date_picker_input_on_mouse_pressed : nil,
			on_mouse_down = props.on_mouse_down != nil ? date_picker_input_on_mouse_down : nil,
			on_mouse_released = props.on_mouse_released != nil ? date_picker_input_on_mouse_released : nil,
			on_mouse_move = props.on_mouse_move != nil ? date_picker_input_on_mouse_move : nil,
			on_contextmenu = props.on_contextmenu != nil ? date_picker_input_on_contextmenu : nil,
			on_key_pressed = props.on_key_pressed != nil ? date_picker_input_on_key_pressed : nil,
			on_key_down = props.on_key_down != nil ? date_picker_input_on_key_down : nil,
			on_key_released = props.on_key_released != nil ? date_picker_input_on_key_released : nil,
		},
	)

	if popover_ctx_ok() && o.ui_pass() == .Draw {
		popover_set_trigger(key, layout_id, o.ui_layout_rect(layout_id))
	}
}

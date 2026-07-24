package oni

import "core:c"
import "core:strings"
import sdl "vendor:sdl3"

input_session_active_id: string
input_session_active_id_owned: bool

@(private)
input_release_session_id :: proc() {
	if input_session_active_id_owned {
		widget_release_key(input_session_active_id)
	}
	input_session_active_id = {}
	input_session_active_id_owned = false
}

/*
Returns whether an IME composition string is active.
*/
input_ime_active :: proc() -> bool {
	return state != nil && len(state.input.ime_text) > 0
}

/*
Assigns IME composition text, replacing any previous heap copy.

Empty text clears composition including cursor/length.
*/
input_set_ime_text :: proc(text: string) {
	if state == nil do return

	if len(state.input.ime_text) > 0 {
		delete(state.input.ime_text)
	}

	if len(text) == 0 {
		state.input.ime_text = {}
		state.input.ime_cursor = 0
		state.input.ime_length = 0

		return
	}

	state.input.ime_text = strings.clone(text)
}

/*
Clears IME composition state and asks SDL to dismiss the OS composition.
*/
input_clear_ime :: proc() {
	if state == nil do return

	if len(state.input.ime_text) > 0 {
		delete(state.input.ime_text)
	}

	state.input.ime_text = {}
	state.input.ime_cursor = 0
	state.input.ime_length = 0

	if state.window != nil {
		_ = sdl.ClearComposition(state.window)
	}
}

/*
Returns committed SDL text input for this frame as a temp-allocator string.
*/
input_take_text_input :: proc() -> string {
	if state == nil || len(state.input.text_input) == 0 do return {}

	result := string(state.input.text_input[:])
	clear(&state.input.text_input)

	return strings.clone(result, context.temp_allocator)
}

/*
Builds display plain text including in-progress IME composition at the caret.
*/
input_ime_preview :: proc(text: string, caret: int, ime: string) -> string {
	if len(ime) == 0 do return text

	clamped_caret := clamp(caret, 0, len(text))
	b := strings.builder_make(context.temp_allocator)
	strings.write_string(&b, text[:clamped_caret])
	strings.write_string(&b, ime)
	strings.write_string(&b, text[clamped_caret:])

	return strings.to_string(b)
}

/*
Starts or stops SDL text input based on focused text field state.

`cursor_x_offset` is the caret x offset relative to `caret_screen_rect.x` in
logical pixels (converted to window coordinates for SDL).
Clears IME when focus leaves a text field or moves between fields.
*/
input_sync_text_input_session :: proc(caret_screen_rect: Rect, cursor_x_offset: int = 0) {
	if state == nil do return

	active := shortcut_text_input_effective(w_ctx.focused_id)
	focused := w_ctx.focused_id

	if active && focused != input_session_active_id {
		if len(input_session_active_id) > 0 {
			input_clear_ime()
		}

		input_release_session_id()
		input_session_active_id = widget_retain_key(focused)
		input_session_active_id_owned = widget_key_is_owned(input_session_active_id)
	} else if !active {
		if len(input_session_active_id) > 0 || input_ime_active() {
			input_clear_ime()
		}

		input_release_session_id()
	}

	if state.window == nil do return

	if active {
		_ = sdl.StartTextInput(state.window)
		screen_rect := logical_to_screen(caret_screen_rect.x, caret_screen_rect.y, state.dpi)
		screen_w := (caret_screen_rect.w if caret_screen_rect.w > 0 else 1) * state.dpi.scale
		screen_h := (caret_screen_rect.h if caret_screen_rect.h > 0 else 16) * state.dpi.scale
		cursor_screen := f32(cursor_x_offset) * state.dpi.scale
		rect := sdl.Rect {
			x = i32(screen_rect.x),
			y = i32(screen_rect.y),
			w = i32(max(screen_w, 1)),
			h = i32(max(screen_h, 1)),
		}
		_ = sdl.SetTextInputArea(state.window, &rect, c.int(cursor_screen))
	} else {
		_ = sdl.StopTextInput(state.window)
	}
}

input_shutdown :: proc() {
	input_release_session_id()
	input_clear_ime()
}

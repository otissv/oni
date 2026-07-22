package oni

import "core:testing"

@(test)
input_ime_preview_inserts_composition :: proc(t: ^testing.T) {
	with_engine_env(
		t,
		proc(t: ^testing.T) {
			preview := input_ime_preview("abc", 1, "X")

			testing.expect_value(t, preview, "aXbc")
		},
	)
}

@(test)
input_set_and_clear_ime_frees_heap_copy :: proc(t: ^testing.T) {
	with_engine_env(
		t,
		proc(t: ^testing.T) {
			input_set_ime_text("compose")
			testing.expect_value(t, state.input.ime_text, "compose")

			input_clear_ime()
			testing.expect_value(t, len(state.input.ime_text), 0)
			testing.expect_value(t, state.input.ime_cursor, 0)
			testing.expect_value(t, state.input.ime_length, 0)
		},
	)
}

@(test)
input_take_text_input_drains_buffer :: proc(t: ^testing.T) {
	with_engine_env(
		t,
		proc(t: ^testing.T) {
			append(&state.input.text_input, 'a')
			append(&state.input.text_input, 'b')

			taken := input_take_text_input()

			testing.expect_value(t, taken, "ab")
			testing.expect_value(t, len(state.input.text_input), 0)
			testing.expect_value(t, len(input_take_text_input()), 0)
		},
	)
}

@(test)
input_shutdown_clears_ime :: proc(t: ^testing.T) {
	with_engine_env(
		t,
		proc(t: ^testing.T) {
			input_set_ime_text("ime")
			input_shutdown()
			testing.expect_value(t, len(state.input.ime_text), 0)
		},
	)
}

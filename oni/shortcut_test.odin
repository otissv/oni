package oni

import "core:strings"
import "core:testing"
import sdl "vendor:sdl3"

@(private)
shortcut_test_flag: bool

@(private)
shortcut_test_winner: string

@(private)
shortcut_test_action_set_flag :: proc(event: ^Shortcut_Event) {
	_ = event
	shortcut_test_flag = true
}

@(private)
shortcut_test_action_set_winner :: proc(event: ^Shortcut_Event) {
	shortcut_test_winner = event.id
}

@(private)
shortcut_test_press :: proc(key: Scancode, mods: Input_Modifiers = {}) {
	state.input.modifiers = mods
	state.input.keys_down[int(key)] = false
	for &k in w_ctx.keys {
		clear_key_transients(&k)
	}
	sync_widget_input()
	for &k in w_ctx.keys {
		clear_key_transients(&k)
	}
	state.input.keys_down[int(key)] = true
	sync_widget_input()
	state.shortcuts.processed = false
	state.shortcuts.consumed_keys = {}
	shortcut_process()
}

@(test)
shortcut_defaults_zoom_wheel_and_keys :: proc(t: ^testing.T) {
	with_engine_env(
		t,
		proc(t: ^testing.T) {
			shortcut_install_defaults()
			testing.expect(t, state.shortcuts.defaults_installed)
			testing.expect(t, len(state.shortcuts.bindings) > 0)

			state.input.mouse_x = 40
			state.input.mouse_y = 20
			state.input.mouse_wheel_y = 1
			state.input.modifiers.ctrl = true

			for &key in w_ctx.keys {
				clear_key_transients(&key)
			}
			sync_widget_input()
			shortcut_process()
			testing.expect(t, state.view.zoom > VIEW_ZOOM_DEFAULT)
			testing.expect(t, shortcut_wheel_consumed())

			before := state.view.zoom
			shortcut_process()
			expect_close(t, state.view.zoom, before)

			// Plain wheel (no CTRL) must not zoom.
			state.view.zoom = VIEW_ZOOM_DEFAULT
			state.input.mouse_wheel_y = 1
			state.input.modifiers.ctrl = false
			for &key in w_ctx.keys {
				clear_key_transients(&key)
			}
			sync_widget_input()
			shortcut_begin_frame()
			shortcut_process()
			expect_close(t, state.view.zoom, VIEW_ZOOM_DEFAULT)
			testing.expect(t, !shortcut_wheel_consumed())
		},
	)
}

@(test)
shortcut_ctrl_shift_chord :: proc(t: ^testing.T) {
	with_engine_env(
		t,
		proc(t: ^testing.T) {
			shortcut_test_flag = false
			shortcut_register_action("file.save_as", shortcut_test_action_set_flag)
			shortcut_bind("file.save_as", {key = .S, ctrl = true, shift = true})

			shortcut_test_press(.S, {ctrl = true})
			testing.expect(t, !shortcut_test_flag)

			shortcut_begin_frame()
			shortcut_test_press(.S, {ctrl = true, shift = true})
			testing.expect(t, shortcut_test_flag)
		},
	)
}

@(test)
shortcut_sequence_g_then_s :: proc(t: ^testing.T) {
	with_engine_env(
		t,
		proc(t: ^testing.T) {
			shortcut_test_flag = false
			shortcut_register_action("goto.save", shortcut_test_action_set_flag)
			shortcut_bind_sequence("goto.save", {.G, .S})

			shortcut_test_press(.G)
			testing.expect(t, !shortcut_test_flag)

			shortcut_begin_frame()
			shortcut_test_press(.S)
			testing.expect(t, shortcut_test_flag)
		},
	)
}

@(test)
shortcut_context_scope_requires_push :: proc(t: ^testing.T) {
	with_engine_env(
		t,
		proc(t: ^testing.T) {
			shortcut_test_flag = false
			shortcut_register_action("test.ctx", shortcut_test_action_set_flag)
			shortcut_bind(
				"test.ctx",
				{key = .A},
				{scope = .Context, scope_key = "artboard"},
			)

			shortcut_test_press(.A)
			testing.expect(t, !shortcut_test_flag)

			shortcut_begin_frame()
			shortcut_push_context("artboard")
			shortcut_test_press(.A)
			testing.expect(t, shortcut_test_flag)
			testing.expect(t, shortcut_key_consumed(.A))
		},
	)
}

@(test)
shortcut_text_input_filters_plain_keys :: proc(t: ^testing.T) {
	with_engine_env(
		t,
		proc(t: ^testing.T) {
			shortcut_test_flag = false
			shortcut_register_action("test.plain", shortcut_test_action_set_flag)
			shortcut_register_action("test.cmd", shortcut_test_action_set_flag)
			shortcut_bind("test.plain", {key = .S})
			shortcut_bind("test.cmd", {key = .S, ctrl = true})

			shortcut_set_text_input_active(true)
			append(&state.input.text_input, 's')
			shortcut_test_press(.S)
			testing.expect(t, !shortcut_test_flag)
			testing.expect_value(t, len(state.input.text_input), 1)

			shortcut_begin_frame()
			shortcut_test_flag = false
			append(&state.input.text_input, 's')
			shortcut_test_press(.S, {ctrl = true})
			testing.expect(t, shortcut_test_flag)
			testing.expect_value(t, len(state.input.text_input), 0)
		},
	)
}

@(test)
shortcut_priority_and_unbind :: proc(t: ^testing.T) {
	with_engine_env(
		t,
		proc(t: ^testing.T) {
			shortcut_test_winner = ""
			shortcut_register_action("low", shortcut_test_action_set_winner)
			shortcut_register_action("high", shortcut_test_action_set_winner)
			shortcut_bind("low", {key = .B}, {priority = 1})
			shortcut_bind("high", {key = .B}, {priority = 10})

			shortcut_test_press(.B)
			testing.expect_value(t, shortcut_test_winner, "high")

			shortcut_unbind("high", {key = .B})
			shortcut_begin_frame()
			shortcut_test_winner = ""
			shortcut_test_press(.B)
			testing.expect_value(t, shortcut_test_winner, "low")
		},
	)
}

@(test)
shortcut_disable_view_zoom :: proc(t: ^testing.T) {
	with_engine_env(
		t,
		proc(t: ^testing.T) {
			shortcut_install_defaults()
			shortcut_set_enabled(SHORTCUT_VIEW_ZOOM_IN, false)
			shortcut_set_enabled(SHORTCUT_VIEW_ZOOM_OUT, false)

			state.input.mouse_wheel_y = 2
			state.input.modifiers.ctrl = true
			for &key in w_ctx.keys {
				clear_key_transients(&key)
			}
			sync_widget_input()
			shortcut_process()
			expect_close(t, state.view.zoom, VIEW_ZOOM_DEFAULT)
			testing.expect(t, !shortcut_wheel_consumed())
		},
	)
}

@(test)
shortcut_escape_not_quit_by_default :: proc(t: ^testing.T) {
	with_engine_env(
		t,
		proc(t: ^testing.T) {
			shortcut_install_defaults()
			shortcut_test_press(.ESCAPE)
			testing.expect(t, state.running)
		},
	)
}

@(test)
shortcut_capture_and_conflicts_and_export :: proc(t: ^testing.T) {
	with_engine_env(
		t,
		proc(t: ^testing.T) {
			shortcut_register_action("a", shortcut_test_action_set_flag)
			shortcut_register_action("b", shortcut_test_action_set_flag)
			shortcut_bind("a", {key = .X, ctrl = true})
			shortcut_bind("b", {key = .X, ctrl = true})

			conflicts := shortcut_collect_conflicts(context.temp_allocator)
			testing.expect(t, len(conflicts) >= 1)

			shortcut_capture_begin()
			testing.expect(t, shortcut_capture_active())
			shortcut_test_press(.Y, {ctrl = true, shift = true})
			result, done, cancelled := shortcut_capture_take()
			testing.expect(t, done)
			testing.expect(t, !cancelled)
			testing.expect(t, result.trigger == .Key)
			testing.expect(t, result.chord.key == .Y)
			testing.expect(t, result.chord.ctrl && result.chord.shift)

			data := shortcut_export_bindings(context.temp_allocator)
			testing.expect(t, len(data) > 0)
			shortcut_clear_user_bindings()
			testing.expect(t, shortcut_import_bindings(data, true))
			testing.expect(t, shortcut_binding_count() > 0)
		},
	)
}

@(test)
shortcut_wheel_and_mouse_respect_modifiers :: proc(t: ^testing.T) {
	with_engine_env(
		t,
		proc(t: ^testing.T) {
			shortcut_test_flag = false
			shortcut_register_action("zoom.ctrl", shortcut_test_action_set_flag)
			shortcut_bind_wheel("zoom.ctrl", 1, {ctrl = true})

			state.input.mouse_wheel_y = 1
			state.input.modifiers = {}
			for &key in w_ctx.keys {
				clear_key_transients(&key)
			}
			sync_widget_input()
			state.shortcuts.processed = false
			shortcut_process()
			testing.expect(t, !shortcut_test_flag)
			testing.expect(t, !shortcut_wheel_consumed())

			shortcut_begin_frame()
			shortcut_test_flag = false
			state.input.mouse_wheel_y = 1
			state.input.modifiers.ctrl = true
			sync_widget_input()
			state.shortcuts.processed = false
			shortcut_process()
			testing.expect(t, shortcut_test_flag)
			testing.expect(t, shortcut_wheel_consumed())

			shortcut_begin_frame()
			shortcut_test_flag = false
			shortcut_register_action("ctx.right", shortcut_test_action_set_flag)
			shortcut_bind_mouse("ctx.right", sdl.BUTTON_RIGHT, {shift = true})

			w_ctx.right_mouse = {}
			state.input.modifiers = {shift = true}
			state.input.mouse_right = true
			for &key in w_ctx.keys {
				clear_key_transients(&key)
			}
			clear_button_transients(&w_ctx.right_mouse)
			sync_widget_input()
			state.shortcuts.processed = false
			shortcut_process()
			testing.expect(t, shortcut_test_flag)
			testing.expect(t, shortcut_mouse_consumed(sdl.BUTTON_RIGHT))
		},
	)
}

@(test)
shortcut_gamepad_start_default_binding :: proc(t: ^testing.T) {
	with_engine_env(
		t,
		proc(t: ^testing.T) {
			shortcut_install_defaults()
			state.input.gamepad.buttons_down[int(sdl.GamepadButton.START)] = true
			for &key in w_ctx.keys {
				clear_key_transients(&key)
			}
			sync_widget_input()
			state.shortcuts.processed = false
			shortcut_process()
			// toggle_fullscreen with nil window is a no-op; binding still consumes.
			testing.expect(t, shortcut_gamepad_consumed(.START))
		},
	)
}

@(test)
shortcut_conflicts_respect_scope :: proc(t: ^testing.T) {
	with_engine_env(
		t,
		proc(t: ^testing.T) {
			shortcut_register_action("a", shortcut_test_action_set_flag)
			shortcut_register_action("b", shortcut_test_action_set_flag)
			shortcut_bind("a", {key = .Z}, {scope = .Context, scope_key = "one"})
			shortcut_bind("b", {key = .Z}, {scope = .Context, scope_key = "two"})
			conflicts := shortcut_collect_conflicts(context.temp_allocator)
			testing.expect_value(t, len(conflicts), 0)

			shortcut_bind("b", {key = .Z}, {scope = .Context, scope_key = "one"})
			conflicts = shortcut_collect_conflicts(context.temp_allocator)
			testing.expect(t, len(conflicts) >= 1)
		},
	)
}

@(test)
shortcut_list_format_and_import_roundtrip :: proc(t: ^testing.T) {
	with_engine_env(
		t,
		proc(t: ^testing.T) {
			shortcut_register_action("file.save", shortcut_test_action_set_flag)
			shortcut_set_action_label("file.save", "Save")
			shortcut_bind("file.save", {key = .S, ctrl = true})
			testing.expect_value(t, shortcut_action_label("file.save"), "Save")

			n := shortcut_binding_count()
			testing.expect(t, n >= 1)
			b, ok := shortcut_binding_get(n - 1)
			testing.expect(t, ok)
			testing.expect_value(t, b.id, "file.save")

			label := shortcut_format_binding(b, context.temp_allocator)
			testing.expect(t, len(label) > 0)

			list := shortcut_list_bindings(context.temp_allocator)
			testing.expect(t, len(list) >= 1)

			data := shortcut_export_bindings(context.temp_allocator)
			shortcut_clear_user_bindings()
			testing.expect(t, shortcut_import_bindings(data, true))
			found := false
			for i in 0 ..< shortcut_binding_count() {
				row, row_ok := shortcut_binding_get(i)
				if row_ok && row.id == "file.save" && row.chord.key == .S {
					found = true
					break
				}
			}
			testing.expect(t, found)
		},
	)
}

@(test)
shortcut_import_rejects_bad_line_without_clearing :: proc(t: ^testing.T) {
	with_engine_env(
		t,
		proc(t: ^testing.T) {
			shortcut_bind("keep", {key = .K})
			before := shortcut_binding_count()
			bad := "NOT_A_VALID_BINDING\n"
			err := shortcut_import_bindings_ex(bad, true)
			testing.expect(t, !err.ok)
			testing.expect(t, err.line >= 1)
			testing.expect_value(t, shortcut_binding_count(), before)
		},
	)
}

@(test)
shortcut_unbind_mouse_sequence_gamepad :: proc(t: ^testing.T) {
	with_engine_env(
		t,
		proc(t: ^testing.T) {
			shortcut_register_action("m", shortcut_test_action_set_flag)
			shortcut_bind_mouse("m", sdl.BUTTON_LEFT)
			shortcut_bind_sequence("m", {.G, .H})
			shortcut_bind_gamepad("m", .SOUTH)
			testing.expect(t, shortcut_binding_count() >= 3)
			shortcut_unbind_mouse("m", sdl.BUTTON_LEFT)
			shortcut_unbind_sequence("m", {.G, .H})
			shortcut_unbind_gamepad("m", .SOUTH)
			for i in 0 ..< shortcut_binding_count() {
				b, ok := shortcut_binding_get(i)
				testing.expect(t, !ok || b.id != "m")
			}
		},
	)
}

@(test)
shortcut_focused_id_and_text_input_note :: proc(t: ^testing.T) {
	with_engine_env(
		t,
		proc(t: ^testing.T) {
			shortcut_test_flag = false
			shortcut_register_action("focus.act", shortcut_test_action_set_flag)
			shortcut_bind(
				"focus.act",
				{key = .F},
				{scope = .Focused_Id, scope_key = "field"},
			)

			shortcut_test_press(.F)
			testing.expect(t, !shortcut_test_flag)

			widget_set_focused_id("field")
			shortcut_begin_frame()
			shortcut_test_press(.F)
			testing.expect(t, shortcut_test_flag)

			shortcut_test_flag = false
			shortcut_bind("plain", {key = .P})
			shortcut_register_action("plain", shortcut_test_action_set_flag)
			shortcut_note_text_input("field")
			shortcut_begin_frame()
			shortcut_note_text_input("field")
			widget_set_focused_id("field")
			shortcut_test_press(.P)
			testing.expect(t, !shortcut_test_flag)
		},
	)
}

@(test)
shortcut_capture_escape_cancels :: proc(t: ^testing.T) {
	with_engine_env(
		t,
		proc(t: ^testing.T) {
			shortcut_capture_begin(.Key)
			shortcut_test_press(.ESCAPE)
			_, done, cancelled := shortcut_capture_take()
			testing.expect(t, !done)
			testing.expect(t, cancelled)
		},
	)
}

@(test)
shortcut_sequence_timeout_resets :: proc(t: ^testing.T) {
	with_engine_env(
		t,
		proc(t: ^testing.T) {
			shortcut_test_flag = false
			shortcut_register_action("seq", shortcut_test_action_set_flag)
			shortcut_bind_sequence("seq", {.G, .S})
			shortcut_test_press(.G)
			testing.expect(t, !shortcut_test_flag)
			for _ in 0 ..< int(SHORTCUT_SEQUENCE_TIMEOUT_FRAMES) {
				shortcut_begin_frame()
			}
			shortcut_test_press(.S)
			testing.expect(t, !shortcut_test_flag)
		},
	)
}

@(test)
shortcut_friendly_format_roundtrip :: proc(t: ^testing.T) {
	with_engine_env(
		t,
		proc(t: ^testing.T) {
			shortcut_register_action("demo.ping", shortcut_test_action_set_flag)
			shortcut_bind("demo.ping", {key = .P, ctrl = true})
			_ = shortcut_bind_wheel("view.zoom_in", 1) // user wheel; builtins are not exported
			shortcut_set_enabled("demo.ping", false)

			data := shortcut_export_bindings(context.temp_allocator)
			testing.expect(t, !strings.contains(data, "oni-shortcuts"))
			testing.expect(t, strings.contains(data, "CTRL+P = demo.ping"))
			testing.expect(t, strings.contains(data, "enabled = false"))
			testing.expect(t, strings.contains(data, "WHEEL+UP = view.zoom_in"))
			testing.expect(t, !strings.contains(data, "source"))

			shortcut_clear_bindings()
			shortcut_register_action("demo.ping", shortcut_test_action_set_flag)
			testing.expect(t, shortcut_import_bindings(data, true))

			found_disabled := false
			found_wheel := false
			for i in 0 ..< shortcut_binding_count() {
				b, ok := shortcut_binding_get(i)
				if !ok do continue
				if b.id == "demo.ping" && b.chord.key == .P && b.chord.ctrl {
					testing.expect(t, !b.enabled)
					testing.expect(t, b.source == .User)
					found_disabled = true
				}
				if b.id == "view.zoom_in" && b.trigger == .Wheel_Y && b.wheel_sign == 1 {
					testing.expect(t, b.source == .User)
					found_wheel = true
				}
			}
			testing.expect(t, found_disabled)
			testing.expect(t, found_wheel)
		},
	)
}

@(test)
shortcut_friendly_parse_mod_wheel_and_gamepad :: proc(t: ^testing.T) {
	with_engine_env(
		t,
		proc(t: ^testing.T) {
			friendly :=
				"MOD+WHEEL+UP = view.zoom_in { enabled = false }\nCTRL+EQUAL = view.zoom_in\nGAMEPAD_START = window.toggle_fullscreen\n"
			testing.expect(t, shortcut_import_bindings(friendly, true))

			mod_wheel := false
			equals := false
			gamepad := false
			for i in 0 ..< shortcut_binding_count() {
				b, ok := shortcut_binding_get(i)
				if !ok do continue
				if b.trigger == .Wheel_Y && b.chord.super && !b.enabled {
					testing.expect(t, b.source == .User)
					mod_wheel = true
				}
				if b.trigger == .Key && b.chord.key == .EQUALS && b.chord.ctrl {
					testing.expect(t, b.source == .User)
					equals = true
				}
				if b.trigger == .Gamepad && b.gamepad_button == i32(sdl.GamepadButton.START) {
					testing.expect(t, b.source == .User)
					gamepad = true
				}
			}
			testing.expect(t, mod_wheel)
			testing.expect(t, equals)
			testing.expect(t, gamepad)
		},
	)
}

@(test)
shortcut_config_overrides_builtin_trigger :: proc(t: ^testing.T) {
	with_engine_env(
		t,
		proc(t: ^testing.T) {
			shortcut_install_defaults()
			before_builtin := false
			for i in 0 ..< shortcut_binding_count() {
				b, ok := shortcut_binding_get(i)
				if !ok do continue
				if b.id == SHORTCUT_VIEW_ZOOM_IN &&
				   b.trigger == .Wheel_Y &&
				   b.wheel_sign == 1 &&
				   b.source == .Builtin {
					before_builtin = true
				}
			}
			testing.expect(t, before_builtin)

			friendly := "CTRL+WHEEL+UP = demo.ping\n"
			shortcut_register_action("demo.ping", shortcut_test_action_set_flag)
			testing.expect(t, shortcut_import_bindings(friendly, true))

			user_override := false
			builtin_left := false
			for i in 0 ..< shortcut_binding_count() {
				b, ok := shortcut_binding_get(i)
				if !ok do continue
				if b.trigger == .Wheel_Y && b.wheel_sign == 1 && b.chord.ctrl {
					if b.id == "demo.ping" && b.source == .User {
						user_override = true
					}
					if b.id == SHORTCUT_VIEW_ZOOM_IN && b.source == .Builtin {
						builtin_left = true
					}
				}
			}
			testing.expect(t, user_override)
			testing.expect(t, !builtin_left)
		},
	)
}

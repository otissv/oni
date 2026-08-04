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
	with_engine_env(t, proc(t: ^testing.T) {
		shortcut_test_flag = false
		shortcut_register_action("file.save_as", shortcut_test_action_set_flag)
		shortcut_bind("file.save_as", {key = .S, ctrl = true, shift = true})

		shortcut_test_press(.S, {ctrl = true})
		testing.expect(t, !shortcut_test_flag)

		shortcut_begin_frame()
		shortcut_test_press(.S, {ctrl = true, shift = true})
		testing.expect(t, shortcut_test_flag)
	})
}

@(test)
shortcut_sequence_g_then_s :: proc(t: ^testing.T) {
	with_engine_env(t, proc(t: ^testing.T) {
		shortcut_test_flag = false
		shortcut_register_action("goto.save", shortcut_test_action_set_flag)
		shortcut_bind_sequence({id = "goto.save", keys = {.G, .S}, enabled = true})

		shortcut_test_press(.G)
		testing.expect(t, !shortcut_test_flag)

		shortcut_begin_frame()
		shortcut_test_press(.S)
		testing.expect(t, shortcut_test_flag)
	})
}

@(test)
shortcut_context_scope_requires_push :: proc(t: ^testing.T) {
	with_engine_env(t, proc(t: ^testing.T) {
		shortcut_test_flag = false
		shortcut_register_action("test.ctx", shortcut_test_action_set_flag)
		shortcut_bind("test.ctx", {key = .A}, {scope = .Context, scope_key = "artboard"})

		shortcut_test_press(.A)
		testing.expect(t, !shortcut_test_flag)

		shortcut_begin_frame()
		shortcut_push_context("artboard")
		shortcut_test_press(.A)
		testing.expect(t, shortcut_test_flag)
		testing.expect(t, shortcut_key_consumed(.A))
	})
}

@(test)
shortcut_text_input_filters_plain_keys :: proc(t: ^testing.T) {
	with_engine_env(t, proc(t: ^testing.T) {
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
	})
}

@(test)
shortcut_priority_and_unbind :: proc(t: ^testing.T) {
	with_engine_env(t, proc(t: ^testing.T) {
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
	})
}

@(test)
shortcut_disable_view_zoom :: proc(t: ^testing.T) {
	with_engine_env(t, proc(t: ^testing.T) {
		shortcut_install_defaults()
		shortcut_set_enabled(Shortcut_Action_Type.SHORTCUT_VIEW_ZOOM_IN, false)
		shortcut_set_enabled(Shortcut_Action_Type.SHORTCUT_VIEW_ZOOM_OUT, false)

		state.input.mouse_wheel_y = 2
		state.input.modifiers.ctrl = true
		for &key in w_ctx.keys {
			clear_key_transients(&key)
		}
		sync_widget_input()
		shortcut_process()
		expect_close(t, state.view.zoom, VIEW_ZOOM_DEFAULT)
		testing.expect(t, !shortcut_wheel_consumed())
	})
}

@(test)
shortcut_escape_not_quit_by_default :: proc(t: ^testing.T) {
	with_engine_env(t, proc(t: ^testing.T) {
		shortcut_install_defaults()
		shortcut_test_press(.ESCAPE)
		testing.expect(t, state.running)
	})
}

@(test)
shortcut_capture_and_conflicts_and_export :: proc(t: ^testing.T) {
	with_engine_env(t, proc(t: ^testing.T) {
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
	})
}

@(test)
shortcut_wheel_and_mouse_respect_modifiers :: proc(t: ^testing.T) {
	with_engine_env(t, proc(t: ^testing.T) {
		shortcut_test_flag = false
		shortcut_register_action("zoom.ctrl", shortcut_test_action_set_flag)
		shortcut_bind_wheel(
			{id = "zoom.ctrl", wheel_sign = 1, chord = {ctrl = true}, enabled = true},
		)

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
		shortcut_bind_mouse(
			{id = "ctx.right", button = sdl.BUTTON_RIGHT, chord = {shift = true}, enabled = true},
		)

		w_ctx.right_mouse = {}
		state.input.modifiers = {
			shift = true,
		}
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
	})
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
	with_engine_env(t, proc(t: ^testing.T) {
		shortcut_register_action("a", shortcut_test_action_set_flag)
		shortcut_register_action("b", shortcut_test_action_set_flag)
		shortcut_bind("a", {key = .Z}, {scope = .Context, scope_key = "one"})
		shortcut_bind("b", {key = .Z}, {scope = .Context, scope_key = "two"})
		conflicts := shortcut_collect_conflicts(context.temp_allocator)
		testing.expect_value(t, len(conflicts), 0)

		shortcut_bind("b", {key = .Z}, {scope = .Context, scope_key = "one"})
		conflicts = shortcut_collect_conflicts(context.temp_allocator)
		testing.expect(t, len(conflicts) >= 1)
	})
}

@(test)
shortcut_list_format_and_import_roundtrip :: proc(t: ^testing.T) {
	with_engine_env(t, proc(t: ^testing.T) {
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
	})
}

@(test)
shortcut_import_rejects_bad_line_without_clearing :: proc(t: ^testing.T) {
	with_engine_env(t, proc(t: ^testing.T) {
		shortcut_bind("keep", {key = .K})
		before := shortcut_binding_count()
		bad := "NOT_A_VALID_BINDING\n"
		err := shortcut_import_bindings_ex(bad, true)
		testing.expect(t, !err.ok)
		testing.expect(t, err.line >= 1)
		testing.expect_value(t, shortcut_binding_count(), before)
	})
}

@(test)
shortcut_remove_and_set_enabled_at :: proc(t: ^testing.T) {
	with_engine_env(t, proc(t: ^testing.T) {
		shortcut_register_action("a", shortcut_test_action_set_flag)
		shortcut_register_action("b", shortcut_test_action_set_flag)
		testing.expect(t, shortcut_bind("a", {key = .A}))
		testing.expect(t, shortcut_bind("b", {key = .B}))
		n := shortcut_binding_count()
		testing.expect(t, n >= 2)

		idx_b := -1
		for i in 0 ..< shortcut_binding_count() {
			b, ok := shortcut_binding_get(i)
			if ok && b.id == "b" {
				idx_b = i
				break
			}
		}
		testing.expect(t, idx_b >= 0)
		testing.expect(t, shortcut_set_binding_enabled_at(idx_b, false))
		b, ok := shortcut_binding_get(idx_b)
		testing.expect(t, ok && !b.enabled)

		testing.expect(t, shortcut_remove_binding_at(idx_b))
		testing.expect_value(t, shortcut_binding_count(), n - 1)
		testing.expect(t, !shortcut_remove_binding_at(999))
		testing.expect(t, !shortcut_set_binding_enabled_at(-1, true))
	})
}

@(test)
shortcut_list_actions_sorted :: proc(t: ^testing.T) {
	with_engine_env(t, proc(t: ^testing.T) {
		shortcut_register_action("z.action", shortcut_test_action_set_flag)
		shortcut_register_action("a.action", shortcut_test_action_set_flag)
		list := shortcut_list_actions(context.temp_allocator)
		defer shortcut_free_action_list(list, context.temp_allocator)
		testing.expect(t, len(list) >= 2)
		found_a := false
		found_z := false
		prev := ""
		for id in list {
			if prev != "" {
				testing.expect(t, prev <= id)
			}
			prev = id
			if id == "a.action" do found_a = true
			if id == "z.action" do found_z = true
		}
		testing.expect(t, found_a && found_z)
	})
}

@(test)
shortcut_unbind_mouse_sequence_gamepad :: proc(t: ^testing.T) {
	with_engine_env(t, proc(t: ^testing.T) {
		shortcut_register_action("m", shortcut_test_action_set_flag)
		shortcut_bind_mouse({id = "m", button = sdl.BUTTON_LEFT, enabled = true})
		shortcut_bind_sequence({id = "m", keys = {.G, .H}, enabled = true})
		shortcut_bind_gamepad({id = "m", button = .SOUTH, enabled = true})
		testing.expect(t, shortcut_binding_count() >= 3)
		shortcut_unbind_mouse("m", sdl.BUTTON_LEFT)
		shortcut_unbind_sequence("m", {.G, .H})
		shortcut_unbind_gamepad("m", .SOUTH)
		for i in 0 ..< shortcut_binding_count() {
			b, ok := shortcut_binding_get(i)
			testing.expect(t, !ok || b.id != "m")
		}
	})
}

@(test)
shortcut_focused_id_and_text_input_note :: proc(t: ^testing.T) {
	with_engine_env(t, proc(t: ^testing.T) {
		shortcut_test_flag = false
		shortcut_register_action("focus.act", shortcut_test_action_set_flag)
		shortcut_bind("focus.act", {key = .F}, {scope = .Focused_Id, scope_key = "field"})

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
	})
}

@(test)
shortcut_capture_escape_cancels :: proc(t: ^testing.T) {
	with_engine_env(t, proc(t: ^testing.T) {
		shortcut_capture_begin(.Key)
		shortcut_test_press(.ESCAPE)
		_, done, cancelled := shortcut_capture_take()
		testing.expect(t, !done)
		testing.expect(t, cancelled)
	})
}

@(test)
shortcut_sequence_timeout_resets :: proc(t: ^testing.T) {
	with_engine_env(t, proc(t: ^testing.T) {
		shortcut_test_flag = false
		shortcut_register_action("seq", shortcut_test_action_set_flag)
		shortcut_bind_sequence({id = "seq", keys = {.G, .S}, enabled = true})
		shortcut_test_press(.G)
		testing.expect(t, !shortcut_test_flag)
		for _ in 0 ..< int(SHORTCUT_SEQUENCE_TIMEOUT_FRAMES) {
			shortcut_begin_frame()
		}
		shortcut_test_press(.S)
		testing.expect(t, !shortcut_test_flag)
	})
}

@(test)
shortcut_friendly_format_roundtrip :: proc(t: ^testing.T) {
	with_engine_env(
		t,
		proc(t: ^testing.T) {
			shortcut_register_action("demo.ping", shortcut_test_action_set_flag)
			shortcut_bind("demo.ping", {key = .P, ctrl = true})
			_ = shortcut_bind_wheel({id = "view.zoom_in", wheel_sign = 1, enabled = true}) // user wheel; builtins are not exported
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
	with_engine_env(t, proc(t: ^testing.T) {
		friendly := "MOD+WHEEL+UP = view.zoom_in { enabled = false }\nCTRL+EQUAL = view.zoom_in\nGAMEPAD_START = window.toggle_fullscreen\n"
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
	})
}

@(test)
shortcut_config_overrides_builtin_trigger :: proc(t: ^testing.T) {
	with_engine_env(t, proc(t: ^testing.T) {
		shortcut_install_defaults()
		before_builtin := false
		for i in 0 ..< shortcut_binding_count() {
			b, ok := shortcut_binding_get(i)
			if !ok do continue
			if b.id == shortcut_action_types[.SHORTCUT_VIEW_ZOOM_IN] && b.trigger == .Wheel_Y && b.wheel_sign == 1 && b.source == .Builtin {
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
				if b.id == shortcut_action_types[.SHORTCUT_VIEW_ZOOM_IN] && b.source == .Builtin {
					builtin_left = true
				}
			}
		}
		testing.expect(t, user_override)
		testing.expect(t, !builtin_left)
	})
}

@(test)
shortcut_import_scoped_override_preserves_other_kinds :: proc(t: ^testing.T) {
	with_engine_env(t, proc(t: ^testing.T) {
		shortcut_install_defaults()
		move_left_id := shortcut_action_types[.SHORTCUT_EDIT_MOVE_LEFT]

		text_input_before := false
		rich_text_input_before := false
		for i in 0 ..< shortcut_binding_count() {
			b, ok := shortcut_binding_get(i)
			if !ok do continue
			if b.id != move_left_id || b.chord.key != .LEFT || !b.chord.ctrl || b.chord.shift do continue

			#partial switch b.scope_kind {
			case .TEXT_INPUT:
				text_input_before = true
			case .RICH_TEXT_INPUT:
				rich_text_input_before = true
			case:
			}
		}

		testing.expect(t, text_input_before)
		testing.expect(t, rich_text_input_before)

		row := "CTRL+LEFT = edit.move_left { scope = focused_kind, scope_kind = 4 }\n"
		testing.expect(t, shortcut_import_bindings(row, false))

		text_input_after := false
		rich_text_input_user := false
		for i in 0 ..< shortcut_binding_count() {
			b, ok := shortcut_binding_get(i)
			if !ok do continue
			if b.id != move_left_id || b.chord.key != .LEFT || !b.chord.ctrl || b.chord.shift do continue

			#partial switch b.scope_kind {
			case .TEXT_INPUT:
				text_input_after = true
			case .RICH_TEXT_INPUT:
				if b.source == .User {
					rich_text_input_user = true
				}
			case:
			}
		}

		testing.expect(t, text_input_after)
		testing.expect(t, rich_text_input_user)
	})
}

@(test)
shortcut_edit_actions_set_text_edit_command :: proc(t: ^testing.T) {
	with_engine_env(t, proc(t: ^testing.T) {
		register_shortcut_actions()

		text_edit_action_copy(nil)
		testing.expect_value(t, text_edit_consume_command(), Text_Edit_Command.COPY)

		text_edit_action_paste(nil)
		testing.expect_value(t, text_edit_consume_command(), Text_Edit_Command.PASTE)

		text_edit_action_undo(nil)
		testing.expect_value(t, text_edit_consume_command(), Text_Edit_Command.UNDO)

		text_edit_action_redo(nil)
		testing.expect_value(t, text_edit_consume_command(), Text_Edit_Command.REDO)
	})
}

@(test)
shortcut_edit_nav_bindings_installed :: proc(t: ^testing.T) {
	with_engine_env(t, proc(t: ^testing.T) {
		shortcut_install_defaults()

		found_plain := false
		found_ctrl := false
		move_left_id := shortcut_action_types[.SHORTCUT_EDIT_MOVE_LEFT]
		for i in 0 ..< shortcut_binding_count() {
			b, ok := shortcut_binding_get(i)
			if !ok do continue
			if b.id != move_left_id do continue
			if b.chord.key != .LEFT do continue

			if b.chord.ctrl {
				found_ctrl = true
			} else if !b.chord.shift && !b.chord.alt && !b.chord.super {
				found_plain = true
			}
		}

		testing.expectf(t, found_plain, "missing plain LEFT binding for %s", move_left_id)
		testing.expectf(t, found_ctrl, "missing CTRL+LEFT binding for %s", move_left_id)
	})
}

@(test)
shortcut_edit_nav_action_sets_pending_nav :: proc(t: ^testing.T) {
	with_engine_env(t, proc(t: ^testing.T) {
		register_shortcut_actions()

		text_edit_action_nav_key(
			&Shortcut_Event{chord = {key = .LEFT, ctrl = true, shift = true}},
		)

		nav, ok := text_edit_take_nav(true)
		testing.expect(t, ok)
		testing.expect_value(t, nav.key, Scancode.LEFT)
		testing.expect(t, nav.ctrl)
		testing.expect(t, nav.shift)
	})
}

@(private)
shortcut_test_press_edit :: proc(
	focused_key: string,
	kind: Widget_Kind,
	key: Scancode,
	mods: Input_Modifiers = {},
) {
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
	state.shortcuts.consumed_keys = {}
	text_edit_shortcut_process(focused_key, kind)
}

@(test)
shortcut_edit_bindings_keep_focused_kind_scopes :: proc(t: ^testing.T) {
	with_engine_env(t, proc(t: ^testing.T) {
		shortcut_install_defaults()

		move_left_id := shortcut_action_types[.SHORTCUT_EDIT_MOVE_LEFT]
		found_text_input := false
		found_rich_text_input := false

		for i in 0 ..< shortcut_binding_count() {
			b, ok := shortcut_binding_get(i)
			if !ok do continue
			if b.id != move_left_id do continue
			if b.chord.key != .LEFT || !b.chord.ctrl || b.chord.shift do continue

			#partial switch b.scope_kind {
			case .TEXT_INPUT:
				found_text_input = true
			case .RICH_TEXT_INPUT:
				found_rich_text_input = true
			case:
			}
		}

		testing.expect(t, found_text_input)
		testing.expect(t, found_rich_text_input)
	})
}

@(test)
shortcut_edit_process_keys_sets_pending_nav :: proc(t: ^testing.T) {
	with_engine_env(t, proc(t: ^testing.T) {
		shortcut_install_defaults()
		widget_set_focused_id("field")

		shortcut_test_press_edit("field", .TEXT_INPUT, .LEFT, {ctrl = true})

		nav, nav_ok := text_edit_take_nav(true)
		testing.expect(t, nav_ok)
		testing.expect_value(t, nav.key, Scancode.LEFT)
		testing.expect(t, nav.ctrl)
	})
}

@(test)
shortcut_edit_process_keys_sets_copy_command :: proc(t: ^testing.T) {
	with_engine_env(t, proc(t: ^testing.T) {
		shortcut_install_defaults()
		widget_set_focused_id("field")

		shortcut_test_press_edit("field", .TEXT_INPUT, .C, {ctrl = true})

		testing.expect_value(t, text_edit_take_command(true), Text_Edit_Command.COPY)
	})
}

@(test)
shortcut_rebind_reinstalls_builtin_bindings :: proc(t: ^testing.T) {
	with_engine_env(t, proc(t: ^testing.T) {
		shortcut_install_defaults()
		before := shortcut_binding_count()

		shortcut_bind_key(
			{
				id = shortcut_action_types[.SHORTCUT_EDIT_MOVE_LEFT],
				chord = {key = .J, ctrl = true},
				scope = .Focused_Kind,
				scope_kind = .TEXT_INPUT,
				enabled = true,
				source = .Builtin,
			},
		)

		testing.expect_value(t, shortcut_binding_count(), before + 1)

		shortcut_rebind_builtin_actions()

		found_default := false
		found_override := false
		for i in 0 ..< shortcut_binding_count() {
			b, ok := shortcut_binding_get(i)
			if !ok do continue
			if b.id != shortcut_action_types[.SHORTCUT_EDIT_MOVE_LEFT] do continue
			if b.chord.key == .LEFT && b.chord.ctrl && b.source == .Builtin {
				found_default = true
			}
			if b.chord.key == .J && b.source == .Builtin {
				found_override = true
			}
		}

		testing.expect(t, found_default)
		testing.expect(t, !found_override)
		testing.expect(t, state.shortcuts.actions[shortcut_action_types[.SHORTCUT_EDIT_MOVE_LEFT]] != nil)
	})
}

@(test)
shortcut_app_type_filter :: proc(t: ^testing.T) {
	with_engine_env(t, proc(t: ^testing.T) {
		shortcut_init()
		shortcut_register_action("test.action", proc(_: ^Shortcut_Event) {})

		tool_only := App_Type_Filter(App_Type_Id(0))
		game_only := App_Type_Filter(App_Type_Id(1))

		shortcut_bind_key(
			{
				id = "test.action",
				chord = {key = .K},
				scope = .Global,
				enabled = true,
				source = .User,
				app_type = tool_only,
			},
		)
		shortcut_bind_key(
			{
				id = "test.action",
				chord = {key = .L},
				scope = .Global,
				enabled = true,
				source = .User,
				app_type = game_only,
			},
		)

		state.app_type = App_Type_Id(0)
		shortcut_test_press(.K)
		testing.expect(t, shortcut_key_consumed(.K))
		shortcut_test_press(.L)
		testing.expect(t, !shortcut_key_consumed(.L))

		state.app_type = App_Type_Id(1)
		shortcut_test_press(.K)
		testing.expect(t, !shortcut_key_consumed(.K))
		shortcut_test_press(.L)
		testing.expect(t, shortcut_key_consumed(.L))
	})
}

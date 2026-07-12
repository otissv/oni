package widgets

import o ".."
import "core:testing"
import sdl "vendor:sdl3"

@(test)
merge_state_config_and_event_carry_fields :: proc(t: ^testing.T) {
	state := o.Widget_Frame_State {
		is_hovered = true,
		is_focused = true,
	}
	config := o.Resolved_Widget_Config {
		id = "x",
		kind = .BUTTON,
	}
	merged := merge_state_config(state, config)
	testing.expect(t, merged.is_hovered)
	testing.expect(t, merged.config.kind == .BUTTON)

	event := merge_state_event(state, config, mouse_button = 1, key = o.Scancode.RETURN)
	testing.expect_value(t, event.mouse_button, u8(1))
	testing.expect(t, event.key == o.Scancode.RETURN)
	testing.expect(t, event.frame_state.is_focused)
}

@(test)
update_mouse_button_sets_edges_and_clear_resets_them :: proc(t: ^testing.T) {
	button: o.Widget_Mouse_Button_State

	update_mouse_button(&button, true)
	testing.expect(t, button.down)
	testing.expect(t, button.pressed)
	testing.expect(t, !button.released)

	clear_button_transients(&button)
	testing.expect(t, button.down)
	testing.expect(t, !button.pressed)

	update_mouse_button(&button, true)
	testing.expect(t, !button.pressed)

	update_mouse_button(&button, false)
	testing.expect(t, !button.down)
	testing.expect(t, button.released)

	clear_button_transients(&button)
	testing.expect(t, !button.released)
}

@(test)
update_key_state_ignores_repeat_on_press :: proc(t: ^testing.T) {
	key: o.Widget_Mouse_Key_State

	update_key_state(&key, true, true)
	testing.expect(t, key.down)
	testing.expect(t, !key.pressed)

	update_key_state(&key, false, false)
	testing.expect(t, key.released)

	clear_key_transients(&key)
	update_key_state(&key, true, false)
	testing.expect(t, key.pressed)
}

@(test)
element_key_registers_static_ids_and_auto_ids :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			o.w_ctx.auto_element_index = 0
			auto := element_key("")
			testing.expect(t, auto != "")

			named := element_key("save")
			got, ok := GetElementById("save")
			testing.expect(t, ok)
			testing.expect_value(t, got, named)

			_, missing := GetElementById("nope")
			testing.expect(t, !missing)
		},
	)
}

@(test)
FocusElement_sets_focused_id_when_registered :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			key := element_key("target")
			testing.expect(t, FocusElement("target"))
			testing.expect_value(t, o.w_ctx.focused_id, key)
			testing.expect(t, !FocusElement("missing"))
		},
	)
}

@(test)
FocusNext_and_FocusPrev_walk_tab_order :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			a := element_key("a")
			b := element_key("b")
			c := element_key("c")
			o.register_tabbable(a)
			o.register_tabbable(b)
			o.register_tabbable(c)
			o.w_ctx.focused_id = a

			testing.expect(t, FocusNext())
			testing.expect_value(t, o.w_ctx.focused_id, b)
			testing.expect(t, FocusNext())
			testing.expect_value(t, o.w_ctx.focused_id, c)
			testing.expect(t, FocusPrev())
			testing.expect_value(t, o.w_ctx.focused_id, b)
		},
	)
}

@(test)
ProcessEvent_updates_mouse_and_keyboard_context :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			motion: sdl.Event
			motion.type = .MOUSE_MOTION
			motion.motion.x = 42
			motion.motion.y = 24
			ProcessEvent(&motion)
			testing.expect(t, o.w_ctx.mouse_moved)
			expect_close(t, o.w_ctx.mouse_x, 42)
			expect_close(t, o.w_ctx.mouse_y, 24)

			down: sdl.Event
			down.type = .MOUSE_BUTTON_DOWN
			down.button.button = sdl.BUTTON_LEFT
			down.button.x = 10
			down.button.y = 11
			ProcessEvent(&down)
			testing.expect(t, o.w_ctx.left_mouse.pressed)
			testing.expect(t, o.w_ctx.left_mouse.down)

			key_down: sdl.Event
			key_down.type = .KEY_DOWN
			key_down.key.scancode = .SPACE
			ProcessEvent(&key_down)
			testing.expect(t, o.w_ctx.keys[int(sdl.Scancode.SPACE)].pressed)
		},
	)
}

@(test)
Shutdown_clears_widget_context_maps :: proc(t: ^testing.T) {
	with_widget_env(
		t,
		proc(t: ^testing.T) {
			_ = element_key("x")
			o.register_tabbable("x")
			testing.expect(t, o.w_ctx.static_ids != nil)
			Shutdown()
			testing.expect(t, o.w_ctx.static_ids == nil)
			testing.expect(t, o.w_ctx.tab_order == nil)
			// Restore maps for ui_shutdown defer in with_widget_env
			o.ui_init()
		},
	)
}

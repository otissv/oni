package oni

import "core:math"
import "core:testing"
import sdl "vendor:sdl3"

@(private)
with_gamepad_env :: proc(t: ^testing.T, body: proc(t: ^testing.T)) {
	with_engine_env(t, body)
}

@(private)
gamepad_expect_deadzone :: proc(t: ^testing.T, value, want: f32, loc := #caller_location) {
	got := gamepad_apply_deadzone(value)
	expect_close(t, got, want, loc = loc)
}

@(private)
gamepad_deadzone_scaled :: proc(value: f32) -> f32 {
	if math.abs(value) < GAMEPAD_DEADZONE do return 0
	sign := value < 0 ? f32(-1) : f32(1)
	return sign * ((math.abs(value) - GAMEPAD_DEADZONE) / (1 - GAMEPAD_DEADZONE))
}

@(private)
gamepad_fill_dirty_input :: proc() {
	state.input.gamepad = {
		connected     = true,
		dpad_left     = true,
		dpad_right    = true,
		dpad_up       = true,
		dpad_down     = true,
		left_stick_x  = 0.5,
		left_stick_y  = -0.5,
		right_stick_x = 0.25,
		right_stick_y = -0.25,
		left_trigger  = 0.8,
		right_trigger = 0.9,
	}
	for &down in state.input.gamepad.buttons_down {
		down = true
	}
}

@(private)
gamepad_expect_cleared :: proc(t: ^testing.T, loc := #caller_location) {
	g := state.input.gamepad
	testing.expect(t, !g.connected, loc = loc)
	testing.expect(t, !g.dpad_left, loc = loc)
	testing.expect(t, !g.dpad_right, loc = loc)
	testing.expect(t, !g.dpad_up, loc = loc)
	testing.expect(t, !g.dpad_down, loc = loc)
	expect_close(t, g.left_stick_x, 0, loc = loc)
	expect_close(t, g.left_stick_y, 0, loc = loc)
	expect_close(t, g.right_stick_x, 0, loc = loc)
	expect_close(t, g.right_stick_y, 0, loc = loc)
	expect_close(t, g.left_trigger, 0, loc = loc)
	expect_close(t, g.right_trigger, 0, loc = loc)
	for down, i in g.buttons_down {
		testing.expectf(t, !down, "buttons_down[%d] still set", i, loc = loc)
	}
}

// ---------------------------------------------------------------------------
// gamepad_button_index
// ---------------------------------------------------------------------------

@(test)
gamepad_button_index_invalid_and_negative :: proc(t: ^testing.T) {
	idx, ok := gamepad_button_index(.INVALID)
	testing.expect(t, !ok)
	testing.expect_value(t, idx, 0)

	idx, ok = gamepad_button_index(sdl.GamepadButton(-2))
	testing.expect(t, !ok)
	testing.expect_value(t, idx, 0)
}

@(test)
gamepad_button_index_out_of_range :: proc(t: ^testing.T) {
	idx, ok := gamepad_button_index(sdl.GamepadButton(GAMEPAD_BUTTON_COUNT))
	testing.expect(t, !ok)
	testing.expect_value(t, idx, 0)

	idx, ok = gamepad_button_index(sdl.GamepadButton(GAMEPAD_BUTTON_COUNT + 8))
	testing.expect(t, !ok)
	testing.expect_value(t, idx, 0)
}

@(test)
gamepad_button_index_all_named_buttons :: proc(t: ^testing.T) {
	named := []sdl.GamepadButton {
		.SOUTH,
		.EAST,
		.WEST,
		.NORTH,
		.BACK,
		.GUIDE,
		.START,
		.LEFT_STICK,
		.RIGHT_STICK,
		.LEFT_SHOULDER,
		.RIGHT_SHOULDER,
		.DPAD_UP,
		.DPAD_DOWN,
		.DPAD_LEFT,
		.DPAD_RIGHT,
		.MISC1,
		.RIGHT_PADDLE1,
		.LEFT_PADDLE1,
		.RIGHT_PADDLE2,
		.LEFT_PADDLE2,
		.TOUCHPAD,
		.MISC2,
		.MISC3,
		.MISC4,
		.MISC5,
		.MISC6,
	}
	for button in named {
		idx, ok := gamepad_button_index(button)
		testing.expectf(t, ok, "button %v should be valid", button)
		testing.expect_value(t, idx, int(button))
		testing.expect(t, idx >= 0 && idx < GAMEPAD_BUTTON_COUNT)
	}
}

@(test)
gamepad_button_index_high_but_in_array_range :: proc(t: ^testing.T) {
	// SDL may grow the enum; values below GAMEPAD_BUTTON_COUNT still map.
	button := sdl.GamepadButton(GAMEPAD_BUTTON_COUNT - 1)
	idx, ok := gamepad_button_index(button)
	testing.expect(t, ok)
	testing.expect_value(t, idx, GAMEPAD_BUTTON_COUNT - 1)
}

// ---------------------------------------------------------------------------
// gamepad_apply_deadzone
// ---------------------------------------------------------------------------

@(test)
gamepad_apply_deadzone_inside_and_at_boundaries :: proc(t: ^testing.T) {
	gamepad_expect_deadzone(t, 0, 0)
	gamepad_expect_deadzone(t, GAMEPAD_DEADZONE * 0.5, 0)
	gamepad_expect_deadzone(t, -GAMEPAD_DEADZONE * 0.5, 0)
	gamepad_expect_deadzone(t, GAMEPAD_DEADZONE - 1e-6, 0)
	gamepad_expect_deadzone(t, -(GAMEPAD_DEADZONE - 1e-6), 0)

	// Exactly at deadzone: abs < deadzone is false, scaled magnitude is 0.
	gamepad_expect_deadzone(t, GAMEPAD_DEADZONE, 0)
	gamepad_expect_deadzone(t, -GAMEPAD_DEADZONE, 0)
}

@(test)
gamepad_apply_deadzone_rescales_outside :: proc(t: ^testing.T) {
	gamepad_expect_deadzone(t, 1, 1)
	gamepad_expect_deadzone(t, -1, -1)
	gamepad_expect_deadzone(t, 0.5, gamepad_deadzone_scaled(0.5))
	gamepad_expect_deadzone(t, -0.5, gamepad_deadzone_scaled(-0.5))
	gamepad_expect_deadzone(t, 0.2, gamepad_deadzone_scaled(0.2))
	gamepad_expect_deadzone(t, -0.2, gamepad_deadzone_scaled(-0.2))
	gamepad_expect_deadzone(t, 0.999, gamepad_deadzone_scaled(0.999))
}

@(test)
gamepad_apply_deadzone_preserves_sign_just_outside :: proc(t: ^testing.T) {
	pos := f32(GAMEPAD_DEADZONE + 0.01)
	neg := f32(-(GAMEPAD_DEADZONE + 0.01))
	got_pos := gamepad_apply_deadzone(pos)
	got_neg := gamepad_apply_deadzone(neg)
	testing.expect(t, got_pos > 0)
	testing.expect(t, got_neg < 0)
	expect_close(t, got_pos, -got_neg)
	expect_close(t, got_pos, gamepad_deadzone_scaled(pos))
}

// ---------------------------------------------------------------------------
// gamepad_clear_input
// ---------------------------------------------------------------------------

@(test)
gamepad_clear_input_zeros_all_fields :: proc(t: ^testing.T) {
	with_gamepad_env(
		t,
		proc(t: ^testing.T) {
			gamepad_fill_dirty_input()
			gamepad_clear_input()
			gamepad_expect_cleared(t)
		},
	)
}

// ---------------------------------------------------------------------------
// gamepad_set_axis
// ---------------------------------------------------------------------------

@(test)
gamepad_set_axis_sticks_apply_deadzone :: proc(t: ^testing.T) {
	with_gamepad_env(
		t,
		proc(t: ^testing.T) {
			gamepad_set_axis(.LEFTX, 32767)
			gamepad_set_axis(.LEFTY, -32767)
			gamepad_set_axis(.RIGHTX, 0)
			gamepad_set_axis(.RIGHTY, i16(2457)) // ~0.075 of full scale, inside deadzone

			expect_close(t, state.input.gamepad.left_stick_x, 1)
			expect_close(t, state.input.gamepad.left_stick_y, -1)
			expect_close(t, state.input.gamepad.right_stick_x, 0)
			expect_close(t, state.input.gamepad.right_stick_y, 0)

			half := i16(16384)
			gamepad_set_axis(.LEFTX, half)
			want := gamepad_apply_deadzone(f32(half) / 32767.0)
			expect_close(t, state.input.gamepad.left_stick_x, want)
		},
	)
}

@(test)
gamepad_set_axis_triggers_ignore_deadzone_and_clamp_non_positive :: proc(t: ^testing.T) {
	with_gamepad_env(
		t,
		proc(t: ^testing.T) {
			gamepad_set_axis(.LEFT_TRIGGER, 32767)
			gamepad_set_axis(.RIGHT_TRIGGER, 16384)
			expect_close(t, state.input.gamepad.left_trigger, 1)
			expect_close(t, state.input.gamepad.right_trigger, f32(16384) / 32767.0)

			// Triggers do not use deadzone scaling — small positive stays small.
			small := i16(100)
			gamepad_set_axis(.LEFT_TRIGGER, small)
			expect_close(t, state.input.gamepad.left_trigger, f32(small) / 32767.0)

			gamepad_set_axis(.LEFT_TRIGGER, 0)
			gamepad_set_axis(.RIGHT_TRIGGER, -1)
			expect_close(t, state.input.gamepad.left_trigger, 0)
			expect_close(t, state.input.gamepad.right_trigger, 0)
		},
	)
}

@(test)
gamepad_set_axis_unknown_axis_is_noop :: proc(t: ^testing.T) {
	with_gamepad_env(
		t,
		proc(t: ^testing.T) {
			state.input.gamepad.left_stick_x = 0.3
			state.input.gamepad.left_trigger = 0.4
			gamepad_set_axis(.INVALID, 32767)
			gamepad_set_axis(sdl.GamepadAxis(99), 32767)
			expect_close(t, state.input.gamepad.left_stick_x, 0.3)
			expect_close(t, state.input.gamepad.left_trigger, 0.4)
		},
	)
}

// ---------------------------------------------------------------------------
// gamepad_set_button
// ---------------------------------------------------------------------------

@(test)
gamepad_set_button_updates_array_and_clears :: proc(t: ^testing.T) {
	with_gamepad_env(
		t,
		proc(t: ^testing.T) {
			gamepad_set_button(.SOUTH, true)
			gamepad_set_button(.START, true)
			testing.expect(t, state.input.gamepad.buttons_down[int(sdl.GamepadButton.SOUTH)])
			testing.expect(t, state.input.gamepad.buttons_down[int(sdl.GamepadButton.START)])

			gamepad_set_button(.SOUTH, false)
			testing.expect(t, !state.input.gamepad.buttons_down[int(sdl.GamepadButton.SOUTH)])
			testing.expect(t, state.input.gamepad.buttons_down[int(sdl.GamepadButton.START)])
		},
	)
}

@(test)
gamepad_set_button_mirrors_dpad_booleans :: proc(t: ^testing.T) {
	with_gamepad_env(
		t,
		proc(t: ^testing.T) {
			gamepad_set_button(.DPAD_LEFT, true)
			gamepad_set_button(.DPAD_RIGHT, true)
			gamepad_set_button(.DPAD_UP, true)
			gamepad_set_button(.DPAD_DOWN, true)
			testing.expect(t, state.input.gamepad.dpad_left)
			testing.expect(t, state.input.gamepad.dpad_right)
			testing.expect(t, state.input.gamepad.dpad_up)
			testing.expect(t, state.input.gamepad.dpad_down)
			testing.expect(t, state.input.gamepad.buttons_down[int(sdl.GamepadButton.DPAD_LEFT)])
			testing.expect(t, state.input.gamepad.buttons_down[int(sdl.GamepadButton.DPAD_RIGHT)])
			testing.expect(t, state.input.gamepad.buttons_down[int(sdl.GamepadButton.DPAD_UP)])
			testing.expect(t, state.input.gamepad.buttons_down[int(sdl.GamepadButton.DPAD_DOWN)])

			gamepad_set_button(.DPAD_LEFT, false)
			gamepad_set_button(.DPAD_UP, false)
			testing.expect(t, !state.input.gamepad.dpad_left)
			testing.expect(t, state.input.gamepad.dpad_right)
			testing.expect(t, !state.input.gamepad.dpad_up)
			testing.expect(t, state.input.gamepad.dpad_down)
		},
	)
}

@(test)
gamepad_set_button_invalid_skips_array_leaves_dpad :: proc(t: ^testing.T) {
	with_gamepad_env(
		t,
		proc(t: ^testing.T) {
			state.input.gamepad.dpad_up = true
			gamepad_set_button(.INVALID, true)
			gamepad_set_button(sdl.GamepadButton(GAMEPAD_BUTTON_COUNT), true)
			for down in state.input.gamepad.buttons_down {
				testing.expect(t, !down)
			}
			testing.expect(t, state.input.gamepad.dpad_up)
		},
	)
}

@(test)
gamepad_set_button_non_dpad_does_not_touch_dpad_flags :: proc(t: ^testing.T) {
	with_gamepad_env(
		t,
		proc(t: ^testing.T) {
			state.input.gamepad.dpad_left = true
			gamepad_set_button(.NORTH, true)
			testing.expect(t, state.input.gamepad.dpad_left)
			testing.expect(t, state.input.gamepad.buttons_down[int(sdl.GamepadButton.NORTH)])
		},
	)
}

// ---------------------------------------------------------------------------
// gamepad_sync_from_device
// ---------------------------------------------------------------------------

@(test)
gamepad_sync_from_device_nil_is_noop :: proc(t: ^testing.T) {
	with_gamepad_env(
		t,
		proc(t: ^testing.T) {
			gamepad_fill_dirty_input()
			state.gamepad = nil
			gamepad_sync_from_device()
			testing.expect(t, state.input.gamepad.connected)
			expect_close(t, state.input.gamepad.left_stick_x, 0.5)
			testing.expect(t, state.input.gamepad.dpad_up)
		},
	)
}

@(test)
gamepad_sync_from_device_reads_stubbed_axes_and_buttons :: proc(t: ^testing.T) {
	with_gamepad_env(
		t,
		proc(t: ^testing.T) {
			test_hook_gamepad_override = true
			state.gamepad = GAMEPAD_TEST_STUB_HANDLE
			state.gamepad_instance_id = 42

			test_hook_gamepad_axes[int(sdl.GamepadAxis.LEFTX)] = 32767
			test_hook_gamepad_axes[int(sdl.GamepadAxis.LEFTY)] = -32767
			test_hook_gamepad_axes[int(sdl.GamepadAxis.RIGHTX)] = 0
			test_hook_gamepad_axes[int(sdl.GamepadAxis.RIGHTY)] = i16(3276) // ~0.1 of full scale, inside deadzone
			test_hook_gamepad_axes[int(sdl.GamepadAxis.LEFT_TRIGGER)] = 32767
			test_hook_gamepad_axes[int(sdl.GamepadAxis.RIGHT_TRIGGER)] = 0

			test_hook_gamepad_buttons[int(sdl.GamepadButton.SOUTH)] = true
			test_hook_gamepad_buttons[int(sdl.GamepadButton.DPAD_UP)] = true
			test_hook_gamepad_buttons[int(sdl.GamepadButton.DPAD_LEFT)] = true

			// Dirty prior input must be cleared then rebuilt from stub reads.
			gamepad_fill_dirty_input()
			gamepad_sync_from_device()

			testing.expect(t, state.input.gamepad.connected)
			expect_close(t, state.input.gamepad.left_stick_x, 1)
			expect_close(t, state.input.gamepad.left_stick_y, -1)
			expect_close(t, state.input.gamepad.right_stick_x, 0)
			expect_close(t, state.input.gamepad.right_stick_y, 0)
			expect_close(t, state.input.gamepad.left_trigger, 1)
			expect_close(t, state.input.gamepad.right_trigger, 0)
			testing.expect(t, state.input.gamepad.buttons_down[int(sdl.GamepadButton.SOUTH)])
			testing.expect(t, !state.input.gamepad.buttons_down[int(sdl.GamepadButton.EAST)])
			testing.expect(t, state.input.gamepad.dpad_up)
			testing.expect(t, state.input.gamepad.dpad_left)
			testing.expect(t, !state.input.gamepad.dpad_right)
			testing.expect(t, !state.input.gamepad.dpad_down)
		},
	)
}

// ---------------------------------------------------------------------------
// gamepad_open / gamepad_open_first_available / gamepad_close
// ---------------------------------------------------------------------------

@(test)
gamepad_open_skips_when_already_connected :: proc(t: ^testing.T) {
	with_gamepad_env(
		t,
		proc(t: ^testing.T) {
			test_hook_gamepad_override = true
			state.gamepad = GAMEPAD_TEST_STUB_HANDLE
			state.gamepad_instance_id = 7
			state.input.gamepad.connected = true

			gamepad_open(99)
			testing.expect_value(t, state.gamepad_instance_id, sdl.JoystickID(7))
			testing.expect(t, state.gamepad == GAMEPAD_TEST_STUB_HANDLE)
		},
	)
}

@(test)
gamepad_open_fail_leaves_disconnected :: proc(t: ^testing.T) {
	with_gamepad_env(
		t,
		proc(t: ^testing.T) {
			test_hook_gamepad_override = true
			test_hook_gamepad_open_fail = true
			gamepad_fill_dirty_input()

			gamepad_open(11)
			testing.expect(t, state.gamepad == nil)
			testing.expect_value(t, state.gamepad_instance_id, sdl.JoystickID(0))
			// Failure returns before sync/clear — prior input is unchanged.
			testing.expect(t, state.input.gamepad.connected)
			expect_close(t, state.input.gamepad.left_stick_x, 0.5)
		},
	)
}

@(test)
gamepad_open_success_syncs_stubbed_device :: proc(t: ^testing.T) {
	with_gamepad_env(
		t,
		proc(t: ^testing.T) {
			test_hook_gamepad_override = true
			test_hook_gamepad_axes[int(sdl.GamepadAxis.RIGHTX)] = 32767
			test_hook_gamepad_buttons[int(sdl.GamepadButton.EAST)] = true
			test_hook_gamepad_buttons[int(sdl.GamepadButton.DPAD_DOWN)] = true

			gamepad_open(55)
			testing.expect(t, state.gamepad == GAMEPAD_TEST_STUB_HANDLE)
			testing.expect_value(t, state.gamepad_instance_id, sdl.JoystickID(55))
			testing.expect(t, state.input.gamepad.connected)
			expect_close(t, state.input.gamepad.right_stick_x, 1)
			testing.expect(t, state.input.gamepad.buttons_down[int(sdl.GamepadButton.EAST)])
			testing.expect(t, state.input.gamepad.dpad_down)

			gamepad_close()
			testing.expect(t, test_hook_gamepad_close_called)
			testing.expect(t, state.gamepad == nil)
			testing.expect_value(t, state.gamepad_instance_id, sdl.JoystickID(0))
			gamepad_expect_cleared(t)
		},
	)
}

@(test)
gamepad_close_nil_is_noop :: proc(t: ^testing.T) {
	with_gamepad_env(
		t,
		proc(t: ^testing.T) {
			test_hook_gamepad_override = true
			gamepad_fill_dirty_input()
			state.gamepad = nil
			state.gamepad_instance_id = 0
			gamepad_close()
			testing.expect(t, !test_hook_gamepad_close_called)
			testing.expect(t, state.input.gamepad.connected)
		},
	)
}

@(test)
gamepad_open_first_available_skips_when_already_open :: proc(t: ^testing.T) {
	with_gamepad_env(
		t,
		proc(t: ^testing.T) {
			test_hook_gamepad_override = true
			state.gamepad = GAMEPAD_TEST_STUB_HANDLE
			state.gamepad_instance_id = 3
			test_hook_gamepad_ids_count = 2
			test_hook_gamepad_ids[0] = 100

			gamepad_open_first_available()
			testing.expect_value(t, state.gamepad_instance_id, sdl.JoystickID(3))
		},
	)
}

@(test)
gamepad_open_first_available_nil_ids_is_noop :: proc(t: ^testing.T) {
	with_gamepad_env(
		t,
		proc(t: ^testing.T) {
			test_hook_gamepad_override = true
			test_hook_gamepad_ids_nil = true
			test_hook_gamepad_ids_count = 2
			test_hook_gamepad_ids[0] = 9

			gamepad_open_first_available()
			testing.expect(t, state.gamepad == nil)
			testing.expect_value(t, state.gamepad_instance_id, sdl.JoystickID(0))
		},
	)
}

@(test)
gamepad_open_first_available_empty_or_negative_count_is_noop :: proc(t: ^testing.T) {
	with_gamepad_env(
		t,
		proc(t: ^testing.T) {
			test_hook_gamepad_override = true
			test_hook_gamepad_ids[0] = 9

			test_hook_gamepad_ids_count = 0
			gamepad_open_first_available()
			testing.expect(t, state.gamepad == nil)

			test_hook_gamepad_ids_count = -3
			gamepad_open_first_available()
			testing.expect(t, state.gamepad == nil)
		},
	)
}

@(test)
gamepad_open_first_available_opens_first_id :: proc(t: ^testing.T) {
	with_gamepad_env(
		t,
		proc(t: ^testing.T) {
			test_hook_gamepad_override = true
			test_hook_gamepad_ids_count = 2
			test_hook_gamepad_ids[0] = 21
			test_hook_gamepad_ids[1] = 22
			test_hook_gamepad_buttons[int(sdl.GamepadButton.WEST)] = true

			gamepad_open_first_available()
			testing.expect(t, state.gamepad == GAMEPAD_TEST_STUB_HANDLE)
			testing.expect_value(t, state.gamepad_instance_id, sdl.JoystickID(21))
			testing.expect(t, state.input.gamepad.connected)
			testing.expect(t, state.input.gamepad.buttons_down[int(sdl.GamepadButton.WEST)])

			gamepad_close()
			gamepad_expect_cleared(t)
		},
	)
}

@(test)
gamepad_open_first_available_open_fail_is_safe :: proc(t: ^testing.T) {
	with_gamepad_env(
		t,
		proc(t: ^testing.T) {
			test_hook_gamepad_override = true
			test_hook_gamepad_open_fail = true
			test_hook_gamepad_ids_count = 1
			test_hook_gamepad_ids[0] = 77

			gamepad_open_first_available()
			testing.expect(t, state.gamepad == nil)
			testing.expect_value(t, state.gamepad_instance_id, sdl.JoystickID(0))
			testing.expect(t, !state.input.gamepad.connected)
		},
	)
}

@(test)
gamepad_read_helpers_out_of_range_axis_returns_zero :: proc(t: ^testing.T) {
	with_gamepad_env(
		t,
		proc(t: ^testing.T) {
			test_hook_gamepad_override = true
			state.gamepad = GAMEPAD_TEST_STUB_HANDLE
			test_hook_gamepad_axes = {1, 2, 3, 4, 5, 6}

			// INVALID / out-of-range axes are skipped by sync; read helper itself returns 0.
			testing.expect_value(t, gamepad_read_axis(.INVALID), i16(0))
			testing.expect_value(t, gamepad_read_axis(sdl.GamepadAxis(99)), i16(0))
			testing.expect(t, !gamepad_read_button(.INVALID))
			testing.expect(t, !gamepad_read_button(sdl.GamepadButton(GAMEPAD_BUTTON_COUNT)))
		},
	)
}

@(test)
gamepad_close_then_reopen_works :: proc(t: ^testing.T) {
	with_gamepad_env(
		t,
		proc(t: ^testing.T) {
			test_hook_gamepad_override = true
			test_hook_gamepad_ids_count = 1
			test_hook_gamepad_ids[0] = 1
			gamepad_open_first_available()
			testing.expect(t, state.gamepad != nil)
			gamepad_close()
			testing.expect(t, state.gamepad == nil)

			test_hook_gamepad_close_called = false
			test_hook_gamepad_ids[0] = 2
			gamepad_open_first_available()
			testing.expect_value(t, state.gamepad_instance_id, sdl.JoystickID(2))
			gamepad_close()
			testing.expect(t, test_hook_gamepad_close_called)
		},
	)
}

// ---------------------------------------------------------------------------
// Real SDL paths (no hooks) — empty enumerate, open fail, optional hardware
// ---------------------------------------------------------------------------

@(test)
gamepad_open_bogus_id_without_override_fails_safely :: proc(t: ^testing.T) {
	with_engine_sdl_env(
		t,
		proc(t: ^testing.T) {
			gamepad_fill_dirty_input()
			gamepad_open(sdl.JoystickID(0x7fff_ffff))
			testing.expect(t, state.gamepad == nil)
			testing.expect_value(t, state.gamepad_instance_id, sdl.JoystickID(0))
			// Open failure must not clear prior input.
			testing.expect(t, state.input.gamepad.connected)
			expect_close(t, state.input.gamepad.left_stick_x, 0.5)
		},
	)
}

@(test)
gamepad_open_first_available_real_sdl_optional_device :: proc(t: ^testing.T) {
	with_engine_sdl_env(
		t,
		proc(t: ^testing.T) {
			// Exercises real GetGamepads / OpenGamepad / sync / CloseGamepad.
			gamepad_open_first_available()
			if state.gamepad == nil {
				testing.expect_value(t, state.gamepad_instance_id, sdl.JoystickID(0))
				testing.expect(t, !state.input.gamepad.connected)
				return
			}
			defer gamepad_close()

			testing.expect(t, state.input.gamepad.connected)
			testing.expect(t, state.gamepad_instance_id != 0)

			state.input.gamepad.left_stick_x = 0.9
			gamepad_sync_from_device()
			testing.expect(t, state.input.gamepad.connected)

			gamepad_close()
			testing.expect(t, state.gamepad == nil)
			gamepad_expect_cleared(t)

			// Second open after close still uses the real enumerate path.
			gamepad_open_first_available()
			if state.gamepad != nil {
				defer gamepad_close()
				testing.expect(t, state.input.gamepad.connected)
			}
		},
	)
}

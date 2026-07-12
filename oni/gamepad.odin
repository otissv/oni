package oni

import "core:c"
import "core:fmt"
import "core:math"
import sdl "vendor:sdl3"

GAMEPAD_DEADZONE :: 0.15

/*
Fake non-nil gamepad handle used only when test_hook_gamepad_override is set.
*/
@(private)
GAMEPAD_TEST_STUB_HANDLE := transmute(^sdl.Gamepad)uintptr(0xDEADBEEF)

/*
Maps an SDL gamepad button to a compact index, or rejects invalid buttons.
*/
gamepad_button_index :: proc(button: sdl.GamepadButton) -> (int, bool) {
	if button == .INVALID do return 0, false
	idx := int(button)
	if idx < 0 || idx >= GAMEPAD_BUTTON_COUNT do return 0, false
	return idx, true
}

/*
Applies the configured deadzone to a normalized stick axis value.
*/
gamepad_apply_deadzone :: proc(value: f32) -> f32 {
	if math.abs(value) < GAMEPAD_DEADZONE do return 0
	sign := value < 0 ? f32(-1) : f32(1)
	scaled := (math.abs(value) - GAMEPAD_DEADZONE) / (1 - GAMEPAD_DEADZONE)
	return sign * scaled
}

/*
Resets all gamepad fields in engine input state to zero/disconnected.
*/
gamepad_clear_input :: proc() {
	state.input.gamepad = {}
}

/*
Polls the open SDL gamepad and refreshes input state from hardware.
*/
gamepad_sync_from_device :: proc() {
	if state.gamepad == nil do return

	state.input.gamepad.connected = true
	gamepad_clear_input()
	state.input.gamepad.connected = true

	for axis in sdl.GamepadAxis {
		if axis == .INVALID do continue
		value := gamepad_read_axis(axis)
		gamepad_set_axis(axis, value)
	}

	for button in sdl.GamepadButton {
		if button == .INVALID do continue
		down := gamepad_read_button(button)
		gamepad_set_button(button, down)
	}
}

@(private)
gamepad_read_axis :: proc(axis: sdl.GamepadAxis) -> i16 {
	if test_hook_gamepad_override {
		idx := int(axis)
		if idx >= 0 && idx < len(test_hook_gamepad_axes) {
			return test_hook_gamepad_axes[idx]
		}
		return 0
	}
	return sdl.GetGamepadAxis(state.gamepad, axis)
}

@(private)
gamepad_read_button :: proc(button: sdl.GamepadButton) -> bool {
	if test_hook_gamepad_override {
		idx, ok := gamepad_button_index(button)
		if !ok do return false
		return test_hook_gamepad_buttons[idx]
	}
	return sdl.GetGamepadButton(state.gamepad, button)
}

/*
Opens the first enumerated SDL gamepad if none is connected.
*/
gamepad_open_first_available :: proc() {
	if state.gamepad != nil do return

	if test_hook_gamepad_override {
		if test_hook_gamepad_ids_nil || test_hook_gamepad_ids_count <= 0 do return
		gamepad_open(sdl.JoystickID(test_hook_gamepad_ids[0]))
		return
	}

	count: c.int
	ids := sdl.GetGamepads(&count)
	if ids == nil || count <= 0 do return
	defer sdl.free(ids)

	gamepad_open(ids[0])
}

/*
Opens a gamepad by SDL instance id and syncs initial axis/button state.
*/
gamepad_open :: proc(instance_id: sdl.JoystickID) {
	if state.gamepad != nil do return

	gamepad: ^sdl.Gamepad
	if test_hook_gamepad_override {
		if test_hook_gamepad_open_fail {
			gamepad = nil
		} else {
			gamepad = GAMEPAD_TEST_STUB_HANDLE
		}
	} else {
		gamepad = sdl.OpenGamepad(instance_id)
	}

	if gamepad == nil {
		fmt.eprintln("SDL_OpenGamepad failed:", sdl.GetError())
		return
	}

	state.gamepad = gamepad
	state.gamepad_instance_id = instance_id
	gamepad_sync_from_device()
}

/*
Closes the current gamepad, clears the SDL handle, and resets input.
*/
gamepad_close :: proc() {
	if state.gamepad == nil do return

	if test_hook_gamepad_override {
		test_hook_gamepad_close_called = true
	} else {
		sdl.CloseGamepad(state.gamepad)
	}
	state.gamepad = nil
	state.gamepad_instance_id = 0
	gamepad_clear_input()
}

/*
Normalizes and stores one SDL axis into engine gamepad input (sticks/triggers).
*/
gamepad_set_axis :: proc(axis: sdl.GamepadAxis, value: i16) {
	normalized := gamepad_apply_deadzone(f32(value) / 32767.0)

	#partial switch axis {
	case .LEFTX:
		state.input.gamepad.left_stick_x = normalized
	case .LEFTY:
		state.input.gamepad.left_stick_y = normalized
	case .RIGHTX:
		state.input.gamepad.right_stick_x = normalized
	case .RIGHTY:
		state.input.gamepad.right_stick_y = normalized
	case .LEFT_TRIGGER:
		state.input.gamepad.left_trigger = f32(value) / 32767.0 if value > 0 else 0
	case .RIGHT_TRIGGER:
		state.input.gamepad.right_trigger = f32(value) / 32767.0 if value > 0 else 0
	}
}

/*
Updates button-down array and mirrors D-pad booleans from SDL button state.
*/
gamepad_set_button :: proc(button: sdl.GamepadButton, down: bool) {
	idx, ok := gamepad_button_index(button)
	if ok {
		state.input.gamepad.buttons_down[idx] = down
	}

	#partial switch button {
	case .DPAD_LEFT:
		state.input.gamepad.dpad_left = down
	case .DPAD_RIGHT:
		state.input.gamepad.dpad_right = down
	case .DPAD_UP:
		state.input.gamepad.dpad_up = down
	case .DPAD_DOWN:
		state.input.gamepad.dpad_down = down
	}
}

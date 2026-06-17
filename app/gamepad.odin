package app

import "core:c"
import "core:fmt"
import "core:math"
import sdl "vendor:sdl3"

GAMEPAD_DEADZONE :: 0.15

gamepad_button_index :: proc(button: sdl.GamepadButton) -> (int, bool) {
	if button == .INVALID do return 0, false
	idx := int(button)
	if idx < 0 || idx >= GAMEPAD_BUTTON_COUNT do return 0, false
	return idx, true
}

gamepad_apply_deadzone :: proc(value: f32) -> f32 {
	if math.abs(value) < GAMEPAD_DEADZONE do return 0
	sign := value < 0 ? f32(-1) : f32(1)
	scaled := (math.abs(value) - GAMEPAD_DEADZONE) / (1 - GAMEPAD_DEADZONE)
	return sign * scaled
}

gamepad_clear_input :: proc() {
	g.input.gamepad = {}
}

gamepad_sync_from_device :: proc() {
	if g.gamepad == nil do return

	g.input.gamepad.connected = true
	gamepad_clear_input()
	g.input.gamepad.connected = true

	for axis in sdl.GamepadAxis {
		if axis == .INVALID do continue
		value := sdl.GetGamepadAxis(g.gamepad, axis)
		gamepad_set_axis(axis, value)
	}

	for button in sdl.GamepadButton {
		if button == .INVALID do continue
		down := sdl.GetGamepadButton(g.gamepad, button)
		gamepad_set_button(button, down)
	}
}

gamepad_open_first_available :: proc() {
	if g.gamepad != nil do return

	count: c.int
	ids := sdl.GetGamepads(&count)
	if ids == nil || count <= 0 do return
	defer sdl.free(ids)

	gamepad_open(ids[0])
}

gamepad_open :: proc(instance_id: sdl.JoystickID) {
	if g.gamepad != nil do return

	gamepad := sdl.OpenGamepad(instance_id)
	if gamepad == nil {
		fmt.eprintln("SDL_OpenGamepad failed:", sdl.GetError())
		return
	}

	g.gamepad = gamepad
	g.gamepad_instance_id = instance_id
	gamepad_sync_from_device()
}

gamepad_close :: proc() {
	if g.gamepad == nil do return

	sdl.CloseGamepad(g.gamepad)
	g.gamepad = nil
	g.gamepad_instance_id = 0
	gamepad_clear_input()
}

gamepad_set_axis :: proc(axis: sdl.GamepadAxis, value: i16) {
	normalized := gamepad_apply_deadzone(f32(value) / 32767.0)

	#partial switch axis {
	case .LEFTX:
		g.input.gamepad.left_stick_x = normalized
	case .LEFTY:
		g.input.gamepad.left_stick_y = normalized
	case .RIGHTX:
		g.input.gamepad.right_stick_x = normalized
	case .RIGHTY:
		g.input.gamepad.right_stick_y = normalized
	case .LEFT_TRIGGER:
		g.input.gamepad.left_trigger = f32(value) / 32767.0 if value > 0 else 0
	case .RIGHT_TRIGGER:
		g.input.gamepad.right_trigger = f32(value) / 32767.0 if value > 0 else 0
	}
}

gamepad_set_button :: proc(button: sdl.GamepadButton, down: bool) {
	idx, ok := gamepad_button_index(button)
	if ok {
		g.input.gamepad.buttons_down[idx] = down
	}

	#partial switch button {
	case .DPAD_LEFT:
		g.input.gamepad.dpad_left = down
	case .DPAD_RIGHT:
		g.input.gamepad.dpad_right = down
	case .DPAD_UP:
		g.input.gamepad.dpad_up = down
	case .DPAD_DOWN:
		g.input.gamepad.dpad_down = down
	}
}

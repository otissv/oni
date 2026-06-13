package game

import "core:fmt"
import sdl "vendor:sdl3"

GAMEPAD_DEADZONE :: 8000

clear_gamepad_input :: proc() {
	g.input.dpad_left = false
	g.input.dpad_right = false
	g.input.dpad_up = false
	g.input.dpad_down = false
	g.input.stick_left = false
	g.input.stick_right = false
	g.input.stick_up = false
	g.input.stick_down = false
}

open_gamepad :: proc(instance_id: sdl.JoystickID) {
	if g.gamepad != nil {
		return
	}

	gamepad := sdl.OpenGamepad(instance_id)
	if gamepad == nil {
		fmt.eprintln("SDL_OpenGamepad failed:", sdl.GetError())
		return
	}

	g.gamepad = gamepad
	g.gamepad_instance_id = instance_id
	fmt.println("Gamepad connected")
}

close_gamepad :: proc() {
	if g.gamepad != nil {
		sdl.CloseGamepad(g.gamepad)
		g.gamepad = nil
		g.gamepad_instance_id = 0
		clear_gamepad_input()
		fmt.println("Gamepad disconnected")
	}
}

set_gamepad_axis :: proc(axis: sdl.GamepadAxis, value: i16) {
	v := int(value)

	#partial switch axis {
	case .LEFTX:
		g.input.stick_left = v < -GAMEPAD_DEADZONE
		g.input.stick_right = v > GAMEPAD_DEADZONE
	case .LEFTY:
		g.input.stick_up = v < -GAMEPAD_DEADZONE
		g.input.stick_down = v > GAMEPAD_DEADZONE
	}
}

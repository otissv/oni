package oni

import "core:c"
import "core:fmt"
import sdl "vendor:sdl3"

MAX_FRAME_TIME :: 0.25

Window_Config :: struct {
	title:                 cstring,
	width, height:         i32,
	min_width, min_height: i32,
}

dpi_sync :: proc() {
	if state.window == nil do return

	log_w, log_h: i32
	if !sdl.GetWindowSize(state.window, &log_w, &log_h) {
		fmt.eprintln("SDL_GetWindowSize failed:", sdl.GetError())
		state.can_render = false
		return
	}

	px_w, px_h: c.int
	if !sdl.GetWindowSizeInPixels(state.window, &px_w, &px_h) {
		fmt.eprintln("SDL_GetWindowSizeInPixels failed:", sdl.GetError())
		state.can_render = false
		return
	}

	state.dpi.logical_w = log_w
	state.dpi.logical_h = log_h
	state.dpi.drawable_w = i32(px_w)
	state.dpi.drawable_h = i32(px_h)
	state.dpi.scale = log_w > 0 ? f32(px_w) / f32(log_w) : 1
	state.can_render = px_w > 0 && px_h > 0
	gpu_update_projection(state.dpi)
}

input_begin_frame :: proc() {
	state.input.mouse_wheel_x = 0
	state.input.mouse_wheel_y = 0
	clear(&state.input.text_input)
}

input_update_modifiers :: proc(mod: sdl.Keymod) {
	state.input.modifiers = {
		shift = (mod & sdl.KMOD_SHIFT) != {},
		ctrl  = (mod & sdl.KMOD_CTRL) != {},
		alt   = (mod & sdl.KMOD_ALT) != {},
		super = (mod & sdl.KMOD_GUI) != {},
	}
}

input_clear_keyboard_mouse :: proc() {
	state.input.keys_down = {}
	state.input.mouse_left = false
	state.input.mouse_right = false
	state.input.mouse_middle = false
	state.input.modifiers = {}
	clear(&state.input.text_input)
}

input_set_mouse_position :: proc(px_x, px_y: f32) {
	logical := screen_to_logical(px_x, px_y, state.dpi)
	state.input.mouse_x = logical.x
	state.input.mouse_y = logical.y
}

input_mouse_screen :: proc() -> Vec2 {
	if state == nil do return {}
	return {state.input.mouse_x, state.input.mouse_y}
}

input_mouse_world :: proc() -> Vec2 {
	return view_screen_to_world(input_mouse_screen())
}

set_fullscreen :: proc(fullscreen: bool) -> bool {
	if state.window == nil do return false

	if !sdl.SetWindowFullscreen(state.window, fullscreen) {
		fmt.eprintln("SDL_SetWindowFullscreen failed:", sdl.GetError())
		return false
	}

	state.fullscreen = fullscreen
	return true
}

toggle_fullscreen :: proc() {
	set_fullscreen(!state.fullscreen)
}

frame_time :: proc() -> f64 {
	current_counter := sdl.GetPerformanceCounter()
	elapsed := f64(current_counter - state.last_counter) / f64(state.perf_frequency)
	state.last_counter = current_counter

	if elapsed > MAX_FRAME_TIME {
		elapsed = MAX_FRAME_TIME
	}

	return elapsed
}

poll_events :: proc() {
	event: sdl.Event

	for sdl.PollEvent(&event) {
		#partial switch event.type {
		case .QUIT:
			state.running = false

		case .WINDOW_CLOSE_REQUESTED:
			state.running = false

		case .KEY_DOWN:
			if event.key.repeat do break

			input_update_modifiers(event.key.mod)

			scancode := int(event.key.scancode)
			if scancode >= 0 && scancode < KEY_COUNT {
				state.input.keys_down[scancode] = true
			}

			#partial switch event.key.scancode {
			case .ESCAPE:
				state.running = false
			case .F5:
				state.force_reload = true
			case .F6:
				state.force_restart = true
			case .F11:
				toggle_fullscreen()
			case .EQUALS, .KP_PLUS:
				if state.input.modifiers.ctrl {
					view_zoom_in_screen(input_mouse_screen())
				}
			case .MINUS, .KP_MINUS:
				if state.input.modifiers.ctrl {
					view_zoom_out_screen(input_mouse_screen())
				}
			case ._0, .KP_0:
				if state.input.modifiers.ctrl {
					view_reset()
				}
			}

			if event.key.key == sdl.K_F5 {
				state.force_reload = true
			} else if event.key.key == sdl.K_F6 {
				state.force_restart = true
			}

		case .KEY_UP:
			input_update_modifiers(event.key.mod)

			scancode := int(event.key.scancode)
			if scancode >= 0 && scancode < KEY_COUNT {
				state.input.keys_down[scancode] = false
			}

		case .TEXT_INPUT:
			if event.text.text != nil {
				append_elem_string(&state.input.text_input, string(event.text.text))
			}

		case .MOUSE_MOTION:
			prev_x := state.input.mouse_x
			prev_y := state.input.mouse_y
			input_set_mouse_position(event.motion.x, event.motion.y)

			if state.input.mouse_middle ||
			   (state.input.mouse_left && state.input.modifiers.alt) {
				view_pan_by({
					state.input.mouse_x - prev_x,
					state.input.mouse_y - prev_y,
				})
			}

		case .MOUSE_BUTTON_DOWN:
			input_set_mouse_position(event.button.x, event.button.y)

			switch event.button.button {
			case sdl.BUTTON_LEFT:
				state.input.mouse_left = true
			case sdl.BUTTON_RIGHT:
				state.input.mouse_right = true
			case sdl.BUTTON_MIDDLE:
				state.input.mouse_middle = true
			}

		case .MOUSE_BUTTON_UP:
			input_set_mouse_position(event.button.x, event.button.y)

			switch event.button.button {
			case sdl.BUTTON_LEFT:
				state.input.mouse_left = false
			case sdl.BUTTON_RIGHT:
				state.input.mouse_right = false
			case sdl.BUTTON_MIDDLE:
				state.input.mouse_middle = false
			}

		case .MOUSE_WHEEL:
			input_set_mouse_position(event.wheel.mouse_x, event.wheel.mouse_y)
			state.input.mouse_wheel_x += event.wheel.x
			state.input.mouse_wheel_y += event.wheel.y

		case .GAMEPAD_ADDED:
			gamepad_open(event.gdevice.which)

		case .GAMEPAD_REMOVED:
			if event.gdevice.which == state.gamepad_instance_id {
				gamepad_close()
			}

		case .GAMEPAD_AXIS_MOTION:
			if event.gaxis.which == state.gamepad_instance_id {
				gamepad_set_axis(sdl.GamepadAxis(event.gaxis.axis), event.gaxis.value)
			}

		case .GAMEPAD_BUTTON_DOWN:
			if event.gbutton.which == state.gamepad_instance_id {
				button := sdl.GamepadButton(event.gbutton.button)
				gamepad_set_button(button, true)

				if button == .START {
					toggle_fullscreen()
				}
			}

		case .GAMEPAD_BUTTON_UP:
			if event.gbutton.which == state.gamepad_instance_id {
				gamepad_set_button(sdl.GamepadButton(event.gbutton.button), false)
			}

		case .WINDOW_RESIZED, .WINDOW_PIXEL_SIZE_CHANGED, .WINDOW_DISPLAY_SCALE_CHANGED:
			dpi_sync()

		case .WINDOW_ENTER_FULLSCREEN:
			state.fullscreen = true

		case .WINDOW_LEAVE_FULLSCREEN:
			state.fullscreen = false

		case .WINDOW_FOCUS_LOST:
			input_clear_keyboard_mouse()
		}
	}

	poll_reload_keys()
}

poll_reload_keys :: proc() {
	kb := sdl.GetKeyboardState(nil)
	if kb == nil do return

	f5_down := kb[int(sdl.Scancode.F5)]
	f6_down := kb[int(sdl.Scancode.F6)]

	if f5_down && !state.reload_keys_prev.f5 {
		state.force_reload = true
	}
	if f6_down && !state.reload_keys_prev.f6 {
		state.force_restart = true
	}

	state.reload_keys_prev.f5 = f5_down
	state.reload_keys_prev.f6 = f6_down
}

reset_input_state :: proc() {
	gamepad := state.gamepad
	gamepad_instance_id := state.gamepad_instance_id

	state.input = {}
	state.force_reload = false
	state.force_restart = false
	state.reload_keys_prev = {}
	state.running = true

	state.gamepad = gamepad
	state.gamepad_instance_id = gamepad_instance_id

	if state.gamepad != nil {
		gamepad_sync_from_device()
	}
}

create_window :: proc(config: Window_Config) -> bool {
	if !sdl.Init({.VIDEO, .GAMEPAD}) {
		fmt.eprintln("SDL_Init failed:", sdl.GetError())
		return false
	}

	state.window = sdl.CreateWindow(
		config.title,
		config.width,
		config.height,
		sdl.WINDOW_RESIZABLE | sdl.WINDOW_HIGH_PIXEL_DENSITY,
	)
	if state.window == nil {
		fmt.eprintln("SDL_CreateWindow failed:", sdl.GetError())
		sdl.Quit()
		return false
	}

	state.gpu = sdl.CreateGPUDevice({.SPIRV}, true, nil)
	if state.gpu == nil {
		fmt.eprintln("SDL_CreateGPUDevice failed:", sdl.GetError())
		sdl.DestroyWindow(state.window)
		state.window = nil
		sdl.Quit()
		return false
	}

	if !sdl.ClaimWindowForGPUDevice(state.gpu, state.window) {
		fmt.eprintln("SDL_ClaimWindowForGPUDevice failed:", sdl.GetError())
		sdl.DestroyGPUDevice(state.gpu)
		state.gpu = nil
		sdl.DestroyWindow(state.window)
		state.window = nil
		sdl.Quit()
		return false
	}

	if !sdl.SetGPUSwapchainParameters(state.gpu, state.window, .SDR, .VSYNC) {
		fmt.eprintln("SDL_SetGPUSwapchainParameters failed:", sdl.GetError())
		sdl.DestroyGPUDevice(state.gpu)
		state.gpu = nil
		sdl.DestroyWindow(state.window)
		state.window = nil
		sdl.Quit()
		return false
	}

	state.perf_frequency = sdl.GetPerformanceFrequency()
	state.last_counter = sdl.GetPerformanceCounter()
	state.fullscreen = false
	state.view = view_default()

	sdl.SetWindowMinimumSize(state.window, config.min_width, config.min_height)
	dpi_sync()
	sdl.ShowWindow(state.window)
	gamepad_open_first_available()

	return true
}

init_window :: proc(config: Window_Config) -> bool {
	if state.window != nil do return true
	return create_window(config)
}

init :: proc() -> bool {
	if state == nil || state.window == nil do return false

	if state.view.zoom <= 0 {
		state.view = view_default()
	}

	gpu_init()
	if !font_init() {
		log_error("font_init failed")
		return false
	}
	ui_init()
	reset_input_state()
	dpi_sync()
	return true
}

shutdown :: proc() {
	if state == nil do return

	gamepad_close()
	ui_shutdown()
	font_shutdown()
	assets_shutdown()
	gpu_destroy()

	if state.gpu != nil {
		sdl.DestroyGPUDevice(state.gpu)
		state.gpu = nil
	}

	if state.window != nil {
		sdl.DestroyWindow(state.window)
		state.window = nil
	}

	delete(state.input.text_input)
	sdl.Quit()
}

should_run :: proc() -> bool {
	return state != nil && state.running
}

can_render :: proc() -> bool {
	return state != nil && state.can_render
}

begin_frame :: proc() {
	ui_begin_frame()
}

end_frame :: proc() {
	ui_end_frame()
}

on_hot_reload :: proc() {
	gpu_reload()
	dpi_sync()
}

peek_force_reload :: proc() -> bool {
	if state == nil do return false
	return state.force_reload
}

peek_force_restart :: proc() -> bool {
	if state == nil do return false
	return state.force_restart
}

consume_force_reload :: proc() {
	if state != nil do state.force_reload = false
}

consume_force_restart :: proc() {
	if state != nil do state.force_restart = false
}

take_force_reload :: proc() -> bool {
	if state == nil do return false
	reload := state.force_reload
	state.force_reload = false
	return reload
}

take_force_restart :: proc() -> bool {
	if state == nil do return false
	restart := state.force_restart
	state.force_restart = false
	return restart
}

copy_state_fields :: proc(dst: ^State, src: ^State) {
	dst.window = src.window
	dst.gpu = src.gpu
	dst.gpu_state = src.gpu_state
	dst.assets = src.assets
	dst.textures = src.textures
	dst.fonts = src.fonts
	dst.dpi = src.dpi
	dst.view = src.view
	dst.can_render = src.can_render
	dst.fullscreen = src.fullscreen
	dst.perf_frequency = src.perf_frequency
	dst.last_counter = src.last_counter
	dst.running = src.running
	dst.ui = src.ui
	dst.gamepad = src.gamepad
	dst.gamepad_instance_id = src.gamepad_instance_id
}

release_input_allocations :: proc(s: ^State) {
	delete(s.input.text_input)
}

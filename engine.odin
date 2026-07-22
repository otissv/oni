package oni

import "core:c"
import "core:fmt"
import sdl "vendor:sdl3"

MAX_FRAME_TIME :: 0.25

/*
Initial SDL window title, size, and minimum dimensions for app startup.
*/
Window_Config :: struct {
	title:                 cstring,
	width, height:         i32,
	min_width, min_height: i32,
}

/*
Refreshes logical and drawable window size, DPI scale, and can_render.

Updates the GPU projection matrix; call after resize, display-scale change,
or hot reload when the window handle is valid.
*/
dpi_sync :: proc() {
	if state.window == nil do return

	log_w, log_h: i32
	if test_hook_dpi_sync_fail_get_size || !sdl.GetWindowSize(state.window, &log_w, &log_h) {
		fmt.eprintln("SDL_GetWindowSize failed:", sdl.GetError())
		state.can_render = false
		return
	}

	px_w, px_h: c.int
	if test_hook_dpi_sync_fail_get_pixels ||
	   !sdl.GetWindowSizeInPixels(state.window, &px_w, &px_h) {
		fmt.eprintln("SDL_GetWindowSizeInPixels failed:", sdl.GetError())
		state.can_render = false
		return
	}

	if test_hook_dpi_sync_force_logical_w_zero {
		log_w = 0
	}
	if test_hook_dpi_sync_force_drawable_zero {
		px_w = 0
		px_h = 0
	}

	prev_scale := state.dpi.scale
	state.dpi.logical_w = log_w
	state.dpi.logical_h = log_h
	state.dpi.drawable_w = i32(px_w)
	state.dpi.drawable_h = i32(px_h)
	state.dpi.scale = log_w > 0 ? f32(px_w) / f32(log_w) : 1
	if prev_scale != state.dpi.scale {
		font_shape_cache_clear()
	}
	state.can_render = px_w > 0 && px_h > 0
	gpu_update_projection(state.dpi)
}

/*
Clears per-frame transient input before polling events.

Resets mouse wheel deltas and the text-input buffer; call at frame start.
*/
input_begin_frame :: proc() {
	state.input.mouse_wheel_x = 0
	state.input.mouse_wheel_y = 0
	clear(&state.input.text_input)
}

/*
Updates modifier-key flags from an SDL keymod bitmask.

Called from key down/up handlers so ctrl/shift/alt/super stay in sync.
*/
input_update_modifiers :: proc(mod: sdl.Keymod) {
	state.input.modifiers = {
		shift = (mod & sdl.KMOD_SHIFT) != {},
		ctrl  = (mod & sdl.KMOD_CTRL) != {},
		alt   = (mod & sdl.KMOD_ALT) != {},
		super = (mod & sdl.KMOD_GUI) != {},
	}
}

/*
Clears keyboard and mouse button state without touching wheel or gamepad.

Used when the window loses focus so keys are not stuck down.
*/
input_clear_keyboard_mouse :: proc() {
	state.input.keys_down = {}
	state.input.mouse_left = false
	state.input.mouse_right = false
	state.input.mouse_middle = false
	state.input.modifiers = {}
	clear(&state.input.text_input)
	input_clear_ime()
}

/*
Stores mouse position in logical screen space from pixel coordinates.

Converts through dpi_sync scale; used by SDL motion, button, and wheel events.
*/
input_set_mouse_position :: proc(px_x, px_y: f32) {
	logical := screen_to_logical(px_x, px_y, state.dpi)
	state.input.mouse_x = logical.x
	state.input.mouse_y = logical.y
}

/*
Returns the current mouse position in logical screen space.

Safe when state is nil; returns zero in that case.
*/
input_mouse_screen :: proc() -> Vec2 {
	if state == nil do return {}
	return {state.input.mouse_x, state.input.mouse_y}
}

/*
Returns the current mouse position in world/view coordinates.

Applies the active view transform to the logical screen position.
*/
input_mouse_world :: proc() -> Vec2 {
	return view_screen_to_world(input_mouse_screen())
}

/*
Sets SDL window fullscreen mode and updates state.fullscreen.

Returns false if the window is nil or SDL rejects the request.
*/
set_fullscreen :: proc(fullscreen: bool) -> bool {
	if state.window == nil do return false

	if test_hook_set_fullscreen_fail || !sdl.SetWindowFullscreen(state.window, fullscreen) {
		fmt.eprintln("SDL_SetWindowFullscreen failed:", sdl.GetError())
		return false
	}

	state.fullscreen = fullscreen
	return true
}

/*
Toggles between windowed and fullscreen display.

Delegates to set_fullscreen with the inverted current flag.
*/
toggle_fullscreen :: proc() {
	set_fullscreen(!state.fullscreen)
}

/*
Returns elapsed seconds since the previous call, capped at MAX_FRAME_TIME.

Advances last_counter; call once per frame for stable dt.
*/
frame_time :: proc() -> f64 {
	current_counter := sdl.GetPerformanceCounter()
	elapsed := f64(current_counter - state.last_counter) / f64(state.perf_frequency)
	state.last_counter = current_counter

	if elapsed > MAX_FRAME_TIME {
		elapsed = MAX_FRAME_TIME
	}

	return elapsed
}

/*
Polls SDL events and updates input, view, gamepad, and running state.

Handles quit, keyboard input, mouse pan, window resize, and gamepad
connect/disconnect. App/view/host shortcuts are dispatched via shortcut_process.
*/
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
			case .F5:
				state.input.keys_down[int(sdl.Scancode.F5)] = true
			case .F6:
				state.input.keys_down[int(sdl.Scancode.F6)] = true
			}

			// Keycode fallback when scancode is unavailable (host reload chords).
			if event.key.key == sdl.K_F5 {
				state.input.keys_down[int(sdl.Scancode.F5)] = true
			} else if event.key.key == sdl.K_F6 {
				state.input.keys_down[int(sdl.Scancode.F6)] = true
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

		case .TEXT_EDITING:
			if event.edit.text != nil {
				input_set_ime_text(string(event.edit.text))
				state.input.ime_cursor = int(event.edit.start)
				state.input.ime_length = int(event.edit.length)
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

/*
Edge-detects F5/F6 held on the keyboard into key state for host reload shortcuts.

Catches keys missed by KEY_DOWN when focus or timing differs; updates
reload_keys_prev for the next frame. Actions fire via shortcut_process.
*/
poll_reload_keys :: proc() {
	f5_down, f6_down: bool
	if test_hook_keyboard_override {
		f5_down = test_hook_keyboard_f5
		f6_down = test_hook_keyboard_f6
	} else {
		kb := sdl.GetKeyboardState(nil)
		if kb == nil do return
		f5_down = kb[int(sdl.Scancode.F5)]
		f6_down = kb[int(sdl.Scancode.F6)]
	}

	if f5_down && !state.reload_keys_prev.f5 {
		state.input.keys_down[int(sdl.Scancode.F5)] = true
	}
	if f6_down && !state.reload_keys_prev.f6 {
		state.input.keys_down[int(sdl.Scancode.F6)] = true
	}

	state.reload_keys_prev.f5 = f5_down
	state.reload_keys_prev.f6 = f6_down
}

/*
Clears input and hot-reload flags while preserving the open gamepad.

Resets running to true; re-syncs gamepad state if a device is connected.
Call after realloc, reset, or when app state is rebuilt.
*/
reset_input_state :: proc() {
	gamepad := state.gamepad
	gamepad_instance_id := state.gamepad_instance_id

	delete(state.input.text_input)
	input_clear_ime()
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

/*
Initializes SDL, creates the window, GPU device, and default view.

Claims the window for the GPU, sets swapchain and minimum size, and opens
the first available gamepad. On failure, tears down partial resources.
*/
create_window :: proc(config: Window_Config) -> bool {
	if test_hook_create_window_fail == .Init || !sdl.Init({.VIDEO, .GAMEPAD}) {
		fmt.eprintln("SDL_Init failed:", sdl.GetError())
		return false
	}

	state.window = sdl.CreateWindow(
		config.title,
		config.width,
		config.height,
		sdl.WINDOW_RESIZABLE | sdl.WINDOW_HIGH_PIXEL_DENSITY,
	)
	if test_hook_create_window_fail == .Window && state.window != nil {
		sdl.DestroyWindow(state.window)
		state.window = nil
	}
	if state.window == nil {
		fmt.eprintln("SDL_CreateWindow failed:", sdl.GetError())
		sdl.Quit()
		return false
	}

	state.gpu = sdl.CreateGPUDevice({.SPIRV}, true, nil)
	if test_hook_create_window_fail == .Gpu && state.gpu != nil {
		sdl.DestroyGPUDevice(state.gpu)
		state.gpu = nil
	}
	if state.gpu == nil {
		fmt.eprintln("SDL_CreateGPUDevice failed:", sdl.GetError())
		sdl.DestroyWindow(state.window)
		state.window = nil
		sdl.Quit()
		return false
	}

	claimed := sdl.ClaimWindowForGPUDevice(state.gpu, state.window)
	if test_hook_create_window_fail == .Claim {
		claimed = false
	}
	if !claimed {
		fmt.eprintln("SDL_ClaimWindowForGPUDevice failed:", sdl.GetError())
		sdl.DestroyGPUDevice(state.gpu)
		state.gpu = nil
		sdl.DestroyWindow(state.window)
		state.window = nil
		sdl.Quit()
		return false
	}

	swapchain_ok := sdl.SetGPUSwapchainParameters(state.gpu, state.window, .SDR, .VSYNC)
	if test_hook_create_window_fail == .Swapchain {
		swapchain_ok = false
	}
	if !swapchain_ok {
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

/*
Creates the SDL window if one does not already exist.

Idempotent; returns true when state.window is already set.
*/
init_window :: proc(config: Window_Config) -> bool {
	if state.window != nil do return true
	return create_window(config)
}

/*
Initializes GPU pipeline, fonts, UI, and input after the window exists.

Resets view if invalid, then runs gpu_init, font_init, and ui_init. Returns
false if font_init fails.
*/
init :: proc() -> bool {
	if state == nil || state.window == nil do return false

	if state.view.zoom <= 0 {
		state.view = view_default()
	}

	gpu_init()
	if !font_init() {
		log_error("font_init failed")
		assets_shutdown()
		gpu_destroy()
		return false
	}
	ui_init()
	shortcut_install_defaults()
	reset_input_state()
	dpi_sync()
	return true
}

/*
Tears down gamepad, UI, fonts, assets, GPU, window, and SDL.

Frees input text buffer and nulls window/gpu handles; call on app exit.
*/
shutdown :: proc() {
	if state == nil do return

	gamepad_close()
	ui_shutdown()
	error_shutdown()
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

/*
Returns whether the main loop should continue.

False when state is nil or running was cleared (quit, failed init, etc.).
*/
should_run :: proc() -> bool {
	return state != nil && state.running
}

/*
Returns whether the window has a non-zero drawable size and can present.

False when state is nil or dpi_sync disabled rendering (e.g. minimized).
*/
can_render :: proc() -> bool {
	return state != nil && state.can_render
}

/*
Starts a UI frame by resetting layout and widget pass state.

Thin wrapper around ui_begin_frame for apps that split tick and draw.
*/
begin_frame :: proc() {
	ui_begin_frame()
}

/*
Ends a UI frame after layout and widget recording.

Thin wrapper around ui_end_frame; call before present_frame.
*/
end_frame :: proc() {
	ui_end_frame()
}

/*
Refreshes GPU resources after a hot library reload.

Reloads shaders/pipeline and re-syncs DPI; SDL window and device persist.
*/
on_hot_reload :: proc() {
	gpu_reload()
	dpi_sync()
	shortcut_rebind_builtin_actions()
}

/*
Returns whether F5 hot reload was requested without clearing the flag.

For host reloaders that peek each frame and consume after a successful swap.
*/
peek_force_reload :: proc() -> bool {
	if state == nil do return false
	return state.force_reload
}

/*
Returns whether F6 full restart was requested without clearing the flag.

For host reloaders that peek each frame and consume after handling restart.
*/
peek_force_restart :: proc() -> bool {
	if state == nil do return false
	return state.force_restart
}

/*
Clears the force-reload flag after the host completes a library swap.

Does nothing when state is nil.
*/
consume_force_reload :: proc() {
	if state != nil do state.force_reload = false
}

/*
Clears the force-restart flag after the host handles a full restart.

Does nothing when state is nil.
*/
consume_force_restart :: proc() {
	if state != nil do state.force_restart = false
}

/*
Returns and clears the force-reload flag in one call.

Use from app_force_reload when the app owns reload timing.
*/
take_force_reload :: proc() -> bool {
	if state == nil do return false
	reload := state.force_reload
	state.force_reload = false
	return reload
}

/*
Returns and clears the force-restart flag in one call.

Use from app_force_restart when the app owns restart timing.
*/
take_force_restart :: proc() -> bool {
	if state == nil do return false
	restart := state.force_restart
	state.force_restart = false
	return restart
}

/*
Copies live engine fields from src into dst for persistent-state migration.

Transfers SDL/GPU handles, assets, view, UI, and gamepad; does not copy
input heap data (see release_input_allocations).
*/
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
	dst.shortcuts = src.shortcuts
	dst.errors = src.errors
	dst.gamepad = src.gamepad
	dst.gamepad_instance_id = src.gamepad_instance_id
}

/*
Frees heap allocations owned by src input state before discarding old memory.

Call on the source State during realloc after fields are copied to dst.
*/
release_input_allocations :: proc(s: ^State) {
	delete(s.input.text_input)
}

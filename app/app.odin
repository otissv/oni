package app

import "core:c"
import "core:fmt"
import "core:mem"
import sdl "vendor:sdl3"

WINDOW_WIDTH :: 1280
WINDOW_HEIGHT :: 720
WINDOW_TITLE :: "Odin + SDL3"

MIN_WINDOW_W :: 320
MIN_WINDOW_H :: 180

MAX_FRAME_TIME :: 0.25

App_State :: struct {
	window:              ^sdl.Window,
	gpu:                 ^sdl.GPUDevice,
	gpu_state:           GPU_State,
	assets:              Asset_Cache,
	textures:            Texture_State,
	fonts:               Font_State,
	running:             bool,
	input:               Input_State,
	dpi:                 Dpi_Info,
	perf_frequency:      u64,
	last_counter:        u64,
	fullscreen:          bool,
	can_render:          bool,
	theme:               Theme,
	ui:                  UI_State,
	gamepad:             ^sdl.Gamepad,
	gamepad_instance_id: sdl.JoystickID,
	force_reload:        bool,
	force_restart:       bool,
}

g: ^App_State

dpi_sync :: proc() {
	if g.window == nil do return

	log_w, log_h: i32
	if !sdl.GetWindowSize(g.window, &log_w, &log_h) {
		fmt.eprintln("SDL_GetWindowSize failed:", sdl.GetError())
		g.can_render = false
		return
	}

	px_w, px_h: c.int
	if !sdl.GetWindowSizeInPixels(g.window, &px_w, &px_h) {
		fmt.eprintln("SDL_GetWindowSizeInPixels failed:", sdl.GetError())
		g.can_render = false
		return
	}

	g.dpi.logical_w = log_w
	g.dpi.logical_h = log_h
	g.dpi.drawable_w = i32(px_w)
	g.dpi.drawable_h = i32(px_h)
	g.dpi.scale = log_w > 0 ? f32(px_w) / f32(log_w) : 1
	g.can_render = px_w > 0 && px_h > 0
	gpu_update_projection(g.dpi)
}

input_begin_frame :: proc() {
	g.input.mouse_wheel_x = 0
	g.input.mouse_wheel_y = 0
	clear(&g.input.text_input)
}

input_update_modifiers :: proc(mod: sdl.Keymod) {
	g.input.modifiers = {
		shift = (mod & sdl.KMOD_SHIFT) != {},
		ctrl  = (mod & sdl.KMOD_CTRL) != {},
		alt   = (mod & sdl.KMOD_ALT) != {},
		super = (mod & sdl.KMOD_GUI) != {},
	}
}

input_clear_keyboard_mouse :: proc() {
	g.input.keys_down = {}
	g.input.mouse_left = false
	g.input.mouse_right = false
	g.input.mouse_middle = false
	g.input.modifiers = {}
	clear(&g.input.text_input)
}

input_set_mouse_position :: proc(px_x, px_y: f32) {
	logical := screen_to_logical(px_x, px_y, g.dpi)
	g.input.mouse_x = logical.x
	g.input.mouse_y = logical.y
}

set_fullscreen :: proc(fullscreen: bool) -> bool {
	if g.window == nil do return false

	if !sdl.SetWindowFullscreen(g.window, fullscreen) {
		fmt.eprintln("SDL_SetWindowFullscreen failed:", sdl.GetError())
		return false
	}

	g.fullscreen = fullscreen
	return true
}

toggle_fullscreen :: proc() {
	set_fullscreen(!g.fullscreen)
}

app_tick :: proc(dt: f32) {
	_ = dt
	ui_begin_frame()
	ui_end_frame()
}

frame_time :: proc() -> f64 {
	current_counter := sdl.GetPerformanceCounter()
	elapsed := f64(current_counter - g.last_counter) / f64(g.perf_frequency)
	g.last_counter = current_counter

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
			g.running = false

		case .WINDOW_CLOSE_REQUESTED:
			g.running = false

		case .KEY_DOWN:
			if event.key.repeat do break

			input_update_modifiers(event.key.mod)

			scancode := int(event.key.scancode)
			if scancode >= 0 && scancode < KEY_COUNT {
				g.input.keys_down[scancode] = true
			}

			#partial switch event.key.scancode {
			case .ESCAPE:
				g.running = false
			case .F5:
				g.force_reload = true
			case .F6:
				g.force_restart = true
			case .F11:
				toggle_fullscreen()
			}

		case .KEY_UP:
			input_update_modifiers(event.key.mod)

			scancode := int(event.key.scancode)
			if scancode >= 0 && scancode < KEY_COUNT {
				g.input.keys_down[scancode] = false
			}

		case .TEXT_INPUT:
			if event.text.text != nil {
				append_elem_string(&g.input.text_input, string(event.text.text))
			}

		case .MOUSE_MOTION:
			input_set_mouse_position(event.motion.x, event.motion.y)

		case .MOUSE_BUTTON_DOWN:
			input_set_mouse_position(event.button.x, event.button.y)

			switch event.button.button {
			case sdl.BUTTON_LEFT:
				g.input.mouse_left = true
			case sdl.BUTTON_RIGHT:
				g.input.mouse_right = true
			case sdl.BUTTON_MIDDLE:
				g.input.mouse_middle = true
			}

		case .MOUSE_BUTTON_UP:
			input_set_mouse_position(event.button.x, event.button.y)

			switch event.button.button {
			case sdl.BUTTON_LEFT:
				g.input.mouse_left = false
			case sdl.BUTTON_RIGHT:
				g.input.mouse_right = false
			case sdl.BUTTON_MIDDLE:
				g.input.mouse_middle = false
			}

		case .MOUSE_WHEEL:
			input_set_mouse_position(event.wheel.mouse_x, event.wheel.mouse_y)
			g.input.mouse_wheel_x += event.wheel.x
			g.input.mouse_wheel_y += event.wheel.y

		case .GAMEPAD_ADDED:
			gamepad_open(event.gdevice.which)

		case .GAMEPAD_REMOVED:
			if event.gdevice.which == g.gamepad_instance_id {
				gamepad_close()
			}

		case .GAMEPAD_AXIS_MOTION:
			if event.gaxis.which == g.gamepad_instance_id {
				gamepad_set_axis(sdl.GamepadAxis(event.gaxis.axis), event.gaxis.value)
			}

		case .GAMEPAD_BUTTON_DOWN:
			if event.gbutton.which == g.gamepad_instance_id {
				button := sdl.GamepadButton(event.gbutton.button)
				gamepad_set_button(button, true)

				if button == .START {
					toggle_fullscreen()
				}
			}

		case .GAMEPAD_BUTTON_UP:
			if event.gbutton.which == g.gamepad_instance_id {
				gamepad_set_button(sdl.GamepadButton(event.gbutton.button), false)
			}

		case .WINDOW_RESIZED, .WINDOW_PIXEL_SIZE_CHANGED, .WINDOW_DISPLAY_SCALE_CHANGED:
			dpi_sync()

		case .WINDOW_ENTER_FULLSCREEN:
			g.fullscreen = true

		case .WINDOW_LEAVE_FULLSCREEN:
			g.fullscreen = false

		case .WINDOW_FOCUS_LOST:
			input_clear_keyboard_mouse()
		}
	}
}

reset_user_state :: proc() {
	gamepad := g.gamepad
	gamepad_instance_id := g.gamepad_instance_id

	g.input = {}
	g.force_reload = false
	g.force_restart = false
	g.running = true

	g.gamepad = gamepad
	g.gamepad_instance_id = gamepad_instance_id

	if g.gamepad != nil {
		gamepad_sync_from_device()
	}
}

create_window :: proc() -> bool {
	if !sdl.Init({.VIDEO, .GAMEPAD}) {
		fmt.eprintln("SDL_Init failed:", sdl.GetError())
		return false
	}

	g.window = sdl.CreateWindow(
		WINDOW_TITLE,
		WINDOW_WIDTH,
		WINDOW_HEIGHT,
		sdl.WINDOW_RESIZABLE | sdl.WINDOW_HIGH_PIXEL_DENSITY,
	)
	if g.window == nil {
		fmt.eprintln("SDL_CreateWindow failed:", sdl.GetError())
		sdl.Quit()
		return false
	}

	g.gpu = sdl.CreateGPUDevice({.SPIRV}, true, nil)
	if g.gpu == nil {
		fmt.eprintln("SDL_CreateGPUDevice failed:", sdl.GetError())
		sdl.DestroyWindow(g.window)
		g.window = nil
		sdl.Quit()
		return false
	}

	if !sdl.ClaimWindowForGPUDevice(g.gpu, g.window) {
		fmt.eprintln("SDL_ClaimWindowForGPUDevice failed:", sdl.GetError())
		sdl.DestroyGPUDevice(g.gpu)
		g.gpu = nil
		sdl.DestroyWindow(g.window)
		g.window = nil
		sdl.Quit()
		return false
	}

	if !sdl.SetGPUSwapchainParameters(g.gpu, g.window, .SDR, .VSYNC) {
		fmt.eprintln("SDL_SetGPUSwapchainParameters failed:", sdl.GetError())
		sdl.DestroyGPUDevice(g.gpu)
		g.gpu = nil
		sdl.DestroyWindow(g.window)
		g.window = nil
		sdl.Quit()
		return false
	}

	g.perf_frequency = sdl.GetPerformanceFrequency()
	g.last_counter = sdl.GetPerformanceCounter()
	g.fullscreen = false

	sdl.SetWindowMinimumSize(g.window, MIN_WINDOW_W, MIN_WINDOW_H)
	dpi_sync()
	sdl.ShowWindow(g.window)
	gamepad_open_first_available()

	return true
}

realloc_memory :: proc(new_size: int) {
	window := g.window
	gpu := g.gpu
	gpu_state := g.gpu_state
	assets := g.assets
	textures := g.textures
	fonts := g.fonts
	dpi := g.dpi
	can_render := g.can_render
	fullscreen := g.fullscreen
	perf_frequency := g.perf_frequency
	last_counter := g.last_counter
	running := g.running
	theme := g.theme
	ui := g.ui
	gamepad := g.gamepad
	gamepad_instance_id := g.gamepad_instance_id

	ptr, err := mem.alloc(new_size)
	if err != nil {
		fmt.eprintln("Failed to allocate App_State:", err)
		reset_user_state()
		return
	}

	old := g
	g = cast(^App_State)ptr
	mem.zero(g, new_size)

	g.window = window
	g.gpu = gpu
	g.gpu_state = gpu_state
	g.assets = assets
	g.textures = textures
	g.fonts = fonts
	g.dpi = dpi
	g.can_render = can_render
	g.fullscreen = fullscreen
	g.perf_frequency = perf_frequency
	g.last_counter = last_counter
	g.running = running
	g.theme = theme
	g.ui = ui
	g.gamepad = gamepad
	g.gamepad_instance_id = gamepad_instance_id

	delete(old.input.text_input)
	free(old)
	reset_user_state()
	dpi_sync()
}

@(export)
app_init_window :: proc() {
	if g == nil {
		g = new(App_State)
	}

	if g.window == nil && !create_window() {
		g.running = false
	}
}

@(export)
app_init :: proc() {
	if g == nil do app_init_window()
	if g.window == nil {
		g.running = false
		return
	}

	gpu_init()
	if !font_init() {
		log_error("font_init failed")
		g.running = false
		return
	}
	g.theme = theme_default(&g.assets)
	ui_init()
	reset_user_state()
	dpi_sync()
}

@(export)
app_update :: proc() {
	dt := frame_time()
	input_begin_frame()
	poll_events()

	if !g.can_render do return

	app_tick(f32(dt))
	render_frame()
}

@(export)
app_should_run :: proc() -> bool {
	return g != nil && g.running
}

@(export)
app_shutdown :: proc() {
	if g == nil do return

	gamepad_close()
	ui_shutdown()
	font_shutdown()
	assets_shutdown()
	gpu_destroy()

	if g.gpu != nil {
		sdl.DestroyGPUDevice(g.gpu)
		g.gpu = nil
	}

	if g.window != nil {
		sdl.DestroyWindow(g.window)
		g.window = nil
	}

	delete(g.input.text_input)
	free(g)
	g = nil

	sdl.Quit()
}

@(export)
app_shutdown_window :: proc() {}

@(export)
app_memory :: proc() -> rawptr {
	return g
}

@(export)
app_memory_size :: proc() -> int {
	return size_of(App_State)
}

@(export)
app_hot_reloaded :: proc(mem: rawptr) {
	g = cast(^App_State)mem
	gpu_reload()
	dpi_sync()
}

@(export)
app_reset :: proc() {
	if g == nil do return
	reset_user_state()
}

@(export)
app_realloc :: proc(new_size: int) {
	if g == nil do return
	realloc_memory(new_size)
}

@(export)
app_force_reload :: proc() -> bool {
	if g == nil do return false
	reload := g.force_reload
	g.force_reload = false
	return reload
}

@(export)
app_force_restart :: proc() -> bool {
	if g == nil do return false
	restart := g.force_restart
	g.force_restart = false
	return restart
}

package main

import "core:fmt"
import sdl "vendor:sdl3"

WINDOW_WIDTH :: 1280
WINDOW_HEIGHT :: 720

FIXED_TIMESTEP :: 1.0 / 60.0 // (fixed delta time) 60 simulation updates per second.
MAX_FRAME_TIME :: 0.25 // Prevent huge jumps after pause/debug breakpoint.
GAMEPAD_DEADZONE :: 8000


// BOUNCE_DAMPING is the energy kept after each bounce. 0.65 means each bounce is 65% as high as the last.
BOUNCE_DAMPING :: 0.65 // 1.0 = perfect bounce, 0.0 = no bounce (current behavior)
MIN_BOUNCE_SPEED :: 60.0 // stop bouncing once it's too small

JUMP_SPEED :: -720.0
GRAVITY :: 1800.0
MAX_JUMPS :: 2

Entity :: struct {
	x:          f32,
	y:          f32,
	w:          f32,
	h:          f32,
	speed:      f32, // Pixels per second.
	velocity_y: f32,
}

Player :: struct {
	using _:         Entity,
	jumps_remaining: int,
	on_ground:       bool,
}

Platform :: distinct sdl.FRect
Platforms :: [dynamic]Platform

Wall :: distinct sdl.FRect
Walls :: [dynamic]Wall

Structure :: union {
	Platforms,
	Walls,
}


Input_State :: struct {
	move_left:       bool,
	move_right:      bool,
	move_up:         bool,
	move_down:       bool,
	dpad_left:       bool,
	dpad_right:      bool,
	dpad_up:         bool,
	dpad_down:       bool,
	stick_left:      bool,
	stick_right:     bool,
	stick_up:        bool,
	stick_down:      bool,
	mouse_x:         f32,
	mouse_y:         f32,
	mouse_left_down: bool,
	gamepad_move_x:  f32,
	gamepad_move_y:  f32,
}

App :: struct {
	window:              ^sdl.Window,
	renderer:            ^sdl.Renderer,
	running:             bool,
	input:               Input_State,
	player:              Player,
	platforms:           Platforms,
	walls:               Walls,
	dragging_player:     bool,
	perf_frequency:      u64,
	last_counter:        u64,
	accumulator:         f64,
	fullscreen:          bool,
	gamepad:             ^sdl.Gamepad,
	gamepad_instance_id: sdl.JoystickID,
}

player_platform_top_y :: proc(player: Player, platform: Platform) -> f32 {
	return platform.y - player.h
}

player_overlaps_platform_x :: proc(player: Player, platform: Platform) -> bool {
	return player.x + player.w > platform.x && player.x < platform.x + platform.w
}

player_touching_platform :: proc(player: Player, platform: Platform) -> bool {
	top_y := player_platform_top_y(player, platform)
	return(
		player_overlaps_platform_x(player, platform) &&
		player.y >= top_y &&
		player.y <= platform.y \
	)
}

player_touching_any_platform :: proc(player: Player, platforms: Platforms) -> bool {
	for platform in platforms {
		if player_touching_platform(player, platform) {
			return true
		}
	}
	return false
}

player_landing_on_platform :: proc(player: Player, platform: Platform) -> bool {
	if !player_overlaps_platform_x(player, platform) {
		return false
	}
	feet_y := player.y + player.h
	return feet_y >= platform.y && player.y <= platform.y
}

player_resolve_platform_landing :: proc(app: ^App) {
	landing_top_y: f32
	landing_platform_y: f32
	found := false

	for platform in app.platforms {
		if !player_landing_on_platform(app.player, platform) {
			continue
		}
		if !found || platform.y < landing_platform_y {
			landing_platform_y = platform.y
			landing_top_y = player_platform_top_y(app.player, platform)
			found = true
		}
	}

	if !found {
		app.player.on_ground = false
		return
	}

	app.player.y = landing_top_y

	// Only bounce when moving downward onto the platform.
	if app.player.velocity_y > 0 {
		app.player.velocity_y = -app.player.velocity_y * BOUNCE_DAMPING
		app.player.jumps_remaining = MAX_JUMPS

		if abs(app.player.velocity_y) < MIN_BOUNCE_SPEED {
			app.player.velocity_y = 0
			app.player.on_ground = true
		} else {
			app.player.on_ground = false
		}
	} else if app.player.velocity_y == 0 {
		app.player.on_ground = true
	}
}

player_jump :: proc(app: ^App) {
	if app.player.jumps_remaining <= 0 {
		return
	}

	// Touching a platform but still bouncing — wait until settled.
	if !app.player.on_ground && player_touching_any_platform(app.player, app.platforms) {
		return
	}

	app.player.velocity_y = JUMP_SPEED
	app.player.jumps_remaining -= 1
	app.player.on_ground = false
}

player_movement :: proc(app: ^App, dt: f32) {
	// Keyboard movement.
	// Because speed is pixels-per-second, multiply by dt.
	move_amount := app.player.speed * dt

	left := app.input.move_left || app.input.dpad_left || app.input.stick_left
	right := app.input.move_right || app.input.dpad_right || app.input.stick_right
	up := app.input.move_up || app.input.dpad_up || app.input.stick_up
	down := app.input.move_down || app.input.dpad_down || app.input.stick_down

	if left do app.player.x -= move_amount
	if right do app.player.x += move_amount
	if up do app.player.y -= move_amount
	if down do app.player.y += move_amount

	if left do app.player.x -= move_amount
	if right do app.player.x += move_amount
	if up do app.player.y -= move_amount
	if down do app.player.y += move_amount

	if !app.player.on_ground {
		app.player.velocity_y += GRAVITY * dt
	}
	app.player.y += app.player.velocity_y * dt

	// Platform collision (top surface only).
	player_resolve_platform_landing(app)

	// Mouse dragging.
	if app.dragging_player {
		app.player.x = app.input.mouse_x - app.player.w / 2
		app.player.y = app.input.mouse_y - app.player.h / 2
	}
}

point_inside_player :: proc(px, py: f32, player: Player) -> bool {
	return(
		px >= player.x &&
		px <= player.x + player.w &&
		py >= player.y &&
		py <= player.y + player.h \
	)
}

app_set_fullscreen :: proc(app: ^App, fullscreen: bool) -> bool {
	if app.window == nil {
		return false
	}

	if !sdl.SetWindowFullscreen(app.window, fullscreen) {
		fmt.eprintln("SDL_SetWindowFullscreen failed:", sdl.GetError())
		return false
	}

	app.fullscreen = fullscreen
	return true
}

app_toggle_fullscreen :: proc(app: ^App) {
	app_set_fullscreen(app, !app.fullscreen)
}

app_clear_gamepad_input :: proc(app: ^App) {
	app.input.dpad_left = false
	app.input.dpad_right = false
	app.input.dpad_up = false
	app.input.dpad_down = false

	app.input.stick_left = false
	app.input.stick_right = false
	app.input.stick_up = false
	app.input.stick_down = false
}

app_open_gamepad :: proc(app: ^App, instance_id: sdl.JoystickID) {
	if app.gamepad != nil {
		return
	}

	gamepad := sdl.OpenGamepad(instance_id)
	if gamepad == nil {
		fmt.eprintln("SDL_OpenGamepad failed:", sdl.GetError())
		return
	}

	app.gamepad = gamepad
	app.gamepad_instance_id = instance_id

	fmt.println("Gamepad connected")
}

app_close_gamepad :: proc(app: ^App) {
	if app.gamepad != nil {
		sdl.CloseGamepad(app.gamepad)
		app.gamepad = nil
		app.gamepad_instance_id = 0
		app_clear_gamepad_input(app)

		fmt.println("Gamepad disconnected")
	}
}

app_set_gamepad_axis :: proc(app: ^App, axis: sdl.GamepadAxis, value: i16) {
	v := int(value)

	#partial switch axis {
	case .LEFTX:
		app.input.stick_left = v < -GAMEPAD_DEADZONE
		app.input.stick_right = v > GAMEPAD_DEADZONE

	case .LEFTY:
		app.input.stick_up = v < -GAMEPAD_DEADZONE
		app.input.stick_down = v > GAMEPAD_DEADZONE
	}
}

app_fixed_update :: proc(app: ^App, dt: f32) {
	player_movement(app, dt)
}

structure_render :: proc(app: ^App, structure: Structure) -> bool {
	// Do not try to draw if the renderer was not created or has already been destroyed.
	if app.renderer == nil {
		return false
	}


	switch rects in structure {
	case Platforms:
		for &platform in rects {
			if !sdl.SetRenderDrawColor(app.renderer, 90, 220, 120, 255) {
				fmt.eprintln("SDL_SetRenderDrawColor failed:", sdl.GetError())
				return false
			}

			frect := sdl.FRect(platform)
			if !sdl.RenderFillRect(app.renderer, &frect) {
				fmt.eprintln("SDL_RenderFillRect failed:", sdl.GetError())
				return false
			}
		}
	case Walls:
		for &wall in rects {
			if !sdl.SetRenderDrawColor(app.renderer, 255, 0, 120, 255) {
				fmt.eprintln("SDL_SetRenderDrawColor failed:", sdl.GetError())
				return false
			}

			frect := sdl.FRect(wall)
			if !sdl.RenderFillRect(app.renderer, &frect) {
				fmt.eprintln("SDL_RenderFillRect failed:", sdl.GetError())
				return false
			}
		}
	}

	return true
}

player_render :: proc(app: ^App) {
	// Build draw rectangle from current player state.
	player_rect := sdl.FRect {
		x = app.player.x,
		y = app.player.y,
		w = app.player.w,
		h = app.player.h,
	}

	// Change player color while mouse is held.
	if app.input.mouse_left_down {
		sdl.SetRenderDrawColor(app.renderer, 80, 180, 255, 255)
	} else {
		sdl.SetRenderDrawColor(app.renderer, 255, 80, 80, 255)
	}

	sdl.RenderFillRect(app.renderer, &player_rect)

	sdl.RenderPresent(app.renderer)
}


app_render :: proc(app: ^App) {
	// Clear background.
	sdl.SetRenderDrawColor(app.renderer, 20, 20, 24, 255)
	sdl.RenderClear(app.renderer)

	// Draw structures before player so the player appears on top.
	structure_render(app, app.platforms)
	structure_render(app, app.walls)
	player_render(app)


}

app_frame_time :: proc(app: ^App) -> f64 {
	current_counter := sdl.GetPerformanceCounter()

	// How many timer ticks passed since the last frame
	// Timer ticks, not seconds. So you divide by perf_frequency
	frame_time := f64(current_counter - app.last_counter) / f64(app.perf_frequency)

	// Updates the previous-frame timer value, ready for the next loop.
	app.last_counter = current_counter

	// Clamp large frame times.
	// Example: app was paused, dragged, debugged, or OS stalled it.
	if frame_time > MAX_FRAME_TIME {
		frame_time = MAX_FRAME_TIME
	}

	return frame_time
}

app_poll_events :: proc(app: ^App) {
	event: sdl.Event

	for sdl.PollEvent(&event) {
		#partial switch event.type {
		case .QUIT:
			app.running = false

		case .WINDOW_CLOSE_REQUESTED:
			app.running = false


		case .KEY_DOWN:
			if event.key.repeat {
				break
			}

			#partial switch event.key.scancode {
			case .ESCAPE:
				app.running = false

			case .F11:
				app_toggle_fullscreen(app)

			case .SPACE:
				player_jump(app)

			case .A, .LEFT:
				app.input.move_left = true

			case .D, .RIGHT:
				app.input.move_right = true

			case .W, .UP:
				app.input.move_up = true

			case .S, .DOWN:
				app.input.move_down = true
			}

		case .KEY_UP:
			#partial switch event.key.scancode {
			case .A, .LEFT:
				app.input.move_left = false

			case .D, .RIGHT:
				app.input.move_right = false

			case .W, .UP:
				app.input.move_up = false

			case .S, .DOWN:
				app.input.move_down = false
			}

		case .MOUSE_MOTION:
			app.input.mouse_x = event.motion.x
			app.input.mouse_y = event.motion.y

		case .MOUSE_BUTTON_DOWN:
			app.input.mouse_x = event.button.x
			app.input.mouse_y = event.button.y

			if event.button.button == sdl.BUTTON_LEFT {
				app.input.mouse_left_down = true

				if point_inside_player(app.input.mouse_x, app.input.mouse_y, app.player) {
					app.dragging_player = true
				}
			} else if event.button.button == sdl.BUTTON_RIGHT {
				// Right-click resets rectangle.
				app.player.x = 100
				app.player.y = 100
				app.player.w = 100
				app.player.h = 100
			} else if event.button.button == sdl.BUTTON_MIDDLE {
				// Middle-click moves rectangle to the mouse.
				app.player.x = app.input.mouse_x - app.player.w / 2
				app.player.y = app.input.mouse_y - app.player.h / 2
			}

		case .MOUSE_BUTTON_UP:
			app.input.mouse_x = event.button.x
			app.input.mouse_y = event.button.y

			if event.button.button == sdl.BUTTON_LEFT {
				app.input.mouse_left_down = false
				app.dragging_player = false
			}

		case .MOUSE_WHEEL:
			// Wheel up makes rectangle bigger, wheel down smaller.
			scale_amount: f32 = 8

			if event.wheel.y > 0 {
				app.player.w += scale_amount
				app.player.h += scale_amount
			} else if event.wheel.y < 0 {
				app.player.w -= scale_amount
				app.player.h -= scale_amount
			}

			if app.player.w < 16 do app.player.w = 16
			if app.player.h < 16 do app.player.h = 16

		case .GAMEPAD_ADDED:
			app_open_gamepad(app, event.gdevice.which)

		case .GAMEPAD_REMOVED:
			if event.gdevice.which == app.gamepad_instance_id {
				app_close_gamepad(app)
			}

		case .GAMEPAD_AXIS_MOTION:
			if event.gaxis.which == app.gamepad_instance_id {
				app_set_gamepad_axis(app, sdl.GamepadAxis(event.gaxis.axis), event.gaxis.value)
			}

		case .GAMEPAD_BUTTON_DOWN:
			if event.gbutton.which == app.gamepad_instance_id {
				#partial switch sdl.GamepadButton(event.gbutton.button) {
				case .DPAD_LEFT:
					app.input.dpad_left = true
				case .DPAD_RIGHT:
					app.input.dpad_right = true
				case .DPAD_UP:
					app.input.dpad_up = true
				case .DPAD_DOWN:
					app.input.dpad_down = true
				case .EAST:
					app.player.x = 0
					app.player.y = 100
					app.player.w = 100
					app.player.h = 100
				case .SOUTH:
					player_jump(app)
				case .START:
					app_toggle_fullscreen(app)
				}
			}

		case .GAMEPAD_BUTTON_UP:
			if event.gbutton.which == app.gamepad_instance_id {
				#partial switch sdl.GamepadButton(event.gbutton.button) {
				case .DPAD_LEFT:
					app.input.dpad_left = false
				case .DPAD_RIGHT:
					app.input.dpad_right = false
				case .DPAD_UP:
					app.input.dpad_up = false
				case .DPAD_DOWN:
					app.input.dpad_down = false
				}
			}

		case .WINDOW_PIXEL_SIZE_CHANGED:
			// Actual drawable pixel size changed.
			// Important for high-DPI displays.
			fmt.println("Window pixel size changed:", event.window.data1, event.window.data2)

		case .WINDOW_FOCUS_LOST:
			// Clear held input so the player does not keep moving after Alt-Tab.
			app.input.move_left = false
			app.input.move_right = false
			app.input.move_up = false
			app.input.move_down = false
			app.input.mouse_left_down = false
			app.dragging_player = false
		}
	}
}

app_init :: proc(app: ^App) -> bool {
	if !sdl.Init(sdl.INIT_VIDEO | sdl.INIT_GAMEPAD) {
		fmt.eprintln("SDL_Init failed:", sdl.GetError())
		return false
	}

	app.window = sdl.CreateWindow(
		"Odin + SDL3 Production-Style Demo",
		WINDOW_WIDTH,
		WINDOW_HEIGHT,
		sdl.WINDOW_RESIZABLE | sdl.WINDOW_HIGH_PIXEL_DENSITY,
	)

	if app.window == nil {
		fmt.eprintln("SDL_CreateWindow failed:", sdl.GetError())
		return false
	}

	app.renderer = sdl.CreateRenderer(app.window, nil)
	if app.renderer == nil {
		fmt.eprintln("SDL_CreateRenderer failed:", sdl.GetError())
		return false
	}

	if !sdl.SetRenderVSync(app.renderer, 1) {
		fmt.eprintln("SDL_SetRenderVSync failed:", sdl.GetError())
		// Not fatal. The app can still run without vsync.
	}

	app.running = true

	app.player = Player {
		x               = 100,
		y               = 100,
		w               = 100,
		h               = 100,
		speed           = 360, // 360 pixels per second.
		velocity_y      = 0,
		on_ground       = false,
		jumps_remaining = MAX_JUMPS,
	}

	append(
		&app.platforms,
		Platform{x = 0, y = 500, w = 500, h = 200},
		Platform{x = 800, y = 500, w = 500, h = 200},
		Platform{x = 1300, y = 500, w = 500, h = 200},
	)

	append(&app.walls, Wall{x = 1200, y = 400, w = 100, h = 100})

	app.perf_frequency = sdl.GetPerformanceFrequency() // How many ticks in one second
	app.last_counter = sdl.GetPerformanceCounter() // Starting time value (timer ticks)
	app.accumulator = 0

	sdl.ShowWindow(app.window)

	return true
}

app_shutdown :: proc(app: ^App) {
	delete(app.platforms)
	delete(app.walls)

	app_close_gamepad(app)

	if app.renderer != nil {
		sdl.DestroyRenderer(app.renderer)
		app.renderer = nil
	}

	if app.window != nil {
		sdl.DestroyWindow(app.window)
		app.window = nil
	}

	sdl.Quit()
}

main :: proc() {
	app: App

	if !app_init(&app) {
		app_shutdown(&app)
		return
	}
	defer app_shutdown(&app)

	for app.running {
		// 1. Measure real time since last frame.
		frame_time := app_frame_time(&app)

		// 2. Read input/events once per rendered frame.
		app_poll_events(&app)

		// 3. Add elapsed time to the fixed timestep accumulator.
		app.accumulator += frame_time

		// 4. Run simulation in fixed-size steps.
		for app.accumulator >= FIXED_TIMESTEP {
			app_fixed_update(&app, f32(FIXED_TIMESTEP))
			app.accumulator -= FIXED_TIMESTEP
		}

		// 5. Render latest state.
		app_render(&app)
	}
}

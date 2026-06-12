package game

import "core:fmt"
import "core:mem"
import sdl "vendor:sdl3"

WINDOW_WIDTH :: 1280
WINDOW_HEIGHT :: 720
WINDOW_TITLE :: "Odin + SDL3"

FIXED_TIMESTEP :: 1.0 / 60.0
MAX_FRAME_TIME :: 0.25
GAMEPAD_DEADZONE :: 8000

BOUNCE_DAMPING :: 0.65
MIN_BOUNCE_SPEED :: 60.0

JUMP_SPEED :: -720.0
GRAVITY :: 1800.0
MAX_JUMPS :: 2

Entity :: struct {
	x:          f32,
	y:          f32,
	w:          f32,
	h:          f32,
	speed:      f32,
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

Game_Memory :: struct {
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
	force_reload:        bool,
	force_restart:       bool,
}

g: ^Game_Memory

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

player_resolve_platform_landing :: proc() {
	landing_top_y: f32
	landing_platform_y: f32
	found := false

	for platform in g.platforms {
		if !player_landing_on_platform(g.player, platform) {
			continue
		}
		if !found || platform.y < landing_platform_y {
			landing_platform_y = platform.y
			landing_top_y = player_platform_top_y(g.player, platform)
			found = true
		}
	}

	if !found {
		g.player.on_ground = false
		return
	}

	g.player.y = landing_top_y

	if g.player.velocity_y > 0 {
		g.player.velocity_y = -g.player.velocity_y * BOUNCE_DAMPING
		g.player.jumps_remaining = MAX_JUMPS

		if abs(g.player.velocity_y) < MIN_BOUNCE_SPEED {
			g.player.velocity_y = 0
			g.player.on_ground = true
		} else {
			g.player.on_ground = false
		}
	} else if g.player.velocity_y == 0 {
		g.player.on_ground = true
	}
}

player_jump :: proc() {
	if g.player.jumps_remaining <= 0 {
		return
	}

	if !g.player.on_ground && player_touching_any_platform(g.player, g.platforms) {
		return
	}

	g.player.velocity_y = JUMP_SPEED
	g.player.jumps_remaining -= 1
	g.player.on_ground = false
}

player_movement :: proc(dt: f32) {
	move_amount := g.player.speed * dt

	left := g.input.move_left || g.input.dpad_left || g.input.stick_left
	right := g.input.move_right || g.input.dpad_right || g.input.stick_right
	up := g.input.move_up || g.input.dpad_up || g.input.stick_up
	down := g.input.move_down || g.input.dpad_down || g.input.stick_down

	if left do g.player.x -= move_amount
	if right do g.player.x += move_amount
	if up do g.player.y -= move_amount
	if down do g.player.y += move_amount

	if !g.player.on_ground {
		g.player.velocity_y += GRAVITY * dt
	}
	g.player.y += g.player.velocity_y * dt

	player_resolve_platform_landing()

	if g.dragging_player {
		g.player.x = g.input.mouse_x - g.player.w / 2
		g.player.y = g.input.mouse_y - g.player.h / 2
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

set_fullscreen :: proc(fullscreen: bool) -> bool {
	if g.window == nil {
		return false
	}

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

fixed_update :: proc(dt: f32) {
	player_movement(dt)
}

structure_render :: proc(structure: Structure) -> bool {
	if g.renderer == nil {
		return false
	}

	switch rects in structure {
	case Platforms:
		for &platform in rects {
			if !sdl.SetRenderDrawColor(g.renderer, 90, 220, 120, 255) {
				fmt.eprintln("SDL_SetRenderDrawColor failed:", sdl.GetError())
				return false
			}

			frect := sdl.FRect(platform)
			if !sdl.RenderFillRect(g.renderer, &frect) {
				fmt.eprintln("SDL_RenderFillRect failed:", sdl.GetError())
				return false
			}
		}
	case Walls:
		for &wall in rects {
			if !sdl.SetRenderDrawColor(g.renderer, 255, 0, 120, 255) {
				fmt.eprintln("SDL_SetRenderDrawColor failed:", sdl.GetError())
				return false
			}

			frect := sdl.FRect(wall)
			if !sdl.RenderFillRect(g.renderer, &frect) {
				fmt.eprintln("SDL_RenderFillRect failed:", sdl.GetError())
				return false
			}
		}
	}

	return true
}

player_render :: proc() {
	player_rect := sdl.FRect {
		x = g.player.x,
		y = g.player.y,
		w = g.player.w,
		h = g.player.h,
	}

	if g.input.mouse_left_down {
		sdl.SetRenderDrawColor(g.renderer, 80, 180, 255, 255)
	} else {
		sdl.SetRenderDrawColor(g.renderer, 255, 80, 80, 255)
	}

	sdl.RenderFillRect(g.renderer, &player_rect)
	sdl.RenderPresent(g.renderer)
}

render :: proc() {
	sdl.SetRenderDrawColor(g.renderer, 20, 20, 24, 255)
	sdl.RenderClear(g.renderer)
	structure_render(g.platforms)
	structure_render(g.walls)
	player_render()
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
			if event.key.repeat {
				break
			}

			#partial switch event.key.scancode {
			case .ESCAPE:
				g.running = false
			case .F5:
				g.force_reload = true
				fmt.println("F5: reload requested")
			case .F6:
				g.force_restart = true
				fmt.println("F6: restart requested")
			case .F11:
				toggle_fullscreen()
			case .SPACE:
				player_jump()
			case .A, .LEFT:
				g.input.move_left = true
			case .D, .RIGHT:
				g.input.move_right = true
			case .W, .UP:
				g.input.move_up = true
			case .S, .DOWN:
				g.input.move_down = true
			}

		case .KEY_UP:
			#partial switch event.key.scancode {
			case .A, .LEFT:
				g.input.move_left = false
			case .D, .RIGHT:
				g.input.move_right = false
			case .W, .UP:
				g.input.move_up = false
			case .S, .DOWN:
				g.input.move_down = false
			}

		case .MOUSE_MOTION:
			g.input.mouse_x = event.motion.x
			g.input.mouse_y = event.motion.y

		case .MOUSE_BUTTON_DOWN:
			g.input.mouse_x = event.button.x
			g.input.mouse_y = event.button.y

			if event.button.button == sdl.BUTTON_LEFT {
				g.input.mouse_left_down = true
				if point_inside_player(g.input.mouse_x, g.input.mouse_y, g.player) {
					g.dragging_player = true
				}
			} else if event.button.button == sdl.BUTTON_RIGHT {
				g.player.x = 100
				g.player.y = 100
				g.player.w = 100
				g.player.h = 100
			} else if event.button.button == sdl.BUTTON_MIDDLE {
				g.player.x = g.input.mouse_x - g.player.w / 2
				g.player.y = g.input.mouse_y - g.player.h / 2
			}

		case .MOUSE_BUTTON_UP:
			g.input.mouse_x = event.button.x
			g.input.mouse_y = event.button.y

			if event.button.button == sdl.BUTTON_LEFT {
				g.input.mouse_left_down = false
				g.dragging_player = false
			}

		case .MOUSE_WHEEL:
			scale_amount: f32 = 8

			if event.wheel.y > 0 {
				g.player.w += scale_amount
				g.player.h += scale_amount
			} else if event.wheel.y < 0 {
				g.player.w -= scale_amount
				g.player.h -= scale_amount
			}

			if g.player.w < 16 do g.player.w = 16
			if g.player.h < 16 do g.player.h = 16

		case .GAMEPAD_ADDED:
			open_gamepad(event.gdevice.which)

		case .GAMEPAD_REMOVED:
			if event.gdevice.which == g.gamepad_instance_id {
				close_gamepad()
			}

		case .GAMEPAD_AXIS_MOTION:
			if event.gaxis.which == g.gamepad_instance_id {
				set_gamepad_axis(sdl.GamepadAxis(event.gaxis.axis), event.gaxis.value)
			}

		case .GAMEPAD_BUTTON_DOWN:
			if event.gbutton.which == g.gamepad_instance_id {
				#partial switch sdl.GamepadButton(event.gbutton.button) {
				case .DPAD_LEFT:
					g.input.dpad_left = true
				case .DPAD_RIGHT:
					g.input.dpad_right = true
				case .DPAD_UP:
					g.input.dpad_up = true
				case .DPAD_DOWN:
					g.input.dpad_down = true
				case .EAST:
					g.player.x = 0
					g.player.y = 100
					g.player.w = 100
					g.player.h = 100
				case .SOUTH:
					player_jump()
				case .START:
					toggle_fullscreen()
				}
			}

		case .GAMEPAD_BUTTON_UP:
			if event.gbutton.which == g.gamepad_instance_id {
				#partial switch sdl.GamepadButton(event.gbutton.button) {
				case .DPAD_LEFT:
					g.input.dpad_left = false
				case .DPAD_RIGHT:
					g.input.dpad_right = false
				case .DPAD_UP:
					g.input.dpad_up = false
				case .DPAD_DOWN:
					g.input.dpad_down = false
				}
			}

		case .WINDOW_PIXEL_SIZE_CHANGED:
			fmt.println("Window pixel size changed:", event.window.data1, event.window.data2)

		case .WINDOW_FOCUS_LOST:
			g.input.move_left = false
			g.input.move_right = false
			g.input.move_up = false
			g.input.move_down = false
			g.input.mouse_left_down = false
			g.dragging_player = false
		}
	}
}

unload_world_state :: proc() {
	delete(g.platforms)
	delete(g.walls)
	clear(&g.platforms)
	clear(&g.walls)
	close_gamepad()
}

load_world_state :: proc() {
	g.player = Player {
		x               = 100,
		y               = 100,
		w               = 100,
		h               = 100,
		speed           = 360,
		velocity_y      = 0,
		on_ground       = false,
		jumps_remaining = MAX_JUMPS,
	}

	append(
		&g.platforms,
		Platform{x = 0, y = 500, w = 500, h = 200},
		Platform{x = 800, y = 500, w = 500, h = 200},
		Platform{x = 1300, y = 500, w = 500, h = 200},
	)

	append(&g.walls, Wall{x = 1200, y = 400, w = 100, h = 100})

	g.input = {}
	g.dragging_player = false
	g.accumulator = 0
	g.force_reload = false
	g.force_restart = false
	g.running = true
}

create_window :: proc() -> bool {
	if !sdl.Init(sdl.INIT_VIDEO | sdl.INIT_GAMEPAD) {
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
		return false
	}

	g.renderer = sdl.CreateRenderer(g.window, nil)
	if g.renderer == nil {
		fmt.eprintln("SDL_CreateRenderer failed:", sdl.GetError())
		return false
	}

	if !sdl.SetRenderVSync(g.renderer, 1) {
		fmt.eprintln("SDL_SetRenderVSync failed:", sdl.GetError())
	}

	g.perf_frequency = sdl.GetPerformanceFrequency()
	g.last_counter = sdl.GetPerformanceCounter()
	g.fullscreen = false

	sdl.ShowWindow(g.window)
	return true
}

realloc_memory :: proc(new_size: int) {
	window := g.window
	renderer := g.renderer
	fullscreen := g.fullscreen
	perf_frequency := g.perf_frequency
	last_counter := g.last_counter
	running := g.running

	unload_world_state()
	free(g)
	g = nil

	ptr, err := mem.alloc(new_size)
	if err != nil {
		fmt.eprintln("Failed to allocate Game_Memory:", err)
		return
	}

	g = cast(^Game_Memory)ptr
	mem.zero(g, new_size)

	g.window = window
	g.renderer = renderer
	g.fullscreen = fullscreen
	g.perf_frequency = perf_frequency
	g.last_counter = last_counter
	g.running = running

	load_world_state()
}

@(export)
game_init_window :: proc() {
	if g == nil {
		g = new(Game_Memory)
	}

	if g.window == nil && !create_window() {
		g.running = false
	}
}

@(export)
game_init :: proc() {
	if g == nil {
		game_init_window()
	}

	if g.window == nil {
		g.running = false
		return
	}

	load_world_state()
}

@(export)
game_update :: proc() {
	elapsed := frame_time()
	poll_events()

	g.accumulator += elapsed

	for g.accumulator >= FIXED_TIMESTEP {
		fixed_update(f32(FIXED_TIMESTEP))
		g.accumulator -= FIXED_TIMESTEP
	}

	render()
}

@(export)
game_should_run :: proc() -> bool {
	return g != nil && g.running
}

@(export)
game_shutdown :: proc() {
	if g == nil {
		return
	}

	unload_world_state()

	if g.renderer != nil {
		sdl.DestroyRenderer(g.renderer)
		g.renderer = nil
	}

	if g.window != nil {
		sdl.DestroyWindow(g.window)
		g.window = nil
	}

	free(g)
	g = nil

	sdl.Quit()
}

@(export)
game_shutdown_window :: proc() {
	// SDL teardown is handled in game_shutdown.
}

@(export)
game_memory :: proc() -> rawptr {
	return g
}

@(export)
game_memory_size :: proc() -> int {
	return size_of(Game_Memory)
}

@(export)
game_hot_reloaded :: proc(mem: rawptr) {
	g = cast(^Game_Memory)mem
}

@(export)
game_reset :: proc() {
	if g == nil {
		return
	}

	unload_world_state()
	load_world_state()
}

@(export)
game_realloc :: proc(new_size: int) {
	if g == nil {
		return
	}

	realloc_memory(new_size)
}

@(export)
game_force_reload :: proc() -> bool {
	if g == nil {
		return false
	}

	reload := g.force_reload
	g.force_reload = false
	return reload
}

@(export)
game_force_restart :: proc() -> bool {
	if g == nil {
		return false
	}

	restart := g.force_restart
	g.force_restart = false
	return restart
}

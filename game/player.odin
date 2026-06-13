package game

import sdl "vendor:sdl3"

BOUNCE_DAMPING :: 0.65
MIN_BOUNCE_SPEED :: 60.0

JUMP_SPEED :: -720.0
GRAVITY :: 1800.0
MAX_JUMPS :: 2

Player :: struct {
	using _:         Entity,
	jumps_remaining: int,
	on_ground:       bool,
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

player_render :: proc(renderer: ^sdl.Renderer, player: Player) {
	player_rect := sdl.FRect {
		x = g.player.x,
		y = g.player.y,
		w = g.player.w,
		h = g.player.h,
	}

	color: [4]u8 = {255, 80, 80, 255}

	if g.input.mouse_left_down {
		color = {80, 180, 255, 255}
	}

	draw_rect(renderer, player_rect, color)
}

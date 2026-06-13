package game

import sdl "vendor:sdl3"

Platform :: distinct sdl.FRect
Platforms :: [dynamic]Platform

Wall :: distinct sdl.FRect
Walls :: [dynamic]Wall

Structure :: union {
	Platforms,
	Walls,
}


platforms_render :: proc(renderer: ^sdl.Renderer, platforms: Platforms) {
	if renderer == nil do return

	for &platform in platforms {
		draw_rect(renderer, cast(sdl.FRect)platform, color = {90, 220, 120, 255})
	}
}

walls_render :: proc(renderer: ^sdl.Renderer, walls: Walls) {
	if renderer == nil do return

	for &wall in walls {
		draw_rect(renderer, cast(sdl.FRect)wall, {255, 0, 120, 255}, false)
	}
}

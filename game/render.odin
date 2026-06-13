package game

import "core:fmt"
import sdl "vendor:sdl3"

render :: proc() {
	if !g.can_render {
		return
	}

	render_clear(g.renderer, {20, 20, 24, 255})
	platforms_render(g.renderer, g.platforms)
	walls_render(g.renderer, g.walls)
	player_render(g.renderer, g.player)
	sdl.RenderPresent(g.renderer)
}


render_clear :: proc(renderer: ^sdl.Renderer, color: [4]u8) {
	if renderer == nil do return

	sdl.SetRenderDrawColor(renderer, color.r, color.g, color.b, color.a)
	sdl.RenderClear(g.renderer)

	return
}

draw_rect :: proc(renderer: ^sdl.Renderer, rect: sdl.FRect, color: [4]u8, filled: bool = true) {
	if renderer == nil do return

	if !sdl.SetRenderDrawColor(renderer, color.r, color.g, color.b, color.a) {
		fmt.eprintln("SDL_SetRenderDrawColor failed:", sdl.GetError())
		return
	}

	r := rect

	if filled {
		if !sdl.RenderFillRect(g.renderer, &r) {
			fmt.eprintln("SDL_RenderFillRect failed:", sdl.GetError())
			return
		}
	} else {
		if !sdl.RenderRect(g.renderer, &r) {
			fmt.eprintln("SDL_RenderFillRect failed:", sdl.GetError())
			return
		}
	}

	return
}

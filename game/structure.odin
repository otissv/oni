package game

import "core:fmt"
import sdl "vendor:sdl3"

Platform :: distinct sdl.FRect
Platforms :: [dynamic]Platform

Wall :: distinct sdl.FRect
Walls :: [dynamic]Wall

Structure :: union {
	Platforms,
	Walls,
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

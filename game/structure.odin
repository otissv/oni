package game

import sdl "vendor:sdl3"


Platform_Tile :: enum {
	A,
	B,
}


Platform_Tiles :: struct {
	A, B: Tile,
}

Green :: distinct Platform_Tile
Brown :: distinct Platform_Tile
Yellow :: distinct Platform_Tile
Blue :: distinct Platform_Tile

Platform_Tileset :: union {
	Green,
	Brown,
	Yellow,
	Blue,
}

Platform :: struct {
	using _: sdl.FRect,
	tileset: Platform_Tileset,
}
Platforms :: [dynamic]Platform

Wall :: distinct sdl.FRect
Walls :: [dynamic]Wall

Structure :: union {
	Platforms,
	Walls,
}


// Platform art sits in the top of each 16px atlas row (9px tall).
PLATFORM_TILE_SIZE :: 16
PLATFORM_TILE_SCALE :: 4
PLATFORM_SURFACE_H :: f32(PLATFORM_TILE_SIZE) * PLATFORM_TILE_SCALE

PLATFORM_TILESET :: struct {
	Green, Brown, Yellow, Blue: Platform_Tiles,
} {
	Green = {A = {0, 0, 1, 1}, B = {1, 0, 1, 1}},
	Brown = {A = {0, 1, 1, 1}, B = {1, 1, 1, 1}},
	Yellow = {A = {0, 2, 1, 1}, B = {1, 2, 1, 1}},
	Blue = {A = {0, 3, 1, 1}, B = {1, 3, 1, 1}},
}

platform_tiles_for :: proc(selection: Platform_Tileset) -> Platform_Tiles {
	switch color in selection {
	case Green:
		return PLATFORM_TILESET.Green
	case Brown:
		return PLATFORM_TILESET.Brown
	case Yellow:
		return PLATFORM_TILESET.Yellow
	case Blue:
		return PLATFORM_TILESET.Blue
	}
	unreachable()
}

platform_tile_at :: proc(selection: Platform_Tileset, index, count: int) -> Tile {
	tiles := platform_tiles_for(selection)

	if count == 1 {
		switch tile in selection {
		case Green:
			return tile == Green.A ? tiles.A : tiles.B
		case Brown:
			return tile == Brown.A ? tiles.A : tiles.B
		case Yellow:
			return tile == Yellow.A ? tiles.A : tiles.B
		case Blue:
			return tile == Blue.A ? tiles.A : tiles.B
		}
	}

	return index == 0 ? tiles.A : tiles.B
}

platforms_render :: proc(renderer: ^sdl.Renderer, platforms: Platforms) {
	if renderer == nil do return

	sheet := g.textures[.Platforms]
	if sheet.texture == nil do return

	scale: f32 = PLATFORM_TILE_SCALE
	tile_px := f32(PLATFORM_TILE_SIZE) * scale

	for platform in platforms {
		rect := cast(sdl.FRect)platform
		tiles := max(1, int(rect.w / tile_px))

		for i in 0 ..< tiles {
			x := rect.x + f32(i) * tile_px
			tile := platform_tile_at(platform.tileset, i, tiles)
			tile_render(renderer, sheet, tile, x, platform.y, scale)
		}
	}
}

walls_render :: proc(renderer: ^sdl.Renderer, walls: Walls) {
	if renderer == nil do return

	for &wall in walls {
		draw_rect(renderer, cast(sdl.FRect)wall, {255, 0, 120, 255}, false)
	}
}

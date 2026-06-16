package game

import "core:fmt"
import sdl "vendor:sdl3"

TILE_SIZE :: 16

Texture_Asset :: struct {
	texture: ^sdl.Texture,
	width:   f32,
	height:  f32,
	path:    cstring,
}

Texture_Id :: enum {
	Platforms,
}

Tile :: struct {
	col:     u8,
	row:     u8,
	colSpan: u8,
	rowSpan: u8,
}


TEXTURE_PATHS := [Texture_Id]cstring {
	.Platforms = "assets/sprites/platforms.png",
}

texture_load :: proc(renderer: ^sdl.Renderer, path: cstring) -> (asset: Texture_Asset, ok: bool) {
	if renderer == nil {
		fmt.eprintln("texture_load failed: render is nil")
		return {}, false
	}

	surface := sdl.LoadSurface(path)
	if surface == nil {
		fmt.eprintln("SDL_LoadSurface failed for", path, ":", sdl.GetError())
		return {}, false
	}
	defer sdl.DestroySurface(surface)

	texture := sdl.CreateTextureFromSurface(renderer, surface)
	if texture == nil {
		fmt.eprintln("SDL_CreateTextureFromSurface failed for", path, ":", sdl.GetError())
		return {}, false
	}

	width, height: f32

	if !sdl.GetTextureSize(texture, &width, &height) {
		fmt.eprintln("SDL_GetTextureSize failed for ", path, ":", sdl.GetError())
		sdl.DestroyTexture(texture)
		return {}, false
	}

	return Texture_Asset{texture = texture, width = width, height = height, path = path}, true
}

texture_destroy :: proc(asset: ^Texture_Asset) {
	if asset == nil do return

	if asset.texture != nil {
		sdl.DestroyTexture(asset.texture)
		asset.texture = nil
	}

	asset.width = 0
	asset.height = 0
}

textures_load_all :: proc(renderer: ^sdl.Renderer, out: ^[Texture_Id]Texture_Asset) -> bool {
	for id in Texture_Id {
		asset, ok := texture_load(renderer, TEXTURE_PATHS[id])
		if !ok do return false
		out[id] = asset
	}
	return true
}

textures_destroy_all :: proc(textures: ^[Texture_Id]Texture_Asset) {
	for id in Texture_Id {
		texture_destroy(&textures[id])
	}
}

texture_render :: proc(
	renderer: ^sdl.Renderer,
	asset: Texture_Asset,
	src: ^sdl.FRect,
	dst: ^sdl.FRect,
) -> bool {
	if renderer == nil || asset.texture == nil do return false


	if !sdl.RenderTexture(renderer, asset.texture, src, dst) {
		fmt.eprintln("SDL_RenderTexture failed:", sdl.GetError())
		return false
	}

	return true

}


tile_src_rect :: proc(tile: Tile) -> sdl.FRect {
	return sdl.FRect {
		x = f32(tile.col * TILE_SIZE),
		y = f32(tile.row * TILE_SIZE),
		w = f32(tile.colSpan * TILE_SIZE),
		h = f32(tile.rowSpan * TILE_SIZE),
	}
}

tile_render :: proc(
	renderer: ^sdl.Renderer,
	sheet: Texture_Asset,
	tile: Tile,
	world_x, world_y: f32,
	scale: f32,
) -> bool {
	if renderer == nil || sheet.texture == nil {
		return false
	}

	src := tile_src_rect(tile)

	dst := sdl.FRect {
		x = world_x,
		y = world_y,
		w = f32(tile.colSpan * TILE_SIZE) * scale,
		h = f32(tile.rowSpan * TILE_SIZE) * scale,
	}

	if !texture_render(renderer, sheet, &src, &dst) {
		fmt.eprintln("SDL_RenderTexture failed:", sdl.GetError())
		return false
	}

	return true
}

package oni

import "core:strings"
import sdl "vendor:sdl3"
import img "vendor:sdl3/image"

/*
Maps loaded file paths to registered texture asset ids.
*/
Asset_Cache :: struct {
	paths: map[string]Asset_Id,
}

/*
Initializes the path-to-asset cache and texture subsystem.

Safe to call once at startup; the gpu parameter is reserved for future use.
*/
assets_init :: proc(gpu: ^sdl.GPUDevice) {
	_ = gpu
	if state.assets.paths == nil {
		state.assets.paths = make(map[string]Asset_Id)
	}
	texture_init()
}

/*
Frees all cached path strings, the asset map, and texture state.

Call during engine shutdown before the GPU device is destroyed.
*/
assets_shutdown :: proc() {
	for path, _ in state.assets.paths {
		delete(path)
	}
	delete(state.assets.paths)
	state.assets.paths = nil
	texture_shutdown()
}

/*
Releases and re-uploads all GPU textures after device recreation.

Delegates to texture_release_gpu and texture_reload_gpu.
*/
assets_reload_gpu :: proc(gpu: ^sdl.GPUDevice) {
	_ = gpu
	texture_release_gpu()
	texture_reload_gpu()
}

/*
Loads a texture from disk, returning a cached handle on subsequent calls.

Registers the decoded surface with the texture system and caches the path mapping.
*/
assets_load_texture :: proc(path: string) -> (Texture_Handle, bool) {
	if id, ok := state.assets.paths[path]; ok {
		return assets_get_texture(id), true
	}

	surface, ok := assets_load_surface(path)
	if !ok do return {}, false

	id, handle, reg_ok := texture_register_surface(surface, path)
	if !reg_ok {
		sdl.DestroySurface(surface)
		return {}, false
	}

	state.assets.paths[strings.clone(path)] = id
	return handle, true
}

/*
Returns a Texture_Handle for a previously loaded asset id.

Delegates to texture_handle.
*/
assets_get_texture :: proc(id: Asset_Id) -> Texture_Handle {
	return texture_handle(id)
}

/*
Loads an image file into an SDL surface using SDL or SDL_image.

Tries SDL_LoadSurface first, then img.Load as a fallback.
*/
assets_load_surface :: proc(path: string) -> (^sdl.Surface, bool) {
	cpath := strings.clone_to_cstring(path, context.temp_allocator)

	surface := sdl.LoadSurface(cpath)
	if surface == nil {
		surface = img.Load(cpath)
	}
	if surface == nil {
		log_errorf("Failed to load image %q: %s", path, sdl.GetError())
		return nil, false
	}

	return surface, true
}

package oni

import "core:strings"
import sdl "vendor:sdl3"
import img "vendor:sdl3/image"

Asset_Cache :: struct {
	paths: map[string]Asset_Id,
}

assets_init :: proc(gpu: ^sdl.GPUDevice) {
	_ = gpu
	if state.assets.paths == nil {
		state.assets.paths = make(map[string]Asset_Id)
	}
	texture_init()
}

assets_shutdown :: proc() {
	for path, _ in state.assets.paths {
		delete(path)
	}
	delete(state.assets.paths)
	state.assets.paths = nil
	texture_shutdown()
}

assets_reload_gpu :: proc(gpu: ^sdl.GPUDevice) {
	_ = gpu
	texture_release_gpu()
	texture_reload_gpu()
}

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

assets_get_texture :: proc(id: Asset_Id) -> Texture_Handle {
	return texture_handle(id)
}

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

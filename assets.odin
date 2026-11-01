package oni

import "core:os"
import "core:path/filepath"
import "core:strings"
import sdl "vendor:sdl3"
import img "vendor:sdl3/image"

@(private)
assets_free_string :: proc(s: ^string) {
	if s == nil || len(s^) == 0 {
		return
	}

	delete(s^)
	s^ = ""
}

/*
Maps loaded file paths to registered texture asset ids.
*/
Asset_Cache :: struct {
	paths:   map[string]Asset_Id,
	io_pool: ^Asset_IO_Pool,
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
	assets_io_shutdown()
	for path, _ in state.assets.paths {
		delete(path)
	}
	delete(state.assets.paths)
	state.assets.paths = nil
	texture_shutdown()
}

/*
Releases and re-uploads all GPU textures after device recreation.

Joins asset IO workers, increments device generation, then rebuilds GPU resources.
Retained CPU surfaces return to Pending until their replacement upload is Ready.
*/
assets_reload_gpu :: proc(gpu: ^sdl.GPUDevice) {
	_ = gpu
	assets_io_shutdown()
	assets_io_bump_device_generation()
	texture_release_gpu()

	for i in 0 ..< len(state.textures.records) {
		entry := &state.textures.records[i]
		if entry.generation == 0 || entry.status == .Failed || len(entry.path) == 0 {
			continue
		}

		entry.status = .Pending
		entry.awaiting_upload = false
		entry.gpu = nil
		entry.request_token += 1
		assets_free_string(&entry.diagnostic)

		if entry.surface != nil {
			if !texture_upload_record(entry, true, Asset_Id(i)) {
				entry.status = .Failed
				entry.diagnostic = strings.clone("GPU reload upload failed")
			}

			continue
		}

		if !assets_io_enqueue(Asset_Id(i), entry.path, entry.generation, entry.request_token) {
			entry.status = .Failed
			entry.diagnostic = strings.clone("asset IO admission failed")
		}
	}

	if state.gpu != nil {
		_ = texture_uploads_flush(state.gpu)
	}

	request_frame()
}

/*
Normalizes a path key lexically (no filesystem access).
*/
@(private)
assets_normalize_path_key :: proc(path: string) -> string {
	cleaned, err := filepath.clean(path, context.temp_allocator)
	if err != nil || len(cleaned) == 0 {
		return path
	}

	return cleaned
}

/*
Requests a texture load. Returns accepted=true with a handle that may be Pending.

Disk/decode run on workers; Ready is published only after GPU upload submission.
Duplicate paths share one handle and acquire one reference. Failed records stay
Failed until `Retry_Texture`. Empty path is rejected immediately.
*/
assets_load_texture :: proc(path: string) -> (Texture_Handle, bool) {
	if state == nil || len(path) == 0 {
		return {}, false
	}

	key := assets_normalize_path_key(path)
	if len(key) == 0 {
		return {}, false
	}

	if id, ok := state.assets.paths[key]; ok {
		index := int(id)
		if index > 0 && index < len(state.textures.records) {
			entry := &state.textures.records[index]
			if entry.generation != 0 {
				entry.refs += 1
				request_frame()

				return texture_handle(id), true
			}
		}
	}

	id, handle, ok := texture_register_pending(key)
	if !ok {
		return {}, false
	}

	owned := strings.clone(key)
	state.assets.paths[owned] = id
	entry := &state.textures.records[int(id)]
	if !assets_io_enqueue(id, owned, entry.generation, entry.request_token) {
		entry.status = .Failed
		assets_free_string(&entry.diagnostic)
		entry.diagnostic = strings.clone("asset IO admission failed")
		request_frame()

		return texture_handle(id), true
	}

	request_frame()

	return handle, true
}

/*
Explicit retry for a Failed texture. Does not retry Ready/Pending.

Increments the request token and re-queues decode when admission succeeds.
*/
assets_retry_texture :: proc(handle: Texture_Handle) -> bool {
	entry := texture_record_matches_handle(handle)
	if entry == nil || entry.status != .Failed {
		return false
	}

	if len(entry.path) == 0 {
		return false
	}

	entry.status = .Pending
	entry.w = 0
	entry.h = 0
	entry.awaiting_upload = false
	entry.request_token += 1
	assets_free_string(&entry.diagnostic)

	if !assets_io_enqueue(handle.id, entry.path, entry.generation, entry.request_token) {
		entry.status = .Failed
		entry.diagnostic = strings.clone("asset IO admission failed")
		request_frame()

		return false
	}

	request_frame()

	return true
}

/*
Releases one reference acquired by Load_Texture. Final release retires the record.
*/
assets_unload_texture :: proc(handle: Texture_Handle) {
	entry := texture_record_matches_handle(handle)
	if entry == nil {
		return
	}

	entry.refs = max(0, entry.refs - 1)
	if entry.refs > 0 {
		return
	}

	if len(entry.path) > 0 {
		if id, ok := state.assets.paths[entry.path]; ok && id == handle.id {
			path_key := entry.path
			delete_key(&state.assets.paths, path_key)
			delete(path_key)
			entry.path = ""
		}
	}

	entry.request_token += 1
	entry.awaiting_upload = false
	assets_free_string(&entry.diagnostic)
	texture_retire_record(handle.id)
	if entry.generation < max(u32) {
		entry.generation += 1
	} else {
		entry.generation = 0
	}
}

/*
Returns a Texture_Handle for a previously loaded asset id.

Delegates to texture_handle (Pending/Failed report zero size).
*/
assets_get_texture :: proc(id: Asset_Id) -> Texture_Handle {
	return texture_handle(id)
}

/*
Loads an image file into an SDL surface using SDL or SDL_image.

Tries SDL_LoadSurface first, then img.Load as a fallback.
Safe to call from asset IO workers.
*/
assets_load_surface :: proc(path: string) -> (^sdl.Surface, bool) {
	info, stat_err := os.stat(path, context.allocator)
	if stat_err == nil {
		encoded_ok := info.size >= 0 && u64(info.size) <= ASSET_IO_MAX_ENCODED_BYTES
		os.file_info_delete(info, context.allocator)
		if !encoded_ok {
			log_errorf("Image %q encoded size exceeds limit", path)

			return nil, false
		}
	}

	cpath := strings.clone_to_cstring(path, context.temp_allocator)

	surface := sdl.LoadSurface(cpath)
	if surface == nil {
		surface = img.Load(cpath)
	}
	if surface == nil {
		log_errorf("Failed to load image %q: %s", path, sdl.GetError())
		return nil, false
	}

	if surface.w > ASSET_IO_MAX_IMAGE_EDGE || surface.h > ASSET_IO_MAX_IMAGE_EDGE {
		sdl.DestroySurface(surface)
		log_errorf("Image %q exceeds max edge %d", path, ASSET_IO_MAX_IMAGE_EDGE)

		return nil, false
	}

	decoded := u64(surface.w) * u64(surface.h) * 4
	if decoded > ASSET_IO_MAX_DECODED_BYTES {
		sdl.DestroySurface(surface)
		log_errorf("Image %q decoded size exceeds limit", path)

		return nil, false
	}

	return surface, true
}

/*
Creates a Pending texture record with no surface/GPU yet.
*/
texture_register_pending :: proc(path: string) -> (Asset_Id, Texture_Handle, bool) {
	if state == nil {
		return {}, {}, false
	}

	entry := Texture_Record {
		status        = .Pending,
		generation    = 1,
		request_token = 1,
		refs          = 1,
	}
	if len(path) > 0 {
		entry.path = strings.clone(path)
	}

	if _, err := append(&state.textures.records, entry); err != nil {
		delete(entry.path)

		return {}, {}, false
	}

	entry_index := len(state.textures.records) - 1
	id := Asset_Id(entry_index)

	return id, {id = id, generation = 1, w = 0, h = 0}, true
}

package app

import "core:strings"
import sdl "vendor:sdl3"

ATLAS_DEFAULT_SIZE :: 2048
ATLAS_PADDING :: 1

Texture_Record :: struct {
	gpu:     ^sdl.GPUTexture,
	surface: ^sdl.Surface,
	w, h:    i32,
	path:    string,
}

Atlas_Shelf :: struct {
	y:        i32,
	height:   i32,
	cursor_x: i32,
}

Atlas_State :: struct {
	texture_id: Asset_Id,
	width:      i32,
	height:     i32,
	shelves:    [dynamic]Atlas_Shelf,
}

Texture_State :: struct {
	records: [dynamic]Texture_Record,
	atlas:   Atlas_State,
}

texture_init :: proc() {
	if len(g.textures.records) == 0 {
		append(&g.textures.records, Texture_Record{})
	}
	if g.textures.atlas.texture_id == TEXTURE_WHITE_ID && g.textures.atlas.width == 0 {
		g.textures.atlas.texture_id = INVALID_ASSET_ID
	}
}

texture_shutdown :: proc() {
	texture_atlas_shutdown()

	for entry, i in g.textures.records {
		if i > 0 && entry.gpu != nil && g.gpu != nil {
			sdl.ReleaseGPUTexture(g.gpu, entry.gpu)
		}
		if entry.surface != nil {
			sdl.DestroySurface(entry.surface)
		}
		if len(entry.path) > 0 {
			delete(entry.path)
		}
	}
	clear(&g.textures.records)
	delete(g.textures.records)
	g.textures.records = nil
}

texture_release_gpu :: proc() {
	if g.gpu == nil do return

	for &entry in g.textures.records {
		if entry.gpu != nil {
			sdl.ReleaseGPUTexture(g.gpu, entry.gpu)
			entry.gpu = nil
		}
	}
}

texture_reload_gpu :: proc() {
	if g.gpu == nil do return

	for &entry in g.textures.records[1:] {
		if entry.surface != nil {
			texture_upload_record(&entry) or_continue
		}
	}

	if g.textures.atlas.texture_id != INVALID_ASSET_ID {
		texture_atlas_rebuild_gpu()
	}
}

texture_register_surface :: proc(
	surface: ^sdl.Surface,
	path: string,
) -> (
	Asset_Id,
	Texture_Handle,
	bool,
) {
	entry := Texture_Record {
		surface = surface,
		w       = surface.w,
		h       = surface.h,
	}
	if len(path) > 0 {
		entry.path = strings.clone(path)
	}

	append(&g.textures.records, entry)
	entry_index := len(g.textures.records) - 1
	id := Asset_Id(entry_index)

	if !texture_upload_record(&g.textures.records[entry_index]) {
		sdl.DestroySurface(g.textures.records[entry_index].surface)
		if len(g.textures.records[entry_index].path) > 0 {
			delete(g.textures.records[entry_index].path)
		}
		ordered_remove(&g.textures.records, entry_index)
		return {}, {}, false
	}

	loaded := g.textures.records[entry_index]
	handle := Texture_Handle {
		id = id,
		w  = f32(loaded.w),
		h  = f32(loaded.h),
	}
	return id, handle, true
}

texture_upload_record :: proc(entry: ^Texture_Record) -> bool {
	if g.gpu == nil || entry.surface == nil do return false

	w := entry.surface.w
	h := entry.surface.h
	if w <= 0 || h <= 0 do return false

	if entry.gpu != nil {
		sdl.ReleaseGPUTexture(g.gpu, entry.gpu)
		entry.gpu = nil
	}

	texture := sdl.CreateGPUTexture(
		g.gpu,
		{
			type = .D2,
			format = .R8G8B8A8_UNORM,
			usage = {.SAMPLER},
			width = u32(w),
			height = u32(h),
			layer_count_or_depth = 1,
			num_levels = 1,
		},
	)
	if texture == nil {
		log_errorf("SDL_CreateGPUTexture failed: %s", sdl.GetError())
		return false
	}

	if !texture_upload_surface(g.gpu, texture, entry.surface, 0, 0, w, h) {
		sdl.ReleaseGPUTexture(g.gpu, texture)
		return false
	}

	entry.gpu = texture
	entry.w = w
	entry.h = h
	return true
}

texture_upload_surface :: proc(
	gpu: ^sdl.GPUDevice,
	texture: ^sdl.GPUTexture,
	surface: ^sdl.Surface,
	dst_x, dst_y, dst_w, dst_h: i32,
) -> bool {
	if gpu == nil || texture == nil || surface == nil do return false
	if dst_w <= 0 || dst_h <= 0 do return false

	row_bytes := u32(dst_w * 4)
	byte_size := row_bytes * u32(dst_h)
	transfer := sdl.CreateGPUTransferBuffer(gpu, {usage = .UPLOAD, size = byte_size})
	if transfer == nil {
		log_errorf("SDL_CreateGPUTransferBuffer failed: %s", sdl.GetError())
		return false
	}
	defer sdl.ReleaseGPUTransferBuffer(gpu, transfer)

	mapped := sdl.MapGPUTransferBuffer(gpu, transfer, false)
	if mapped == nil {
		log_errorf("SDL_MapGPUTransferBuffer failed: %s", sdl.GetError())
		return false
	}

	converted := sdl.ConvertSurface(surface, .RGBA8888)
	if converted == nil {
		log_errorf("SDL_ConvertSurface failed: %s", sdl.GetError())
		sdl.UnmapGPUTransferBuffer(gpu, transfer)
		return false
	}
	defer if converted != surface do sdl.DestroySurface(converted)

	src_pitch := u32(converted.pitch)
	dst := cast([^]u8)mapped
	src := cast([^]u8)converted.pixels
	copy_h := min(dst_h, converted.h)
	copy_w := min(dst_w, converted.w)
	copy_row_bytes := u32(copy_w * 4)

	for row in 0 ..< copy_h {
		row_u := u32(row)
		copy(
			dst[row_u * row_bytes:(row_u + 1) * row_bytes],
			src[row_u * src_pitch:row_u * src_pitch + copy_row_bytes],
		)
	}
	sdl.UnmapGPUTransferBuffer(gpu, transfer)

	cmd := sdl.AcquireGPUCommandBuffer(gpu)
	if cmd == nil {
		log_errorf("SDL_AcquireGPUCommandBuffer failed: %s", sdl.GetError())
		return false
	}

	copy_pass := sdl.BeginGPUCopyPass(cmd)
	sdl.UploadToGPUTexture(
		copy_pass,
		{
			transfer_buffer = transfer,
			offset = 0,
			pixels_per_row = u32(dst_w),
			rows_per_layer = u32(dst_h),
		},
		{
			texture = texture,
			mip_level = 0,
			layer = 0,
			x = u32(dst_x),
			y = u32(dst_y),
			z = 0,
			w = u32(dst_w),
			h = u32(dst_h),
			d = 1,
		},
		false,
	)
	sdl.EndGPUCopyPass(copy_pass)

	if !sdl.SubmitGPUCommandBuffer(cmd) {
		log_errorf("SDL_SubmitGPUCommandBuffer failed: %s", sdl.GetError())
		return false
	}

	return true
}

texture_get_gpu :: proc(id: Asset_Id) -> ^sdl.GPUTexture {
	if id == TEXTURE_WHITE_ID {
		return g.gpu_state.white_texture
	}

	index := int(id)
	if index <= 0 || index >= len(g.textures.records) do return nil
	return g.textures.records[index].gpu
}

texture_handle :: proc(id: Asset_Id) -> Texture_Handle {
	if id == TEXTURE_WHITE_ID {
		return {id = TEXTURE_WHITE_ID, w = 1, h = 1}
	}

	index := int(id)
	if index <= 0 || index >= len(g.textures.records) do return {}
	entry := g.textures.records[index]
	return {id = id, w = f32(entry.w), h = f32(entry.h)}
}

atlas_region_from :: proc(tex: Texture_Handle, src: Rect) -> Atlas_Region {
	return Atlas_Region{texture_id = tex.id, x = src.x, y = src.y, w = src.w, h = src.h}
}

atlas_region_handle :: proc(region: Atlas_Region) -> Texture_Handle {
	return texture_handle(region.texture_id)
}

texture_atlas_init :: proc(size: i32 = ATLAS_DEFAULT_SIZE) -> bool {
	if g.textures.atlas.texture_id != INVALID_ASSET_ID && g.textures.atlas.width > 0 do return true
	if g.gpu == nil do return false

	surface := sdl.CreateSurface(size, size, .RGBA8888)
	if surface == nil {
		log_errorf("SDL_CreateSurface failed for atlas: %s", sdl.GetError())
		return false
	}

	id, _, ok := texture_register_surface(surface, "")
	if !ok {
		sdl.DestroySurface(surface)
		return false
	}

	g.textures.atlas = {
		texture_id = id,
		width      = size,
		height     = size,
	}
	return true
}

texture_atlas_shutdown :: proc() {
	delete(g.textures.atlas.shelves)
	g.textures.atlas = {}
}

texture_atlas_rebuild_gpu :: proc() {
	if g.textures.atlas.texture_id == INVALID_ASSET_ID do return

	index := int(g.textures.atlas.texture_id)
	if index <= 0 || index >= len(g.textures.records) do return

	entry := &g.textures.records[index]
	if entry.surface == nil do return

	if !texture_upload_record(entry) {
		log_error("Failed to rebuild atlas GPU texture after hot reload")
	}
}

texture_atlas_alloc :: proc(w, h: i32) -> (Atlas_Region, bool) {
	if w <= 0 || h <= 0 do return {}, false
	if !texture_atlas_init() do return {}, false

	atlas := &g.textures.atlas
	pad := i32(ATLAS_PADDING)
	need_w := w + pad
	need_h := h + pad

	for &shelf in atlas.shelves {
		if shelf.height < need_h do continue
		if shelf.cursor_x + need_w > atlas.width do continue

		region := Atlas_Region {
			texture_id = atlas.texture_id,
			x          = f32(shelf.cursor_x),
			y          = f32(shelf.y),
			w          = f32(w),
			h          = f32(h),
		}
		shelf.cursor_x += need_w
		return region, true
	}

	new_y: i32 = 0
	if len(atlas.shelves) > 0 {
		last := atlas.shelves[len(atlas.shelves) - 1]
		new_y = last.y + last.height
	}
	if new_y + need_h > atlas.height {
		log_errorf("Atlas out of space for %dx%d region", w, h)
		return {}, false
	}

	append(&atlas.shelves, Atlas_Shelf{y = new_y, height = need_h, cursor_x = need_w})
	return Atlas_Region {
			texture_id = atlas.texture_id,
			x = 0,
			y = f32(new_y),
			w = f32(w),
			h = f32(h),
		},
		true
}

texture_atlas_upload :: proc(region: Atlas_Region, surface: ^sdl.Surface) -> bool {
	if g.textures.atlas.texture_id == INVALID_ASSET_ID do return false
	if region.texture_id != g.textures.atlas.texture_id do return false
	if surface == nil do return false

	index := int(g.textures.atlas.texture_id)
	if index <= 0 || index >= len(g.textures.records) do return false
	entry := &g.textures.records[index]
	if entry.gpu == nil do return false

	dst_x := i32(region.x)
	dst_y := i32(region.y)
	dst_w := i32(region.w)
	dst_h := i32(region.h)

	if !texture_upload_surface(g.gpu, entry.gpu, surface, dst_x, dst_y, dst_w, dst_h) {
		return false
	}

	atlas_surface := entry.surface
	if atlas_surface != nil {
		converted := sdl.ConvertSurface(surface, .RGBA8888)
		if converted != nil {
			defer if converted != surface do sdl.DestroySurface(converted)
			src_pitch := converted.pitch
			dst_pitch := atlas_surface.pitch
			src := cast([^]u8)converted.pixels
			dst := cast([^]u8)atlas_surface.pixels
			copy_w := min(dst_w, converted.w)
			copy_h := min(dst_h, converted.h)
			for row in 0 ..< copy_h {
				src_off := row * src_pitch
				dst_off := (dst_y + row) * dst_pitch + dst_x * 4
				copy(dst[dst_off:dst_off + copy_w * 4], src[src_off:src_off + copy_w * 4])
			}
		}
	}

	return true
}

texture_atlas_pack :: proc(surface: ^sdl.Surface) -> (Atlas_Region, bool) {
	if surface == nil do return {}, false

	shelf_count := len(g.textures.atlas.shelves)
	region, ok := texture_atlas_alloc(surface.w, surface.h)
	if !ok do return {}, false

	if !texture_atlas_upload(region, surface) {
		resize(&g.textures.atlas.shelves, shelf_count)
		return {}, false
	}

	return region, true
}

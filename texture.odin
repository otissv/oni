package oni

import "core:strings"
import sdl "vendor:sdl3"

ATLAS_DEFAULT_SIZE :: 2048
ATLAS_PADDING :: 1

/*
Single registered texture: GPU handle, CPU surface, dimensions, and source path.
*/
Texture_Record :: struct {
	gpu:     ^sdl.GPUTexture,
	surface: ^sdl.Surface,
	w, h:    i32,
	path:    string,
}

/*
One horizontal shelf row in the shelf atlas packer with cursor position.
*/
Atlas_Shelf :: struct {
	y:        i32,
	height:   i32,
	cursor_x: i32,
}

/*
Shelf atlas backing texture and its row allocation bookkeeping.
*/
Atlas_State :: struct {
	texture_id: Asset_Id,
	width:      i32,
	height:     i32,
	shelves:    [dynamic]Atlas_Shelf,
}

/*
One deferred GPU texture upload: copies a sub-rect from a CPU surface into a GPU texture.

`surface` is borrowed and must remain valid until `texture_uploads_flush`.
Atlas glyph packs point at the shared atlas CPU surface with matching src/dst offsets.
*/
Pending_Upload :: struct {
	texture:                    ^sdl.GPUTexture,
	surface:                    ^sdl.Surface,
	dst_x, dst_y, dst_w, dst_h: i32,
	src_x, src_y:               i32,
}

/*
All texture records plus the shared glyph/image atlas state.
*/
Texture_State :: struct {
	records:         [dynamic]Texture_Record,
	atlas:           Atlas_State,
	pending_uploads: [dynamic]Pending_Upload,
}

/*
Initializes texture state with a reserved slot-zero record and a cleared atlas.

Safe to call multiple times; only allocates the records array on first use.
*/
texture_init :: proc() {
	if len(state.textures.records) == 0 {
		append(&state.textures.records, Texture_Record{})
	}
	if state.textures.atlas.texture_id == TEXTURE_WHITE_ID && state.textures.atlas.width == 0 {
		state.textures.atlas.texture_id = INVALID_ASSET_ID
	}
}

/*
Releases all GPU textures, surfaces, and path strings owned by texture state.

Also shuts down the atlas and clears the records array.
*/
texture_shutdown :: proc() {
	texture_atlas_shutdown()

	clear(&state.textures.pending_uploads)
	delete(state.textures.pending_uploads)
	state.textures.pending_uploads = nil

	for entry, i in state.textures.records {
		if i > 0 && entry.gpu != nil && state.gpu != nil {
			sdl.ReleaseGPUTexture(state.gpu, entry.gpu)
		}
		if entry.surface != nil {
			sdl.DestroySurface(entry.surface)
		}
		if len(entry.path) > 0 {
			delete(entry.path)
		}
	}
	clear(&state.textures.records)
	delete(state.textures.records)
	state.textures.records = nil
}

/*
Releases GPU textures for all records while keeping CPU surfaces intact.

Used before device teardown or hot reload so surfaces can be re-uploaded later.
*/
texture_release_gpu :: proc() {
	// Drop pending uploads first — they hold pointers to GPU textures about to be released.
	clear(&state.textures.pending_uploads)

	if state.gpu == nil do return

	for &entry in state.textures.records {
		if entry.gpu != nil {
			sdl.ReleaseGPUTexture(state.gpu, entry.gpu)
			entry.gpu = nil
		}
	}
}

/*
Re-uploads every record surface to the GPU and rebuilds the atlas texture.

Call after the GPU device is recreated, such as during hot reload.
Queues all record uploads and submits them in one flush before the atlas rebuild pass.
*/
texture_reload_gpu :: proc() {
	if state.gpu == nil do return

	for &entry in state.textures.records[1:] {
		if entry.surface != nil {
			texture_upload_record(&entry, true) or_continue
		}
	}
	// Flush before atlas rebuild so pending refs stay valid (rebuild recreates the GPU texture).
	_ = texture_uploads_flush(state.gpu)

	if state.textures.atlas.texture_id != INVALID_ASSET_ID {
		texture_atlas_rebuild_gpu()
	}
}

/*
Registers a loaded surface as a texture record and uploads it to the GPU.

Returns the asset id, handle, and false if upload or registration fails.
*/
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

	append(&state.textures.records, entry)
	entry_index := len(state.textures.records) - 1
	id := Asset_Id(entry_index)

	if !texture_upload_record(&state.textures.records[entry_index]) {
		sdl.DestroySurface(state.textures.records[entry_index].surface)
		if len(state.textures.records[entry_index].path) > 0 {
			delete(state.textures.records[entry_index].path)
		}
		ordered_remove(&state.textures.records, entry_index)
		return {}, {}, false
	}

	loaded := state.textures.records[entry_index]
	handle := Texture_Handle {
		id = id,
		w  = f32(loaded.w),
		h  = f32(loaded.h),
	}
	return id, handle, true
}

/*
Swizzles one row of SDL RGBA8888 pixels into GPU R8G8B8A8 byte order.

SDL stores 32-bit pixels as A,B,G,R in memory on little-endian hosts;
Vulkan R8G8B8A8_UNORM expects R,G,B,A.
*/
@(private)
surface_row_to_gpu_rgba :: proc(dst, src: []u8, pixels: int) {
	when ODIN_ENDIAN == .Little {
		for i in 0 ..< pixels {
			off := i * 4
			dst[off + 0] = src[off + 3]
			dst[off + 1] = src[off + 2]
			dst[off + 2] = src[off + 1]
			dst[off + 3] = src[off + 0]
		}
	} else {
		copy(dst[:pixels * 4], src[:pixels * 4])
	}
}

/*
Creates or replaces the GPU texture for a single texture record from its surface.

Releases any existing GPU texture on the record before uploading.
When `deferred` is true, the pixel copy is queued for `texture_uploads_flush`
instead of submitting immediately.
*/
texture_upload_record :: proc(entry: ^Texture_Record, deferred := false) -> bool {
	if state.gpu == nil || entry.surface == nil do return false

	w := entry.surface.w
	h := entry.surface.h
	if w <= 0 || h <= 0 do return false

	if entry.gpu != nil {
		sdl.ReleaseGPUTexture(state.gpu, entry.gpu)
		entry.gpu = nil
	}

	texture := sdl.CreateGPUTexture(
		state.gpu,
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

	ok: bool
	if deferred {
		ok = texture_upload_surface_deferred(state.gpu, texture, entry.surface, 0, 0, w, h)
	} else {
		ok = texture_upload_surface(state.gpu, texture, entry.surface, 0, 0, w, h)
	}
	if !ok {
		sdl.ReleaseGPUTexture(state.gpu, texture)
		return false
	}

	entry.gpu = texture
	entry.w = w
	entry.h = h
	return true
}

/*
Resolves a surface to RGBA8888 for upload, returning whether the result is owned.
*/
@(private)
texture_surface_as_rgba8888 :: proc(surface: ^sdl.Surface) -> (converted: ^sdl.Surface, owned: bool) {
	if surface == nil do return nil, false
	if surface.format == .RGBA8888 do return surface, false
	converted = sdl.ConvertSurface(surface, .RGBA8888)
	if converted == nil {
		log_errorf("SDL_ConvertSurface failed: %s", sdl.GetError())
		return nil, false
	}
	return converted, converted != surface
}

/*
Fills a mapped transfer buffer with a sub-rect of a surface in GPU R8G8B8A8 order.
*/
@(private)
texture_fill_transfer_from_surface :: proc(
	gpu: ^sdl.GPUDevice,
	transfer: ^sdl.GPUTransferBuffer,
	surface: ^sdl.Surface,
	src_x, src_y, copy_w, copy_h: i32,
) -> bool {
	if gpu == nil || transfer == nil || surface == nil do return false
	if copy_w <= 0 || copy_h <= 0 do return false
	if src_x < 0 || src_y < 0 do return false

	mapped := sdl.MapGPUTransferBuffer(gpu, transfer, false)
	if mapped == nil {
		log_errorf("SDL_MapGPUTransferBuffer failed: %s", sdl.GetError())
		return false
	}

	converted, owned := texture_surface_as_rgba8888(surface)
	if converted == nil {
		sdl.UnmapGPUTransferBuffer(gpu, transfer)
		return false
	}
	defer if owned do sdl.DestroySurface(converted)

	row_bytes := u32(copy_w * 4)
	src_pitch := u32(converted.pitch)
	dst := cast([^]u8)mapped
	src := cast([^]u8)converted.pixels

	avail_w := converted.w - src_x
	avail_h := converted.h - src_y
	if avail_w <= 0 || avail_h <= 0 {
		sdl.UnmapGPUTransferBuffer(gpu, transfer)
		return false
	}
	use_w := min(copy_w, avail_w)
	use_h := min(copy_h, avail_h)
	use_row_bytes := u32(use_w * 4)

	for row in 0 ..< use_h {
		row_u := u32(row)
		dst_row := dst[row_u * row_bytes:]
		src_row := src[u32(src_y + row) * src_pitch + u32(src_x) * 4:]
		surface_row_to_gpu_rgba(dst_row[:use_row_bytes], src_row[:use_row_bytes], int(use_w))
	}
	sdl.UnmapGPUTransferBuffer(gpu, transfer)
	return true
}

/*
Creates a transfer buffer sized for a w×h RGBA upload and fills it from a surface region.
*/
@(private)
texture_create_filled_transfer :: proc(
	gpu: ^sdl.GPUDevice,
	surface: ^sdl.Surface,
	src_x, src_y, w, h: i32,
) -> ^sdl.GPUTransferBuffer {
	if gpu == nil || surface == nil || w <= 0 || h <= 0 do return nil

	row_bytes := u32(w * 4)
	byte_size := row_bytes * u32(h)
	transfer := sdl.CreateGPUTransferBuffer(gpu, {usage = .UPLOAD, size = byte_size})
	if transfer == nil {
		log_errorf("SDL_CreateGPUTransferBuffer failed: %s", sdl.GetError())
		return nil
	}
	if !texture_fill_transfer_from_surface(gpu, transfer, surface, src_x, src_y, w, h) {
		sdl.ReleaseGPUTransferBuffer(gpu, transfer)
		return nil
	}
	return transfer
}

/*
Queues a surface sub-rect for GPU upload without acquiring a command buffer.

Call `texture_uploads_flush` to submit all pending uploads in one copy pass.
*/
texture_upload_surface_deferred :: proc(
	gpu: ^sdl.GPUDevice,
	texture: ^sdl.GPUTexture,
	surface: ^sdl.Surface,
	dst_x, dst_y, dst_w, dst_h: i32,
	src_x: i32 = 0,
	src_y: i32 = 0,
) -> bool {
	if gpu == nil || texture == nil || surface == nil do return false
	if dst_w <= 0 || dst_h <= 0 do return false

	append(
		&state.textures.pending_uploads,
		Pending_Upload {
			texture = texture,
			surface = surface,
			dst_x = dst_x,
			dst_y = dst_y,
			dst_w = dst_w,
			dst_h = dst_h,
			src_x = src_x,
			src_y = src_y,
		},
	)
	return true
}

/*
Submits all pending texture uploads in a single command buffer / copy pass.

Clears the queue on success or failure. Transfers are always released.
*/
texture_uploads_flush :: proc(gpu: ^sdl.GPUDevice) -> bool {
	uploads := state.textures.pending_uploads[:]
	if len(uploads) == 0 do return true
	defer clear(&state.textures.pending_uploads)

	if gpu == nil do return false

	transfers := make([dynamic]^sdl.GPUTransferBuffer, 0, len(uploads))
	defer {
		for t in transfers {
			if t != nil do sdl.ReleaseGPUTransferBuffer(gpu, t)
		}
		delete(transfers)
	}

	for upload in uploads {
		transfer := texture_create_filled_transfer(
			gpu,
			upload.surface,
			upload.src_x,
			upload.src_y,
			upload.dst_w,
			upload.dst_h,
		)
		if transfer == nil do return false
		append(&transfers, transfer)
	}

	cmd := sdl.AcquireGPUCommandBuffer(gpu)
	if cmd == nil {
		log_errorf("SDL_AcquireGPUCommandBuffer failed: %s", sdl.GetError())
		return false
	}

	copy_pass := sdl.BeginGPUCopyPass(cmd)
	for i in 0 ..< len(uploads) {
		upload := uploads[i]
		sdl.UploadToGPUTexture(
			copy_pass,
			{
				transfer_buffer = transfers[i],
				offset = 0,
				pixels_per_row = u32(upload.dst_w),
				rows_per_layer = u32(upload.dst_h),
			},
			{
				texture = upload.texture,
				mip_level = 0,
				layer = 0,
				x = u32(upload.dst_x),
				y = u32(upload.dst_y),
				z = 0,
				w = u32(upload.dst_w),
				h = u32(upload.dst_h),
				d = 1,
			},
			false,
		)
	}
	sdl.EndGPUCopyPass(copy_pass)

	if !sdl.SubmitGPUCommandBuffer(cmd) {
		log_errorf("SDL_SubmitGPUCommandBuffer failed: %s", sdl.GetError())
		return false
	}

	return true
}

/*
Uploads a sub-rectangle of a surface into a GPU texture via a transfer buffer.

Converts the source to RGBA8888, swizzles to GPU byte order, and submits a copy pass.
Immediate path used by tests and non-deferred callers; prefers `texture_upload_surface_deferred`
+ flush for atlas packs and hot-reload batches.
*/
texture_upload_surface :: proc(
	gpu: ^sdl.GPUDevice,
	texture: ^sdl.GPUTexture,
	surface: ^sdl.Surface,
	dst_x, dst_y, dst_w, dst_h: i32,
	src_x: i32 = 0,
	src_y: i32 = 0,
) -> bool {
	if gpu == nil || texture == nil || surface == nil do return false
	if dst_w <= 0 || dst_h <= 0 do return false

	transfer := texture_create_filled_transfer(gpu, surface, src_x, src_y, dst_w, dst_h)
	if transfer == nil do return false
	defer sdl.ReleaseGPUTransferBuffer(gpu, transfer)

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

/*
Returns the GPU texture pointer for an asset id, or nil if invalid.

The white texture id resolves to the engine's built-in 1x1 white texture.
*/
texture_get_gpu :: proc(id: Asset_Id) -> ^sdl.GPUTexture {
	if id == TEXTURE_WHITE_ID {
		return state.gpu_state.white_texture
	}

	index := int(id)
	if index <= 0 || index >= len(state.textures.records) do return nil
	return state.textures.records[index].gpu
}

/*
Builds a Texture_Handle with pixel dimensions for a registered asset id.

Returns an empty handle when the id is out of range.
*/
texture_handle :: proc(id: Asset_Id) -> Texture_Handle {
	if id == TEXTURE_WHITE_ID {
		return {id = TEXTURE_WHITE_ID, w = 1, h = 1}
	}

	index := int(id)
	if index <= 0 || index >= len(state.textures.records) do return {}
	entry := state.textures.records[index]
	return {id = id, w = f32(entry.w), h = f32(entry.h)}
}

/*
Wraps a texture handle and source rect into an atlas region descriptor.

The region references the parent texture id with sub-rectangle coordinates.
*/
atlas_region_from :: proc(tex: Texture_Handle, src: Rect) -> Atlas_Region {
	return Atlas_Region{texture_id = tex.id, x = src.x, y = src.y, w = src.w, h = src.h}
}

/*
Returns the parent Texture_Handle for an atlas sub-region.

Delegates to texture_handle using the region's texture_id.
*/
atlas_region_handle :: proc(region: Atlas_Region) -> Texture_Handle {
	return texture_handle(region.texture_id)
}

/*
Creates the shelf atlas backing texture at the given size if not already initialized.

Registers an empty RGBA surface as the atlas record and records shelf state.
*/
texture_atlas_init :: proc(size: i32 = ATLAS_DEFAULT_SIZE) -> bool {
	if state.textures.atlas.texture_id != INVALID_ASSET_ID && state.textures.atlas.width > 0 do return true
	if state.gpu == nil do return false

	surface := sdl.CreateSurface(size, size, .RGBA8888)
	if surface == nil {
		log_errorf("SDL_CreateSurface failed for atlas: %s", sdl.GetError())
		return false
	}

	id, _, ok := texture_register_surface(surface, "")
	if !ok {
		// texture_register_surface destroys the surface on upload failure.
		return false
	}

	state.textures.atlas = {
		texture_id = id,
		width      = size,
		height     = size,
	}
	return true
}

/*
Frees atlas shelf bookkeeping and resets atlas state to empty.

Does not destroy the underlying atlas texture record.
*/
texture_atlas_shutdown :: proc() {
	delete(state.textures.atlas.shelves)
	state.textures.atlas = {}
}

/*
Re-uploads the atlas backing texture from its CPU surface after GPU reload.

Logs an error if the atlas record or upload is unavailable.
*/
texture_atlas_rebuild_gpu :: proc() {
	if state.textures.atlas.texture_id == INVALID_ASSET_ID do return

	index := int(state.textures.atlas.texture_id)
	if index <= 0 || index >= len(state.textures.records) do return

	entry := &state.textures.records[index]
	if entry.surface == nil do return

	if !texture_upload_record(entry) {
		log_error("Failed to rebuild atlas GPU texture after hot reload")
	}
}

/*
Allocates a padded w×h rectangle in the shelf atlas using first-fit placement.

Opens a new shelf row when no existing shelf has room; returns false when full.
*/
texture_atlas_alloc :: proc(w, h: i32) -> (Atlas_Region, bool) {
	if w <= 0 || h <= 0 do return {}, false
	if !texture_atlas_init() do return {}, false

	atlas := &state.textures.atlas
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

/*
Uploads a surface into an allocated atlas region on both GPU and CPU backing.

Copies pixels into the atlas CPU surface first, then queues a deferred GPU upload
of that region from the shared atlas surface (flushed in present / reload).
*/
texture_atlas_upload :: proc(region: Atlas_Region, surface: ^sdl.Surface) -> bool {
	if state.textures.atlas.texture_id == INVALID_ASSET_ID do return false
	if region.texture_id != state.textures.atlas.texture_id do return false
	if surface == nil do return false

	index := int(state.textures.atlas.texture_id)
	if index <= 0 || index >= len(state.textures.records) do return false
	entry := &state.textures.records[index]
	if entry.gpu == nil do return false

	dst_x := i32(region.x)
	dst_y := i32(region.y)
	dst_w := i32(region.w)
	dst_h := i32(region.h)

	// Validate / convert before mutating the CPU atlas so bad formats fail cleanly.
	converted, owned := texture_surface_as_rgba8888(surface)
	if converted == nil do return false
	defer if owned do sdl.DestroySurface(converted)

	atlas_surface := entry.surface
	if atlas_surface != nil {
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

		// GPU copy of the packed region from the long-lived atlas CPU surface.
		return texture_upload_surface_deferred(
			state.gpu,
			entry.gpu,
			atlas_surface,
			dst_x,
			dst_y,
			dst_w,
			dst_h,
			dst_x,
			dst_y,
		)
	}

	// No CPU atlas — upload the converted source immediately (tests / edge cases).
	return texture_upload_surface(state.gpu, entry.gpu, converted, dst_x, dst_y, dst_w, dst_h)
}

/*
Allocates atlas space for a surface and uploads it in one step.

Rolls back the shelf allocation if the upload fails.
*/
texture_atlas_pack :: proc(surface: ^sdl.Surface) -> (Atlas_Region, bool) {
	if surface == nil do return {}, false

	shelf_count := len(state.textures.atlas.shelves)
	region, ok := texture_atlas_alloc(surface.w, surface.h)
	if !ok do return {}, false

	if !texture_atlas_upload(region, surface) {
		resize(&state.textures.atlas.shelves, shelf_count)
		return {}, false
	}

	return region, true
}

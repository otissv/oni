package oni

import "core:strings"
import "core:sync"
import sdl "vendor:sdl3"

ATLAS_DEFAULT_SIZE :: 2048
ATLAS_HARD_MAX :: 8192
ATLAS_PADDING :: 1
ATLAS_OVERFLOW_CAP :: 2
ATLAS_SAMPLER_SLOTS :: 4
// Glyphs unused for this many frames are cold and eligible for eviction (Group C).
ATLAS_EVICT_COLD_FRAMES :: 3
// Prefetch starts Pinned|Prefetched; clear both after this many unused frames.
ATLAS_PREFETCH_PIN_FRAMES :: 5

/*
Atlas / glyph concurrency contract (Group G):

| Resource | Read | Write |
|----------|------|-------|
| Shelves / atlas CPU surface / generation | owner thread | owner only (pack, evict, repack, grow, reset) |
| `glyph_cache` | owner | owner only (insert after pack; delete on evict) |
| `pending_uploads` | owner / present flush | owner pack/upload only |
| FreeType shared library / face | owner face ops | workers: temp library+face only |
| Batch / GPU atlas binds | render / present | not mid-draw |

`owner_mutex` (recursive) serializes ensure/prefetch/funnel/repack/reset and all
shelf mutators. FreeType raster workers may run only while the owner holds the
lock and must join before any shelf/cache mutate (`raster_workers` must be 0).
*/

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

`cursor_x` advances only on successful placement. It never moves backward except
via explicit rewind (failed pack rollback) or a future repack that rebuilds shelves.
*/
Atlas_Shelf :: struct {
	y:        i32,
	height:   i32,
	cursor_x: i32,
}

/*
Shelf atlas backing texture and its row allocation bookkeeping.

Invariants:
- Shelf `cursor_x` never moves backward except explicit rewind or repack.
- Packed `Atlas_Region` values are invalid after atlas reset / repack / grow until
  every consumer (glyph cache) is rewritten or cleared.
- Atlas mutation (pack, alloc, shelf rewind, reset, repack, grow) is single-owner:
  only the engine owner path may mutate shelves / CPU surface; workers must not.
- `generation` bumps on reset / repack / grow; glyph cache entries must match.
- Occupancy (`bytes_used`, `slot_count`) tracks successful padded allocations;
  pack rewind and atlas reset keep it accurate.
- Glyph residency stamps use engine frame index `state.ui.frame`.
- `needs_repack` is set when cold glyphs are evicted; cleared after compaction.
- `repacking` is true only while `atlas_compact` mutates shelves (blocks nested recover).
*/
Atlas_State :: struct {
	texture_id:   Asset_Id,
	width:        i32,
	height:       i32,
	shelves:      [dynamic]Atlas_Shelf,
	generation:   u32,
	bytes_used:   u64,
	slot_count:   u32,
	needs_repack: bool,
	repacking:    bool,
}

/*
How atlas textures are sampled at draw time.

`Unset` until GPU pipeline creation probes multi-sampler support.
SDL_GPU ships `Multi_Texture` (four consecutive samplers); true descriptor-index
bindless is not used. `Fallback_Split` is the tested capability fallback.
*/
Atlas_Draw_Mode :: enum u8 {
	Unset = 0,
	Multi_Texture,
	Fallback_Split,
}

/*
Why the last atlas pack funnel attempt failed (Group F).

`None` after a successful pack. Oversize never mutates shelves.
*/
Atlas_Pack_Fail :: enum u8 {
	None = 0,
	Nil_Surface,
	Init_Failed,
	Oversize,
	Upload_Failed,
	Exhausted,
	Nested_Repack,
	Flush_Failed,
}

/*
Snapshot of atlas occupancy and residency bookkeeping.

Exposed via `Get_Atlas_Stats` / `atlas_stats`.
*/
Atlas_Stats :: struct {
	width:          i32,
	height:         i32,
	bytes_used:     u64,
	bytes_total:    u64,
	used_percent:   f32,
	slot_count:     u32,
	cache_count:    int,
	generation:     u32,
	overflow_count: int,
	draw_mode:      Atlas_Draw_Mode,
	frame:          u64,
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
	records:               [dynamic]Texture_Record,
	atlas:                 Atlas_State,
	overflow:              [dynamic]Atlas_State,
	pending_uploads:       [dynamic]Pending_Upload,
	// Probed max 2D texture edge (RGBA8). 0 = not probed; tests may override.
	max_2d_texture_size:   i32,
	atlas_draw_mode:       Atlas_Draw_Mode,
	atlas_fallback_logged: bool,
	last_pack_fail:        Atlas_Pack_Fail,
	// Group G: recursive so funnel/repack may nest under ensure/prefetch.
	owner_mutex:           sync.Recursive_Mutex,
	owner_depth:           int,
	// Count of live FreeType raster worker threads; must be 0 before shelf mutate.
	raster_workers:        int,
}

/*
Acquires the atlas owner lock (recursive). Pair with `defer atlas_owner_unlock()`.
*/
atlas_owner_lock :: proc() {
	if state == nil {
		return
	}

	sync.recursive_mutex_lock(&state.textures.owner_mutex)
	state.textures.owner_depth += 1
}

/*
Releases one atlas owner lock acquisition.
*/
atlas_owner_unlock :: proc() {
	if state == nil {
		return
	}

	if state.textures.owner_depth <= 0 {
		return
	}

	state.textures.owner_depth -= 1
	sync.recursive_mutex_unlock(&state.textures.owner_mutex)
}

/*
Non-blocking owner lock for concurrent-misuse tests.
*/
atlas_owner_try_lock :: proc() -> bool {
	if state == nil {
		return false
	}

	if !sync.recursive_mutex_try_lock(&state.textures.owner_mutex) {
		return false
	}

	state.textures.owner_depth += 1

	return true
}

/*
Debug: panics when a shelf/cache mutator runs without the owner lock.
*/
atlas_owner_assert_held :: proc() {
	when ODIN_DEBUG {
		if state == nil || state.textures.owner_depth <= 0 {
			panic("atlas mutation without owner lock (Group G)")
		}
	}
}

/*
Debug: panics when shelves/cache mutate while FreeType raster workers are live.
*/
atlas_owner_assert_no_raster_workers :: proc() {
	when ODIN_DEBUG {
		if state != nil && state.textures.raster_workers != 0 {
			panic("atlas mutation while raster workers active (Group G)")
		}
	}
}

/*
Marks the start of a FreeType raster worker burst (owner lock must be held).
*/
atlas_owner_begin_raster_workers :: proc(count: int) {
	atlas_owner_assert_held()
	atlas_owner_assert_no_raster_workers()
	if state == nil {
		return
	}

	state.textures.raster_workers = count
}

/*
Clears the raster worker burst counter after all workers have joined.
*/
atlas_owner_end_raster_workers :: proc() {
	atlas_owner_assert_held()
	if state == nil {
		return
	}

	state.textures.raster_workers = 0
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

	if texture_atlas_count() > 0 {
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
RGBA upload byte count for a w×h region, or false when the size overflows u32.
*/
@(private)
texture_transfer_byte_size :: proc(w, h: i32) -> (size: u32, ok: bool) {
	if w <= 0 || h <= 0 do return 0, false

	wide := u64(w) * u64(h) * 4
	if wide > u64(max(u32)) do return 0, false

	return u32(wide), true
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
	if src_x < 0 || src_y < 0 do return false

	_, size_ok := texture_transfer_byte_size(copy_w, copy_h)
	if !size_ok do return false

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

	row_bytes := u32(copy_w) * 4
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
	use_row_bytes := u32(use_w) * 4

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
	if gpu == nil || surface == nil do return nil

	byte_size, size_ok := texture_transfer_byte_size(w, h)
	if !size_ok {
		log_errorf("texture transfer size overflows u32 (%dx%d)", w, h)
		return nil
	}

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

	transfers := make([dynamic]^sdl.GPUTransferBuffer, 0, len(uploads), context.temp_allocator)
	defer {
		for t in transfers {
			if t != nil do sdl.ReleaseGPUTransferBuffer(gpu, t)
		}
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
Releases GPU/CPU resources for a non-atlas texture record without reclaiming the
asset-id slot (tombstone). Atlas sheet ids are rejected.
*/
texture_retire_record :: proc(id: Asset_Id) {
	if state == nil {
		return
	}

	if texture_atlas_by_id(id) != nil {
		return
	}

	index := int(id)
	if index <= 0 || index >= len(state.textures.records) {
		return
	}

	entry := &state.textures.records[index]
	if entry.gpu != nil && state.gpu != nil {
		sdl.ReleaseGPUTexture(state.gpu, entry.gpu)
		entry.gpu = nil
	}

	if entry.surface != nil {
		sdl.DestroySurface(entry.surface)
		entry.surface = nil
	}

	if len(entry.path) > 0 {
		delete(entry.path)
		entry.path = ""
	}

	entry.w = 0
	entry.h = 0
}

/*
True when padded w×h cannot fit any atlas sheet even after capped growth.
*/
texture_atlas_padded_exceeds_effective_max :: proc(w, h: i32) -> bool {
	if w <= 0 || h <= 0 {
		return true
	}

	max_edge := texture_atlas_effective_max()
	if max_edge <= 0 {
		return true
	}

	pad := i32(ATLAS_PADDING)

	return w + pad > max_edge || h + pad > max_edge
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
Engine frame index used for glyph residency stamps (`state.ui.frame`).
*/
atlas_current_frame :: proc() -> u64 {
	if state == nil {
		return 0
	}

	return state.ui.frame
}

/*
Probes the largest power-of-two 2D RGBA8 texture the device can create.

Tries `ATLAS_HARD_MAX` downward by halves until CreateGPUTexture succeeds.
Returns `ATLAS_DEFAULT_SIZE` when the device is missing or even the default fails.
*/
gpu_probe_max_2d_texture_size :: proc(device: ^sdl.GPUDevice) -> i32 {
	if device == nil {
		return ATLAS_DEFAULT_SIZE
	}

	size := i32(ATLAS_HARD_MAX)
	for size >= ATLAS_DEFAULT_SIZE {
		texture := sdl.CreateGPUTexture(
			device,
			{
				type = .D2,
				format = .R8G8B8A8_UNORM,
				usage = {.SAMPLER},
				width = u32(size),
				height = u32(size),
				layer_count_or_depth = 1,
				num_levels = 1,
			},
		)
		if texture != nil {
			sdl.ReleaseGPUTexture(device, texture)

			return size
		}

		size /= 2
	}

	// Last resort: accept below default if HARD/DEFAULT both fail (rare).
	for size >= 64 {
		texture := sdl.CreateGPUTexture(
			device,
			{
				type = .D2,
				format = .R8G8B8A8_UNORM,
				usage = {.SAMPLER},
				width = u32(size),
				height = u32(size),
				layer_count_or_depth = 1,
				num_levels = 1,
			},
		)
		if texture != nil {
			sdl.ReleaseGPUTexture(device, texture)

			return size
		}

		size /= 2
	}

	return ATLAS_DEFAULT_SIZE
}

/*
Caches the device max 2D texture size on texture state (idempotent).

Tests may set `max_2d_texture_size` before calling to skip/override the probe.
*/
texture_atlas_probe_device_max :: proc() {
	if state == nil {
		return
	}

	if state.textures.max_2d_texture_size > 0 {
		return
	}

	state.textures.max_2d_texture_size = gpu_probe_max_2d_texture_size(state.gpu)
}

/*
Effective atlas growth ceiling: `min(ATLAS_HARD_MAX, device max)`.
*/
texture_atlas_effective_max :: proc() -> i32 {
	texture_atlas_probe_device_max()
	device_max := state.textures.max_2d_texture_size
	if device_max <= 0 {
		device_max = ATLAS_DEFAULT_SIZE
	}

	return min(i32(ATLAS_HARD_MAX), device_max)
}

/*
Selects the atlas draw path after the multi-sampler pipeline capability probe.

The test hook exercises the split path on devices that normally support four
samplers. The warning is emitted at most once per texture-state lifetime.
*/
texture_atlas_select_draw_mode :: proc(multi_texture_supported: bool) {
	if state == nil {
		return
	}

	if multi_texture_supported && !test_hook_atlas_force_fallback_split {
		state.textures.atlas_draw_mode = .Multi_Texture

		return
	}

	state.textures.atlas_draw_mode = .Fallback_Split
	if !state.textures.atlas_fallback_logged {
		log_warn("Atlas multi-texture sampling unavailable; using split batches")
		state.textures.atlas_fallback_logged = true
		test_hook_atlas_fallback_log_count += 1
	}
}

/*
Padded RGBA byte footprint for a w×h atlas allocation.
*/
texture_atlas_padded_bytes :: proc(w, h: i32) -> u64 {
	pad := i32(ATLAS_PADDING)
	need_w := u64(w + pad)
	need_h := u64(h + pad)

	return need_w * need_h * 4
}

/*
Records occupancy for a successful padded allocation.
*/
texture_atlas_occupancy_add :: proc(atlas: ^Atlas_State, w, h: i32) {
	if atlas == nil {
		return
	}

	atlas.bytes_used += texture_atlas_padded_bytes(w, h)
	atlas.slot_count += 1
}

/*
Reverses occupancy after a failed pack rewind or eviction.
*/
texture_atlas_occupancy_sub :: proc(atlas: ^Atlas_State, w, h: i32) {
	if atlas == nil {
		return
	}

	delta := texture_atlas_padded_bytes(w, h)

	if atlas.bytes_used >= delta {
		atlas.bytes_used -= delta
	} else {
		atlas.bytes_used = 0
	}

	if atlas.slot_count > 0 {
		atlas.slot_count -= 1
	}
}

/*
Clears shelf occupancy counters without touching texture identity or generation.
*/
texture_atlas_occupancy_clear :: proc(atlas: ^Atlas_State = nil) {
	target := atlas
	if target == nil {
		target = &state.textures.atlas
	}

	target.bytes_used = 0
	target.slot_count = 0
}

/*
Returns the number of live atlas sheets (primary plus overflow).
*/
texture_atlas_count :: proc() -> int {
	if state == nil || state.textures.atlas.texture_id == INVALID_ASSET_ID {
		return 0
	}

	return 1 + len(state.textures.overflow)
}

/*
Resolves an atlas sheet by texture id.
*/
texture_atlas_by_id :: proc(id: Asset_Id) -> ^Atlas_State {
	if state == nil {
		return nil
	}

	if state.textures.atlas.texture_id == id {
		return &state.textures.atlas
	}

	for &atlas in state.textures.overflow {
		if atlas.texture_id == id {
			return &atlas
		}
	}

	return nil
}

texture_atlas_owns_id :: proc(id: Asset_Id) -> bool {
	return texture_atlas_by_id(id) != nil
}

/*
Returns the stable sampler slot for a live atlas id: primary is zero.
*/
texture_atlas_slot_for_id :: proc(id: Asset_Id) -> (u32, bool) {
	if state == nil {
		return 0, false
	}

	if state.textures.atlas.texture_id == id {
		return 0, true
	}

	for atlas, index in state.textures.overflow {
		if atlas.texture_id == id {
			slot := index + 1

			return u32(slot), slot < ATLAS_SAMPLER_SLOTS
		}
	}

	return 0, false
}

/*
Atlas occupancy / residency snapshot for tools and `Get_Atlas_Stats`.

Includes all live sheets in occupancy totals, overflow count, and draw mode.
*/
atlas_stats :: proc() -> Atlas_Stats {
	if state == nil {
		return {}
	}

	atlas := state.textures.atlas
	total := u64(atlas.width) * u64(atlas.height) * 4
	bytes_used := atlas.bytes_used
	slot_count := atlas.slot_count

	for overflow in state.textures.overflow {
		total += u64(overflow.width) * u64(overflow.height) * 4
		bytes_used += overflow.bytes_used
		slot_count += overflow.slot_count
	}

	used_percent: f32 = 0

	if total > 0 {
		used_percent = f32(f64(bytes_used) * 100.0 / f64(total))
		if used_percent > 100 {
			used_percent = 100
		}
	}

	cache_count := 0
	if state.fonts.glyph_cache != nil {
		cache_count = len(state.fonts.glyph_cache)
	}

	return Atlas_Stats {
		width          = atlas.width,
		height         = atlas.height,
		bytes_used     = bytes_used,
		bytes_total    = total,
		used_percent   = used_percent,
		slot_count     = slot_count,
		cache_count    = cache_count,
		generation     = atlas.generation,
		overflow_count = len(state.textures.overflow),
		draw_mode      = state.textures.atlas_draw_mode,
		frame          = atlas_current_frame(),
	}
}

/*
Creates the shelf atlas backing texture at the given size if not already initialized.

Registers an empty RGBA surface as the atlas record and records shelf state.
*/
texture_atlas_init :: proc(size: i32 = ATLAS_DEFAULT_SIZE) -> bool {
	if state.textures.atlas.texture_id != INVALID_ASSET_ID && state.textures.atlas.width > 0 {
		return true
	}

	if state.gpu == nil {
		return false
	}

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
		generation = 0,
		bytes_used = 0,
		slot_count = 0,
	}

	return true
}

/*
Frees atlas shelf bookkeeping and resets atlas state to empty.

Does not destroy the underlying atlas texture record.
*/
texture_atlas_shutdown :: proc() {
	atlas_owner_lock()
	defer atlas_owner_unlock()

	if state.textures.raster_workers != 0 {
		log_errorf(
			"texture_atlas_shutdown: %d raster workers still marked active",
			state.textures.raster_workers,
		)
		state.textures.raster_workers = 0
	}

	// Pool lives on Font_State; font_shutdown joins it. Guard if atlas tears down first.
	font_raster_pool_shutdown()

	delete(state.textures.atlas.shelves)

	for &atlas in state.textures.overflow {
		delete(atlas.shelves)
		atlas.shelves = nil
	}

	delete(state.textures.overflow)
	state.textures.overflow = nil
	state.textures.atlas = {}
	state.textures.atlas_draw_mode = .Unset
	state.textures.atlas_fallback_logged = false
	state.textures.last_pack_fail = .None
}

/*
Re-uploads the atlas backing texture from its CPU surface after GPU reload.

Logs an error if the atlas record or upload is unavailable.
*/
texture_atlas_rebuild_gpu :: proc() {
	if state == nil {
		return
	}

	count := texture_atlas_count()
	for slot in 0 ..< count {
		atlas := slot == 0 ? &state.textures.atlas : &state.textures.overflow[slot - 1]
		index := int(atlas.texture_id)
		if index <= 0 || index >= len(state.textures.records) {
			continue
		}

		entry := &state.textures.records[index]
		if entry.surface == nil {
			continue
		}

		if !texture_upload_record(entry) {
			log_errorf("Failed to rebuild atlas GPU texture %d after hot reload", atlas.texture_id)
		}
	}
}

/*
Returns whether a padded w×h region would fit without mutating shelves.

Used to distinguish atlas-full failures from upload failures and to decide
whether evict+repack recovered enough space.
*/
texture_atlas_can_fit_in :: proc(atlas: ^Atlas_State, w, h: i32) -> bool {
	if w <= 0 || h <= 0 {
		return false
	}

	if atlas == nil {
		return false
	}

	if atlas.texture_id == INVALID_ASSET_ID || atlas.width <= 0 || atlas.height <= 0 {
		return false
	}

	pad := i32(ATLAS_PADDING)
	need_w := w + pad
	need_h := h + pad

	if need_w > atlas.width || need_h > atlas.height {
		return false
	}

	for shelf in atlas.shelves {
		if shelf.height < need_h {
			continue
		}

		if shelf.cursor_x + need_w <= atlas.width {
			return true
		}
	}

	new_y: i32 = 0
	if len(atlas.shelves) > 0 {
		last := atlas.shelves[len(atlas.shelves) - 1]
		new_y = last.y + last.height
	}

	return new_y + need_h <= atlas.height
}

texture_atlas_can_fit :: proc(w, h: i32) -> bool {
	return texture_atlas_can_fit_in(&state.textures.atlas, w, h)
}

texture_atlas_can_fit_any :: proc(w, h: i32) -> bool {
	if texture_atlas_can_fit_in(&state.textures.atlas, w, h) {
		return true
	}

	for &atlas in state.textures.overflow {
		if texture_atlas_can_fit_in(&atlas, w, h) {
			return true
		}
	}

	return false
}

/*
Replaces the atlas CPU surface with a cleared surface and resets shelves.

When `new_size > 0`, grows/shrinks atlas dimensions to that square edge before
allocating the surface (Group D). `new_size == 0` keeps the current size.
Flushes pending uploads first. Does not bump `generation` (caller does after
survivors are rewritten). Keeps `texture_id`. GPU is rebuilt by the caller
after packing.
*/
texture_atlas_begin_repack_in :: proc(atlas: ^Atlas_State, new_size: i32 = 0) -> bool {
	atlas_owner_lock()
	defer atlas_owner_unlock()

	atlas_owner_assert_no_raster_workers()

	if atlas == nil {
		return false
	}

	if atlas.texture_id == INVALID_ASSET_ID || atlas.width <= 0 || atlas.height <= 0 {
		return false
	}

	size := new_size > 0 ? new_size : atlas.width
	if size <= 0 {
		return false
	}

	if !texture_uploads_flush(state.gpu) {
		log_error("texture_atlas_begin_repack: pending upload flush failed")

		return false
	}

	index := int(atlas.texture_id)
	if index <= 0 || index >= len(state.textures.records) {
		return false
	}

	entry := &state.textures.records[index]
	new_surface := sdl.CreateSurface(size, size, .RGBA8888)
	if new_surface == nil {
		log_errorf("SDL_CreateSurface failed for atlas repack: %s", sdl.GetError())

		return false
	}

	pixels := cast([^]u8)new_surface.pixels
	byte_count := int(new_surface.pitch) * int(new_surface.h)
	for i in 0 ..< byte_count {
		pixels[i] = 0
	}

	if entry.surface != nil {
		sdl.DestroySurface(entry.surface)
	}

	// Keep any existing GPU handle until the end-of-repack `texture_upload_record`
	// rebuild (packs during `repacking` are CPU-only; see `texture_atlas_upload`).
	entry.surface = new_surface
	entry.w = size
	entry.h = size
	atlas.width = size
	atlas.height = size

	clear(&atlas.shelves)
	texture_atlas_occupancy_clear(atlas)
	atlas.needs_repack = false

	return true
}

texture_atlas_begin_repack :: proc(new_size: i32 = 0) -> bool {
	return texture_atlas_begin_repack_in(&state.textures.atlas, new_size)
}

/*
Allocates a padded w×h rectangle in the shelf atlas using first-fit placement.

Opens a new shelf row when no existing shelf has room; returns false when full.
Padded size larger than the atlas is rejected before any shelf is opened or advanced.
*/
texture_atlas_alloc_in :: proc(atlas: ^Atlas_State, w, h: i32) -> (Atlas_Region, bool) {
	atlas_owner_lock()
	defer atlas_owner_unlock()

	atlas_owner_assert_no_raster_workers()

	if w <= 0 || h <= 0 {
		return {}, false
	}

	if atlas == nil || atlas.texture_id == INVALID_ASSET_ID {
		return {}, false
	}

	pad := i32(ATLAS_PADDING)
	need_w := w + pad
	need_h := h + pad

	// Reject oversize before mutating shelves (width-only overflow used to open a
	// shelf with cursor_x past atlas.width).
	if need_w > atlas.width || need_h > atlas.height {
		log_errorf(
			"Atlas region %dx%d (padded %dx%d) exceeds atlas %dx%d",
			w,
			h,
			need_w,
			need_h,
			atlas.width,
			atlas.height,
		)

		return {}, false
	}

	for &shelf in atlas.shelves {
		if shelf.height < need_h {
			continue
		}

		if shelf.cursor_x + need_w > atlas.width {
			continue
		}

		region := Atlas_Region {
			texture_id = atlas.texture_id,
			x          = f32(shelf.cursor_x),
			y          = f32(shelf.y),
			w          = f32(w),
			h          = f32(h),
		}
		shelf.cursor_x += need_w
		texture_atlas_occupancy_add(atlas, w, h)

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
	texture_atlas_occupancy_add(atlas, w, h)

	return Atlas_Region {
			texture_id = atlas.texture_id,
			x = 0,
			y = f32(new_y),
			w = f32(w),
			h = f32(h),
		},
		true
}

texture_atlas_alloc :: proc(w, h: i32) -> (Atlas_Region, bool) {
	if !texture_atlas_init() {
		return {}, false
	}

	return texture_atlas_alloc_in(&state.textures.atlas, w, h)
}

/*
Restores shelf state after a failed pack upload.

If alloc opened a new shelf, it is removed. If alloc advanced an existing shelf
cursor, that cursor is rewound by the padded width. Single-owner path only.
*/
texture_atlas_pack_rewind_in :: proc(
	atlas: ^Atlas_State,
	shelf_count_before: int,
	region: Atlas_Region,
	w: i32,
) {
	atlas_owner_lock()
	defer atlas_owner_unlock()

	atlas_owner_assert_no_raster_workers()

	if atlas == nil {
		return
	}

	h := i32(region.h)

	if len(atlas.shelves) > shelf_count_before {
		resize(&atlas.shelves, shelf_count_before)
		texture_atlas_occupancy_sub(atlas, w, h)

		return
	}

	need_w := w + i32(ATLAS_PADDING)
	region_y := i32(region.y)

	for &shelf in atlas.shelves {
		if shelf.y != region_y {
			continue
		}

		shelf.cursor_x -= need_w
		if shelf.cursor_x < 0 {
			shelf.cursor_x = 0
		}

		texture_atlas_occupancy_sub(atlas, w, h)

		return
	}
}

texture_atlas_pack_rewind :: proc(shelf_count_before: int, region: Atlas_Region, w: i32) {
	atlas := texture_atlas_by_id(region.texture_id)
	texture_atlas_pack_rewind_in(atlas, shelf_count_before, region, w)
}

/*
Uploads a surface into an allocated atlas region on both GPU and CPU backing.

Copies pixels into the atlas CPU surface first, then queues a deferred GPU upload
of that region from the shared atlas surface (flushed in present / reload).
*/
texture_atlas_upload :: proc(region: Atlas_Region, surface: ^sdl.Surface) -> bool {
	atlas := texture_atlas_by_id(region.texture_id)
	if atlas == nil {
		return false
	}

	if surface == nil {
		return false
	}

	index := int(atlas.texture_id)
	if index <= 0 || index >= len(state.textures.records) {
		return false
	}

	entry := &state.textures.records[index]
	repacking := atlas.repacking

	// Normal packs need a live GPU texture; compact/grow rebuilds GPU after CPU packs.
	if !repacking && entry.gpu == nil {
		return false
	}

	dst_x := i32(region.x)
	dst_y := i32(region.y)
	dst_w := i32(region.w)
	dst_h := i32(region.h)

	// Validate / convert before mutating the CPU atlas so bad formats fail cleanly.
	converted, owned := texture_surface_as_rgba8888(surface)
	if converted == nil {
		return false
	}

	defer if owned {
		sdl.DestroySurface(converted)
	}

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

		if repacking {
			return true
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

	if repacking || entry.gpu == nil {
		return false
	}

	// No CPU atlas — upload the converted source immediately (tests / edge cases).
	return texture_upload_surface(state.gpu, entry.gpu, converted, dst_x, dst_y, dst_w, dst_h)
}

/*
Allocates atlas space for a surface and uploads it in one step.

Low-level try only (primary then existing overflow). Does not run the Group F
recovery funnel — use `font_atlas_pack_funnel` for pack-with-recover.

On upload failure, rolls back both a newly opened shelf and any existing shelf
`cursor_x` advanced by the alloc (see `texture_atlas_pack_rewind`).
*/
texture_atlas_pack :: proc(surface: ^sdl.Surface) -> (Atlas_Region, bool) {
	if surface == nil {
		return {}, false
	}

	if !texture_atlas_init() {
		return {}, false
	}

	if texture_atlas_can_fit_in(&state.textures.atlas, surface.w, surface.h) {
		return texture_atlas_pack_into(&state.textures.atlas, surface)
	}

	for &atlas in state.textures.overflow {
		if texture_atlas_can_fit_in(&atlas, surface.w, surface.h) {
			return texture_atlas_pack_into(&atlas, surface)
		}
	}

	return {}, false
}

texture_atlas_pack_into :: proc(
	atlas: ^Atlas_State,
	surface: ^sdl.Surface,
) -> (Atlas_Region, bool) {
	if atlas == nil || surface == nil {
		return {}, false
	}

	shelf_count := len(atlas.shelves)
	region, ok := texture_atlas_alloc_in(atlas, surface.w, surface.h)
	if !ok {
		return {}, false
	}

	if !texture_atlas_upload(region, surface) {
		texture_atlas_pack_rewind_in(atlas, shelf_count, region, surface.w)

		return {}, false
	}

	return region, true
}

/*
True when any glyph-cache entry still references `id`.
*/
texture_atlas_cache_refs_id :: proc(id: Asset_Id) -> bool {
	if state == nil || state.fonts.glyph_cache == nil {
		return false
	}

	for _, entry in state.fonts.glyph_cache {
		if entry.region.texture_id == id {
			return true
		}
	}

	return false
}

/*
Destroys overflow sheet at `index` (owner lock held).

Removes the sheet from `overflow`, then retires its texture record. Primary is
never destroyed here. Pending uploads must already be flushed (recover / caller).
*/
texture_atlas_destroy_overflow_at :: proc(index: int) {
	atlas_owner_assert_held()
	atlas_owner_assert_no_raster_workers()

	if state == nil || index < 0 || index >= len(state.textures.overflow) {
		return
	}

	atlas := &state.textures.overflow[index]
	id := atlas.texture_id

	delete(atlas.shelves)
	atlas.shelves = nil
	ordered_remove(&state.textures.overflow, index)

	// No longer an atlas id — retire GPU/CPU resources (tombstone slot).
	texture_retire_record(id)
}

/*
Drops overflow sheets with no live glyph-cache references (Group E optional).

Walks from the end so slot indices for remaining sheets stay valid during removal.
Primary is never pruned. Call after eviction / overflow repack under the owner lock.
*/
texture_atlas_prune_empty_overflow :: proc() {
	atlas_owner_assert_held()
	atlas_owner_assert_no_raster_workers()

	if state == nil || len(state.textures.overflow) == 0 {
		return
	}

	for i := len(state.textures.overflow) - 1; i >= 0; i -= 1 {
		atlas := &state.textures.overflow[i]
		if atlas.slot_count != 0 || atlas.bytes_used != 0 {
			continue
		}

		if texture_atlas_cache_refs_id(atlas.texture_id) {
			continue
		}

		texture_atlas_destroy_overflow_at(i)
	}
}

/*
Creates one capped overflow sheet at the primary/effective-max size.
*/
texture_atlas_ensure_overflow :: proc() -> (^Atlas_State, bool) {
	atlas_owner_lock()
	defer atlas_owner_unlock()

	atlas_owner_assert_no_raster_workers()

	if state == nil || state.gpu == nil {
		return nil, false
	}

	if len(state.textures.overflow) >= ATLAS_OVERFLOW_CAP ||
	   1 + len(state.textures.overflow) >= ATLAS_SAMPLER_SLOTS {
		log_errorf("Atlas overflow cap reached (%d)", ATLAS_OVERFLOW_CAP)

		return nil, false
	}

	size := state.textures.atlas.width
	if size <= 0 {
		size = min(i32(ATLAS_DEFAULT_SIZE), texture_atlas_effective_max())
	} else {
		size = min(size, texture_atlas_effective_max())
	}

	if size <= 0 {
		return nil, false
	}

	surface := sdl.CreateSurface(size, size, .RGBA8888)
	if surface == nil {
		log_errorf("SDL_CreateSurface failed for atlas overflow: %s", sdl.GetError())

		return nil, false
	}

	id, _, ok := texture_register_surface(surface, "")
	if !ok {
		return nil, false
	}

	append(
		&state.textures.overflow,
		Atlas_State {
			texture_id = id,
			width      = size,
			height     = size,
		},
	)

	return &state.textures.overflow[len(state.textures.overflow) - 1], true
}

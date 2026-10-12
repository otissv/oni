package oni

import "core:c"
import "core:math"
import "core:mem"
import "core:slice"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:unicode/utf8"
import sdl "vendor:sdl3"

FONT_GLYPH_PARALLEL_THRESHOLD :: 4
FONT_GLYPH_MAX_WORKERS :: 4
// Per-worker op arena for temp-face path/coords (never the engine frame temp_allocator).
FONT_RASTER_WORKER_SCRATCH :: 64 * 1024

/*
One FreeType raster job before serial atlas packing (Group G).

Workers fill `surface` / bearings via a temporary FT library+face. The owner
thread packs only after all workers join (`atlas_owner_assert_no_raster_workers`).
*/
Font_Raster_Job :: struct {
	face:        ^Font_Face,
	glyph_id:    u32,
	render_mode: Font_Glyph_Render_Mode,
	surface:     ^sdl.Surface,
	bearing_x:   f32,
	bearing_y:   f32,
	ok:          bool,
}

/*
Per-worker chunk of raster jobs plus a private scratch arena.

May mix faces; worker opens temp faces through `scratch` so path/coords never
race the owner `context.temp_allocator` frame wipe (Group I).
*/
Font_Raster_Worker_Chunk :: struct {
	jobs:            []Font_Raster_Job,
	scratch:         mem.Arena,
	scratch_backing: []u8,
}

/*
One persistent FreeType raster worker slot (bounded pool, Group G).
*/
Font_Raster_Pool_Slot :: struct {
	pool:      ^Font_Raster_Pool,
	thread:    ^thread.Thread,
	chunk:     Font_Raster_Worker_Chunk,
	work_sema: sync.Sema,
}

/*
Bounded FreeType raster worker pool reused across miss/repack bursts.

Workers sleep on `work_sema`; the owner posts work, then waits on `done_sema`
once per assigned worker. Shutdown posts quit and joins every thread.
*/
Font_Raster_Pool :: struct {
	slots:          [FONT_GLYPH_MAX_WORKERS]Font_Raster_Pool_Slot,
	done_sema:      sync.Sema,
	quit:           bool,
	started_count:  int,
}

/*
Maps a named Font_Weights value to its CSS numeric weight.
*/
font_weights_to_f32 :: proc(weight: Font_Weights) -> f32 {
	switch weight {
	case .Thin:
		return 100
	case .Extra_Light:
		return 200
	case .Light:
		return 300
	case .Normal:
		return 400
	case .Medium:
		return 500
	case .Semi_Bold:
		return 600
	case .Bold:
		return 700
	case .Extra_Bold:
		return 800
	case .Heavy:
		return 900
	}
	unreachable()
}

/*
Returns the numeric CSS weight from a resolved Font_Weight value.

Nil weight defaults to Normal (400). Unresolved procs panic.
*/
font_weight_value :: proc(weight: Font_Weight) -> f32 {
	switch v in weight {
	case Inherit:
		panic("font_weight_value: unresolved Inherit")
	case Font_Weights:
		return font_weights_to_f32(v)
	case f32:
		return v
	case proc(
		     frame_state: Widget_Frame_State,
		     event: Widget_Event(Widget_Frame_State),
	     ) -> Font_Weight:
		panic("font_weight_value: unresolved Font_Weight")
	}
	return font_weights_to_f32(.Normal)
}

/*
Returns the concrete Font_Styles kind from a resolved Font_Style value.

Nil style defaults to NORMAL. Unresolved procs panic.
*/
font_style_kind :: proc(style: Font_Style) -> Font_Styles {
	switch v in style {
	case Inherit:
		panic("font_style_kind: unresolved Inherit")
	case Font_Styles:
		return v
	case proc(
		     frame_state: Widget_Frame_State,
		     event: Widget_Event(Widget_Frame_State),
	     ) -> Font_Style:
		panic("font_style_kind: unresolved Font_Style")
	}
	return .NORMAL
}

/*
Resolves a family + weight/style + logical size to a raster face instance.

On artboard space, scales by view zoom and returns a layout_scale to map back.
*/
font_resolve :: proc(
	font: Font_Handle,
	logical_size: f32,
	space: Draw_Space,
	weight: Font_Weight = Font_Weights.Normal,
	style: Font_Style = Font_Styles.NORMAL,
) -> (
	resolved: Font_Face_Handle,
	layout_scale: f32,
	ok: bool,
) {
	family := font_family_from_handle(font)
	if family == nil do return {}, 1, false

	size := logical_size > 0 ? logical_size : font.size_px
	if size <= 0 do size = 16

	zoom: f32 = 1
	if space == .ARTBOARD {
		zoom = layout_artboard_zoom()
	}

	raster_size := max(size * zoom, 1)
	req_weight := font_weight_value(weight)
	req_style := font_style_kind(style)

	src, fake_bold, fake_italic, match_ok := font_match_source(family, req_weight, req_style)
	if !match_ok do return {}, 1, false

	resolved, ok = font_find_or_create_instance(
		src,
		raster_size,
		req_weight,
		req_style,
		fake_bold,
		fake_italic,
	)
	if !ok do return {}, 1, false

	layout_scale = 1
	if space == .ARTBOARD && zoom > 0 {
		layout_scale = 1 / zoom
	}
	return resolved, layout_scale, true
}

/*
Loads one glyph outline and returns layout paint metrics in logical pixels.

Uses FT_LOAD_DEFAULT (or FT_LOAD_NO_BITMAP + embolden for synthetic bold).
Prefer atlas-backed paint quads (layout_glyph_paint_quad) for draw sizes;
these outline metrics remain for tests and non-atlas fallbacks.
*/
font_glyph_metrics :: proc(face: ^Font_Face, glyph_id: u32) -> (w, h, bearing_x, bearing_y: f32, ok: bool) {
	if face == nil || face.ft_face == nil do return 0, 0, 0, 0, false

	base: c.int = face.fake_bold ? c.int(FT_LOAD_NO_BITMAP) : c.int(FT_LOAD_DEFAULT)
	load_flags := font_load_flags(face.pixel_size, base)
	if !ft_ok(Load_Glyph(face.ft_face, c.uint(glyph_id), load_flags)) {
		log_errorf("FT_Load_Glyph failed for metrics glyph %d", glyph_id)
		return 0, 0, 0, 0, false
	}

	slot := ft_glyph_slot(face.ft_face)
	if face.fake_bold {
		GlyphSlot_Embolden(slot)
	}

	metrics := ft_slot_metrics(slot)^
	w = font_device_to_logical(ft_pos_to_f32(metrics.width))
	h = font_device_to_logical(ft_pos_to_f32(metrics.height))
	bearing_x = font_device_to_logical(ft_pos_to_f32(metrics.hori_bearing_x))
	bearing_y = font_device_to_logical(ft_pos_to_f32(metrics.hori_bearing_y))

	if w <= 0 || h <= 0 {
		w = font_device_to_logical(1)
		h = font_device_to_logical(1)
		bearing_x = 0
		bearing_y = 0
	}

	return w, h, bearing_x, bearing_y, true
}

/*
Clears the font atlas CPU surface, resets shelf allocation, and invalidates the
glyph cache.

Cache entries hold `Atlas_Region` UVs into this atlas; clearing shelves/pixels
without dropping those entries would leave stale draws. Bumps atlas `generation`
and clears occupancy so residency bookkeeping stays consistent. Used before
reloading faces or after DPI changes so packing starts from a clean atlas.
Retires standalone (oversize-bypass) texture records before dropping the cache.
*/
font_atlas_reset :: proc() {
	atlas_owner_lock()
	defer atlas_owner_unlock()

	atlas_owner_assert_no_raster_workers()

	if state.textures.atlas.texture_id == INVALID_ASSET_ID {
		return
	}

	count := texture_atlas_count()
	for slot in 0 ..< count {
		atlas := slot == 0 ? &state.textures.atlas : &state.textures.overflow[slot - 1]
		index := int(atlas.texture_id)
		if index > 0 && index < len(state.textures.records) {
			entry := &state.textures.records[index]
			if entry.surface != nil {
				pixels := cast([^]u8)entry.surface.pixels
				size := int(entry.surface.pitch) * int(entry.surface.h)
				for i in 0 ..< size {
					pixels[i] = 0
				}
			}
		}

		clear(&atlas.shelves)
		texture_atlas_occupancy_clear(atlas)
		atlas.generation += 1
		atlas.needs_repack = false
		atlas.repacking = false
	}

	// Regions in the cache point at this atlas and are invalid after reset.
	if state.fonts.glyph_cache != nil {
		for _, entry in state.fonts.glyph_cache {
			if .Standalone in entry.flags {
				texture_retire_record(entry.region.texture_id)
			}
		}

		clear(&state.fonts.glyph_cache)
	}
}

/*
Stamps `last_used_frame` from the engine frame index for residency tracking.
*/
font_glyph_entry_touch :: proc(entry: ^Font_Glyph_Entry) {
	if entry == nil {
		return
	}

	entry.last_used_frame = atlas_current_frame()
}

/*
True when a cache entry still points at a live atlas generation or standalone GPU texture.
*/
font_glyph_entry_is_live :: proc(entry: Font_Glyph_Entry) -> bool {
	if .Standalone in entry.flags {
		return texture_get_gpu(entry.region.texture_id) != nil
	}

	atlas := texture_atlas_by_id(entry.region.texture_id)

	return atlas != nil && entry.generation == atlas.generation
}

/*
Drops a glyph cache key and retires standalone texture resources.
*/
font_glyph_cache_drop :: proc(key: Font_Glyph_Key) {
	if state == nil || state.fonts.glyph_cache == nil {
		return
	}

	entry, ok := state.fonts.glyph_cache[key]
	if !ok {
		return
	}

	if .Standalone in entry.flags {
		texture_retire_record(entry.region.texture_id)
	}

	delete_key(&state.fonts.glyph_cache, key)
}

/*
Clears Prefetched|Pinned after ATLAS_PREFETCH_PIN_FRAMES unused frames.

Prefetch must not be immortal; after pin expiry glyphs become normal cold-evict
candidates.
*/
font_atlas_expire_prefetch_pins :: proc() {
	if state == nil || state.fonts.glyph_cache == nil {
		return
	}

	frame := atlas_current_frame()
	if frame < u64(ATLAS_PREFETCH_PIN_FRAMES) {
		return
	}

	cutoff := frame - u64(ATLAS_PREFETCH_PIN_FRAMES)

	for key, &entry in state.fonts.glyph_cache {
		_ = key
		if .Prefetched not_in entry.flags && .Pinned not_in entry.flags {
			continue
		}

		if entry.last_used_frame < cutoff {
			entry.flags -= {.Pinned, .Prefetched}
		}
	}
}

/*
Deletes cold glyph cache entries and marks each owning atlas for compaction.

Cold: `last_used_frame < frame - ATLAS_EVICT_COLD_FRAMES`, and neither Pinned nor
Prefetched. Does not punch shelf holes — caller must `atlas_compact` when
`needs_repack` is set. Returns how many keys were removed.
*/
font_atlas_evict_cold :: proc() -> int {
	atlas_owner_lock()
	defer atlas_owner_unlock()

	atlas_owner_assert_no_raster_workers()

	if state == nil || state.fonts.glyph_cache == nil {
		return 0
	}

	font_atlas_expire_prefetch_pins()

	frame := atlas_current_frame()
	if frame < u64(ATLAS_EVICT_COLD_FRAMES) {
		return 0
	}

	cutoff := frame - u64(ATLAS_EVICT_COLD_FRAMES)
	to_delete := make([dynamic]Font_Glyph_Key, context.temp_allocator)

	for key, entry in state.fonts.glyph_cache {
		if .Pinned in entry.flags || .Prefetched in entry.flags || .Standalone in entry.flags {
			continue
		}

		if entry.last_used_frame >= cutoff {
			continue
		}

		append(&to_delete, key)
	}

	for key in to_delete {
		entry := state.fonts.glyph_cache[key]
		if atlas := texture_atlas_by_id(entry.region.texture_id); atlas != nil {
			atlas.needs_repack = true
			texture_atlas_occupancy_sub(atlas, i32(entry.region.w), i32(entry.region.h))
		}

		font_glyph_cache_drop(key)
	}

	if len(to_delete) > 0 {
		texture_atlas_prune_empty_overflow()
	}

	return len(to_delete)
}

/*
Survivor metadata preserved across atlas compaction.
*/
Font_Atlas_Repack_Survivor :: struct {
	key:             Font_Glyph_Key,
	flags:           Font_Glyph_Residency_Flags,
	last_used_frame: u64,
	surface:         ^sdl.Surface,
	bearing_x:       f32,
	bearing_y:       f32,
	ok:              bool,
}

/*
Re-rasterizes glyph-cache survivors into a fresh atlas surface.

When `new_size > 0`, repacks into that square edge (Group D grow). `new_size == 0`
keeps the current size (pure compact). Flushes pending uploads, clears shelves,
packs survivors (height-desc), rewrites regions + generation, rebuilds the GPU
texture, and flushes. Only glyph_cache entries are survivors.
*/
font_atlas_repack_in :: proc(target: ^Atlas_State, new_size: i32 = 0) -> bool {
	atlas_owner_lock()
	defer atlas_owner_unlock()

	atlas_owner_assert_no_raster_workers()

	if state == nil || target == nil || target.texture_id == INVALID_ASSET_ID {
		return false
	}

	if target.repacking {
		log_error("font_atlas_repack: nested repack is not allowed")

		return false
	}

	target.repacking = true
	defer {
		target.repacking = false
	}

	survivors := make([dynamic]Font_Atlas_Repack_Survivor, 0, len(state.fonts.glyph_cache), context.temp_allocator)

	target_id := target.texture_id
	for key, entry in state.fonts.glyph_cache {
		if entry.region.texture_id != target_id {
			continue
		}

		if .Standalone in entry.flags {
			continue
		}

		append(
			&survivors,
			Font_Atlas_Repack_Survivor {
				key = key,
				flags = entry.flags,
				last_used_frame = entry.last_used_frame,
			},
		)
	}

	jobs := make([]Font_Raster_Job, len(survivors), context.temp_allocator)
	for &s, i in survivors {
		face := font_face_from_handle(Font_Face_Handle{id = s.key.face_id})
		if face == nil || face.ft_face == nil {
			log_errorf(
				"font_atlas_repack: missing face %d for glyph %d — dropping",
				s.key.face_id,
				s.key.glyph_id,
			)
			s.ok = false
			continue
		}

		jobs[i] = Font_Raster_Job {
			face        = face,
			glyph_id    = s.key.glyph_id,
			render_mode = s.key.render_mode,
		}
	}

	if len(jobs) > 0 {
		font_rasterize_jobs(jobs)
		for &s, i in survivors {
			s.surface = jobs[i].surface
			s.bearing_x = jobs[i].bearing_x
			s.bearing_y = jobs[i].bearing_y
			s.ok = jobs[i].ok
			jobs[i].surface = nil
		}
	}

	defer {
		for &s in survivors {
			if s.surface != nil {
				sdl.DestroySurface(s.surface)
				s.surface = nil
			}
		}
		for &job in jobs {
			if job.surface != nil {
				sdl.DestroySurface(job.surface)
				job.surface = nil
			}
		}
	}

	slice.sort_by(
		survivors[:],
		proc(a, b: Font_Atlas_Repack_Survivor) -> bool {
			ah := a.ok && a.surface != nil ? a.surface.h : 0
			bh := b.ok && b.surface != nil ? b.surface.h : 0

			return ah > bh
		},
	)

	if !texture_atlas_begin_repack_in(target, new_size) {
		return false
	}

	target.generation += 1
	new_gen := target.generation

	primary_keys := make([dynamic]Font_Glyph_Key, context.temp_allocator)
	for key, entry in state.fonts.glyph_cache {
		if entry.region.texture_id == target_id {
			append(&primary_keys, key)
		}
	}

	for key in primary_keys {
		delete_key(&state.fonts.glyph_cache, key)
	}

	for &s in survivors {
		if !s.ok || s.surface == nil {
			continue
		}

		region, pok := texture_atlas_pack_into(target, s.surface)
		if !pok {
			log_errorf(
				"font_atlas_repack: survivor glyph %d failed to pack — dropping",
				s.key.glyph_id,
			)
			continue
		}

		state.fonts.glyph_cache[s.key] = Font_Glyph_Entry {
			region          = region,
			bearing_x       = s.bearing_x,
			bearing_y       = s.bearing_y,
			last_used_frame = s.last_used_frame,
			flags           = s.flags,
			generation      = new_gen,
		}

		sdl.DestroySurface(s.surface)
		s.surface = nil
	}

	index := int(target.texture_id)
	if index <= 0 || index >= len(state.textures.records) {
		return false
	}

	entry := &state.textures.records[index]
	if !texture_upload_record(entry, true) {
		log_error("font_atlas_repack: deferred GPU rebuild failed")

		return false
	}

	if !texture_uploads_flush(state.gpu) {
		log_error("font_atlas_repack: GPU flush failed")

		return false
	}

	target.needs_repack = false

	return true
}

font_atlas_repack :: proc(new_size: i32 = 0) -> bool {
	return font_atlas_repack_in(&state.textures.atlas, new_size)
}

/*
Internal compaction entry point for tools/tests (same-size survivor repack).
*/
atlas_compact :: proc() -> bool {
	return font_atlas_repack(0)
}

/*
Doubles atlas size (capped) and repacks survivors so a padded w×h pack can fit.

`new_size = min(old * 2, effective_max)`. Returns false when already at the
effective max (Group E overflow) or the requested glyph still exceeds the new
edge. At most one growth step per call.
*/
font_atlas_try_grow :: proc(w, h: i32) -> bool {
	if state == nil || state.textures.atlas.texture_id == INVALID_ASSET_ID {
		return false
	}

	if state.textures.atlas.repacking {
		return false
	}

	old_size := state.textures.atlas.width
	if old_size <= 0 {
		return false
	}

	effective := texture_atlas_effective_max()
	new_size := min(old_size * 2, effective)
	if new_size <= old_size {
		return false
	}

	pad := i32(ATLAS_PADDING)
	if w + pad > new_size || h + pad > new_size {
		return false
	}

	if !font_atlas_repack(new_size) {
		return false
	}

	log_warnf("Atlas grew %dx%d → %dx%d", old_size, old_size, new_size, new_size)

	return texture_atlas_can_fit_in(&state.textures.atlas, w, h)
}

/*
Evicts cold glyphs, compacts, grows, then opens overflow so a padded w×h pack can succeed.

Group F funnel step (after a failed low-level pack):
flush → expire pins → evict cold → same-size repack → capped grow → ensure overflow.
Returns false when still full at the overflow cap / effective max, or a step fails.
Sets `state.textures.last_pack_fail` on nested-repack / flush failure.
*/
font_atlas_recover_space :: proc(w, h: i32) -> bool {
	atlas_owner_lock()
	defer atlas_owner_unlock()
	atlas_owner_assert_no_raster_workers()

	if texture_atlas_can_fit_any(w, h) {
		return true
	}

	if state.textures.atlas.repacking {
		state.textures.last_pack_fail = .Nested_Repack

		return false
	}

	if !texture_uploads_flush(state.gpu) {
		log_error("font_atlas_recover_space: pending upload flush failed")
		state.textures.last_pack_fail = .Flush_Failed

		return false
	}

	evicted := font_atlas_evict_cold()
	if evicted > 0 && state.textures.atlas.needs_repack {
		if !font_atlas_repack(0) {
			// Still attempt grow; same-size compact failure must not skip D.
		}
	}

	if evicted > 0 {
		for i := 0; i < len(state.textures.overflow); i += 1 {
			if state.textures.overflow[i].needs_repack {
				_ = font_atlas_repack_in(&state.textures.overflow[i], 0)
			}
		}

		texture_atlas_prune_empty_overflow()
	}

	if texture_atlas_can_fit_any(w, h) {
		return true
	}

	if font_atlas_try_grow(w, h) {
		return true
	}

	overflow_size := min(state.textures.atlas.width, texture_atlas_effective_max())
	if w + ATLAS_PADDING > overflow_size || h + ATLAS_PADDING > overflow_size {
		return false
	}

	atlas, ok := texture_atlas_ensure_overflow()
	if !ok {
		return false
	}

	return texture_atlas_can_fit_in(atlas, w, h)
}

/*
Single pack-failure funnel (Group F): try pack → recover C→D→E → retry.

Oversize vs effective max is reported without mutating shelves (caller may
standalone-bypass). Upload failures do not run recovery. Final exhaustion uses
`error_report`.
*/
font_atlas_pack_funnel :: proc(surface: ^sdl.Surface) -> (Atlas_Region, Atlas_Pack_Fail) {
	atlas_owner_lock()
	defer atlas_owner_unlock()

	atlas_owner_assert_no_raster_workers()
	state.textures.last_pack_fail = .None

	if surface == nil {
		state.textures.last_pack_fail = .Nil_Surface

		return {}, .Nil_Surface
	}

	if texture_atlas_padded_exceeds_effective_max(surface.w, surface.h) {
		state.textures.last_pack_fail = .Oversize

		return {}, .Oversize
	}

	if !texture_atlas_init() {
		state.textures.last_pack_fail = .Init_Failed

		return {}, .Init_Failed
	}

	region, ok := texture_atlas_pack(surface)
	if ok {
		return region, .None
	}

	if texture_atlas_can_fit_any(surface.w, surface.h) {
		state.textures.last_pack_fail = .Upload_Failed

		return {}, .Upload_Failed
	}

	if !font_atlas_recover_space(surface.w, surface.h) {
		fail := state.textures.last_pack_fail
		if fail == .None {
			fail = .Exhausted
			state.textures.last_pack_fail = .Exhausted
		}

		if fail == .Exhausted {
			error_reportf(
				"Atlas pack exhausted for %dx%d after evict/repack/grow/overflow",
				surface.w,
				surface.h,
			)
		}

		return {}, fail
	}

	region, ok = texture_atlas_pack(surface)
	if ok {
		state.textures.last_pack_fail = .None

		return region, .None
	}

	if texture_atlas_can_fit_any(surface.w, surface.h) {
		state.textures.last_pack_fail = .Upload_Failed

		return {}, .Upload_Failed
	}

	state.textures.last_pack_fail = .Exhausted
	error_reportf(
		"Atlas pack exhausted for %dx%d after evict/repack/grow/overflow",
		surface.w,
		surface.h,
	)

	return {}, .Exhausted
}

/*
Rasterizes and caches any glyphs from shaped lines that are not yet in the atlas.

Ensures the atlas is initialized before packing missing glyphs. Large miss sets
rasterize FreeType bitmaps in parallel, then pack into the atlas serially.
`render_mode` selects gray AA or LCD RGB coverage (separate cache entries).
*/
font_ensure_glyphs :: proc(
	face: ^Font_Face,
	face_id: Asset_Id,
	glyphs: []Shaped_Glyph,
	render_mode: Font_Glyph_Render_Mode = .Gray,
) -> bool {
	if face == nil || len(glyphs) == 0 do return true

	atlas_owner_lock()
	defer atlas_owner_unlock()

	missing := make([dynamic]u32, 0, len(glyphs), context.temp_allocator)
	seen := make(map[u32]struct{}, context.temp_allocator)

	for glyph in glyphs {
		key := Font_Glyph_Key {
			face_id     = face_id,
			glyph_id    = glyph.glyph_id,
			render_mode = render_mode,
		}
		if entry, ok := &state.fonts.glyph_cache[key]; ok {
			if font_glyph_entry_is_live(entry^) {
				font_glyph_entry_touch(entry)
				continue
			}

			font_glyph_cache_drop(key)
		}

		if glyph.glyph_id in seen {
			continue
		}

		seen[glyph.glyph_id] = {}
		append(&missing, glyph.glyph_id)
	}

	if len(missing) == 0 {
		return true
	}

	if !texture_atlas_init() {
		return false
	}

	return font_rasterize_and_cache_missing(face, face_id, missing[:], render_mode)
}

/*
Opens a temporary FreeType library + face matching `face` for worker rasterization.

`allocator` owns path/coords scratch for this open (default: `context.temp_allocator`
on the owner thread). Workers must pass a private op-arena allocator — never the
engine frame temp allocator (Group I).

Caller must Done_Face then Done_FreeType. Does not use the engine FT_Library so
New_Face/Load_Glyph stay off the shared face/library on other threads.
*/
font_open_temp_raster_face :: proc(
	face: ^Font_Face,
	allocator: mem.Allocator = {},
) -> (
	library: FT_Library,
	ft_face: FT_Face,
	ok: bool,
) {
	if face == nil || len(face.path) == 0 do return {}, nil, false

	alloc := allocator
	if alloc.procedure == nil {
		alloc = context.temp_allocator
	}

	if !ft_ok(Init_FreeType(&library)) {
		log_error("FT_Init_FreeType failed for worker face")
		return {}, nil, false
	}

	if !font_library_enable_lcd_filter(library) {
		Done_FreeType(library)
		return {}, nil, false
	}

	cpath := strings.clone_to_cstring(face.path, alloc)
	if cpath == nil {
		Done_FreeType(library)
		return {}, nil, false
	}

	if !ft_ok(New_Face(library, cpath, 0, &ft_face)) {
		log_errorf("FT_New_Face failed for worker face %q", face.path)
		Done_FreeType(library)
		return {}, nil, false
	}

	pixel_size := face.pixel_size
	if pixel_size <= 0 do pixel_size = font_pixel_size(face.size_px)
	if !ft_ok(Set_Pixel_Sizes(ft_face, c.uint(pixel_size), c.uint(pixel_size))) {
		log_errorf("FT_Set_Pixel_Sizes failed for worker face %q", face.path)
		Done_Face(ft_face)
		Done_FreeType(library)
		return {}, nil, false
	}

	mm: ^FT_MM_Var
	if ft_ok(Get_MM_Var(ft_face, &mm)) && mm != nil && mm.num_axis > 0 {
		defer Done_MM_Var(library, mm)
		coords := make([]FT_Fixed, int(mm.num_axis), alloc)
		for i in 0 ..< int(mm.num_axis) {
			coords[i] = mm.axis[i].def
			tag := u32(mm.axis[i].tag)
			if tag == FT_TAG_WGHT {
				min_v := ft_fixed_to_f32(mm.axis[i].minimum)
				max_v := ft_fixed_to_f32(mm.axis[i].maximum)
				w := clamp(face.weight, min_v, max_v)
				coords[i] = ft_fixed_from_f32(w)
			} else if tag == FT_TAG_OPSZ {
				min_v := ft_fixed_to_f32(mm.axis[i].minimum)
				max_v := ft_fixed_to_f32(mm.axis[i].maximum)
				opsz := clamp(face.size_px, min_v, max_v)
				coords[i] = ft_fixed_from_f32(opsz)
			}
		}
		if !ft_ok(Set_Var_Design_Coordinates(ft_face, c.uint(mm.num_axis), raw_data(coords))) {
			log_errorf("FT_Set_Var_Design_Coordinates failed for worker face %q", face.path)
			Done_Face(ft_face)
			Done_FreeType(library)
			return {}, nil, false
		}
	}

	if face.fake_italic {
		shear := FT_Matrix {
			xx = 0x10000,
			xy = 13933,
			yx = 0,
			yy = 0x10000,
		}
		Set_Transform(ft_face, &shear, nil)
	} else {
		Set_Transform(ft_face, nil, nil)
	}

	return library, ft_face, true
}

/*
FT load/render + SDL surface copy. Does not touch the glyph atlas.

LCD bitmaps use FreeType subpixel width; the surface is logical width (bitmap.w/3).
*/
font_rasterize_glyph_bitmap :: proc(
	ft_face: FT_Face,
	fake_bold: bool,
	glyph_id: u32,
	device_px: i32 = 0,
	render_mode: Font_Glyph_Render_Mode = .Gray,
) -> (
	surface: ^sdl.Surface,
	bearing_x: f32,
	bearing_y: f32,
	ok: bool,
) {
	if ft_face == nil do return nil, 0, 0, false

	pixel_size := device_px
	if pixel_size <= 0 {
		if metrics := ft_face_size_metrics(ft_face); metrics != nil {
			pixel_size = i32(math.round(f32(metrics.height) / 64))
		}
		if pixel_size <= 0 do pixel_size = FONT_UI_HINT_MAX_PX
	}

	base: c.int = fake_bold ? c.int(FT_LOAD_NO_BITMAP) : c.int(FT_LOAD_RENDER)
	load_flags := font_load_flags(pixel_size, base, render_mode)
	if !ft_ok(Load_Glyph(ft_face, c.uint(glyph_id), load_flags)) {
		log_errorf("FT_Load_Glyph failed for glyph %d", glyph_id)
		return nil, 0, 0, false
	}

	slot := ft_glyph_slot(ft_face)
	if fake_bold {
		GlyphSlot_Embolden(slot)
	}

	if ft_slot_format(slot) != .BITMAP {
		ft_mode := font_render_mode_ft(pixel_size, render_mode)
		if !ft_ok(Render_Glyph(slot, ft_mode)) {
			log_errorf("FT_Render_Glyph failed for glyph %d", glyph_id)
			return nil, 0, 0, false
		}
	}

	bitmap := ft_slot_bitmap(slot)^
	w := i32(bitmap.width)
	h := i32(bitmap.rows)
	bearing_x = f32(ft_slot_bitmap_left(slot))
	bearing_y = f32(ft_slot_bitmap_top(slot))

	if w <= 0 || h <= 0 {
		surface = sdl.CreateSurface(1, 1, .RGBA8888)
		if surface == nil do return nil, 0, 0, false
		sdl.WriteSurfacePixel(surface, 0, 0, 0, 0, 0, 0)
		return surface, 0, 0, true
	}

	surface_w := w
	if bitmap.pixel_mode == FT_PIXEL_MODE_LCD {
		if w % 3 != 0 {
			log_errorf("LCD glyph bitmap width %d is not divisible by 3", w)
			return nil, 0, 0, false
		}

		surface_w = w / 3
	}

	surface = sdl.CreateSurface(surface_w, h, .RGBA8888)
	if surface == nil {
		log_error("SDL_CreateSurface failed for glyph bitmap")
		return nil, 0, 0, false
	}
	font_copy_glyph_bitmap(&bitmap, surface)
	return surface, bearing_x, bearing_y, true
}

/*
Packs an oversize glyph as a standalone texture (never opens an atlas shelf).

Duplicates `surface` because the caller retains ownership. Marks the entry
`.Standalone` so ensure/draw skip atlas generation checks and eviction skips it.
*/
font_pack_glyph_standalone :: proc(
	surface: ^sdl.Surface,
	bearing_x: f32,
	bearing_y: f32,
	glyph_id: u32,
) -> (
	Font_Glyph_Entry,
	bool,
) {
	if surface == nil {
		return {}, false
	}

	dup := sdl.DuplicateSurface(surface)
	if dup == nil {
		error_reportf(
			"Atlas oversize glyph %d (%dx%d): duplicate failed; skipped",
			glyph_id,
			surface.w,
			surface.h,
		)
		state.textures.last_pack_fail = .Oversize

		return {}, false
	}

	id, handle, ok := texture_register_surface(dup, "")
	if !ok {
		error_reportf(
			"Atlas oversize glyph %d (%dx%d): standalone register failed; skipped",
			glyph_id,
			surface.w,
			surface.h,
		)
		state.textures.last_pack_fail = .Oversize

		return {}, false
	}

	log_warnf(
		"Atlas oversize glyph %d (%dx%d): packed as standalone texture %d",
		glyph_id,
		surface.w,
		surface.h,
		id,
	)

	return Font_Glyph_Entry {
			region = Atlas_Region {
				texture_id = id,
				x = 0,
				y = 0,
				w = handle.w,
				h = handle.h,
			},
			bearing_x = bearing_x,
			bearing_y = bearing_y,
			last_used_frame = atlas_current_frame(),
			flags = {.Standalone},
			generation = 0,
		},
		true
}

/*
Packs a rasterized glyph surface into the atlas and returns the cache entry.

Stamps residency (`last_used_frame`, `generation`) for the current atlas state.
Uses the Group F pack funnel (evict → repack → grow → overflow). Oversize glyphs
bypass the atlas as standalone textures.
*/
font_pack_glyph_bitmap :: proc(
	surface: ^sdl.Surface,
	bearing_x: f32,
	bearing_y: f32,
	glyph_id: u32,
) -> (
	Font_Glyph_Entry,
	bool,
) {
	if surface == nil {
		return {}, false
	}

	region, fail := font_atlas_pack_funnel(surface)
	if fail == .Oversize {
		return font_pack_glyph_standalone(surface, bearing_x, bearing_y, glyph_id)
	}

	if fail != .None {
		log_errorf("atlas pack funnel failed for glyph %d (%v)", glyph_id, fail)

		return {}, false
	}

	atlas := texture_atlas_by_id(region.texture_id)
	if atlas == nil {
		return {}, false
	}

	return Font_Glyph_Entry {
			region = region,
			bearing_x = bearing_x,
			bearing_y = bearing_y,
			last_used_frame = atlas_current_frame(),
			generation = atlas.generation,
		},
		true
}

/*
ASCII printable + common UI punctuation for face-load prefetch call sites.
*/
FONT_PREFETCH_ASCII_UI :: " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~"

/*
Ensures glyph ids are rasterized into the atlas and marks them Prefetched|Pinned.

Call at face load (`FONT_PREFETCH_ASCII_UI`), locale switch, or before HUD strings
so the first visible frame avoids raster hitch. Pins expire after
`ATLAS_PREFETCH_PIN_FRAMES` unused frames (Group C).
*/
font_prefetch_glyphs :: proc(
	face: ^Font_Face,
	face_id: Asset_Id,
	glyph_ids: []u32,
	render_mode: Font_Glyph_Render_Mode = .Gray,
) -> bool {
	if face == nil || len(glyph_ids) == 0 {
		return true
	}

	atlas_owner_lock()
	defer atlas_owner_unlock()

	shaped := make([]Shaped_Glyph, len(glyph_ids), context.temp_allocator)
	for id, i in glyph_ids {
		shaped[i] = Shaped_Glyph {
			glyph_id = id,
		}
	}

	if !font_ensure_glyphs(face, face_id, shaped, render_mode) {
		return false
	}

	for id in glyph_ids {
		key := Font_Glyph_Key {
			face_id     = face_id,
			glyph_id    = id,
			render_mode = render_mode,
		}
		entry, ok := &state.fonts.glyph_cache[key]
		if !ok {
			continue
		}

		if !font_glyph_entry_is_live(entry^) {
			continue
		}

		entry.flags += {.Prefetched, .Pinned}
		font_glyph_entry_touch(entry)
	}

	return true
}

/*
Shapes `text`, ensures glyphs, and marks them Prefetched|Pinned.

Prefer for locale/HUD strings. For face-load ASCII/UI charset, pass
`FONT_PREFETCH_ASCII_UI` (or a locale subset).

Shaping uses `context.temp_allocator` (call-scoped scratch), not the layout
frame arena — only glyph ids are retained into the long-lived cache (Group I).
*/
font_prefetch_text :: proc(
	face: ^Font_Face,
	face_id: Asset_Id,
	text: string,
	direction: Text_Direction_Kind = .LTR,
	render_mode: Font_Glyph_Render_Mode = .Gray,
) -> bool {
	if face == nil || len(text) == 0 {
		return true
	}

	shaped := font_shape(face, text, direction, context.temp_allocator)
	if len(shaped) == 0 {
		return true
	}

	ids := make([]u32, len(shaped), context.temp_allocator)
	for g, i in shaped {
		ids[i] = g.glyph_id
	}

	return font_prefetch_glyphs(face, face_id, ids, render_mode)
}

@(private)
font_raster_temp_face_close :: proc(library: ^FT_Library, ft_face: ^FT_Face) {
	if ft_face != nil && ft_face^ != nil {
		Done_Face(ft_face^)
		ft_face^ = nil
	}

	if library != nil && library^ != nil {
		Done_FreeType(library^)
		library^ = nil
	}
}

/*
Ensures the bounded FreeType raster pool is running with persistent scratch arenas.

Returns false if threads or scratch cannot be allocated (caller falls back to serial).
*/
font_raster_pool_ensure :: proc() -> bool {
	if state == nil {
		return false
	}

	if state.fonts.raster_pool != nil && state.fonts.raster_pool.started_count == FONT_GLYPH_MAX_WORKERS {
		return true
	}

	if state.fonts.raster_pool != nil {
		font_raster_pool_shutdown()
	}

	pool := new(Font_Raster_Pool)
	if pool == nil {
		return false
	}

	pool.quit = false
	state.fonts.raster_pool = pool

	for i in 0 ..< FONT_GLYPH_MAX_WORKERS {
		slot := &pool.slots[i]
		slot.pool = pool
		backing := make([]u8, FONT_RASTER_WORKER_SCRATCH)
		if len(backing) != FONT_RASTER_WORKER_SCRATCH {
			font_raster_pool_shutdown()

			return false
		}

		mem.arena_init(&slot.chunk.scratch, backing)
		slot.chunk.scratch_backing = backing
		slot.thread = thread.create_and_start_with_poly_data(slot, font_raster_pool_worker)
		if slot.thread == nil {
			delete(slot.chunk.scratch_backing)
			slot.chunk.scratch_backing = nil
			slot.chunk.scratch = {}
			slot.pool = nil
			font_raster_pool_shutdown()

			return false
		}

		pool.started_count += 1
	}

	return true
}

/*
Signals quit, joins workers, and frees pool scratch + heap (owner lock held).
*/
font_raster_pool_shutdown :: proc() {
	if state == nil || state.fonts.raster_pool == nil {
		return
	}

	pool := state.fonts.raster_pool
	pool.quit = true

	for i in 0 ..< pool.started_count {
		sync.sema_post(&pool.slots[i].work_sema)
	}

	for i in 0 ..< pool.started_count {
		slot := &pool.slots[i]
		if slot.thread != nil {
			thread.join(slot.thread)
			thread.destroy(slot.thread)
			slot.thread = nil
		}

		if slot.chunk.scratch_backing != nil {
			delete(slot.chunk.scratch_backing)
			slot.chunk.scratch_backing = nil
			slot.chunk.scratch = {}
		}

		slot.chunk.jobs = nil
		slot.pool = nil
	}

	free(pool)
	state.fonts.raster_pool = nil
}

/*
Persistent pool worker: wait for work, rasterize chunk, signal done, or quit.
*/
@(private)
font_raster_pool_worker :: proc(slot: ^Font_Raster_Pool_Slot) {
	if slot == nil || slot.pool == nil {
		return
	}

	for {
		sync.sema_wait(&slot.work_sema)
		if slot.pool.quit {
			return
		}

		font_raster_worker_chunk(&slot.chunk)
		sync.sema_post(&slot.pool.done_sema)
	}
}

/*
Worker entry: rasterizes a chunk with temporary FreeType faces only.

Never mutates shelves, glyph_cache, or pending_uploads (Group G).
Scratch path/coords use the chunk's private arena (Group I).
*/
@(private)
font_raster_worker_chunk :: proc(args: ^Font_Raster_Worker_Chunk) {
	if args == nil || len(args.jobs) == 0 {
		return
	}

	scratch_alloc := mem.arena_allocator(&args.scratch)
	context.allocator = scratch_alloc
	context.temp_allocator = scratch_alloc

	current_face: ^Font_Face
	library: FT_Library
	ft_face: FT_Face
	defer font_raster_temp_face_close(&library, &ft_face)

	for &job in args.jobs {
		if job.face == nil {
			job.ok = false
			continue
		}

		if job.face != current_face {
			font_raster_temp_face_close(&library, &ft_face)
			mem.arena_free_all(&args.scratch)
			current_face = job.face
			ok: bool
			library, ft_face, ok = font_open_temp_raster_face(job.face, scratch_alloc)
			if !ok {
				job.ok = false
				current_face = nil
				library = nil
				ft_face = nil
				continue
			}
		}

		surface, bx, by, rok := font_rasterize_glyph_bitmap(
			ft_face,
			job.face.fake_bold,
			job.glyph_id,
			job.face.pixel_size,
			job.render_mode,
		)
		job.surface = surface
		job.bearing_x = bx
		job.bearing_y = by
		job.ok = rok
	}
}

/*
Rasterizes jobs on the owner thread using each job's engine face (no workers).
*/
@(private)
font_rasterize_jobs_serial :: proc(jobs: []Font_Raster_Job) {
	atlas_owner_assert_held()
	atlas_owner_assert_no_raster_workers()

	for &job in jobs {
		if job.face == nil || job.face.ft_face == nil {
			job.ok = false
			continue
		}

		surface, bx, by, rok := font_rasterize_glyph_bitmap(
			job.face.ft_face,
			job.face.fake_bold,
			job.glyph_id,
			job.face.pixel_size,
			job.render_mode,
		)
		job.surface = surface
		job.bearing_x = bx
		job.bearing_y = by
		job.ok = rok
	}
}

/*
Parallel FreeType raster for a job list via the bounded worker pool.

Owner lock must be held. Shelf/cache mutation is forbidden until this returns
(`raster_workers` tracks the burst). Falls back to serial if the pool cannot start.
*/
font_rasterize_jobs :: proc(jobs: []Font_Raster_Job) {
	atlas_owner_assert_held()
	atlas_owner_assert_no_raster_workers()

	if len(jobs) == 0 {
		return
	}

	if len(jobs) < FONT_GLYPH_PARALLEL_THRESHOLD {
		font_rasterize_jobs_serial(jobs)

		return
	}

	if !font_raster_pool_ensure() {
		font_rasterize_jobs_serial(jobs)

		return
	}

	pool := state.fonts.raster_pool
	n_workers := min(FONT_GLYPH_MAX_WORKERS, len(jobs))

	base := 0
	for w in 0 ..< n_workers {
		remaining := len(jobs) - base
		chunks_left := n_workers - w
		count := remaining / chunks_left
		slot := &pool.slots[w]
		mem.arena_free_all(&slot.chunk.scratch)
		slot.chunk.jobs = jobs[base:][:count]
		base += count
	}

	atlas_owner_begin_raster_workers(n_workers)
	defer atlas_owner_end_raster_workers()

	for w in 0 ..< n_workers {
		sync.sema_post(&pool.slots[w].work_sema)
	}

	for w in 0 ..< n_workers {
		_ = w
		sync.sema_wait(&pool.done_sema)
	}
}

/*
Rasterizes missing glyph ids and inserts them into the glyph cache.

Uses the serial FreeType path for small miss counts; larger sets fan out to
temporary faces on worker threads, then pack into the atlas on this thread.
Owner lock must already be held (ensure/prefetch).
*/
font_rasterize_and_cache_missing :: proc(
	face: ^Font_Face,
	face_id: Asset_Id,
	missing: []u32,
	render_mode: Font_Glyph_Render_Mode = .Gray,
) -> bool {
	atlas_owner_assert_held()

	if len(missing) == 0 {
		return true
	}

	cache_key :: proc(face_id: Asset_Id, gid: u32, mode: Font_Glyph_Render_Mode) -> Font_Glyph_Key {
		return Font_Glyph_Key{face_id = face_id, glyph_id = gid, render_mode = mode}
	}

	jobs := make([]Font_Raster_Job, len(missing), context.temp_allocator)
	for gid, i in missing {
		jobs[i] = Font_Raster_Job {
			face        = face,
			glyph_id    = gid,
			render_mode = render_mode,
		}
	}

	defer {
		for &job in jobs {
			if job.surface != nil {
				sdl.DestroySurface(job.surface)
				job.surface = nil
			}
		}
	}

	font_rasterize_jobs(jobs)

	for &job in jobs {
		if !job.ok || job.surface == nil {
			return false
		}

		entry, ok := font_pack_glyph_bitmap(job.surface, job.bearing_x, job.bearing_y, job.glyph_id)
		if !ok {
			return false
		}

		state.fonts.glyph_cache[cache_key(face_id, job.glyph_id, render_mode)] = entry
		sdl.DestroySurface(job.surface)
		job.surface = nil
	}

	return true
}

/*
Rasterizes a single glyph via FreeType and packs it into the texture atlas.

Applies synthetic embolden when the face instance requests fake bold.
*/
font_rasterize_glyph :: proc(
	face: ^Font_Face,
	glyph_id: u32,
	render_mode: Font_Glyph_Render_Mode = .Gray,
) -> (
	Font_Glyph_Entry,
	bool,
) {
	if face == nil || face.ft_face == nil do return {}, false
	surface, bx, by, ok := font_rasterize_glyph_bitmap(
		face.ft_face,
		face.fake_bold,
		glyph_id,
		face.pixel_size,
		render_mode,
	)
	if !ok do return {}, false
	defer sdl.DestroySurface(surface)
	return font_pack_glyph_bitmap(surface, bx, by, glyph_id)
}

/*
Returns a pointer to scanline `row` of a FreeType bitmap.

Honors FreeType's signed pitch: negative pitch means bottom-up storage while
`buffer` still addresses the visually topmost row.
*/
font_bitmap_row :: proc(buffer: [^]u8, pitch: c.int, row: int) -> [^]u8 {
	return mem.ptr_offset(buffer, row * int(pitch))
}

/*
Copies a FreeType glyph bitmap into an RGBA SDL surface.

Gray/mono → white with coverage in alpha. LCD → RGB coverage (logical width =
bitmap.width/3); alpha is unused by the LCD shader and written as 255.
Handles negative pitch; logs a warning for unsupported modes.
*/
font_copy_glyph_bitmap :: proc(bitmap: ^FT_Bitmap, surface: ^sdl.Surface) {
	w := int(bitmap.width)
	h := int(bitmap.rows)
	if w <= 0 || h <= 0 || bitmap.buffer == nil || surface == nil do return

	switch bitmap.pixel_mode {
	case FT_PIXEL_MODE_GRAY:
		for row in 0 ..< h {
			src := font_bitmap_row(bitmap.buffer, bitmap.pitch, row)
			for col in 0 ..< w {
				sdl.WriteSurfacePixel(surface, c.int(col), c.int(row), 255, 255, 255, src[col])
			}
		}
	case FT_PIXEL_MODE_MONO:
		for row in 0 ..< h {
			src := font_bitmap_row(bitmap.buffer, bitmap.pitch, row)
			for col in 0 ..< w {
				byte := src[col / 8]
				bit := (byte >> u8(7 - (col % 8))) & 1
				alpha: u8 = bit != 0 ? 255 : 0
				sdl.WriteSurfacePixel(surface, c.int(col), c.int(row), 255, 255, 255, alpha)
			}
		}
	case FT_PIXEL_MODE_LCD:
		if w % 3 != 0 {
			log_warnf("LCD glyph bitmap width %d is not divisible by 3", w)

			return
		}

		logical_w := w / 3
		for row in 0 ..< h {
			src := font_bitmap_row(bitmap.buffer, bitmap.pitch, row)
			for col in 0 ..< logical_w {
				src_off := col * 3
				sdl.WriteSurfacePixel(
					surface,
					c.int(col),
					c.int(row),
					src[src_off + 0],
					src[src_off + 1],
					src[src_off + 2],
					255,
				)
			}
		}
	case FT_PIXEL_MODE_BGRA:
		for row in 0 ..< h {
			src := font_bitmap_row(bitmap.buffer, bitmap.pitch, row)
			for col in 0 ..< w {
				src_off := col * 4
				sdl.WriteSurfacePixel(
					surface,
					c.int(col),
					c.int(row),
					src[src_off + 2],
					src[src_off + 1],
					src[src_off + 0],
					src[src_off + 3],
				)
			}
		}
	case:
		log_warnf("Unsupported glyph pixel mode %d", bitmap.pixel_mode)
	}
}

/*
Returns the effective line height for text layout, preferring an explicit override.

Falls back to the face line height scaled by layout_scale when line_height is zero.
*/
font_text_line_height :: proc(face: ^Font_Face, line_height: f32, layout_scale: f32) -> f32 {
	if line_height > 0 do return line_height
	return face.line_height * layout_scale
}

/*
Estimates horizontal advance for one text segment using FreeType glyph metrics.

Does not call HarfBuzz. Used during layout measure before finalize shaping.
*/
font_text_segment_advance_estimate :: proc(
	face: ^Font_Face,
	text: string,
	letter_spacing: f32,
	word_spacing: f32,
) -> f32 {
	if face == nil || len(text) == 0 do return 0

	width: f32
	glyph_count := 0

	for i := 0; i < len(text); {
		if text[i] == '\r' {
			i += 1

			if i < len(text) && text[i] == '\n' {
				i += 1
			}

			continue
		}

		if text[i] == '\n' do break

		r, w := utf8.decode_rune_in_string(text[i:])
		if w == 0 do break

		glyph_index := Get_Char_Index(face.ft_face, c.ulong(r))
		if glyph_index == 0 {
			i += w
			continue
		}

		if !ft_ok(Load_Glyph(face.ft_face, glyph_index, font_load_flags(face.pixel_size, c.int(FT_LOAD_DEFAULT)))) {
			i += w
			continue
		}

		slot := ft_glyph_slot(face.ft_face)
		if face.fake_bold {
			GlyphSlot_Embolden(slot)
		}

		if glyph_count > 0 {
			width += letter_spacing
		}

		width += font_device_to_logical(ft_pos_to_f32(ft_slot_metrics(slot).hori_advance))

		if r == ' ' || r == '\t' {
			width += word_spacing
		}

		glyph_count += 1
		i += w
	}

	return width
}

/*
Estimates the widest line advance for newline-separated text.

When expand_tabs is true, tabs are expanded on the temp allocator before measuring.
*/
font_text_max_line_advance_estimate :: proc(
	face: ^Font_Face,
	text: string,
	letter_spacing: f32,
	word_spacing: f32,
	expand_tabs: bool,
	tab_size: f32,
) -> f32 {
	if face == nil || len(text) == 0 do return 0

	max_width: f32
	line_start := 0

	for i in 0 ..= len(text) {
		if i < len(text) && text[i] != '\n' do continue

		segment := text[line_start:i]
		if expand_tabs && strings.contains_rune(segment, '\t') {
			segment = text_expand_tabs(segment, tab_size, context.temp_allocator)
		}

		line_width := font_text_segment_advance_estimate(face, segment, letter_spacing, word_spacing)
		max_width = max(max_width, line_width)
		line_start = i + 1
	}

	return max_width
}

/*
Estimates CSS min-content inline size: widest unbreakable run.

Break opportunities match soft-wrap (`font_is_break_cluster`): space, tab, and
hard newlines. Does not call HarfBuzz.
*/
font_text_min_content_advance_estimate :: proc(
	face: ^Font_Face,
	text: string,
	letter_spacing: f32,
) -> f32 {
	if face == nil || len(text) == 0 do return 0

	max_width: f32
	run_start := 0

	for i in 0 ..= len(text) {
		at_end := i >= len(text)
		is_break := !at_end && (text[i] == ' ' || text[i] == '\t' || text[i] == '\n')

		if !at_end && !is_break do continue

		if i > run_start {
			run_width := font_text_segment_advance_estimate(
				face,
				text[run_start:i],
				letter_spacing,
				0,
			)
			max_width = max(max_width, run_width)
		}

		run_start = i + 1
	}

	return max_width
}

/*
Computes the bounding size of shaped lines using the widest line and line count.

Applies layout_scale to line widths and uses font_text_line_height for height.
*/
font_measure_lines :: proc(
	face: ^Font_Face,
	lines: []Shaped_Line,
	line_height: f32 = 0,
	layout_scale: f32 = 1,
) -> Vec2 {
	if face == nil || len(lines) == 0 do return {}

	width: f32
	for line in lines {
		width = max(width, line.width * layout_scale)
	}

	lh := font_text_line_height(face, line_height, layout_scale)
	return {width, f32(len(lines)) * lh}
}

/*
Snaps a logical coordinate onto a device-pixel boundary.

`logical * dpi.scale` lands on an integer drawable pixel so glyph edges do not
straddle fragments after the present transform.
*/
snap_logical :: proc(v: f32) -> f32 {
	scale := font_dpi_scale()

	return math.round(v * scale) / scale
}

/*
Builds a logical paint quad from a cached atlas glyph entry.

`layout_scale` maps artboard-zoomed face units back to layout space. Bitmap
size and bearings stay device-pixel in the cache and are converted here.
*/
font_glyph_paint_from_entry :: proc(
	face_id: Asset_Id,
	glyph: Shaped_Glyph,
	entry: Font_Glyph_Entry,
	pen_x, baseline_y, layout_scale: f32,
	run_index: u16 = 0,
) -> Layout_Glyph_Paint {
	scale := layout_scale
	if scale <= 0 do scale = 1

	bx := font_device_to_logical(entry.bearing_x) * scale
	by := font_device_to_logical(entry.bearing_y) * scale
	w := font_device_to_logical(entry.region.w) * scale
	h := font_device_to_logical(entry.region.h) * scale

	if w <= 0 do w = font_device_to_logical(1) * scale
	if h <= 0 do h = font_device_to_logical(1) * scale

	glyph_x := pen_x + glyph.x_offset * scale
	glyph_y := baseline_y + glyph.y_offset * scale - by

	return Layout_Glyph_Paint {
		face_id = face_id,
		glyph_id = glyph.glyph_id,
		dst = {
			x = snap_logical(glyph_x + bx),
			y = snap_logical(glyph_y),
			w = w,
			h = h,
		},
		run_index = run_index,
	}
}

/*
Draws layout-owned shaped text using precomputed glyph quads and decoration strokes.

Does not reshape, wrap, align, or position — layout owns those.
Uses should_use_lcd for raster mode and Batch_Key.lcd (same gate as layout).
*/
font_draw_layout_text :: proc(
	laid: ^Layout_Text,
	color: RGBA,
	decoration_color: RGBA = {},
	run_colors: []RGBA = nil,
) -> Vec2 {
	if laid == nil || len(laid.lines) == 0 do return {}

	opacity := draw_effective_opacity()

	if len(laid.glyphs) > 0 {
		if !font_ensure_glyphs_from_paint_for_draw(laid.glyphs, color, run_colors, opacity) {
			return {}
		}
	}

	glyph_color :: proc(
		paint: Layout_Glyph_Paint,
		default_color: RGBA,
		run_colors: []RGBA,
	) -> RGBA {
		if len(run_colors) == 0 do return default_color

		idx := int(paint.run_index)

		if idx < 0 || idx >= len(run_colors) do return default_color

		return run_colors[idx]
	}

	nearest := font_text_uses_nearest_filter()

	for paint in laid.glyphs {
		tint := glyph_color(paint, color, run_colors)
		mode := font_glyph_render_mode_for_draw(
			{tint_a = tint.a, effective_opacity = opacity, axis_aligned = true},
		)
		lcd := mode == .LCD

		key := Font_Glyph_Key {
			face_id     = paint.face_id,
			glyph_id    = paint.glyph_id,
			render_mode = mode,
		}
		entry_ptr, ok := &state.fonts.glyph_cache[key]
		if !ok {
			continue
		}

		if !font_glyph_entry_is_live(entry_ptr^) {
			continue
		}

		font_glyph_entry_touch(entry_ptr)
		entry := entry_ptr^

		// Standalone oversize glyphs are not in the multi-atlas sampler set.
		if .Standalone in entry.flags || state.textures.atlas_draw_mode != .Multi_Texture {
			draw_glyph_atlas_region(entry.region, paint.dst, tint, lcd)
			continue
		}

		slot, slot_ok := texture_atlas_slot_for_id(entry.region.texture_id)
		texture := texture_handle(entry.region.texture_id)
		if !slot_ok || texture.w <= 0 || texture.h <= 0 {
			continue
		}

		uv := Rect {
			entry.region.x / texture.w,
			entry.region.y / texture.h,
			entry.region.w / texture.w,
			entry.region.h / texture.h,
		}
		batch_current().dpi = state.dpi
		batch_check_key(
			state.textures.atlas.texture_id,
			nearest,
			lcd,
			true,
		)
		batch_push_axis_quad(
			paint.dst,
			uv,
			tint,
			{},
			{paint.dst.w, paint.dst.h},
			{},
			{},
			.Textured_Text,
			true,
			f32(slot),
		)
	}

	if decoration_color.a > 0 || len(laid.decoration_strokes) > 0 {
		for stroke in laid.decoration_strokes {
			stroke_color := stroke.color

			if stroke_color.a == 0 && decoration_color.a > 0 {
				stroke_color = decoration_color
			}

			draw_line(stroke.a, stroke.b, stroke_color, stroke.thickness)
		}
	}

	return laid.size
}

/*
Ensures atlas glyphs for paint quads using each glyph's gated render mode at draw.
*/
font_ensure_glyphs_from_paint_for_draw :: proc(
	glyphs: []Layout_Glyph_Paint,
	default_color: RGBA,
	run_colors: []RGBA,
	effective_opacity: f32,
) -> bool {
	if len(glyphs) == 0 do return true

	atlas_owner_lock()
	defer atlas_owner_unlock()

	if !texture_atlas_init() do return false

	Face_Mode :: struct {
		face_id:     Asset_Id,
		render_mode: Font_Glyph_Render_Mode,
	}

	face_missing := make(map[Face_Mode][dynamic]u32, context.temp_allocator)

	for paint in glyphs {
		tint := default_color
		if len(run_colors) > 0 {
			idx := int(paint.run_index)
			if idx >= 0 && idx < len(run_colors) {
				tint = run_colors[idx]
			}
		}

		mode := font_glyph_render_mode_for_draw(
			{tint_a = tint.a, effective_opacity = effective_opacity, axis_aligned = true},
		)
		key := Font_Glyph_Key {
			face_id     = paint.face_id,
			glyph_id    = paint.glyph_id,
			render_mode = mode,
		}

		if entry, ok := &state.fonts.glyph_cache[key]; ok {
			if font_glyph_entry_is_live(entry^) {
				font_glyph_entry_touch(entry)
				continue
			}

			font_glyph_cache_drop(key)
		}

		fm := Face_Mode {
			face_id     = paint.face_id,
			render_mode = mode,
		}
		list, list_ok := &face_missing[fm]
		if !list_ok {
			face_missing[fm] = make([dynamic]u32, context.temp_allocator)
			list = &face_missing[fm]
		}

		seen := false
		for id in list {
			if id == paint.glyph_id {
				seen = true
				break
			}
		}

		if seen {
			continue
		}

		append(list, paint.glyph_id)
	}

	for fm, missing in face_missing {
		if len(missing) == 0 do continue

		face := font_face_from_handle(Font_Face_Handle{id = fm.face_id})
		if face == nil do return false

		if !font_rasterize_and_cache_missing(face, fm.face_id, missing[:], fm.render_mode) {
			return false
		}
	}

	return true
}

/*
Ensures atlas glyphs exist for precomputed layout glyph paint quads.
*/
font_ensure_glyphs_from_paint :: proc(
	glyphs: []Layout_Glyph_Paint,
	render_mode: Font_Glyph_Render_Mode = .Gray,
) -> bool {
	if len(glyphs) == 0 do return true

	atlas_owner_lock()
	defer atlas_owner_unlock()

	if !texture_atlas_init() do return false

	face_missing := make(map[Asset_Id][dynamic]u32, context.temp_allocator)

	for paint in glyphs {
		key := Font_Glyph_Key {
			face_id     = paint.face_id,
			glyph_id    = paint.glyph_id,
			render_mode = render_mode,
		}

		if entry, ok := &state.fonts.glyph_cache[key]; ok {
			if font_glyph_entry_is_live(entry^) {
				font_glyph_entry_touch(entry)
				continue
			}

			font_glyph_cache_drop(key)
		}

		list, list_ok := &face_missing[paint.face_id]
		if !list_ok {
			face_missing[paint.face_id] = make([dynamic]u32, context.temp_allocator)
			list = &face_missing[paint.face_id]
		}

		seen := false

		for id in list {
			if id == paint.glyph_id {
				seen = true
				break
			}
		}

		if seen {
			continue
		}

		append(list, paint.glyph_id)
	}

	for face_id, missing in face_missing {
		if len(missing) == 0 do continue

		face := font_face_from_handle(Font_Face_Handle{id = face_id})
		if face == nil do return false

		if !font_rasterize_and_cache_missing(face, face_id, missing[:], render_mode) do return false
	}

	return true
}

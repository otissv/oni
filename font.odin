package oni

import "core:c"
import "core:math"
import "core:mem"
import "core:strings"
import "core:thread"
import sdl "vendor:sdl3"

FONT_GLYPH_PARALLEL_THRESHOLD :: 4
FONT_GLYPH_MAX_WORKERS :: 4

/*
Owned FreeType render result before serial atlas packing.
*/
Font_Glyph_Bitmap_Result :: struct {
	glyph_id:  u32,
	surface:   ^sdl.Surface,
	bearing_x: f32,
	bearing_y: f32,
	ok:        bool,
}

/*
Per-worker glyph subset for parallel FreeType rasterization.

Each worker opens a temporary FT_Face (and FT_Library) so FreeType work never
touches the engine face concurrently.
*/
Font_Glyph_Worker_Args :: struct {
	face:      ^Font_Face,
	glyph_ids: []u32,
	results:   []Font_Glyph_Bitmap_Result,
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
Loads one glyph outline and returns layout paint metrics without rasterizing.

Uses FT_LOAD_DEFAULT (or FT_LOAD_NO_BITMAP + embolden for synthetic bold) so
layout can position quads while draw owns atlas rasterization.
*/
font_glyph_metrics :: proc(face: ^Font_Face, glyph_id: u32) -> (w, h, bearing_x, bearing_y: f32, ok: bool) {
	if face == nil || face.ft_face == nil do return 0, 0, 0, 0, false

	load_flags: c.int = face.fake_bold ? c.int(FT_LOAD_NO_BITMAP) : c.int(FT_LOAD_DEFAULT)
	if !ft_ok(Load_Glyph(face.ft_face, c.uint(glyph_id), load_flags)) {
		log_errorf("FT_Load_Glyph failed for metrics glyph %d", glyph_id)
		return 0, 0, 0, 0, false
	}

	slot := ft_glyph_slot(face.ft_face)
	if face.fake_bold {
		GlyphSlot_Embolden(slot)
	}

	metrics := ft_slot_metrics(slot)^
	w = ft_pos_to_f32(metrics.width)
	h = ft_pos_to_f32(metrics.height)
	bearing_x = ft_pos_to_f32(metrics.hori_bearing_x)
	bearing_y = ft_pos_to_f32(metrics.hori_bearing_y)

	if w <= 0 || h <= 0 {
		w = 1
		h = 1
		bearing_x = 0
		bearing_y = 0
	}

	return w, h, bearing_x, bearing_y, true
}

/*
Clears the font atlas CPU surface and resets shelf allocation state.

Used before reloading faces so glyph packing starts from a clean atlas.
*/
font_atlas_reset :: proc() {
	if state.textures.atlas.texture_id == INVALID_ASSET_ID do return

	index := int(state.textures.atlas.texture_id)
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

	clear(&state.textures.atlas.shelves)
}

/*
Rasterizes and caches any glyphs from shaped lines that are not yet in the atlas.

Ensures the atlas is initialized before packing missing glyphs. Large miss sets
rasterize FreeType bitmaps in parallel, then pack into the atlas serially.
*/
font_ensure_glyphs :: proc(face: ^Font_Face, face_id: Asset_Id, glyphs: []Shaped_Glyph) -> bool {
	if face == nil || len(glyphs) == 0 do return true

	missing := make([dynamic]u32, 0, len(glyphs), context.temp_allocator)
	seen := make(map[u32]struct{}, context.temp_allocator)

	for glyph in glyphs {
		key := Font_Glyph_Key {
			face_id  = face_id,
			glyph_id = glyph.glyph_id,
		}
		if key in state.fonts.glyph_cache do continue
		if glyph.glyph_id in seen do continue
		seen[glyph.glyph_id] = {}
		append(&missing, glyph.glyph_id)
	}
	if len(missing) == 0 do return true
	if !texture_atlas_init() do return false
	return font_rasterize_and_cache_missing(face, face_id, missing[:])
}

/*
Opens a temporary FreeType library + face matching `face` for worker rasterization.

Caller must Done_Face then Done_FreeType. Does not use the engine FT_Library so
New_Face/Load_Glyph stay off the shared face/library on other threads.
*/
font_open_temp_raster_face :: proc(face: ^Font_Face) -> (library: FT_Library, ft_face: FT_Face, ok: bool) {
	if face == nil || len(face.path) == 0 do return {}, nil, false

	if !ft_ok(Init_FreeType(&library)) {
		log_error("FT_Init_FreeType failed for worker face")
		return {}, nil, false
	}

	cpath := strings.clone_to_cstring(face.path)
	if cpath == nil {
		Done_FreeType(library)
		return {}, nil, false
	}
	defer delete(cpath)

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
		coords := make([]FT_Fixed, int(mm.num_axis))
		defer delete(coords)
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
*/
font_rasterize_glyph_bitmap :: proc(
	ft_face: FT_Face,
	fake_bold: bool,
	glyph_id: u32,
) -> (
	surface: ^sdl.Surface,
	bearing_x: f32,
	bearing_y: f32,
	ok: bool,
) {
	if ft_face == nil do return nil, 0, 0, false

	load_flags: c.int = fake_bold ? c.int(FT_LOAD_NO_BITMAP) : c.int(FT_LOAD_RENDER)
	if !ft_ok(Load_Glyph(ft_face, c.uint(glyph_id), load_flags)) {
		log_errorf("FT_Load_Glyph failed for glyph %d", glyph_id)
		return nil, 0, 0, false
	}

	slot := ft_glyph_slot(ft_face)
	if fake_bold {
		GlyphSlot_Embolden(slot)
	}

	if ft_slot_format(slot) != .BITMAP {
		if !ft_ok(Render_Glyph(slot, FT_RENDER_MODE_NORMAL)) {
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

	surface = sdl.CreateSurface(w, h, .RGBA8888)
	if surface == nil {
		log_error("SDL_CreateSurface failed for glyph bitmap")
		return nil, 0, 0, false
	}
	font_copy_glyph_bitmap(&bitmap, surface)
	return surface, bearing_x, bearing_y, true
}

/*
Packs a rasterized glyph surface into the atlas and returns the cache entry.
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
	if surface == nil do return {}, false
	region, ok := texture_atlas_pack(surface)
	if !ok {
		log_errorf("texture_atlas_pack failed for glyph %d", glyph_id)
		return {}, false
	}
	return Font_Glyph_Entry{region = region, bearing_x = bearing_x, bearing_y = bearing_y}, true
}

@(private)
font_glyph_worker :: proc(args: ^Font_Glyph_Worker_Args) {
	if args == nil || args.face == nil do return

	library, ft_face, ok := font_open_temp_raster_face(args.face)
	if !ok {
		for i in 0 ..< len(args.glyph_ids) {
			args.results[i] = Font_Glyph_Bitmap_Result {
				glyph_id = args.glyph_ids[i],
				ok       = false,
			}
		}
		return
	}
	defer {
		Done_Face(ft_face)
		Done_FreeType(library)
	}

	for i in 0 ..< len(args.glyph_ids) {
		gid := args.glyph_ids[i]
		surface, bx, by, rok := font_rasterize_glyph_bitmap(ft_face, args.face.fake_bold, gid)
		args.results[i] = Font_Glyph_Bitmap_Result {
			glyph_id  = gid,
			surface   = surface,
			bearing_x = bx,
			bearing_y = by,
			ok        = rok,
		}
	}
}

/*
Rasterizes missing glyph ids and inserts them into the glyph cache.

Uses the serial FreeType path for small miss counts; larger sets fan out to
temporary faces on worker threads, then pack into the atlas on this thread.
*/
font_rasterize_and_cache_missing :: proc(face: ^Font_Face, face_id: Asset_Id, missing: []u32) -> bool {
	if len(missing) == 0 do return true

	if len(missing) < FONT_GLYPH_PARALLEL_THRESHOLD {
		for gid in missing {
			entry, ok := font_rasterize_glyph(face, gid)
			if !ok do return false
			state.fonts.glyph_cache[Font_Glyph_Key{face_id = face_id, glyph_id = gid}] = entry
		}
		return true
	}

	results := make([]Font_Glyph_Bitmap_Result, len(missing))
	defer {
		for &r in results {
			if r.surface != nil {
				sdl.DestroySurface(r.surface)
				r.surface = nil
			}
		}
		delete(results)
	}

	n_workers := min(FONT_GLYPH_MAX_WORKERS, len(missing))
	worker_args := make([]Font_Glyph_Worker_Args, n_workers)
	defer delete(worker_args)

	base := 0
	for w in 0 ..< n_workers {
		remaining := len(missing) - base
		chunks_left := n_workers - w
		count := remaining / chunks_left
		worker_args[w] = Font_Glyph_Worker_Args {
			face      = face,
			glyph_ids = missing[base:][:count],
			results   = results[base:][:count],
		}
		base += count
	}

	threads := make([]^thread.Thread, n_workers)
	defer {
		for t in threads {
			if t != nil do thread.destroy(t)
		}
		delete(threads)
	}

	for w in 0 ..< n_workers {
		threads[w] = thread.create_and_start_with_poly_data(&worker_args[w], font_glyph_worker)
		if threads[w] == nil {
			// Finish any started workers, then fall back to serial for the whole set.
			for j in 0 ..< w {
				thread.join(threads[j])
			}
			for &r in results {
				if r.surface != nil {
					sdl.DestroySurface(r.surface)
					r.surface = nil
				}
			}
			for gid in missing {
				entry, ok := font_rasterize_glyph(face, gid)
				if !ok do return false
				state.fonts.glyph_cache[Font_Glyph_Key{face_id = face_id, glyph_id = gid}] = entry
			}
			return true
		}
	}

	for w in 0 ..< n_workers {
		thread.join(threads[w])
	}

	for &r in results {
		if !r.ok || r.surface == nil do return false
		entry, ok := font_pack_glyph_bitmap(r.surface, r.bearing_x, r.bearing_y, r.glyph_id)
		if !ok do return false
		state.fonts.glyph_cache[Font_Glyph_Key{face_id = face_id, glyph_id = r.glyph_id}] = entry
		sdl.DestroySurface(r.surface)
		r.surface = nil
	}
	return true
}

/*
Rasterizes a single glyph via FreeType and packs it into the texture atlas.

Applies synthetic embolden when the face instance requests fake bold.
*/
font_rasterize_glyph :: proc(face: ^Font_Face, glyph_id: u32) -> (Font_Glyph_Entry, bool) {
	if face == nil || face.ft_face == nil do return {}, false
	surface, bx, by, ok := font_rasterize_glyph_bitmap(face.ft_face, face.fake_bold, glyph_id)
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
Copies a FreeType glyph bitmap into an RGBA SDL surface as white with alpha.

Handles gray, mono, and BGRA pixel modes (including negative pitch); logs a
warning for unsupported modes.
*/
font_copy_glyph_bitmap :: proc(bitmap: ^FT_Bitmap, surface: ^sdl.Surface) {
	w := int(bitmap.width)
	h := int(bitmap.rows)
	if w <= 0 || h <= 0 || bitmap.buffer == nil do return

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
Snaps a logical coordinate to the nearest half-pixel for crisp glyph placement.
*/
snap_logical :: proc(v: f32) -> f32 {
	return math.round(v * 2) / 2
}

/*
Draws layout-owned shaped text using precomputed glyph quads and decoration strokes.

Does not reshape, wrap, align, or position — layout owns those.
*/
font_draw_layout_text :: proc(
	laid: ^Layout_Text,
	color: RGBA,
	decoration_color: RGBA = {},
	run_colors: []RGBA = nil,
) -> Vec2 {
	if laid == nil || len(laid.lines) == 0 do return {}

	if len(laid.glyphs) > 0 {
		if !font_ensure_glyphs_from_paint(laid.glyphs) do return {}
	}

	atlas := texture_handle(state.textures.atlas.texture_id)
	use_atlas_batch := atlas.id != INVALID_ASSET_ID && atlas.w > 0 && atlas.h > 0

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

	flush_batch :: proc(
		atlas: Texture_Handle,
		use_atlas_batch: bool,
		dsts: ^[dynamic]Rect,
		srcs: ^[dynamic]Rect,
		batch_color: RGBA,
	) {
		if len(dsts) == 0 do return

		if use_atlas_batch {
			batch_push_atlas_quads(atlas, dsts[:], srcs[:], batch_color)
		}

		clear(dsts)
		clear(srcs)
	}

	dsts := make([dynamic]Rect, 0, len(laid.glyphs), context.temp_allocator)
	srcs := make([dynamic]Rect, 0, len(laid.glyphs), context.temp_allocator)
	current_color := color

	for paint in laid.glyphs {
		tint := glyph_color(paint, color, run_colors)

		key := Font_Glyph_Key {
			face_id  = paint.face_id,
			glyph_id = paint.glyph_id,
		}
		entry, ok := state.fonts.glyph_cache[key]
		if !ok do continue

		if use_atlas_batch && entry.region.texture_id == atlas.id {
			if len(dsts) > 0 && tint != current_color {
				flush_batch(atlas, use_atlas_batch, &dsts, &srcs, current_color)
			}

			current_color = tint
			append(&dsts, paint.dst)
			append(
				&srcs,
				Rect{entry.region.x, entry.region.y, entry.region.w, entry.region.h},
			)
		} else {
			flush_batch(atlas, use_atlas_batch, &dsts, &srcs, current_color)
			current_color = tint
			draw_atlas_region(entry.region, paint.dst, tint)
		}
	}

	flush_batch(atlas, use_atlas_batch, &dsts, &srcs, current_color)

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
Ensures atlas glyphs exist for precomputed layout glyph paint quads.
*/
font_ensure_glyphs_from_paint :: proc(glyphs: []Layout_Glyph_Paint) -> bool {
	if len(glyphs) == 0 do return true

	if !texture_atlas_init() do return false

	face_missing: map[Asset_Id][dynamic]u32
	defer {
		for _, list in face_missing {
			delete(list)
		}
		delete(face_missing)
	}

	for paint in glyphs {
		key := Font_Glyph_Key {
			face_id  = paint.face_id,
			glyph_id = paint.glyph_id,
		}

		if key in state.fonts.glyph_cache do continue

		list, ok := &face_missing[paint.face_id]
		if !ok {
			face_missing[paint.face_id] = make([dynamic]u32)
			list = &face_missing[paint.face_id]
		}

		seen := false

		for id in list {
			if id == paint.glyph_id {
				seen = true
				break
			}
		}

		if seen do continue

		append(list, paint.glyph_id)
	}

	for face_id, missing in face_missing {
		if len(missing) == 0 do continue

		face := font_face_from_handle(Font_Face_Handle{id = face_id})
		if face == nil do return false

		if !font_rasterize_and_cache_missing(face, face_id, missing[:]) do return false
	}

	return true
}

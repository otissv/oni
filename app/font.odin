package app

import "core:c"
import "core:math"
import sdl "vendor:sdl3"

font_atlas_reset :: proc() {
	if g.textures.atlas.texture_id == INVALID_ASSET_ID do return

	index := int(g.textures.atlas.texture_id)
	if index > 0 && index < len(g.textures.records) {
		entry := &g.textures.records[index]
		if entry.surface != nil {
			pixels := cast([^]u8)entry.surface.pixels
			size := int(entry.surface.pitch) * int(entry.surface.h)
			for i in 0 ..< size {
				pixels[i] = 0
			}
		}
	}

	clear(&g.textures.atlas.shelves)
}

font_ensure_glyphs :: proc(face: ^Font_Face, face_id: Asset_Id, glyphs: []Shaped_Glyph) -> bool {
	if face == nil || len(glyphs) == 0 do return true
	if !texture_atlas_init() do return false

	for glyph in glyphs {
		key := Font_Glyph_Key{face_id = face_id, glyph_id = glyph.glyph_id}
		if key in g.fonts.glyph_cache do continue

		entry, ok := font_rasterize_glyph(face, key.glyph_id)
		if !ok do return false
		g.fonts.glyph_cache[key] = entry
	}

	return true
}

font_rasterize_glyph :: proc(face: ^Font_Face, glyph_id: u32) -> (Font_Glyph_Entry, bool) {
	if !ft_ok(Load_Glyph(face.ft_face, c.uint(glyph_id), FT_LOAD_RENDER)) {
		log_errorf("FT_Load_Glyph failed for glyph %d", glyph_id)
		return {}, false
	}

	slot := ft_glyph_slot(face.ft_face)
	if ft_slot_format(slot) != .BITMAP {
		if !ft_ok(Render_Glyph(slot, FT_RENDER_MODE_NORMAL)) {
			log_errorf("FT_Render_Glyph failed for glyph %d", glyph_id)
			return {}, false
		}
	}

	bitmap := ft_slot_bitmap(slot)^
	w := i32(bitmap.width)
	h := i32(bitmap.rows)
	if w <= 0 || h <= 0 {
		region, ok := texture_atlas_alloc(1, 1)
		if !ok do return {}, false

		surface := sdl.CreateSurface(1, 1, .RGBA8888)
		if surface == nil do return {}, false
		defer sdl.DestroySurface(surface)

		pixels := cast([^]u8)surface.pixels
		pixels[3] = 0

		if !texture_atlas_upload(region, surface) do return {}, false
		return Font_Glyph_Entry{region = region}, true
	}

	surface := sdl.CreateSurface(w, h, .RGBA8888)
	if surface == nil {
		log_error("SDL_CreateSurface failed for glyph bitmap")
		return {}, false
	}
	defer sdl.DestroySurface(surface)

	font_copy_glyph_bitmap(&bitmap, surface)

	region, ok := texture_atlas_pack(surface)
	if !ok {
		log_errorf("texture_atlas_pack failed for glyph %d", glyph_id)
		return {}, false
	}

	return Font_Glyph_Entry {
		region    = region,
		bearing_x = f32(ft_slot_bitmap_left(slot)),
		bearing_y = f32(ft_slot_bitmap_top(slot)),
	}, true
}

font_copy_glyph_bitmap :: proc(bitmap: ^FT_Bitmap, surface: ^sdl.Surface) {
	dst := cast([^]u8)surface.pixels
	dst_pitch := int(surface.pitch)
	w := int(bitmap.width)
	h := int(bitmap.rows)

	switch bitmap.pixel_mode {
	case FT_PIXEL_MODE_GRAY:
		src := bitmap.buffer
		src_pitch := int(bitmap.pitch)
		for row in 0 ..< h {
			for col in 0 ..< w {
				alpha := src[row * src_pitch + col]
				off := row * dst_pitch + col * 4
				dst[off + 0] = 255
				dst[off + 1] = 255
				dst[off + 2] = 255
				dst[off + 3] = alpha
			}
		}
	case FT_PIXEL_MODE_MONO:
		src := bitmap.buffer
		src_pitch := int(bitmap.pitch)
		for row in 0 ..< h {
			for col in 0 ..< w {
				byte := src[row * src_pitch + col / 8]
				bit := (byte >> u8(7 - (col % 8))) & 1
				alpha: u8 = bit != 0 ? 255 : 0
				off := row * dst_pitch + col * 4
				dst[off + 0] = 255
				dst[off + 1] = 255
				dst[off + 2] = 255
				dst[off + 3] = alpha
			}
		}
	case FT_PIXEL_MODE_BGRA:
		src := bitmap.buffer
		src_pitch := int(bitmap.pitch)
		for row in 0 ..< h {
			for col in 0 ..< w {
				off := row * dst_pitch + col * 4
				src_off := row * src_pitch + col * 4
				dst[off + 0] = src[src_off + 2]
				dst[off + 1] = src[src_off + 1]
				dst[off + 2] = src[src_off + 0]
				dst[off + 3] = src[src_off + 3]
			}
		}
	case:
		log_warnf("Unsupported glyph pixel mode %d", bitmap.pixel_mode)
	}
}

font_measure_lines :: proc(face: ^Font_Face, lines: []Shaped_Line) -> Vec2 {
	if face == nil || len(lines) == 0 do return {}

	width: f32
	for line in lines {
		width = max(width, line.width)
	}

	return {width, f32(len(lines)) * face.line_height}
}

font_measure_cached :: proc(
	handle: Font_Handle,
	cache: ^Shaped_Text,
	text: string,
	max_w: f32 = 0,
	direction: Text_Direction = .LTR,
) -> Vec2 {
	face := font_face_from_handle(handle)
	if face == nil || len(text) == 0 || cache == nil do return {}

	lines := shaped_text_ensure(cache, handle.id, face, text, max_w, direction)
	if len(lines) == 0 do return {}
	return font_measure_lines(face, lines)
}

font_measure_uncached :: proc(
	handle: Font_Handle,
	text: string,
	max_w: f32 = 0,
	direction: Text_Direction = .LTR,
) -> Vec2 {
	face := font_face_from_handle(handle)
	if face == nil || len(text) == 0 do return {}

	lines := font_shape_line_build(face, text, max_w, direction)
	if len(lines) == 0 do return {}
	defer font_destroy_shaped_lines(lines)
	return font_measure_lines(face, lines)
}

snap_logical :: proc(v: f32) -> f32 {
	return math.round(v * 2) / 2
}

font_draw_shaped_line :: proc(
	face: ^Font_Face,
	face_id: Asset_Id,
	line: Shaped_Line,
	pos: Vec2,
	color: Color,
) {
	if face == nil || len(line.glyphs) == 0 do return
	if !font_ensure_glyphs(face, face_id, line.glyphs) do return

	baseline_y := snap_logical(pos.y + face.ascent)
	pen_x := pos.x
	if line.direction == .RTL {
		pen_x = pos.x + line.width
	}

	for glyph in line.glyphs {
		key := Font_Glyph_Key{face_id = face_id, glyph_id = glyph.glyph_id}
		entry, ok := g.fonts.glyph_cache[key]
		if !ok do continue

		glyph_x: f32
		if line.direction == .RTL {
			pen_x -= glyph.x_advance
			glyph_x = pen_x + glyph.x_offset
		} else {
			glyph_x = pen_x + glyph.x_offset
			pen_x += glyph.x_advance
		}

		glyph_y := baseline_y + glyph.y_offset - entry.bearing_y
		dst := Rect {
			x = snap_logical(glyph_x + entry.bearing_x),
			y = snap_logical(glyph_y),
			w = entry.region.w,
			h = entry.region.h,
		}

		draw_atlas_region(entry.region, dst, color)
	}
}

font_draw_shaped_lines :: proc(
	handle: Font_Handle,
	face: ^Font_Face,
	lines: []Shaped_Line,
	pos: Vec2,
	color: Color,
	max_w: f32 = 0,
) -> Vec2 {
	if face == nil || len(lines) == 0 do return {}

	width: f32
	cursor := pos
	for line in lines {
		width = max(width, line.width)
		line_pos := cursor
		if line.direction == .RTL && max_w > 0 {
			line_pos.x = pos.x + max_w - line.width
		}
		font_draw_shaped_line(face, handle.id, line, line_pos, color)
		cursor.y += face.line_height
	}

	return {width, f32(len(lines)) * face.line_height}
}

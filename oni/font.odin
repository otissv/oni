package oni

import "core:c"
import "core:math"
import sdl "vendor:sdl3"

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
		zoom = view_effective_zoom()
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

Ensures the atlas is initialized before packing missing glyphs.
*/
font_ensure_glyphs :: proc(face: ^Font_Face, face_id: Asset_Id, glyphs: []Shaped_Glyph) -> bool {
	if face == nil || len(glyphs) == 0 do return true

	all_cached := true
	for glyph in glyphs {
		key := Font_Glyph_Key {
			face_id  = face_id,
			glyph_id = glyph.glyph_id,
		}
		if key not_in state.fonts.glyph_cache {
			all_cached = false
			break
		}
	}
	if all_cached do return true

	if !texture_atlas_init() do return false

	for glyph in glyphs {
		key := Font_Glyph_Key {
			face_id  = face_id,
			glyph_id = glyph.glyph_id,
		}
		if key in state.fonts.glyph_cache do continue

		entry, ok := font_rasterize_glyph(face, key.glyph_id)
		if !ok do return false
		state.fonts.glyph_cache[key] = entry
	}

	return true
}

/*
Rasterizes a single glyph via FreeType and packs it into the texture atlas.

Applies synthetic embolden when the face instance requests fake bold.
*/
font_rasterize_glyph :: proc(face: ^Font_Face, glyph_id: u32) -> (Font_Glyph_Entry, bool) {
	load_flags: c.int = face.fake_bold ? c.int(FT_LOAD_NO_BITMAP) : c.int(FT_LOAD_RENDER)
	if !ft_ok(Load_Glyph(face.ft_face, c.uint(glyph_id), load_flags)) {
		log_errorf("FT_Load_Glyph failed for glyph %d", glyph_id)
		return {}, false
	}

	slot := ft_glyph_slot(face.ft_face)
	if face.fake_bold {
		GlyphSlot_Embolden(slot)
	}

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

		sdl.WriteSurfacePixel(surface, 0, 0, 0, 0, 0, 0)

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
			region = region,
			bearing_x = f32(ft_slot_bitmap_left(slot)),
			bearing_y = f32(ft_slot_bitmap_top(slot)),
		},
		true
}

/*
Copies a FreeType glyph bitmap into an RGBA SDL surface as white with alpha.

Handles gray, mono, and BGRA pixel modes; logs a warning for unsupported modes.
*/
font_copy_glyph_bitmap :: proc(bitmap: ^FT_Bitmap, surface: ^sdl.Surface) {
	w := int(bitmap.width)
	h := int(bitmap.rows)

	switch bitmap.pixel_mode {
	case FT_PIXEL_MODE_GRAY:
		src := bitmap.buffer
		src_pitch := int(bitmap.pitch)
		for row in 0 ..< h {
			for col in 0 ..< w {
				alpha := src[row * src_pitch + col]
				sdl.WriteSurfacePixel(surface, c.int(col), c.int(row), 255, 255, 255, alpha)
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
				sdl.WriteSurfacePixel(surface, c.int(col), c.int(row), 255, 255, 255, alpha)
			}
		}
	case FT_PIXEL_MODE_BGRA:
		src := bitmap.buffer
		src_pitch := int(bitmap.pitch)
		for row in 0 ..< h {
			for col in 0 ..< w {
				src_off := row * src_pitch + col * 4
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
) -> Vec2 {
	if laid == nil || len(laid.lines) == 0 do return {}

	face := font_face_from_handle(laid.font)
	if face == nil do return {}

	if len(laid.glyphs) > 0 {
		if !font_ensure_glyphs_from_paint(face, laid.font.id, laid.glyphs) do return {}
		for paint in laid.glyphs {
			key := Font_Glyph_Key {
				face_id  = laid.font.id,
				glyph_id = paint.glyph_id,
			}
			entry, ok := state.fonts.glyph_cache[key]
			if !ok do continue
			draw_atlas_region(entry.region, paint.dst, color)
		}
	}

	if decoration_color.a > 0 {
		for stroke in laid.decoration_strokes {
			draw_line(stroke.a, stroke.b, decoration_color, stroke.thickness)
		}
	}

	return laid.size
}

/*
Ensures atlas glyphs exist for precomputed layout glyph paint quads.
*/
font_ensure_glyphs_from_paint :: proc(
	face: ^Font_Face,
	face_id: Asset_Id,
	glyphs: []Layout_Glyph_Paint,
) -> bool {
	if face == nil || len(glyphs) == 0 do return true
	if !texture_atlas_init() do return false

	for paint in glyphs {
		key := Font_Glyph_Key {
			face_id  = face_id,
			glyph_id = paint.glyph_id,
		}
		if key in state.fonts.glyph_cache do continue

		entry, ok := font_rasterize_glyph(face, key.glyph_id)
		if !ok do return false
		state.fonts.glyph_cache[key] = entry
	}

	return true
}

package oni

import "core:c"
import "core:math"
import sdl "vendor:sdl3"

/*
Resolves a family + weight/style + logical size to a raster face instance.

On artboard space, scales by view zoom and returns a layout_scale to map back.
*/
font_resolve :: proc(
	font: Font_Handle,
	logical_size: f32,
	space: Draw_Space,
	weight: Font_Weight = FONT_WEIGHT_NORMAL,
	style: Font_Style = .NORMAL,
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
	req_weight := weight != 0 ? weight : FONT_WEIGHT_NORMAL

	src, fake_bold, fake_italic, match_ok := font_match_source(family, req_weight, style)
	if !match_ok do return {}, 1, false

	resolved, ok = font_find_or_create_instance(
		src,
		raster_size,
		req_weight,
		style,
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
Decoration parameters for drawing text decorations over shaped lines.
*/
Font_Decoration_Draw :: struct {
	lines: Text_Decoration_Lines,
	style: Text_Decoration_Style_Kind,
	color: RGBA,
}

/*
Draws layout-owned shaped text at the node's rect using precomputed line origins.

Does not reshape, wrap, or align — layout owns those.
*/
font_draw_layout_text :: proc(
	laid: ^Layout_Text,
	rect: Rect,
	color: RGBA,
	decoration: Font_Decoration_Draw = {},
) -> Vec2 {
	if laid == nil || len(laid.lines) == 0 do return {}

	face := font_face_from_handle(laid.font)
	if face == nil do return {}

	for line, i in laid.lines {
		origin := laid.line_origins[i]
		pos := Vec2{rect.x + origin.x, rect.y + origin.y}
		font_draw_shaped_line(face, laid.font.id, line, pos, color, laid.layout_scale)
		if decoration.lines != {} {
			font_draw_decoration(face, line, pos, decoration, laid.layout_scale)
		}
	}

	return laid.size
}

/*
Draws one shaped line of text by blitting cached atlas glyphs at the given position.

Handles LTR and RTL pen advancement and applies layout_scale to metrics.
*/
font_draw_shaped_line :: proc(
	face: ^Font_Face,
	face_id: Asset_Id,
	line: Shaped_Line,
	pos: Vec2,
	color: RGBA,
	layout_scale: f32,
) {
	if face == nil || len(line.glyphs) == 0 do return
	if !font_ensure_glyphs(face, face_id, line.glyphs) do return

	baseline_y := snap_logical(pos.y + face.ascent * layout_scale)
	pen_x := pos.x
	if line.direction == .RTL {
		pen_x = pos.x + line.width * layout_scale
	}

	for glyph in line.glyphs {
		key := Font_Glyph_Key {
			face_id  = face_id,
			glyph_id = glyph.glyph_id,
		}
		entry, ok := state.fonts.glyph_cache[key]
		if !ok do continue

		glyph_x: f32
		if line.direction == .RTL {
			pen_x -= glyph.x_advance * layout_scale
			glyph_x = pen_x + glyph.x_offset * layout_scale
		} else {
			glyph_x = pen_x + glyph.x_offset * layout_scale
			pen_x += glyph.x_advance * layout_scale
		}

		glyph_y := baseline_y + glyph.y_offset * layout_scale - entry.bearing_y * layout_scale
		dst := Rect {
			x = snap_logical(glyph_x + entry.bearing_x * layout_scale),
			y = snap_logical(glyph_y),
			w = entry.region.w * layout_scale,
			h = entry.region.h * layout_scale,
		}

		draw_atlas_region(entry.region, dst, color)
	}
}

/*
Draws underline, line-through, and/or overline for one shaped line.
*/
font_draw_decoration :: proc(
	face: ^Font_Face,
	line: Shaped_Line,
	pos: Vec2,
	decoration: Font_Decoration_Draw,
	layout_scale: f32,
) {
	if face == nil || decoration.lines == {} do return

	width := line.width * layout_scale
	if width <= 0 do return

	baseline_y := pos.y + face.ascent * layout_scale
	thickness := max(face.underline_thickness * layout_scale, 1)
	x0 := pos.x
	x1 := pos.x + width

	if .UNDERLINE in decoration.lines {
		y := baseline_y - face.underline_position * layout_scale
		font_draw_decoration_stroke(x0, x1, y, thickness, decoration.style, decoration.color)
	}
	if .LINE_THROUGH in decoration.lines {
		y := baseline_y - (face.ascent * 0.35) * layout_scale
		font_draw_decoration_stroke(x0, x1, y, thickness, decoration.style, decoration.color)
	}
	if .OVERLINE in decoration.lines {
		y := pos.y + thickness * 0.5
		font_draw_decoration_stroke(x0, x1, y, thickness, decoration.style, decoration.color)
	}
}

/*
Draws a single decoration stroke between x0 and x1 at y with the given style.
*/
@(private)
font_draw_decoration_stroke :: proc(
	x0, x1, y, thickness: f32,
	style: Text_Decoration_Style_Kind,
	color: RGBA,
) {
	switch style {
	case .SOLID:
		draw_line({x0, y}, {x1, y}, color, thickness)
	case .DOUBLE:
		gap := thickness * 1.5
		draw_line({x0, y - gap * 0.5}, {x1, y - gap * 0.5}, color, thickness)
		draw_line({x0, y + gap * 0.5}, {x1, y + gap * 0.5}, color, thickness)
	case .DOTTED:
		dot := max(thickness, 1)
		gap := dot
		x := x0
		for x < x1 {
			end := min(x + dot, x1)
			draw_line({x, y}, {end, y}, color, thickness)
			x += dot + gap
		}
	case .DASHED:
		dash := thickness * 3
		gap := thickness * 2
		x := x0
		for x < x1 {
			end := min(x + dash, x1)
			draw_line({x, y}, {end, y}, color, thickness)
			x += dash + gap
		}
	case .WAVY:
		amp := thickness
		period := max(thickness * 2.5, 4)
		x := x0
		prev := Vec2{x0, y}
		up := true
		for x < x1 {
			next_x := min(x + period * 0.5, x1)
			next_y := y + (up ? -amp : amp)
			next := Vec2{next_x, next_y}
			draw_line(prev, next, color, thickness)
			prev = next
			x = next_x
			up = !up
		}
	}
}

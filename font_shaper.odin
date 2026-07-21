package oni

import "core:c"
import "core:hash"
import "core:math"
import "core:mem"
import "core:strings"
import "core:unicode/utf8"

/*
One glyph produced by text shaping with cluster and advance offsets.
*/
Shaped_Glyph :: struct {
	glyph_id:             u32,
	cluster:              u32,
	x_offset, y_offset:   f32,
	x_advance, y_advance: f32,
}

/*
A single line of shaped glyphs with total width and text direction.
*/
Shaped_Line :: struct {
	glyphs:    []Shaped_Glyph,
	width:     f32,
	direction: Text_Direction_Kind,
}

/*
Shaped lines from font_shape_line_build with ownership metadata.

When borrowed is true, lines point into the persistent shape cache and must not
be destroyed by callers. Borrowed slices are invalid after font_shape_cache_clear,
DPI scale changes, or hot reload (faces/cache are cleared on those paths).
*/
Font_Shape_Lines :: struct {
	lines:    []Shaped_Line,
	borrowed: bool,
}

/*
Lookup key for the persistent shaped-text cache.

`wrap_width` and spacing use exact f32 bit patterns so float equality is bit-exact.
*/
Font_Shape_Cache_Key :: struct {
	face_id:             Asset_Id,
	text_hash:           u32,
	text_len:            int,
	letter_spacing_bits: u32,
	word_spacing_bits:   u32,
	tab_size_bits:       u32,
	wrap_mode:           Text_Wrap_Kind,
	wrap_width_bits:     u32,
	direction:           Text_Direction_Kind,
}

/*
Cache-owned shaped lines plus the source text for collision checks.
*/
Font_Shape_Cache_Entry :: struct {
	text:  string,
	lines: []Shaped_Line,
}

/*
Loaded font face pairing FreeType and HarfBuzz handles with metrics.
*/
Font_Face :: struct {
	ft_face:              FT_Face,
	hb_font:              hb_font_t,
	path:                 string,
	size_px:              f32,
	pixel_size:           i32,
	weight:               f32,
	style:                Font_Styles,
	fake_bold:            bool,
	fake_italic:          bool,
	ascent:               f32,
	descent:              f32,
	line_height:          f32,
	underline_position:   f32,
	underline_thickness:  f32,
}

/*
Atlas placement and bearing for one cached glyph raster.
*/
Font_Glyph_Entry :: struct {
	region:    Atlas_Region,
	bearing_x: f32,
	bearing_y: f32,
}

/*
Probed source file belonging to a registered family.
*/
Font_Family_Source :: struct {
	path:      string,
	style:     Font_Styles,
	weight:    f32,
	has_wght:  bool,
	has_opsz:  bool,
	num_axes:  u32,
	wght_axis: i32,
	opsz_axis: i32,
	wght_min:  f32,
	wght_max:  f32,
	wght_def:  f32,
	opsz_min:  f32,
	opsz_max:  f32,
	opsz_def:  f32,
}

/*
Registered font family with one or more source faces.
*/
Font_Family :: struct {
	name:    string,
	sources: [dynamic]Font_Family_Source,
}

/*
Font subsystem: FreeType library, families, face instances, and glyph cache.
*/
Font_State :: struct {
	library:           FT_Library,
	families:          [dynamic]Font_Family,
	faces:             [dynamic]Font_Face,
	glyph_cache:       map[Font_Glyph_Key]Font_Glyph_Entry,
	shape_cache:       map[Font_Shape_Cache_Key]Font_Shape_Cache_Entry,
	shape_cache_dpi:   f32,
}

/*
Cache key identifying a rasterized glyph by face and glyph id.
*/
Font_Glyph_Key :: struct {
	face_id:  Asset_Id,
	glyph_id: u32,
}

/*
Initializes the FreeType library and glyph cache on first use.

Returns false if FT_Init_FreeType fails.
*/
font_init :: proc() -> bool {
	if test_hook_font_init_fail do return false
	if state.fonts.library != nil do return true

	if !ft_ok(Init_FreeType(&state.fonts.library)) {
		log_error("FT_Init_FreeType failed")
		return false
	}

	if state.fonts.glyph_cache == nil {
		state.fonts.glyph_cache = make(map[Font_Glyph_Key]Font_Glyph_Entry)
	}

	return true
}

/*
Shuts down all font resources: faces, families, FreeType, and glyph cache.

Safe to call during engine teardown after drawing has stopped.
*/
font_shutdown :: proc() {
	font_destroy_faces()
	font_destroy_families()
	font_shape_cache_destroy()

	if state.fonts.library != nil {
		Done_FreeType(state.fonts.library)
		state.fonts.library = nil
	}

	for key, _ in state.fonts.glyph_cache {
		delete_key(&state.fonts.glyph_cache, key)
	}
	delete(state.fonts.glyph_cache)
	state.fonts.glyph_cache = nil

	delete(state.fonts.faces)
	state.fonts.faces = nil
	delete(state.fonts.families)
	state.fonts.families = nil
}

/*
Saved family registration used to reload fonts after hot reload or DPI change.
*/
Font_Family_Reload :: struct {
	name:  string,
	faces: [dynamic]Font_Face_Desc,
}

/*
Saves family registrations, clears the atlas, and re-registers every family.

Face instances are discarded; they are recreated on the next font_resolve.
*/
font_reload_faces :: proc() {
	saved := make([dynamic]Font_Family_Reload)
	defer {
		for &entry in saved {
			delete(entry.name)
			for face in entry.faces {
				delete(face.path)
			}
			delete(entry.faces)
		}
		delete(saved)
	}

	for family in state.fonts.families {
		entry := Font_Family_Reload {
			name  = strings.clone(family.name),
			faces = make([dynamic]Font_Face_Desc),
		}
		for src in family.sources {
			append(
				&entry.faces,
				Font_Face_Desc {
					path = strings.clone(src.path),
					style = src.style,
					weight = src.weight,
				},
			)
		}
		append(&saved, entry)
	}

	font_atlas_reset()
	font_destroy_faces()
	font_destroy_families()

	for entry in saved {
		if _, ok := font_register_family(entry.name, entry.faces[:]); !ok {
			log_errorf("font_reload_faces: failed to reload family %q", entry.name)
		}
	}
}

/*
Registers a named font family from one or more source files.

Probes variable axes on each source. Returns a family handle with size_px 0;
use font_with_size for theme body/heading defaults.
*/
font_register_family :: proc(name: string, faces: []Font_Face_Desc) -> (Font_Handle, bool) {
	if !font_init() do return {}, false
	if len(faces) == 0 {
		log_errorf("font_register_family: family %q has no faces", name)
		return {}, false
	}

	family := Font_Family {
		name    = strings.clone(name),
		sources = make([dynamic]Font_Family_Source),
	}

	ok_count := 0
	for desc in faces {
		src, src_ok := font_probe_family_source(desc)
		if !src_ok {
			log_errorf(
				"font_register_family: failed to probe %q for family %q",
				desc.path,
				name,
			)
			continue
		}
		append(&family.sources, src)
		ok_count += 1
	}

	if ok_count == 0 {
		delete(family.name)
		delete(family.sources)
		return {}, false
	}

	append(&state.fonts.families, family)
	return Font_Handle{id = Asset_Id(len(state.fonts.families) - 1), size_px = 0}, true
}

/*
Looks up a registered font family by name.

Matches registered family names case-insensitively. Theme aliases `body` and
`heading` resolve to theme.font_body and theme.font_heading when theme is set.
Returns a family handle with size_px 0; use font_with_size or a font tag size.
*/
font_family_by_name :: proc(name: string) -> (Font_Handle, bool) {
	if len(name) == 0 do return {}, false

	lower := strings.to_lower(name, context.temp_allocator)

	if theme != nil {
		switch lower {
		case "body":
			return theme.font_body, true
		case "heading":
			return theme.font_heading, true
		}
	}

	if !font_init() do return {}, false

	for &family, i in state.fonts.families {
		if strings.to_lower(family.name, context.temp_allocator) == lower {
			return Font_Handle{id = Asset_Id(i), size_px = 0}, true
		}
	}

	return {}, false
}

/*
Returns a family handle with an explicit default logical size.
*/
font_with_size :: proc(font: Font_Handle, size_px: f32) -> Font_Handle {
	return Font_Handle{id = font.id, size_px = size_px}
}

/*
Probes a font file for style/weight metadata and variable axes.
*/
@(private)
font_probe_family_source :: proc(desc: Font_Face_Desc) -> (Font_Family_Source, bool) {
	cpath := strings.clone_to_cstring(desc.path, context.temp_allocator)
	ft_face: FT_Face
	if !ft_ok(New_Face(state.fonts.library, cpath, 0, &ft_face)) {
		return {}, false
	}
	defer Done_Face(ft_face)

	src := Font_Family_Source {
		path      = strings.clone(desc.path),
		style     = font_style_kind(desc.style),
		weight    = font_weight_value(desc.weight),
		wght_axis = -1,
		opsz_axis = -1,
	}

	mm: ^FT_MM_Var
	if ft_ok(Get_MM_Var(ft_face, &mm)) && mm != nil {
		defer Done_MM_Var(state.fonts.library, mm)
		src.num_axes = u32(mm.num_axis)
		for i in 0 ..< int(mm.num_axis) {
			axis := mm.axis[i]
			tag := u32(axis.tag)
			min_v := ft_fixed_to_f32(axis.minimum)
			max_v := ft_fixed_to_f32(axis.maximum)
			def_v := ft_fixed_to_f32(axis.def)
			if tag == FT_TAG_WGHT {
				src.has_wght = true
				src.wght_axis = i32(i)
				src.wght_min = min_v
				src.wght_max = max_v
				src.wght_def = def_v
			} else if tag == FT_TAG_OPSZ {
				src.has_opsz = true
				src.opsz_axis = i32(i)
				src.opsz_min = min_v
				src.opsz_max = max_v
				src.opsz_def = def_v
			}
		}
	}

	return src, true
}

/*
Destroys all registered families and their cloned paths/names.
*/
font_destroy_families :: proc() {
	for &family in state.fonts.families {
		delete(family.name)
		for &src in family.sources {
			delete(src.path)
		}
		delete(family.sources)
	}
	clear(&state.fonts.families)
}

/*
Returns the Font_Family for a handle, or nil when out of range.
*/
font_family_from_handle :: proc(handle: Font_Handle) -> ^Font_Family {
	index := int(handle.id)
	if index < 0 || index >= len(state.fonts.families) do return nil
	return &state.fonts.families[index]
}

/*
Selects the best family source for the requested style and weight.
*/
@(private)
font_match_source :: proc(
	family: ^Font_Family,
	weight: f32,
	style: Font_Styles,
) -> (
	src: ^Font_Family_Source,
	fake_bold: bool,
	fake_italic: bool,
	ok: bool,
) {
	if family == nil || len(family.sources) == 0 do return nil, false, false, false

	want_style := style
	fake_italic = false

	has_style := false
	for &s in family.sources {
		if s.style == want_style {
			has_style = true
			break
		}
	}
	if !has_style && want_style == .ITALIC {
		want_style = .NORMAL
		fake_italic = true
	}

	best_idx := -1
	best_score: f32 = 1e9
	best_has_wght := false

	for &s, i in family.sources {
		if s.style != want_style do continue
		if s.has_wght {
			if !best_has_wght || best_idx < 0 {
				best_idx = i
				best_has_wght = true
				best_score = 0
			}
			continue
		}
		if best_has_wght do continue
		score := abs(s.weight - weight)
		if score < best_score {
			best_score = score
			best_idx = i
		}
	}

	if best_idx < 0 {
		best_idx = 0
		fake_italic = style == .ITALIC && family.sources[0].style != .ITALIC
	}

	src = &family.sources[best_idx]
	fake_bold = !src.has_wght && weight > src.weight + 50
	return src, fake_bold, fake_italic, true
}

/*
Finds or creates a raster face instance for the given source and parameters.
*/
@(private)
font_find_or_create_instance :: proc(
	src: ^Font_Family_Source,
	size_px: f32,
	weight: f32,
	style: Font_Styles,
	fake_bold: bool,
	fake_italic: bool,
) -> (
	Font_Face_Handle,
	bool,
) {
	pixel_size := font_pixel_size(size_px)
	instance_weight := src.has_wght ? weight : src.weight

	for &face, i in state.fonts.faces {
		if face.path == src.path &&
		   face.pixel_size == pixel_size &&
		   face.weight == instance_weight &&
		   face.style == style &&
		   face.fake_bold == fake_bold &&
		   face.fake_italic == fake_italic {
			return Font_Face_Handle{id = Asset_Id(i), size_px = size_px}, true
		}
	}

	return font_create_instance(src, size_px, instance_weight, style, fake_bold, fake_italic)
}

/*
Creates a FreeType/HarfBuzz face instance with optional VF axes and synthesis flags.
*/
@(private)
font_create_instance :: proc(
	src: ^Font_Family_Source,
	size_px: f32,
	weight: f32,
	style: Font_Styles,
	fake_bold: bool,
	fake_italic: bool,
) -> (
	Font_Face_Handle,
	bool,
) {
	cpath := strings.clone_to_cstring(src.path, context.temp_allocator)
	ft_face: FT_Face
	if !ft_ok(New_Face(state.fonts.library, cpath, 0, &ft_face)) {
		log_errorf("FT_New_Face failed for %q", src.path)
		return {}, false
	}

	pixel_size := font_pixel_size(size_px)
	if !ft_ok(Set_Pixel_Sizes(ft_face, c.uint(pixel_size), c.uint(pixel_size))) {
		log_errorf("FT_Set_Pixel_Sizes failed for %q", src.path)
		Done_Face(ft_face)
		return {}, false
	}

	if src.num_axes > 0 && (src.has_wght || src.has_opsz) {
		coords := make([]FT_Fixed, src.num_axes, context.temp_allocator)
		for i in 0 ..< int(src.num_axes) {
			coords[i] = 0
		}
		// Default all axes to 0 first; set known axes explicitly.
		if src.has_wght && src.wght_axis >= 0 {
			w := clamp(weight, src.wght_min, src.wght_max)
			coords[src.wght_axis] = ft_fixed_from_f32(w)
		}
		if src.has_opsz && src.opsz_axis >= 0 {
			opsz := clamp(size_px, src.opsz_min, src.opsz_max)
			coords[src.opsz_axis] = ft_fixed_from_f32(opsz)
		}
		// For axes we did not set, FreeType expects valid coords — re-read defaults.
		mm: ^FT_MM_Var
		if ft_ok(Get_MM_Var(ft_face, &mm)) && mm != nil {
			defer Done_MM_Var(state.fonts.library, mm)
			for i in 0 ..< int(mm.num_axis) {
				if i32(i) == src.wght_axis || i32(i) == src.opsz_axis do continue
				coords[i] = mm.axis[i].def
			}
		}
		if !ft_ok(Set_Var_Design_Coordinates(ft_face, c.uint(src.num_axes), raw_data(coords))) {
			log_errorf("FT_Set_Var_Design_Coordinates failed for %q", src.path)
			Done_Face(ft_face)
			return {}, false
		}
	}

	if fake_italic {
		// ~12° shear (tan(12°) ≈ 0.2126) for CSS-like synthetic italic.
		shear := FT_Matrix {
			xx = 0x10000,
			xy = 13933, // ~tan(12°) in 16.16 fixed
			yx = 0,
			yy = 0x10000,
		}
		Set_Transform(ft_face, &shear, nil)
	} else {
		Set_Transform(ft_face, nil, nil)
	}

	hb_font := ft_font_create_referenced(ft_face)
	if hb_font == nil {
		log_errorf("hb_ft_font_create_referenced failed for %q", src.path)
		Done_Face(ft_face)
		return {}, false
	}
	ft_font_changed(hb_font)

	ascent, descent, line_height := font_metrics_from_face(ft_face)
	underline_position, underline_thickness := font_underline_metrics(ft_face, pixel_size)

	entry := Font_Face {
		ft_face             = ft_face,
		hb_font             = hb_font,
		path                = strings.clone(src.path),
		size_px             = size_px,
		pixel_size          = pixel_size,
		weight              = weight,
		style               = style,
		fake_bold           = fake_bold,
		fake_italic         = fake_italic,
		ascent              = ascent,
		descent             = descent,
		line_height         = line_height,
		underline_position  = underline_position,
		underline_thickness = underline_thickness,
	}

	append(&state.fonts.faces, entry)
	face_id := Asset_Id(len(state.fonts.faces) - 1)
	return Font_Face_Handle{id = face_id, size_px = size_px}, true
}

/*
Reads underline position/thickness in pixels from FreeType face metrics.
*/
@(private)
font_underline_metrics :: proc(ft_face: FT_Face, pixel_size: i32) -> (position, thickness: f32) {
	upem := ft_face_units_per_em(ft_face)
	if upem == 0 {
		thickness = max(f32(pixel_size) / 14, 1)
		position = -f32(pixel_size) * 0.15
		return
	}
	scale := f32(pixel_size) / f32(upem)
	position = f32(ft_face_underline_position(ft_face)) * scale
	thickness = f32(ft_face_underline_thickness(ft_face)) * scale
	if thickness <= 0 {
		thickness = max(f32(pixel_size) / 14, 1)
	}
	if position == 0 {
		position = -f32(pixel_size) * 0.15
	}
	return
}

/*
Destroys all loaded face instances and clears the glyph cache.

Does not shut down the FreeType library or registered families.
*/
font_destroy_faces :: proc() {
	for &face in state.fonts.faces {
		font_destroy_face(&face)
	}
	clear(&state.fonts.faces)

	for key, _ in state.fonts.glyph_cache {
		delete_key(&state.fonts.glyph_cache, key)
	}
	clear(&state.fonts.glyph_cache)
	font_shape_cache_clear()
}

/*
Releases FreeType, HarfBuzz, and path resources for a single face.
*/
font_destroy_face :: proc(face: ^Font_Face) {
	if face == nil do return

	if face.hb_font != nil {
		font_destroy(face.hb_font)
		face.hb_font = nil
	}
	if face.ft_face != nil {
		Done_Face(face.ft_face)
		face.ft_face = nil
	}
	if len(face.path) > 0 {
		delete(face.path)
		face.path = ""
	}
}

/*
Returns the Font_Face pointer for a face handle, or nil when out of range.
*/
font_face_from_handle :: proc(handle: Font_Face_Handle) -> ^Font_Face {
	index := int(handle.id)
	if index < 0 || index >= len(state.fonts.faces) do return nil
	return &state.fonts.faces[index]
}

/*
Converts a logical pixel size to a DPI-scaled integer raster size.

Clamps to at least one pixel.
*/
font_pixel_size :: proc(size_px: f32) -> i32 {
	scale := state.dpi.scale
	if scale <= 0 do scale = 1
	return max(i32(math.round(size_px * scale)), 1)
}

/*
Reads ascent, descent, and line height from a FreeType face in logical pixels.

Falls back to reasonable defaults when size metrics are unavailable.
*/
font_metrics_from_face :: proc(ft_face: FT_Face) -> (ascent, descent, line_height: f32) {
	if metrics := ft_face_size_metrics(ft_face); metrics != nil {
		ascent = f32(metrics.ascender) / 64.0
		descent = f32(-metrics.descender) / 64.0
		line_height = f32(metrics.height) / 64.0
		if line_height <= 0 {
			line_height = ascent + descent
		}
		return
	}

	return 16, 4, 20
}

/*
Shapes a UTF-8 string into positioned glyphs using HarfBuzz.

Returns a newly allocated glyph slice, or nil on failure.
*/
font_shape :: proc(
	face: ^Font_Face,
	text: string,
	direction: Text_Direction_Kind,
) -> []Shaped_Glyph {
	test_hook_font_shape_call_count += 1

	if face == nil || len(text) == 0 do return nil

	buffer := buffer_create()
	if buffer == nil do return nil
	defer buffer_destroy(buffer)

	buffer_reset(buffer)
	buffer_add_utf8(
		buffer,
		strings.clone_to_cstring(text, context.temp_allocator),
		c.int(len(text)),
		0,
		c.int(len(text)),
	)
	buffer_guess_segment_properties(buffer)
	buffer_set_direction(buffer, hb_to_direction(direction))

	if shape(face.hb_font, buffer, nil, 0) == 0 {
		log_error("hb_shape failed")
		return nil
	}

	count := buffer_get_length(buffer)
	if count == 0 do return nil

	glyph_len: c.uint
	infos := buffer_get_glyph_infos(buffer, &glyph_len)
	pos_len: c.uint
	positions := buffer_get_glyph_positions(buffer, &pos_len)
	n := int(min(glyph_len, pos_len))

	glyphs := make([]Shaped_Glyph, n, layout_frame_allocator())
	for i in 0 ..< n {
		glyphs[i] = {
			glyph_id  = u32(infos[i].codepoint),
			cluster   = infos[i].cluster,
			x_offset  = hb_pos_to_px(positions[i].x_offset),
			y_offset  = hb_pos_to_px(positions[i].y_offset),
			x_advance = hb_pos_to_px(positions[i].x_advance),
			y_advance = hb_pos_to_px(positions[i].y_advance),
		}
	}

	return glyphs
}

/*
Returns the concrete text-align kind from a resolved Text_Align value.
*/
text_align_kind :: proc(align: Text_Align) -> Text_Align_Kind {
	#partial switch v in align {
	case Text_Align_Kind:
		return v
	}
	panic("text_align_kind: unresolved Text_Align")
}

/*
Returns the concrete text-wrap kind from a resolved Text_Wrap value.
*/
text_wrap_kind :: proc(wrap: Text_Wrap) -> Text_Wrap_Kind {
	#partial switch v in wrap {
	case Text_Wrap_Kind:
		return v
	}
	panic("text_wrap_kind: unresolved Text_Wrap")
}

/*
Returns the concrete text-direction kind from a resolved Text_Direction value.
*/
text_direction_kind :: proc(direction: Text_Direction) -> Text_Direction_Kind {
	#partial switch v in direction {
	case Text_Direction_Kind:
		return v
	}
	panic("text_direction_kind: unresolved Text_Direction")
}

/*
Returns the concrete decoration lines from a resolved Text_Decoration value.
*/
text_decoration_lines :: proc(decoration: Text_Decoration) -> Text_Decoration_Lines {
	#partial switch v in decoration {
	case Text_Decoration_Lines:
		return v
	}
	panic("text_decoration_lines: unresolved Text_Decoration")
}

/*
Returns the concrete decoration style kind from a resolved Text_Decoration_Style value.
*/
text_decoration_style_kind :: proc(style: Text_Decoration_Style) -> Text_Decoration_Style_Kind {
	#partial switch v in style {
	case Text_Decoration_Style_Kind:
		return v
	}
	panic("text_decoration_style_kind: unresolved Text_Decoration_Style")
}

/*
Copies glyphs into a shaped line and bakes letter-spacing and word-spacing into advances.

Letter-spacing is applied between glyphs (not after the last). Word-spacing is added to
space cluster advances, matching CSS word-spacing.
*/
font_make_shaped_line :: proc(
	text: string,
	glyphs: []Shaped_Glyph,
	direction: Text_Direction_Kind,
	letter_spacing: f32,
	word_spacing: f32,
) -> Shaped_Line {
	line_glyphs := make([]Shaped_Glyph, len(glyphs), layout_frame_allocator())
	copy(line_glyphs, glyphs)

	if letter_spacing != 0 && len(line_glyphs) > 1 {
		for i in 0 ..< len(line_glyphs) - 1 {
			line_glyphs[i].x_advance += letter_spacing
		}
	}

	if word_spacing != 0 {
		for i in 0 ..< len(line_glyphs) {
			if font_is_break_cluster(text, line_glyphs[i].cluster) {
				line_glyphs[i].x_advance += word_spacing
			}
		}
	}

	return Shaped_Line {
		glyphs    = line_glyphs,
		width     = shaped_line_width(line_glyphs),
		direction = direction,
	}
}

/*
Returns the UTF-8 byte range covered by one shaped line in the source string.
*/
font_line_byte_range :: proc(text: string, line: Shaped_Line) -> (start, end: int) {
	if len(line.glyphs) == 0 do return 0, 0

	start = int(line.glyphs[0].cluster)
	end = int(line.glyphs[len(line.glyphs) - 1].cluster)

	for end < len(text) {
		_, w := utf8.decode_rune_in_string(text[end:])

		if w == 0 do break

		end += w
	}

	return start, end
}

/*
Normalizes CRLF and lone CR line endings to LF.
*/
text_normalize_line_endings :: proc(text: string, allocator: mem.Allocator) -> string {
	if len(text) == 0 do return text
	if !strings.contains_rune(text, '\r') do return text

	b := strings.builder_make(allocator)
	for i := 0; i < len(text); {
		switch text[i] {
		case '\r':
			strings.write_byte(&b, '\n')

			if i + 1 < len(text) && text[i + 1] == '\n' {
				i += 2
			} else {
				i += 1
			}
		case '\n':
			strings.write_byte(&b, '\n')
			i += 1
		case:
			_, w := utf8.decode_rune_in_string(text[i:])
			strings.write_string(&b, text[i:i + w])
			i += w
		}
	}

	return strings.to_string(b)
}

/*
Expands tab characters to spaces on a fixed column grid.

`tab_size` is the stop interval in columns; values below one use `DEFAULT_TAB_SIZE`.
*/
text_expand_tabs :: proc(text: string, tab_size: f32, allocator: mem.Allocator) -> string {
	if len(text) == 0 do return text
	if !strings.contains_rune(text, '\t') do return text

	stop := int(tab_size)
	if stop < 1 do stop = DEFAULT_TAB_SIZE

	b := strings.builder_make(allocator)
	column := 0

	for i := 0; i < len(text); {
		switch text[i] {
		case '\n':
			strings.write_byte(&b, '\n')
			column = 0
			i += 1
		case '\t':
			spaces := stop - (column % stop)
			if spaces == 0 do spaces = stop

			for _ in 0 ..< spaces {
				strings.write_byte(&b, ' ')
			}

			column += spaces
			i += 1
		case:
			_, w := utf8.decode_rune_in_string(text[i:])
			strings.write_string(&b, text[i:i + w])
			column += 1
			i += w
		}
	}

	return strings.to_string(b)
}

/*
Prepares author text for preserve shaping: normalize line endings and expand tabs.
*/
text_prepare_preserve :: proc(text: string, tab_size: f32, allocator: mem.Allocator) -> string {
	if len(text) == 0 do return text

	has_cr := strings.contains_rune(text, '\r')
	has_tab := strings.contains_rune(text, '\t')

	if !has_cr && !has_tab do return text

	stop := int(tab_size)
	if stop < 1 do stop = DEFAULT_TAB_SIZE

	b := strings.builder_make(allocator)
	column := 0

	for i := 0; i < len(text); {
		switch text[i] {
		case '\r':
			strings.write_byte(&b, '\n')

			if i + 1 < len(text) && text[i + 1] == '\n' {
				i += 2
			} else {
				i += 1
			}

			column = 0
		case '\n':
			strings.write_byte(&b, '\n')
			i += 1
			column = 0
		case '\t':
			spaces := stop - (column % stop)
			if spaces == 0 do spaces = stop

			for _ in 0 ..< spaces {
				strings.write_byte(&b, ' ')
			}

			column += spaces
			i += 1
		case:
			_, w := utf8.decode_rune_in_string(text[i:])
			strings.write_string(&b, text[i:i + w])
			column += 1
			i += w
		}
	}

	return strings.to_string(b)
}

/*
Shapes text and splits it into lines according to wrap mode, width, and spacing.

NONE: single line (newlines omitted).
NEWLINES: hard breaks only.
PRESERVE: hard breaks with CRLF normalization and tab expansion.
BALANCE: soft-wrap at max_w, then rebalance line lengths.

On cache hit (and after insert on miss), returns a borrow of the persistent cache
entry. Otherwise returns frame-arena or heap-owned lines. Release with
font_shape_lines_release when not borrowing into layout-owned node.text.
*/
font_shape_line_build :: proc(
	face: ^Font_Face,
	face_id: Asset_Id,
	text: string,
	max_w: f32,
	letter_spacing: f32,
	word_spacing: f32,
	tab_size: f32,
	wrap: Text_Wrap_Kind,
	direction: Text_Direction_Kind,
) -> Font_Shape_Lines {
	if face == nil || len(text) == 0 do return {}

	allocator := layout_frame_allocator()
	shape_text := text
	preprocess_heap := false

	if wrap == .PRESERVE {
		prepared := text_prepare_preserve(text, tab_size, allocator)

		if prepared != text {
			shape_text = prepared
			preprocess_heap = !layout_uses_frame_arena()
		}
	} else {
		normalized := text_normalize_line_endings(text, allocator)

		if normalized != text {
			shape_text = normalized
			preprocess_heap = !layout_uses_frame_arena()
		}
	}

	defer if preprocess_heap do delete(shape_text)

	font_shape_cache_ensure_dpi()
	key := font_shape_cache_key(
		face_id,
		shape_text,
		letter_spacing,
		word_spacing,
		tab_size,
		wrap,
		max_w,
		direction,
	)
	if cached, ok := font_shape_cache_lookup(key, shape_text); ok {
		return Font_Shape_Lines{lines = cached, borrowed = true}
	}

	shaped := font_shape(face, shape_text, direction)
	if len(shaped) == 0 do return {}

	result: []Shaped_Line
	switch wrap {
	case .NONE:
		result = font_shape_lines_none(shape_text, shaped, direction, letter_spacing, word_spacing)
	case .NEWLINES, .PRESERVE:
		result = font_shape_lines_newlines(shape_text, shaped, direction, letter_spacing, word_spacing)
	case .BALANCE:
		result = font_shape_lines_balance(
			shape_text,
			shaped,
			max_w,
			direction,
			letter_spacing,
			word_spacing,
		)
	}
	if !layout_uses_frame_arena() {
		delete(shaped)
	}
	if len(result) == 0 do return {}

	font_shape_cache_insert(key, shape_text, result)

	if cached, ok := font_shape_cache_lookup(key, shape_text); ok {
		if !layout_uses_frame_arena() {
			font_destroy_shaped_lines(result)
		}

		return Font_Shape_Lines{lines = cached, borrowed = true}
	}

	return Font_Shape_Lines{lines = result, borrowed = false}
}

/*
Releases shaped lines returned by font_shape_line_build when they are owned locally.

No-op for cache borrows and when the layout frame arena owns the slice.
*/
font_shape_lines_release :: proc(shaped: Font_Shape_Lines) {
	if shaped.borrowed do return
	if layout_uses_frame_arena() do return
	if len(shaped.lines) > 0 {
		font_destroy_shaped_lines(shaped.lines)
	}
}

/*
Shapes one rich-text segment (no wrap) with letter/word spacing via the persistent shape cache.

Returns at most one Shaped_Line keyed by face, substring, direction, and spacing.
Release with font_shape_lines_release when not borrowing into layout-owned storage.
*/
font_shape_segment_build :: proc(
	face: ^Font_Face,
	face_id: Asset_Id,
	text: string,
	letter_spacing: f32,
	word_spacing: f32,
	direction: Text_Direction_Kind,
) -> Font_Shape_Lines {
	return font_shape_line_build(
		face,
		face_id,
		text,
		0,
		letter_spacing,
		word_spacing,
		DEFAULT_TAB_SIZE,
		.NONE,
		direction,
	)
}

/*
Deep-copies shaped lines into the given allocator.
*/
font_clone_shaped_lines :: proc(lines: []Shaped_Line, allocator: mem.Allocator) -> []Shaped_Line {
	if len(lines) == 0 do return nil
	out := make([]Shaped_Line, len(lines), allocator)
	for line, i in lines {
		glyphs := make([]Shaped_Glyph, len(line.glyphs), allocator)
		copy(glyphs, line.glyphs)
		out[i] = {
			glyphs    = glyphs,
			width     = line.width,
			direction = line.direction,
		}
	}
	return out
}

@(private)
font_shape_cache_wrap_max_w :: proc(wrap: Text_Wrap_Kind, max_w: f32) -> f32 {
	#partial switch wrap {
	case .BALANCE:
		return max_w
	}

	return 0
}

@(private)
font_shape_cache_key :: proc(
	face_id: Asset_Id,
	text: string,
	letter_spacing: f32,
	word_spacing: f32,
	tab_size: f32,
	wrap: Text_Wrap_Kind,
	max_w: f32,
	direction: Text_Direction_Kind,
) -> Font_Shape_Cache_Key {
	cache_max_w := font_shape_cache_wrap_max_w(wrap, max_w)

	return Font_Shape_Cache_Key {
		face_id             = face_id,
		text_hash           = hash.crc32(transmute([]u8)text),
		text_len            = len(text),
		letter_spacing_bits = transmute(u32)letter_spacing,
		word_spacing_bits   = transmute(u32)word_spacing,
		tab_size_bits       = transmute(u32)tab_size,
		wrap_mode           = wrap,
		wrap_width_bits     = transmute(u32)cache_max_w,
		direction           = direction,
	}
}

/*
Read-only shape-cache lookup without HarfBuzz or insert.

Returns cached shaped lines when the key and text match. Invalid after
font_shape_cache_clear, DPI scale changes, or hot reload.
*/
font_shape_cache_peek :: proc(
	face_id: Asset_Id,
	text: string,
	letter_spacing: f32,
	word_spacing: f32,
	tab_size: f32,
	wrap: Text_Wrap_Kind,
	max_w: f32,
	direction: Text_Direction_Kind,
) -> (
	[]Shaped_Line,
	bool,
) {
	font_shape_cache_ensure_dpi()
	shape_max_w := font_shape_cache_wrap_max_w(wrap, max_w)
	key := font_shape_cache_key(
		face_id,
		text,
		letter_spacing,
		word_spacing,
		tab_size,
		wrap,
		shape_max_w,
		direction,
	)

	return font_shape_cache_lookup(key, text)
}

@(private)
font_shape_cache_ensure :: proc() {
	if state == nil do return
	if state.fonts.shape_cache == nil {
		state.fonts.shape_cache = make(map[Font_Shape_Cache_Key]Font_Shape_Cache_Entry)
	}
}

/*
Drops all shape-cache entries. Safe under tracking allocator when every insert
cloned its own text and line buffers.
*/
font_shape_cache_clear :: proc() {
	if state == nil || state.fonts.shape_cache == nil do return
	for _, entry in state.fonts.shape_cache {
		delete(entry.text)
		font_destroy_shaped_lines(entry.lines)
	}
	clear(&state.fonts.shape_cache)
	state.fonts.shape_cache_dpi = 0
}

font_shape_cache_destroy :: proc() {
	font_shape_cache_clear()
	if state == nil || state.fonts.shape_cache == nil do return
	delete(state.fonts.shape_cache)
	state.fonts.shape_cache = nil
}

@(private)
font_shape_cache_ensure_dpi :: proc() {
	if state == nil do return
	scale := state.dpi.scale
	if state.fonts.shape_cache != nil && state.fonts.shape_cache_dpi != 0 && state.fonts.shape_cache_dpi != scale {
		font_shape_cache_clear()
	}
	font_shape_cache_ensure()
	state.fonts.shape_cache_dpi = scale
}

@(private)
font_shape_cache_lookup :: proc(
	key: Font_Shape_Cache_Key,
	text: string,
) -> (
	[]Shaped_Line,
	bool,
) {
	if state == nil || state.fonts.shape_cache == nil do return nil, false
	entry, ok := state.fonts.shape_cache[key]
	if !ok do return nil, false
	if entry.text != text do return nil, false
	return entry.lines, true
}

/*
Inserts a general-allocator clone of lines into the shape cache.

`source` may be frame-arena or heap owned; the cache always takes its own copy.
*/
@(private)
font_shape_cache_insert :: proc(key: Font_Shape_Cache_Key, text: string, source: []Shaped_Line) {
	if state == nil || len(source) == 0 do return
	font_shape_cache_ensure()
	if existing, ok := state.fonts.shape_cache[key]; ok {
		delete(existing.text)
		font_destroy_shaped_lines(existing.lines)
		delete_key(&state.fonts.shape_cache, key)
	}
	cloned := font_clone_shaped_lines(source, context.allocator)
	if len(cloned) == 0 do return
	state.fonts.shape_cache[key] = Font_Shape_Cache_Entry {
		text  = strings.clone(text),
		lines = cloned,
	}
}

/*
Builds one line from all glyphs, omitting newline clusters.
*/
@(private)
font_shape_lines_none :: proc(
	text: string,
	shaped: []Shaped_Glyph,
	direction: Text_Direction_Kind,
	letter_spacing: f32,
	word_spacing: f32,
) -> []Shaped_Line {
	kept := make([dynamic]Shaped_Glyph, context.temp_allocator)

	for glyph in shaped {
		if font_is_newline_cluster(text, glyph.cluster) do continue
		append(&kept, glyph)
	}
	if len(kept) == 0 do return nil

	lines := make([]Shaped_Line, 1, layout_frame_allocator())
	lines[0] = font_make_shaped_line(text, kept[:], direction, letter_spacing, word_spacing)

	return lines
}

/*
Builds lines broken only on newline clusters.
*/
@(private)
font_shape_lines_newlines :: proc(
	text: string,
	shaped: []Shaped_Glyph,
	direction: Text_Direction_Kind,
	letter_spacing: f32,
	word_spacing: f32,
) -> []Shaped_Line {
	lines := make([dynamic]Shaped_Line, layout_frame_allocator())
	line_start := 0

	for i in 0 ..< len(shaped) {
		if !font_is_newline_cluster(text, shaped[i].cluster) do continue

		if i > line_start {
			append(
				&lines,
				font_make_shaped_line(text, shaped[line_start:i], direction, letter_spacing, word_spacing),
			)
		}

		line_start = i + 1
	}

	if line_start < len(shaped) {
		append(
			&lines,
			font_make_shaped_line(text, shaped[line_start:], direction, letter_spacing, word_spacing),
		)
	}

	if len(lines) == 0 do return nil

	return lines[:]
}

/*
Soft-wraps at max_w with newline breaks, then balances line lengths when possible.

Trial soft-wraps allocate from the layout frame arena when active so the binary
search does not make/destroy heap repeatedly.
*/
@(private)
font_shape_lines_balance :: proc(
	text: string,
	shaped: []Shaped_Glyph,
	max_w: f32,
	direction: Text_Direction_Kind,
	letter_spacing: f32,
	word_spacing: f32,
) -> []Shaped_Line {
	if max_w <= 0 {
		return font_shape_lines_newlines(text, shaped, direction, letter_spacing, word_spacing)
	}

	lines := font_shape_lines_soft_wrap(text, shaped, max_w, direction, letter_spacing, word_spacing)
	if len(lines) <= 1 do return lines

	target_count := len(lines)
	lo := font_shape_min_wrap_width(text, shaped, letter_spacing)
	hi := max_w
	if lo >= hi do return lines

	arena := layout_uses_frame_arena()
	best := lines
	for _ in 0 ..< 16 {
		mid := (lo + hi) * 0.5
		trial := font_shape_lines_soft_wrap(text, shaped, mid, direction, letter_spacing, word_spacing)
		if len(trial) > target_count {
			if !arena {
				font_destroy_shaped_lines(trial)
			}
			lo = mid
			continue
		}
		if !arena {
			font_destroy_shaped_lines(best)
		}
		best = trial
		hi = mid
	}
	return best
}

/*
Minimum width that can hold the widest unbreakable run (for balance search).
*/
@(private)
font_shape_min_wrap_width :: proc(text: string, shaped: []Shaped_Glyph, letter_spacing: f32) -> f32 {
	min_w: f32
	run_w: f32
	run_glyphs := 0

	for glyph in shaped {
		if font_is_newline_cluster(text, glyph.cluster) || font_is_break_cluster(text, glyph.cluster) {
			if run_glyphs > 0 {
				min_w = max(min_w, run_w)
			}
			run_w = 0
			run_glyphs = 0
			continue
		}
		if run_glyphs > 0 {
			run_w += letter_spacing
		}
		run_w += glyph.x_advance
		run_glyphs += 1
	}
	if run_glyphs > 0 {
		min_w = max(min_w, run_w)
	}
	return min_w
}

/*
Greedy soft-wrap at max_w, honoring newlines and letter-spacing in width checks.
*/
@(private)
font_shape_lines_soft_wrap :: proc(
	text: string,
	shaped: []Shaped_Glyph,
	max_w: f32,
	direction: Text_Direction_Kind,
	letter_spacing: f32,
	word_spacing: f32,
) -> []Shaped_Line {
	lines := make([dynamic]Shaped_Line, layout_frame_allocator())
	line_start := 0
	line_width: f32 = 0
	line_glyphs := 0
	last_break := 0
	i := 0

	for i < len(shaped) {
		glyph := shaped[i]

		if font_is_newline_cluster(text, glyph.cluster) {
			if i > line_start {
				append(
					&lines,
					font_make_shaped_line(
						text,
						shaped[line_start:i],
						direction,
						letter_spacing,
						word_spacing,
					),
				)
			}
			line_start = i + 1
			line_width = 0
			line_glyphs = 0
			last_break = line_start
			i += 1
			continue
		}

		spacing := line_glyphs > 0 ? letter_spacing : 0
		next_width := line_width + spacing + glyph.x_advance

		if i > line_start && next_width > max_w {
			break_at := last_break > line_start ? last_break : i
			if break_at <= line_start {
				break_at = i
			}

			append(
				&lines,
				font_make_shaped_line(
					text,
					shaped[line_start:break_at],
					direction,
					letter_spacing,
					word_spacing,
				),
			)

			line_start = break_at
			line_width = 0
			line_glyphs = 0
			last_break = break_at
			i = break_at
			continue
		}

		line_width = next_width
		line_glyphs += 1
		if font_is_break_cluster(text, glyph.cluster) {
			last_break = i + 1
		}
		i += 1
	}

	if line_start < len(shaped) {
		append(
			&lines,
			font_make_shaped_line(text, shaped[line_start:], direction, letter_spacing, word_spacing),
		)
	}

	if len(lines) == 0 do return nil

	return lines[:]
}

/*
Frees glyph slices for each line and the lines slice itself.
*/
font_destroy_shaped_lines :: proc(lines: []Shaped_Line) {
	for &line in lines {
		delete(line.glyphs)
	}
	delete(lines)
}

/*
Sums x_advance across glyphs to compute the total width of a shaped line.
*/
shaped_line_width :: proc(glyphs: []Shaped_Glyph) -> f32 {
	width: f32
	for glyph in glyphs {
		width += glyph.x_advance
	}
	return width
}

/*
Returns whether the cluster index points to a word-break character (space or tab).
*/
font_is_break_cluster :: proc(text: string, cluster: u32) -> bool {
	if int(cluster) >= len(text) do return false
	b := text[cluster]
	return b == ' ' || b == '\t'
}

/*
Returns whether the cluster index points to a newline character.
*/
font_is_newline_cluster :: proc(text: string, cluster: u32) -> bool {
	if int(cluster) >= len(text) do return false
	return text[cluster] == '\n'
}

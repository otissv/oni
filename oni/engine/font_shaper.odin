package engine

import "core:c"
import "core:hash"
import "core:math"
import "core:strings"

Text_Direction :: enum {
	LTR,
	RTL,
}

Shaped_Glyph :: struct {
	glyph_id:           u32,
	cluster:            u32,
	x_offset, y_offset: f32,
	x_advance, y_advance: f32,
}

Shaped_Line :: struct {
	glyphs:    []Shaped_Glyph,
	width:     f32,
	direction: Text_Direction,
}

Font_Face :: struct {
	ft_face:                FT_Face,
	hb_font:                hb_font_t,
	path:                   string,
	size_px:                f32,
	pixel_size:             i32,
	ascent, descent, line_height: f32,
}

Font_Glyph_Entry :: struct {
	region:    Atlas_Region,
	bearing_x: f32,
	bearing_y: f32,
}

Font_State :: struct {
	library:     FT_Library,
	faces:       [dynamic]Font_Face,
	glyph_cache: map[Font_Glyph_Key]Font_Glyph_Entry,
	shape_pool:  Shaped_Text_Pool,
}

Font_Glyph_Key :: struct {
	face_id:  Asset_Id,
	glyph_id: u32,
}

TEXT_SHAPE_POOL_CAPACITY :: 256

Shaped_Text_Key :: struct {
	face_id:    Asset_Id,
	pixel_size: i32,
	max_w:      f32,
	direction:  Text_Direction,
	text_hash:  u64,
	text_len:   int,
}

INVALID_SHAPE_POOL_SLOT :: -1

Shaped_Text :: struct {
	key:         Shaped_Text_Key,
	text:        string,
	lines:       []Shaped_Line,
	pool_slot:   int,
	last_access: u64,
}

Shaped_Text_Pool :: struct {
	entries:    [TEXT_SHAPE_POOL_CAPACITY]^Shaped_Text,
	count:      int,
	access_seq: u64,
}

font_init :: proc() -> bool {
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

shaped_text_key_make :: proc(
	face_id: Asset_Id,
	face: ^Font_Face,
	text: string,
	max_w: f32,
	direction: Text_Direction,
) -> Shaped_Text_Key {
	return {
		face_id = face_id,
		pixel_size = face.pixel_size,
		max_w = max_w,
		direction = direction,
		text_hash = u64(hash.crc32(transmute([]u8)text)),
		text_len = len(text),
	}
}

shaped_text_key_valid :: proc(cache: ^Shaped_Text, key: Shaped_Text_Key, text: string) -> bool {
	if cache.key != key do return false
	if len(cache.text) != len(text) do return false
	return cache.text == text
}

shaped_text_pool_touch :: proc(cache: ^Shaped_Text) {
	state.fonts.shape_pool.access_seq += 1
	cache.last_access = state.fonts.shape_pool.access_seq
}

shaped_text_pool_unregister :: proc(cache: ^Shaped_Text) {
	if cache.pool_slot == INVALID_SHAPE_POOL_SLOT do return

	slot := cache.pool_slot
	last := state.fonts.shape_pool.count - 1
	if slot != last {
		moved := state.fonts.shape_pool.entries[last]
		state.fonts.shape_pool.entries[slot] = moved
		moved.pool_slot = slot
	}
	state.fonts.shape_pool.count -= 1
	cache.pool_slot = INVALID_SHAPE_POOL_SLOT
}

shaped_text_pool_evict_lru :: proc() {
	if state.fonts.shape_pool.count <= 0 do return

	oldest_slot := 0
	oldest_access := state.fonts.shape_pool.entries[0].last_access
	for i in 1 ..< state.fonts.shape_pool.count {
		entry := state.fonts.shape_pool.entries[i]
		if entry.last_access < oldest_access {
			oldest_access = entry.last_access
			oldest_slot = i
		}
	}

	shaped_text_release(state.fonts.shape_pool.entries[oldest_slot])
}

shaped_text_pool_register :: proc(cache: ^Shaped_Text) {
	if cache.pool_slot != INVALID_SHAPE_POOL_SLOT {
		shaped_text_pool_touch(cache)
		return
	}

	if state.fonts.shape_pool.count >= TEXT_SHAPE_POOL_CAPACITY {
		shaped_text_pool_evict_lru()
	}

	slot := state.fonts.shape_pool.count
	state.fonts.shape_pool.entries[slot] = cache
	cache.pool_slot = slot
	state.fonts.shape_pool.count += 1
	shaped_text_pool_touch(cache)
}

shaped_text_release :: proc(cache: ^Shaped_Text) {
	if cache == nil do return

	shaped_text_pool_unregister(cache)
	font_destroy_shaped_lines(cache.lines)
	cache.lines = nil
	delete(cache.text)
	cache.text = ""
	cache.key = {}
	cache.last_access = 0
}

shaped_text_pool_clear :: proc() {
	for i in 0 ..< state.fonts.shape_pool.count {
		cache := state.fonts.shape_pool.entries[i]
		if cache == nil do continue

		font_destroy_shaped_lines(cache.lines)
		cache.lines = nil
		delete(cache.text)
		cache.text = ""
		cache.key = {}
		cache.pool_slot = INVALID_SHAPE_POOL_SLOT
		cache.last_access = 0
	}
	state.fonts.shape_pool.count = 0
	state.fonts.shape_pool.access_seq = 0
}

// Returns lines owned by cache. Do not free the result.
shaped_text_ensure :: proc(
	cache: ^Shaped_Text,
	face_id: Asset_Id,
	face: ^Font_Face,
	text: string,
	max_w: f32,
	direction: Text_Direction,
) -> []Shaped_Line {
	if cache == nil || face == nil || len(text) == 0 {
		if cache != nil do shaped_text_release(cache)
		return nil
	}
	if !font_init() do return nil

	key := shaped_text_key_make(face_id, face, text, max_w, direction)
	if len(cache.lines) > 0 && shaped_text_key_valid(cache, key, text) {
		shaped_text_pool_touch(cache)
		return cache.lines
	}

	shaped_text_release(cache)

	lines := font_shape_line_build(face, text, max_w, direction)
	if len(lines) == 0 do return nil

	cache.key = key
	cache.text = strings.clone(text)
	cache.lines = lines
	shaped_text_pool_register(cache)
	return cache.lines
}

font_shutdown :: proc() {
	font_destroy_faces()

	if state.fonts.library != nil {
		Done_FreeType(state.fonts.library)
		state.fonts.library = nil
	}

	for key, _ in state.fonts.glyph_cache {
		delete_key(&state.fonts.glyph_cache, key)
	}
	delete(state.fonts.glyph_cache)
	state.fonts.glyph_cache = nil

	shaped_text_pool_clear()

	delete(state.fonts.faces)
	state.fonts.faces = nil
}

Font_Reload_Entry :: struct {
	path:    string,
	size_px: f32,
}

font_reload_faces :: proc() {
	saved := make([dynamic]Font_Reload_Entry)
	defer {
		for entry in saved {
			delete(entry.path)
		}
		delete(saved)
	}

	for face in state.fonts.faces {
		append_elem(&saved, Font_Reload_Entry{strings.clone(face.path), face.size_px})
	}

	font_atlas_reset()
	font_destroy_faces()

	for entry in saved {
		if _, ok := font_load_face(entry.path, entry.size_px); !ok {
			log_errorf("font_reload_faces: failed to reload %q", entry.path)
		}
	}
}

font_load_face :: proc(path: string, size_px: f32) -> (Font_Handle, bool) {
	if !font_init() do return {}, false

	cpath := strings.clone_to_cstring(path, context.temp_allocator)
	ft_face: FT_Face
	if !ft_ok(New_Face(state.fonts.library, cpath, 0, &ft_face)) {
		log_errorf("FT_New_Face failed for %q", path)
		return {}, false
	}

	pixel_size := font_pixel_size(size_px)
	if !ft_ok(Set_Pixel_Sizes(ft_face, c.uint(pixel_size), c.uint(pixel_size))) {
		log_errorf("FT_Set_Pixel_Sizes failed for %q", path)
		Done_Face(ft_face)
		return {}, false
	}

	hb_font := ft_font_create_referenced(ft_face)
	if hb_font == nil {
		log_errorf("hb_ft_font_create_referenced failed for %q", path)
		Done_Face(ft_face)
		return {}, false
	}

	ascent, descent, line_height := font_metrics_from_face(ft_face)

	entry := Font_Face {
		ft_face    = ft_face,
		hb_font    = hb_font,
		path       = strings.clone(path),
		size_px    = size_px,
		pixel_size = pixel_size,
		ascent     = ascent,
		descent    = descent,
		line_height = line_height,
	}

	append(&state.fonts.faces, entry)
	face_id := Asset_Id(len(state.fonts.faces) - 1)

	return Font_Handle{id = face_id, size_px = size_px}, true
}

font_destroy_faces :: proc() {
	for &face in state.fonts.faces {
		font_destroy_face(&face)
	}
	clear(&state.fonts.faces)

	shaped_text_pool_clear()

	for key, _ in state.fonts.glyph_cache {
		delete_key(&state.fonts.glyph_cache, key)
	}
	clear(&state.fonts.glyph_cache)
}

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

font_face_from_handle :: proc(handle: Font_Handle) -> ^Font_Face {
	index := int(handle.id)
	if index < 0 || index >= len(state.fonts.faces) do return nil
	return &state.fonts.faces[index]
}

font_pixel_size :: proc(size_px: f32) -> i32 {
	scale := state.dpi.scale
	if scale <= 0 do scale = 1
	return max(i32(math.round(size_px * scale)), 1)
}

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

font_shape :: proc(face: ^Font_Face, text: string, direction: Text_Direction) -> []Shaped_Glyph {
	if face == nil || len(text) == 0 do return nil

	buffer := buffer_create()
	if buffer == nil do return nil
	defer buffer_destroy(buffer)

	buffer_reset(buffer)
	buffer_add_utf8(buffer, strings.clone_to_cstring(text, context.temp_allocator), c.int(len(text)), 0, c.int(len(text)))
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

	glyphs := make([]Shaped_Glyph, n)
	for i in 0 ..< n {
		glyphs[i] = {
			glyph_id = u32(infos[i].codepoint),
			cluster = infos[i].cluster,
			x_offset = hb_pos_to_px(positions[i].x_offset),
			y_offset = hb_pos_to_px(positions[i].y_offset),
			x_advance = hb_pos_to_px(positions[i].x_advance),
			y_advance = hb_pos_to_px(positions[i].y_advance),
		}
	}

	return glyphs
}

font_shape_line_build :: proc(
	face: ^Font_Face,
	text: string,
	max_w: f32,
	direction: Text_Direction,
) -> []Shaped_Line {
	shaped := font_shape(face, text, direction)
	if len(shaped) == 0 do return nil
	defer delete(shaped)

	if max_w <= 0 {
		line_glyphs := make([]Shaped_Glyph, len(shaped))
		copy(line_glyphs, shaped)
		lines := make([]Shaped_Line, 1)
		lines[0] = Shaped_Line {
			glyphs    = line_glyphs,
			width     = shaped_line_width(line_glyphs),
			direction = direction,
		}
		return lines
	}

	lines := make([dynamic]Shaped_Line)
	line_start := 0
	line_width: f32 = 0
	last_break := 0
	i := 0

	for i < len(shaped) {
		glyph := shaped[i]

		if font_is_newline_cluster(text, glyph.cluster) {
			if i > line_start {
				line_glyphs := make([]Shaped_Glyph, i - line_start)
				copy(line_glyphs, shaped[line_start:i])
				append(
					&lines,
					Shaped_Line {
						glyphs = line_glyphs,
						width = shaped_line_width(line_glyphs),
						direction = direction,
					},
				)
			}
			line_start = i + 1
			line_width = 0
			last_break = line_start
			i += 1
			continue
		}

		next_width := line_width + glyph.x_advance

		if i > line_start && next_width > max_w {
			break_at := last_break > line_start ? last_break : i
			if break_at <= line_start {
				break_at = i
			}

			line_glyphs := make([]Shaped_Glyph, break_at - line_start)
			copy(line_glyphs, shaped[line_start:break_at])
			append(
				&lines,
				Shaped_Line {
					glyphs = line_glyphs,
					width = shaped_line_width(line_glyphs),
					direction = direction,
				},
			)

			line_start = break_at
			line_width = 0
			last_break = break_at
			i = break_at
			continue
		}

		line_width = next_width
		if font_is_break_cluster(text, glyph.cluster) {
			last_break = i + 1
		}
		i += 1
	}

	if line_start < len(shaped) {
		line_glyphs := make([]Shaped_Glyph, len(shaped) - line_start)
		copy(line_glyphs, shaped[line_start:])
		append(
			&lines,
			Shaped_Line {
				glyphs = line_glyphs,
				width = shaped_line_width(line_glyphs),
				direction = direction,
			},
		)
	}

	return lines[:]
}

font_destroy_shaped_lines :: proc(lines: []Shaped_Line) {
	for &line in lines {
		delete(line.glyphs)
	}
	delete(lines)
}

shaped_line_width :: proc(glyphs: []Shaped_Glyph) -> f32 {
	width: f32
	for glyph in glyphs {
		width += glyph.x_advance
	}
	return width
}

font_is_break_cluster :: proc(text: string, cluster: u32) -> bool {
	if int(cluster) >= len(text) do return false
	b := text[cluster]
	return b == ' ' || b == '\t'
}

font_is_newline_cluster :: proc(text: string, cluster: u32) -> bool {
	if int(cluster) >= len(text) do return false
	return text[cluster] == '\n'
}

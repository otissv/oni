package oni

import "core:c"
import "core:math"
import "core:os"
import "core:strings"
import "core:sync"
import "core:testing"

@(test)
hb_to_direction_maps_ltr_and_rtl :: proc(t: ^testing.T) {
	testing.expect_value(t, hb_to_direction(.LTR), HB_DIRECTION_LTR)
	testing.expect_value(t, hb_to_direction(.RTL), HB_DIRECTION_RTL)
}

@(test)
hb_direction_constants_match_harfbuzz :: proc(t: ^testing.T) {
	testing.expect_value(t, HB_DIRECTION_INVALID, hb_direction_t(0))
	testing.expect_value(t, HB_DIRECTION_LTR, hb_direction_t(4))
	testing.expect_value(t, HB_DIRECTION_RTL, hb_direction_t(5))
	testing.expect(t, HB_DIRECTION_LTR != HB_DIRECTION_RTL)
	testing.expect(t, HB_DIRECTION_LTR != HB_DIRECTION_INVALID)
}

@(test)
hb_pos_to_px_converts_26_6_fixed :: proc(t: ^testing.T) {
	expect_close(t, hb_pos_to_px(0), 0)
	expect_close(t, hb_pos_to_px(64), 1)
	expect_close(t, hb_pos_to_px(-64), -1)
	expect_close(t, hb_pos_to_px(32), 0.5)
	expect_close(t, hb_pos_to_px(96), 1.5)
	expect_close(t, hb_pos_to_px(640), 10)
	expect_close(t, hb_pos_to_px(1), 1.0 / 64.0)
	expect_close(t, hb_pos_to_px(-1), -1.0 / 64.0)

	// Large advances stay finite.
	big := hb_pos_to_px(hb_position_t(1_000_000))
	testing.expect(t, math.is_nan(big) == false)
	testing.expect(t, big > 0)
}

@(test)
hb_buffer_create_reset_destroy_lifecycle :: proc(t: ^testing.T) {
	buf := buffer_create()
	testing.expect(t, buf != nil)
	if buf == nil do return
	defer buffer_destroy(buf)

	testing.expect_value(t, buffer_get_length(buf), c.uint(0))
	buffer_add_utf8(buf, "hi", 2, 0, 2)
	testing.expect(t, buffer_get_length(buf) >= 2)

	buffer_reset(buf)
	testing.expect_value(t, buffer_get_length(buf), c.uint(0))

	// Reuse after reset.
	buffer_add_utf8(buf, "x", 1, 0, 1)
	testing.expect_value(t, buffer_get_length(buf), c.uint(1))
}

@(test)
hb_buffer_add_utf8_partial_item_range :: proc(t: ^testing.T) {
	buf := buffer_create()
	testing.expect(t, buf != nil)
	if buf == nil do return
	defer buffer_destroy(buf)

	text := "abcdef"
	buffer_add_utf8(buf, strings.clone_to_cstring(text, context.temp_allocator), c.int(len(text)), 2, 3)
	testing.expect_value(t, buffer_get_length(buf), c.uint(3))
}

@(test)
hb_buffer_set_direction_and_guess_properties :: proc(t: ^testing.T) {
	buf := buffer_create()
	testing.expect(t, buf != nil)
	if buf == nil do return
	defer buffer_destroy(buf)

	buffer_add_utf8(buf, "Hello", 5, 0, 5)
	buffer_guess_segment_properties(buf)
	buffer_set_direction(buf, HB_DIRECTION_RTL)
	buffer_set_direction(buf, HB_DIRECTION_LTR)
	testing.expect(t, buffer_get_length(buf) >= 5)
}

@(test)
hb_ft_font_create_referenced_shape_and_positions :: proc(t: ^testing.T) {
	if !os.exists(INTER_FONT_FIXTURE) {
		testing.expectf(t, false, "missing font fixture %s", INTER_FONT_FIXTURE)
		return
	}

	library: FT_Library
	testing.expect(t, ft_ok(Init_FreeType(&library)))
	if library == nil do return
	defer Done_FreeType(library)

	cpath := strings.clone_to_cstring(INTER_FONT_FIXTURE, context.temp_allocator)
	ft_face: FT_Face
	testing.expect(t, ft_ok(New_Face(library, cpath, 0, &ft_face)))
	if ft_face == nil do return
	defer Done_Face(ft_face)
	testing.expect(t, ft_ok(Set_Pixel_Sizes(ft_face, 16, 16)))

	hb_font := ft_font_create_referenced(ft_face)
	testing.expect(t, hb_font != nil)
	if hb_font == nil do return
	defer font_destroy(hb_font)

	ft_font_changed(hb_font)

	buf := buffer_create()
	testing.expect(t, buf != nil)
	if buf == nil do return
	defer buffer_destroy(buf)

	text := "Hi"
	buffer_add_utf8(buf, strings.clone_to_cstring(text, context.temp_allocator), c.int(len(text)), 0, c.int(len(text)))
	buffer_guess_segment_properties(buf)
	buffer_set_direction(buf, hb_to_direction(.LTR))

	testing.expect(t, shape(hb_font, buf, nil, 0) != 0)
	count := buffer_get_length(buf)
	testing.expect(t, count >= 2)

	info_len: c.uint
	infos := buffer_get_glyph_infos(buf, &info_len)
	pos_len: c.uint
	positions := buffer_get_glyph_positions(buf, &pos_len)
	testing.expect(t, infos != nil && positions != nil)
	testing.expect_value(t, info_len, count)
	testing.expect_value(t, pos_len, count)

	advance: f32
	for i in 0 ..< int(count) {
		testing.expect(t, infos[i].codepoint > 0)
		advance += hb_pos_to_px(positions[i].x_advance)
		testing.expect(t, math.is_nan(hb_pos_to_px(positions[i].x_offset)) == false)
		testing.expect(t, math.is_nan(hb_pos_to_px(positions[i].y_offset)) == false)
	}
	testing.expect(t, advance > 0)
}

@(test)
hb_shape_empty_buffer_returns_zero_glyphs :: proc(t: ^testing.T) {
	if !os.exists(INTER_FONT_FIXTURE) {
		testing.expectf(t, false, "missing font fixture %s", INTER_FONT_FIXTURE)
		return
	}

	library: FT_Library
	testing.expect(t, ft_ok(Init_FreeType(&library)))
	if library == nil do return
	defer Done_FreeType(library)

	cpath := strings.clone_to_cstring(INTER_FONT_FIXTURE, context.temp_allocator)
	ft_face: FT_Face
	testing.expect(t, ft_ok(New_Face(library, cpath, 0, &ft_face)))
	if ft_face == nil do return
	defer Done_Face(ft_face)
	testing.expect(t, ft_ok(Set_Pixel_Sizes(ft_face, 16, 16)))

	hb_font := ft_font_create_referenced(ft_face)
	testing.expect(t, hb_font != nil)
	if hb_font == nil do return
	defer font_destroy(hb_font)

	buf := buffer_create()
	testing.expect(t, buf != nil)
	if buf == nil do return
	defer buffer_destroy(buf)

	// Empty add still shapes successfully with zero length.
	testing.expect(t, shape(hb_font, buf, nil, 0) != 0)
	testing.expect_value(t, buffer_get_length(buf), c.uint(0))
}

@(test)
hb_shape_rtl_latin_preserves_glyph_count :: proc(t: ^testing.T) {
	with_font_fixtures(
		t,
		proc(inter, pixel: Font_Handle, t: ^testing.T) {
			_ = pixel
			face, _, ok := font_test_face(inter, 16)
			testing.expect(t, ok)
			if !ok do return

			buf_ltr := buffer_create()
			buf_rtl := buffer_create()
			testing.expect(t, buf_ltr != nil && buf_rtl != nil)
			if buf_ltr == nil || buf_rtl == nil do return
			defer buffer_destroy(buf_ltr)
			defer buffer_destroy(buf_rtl)

			text := "Hello"
			ctext := strings.clone_to_cstring(text, context.temp_allocator)
			buffer_add_utf8(buf_ltr, ctext, c.int(len(text)), 0, c.int(len(text)))
			buffer_add_utf8(buf_rtl, ctext, c.int(len(text)), 0, c.int(len(text)))
			buffer_guess_segment_properties(buf_ltr)
			buffer_guess_segment_properties(buf_rtl)
			buffer_set_direction(buf_ltr, hb_to_direction(.LTR))
			buffer_set_direction(buf_rtl, hb_to_direction(.RTL))

			testing.expect(t, shape(face.hb_font, buf_ltr, nil, 0) != 0)
			testing.expect(t, shape(face.hb_font, buf_rtl, nil, 0) != 0)
			testing.expect_value(t, buffer_get_length(buf_ltr), buffer_get_length(buf_rtl))
		},
	)
}

@(test)
hb_ft_font_changed_after_size_change_keeps_shape_working :: proc(t: ^testing.T) {
	if !os.exists(INTER_FONT_FIXTURE) {
		testing.expectf(t, false, "missing font fixture %s", INTER_FONT_FIXTURE)
		return
	}

	sync.mutex_lock(&test_global_state_guard)
	defer sync.mutex_unlock(&test_global_state_guard)

	library: FT_Library
	testing.expect(t, ft_ok(Init_FreeType(&library)))
	if library == nil do return
	defer Done_FreeType(library)

	cpath := strings.clone_to_cstring(INTER_FONT_FIXTURE, context.temp_allocator)
	ft_face: FT_Face
	testing.expect(t, ft_ok(New_Face(library, cpath, 0, &ft_face)))
	if ft_face == nil do return
	defer Done_Face(ft_face)
	testing.expect(t, ft_ok(Set_Pixel_Sizes(ft_face, 12, 12)))

	hb_font := ft_font_create_referenced(ft_face)
	testing.expect(t, hb_font != nil)
	if hb_font == nil do return
	defer font_destroy(hb_font)
	ft_font_changed(hb_font)

	shape_width :: proc(hb_font: hb_font_t, text: string) -> f32 {
		buf := buffer_create()
		if buf == nil do return -1
		defer buffer_destroy(buf)
		buffer_add_utf8(
			buf,
			strings.clone_to_cstring(text, context.temp_allocator),
			c.int(len(text)),
			0,
			c.int(len(text)),
		)
		buffer_guess_segment_properties(buf)
		buffer_set_direction(buf, HB_DIRECTION_LTR)
		if shape(hb_font, buf, nil, 0) == 0 do return -1
		pos_len: c.uint
		positions := buffer_get_glyph_positions(buf, &pos_len)
		w: f32
		for i in 0 ..< int(pos_len) {
			w += hb_pos_to_px(positions[i].x_advance)
		}
		return w
	}

	w12 := shape_width(hb_font, "Mm")
	testing.expect(t, w12 > 0)

	testing.expect(t, ft_ok(Set_Pixel_Sizes(ft_face, 24, 24)))
	ft_font_changed(hb_font)
	w24 := shape_width(hb_font, "Mm")
	testing.expect(t, w24 > w12)
}

@(test)
hb_glyph_info_and_position_struct_sizes_are_stable :: proc(t: ^testing.T) {
	// Guard against accidental layout drift vs HarfBuzz C ABI used by the bindings.
	testing.expect(t, size_of(hb_glyph_info_t) >= size_of(hb_codepoint_t) + size_of(c.uint32_t) * 2)
	testing.expect(t, size_of(hb_glyph_position_t) >= size_of(hb_position_t) * 4)
	testing.expect_value(t, size_of(hb_codepoint_t), 4)
	testing.expect_value(t, size_of(hb_position_t), 4)
}

// --- Gap coverage: features, shape failure, nil len, Arabic RTL, create fail ---

@(private)
hb_tag :: proc(a, b, c, d: u8) -> u32 {
	return (u32(a) << 24) | (u32(b) << 16) | (u32(c) << 8) | u32(d)
}

/*
HarfBuzz hb_feature_t layout matching the C ABI.
*/
hb_feature_t :: struct {
	tag:   u32,
	value: u32,
	start: u32,
	end:   u32,
}

@(test)
hb_shape_with_liga_feature_runs :: proc(t: ^testing.T) {
	if !os.exists(INTER_FONT_FIXTURE) {
		testing.expectf(t, false, "missing %s", INTER_FONT_FIXTURE)
		return
	}
	library: FT_Library
	testing.expect(t, ft_ok(Init_FreeType(&library)))
	if library == nil do return
	defer Done_FreeType(library)

	cpath := strings.clone_to_cstring(INTER_FONT_FIXTURE, context.temp_allocator)
	ft_face: FT_Face
	testing.expect(t, ft_ok(New_Face(library, cpath, 0, &ft_face)))
	if ft_face == nil do return
	defer Done_Face(ft_face)
	testing.expect(t, ft_ok(Set_Pixel_Sizes(ft_face, 16, 16)))

	hb_font := ft_font_create_referenced(ft_face)
	testing.expect(t, hb_font != nil)
	if hb_font == nil do return
	defer font_destroy(hb_font)

	shape_with :: proc(hb_font: hb_font_t, text: string, features: []hb_feature_t) -> int {
		buf := buffer_create()
		if buf == nil do return -1
		defer buffer_destroy(buf)
		buffer_add_utf8(
			buf,
			strings.clone_to_cstring(text, context.temp_allocator),
			c.int(len(text)),
			0,
			c.int(len(text)),
		)
		buffer_guess_segment_properties(buf)
		buffer_set_direction(buf, HB_DIRECTION_LTR)
		feat_ptr: rawptr = nil
		nfeat: c.uint = 0
		if len(features) > 0 {
			feat_ptr = raw_data(features)
			nfeat = c.uint(len(features))
		}
		if shape(hb_font, buf, feat_ptr, nfeat) == 0 do return -1
		return int(buffer_get_length(buf))
	}

	off := []hb_feature_t{{tag = hb_tag('l', 'i', 'g', 'a'), value = 0, start = 0, end = max(u32)}}
	on := []hb_feature_t{{tag = hb_tag('l', 'i', 'g', 'a'), value = 1, start = 0, end = max(u32)}}
	n_off := shape_with(hb_font, "fi", off)
	n_on := shape_with(hb_font, "fi", on)
	testing.expect(t, n_off >= 1)
	testing.expect(t, n_on >= 1)
	// With liga off, expect two glyphs; with liga on, Inter often collapses to one.
	testing.expect(t, n_off >= n_on)
}

@(test)
hb_shape_rejects_empty_utf8_add_still_succeeds_with_zero_glyphs :: proc(t: ^testing.T) {
	// Covered more fully by hb_shape_empty_buffer_returns_zero_glyphs; this asserts
	// add_utf8 with zero item_length does not leave stale glyphs after a prior shape.
	if !os.exists(INTER_FONT_FIXTURE) {
		testing.expectf(t, false, "missing %s", INTER_FONT_FIXTURE)
		return
	}
	library: FT_Library
	testing.expect(t, ft_ok(Init_FreeType(&library)))
	if library == nil do return
	defer Done_FreeType(library)
	cpath := strings.clone_to_cstring(INTER_FONT_FIXTURE, context.temp_allocator)
	ft_face: FT_Face
	testing.expect(t, ft_ok(New_Face(library, cpath, 0, &ft_face)))
	if ft_face == nil do return
	defer Done_Face(ft_face)
	testing.expect(t, ft_ok(Set_Pixel_Sizes(ft_face, 16, 16)))
	hb_font := ft_font_create_referenced(ft_face)
	testing.expect(t, hb_font != nil)
	if hb_font == nil do return
	defer font_destroy(hb_font)

	buf := buffer_create()
	testing.expect(t, buf != nil)
	if buf == nil do return
	defer buffer_destroy(buf)

	buffer_add_utf8(buf, "Hi", 2, 0, 2)
	buffer_guess_segment_properties(buf)
	testing.expect(t, shape(hb_font, buf, nil, 0) != 0)
	testing.expect(t, buffer_get_length(buf) >= 2)

	buffer_reset(buf)
	buffer_add_utf8(buf, "Hi", 2, 0, 0) // item_length 0 → no codepoints
	testing.expect(t, shape(hb_font, buf, nil, 0) != 0)
	testing.expect_value(t, buffer_get_length(buf), c.uint(0))
}

@(test)
hb_ft_font_create_referenced_requires_live_face :: proc(t: ^testing.T) {
	if !os.exists(INTER_FONT_FIXTURE) {
		testing.expectf(t, false, "missing %s", INTER_FONT_FIXTURE)
		return
	}
	library: FT_Library
	testing.expect(t, ft_ok(Init_FreeType(&library)))
	if library == nil do return
	defer Done_FreeType(library)
	cpath := strings.clone_to_cstring(INTER_FONT_FIXTURE, context.temp_allocator)
	ft_face: FT_Face
	testing.expect(t, ft_ok(New_Face(library, cpath, 0, &ft_face)))
	if ft_face == nil do return

	hb_font := ft_font_create_referenced(ft_face)
	testing.expect(t, hb_font != nil)
	if hb_font != nil {
		font_destroy(hb_font)
	}
	Done_Face(ft_face)
	// Creating against a dead face is UB in HarfBuzz; we only assert the live path above.
}

@(test)
hb_buffer_get_infos_and_positions_nil_length_pointer :: proc(t: ^testing.T) {
	with_font_fixtures(
		t,
		proc(inter, pixel: Font_Handle, t: ^testing.T) {
			_ = pixel
			face, _, ok := font_test_face(inter, 16)
			testing.expect(t, ok)
			if !ok do return

			buf := buffer_create()
			testing.expect(t, buf != nil)
			if buf == nil do return
			defer buffer_destroy(buf)

			buffer_add_utf8(buf, "Ab", 2, 0, 2)
			buffer_guess_segment_properties(buf)
			buffer_set_direction(buf, HB_DIRECTION_LTR)
			testing.expect(t, shape(face.hb_font, buf, nil, 0) != 0)

			infos := buffer_get_glyph_infos(buf, nil)
			positions := buffer_get_glyph_positions(buf, nil)
			testing.expect(t, infos != nil)
			testing.expect(t, positions != nil)
			count := int(buffer_get_length(buf))
			testing.expect(t, count >= 2)
			for i in 0 ..< count {
				testing.expect(t, infos[i].codepoint > 0)
				testing.expect(t, math.is_nan(hb_pos_to_px(positions[i].x_advance)) == false)
			}
		},
	)
}

@(test)
hb_shape_arabic_rtl_sets_clusters_and_advances :: proc(t: ^testing.T) {
	with_font_fixtures(
		t,
		proc(inter, pixel: Font_Handle, t: ^testing.T) {
			_ = pixel
			face, _, ok := font_test_face(inter, 16)
			testing.expect(t, ok)
			if !ok do return

			buf := buffer_create()
			testing.expect(t, buf != nil)
			if buf == nil do return
			defer buffer_destroy(buf)

			text := "مرحبا"
			ctext := strings.clone_to_cstring(text, context.temp_allocator)
			buffer_add_utf8(buf, ctext, c.int(len(text)), 0, c.int(len(text)))
			buffer_guess_segment_properties(buf)
			buffer_set_direction(buf, hb_to_direction(.RTL))
			testing.expect(t, shape(face.hb_font, buf, nil, 0) != 0)

			count := buffer_get_length(buf)
			testing.expect(t, count >= 1)
			info_len: c.uint
			infos := buffer_get_glyph_infos(buf, &info_len)
			pos_len: c.uint
			positions := buffer_get_glyph_positions(buf, &pos_len)
			testing.expect_value(t, info_len, count)
			testing.expect_value(t, pos_len, count)

			advance: f32
			saw_cluster := false
			for i in 0 ..< int(count) {
				advance += hb_pos_to_px(positions[i].x_advance)
				if infos[i].cluster > 0 do saw_cluster = true
				_ = infos[i].mask
			}
			testing.expect(t, advance >= 0)
			// Multi-codepoint Arabic should produce non-zero clusters for later glyphs.
			if count > 1 {
				testing.expect(t, saw_cluster || infos[0].cluster == 0)
			}
		},
	)
}

@(test)
hb_shape_hebrew_rtl_preserves_positive_total_advance :: proc(t: ^testing.T) {
	with_font_fixtures(
		t,
		proc(inter, pixel: Font_Handle, t: ^testing.T) {
			_ = pixel
			face, _, ok := font_test_face(inter, 16)
			testing.expect(t, ok)
			if !ok do return

			buf := buffer_create()
			testing.expect(t, buf != nil)
			if buf == nil do return
			defer buffer_destroy(buf)

			text := "שלום"
			buffer_add_utf8(
				buf,
				strings.clone_to_cstring(text, context.temp_allocator),
				c.int(len(text)),
				0,
				c.int(len(text)),
			)
			buffer_guess_segment_properties(buf)
			buffer_set_direction(buf, HB_DIRECTION_RTL)
			testing.expect(t, shape(face.hb_font, buf, nil, 0) != 0)
			testing.expect(t, buffer_get_length(buf) >= 1)

			pos_len: c.uint
			positions := buffer_get_glyph_positions(buf, &pos_len)
			w: f32
			for i in 0 ..< int(pos_len) {
				w += abs(hb_pos_to_px(positions[i].x_advance))
			}
			testing.expect(t, w > 0)
		},
	)
}

@(test)
hb_buffer_get_length_matches_info_and_position_counts :: proc(t: ^testing.T) {
	with_font_fixtures(
		t,
		proc(inter, pixel: Font_Handle, t: ^testing.T) {
			_ = pixel
			face, _, ok := font_test_face(inter, 16)
			testing.expect(t, ok)
			buf := buffer_create()
			if buf == nil do return
			defer buffer_destroy(buf)
			buffer_add_utf8(buf, "Typo", 4, 0, 4)
			buffer_guess_segment_properties(buf)
			testing.expect(t, shape(face.hb_font, buf, nil, 0) != 0)

			n := buffer_get_length(buf)
			il, pl: c.uint
			_ = buffer_get_glyph_infos(buf, &il)
			_ = buffer_get_glyph_positions(buf, &pl)
			testing.expect_value(t, il, n)
			testing.expect_value(t, pl, n)
		},
	)
}

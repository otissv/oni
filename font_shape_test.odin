package oni

import "core:math"
import "core:os"
import "core:sync"
import "core:testing"

INTER_FONT_FIXTURE :: "fixtures/fonts/Inter-VariableFont_opsz,wght.ttf"
INTER_ITALIC_FONT_FIXTURE :: "fixtures/fonts/Inter-Italic-VariableFont_opsz,wght.ttf"
PIXEL_FONT_FIXTURE :: "fixtures/fonts/PixelOperator8.ttf"

@(private)
font_fixture_available :: proc() -> bool {
	return os.exists(INTER_FONT_FIXTURE) && os.exists(PIXEL_FONT_FIXTURE)
}

@(private)
with_font_fixtures :: proc(t: ^testing.T, body: proc(inter, pixel: Font_Handle, t: ^testing.T)) {
	if !font_fixture_available() {
		testing.expectf(
			t,
			false,
			"missing font fixtures; expected %s and %s (run from repo root)",
			INTER_FONT_FIXTURE,
			PIXEL_FONT_FIXTURE,
		)
		return
	}

	sync.mutex_lock(&test_global_state_guard)
	defer sync.mutex_unlock(&test_global_state_guard)

	test_state: State
	saved_state := state
	saved_theme := theme
	defer {
		state = saved_state
		widget_ctx_sync()
		theme = saved_theme
	}

	state = &test_state
	widget_ctx_sync()
	theme = nil
	state.dpi = {
		logical_w = 800,
		logical_h = 600,
		scale     = 1,
	}
	state.view = view_default()

	testing.expect(t, font_init())
	defer font_shutdown()

	inter, inter_ok := font_register_family(
		"InterTest",
		{
			{path = INTER_FONT_FIXTURE, style = .NORMAL, weight = .Normal},
			{path = INTER_ITALIC_FONT_FIXTURE, style = .ITALIC, weight = .Normal},
		},
	)
	testing.expect(t, inter_ok)
	inter = font_with_size(inter, 16)

	pixel, pixel_ok := font_register_family(
		"PixelTest",
		{{path = PIXEL_FONT_FIXTURE, style = .NORMAL, weight = .Normal}},
	)
	testing.expect(t, pixel_ok)
	pixel = font_with_size(pixel, 8)

	body(inter, pixel, t)
}

@(private)
font_test_face :: proc(font: Font_Handle, size: f32 = 0) -> (^Font_Face, Font_Face_Handle, bool) {
	logical := size > 0 ? size : font.size_px
	handle, _, ok := font_resolve(font, logical, .SCREEN, .Normal, .NORMAL)
	if !ok do return nil, {}, false
	face := font_face_from_handle(handle)
	return face, handle, face != nil
}

@(test)
font_fixtures_register_and_resolve_inter_and_pixel :: proc(t: ^testing.T) {
	with_font_fixtures(t, proc(inter, pixel: Font_Handle, t: ^testing.T) {
		face, handle, ok := font_test_face(inter, 16)
		testing.expect(t, ok)
		testing.expect(t, face.ft_face != nil)
		testing.expect(t, face.hb_font != nil)
		testing.expect(t, face.ascent > 0)
		testing.expect(t, face.line_height > 0)
		testing.expect(t, handle.size_px == 16 || handle.size_px > 0)

		pface, _, pok := font_test_face(pixel, 8)
		testing.expect(t, pok)
		testing.expect(t, pface.ft_face != nil)

		italic_handle, _, italic_ok := font_resolve(inter, 16, .SCREEN, .Normal, .ITALIC)
		testing.expect(t, italic_ok)
		italic_face := font_face_from_handle(italic_handle)
		testing.expect(t, italic_face != nil)
		testing.expect(t, italic_face.style == .ITALIC || italic_face.fake_italic)
	})
}

@(test)
font_shape_empty_and_basic_ascii :: proc(t: ^testing.T) {
	with_font_fixtures(t, proc(inter, pixel: Font_Handle, t: ^testing.T) {
		_ = pixel
		face, _, ok := font_test_face(inter, 16)
		testing.expect(t, ok)

		testing.expect(t, font_shape(face, "", .LTR) == nil)
		testing.expect(t, font_shape(nil, "x", .LTR) == nil)

		glyphs := font_shape(face, "Hello", .LTR)
		defer delete(glyphs)
		testing.expect(t, len(glyphs) >= 4)
		width: f32
		for g in glyphs {
			testing.expect(t, g.glyph_id != 0 || g.x_advance >= 0)
			width += g.x_advance
		}
		testing.expect(t, width > 0)
	})
}

@(test)
font_shape_is_deterministic_for_same_input :: proc(t: ^testing.T) {
	with_font_fixtures(t, proc(inter, pixel: Font_Handle, t: ^testing.T) {
		_ = pixel
		face, _, ok := font_test_face(inter, 16)
		testing.expect(t, ok)

		a := font_shape(face, "Typography", .LTR)
		b := font_shape(face, "Typography", .LTR)
		defer delete(a)
		defer delete(b)
		testing.expect_value(t, len(a), len(b))
		for i in 0 ..< len(a) {
			testing.expect_value(t, a[i].glyph_id, b[i].glyph_id)
			expect_close(t, a[i].x_advance, b[i].x_advance)
			expect_close(t, a[i].x_offset, b[i].x_offset)
		}
	})
}

@(test)
font_shape_may_apply_standard_ligatures :: proc(t: ^testing.T) {
	with_font_fixtures(
		t,
		proc(inter, pixel: Font_Handle, t: ^testing.T) {
			_ = pixel
			face, _, ok := font_test_face(inter, 16)
			testing.expect(t, ok)

			// Inter enables default liga; "fi" often collapses to one glyph.
			fi := font_shape(face, "fi", .LTR)
			defer delete(fi)
			testing.expect(t, len(fi) >= 1)
			testing.expect(t, len(fi) <= 2)

			ab := font_shape(face, "ab", .LTR)
			defer delete(ab)
			testing.expect_value(t, len(ab), 2)
		},
	)
}

@(test)
font_shape_rtl_latin_does_not_crash_and_keeps_advances :: proc(t: ^testing.T) {
	with_font_fixtures(t, proc(inter, pixel: Font_Handle, t: ^testing.T) {
		_ = pixel
		face, _, ok := font_test_face(inter, 16)
		testing.expect(t, ok)

		ltr := font_shape(face, "Hello", .LTR)
		rtl := font_shape(face, "Hello", .RTL)
		defer delete(ltr)
		defer delete(rtl)
		testing.expect_value(t, len(ltr), len(rtl))
		ltr_w, rtl_w: f32
		for g in ltr do ltr_w += g.x_advance
		for g in rtl do rtl_w += g.x_advance
		testing.expectf(t, abs(ltr_w - rtl_w) < 1e-2, "ltr_w=%v rtl_w=%v", ltr_w, rtl_w)
	})
}

@(test)
font_make_shaped_line_applies_letter_spacing_between_glyphs :: proc(t: ^testing.T) {
	glyphs := []Shaped_Glyph {
		{glyph_id = 1, x_advance = 10},
		{glyph_id = 2, x_advance = 12},
		{glyph_id = 3, x_advance = 8},
	}
	plain := font_make_shaped_line("ABC", glyphs, .LTR, 0, 0)
	defer delete(plain.glyphs)
	spaced := font_make_shaped_line("ABC", glyphs, .LTR, 2, 0)
	defer delete(spaced.glyphs)

	expect_close(t, plain.width, 30)
	expect_close(t, spaced.width, 34) // +2 between first-second and second-third
	expect_close(t, spaced.glyphs[0].x_advance, 12)
	expect_close(t, spaced.glyphs[1].x_advance, 14)
	expect_close(t, spaced.glyphs[2].x_advance, 8)
}

@(test)
font_shape_line_build_none_omits_newlines :: proc(t: ^testing.T) {
	with_font_fixtures(t, proc(inter, pixel: Font_Handle, t: ^testing.T) {
		_ = pixel
		face, handle, ok := font_test_face(inter, 16)
		testing.expect(t, ok)

		shaped := font_shape_line_build(face, handle.id, "one\ntwo", 0, 0, 0, DEFAULT_TAB_SIZE, .NONE, .LTR)
		defer font_shape_lines_release(shaped)
		testing.expect_value(t, len(shaped.lines), 1)
		testing.expect(t, shaped.lines[0].width > 0)
	})
}

@(test)
font_shape_line_build_newlines_hard_breaks :: proc(t: ^testing.T) {
	with_font_fixtures(t, proc(inter, pixel: Font_Handle, t: ^testing.T) {
		_ = pixel
		face, handle, ok := font_test_face(inter, 16)
		testing.expect(t, ok)

		shaped := font_shape_line_build(
			face,
			handle.id,
			"one\ntwo\nthree",
			0,
			0,
			0,
			DEFAULT_TAB_SIZE,
			.NEWLINES,
			.LTR,
		)
		defer font_shape_lines_release(shaped)
		testing.expect_value(t, len(shaped.lines), 3)
		for line in shaped.lines {
			testing.expect(t, line.width > 0)
			testing.expect(t, len(line.glyphs) > 0)
		}
	})
}

@(test)
font_shape_line_build_balance_soft_wraps_under_max_width :: proc(t: ^testing.T) {
	with_font_fixtures(
		t,
		proc(inter, pixel: Font_Handle, t: ^testing.T) {
			_ = pixel
			face, handle, ok := font_test_face(inter, 16)
			testing.expect(t, ok)

			text := "alpha beta gamma delta epsilon zeta eta theta"
			wide := font_shape_line_build(face, handle.id, text, 1000, 0, 0, DEFAULT_TAB_SIZE, .BALANCE, .LTR)
			defer font_shape_lines_release(wide)
			testing.expect_value(t, len(wide.lines), 1)

			narrow := font_shape_line_build(face, handle.id, text, 80, 0, 0, DEFAULT_TAB_SIZE, .BALANCE, .LTR)
			defer font_shape_lines_release(narrow)
			testing.expect(t, len(narrow.lines) >= 2)
			for line in narrow.lines {
				testing.expect(t, line.width > 0)
				// Soft wrap keeps lines under max_w except when a single unbreakable run is wider.
				if line.width > 80 + 1 {
					testing.expect(t, len(line.glyphs) > 0)
				} else {
					testing.expect(t, line.width <= 80 + 1)
				}
			}
		},
	)
}

@(test)
font_shape_line_build_balance_zero_max_w_falls_back_to_newlines :: proc(t: ^testing.T) {
	with_font_fixtures(t, proc(inter, pixel: Font_Handle, t: ^testing.T) {
		_ = pixel
		face, handle, ok := font_test_face(inter, 16)
		testing.expect(t, ok)

		shaped := font_shape_line_build(face, handle.id, "a\nb\nc", 0, 0, 0, DEFAULT_TAB_SIZE, .BALANCE, .LTR)
		defer font_shape_lines_release(shaped)
		testing.expect_value(t, len(shaped.lines), 3)
	})
}

@(test)
font_shape_line_build_letter_spacing_increases_width :: proc(t: ^testing.T) {
	with_font_fixtures(
		t,
		proc(inter, pixel: Font_Handle, t: ^testing.T) {
			_ = pixel
			face, handle, ok := font_test_face(inter, 16)
			testing.expect(t, ok)

			plain := font_shape_line_build(face, handle.id, "ABCD", 0, 0, 0, DEFAULT_TAB_SIZE, .NONE, .LTR)
			spaced := font_shape_line_build(face, handle.id, "ABCD", 0, 2, 0, DEFAULT_TAB_SIZE, .NONE, .LTR)
			defer font_shape_lines_release(plain)
			defer font_shape_lines_release(spaced)
			testing.expect_value(t, len(plain.lines), 1)
			testing.expect_value(t, len(spaced.lines), 1)
			testing.expect(t, spaced.lines[0].width > plain.lines[0].width)
			expect_close(t, spaced.lines[0].width - plain.lines[0].width, 6) // 3 gaps * 2
		},
	)
}

@(test)
font_measure_lines_matches_line_count_and_max_width :: proc(t: ^testing.T) {
	with_font_fixtures(t, proc(inter, pixel: Font_Handle, t: ^testing.T) {
		_ = pixel
		face, handle, ok := font_test_face(inter, 16)
		testing.expect(t, ok)

		shaped := font_shape_line_build(face, handle.id, "hello\nworld", 0, 0, 0, DEFAULT_TAB_SIZE, .NEWLINES, .LTR)
		defer font_shape_lines_release(shaped)
		size := font_measure_lines(face, shaped.lines, 24, 1)
		expect_close(t, size.y, 48)
		max_w := max(shaped.lines[0].width, shaped.lines[1].width)
		expect_close(t, size.x, max_w)
	})
}

@(test)
font_pixel_operator_shapes_ascii_monospacedish :: proc(t: ^testing.T) {
	with_font_fixtures(
		t,
		proc(inter, pixel: Font_Handle, t: ^testing.T) {
			_ = inter
			face, _, ok := font_test_face(pixel, 8)
			testing.expect(t, ok)

			glyphs := font_shape(face, "WWW", .LTR)
			defer delete(glyphs)
			testing.expect_value(t, len(glyphs), 3)
			// PixelOperator is a bitmap/pixel font; advances should be stable and positive.
			expect_close(t, glyphs[0].x_advance, glyphs[1].x_advance)
			expect_close(t, glyphs[1].x_advance, glyphs[2].x_advance)
			testing.expect(t, glyphs[0].x_advance > 0)
		},
	)
}

@(test)
layout_text_build_with_real_inter_fixture :: proc(t: ^testing.T) {
	with_font_fixtures(t, proc(inter, pixel: Font_Handle, t: ^testing.T) {
		_ = pixel
		node := Layout_Node {
			measure = {text = "Layout owns shaping", max_w = 120},
			config = {
				font = inter,
				font_size = 16,
				line_height = 1.5,
				wrap = Text_Wrap_Kind.BALANCE,
				text_direction = Text_Direction_Kind.LTR,
				align = Text_Align_Kind.LEFT,
				space = .SCREEN,
			},
		}
		layout_text_build(&node, 120)
		defer layout_text_release(&node)

		testing.expect(t, len(node.text.lines) >= 1)
		testing.expect(t, node.text.size.x > 0)
		testing.expect(t, node.text.size.y > 0)
		expect_close(t, node.text.wrap_w, 120)
		testing.expect(t, node.text.font.id != Asset_Id(0) || len(state.fonts.faces) > 0)
	})
}

@(test)
layout_finalize_text_node_with_real_font_positions_glyphs_without_gpu :: proc(t: ^testing.T) {
	with_font_fixtures(
		t,
		proc(inter, pixel: Font_Handle, t: ^testing.T) {
			_ = pixel
			node := Layout_Node {
				measure = {text = "Hi"},
				rect = {10, 20, 200, 10},
				config = {
					font = inter,
					font_size = 16,
					line_height = 1.5,
					wrap = Text_Wrap_Kind.NONE,
					text_direction = Text_Direction_Kind.LTR,
					align = Text_Align_Kind.CENTER,
					space = .SCREEN,
					text_decoration = Text_Decoration_Lines{.UNDERLINE},
					text_decoration_style = Text_Decoration_Style_Kind.SOLID,
				},
			}
			layout_text_build(&node, 200)
			defer layout_text_release(&node)
			testing.expect(t, len(node.text.lines) == 1)

			layout_finalize_text_node(&node)
			testing.expect(t, node.rect.h > 10) // auto height from shaped size
			testing.expect(t, len(node.text.line_origins) == 1)
			testing.expect(t, node.text.line_origins[0].x > 0) // centered
			testing.expect(t, len(node.text.glyphs) >= 1)
			testing.expect(t, len(node.text.decoration_strokes) >= 1)
			for paint in node.text.glyphs {
				testing.expect(t, math.is_nan(paint.dst.x) == false)
				testing.expect(t, paint.dst.w >= 0)
			}
		},
	)
}

@(test)
font_resolve_bold_on_variable_inter_uses_weight_axis_or_synthesis :: proc(t: ^testing.T) {
	with_font_fixtures(
		t,
		proc(inter, pixel: Font_Handle, t: ^testing.T) {
			_ = pixel
			normal, _, nok := font_resolve(inter, 16, .SCREEN, .Normal, .NORMAL)
			bold, _, bok := font_resolve(inter, 16, .SCREEN, .Bold, .NORMAL)
			testing.expect(t, nok && bok)

			nface := font_face_from_handle(normal)
			bface := font_face_from_handle(bold)
			testing.expect(t, nface != nil && bface != nil)
			// Variable Inter should prefer a heavier instance weight, not necessarily fake_bold.
			testing.expect(t, bface.weight >= nface.weight || bface.fake_bold)

			ng := font_shape(nface, "Bold", .LTR)
			bg := font_shape(bface, "Bold", .LTR)
			defer delete(ng)
			defer delete(bg)
			testing.expect_value(t, len(ng), len(bg))
		},
	)
}

@(test)
font_shape_unicode_latin_and_cjk_clusters :: proc(t: ^testing.T) {
	with_font_fixtures(t, proc(inter, pixel: Font_Handle, t: ^testing.T) {
		_ = pixel
		face, handle, ok := font_test_face(inter, 16)
		testing.expect(t, ok)

		cafe := font_shape(face, "café", .LTR)
		defer delete(cafe)
		testing.expect(t, len(cafe) >= 4)
		cafe_w: f32
		for g in cafe do cafe_w += g.x_advance
		testing.expect(t, cafe_w > 0)

		cjk := font_shape(face, "日本語", .LTR)
		defer delete(cjk)
		testing.expect(t, len(cjk) >= 1)
		cjk_w: f32
		for g in cjk do cjk_w += g.x_advance
		testing.expect(t, cjk_w > 0)

		mixed := font_shape_line_build(face, handle.id, "Hello 世界\nBonjour", 100, 0, 0, DEFAULT_TAB_SIZE, .BALANCE, .LTR)
		defer font_shape_lines_release(mixed)
		testing.expect(t, len(mixed.lines) >= 2)
	})
}

@(test)
font_is_break_and_newline_cluster_helpers :: proc(t: ^testing.T) {
	testing.expect(t, font_is_break_cluster("a b", 1))
	testing.expect(t, font_is_break_cluster("a\tb", 1))
	testing.expect(t, !font_is_break_cluster("ab", 0))
	testing.expect(t, font_is_newline_cluster("a\nb", 1))
	testing.expect(t, !font_is_newline_cluster("ab", 1))
	testing.expect(t, !font_is_newline_cluster("a", 9))
}

@(test)
text_normalize_line_endings_converts_crlf_and_cr :: proc(t: ^testing.T) {
	got := text_normalize_line_endings("a\r\nb\rc", context.temp_allocator)
	testing.expect_value(t, got, "a\nb\nc")
}

@(test)
text_expand_tabs_uses_column_stops :: proc(t: ^testing.T) {
	got := text_expand_tabs("a\tb", 4, context.temp_allocator)
	testing.expect_value(t, got, "a   b")
	got = text_expand_tabs("\tb", 4, context.temp_allocator)
	testing.expect_value(t, got, "    b")
}

@(test)
font_shape_line_build_preserve_expands_tabs_and_normalizes_crlf :: proc(t: ^testing.T) {
	with_font_fixtures(t, proc(inter, pixel: Font_Handle, t: ^testing.T) {
		_ = pixel
		face, handle, ok := font_test_face(inter, 16)
		testing.expect(t, ok)

		shaped := font_shape_line_build(
			face,
			handle.id,
			"a\tb\r\nc",
			0,
			0,
			0,
			4,
			.PRESERVE,
			.LTR,
		)
		defer font_shape_lines_release(shaped)
		testing.expect_value(t, len(shaped.lines), 2)
		testing.expect(t, shaped.lines[0].width > 0)
		testing.expect(t, shaped.lines[1].width > 0)
	})
}

@(test)
font_make_shaped_line_applies_word_spacing_to_spaces :: proc(t: ^testing.T) {
	glyphs := []Shaped_Glyph {
		{glyph_id = 1, cluster = 0, x_advance = 10},
		{glyph_id = 2, cluster = 1, x_advance = 5},
		{glyph_id = 3, cluster = 2, x_advance = 8},
	}
	plain := font_make_shaped_line("a b c", glyphs, .LTR, 0, 0)
	defer delete(plain.glyphs)
	spaced := font_make_shaped_line("a b c", glyphs, .LTR, 0, 3)
	defer delete(spaced.glyphs)

	expect_close(t, plain.width, 23)
	expect_close(t, spaced.width, 26)
	expect_close(t, spaced.glyphs[1].x_advance, 8)
}

@(test)
font_shape_line_build_cache_hit_is_borrowed :: proc(t: ^testing.T) {
	with_font_fixtures(t, proc(inter, pixel: Font_Handle, t: ^testing.T) {
		_ = pixel
		face, handle, ok := font_test_face(inter, 16)
		testing.expect(t, ok)

		first := font_shape_line_build(
			face,
			handle.id,
			"Static label",
			0,
			0,
			0,
			DEFAULT_TAB_SIZE,
			.NONE,
			.LTR,
		)
		defer font_shape_lines_release(first)
		testing.expect(t, first.borrowed)
		testing.expect_value(t, len(first.lines), 1)

		second := font_shape_line_build(
			face,
			handle.id,
			"Static label",
			0,
			0,
			0,
			DEFAULT_TAB_SIZE,
			.NONE,
			.LTR,
		)
		defer font_shape_lines_release(second)
		testing.expect(t, second.borrowed)
		testing.expect(t, raw_data(second.lines) == raw_data(first.lines))
	})
}

@(test)
layout_text_build_borrows_cached_shape_lines :: proc(t: ^testing.T) {
	with_font_fixtures(t, proc(inter, pixel: Font_Handle, t: ^testing.T) {
		_ = pixel
		node := Layout_Node {
			measure = {text = "Borrowed cache lines"},
			config = {
				font = inter,
				font_size = 16,
				line_height = 1.5,
				wrap = Text_Wrap_Kind.NONE,
				text_direction = Text_Direction_Kind.LTR,
				align = Text_Align_Kind.LEFT,
				space = .SCREEN,
			},
		}

		layout_text_build(&node, 0)
		testing.expect(t, node.text.lines_borrowed)
		first_ptr := raw_data(node.text.lines)
		layout_text_release(&node)

		layout_text_build(&node, 0)
		defer layout_text_release(&node)
		testing.expect(t, node.text.lines_borrowed)
		testing.expect(t, raw_data(node.text.lines) == first_ptr)
	})
}

@(test)
font_shape_segment_build_cache_hit_is_borrowed :: proc(t: ^testing.T) {
	with_font_fixtures(t, proc(inter, pixel: Font_Handle, t: ^testing.T) {
		_ = pixel
		face, handle, ok := font_test_face(inter, 16)
		testing.expect(t, ok)

		first := font_shape_segment_build(face, handle.id, "Bold span", 0, 0, .LTR)
		defer font_shape_lines_release(first)
		testing.expect(t, first.borrowed)
		testing.expect_value(t, len(first.lines), 1)
		testing.expect(t, len(first.lines[0].glyphs) > 0)

		second := font_shape_segment_build(face, handle.id, "Bold span", 0, 0, .LTR)
		defer font_shape_lines_release(second)
		testing.expect(t, second.borrowed)
		testing.expect(t, raw_data(second.lines) == raw_data(first.lines))
	})
}

@(test)
font_shape_segment_build_matches_uncached_shaped_line :: proc(t: ^testing.T) {
	with_font_fixtures(t, proc(inter, pixel: Font_Handle, t: ^testing.T) {
		_ = pixel
		face, handle, ok := font_test_face(inter, 16)
		testing.expect(t, ok)

		text := "Segment"
		letter_spacing: f32 = 1.5
		word_spacing: f32 = 2

		cached := font_shape_segment_build(face, handle.id, text, letter_spacing, word_spacing, .LTR)
		defer font_shape_lines_release(cached)
		testing.expect_value(t, len(cached.lines), 1)

		raw := font_shape(face, text, .LTR)
		defer delete(raw)
		uncached := font_make_shaped_line(text, raw, .LTR, letter_spacing, word_spacing)
		defer delete(uncached.glyphs)

		expect_close(t, cached.lines[0].width, uncached.width)
		testing.expect_value(t, len(cached.lines[0].glyphs), len(uncached.glyphs))
		for i in 0 ..< len(uncached.glyphs) {
			testing.expect_value(t, cached.lines[0].glyphs[i].glyph_id, uncached.glyphs[i].glyph_id)
			expect_close(t, cached.lines[0].glyphs[i].x_advance, uncached.glyphs[i].x_advance)
		}
	})
}

@(test)
font_shape_segment_build_letter_spacing_uses_separate_cache_entries :: proc(t: ^testing.T) {
	with_font_fixtures(t, proc(inter, pixel: Font_Handle, t: ^testing.T) {
		_ = pixel
		face, handle, ok := font_test_face(inter, 16)
		testing.expect(t, ok)

		plain := font_shape_segment_build(face, handle.id, "AB", 0, 0, .LTR)
		defer font_shape_lines_release(plain)
		spaced := font_shape_segment_build(face, handle.id, "AB", 2, 0, .LTR)
		defer font_shape_lines_release(spaced)

		testing.expect(t, plain.borrowed)
		testing.expect(t, spaced.borrowed)
		testing.expect(t, spaced.lines[0].width > plain.lines[0].width)
	})
}

@(test)
font_shape_segment_build_different_faces_do_not_share_cache :: proc(t: ^testing.T) {
	with_font_fixtures(t, proc(inter, pixel: Font_Handle, t: ^testing.T) {
		iface, ihandle, iok := font_test_face(inter, 16)
		pface, phandle, pok := font_test_face(pixel, 8)
		testing.expect(t, iok && pok)

		text := "Aa"
		inter_seg := font_shape_segment_build(iface, ihandle.id, text, 0, 0, .LTR)
		defer font_shape_lines_release(inter_seg)
		pixel_seg := font_shape_segment_build(pface, phandle.id, text, 0, 0, .LTR)
		defer font_shape_lines_release(pixel_seg)

		testing.expect(t, inter_seg.borrowed)
		testing.expect(t, pixel_seg.borrowed)
		testing.expect(t, raw_data(inter_seg.lines) != raw_data(pixel_seg.lines))
	})
}

package oni

import "core:math"
import "core:testing"

@(private)
layout_test_stub_font :: proc() -> Font_Face_Handle {
	if state.fonts.glyph_cache == nil {
		state.fonts.glyph_cache = make(map[Font_Glyph_Key]Font_Glyph_Entry)
	}
	append(
		&state.fonts.faces,
		Font_Face {
			ascent = 10,
			descent = 2,
			line_height = 12,
			underline_position = 1,
			underline_thickness = 1,
			size_px = 16,
		},
	)
	return {id = Asset_Id(len(state.fonts.faces) - 1), size_px = 16}
}

@(private)
layout_test_seed_glyph :: proc(face_id: Asset_Id, glyph_id: u32, w: f32 = 8, h: f32 = 10) {
	state.fonts.glyph_cache[{face_id = face_id, glyph_id = glyph_id}] = Font_Glyph_Entry {
		region = {texture_id = face_id, w = w, h = h},
		bearing_x = 0,
		bearing_y = 8,
	}
}

@(private)
layout_test_make_line :: proc(
	glyph_ids: []u32,
	advances: []f32,
	direction: Text_Direction_Kind = .LTR,
) -> Shaped_Line {
	glyphs := make([]Shaped_Glyph, len(glyph_ids), layout_frame_allocator())
	width: f32
	for id, i in glyph_ids {
		adv := i < len(advances) ? advances[i] : 8
		glyphs[i] = {glyph_id = id, x_advance = adv}
		width += adv
	}
	return {glyphs = glyphs, width = width, direction = direction}
}

@(private)
layout_test_make_lines :: proc(lines: []Shaped_Line) -> []Shaped_Line {
	out := make([]Shaped_Line, len(lines), layout_frame_allocator())
	for line, i in lines {
		out[i] = line
	}
	return out
}

@(private)
layout_test_clear_stub_fonts :: proc() {
	delete(state.fonts.faces)
	delete(state.fonts.glyph_cache)
	state.fonts.faces = nil
	state.fonts.glyph_cache = nil
}

@(private)
layout_test_register_inter_font :: proc() -> (inter: Font_Handle, ok: bool) {
	inter, ok = font_register_family(
		"LayoutEdgeTest",
		{{path = INTER_FONT_FIXTURE, style = .NORMAL, weight = .Normal}},
	)
	if !ok do return inter, false

	return font_with_size(inter, 16), true
}

@(private)
layout_test_glyph_ids :: proc(face: ^Font_Face, text: string) -> (first, second: u32, ok: bool) {
	shaped := font_shape(face, text, .LTR)
	if len(shaped) < 2 do return 0, 0, false

	return shaped[0].glyph_id, shaped[1].glyph_id, true
}

@(private)
layout_test_attach_stub_text :: proc(
	node: ^Layout_Node,
	font: Font_Face_Handle,
	lines: []Shaped_Line,
	wrap_w: f32,
	font_size: f32 = 16,
	line_height_mult: f32 = 1.5,
	align: Text_Align_Kind = .LEFT,
) {
	node.measure.text = "stub"
	node.config.align = align
	node.config.font_size = font_size
	node.config.line_height = line_height_mult
	node.config.text_direction = Text_Direction_Kind.LTR
	node.config.wrap = Text_Wrap_Kind.NONE
	lh := font_size * line_height_mult
	face := font_face_from_handle(font)
	size := font_measure_lines(face, lines, lh, 1)
	node.text = {
		lines        = lines,
		font         = font,
		layout_scale = 1,
		wrap_w       = wrap_w,
		line_height  = lh,
		size         = size,
	}
}

// --- text layout ---

@(test)
layout_text_resolve_wrap_w_priority :: proc(t: ^testing.T) {
	node := Layout_Node {
		measure = {max_w = 120},
		config = {width = {kind = .FIXED, value = 200}, max_w = 180},
	}
	expect_close(t, layout_text_resolve_wrap_w(&node, 300), 120)

	node.measure.max_w = 0
	expect_close(t, layout_text_resolve_wrap_w(&node, 300), 200)

	node.config.width = {}
	expect_close(t, layout_text_resolve_wrap_w(&node, 300), 180)

	node.config.max_w = 0
	expect_close(t, layout_text_resolve_wrap_w(&node, 300), 300)
}

@(test)
layout_node_has_text_and_release_are_safe :: proc(t: ^testing.T) {
	testing.expect(t, !layout_node_has_text(nil))
	empty := Layout_Node{}
	testing.expect(t, !layout_node_has_text(&empty))
	empty.measure.text = "x"
	testing.expect(t, layout_node_has_text(&empty))
	layout_text_release(nil)
	layout_text_release(&empty)
}

@(test)
layout_text_append_decoration_stroke_styles :: proc(t: ^testing.T) {
	strokes: [dynamic]Layout_Decoration_Stroke
	defer delete(strokes)

	white := RGBA{255, 255, 255, 255}
	layout_text_append_decoration_stroke(&strokes, 0, 40, 10, 2, .SOLID, white)
	testing.expect_value(t, len(strokes), 1)

	clear(&strokes)
	layout_text_append_decoration_stroke(&strokes, 0, 40, 10, 2, .DOUBLE, white)
	testing.expect_value(t, len(strokes), 2)

	clear(&strokes)
	layout_text_append_decoration_stroke(&strokes, 0, 20, 10, 2, .DOTTED, white)
	testing.expect(t, len(strokes) >= 2)

	clear(&strokes)
	layout_text_append_decoration_stroke(&strokes, 0, 30, 10, 2, .DASHED, white)
	testing.expect(t, len(strokes) >= 2)

	clear(&strokes)
	layout_text_append_decoration_stroke(&strokes, 0, 20, 10, 2, .WAVY, white)
	testing.expect(t, len(strokes) >= 2)
}

@(test)
layout_text_position_lines_aligns_left_center_right :: proc(t: ^testing.T) {
	with_layout_solve(
		t,
		proc(layout: ^Layout_State, t: ^testing.T) {
			_ = layout
			font := layout_test_stub_font()
			defer layout_test_clear_stub_fonts()

			line := layout_test_make_line({1, 2}, {10, 10})
			lines := layout_test_make_lines({line})
			node := Layout_Node {
				rect = {0, 0, 100, 40},
			}
			layout_test_attach_stub_text(&node, font, lines, 100, align = .LEFT)
			layout_text_position_lines(&node)
			expect_close(t, node.text.line_origins[0].x, 0)
			layout_text_release(&node)

			line = layout_test_make_line({1, 2}, {10, 10})
			lines = layout_test_make_lines({line})
			layout_test_attach_stub_text(&node, font, lines, 100, align = .CENTER)
			layout_text_position_lines(&node)
			expect_close(t, node.text.line_origins[0].x, 40)
			layout_text_release(&node)

			line = layout_test_make_line({1, 2}, {10, 10})
			lines = layout_test_make_lines({line})
			layout_test_attach_stub_text(&node, font, lines, 100, align = .RIGHT)
			layout_text_position_lines(&node)
			expect_close(t, node.text.line_origins[0].x, 80)
			layout_text_release(&node)
		},
	)
}

@(test)
layout_text_position_lines_stacks_multiple_lines :: proc(t: ^testing.T) {
	with_layout_solve(
		t,
		proc(layout: ^Layout_State, t: ^testing.T) {
			_ = layout
			font := layout_test_stub_font()
			defer layout_test_clear_stub_fonts()

			l0 := layout_test_make_line({1}, {8})
			l1 := layout_test_make_line({2}, {8})
			lines := layout_test_make_lines({l0, l1})
			node := Layout_Node {
				rect = {5, 5, 80, 60},
			}
			layout_test_attach_stub_text(&node, font, lines, 80, font_size = 16, line_height_mult = 1.5)
			layout_text_position_lines(&node)
			testing.expect_value(t, len(node.text.line_origins), 2)
			expect_close(t, node.text.line_origins[0].y, 0)
			expect_close(t, node.text.line_origins[1].y, 24)
			layout_text_release(&node)
		},
	)
}

@(test)
layout_text_position_glyphs_ltr_and_rtl :: proc(t: ^testing.T) {
	if !font_fixture_available() do return

	with_layout_solve(
		t,
		proc(layout: ^Layout_State, t: ^testing.T) {
			_ = layout
			testing.expect(t, font_init())
			defer font_shutdown()

			inter, inter_ok := layout_test_register_inter_font()
			testing.expect(t, inter_ok)

			face, font, face_ok := font_test_face(inter, 16)
			testing.expect(t, face_ok)

			gid_a, gid_b, ids_ok := layout_test_glyph_ids(face, "AB")
			testing.expect(t, ids_ok)

			ltr := layout_test_make_line({gid_a, gid_b}, {10, 12}, .LTR)
			lines := layout_test_make_lines({ltr})
			node := Layout_Node {
				rect = {10, 20, 100, 40},
			}
			layout_test_attach_stub_text(&node, font, lines, 100)
			layout_text_position_lines(&node)
			layout_text_position_glyphs(&node)
			testing.expect_value(t, len(node.text.glyphs), 2)
			testing.expect(t, node.text.glyphs[0].dst.x < node.text.glyphs[1].dst.x)
			layout_text_release(&node)

			rtl := layout_test_make_line({gid_a, gid_b}, {10, 12}, .RTL)
			lines = layout_test_make_lines({rtl})
			layout_test_attach_stub_text(&node, font, lines, 100)
			layout_text_position_lines(&node)
			layout_text_position_glyphs(&node)
			testing.expect_value(t, len(node.text.glyphs), 2)
			// RTL places first logical glyph toward the right edge of the line box.
			testing.expect(t, node.text.glyphs[0].dst.x > node.text.glyphs[1].dst.x)
			layout_text_release(&node)
		},
	)
}

@(test)
layout_text_position_glyphs_matches_rasterized_dst :: proc(t: ^testing.T) {
	with_font_gpu_fixtures(
		t,
		proc(inter, pixel: Font_Handle, t: ^testing.T) {
			_ = pixel
			state.ui.layout = layout_test_begin()
			defer layout_test_end(&state.ui.layout)

			face, font, face_ok := font_test_face(inter, 16)
			testing.expect(t, face_ok)

			shaped := font_shape(face, "Hi", .LTR)
			testing.expect(t, len(shaped) >= 2)

			line := font_make_shaped_line("Hi", shaped, .LTR, 0, 0)
			lines := layout_test_make_lines({line})
			node := Layout_Node {
				rect = {10, 20, 200, 40},
			}
			layout_test_attach_stub_text(&node, font, lines, 200)
			layout_text_position_lines(&node)

			cache_before := len(state.fonts.glyph_cache)
			layout_text_position_glyphs(&node)
			testing.expect_value(t, len(state.fonts.glyph_cache), cache_before)

			testing.expect(t, font_ensure_glyphs(face, font.id, shaped))
			baseline_y := snap_logical(node.rect.y + node.text.line_origins[0].y + face.ascent)
			pen_x := node.rect.x + node.text.line_origins[0].x

			for glyph, i in shaped {
				expected, expected_ok := font_test_glyph_paint_from_cache(
					face,
					font.id,
					glyph,
					pen_x,
					baseline_y,
					1,
				)
				testing.expect(t, expected_ok)
				pen_x += glyph.x_advance

				expect_close(t, node.text.glyphs[i].dst.x, expected.dst.x, 1.5)
				expect_close(t, node.text.glyphs[i].dst.y, expected.dst.y, 1.5)
				expect_close(t, node.text.glyphs[i].dst.w, expected.dst.w, 1.5)
				expect_close(t, node.text.glyphs[i].dst.h, expected.dst.h, 1.5)
			}

			layout_text_release(&node)
		},
	)
}

@(test)
layout_text_position_decorations_emits_underline_strike_overline :: proc(t: ^testing.T) {
	with_layout_solve(
		t,
		proc(layout: ^Layout_State, t: ^testing.T) {
			_ = layout
			font := layout_test_stub_font()
			defer layout_test_clear_stub_fonts()

			line := layout_test_make_line({1}, {40})
			lines := layout_test_make_lines({line})
			node := Layout_Node {
				rect = {0, 0, 100, 40},
				config = {
					text_decoration = Text_Decoration_Lines{.UNDERLINE, .LINE_THROUGH, .OVERLINE},
					text_decoration_style = Text_Decoration_Style_Kind.SOLID,
				},
			}
			layout_test_attach_stub_text(&node, font, lines, 100)
			layout_text_position_lines(&node)
			layout_text_position_decorations(&node)
			testing.expect_value(t, len(node.text.decoration_strokes), 3)
			layout_text_release(&node)
		},
	)
}

@(test)
layout_text_auto_height_and_paint_from_shaped_text :: proc(t: ^testing.T) {
	if !font_fixture_available() do return

	with_layout_solve(
		t,
		proc(layout: ^Layout_State, t: ^testing.T) {
			_ = layout
			testing.expect(t, font_init())
			defer font_shutdown()

			inter, inter_ok := layout_test_register_inter_font()
			testing.expect(t, inter_ok)

			face, font, face_ok := font_test_face(inter, 16)
			testing.expect(t, face_ok)

			gid, _, ids_ok := layout_test_glyph_ids(face, "AA")
			testing.expect(t, ids_ok)

			l0 := layout_test_make_line({gid}, {20})
			l1 := layout_test_make_line({gid}, {20})
			lines := layout_test_make_lines({l0, l1})
			node := Layout_Node {
				rect = {0, 0, 100, 10},
				config = {
					text_decoration = Text_Decoration_Lines{.UNDERLINE},
					text_decoration_style = Text_Decoration_Style_Kind.SOLID,
					height = {}, // auto
					min_h = 0,
					max_h = 0,
				},
			}
			layout_test_attach_stub_text(&node, font, lines, 100, font_size = 16, line_height_mult = 1.5)

			if !length_is_definite(node.config.height) && node.text.size.y > 0 {
				node.rect.h = layout_clamp_axis(node.text.size.y, node.config.min_h, node.config.max_h)
			}

			layout_text_position_lines(&node)
			layout_text_position_glyphs(&node)
			layout_text_position_decorations(&node)

			expect_close(t, node.rect.h, 48) // 2 * 24
			testing.expect(t, len(node.text.line_origins) == 2)
			testing.expect(t, len(node.text.glyphs) == 2)
			testing.expect(t, len(node.text.decoration_strokes) >= 1)
			layout_text_release(&node)
		},
	)
}

@(test)
layout_text_build_noop_without_font_subsystem :: proc(t: ^testing.T) {
	with_layout_solve(
		t,
		proc(layout: ^Layout_State, t: ^testing.T) {
			_ = layout
			node := Layout_Node {
				measure = {text = "hello"},
				config = {font_size = 16, line_height = 1.5, wrap = Text_Wrap_Kind.NONE, text_direction = Text_Direction_Kind.LTR},
			}
			layout_text_build(&node, 100)
			// No registered faces => build exits without lines.
			testing.expect_value(t, len(node.text.lines), 0)
		},
	)
}

@(test)
layout_text_result_returns_nil_for_missing_id :: proc(t: ^testing.T) {
	with_layout_solve(
		t,
		proc(layout: ^Layout_State, t: ^testing.T) {
			_ = layout
			testing.expect(t, layout_text_result(UI_Id(999)) == nil)
		},
	)
}

// --- push / pop tree API ---

@(test)
layout_push_pop_builds_parent_child_and_measures :: proc(t: ^testing.T) {
	with_layout_solve(
		t,
		proc(layout: ^Layout_State, t: ^testing.T) {
			state.dpi = {logical_w = 400, logical_h = 300, scale = 1}
			layout_begin_space(.SCREEN)

			parent := layout_push_node(
				UI_Id(1),
				{kind = .RECT, direction = .HORIZONTAL, gap_x = 10, width = layout_len_fixed(200), height = layout_len_fixed(100)},
			)
			_ = parent
			a := layout_push_node(UI_Id(2), {kind = .RECT})
			layout_set_measure_size(a, {40, 20})
			layout_pop_node()
			b := layout_push_node(UI_Id(3), {kind = .RECT})
			layout_set_measure_size(b, {50, 20})
			layout_pop_node()
			layout_pop_node()

			layout_end_space()

			testing.expect_value(t, len(layout.nodes), 3)
			testing.expect_value(t, len(layout.nodes[0].child_indices), 2)
			expect_close(t, layout.nodes[1].desired.x, 40)
			expect_close(t, layout.nodes[2].desired.x, 50)
			expect_close(t, layout.nodes[0].desired.x, 200)
			expect_rect(t, layout.nodes[1].rect, {0, 0, 40, 20})
			expect_rect(t, layout.nodes[2].rect, {50, 0, 50, 20})
		},
	)
}

@(test)
layout_push_pop_nested_column_inside_row :: proc(t: ^testing.T) {
	with_layout_solve(
		t,
		proc(layout: ^Layout_State, t: ^testing.T) {
			state.dpi = {logical_w = 400, logical_h = 300, scale = 1}
			layout_begin_space(.SCREEN)

			_ = layout_push_node(
				UI_Id(10),
				{kind = .RECT, direction = .HORIZONTAL, width = layout_len_fixed(300), height = layout_len_fixed(200)},
			)
			_ = layout_push_node(
				UI_Id(11),
				{kind = .RECT, direction = .VERTICAL, width = layout_len_fixed(100), height = layout_len_fixed(200)},
			)
			c1 := layout_push_node(UI_Id(12), {kind = .RECT})
			layout_set_measure_size(c1, {80, 30})
			layout_pop_node()
			c2 := layout_push_node(UI_Id(13), {kind = .RECT})
			layout_set_measure_size(c2, {80, 40})
			layout_pop_node()
			layout_pop_node()
			side := layout_push_node(UI_Id(14), {kind = .RECT})
			layout_set_measure_size(side, {60, 20})
			layout_pop_node()
			layout_pop_node()

			layout_end_space()

			expect_rect(t, layout.nodes[2].rect, {0, 0, 80, 30})
			expect_rect(t, layout.nodes[3].rect, {0, 30, 80, 40})
			expect_rect(t, layout.nodes[4].rect, {100, 0, 60, 20})
		},
	)
}

@(test)
layout_push_pop_empty_stack_is_safe :: proc(t: ^testing.T) {
	with_layout_solve(
		t,
		proc(layout: ^Layout_State, t: ^testing.T) {
			_ = layout
			layout_pop_node()
			testing.expect_value(t, len(state.ui.layout.node_stack), 0)
		},
	)
}

@(test)
layout_push_pop_id_map_roundtrip :: proc(t: ^testing.T) {
	with_layout_solve(
		t,
		proc(layout: ^Layout_State, t: ^testing.T) {
			node := layout_push_node(UI_Id(42), {kind = .BUTTON, width = layout_len_fixed(10), height = layout_len_fixed(10)})
			layout_set_measure_size(node, {10, 10})
			layout_pop_node()

			idx, ok := layout.id_to_node[UI_Id(42)]
			testing.expect(t, ok)
			testing.expect(t, layout.nodes[idx].kind == .BUTTON)
			testing.expect(t, layout_text_result(UI_Id(42)) == nil)
			testing.expect(t, layout_image_result(UI_Id(42)) == nil)
		},
	)
}

@(test)
layout_set_measure_text_and_size_update_node :: proc(t: ^testing.T) {
	with_layout_solve(
		t,
		proc(layout: ^Layout_State, t: ^testing.T) {
			node := layout_push_node(UI_Id(7), {kind = .TEXT})
			layout_set_measure_text(node, "hello", 80)
			layout_set_measure_size(node, {1, 1})
			testing.expect_value(t, node.measure.text, "hello")
			expect_close(t, node.measure.max_w, 80)
			expect_close(t, node.desired.x, 1)
			// Avoid layout_pop_node: text measure needs a style stack / font.
			ordered_remove(&layout.node_stack, len(layout.node_stack) - 1)
		},
	)
}

// --- edge fuzz ---

@(test)
layout_nan_sizes_do_not_crash_solve :: proc(t: ^testing.T) {
	with_layout_solve(
		t,
		proc(layout: ^Layout_State, t: ^testing.T) {
			nan := math.nan_f32()
			root := layout_test_append_node(
				layout,
				-1,
				.RECT,
				{},
				{nan, nan},
				{direction = .HORIZONTAL, width = layout_len_fixed(200), height = layout_len_fixed(100)},
			)
			a := layout_test_append_node(layout, root, .RECT, {}, {nan, 20})
			b := layout_test_append_node(layout, root, .RECT, {}, {40, nan})

			layout_solve(&layout.nodes[root], {0, 0, 200, 100})

			testing.expect(t, layout.nodes[root].rect.w == 200 || math.is_nan(layout.nodes[root].rect.w))
			_ = a
			_ = b
			// Primary contract: solve completes without trapping.
			testing.expect(t, true)
		},
	)
}

@(test)
layout_inf_and_negative_desired_sizes_are_clamped_or_tolerated :: proc(t: ^testing.T) {
	with_layout_solve(
		t,
		proc(layout: ^Layout_State, t: ^testing.T) {
			root := layout_test_append_node(
				layout,
				-1,
				.RECT,
				{},
				{200, 100},
				{direction = .HORIZONTAL, min_w = 50, max_w = 150, min_h = 10, max_h = 80},
			)
			_ = layout_test_append_node(layout, root, .RECT, {}, {-20, 1000})
			layout_solve(&layout.nodes[root], {0, 0, 400, 400})
			expect_close(t, layout.nodes[root].rect.w, 150)
			expect_close(t, layout.nodes[root].rect.h, 80)
		},
	)
}

@(test)
layout_huge_sibling_row_solves_without_crash :: proc(t: ^testing.T) {
	with_layout_solve(
		t,
		proc(layout: ^Layout_State, t: ^testing.T) {
			root := layout_test_append_node(
				layout,
				-1,
				.RECT,
				{},
				{4000, 40},
				{direction = .HORIZONTAL, width = layout_len_fixed(4000), height = layout_len_fixed(40), gap_x = 1},
			)
			N :: 500
			for i in 0 ..< N {
				_ = layout_test_append_node(layout, root, .RECT, {}, {4, 20})
				_ = i
			}
			layout_solve(&layout.nodes[root], {0, 0, 4000, 40})
			testing.expect_value(t, len(layout.nodes[root].child_indices), N)
			expect_close(t, layout.nodes[1].rect.x, 0)
			expect_close(t, layout.nodes[2].rect.x, 5)
			last := layout.nodes[root].child_indices[N - 1]
			testing.expect(t, layout.nodes[last].rect.x >= 0)
		},
	)
}

@(test)
layout_deep_nested_columns_solves_without_crash :: proc(t: ^testing.T) {
	with_layout_solve(
		t,
		proc(layout: ^Layout_State, t: ^testing.T) {
			DEPTH :: 64
			parent := layout_test_append_node(
				layout,
				-1,
				.RECT,
				{},
				{100, 100},
				{direction = .VERTICAL, width = layout_len_fixed(100), height = layout_len_fixed(100)},
			)
			for i in 0 ..< DEPTH {
				parent = layout_test_append_node(
					layout,
					parent,
					.RECT,
					{},
					{100, 100},
					{direction = .VERTICAL, width = layout_len_fixed(100), height = layout_len_fixed(100)},
				)
				_ = i
			}
			leaf := layout_test_append_node(layout, parent, .RECT, {}, {40, 20})
			layout_solve(&layout.nodes[0], {0, 0, 100, 100})
			expect_rect_inside(t, layout.nodes[0].rect, layout.nodes[leaf].rect)
		},
	)
}

@(test)
layout_wrap_reverse_space_between_combo :: proc(t: ^testing.T) {
	with_layout_solve(
		t,
		proc(layout: ^Layout_State, t: ^testing.T) {
			root := layout_test_append_node(
				layout,
				-1,
				.RECT,
				{x = .SPACE_BETWEEN, y = .CENTER},
				{120, 120},
				{
					direction = .HORIZONTAL_WRAP_REVERSE,
					width = layout_len_fixed(120),
					height = layout_len_fixed(120),
					gap_x = 8,
					gap_y = 6,
				},
			)
			a := layout_test_append_node(layout, root, .RECT, {}, {50, 20})
			b := layout_test_append_node(layout, root, .RECT, {}, {50, 20})
			c := layout_test_append_node(layout, root, .RECT, {}, {50, 20})

			layout_solve(&layout.nodes[root], {0, 0, 120, 120})

			expect_rect_inside(t, layout.nodes[root].rect, layout.nodes[a].rect)
			expect_rect_inside(t, layout.nodes[root].rect, layout.nodes[b].rect)
			expect_rect_inside(t, layout.nodes[root].rect, layout.nodes[c].rect)
			// wrap-reverse mirrors main axis within a line
			testing.expect(t, layout.nodes[a].rect.x != layout.nodes[b].rect.x || layout.nodes[a].rect.y != layout.nodes[c].rect.y)
		},
	)
}

@(test)
layout_vertical_wrap_reverse_space_around_combo :: proc(t: ^testing.T) {
	with_layout_solve(
		t,
		proc(layout: ^Layout_State, t: ^testing.T) {
			root := layout_test_append_node(
				layout,
				-1,
				.RECT,
				{y = .SPACE_AROUND, x = .END},
				{120, 120},
				{
					direction = .VERTICAL_WRAP_REVERSE,
					width = layout_len_fixed(120),
					height = layout_len_fixed(120),
					gap_x = 4,
					gap_y = 8,
				},
			)
			for _ in 0 ..< 5 {
				_ = layout_test_append_node(layout, root, .RECT, {}, {20, 40})
			}
			layout_solve(&layout.nodes[root], {0, 0, 120, 120})
			for child_index in layout.nodes[root].child_indices {
				expect_rect_inside(t, layout.nodes[root].rect, layout.nodes[child_index].rect)
			}
		},
	)
}

@(test)
layout_reverse_space_evenly_with_flex_children :: proc(t: ^testing.T) {
	with_layout_solve(
		t,
		proc(layout: ^Layout_State, t: ^testing.T) {
			root := layout_test_append_node(
				layout,
				-1,
				.RECT,
				{x = .SPACE_EVENLY},
				{300, 80},
				{direction = .HORIZONTAL_REVERSE, width = layout_len_fixed(300), height = layout_len_fixed(80)},
			)
			a := layout_test_append_node(layout, root, .RECT, {}, {20, 20}, {flex = 1})
			b := layout_test_append_node(layout, root, .RECT, {}, {20, 20}, {flex = 1})
			c := layout_test_append_node(layout, root, .RECT, {}, {40, 20}, {width = layout_len_fixed(40)})

			layout_solve(&layout.nodes[root], {0, 0, 300, 80})
			expect_rect_inside(t, layout.nodes[root].rect, layout.nodes[a].rect)
			expect_rect_inside(t, layout.nodes[root].rect, layout.nodes[b].rect)
			expect_rect_inside(t, layout.nodes[root].rect, layout.nodes[c].rect)
			testing.expect(t, layout.nodes[a].rect.w > 0)
			testing.expect(t, layout.nodes[b].rect.w > 0)
		},
	)
}

@(test)
layout_wrap_space_between_and_self_out_of_flow_combo :: proc(t: ^testing.T) {
	with_layout_solve(
		t,
		proc(layout: ^Layout_State, t: ^testing.T) {
			root := layout_test_append_node(
				layout,
				-1,
				.RECT,
				{x = .SPACE_BETWEEN},
				{200, 100},
				{
					direction = .HORIZONTAL_WRAP,
					width = layout_len_fixed(200),
					height = layout_len_fixed(100),
					gap_x = 10,
					gap_y = 5,
				},
			)
			a := layout_test_append_node(layout, root, .RECT, {}, {60, 20})
			overlay := layout_test_append_node(layout, root, .RECT, {}, {30, 20}, {self = {x = .END}})
			b := layout_test_append_node(layout, root, .RECT, {}, {60, 20})
			c := layout_test_append_node(layout, root, .RECT, {}, {60, 20})

			layout_solve(&layout.nodes[root], {0, 0, 200, 100})
			expect_rect_inside(t, layout.nodes[root].rect, layout.nodes[a].rect)
			expect_rect_inside(t, layout.nodes[root].rect, layout.nodes[b].rect)
			expect_rect_inside(t, layout.nodes[root].rect, layout.nodes[c].rect)
			expect_rect_inside(t, layout.nodes[root].rect, layout.nodes[overlay].rect)
			expect_close(t, layout.nodes[overlay].rect.x, 170)
		},
	)
}

@(test)
layout_zero_bounds_and_empty_wrap_are_stable :: proc(t: ^testing.T) {
	with_layout_solve(
		t,
		proc(layout: ^Layout_State, t: ^testing.T) {
			root := layout_test_append_node(
				layout,
				-1,
				.RECT,
				{},
				{},
				{direction = .HORIZONTAL_WRAP, width = layout_len_fixed(0), height = layout_len_fixed(0)},
			)
			_ = layout_test_append_node(layout, root, .RECT, {}, {10, 10})
			layout_solve(&layout.nodes[root], {0, 0, 0, 0})
			expect_close(t, layout.nodes[root].rect.w, 0)
			expect_close(t, layout.nodes[root].rect.h, 0)
		},
	)
}

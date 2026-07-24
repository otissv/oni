package oni

import "core:testing"

@(test)
scroll_bar_thumb_geometry_scales_with_viewport :: proc(t: ^testing.T) {
	thumb_len, thumb_pos := scroll_bar_thumb_geometry(100, 50, 200, 0, SCROLL_BAR_MIN_THUMB)
	expect_close(t, thumb_len, 25)
	expect_close(t, thumb_pos, 0)

	_, thumb_pos = scroll_bar_thumb_geometry(100, 50, 200, 150, SCROLL_BAR_MIN_THUMB)
	expect_close(t, thumb_pos, 75)
}

@(test)
scroll_clamp_and_wheel_update_offsets :: proc(t: ^testing.T) {
	sx, sy: f32
	ov_scroll: Overflow = .SCROLL
	changed := scroll_apply_wheel(&sx, &sy, {0, 200}, 0, -1, ov_scroll, ov_scroll)
	testing.expect(t, changed)
	expect_close(t, sy, SCROLL_WHEEL_SCALE)

	changed = scroll_apply_wheel(&sx, &sy, {0, 200}, 0, -10, ov_scroll, ov_scroll)
	testing.expect(t, changed)
	expect_close(t, sy, 200)
}

@(test)
layout_scrollport_offsets_content_children :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			ui_begin_frame()
			ui_push_style(style_root(.SCREEN, {0, 0, 800, 600}))
			defer ui_pop_style()

			layout_begin_space(.SCREEN)
			ov_scroll: Overflow = .SCROLL
			parent := layout_push_node(
				UI_Id(1),
				{
					kind = .RECT,
					width = layout_len_fixed(100),
					height = layout_len_fixed(100),
					overflow_x = ov_scroll,
					overflow_y = ov_scroll,
					scroll_y = 40,
				},
			)
			_ = parent
			child := layout_push_node(
				UI_Id(2),
				{kind = .RECT, width = layout_len_fixed(80), height = layout_len_fixed(200)},
			)
			layout_set_measure_size(child, {80, 200})
			layout_pop_node()
			layout_pop_node()
			layout_end_space()

			child_i := state.ui.layout.id_to_node[UI_Id(2)]
			parent_i := state.ui.layout.id_to_node[UI_Id(1)]
			p := &state.ui.layout.nodes[parent_i]
			c := &state.ui.layout.nodes[child_i]

			expect_close(t, p.max_scroll.y, 100)
			expect_close(t, p.scroll.y, 40)
			expect_close(t, c.rect.y, p.rect.y + p.padding.t + p.border.t - 40)
		},
	)
}

@(test)
layout_scrollport_skips_scrollbar_children :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			ui_begin_frame()
			ui_push_style(style_root(.SCREEN, {0, 0, 800, 600}))
			defer ui_pop_style()

			layout_begin_space(.SCREEN)
			ov_scroll: Overflow = .SCROLL
			parent := layout_push_node(
				UI_Id(10),
				{
					kind = .RECT,
					width = layout_len_fixed(100),
					height = layout_len_fixed(100),
					overflow_y = ov_scroll,
					scroll_y = 25,
				},
			)
			_ = parent
			content := layout_push_node(
				UI_Id(11),
				{kind = .RECT, width = layout_len_fixed(80), height = layout_len_fixed(180)},
			)
			layout_set_measure_size(content, {80, 180})
			layout_pop_node()

			bar := layout_push_node(
				UI_Id(12),
				{
					kind = .SCROLL_BAR,
					position = .ABSOLUTE,
					width = layout_len_fixed(12),
					height = layout_len_fixed(100),
					right = 0,
					right_set = true,
					y = 0,
					y_set = true,
				},
			)
			layout_set_measure_size(bar, {12, 100})
			layout_pop_node()
			layout_pop_node()
			layout_end_space()

			content_i := state.ui.layout.id_to_node[UI_Id(11)]
			bar_i := state.ui.layout.id_to_node[UI_Id(12)]
			parent_i := state.ui.layout.id_to_node[UI_Id(10)]
			p := &state.ui.layout.nodes[parent_i]
			c := &state.ui.layout.nodes[content_i]
			b := &state.ui.layout.nodes[bar_i]

			expect_close(t, c.rect.y, p.rect.y + p.padding.t + p.border.t - 25)
			expect_close(t, b.rect.y, p.rect.y + p.padding.t + p.border.t)
		},
	)
}

@(test)
layout_scrollport_offsets_text_leaf_content :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			ov_scroll: Overflow = .SCROLL
			glyphs := make([]Layout_Glyph_Paint, 1)
			defer delete(glyphs)
			glyphs[0] = {face_id = Asset_Id(0), glyph_id = 1, dst = {4, 24, 8, 12}}
			origins := make([]Vec2, 1)
			defer delete(origins)
			origins[0] = {4, 24}
			edit_glyphs := make([]Text_Edit_Glyph, 1)
			defer delete(edit_glyphs)
			edit_glyphs[0] = {cluster = 0, x0 = 14, x1 = 22, line_index = 0}

			append(
				&state.ui.layout.nodes,
				Layout_Node {
					ui_id = UI_Id(20),
					kind = .TEXT_INPUT,
					config = {
						width = layout_len_fixed(100),
						height = layout_len_fixed(40),
						overflow_y = ov_scroll,
						scroll_y = 20,
					},
					rect = {0, 0, 100, 40},
					measure = {text = "line one\nline two\nline three"},
					text = {
						size = {80, 120},
						glyphs = glyphs,
						line_origins = origins,
						edit_geometry = {
							plain = "a",
							line_origins = origins,
							line_height = 16,
							glyphs = edit_glyphs,
						},
					},
				},
			)

			node := &state.ui.layout.nodes[0]
			content := layout_inner_rect(node.rect, node.border, node.padding)
			layout_finalize_scrollport(node, content)

			expect_close(t, node.max_scroll.y, 80)
			expect_close(t, node.scroll.y, 20)
			expect_close(t, node.text.glyphs[0].dst.y, 4)
			expect_close(t, node.text.edit_geometry.glyphs[0].x0, 14)
			expect_close(t, node.text.edit_geometry.glyphs[0].x1, 22)
			expect_close(t, node.text.line_origins[0].y, 4)

			node.text.glyphs = nil
			node.text.line_origins = nil
			node.text.edit_geometry = {}
		},
	)
}

@(test)
layout_apply_scroll_delta_offsets_text_paint_geometry :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			glyphs := make([]Layout_Glyph_Paint, 1)
			defer delete(glyphs)
			glyphs[0] = {face_id = Asset_Id(0), glyph_id = 1, dst = {4, 24, 8, 12}}
			origins := make([]Vec2, 1)
			defer delete(origins)
			origins[0] = {4, 24}
			edit_glyphs := make([]Text_Edit_Glyph, 1)
			defer delete(edit_glyphs)
			edit_glyphs[0] = {cluster = 0, x0 = 10, x1 = 18, line_index = 0}

			append(
				&state.ui.layout.nodes,
				Layout_Node {
					ui_id = UI_Id(21),
					kind = .TEXT_INPUT,
					rect = {0, 0, 100, 40},
					text = {
						size = {80, 120},
						glyphs = glyphs,
						line_origins = origins,
						edit_geometry = {
							plain = "a",
							line_origins = origins,
							line_height = 16,
							glyphs = edit_glyphs,
						},
					},
				},
			)
			state.ui.layout.id_to_node[UI_Id(21)] = 0

			changed := layout_apply_scroll_delta(UI_Id(21), {0, 20})
			node := &state.ui.layout.nodes[0]

			testing.expect(t, changed)
			expect_close(t, node.scroll.y, 20)
			expect_close(t, node.text.glyphs[0].dst.y, 4)
			expect_close(t, node.text.edit_geometry.glyphs[0].x0, 10)
			expect_close(t, node.text.edit_geometry.glyphs[0].x1, 18)

			node.text.glyphs = nil
			node.text.line_origins = nil
			node.text.edit_geometry = {}
		},
	)
}

@(test)
layout_offset_paint_geometry_offsets_edit_glyphs_x :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			edit_glyphs := make([]Text_Edit_Glyph, 1)
			defer delete(edit_glyphs)
			edit_glyphs[0] = {cluster = 0, x0 = 40, x1 = 48, line_index = 0}
			origins := make([]Vec2, 1)
			defer delete(origins)
			origins[0] = {8, 6}

			node := Layout_Node {
				text = {
					line_origins = origins,
					edit_geometry = {
						plain = "a",
						line_origins = origins,
						line_height = 16,
						glyphs = edit_glyphs,
					},
				},
			}

			layout_offset_paint_geometry(&node, -12, -3)

			expect_close(t, node.text.edit_geometry.glyphs[0].x0, 28)
			expect_close(t, node.text.edit_geometry.glyphs[0].x1, 36)
			expect_close(t, node.text.line_origins[0].x, -4)
			expect_close(t, node.text.line_origins[0].y, 3)

			node.text.line_origins = nil
			node.text.edit_geometry = {}
		},
	)
}

@(test)
layout_offset_subtree_moves_text_paint_geometry :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			ui_begin_frame()
			glyphs := make([]Layout_Glyph_Paint, 1, context.temp_allocator)
			glyphs[0] = {face_id = Asset_Id(0), glyph_id = 1, dst = {10, 20, 8, 12}}
			origins := make([]Vec2, 1, context.temp_allocator)
			origins[0] = {10, 30}
			strokes := make([]Layout_Decoration_Stroke, 1, context.temp_allocator)
			strokes[0] = {a = {10, 40}, b = {18, 40}, thickness = 1, color = {255, 255, 255, 255}}

			append(
				&state.ui.layout.nodes,
				Layout_Node {
					ui_id = UI_Id(99),
					kind = .TEXT,
					rect = {10, 20, 40, 20},
					text = {
						line_origins = origins,
						glyphs = glyphs,
						decoration_strokes = strokes,
					},
					image = {active = true, content = {10, 20, 40, 20}, dst = {10, 20, 40, 20}},
					collapsed_borders = {
						active = true,
						strips = {{10, 20, 40, 1}, {}, {}, {}},
					},
				},
			)
			idx := len(state.ui.layout.nodes) - 1
			layout_offset_subtree(idx, -5, -15)

			node := &state.ui.layout.nodes[idx]
			expect_close(t, node.rect.x, 5)
			expect_close(t, node.rect.y, 5)
			expect_close(t, node.text.glyphs[0].dst.x, 5)
			expect_close(t, node.text.glyphs[0].dst.y, 5)
			expect_close(t, node.text.line_origins[0].x, 5)
			expect_close(t, node.text.line_origins[0].y, 15)
			expect_close(t, node.text.decoration_strokes[0].a.y, 25)
			expect_close(t, node.image.dst.y, 5)
			expect_close(t, node.collapsed_borders.strips[0].y, 5)
		},
	)
}

@(test)
layout_finalize_after_rect_finalizes_leaf_scrollport :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			ov_scroll: Overflow = .SCROLL
			append(
				&state.ui.layout.nodes,
				Layout_Node {
					ui_id = UI_Id(51),
					kind = .RECT,
					config = {
						width = layout_len_fixed(100),
						height = layout_len_fixed(40),
						overflow_y = ov_scroll,
						scroll_y = 10,
					},
					rect = {0, 0, 100, 40},
					image_input = {
						src = {0, 0, 80, 120},
						dst = {0, 0, 80, 120},
						fit = .FILL,
						active = true,
					},
				},
			)

			node := &state.ui.layout.nodes[0]
			layout_finalize_after_rect(node)

			expect_close(t, node.content_size.y, 120)
			expect_close(t, node.max_scroll.y, 80)
			expect_close(t, node.scroll.y, 10)
		},
	)
}

@(test)
layout_child_leaf_scrollport_finalizes_via_parent :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			ui_begin_frame()
			ui_push_style(style_root(.SCREEN, {0, 0, 800, 600}))
			defer ui_pop_style()

			layout_begin_space(.SCREEN)
			ov_scroll: Overflow = .SCROLL
			_ = layout_push_node(
				UI_Id(60),
				{
					kind = .RECT,
					width = layout_len_fixed(200),
					height = layout_len_fixed(200),
					direction = .VERTICAL,
				},
			)
			child := layout_push_node(
				UI_Id(61),
				{
					kind = .RECT,
					width = layout_len_fixed(100),
					height = layout_len_fixed(40),
					overflow_y = ov_scroll,
					scroll_y = 15,
				},
			)
			layout_set_measure_size(child, {100, 40})
			layout_set_image(child, {0, 0, 80, 120}, {0, 0, 80, 120}, .FILL, {})
			layout_pop_node()
			layout_pop_node()
			layout_end_space()

			child_i := state.ui.layout.id_to_node[UI_Id(61)]
			c := &state.ui.layout.nodes[child_i]

			expect_close(t, c.max_scroll.y, 80)
			expect_close(t, c.scroll.y, 15)
		},
	)
}

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
	with_ui_env(t, proc(t: ^testing.T) {
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
	})
}

@(test)
layout_scrollport_skips_scrollbar_children :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
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
	})
}

@(test)
layout_scrollport_offsets_text_leaf_content :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		ov_scroll: Overflow = .SCROLL
		glyphs := make([]Layout_Glyph_Paint, 1)
		defer delete(glyphs)
		glyphs[0] = {
			face_id  = Asset_Id(0),
			glyph_id = 1,
			dst      = {4, 24, 8, 12},
		}
		origins := make([]Vec2, 1)
		defer delete(origins)
		origins[0] = {4, 24}
		edit_glyphs := make([]Text_Edit_Glyph, 1)
		defer delete(edit_glyphs)
		edit_glyphs[0] = {
			cluster    = 0,
			x0         = 14,
			x1         = 22,
			line_index = 0,
		}

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
	})
}

@(test)
layout_apply_scroll_delta_offsets_text_paint_geometry :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		glyphs := make([]Layout_Glyph_Paint, 1)
		defer delete(glyphs)
		glyphs[0] = {
			face_id  = Asset_Id(0),
			glyph_id = 1,
			dst      = {4, 24, 8, 12},
		}
		origins := make([]Vec2, 1)
		defer delete(origins)
		origins[0] = {4, 24}
		edit_glyphs := make([]Text_Edit_Glyph, 1)
		defer delete(edit_glyphs)
		edit_glyphs[0] = {
			cluster    = 0,
			x0         = 10,
			x1         = 18,
			line_index = 0,
		}

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
	})
}

@(test)
layout_offset_paint_geometry_offsets_edit_glyphs_x :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		edit_glyphs := make([]Text_Edit_Glyph, 1)
		defer delete(edit_glyphs)
		edit_glyphs[0] = {
			cluster    = 0,
			x0         = 40,
			x1         = 48,
			line_index = 0,
		}
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
	})
}

@(test)
layout_offset_subtree_moves_text_paint_geometry :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		ui_begin_frame()
		glyphs := make([]Layout_Glyph_Paint, 1, context.temp_allocator)
		glyphs[0] = {
			face_id  = Asset_Id(0),
			glyph_id = 1,
			dst      = {10, 20, 8, 12},
		}
		origins := make([]Vec2, 1, context.temp_allocator)
		origins[0] = {10, 30}
		strokes := make([]Layout_Decoration_Stroke, 1, context.temp_allocator)
		strokes[0] = {
			a         = {10, 40},
			b         = {18, 40},
			thickness = 1,
			color     = {255, 255, 255, 255},
		}

		append(
			&state.ui.layout.nodes,
			Layout_Node {
				ui_id = UI_Id(99),
				kind = .TEXT,
				rect = {10, 20, 40, 20},
				text = {line_origins = origins, glyphs = glyphs, decoration_strokes = strokes},
				image = {active = true, content = {10, 20, 40, 20}, dst = {10, 20, 40, 20}},
				collapsed_borders = {active = true, strips = {{10, 20, 40, 1}, {}, {}, {}}},
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
	})
}

/*
GROW scrollport → content-sized section → nested BALANCE text measured at
max-content (short), then solved at a narrow width (taller). Scroll extent must
reach the true text bottom, not stop at the short section box from bottom-up
measure.
*/
@(test)
layout_nested_soft_wrap_scrollport_reaches_content_bottom :: proc(t: ^testing.T) {
	if !layout_test_font_fixtures_available() {
		testing.expectf(
			t,
			false,
			"missing font fixtures; expected %s and %s (run from repo root)",
			LAYOUT_TEST_INTER_FONT,
			LAYOUT_TEST_INTER_ITALIC_FONT,
		)

		return
	}

	with_layout_solve(t, proc(layout: ^Layout_State, t: ^testing.T) {
		state.dpi = {
			logical_w = 800,
			logical_h = 600,
			scale     = 1,
		}

		testing.expect(t, font_init())
		defer font_shutdown()

		inter, inter_ok := font_register_family(
			"LayoutNestedSoftWrapScrollTest",
			{{path = LAYOUT_TEST_INTER_FONT, style = .NORMAL, weight = .Normal}},
		)
		testing.expect(t, inter_ok)
		inter = font_with_size(inter, 16)

		text := "Interactive control with layout chrome, focus, and pointer / keyboard handling. Style with set.* helpers on Button_Config."
		probe := Layout_Node {
			measure = {text = text},
			config = {
				font = inter,
				font_size = 16,
				line_height = 1.55,
				wrap = Text_Wrap_Kind.BALANCE,
				text_direction = Text_Direction_Kind.LTR,
				align = Text_Align_Kind.LEFT,
				space = .SCREEN,
				text_decoration = Text_Decoration_Lines{},
				text_decoration_style = Text_Decoration_Style_Kind.SOLID,
			},
		}
		short := layout_text_estimate_size(&probe, 0)
		tall := layout_text_estimate_size(&probe, 200)
		testing.expect(t, tall.y > short.y + 1)

		ov_auto: Overflow = .AUTO
		root := layout_test_append_node(
			layout,
			-1,
			.RECT,
			{x = .STRETCH, y = .START},
			{240, 160},
			{direction = .VERTICAL, width = layout_len_fixed(240), height = layout_len_fixed(160)},
		)
		port := layout_test_append_node(
			layout,
			root,
			.RECT,
			{x = .STRETCH, y = .START},
			{240, short.y + 40},
			{
				direction = .VERTICAL,
				width = layout_len_fixed(240),
				height = layout_len_grow(),
				overflow_y = ov_auto,
				gap_y = 8,
			},
		)
		section := layout_test_append_node(
			layout,
			port,
			.RECT,
			{x = .STRETCH, y = .START},
			{240, short.y},
			{direction = .VERTICAL, width = layout_len_grow()},
		)
		body := layout_test_append_node(
			layout,
			section,
			.TEXT,
			{},
			short,
			{
				font = inter,
				font_size = 16,
				line_height = 1.55,
				wrap = Text_Wrap_Kind.BALANCE,
				text_direction = Text_Direction_Kind.LTR,
				align = Text_Align_Kind.LEFT,
				space = .SCREEN,
				width = layout_len_grow(),
				text_decoration = Text_Decoration_Lines{},
				text_decoration_style = Text_Decoration_Style_Kind.SOLID,
			},
		)
		layout.nodes[body].measure = {
			text            = text,
			measured_wrap_w = 0,
		}
		footer := layout_test_append_node(
			layout,
			port,
			.RECT,
			{},
			{240, 40},
			{width = layout_len_fixed(240), height = layout_len_fixed(40)},
		)

		layout.nodes[section].desired = layout_measure(&layout.nodes[section])
		layout.nodes[port].desired = layout_measure(&layout.nodes[port])
		layout.nodes[root].desired = layout_measure(&layout.nodes[root])
		layout_solve(&layout.nodes[root], {0, 0, 240, 160})
		defer layout_text_release(&layout.nodes[body])

		port_node := &layout.nodes[port]
		body_node := &layout.nodes[body]
		footer_node := &layout.nodes[footer]
		content := layout_inner_rect(port_node.rect, port_node.border, port_node.padding)
		true_bottom := max(
			body_node.rect.y + body_node.rect.h - content.y,
			footer_node.rect.y + footer_node.rect.h - content.y,
		)

		expect_close(t, port_node.rect.h, 160)
		testing.expect(t, body_node.rect.h > short.y + 1)
		testing.expect(t, port_node.content_size.y + 0.5 >= true_bottom)
		testing.expect(t, port_node.max_scroll.y + 0.5 >= true_bottom - port_node.viewport_size.y)
		testing.expect(t, footer_node.rect.y + 0.5 >= body_node.rect.y + body_node.rect.h + 8)
	})
}

@(test)
layout_grow_height_scrollport_keeps_viewport_and_scrolls :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		ui_begin_frame()
		ui_push_style(style_root(.SCREEN, {0, 0, 400, 300}))
		defer ui_pop_style()

		layout_begin_space(.SCREEN)
		ov_auto: Overflow = .AUTO
		parent := layout_push_node(
			UI_Id(70),
			{
				kind = .RECT,
				width = layout_len_fixed(200),
				height = layout_len_fixed(200),
				direction = .VERTICAL,
			},
		)
		_ = parent
		port := layout_push_node(
			UI_Id(71),
			{
				kind = .RECT,
				width = layout_len_fixed(200),
				height = layout_len_grow(),
				direction = .VERTICAL,
				overflow_y = ov_auto,
			},
		)
		_ = port
		for i in 0 ..< 4 {
			child := layout_push_node(
				UI_Id(u64(80 + i)),
				{kind = .RECT, width = layout_len_fixed(180), height = layout_len_fixed(100)},
			)
			layout_set_measure_size(child, {180, 100})
			layout_pop_node()
		}
		layout_pop_node()
		layout_pop_node()
		layout_end_space()

		port_i := state.ui.layout.id_to_node[UI_Id(71)]
		p := &state.ui.layout.nodes[port_i]

		expect_close(t, p.rect.h, 200)
		expect_close(t, p.viewport_size.y, 200)
		expect_close(t, p.content_size.y, 400)
		expect_close(t, p.max_scroll.y, 200)
	})
}

@(test)
layout_finalize_after_rect_finalizes_leaf_scrollport :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
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
	})
}

@(test)
layout_child_leaf_scrollport_finalizes_via_parent :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
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
	})
}

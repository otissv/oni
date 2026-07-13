package oni

import "core:testing"

@(private)
layout_stack_abs :: proc() -> Position {
	p: Position = .ABSOLUTE
	return p
}

@(private)
layout_stack_hidden :: proc() -> Visibility {
	v: Visibility = .HIDDEN
	return v
}

@(private)
layout_stack_pe_none :: proc() -> Pointer_Events {
	p: Pointer_Events = .NONE
	return p
}

@(private)
layout_stack_ov_hidden :: proc() -> Overflow {
	o: Overflow = .HIDDEN
	return o
}

@(test)
layout_stack_negative_z_under_parent_chrome :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			ui_begin_frame()
			ui_push_style(style_root(.SCREEN, {0, 0, 800, 600}))
			defer ui_pop_style()

			layout_begin_space(.SCREEN)
			_ = layout_push_node(
				UI_Id(1),
				{kind = .RECT, width = layout_len_fixed(200), height = layout_len_fixed(200)},
			)
			_ = layout_push_node(
				UI_Id(2),
				{kind = .RECT, z_index = -1, width = layout_len_fixed(10), height = layout_len_fixed(10)},
			)
			layout_pop_node()
			_ = layout_push_node(
				UI_Id(3),
				{kind = .RECT, z_index = 1, width = layout_len_fixed(10), height = layout_len_fixed(10)},
			)
			layout_pop_node()
			layout_pop_node()
			layout_end_space()
			layout_finalize_stack_order()

			neg_i := state.ui.layout.id_to_node[UI_Id(2)]
			parent_i := state.ui.layout.id_to_node[UI_Id(1)]
			pos_i := state.ui.layout.id_to_node[UI_Id(3)]
			testing.expect(
				t,
				state.ui.layout.nodes[neg_i].stack_index < state.ui.layout.nodes[parent_i].stack_index,
			)
			testing.expect(
				t,
				state.ui.layout.nodes[parent_i].stack_index < state.ui.layout.nodes[pos_i].stack_index,
			)
		},
	)
}

@(test)
layout_stack_order_tiebreaks_equal_z :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			ui_begin_frame()
			ui_push_style(style_root(.SCREEN, {0, 0, 800, 600}))
			defer ui_pop_style()

			layout_begin_space(.SCREEN)
			_ = layout_push_node(
				UI_Id(1),
				{kind = .RECT, width = layout_len_fixed(100), height = layout_len_fixed(100)},
			)
			_ = layout_push_node(
				UI_Id(2),
				{kind = .RECT, order = 2, width = layout_len_fixed(10), height = layout_len_fixed(10)},
			)
			layout_pop_node()
			_ = layout_push_node(
				UI_Id(3),
				{kind = .RECT, order = 1, width = layout_len_fixed(10), height = layout_len_fixed(10)},
			)
			layout_pop_node()
			layout_pop_node()
			layout_end_space()
			layout_finalize_stack_order()

			a_i := state.ui.layout.id_to_node[UI_Id(2)]
			b_i := state.ui.layout.id_to_node[UI_Id(3)]
			testing.expect(
				t,
				state.ui.layout.nodes[b_i].stack_index < state.ui.layout.nodes[a_i].stack_index,
			)
		},
	)
}

@(test)
layout_absolute_left_right_stretch :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			ui_begin_frame()
			ui_push_style(style_root(.SCREEN, {0, 0, 800, 600}))
			defer ui_pop_style()

			layout_begin_space(.SCREEN)
			_ = layout_push_node(
				UI_Id(1),
				{kind = .RECT, width = layout_len_fixed(200), height = layout_len_fixed(100)},
			)
			child := layout_push_node(
				UI_Id(2),
				{kind = .RECT, height = layout_len_fixed(30)},
			)
			child.config.position = layout_stack_abs()
			child.config.x = 10
			child.config.x_set = true
			child.config.right = 20
			child.config.right_set = true
			child.config.y = 5
			child.config.y_set = true
			layout_set_measure_size(child, {0, 30})
			layout_pop_node()
			layout_pop_node()
			layout_end_space()

			got := state.ui.layout.nodes[state.ui.layout.id_to_node[UI_Id(2)]].rect
			expect_close(t, got.x, 10)
			expect_close(t, got.w, 170)
			expect_close(t, got.y, 5)
			expect_close(t, got.h, 30)
		},
	)
}

@(test)
layout_absolute_right_only_pin :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			ui_begin_frame()
			ui_push_style(style_root(.SCREEN, {0, 0, 800, 600}))
			defer ui_pop_style()

			layout_begin_space(.SCREEN)
			_ = layout_push_node(
				UI_Id(1),
				{kind = .RECT, width = layout_len_fixed(200), height = layout_len_fixed(100)},
			)
			child := layout_push_node(
				UI_Id(2),
				{kind = .RECT, width = layout_len_fixed(40), height = layout_len_fixed(20)},
			)
			child.config.position = layout_stack_abs()
			child.config.right = 15
			child.config.right_set = true
			child.config.y = 0
			child.config.y_set = true
			layout_set_measure_size(child, {40, 20})
			layout_pop_node()
			layout_pop_node()
			layout_end_space()

			got := state.ui.layout.nodes[state.ui.layout.id_to_node[UI_Id(2)]].rect
			expect_close(t, got.x, 145)
			expect_close(t, got.w, 40)
		},
	)
}

@(test)
layout_absolute_percent_width_vs_containing_block :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			ui_begin_frame()
			ui_push_style(style_root(.SCREEN, {0, 0, 800, 600}))
			defer ui_pop_style()

			layout_begin_space(.SCREEN)
			_ = layout_push_node(
				UI_Id(1),
				{kind = .RECT, width = layout_len_fixed(200), height = layout_len_fixed(100)},
			)
			child := layout_push_node(
				UI_Id(2),
				{kind = .RECT, width = {kind = .PERCENT, value = 50}, height = layout_len_fixed(10)},
			)
			child.config.position = layout_stack_abs()
			child.config.x = 0
			child.config.x_set = true
			child.config.y = 0
			child.config.y_set = true
			layout_set_measure_size(child, {0, 10})
			layout_pop_node()
			layout_pop_node()
			layout_end_space()

			got := state.ui.layout.nodes[state.ui.layout.id_to_node[UI_Id(2)]].rect
			expect_close(t, got.w, 100)
		},
	)
}

@(test)
layout_hidden_keeps_flex_space_skips_hit :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			ui_begin_frame()
			ui_push_style(style_root(.SCREEN, {0, 0, 800, 600}))
			defer ui_pop_style()

			layout_begin_space(.SCREEN)
			_ = layout_push_node(
				UI_Id(1),
				{
					kind = .RECT,
					direction = .HORIZONTAL,
					width = layout_len_fixed(300),
					height = layout_len_fixed(50),
				},
			)
			a := layout_push_node(
				UI_Id(2),
				{kind = .RECT, width = layout_len_fixed(100), height = layout_len_fixed(50)},
			)
			a.config.visibility = layout_stack_hidden()
			layout_set_measure_size(a, {100, 50})
			layout_pop_node()
			b := layout_push_node(
				UI_Id(3),
				{kind = .RECT, width = layout_len_fixed(100), height = layout_len_fixed(50)},
			)
			layout_set_measure_size(b, {100, 50})
			layout_pop_node()
			layout_pop_node()
			layout_end_space()
			layout_finalize_stack_order()

			a_i := state.ui.layout.id_to_node[UI_Id(2)]
			b_i := state.ui.layout.id_to_node[UI_Id(3)]
			expect_close(t, state.ui.layout.nodes[a_i].rect.w, 100)
			expect_close(t, state.ui.layout.nodes[b_i].rect.x, 100)
			testing.expect(t, state.ui.layout.nodes[a_i].paint_skip)
			testing.expect(t, state.ui.layout.nodes[a_i].hit_skip)

			w_ctx.mouse_x = 50
			w_ctx.mouse_y = 25
			layout_resolve_pointer_hit()
			testing.expect(t, !w_ctx.pointer_hit_valid || w_ctx.pointer_hit_ui_id != UI_Id(2))
		},
	)
}

@(test)
layout_pointer_events_none_parent_child_hittable :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			ui_begin_frame()
			ui_push_style(style_root(.SCREEN, {0, 0, 800, 600}))
			defer ui_pop_style()

			layout_begin_space(.SCREEN)
			parent := layout_push_node(
				UI_Id(1),
				{kind = .RECT, width = layout_len_fixed(100), height = layout_len_fixed(100)},
			)
			parent.config.pointer_events = layout_stack_pe_none()
			child := layout_push_node(
				UI_Id(2),
				{kind = .RECT, width = layout_len_fixed(100), height = layout_len_fixed(100)},
			)
			layout_set_measure_size(child, {100, 100})
			layout_pop_node()
			layout_pop_node()
			layout_end_space()
			layout_finalize_stack_order()

			parent_i := state.ui.layout.id_to_node[UI_Id(1)]
			child_i := state.ui.layout.id_to_node[UI_Id(2)]
			testing.expect(t, state.ui.layout.nodes[parent_i].hit_skip)
			testing.expect(t, !state.ui.layout.nodes[child_i].hit_skip)

			w_ctx.mouse_x = 50
			w_ctx.mouse_y = 50
			layout_resolve_pointer_hit()
			testing.expect(t, w_ctx.pointer_hit_ui_id == UI_Id(2))
			testing.expect(t, pointer_hits(UI_Id(2), state.ui.layout.nodes[child_i].rect, .SCREEN))
			testing.expect(
				t,
				pointer_hits(UI_Id(1), state.ui.layout.nodes[parent_i].rect, .SCREEN),
			)
			testing.expect(t, pointer_is_target(UI_Id(2)))
			testing.expect(t, !pointer_is_target(UI_Id(1)))
		},
	)
}

@(test)
layout_overflow_clip_excludes_outside_hits :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			ui_begin_frame()
			ui_push_style(style_root(.SCREEN, {0, 0, 800, 600}))
			defer ui_pop_style()

			layout_begin_space(.SCREEN)
			parent := layout_push_node(
				UI_Id(1),
				{kind = .RECT, width = layout_len_fixed(50), height = layout_len_fixed(50)},
			)
			parent.config.overflow_x = layout_stack_ov_hidden()
			parent.config.overflow_y = layout_stack_ov_hidden()
			child := layout_push_node(
				UI_Id(2),
				{kind = .RECT, width = layout_len_fixed(100), height = layout_len_fixed(100)},
			)
			layout_set_measure_size(child, {100, 100})
			layout_pop_node()
			layout_pop_node()
			layout_end_space()
			layout_finalize_stack_order()

			child_i := state.ui.layout.id_to_node[UI_Id(2)]
			testing.expect(t, state.ui.layout.nodes[child_i].has_clip)

			w_ctx.mouse_x = 80
			w_ctx.mouse_y = 25
			layout_resolve_pointer_hit()
			testing.expect(t, !w_ctx.pointer_hit_valid || w_ctx.pointer_hit_ui_id != UI_Id(2))
		},
	)
}

@(test)
layout_top_layer_above_screen_for_hit :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			ui_begin_frame()
			ui_push_style(style_root(.SCREEN, {0, 0, 800, 600}))
			defer ui_pop_style()

			layout_begin_space(.SCREEN)
			a := layout_push_node(
				UI_Id(1),
				{kind = .RECT, width = layout_len_fixed(100), height = layout_len_fixed(100)},
			)
			layout_set_measure_size(a, {100, 100})
			layout_pop_node()
			b := layout_push_node(
				UI_Id(2),
				{kind = .RECT, width = layout_len_fixed(100), height = layout_len_fixed(100)},
			)
			b.config.top_layer = true
			layout_set_measure_size(b, {100, 100})
			layout_pop_node()
			layout_end_space()
			layout_finalize_stack_order()

			a_i := state.ui.layout.id_to_node[UI_Id(1)]
			b_i := state.ui.layout.id_to_node[UI_Id(2)]
			testing.expect(
				t,
				state.ui.layout.nodes[a_i].stack_index < state.ui.layout.nodes[b_i].stack_index,
			)

			w_ctx.mouse_x = 50
			w_ctx.mouse_y = 50
			layout_resolve_pointer_hit()
			testing.expect(t, w_ctx.pointer_hit_ui_id == UI_Id(2))
		},
	)
}

@(test)
layout_child_z_cannot_beat_uncle :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			ui_begin_frame()
			ui_push_style(style_root(.SCREEN, {0, 0, 800, 600}))
			defer ui_pop_style()

			layout_begin_space(.SCREEN)
			_ = layout_push_node(
				UI_Id(1),
				{
					kind = .RECT,
					direction = .HORIZONTAL,
					width = layout_len_fixed(200),
					height = layout_len_fixed(100),
				},
			)
			_ = layout_push_node(
				UI_Id(2),
				{kind = .RECT, width = layout_len_fixed(100), height = layout_len_fixed(100)},
			)
			nephew := layout_push_node(
				UI_Id(3),
				{kind = .RECT, z_index = 99, width = layout_len_fixed(100), height = layout_len_fixed(100)},
			)
			layout_set_measure_size(nephew, {100, 100})
			layout_pop_node()
			layout_pop_node()
			uncle := layout_push_node(
				UI_Id(4),
				{kind = .RECT, z_index = 1, width = layout_len_fixed(100), height = layout_len_fixed(100)},
			)
			layout_set_measure_size(uncle, {100, 100})
			layout_pop_node()
			layout_pop_node()
			layout_end_space()
			layout_finalize_stack_order()

			nephew_i := state.ui.layout.id_to_node[UI_Id(3)]
			uncle_i := state.ui.layout.id_to_node[UI_Id(4)]
			testing.expect(
				t,
				state.ui.layout.nodes[nephew_i].stack_index <
					state.ui.layout.nodes[uncle_i].stack_index,
			)
		},
	)
}

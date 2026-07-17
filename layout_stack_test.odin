package oni

import "core:testing"

@(private)
layout_stack_abs :: proc() -> Position {
	p: Position = .ABSOLUTE
	return p
}

@(private)
layout_stack_fixed :: proc() -> Position {
	p: Position = .FIXED
	return p
}

@(private)
layout_stack_hidden :: proc() -> Visibility {
	v: Visibility = .HIDDEN
	return v
}

@(private)
layout_stack_none :: proc() -> Visibility {
	v: Visibility = .NONE
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
layout_fixed_places_against_space_bounds_not_parent :: proc(t: ^testing.T) {
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
					width = layout_len_fixed(800),
					height = layout_len_fixed(600),
				},
			)
			spacer := layout_push_node(
				UI_Id(2),
				{kind = .RECT, width = layout_len_fixed(120), height = layout_len_fixed(80)},
			)
			layout_set_measure_size(spacer, {120, 80})
			layout_pop_node()
			_ = layout_push_node(
				UI_Id(3),
				{kind = .RECT, width = layout_len_fixed(200), height = layout_len_fixed(100)},
			)
			fixed := layout_push_node(
				UI_Id(4),
				{
					kind = .RECT,
					position = layout_stack_fixed(),
					width = layout_len_fixed(40),
					height = layout_len_fixed(30),
					x = 20,
					x_set = true,
					y = 40,
					y_set = true,
				},
			)
			layout_set_measure_size(fixed, {40, 30})
			layout_pop_node()
			layout_pop_node()
			layout_pop_node()
			layout_end_space()

			parent_i := state.ui.layout.id_to_node[UI_Id(3)]
			fixed_i := state.ui.layout.id_to_node[UI_Id(4)]
			expect_close(t, state.ui.layout.nodes[parent_i].rect.x, 120)
			got := state.ui.layout.nodes[fixed_i].rect
			expect_close(t, got.x, 20)
			expect_close(t, got.y, 40)
			expect_close(t, got.w, 40)
			expect_close(t, got.h, 30)
			testing.expect(t, !state.ui.layout.nodes[fixed_i].in_flex_flow)
		},
	)
}

@(test)
layout_fixed_right_pin_uses_space_width :: proc(t: ^testing.T) {
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
			fixed := layout_push_node(
				UI_Id(2),
				{
					kind = .RECT,
					position = layout_stack_fixed(),
					width = layout_len_fixed(50),
					height = layout_len_fixed(20),
					right = 15,
					right_set = true,
					y = 10,
					y_set = true,
				},
			)
			layout_set_measure_size(fixed, {50, 20})
			layout_pop_node()
			layout_pop_node()
			layout_end_space()

			got := state.ui.layout.nodes[state.ui.layout.id_to_node[UI_Id(2)]].rect
			expect_close(t, got.x, 735)
			expect_close(t, got.y, 10)
			expect_close(t, got.w, 50)
		},
	)
}

@(test)
layout_fixed_excluded_from_flex_gap :: proc(t: ^testing.T) {
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
					gap_x = 10,
					width = layout_len_fixed(400),
					height = layout_len_fixed(50),
				},
			)
			a := layout_push_node(
				UI_Id(2),
				{kind = .RECT, width = layout_len_fixed(100), height = layout_len_fixed(50)},
			)
			layout_set_measure_size(a, {100, 50})
			layout_pop_node()
			fixed := layout_push_node(
				UI_Id(3),
				{
					kind = .RECT,
					position = layout_stack_fixed(),
					width = layout_len_fixed(100),
					height = layout_len_fixed(50),
					x = 5,
					x_set = true,
					y = 5,
					y_set = true,
				},
			)
			layout_set_measure_size(fixed, {100, 50})
			layout_pop_node()
			b := layout_push_node(
				UI_Id(4),
				{kind = .RECT, width = layout_len_fixed(100), height = layout_len_fixed(50)},
			)
			layout_set_measure_size(b, {100, 50})
			layout_pop_node()
			layout_pop_node()
			layout_end_space()

			a_i := state.ui.layout.id_to_node[UI_Id(2)]
			fixed_i := state.ui.layout.id_to_node[UI_Id(3)]
			b_i := state.ui.layout.id_to_node[UI_Id(4)]
			expect_close(t, state.ui.layout.nodes[a_i].rect.x, 0)
			expect_close(t, state.ui.layout.nodes[b_i].rect.x, 110)
			expect_close(t, state.ui.layout.nodes[fixed_i].rect.x, 5)
			expect_close(t, state.ui.layout.nodes[fixed_i].rect.y, 5)
			testing.expect(t, !state.ui.layout.nodes[fixed_i].in_flex_flow)
		},
	)
}

@(test)
layout_absolute_vs_fixed_containing_block :: proc(t: ^testing.T) {
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
					width = layout_len_fixed(800),
					height = layout_len_fixed(200),
				},
			)
			spacer := layout_push_node(
				UI_Id(2),
				{kind = .RECT, width = layout_len_fixed(100), height = layout_len_fixed(100)},
			)
			layout_set_measure_size(spacer, {100, 100})
			layout_pop_node()
			_ = layout_push_node(
				UI_Id(3),
				{kind = .RECT, width = layout_len_fixed(200), height = layout_len_fixed(100)},
			)
			abs := layout_push_node(
				UI_Id(4),
				{
					kind = .RECT,
					position = layout_stack_abs(),
					width = layout_len_fixed(40),
					height = layout_len_fixed(20),
					x = 10,
					x_set = true,
					y = 15,
					y_set = true,
				},
			)
			layout_set_measure_size(abs, {40, 20})
			layout_pop_node()
			fixed := layout_push_node(
				UI_Id(5),
				{
					kind = .RECT,
					position = layout_stack_fixed(),
					width = layout_len_fixed(40),
					height = layout_len_fixed(20),
					x = 10,
					x_set = true,
					y = 15,
					y_set = true,
				},
			)
			layout_set_measure_size(fixed, {40, 20})
			layout_pop_node()
			layout_pop_node()
			layout_pop_node()
			layout_end_space()

			abs_r := state.ui.layout.nodes[state.ui.layout.id_to_node[UI_Id(4)]].rect
			fixed_r := state.ui.layout.nodes[state.ui.layout.id_to_node[UI_Id(5)]].rect
			expect_close(t, abs_r.x, 110)
			expect_close(t, abs_r.y, 15)
			expect_close(t, fixed_r.x, 10)
			expect_close(t, fixed_r.y, 15)
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

@(private)
layout_stack_none_nested_ran: bool

@(test)
layout_children_visibility_none_skips_nested_registration :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			ui_begin_frame()
			ui_push_style(style_root(.SCREEN, {0, 0, 800, 600}))
			defer ui_pop_style()

			frame, event := ui_test_frame_event()
			none_cfg := resolve_widget_config(
				{},
				{
					id = "none-parent",
					visibility = {mode = .Value, value = layout_stack_none()},
				},
				&frame,
				event,
			)
			layout_stack_none_nested_ran = false
			Children(
				proc(_: Widget_Frame_State) {
					layout_stack_none_nested_ran = true
				},
				ui_id("none-parent"),
				none_cfg,
				frame,
			)
			testing.expect(t, !layout_stack_none_nested_ran)
			testing.expect(t, !ui_has_layout_node(ui_id("none-parent")))
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
layout_popover_above_screen_for_hit :: proc(t: ^testing.T) {
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
				{
					kind = .RECT,
					space = .POPOVER,
					width = layout_len_fixed(100),
					height = layout_len_fixed(100),
				},
			)
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
layout_popover_z_index_within_stacking_context :: proc(t: ^testing.T) {
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
					space = .POPOVER,
					width = layout_len_fixed(200),
					height = layout_len_fixed(200),
				},
			)
			back := layout_push_node(
				UI_Id(2),
				{kind = .RECT, z_index = 1, width = layout_len_fixed(100), height = layout_len_fixed(100)},
			)
			back.config.position = layout_stack_abs()
			back.config.x = 0
			back.config.x_set = true
			back.config.y = 0
			back.config.y_set = true
			layout_set_measure_size(back, {100, 100})
			layout_pop_node()
			front := layout_push_node(
				UI_Id(3),
				{kind = .RECT, z_index = 5, width = layout_len_fixed(100), height = layout_len_fixed(100)},
			)
			front.config.position = layout_stack_abs()
			front.config.x = 0
			front.config.x_set = true
			front.config.y = 0
			front.config.y_set = true
			layout_set_measure_size(front, {100, 100})
			layout_pop_node()
			layout_pop_node()
			layout_end_space()
			layout_finalize_stack_order()

			back_i := state.ui.layout.id_to_node[UI_Id(2)]
			front_i := state.ui.layout.id_to_node[UI_Id(3)]
			testing.expect(t, state.ui.layout.nodes[back_i].space == .POPOVER)
			testing.expect(t, state.ui.layout.nodes[front_i].space == .POPOVER)
			testing.expect(
				t,
				state.ui.layout.nodes[back_i].stack_index <
					state.ui.layout.nodes[front_i].stack_index,
			)

			w_ctx.mouse_x = 50
			w_ctx.mouse_y = 50
			layout_resolve_pointer_hit()
			testing.expect(t, w_ctx.pointer_hit_ui_id == UI_Id(3))
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

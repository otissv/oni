package oni

import "core:testing"

@(test)
widget_register_tabbable_appends_in_order :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			register_tabbable("a")
			register_tabbable("b")
			register_tabbable("c")
			testing.expect_value(t, len(w_ctx.tab_order), 3)
			testing.expect_value(t, w_ctx.tab_order[0], "a")
			testing.expect_value(t, w_ctx.tab_order[1], "b")
			testing.expect_value(t, w_ctx.tab_order[2], "c")
		},
	)
}

@(test)
widget_prune_focus_clears_missing_and_keeps_present :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			register_tabbable("alive")
			w_ctx.focused_id = "gone"
			widget_prune_focus()
			testing.expect_value(t, w_ctx.focused_id, "")

			w_ctx.focused_id = "alive"
			widget_prune_focus()
			testing.expect_value(t, w_ctx.focused_id, "alive")

			w_ctx.focused_id = ""
			widget_prune_focus()
			testing.expect_value(t, w_ctx.focused_id, "")
		},
	)
}

@(test)
widget_focus_tab_wraps_forward_and_backward :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			register_tabbable("a")
			register_tabbable("b")
			register_tabbable("c")

			testing.expect(t, widget_focus_tab(false))
			testing.expect_value(t, w_ctx.focused_id, "a")
			testing.expect(t, w_ctx.tab_focus_changed)
			testing.expect_value(t, w_ctx.tab_focus_previous_id, "")

			testing.expect(t, focus_next())
			testing.expect_value(t, w_ctx.focused_id, "b")
			testing.expect(t, focus_next())
			testing.expect_value(t, w_ctx.focused_id, "c")
			testing.expect(t, focus_next())
			testing.expect_value(t, w_ctx.focused_id, "a")

			testing.expect(t, focus_prev())
			testing.expect_value(t, w_ctx.focused_id, "c")
			testing.expect(t, focus_prev())
			testing.expect_value(t, w_ctx.focused_id, "b")
		},
	)
}

@(test)
widget_focus_tab_empty_and_single_element :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			testing.expect(t, !widget_focus_tab(false))
			testing.expect(t, !focus_next())
			testing.expect(t, !focus_prev())

			register_tabbable("only")
			w_ctx.focused_id = "only"
			testing.expect(t, !widget_focus_tab(false))
			testing.expect_value(t, w_ctx.focused_id, "only")
		},
	)
}

@(test)
widget_process_tab_navigation_respects_shift :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			register_tabbable("a")
			register_tabbable("b")
			w_ctx.focused_id = "a"
			w_ctx.keys[int(Scancode.TAB)].pressed = true

			widget_process_tab_navigation()
			testing.expect_value(t, w_ctx.focused_id, "b")

			state.input.modifiers.shift = true
			w_ctx.keys[int(Scancode.TAB)].pressed = true
			widget_process_tab_navigation()
			testing.expect_value(t, w_ctx.focused_id, "a")
		},
	)
}

@(test)
widget_auto_element_id_and_static_id_mapping :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			w_ctx.auto_element_index = 0
			a := auto_element_id()
			b := auto_element_id()
			testing.expect(t, a != b)
			testing.expect_value(t, a, "__auto_element__0")
			testing.expect_value(t, b, "__auto_element__1")

			register_static_id("", "ignored")
			testing.expect(t, w_ctx.static_ids == nil || len(w_ctx.static_ids) == 0)

			key := element_key("btn")
			testing.expect_value(t, key, "btn")
			testing.expect_value(t, w_ctx.static_ids["btn"], key)
		},
	)
}

@(test)
widget_element_keys_survive_temp_allocator_wipe :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			named := element_key("stable")
			auto := element_key("")
			testing.expect_value(t, auto, "__auto_element__0")

			widget_set_focused_id(auto)
			_, _ = consume_hover_transition(named, true)
			_, _ = consume_hover_transition(auto, true)

			free_all(context.temp_allocator)

			// Look up with stable/literal keys — the pre-wipe `auto` temp is invalid.
			testing.expect_value(t, w_ctx.focused_id, "__auto_element__0")
			testing.expect(t, w_ctx.element_was_hovered[named])
			testing.expect(t, w_ctx.element_was_hovered["__auto_element__0"])
			testing.expect_value(t, element_key("stable"), "stable")
		},
	)
}

@(test)
widget_button_and_key_transients_clear :: proc(t: ^testing.T) {
	button := Widget_Mouse_Button_State {
		down     = true,
		pressed  = true,
		released = true,
	}
	clear_button_transients(&button)
	testing.expect(t, button.down)
	testing.expect(t, !button.pressed)
	testing.expect(t, !button.released)

	key := Widget_Mouse_Key_State {
		down     = true,
		pressed  = true,
		released = true,
	}
	clear_key_transients(&key)
	testing.expect(t, key.down)
	testing.expect(t, !key.pressed)
	testing.expect(t, !key.released)
}

@(test)
widget_sync_input_tracks_mouse_and_edges :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			state.input.mouse_x = 12
			state.input.mouse_y = 34
			state.input.mouse_left = true
			state.input.keys_down[int(Scancode.A)] = true

			sync_widget_input()
			testing.expect(t, w_ctx.mouse_moved)
			expect_close(t, w_ctx.mouse_x, 12)
			expect_close(t, w_ctx.mouse_y, 34)
			testing.expect(t, w_ctx.left_mouse.pressed)
			testing.expect(t, w_ctx.left_mouse.down)
			testing.expect(t, w_ctx.keys[int(Scancode.A)].pressed)

			w_ctx.mouse_moved = false
			clear_button_transients(&w_ctx.left_mouse)
			clear_key_transients(&w_ctx.keys[int(Scancode.A)])
			sync_widget_input()
			testing.expect(t, !w_ctx.mouse_moved)
			testing.expect(t, !w_ctx.left_mouse.pressed)
			testing.expect(t, w_ctx.left_mouse.down)

			state.input.mouse_left = false
			state.input.keys_down[int(Scancode.A)] = false
			sync_widget_input()
			testing.expect(t, w_ctx.left_mouse.released)
			testing.expect(t, !w_ctx.left_mouse.down)
			testing.expect(t, w_ctx.keys[int(Scancode.A)].released)
		},
	)
}

@(test)
widget_pointer_over_screen_space :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			w_ctx.mouse_x = 25
			w_ctx.mouse_y = 35
			rect := Rect{20, 30, 40, 20}
			testing.expect(t, pointer_over(rect, .SCREEN))

			w_ctx.mouse_x = 19
			testing.expect(t, !pointer_over(rect, .SCREEN))

			w_ctx.mouse_x = 60
			testing.expect(t, !pointer_over(rect, .SCREEN))

			w_ctx.mouse_x = 25
			w_ctx.mouse_y = 50
			testing.expect(t, !pointer_over(rect, .SCREEN))
		},
	)
}

@(test)
widget_pointer_hits_prefers_higher_stack_order :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			ui_begin_frame()
			ui_push_style(style_root(.SCREEN, {0, 0, 800, 600}))
			defer {
				ui_pop_style()
			}

			_ = layout_push_node(
				UI_Id(10),
				{kind = .RECT, space = .SCREEN, z_index = 1},
			)
			layout_pop_node()
			_ = layout_push_node(
				UI_Id(20),
				{kind = .RECT, space = .SCREEN, z_index = 5},
			)
			layout_pop_node()

			low_i := state.ui.layout.id_to_node[UI_Id(10)]
			high_i := state.ui.layout.id_to_node[UI_Id(20)]
			state.ui.layout.nodes[low_i].rect = {0, 0, 100, 100}
			state.ui.layout.nodes[high_i].rect = {0, 0, 100, 100}

			w_ctx.mouse_x = 50
			w_ctx.mouse_y = 50
			layout_finalize_stack_order()
			layout_resolve_pointer_hit()

			testing.expect(t, w_ctx.pointer_hit_valid)
			testing.expect(t, w_ctx.pointer_hit_ui_id == UI_Id(20))
			testing.expect(t, pointer_hits(UI_Id(20), state.ui.layout.nodes[high_i].rect, .SCREEN))
			testing.expect(t, !pointer_hits(UI_Id(10), state.ui.layout.nodes[low_i].rect, .SCREEN))
			testing.expect(t, pointer_is_target(UI_Id(20)))
			testing.expect(t, !pointer_is_target(UI_Id(10)))
		},
	)
}

@(test)
widget_pointer_hits_includes_layout_ancestors :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			ui_begin_frame()
			ui_push_style(style_root(.SCREEN, {0, 0, 800, 600}))
			defer ui_pop_style()

			_ = layout_push_node(
				UI_Id(1),
				{kind = .RECT, space = .SCREEN, width = layout_len_fixed(100), height = layout_len_fixed(100)},
			)
			_ = layout_push_node(
				UI_Id(2),
				{kind = .RECT, space = .SCREEN, width = layout_len_fixed(100), height = layout_len_fixed(100)},
			)
			layout_pop_node()
			layout_pop_node()

			parent_i := state.ui.layout.id_to_node[UI_Id(1)]
			child_i := state.ui.layout.id_to_node[UI_Id(2)]
			state.ui.layout.nodes[parent_i].rect = {0, 0, 100, 100}
			state.ui.layout.nodes[child_i].rect = {10, 10, 40, 40}

			w_ctx.mouse_x = 20
			w_ctx.mouse_y = 20
			layout_finalize_stack_order()
			layout_resolve_pointer_hit()

			testing.expect(t, w_ctx.pointer_hit_ui_id == UI_Id(2))
			testing.expect(t, pointer_hits(UI_Id(2), state.ui.layout.nodes[child_i].rect, .SCREEN))
			testing.expect(t, pointer_hits(UI_Id(1), state.ui.layout.nodes[parent_i].rect, .SCREEN))
			testing.expect(t, pointer_is_target(UI_Id(2)))
			testing.expect(t, !pointer_is_target(UI_Id(1)))
			testing.expect(t, layout_is_ancestor_of(UI_Id(1), UI_Id(2)))
			testing.expect(t, !layout_is_ancestor_of(UI_Id(2), UI_Id(1)))
		},
	)
}

@(test)
widget_stop_propagation_sets_frame_flag :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			testing.expect(t, !w_ctx.pointer_propagation_stopped)
			stop_propagation()
			testing.expect(t, w_ctx.pointer_propagation_stopped)
			ui_begin_frame()
			testing.expect(t, !w_ctx.pointer_propagation_stopped)
		},
	)
}

@(test)
widget_pointer_hits_excludes_uncle_of_hit :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			ui_begin_frame()
			ui_push_style(style_root(.SCREEN, {0, 0, 800, 600}))
			defer ui_pop_style()

			_ = layout_push_node(
				UI_Id(1),
				{
					kind = .RECT,
					space = .SCREEN,
					direction = .HORIZONTAL,
					width = layout_len_fixed(200),
					height = layout_len_fixed(100),
				},
			)
			_ = layout_push_node(
				UI_Id(2),
				{kind = .RECT, space = .SCREEN, width = layout_len_fixed(100), height = layout_len_fixed(100)},
			)
			layout_pop_node()
			_ = layout_push_node(
				UI_Id(3),
				{kind = .RECT, space = .SCREEN, width = layout_len_fixed(100), height = layout_len_fixed(100)},
			)
			layout_pop_node()
			layout_pop_node()

			root_i := state.ui.layout.id_to_node[UI_Id(1)]
			a_i := state.ui.layout.id_to_node[UI_Id(2)]
			b_i := state.ui.layout.id_to_node[UI_Id(3)]
			state.ui.layout.nodes[root_i].rect = {0, 0, 200, 100}
			state.ui.layout.nodes[a_i].rect = {0, 0, 100, 100}
			state.ui.layout.nodes[b_i].rect = {100, 0, 100, 100}

			w_ctx.mouse_x = 20
			w_ctx.mouse_y = 20
			layout_finalize_stack_order()
			layout_resolve_pointer_hit()

			testing.expect(t, w_ctx.pointer_hit_ui_id == UI_Id(2))
			testing.expect(t, pointer_hits(UI_Id(1), state.ui.layout.nodes[root_i].rect, .SCREEN))
			testing.expect(t, pointer_hits(UI_Id(2), state.ui.layout.nodes[a_i].rect, .SCREEN))
			testing.expect(t, !pointer_hits(UI_Id(3), state.ui.layout.nodes[b_i].rect, .SCREEN))
			testing.expect(t, !layout_is_ancestor_of(UI_Id(3), UI_Id(2)))
		},
	)
}

@(test)
widget_pointer_hits_ancestor_when_child_overflows_parent_rect :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			ui_begin_frame()
			ui_push_style(style_root(.SCREEN, {0, 0, 800, 600}))
			defer ui_pop_style()

			_ = layout_push_node(
				UI_Id(1),
				{kind = .RECT, space = .SCREEN, width = layout_len_fixed(50), height = layout_len_fixed(50)},
			)
			_ = layout_push_node(
				UI_Id(2),
				{kind = .RECT, space = .SCREEN, width = layout_len_fixed(100), height = layout_len_fixed(100)},
			)
			layout_pop_node()
			layout_pop_node()

			parent_i := state.ui.layout.id_to_node[UI_Id(1)]
			child_i := state.ui.layout.id_to_node[UI_Id(2)]
			state.ui.layout.nodes[parent_i].rect = {0, 0, 50, 50}
			state.ui.layout.nodes[child_i].rect = {0, 0, 100, 100}

			// Pointer over child ink outside the parent's box.
			w_ctx.mouse_x = 80
			w_ctx.mouse_y = 20
			layout_finalize_stack_order()
			layout_resolve_pointer_hit()

			testing.expect(t, w_ctx.pointer_hit_ui_id == UI_Id(2))
			testing.expect(t, pointer_is_target(UI_Id(2)))
			testing.expect(t, pointer_hits(UI_Id(2), state.ui.layout.nodes[child_i].rect, .SCREEN))
			testing.expect(t, pointer_hits(UI_Id(1), state.ui.layout.nodes[parent_i].rect, .SCREEN))
			testing.expect(t, !pointer_over(state.ui.layout.nodes[parent_i].rect, .SCREEN))
		},
	)
}

@(test)
widget_pointer_hits_includes_deep_ancestor_chain :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			ui_begin_frame()
			ui_push_style(style_root(.SCREEN, {0, 0, 800, 600}))
			defer ui_pop_style()

			_ = layout_push_node(UI_Id(1), {kind = .RECT, space = .SCREEN})
			_ = layout_push_node(UI_Id(2), {kind = .RECT, space = .SCREEN})
			_ = layout_push_node(UI_Id(3), {kind = .RECT, space = .SCREEN})
			layout_pop_node()
			layout_pop_node()
			layout_pop_node()

			g_i := state.ui.layout.id_to_node[UI_Id(1)]
			p_i := state.ui.layout.id_to_node[UI_Id(2)]
			c_i := state.ui.layout.id_to_node[UI_Id(3)]
			state.ui.layout.nodes[g_i].rect = {0, 0, 100, 100}
			state.ui.layout.nodes[p_i].rect = {0, 0, 80, 80}
			state.ui.layout.nodes[c_i].rect = {10, 10, 40, 40}

			w_ctx.mouse_x = 20
			w_ctx.mouse_y = 20
			layout_finalize_stack_order()
			layout_resolve_pointer_hit()

			testing.expect(t, w_ctx.pointer_hit_ui_id == UI_Id(3))
			testing.expect(t, pointer_hits(UI_Id(3), state.ui.layout.nodes[c_i].rect, .SCREEN))
			testing.expect(t, pointer_hits(UI_Id(2), state.ui.layout.nodes[p_i].rect, .SCREEN))
			testing.expect(t, pointer_hits(UI_Id(1), state.ui.layout.nodes[g_i].rect, .SCREEN))
			testing.expect(t, layout_is_ancestor_of(UI_Id(1), UI_Id(3)))
			testing.expect(t, layout_is_ancestor_of(UI_Id(2), UI_Id(3)))
			testing.expect(t, !pointer_is_target(UI_Id(1)))
			testing.expect(t, !pointer_is_target(UI_Id(2)))
		},
	)
}

@(test)
widget_hover_transition_enter_leave_and_steady :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			entered, left := consume_hover_transition("el", true)
			testing.expect(t, entered && !left)

			entered, left = consume_hover_transition("el", true)
			testing.expect(t, !entered && !left)

			entered, left = consume_hover_transition("el", false)
			testing.expect(t, !entered && left)

			entered, left = consume_hover_transition("el", false)
			testing.expect(t, !entered && !left)
		},
	)
}

@(test)
widget_consume_pointer_click_requires_press_then_release_while_hovered :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			testing.expect(t, !consume_pointer_click("btn", true, true, false))
			testing.expect(t, w_ctx.element_pointer_down["btn"])

			testing.expect(t, consume_pointer_click("btn", true, false, true))
			testing.expect(t, !w_ctx.element_pointer_down["btn"])

			testing.expect(t, !consume_pointer_click("btn", true, true, false))
			testing.expect(t, !consume_pointer_click("btn", false, false, true))
		},
	)
}

@(test)
widget_prune_element_maps_removes_inactive_keys :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			register_tabbable("alive")
			w_ctx.focused_id = "focused"
			w_ctx.element_was_hovered = make(map[string]bool)
			w_ctx.element_pointer_down = make(map[string]bool)
			w_ctx.element_was_hovered["alive"] = true
			w_ctx.element_was_hovered["stale"] = true
			w_ctx.element_was_hovered["focused"] = true
			w_ctx.element_pointer_down["stale"] = true
			w_ctx.element_pointer_down["alive"] = true

			widget_prune_element_maps()
			testing.expect(t, w_ctx.element_was_hovered["alive"])
			testing.expect(t, w_ctx.element_was_hovered["focused"])
			_, stale_hover := w_ctx.element_was_hovered["stale"]
			testing.expect(t, !stale_hover)
			_, stale_down := w_ctx.element_pointer_down["stale"]
			testing.expect(t, !stale_down)
			testing.expect(t, w_ctx.element_pointer_down["alive"])
		},
	)
}

@(test)
widget_text_edit_caret_selection_api_round_trips :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			key := element_key("caret-api")
			plain := "hello"

			widget_text_edit_set_caret(key, plain, 2)
			testing.expect_value(t, widget_text_edit_caret(key), 2)
			sel := widget_text_edit_selection(key)
			testing.expect_value(t, sel.anchor, 2)
			testing.expect_value(t, sel.head, 2)

			widget_text_edit_set_selection(key, plain, {1, 4})
			testing.expect_value(t, widget_text_edit_caret(key), 4)
			sel = widget_text_edit_selection(key)
			testing.expect_value(t, sel.anchor, 1)
			testing.expect_value(t, sel.head, 4)

			widget_text_edit_set_caret(key, plain, 99)
			testing.expect_value(t, widget_text_edit_caret(key), len(plain))

			widget_text_edit_set_selection(key, plain, {-1, 100})
			sel = widget_text_edit_selection(key)
			testing.expect_value(t, sel.anchor, 0)
			testing.expect_value(t, sel.head, len(plain))
		},
	)
}

@(test)
widget_ctx_shutdown_releases_maps :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			register_tabbable("a")
			_ = element_key("b")
			_, _ = consume_hover_transition("a", true)
			_ = consume_pointer_click("a", true, true, false)

			key := element_key("edit-field")
			edit := widget_text_edit_ensure(key)
			testing.expect(t, edit != nil)
			text_edit_undo_push(&edit.undo, "undo", 4, {}, 1)

			widget_ctx_shutdown()
			testing.expect(t, w_ctx.tab_order == nil)
			testing.expect(t, w_ctx.static_ids == nil)
			testing.expect(t, w_ctx.element_was_hovered == nil)
			testing.expect(t, w_ctx.element_pointer_down == nil)
			testing.expect(t, w_ctx.text_edit_states == nil)
			testing.expect_value(t, w_ctx.focused_id, "")

			// Restore maps so with_ui_env defer can shut down cleanly.
			ui_init()
		},
	)
}

@(test)
widget_resolve_padding_variants :: proc(t: ^testing.T) {
	expect_pd(t, resolve_padding_xy(4, 0), {4, 4, 4, 4})
	expect_pd(t, resolve_padding_xy(3, 5), {5, 5, 3, 3})

	p, ok := resolve_padding_value(f32(0))
	testing.expect(t, !ok)

	p, ok = resolve_padding_value(f32(8))
	testing.expect(t, ok)
	expect_pd(t, p, {8, 8, 8, 8})

	p, ok = resolve_padding_value(Inherit.INHERIT, {1, 2, 3, 4})
	testing.expect(t, ok)
	expect_pd(t, p, {1, 2, 3, 4})

	p, ok = resolve_padding_value(struct{}{})
	testing.expect(t, !ok)

	p, ok = resolve_padding_value(Pd_pos{x = 6, y = 2})
	testing.expect(t, ok)
	expect_pd(t, p, {2, 2, 6, 6})

	p, ok = resolve_padding_value(Pd{t = 1, b = 2, l = 3, r = 4})
	testing.expect(t, ok)
	expect_pd(t, p, {1, 2, 3, 4})

	p, ok = resolve_padding_value(Pd_struct{sm = true})
	testing.expect(t, ok)
	expect_pd(t, p, {PADDING_SM, PADDING_SM, PADDING_SM, PADDING_SM})

	p, ok = resolve_padding_value(Pd_struct{md = true})
	testing.expect(t, ok)
	expect_pd(t, p, {PADDING_MD, PADDING_MD, PADDING_MD, PADDING_MD})

	p, ok = resolve_padding_value(Pd_struct{lg = true})
	testing.expect(t, ok)
	expect_pd(t, p, {PADDING_LG, PADDING_LG, PADDING_LG, PADDING_LG})

	p, ok = resolve_padding_value(Pd_struct{xl = true})
	testing.expect(t, ok)
	expect_pd(t, p, {PADDING_XL, PADDING_XL, PADDING_XL, PADDING_XL})

	p, ok = resolve_padding_value(Pd_struct{t = 9, r = 8})
	testing.expect(t, ok)
	expect_pd(t, p, {9, 0, 0, 8})

	p, ok = resolve_padding_value(Pd_struct{x = 4, y = 7})
	testing.expect(t, ok)
	expect_pd(t, p, {7, 7, 4, 4})

	parent := Pd_px{t = 10, b = 20, l = 30, r = 40}
	p, ok = resolve_padding_value(Pd_struct{t = .INHERIT, l = .INHERIT}, parent)
	testing.expect(t, ok)
	expect_pd(t, p, {10, 0, 30, 0})
}

@(test)
widget_resolve_radius_variants :: proc(t: ^testing.T) {
	r, ok := resolve_radius_value(f32(0))
	testing.expect(t, !ok)

	r, ok = resolve_radius_value(f32(5))
	testing.expect(t, ok)
	expect_radius(t, r, {5, 5, 5, 5})

	r, ok = resolve_radius_value(Inherit.INHERIT, {1, 2, 3, 4})
	testing.expect(t, ok)
	expect_radius(t, r, {1, 2, 3, 4})

	r, ok = resolve_radius_value(struct{}{})
	testing.expect(t, !ok)

	r, ok = resolve_radius_value(Radius_struct{sm = true})
	testing.expect(t, ok)
	expect_radius(t, r, {RADIUS_SM, RADIUS_SM, RADIUS_SM, RADIUS_SM})

	r, ok = resolve_radius_value(Radius_struct{md = true})
	testing.expect(t, ok)
	expect_radius(t, r, {RADIUS_MD, RADIUS_MD, RADIUS_MD, RADIUS_MD})

	r, ok = resolve_radius_value(Radius_struct{lg = true})
	testing.expect(t, ok)
	expect_radius(t, r, {RADIUS_LG, RADIUS_LG, RADIUS_LG, RADIUS_LG})

	r, ok = resolve_radius_value(Radius_struct{xl = true})
	testing.expect(t, ok)
	expect_radius(t, r, {RADIUS_XL, RADIUS_XL, RADIUS_XL, RADIUS_XL})

	r, ok = resolve_radius_value(Radius_struct{tl = 1, br = 4})
	testing.expect(t, ok)
	expect_radius(t, r, {1, 0, 0, 4})

	r, ok = resolve_radius_value(Radius_struct{t = 3, b = 6})
	testing.expect(t, ok)
	expect_radius(t, r, {3, 3, 6, 6})

	r, ok = resolve_radius_value(Radius_struct{l = 2, r = 8})
	testing.expect(t, ok)
	expect_radius(t, r, {2, 8, 2, 8})

	r, ok = resolve_radius_value(Radius_struct{x = 4, y = 9})
	testing.expect(t, ok)
	expect_radius(t, r, {4, 4, 9, 9})

	r, ok = resolve_radius_value(Radius_corners{tl = 1, tr = 2, bl = 3, br = 4})
	testing.expect(t, ok)
	expect_radius(t, r, {1, 2, 3, 4})

	r, ok = resolve_radius_value(Radius_corners{})
	testing.expect(t, !ok)

	corners := radius_px_to_corners({1, 2, 3, 4})
	expect_close(t, f32_i_px(corners.tl), 1)
	expect_close(t, f32_i_px(corners.br), 4)
}

@(test)
widget_resolve_border_variants :: proc(t: ^testing.T) {
	b, ok := resolve_border_value(f32(0))
	testing.expect(t, !ok)

	b, ok = resolve_border_value(f32(2))
	testing.expect(t, ok)
	expect_bd(t, b, {2, 2, 2, 2})

	b, ok = resolve_border_value(Inherit.INHERIT, {1, 2, 3, 4})
	testing.expect(t, ok)
	expect_bd(t, b, {1, 2, 3, 4})

	b, ok = resolve_border_value(struct{}{})
	testing.expect(t, !ok)

	b, ok = resolve_border_value(Bd{t = 1, b = 2, l = 3, r = 4})
	testing.expect(t, ok)
	expect_bd(t, b, {1, 2, 3, 4})

	b, ok = resolve_border_value(Bd_struct{sm = true})
	testing.expect(t, ok)
	expect_bd(t, b, {BORDER_SM, BORDER_SM, BORDER_SM, BORDER_SM})

	b, ok = resolve_border_value(Bd_struct{md = true})
	testing.expect(t, ok)
	expect_bd(t, b, {BORDER_MD, BORDER_MD, BORDER_MD, BORDER_MD})

	b, ok = resolve_border_value(Bd_struct{lg = true})
	testing.expect(t, ok)
	expect_bd(t, b, {BORDER_LG, BORDER_LG, BORDER_LG, BORDER_LG})

	b, ok = resolve_border_value(Bd_struct{xl = true})
	testing.expect(t, ok)
	expect_bd(t, b, {BORDER_XL, BORDER_XL, BORDER_XL, BORDER_XL})

	b, ok = resolve_border_value(Bd_struct{})
	testing.expect(t, !ok)

	parent := Bd_px{t = 9, b = 8, l = 7, r = 6}
	b, ok = resolve_border_value(Bd_struct{t = .INHERIT, r = .INHERIT}, parent)
	testing.expect(t, ok)
	expect_bd(t, b, {9, 0, 0, 6})

	bd := border_px_to_bd({1, 2, 3, 4})
	expect_close(t, f32_i_px(bd.t), 1)
	expect_close(t, f32_i_px(bd.r), 4)
	pd := padding_px_to_pd({5, 6, 7, 8})
	expect_close(t, f32_i_px(pd.b), 6)
	expect_close(t, f32_i_px(pd.l), 7)
}

@(test)
widget_resolve_gap_direction_justify :: proc(t: ^testing.T) {
	g, ok := resolve_gap_x_value(u16(12))
	testing.expect(t, ok)
	testing.expect_value(t, g, u16(12))
	_, ok = resolve_gap_x_value(struct{}{})
	testing.expect(t, !ok)
	_, ok = resolve_gap_x_value(Inherit.INHERIT)
	testing.expect(t, !ok)

	gy, yok := resolve_gap_y_value(u16(4))
	testing.expect(t, yok)
	testing.expect_value(t, gy, u16(4))

	d, dok := resolve_direction_value(Direction_Layout.VERTICAL)
	testing.expect(t, dok)
	testing.expect(t, d == .VERTICAL)
	_, dok = resolve_direction_value(struct{}{})
	testing.expect(t, !dok)

	align, aok := resolve_justify_value(Justify_Align.CENTER)
	testing.expect(t, aok)
	testing.expect(t, align.x == Justify_Align.CENTER)
	testing.expect(t, align.y == Justify_Align.CENTER)

	align, aok = resolve_align_pos({x = Justify_Align.END, y = Justify_Align.START})
	testing.expect(t, aok)
	testing.expect(t, align.x == Justify_Align.END)
	testing.expect(t, align.y == Justify_Align.START)

	partial, pok := resolve_justify_pos_partial({x = Justify_Align.CENTER})
	testing.expect(t, pok)
	testing.expect(t, partial.x == Justify_Align.CENTER)

	_, aok = resolve_justify_value(struct{}{})
	testing.expect(t, !aok)
}

@(test)
widget_justify_align_helpers :: proc(t: ^testing.T) {
	testing.expect(t, justify_align_is_space(.SPACE_BETWEEN))
	testing.expect(t, justify_align_is_space(.SPACE_AROUND))
	testing.expect(t, justify_align_is_space(.SPACE_EVENLY))
	testing.expect(t, !justify_align_is_space(.CENTER))

	testing.expect(t, justify_align_is_content(.MAX_CONTENT))
	testing.expect(t, justify_align_is_content(.MIN_CONTENT))
	testing.expect(t, !justify_align_is_content(.START))

	expect_close(t, justify_align_position_offset(100, 40, .START), 0)
	expect_close(t, justify_align_position_offset(100, 40, .CENTER), 30)
	expect_close(t, justify_align_position_offset(100, 40, .END), 60)
	expect_close(t, justify_align_position_offset(10, 40, .CENTER), 0)

	expect_close(t, justify_align_position_offset_x(80, 20, Justify_Align.END), 60)
	expect_close(t, justify_align_position_offset_y(80, 20, Justify_Align.CENTER), 30)
	expect_close(t, justify_align_position_offset_x(80, 20, struct{}{}), 0)

	testing.expect(t, justify_axis_is_stretch_y(Justify_Align.STRETCH))
	testing.expect(t, !justify_axis_is_stretch_y(Justify_Align.START))
	testing.expect(t, justify_axis_is_stretch_x(Justify_Align.STRETCH))
	testing.expect(t, !justify_axis_is_stretch_x(struct{}{}))

	ax, ax_ok := justify_align_from_x(Justify_Align.END)
	testing.expect(t, ax_ok)
	testing.expect(t, ax == .END)
	_, ax_ok = justify_align_from_x(struct{}{})
	testing.expect(t, !ax_ok)
}

@(test)
widget_resolve_texture_pos_and_fit :: proc(t: ^testing.T) {
	pos, ok := resolve_texture_pos_value(struct{}{})
	testing.expect(t, ok)
	expect_close(t, pos.x, 0.5)
	expect_close(t, pos.y, 0.5)

	_, ok = resolve_texture_pos_value(Inherit.INHERIT)
	testing.expect(t, !ok)

	pos, ok = resolve_texture_pos_value(Texture_Pos{l = 10, t = 5})
	testing.expect(t, ok)
	expect_close(t, pos.x, 0)
	expect_close(t, pos.offset_x, 10)
	expect_close(t, pos.y, 0)
	expect_close(t, pos.offset_y, 5)

	pos, ok = resolve_texture_pos_value(Texture_Pos{r = 8, b = 4})
	testing.expect(t, ok)
	expect_close(t, pos.x, 1)
	expect_close(t, pos.offset_x, -8)
	expect_close(t, pos.y, 1)
	expect_close(t, pos.offset_y, -4)

	pos, ok = resolve_texture_pos_value(Texture_Pos_X_Y{x = 50, y = 25})
	testing.expect(t, ok)
	expect_close(t, pos.x, 0.5)
	expect_close(t, pos.y, 0.25)

	pos, ok = resolve_texture_pos_value(Texture_Pos_X_Y{x = 0.2, y = 0.8})
	testing.expect(t, ok)
	expect_close(t, pos.x, 0.2)
	expect_close(t, pos.y, 0.8)

	explicit := Resolved_Texture_Pos{0.1, 0.9, 2, -3}
	pos, ok = resolve_texture_pos_value(explicit)
	testing.expect(t, ok)
	expect_close(t, pos.offset_x, 2)

	fit, fok := resolve_texture_fit_value(Texture_Fit.COVER)
	testing.expect(t, fok)
	testing.expect(t, fit == .COVER)
	_, fok = resolve_texture_fit_value(struct{}{})
	testing.expect(t, !fok)
	_, fok = resolve_texture_fit_value(Inherit.INHERIT)
	testing.expect(t, !fok)
}

@(test)
widget_texture_fit_rects_all_modes :: proc(t: ^testing.T) {
	src := Rect{0, 0, 100, 50}
	container := Rect{10, 20, 200, 200}
	pos := Resolved_Texture_Pos{0.5, 0.5, 0, 0}

	out_src, out_dst := texture_fit_rects(src, container, .FILL, pos)
	expect_rect(t, out_src, src)
	expect_rect(t, out_dst, container)

	_, dst := texture_fit_rects(src, container, .CONTAIN, pos)
	expect_close(t, dst.w, 200)
	expect_close(t, dst.h, 100)
	expect_close(t, dst.x, 10)
	expect_close(t, dst.y, 70)

	cover_src, cover_dst := texture_fit_rects(src, container, .COVER, pos)
	expect_rect(t, cover_dst, container)
	expect_close(t, cover_src.w, 50)
	expect_close(t, cover_src.h, 50)

	_, none_dst := texture_fit_rects(src, container, .NONE, pos)
	expect_close(t, none_dst.w, 100)
	expect_close(t, none_dst.h, 50)

	_, scale_ok := texture_fit_rects(src, container, .SCALE_DOWN, pos)
	expect_close(t, scale_ok.w, 100)
	expect_close(t, scale_ok.h, 50)

	big := Rect{0, 0, 400, 400}
	_, scale_big := texture_fit_rects(big, container, .SCALE_DOWN, pos)
	testing.expect(t, scale_big.w <= container.w + 0.01)
	testing.expect(t, scale_big.h <= container.h + 0.01)

	empty_src, empty_dst := texture_fit_rects({}, container, .CONTAIN, pos)
	expect_rect(t, empty_src, {})
	expect_rect(t, empty_dst, container)
}

@(test)
widget_lifecycle_entry_and_remove :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			state.ui.frame = 7
			id := UI_Id(42)
			entry := widget_lifecycle_entry(id)
			testing.expect_value(t, entry.last_frame, u64(7))
			testing.expect(t, id in state.ui.widgets)

			entry.last_frame = 1
			again := widget_lifecycle_entry(id)
			testing.expect_value(t, again.last_frame, u64(7))

			widget_lifecycle_remove(id)
			testing.expect(t, !(id in state.ui.widgets))

			widget_lifecycle_remove(UI_Id(999))
		},
	)
}

@(test)
widget_resolve_with_proc_callbacks :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			frame, event := ui_test_frame_event()

			pad_proc :: proc(
				frame_state: Widget_Frame_State,
				event: Widget_Event(Widget_Frame_State),
			) -> Padding {
				_ = frame_state
				_ = event
				return f32(11)
			}
			padding, pok := resolve_padding(Padding(pad_proc), &frame, event)
			testing.expect(t, pok)
			expect_pd(t, padding, {11, 11, 11, 11})

			radius_proc :: proc(
				frame_state: Widget_Frame_State,
				event: Widget_Event(Widget_Frame_State),
			) -> Radius {
				_ = frame_state
				_ = event
				return f32(7)
			}
			radius, rok := resolve_radius(Radius(radius_proc), &frame, event)
			testing.expect(t, rok)
			expect_radius(t, radius, {7, 7, 7, 7})

			border_proc :: proc(
				frame_state: Widget_Frame_State,
				event: Widget_Event(Widget_Frame_State),
			) -> Border {
				_ = frame_state
				_ = event
				return f32(3)
			}
			border, bok := resolve_border(Border(border_proc), &frame, event)
			testing.expect(t, bok)
			expect_bd(t, border, {3, 3, 3, 3})

			gap_proc :: proc(
				frame_state: Widget_Frame_State,
				event: Widget_Event(Widget_Frame_State),
			) -> Gap_X {
				_ = frame_state
				_ = event
				return u16(15)
			}
			gap, gok := resolve_child_gap_x(Gap_X(gap_proc), &frame, event)
			testing.expect(t, gok)
			testing.expect_value(t, gap, u16(15))

			gap_y_proc :: proc(
				frame_state: Widget_Frame_State,
				event: Widget_Event(Widget_Frame_State),
			) -> Gap_Y {
				_ = frame_state
				_ = event
				return u16(9)
			}
			gap_y, gyok := resolve_child_gap_y(Gap_Y(gap_y_proc), &frame, event)
			testing.expect(t, gyok)
			testing.expect_value(t, gap_y, u16(9))

			justify_proc :: proc(
				frame_state: Widget_Frame_State,
				event: Widget_Event(Widget_Frame_State),
			) -> Justify {
				_ = frame_state
				_ = event
				return Justify_Align.END
			}
			align, aok := resolve_align(Justify(justify_proc), &frame, event)
			testing.expect(t, aok)
			testing.expect(t, align.x == Justify_Align.END)

			dir_proc :: proc(
				frame_state: Widget_Frame_State,
				event: Widget_Event(Widget_Frame_State),
			) -> Widget_Direction {
				_ = frame_state
				_ = event
				return Direction_Layout.HORIZONTAL
			}
			dir, dok := resolve_direction(Widget_Direction(dir_proc), &frame, event)
			testing.expect(t, dok)
			testing.expect(t, dir == Direction_Layout.HORIZONTAL)

			fit_proc :: proc(
				frame_state: Widget_Frame_State,
				event: Widget_Event(Widget_Frame_State),
			) -> Texture_Fit {
				_ = frame_state
				_ = event
				return .CONTAIN
			}
			fit, fok := resolve_texture_fit(Style_Texture_Fit(fit_proc), &frame, event)
			testing.expect(t, fok)
			testing.expect(t, fit == .CONTAIN)

			pos_proc :: proc(
				frame_state: Widget_Frame_State,
				event: Widget_Event(Widget_Frame_State),
			) -> Texture_Pos {
				_ = frame_state
				_ = event
				return Texture_Pos{l = 2}
			}
			pos, pos_ok := resolve_texture_pos(Style_Texture_Pos(pos_proc), &frame, event)
			testing.expect(t, pos_ok)
			expect_close(t, pos.x, 0)
			expect_close(t, pos.offset_x, 2)
		},
	)
}

@(test)
widget_pointer_over_artboard_applies_view_transform :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			// Default view: pan=0 zoom=1 → screen == world.
			w_ctx.mouse_x = 25
			w_ctx.mouse_y = 35
			rect := Rect{20, 30, 40, 20}
			testing.expect(t, pointer_over(rect, .ARTBOARD))

			// Zoom 2x: screen (50, 70) → world (25, 35).
			view_set_zoom(2)
			w_ctx.mouse_x = 50
			w_ctx.mouse_y = 70
			testing.expect(t, pointer_over(rect, .ARTBOARD))
			testing.expect(t, !pointer_over(rect, .SCREEN))

			// Pan shifts world origin: screen - pan / zoom.
			view_set_pan({10, 20})
			// world = (50-10)/2, (70-20)/2 = (20, 25) — left edge of rect (x>=20, y>=30 fails).
			testing.expect(t, !pointer_over(rect, .ARTBOARD))
			w_ctx.mouse_y = 80 // world y = (80-20)/2 = 30
			testing.expect(t, pointer_over(rect, .ARTBOARD))
		},
	)
}

@(test)
widget_to_ui_state_and_event_preserve_frame_fields :: proc(t: ^testing.T) {
	frame := Widget_Frame_State {
		is_hovered = true,
		is_focused = true,
		is_left_clicked = true,
		is_disabled = true,
	}
	got := to_ui_state(&frame)
	testing.expect(t, got.is_hovered)
	testing.expect(t, got.is_focused)
	testing.expect(t, got.is_left_clicked)
	testing.expect(t, got.is_disabled)

	event := to_ui_event(&frame)
	testing.expect(t, event.frame_state.is_hovered)
	testing.expect(t, event.frame_state.is_focused)
	testing.expect(t, event.frame_state.is_left_clicked)
	testing.expect(t, event.frame_state.is_disabled)
}

@(test)
widget_resolve_uses_style_stack_parent_insets :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			frame, event := ui_test_frame_event()

			parent := resolve_widget_config(
				{},
				{
					padding = {mode = .Value, value = f32(12)},
					radius = {mode = .Value, value = f32(8)},
					border = {mode = .Value, value = f32(3)},
				},
				&frame,
				event,
			)
			ui_push_style(style_child_context(parent))
			defer ui_pop_style()

			pad, pok := resolve_padding(Padding(Inherit.INHERIT), &frame, event)
			testing.expect(t, pok)
			expect_pd(t, pad, {12, 12, 12, 12})

			rad, rok := resolve_radius(Radius(Inherit.INHERIT), &frame, event)
			testing.expect(t, rok)
			expect_radius(t, rad, {8, 8, 8, 8})

			bd, bok := resolve_border(Border(Inherit.INHERIT), &frame, event)
			testing.expect(t, bok)
			expect_bd(t, bd, {3, 3, 3, 3})

			// Explicit values still resolve; .INHERIT side fields pull parent.
			pad2, pok2 := resolve_padding(
				Padding(Pd_struct{t = .INHERIT, l = 4}),
				&frame,
				event,
			)
			testing.expect(t, pok2)
			expect_pd(t, pad2, {12, 0, 4, 0})
		},
	)
}

@(test)
widget_sync_input_nil_state_and_all_mouse_buttons :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			saved := state
			state = nil
			w_ctx.mouse_x = 1
			sync_widget_input()
			expect_close(t, w_ctx.mouse_x, 1) // unchanged when state is nil
			state = saved
			widget_ctx_sync()

			state.input.mouse_left = true
			state.input.mouse_right = true
			state.input.mouse_middle = true
			sync_widget_input()
			testing.expect(t, w_ctx.left_mouse.pressed && w_ctx.left_mouse.down)
			testing.expect(t, w_ctx.right_mouse.pressed && w_ctx.right_mouse.down)
			testing.expect(t, w_ctx.middle_mouse.pressed && w_ctx.middle_mouse.down)

			clear_button_transients(&w_ctx.left_mouse)
			clear_button_transients(&w_ctx.right_mouse)
			clear_button_transients(&w_ctx.middle_mouse)
			state.input.mouse_left = false
			state.input.mouse_right = false
			state.input.mouse_middle = false
			sync_widget_input()
			testing.expect(t, w_ctx.left_mouse.released && !w_ctx.left_mouse.down)
			testing.expect(t, w_ctx.right_mouse.released && !w_ctx.right_mouse.down)
			testing.expect(t, w_ctx.middle_mouse.released && !w_ctx.middle_mouse.down)
		},
	)
}

@(test)
widget_padding_empty_pos_and_proc_static_value :: proc(t: ^testing.T) {
	p, ok := resolve_padding_value(Pd_pos{})
	testing.expect(t, !ok)

	// Explicit f32(0) is "set" for F32_I; resolves to zero padding.
	p, ok = resolve_padding_value(Pd_pos{x = 0, y = 0})
	testing.expect(t, ok)
	expect_pd(t, p, {})

	p, ok = resolve_padding_value(Pd_pos{x = 5})
	testing.expect(t, ok)
	expect_pd(t, p, {5, 5, 5, 5}) // y unset (nil) → 0 → uniform from x

	// Static resolve_padding_value rejects proc-valued padding.
	pad_proc :: proc(
		frame_state: Widget_Frame_State,
		event: Widget_Event(Widget_Frame_State),
	) -> Padding {
		_ = frame_state
		_ = event
		return f32(1)
	}
	_, ok = resolve_padding_value(Padding(pad_proc))
	testing.expect(t, !ok)
}

@(test)
widget_radius_axis_and_corner_override_precedence :: proc(t: ^testing.T) {
	// Axis-only: t/b set top and bottom corners.
	r, ok := resolve_radius_struct(Radius_struct{t = 5, b = 9})
	testing.expect(t, ok)
	expect_radius(t, r, {5, 5, 9, 9})

	// Explicit corners take the early path and ignore axis fields.
	r, ok = resolve_radius_struct(Radius_struct{tl = 1, tr = 2, t = 99})
	testing.expect(t, ok)
	expect_radius(t, r, {1, 2, 0, 0})

	// Axis fills only unset corners when any_corner is false.
	r, ok = resolve_radius_struct(Radius_struct{t = 7, l = 3})
	testing.expect(t, ok)
	// t sets tl/tr; l then overrides tl/bl because those corners aren't explicitly set.
	expect_close(t, r.tl, 3)
	expect_close(t, r.tr, 7)
	expect_close(t, r.bl, 3)
	expect_close(t, r.br, 0)

	parent := Radius_px{tl = 10, tr = 20, bl = 30, br = 40}
	r, ok = resolve_radius_corners(
		Radius_corners{tl = .INHERIT, br = .INHERIT},
		parent,
	)
	testing.expect(t, ok)
	expect_radius(t, r, {10, 0, 0, 40})
}

@(test)
widget_texture_pos_conflicting_sides_and_normalize :: proc(t: ^testing.T) {
	// Both horizontal sides set → neither exclusive branch fires; stays centered.
	pos, ok := resolve_texture_pos_value(Texture_Pos{l = 4, r = 4})
	testing.expect(t, ok)
	expect_close(t, pos.x, 0.5)
	expect_close(t, pos.offset_x, 0)

	pos, ok = resolve_texture_pos_value(Texture_Pos{t = 3, b = 3})
	testing.expect(t, ok)
	expect_close(t, pos.y, 0.5)
	expect_close(t, pos.offset_y, 0)

	// Percent-style X/Y (>1) normalize to 0–1.
	pos, ok = resolve_texture_pos_value(Texture_Pos_X_Y{x = 100, y = 0})
	testing.expect(t, ok)
	expect_close(t, pos.x, 1)
	expect_close(t, pos.y, 0)

	expect_close(t, texture_pos_normalize(50), 0.5)
	expect_close(t, texture_pos_normalize(0.25), 0.25)
	expect_close(t, texture_pos_normalize(1), 1)
}

@(test)
widget_texture_fit_rects_honor_anchor_offsets :: proc(t: ^testing.T) {
	src := Rect{0, 0, 100, 50}
	container := Rect{0, 0, 200, 200}

	centered := Resolved_Texture_Pos{0.5, 0.5, 0, 0}
	_, contain := texture_fit_rects(src, container, .CONTAIN, centered)
	expect_close(t, contain.x, 0)
	expect_close(t, contain.y, 50)

	offset := Resolved_Texture_Pos{0.5, 0.5, 10, -20}
	_, contain_off := texture_fit_rects(src, container, .CONTAIN, offset)
	expect_close(t, contain_off.x, 10)
	expect_close(t, contain_off.y, 30)

	_, none_off := texture_fit_rects(src, container, .NONE, offset)
	expect_close(t, none_off.x, 50 + 10)
	expect_close(t, none_off.y, 75 - 20)

	cover_src, _ := texture_fit_rects(src, container, .COVER, offset)
	// COVER crops source; offset adjusts crop origin by -offset/scale.
	testing.expect(t, cover_src.w > 0 && cover_src.h > 0)
	plain_src, _ := texture_fit_rects(src, container, .COVER, centered)
	testing.expect(t, cover_src.x != plain_src.x || cover_src.y != plain_src.y)
}

@(test)
widget_prune_keeps_static_id_mapped_keys :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			key := element_key("named")
			w_ctx.element_was_hovered = make(map[string]bool)
			w_ctx.element_pointer_down = make(map[string]bool)
			w_ctx.element_was_hovered[key] = true
			w_ctx.element_pointer_down[key] = true
			w_ctx.element_was_hovered["orphan"] = true

			// Not in tab order or focus — kept only via static_ids mapping.
			testing.expect(t, len(w_ctx.tab_order) == 0)
			testing.expect_value(t, w_ctx.focused_id, "")

			widget_prune_element_maps()
			testing.expect(t, w_ctx.element_was_hovered[key])
			testing.expect(t, w_ctx.element_pointer_down[key])
			_, orphan := w_ctx.element_was_hovered["orphan"]
			testing.expect(t, !orphan)
		},
	)
}

@(test)
widget_process_tab_ignores_unpressed_and_empty :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			register_tabbable("a")
			w_ctx.focused_id = "a"
			w_ctx.keys[int(Scancode.TAB)].pressed = false
			widget_process_tab_navigation()
			testing.expect_value(t, w_ctx.focused_id, "a")

			// Empty tab order: pressed Tab is a no-op.
			clear(&w_ctx.tab_order)
			w_ctx.keys[int(Scancode.TAB)].pressed = true
			widget_process_tab_navigation()
			testing.expect_value(t, w_ctx.focused_id, "a")
		},
	)
}

@(test)
widget_focus_tab_starts_from_end_when_reverse_and_unfocused :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			register_tabbable("a")
			register_tabbable("b")
			register_tabbable("c")
			w_ctx.focused_id = ""
			testing.expect(t, widget_focus_tab(true))
			testing.expect_value(t, w_ctx.focused_id, "c")
		},
	)
}

@(test)
widget_resolve_gap_and_direction_static_reject_procs :: proc(t: ^testing.T) {
	gap_x_proc :: proc(
		frame_state: Widget_Frame_State,
		event: Widget_Event(Widget_Frame_State),
	) -> Gap_X {
		_ = frame_state
		_ = event
		return u16(1)
	}
	_, ok := resolve_gap_x_value(Gap_X(gap_x_proc))
	testing.expect(t, !ok)

	gap_y_proc :: proc(
		frame_state: Widget_Frame_State,
		event: Widget_Event(Widget_Frame_State),
	) -> Gap_Y {
		_ = frame_state
		_ = event
		return u16(1)
	}
	_, ok = resolve_gap_y_value(Gap_Y(gap_y_proc))
	testing.expect(t, !ok)

	_, ok = resolve_direction_value(Widget_Direction(Inherit.INHERIT))
	testing.expect(t, !ok)

	_, ok = resolve_justify_value(Justify(Inherit.INHERIT))
	testing.expect(t, !ok)

	_, ok = resolve_align_pos({x = struct{}{}, y = Justify_Align.CENTER})
	testing.expect(t, !ok)

	partial, pok := resolve_justify_pos_partial({})
	testing.expect(t, !pok)
	_ = partial
}

@(private)
widget_callback_saw_hovered: bool
@(private)
widget_callback_saw_focused: bool

@(private)
widget_gap_callback_probe :: proc(
	frame_state: Widget_Frame_State,
	event: Widget_Event(Widget_Frame_State),
) -> Padding {
	widget_callback_saw_hovered = frame_state.is_hovered
	widget_callback_saw_focused = event.frame_state.is_focused
	return f32(4)
}

@(test)
widget_resolve_padding_callback_sees_typed_frame_state :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			frame := Widget_Frame_State {
				is_hovered = true,
				is_focused = true,
			}
			event := Widget_Event(Widget_Frame_State) {
				frame_state = frame,
			}
			widget_callback_saw_hovered = false
			widget_callback_saw_focused = false

			pad, ok := resolve_padding(Padding(widget_gap_callback_probe), &frame, event)
			testing.expect(t, ok)
			expect_pd(t, pad, {4, 4, 4, 4})
			testing.expect(t, widget_callback_saw_hovered)
			testing.expect(t, widget_callback_saw_focused)
		},
	)
}

@(test)
widget_border_struct_inherit_and_empty :: proc(t: ^testing.T) {
	b, ok := resolve_border_struct(Bd_struct{})
	testing.expect(t, !ok)

	parent := Bd_px{t = 5, b = 6, l = 7, r = 8}
	b, ok = resolve_border_struct(Bd_struct{t = .INHERIT, b = 1, l = .INHERIT}, parent)
	testing.expect(t, ok)
	expect_bd(t, b, {5, 1, 7, 0})
}

@(test)
widget_justify_space_offsets_are_zero :: proc(t: ^testing.T) {
	expect_close(t, justify_align_position_offset(100, 20, .SPACE_BETWEEN), 0)
	expect_close(t, justify_align_position_offset(100, 20, .SPACE_AROUND), 0)
	expect_close(t, justify_align_position_offset(100, 20, .SPACE_EVENLY), 0)
	expect_close(t, justify_align_position_offset(100, 20, .STRETCH), 0)
	expect_close(t, justify_align_position_offset(100, 20, .TABLE_CELL), 0)
}

@(test)
widget_texture_fit_value_and_fit_proc_reject_static :: proc(t: ^testing.T) {
	fit_proc :: proc(
		frame_state: Widget_Frame_State,
		event: Widget_Event(Widget_Frame_State),
	) -> Texture_Fit {
		_ = frame_state
		_ = event
		return .FILL
	}
	_, ok := resolve_texture_fit_value(Style_Texture_Fit(fit_proc))
	testing.expect(t, !ok)

	pos_proc :: proc(
		frame_state: Widget_Frame_State,
		event: Widget_Event(Widget_Frame_State),
	) -> Texture_Pos {
		_ = frame_state
		_ = event
		return Texture_Pos{l = 1}
	}
	_, ok = resolve_texture_pos_value(Style_Texture_Pos(pos_proc))
	testing.expect(t, !ok)
}

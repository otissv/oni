package oni

import "core:testing"

@(test)
ui_init_is_idempotent_and_allocates_maps :: proc(t: ^testing.T) {
	test_state: State

	with_test_global_state(
		&test_state,
		proc(test_state: ^State, t: ^testing.T) {
			testing.expect(t, state == test_state)

			ui_init()
			// Freshly made maps compare equal to nil until first insert in this
			// Odin version; verify allocation by writing and reading back.
			state.ui.widgets[UI_Id(1)] = {}
			testing.expect(t, UI_Id(1) in state.ui.widgets)
			state.ui.layout.id_to_node[UI_Id(2)] = 0
			testing.expect(t, UI_Id(2) in state.ui.layout.id_to_node)
			state.ui.layout_ids_prev[UI_Id(3)] = true
			testing.expect(t, state.ui.layout_ids_prev[UI_Id(3)])
			state.ui.layout_ids_snapshot[UI_Id(4)] = true
			testing.expect(t, state.ui.layout_ids_snapshot[UI_Id(4)])
			state.ui.layout.table_tracks[0] = {}
			testing.expect(t, 0 in state.ui.layout.table_tracks)

			ui_init()
			testing.expect(t, UI_Id(1) in state.ui.widgets)

			ui_shutdown()
			testing.expect(t, !(UI_Id(1) in state.ui.widgets))
			testing.expect(t, state.ui.widgets == nil)
		},
		t,
	)
}

@(test)
ui_begin_frame_increments_and_resets_transient_state :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			state.ui.layout_ids_snapshot[UI_Id(7)] = true
			register_tabbable("a")
			_ = element_key("x")
			w_ctx.auto_element_index = 9
			w_ctx.mouse_moved = true
			w_ctx.tab_focus_changed = true
			w_ctx.tab_focus_previous_id = "prev"
			ui_push_scope(UI_Id(1))

			ui_begin_frame()
			testing.expect_value(t, state.ui.frame, u64(1))
			testing.expect(t, state.ui.pass == .Layout)
			testing.expect(t, state.ui.layout_ids_prev[UI_Id(7)])
			testing.expect_value(t, len(state.ui.scope_stack), 0)
			testing.expect_value(t, len(state.ui.style_stack), 0)
			testing.expect_value(t, w_ctx.auto_element_index, u32(0))
			testing.expect_value(t, len(w_ctx.tab_order), 0)
			testing.expect(t, !w_ctx.mouse_moved)
			testing.expect(t, !w_ctx.tab_focus_changed)
			testing.expect_value(t, w_ctx.tab_focus_previous_id, "")

			ui_push_style(style_root(.SCREEN, {0, 0, 800, 600}))
		},
	)
}

@(test)
ui_end_layout_pass_snapshots_and_switches_to_draw :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			ui_begin_frame()
			ui_push_style(style_root(.SCREEN, {0, 0, 800, 600}))
			layout_begin_space(.SCREEN)

			id := ui_id("node")
			layout_push_node(
				id,
				Resolved_Widget_Config {
					width  = {kind = .FIXED, value = 10},
					height = {kind = .FIXED, value = 10},
				},
			)
			layout_pop_node()
			layout_end_space()

			register_tabbable("keep")
			w_ctx.focused_id = "gone"
			w_ctx.auto_element_index = 5
			_ = element_key("mapped")

			ui_end_layout_pass()
			testing.expect(t, state.ui.pass == .Draw)
			testing.expect(t, state.ui.layout_ids_snapshot[id])
			testing.expect_value(t, w_ctx.focused_id, "")
			testing.expect_value(t, w_ctx.auto_element_index, u32(0))
			testing.expect(t, len(w_ctx.static_ids) == 0)
		},
	)
}

@(test)
ui_end_frame_prunes_stale_widgets_and_element_maps :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			state.ui.frame = 3
			live := widget_lifecycle_entry(UI_Id(1))
			testing.expect_value(t, live.last_frame, u64(3))
			state.ui.widgets[UI_Id(2)] = UI_Widget_Entry {
				last_frame = 1,
			}

			w_ctx.element_was_hovered = make(map[string]bool)
			w_ctx.element_was_hovered["stale"] = true

			ui_end_frame()
			testing.expect(t, UI_Id(1) in state.ui.widgets)
			testing.expect(t, !(UI_Id(2) in state.ui.widgets))
			_, stale := w_ctx.element_was_hovered["stale"]
			testing.expect(t, !stale)
		},
	)
}

@(test)
ui_pass_layout_rect_and_presence_helpers :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			testing.expect(t, ui_pass() == .Layout)

			missing := ui_layout_rect(UI_Id(123))
			expect_rect(t, missing, {})

			_ = layout_test_begin()
			defer layout_test_end(&state.ui.layout)
			idx := layout_test_append_node(&state.ui.layout, -1, .RECT)
			state.ui.layout.nodes[idx].rect = {1, 2, 3, 4}
			state.ui.layout.id_to_node[UI_Id(9)] = idx

			got := ui_layout_rect(UI_Id(9))
			expect_rect(t, got, {1, 2, 3, 4})
			testing.expect(t, ui_has_layout_node(UI_Id(9)))
			testing.expect(t, !ui_has_layout_node(UI_Id(8)))

			state.ui.layout_ids_prev[UI_Id(9)] = true
			testing.expect(t, ui_was_laid_out_prev(UI_Id(9)))
			testing.expect(t, !ui_was_laid_out_prev(UI_Id(8)))
		},
	)
}

@(test)
ui_scope_stack_and_stable_ids :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			root_hash := ui_parent_hash()
			a := ui_id("button")
			b := ui_id("button")
			testing.expect_value(t, a, b)

			ui_push_scope(UI_Id(11))
			testing.expect_value(t, len(state.ui.scope_stack), 1)
			scoped := ui_id("button")
			testing.expect(t, scoped != a)
			testing.expect(t, ui_parent_hash() != root_hash)

			ui_push_scope(UI_Id(22))
			nested := ui_id("button")
			testing.expect(t, nested != scoped)

			ui_pop_scope()
			testing.expect_value(t, len(state.ui.scope_stack), 1)
			again := ui_id("button")
			testing.expect_value(t, again, scoped)

			ui_pop_scope()
			ui_pop_scope() // underflow-safe
			testing.expect_value(t, len(state.ui.scope_stack), 0)
			testing.expect_value(t, ui_id("button"), a)

			other := ui_id("label")
			testing.expect(t, other != a)
		},
	)
}

@(private)
render_calls: int
@(private)
render_pass_log: [dynamic]UI_Pass

@(private)
ui_test_render_builder :: proc() {
	if render_calls == 0 {
		ui_push_style(style_root(.SCREEN, {0, 0, 800, 600}))
		layout_begin_space(.SCREEN)
		id := ui_id("render-node")
		layout_push_node(
			id,
			Resolved_Widget_Config {
				width  = {kind = .FIXED, value = 20},
				height = {kind = .FIXED, value = 20},
			},
		)
		layout_pop_node()
		layout_end_space()
	} else {
		_ = ui_layout_rect(ui_id("render-node"))
	}
	append(&render_pass_log, ui_pass())
	render_calls += 1
}

@(test)
ui_render_runs_layout_then_draw_then_end_frame :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			render_calls = 0
			delete(render_pass_log)
			render_pass_log = nil
			defer {
				delete(render_pass_log)
				render_pass_log = nil
			}

			render(ui_test_render_builder)
			testing.expect_value(t, render_calls, 2)
			testing.expect_value(t, len(render_pass_log), 2)
			testing.expect(t, render_pass_log[0] == .Layout)
			testing.expect(t, render_pass_log[1] == .Draw)
			testing.expect(t, state.ui.pass == .Draw)

			ui_push_style(style_root(.SCREEN, {0, 0, 800, 600}))
		},
	)
}

@(test)
ui_shutdown_clears_all_ui_state :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			register_tabbable("a")
			_ = element_key("b")
			_ = widget_lifecycle_entry(UI_Id(3))
			state.ui.frame = 9

			ui_shutdown()
			testing.expect(t, state.ui.widgets == nil)
			testing.expect(t, state.ui.layout.id_to_node == nil)
			testing.expect(t, state.ui.layout.table_tracks == nil)
			testing.expect(t, state.ui.layout_ids_prev == nil)
			testing.expect(t, state.ui.layout_ids_snapshot == nil)
			testing.expect(t, w_ctx.tab_order == nil)
			testing.expect_value(t, state.ui.frame, u64(0))
			testing.expect(t, state.ui.pass == .Layout)

			ui_init()
			ui_push_style(style_root(.SCREEN, {0, 0, 800, 600}))
		},
	)
}

@(test)
ui_begin_frame_syncs_input_and_clears_button_edges :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			w_ctx.left_mouse = {down = true, pressed = true, released = true}
			state.input.mouse_x = 15
			state.input.mouse_y = 25
			state.input.mouse_left = true

			ui_begin_frame()
			testing.expect(t, !w_ctx.left_mouse.pressed)
			testing.expect(t, !w_ctx.left_mouse.released)
			testing.expect(t, w_ctx.left_mouse.down)
			expect_close(t, w_ctx.mouse_x, 15)
			expect_close(t, w_ctx.mouse_y, 25)

			ui_push_style(style_root(.SCREEN, {0, 0, 800, 600}))
		},
	)
}

@(test)
ui_begin_frame_copies_snapshot_to_prev_across_frames :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			ui_begin_frame()
			ui_push_style(style_root(.SCREEN, {0, 0, 800, 600}))
			layout_begin_space(.SCREEN)
			id_a := ui_id("a")
			id_b := ui_id("b")
			layout_push_node(
				id_a,
				Resolved_Widget_Config {
					width  = {kind = .FIXED, value = 10},
					height = {kind = .FIXED, value = 10},
				},
			)
			layout_pop_node()
			layout_push_node(
				id_b,
				Resolved_Widget_Config {
					width  = {kind = .FIXED, value = 10},
					height = {kind = .FIXED, value = 10},
				},
			)
			layout_pop_node()
			layout_end_space()
			ui_end_layout_pass()
			testing.expect(t, state.ui.layout_ids_snapshot[id_a])
			testing.expect(t, state.ui.layout_ids_snapshot[id_b])
			ui_end_frame()

			ui_begin_frame()
			testing.expect_value(t, state.ui.frame, u64(2))
			testing.expect(t, ui_was_laid_out_prev(id_a))
			testing.expect(t, ui_was_laid_out_prev(id_b))
			testing.expect(t, !ui_has_layout_node(id_a))
			testing.expect(t, state.ui.layout_ids_prev[id_a])

			ui_push_style(style_root(.SCREEN, {0, 0, 800, 600}))
		},
	)
}

@(test)
ui_begin_frame_clears_all_button_and_key_edges_and_static_ids :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			_ = element_key("keep")
			testing.expect(t, len(w_ctx.static_ids) > 0)

			w_ctx.left_mouse = {down = true, pressed = true, released = true}
			w_ctx.right_mouse = {down = true, pressed = true, released = true}
			w_ctx.middle_mouse = {down = false, pressed = true, released = true}
			w_ctx.keys[int(Scancode.A)] = {down = true, pressed = true, released = true}
			w_ctx.keys[int(Scancode.TAB)] = {down = false, pressed = true, released = true}
			state.input.mouse_left = true
			state.input.mouse_right = true
			state.input.keys_down[int(Scancode.A)] = true

			ui_begin_frame()
			// Transients cleared, then input re-synced: held buttons stay down without edges.
			testing.expect(t, !w_ctx.left_mouse.pressed && !w_ctx.left_mouse.released)
			testing.expect(t, w_ctx.left_mouse.down)
			testing.expect(t, !w_ctx.right_mouse.pressed && !w_ctx.right_mouse.released)
			testing.expect(t, w_ctx.right_mouse.down)
			testing.expect(t, !w_ctx.middle_mouse.pressed && !w_ctx.middle_mouse.released)
			testing.expect(t, !w_ctx.middle_mouse.down)
			testing.expect(t, !w_ctx.keys[int(Scancode.A)].pressed)
			testing.expect(t, !w_ctx.keys[int(Scancode.A)].released)
			testing.expect(t, w_ctx.keys[int(Scancode.A)].down)
			testing.expect(t, !w_ctx.keys[int(Scancode.TAB)].pressed)
			testing.expect(t, len(w_ctx.static_ids) == 0)

			ui_push_style(style_root(.SCREEN, {0, 0, 800, 600}))
		},
	)
}

@(test)
ui_begin_frame_allocates_maps_when_uninitialized :: proc(t: ^testing.T) {
	test_state: State
	with_test_global_state(
		&test_state,
		proc(test_state: ^State, t: ^testing.T) {
			_ = test_state
			testing.expect(t, state.ui.widgets == nil)
			ui_begin_frame()
			state.ui.widgets[UI_Id(1)] = {}
			testing.expect(t, UI_Id(1) in state.ui.widgets)
			testing.expect_value(t, state.ui.frame, u64(1))
			testing.expect(t, state.ui.pass == .Layout)
			ui_shutdown()
		},
		t,
	)
}

@(test)
ui_end_layout_pass_replaces_snapshot_and_runs_tab_nav :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			ui_begin_frame()
			ui_push_style(style_root(.SCREEN, {0, 0, 800, 600}))

			state.ui.layout_ids_snapshot[UI_Id(99)] = true

			layout_begin_space(.SCREEN)
			id := ui_id("fresh")
			layout_push_node(
				id,
				Resolved_Widget_Config {
					width  = {kind = .FIXED, value = 8},
					height = {kind = .FIXED, value = 8},
				},
			)
			layout_pop_node()
			layout_end_space()

			register_tabbable("first")
			register_tabbable("second")
			w_ctx.focused_id = "first"
			w_ctx.keys[int(Scancode.TAB)].pressed = true

			ui_end_layout_pass()
			testing.expect(t, state.ui.layout_ids_snapshot[id])
			_, stale := state.ui.layout_ids_snapshot[UI_Id(99)]
			testing.expect(t, !stale)
			testing.expect_value(t, w_ctx.focused_id, "second")
			testing.expect(t, w_ctx.tab_focus_changed)
			testing.expect_value(t, w_ctx.tab_focus_previous_id, "first")
		},
	)
}

@(test)
ui_end_frame_noop_when_widgets_nil :: proc(t: ^testing.T) {
	test_state: State
	with_test_global_state(
		&test_state,
		proc(test_state: ^State, t: ^testing.T) {
			_ = test_state
			testing.expect(t, state.ui.widgets == nil)
			ui_end_frame()
			testing.expect(t, state.ui.widgets == nil)
		},
		t,
	)
}

@(test)
ui_end_frame_keeps_current_frame_entries_only :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			state.ui.frame = 5
			_ = widget_lifecycle_entry(UI_Id(10))
			_ = widget_lifecycle_entry(UI_Id(11))
			state.ui.widgets[UI_Id(12)] = {last_frame = 4}
			state.ui.widgets[UI_Id(13)] = {last_frame = 5}

			register_tabbable("alive")
			w_ctx.element_was_hovered = make(map[string]bool)
			w_ctx.element_pointer_down = make(map[string]bool)
			w_ctx.element_was_hovered["alive"] = true
			w_ctx.element_was_hovered["dead"] = true
			w_ctx.element_pointer_down["dead"] = true

			ui_end_frame()
			testing.expect(t, UI_Id(10) in state.ui.widgets)
			testing.expect(t, UI_Id(11) in state.ui.widgets)
			testing.expect(t, UI_Id(13) in state.ui.widgets)
			testing.expect(t, !(UI_Id(12) in state.ui.widgets))
			testing.expect(t, w_ctx.element_was_hovered["alive"])
			_, dead_h := w_ctx.element_was_hovered["dead"]
			testing.expect(t, !dead_h)
			_, dead_p := w_ctx.element_pointer_down["dead"]
			testing.expect(t, !dead_p)
		},
	)
}

@(private)
render_multi_a_calls: int
@(private)
render_multi_b_calls: int
@(private)
render_multi_pass_log: [dynamic]UI_Pass

@(private)
ui_test_render_builder_a :: proc() {
	if render_multi_a_calls == 0 {
		ui_push_style(style_root(.SCREEN, {0, 0, 800, 600}))
		layout_begin_space(.SCREEN)
		layout_push_node(
			ui_id("a"),
			Resolved_Widget_Config {
				width  = {kind = .FIXED, value = 5},
				height = {kind = .FIXED, value = 5},
			},
		)
		layout_pop_node()
		layout_end_space()
	}
	append(&render_multi_pass_log, ui_pass())
	render_multi_a_calls += 1
}

@(private)
ui_test_render_builder_b :: proc() {
	if render_multi_b_calls == 0 {
		if len(state.ui.style_stack) == 0 {
			ui_push_style(style_root(.SCREEN, {0, 0, 800, 600}))
		}
		layout_begin_space(.SCREEN)
		layout_push_node(
			ui_id("b"),
			Resolved_Widget_Config {
				width  = {kind = .FIXED, value = 5},
				height = {kind = .FIXED, value = 5},
			},
		)
		layout_pop_node()
		layout_end_space()
	}
	append(&render_multi_pass_log, ui_pass())
	render_multi_b_calls += 1
}

@(test)
ui_render_runs_each_builder_twice_in_order :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			render_multi_a_calls = 0
			render_multi_b_calls = 0
			delete(render_multi_pass_log)
			render_multi_pass_log = nil
			defer {
				delete(render_multi_pass_log)
				render_multi_pass_log = nil
			}

			render(ui_test_render_builder_a, ui_test_render_builder_b)
			testing.expect_value(t, render_multi_a_calls, 2)
			testing.expect_value(t, render_multi_b_calls, 2)
			testing.expect_value(t, len(render_multi_pass_log), 4)
			testing.expect(t, render_multi_pass_log[0] == .Layout)
			testing.expect(t, render_multi_pass_log[1] == .Draw)
			// render() does not reset pass to Layout between builders, so B sees Draw.
			testing.expect(t, render_multi_pass_log[2] == .Draw)
			testing.expect(t, render_multi_pass_log[3] == .Draw)

			if len(state.ui.style_stack) == 0 {
				ui_push_style(style_root(.SCREEN, {0, 0, 800, 600}))
			}
		},
	)
}

@(test)
ui_render_empty_vararg_is_noop :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			frame_before := state.ui.frame
			pass_before := state.ui.pass
			render()
			testing.expect_value(t, state.ui.frame, frame_before)
			testing.expect(t, state.ui.pass == pass_before)
		},
	)
}

@(test)
ui_parent_hash_empty_and_order_sensitive :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			empty := ui_parent_hash()
			testing.expect_value(t, empty, u64(14695981039346656037))

			ui_push_scope(UI_Id(1))
			ui_push_scope(UI_Id(2))
			ab := ui_parent_hash()
			ui_pop_scope()
			ui_pop_scope()

			ui_push_scope(UI_Id(2))
			ui_push_scope(UI_Id(1))
			ba := ui_parent_hash()
			ui_pop_scope()
			ui_pop_scope()

			testing.expect(t, ab != ba)
			testing.expect(t, ab != empty)
			testing.expect_value(t, ui_parent_hash(), empty)

			ui_push_scope(UI_Id(1))
			once := ui_parent_hash()
			again := ui_parent_hash()
			testing.expect_value(t, once, again)
			ui_pop_scope()
		},
	)
}

@(test)
ui_id_empty_label_and_scope_xor_stability :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			empty_a := ui_id("")
			empty_b := ui_id("")
			testing.expect_value(t, empty_a, empty_b)

			root := ui_id("item")
			ui_push_scope(UI_Id(7))
			scoped := ui_id("item")
			ui_pop_scope()
			testing.expect(t, scoped != root)
			testing.expect_value(t, ui_id("item"), root)

			ui_push_scope(UI_Id(7))
			a1 := ui_id("alpha")
			a2 := ui_id("alpha")
			b1 := ui_id("beta")
			testing.expect_value(t, a1, a2)
			testing.expect(t, a1 != b1)
			ui_pop_scope()
		},
	)
}

@(test)
ui_layout_rect_and_pass_after_full_cycle :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			ui_begin_frame()
			testing.expect(t, ui_pass() == .Layout)
			ui_push_style(style_root(.SCREEN, {0, 0, 800, 600}))
			layout_begin_space(.SCREEN)
			id := ui_id("box")
			layout_push_node(
				id,
				Resolved_Widget_Config {
					width  = {kind = .FIXED, value = 40},
					height = {kind = .FIXED, value = 20},
				},
			)
			layout_pop_node()
			layout_end_space()

			got := ui_layout_rect(id)
			testing.expect(t, ui_has_layout_node(id))
			expect_close(t, got.w, 40)
			expect_close(t, got.h, 20)

			ui_end_layout_pass()
			testing.expect(t, ui_pass() == .Draw)
			expect_rect(t, ui_layout_rect(id), got)

			_ = widget_lifecycle_entry(id)
			ui_end_frame()
			testing.expect(t, id in state.ui.widgets)

			ui_push_style(style_root(.SCREEN, {0, 0, 800, 600}))
		},
	)
}

@(test)
ui_shutdown_clears_stacks_and_is_safe_twice :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			ui_push_scope(UI_Id(1))
			ui_push_scope(UI_Id(2))
			testing.expect(t, len(state.ui.scope_stack) >= 2)
			testing.expect(t, len(state.ui.style_stack) >= 1)

			ui_shutdown()
			testing.expect(t, state.ui.scope_stack == nil)
			testing.expect(t, state.ui.style_stack == nil)
			testing.expect(t, w_ctx.static_ids == nil)
			testing.expect(t, state.ui.pass == .Layout)
			testing.expect_value(t, state.ui.frame, u64(0))

			ui_shutdown()

			ui_init()
			ui_push_style(style_root(.SCREEN, {0, 0, 800, 600}))
		},
	)
}

@(test)
ui_end_layout_pass_clears_static_ids_for_draw_regen :: proc(t: ^testing.T) {
	with_ui_env(
		t,
		proc(t: ^testing.T) {
			ui_begin_frame()
			ui_push_style(style_root(.SCREEN, {0, 0, 800, 600}))
			key := element_key("btn")
			testing.expect_value(t, w_ctx.static_ids["btn"], key)
			testing.expect_value(t, key, "btn")
			testing.expect_value(t, w_ctx.auto_element_index, u32(0))

			ui_end_layout_pass()
			testing.expect(t, len(w_ctx.static_ids) == 0)
			testing.expect_value(t, w_ctx.auto_element_index, u32(0))

			key2 := element_key("btn")
			testing.expect_value(t, w_ctx.static_ids["btn"], key2)
			testing.expect_value(t, key2, "btn")
			testing.expect_value(t, w_ctx.auto_element_index, u32(0))
		},
	)
}

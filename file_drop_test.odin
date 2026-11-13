#+test
package oni

import "core:testing"
import sdl "vendor:sdl3"

@(private)
file_drop_test_send :: proc(kind: sdl.EventType, data: cstring = nil, point := Vec2{40, 30}, window_id := sdl.WindowID(1)) {
	file_drop_process_event({commonEvent = {type = kind}, windowID = window_id, data = data, x = point.x, y = point.y}, 1, {800, 600})
}

@(private)
file_drop_test_complete :: proc(path: cstring = "/tmp/file.png", point := Vec2{40, 30}) {
	file_drop_test_send(.DROP_BEGIN)
	file_drop_test_send(.DROP_FILE, path, point)
	file_drop_test_send(.DROP_COMPLETE, point = point)
}

@(test)
file_drop_copies_borrowed_paths_and_delivers_complete_batch_once :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer file_drop_shutdown()
		path := [12]u8{'/', 't', 'm', 'p', '/', 'a', '.', 'p', 'n', 'g', 0, 0}
		file_drop_test_send(.DROP_BEGIN)
		file_drop_test_send(.DROP_FILE, cstring(&path[0]))
		path[5] = 'b'
		file_drop_test_send(.DROP_FILE, cstring(&path[0]))
		_, premature := take_file_drop()
		testing.expect(t, !premature)
		file_drop_test_send(.DROP_COMPLETE)
		result, ok := take_file_drop()
		defer destroy_file_drop_result(&result)
		testing.expect(t, ok)
		testing.expect_value(t, result.status, .Selected)
		testing.expect_value(t, len(result.paths), 2)
		if len(result.paths) == 2 {
			testing.expect_value(t, result.paths[0], "/tmp/a.png")
			testing.expect_value(t, result.paths[1], "/tmp/b.png")
		}
		testing.expect(t, result.has_position)
		testing.expect_value(t, result.position, Vec2{40, 30})
		_, duplicate := take_file_drop()
		testing.expect(t, !duplicate)
		destroy_file_drop_result(&result)
		destroy_file_drop_result(&result)
	})
}

@(test)
file_drop_coordinates_account_for_window_pixels_and_design_scale :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer file_drop_shutdown()
		state.dpi = {logical_w = 800, logical_h = 600, drawable_w = 1600, drawable_h = 1200, scale = 2}
		file_drop_process_event({commonEvent = {type = .DROP_POSITION}, windowID = 1, x = 100, y = 50}, 1, {800, 600})
		drag := file_drag_state()
		testing.expect(t, drag.active && drag.has_position)
		testing.expect_value(t, drag.position, Vec2{100, 50})
		state.dpi.scale = 1.5
		file_drop_process_event({commonEvent = {type = .DROP_POSITION}, windowID = 1, x = 300, y = 150}, 1, {800, 600})
		testing.expect_value(t, file_drag_state().position, Vec2{400, 200})
	})
}

@(test)
file_drop_foreign_windows_text_and_empty_sessions_do_not_deliver_files :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer file_drop_shutdown()
		file_drop_test_send(.DROP_BEGIN, window_id = 2)
		file_drop_test_send(.DROP_FILE, "/tmp/foreign", window_id = 2)
		file_drop_test_send(.DROP_COMPLETE, window_id = 2)
		file_drop_test_send(.DROP_BEGIN)
		file_drop_test_send(.DROP_TEXT, "some text")
		file_drop_test_send(.DROP_COMPLETE)
		_, ok := take_file_drop()
		testing.expect(t, !ok)
		testing.expect(t, !file_drag_state().active)
		file_drop_test_send(.DROP_FILE, "/tmp/open-from-system", window_id = 0)
		file_drop_test_send(.DROP_COMPLETE, window_id = 0)
		result, selected := take_file_drop()
		defer destroy_file_drop_result(&result)
		testing.expect(t, selected)
		testing.expect(t, !result.has_position)
	})
}

@(test)
file_drop_invalid_or_oversized_input_rejects_the_entire_batch :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer file_drop_shutdown()
		invalid := [2]u8{255, 0}
		for bad in ([3]cstring{nil, "", cstring(&invalid[0])}) {
			file_drop_test_send(.DROP_BEGIN)
			file_drop_test_send(.DROP_FILE, "/tmp/valid-first")
			file_drop_test_send(.DROP_FILE, bad)
			file_drop_test_send(.DROP_COMPLETE)
			result, ok := take_file_drop()
			testing.expect(t, ok)
			testing.expect_value(t, result.status, .Failed)
			testing.expect_value(t, result.error_code, .Invalid_Data)
			testing.expect_value(t, len(result.paths), 0)
			destroy_file_drop_result(&result)
		}
		long := make([]u8, FILE_DROP_MAX_PATH_BYTES + 2)
		defer delete(long)
		for &b in long[:len(long) - 1] { b = 'a' }
		file_drop_test_complete(cstring(raw_data(long)))
		result, ok := take_file_drop()
		defer destroy_file_drop_result(&result)
		testing.expect(t, ok)
		testing.expect_value(t, result.error_code, .Limit_Exceeded)
		testing.expect_value(t, state.file_drop.owned_bytes, 0)
	})
}

@(test)
file_drop_limits_bound_unconsumed_memory_and_report_queue_overflow :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer file_drop_shutdown()
		for _ in 0 ..< FILE_DROP_MAX_BATCHES + 3 { file_drop_test_complete() }
		for _ in 0 ..< FILE_DROP_MAX_BATCHES {
			result, ok := take_file_drop()
			testing.expect(t, ok)
			testing.expect_value(t, result.status, .Selected)
			destroy_file_drop_result(&result)
		}
		result, ok := take_file_drop()
		defer destroy_file_drop_result(&result)
		testing.expect(t, ok)
		testing.expect_value(t, result.error_code, .Queue_Full)
		testing.expect_value(t, result.omitted_batches, u64(3))
		testing.expect_value(t, state.file_drop.owned_bytes, 0)
	})
}

@(test)
file_drop_allocation_failures_release_partial_results_with_origin_allocator :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		backing := context.allocator
		for allowed in 0 ..< 6 {
			fault := Test_Vector_Failing_Allocator{backing = backing, remaining = allowed}
			context.allocator = {procedure = test_vector_failing_allocator, data = &fault}
			file_drop_test_send(.DROP_BEGIN)
			file_drop_test_send(.DROP_FILE, "/tmp/first")
			file_drop_test_send(.DROP_FILE, "/tmp/second")
			file_drop_test_send(.DROP_COMPLETE)
			context.allocator = backing
			result, ok := take_file_drop()
			testing.expect(t, ok)
			testing.expect(t, result.status == .Selected || result.error_code == .Allocation_Failed)
			if result.status == .Failed { testing.expect_value(t, len(result.paths), 0) }
			destroy_file_drop_result(&result)
			file_drop_shutdown()
		}
	})
}

@(test)
file_drop_reset_cancels_incomplete_data_but_keeps_completed_results :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer file_drop_shutdown()
		file_drop_test_complete()
		file_drop_test_send(.DROP_BEGIN)
		file_drop_test_send(.DROP_FILE, "/tmp/not-complete")
		reset_input_state()
		testing.expect(t, !file_drag_state().active)
		result, ok := take_file_drop()
		defer destroy_file_drop_result(&result)
		testing.expect(t, ok)
		testing.expect_value(t, len(result.paths), 1)
		_, extra := take_file_drop()
		testing.expect(t, !extra)
		file_drop_shutdown()
		file_drop_shutdown()
	})
}

@(test)
file_drop_hover_and_idle_processing_allocate_nothing :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer file_drop_shutdown()
		fault := Test_Vector_Failing_Allocator{backing = context.allocator, remaining = 0}
		context.allocator = {procedure = test_vector_failing_allocator, data = &fault}
		for _ in 0 ..< 1000 {
			file_drop_test_send(.DROP_POSITION)
			file_drop_begin_ui_frame()
			file_drop_resolve_targets()
		}
		testing.expect(t, !fault.rejected, "hovering and idle frames must not allocate")
	})
}

@(test)
file_drop_target_routes_to_nearest_ancestor_and_obeys_occlusion :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer file_drop_shutdown()
		ui_begin_frame()
		ui_push_style(style_root(.SCREEN, {0, 0, 800, 600}))
		defer ui_pop_style()
		layout_begin_space(.SCREEN)
		_ = layout_push_node(UI_Id(1), {width = layout_len_fixed(200), height = layout_len_fixed(200)})
		_ = layout_push_node(UI_Id(2), {width = layout_len_fixed(100), height = layout_len_fixed(100)})
		layout_pop_node()
		layout_pop_node()
		layout_end_space()
		testing.expect(t, file_drop_register_target(UI_Id(1), true))
		file_drop_test_complete()
		ui_end_layout_pass()
		result, ok := take_file_drop(UI_Id(1))
		defer destroy_file_drop_result(&result)
		testing.expect(t, ok)

		file_drop_test_complete()
		state.ui.layout.nodes[state.ui.layout.id_to_node[UI_Id(2)]].parent = -1
		file_drop_resolve_targets()
		_, blocked := take_file_drop(UI_Id(1))
		testing.expect(t, !blocked, "an unrelated foreground node must block the target behind it")
	})
}

@(test)
file_drop_result_outlives_engine_shutdown :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		file_drop_test_complete("/tmp/retained.png")
		result, ok := take_file_drop()
		defer destroy_file_drop_result(&result)
		file_drop_shutdown()
		testing.expect(t, ok)
		if len(result.paths) == 1 { testing.expect_value(t, result.paths[0], "/tmp/retained.png") }
	})
}

@(test)
file_drop_file_count_and_total_bytes_are_atomic_limits :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer file_drop_shutdown()
		file_drop_test_send(.DROP_BEGIN)
		for _ in 0 ..< FILE_DROP_MAX_FILES + 1 { file_drop_test_send(.DROP_FILE, "/tmp/a") }
		file_drop_test_send(.DROP_COMPLETE)
		result, ok := take_file_drop()
		testing.expect(t, ok)
		testing.expect_value(t, result.error_code, .Limit_Exceeded)
		testing.expect_value(t, len(result.paths), 0)
		destroy_file_drop_result(&result)

		path := make([]u8, FILE_DROP_MAX_PATH_BYTES + 1)
		defer delete(path)
		for &b in path[:len(path) - 1] { b = 'a' }
		file_drop_test_send(.DROP_BEGIN)
		for _ in 0 ..< FILE_DROP_MAX_OWNED_BYTES / FILE_DROP_MAX_PATH_BYTES + 1 {
			file_drop_test_send(.DROP_FILE, cstring(raw_data(path)))
		}
		file_drop_test_send(.DROP_COMPLETE)
		result, ok = take_file_drop()
		defer destroy_file_drop_result(&result)
		testing.expect(t, ok)
		testing.expect_value(t, result.error_code, .Limit_Exceeded)
		testing.expect_value(t, len(result.paths), 0)
		testing.expect_value(t, state.file_drop.owned_bytes, 0)
	})
}

@(test)
file_drop_growing_path_storage_handles_every_allocation_failure :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		backing := context.allocator
		for allowed in 0 ..< 25 {
			fault := Test_Vector_Failing_Allocator{backing = backing, remaining = allowed}
			context.allocator = {procedure = test_vector_failing_allocator, data = &fault}
			file_drop_test_send(.DROP_BEGIN)
			for _ in 0 ..< 20 { file_drop_test_send(.DROP_FILE, "/tmp/画像.png") }
			file_drop_test_send(.DROP_COMPLETE)
			context.allocator = backing
			result, ok := take_file_drop()
			testing.expect(t, ok)
			testing.expect(t, result.status == .Selected || result.error_code == .Allocation_Failed)
			if result.status == .Selected {
				testing.expect_value(t, len(result.paths), 20)
				testing.expect_value(t, result.paths[0], "/tmp/画像.png")
			}
			destroy_file_drop_result(&result)
			file_drop_shutdown()
		}
	})
}

@(test)
file_drop_poll_budget_preserves_order_and_wakes_remaining_work :: proc(t: ^testing.T) {
	with_engine_sdl_env(t, proc(t: ^testing.T) {
		defer file_drop_shutdown()
		testing.expect(t, engine_test_push(t, {drop = {commonEvent = {type = .DROP_BEGIN}}}))
		for _ in 0 ..< FILE_DROP_EVENTS_PER_POLL + 7 {
			testing.expect(t, engine_test_push(t, {drop = {commonEvent = {type = .DROP_FILE}, data = "/tmp/budgeted.png"}}))
		}
		testing.expect(t, engine_test_push(t, {drop = {commonEvent = {type = .DROP_COMPLETE}}}))
		state.frame_dirty = false
		poll_events()
		testing.expect(t, state.frame_dirty)
		_, premature := take_file_drop()
		testing.expect(t, !premature)
		poll_events()
		result, ok := take_file_drop()
		defer destroy_file_drop_result(&result)
		testing.expect(t, ok)
		testing.expect_value(t, len(result.paths), FILE_DROP_EVENTS_PER_POLL + 7)
	})
}

@(test)
file_drop_migration_moves_ownership_and_reset_keeps_ready_paths :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		original := state
		file_drop_test_complete()
		file_drop_test_send(.DROP_BEGIN)
		file_drop_test_send(.DROP_FILE, "/tmp/in-flight")
		moved: State
		copy_state_fields(&moved, original)
		testing.expect_value(t, original.file_drop.count, 0)
		testing.expect_value(t, len(original.file_drop.pending), 0)
		state = &moved
		defer { file_drop_shutdown(); state = original }
		reset_input_state()
		result, ok := take_file_drop()
		defer destroy_file_drop_result(&result)
		testing.expect(t, ok)
		testing.expect_value(t, result.status, .Selected)
		testing.expect_value(t, len(moved.file_drop.pending), 0)
	})
}

@(test)
file_drop_nested_disabled_target_blocks_parent_and_hover_leaves_on_cancel :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer file_drop_shutdown()
		ui_begin_frame()
		ui_push_style(style_root(.SCREEN, {0, 0, 800, 600}))
		defer ui_pop_style()
		layout_begin_space(.SCREEN)
		_ = layout_push_node(UI_Id(1), {width = layout_len_fixed(200), height = layout_len_fixed(200)})
		_ = layout_push_node(UI_Id(2), {width = layout_len_fixed(100), height = layout_len_fixed(100)})
		layout_pop_node()
		layout_pop_node()
		layout_end_space()
		_ = file_drop_register_target(UI_Id(1), true)
		_ = file_drop_register_target(UI_Id(2), false)
		file_drop_test_complete()
		ui_end_layout_pass()
		_, parent_received := take_file_drop(UI_Id(1))
		testing.expect(t, !parent_received)
		result, ok := take_file_drop()
		testing.expect(t, ok)
		destroy_file_drop_result(&result)
		file_drop_test_send(.DROP_POSITION)
		state.file_drop.targets[UI_Id(2)] = true
		file_drop_resolve_targets()
		testing.expect(t, file_drop_target_entered(UI_Id(2)))
		file_drop_test_send(.DROP_COMPLETE)
		file_drop_begin_ui_frame()
		testing.expect(t, file_drop_target_left(UI_Id(2)))
	})
}

@(test)
file_drop_native_event_wakes_on_demand_and_consume_schedules_feedback :: proc(t: ^testing.T) {
	with_runtime_window_env(t, proc(t: ^testing.T) {
		frame_mode_set(.On_Demand)
		state.frame_dirty = false
		window_id := sdl.GetWindowID(state.window)
		testing.expect(t, engine_test_push(t, {drop = {commonEvent = {type = .DROP_FILE}, windowID = window_id, data = "/tmp/wake.txt", x = 20, y = 20}}))
		testing.expect(t, engine_test_push(t, {drop = {commonEvent = {type = .DROP_COMPLETE}, windowID = window_id, x = 20, y = 20}}))
		run_frame(runtime_test_tick, runtime_test_draw, runtime_test_init)
		testing.expect_value(t, runtime_test_draw_calls, 1)
		result, ok := take_file_drop()
		defer destroy_file_drop_result(&result)
		testing.expect(t, ok)
		testing.expect(t, state.frame_dirty)
	})
}

@(test)
file_drop_target_obeys_scroll_clip_and_viewport_boundaries :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer file_drop_shutdown()
		ui_begin_frame()
		ui_push_style(style_root(.SCREEN, {0, 0, 800, 600}))
		defer ui_pop_style()
		layout_begin_space(.SCREEN)
		_ = layout_push_node(UI_Id(1), {width = layout_len_fixed(50), height = layout_len_fixed(100), overflow_x = layout_stack_ov_hidden()})
		_ = layout_push_node(UI_Id(2), {width = layout_len_fixed(100), height = layout_len_fixed(100)})
		layout_pop_node()
		layout_pop_node()
		layout_end_space()
		_ = file_drop_register_target(UI_Id(2), true)
		file_drop_test_complete(point = {75, 20})
		ui_end_layout_pass()
		_, clipped := take_file_drop(UI_Id(2))
		testing.expect(t, !clipped)
		testing.expect_value(t, file_drop_target_at({-1, 20}), UI_Id{})
		testing.expect_value(t, file_drop_target_at({800, 20}), UI_Id{})
	})
}

@(test)
file_drop_target_uses_artboard_transform_instead_of_mouse_position :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer file_drop_shutdown()
		ui_begin_frame()
		state.view.zoom = 2
		state.view.pan = {100, 20}
		ui_push_style(style_root(.ARTBOARD, {0, 0, 400, 300}))
		defer ui_pop_style()
		layout_begin_space(.ARTBOARD)
		_ = layout_push_node(UI_Id(1), {width = layout_len_fixed(100), height = layout_len_fixed(100)})
		layout_pop_node()
		layout_end_space()
		_ = file_drop_register_target(UI_Id(1), true)
		state.input.mouse_x, state.input.mouse_y = 700, 500
		file_drop_test_complete(point = {140, 60})
		ui_end_layout_pass()
		result, ok := take_file_drop(UI_Id(1))
		defer destroy_file_drop_result(&result)
		testing.expect(t, ok)
		testing.expect_value(t, result.position, Vec2{140, 60})
	})
}

@(test)
file_drop_modal_occludes_background_and_hidden_overlay_does_not :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer file_drop_shutdown()
		for hidden in ([2]bool{false, true}) {
			ui_begin_frame()
			ui_push_style(style_root(.SCREEN, {0, 0, 800, 600}))
			layout_begin_space(.SCREEN)
			_ = layout_push_node(UI_Id(1), {width = layout_len_fixed(200), height = layout_len_fixed(200)})
			layout_pop_node()
			layout_end_space()
			layout_begin_space(.OVERLAY)
			node := layout_push_node(UI_Id(2), {width = layout_len_fixed(200), height = layout_len_fixed(200), space = .OVERLAY})
			if hidden { node.config.visibility = layout_stack_hidden() }
			layout_pop_node()
			layout_end_space()
			_ = file_drop_register_target(UI_Id(1), true)
			file_drop_test_complete()
			ui_end_layout_pass()
			result, ok := take_file_drop(UI_Id(1))
			testing.expect_value(t, ok, hidden)
			destroy_file_drop_result(&result)
			if !ok { result, _ = take_file_drop(); destroy_file_drop_result(&result) }
			ui_pop_style()
		}
	})
}

@(test)
file_drop_unclaimed_completion_is_not_rerouted_to_a_later_target :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer file_drop_shutdown()
		file_drop_test_complete()
		file_drop_resolve_targets()
		testing.expect(t, state.file_drop.ready[0].routed)
		testing.expect_value(t, state.file_drop.ready[0].target, UI_Id{})
	})
}

@(test)
file_drop_nested_modal_does_not_bubble_to_its_background_target :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer file_drop_shutdown()
		ui_begin_frame()
		ui_push_style(style_root(.SCREEN, {0, 0, 800, 600}))
		defer ui_pop_style()
		layout_begin_space(.SCREEN)
		_ = layout_push_node(UI_Id(1), {width = layout_len_fixed(200), height = layout_len_fixed(200)})
		_ = layout_push_node(UI_Id(2), {width = layout_len_fixed(200), height = layout_len_fixed(200), space = .OVERLAY})
		layout_pop_node()
		layout_pop_node()
		layout_end_space()
		_ = file_drop_register_target(UI_Id(1), true)
		file_drop_test_complete()
		ui_end_layout_pass()
		result, background_received := take_file_drop(UI_Id(1))
		defer destroy_file_drop_result(&result)
		testing.expect(t, !background_received)
	})
}

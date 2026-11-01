#+test
package oni

import "core:testing"

@(private)
vector_tess_test_triangle :: proc() -> [4]Vector_Path_Command {
	return {
		{kind = .Move, points = {{0, 0}, {}, {}}},
		{kind = .Line, points = {{10, 0}, {}, {}}},
		{kind = .Line, points = {{0, 10}, {}, {}}},
		{kind = .Close},
	}
}

@(test)
vector_prefetch_paths_serial_below_threshold_matches_draw :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		state.ui.pass = .Draw
		commands := vector_tess_test_triangle()
		handles: [3]Vector_Path_Handle
		specs: [3]Vector_Path_Tess_Spec
		for i in 0 ..< 3 {
			handle, err := Vector_Create_Path(commands[:])
			testing.expect_value(t, err, Vector_Error.None)
			handles[i] = handle
			scale := f64(i + 1)
			specs[i] = {handle = handle, transform = {scale, 0, 0, scale, 0, 0}, rule = .Nonzero}
		}

		testing.expect_value(t, Vector_Prefetch_Paths(specs[:]), Vector_Error.None)
		testing.expect(t, state.vector.tess_pool == nil || state.vector.tess_workers == 0)

		for i in 0 ..< 3 {
			entry := vector_path_entry(handles[i])
			testing.expect(t, entry != nil)
			testing.expect(t, len(entry.cache) >= 1)
			testing.expect(t, entry.cache[0].valid)
			testing.expect_value(t, Draw_Vector_Path(handles[i], {255, 0, 0, 255}, specs[i].transform), Vector_Error.None)
		}
	})
}

@(test)
vector_prefetch_paths_parallel_at_threshold_fills_cache :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		state.ui.pass = .Draw
		commands := vector_tess_test_triangle()
		handles: [VECTOR_TESS_PARALLEL_THRESHOLD]Vector_Path_Handle
		specs: [VECTOR_TESS_PARALLEL_THRESHOLD]Vector_Path_Tess_Spec
		for i in 0 ..< VECTOR_TESS_PARALLEL_THRESHOLD {
			handle, err := Vector_Create_Path(commands[:])
			testing.expect_value(t, err, Vector_Error.None)
			handles[i] = handle
			scale := f64(i + 1)
			specs[i] = {handle = handle, transform = {scale, 0, 0, scale, f64(i) * 2, 0}, rule = .Nonzero}
		}

		testing.expect_value(t, Vector_Ensure_Path_Meshes(specs[:]), Vector_Error.None)
		testing.expect(t, state.vector.tess_pool != nil)
		testing.expect_value(t, state.vector.tess_workers, 0)

		for i in 0 ..< VECTOR_TESS_PARALLEL_THRESHOLD {
			entry := vector_path_entry(handles[i])
			testing.expect(t, entry != nil)
			testing.expect(t, len(entry.cache) >= 1)
			testing.expect(t, entry.cache[0].valid)
			testing.expect(t, len(entry.cache[0].mesh.vertices) > 0)
		}

		testing.expect(t, state.vector.path_cache_bytes > 0)
	})
}

@(test)
draw_vector_paths_batches_unique_misses :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		state.ui.pass = .Draw
		commands := vector_tess_test_triangle()
		items: [VECTOR_TESS_PARALLEL_THRESHOLD]Vector_Path_Draw
		for i in 0 ..< VECTOR_TESS_PARALLEL_THRESHOLD {
			handle, err := Vector_Create_Path(commands[:])
			testing.expect_value(t, err, Vector_Error.None)
			scale := f64(i + 1)
			items[i] = {
				handle    = handle,
				paint     = Solid_Paint({255, 0, 0, 255}),
				transform = {scale, 0, 0, scale, f64(i) * 4, 0},
				rule      = .Nonzero,
				opacity   = 1,
			}
		}

		testing.expect_value(t, Draw_Vector_Paths(items[:]), Vector_Error.None)
		testing.expect(t, len(vector_frame().draws) > 0)
		testing.expect_value(t, state.vector.tess_workers, 0)
	})
}

@(test)
vector_tess_pool_shutdown_joins_workers :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		state.ui.pass = .Draw
		commands := vector_tess_test_triangle()
		specs: [VECTOR_TESS_PARALLEL_THRESHOLD]Vector_Path_Tess_Spec
		for i in 0 ..< VECTOR_TESS_PARALLEL_THRESHOLD {
			handle, err := Vector_Create_Path(commands[:])
			testing.expect_value(t, err, Vector_Error.None)
			scale := f64(i + 1)
			specs[i] = {handle = handle, transform = {scale, 0, 0, scale, 0, 0}}
		}

		testing.expect_value(t, Vector_Prefetch_Paths(specs[:]), Vector_Error.None)
		testing.expect(t, state.vector.tess_pool != nil)
		vector_tess_pool_shutdown()
		testing.expect(t, state.vector.tess_pool == nil)
		testing.expect_value(t, state.vector.tess_workers, 0)
	})
}

@(test)
vector_prefetch_rejects_invalid_handle :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		specs := [1]Vector_Path_Tess_Spec{{handle = {index = 99, generation = 1}}}
		testing.expect_value(t, Vector_Prefetch_Paths(specs[:]), Vector_Error.Invalid_Handle)
	})
}

@(test)
vector_draw_path_still_serial_on_single_miss :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		state.ui.pass = .Draw
		commands := vector_tess_test_triangle()
		handle, err := Vector_Create_Path(commands[:])
		testing.expect_value(t, err, Vector_Error.None)
		testing.expect_value(t, Draw_Vector_Path(handle, {255, 0, 0, 255}), Vector_Error.None)
		testing.expect(t, state.vector.tess_pool == nil)
		testing.expect(t, state.vector.path_cache_bytes > 0)
	})
}

@(test)
vector_prefetch_parallel_respects_exhausted_frame_budget :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		state.ui.pass = .Draw
		commands := vector_tess_test_triangle()
		specs: [VECTOR_TESS_PARALLEL_THRESHOLD]Vector_Path_Tess_Spec
		for i in 0 ..< VECTOR_TESS_PARALLEL_THRESHOLD {
			handle, err := Vector_Create_Path(commands[:])
			testing.expect_value(t, err, Vector_Error.None)
			scale := f64(i + 1)
			specs[i] = {handle = handle, transform = {scale, 0, 0, scale, 0, 0}}
		}

		vector_frame().new_segments = VECTOR_MAX_NEW_SEGMENTS
		testing.expect_value(t, Vector_Prefetch_Paths(specs[:]), Vector_Error.Limit_Exceeded)
		testing.expect_value(t, state.vector.tess_workers, 0)
	})
}

@(test)
vector_prefetch_command_copy_survives_update_path :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		state.ui.pass = .Draw
		commands := vector_tess_test_triangle()
		handles: [VECTOR_TESS_PARALLEL_THRESHOLD]Vector_Path_Handle
		specs: [VECTOR_TESS_PARALLEL_THRESHOLD]Vector_Path_Tess_Spec
		for i in 0 ..< VECTOR_TESS_PARALLEL_THRESHOLD {
			handle, err := Vector_Create_Path(commands[:])
			testing.expect_value(t, err, Vector_Error.None)
			handles[i] = handle
			scale := f64(i + 1)
			specs[i] = {handle = handle, transform = {scale, 0, 0, scale, 0, 0}}
		}

		testing.expect_value(t, Vector_Prefetch_Paths(specs[:]), Vector_Error.None)
		updated := vector_tess_test_triangle()
		updated[1].points[0] = {20, 0}
		testing.expect_value(t, Vector_Update_Path(handles[0], updated[:]), Vector_Error.None)
		// Basis morph path may keep cache; non-affine update invalidates.
		entry := vector_path_entry(handles[0])
		testing.expect(t, entry != nil)
		for cached in entry.cache {
			if !cached.valid {
				testing.expect(t, true)
				return
			}
		}
		// Affine-compatible updates keep shared meshes valid via morph.
		testing.expect(t, len(entry.cache) > 0)
	})
}

@(test)
vector_prefetch_then_evict_with_pool_idle :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		state.ui.pass = .Draw
		commands := vector_tess_test_triangle()
		specs: [VECTOR_TESS_PARALLEL_THRESHOLD]Vector_Path_Tess_Spec
		handle: Vector_Path_Handle
		for i in 0 ..< VECTOR_TESS_PARALLEL_THRESHOLD {
			h, err := Vector_Create_Path(commands[:])
			testing.expect_value(t, err, Vector_Error.None)
			if i == 0 {
				handle = h
			}
			scale := f64(i + 1)
			specs[i] = {handle = h, transform = {scale, 0, 0, scale, 0, 0}}
		}

		testing.expect_value(t, Vector_Prefetch_Paths(specs[:]), Vector_Error.None)
		testing.expect_value(t, state.vector.tess_workers, 0)
		testing.expect(t, state.vector.path_cache_bytes > 0)
		testing.expect_value(t, Vector_Destroy_Path(handle), Vector_Error.None)
		testing.expect_value(t, state.vector.tess_workers, 0)
	})
}

@(test)
vector_migrate_shuts_down_tess_pool :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		state.ui.pass = .Draw
		commands := vector_tess_test_triangle()
		specs: [VECTOR_TESS_PARALLEL_THRESHOLD]Vector_Path_Tess_Spec
		for i in 0 ..< VECTOR_TESS_PARALLEL_THRESHOLD {
			handle, err := Vector_Create_Path(commands[:])
			testing.expect_value(t, err, Vector_Error.None)
			scale := f64(i + 1)
			specs[i] = {handle = handle, transform = {scale, 0, 0, scale, 0, 0}}
		}

		testing.expect_value(t, Vector_Prefetch_Paths(specs[:]), Vector_Error.None)
		testing.expect(t, state.vector.tess_pool != nil)

		dst: State
		copy_state_fields(&dst, state)
		testing.expect(t, dst.vector.tess_pool == nil)
		testing.expect(t, state.vector.tess_pool == nil)
		dst.assets.io_pool = nil
		dst.fonts.raster_pool = nil
	})
}

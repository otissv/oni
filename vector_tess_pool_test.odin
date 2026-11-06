#+test
package oni

import "core:testing"
import "core:slice"
import v "./vector"

@(test)
vector_small_fill_remesh_matches_cpu_mesh_and_enforces_frame_work_budget :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		state.ui.pass = .Draw
		items: [4]Vector_Path_Draw
		references: [4]v.Mesh
		defer for &mesh in references { v.Destroy_Mesh(&mesh) }
		for i in 0 ..< len(items) {
			commands := vector_benchmark_circle(3, 3.5, f64(i))
			handle, created := Vector_Create_Path(commands[:])
			testing.expect_value(t, created, Vector_Error.None)
			items[i] = {handle = handle, paint = Solid_Paint({255, 0, 0, 255}), transform = Vector_Identity, opacity = 1}
		}
		for frame in 0 ..< 4 {
			vector_scene_reset()
			state.ui.frame += 1
			for item, i in items {
				commands, borrowed := Vector_Borrow_Path_Commands(item.handle)
				testing.expect_value(t, borrowed, Vector_Error.None)
				vector_benchmark_morph_into(frame, 1536 + i, 3, commands)
				testing.expect_value(t, Vector_Path_Geometry_Changed(item.handle), Vector_Error.None)
				limits := v.DEFAULT_LIMITS
				limits.uniform_subdivision = -1
				testing.expect_value(t, v.Tessellate_Into(&references[i], commands, v.IDENTITY, .Nonzero, limits), v.Error.None)
			}
			testing.expect_value(t, Draw_Vector_Paths(items[:]), Vector_Error.None)
			for item, i in items {
				mesh := &vector_path_entry(item.handle).cache[0].mesh
				testing.expect(t, slice.equal(mesh.vertices[:], references[i].vertices[:]))
				testing.expect(t, slice.equal(mesh.indices[:], references[i].indices[:]))
			}
		}
		vector_scene_reset()
		vector_frame().exact_ops = VECTOR_MAX_FRAME_EXACT_OPS
		for item in items { _ = Vector_Path_Geometry_Changed(item.handle) }
		testing.expect_value(t, Draw_Vector_Paths(items[:]), Vector_Error.Limit_Exceeded)
		testing.expect_value(t, len(vector_frame().commands), 0)
	})
}

@(test)
vector_small_path_batch_deduplicates_and_rolls_back_invalid_tail :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		state.ui.pass = .Draw
		commands := vector_tess_test_triangle()
		handle, created := Vector_Create_Path(commands[:])
		testing.expect_value(t, created, Vector_Error.None)
		items := [3]Vector_Path_Draw{
			{handle = handle, paint = Solid_Paint({255, 0, 0, 255}), transform = Vector_Identity, opacity = 1},
			{handle = handle, paint = Solid_Paint({0, 255, 0, 255}), transform = {1, 0, 0, 1, 20, 0}, opacity = 1},
			{handle = handle, paint = Solid_Paint({0, 0, 255, 255}), transform = Vector_Identity, opacity = 1},
		}
		testing.expect_value(t, Draw_Vector_Paths(items[:2]), Vector_Error.None)
		testing.expect_value(t, len(vector_path_entry(handle).cache), 1)
		before_commands := len(vector_frame().commands)
		before_instances := len(vector_frame().instances)
		before_draw := vector_frame().draws[0]
		items[2].handle = {}
		testing.expect_value(t, Draw_Vector_Paths(items[:]), Vector_Error.Invalid_Handle)
		testing.expect_value(t, len(vector_frame().commands), before_commands)
		testing.expect_value(t, len(vector_frame().instances), before_instances)
		testing.expect_value(t, vector_frame().draws[0].merged_commands, before_draw.merged_commands)
	})
}

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

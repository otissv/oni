#+test
package oni

import "core:testing"
import "core:math"

@(test)
vector_tessellation_installs_charge_successful_and_failed_work :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		commands := vector_benchmark_circle(1, 3.5, 0)
		handle, created := Vector_Create_Path(commands[:])
		testing.expect_value(t, created, Vector_Error.None)
		for fail in ([2]bool{true, false}) {
			vector_scene_reset()
			entry := vector_path_entry(handle)
			job, need, err := vector_path_build_miss_job(handle, entry, {1, 0, 0, 1}, .Nonzero)
			testing.expect(t, need && err == .None)
			jobs := [1]Vector_Tess_Job{job}
			if fail { jobs[0].limits.max_triangles = 0 }
			vector_tessellate_jobs_serial(jobs[:])
			testing.expect(t, jobs[0].usage.exact_ops > 0)
			usage := jobs[0].usage
			installed := vector_path_install_tess_job(&jobs[0])
			testing.expect(t, (installed != .None) == fail)
			testing.expect_value(t, vector_frame().exact_ops, usage.exact_ops)
			testing.expect_value(t, vector_frame().pair_tests, usage.pair_tests)
			if fail {
				testing.expect_value(t, state.vector.last_build_usage.exact_ops, usage.exact_ops)
				testing.expect_value(t, state.vector.last_build_limits.max_triangles, jobs[0].limits.max_triangles)
			} else { testing.expect_value(t, state.vector.last_build_usage.exact_ops, 0) }
		}
	})
}

@(test)
vector_geometry_recording_cache_survives_slot_changes_and_rollback :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		state.ui.pass = .Draw
		commands := vector_tess_test_triangle()
		a, _ := Vector_Create_Path(commands[:])
		b, _ := Vector_Create_Path(commands[:])
		paint := Solid_Paint({255, 0, 0, 255})
		for _ in 0 ..< 2 {
			testing.expect_value(t, Draw_Vector_Path(a, paint), Vector_Error.None)
			testing.expect_value(t, len(vector_frame().vertices), 3)
			batch_flip()
		}
		vector_scene_reset()
		testing.expect_value(t, Draw_Vector_Path(a, paint), Vector_Error.None)
		testing.expect_value(t, len(vector_frame().vertices), 3)
		spec := [1]Vector_Path_Tess_Spec{{handle = b, transform = Vector_Identity}}
		testing.expect_value(t, Vector_Prefetch_Paths(spec[:]), Vector_Error.None)
		items := [2]Vector_Path_Draw{
			{handle = b, paint = paint, transform = Vector_Identity, opacity = 1},
			{handle = a, paint = paint, transform = {math.nan_f64(), 0, 0, 1, 0, 0}, opacity = 1},
		}
		testing.expect_value(t, Draw_Vector_Paths(items[:]), Vector_Error.Invalid_Value)
		testing.expect_value(t, len(vector_frame().vertices), 3)
		testing.expect_value(t, Draw_Vector_Path(b, paint), Vector_Error.None)
		testing.expect_value(t, len(vector_frame().vertices), 6)
		testing.expect_value(t, vector_frame().commands[1].vertex_offset, i32(3))
	})
}

@(test)
vector_composite_quad_retains_uv_mapping_in_instance :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		bounds := Rect{13, 27, 32, 48}
		command := vector_record_quad(bounds, .5)
		f := vector_frame()
		instance := f.instances[f.commands[command].first_instance]
		testing.expect_value(t, instance.paint[0], f32(3))
		testing.expect_value(t, instance.grad0, [4]f32{13, 27, 32, 48})
		testing.expect_value(t, f.vertices[0].pos, Vec2{13, 27})
		testing.expect_value(t, f.vertices[2].pos, Vec2{45, 75})
	})
}

@(test)
vector_parallel_prefetch_installs_each_mesh_bounds :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		specs: [65]Vector_Path_Tess_Spec
		for &spec, i in specs {
			commands := vector_tess_test_triangle()
			for &command in commands { for &point in command.points { point.x += f64(i) } }
			handle, err := Vector_Create_Path(commands[:])
			testing.expect_value(t, err, Vector_Error.None)
			spec = {handle = handle, transform = Vector_Identity}
		}
		testing.expect_value(t, Vector_Prefetch_Paths(specs[:]), Vector_Error.None)
		for spec in specs {
			cached := &vector_path_entry(spec.handle).cache[0]
			testing.expect_value(t, cached.bounds, vector_path_mesh_bounds(cached.mesh))
		}
	})
}

@(test)
vector_svg_command_hash_covers_payload_and_chunk_boundaries :: proc(t: ^testing.T) {
	commands: [130]Vector_Path_Command
	for &command in commands { command.kind = .Line }
	before := vector_svg_path_command_hash(commands[:])
	for i in ([4]int{0, 63, 64, 129}) {
		for field in 0 ..< 12 {
			original := commands[i]
			switch field {
			case 0: commands[i].kind = .Cubic
			case 1 ..< 7: commands[i].points[(field - 1) / 2][(field - 1) % 2] = 1
			case 7, 8: commands[i].radii[field - 7] = 1
			case 9: commands[i].rotation = 1
			case 10: commands[i].large_arc = true
			case 11: commands[i].sweep = true
			}
			testing.expect(t, vector_svg_path_command_hash(commands[:]) != before)
			commands[i] = original
		}
	}
	testing.expect_value(t, vector_svg_path_command_hash(commands[:]), before)
	testing.expect(t, vector_svg_path_command_hash(commands[:129]) != before)
}

@(test)
vector_cached_batch_late_validation_and_miss_preserve_recording :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		state.ui.pass = .Draw
		commands := vector_tess_test_triangle()
		a, _ := Vector_Create_Path(commands[:])
		b, _ := Vector_Create_Path(commands[:])
		paint := Solid_Paint({255, 0, 0, 255})
		testing.expect_value(t, Draw_Vector_Path(a, paint), Vector_Error.None)
		items := [2]Vector_Path_Draw{
			{handle = a, paint = paint, transform = Vector_Identity, opacity = 1},
			{handle = b, paint = paint, transform = Vector_Identity, opacity = 1},
		}
		testing.expect_value(t, Draw_Vector_Paths(items[:]), Vector_Error.None)
		testing.expect_value(t, len(vector_frame().commands), 3)
		saved := vector_frame().records[0]
		items[1].transform[0] = math.nan_f64()
		testing.expect_value(t, Draw_Vector_Paths(items[:]), Vector_Error.Invalid_Value)
		testing.expect_value(t, len(vector_frame().commands), 3)
		testing.expect_value(t, vector_frame().draws[0].merged_commands, u32(3))
		testing.expect_value(t, vector_frame().records[0], saved)
		items[1].transform = Vector_Identity
		items[1].handle = {}
		testing.expect_value(t, Draw_Vector_Paths(items[:]), Vector_Error.Invalid_Handle)
		testing.expect_value(t, len(vector_frame().commands), 3)
		testing.expect_value(t, vector_frame().records[0], saved)
	})
}

@(test)
vector_svg_recycles_only_unrecorded_compatible_geometry :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		commands := vector_tess_test_triangle()
		first, err := vector_svg_path(commands[:])
		testing.expect_value(t, err, Vector_Error.None)
		commands[1].points[0].x += 1
		second, err2 := vector_svg_path(commands[:])
		testing.expect_value(t, err2, Vector_Error.None)
		testing.expect(t, second != first, "Current-frame paths must remain immutable")
		state.ui.frame += 1
		commands[1].points[0].x += 1
		third, err3 := vector_svg_path(commands[:])
		testing.expect_value(t, err3, Vector_Error.None)
		testing.expect_value(t, third, first)
		testing.expect_value(t, len(state.vector.paths), 2)
		testing.expect_value(t, vector_path_entry(third).commands[1].points[0], commands[1].points[0])
		vector_expect_owned_svg_cache(t)
	})
}

@(test)
vector_cached_mesh_copy_preserves_offsets_and_replaces_reused_vertices :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		state.ui.pass = .Draw
		points := [3]Vec2{{1, 2}, {4, 2}, {1, 5}}
		indices := [3]u32{0, 1, 2}
		f := vector_frame()
		// Reused frame capacity may contain positions from composition quads.
		resize(&f.vertices, 8)
		for &vertex in f.vertices { vertex.pos = {7, 9} }
		resize(&f.vertices, 1)
		append(&f.indices, u32(0))
		for id in 1 ..= 2 {
			testing.expect_value(t, vector_record_cached_mesh(points[:], indices[:], {1, 2, 3, 3}, {}, {colour = {1, 1, 1, 1}}, u64(id)), Vector_Error.None)
		}
		testing.expect_value(t, len(f.vertices), 7)
		for vertex, i in f.vertices[1:] {
			testing.expect_value(t, vertex.pos, points[i % 3])
		}
		testing.expect_value(t, f.commands[0].vertex_offset, i32(1))
		testing.expect_value(t, f.commands[1].vertex_offset, i32(4))
		testing.expect_value(t, f.commands[0].first_index, u32(1))
		testing.expect_value(t, f.commands[1].first_index, u32(4))
	})
}

@(test)
vector_prefetch_failure_releases_pending_slots_for_retry :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		commands := [4]Vector_Path_Command{
			{kind = .Move}, {kind = .Line, points = {{10, 0}, {}, {}}},
			{kind = .Line, points = {{0, 10}, {}, {}}}, {kind = .Close},
		}
		handle, err := Vector_Create_Path(commands[:])
		testing.expect_value(t, err, Vector_Error.None)
		specs := [2]Vector_Path_Tess_Spec{{handle = handle, transform = Vector_Identity}, {transform = Vector_Identity}}
		testing.expect_value(t, Vector_Prefetch_Paths(specs[:]), Vector_Error.Invalid_Handle)
		testing.expect(t, !vector_path_entry(handle).cache[0].pending && !state.vector.tess_jobs_in_use)
		testing.expect_value(t, Vector_Prefetch_Paths(specs[:1]), Vector_Error.None)
		testing.expect(t, vector_path_entry(handle).cache[0].valid)
	})
}

@(test)
vector_coalesced_records_union_bounds_and_restore_after_failure :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		state.ui.pass = .Draw
		commands := [4]Vector_Path_Command{
			{kind = .Move}, {kind = .Line, points = {{10, 0}, {}, {}}},
			{kind = .Line, points = {{0, 10}, {}, {}}}, {kind = .Close},
		}
		handle, err := Vector_Create_Path(commands[:])
		testing.expect_value(t, err, Vector_Error.None)
		testing.expect_value(t, Draw_Vector_Path(handle, Solid_Paint({255, 0, 0, 255})), Vector_Error.None)
		before := vector_frame().records[0]
		items := [2]Vector_Path_Draw{
			{handle = handle, paint = Solid_Paint({0, 255, 0, 255}), transform = {1, 0, 0, 1, 100, 0}, opacity = 1},
			{handle = handle, paint = Linear_Paint({x2 = math.nan_f64()}), transform = Vector_Identity, opacity = 1},
		}
		testing.expect_value(t, Draw_Vector_Paths(items[:]), Vector_Error.Invalid_Value)
		testing.expect_value(t, len(vector_frame().records), 1)
		testing.expect_value(t, len(vector_frame().commands), 1)
		testing.expect_value(t, vector_frame().draws[0].merged_commands, 1)
		testing.expect_value(t, vector_frame().records[0].bounds, before.bounds)
		items[1].paint = Solid_Paint({0, 0, 255, 255})
		testing.expect_value(t, Draw_Vector_Paths(items[:]), Vector_Error.None)
		testing.expect_value(t, len(vector_frame().records), 1)
		testing.expect_value(t, vector_frame().draws[0].merged_commands, 3)
		testing.expect(t, vector_frame().records[0].bounds.w >= 110)
	})
}

@(test)
vector_prefetch_deduplicates_pending_fill_slots :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		commands := [4]Vector_Path_Command{
			{kind = .Move}, {kind = .Line, points = {{10, 0}, {}, {}}},
			{kind = .Line, points = {{0, 10}, {}, {}}}, {kind = .Close},
		}
		handle, err := Vector_Create_Path(commands[:])
		testing.expect_value(t, err, Vector_Error.None)
		specs := [3]Vector_Path_Tess_Spec{
			{handle = handle, transform = Vector_Identity},
			{handle = handle, transform = Vector_Identity},
			{handle = handle, transform = Vector_Identity, rule = .Even_Odd},
		}
		testing.expect_value(t, Vector_Prefetch_Paths(specs[:]), Vector_Error.None)
		entry := vector_path_entry(handle)
		testing.expect_value(t, len(entry.cache), 2)
		for cached in entry.cache { testing.expect(t, cached.valid && !cached.pending) }
	})
}

@(test)
vector_fill_basis_applies_dpi_once :: proc(t: ^testing.T) {
	entry := Vector_Path_Entry{morph = Vector_Identity}
	linear := [4]f64{2, 0, 0, 2}
	testing.expect_value(t, vector_path_fill_gpu_morph(&entry, Vector_Identity, linear, linear), Vector_Identity)
	entry.morph = {1, 0, 0, 1, 3, 4}
	testing.expect_value(t, vector_path_fill_gpu_morph(&entry, Vector_Identity, linear, linear), Vector_Transform{1, 0, 0, 1, 6, 8})
}

@(test)
vector_single_fill_cache_checks_policy_and_state :: proc(t: ^testing.T) {
	entry := Vector_Path_Entry{}
	entry.cache = make([dynamic]Vector_Path_Cache)
	defer delete(entry.cache)
	linear := [4]f64{1, 0, 0, 1}
	append(&entry.cache, Vector_Path_Cache{
		linear = linear, rule = .Nonzero, op = .Fill,
		policy_revision = VECTOR_GEOMETRY_POLICY_REVISION, valid = true,
	})
	// The common single-slot lookup must work without a hash table.
	testing.expect_value(t, vector_path_find_cache_index(&entry, linear, .Nonzero), 0)
	testing.expect_value(t, vector_path_find_cache_index(&entry, linear, .Even_Odd), -1)
	testing.expect_value(t, vector_path_find_cache_index(&entry, {2, 0, 0, 2}, .Nonzero), -1)
	entry.cache[0].valid = false
	testing.expect_value(t, vector_path_find_cache_index(&entry, linear, .Nonzero), -1)
	testing.expect_value(t, vector_path_find_cache_index(&entry, linear, .Nonzero, require_valid = false), 0)
	entry.cache[0].pending = true
	testing.expect_value(t, vector_path_find_cache_index(&entry, linear, .Nonzero, require_valid = false), -1)
	entry.cache[0].pending = false
	entry.cache[0].policy_revision = 0
	testing.expect_value(t, vector_path_find_cache_index(&entry, linear, .Nonzero, require_valid = false), -1)
}

@(test)
vector_svg_path_reuses_slots_and_skips_rehash_on_hit :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		commands := [4]Vector_Path_Command{
			{kind = .Move, points = {{0, 0}, {}, {}}},
			{kind = .Line, points = {{10, 0}, {}, {}}},
			{kind = .Line, points = {{5, 10}, {}, {}}},
			{kind = .Close},
		}
		first, err := vector_svg_path(commands[:])
		testing.expect_value(t, err, Vector_Error.None)
		second, err2 := vector_svg_path(commands[:])
		testing.expect_value(t, err2, Vector_Error.None)
		testing.expect_value(t, first, second)
		testing.expect_value(t, len(state.vector.path_free), 0)
		testing.expect_value(t, len(state.vector.paths), 1)
		_ = Vector_Destroy_Path(first)
		testing.expect_value(t, len(state.vector.path_free), 1)
		third, err3 := vector_svg_path(commands[:])
		testing.expect_value(t, err3, Vector_Error.None)
		testing.expect_value(t, len(state.vector.paths), 1)
		testing.expect(t, third.index == 1)
	})
}

@(test)
vector_gpu_pooled_targets_reuse_quantized_size_class :: proc(t: ^testing.T) {
	with_gpu_device_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		defer vector_gpu_shutdown()
		if !vector_composition_gpu_setup(t, 64, 64) {
			return
		}
		if !vector_gpu_init(.R8G8B8A8_UNORM) { testing.expect(t, false); return }

		target: Vector_Target
		testing.expect(t, vector_target_ensure(&target, {0, 0, 10, 10}, true, false, false))
		first_w, first_h := target.alloc_w, target.alloc_h
		creates := state.vector.gpu.target_creates
		testing.expect(t, vector_target_ensure(&target, {0, 0, 12, 11}, true, false, false))
		testing.expect_value(t, state.vector.gpu.target_creates, creates)
		testing.expect(t, target.alloc_w >= first_w && target.alloc_h >= first_h)
		vector_target_release(&target, true)
	})
}

@(test)
vector_merge_submissions_coalesces_path_draws :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		state.ui.pass = .Draw
		commands := [4]Vector_Path_Command{
			{kind = .Move, points = {{0, 0}, {}, {}}},
			{kind = .Line, points = {{8, 0}, {}, {}}},
			{kind = .Line, points = {{0, 8}, {}, {}}},
			{kind = .Close},
		}
		handle, err := vector_svg_path(commands[:])
		testing.expect_value(t, err, Vector_Error.None)
		spec := Vector_Path_Tess_Spec{handle = handle, transform = Vector_Identity}
		testing.expect_value(t, Vector_Ensure_Path_Meshes([]Vector_Path_Tess_Spec{spec}), Vector_Error.None)
		items := [2]Vector_Path_Draw{
			{handle = handle, paint = Solid_Paint({255, 0, 0, 255}), transform = Vector_Identity, opacity = 1},
			{handle = handle, paint = Solid_Paint({0, 255, 0, 255}), transform = {1, 0, 0, 1, 16, 0}, opacity = 1},
		}
		testing.expect_value(t, Draw_Vector_Paths(items[:]), Vector_Error.None)
		testing.expect_value(t, len(vector_frame().draws), 1)
		testing.expect_value(t, vector_frame().draws[0].merged_commands, 2)
	})
}

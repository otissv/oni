#+test
package oni

import "core:testing"
import "core:fmt"
import "core:math"
import "core:time"
import v "./vector"

@(test)
vector_cancelled_layout_releases_revision_pins :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		for _ in 0 ..< 100 {
			asset, loaded := Load_Svg_Memory(`<svg xmlns="http://www.w3.org/2000/svg"><rect width="10" height="10"/></svg>`)
			Destroy_Svg_Load_Result(&loaded)
			instance, prepared := Prepare_Svg_Frame_Instance(asset)
			testing.expect(t, instance != nil && prepared.ok)
			Destroy_Svg_Load_Result(&prepared)
			Destroy_Svg_Asset(asset)
			testing.expect_value(t, len(state.ui.layout.svg_instances), 1)
			layout_frame_arena_reset(&state.ui.layout)
			testing.expect_value(t, len(state.ui.layout.svg_instances), 0)
		}
	})
}

@(private)
vector_expect_owned_svg_cache :: proc(t: ^testing.T) {
	bytes := u64(0)
	count := 0
	for entry, i in state.vector.paths {
		if !entry.live { continue }
		testing.expect(t, entry.svg_retained)
		testing.expect_value(t, state.vector.svg_paths[entry.svg_key], Vector_Path_Handle{u32(i + 1), entry.generation})
		bytes += u64(len(entry.commands)) * size_of(Vector_Path_Command)
		count += 1
	}
	testing.expect_value(t, len(state.vector.svg_paths), count)
	testing.expect_value(t, state.vector.svg_path_bytes, bytes)
}

@(test)
vector_svg_reuses_geometry_across_instances_and_frames :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		state.ui.pass = .Draw
		asset, result := Load_Svg_Memory(`<svg xmlns="http://www.w3.org/2000/svg"><path d="M0 0 L20 0 L10 20 Z"/></svg>`)
		defer Destroy_Svg_Asset(asset)
		defer Destroy_Svg_Load_Result(&result)
		testing.expect(t, result.ok)
		testing.expect_value(t, Draw_Svg_Asset(asset), Vector_Error.None)
		id := state.vector.next_geometry_id
		testing.expect_value(t, Draw_Svg_Asset(asset, {1, 0, 0, 1, 30, 0}), Vector_Error.None)
		testing.expect_value(t, state.vector.next_geometry_id, id)
		vector_scene_reset()
		testing.expect_value(t, Draw_Svg_Asset(asset), Vector_Error.None)
		testing.expect_value(t, state.vector.next_geometry_id, id)
	})
}

@(test)
vector_frame_budgets_include_failed_work_and_parallel_quotas :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		vector_frame().pair_tests = VECTOR_MAX_FRAME_PAIR_TESTS - 7
		vector_frame().exact_ops = VECTOR_MAX_FRAME_EXACT_OPS - 11
		jobs: [3]Vector_Tess_Job
		vector_tess_assign_exclusive_quotas(jobs[:])
		pairs, exact := 0, 0
		for job in jobs { pairs += job.limits.max_pair_tests; exact += job.limits.max_exact_ops }
		testing.expect_value(t, pairs, 7)
		testing.expect_value(t, exact, 11)
		vector_frame().pair_tests = VECTOR_MAX_FRAME_PAIR_TESTS
		vector_frame().exact_ops = VECTOR_MAX_FRAME_EXACT_OPS
		exhausted: [1]Vector_Tess_Job
		exhausted[0].limits = v.DEFAULT_LIMITS
		vector_tess_assign_exclusive_quotas(exhausted[:])
		testing.expect_value(t, exhausted[0].limits.max_pair_tests, 0)
		testing.expect_value(t, exhausted[0].limits.max_exact_ops, 0)
		vector_frame().new_segments = VECTOR_MAX_NEW_SEGMENTS
		_, err := vector_path_frame_tess_limits()
		testing.expect_value(t, err, Vector_Error.Limit_Exceeded)
	})
}

@(test)
vector_stroke_cache_accounts_owned_dash_storage :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		state.ui.pass = .Draw
		commands := vector_tess_test_triangle()
		handle, err := Vector_Create_Path(commands[:])
		testing.expect_value(t, err, Vector_Error.None)
		stroke := Vector_Default_Stroke
		stroke.dash = []f64{2, 3, 4, 5}
		testing.expect_value(t, Draw_Vector_Path(handle, Solid_Paint({255, 0, 0, 255}), op = .Stroke, stroke = stroke), Vector_Error.None)
		entry := vector_path_entry(handle)
		bytes := u64(cap(entry.cache)) * size_of(Vector_Path_Cache)
		for cached in entry.cache { bytes += vector_path_cache_bytes(cached.mesh) + u64(len(cached.stroke.dash)) * size_of(f64) }
		testing.expect_value(t, state.vector.path_cache_bytes, bytes)
		testing.expect_value(t, Vector_Destroy_Path(handle), Vector_Error.None)
		testing.expect_value(t, state.vector.path_cache_bytes, u64(0))
	})
}

@(test)
vector_prefetch_processes_multiple_bounded_bursts :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		// Fill draws share one DPI×zoom basis mesh; use distinct path handles so
		// each prefetch job installs its own geometry and spans multiple bursts.
		handles := make([]Vector_Path_Handle, VECTOR_TESS_MAX_JOBS_PER_BURST + 1)
		defer {
			for handle in handles {
				_ = Vector_Destroy_Path(handle)
			}

			delete(handles)
		}

		for i in 0 ..< len(handles) {
			commands := vector_tess_test_triangle()
			commands[0].points[0].x += f64(i) * 0.01
			handle, err := Vector_Create_Path(commands[:])
			testing.expect_value(t, err, Vector_Error.None)
			handles[i] = handle
		}

		specs := make([]Vector_Path_Tess_Spec, len(handles))
		defer delete(specs)
		for &spec, i in specs {
			spec = {handle = handles[i], transform = Vector_Identity}
		}

		testing.expect_value(t, Vector_Prefetch_Paths(specs), Vector_Error.None)
		testing.expect_value(t, state.vector.next_geometry_id, u64(len(specs)))
	})
}

@(test)
vector_canonical_dense_geometry_fits_frame_budgets :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		state.ui.pass = .Draw
		static: [8][4]Vector_Path_Handle
		for variant in 0 ..< 8 {
			for part in 0 ..< 4 {
				commands := vector_benchmark_circle(part, 3.5, f64(variant))
				handle, err := Vector_Create_Path(commands[:])
				testing.expect_value(t, err, Vector_Error.None)
				static[variant][part] = handle
			}
		}
		items := make([]Vector_Path_Draw, 2048 * 4)
		defer delete(items)
		for icon in 0 ..< 2048 {
			for part in 0 ..< 4 {
				handle := static[icon % 8][part]
				if icon >= 1536 {
					commands := vector_benchmark_morph(123, icon, part)
					var_err: Vector_Error
					handle, var_err = Vector_Create_Path(commands[:])
					testing.expect_value(t, var_err, Vector_Error.None)
				}
				items[icon * 4 + part] = {handle = handle, paint = Solid_Paint({120, 140, 220, 255}), opacity = .8, transform = vector_benchmark_transform(123, icon, f64(64 + (icon % 64) * 28), f64(100 + (icon / 64) * 28))}
			}
		}
		err := Draw_Vector_Paths(items)
		testing.expectf(t, err == .None, "dense geometry failed: %v pairs=%d exact=%d last_usage=%v last_limits=%v", err, vector_frame().pair_tests, vector_frame().exact_ops, state.vector.last_build_usage, state.vector.last_build_limits)
		testing.expect_value(t, len(vector_frame().commands), 8192)
	})
}

@(test)
vector_cache_eviction_preserves_pending_slot_indices :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		state.ui.pass = .Draw
		commands := vector_tess_test_triangle()
		handle, created := Vector_Create_Path(commands[:])
		testing.expect_value(t, created, Vector_Error.None)
		testing.expect_value(t, Draw_Vector_Path(handle, Solid_Paint({255, 0, 0, 255})), Vector_Error.None)
		entry := vector_path_entry(handle)
		job, need, err := vector_path_build_miss_job(handle, entry, {2, 0, 0, 2}, .Nonzero)
		defer vector_path_cancel_job(&job)
		testing.expect(t, need)
		testing.expect_value(t, err, Vector_Error.None)
		slot := job.cache_index
		first_bytes := vector_path_cache_bytes(entry.cache[0].mesh)
		testing.expect(t, vector_path_evict_cache(VECTOR_CPU_CACHE_BUDGET - (state.vector.path_cache_bytes - first_bytes)))
		testing.expect(t, entry.cache[slot].pending)
		jobs := [1]Vector_Tess_Job{job}
		vector_tess_assign_exclusive_quotas(jobs[:])
		vector_tessellate_jobs_serial(jobs[:])
		job = jobs[0]
		testing.expect_value(t, vector_path_install_tess_job(&job), Vector_Error.None)
		testing.expect(t, entry.cache[slot].valid && !entry.cache[slot].pending)
	})
}

@(test)
vector_composition_releases_only_consumed_child_targets :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		defer vector_gpu_shutdown()
		append(&vector_frame().records, Vector_Record{kind = .Group, next = -1})
		append(&vector_gpu_frame().outputs, Vector_GPU_Record{content = 0, mask = 1})
		for _ in 0 ..< 3 { append(&vector_gpu_frame().pool, Vector_Target{in_use = true, used_this_encode = true}) }
		vector_gpu_release_list_outputs(0)
		testing.expect(t, !vector_gpu_frame().pool[0].in_use && !vector_gpu_frame().pool[1].in_use)
		testing.expect(t, vector_gpu_frame().pool[2].in_use)
		testing.expect(t, vector_gpu_frame().pool[0].used_this_encode)
		testing.expect_value(t, vector_gpu_frame().outputs[0], Vector_GPU_Record{content = -1, mask = -1})
	})
}

@(test)
vector_imported_dense_geometry_fits_frame_budgets :: proc(t: ^testing.T) {
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		state.ui.pass = .Draw
		assets: [8]Svg_Asset
		defer for asset in assets { Destroy_Svg_Asset(asset) }
		for &asset, i in assets {
			loaded_asset, result := Load_Svg_File(fmt.tprintf("fixtures/vector/benchmark/icon-%d.svg", i))
			testing.expect(t, result.ok)
			Destroy_Svg_Load_Result(&result)
			asset = loaded_asset
		}
		profile_start := time.tick_now()
		for icon in 0 ..< 2048 {
			asset := assets[icon % 8]
			phase := 123.0 / 60 + f64(icon) * .0137
			color := RGBA{u8(120 + 100 * math.sin(phase)), u8(120 + 100 * math.cos(phase)), 220, 255}
			overrides: [8]Svg_Override
			commands: [4][36]Vector_Path_Command
			for part in 0 ..< 4 {
				target, _ := Svg_Lookup_Element(asset, fmt.tprintf("p%d", part))
				overrides[part] = {target = target, property = .Fill, paint = Solid_Paint(color)}
				if icon >= 1536 { commands[part] = vector_benchmark_morph(123, icon, part); overrides[part + 4] = {target = target, property = .Path, commands = commands[part][:]} }
			}
			count := icon >= 1536 ? 8 : 4
			err := Draw_Svg_Asset(asset, vector_benchmark_transform(123, icon, f64(64 + (icon % 64) * 28), f64(100 + (icon / 64) * 28)), f32(.8 + .2 * math.sin(phase)), overrides[:count])
			if err != .None { testing.expectf(t, false, "imported dense rejection at %d: %v SVG usage=%v exact=%d", icon, err, vector_frame().svg_usage, vector_frame().exact_ops); return }
		}
		if #config(ONI_VECTOR_CPU_PROFILE, false) { fmt.printf("Imported SVG CPU preparation only: %.3f ms\n", time.duration_milliseconds(time.tick_since(profile_start))) }
		testing.expect_value(t, len(vector_frame().commands), 8192)
	})
}

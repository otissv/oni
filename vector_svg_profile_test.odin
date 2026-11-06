#+test
package oni

import "core:fmt"
import "core:testing"
import "core:time"
import "core:math"

@(private)
svg_profile_collect_ms, svg_profile_draw_ms: f64

@(private)
svg_profile_setup_ms, svg_profile_cleanup_ms: f64

@(private)
svg_profile_instances :: proc() {
	for icon in 0 ..< 2048 {
		setup_start := time.tick_now()
		phase := f64(vector_benchmark_m8.frame) / 60 + f64(icon) * .0137
		asset := vector_benchmark_m8.assets[icon % 8]
		color := RGBA{u8(120 + 100 * math.sin(phase)), u8(120 + 100 * math.cos(phase)), 220, 255}
		overrides := make([dynamic]Svg_Override, context.temp_allocator)
		for part in 0 ..< 4 {
			target, _ := Svg_Lookup_Element(asset, fmt.tprintf("p%d", part))
			append(&overrides, Svg_Override{target = target, property = .Fill, paint = Solid_Paint(color)})
		}
		if icon >= 1536 {
			for part in 0 ..< 4 {
				target, _ := Svg_Lookup_Element(asset, fmt.tprintf("p%d", part))
				append(&overrides, Svg_Override{target = target, property = .Path, commands = vector_benchmark_m8.morph_commands[icon - 1536][part][:]})
			}
		}
		svg_profile_setup_ms += time.duration_milliseconds(time.tick_since(setup_start))
		start := time.tick_now()
		instance, result := Prepare_Svg_Instance(asset, overrides[:])
		vector_benchmark_m8.prepare_ms += time.duration_milliseconds(time.tick_since(start))
		if !result.ok { vector_benchmark_m8.error = Svg_Result_Error(result); return }
		items := make([dynamic]Vector_Path_Draw, context.temp_allocator)
		start = time.tick_now()
		_ = draw_svg_collect_paths(instance.roots, vector_benchmark_transform(vector_benchmark_m8.frame, icon, f64(64 + icon % 64 * 28), f64(100 + icon / 64 * 28)), 1, &items)
		svg_profile_collect_ms += time.duration_milliseconds(time.tick_since(start))
		start = time.tick_now()
		err := Draw_Vector_Paths(items[:])
		if err != .None { vector_benchmark_m8.error = err }
		svg_profile_draw_ms += time.duration_milliseconds(time.tick_since(start))
		cleanup_start := time.tick_now()
		Destroy_Svg_Instance(instance)
		Destroy_Svg_Load_Result(&result)
		svg_profile_cleanup_ms += time.duration_milliseconds(time.tick_since(cleanup_start))
	}
}

// CPU-only diagnostic. The frozen GPU workloads remain the acceptance gate.
@(test)
vector_svg_cpu_profile :: proc(t: ^testing.T) {
	if !#config(ONI_VECTOR_SVG_CPU_PROFILE, false) { return }
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		benchmark := new(Vector_Benchmark_M8)
		defer free(benchmark)
		vector_benchmark_m8 = benchmark
		defer vector_benchmark_m8 = nil
		for i in 0 ..< 8 {
			asset, loaded := Load_Svg_File(fmt.tprintf("fixtures/vector/benchmark/icon-%d.svg", i))
			testing.expect(t, loaded.ok)
			Destroy_Svg_Load_Result(&loaded)
			benchmark.assets[i] = asset
		}
		defer for asset in benchmark.assets { Destroy_Svg_Asset(asset) }
		elapsed, prepare, collect, draw, setup, cleanup, generation: f64
		for frame in 0 ..< 240 {
			free_all(context.temp_allocator)
			vector_scene_reset()
			state.ui.pass = .Draw
			state.ui.frame += 1
			benchmark.frame = frame
			benchmark.prepare_ms = 0
			svg_profile_collect_ms, svg_profile_draw_ms = 0, 0
			svg_profile_setup_ms, svg_profile_cleanup_ms = 0, 0
			start := time.tick_now()
			for icon in 0 ..< 512 {
				for part in 0 ..< 4 { benchmark.morph_commands[icon][part] = vector_benchmark_morph(frame, icon + 1536, part) }
			}
			generated := time.duration_milliseconds(time.tick_since(start))
			svg_profile_instances()
			if frame >= 120 {
				elapsed += time.duration_milliseconds(time.tick_since(start))
				prepare += benchmark.prepare_ms
				collect += svg_profile_collect_ms
				draw += svg_profile_draw_ms
				setup += svg_profile_setup_ms
				cleanup += svg_profile_cleanup_ms
				generation += generated
			}
		}
		testing.expect_value(t, benchmark.error, Vector_Error.None)
		fmt.printf("SVG CPU average %.3f ms, prepare %.3f ms, paths %d, command bytes %d, mesh bytes %d\n", elapsed / 120, prepare / 120, len(state.vector.svg_paths), state.vector.svg_path_bytes, state.vector.path_cache_bytes)
		fmt.printf("SVG collect %.3f ms, draw %.3f ms\n", collect / 120, draw / 120)
		fmt.printf("SVG setup %.3f, cleanup %.3f, generation %.3f, override bytes %d\n", setup / 120, cleanup / 120, generation / 120, size_of(Svg_Override))
		fmt.printf("SVG segments %d triangles %d exact %d\n", vector_frame().new_segments, vector_frame().new_triangles, vector_frame().exact_ops)
	})
}

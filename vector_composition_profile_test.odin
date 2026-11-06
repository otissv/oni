#+test
package oni

import "core:testing"
import "core:time"
import "core:fmt"
import "core:math"
import "core:slice"
import "base:intrinsics"

@(test)
vector_composition_cpu_profile :: proc(t: ^testing.T) {
	if !#config(ONI_VECTOR_COMPOSITION_CPU_PROFILE, false) { return }
	with_ui_env(t, proc(t: ^testing.T) {
		defer vector_scene_shutdown()
		asset, loaded := Load_Svg_File("fixtures/vector/benchmark/composition.svg")
		defer Destroy_Svg_Asset(asset)
		defer Destroy_Svg_Load_Result(&loaded)
		testing.expect(t, loaded.ok)
		alpha, _ := Svg_Lookup_Element(asset, "alpha-shape")
		luma, _ := Svg_Lookup_Element(asset, "luma-shape")
		outer, _ := Svg_Lookup_Element(asset, "outer")
		inner, _ := Svg_Lookup_Element(asset, "inner")
		prepare, build, record: f64
		for frame in 0 ..< 120 {
			free_all(context.temp_allocator)
			vector_scene_reset()
			state.ui.pass = .Draw
			state.ui.frame += 1
			for i in 0 ..< 256 {
				phase := f64(frame) / 60 + f64(i) * .03
				overrides := [4]Svg_Override{
					{target = alpha, property = .Transform, transform = {1, 0, 0, 1, 2 * math.sin(phase), 2 * math.cos(phase)}},
					{target = luma, property = .Transform, transform = {1, 0, 0, 1, 2 * math.cos(phase * .7), 2 * math.sin(phase * .7)}},
					{target = outer, property = .Opacity, opacity = .7 + .2 * math.cos(phase * .7)},
					{target = inner, property = .Opacity, opacity = .6 + .2 * math.sin(phase)},
				}
				start := time.tick_now()
				instance, result := Prepare_Svg_Instance(asset, overrides[:])
				testing.expect(t, result.ok)
				defer Destroy_Svg_Instance(instance)
				defer Destroy_Svg_Load_Result(&result)
				prepared := time.tick_now()
				nodes := make([dynamic]Vector_Node, context.temp_allocator)
				testing.expect_value(t, draw_svg_build_nodes(instance.roots, {1, 0, 0, 1, f64(208 + i % 16 * 96), f64(36 + i / 16 * 64)}, &nodes), Vector_Error.None)
				built := time.tick_now()
				testing.expect_value(t, Draw_Vector_Scene({nodes = nodes[:], opacity = 1}), Vector_Error.None)
				if frame >= 60 {
					prepare += time.duration_milliseconds(time.tick_diff(start, prepared))
					build += time.duration_milliseconds(time.tick_diff(prepared, built))
					record += time.duration_milliseconds(time.tick_since(built))
				}
			}
		}
		fmt.printf("Composition CPU: prepare %.3f build %.3f record %.3f ms\n", prepare / 60, build / 60, record / 60)
	})
}

@(private)
vector_svg_current_profile_ui :: proc() {
	if ui_pass() == .Draw { vector_benchmark_m8_instances() }
}

@(test)
vector_svg_current_cpu_profile :: proc(t: ^testing.T) {
	if !#config(ONI_VECTOR_SVG_CURRENT_CPU_PROFILE, false) { return }
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
		generation, recording, prepare: f64
		for frame in 0 ..< 240 {
			free_all(context.temp_allocator)
			ui_begin_frame()
			benchmark.frame, benchmark.prepare_ms = frame, 0
			start := time.tick_now()
			for icon in 0 ..< 512 {
				for part in 0 ..< 4 { benchmark.morph_commands[icon][part] = vector_benchmark_morph(frame, icon + 1536, part) }
			}
			generated := time.tick_now()
			render(vector_svg_current_profile_ui)
			if frame >= 120 {
				generation += time.duration_milliseconds(time.tick_diff(start, generated))
				recording += time.duration_milliseconds(time.tick_since(generated))
				prepare += benchmark.prepare_ms
			}
			batch_reset()
		}
		testing.expect_value(t, benchmark.error, Vector_Error.None)
		fmt.printf("Current SVG CPU average: generate %.3f record %.3f (prepare %.3f) ms\n", generation / 120, recording / 120, prepare / 120)
	})
}

@(private)
vector_svg_fixed_cost_sink: u64

@(private)
vector_svg_consume_profile_overrides :: #force_no_inline proc(overrides: []Svg_Override) {
	value := u64(0)
	for &override in overrides {
		value += u64(override.target.index)
		if override.property == .Path { value += u64(len(override.commands)) }
		if override.property == .Fill { value += u64(override.paint.solid.r) }
	}
	intrinsics.volatile_store(&vector_svg_fixed_cost_sink, value)
}

@(private)
vector_svg_fixed_cost_profile_ui :: proc() {
	if ui_pass() != .Draw { return }
	for icon in 0 ..< 2048 {
		phase := f64(vector_benchmark_m8.frame) / 60 + f64(icon) * .0137
		transform := vector_benchmark_isolated_transform(.Full, vector_benchmark_m8.frame, icon,
			f64(64 + icon % 64 * 28), f64(100 + icon / 64 * 28))
		opacity := f32(.8 + .2 * math.sin(phase))
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
		start := time.tick_now()
		vector_svg_consume_profile_overrides(overrides[:])
		vector_benchmark_m8.prepare_ms += time.duration_milliseconds(time.tick_since(start))
		intrinsics.volatile_store(&vector_svg_fixed_cost_sink, transmute(u64)transform[0] + u64(opacity * 1000))
	}
}

// Diagnostic lower-bound estimate: input generation, property construction,
// lookups and the frozen per-instance timers, without SVG preparation or draw.
@(test)
vector_svg_fixed_cost_profile :: proc(t: ^testing.T) {
	if !#config(ONI_VECTOR_SVG_FIXED_COST_PROFILE, false) { return }
	with_ui_env(t, proc(t: ^testing.T) {
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
		times: [600]f64
		for frame in 0 ..< 720 {
			free_all(context.temp_allocator)
			start := time.tick_now()
			ui_begin_frame()
			benchmark.frame = frame
			for icon in 0 ..< 512 {
				for part in 0 ..< 4 { benchmark.morph_commands[icon][part] = vector_benchmark_morph(frame, icon + 1536, part) }
			}
			render(vector_svg_fixed_cost_profile_ui)
			batch_reset()
			if frame >= 120 { times[frame - 120] = time.duration_milliseconds(time.tick_since(start)) }
		}
		slice.sort(times[:])
		fmt.printf("Frozen SVG fixed input/timer CPU: p50 %.3f p95 %.3f ms (excludes SVG prepare, draw, ordinary UI and GPU encode)\n", times[299], times[569])
	})
}

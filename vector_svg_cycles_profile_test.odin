#+build amd64
#+test
package oni

import "core:fmt"
import "core:math"
import "core:slice"
import "core:testing"
import "core:time"
import x86 "core:simd/x86"

@(private)
svg_profile_cycles :: #force_inline proc "contextless" () -> u64 {
	aux: u32
	return x86.__rdtscp(&aux)
}

// Diagnostic only; the frozen complete GPU workload remains the acceptance gate.
@(test)
vector_svg_cycle_stage_profile :: proc(t: ^testing.T) {
	if !#config(ONI_VECTOR_SVG_CYCLE_PROFILE, false) { return }
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
		layout_frame_arena_push_block(&state.ui.render_scratch, 0)
		context.temp_allocator = layout_frame_arena_chain_allocator(&state.ui.render_scratch)
		samples: [6][240]f64
		wall_start := time.tick_now()
		cycle_start := svg_profile_cycles()
		for frame in 0 ..< 360 {
			ui_begin_frame()
			vector_scene_reset()
			state.ui.pass = .Draw
			benchmark.frame = frame
			stages: [6]u64
			start := svg_profile_cycles()
			for icon in 0 ..< 512 {
				for part in 0 ..< 4 { benchmark.morph_commands[icon][part] = vector_benchmark_morph(frame, icon + 1536, part) }
			}
			stages[0] = svg_profile_cycles() - start
			for icon in 0 ..< 2048 {
				start = svg_profile_cycles()
				phase := f64(frame) / 60 + f64(icon) * .0137
				transform := vector_benchmark_transform(frame, icon, f64(64 + icon % 64 * 28), f64(100 + icon / 64 * 28))
				opacity := f32(.8 + .2 * math.sin(phase))
				asset := benchmark.assets[icon % 8]
				color := RGBA{u8(120 + 100 * math.sin(phase)), u8(120 + 100 * math.cos(phase)), 220, 255}
				overrides := make([dynamic]Svg_Override, context.temp_allocator)
				for part in 0 ..< 4 {
					target, _ := Svg_Lookup_Element(asset, fmt.tprintf("p%d", part))
					append(&overrides, Svg_Override{target = target, property = .Fill, paint = Solid_Paint(color)})
				}
				if icon >= 1536 {
					for part in 0 ..< 4 {
						target, _ := Svg_Lookup_Element(asset, fmt.tprintf("p%d", part))
						append(&overrides, Svg_Override{target = target, property = .Path, commands = benchmark.morph_commands[icon - 1536][part][:]})
					}
				}
				setup_end := svg_profile_cycles()
				prepare_start := time.tick_now()
				prepare_cycles := svg_profile_cycles()
				instance, result := Prepare_Svg_Instance(asset, overrides[:])
				prepare_end := svg_profile_cycles()
				benchmark.prepare_ms += time.duration_milliseconds(time.tick_since(prepare_start))
				if !result.ok { testing.expect(t, false); Destroy_Svg_Load_Result(&result); Destroy_Svg_Instance(instance); return }
				draw_start := svg_profile_cycles()
				err := Draw_Svg_Instance(instance, transform, opacity)
				draw_end := svg_profile_cycles()
				Destroy_Svg_Instance(instance)
				Destroy_Svg_Load_Result(&result)
				cleanup_end := svg_profile_cycles()
				if err != .None { testing.expect_value(t, err, Vector_Error.None); return }
				stages[1] += setup_end - start
				stages[2] += prepare_end - prepare_cycles
				stages[3] += draw_end - draw_start
				stages[4] += cleanup_end - draw_end
				stages[5] += prepare_cycles - setup_end + draw_start - prepare_end
			}
			if frame >= 120 {
				for value, i in stages { samples[i][frame - 120] = f64(value) }
			}
		}
		cycles_per_ms := f64(svg_profile_cycles() - cycle_start) / time.duration_milliseconds(time.tick_since(wall_start))
		for &stage, i in samples {
			slice.sort(stage[:])
			fmt.printf("SVG cycle stage %d median %.3fms p95 %.3fms\n", i, stage[119] / cycles_per_ms, stage[227] / cycles_per_ms)
		}
	})
}

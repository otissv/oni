#+test
package oni

import "core:fmt"
import "core:encoding/json"
import "core:math"
import "core:os"
import "core:slice"
import "core:sync"
import "core:testing"
import "core:time"
import sdl "vendor:sdl3"

@(private)
Vector_Benchmark :: struct {
	engine: State,
	theme: Theme,
	static_paths: [8][4]Vector_Path_Handle,
	morph_paths: [512][4]Vector_Path_Handle,
	draw_items: []Vector_Path_Draw,
	frame: int,
	error: Vector_Error,
	isolation: Vector_Benchmark_Isolation,
}

@(private)
vector_benchmark: ^Vector_Benchmark

@(private)
vector_benchmark_circle :: proc(part: int, radius, variant: f64) -> (commands: [36]Vector_Path_Command) {
	cx, cy := f64(6 + (part % 2) * 12), f64(6 + (part / 2) * 12)
	contours := part == 0 ? 2 : 1
	segments := 32 / contours
	cursor := 0
	for contour in 0 ..< contours {
		r := contour == 1 ? radius * .45 : radius
		direction := contour == 1 ? f64(-1) : f64(1)
		step := direction * 2 * math.PI / f64(segments)
		for i in 0 ..< segments {
			a, b := f64(i) * step, f64(i + 1) * step
			pa, ta := vector_benchmark_point(part, r, variant, a)
			pb, tb := vector_benchmark_point(part, r, variant, b)
			pa += {cx, cy}; pb += {cx, cy}
			if i == 0 { commands[cursor] = {kind = .Move, points = {pa, {}, {}}}; cursor += 1 }
			commands[cursor] = {kind = .Cubic, points = {pa + ta * (step / 3), pb - tb * (step / 3), pb}}
			cursor += 1
		}
		commands[cursor] = {kind = .Close}; cursor += 1
	}
	for cursor < len(commands) { commands[cursor] = {kind = .Close}; cursor += 1 }
	return
}

@(private)
vector_benchmark_point :: proc(part: int, radius, variant, angle: f64) -> (point, tangent: [2]f64) {
	vertical := .8 + variant * .025
	if part == 1 {
		return {radius * math.cos(angle), vertical * radius * math.sin(2 * angle)}, {-radius * math.sin(angle), 2 * vertical * radius * math.cos(2 * angle)}
	}
	lobes := int(variant) % 2 == 0 ? f64(0) : f64(.3)
	r := radius * (1 + lobes * math.cos(3 * angle))
	d := -3 * radius * lobes * math.sin(3 * angle)
	return {r * math.cos(angle), vertical * r * math.sin(angle)}, {d * math.cos(angle) - r * math.sin(angle), vertical * (d * math.sin(angle) + r * math.cos(angle))}
}

@(private)
vector_benchmark_ui :: proc() {
	draw_push_screen()
	defer draw_pop_screen()
	base := style_root(.SCREEN, {0, 0, 1920, 1080})
	ui_push_style(base)
	defer ui_pop_style()
	vector_benchmark_frozen_ui_labels()
	if ui_pass() == .Draw {
		items := vector_benchmark.draw_items
		for slot in 0 ..< vector_benchmark_icon_count(vector_benchmark.isolation) {
			icon := vector_benchmark_source_icon(vector_benchmark.isolation, slot)
			x := f32(64 + (icon % 64) * 28)
			y := f32(100 + (icon / 64) * 28)
			phase := f64(vector_benchmark.frame) / 60 + f64(icon) * 0.0137
			transform := vector_benchmark_isolated_transform(vector_benchmark.isolation, vector_benchmark.frame, icon, f64(x), f64(y))
			colour := RGBA{u8(120 + 100 * math.sin(phase)), u8(120 + 100 * math.cos(phase)), 220, 255}
			opacity := f32(0.8 + 0.2 * math.sin(phase))
			for part in 0 ..< 4 {

				items[slot * 4 + part] = {
					handle = vector_benchmark.morph_paths[icon - 1536][part] if vector_benchmark_uses_morph(vector_benchmark.isolation, icon) else vector_benchmark.static_paths[icon % 8][part],
					paint = Solid_Paint(colour),
					transform = transform,
					opacity = opacity,
				}
			}
		}
		if err := Draw_Vector_Paths(items); err != .None {
			vector_benchmark.error = err
		}
	}
}

// Opt-in: compile this test in release mode with scripts/benchmark_vector.sh.
// The normal correctness suite does not claim to have run the performance gate.
@(test)
vector_dense_scene_benchmark :: proc(t: ^testing.T) {
	if !#config(ONI_VECTOR_BENCHMARK, false) {
		return
	}
	sync.mutex_lock(&test_global_state_guard)
	defer sync.mutex_unlock(&test_global_state_guard)
	defer free_all(context.temp_allocator)
	benchmark := new(Vector_Benchmark)
	defer {
		delete(benchmark.draw_items)
		free(benchmark)
	}
	ISOLATION :: #config(ONI_VECTOR_BENCHMARK_ISOLATION, "full")
	mode, valid_mode := vector_benchmark_isolation(ISOLATION)
	testing.expect(t, valid_mode && (mode == .Full || mode == .Transform_Only || mode == .Morph_Only), "Invalid M2 isolation mode")
	if !valid_mode || (mode != .Full && mode != .Transform_Only && mode != .Morph_Only) { return }
	benchmark.isolation = mode
	icon_count := vector_benchmark_icon_count(mode)
	benchmark.draw_items = make([]Vector_Path_Draw, icon_count * 4)
	saved_state, saved_theme := state, theme
	defer {
		state, theme = saved_state, saved_theme
		widget_ctx_sync()
		vector_benchmark = nil
	}
	vector_benchmark = benchmark
	state, theme = &benchmark.engine, &benchmark.theme
	widget_ctx_sync()
	if !sdl.Init({.VIDEO}) {
		testing.expectf(t, false, "Benchmark video init failed: %s", sdl.GetError())
		return
	}
	defer sdl.Quit()
	state.gpu = gpu_create_device(false)
	testing.expect(t, state.gpu != nil)
	if state.gpu == nil {
		return
	}
	defer {
		ui_shutdown()
		shortcut_shutdown()
		error_shutdown()
		settings_shutdown()
		font_shutdown()
		vector_scene_shutdown()
		assets_shutdown()
		gpu_destroy()
		sdl.DestroyGPUDevice(state.gpu)
		state.gpu = nil
	}
	state.dpi = {logical_w = 1920, logical_h = 1080, drawable_w = 1920, drawable_h = 1080, scale = 1}
	state.view = view_default()
	if !vector_benchmark_init_ui_gpu() { testing.expect(t, false, "Benchmark GPU setup failed"); return }
	assets_init(state.gpu)
	batch_init()
	ui_init()
	gpu_update_projection(state.dpi)
	family, font_ok := font_register_family("InterBenchmark", {{path = "fixtures/fonts/Inter-VariableFont_opsz,wght.ttf", style = .NORMAL, weight = .Normal}})
	testing.expect(t, font_ok)
	if !font_ok {
		return
	}
	theme.font_body = font_with_size(family, 18)
	for variant in 0 ..< 8 {
		for part in 0 ..< 4 {
			commands := vector_benchmark_circle(part, 3.5, f64(variant))
			handle, err := Vector_Create_Path(commands[:])
			testing.expect_value(t, err, Vector_Error.None)
			benchmark.static_paths[variant][part] = handle
		}
	}
	for icon in 0 ..< 512 {
		for part in 0 ..< 4 {
			commands := vector_benchmark_morph(0, icon + 1536, part)
			handle, err := Vector_Create_Path(commands[:])
			testing.expect_value(t, err, Vector_Error.None)
			benchmark.morph_paths[icon][part] = handle
		}
	}
	WARMUP :: #config(ONI_VECTOR_BENCHMARK_WARMUP, 120)
	FRAMES :: #config(ONI_VECTOR_BENCHMARK_FRAMES, 1800)
	cpu_times := make([]f64, FRAMES)
	defer delete(cpu_times)
	update_times := make([]f64, FRAMES)
	paint_times := make([]f64, FRAMES)
	encode_times := make([]f64, FRAMES)
	fence_times := make([]f64, FRAMES)
	upload_times := make([]f64, FRAMES)
	record_times := make([]f64, FRAMES)
	defer delete(update_times)
	defer delete(paint_times)
	defer delete(encode_times)
	defer delete(fence_times)
	defer delete(upload_times)
	defer delete(record_times)
	start := time.tick_now()
	last_segments, last_triangles, last_pairs, last_exact := 0, 0, 0, 0
	for frame in 0 ..< WARMUP + FRAMES {
		if frame == WARMUP {
			for &slot in state.vector.gpu.frames {
				if slot.fence != nil {
					testing.expect(t, sdl.WaitForGPUFences(state.gpu, true, &slot.fence, 1))
				}
			}
			start = time.tick_now()
		}
		cpu_start := time.tick_now()
		free_all(context.temp_allocator)
		ui_begin_frame()
		benchmark.frame = frame
		if mode != .Transform_Only {
			vector_benchmark_ensure_bases()
			handles: [2048]Vector_Path_Handle
			n := 0
			for icon in 0 ..< 512 {
				for part in 0 ..< 4 {
					commands, borrow_err := Vector_Borrow_Path_Commands(benchmark.morph_paths[icon][part])
					testing.expect_value(t, borrow_err, Vector_Error.None)
					vector_benchmark_morph_into(frame, icon + 1536, part, commands)
					handles[n] = benchmark.morph_paths[icon][part]
					n += 1
				}
			}
			testing.expect_value(t, Vector_Path_Geometry_Changed_Many(handles[:n]), Vector_Error.None)
			// Remesh morphs before Draw so paint is mostly cache-hit recording.
			specs := make([]Vector_Path_Tess_Spec, n, context.temp_allocator)
			for i in 0 ..< n {
				specs[i] = {handle = handles[i], transform = {1, 0, 0, 1, 0, 0}, rule = .Nonzero}
			}
			testing.expect_value(t, Vector_Prefetch_Paths(specs), Vector_Error.None)
		}
		update_end := time.tick_now()
		draw_record_begin(state.dpi)
		render(vector_benchmark_ui)
		draw_record_end()
		testing.expect(t, len(state.ui.layout.nodes) >= 1, "Benchmark keeps ordinary text layout in the same frame")
		testing.expect_value(t, len(vector_frame().commands), icon_count * 4)
		testing.expect_value(t, len(vector_frame().instances), icon_count * 4)
		testing.expect(t, len(vector_frame().draws) >= 1 && len(vector_frame().draws) <= 8, "Dense scene coalesces vector submissions")
		testing.expect(t, vector_frame().atlas_vertex_count > 0 && vector_frame().atlas_index_count > 0)
		_ = texture_uploads_flush(state.gpu)
		paint_end := time.tick_now()
		cmd := vector_gpu_prepare_frame(.R8G8B8A8_UNORM, {0.02, 0.03, 0.05, 1})
		testing.expect(t, cmd != nil)
		if cmd == nil {
			return
		}
		testing.expect_value(t, Vector_Last_Error(), Vector_Error.None)
		omitted := false
		for draw in vector_frame().draws { omitted ||= draw.failed }
		testing.expect(t, !omitted, "Benchmark frame omitted a vector submission")
		root := vector_gpu_frame().root.bounds
		testing.expect(t, root.w > 0 && root.h > 0 && root.w <= 1920 && root.h <= 1080)
		encode_end := time.tick_now()
		frame_gpu := vector_gpu_frame()
		frame_gpu.fence = sdl.SubmitGPUCommandBufferAndAcquireFence(cmd)
		testing.expect(t, frame_gpu.fence != nil)
		if frame_gpu.fence == nil {
			_ = sdl.WaitForGPUIdle(state.gpu)
			return
		}
		vector_gpu_advance_frame()
		last_segments, last_triangles = vector_frame().new_segments, vector_frame().new_triangles
		last_pairs, last_exact = vector_frame().pair_tests, vector_frame().exact_ops
		batch_reset()
		batch_flip()
		if frame >= WARMUP {
			cpu_times[frame - WARMUP] = time.duration_milliseconds(time.tick_since(cpu_start))
			update_times[frame - WARMUP] = time.duration_milliseconds(time.tick_diff(cpu_start, update_end))
			paint_times[frame - WARMUP] = time.duration_milliseconds(time.tick_diff(update_end, paint_end))
			encode_times[frame - WARMUP] = time.duration_milliseconds(time.tick_diff(paint_end, encode_end))
			fence_times[frame - WARMUP] = state.vector.gpu.encode_fence_ms
			upload_times[frame - WARMUP] = state.vector.gpu.encode_upload_ms
			record_times[frame - WARMUP] = state.vector.gpu.encode_record_ms
		}
	}
	for &slot in state.vector.gpu.frames {
		if slot.fence != nil {
			testing.expect(t, sdl.WaitForGPUFences(state.gpu, true, &slot.fence, 1))
		}
	}
	elapsed := time.duration_seconds(time.tick_since(start))
	slice.sort(cpu_times)
	slice.sort(update_times)
	slice.sort(paint_times)
	slice.sort(encode_times)
	slice.sort(fence_times)
	slice.sort(upload_times)
	slice.sort(record_times)
	p95_index := min(FRAMES - 1, int(math.ceil(f64(FRAMES) * 0.95)) - 1)
	p99_index := min(FRAMES - 1, int(math.ceil(f64(FRAMES) * 0.99)) - 1)
	p95 := cpu_times[p95_index]
	p99 := cpu_times[p99_index]
	fps := f64(FRAMES) / elapsed
	complete := mode == .Full && FRAMES >= 1800 && WARMUP >= 120
	report_data := struct {
		frames, warmup: int,
		completed_fps, cpu_p95_ms, cpu_p99_ms: f64,
		full_gate_run: bool,
		error: string,
		update_p95_ms, paint_p95_ms, encode_p95_ms: f64,
		fence_p95_ms, upload_p95_ms, record_p95_ms: f64,
		backend: string,
		gpu_name, gpu_driver, gpu_driver_version: string,
		width, height, samples, icons, paths_per_icon, curves_per_path, independent_morphs: int,
		new_segments, new_triangles, pair_tests, exact_ops, failed_build_exact_ops, failed_build_exact_limit: int,
		manifest_hash: string,
		isolation: string,
	}{
		FRAMES, WARMUP, fps, p95, p99, complete, fmt.tprintf("%v", benchmark.error),
		update_times[p95_index], paint_times[p95_index], encode_times[p95_index],
		fence_times[p95_index], upload_times[p95_index], record_times[p95_index],
		string(sdl.GetGPUDeviceDriver(state.gpu)),
		string(sdl.GetStringProperty(sdl.GetGPUDeviceProperties(state.gpu), sdl.PROP_GPU_DEVICE_NAME_STRING, "unknown")),
		string(sdl.GetStringProperty(sdl.GetGPUDeviceProperties(state.gpu), sdl.PROP_GPU_DEVICE_DRIVER_NAME_STRING, "unknown")),
		string(sdl.GetStringProperty(sdl.GetGPUDeviceProperties(state.gpu), sdl.PROP_GPU_DEVICE_DRIVER_VERSION_STRING, "unknown")),
		1920, 1080, 4, icon_count, 4, 32, 0 if mode == .Transform_Only else 512,
		last_segments, last_triangles, last_pairs, last_exact, state.vector.last_build_usage.exact_ops, state.vector.last_build_limits.max_exact_ops,
		vector_benchmark_manifest_hash(),
		ISOLATION,
	}
	report, report_error := json.marshal(report_data)
	testing.expect(t, report_error == nil)
	defer delete(report)
	fmt.println(string(report))
	output := "build/test/vector-benchmark.json" if mode == .Full else fmt.tprintf("build/test/vector-benchmark-%s.json", ISOLATION)
	testing.expect(t, os.write_entire_file(output, report) == nil)
	testing.expect_value(t, benchmark.error, Vector_Error.None)
	if complete {
		testing.expectf(t, fps >= 60, "Vector throughput %.3f fps is below the 60 fps gate", fps)
		testing.expectf(t, p95 <= 4, "Vector CPU p95 %.3f ms exceeds the 4 ms gate", p95)
	}
}

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
	morph_affines: [512][4]Vector_Transform,
	draw_items: []Vector_Path_Draw,
	frame: int,
	error: Vector_Error,
}

@(private)
vector_benchmark: ^Vector_Benchmark

@(private)
vector_benchmark_circle :: proc(part: int, radius, variant: f64) -> (commands: [34]Vector_Path_Command) {
	cx := f64(6 + (part % 2) * 12)
	cy := f64(6 + (part / 2) * 12)
	step := 2 * math.PI / 32
	lobes := int(variant) % 2 == 0 ? f64(0) : f64(0.3)
	vertical := 0.8 + variant * 0.025
	for i in 0 ..< 32 {
		a, b := f64(i) * step, f64(i + 1) * step
		ra, rb := radius * (1 + lobes * math.cos(3 * a)), radius * (1 + lobes * math.cos(3 * b))
		da, db := -3 * radius * lobes * math.sin(3 * a), -3 * radius * lobes * math.sin(3 * b)
		pa := [2]f64{cx + ra * math.cos(a), cy + vertical * ra * math.sin(a)}
		pb := [2]f64{cx + rb * math.cos(b), cy + vertical * rb * math.sin(b)}
		ta := [2]f64{da * math.cos(a) - ra * math.sin(a), vertical * (da * math.sin(a) + ra * math.cos(a))}
		tb := [2]f64{db * math.cos(b) - rb * math.sin(b), vertical * (db * math.sin(b) + rb * math.cos(b))}
		if i == 0 { commands[0] = {kind = .Move, points = {pa, {}, {}}} }
		commands[i + 1] = {kind = .Cubic, points = {pa + ta * (step / 3), pb - tb * (step / 3), pb}}
	}
	commands[33] = {kind = .Close}
	return
}

@(private)
vector_benchmark_ui :: proc() {
	draw_push_screen()
	defer draw_pop_screen()
	base := style_root(.SCREEN, {0, 0, 1920, 1080})
	ui_push_style(base)
	defer ui_pop_style()
	if ui_pass() == .Layout {
		config := Resolved_Widget_Config{kind = .RECT, style = base.style}
		config.width = {kind = .FIXED, value = 800}
		config.height = {kind = .FIXED, value = 30}
		config.position = .ABSOLUTE
		config.x, config.y, config.x_set, config.y_set = 24, 24, true, true
		config.font, config.font_size, config.opacity = theme.font_body, 18, 1
		node := layout_push_node(UI_Id(7), config)
		layout_set_measure_text(node, "Oni native vectors: 2048 icons / 25% independent path morphs", 800)
		layout_pop_node()
	} else {
		draw_rect({16, 16, 1888, 48}, {25, 30, 45, 255})
		_ = font_draw_layout_text(layout_text_result(UI_Id(7)), {255, 255, 255, 255})
	}
	if ui_pass() == .Draw {
		items := vector_benchmark.draw_items
		for icon in 0 ..< 2048 {
			x := f32(64 + (icon % 64) * 28)
			y := f32(100 + (icon / 64) * 28)
			phase := f64(vector_benchmark.frame) / 120 + f64(icon) * 0.0137
			transform := Vector_Identity
			transform[4] = f64(x) + math.sin(phase) * 1.5
			transform[5] = f64(y) + math.cos(phase * 0.7) * 1.5
			colour := RGBA{u8(120 + 100 * math.sin(phase)), u8(120 + 100 * math.cos(phase)), 220, 255}
			opacity := f32(0.8 + 0.2 * math.sin(phase))
			for part in 0 ..< 4 {
				morph := Vector_Identity
				if icon % 4 == 0 {
					morph = vector_benchmark.morph_affines[icon / 4][part]
				}
				items[icon * 4 + part] = {
					handle = vector_benchmark.static_paths[icon % 8][part],
					paint = Solid_Paint(colour),
					transform = transform,
					opacity = opacity,
					instance_morph = morph,
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
	benchmark.draw_items = make([]Vector_Path_Draw, 2048 * 4)
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
	state.gpu_state.pipeline = gpu_create_ui_layout_pipeline(state.gpu, .R8G8B8A8_UNORM, frag_shader_code, gpu_blend_state())
	state.gpu_state.sampler = gpu_create_sampler(state.gpu)
	state.gpu_state.sampler_nearest = gpu_create_sampler(state.gpu, .NEAREST, .NEAREST)
	state.gpu_state.white_texture = gpu_create_white_texture(state.gpu)
	if state.gpu_state.pipeline == nil || state.gpu_state.sampler == nil || state.gpu_state.sampler_nearest == nil || state.gpu_state.white_texture == nil {
		testing.expect(t, false, "Benchmark GPU setup failed")
		return
	}
	assets_init(state.gpu)
	batch_init()
	ui_init()
	gpu_update_projection(state.dpi)
	family, font_ok := settings_register_fonts()
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
		for icon in 0 ..< 512 {
			phase := f64(frame) / 120 + f64(icon) * 0.0548
			for part in 0 ..< 4 {
				factor := (3.5 + 0.45 * math.sin(phase + f64(part) * 0.17)) / 3.5
				cx := f64(6 + (part % 2) * 12)
				cy := f64(6 + (part / 2) * 12)
				benchmark.morph_affines[icon][part] = {factor, 0, 0, factor, cx * (1 - factor), cy * (1 - factor)}
			}
		}
		testing.expect_value(t, len(state.vector.paths), 8 * 4)
		update_end := time.tick_now()
		draw_record_begin(state.dpi)
		render(vector_benchmark_ui)
		draw_record_end()
		testing.expect(t, len(state.ui.layout.nodes) >= 1, "Benchmark keeps ordinary text layout in the same frame")
		testing.expect_value(t, len(vector_frame().commands), 2048 * 4)
		testing.expect_value(t, len(vector_frame().instances), 2048 * 4)
		testing.expect(t, len(vector_frame().draws) >= 1 && len(vector_frame().draws) <= 8, "Dense scene coalesces vector submissions")
		testing.expect(t, len(vector_frame().vertices) > 0 && len(vector_frame().indices) > 0)
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
	complete := FRAMES >= 1800 && WARMUP >= 120
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
	}{
		FRAMES, WARMUP, fps, p95, p99, complete, fmt.tprintf("%v", benchmark.error),
		update_times[p95_index], paint_times[p95_index], encode_times[p95_index],
		fence_times[p95_index], upload_times[p95_index], record_times[p95_index],
		string(sdl.GetGPUDeviceDriver(state.gpu)),
		string(sdl.GetStringProperty(sdl.GetGPUDeviceProperties(state.gpu), sdl.PROP_GPU_DEVICE_NAME_STRING, "unknown")),
		string(sdl.GetStringProperty(sdl.GetGPUDeviceProperties(state.gpu), sdl.PROP_GPU_DEVICE_DRIVER_NAME_STRING, "unknown")),
		string(sdl.GetStringProperty(sdl.GetGPUDeviceProperties(state.gpu), sdl.PROP_GPU_DEVICE_DRIVER_VERSION_STRING, "unknown")),
		1920, 1080, 4, 2048, 4, 32, 512,
	}
	report, report_error := json.marshal(report_data)
	testing.expect(t, report_error == nil)
	defer delete(report)
	fmt.println(string(report))
	testing.expect(t, os.write_entire_file("build/test/vector-benchmark.json", report) == nil)
	testing.expect_value(t, benchmark.error, Vector_Error.None)
	if complete {
		testing.expectf(t, fps >= 60, "Vector throughput %.3f fps is below the 60 fps gate", fps)
		testing.expectf(t, p95 <= 4, "Vector CPU p95 %.3f ms exceeds the 4 ms gate", p95)
	}
}

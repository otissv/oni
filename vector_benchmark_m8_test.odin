#+test
package oni

import "core:encoding/json"
import "core:encoding/hex"
import "core:fmt"
import "core:math"
import "core:os"
import "core:slice"
import "core:sync"
import "core:testing"
import "core:time"
import "core:crypto/hash"
import sdl "vendor:sdl3"

@(private)
Vector_Benchmark_M8 :: struct {
	engine: State,
	theme: Theme,
	assets: [8]Svg_Asset,
	morph_commands: [512][4][36]Vector_Path_Command,
	frame: int,
	error: Vector_Error,
	isolation: Vector_Benchmark_Isolation,
	prepare_ms: f64,
}

@(private)
vector_benchmark_m8: ^Vector_Benchmark_M8

@(private)
vector_benchmark_m8_ui :: proc() {
	draw_push_screen()
	defer draw_pop_screen()
	base := style_root(.SCREEN, {0, 0, 1920, 1080})
	ui_push_style(base)
	defer ui_pop_style()
	vector_benchmark_frozen_ui_labels()
	if ui_pass() == .Draw {
		vector_benchmark_m8_instances()
	}
}

@(private)
vector_benchmark_m8_instances :: proc() {
	for icon in 0 ..< 2048 {
		x := f32(64 + (icon % 64) * 28)
		y := f32(100 + (icon / 64) * 28)
		phase := f64(vector_benchmark_m8.frame) / 60 + f64(icon) * 0.0137
		transform := vector_benchmark_isolated_transform(vector_benchmark_m8.isolation, vector_benchmark_m8.frame, icon, f64(x), f64(y))
		opacity := f32(0.8 + 0.2 * math.sin(phase))
		asset := vector_benchmark_m8.assets[icon % 8]
		color := RGBA{u8(120 + 100 * math.sin(phase)), u8(120 + 100 * math.cos(phase)), 220, 255}
		overrides := make([dynamic]Svg_Override, context.temp_allocator)
		for part in 0 ..< 4 { target, _ := Svg_Lookup_Element(asset, fmt.tprintf("p%d", part)); append(&overrides, Svg_Override{target = target, property = .Fill, paint = Solid_Paint(color)}) }
		if vector_benchmark_uses_morph(vector_benchmark_m8.isolation, icon) {
			morph_icon := icon - 1536
			for part in 0 ..< 4 {
				target, ok := Svg_Lookup_Element(asset, fmt.tprintf("p%d", part))
				if !ok {
					vector_benchmark_m8.error = .Invalid_Handle
					continue
				}
				append(&overrides, Svg_Override{target = target, property = .Path, commands = vector_benchmark_m8.morph_commands[morph_icon][part][:]})
			}
		}
		diagnostics: Svg_Load_Result
		prepare_start := time.tick_now()
		instance, result := Prepare_Svg_Instance(asset, overrides[:])
		vector_benchmark_m8.prepare_ms += time.duration_milliseconds(time.tick_since(prepare_start))
		diagnostics = result
		err := Svg_Result_Error(result)
		if err == .None && vector_benchmark_m8.isolation != .Svg_Prepare_Only { err = Draw_Svg_Instance(instance, transform, opacity) }
		Destroy_Svg_Instance(instance)
		if err != .None {
			if vector_benchmark_m8.error == .None { fmt.printf("SVG benchmark first rejection: instance=%d error=%v diagnostics=%v stats=%v svg_usage=%v\n", icon, err, diagnostics.diagnostics[:], vector_stats(), vector_frame().svg_usage) }
			vector_benchmark_m8.error = err
		}
		Destroy_Svg_Load_Result(&diagnostics)
	}
}

@(private)
vector_benchmark_frozen_ui_labels :: proc() {
	if ui_pass() == .Layout {
		for button in 0 ..< 32 {
			config := Resolved_Widget_Config{kind = .RECT, style = base_style_from_screen()}
			config.width = {kind = .FIXED, value = 72}
			config.height = {kind = .FIXED, value = 24}
			config.position = .ABSOLUTE
			config.x = f32(16 + (button % 8) * 80)
			config.y = f32(16 + (button / 8) * 28)
			config.x_set, config.y_set = true, true
			config.font, config.font_size = theme.font_body, 14
			node := layout_push_node(UI_Id(u32(1000 + button)), config)
			layout_set_measure_text(node, fmt.tprintf("Btn %d", button), 72)
			layout_pop_node()
		}
		for label in 0 ..< 96 {
			config := Resolved_Widget_Config{kind = .RECT, style = base_style_from_screen()}
			config.width = {kind = .FIXED, value = 120}
			config.height = {kind = .FIXED, value = 18}
			config.position = .ABSOLUTE
			config.x = f32(720 + (label % 12) * 96)
			config.y = f32(16 + (label / 12) * 20)
			config.x_set, config.y_set = true, true
			config.font, config.font_size = theme.font_body, 12
			node := layout_push_node(UI_Id(u32(2000 + label)), config)
			layout_set_measure_text(node, fmt.tprintf("Label %d", label), 120)
			layout_pop_node()
		}
	} else {
		for button in 0 ..< 32 {
			draw_rect({f32(16 + (button % 8) * 80), f32(16 + (button / 8) * 28), 72, 24}, {35, 45, 65, 255})
			_ = font_draw_layout_text(layout_text_result(UI_Id(u32(1000 + button))), {240, 240, 240, 255})
		}
		for label in 0 ..< 96 {
			_ = font_draw_layout_text(layout_text_result(UI_Id(u32(2000 + label))), {200, 210, 230, 255})
		}
	}
}

@(private)
base_style_from_screen :: proc() -> Resolved_Widget_Style {
	return style_root(.SCREEN, {0, 0, 1920, 1080}).style
}

@(private)
vector_benchmark_manifest_hash :: proc() -> string {
	data, read_err := os.read_entire_file("fixtures/vector/benchmark/manifest.toml", context.temp_allocator)
	if read_err != nil {
		return "missing"
	}
	digest := hash.hash(hash.Algorithm.SHA256, data)
	defer delete(digest)
	encoded, err := hex.encode(digest, context.temp_allocator)
	if err != nil { return "allocation-failed" }
	return string(encoded)
}

// Opt-in M8 imported-SVG dense-scene gate (scripts/benchmark_vector.sh --m8).
@(test)
vector_dense_scene_svg_benchmark :: proc(t: ^testing.T) {
	if !#config(ONI_VECTOR_BENCHMARK_M8, false) {
		return
	}
	sync.mutex_lock(&test_global_state_guard)
	defer sync.mutex_unlock(&test_global_state_guard)
	defer free_all(context.temp_allocator)
	benchmark := new(Vector_Benchmark_M8)
	defer {
		for asset in benchmark.assets {
			Destroy_Svg_Asset(asset)
		}
		free(benchmark)
	}
	ISOLATION :: #config(ONI_VECTOR_BENCHMARK_ISOLATION, "full")
	mode, valid_mode := vector_benchmark_isolation(ISOLATION)
	testing.expect(t, valid_mode && (mode == .Full || mode == .Svg_Prepare_Only || mode == .Svg_Paint_Only), "Invalid M8 isolation mode")
	if !valid_mode || (mode != .Full && mode != .Svg_Prepare_Only && mode != .Svg_Paint_Only) { return }
	benchmark.isolation = mode
	saved_state, saved_theme := state, theme
	defer {
		state, theme = saved_state, saved_theme
		widget_ctx_sync()
		vector_benchmark_m8 = nil
	}
	vector_benchmark_m8 = benchmark
	state, theme = &benchmark.engine, &benchmark.theme
	widget_ctx_sync()
	for variant in 0 ..< 8 {
		path := fmt.tprintf("fixtures/vector/benchmark/icon-%d.svg", variant)
		asset, result := Load_Svg_File(path)
		testing.expectf(t, result.ok, "%v", result.diagnostics[:])
		Destroy_Svg_Load_Result(&result)
		benchmark.assets[variant] = asset
	}
	if !sdl.Init({.VIDEO}) {
		testing.expectf(t, false, "Benchmark video init failed: %s", sdl.GetError())
		return
	}
	defer sdl.Quit()
	state.gpu = gpu_create_device(false)
	testing.expect(t, state.gpu != nil, "Benchmark requires a real GPU")
	if state.gpu == nil {
		return
	}
	defer vector_benchmark_shutdown_gpu_stack()
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
	theme.font_body = font_with_size(family, 14)
	WARMUP :: #config(ONI_VECTOR_BENCHMARK_WARMUP, 120)
	FRAMES :: #config(ONI_VECTOR_BENCHMARK_FRAMES, 1800)
	cpu_times := make([]f64, FRAMES)
	defer delete(cpu_times)
	prepare_times := make([]f64, FRAMES)
	defer delete(prepare_times)
	paint_times := make([]f64, FRAMES)
	encode_times := make([]f64, FRAMES)
	defer delete(paint_times)
	defer delete(encode_times)
	start := time.tick_now()
	for frame in 0 ..< WARMUP + FRAMES {
		if frame == WARMUP {
			vector_benchmark_wait_fences(t)
			start = time.tick_now()
		}
		cpu_start := time.tick_now()
		free_all(context.temp_allocator)
		ui_begin_frame()
		benchmark.frame = frame
		benchmark.prepare_ms = 0
		for icon in 0 ..< (512 if mode == .Full else 0) {
			for part in 0 ..< 4 { benchmark.morph_commands[icon][part] = vector_benchmark_morph(frame, icon + 1536, part) }
		}
		if mode == .Svg_Prepare_Only {
			vector_scene_reset()
			vector_benchmark_m8_instances()
			if frame >= WARMUP {
				cpu_times[frame - WARMUP] = time.duration_milliseconds(time.tick_since(cpu_start))
				prepare_times[frame - WARMUP] = benchmark.prepare_ms
			}
			continue
		}
		draw_record_begin(state.dpi)
		paint_start := time.tick_now()
		render(vector_benchmark_m8_ui)
		draw_record_end()
		_ = texture_uploads_flush(state.gpu)
		paint_end := time.tick_now()
		cmd := vector_gpu_prepare_frame(.R8G8B8A8_UNORM, {0.02, 0.03, 0.05, 1})
		testing.expect(t, cmd != nil)
		if cmd == nil {
			return
		}
		frame_gpu := vector_gpu_frame()
		vector_benchmark_validate_frame(t)
		frame_gpu.fence = sdl.SubmitGPUCommandBufferAndAcquireFence(cmd)
		testing.expect(t, frame_gpu.fence != nil)
		if frame_gpu.fence == nil { _ = sdl.WaitForGPUIdle(state.gpu); return }
		vector_gpu_advance_frame()
		encode_end := time.tick_now()
		batch_reset()
		batch_flip()
		if frame >= WARMUP {
			cpu_times[frame - WARMUP] = time.duration_milliseconds(time.tick_since(cpu_start))
			prepare_times[frame - WARMUP] = benchmark.prepare_ms
			paint_times[frame - WARMUP] = time.duration_milliseconds(time.tick_diff(paint_start, paint_end))
			encode_times[frame - WARMUP] = time.duration_milliseconds(time.tick_diff(paint_end, encode_end))
		}
	}
	vector_benchmark_wait_fences(t)
	elapsed := time.duration_seconds(time.tick_since(start))
	slice.sort(cpu_times)
	slice.sort(prepare_times)
	slice.sort(paint_times)
	slice.sort(encode_times)
	p95_index := min(FRAMES - 1, int(math.ceil(f64(FRAMES) * 0.95)) - 1)
	p95 := cpu_times[p95_index]
	fps := f64(FRAMES) / elapsed
	manifest_hash := vector_benchmark_manifest_hash()
	report_data := struct {
		workload: string,
		manifest_hash: string,
		completed_fps, cpu_p95_ms: f64,
		frames, warmup, icons: int,
		error: string,
		isolation: string,
		prepare_p95_ms, iterations_per_second: f64,
		paint_p95_ms, encode_p95_ms: f64,
	}{
		"m8-imported-svg", manifest_hash, 0 if mode == .Svg_Prepare_Only else fps, p95, FRAMES, WARMUP, 2048, fmt.tprintf("%v", benchmark.error),
		ISOLATION, prepare_times[p95_index], fps,
		paint_times[p95_index], encode_times[p95_index],
	}
	report, report_error := json.marshal(report_data)
	testing.expect(t, report_error == nil)
	defer delete(report)
	fmt.println(string(report))
	output := "build/test/vector-benchmark-m8.json" if mode == .Full else fmt.tprintf("build/test/vector-benchmark-%s.json", ISOLATION)
	testing.expect(t, os.write_entire_file(output, report) == nil)
	testing.expect_value(t, benchmark.error, Vector_Error.None)
	if mode == .Full && FRAMES >= 1800 && WARMUP >= 120 {
		testing.expectf(t, fps >= 60, "M8 throughput %.3f fps below gate", fps)
		testing.expectf(t, p95 <= 4, "M8 CPU p95 %.3f ms above gate", p95)
	}
}

@(private)
vector_benchmark_wait_fences :: proc(t: ^testing.T) {
	for &slot in state.vector.gpu.frames {
		if slot.fence != nil {
			testing.expect(t, sdl.WaitForGPUFences(state.gpu, true, &slot.fence, 1))
		}
	}
}

@(private)
vector_benchmark_validate_frame :: proc(t: ^testing.T) {
	testing.expect(t, state.gpu_state.pipeline != nil && state.gpu_state.lcd_pipeline != nil, "Benchmark must execute ordinary UI and vector batches")
	testing.expect_value(t, Vector_Last_Error(), Vector_Error.None)
	for draw in vector_frame().draws { testing.expect(t, !draw.failed, "Benchmark omitted a submission") }
}

@(private)
vector_benchmark_init_ui_gpu :: proc() -> bool {
	state.vector.gpu.format = .R8G8B8A8_UNORM
	state.gpu_state.pipeline = gpu_create_ui_layout_pipeline(state.gpu, .R8G8B8A8_UNORM, .UI_Fragment, gpu_blend_state())
	state.gpu_state.lcd_pipeline = gpu_create_lcd_pipeline(state.gpu, .R8G8B8A8_UNORM)
	state.gpu_state.sampler = gpu_create_sampler(state.gpu)
	state.gpu_state.sampler_nearest = gpu_create_sampler(state.gpu, .NEAREST, .NEAREST)
	state.gpu_state.white_texture = gpu_create_white_texture(state.gpu)
	return state.gpu_state.pipeline != nil && state.gpu_state.lcd_pipeline != nil && state.gpu_state.sampler != nil && state.gpu_state.sampler_nearest != nil && state.gpu_state.white_texture != nil
}

@(private)
vector_benchmark_shutdown_gpu_stack :: proc() {
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

@(private)
vector_benchmark_composition_ui :: proc() {
	draw_push_screen()
	defer draw_pop_screen()
	ui_push_style(style_root(.SCREEN, {0, 0, 1920, 1080}))
	defer ui_pop_style()
	vector_benchmark_frozen_ui_labels()
	if ui_pass() != .Draw { return }
	asset := vector_benchmark_m8.assets[0]
	alpha, _ := Svg_Lookup_Element(asset, "alpha-shape")
	luma, _ := Svg_Lookup_Element(asset, "luma-shape")
	outer, _ := Svg_Lookup_Element(asset, "outer")
	inner, _ := Svg_Lookup_Element(asset, "inner")
	for i in 0 ..< 256 {
		phase := f64(vector_benchmark_m8.frame) / 60 + f64(i) * .03
		overrides := [4]Svg_Override{
			{target = alpha, property = .Transform, transform = {1, 0, 0, 1, 2 * math.sin(phase), 2 * math.cos(phase)}},
			{target = luma, property = .Transform, transform = {1, 0, 0, 1, 2 * math.cos(phase * .7), 2 * math.sin(phase * .7)}},
			{target = outer, property = .Opacity, opacity = .7 + .2 * math.cos(phase * .7)},
			{target = inner, property = .Opacity, opacity = .6 + .2 * math.sin(phase)},
		}
		transform := Vector_Transform{1, 0, 0, 1, f64(208 + (i % 16) * 96), f64(36 + (i / 16) * 64)}
		if err := Draw_Svg_Asset(asset, transform, overrides = overrides[:]); err != .None { vector_benchmark_m8.error = err }
	}
}

@(test)
vector_composition_dense_benchmark :: proc(t: ^testing.T) {
	if !#config(ONI_VECTOR_BENCHMARK_COMPOSITION, false) {
		return
	}
	sync.mutex_lock(&test_global_state_guard)
	defer sync.mutex_unlock(&test_global_state_guard)
	defer free_all(context.temp_allocator)
	benchmark := new(Vector_Benchmark_M8)
	defer free(benchmark)
	defer Destroy_Svg_Asset(benchmark.assets[0])
	vector_benchmark_m8 = benchmark
	defer vector_benchmark_m8 = nil
	asset, result := Load_Svg_File("fixtures/vector/benchmark/composition.svg")
	defer Destroy_Svg_Load_Result(&result)
	testing.expect(t, result.ok)
	if !result.ok { return }
	benchmark.assets[0] = asset
	saved_state, saved_theme := state, theme
	defer {
		state, theme = saved_state, saved_theme
		widget_ctx_sync()
	}
	state, theme = &benchmark.engine, &benchmark.theme
	widget_ctx_sync()
	if !sdl.Init({.VIDEO}) {
		testing.expect(t, false, "GPU benchmark requires SDL video")
		return
	}
	defer sdl.Quit()
	state.gpu = gpu_create_device(false)
	if state.gpu == nil {
		testing.expect(t, false, "GPU benchmark requires a real GPU")
		return
	}
	defer vector_benchmark_shutdown_gpu_stack()
	state.dpi = {logical_w = 1920, logical_h = 1080, drawable_w = 1920, drawable_h = 1080, scale = 1}
	state.view = view_default()
	if !vector_benchmark_init_ui_gpu() { testing.expect(t, false, "Benchmark GPU setup failed"); return }
	assets_init(state.gpu)
	batch_init()
	ui_init()
	gpu_update_projection(state.dpi)
	family, font_ok := font_register_family("InterBenchmark", {{path = "fixtures/fonts/Inter-VariableFont_opsz,wght.ttf", style = .NORMAL, weight = .Normal}})
	testing.expect(t, font_ok)
	if !font_ok { return }
	theme.font_body = font_with_size(family, 14)
	WARMUP :: #config(ONI_VECTOR_BENCHMARK_WARMUP, 120)
	FRAMES :: #config(ONI_VECTOR_BENCHMARK_FRAMES, 1800)
	cpu_times := make([]f64, FRAMES)
	defer delete(cpu_times)
	start := time.tick_now()
	for frame in 0 ..< WARMUP + FRAMES {
		if frame == WARMUP {
			vector_benchmark_wait_fences(t)
			start = time.tick_now()
		}
		cpu_start := time.tick_now()
		free_all(context.temp_allocator)
		ui_begin_frame()
		benchmark.frame = frame
		draw_record_begin(state.dpi)
		render(vector_benchmark_composition_ui)
		draw_record_end()
		cmd := vector_gpu_prepare_frame(.R8G8B8A8_UNORM, {0.02, 0.03, 0.05, 1})
		testing.expect(t, cmd != nil)
		if cmd == nil {
			return
		}
		vector_gpu_frame().fence = sdl.SubmitGPUCommandBufferAndAcquireFence(cmd)
		vector_benchmark_validate_frame(t)
		testing.expect(t, vector_gpu_frame().fence != nil)
		if vector_gpu_frame().fence == nil { _ = sdl.WaitForGPUIdle(state.gpu); return }
		vector_gpu_advance_frame()
		batch_reset()
		batch_flip()
		if frame >= WARMUP {
			cpu_times[frame - WARMUP] = time.duration_milliseconds(time.tick_since(cpu_start))
		}
	}
	testing.expect_value(t, benchmark.error, Vector_Error.None)
	vector_benchmark_wait_fences(t)
	elapsed := time.duration_seconds(time.tick_since(start))
	slice.sort(cpu_times)
	p95_index := min(FRAMES - 1, int(math.ceil(f64(FRAMES) * 0.95)) - 1)
	p95 := cpu_times[p95_index]
	fps := f64(FRAMES) / elapsed
	stats := vector_stats()
	report_data := struct {
		workload: string,
		frames, warmup: int,
		completed_fps, cpu_p95_ms: f64,
		sample_work, peak_pool_bytes, peak_gpu_bytes: u64,
		manifest_hash: string,
	}{"m8-composition", FRAMES, WARMUP, fps, p95, stats.sample_work, stats.gpu_peak[.Intermediate_Targets], stats.gpu_peak_bytes, vector_benchmark_manifest_hash()}
	report, report_error := json.marshal(report_data)
	testing.expect(t, report_error == nil)
	defer delete(report)
	fmt.println(string(report))
	testing.expect(t, os.write_entire_file("build/test/vector-benchmark-composition.json", report) == nil)
	if FRAMES >= 1800 {
		testing.expectf(t, fps >= 60, "composition fps %.3f", fps)
		testing.expectf(t, p95 <= 4, "composition p95 %.3f", p95)
	}
}

// Opt-in no-vector UI baseline for regression tracking (compare median p95 across releases).
@(test)
vector_ordinary_ui_baseline_benchmark :: proc(t: ^testing.T) {
	if !#config(ONI_VECTOR_BENCHMARK_BASELINE, false) {
		return
	}
	sync.mutex_lock(&test_global_state_guard)
	defer sync.mutex_unlock(&test_global_state_guard)
	defer free_all(context.temp_allocator)
	benchmark := new(Vector_Benchmark_M8)
	defer free(benchmark)
	saved_state, saved_theme := state, theme
	defer {
		state, theme = saved_state, saved_theme
		widget_ctx_sync()
	}
	state, theme = &benchmark.engine, &benchmark.theme
	widget_ctx_sync()
	if !sdl.Init({.VIDEO}) {
		testing.expect(t, false, "Baseline requires SDL video")
		return
	}
	defer sdl.Quit()
	state.gpu = gpu_create_device(false)
	if state.gpu == nil {
		testing.expect(t, false, "Baseline requires a real GPU")
		return
	}
	defer vector_benchmark_shutdown_gpu_stack()
	state.dpi = {logical_w = 1920, logical_h = 1080, drawable_w = 1920, drawable_h = 1080, scale = 1}
	if !vector_benchmark_init_ui_gpu() { testing.expect(t, false, "Benchmark GPU setup failed"); return }
	state.view = view_default()
	assets_init(state.gpu)
	batch_init()
	ui_init()
	gpu_update_projection(state.dpi)
	family, font_ok := font_register_family("InterBenchmark", {{path = "fixtures/fonts/Inter-VariableFont_opsz,wght.ttf", style = .NORMAL, weight = .Normal}})
	if !font_ok {
		testing.expect(t, false, "Baseline requires the frozen font")
		return
	}
	theme.font_body = font_with_size(family, 14)
	FRAMES :: #config(ONI_VECTOR_BENCHMARK_FRAMES, 1800)
	WARMUP :: #config(ONI_VECTOR_BENCHMARK_WARMUP, 120)
	cpu_times := make([]f64, FRAMES)
	defer delete(cpu_times)
	start := time.tick_now()
	for frame in 0 ..< WARMUP + FRAMES {
		if frame == WARMUP {
			vector_benchmark_wait_fences(t)
			start = time.tick_now()
		}
		cpu_start := time.tick_now()
		free_all(context.temp_allocator)
		ui_begin_frame()
		draw_record_begin(state.dpi)
		render(vector_benchmark_ui_only)
		draw_record_end()
		_ = texture_uploads_flush(state.gpu)
		slot := vector_gpu_frame()
		testing.expect(t, vector_gpu_wait_slot_fence(slot))
		if !vector_target_ensure(&slot.root, {0, 0, 1920, 1080}, false, false, false) { testing.expect(t, false); return }
		cmd := sdl.AcquireGPUCommandBuffer(state.gpu)
		if cmd == nil { testing.expect(t, false); return }
		if !batch_upload(cmd) { _ = sdl.CancelGPUCommandBuffer(cmd); testing.expect(t, false); return }
		colour := sdl.GPUColorTargetInfo{texture = slot.root.colour, load_op = .CLEAR, store_op = .STORE, clear_color = {0.02, 0.03, 0.05, 1}}
		pass := sdl.BeginGPURenderPass(cmd, &colour, 1, nil)
		if pass == nil { _ = sdl.CancelGPUCommandBuffer(cmd); testing.expect(t, false); return }
		draw_begin(cmd, pass, state.dpi)
		batch_flush_draws()
		batch_current().cmd, batch_current().pass = nil, nil
		sdl.EndGPURenderPass(pass)
		slot.fence = sdl.SubmitGPUCommandBufferAndAcquireFence(cmd)
		testing.expect(t, slot.fence != nil)
		if slot.fence == nil { _ = sdl.WaitForGPUIdle(state.gpu); return }
		vector_gpu_advance_frame()
		batch_reset()
		batch_flip()
		if frame >= WARMUP {
			cpu_times[frame - WARMUP] = time.duration_milliseconds(time.tick_since(cpu_start))
		}
	}
	vector_benchmark_wait_fences(t)
	elapsed := time.duration_seconds(time.tick_since(start))
	slice.sort(cpu_times)
	p95_index := min(FRAMES - 1, int(math.ceil(f64(FRAMES) * 0.95)) - 1)
	report_data := struct {
		workload: string,
		frames, warmup: int,
		cpu_p95_ms, fps: f64,
		manifest_hash: string,
	}{"ordinary-ui-baseline", FRAMES, WARMUP, cpu_times[p95_index], f64(FRAMES)/elapsed, vector_benchmark_manifest_hash()}
	report, report_error := json.marshal(report_data)
	testing.expect(t, report_error == nil)
	defer delete(report)
	fmt.println(string(report))
	testing.expect(t, os.write_entire_file("build/test/vector-benchmark-ui-baseline.json", report) == nil)
}

@(private)
vector_benchmark_ui_only :: proc() {
	draw_push_screen()
	defer draw_pop_screen()
	ui_push_style(style_root(.SCREEN, {0, 0, 1920, 1080}))
	defer ui_pop_style()
	vector_benchmark_frozen_ui_labels()
}

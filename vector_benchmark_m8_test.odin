#+test
package oni

import "core:encoding/json"
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
	morph_commands: [512][4][34]Vector_Path_Command,
	frame: int,
	error: Vector_Error,
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
		for icon in 0 ..< 2048 {
			x := f32(64 + (icon % 64) * 28)
			y := f32(100 + (icon / 64) * 28)
			phase := f64(vector_benchmark_m8.frame) / 120 + f64(icon) * 0.0137
			transform := Vector_Identity
			transform[4] = f64(x) + math.sin(phase) * 1.5
			transform[5] = f64(y) + math.cos(phase * 0.7) * 1.5
			opacity := f32(0.8 + 0.2 * math.sin(phase))
			asset := vector_benchmark_m8.assets[icon % 8]
			if icon % 4 == 0 {
				overrides := make([dynamic]Svg_Override, context.temp_allocator)
				morph_icon := icon / 4
				for part in 0 ..< 4 {
					target, ok := Svg_Lookup_Element(asset, fmt.tprintf("p%d", part))
					if !ok {
						vector_benchmark_m8.error = .Invalid_Handle
						continue
					}
					append(&overrides, Svg_Override{target = target, property = .Path, commands = vector_benchmark_m8.morph_commands[morph_icon][part][:]})
				}
				if err := Draw_Svg_Asset(asset, transform, opacity, overrides[:]); err != .None {
					vector_benchmark_m8.error = err
				}
			} else if err := Draw_Svg_Asset(asset, transform, opacity); err != .None {
				vector_benchmark_m8.error = err
			}
		}
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
	return fmt.tprintf("%x", digest)
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
	if state.gpu == nil {
		return
	}
	defer vector_benchmark_shutdown_gpu_stack()
	state.dpi = {logical_w = 1920, logical_h = 1080, drawable_w = 1920, drawable_h = 1080, scale = 1}
	state.view = view_default()
	assets_init(state.gpu)
	batch_init()
	ui_init()
	gpu_update_projection(state.dpi)
	family, font_ok := settings_register_fonts()
	testing.expect(t, font_ok)
	if !font_ok {
		return
	}
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
		for icon in 0 ..< 512 {
			phase := f64(frame) / 120 + f64(icon) * 0.0548
			for part in 0 ..< 4 {
				commands := vector_benchmark_circle(part, 3.5, f64(icon % 8))
				benchmark.morph_commands[icon][part] = commands
				factor := (3.5 + 0.45 * math.sin(phase + f64(part) * 0.17)) / 3.5
				cx := f64(6 + (part % 2) * 12)
				cy := f64(6 + (part / 2) * 12)
				for i in 0 ..< 34 {
					cmd := &benchmark.morph_commands[icon][part][i]
					if cmd.kind != .Move && cmd.kind != .Cubic {
						continue
					}
					for j in 0 ..< 3 {
						cmd.points[j][0] = cx + (cmd.points[j][0] - cx) * factor
						cmd.points[j][1] = cy + (cmd.points[j][1] - cy) * factor
					}
				}
			}
		}
		draw_record_begin(state.dpi)
		render(vector_benchmark_m8_ui)
		draw_record_end()
		_ = texture_uploads_flush(state.gpu)
		cmd := vector_gpu_prepare_frame(.R8G8B8A8_UNORM, {0.02, 0.03, 0.05, 1})
		testing.expect(t, cmd != nil)
		if cmd == nil {
			return
		}
		frame_gpu := vector_gpu_frame()
		frame_gpu.fence = sdl.SubmitGPUCommandBufferAndAcquireFence(cmd)
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
	p95 := cpu_times[p95_index]
	fps := f64(FRAMES) / elapsed
	manifest_hash := vector_benchmark_manifest_hash()
	report_data := struct {
		workload: string,
		manifest_hash: string,
		completed_fps, cpu_p95_ms: f64,
		frames, warmup, icons: int,
		error: string,
	}{
		"m8-imported-svg", manifest_hash, fps, p95, FRAMES, WARMUP, 2048, fmt.tprintf("%v", benchmark.error),
	}
	report, report_error := json.marshal(report_data)
	testing.expect(t, report_error == nil)
	defer delete(report)
	fmt.println(string(report))
	testing.expect(t, os.write_entire_file("build/test/vector-benchmark-m8.json", report) == nil)
	testing.expect_value(t, benchmark.error, Vector_Error.None)
	if FRAMES >= 1800 && WARMUP >= 120 {
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
vector_benchmark_composition_node :: proc(phase: f64, origin: Vec2, out: ^Vector_Node) {
	curve := [1]Vector_Node{vector_test_rect({origin.x, origin.y, origin.x + 40, origin.y + 28}, {220, 80, 80, 255})}
	inner := make([dynamic]Vector_Node, context.temp_allocator)
	append(&inner, Vector_Node{kind = .Group, opacity = f32(0.6 + 0.2 * math.sin(phase)), children = curve[:]})
	alpha_mask := [1]Vector_Node{vector_test_rect({origin.x, origin.y, origin.x + 40, origin.y + 28}, {255, 255, 255, 200})}
	masked := make([dynamic]Vector_Node, context.temp_allocator)
	append(&masked, Vector_Node{kind = .Mask, opacity = 1, children = inner[:], mask = alpha_mask[:], mask_kind = .Alpha})
	luma_mask := [1]Vector_Node{vector_test_rect({origin.x + 4, origin.y + 4, origin.x + 36, origin.y + 24}, {180, 180, 180, 255})}
	outer := make([dynamic]Vector_Node, context.temp_allocator)
	append(&outer, Vector_Node{kind = .Group, opacity = f32(0.7 + 0.2 * math.cos(phase * 0.7)), children = masked[:]})
	luma := make([dynamic]Vector_Node, context.temp_allocator)
	append(&luma, Vector_Node{kind = .Mask, opacity = 1, children = outer[:], mask = luma_mask[:], mask_kind = .Luminance})
	root := make([dynamic]Vector_Node, context.temp_allocator)
	append(&root, Vector_Node{kind = .Group, opacity = 1, children = luma[:]})
	out^ = root[0]
}

// Opt-in composition workload gate (256 nested opacity/mask instances).
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
	saved_state, saved_theme := state, theme
	defer {
		state, theme = saved_state, saved_theme
		widget_ctx_sync()
	}
	state, theme = &benchmark.engine, &benchmark.theme
	widget_ctx_sync()
	if !sdl.Init({.VIDEO}) {
		return
	}
	defer sdl.Quit()
	state.gpu = gpu_create_device(false)
	if state.gpu == nil {
		return
	}
	defer vector_benchmark_shutdown_gpu_stack()
	state.dpi = {logical_w = 1920, logical_h = 1080, drawable_w = 1920, drawable_h = 1080, scale = 1}
	state.view = view_default()
	assets_init(state.gpu)
	batch_init()
	ui_init()
	gpu_update_projection(state.dpi)
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
		state.ui.pass = .Draw
		draw_record_begin(state.dpi)
		phase := f64(frame) / 120
		for instance in 0 ..< 256 {
			x := f32(48 + (instance % 16) * 96)
			y := f32(48 + (instance / 16) * 64)
			node: Vector_Node
			vector_benchmark_composition_node(phase + f64(instance) * 0.03, {x, y}, &node)
			_ = draw_vector_scene({nodes = []Vector_Node{node}, opacity = 1})
		}
		draw_record_end()
		cmd := vector_gpu_prepare_frame(.R8G8B8A8_UNORM, {0.02, 0.03, 0.05, 1})
		if cmd == nil {
			return
		}
		vector_gpu_frame().fence = sdl.SubmitGPUCommandBufferAndAcquireFence(cmd)
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
	p95 := cpu_times[p95_index]
	fps := f64(FRAMES) / elapsed
	stats := vector_stats()
	report := fmt.tprintf(`{"workload":"m8-composition","completed_fps":%.3f,"cpu_p95_ms":%.3f,"sample_work":%d,"peak_pool_bytes":%d}`, fps, p95, stats.sample_work, stats.gpu_pool_bytes)
	fmt.println(report)
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
		return
	}
	defer sdl.Quit()
	state.gpu = gpu_create_device(false)
	if state.gpu == nil {
		return
	}
	defer vector_benchmark_shutdown_gpu_stack()
	state.dpi = {logical_w = 1920, logical_h = 1080, drawable_w = 1920, drawable_h = 1080, scale = 1}
	state.gpu_state.pipeline = gpu_create_ui_layout_pipeline(state.gpu, .R8G8B8A8_UNORM, frag_shader_code, gpu_blend_state())
	state.gpu_state.sampler = gpu_create_sampler(state.gpu)
	state.gpu_state.white_texture = gpu_create_white_texture(state.gpu)
	assets_init(state.gpu)
	batch_init()
	ui_init()
	gpu_update_projection(state.dpi)
	family, font_ok := settings_register_fonts()
	if !font_ok {
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
			start = time.tick_now()
		}
		cpu_start := time.tick_now()
		free_all(context.temp_allocator)
		ui_begin_frame()
		draw_record_begin(state.dpi)
		vector_benchmark_frozen_ui_labels()
		draw_record_end()
		end_frame()
		if frame >= WARMUP {
			cpu_times[frame - WARMUP] = time.duration_milliseconds(time.tick_since(cpu_start))
		}
	}
	elapsed := time.duration_seconds(time.tick_since(start))
	slice.sort(cpu_times)
	p95_index := min(FRAMES - 1, int(math.ceil(f64(FRAMES) * 0.95)) - 1)
	report := fmt.tprintf(`{"workload":"ordinary-ui-baseline","cpu_p95_ms":%.3f,"fps":%.3f}`, cpu_times[p95_index], f64(FRAMES)/elapsed)
	fmt.println(report)
	_ = os.write_entire_file("build/test/vector-benchmark-ui-baseline.json", report)
}

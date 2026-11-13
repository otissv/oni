package oni

import "core:fmt"
import sdl "vendor:sdl3"

/*
Last presentation attempt. Draw calls count SDL primitive draw API calls;
draw_commands includes each command inside indirect draws. Blits are separate.
Counters include diagnostic chrome and exclude cancelled command buffers.
FPS uses successful presentation intervals, including idle time, not capped dt.
*/
Render_Stats :: struct {
	fps, frame_ms: f64,
	draw_calls, draw_commands, batch_flushes, blits: u64,
	presented: bool,
	atlas: Atlas_Stats,
	memory: Render_Memory_Stats,
}

@(private)
DEBUG_OVERLAY_ID :: "oni-debug-overlay"
@(private)
DEBUG_OVERLAY_REFRESH_NS :: u64(250_000_000)

@(private)
Debug_Overlay_State :: struct {
	visible, frame_visible, recording, minimized: bool,
	current, stats: Render_Stats,
	last_present_ns, sample_start_ns, sample_frames, refresh_ns: u64,
	memory_sample_ns: u64,
	text: [2048]u8,
	text_length: int,
}

// All diagnostics storage is inline in State; no owned strings or GPU handles.
debug_overlay_visible :: proc() -> bool {
	return state != nil && state.debug_overlay.visible
}

debug_overlay_set_visible :: proc(visible: bool) {
	if state == nil || state.debug_overlay.visible == visible do return
	state.debug_overlay.visible = visible
	state.debug_overlay.refresh_ns = 0
	state.debug_overlay.memory_sample_ns = 0
	request_frame()
}

render_stats :: proc() -> Render_Stats {
	if state == nil do return {}
	return state.debug_overlay.stats
}

@(private)
debug_overlay_begin_present :: proc() {
	state.debug_overlay.current = {}
	state.debug_overlay.recording = true
}

@(private)
debug_overlay_record_draw :: #force_inline proc(commands: u32) {
	if !state.debug_overlay.recording do return
	state.debug_overlay.current.draw_calls += 1
	state.debug_overlay.current.draw_commands += u64(commands)
}

@(private)
debug_overlay_end_present :: proc(now: u64) {
	d := &state.debug_overlay
	if !d.current.presented {
		d.current = {}
	} else {
		if d.last_present_ns != 0 && now > d.last_present_ns {
			d.current.frame_ms = f64(now - d.last_present_ns) / 1_000_000
		}
		d.last_present_ns = now
	}
	if d.sample_start_ns == 0 || now < d.sample_start_ns {
		d.sample_start_ns = now
		d.sample_frames = 0
	} else {
		if d.current.presented do d.sample_frames += 1
		elapsed := now - d.sample_start_ns
		if elapsed >= DEBUG_OVERLAY_REFRESH_NS {
			d.stats.fps = f64(d.sample_frames) * 1_000_000_000 / f64(elapsed)
			d.sample_start_ns = now
			d.sample_frames = 0
		}
	}
	d.current.fps = d.stats.fps
	d.current.atlas = atlas_stats()
	d.current.memory = d.stats.memory

	if d.visible && !d.minimized && (d.memory_sample_ns == 0 || now < d.memory_sample_ns || now - d.memory_sample_ns >= DEBUG_OVERLAY_REFRESH_NS) {
		d.current.memory = debug_memory_snapshot()
		d.memory_sample_ns = now
	}

	d.stats = d.current
	d.recording = false
	d.refresh_ns = now + DEBUG_OVERLAY_REFRESH_NS
}

@(private)
debug_overlay_refresh_due :: proc(now: u64) -> bool {
	return state != nil && state.can_render && !state.debug_overlay.minimized && state.debug_overlay.visible && now >= state.debug_overlay.refresh_ns
}

@(private)
debug_overlay_wait_timeout :: proc(now: u64, timeout: i32) -> i32 {
	if state == nil || !state.can_render || state.debug_overlay.minimized || !state.debug_overlay.visible do return timeout
	deadline := state.debug_overlay.refresh_ns
	if now >= deadline do return 0
	// Round up so sub-millisecond waits cannot create an idle spin.
	remaining := (deadline - now + 999_999) / 1_000_000
	return i32(min(u64(max(timeout, 0)), remaining))
}

@(private)
debug_overlay_format :: proc() {
	d := &state.debug_overlay
	s := d.stats
	a := s.atlas
	m := s.memory
	MIB :: f64(1024 * 1024)
	gpu_driver := "unavailable"

	if state.gpu != nil {
		gpu_driver = string(sdl.GetGPUDeviceDriver(state.gpu))
	}

	process_text: [256]u8
	ram := "RAM: unavailable"

	if m.process.available {
		ram = fmt.bprintf(process_text[:], "RAM: %.1f MiB   Peak: %.1f MiB", f64(m.process.resident_bytes) / MIB, f64(m.process.peak_resident_bytes) / MIB)
	}
	breakdown_text: [256]u8
	breakdown := "Anon/file/shared: unavailable"

	if m.process.breakdown_available {
		breakdown = fmt.bprintf(breakdown_text[:], "Anon/file/shared: %.1f / %.1f / %.1f MiB", f64(m.process.anonymous_bytes) / MIB, f64(m.process.file_bytes) / MIB, f64(m.process.shared_bytes) / MIB)
	}

	text := fmt.bprintf(d.text[:],
		"ONI DEBUG\n%s\n%s\nLayout used/cap: %.2f / %.2f MiB\nScratch used/cap: %.2f / %.2f MiB\nTextures CPU/GPU: %.2f / %.2f MiB (%d)\nBatch CPU/GPU: %.2f / %.2f MiB\nUploads (batch): %.2f MiB\nVector GPU/pool: %.2f / %.2f MiB\nVector path cache: %.2f MiB\nGPU = estimates; separate from RAM\nBuild: %s   GPU: %s\nDrawable: %dx%d   DPI: %.2f\nFPS: %.1f   Frame: %.2f ms\nDraw calls: %d   Commands: %d\nBatch flushes: %d   Blits: %d\nAtlas: %dx%d   Sheets: %d\nAtlas used: %.1f%%   %.2f / %.2f MiB\nGlyphs: %d   Slots: %d\nAtlas generation: %d   Mode: %v",
		ram, breakdown,
		f64(m.layout_used_bytes) / MIB, f64(m.layout_capacity_bytes) / MIB,
		f64(m.scratch_used_bytes) / MIB, f64(m.scratch_capacity_bytes) / MIB,
		f64(m.texture_cpu_bytes) / MIB, f64(m.texture_gpu_bytes) / MIB, m.texture_count,
		f64(m.batch_cpu_bytes) / MIB, f64(m.batch_gpu_bytes) / MIB,
		f64(m.batch_upload_bytes) / MIB,
		f64(m.vector_gpu_bytes) / MIB, f64(m.vector_pool_bytes) / MIB,
		f64(m.vector_cache_bytes) / MIB,
		"debug" if ODIN_DEBUG else "release", gpu_driver,
		state.dpi.drawable_w, state.dpi.drawable_h, state.dpi.scale,
		s.fps, s.frame_ms, s.draw_calls, s.draw_commands,
		s.batch_flushes, s.blits, a.width, a.height,
		(a.overflow_count + 1) if a.bytes_total > 0 else 0,
		a.used_percent, f64(a.bytes_used) / (1024 * 1024), f64(a.bytes_total) / (1024 * 1024),
		a.cache_count, a.slot_count, a.generation, a.draw_mode,
	)
	d.text_length = len(text)
}

// This is framework chrome, built alongside app UI in the same two passes.
// Visibility/text are captured on Layout because shortcuts run between passes.
@(private)
debug_overlay_ui :: proc() {
	if state == nil do return
	d := &state.debug_overlay
	if ui_pass() == .Layout {
		d.frame_visible = d.visible && theme != nil && state.dpi.logical_w > 0 && state.dpi.logical_h > 0
		if d.frame_visible do debug_overlay_format()
	}
	if !d.frame_visible do return

	begin_overlay()
	defer end_overlay()
	id := ui_id(DEBUG_OVERLAY_ID)
	if ui_pass() == .Layout {
		config := Resolved_Widget_Config{
			kind = .TEXT, space = .OVERLAY,
			font = theme.font_body, font_size = 13,
			font_weight = Font_Weights.Normal, font_style = Font_Styles.NORMAL,
			line_height = 1.4, wrap = Text_Wrap_Kind.NEWLINES,
			text_decoration = Text_Decoration_Lines{},
			text_decoration_style = Text_Decoration_Style_Kind.SOLID,
			text_direction = Text_Direction_Kind.LTR, align = .LEFT,
			width = {kind = .FIXED, value = min(f32(390), max(f32(1), f32(state.dpi.logical_w) - 16))},
			height = {kind = .FIT}, padding = f32(10),
			position = .FIXED, x = 8, y = 8, x_set = true, y_set = true,
			opacity = 1, pointer_events = .NONE,
			z_index = 1_000_000,
		}
		node := layout_push_node(id, config)
		layout_set_measure_text(node, string(d.text[:d.text_length]), 0)
		node.measure.transient_text = true
		layout_pop_node()
		return
	}
	stack := batch_current().current_stack
	batch_set_stack_index(ui_layout_stack_index(id))
	defer batch_set_stack_index(stack)
	viewport := layout_space_bounds(.OVERLAY)
	draw_push_clip(viewport)
	defer draw_pop_clip()
	rect := ui_layout_rect(id)
	draw_rect(rect, {18, 22, 30, 245}, {6, 6, 6, 6})
	draw_push_clip(rect)
	defer draw_pop_clip()
	_ = font_draw_layout_text(layout_text_result(id), {236, 242, 250, 255})
}

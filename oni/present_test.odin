package oni

import "core:sync"
import "core:testing"
import sdl "vendor:sdl3"

@(private)
present_test_draw_calls: int

@(private)
present_test_noop_draw :: proc() {
	present_test_draw_calls += 1
}

@(private)
present_test_quad_draw :: proc() {
	present_test_draw_calls += 1
	batch_check_key(TEXTURE_WHITE_ID)
	batch_push_axis_quad(
		{0, 0, 32, 32},
		{0, 0, 1, 1},
		{255, 255, 255, 255},
		{},
		{32, 32},
		{},
		{},
		.Solid,
	)
}

@(private)
present_test_theme :: proc() -> Theme {
	return Theme {
		palette      = palette,
		border       = 0,
		border_color = .BLACK,
		background   = .BLACK,
		padding      = 0,
		radius       = 0,
		gap_x        = u16(0),
		gap_y        = u16(0),
		color        = .FOREGROUND,
		justify      = Justify_Pos{x = .START, y = .START},
		direction    = Direction_Layout.VERTICAL,
		font_body    = {},
		width        = 0,
		height       = 0,
	}
}

/*
Full window + GPU + theme for present_frame happy/error paths.
*/
@(private)
with_present_env :: proc(t: ^testing.T, body: proc(t: ^testing.T)) {
	sync.mutex_lock(&test_global_state_guard)
	defer sync.mutex_unlock(&test_global_state_guard)

	test_state: State
	test_theme := present_test_theme()
	saved_state := state
	saved_theme := theme
	defer {
		state = saved_state
		theme = saved_theme
	}

	state = &test_state
	theme = &test_theme
	clear_test_hooks()
	defer clear_test_hooks()
	present_test_draw_calls = 0

	ok := create_window(
		{
			title = "oni present test",
			width = 320,
			height = 240,
			min_width = 64,
			min_height = 64,
		},
	)
	if !ok {
		testing.expectf(t, false, "create_window failed: %s", sdl.GetError())
		return
	}
	defer shutdown()

	if !init() {
		testing.expect(t, false, "engine init failed")
		return
	}

	body(t)
}

// ---------------------------------------------------------------------------
// Early returns (no GPU command buffer)
// ---------------------------------------------------------------------------

@(test)
present_frame_noop_when_cannot_render :: proc(t: ^testing.T) {
	with_engine_env(
		t,
		proc(t: ^testing.T) {
			state.can_render = false
			state.window = transmute(^sdl.Window)uintptr(1)
			state.gpu = transmute(^sdl.GPUDevice)uintptr(1)
			state.gpu_state.pipeline = transmute(^sdl.GPUGraphicsPipeline)uintptr(1)
			theme_local := present_test_theme()
			theme = &theme_local
			present_test_draw_calls = 0
			present_frame(present_test_noop_draw)
			testing.expect_value(t, present_test_draw_calls, 0)
			state.window = nil
			state.gpu = nil
			state.gpu_state.pipeline = nil
		},
	)
}

@(test)
present_frame_noop_when_window_nil :: proc(t: ^testing.T) {
	with_engine_env(
		t,
		proc(t: ^testing.T) {
			state.can_render = true
			state.window = nil
			state.gpu = transmute(^sdl.GPUDevice)uintptr(1)
			state.gpu_state.pipeline = transmute(^sdl.GPUGraphicsPipeline)uintptr(1)
			theme_local := present_test_theme()
			theme = &theme_local
			present_test_draw_calls = 0
			present_frame(present_test_noop_draw)
			testing.expect_value(t, present_test_draw_calls, 0)
			state.gpu = nil
			state.gpu_state.pipeline = nil
		},
	)
}

@(test)
present_frame_noop_when_gpu_nil :: proc(t: ^testing.T) {
	with_engine_env(
		t,
		proc(t: ^testing.T) {
			state.can_render = true
			state.window = transmute(^sdl.Window)uintptr(1)
			state.gpu = nil
			state.gpu_state.pipeline = transmute(^sdl.GPUGraphicsPipeline)uintptr(1)
			theme_local := present_test_theme()
			theme = &theme_local
			present_test_draw_calls = 0
			present_frame(present_test_noop_draw)
			testing.expect_value(t, present_test_draw_calls, 0)
			state.window = nil
			state.gpu_state.pipeline = nil
		},
	)
}

@(test)
present_frame_noop_when_pipeline_nil :: proc(t: ^testing.T) {
	with_engine_env(
		t,
		proc(t: ^testing.T) {
			state.can_render = true
			state.window = transmute(^sdl.Window)uintptr(1)
			state.gpu = transmute(^sdl.GPUDevice)uintptr(1)
			state.gpu_state.pipeline = nil
			theme_local := present_test_theme()
			theme = &theme_local
			present_test_draw_calls = 0
			present_frame(present_test_noop_draw)
			testing.expect_value(t, present_test_draw_calls, 0)
			state.window = nil
			state.gpu = nil
		},
	)
}

@(test)
present_frame_noop_when_theme_nil :: proc(t: ^testing.T) {
	with_engine_env(
		t,
		proc(t: ^testing.T) {
			state.can_render = true
			state.window = transmute(^sdl.Window)uintptr(1)
			state.gpu = transmute(^sdl.GPUDevice)uintptr(1)
			state.gpu_state.pipeline = transmute(^sdl.GPUGraphicsPipeline)uintptr(1)
			theme = nil
			present_test_draw_calls = 0
			present_frame(present_test_noop_draw)
			testing.expect_value(t, present_test_draw_calls, 0)
			state.window = nil
			state.gpu = nil
			state.gpu_state.pipeline = nil
		},
	)
}

// ---------------------------------------------------------------------------
// Happy paths
// ---------------------------------------------------------------------------

@(test)
present_frame_clears_and_submits_empty_batch :: proc(t: ^testing.T) {
	with_present_env(
		t,
		proc(t: ^testing.T) {
			testing.expect(t, state.gpu_state.pipeline != nil)
			testing.expect(t, theme != nil)
			present_frame(present_test_noop_draw)
			testing.expect_value(t, present_test_draw_calls, 1)
			testing.expect_value(t, len(state.gpu_state.batch.vertices), 0)
			testing.expect_value(t, len(state.gpu_state.batch.indices), 0)
			testing.expect(t, state.gpu_state.batch.cmd == nil)
			testing.expect(t, state.gpu_state.batch.pass == nil)
		},
	)
}

@(test)
present_frame_uploads_geometry_and_resets_batch :: proc(t: ^testing.T) {
	with_present_env(
		t,
		proc(t: ^testing.T) {
			present_frame(present_test_quad_draw)
			testing.expect_value(t, present_test_draw_calls, 1)
			testing.expect_value(t, len(state.gpu_state.batch.vertices), 0)
			testing.expect_value(t, len(state.gpu_state.batch.indices), 0)
			testing.expect_value(t, len(state.gpu_state.batch.segments), 0)
		},
	)
}

@(test)
present_frame_two_frames_in_a_row :: proc(t: ^testing.T) {
	with_present_env(
		t,
		proc(t: ^testing.T) {
			present_frame(present_test_quad_draw)
			present_frame(present_test_noop_draw)
			testing.expect_value(t, present_test_draw_calls, 2)
			testing.expect_value(t, len(state.gpu_state.batch.vertices), 0)
		},
	)
}

// ---------------------------------------------------------------------------
// SDL / upload failure branches
// ---------------------------------------------------------------------------

@(test)
present_frame_acquire_cmd_failure_skips_draw :: proc(t: ^testing.T) {
	with_present_env(
		t,
		proc(t: ^testing.T) {
			test_hook_present_fail_acquire_cmd = true
			present_frame(present_test_noop_draw)
			testing.expect_value(t, present_test_draw_calls, 0)
		},
	)
}

@(test)
present_frame_swapchain_failure_cancels_and_skips_draw :: proc(t: ^testing.T) {
	with_present_env(
		t,
		proc(t: ^testing.T) {
			test_hook_present_fail_swapchain = true
			present_frame(present_test_noop_draw)
			testing.expect_value(t, present_test_draw_calls, 0)
		},
	)
}

@(test)
present_frame_swapchain_failure_logs_cancel_failure :: proc(t: ^testing.T) {
	with_present_env(
		t,
		proc(t: ^testing.T) {
			test_hook_present_fail_swapchain = true
			test_hook_present_fail_cancel = true
			present_frame(present_test_noop_draw)
			testing.expect_value(t, present_test_draw_calls, 0)
		},
	)
}

@(test)
present_frame_nil_swapchain_cancels_and_skips_draw :: proc(t: ^testing.T) {
	with_present_env(
		t,
		proc(t: ^testing.T) {
			test_hook_present_nil_swapchain = true
			present_frame(present_test_noop_draw)
			testing.expect_value(t, present_test_draw_calls, 0)
		},
	)
}

@(test)
present_frame_nil_swapchain_logs_cancel_failure :: proc(t: ^testing.T) {
	with_present_env(
		t,
		proc(t: ^testing.T) {
			test_hook_present_nil_swapchain = true
			test_hook_present_fail_cancel = true
			present_frame(present_test_noop_draw)
			testing.expect_value(t, present_test_draw_calls, 0)
		},
	)
}

@(test)
present_frame_batch_upload_failure_still_clears_and_resets :: proc(t: ^testing.T) {
	with_present_env(
		t,
		proc(t: ^testing.T) {
			test_hook_batch_upload_fail_transfer = true
			present_frame(present_test_quad_draw)
			testing.expect_value(t, present_test_draw_calls, 1)
			testing.expect_value(t, len(state.gpu_state.batch.vertices), 0)
			testing.expect_value(t, len(state.gpu_state.batch.indices), 0)
		},
	)
}

@(test)
present_frame_batch_upload_failure_logs_submit_failure :: proc(t: ^testing.T) {
	with_present_env(
		t,
		proc(t: ^testing.T) {
			test_hook_batch_upload_fail_map = true
			test_hook_present_fail_submit = true
			present_frame(present_test_quad_draw)
			testing.expect_value(t, present_test_draw_calls, 1)
			testing.expect_value(t, len(state.gpu_state.batch.vertices), 0)
		},
	)
}

@(test)
present_frame_render_pass_failure_submits_and_resets :: proc(t: ^testing.T) {
	with_present_env(
		t,
		proc(t: ^testing.T) {
			test_hook_present_fail_render_pass = true
			present_frame(present_test_quad_draw)
			testing.expect_value(t, present_test_draw_calls, 1)
			testing.expect_value(t, len(state.gpu_state.batch.vertices), 0)
			testing.expect(t, state.gpu_state.batch.cmd == nil)
			testing.expect(t, state.gpu_state.batch.pass == nil)
		},
	)
}

@(test)
present_frame_render_pass_failure_logs_submit_failure :: proc(t: ^testing.T) {
	with_present_env(
		t,
		proc(t: ^testing.T) {
			test_hook_present_fail_render_pass = true
			test_hook_present_fail_submit = true
			present_frame(present_test_noop_draw)
			testing.expect_value(t, present_test_draw_calls, 1)
		},
	)
}

@(test)
present_frame_submit_failure_still_resets_batch :: proc(t: ^testing.T) {
	with_present_env(
		t,
		proc(t: ^testing.T) {
			test_hook_present_fail_submit = true
			present_frame(present_test_quad_draw)
			testing.expect_value(t, present_test_draw_calls, 1)
			testing.expect_value(t, len(state.gpu_state.batch.vertices), 0)
			testing.expect_value(t, len(state.gpu_state.batch.indices), 0)
		},
	)
}

@(test)
present_frame_vertices_only_skips_failed_upload_path :: proc(t: ^testing.T) {
	with_present_env(
		t,
		proc(t: ^testing.T) {
			// draw adds verts without indices via direct append — upload returns true
			present_frame(proc() {
				present_test_draw_calls += 1
				append(&state.gpu_state.batch.vertices, UI_Vertex{})
			})
			testing.expect_value(t, present_test_draw_calls, 1)
			testing.expect_value(t, len(state.gpu_state.batch.vertices), 0)
		},
	)
}

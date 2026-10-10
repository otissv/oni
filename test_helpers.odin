package oni

import "core:log"
import "core:sync"
import "core:testing"
import sdl "vendor:sdl3"

@(private)
Test_Backend_Status :: enum u8 {
	Unknown,
	Available,
	Unavailable,
}

@(private)
test_gpu_device_status: Test_Backend_Status

@(private)
test_gpu_window_status: Test_Backend_Status

@(private)
test_gpu_device_skip_logged: bool

@(private)
test_gpu_window_skip_logged: bool

/*
Shared GPU/window capability probes for tests that require a real SDL GPU backend.

Callers must hold `test_global_state_guard` before invoking these helpers so the
cached probe state and SDL init/quit sequence stay serialized across parallel tests.
*/
@(private)
test_gpu_device_available_unlocked :: proc() -> bool {
	if test_gpu_device_status != .Unknown {
		return test_gpu_device_status == .Available
	}

	if !sdl.Init({.VIDEO}) {
		test_gpu_device_status = .Unavailable
		return false
	}
	defer sdl.Quit()

	gpu := sdl.CreateGPUDevice({.SPIRV}, true, nil)
	if gpu == nil {
		test_gpu_device_status = .Unavailable
		return false
	}

	sdl.DestroyGPUDevice(gpu)
	test_gpu_device_status = .Available
	return true
}

@(private)
test_gpu_window_available_unlocked :: proc() -> bool {
	if test_gpu_window_status != .Unknown {
		return test_gpu_window_status == .Available
	}

	if test_gpu_device_status == .Unavailable {
		test_gpu_window_status = .Unavailable
		return false
	}

	if !sdl.Init({.VIDEO}) {
		test_gpu_window_status = .Unavailable
		test_gpu_device_status = .Unavailable
		return false
	}
	defer sdl.Quit()

	window := sdl.CreateWindow("oni test probe", 64, 64, sdl.WINDOW_RESIZABLE | sdl.WINDOW_HIGH_PIXEL_DENSITY)
	if window == nil {
		test_gpu_window_status = .Unavailable
		return false
	}
	defer sdl.DestroyWindow(window)

	gpu := sdl.CreateGPUDevice({.SPIRV}, true, nil)
	if gpu == nil {
		test_gpu_window_status = .Unavailable
		test_gpu_device_status = .Unavailable
		return false
	}
	defer sdl.DestroyGPUDevice(gpu)
	test_gpu_device_status = .Available

	if !sdl.ClaimWindowForGPUDevice(gpu, window) {
		test_gpu_window_status = .Unavailable
		return false
	}
	defer sdl.ReleaseWindowFromGPUDevice(gpu, window)

	if !sdl.SetGPUSwapchainParameters(gpu, window, .SDR, .VSYNC) {
		test_gpu_window_status = .Unavailable
		return false
	}

	test_gpu_window_status = .Available
	return true
}

@(private)
test_require_gpu_device_unlocked :: proc(loc := #caller_location) -> bool {
	if test_gpu_device_available_unlocked() {
		return true
	}

	if !test_gpu_device_skip_logged {
		log.info("SKIP: GPU device tests require an SDL GPU backend on this machine", location = loc)
		test_gpu_device_skip_logged = true
	}

	return false
}

@(private)
test_require_gpu_window_unlocked :: proc(loc := #caller_location) -> bool {
	if test_gpu_window_available_unlocked() {
		return true
	}

	if !test_gpu_window_skip_logged {
		log.info("SKIP: window + GPU tests require an SDL GPU backend on this machine", location = loc)
		test_gpu_window_skip_logged = true
	}

	return false
}

/*
Runs body with engine state, theme, and UI maps ready for style/widget/ui tests.

Shares the layout-test mutex so parallel `odin test` workers do not clobber globals.
*/
@(private)
with_ui_env :: proc(t: ^testing.T, body: proc(t: ^testing.T)) {
	test_state: State
	test_theme := Theme {
		palette      = palette,
		border       = 0,
		border_color = .BLACK,
		background   = .TRANSPARENT,
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

	sync.mutex_lock(&test_global_state_guard)
	defer sync.mutex_unlock(&test_global_state_guard)

	saved_state := state
	saved_theme := theme
	saved_w_ctx := w_ctx
	defer {
		state = saved_state
		theme = saved_theme
		w_ctx = saved_w_ctx
	}

	state = &test_state
	theme = &test_theme
	w_ctx = &state.widget
	state.widget = {}
	state.dpi = {logical_w = 800, logical_h = 600, scale = 1}
	state.view = view_default()
	batch_current().vertex_capacity = 64 * 1024
	batch_current().index_capacity = 64 * 1024 * 6

	ui_init()
	defer {
		for len(state.ui.style_stack) > 0 {
			ui_pop_style()
		}
		ui_shutdown()
		shortcut_shutdown()
		settings_shutdown()
		batch_delete_cpu_arrays(&state.gpu_state)
	}

	ui_push_style(style_root(.SCREEN, {0, 0, 800, 600}))
	body(t)
}

@(private)
ui_test_frame_event :: proc() -> (frame: Widget_Frame_State, event: Widget_Event(Widget_Frame_State)) {
	frame = {}
	event = {frame_state = frame}
	return
}

@(private)
expect_pd :: proc(t: ^testing.T, got, want: Pd_px, loc := #caller_location) {
	expect_close(t, got.t, want.t, loc = loc)
	expect_close(t, got.b, want.b, loc = loc)
	expect_close(t, got.l, want.l, loc = loc)
	expect_close(t, got.r, want.r, loc = loc)
}

@(private)
expect_mg :: proc(t: ^testing.T, got, want: Mg_px, loc := #caller_location) {
	expect_close(t, got.t, want.t, loc = loc)
	expect_close(t, got.b, want.b, loc = loc)
	expect_close(t, got.l, want.l, loc = loc)
	expect_close(t, got.r, want.r, loc = loc)
}

@(private)
expect_bd :: proc(t: ^testing.T, got, want: Bd_px, loc := #caller_location) {
	expect_close(t, got.t, want.t, loc = loc)
	expect_close(t, got.b, want.b, loc = loc)
	expect_close(t, got.l, want.l, loc = loc)
	expect_close(t, got.r, want.r, loc = loc)
}

@(private)
expect_radius :: proc(t: ^testing.T, got, want: Radius_px, loc := #caller_location) {
	expect_close(t, got.tl, want.tl, loc = loc)
	expect_close(t, got.tr, want.tr, loc = loc)
	expect_close(t, got.bl, want.bl, loc = loc)
	expect_close(t, got.br, want.br, loc = loc)
}

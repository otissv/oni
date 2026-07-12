package oni

import "core:sync"
import "core:testing"
import sdl "vendor:sdl3"

@(private)
runtime_test_tick_calls: int
@(private)
runtime_test_draw_calls: int
@(private)
runtime_test_init_calls: int
@(private)
runtime_test_last_dt: f32
@(private)
runtime_test_ready_ok: bool

@(private)
runtime_test_tick :: proc(dt: f32) {
	runtime_test_tick_calls += 1
	runtime_test_last_dt = dt
}

@(private)
runtime_test_draw :: proc() {
	runtime_test_draw_calls += 1
}

@(private)
runtime_test_init :: proc() {
	runtime_test_init_calls += 1
}

@(private)
runtime_test_ready :: proc() -> bool {
	return runtime_test_ready_ok
}

@(private)
runtime_test_reset_counters :: proc() {
	runtime_test_tick_calls = 0
	runtime_test_draw_calls = 0
	runtime_test_init_calls = 0
	runtime_test_last_dt = -1
}

@(private)
runtime_test_window_cfg :: proc() -> Window_Config {
	return {
		title = "oni runtime test",
		width = 320,
		height = 240,
		min_width = 64,
		min_height = 64,
	}
}

/*
CPU-only engine state with init-once flag isolated.
*/
@(private)
with_runtime_env :: proc(t: ^testing.T, body: proc(t: ^testing.T)) {
	test_state: State

	sync.mutex_lock(&test_global_state_guard)
	defer sync.mutex_unlock(&test_global_state_guard)

	saved_state := state
	saved_theme := theme
	saved_init := has_init_run_once
	defer {
		delete(test_state.input.text_input)
		delete(test_state.gpu_state.batch.vertices)
		delete(test_state.gpu_state.batch.indices)
		delete(test_state.gpu_state.batch.segments)
		delete(test_state.gpu_state.batch.clip_stack)
		delete(test_state.gpu_state.batch.space_stack)
		state = saved_state
		theme = saved_theme
		has_init_run_once = saved_init
	}

	state = &test_state
	theme = nil
	has_init_run_once = false
	runtime_test_reset_counters()
	clear_test_hooks()
	defer clear_test_hooks()
	state.running = true
	state.can_render = true
	state.dpi = {logical_w = 800, logical_h = 600, scale = 1, drawable_w = 800, drawable_h = 600}
	state.view = view_default()
	body(t)
}

/*
SDL + timing for run_frame without requiring a successful present.
*/
@(private)
with_runtime_sdl_env :: proc(t: ^testing.T, body: proc(t: ^testing.T)) {
	sync.mutex_lock(&test_global_state_guard)
	defer sync.mutex_unlock(&test_global_state_guard)

	if !sdl.Init({.VIDEO, .GAMEPAD}) {
		testing.expectf(t, false, "SDL_Init failed: %s", sdl.GetError())
		return
	}
	defer sdl.Quit()

	test_state: State
	saved_state := state
	saved_theme := theme
	saved_init := has_init_run_once
	defer {
		delete(test_state.input.text_input)
		delete(test_state.gpu_state.batch.vertices)
		delete(test_state.gpu_state.batch.indices)
		delete(test_state.gpu_state.batch.segments)
		delete(test_state.gpu_state.batch.clip_stack)
		delete(test_state.gpu_state.batch.space_stack)
		state = saved_state
		theme = saved_theme
		has_init_run_once = saved_init
	}

	state = &test_state
	theme = nil
	has_init_run_once = false
	runtime_test_reset_counters()
	clear_test_hooks()
	defer clear_test_hooks()
	state.running = true
	state.can_render = true
	state.dpi = {logical_w = 800, logical_h = 600, scale = 1, drawable_w = 800, drawable_h = 600}
	state.view = view_default()
	state.perf_frequency = sdl.GetPerformanceFrequency()
	state.last_counter = sdl.GetPerformanceCounter()
	engine_test_drain_events()
	body(t)
}

/*
Full create_window → init lifecycle for init_runtime / on_reload / run_frame present.
*/
@(private)
with_runtime_window_env :: proc(t: ^testing.T, body: proc(t: ^testing.T)) {
	sync.mutex_lock(&test_global_state_guard)
	defer sync.mutex_unlock(&test_global_state_guard)

	test_state: State
	test_theme := present_test_theme()
	saved_state := state
	saved_theme := theme
	saved_init := has_init_run_once
	defer {
		state = saved_state
		theme = saved_theme
		has_init_run_once = saved_init
	}

	state = &test_state
	theme = &test_theme
	has_init_run_once = false
	runtime_test_reset_counters()
	clear_test_hooks()
	defer clear_test_hooks()

	ok := create_window(runtime_test_window_cfg())
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

@(private)
with_runtime_init_flag :: proc(t: ^testing.T, body: proc(t: ^testing.T)) {
	sync.mutex_lock(&test_global_state_guard)
	defer sync.mutex_unlock(&test_global_state_guard)

	saved_init := has_init_run_once
	defer {
		has_init_run_once = saved_init
	}
	has_init_run_once = false
	runtime_test_reset_counters()
	clear_test_hooks()
	defer clear_test_hooks()
	body(t)
}

// ---------------------------------------------------------------------------
// run_init_once
// ---------------------------------------------------------------------------

@(test)
runtime_run_init_once_runs_first_call_only :: proc(t: ^testing.T) {
	with_runtime_init_flag(
		t,
		proc(t: ^testing.T) {
			testing.expect(t, !has_init_run_once)
			run_init_once(runtime_test_init)
			testing.expect(t, has_init_run_once)
			testing.expect_value(t, runtime_test_init_calls, 1)

			run_init_once(runtime_test_init)
			testing.expect_value(t, runtime_test_init_calls, 1)
		},
	)
}

@(test)
runtime_run_init_once_nil_proc_still_marks_done :: proc(t: ^testing.T) {
	with_runtime_init_flag(
		t,
		proc(t: ^testing.T) {
			run_init_once(nil)
			testing.expect(t, has_init_run_once)
			testing.expect_value(t, runtime_test_init_calls, 0)

			run_init_once(runtime_test_init)
			testing.expect_value(t, runtime_test_init_calls, 0)
		},
	)
}

// ---------------------------------------------------------------------------
// run_frame
// ---------------------------------------------------------------------------

@(test)
runtime_run_frame_nil_state_is_noop :: proc(t: ^testing.T) {
	with_runtime_init_flag(
		t,
		proc(t: ^testing.T) {
			saved := state
			state = nil
			defer {
				state = saved
			}

			run_frame(runtime_test_tick, runtime_test_draw, runtime_test_init)
			testing.expect_value(t, runtime_test_tick_calls, 0)
			testing.expect_value(t, runtime_test_draw_calls, 0)
			testing.expect_value(t, runtime_test_init_calls, 0)
			testing.expect(t, !has_init_run_once)
		},
	)
}

@(test)
runtime_run_frame_returns_early_when_cannot_render :: proc(t: ^testing.T) {
	with_runtime_sdl_env(
		t,
		proc(t: ^testing.T) {
			state.can_render = false
			state.input.mouse_wheel_y = 3
			append(&state.input.text_input, 'x')

			run_frame(runtime_test_tick, runtime_test_draw, runtime_test_init)

			// input_begin_frame still ran
			expect_close(t, state.input.mouse_wheel_y, 0)
			testing.expect_value(t, len(state.input.text_input), 0)
			testing.expect_value(t, runtime_test_tick_calls, 0)
			testing.expect_value(t, runtime_test_draw_calls, 0)
			testing.expect_value(t, runtime_test_init_calls, 0)
			testing.expect(t, !has_init_run_once)
		},
	)
}

@(test)
runtime_run_frame_nil_tick_and_init_still_presents :: proc(t: ^testing.T) {
	with_runtime_window_env(
		t,
		proc(t: ^testing.T) {
			run_frame(nil, runtime_test_draw, nil)
			testing.expect_value(t, runtime_test_tick_calls, 0)
			testing.expect_value(t, runtime_test_draw_calls, 1)
			testing.expect(t, has_init_run_once)
		},
	)
}

@(test)
runtime_run_frame_runs_tick_init_draw_once :: proc(t: ^testing.T) {
	with_runtime_window_env(
		t,
		proc(t: ^testing.T) {
			run_frame(runtime_test_tick, runtime_test_draw, runtime_test_init)
			testing.expect_value(t, runtime_test_tick_calls, 1)
			testing.expect_value(t, runtime_test_init_calls, 1)
			testing.expect_value(t, runtime_test_draw_calls, 1)
			testing.expect(t, runtime_test_last_dt >= 0)
			testing.expect(t, has_init_run_once)

			runtime_test_reset_counters()
			run_frame(runtime_test_tick, runtime_test_draw, runtime_test_init)
			testing.expect_value(t, runtime_test_tick_calls, 1)
			testing.expect_value(t, runtime_test_init_calls, 0)
			testing.expect_value(t, runtime_test_draw_calls, 1)
		},
	)
}

@(test)
runtime_run_frame_present_noop_without_theme_still_ends_frame :: proc(t: ^testing.T) {
	with_runtime_sdl_env(
		t,
		proc(t: ^testing.T) {
			// can_render true but no window/gpu/theme → present early-outs after tick/init
			theme = nil
			state.window = nil
			state.gpu = nil
			ui_init()
			defer ui_shutdown()

			run_frame(runtime_test_tick, runtime_test_draw, runtime_test_init)
			testing.expect_value(t, runtime_test_tick_calls, 1)
			testing.expect_value(t, runtime_test_init_calls, 1)
			testing.expect_value(t, runtime_test_draw_calls, 0)
			testing.expect(t, has_init_run_once)
		},
	)
}

// ---------------------------------------------------------------------------
// init_window_only
// ---------------------------------------------------------------------------

@(test)
runtime_init_window_only_nil_state_returns_false :: proc(t: ^testing.T) {
	with_nil_state(
		t,
		proc(t: ^testing.T) {
			testing.expect(t, !init_window_only(runtime_test_window_cfg()))
		},
	)
}

@(test)
runtime_init_window_only_idempotent_when_window_exists :: proc(t: ^testing.T) {
	with_engine_sdl_window_env(
		t,
		proc(t: ^testing.T) {
			testing.expect(t, state.window != nil)
			testing.expect(t, state.gpu == nil)
			testing.expect(t, init_window_only(runtime_test_window_cfg()))
			testing.expect(t, state.gpu == nil)
		},
	)
}

@(test)
runtime_init_window_only_creates_and_sets_running :: proc(t: ^testing.T) {
	sync.mutex_lock(&test_global_state_guard)
	defer sync.mutex_unlock(&test_global_state_guard)
	clear_test_hooks()
	defer clear_test_hooks()

	test_state: State
	saved_state := state
	saved_theme := theme
	defer {
		state = saved_state
		theme = saved_theme
	}

	state = &test_state
	theme = nil
	state.running = false
	if !init_window_only(runtime_test_window_cfg()) {
		testing.expectf(t, false, "init_window_only failed: %s", sdl.GetError())
		return
	}
	defer shutdown()
	testing.expect(t, state.window != nil)
	testing.expect(t, state.gpu != nil)
	testing.expect(t, state.running)
	testing.expect(t, init_window_only({title = "again", width = 1, height = 1}))
}

@(test)
runtime_init_window_only_failure_clears_running :: proc(t: ^testing.T) {
	sync.mutex_lock(&test_global_state_guard)
	defer sync.mutex_unlock(&test_global_state_guard)
	clear_test_hooks()
	defer clear_test_hooks()

	test_state: State
	saved_state := state
	defer {
		state = saved_state
	}

	state = &test_state
	state.running = true
	test_hook_create_window_fail = .Init
	testing.expect(t, !init_window_only(runtime_test_window_cfg()))
	testing.expect(t, !state.running)
	testing.expect(t, state.window == nil)
}

@(test)
runtime_init_window_only_window_create_failure_clears_running :: proc(t: ^testing.T) {
	sync.mutex_lock(&test_global_state_guard)
	defer sync.mutex_unlock(&test_global_state_guard)
	clear_test_hooks()
	defer clear_test_hooks()

	test_state: State
	saved_state := state
	defer {
		state = saved_state
	}

	state = &test_state
	state.running = true
	test_hook_create_window_fail = .Window
	testing.expect(t, !init_window_only(runtime_test_window_cfg()))
	testing.expect(t, !state.running)
}

// ---------------------------------------------------------------------------
// init_runtime
// ---------------------------------------------------------------------------

@(test)
runtime_init_runtime_requires_state_and_window :: proc(t: ^testing.T) {
	with_nil_state(
		t,
		proc(t: ^testing.T) {
			testing.expect(t, !init_runtime(nil))
		},
	)

	with_runtime_env(
		t,
		proc(t: ^testing.T) {
			testing.expect(t, state.window == nil)
			testing.expect(t, !init_runtime(nil))
		},
	)
}

@(test)
runtime_init_runtime_init_failure_clears_running :: proc(t: ^testing.T) {
	sync.mutex_lock(&test_global_state_guard)
	defer sync.mutex_unlock(&test_global_state_guard)
	clear_test_hooks()
	defer clear_test_hooks()

	test_state: State
	saved_state := state
	saved_theme := theme
	defer {
		state = saved_state
		theme = saved_theme
	}

	state = &test_state
	theme = nil
	if !init_window_only(runtime_test_window_cfg()) {
		testing.expectf(t, false, "init_window_only failed: %s", sdl.GetError())
		return
	}
	defer shutdown()

	state.running = true
	test_hook_font_init_fail = true
	testing.expect(t, !init_runtime(nil))
	testing.expect(t, !state.running)
}

@(test)
runtime_init_runtime_on_ready_failure_clears_running :: proc(t: ^testing.T) {
	sync.mutex_lock(&test_global_state_guard)
	defer sync.mutex_unlock(&test_global_state_guard)
	clear_test_hooks()
	defer clear_test_hooks()

	test_state: State
	saved_state := state
	saved_theme := theme
	defer {
		state = saved_state
		theme = saved_theme
	}

	state = &test_state
	theme = nil
	if !init_window_only(runtime_test_window_cfg()) {
		testing.expectf(t, false, "init_window_only failed: %s", sdl.GetError())
		return
	}
	defer shutdown()

	state.running = true
	runtime_test_ready_ok = false
	testing.expect(t, !init_runtime(runtime_test_ready))
	testing.expect(t, !state.running)
}

@(test)
runtime_init_runtime_success_with_nil_ready :: proc(t: ^testing.T) {
	sync.mutex_lock(&test_global_state_guard)
	defer sync.mutex_unlock(&test_global_state_guard)
	clear_test_hooks()
	defer clear_test_hooks()

	test_state: State
	saved_state := state
	saved_theme := theme
	defer {
		state = saved_state
		theme = saved_theme
	}

	state = &test_state
	theme = nil
	if !init_window_only(runtime_test_window_cfg()) {
		testing.expectf(t, false, "init_window_only failed: %s", sdl.GetError())
		return
	}
	defer shutdown()

	state.running = true
	if !init_runtime(nil) {
		testing.expect(t, false, "init_runtime(nil) failed")
		return
	}
	testing.expect(t, state.running)
	testing.expect(t, state.gpu_state.pipeline != nil)
}

@(test)
runtime_init_runtime_success_with_ok_ready :: proc(t: ^testing.T) {
	sync.mutex_lock(&test_global_state_guard)
	defer sync.mutex_unlock(&test_global_state_guard)
	clear_test_hooks()
	defer clear_test_hooks()

	test_state: State
	saved_state := state
	saved_theme := theme
	defer {
		state = saved_state
		theme = saved_theme
	}

	state = &test_state
	theme = nil
	if !init_window_only(runtime_test_window_cfg()) {
		testing.expectf(t, false, "init_window_only failed: %s", sdl.GetError())
		return
	}
	defer shutdown()

	state.running = true
	runtime_test_ready_ok = true
	if !init_runtime(runtime_test_ready) {
		testing.expect(t, false, "init_runtime(ready) failed")
		return
	}
	testing.expect(t, state.running)
	testing.expect(t, state.gpu_state.pipeline != nil)
}

// ---------------------------------------------------------------------------
// migrate_state / after_realloc / realloc_failed / on_reload
// ---------------------------------------------------------------------------

@(test)
runtime_migrate_state_copies_fields_and_releases_input :: proc(t: ^testing.T) {
	src: State
	dst: State
	defer {
		delete(dst.input.text_input)
	}

	src.window = transmute(^sdl.Window)uintptr(11)
	src.gpu = transmute(^sdl.GPUDevice)uintptr(22)
	src.can_render = true
	src.running = true
	src.fullscreen = true
	src.dpi = {logical_w = 100, logical_h = 50, scale = 2, drawable_w = 200, drawable_h = 100}
	src.view = view_default()
	src.view.zoom = 1.5
	src.perf_frequency = 99
	src.last_counter = 7
	src.gamepad_instance_id = 3
	append(&src.input.text_input, 'a', 'b', 'c')

	migrate_state(&dst, &src)

	testing.expect_value(t, uintptr(dst.window), uintptr(11))
	testing.expect_value(t, uintptr(dst.gpu), uintptr(22))
	testing.expect(t, dst.can_render)
	testing.expect(t, dst.running)
	testing.expect(t, dst.fullscreen)
	testing.expect_value(t, dst.dpi.logical_w, i32(100))
	expect_close(t, dst.view.zoom, 1.5)
	testing.expect_value(t, dst.perf_frequency, u64(99))
	testing.expect_value(t, dst.last_counter, u64(7))
	testing.expect_value(t, dst.gamepad_instance_id, sdl.JoystickID(3))
	testing.expect_value(t, len(dst.input.text_input), 0)
}

@(test)
runtime_after_realloc_resets_input_and_syncs_dpi :: proc(t: ^testing.T) {
	with_engine_sdl_window_env(
		t,
		proc(t: ^testing.T) {
			state.force_reload = true
			state.force_restart = true
			state.input.mouse_left = true
			state.input.keys_down[1] = true
			append(&state.input.text_input, 'z')
			state.dpi = {}
			state.can_render = false

			after_realloc()

			testing.expect(t, !state.force_reload)
			testing.expect(t, !state.force_restart)
			testing.expect(t, !state.input.mouse_left)
			testing.expect(t, !state.input.keys_down[1])
			testing.expect_value(t, len(state.input.text_input), 0)
			testing.expect(t, state.dpi.logical_w > 0)
			testing.expect(t, state.can_render)
		},
	)
}

@(test)
runtime_realloc_failed_resets_input_only :: proc(t: ^testing.T) {
	with_runtime_env(
		t,
		proc(t: ^testing.T) {
			state.force_reload = true
			state.force_restart = true
			state.input.mouse_right = true
			append(&state.input.text_input, 'q')
			before_dpi := state.dpi

			realloc_failed()

			testing.expect(t, !state.force_reload)
			testing.expect(t, !state.force_restart)
			testing.expect(t, !state.input.mouse_right)
			testing.expect_value(t, len(state.input.text_input), 0)
			testing.expect_value(t, state.dpi.logical_w, before_dpi.logical_w)
		},
	)
}

@(test)
runtime_on_reload_refreshes_pipeline_and_dpi :: proc(t: ^testing.T) {
	with_runtime_window_env(
		t,
		proc(t: ^testing.T) {
			testing.expect(t, state.gpu_state.pipeline != nil)
			state.dpi = {}
			state.can_render = false

			on_reload()

			testing.expect(t, state.gpu_state.pipeline != nil)
			testing.expect(t, state.gpu_state.sampler != nil)
			testing.expect(t, state.dpi.logical_w > 0)
			testing.expect(t, state.can_render)
		},
	)
}

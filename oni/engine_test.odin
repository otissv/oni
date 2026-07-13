package oni

import "core:strings"
import "core:sync"
import "core:testing"
import "core:time"
import sdl "vendor:sdl3"

/*
Minimal engine state for input/view/flag tests (no window/GPU).
*/
@(private)
with_engine_env :: proc(t: ^testing.T, body: proc(t: ^testing.T)) {
	test_state: State

	sync.mutex_lock(&test_global_state_guard)
	defer sync.mutex_unlock(&test_global_state_guard)

	saved_state := state
	saved_theme := theme
	defer {
		delete(test_state.input.text_input)
		delete(test_state.gpu_state.batch.vertices)
		delete(test_state.gpu_state.batch.indices)
		delete(test_state.gpu_state.batch.segments)
		delete(test_state.gpu_state.batch.clip_stack)
		delete(test_state.gpu_state.batch.space_stack)
		state = saved_state
		widget_ctx_sync()
		theme = saved_theme
	}

	state = &test_state
	widget_ctx_sync()
	theme = nil
	clear_test_hooks()
	defer clear_test_hooks()
	state.running = true
	state.can_render = true
	state.dpi = {logical_w = 800, logical_h = 600, scale = 1, drawable_w = 800, drawable_h = 600}
	state.view = view_default()
	body(t)
}

/*
SDL event pump without a window — enough for poll_events / frame_time.
*/
@(private)
with_engine_sdl_env :: proc(t: ^testing.T, body: proc(t: ^testing.T)) {
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
	defer {
		delete(test_state.input.text_input)
		delete(test_state.gpu_state.batch.vertices)
		delete(test_state.gpu_state.batch.indices)
		delete(test_state.gpu_state.batch.segments)
		delete(test_state.gpu_state.batch.clip_stack)
		delete(test_state.gpu_state.batch.space_stack)
		state = saved_state
		widget_ctx_sync()
		theme = saved_theme
	}

	state = &test_state
	widget_ctx_sync()
	theme = nil
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
SDL window without GPU — enough for dpi_sync, fullscreen, and resize events.
*/
@(private)
with_engine_sdl_window_env :: proc(t: ^testing.T, body: proc(t: ^testing.T)) {
	sync.mutex_lock(&test_global_state_guard)
	defer sync.mutex_unlock(&test_global_state_guard)

	if !sdl.Init({.VIDEO, .GAMEPAD}) {
		testing.expectf(t, false, "SDL_Init failed: %s", sdl.GetError())
		return
	}
	defer sdl.Quit()

	window := sdl.CreateWindow("oni engine window test", 320, 240, sdl.WINDOW_RESIZABLE | sdl.WINDOW_HIGH_PIXEL_DENSITY)
	if window == nil {
		testing.expectf(t, false, "SDL_CreateWindow failed: %s", sdl.GetError())
		return
	}
	defer sdl.DestroyWindow(window)

	test_state: State
	saved_state := state
	saved_theme := theme
	defer {
		delete(test_state.input.text_input)
		delete(test_state.gpu_state.batch.vertices)
		delete(test_state.gpu_state.batch.indices)
		delete(test_state.gpu_state.batch.segments)
		delete(test_state.gpu_state.batch.clip_stack)
		delete(test_state.gpu_state.batch.space_stack)
		state = saved_state
		widget_ctx_sync()
		theme = saved_theme
	}

	state = &test_state
	widget_ctx_sync()
	theme = nil
	clear_test_hooks()
	defer clear_test_hooks()
	state.window = window
	state.running = true
	state.view = view_default()
	state.perf_frequency = sdl.GetPerformanceFrequency()
	state.last_counter = sdl.GetPerformanceCounter()
	dpi_sync()
	engine_test_drain_events()
	body(t)
}

/*
Full create_window → init → shutdown lifecycle when a display + GPU are available.
*/
@(private)
with_engine_window_env :: proc(t: ^testing.T, body: proc(t: ^testing.T)) {
	sync.mutex_lock(&test_global_state_guard)
	defer sync.mutex_unlock(&test_global_state_guard)

	test_state: State
	saved_state := state
	saved_theme := theme
	defer {
		state = saved_state
		widget_ctx_sync()
		theme = saved_theme
	}

	state = &test_state
	widget_ctx_sync()
	theme = nil
	clear_test_hooks()
	defer clear_test_hooks()

	ok := create_window(
		{
			title = "oni engine test",
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

@(private)
engine_test_drain_events :: proc() {
	e: sdl.Event
	for sdl.PollEvent(&e) {}
}

@(private)
engine_test_push :: proc(t: ^testing.T, event: sdl.Event, loc := #caller_location) -> bool {
	ev := event
	ok := sdl.PushEvent(&ev)
	testing.expectf(t, ok, "PushEvent failed: %s", sdl.GetError(), loc = loc)
	return ok
}

// ---------------------------------------------------------------------------
// dpi_sync
// ---------------------------------------------------------------------------

@(test)
engine_dpi_sync_nil_window_is_noop :: proc(t: ^testing.T) {
	with_engine_env(
		t,
		proc(t: ^testing.T) {
			before := state.dpi
			state.can_render = true
			dpi_sync()
			testing.expect_value(t, state.dpi.logical_w, before.logical_w)
			testing.expect_value(t, state.dpi.logical_h, before.logical_h)
			testing.expect(t, state.can_render)
		},
	)
}

@(test)
engine_dpi_sync_updates_from_real_window :: proc(t: ^testing.T) {
	with_engine_sdl_window_env(
		t,
		proc(t: ^testing.T) {
			state.dpi = {}
			state.can_render = false
			dpi_sync()
			testing.expect(t, state.dpi.logical_w > 0)
			testing.expect(t, state.dpi.logical_h > 0)
			testing.expect(t, state.dpi.drawable_w > 0)
			testing.expect(t, state.dpi.drawable_h > 0)
			testing.expect(t, state.dpi.scale > 0)
			testing.expect(t, state.can_render)
		},
	)
}

// ---------------------------------------------------------------------------
// Input helpers
// ---------------------------------------------------------------------------

@(test)
engine_input_begin_frame_clears_wheel_and_text :: proc(t: ^testing.T) {
	with_engine_env(
		t,
		proc(t: ^testing.T) {
			state.input.mouse_wheel_x = 3
			state.input.mouse_wheel_y = -2
			append(&state.input.text_input, 'a', 'b')
			state.input.mouse_left = true
			state.input.keys_down[1] = true

			input_begin_frame()
			expect_close(t, state.input.mouse_wheel_x, 0)
			expect_close(t, state.input.mouse_wheel_y, 0)
			testing.expect_value(t, len(state.input.text_input), 0)
			testing.expect(t, state.input.mouse_left)
			testing.expect(t, state.input.keys_down[1])
		},
	)
}

@(test)
engine_input_update_modifiers_all_flags :: proc(t: ^testing.T) {
	with_engine_env(
		t,
		proc(t: ^testing.T) {
			input_update_modifiers({})
			testing.expect(t, !state.input.modifiers.shift)
			testing.expect(t, !state.input.modifiers.ctrl)
			testing.expect(t, !state.input.modifiers.alt)
			testing.expect(t, !state.input.modifiers.super)

			input_update_modifiers(sdl.KMOD_SHIFT)
			testing.expect(t, state.input.modifiers.shift)
			testing.expect(t, !state.input.modifiers.ctrl)

			input_update_modifiers(sdl.KMOD_CTRL | sdl.KMOD_ALT | sdl.KMOD_GUI)
			testing.expect(t, !state.input.modifiers.shift)
			testing.expect(t, state.input.modifiers.ctrl)
			testing.expect(t, state.input.modifiers.alt)
			testing.expect(t, state.input.modifiers.super)

			input_update_modifiers(
				sdl.KMOD_SHIFT | sdl.KMOD_CTRL | sdl.KMOD_ALT | sdl.KMOD_GUI,
			)
			testing.expect(t, state.input.modifiers.shift)
			testing.expect(t, state.input.modifiers.ctrl)
			testing.expect(t, state.input.modifiers.alt)
			testing.expect(t, state.input.modifiers.super)
		},
	)
}

@(test)
engine_input_clear_keyboard_mouse_preserves_wheel_gamepad :: proc(t: ^testing.T) {
	with_engine_env(
		t,
		proc(t: ^testing.T) {
			state.input.keys_down[10] = true
			state.input.mouse_left = true
			state.input.mouse_right = true
			state.input.mouse_middle = true
			state.input.modifiers = {shift = true, ctrl = true}
			append(&state.input.text_input, 'x')
			state.input.mouse_wheel_y = 4
			state.input.gamepad.connected = true
			state.input.gamepad.left_stick_x = 0.5

			input_clear_keyboard_mouse()
			testing.expect(t, !state.input.keys_down[10])
			testing.expect(t, !state.input.mouse_left)
			testing.expect(t, !state.input.mouse_right)
			testing.expect(t, !state.input.mouse_middle)
			testing.expect(t, !state.input.modifiers.shift)
			testing.expect(t, !state.input.modifiers.ctrl)
			testing.expect_value(t, len(state.input.text_input), 0)
			expect_close(t, state.input.mouse_wheel_y, 4)
			testing.expect(t, state.input.gamepad.connected)
			expect_close(t, state.input.gamepad.left_stick_x, 0.5)
		},
	)
}

@(test)
engine_input_set_mouse_position_applies_dpi :: proc(t: ^testing.T) {
	with_engine_env(
		t,
		proc(t: ^testing.T) {
			state.dpi.scale = 2
			input_set_mouse_position(200, 100)
			expect_close(t, state.input.mouse_x, 100)
			expect_close(t, state.input.mouse_y, 50)

			state.dpi.scale = 0
			input_set_mouse_position(40, 60)
			expect_close(t, state.input.mouse_x, 40)
			expect_close(t, state.input.mouse_y, 60)

			state.dpi.scale = -1
			input_set_mouse_position(10, 20)
			expect_close(t, state.input.mouse_x, 10)
			expect_close(t, state.input.mouse_y, 20)
		},
	)
}

@(test)
engine_input_mouse_screen_nil_and_world :: proc(t: ^testing.T) {
	with_nil_state(
		t,
		proc(t: ^testing.T) {
			got := input_mouse_screen()
			expect_vec2(t, got, {})
		},
	)

	with_engine_env(
		t,
		proc(t: ^testing.T) {
			state.input.mouse_x = 100
			state.input.mouse_y = 50
			state.view.zoom = 2
			state.view.pan = {20, 10}
			screen := input_mouse_screen()
			expect_vec2(t, screen, {100, 50})
			world := input_mouse_world()
			expect_vec2(t, world, view_screen_to_world(screen))
		},
	)
}

// ---------------------------------------------------------------------------
// Fullscreen
// ---------------------------------------------------------------------------

@(test)
engine_set_fullscreen_nil_window_returns_false :: proc(t: ^testing.T) {
	with_engine_env(
		t,
		proc(t: ^testing.T) {
			testing.expect(t, state.window == nil)
			testing.expect(t, !set_fullscreen(true))
			testing.expect(t, !state.fullscreen)
			toggle_fullscreen()
			testing.expect(t, !state.fullscreen)
		},
	)
}

@(test)
engine_set_fullscreen_round_trip :: proc(t: ^testing.T) {
	with_engine_sdl_window_env(
		t,
		proc(t: ^testing.T) {
			testing.expect(t, !state.fullscreen)
			if !set_fullscreen(true) {
				// Some environments reject fullscreen; still exercise the API.
				return
			}
			testing.expect(t, state.fullscreen)
			testing.expect(t, set_fullscreen(false))
			testing.expect(t, !state.fullscreen)
			toggle_fullscreen()
			testing.expect(t, state.fullscreen)
			toggle_fullscreen()
			testing.expect(t, !state.fullscreen)
		},
	)
}

// ---------------------------------------------------------------------------
// frame_time
// ---------------------------------------------------------------------------

@(test)
engine_frame_time_advances_and_caps :: proc(t: ^testing.T) {
	with_engine_sdl_env(
		t,
		proc(t: ^testing.T) {
			freq := state.perf_frequency
			testing.expect(t, freq > 0)

			// Force a huge elapsed interval so the cap applies.
			state.last_counter = sdl.GetPerformanceCounter() - freq * 10
			dt := frame_time()
			testing.expect(t, dt <= MAX_FRAME_TIME + 1e-9)
			expect_close(t, f32(dt), f32(MAX_FRAME_TIME))

			time.sleep(2 * time.Millisecond)
			dt2 := frame_time()
			testing.expect(t, dt2 > 0)
			testing.expect(t, dt2 <= MAX_FRAME_TIME)
		},
	)
}

@(test)
engine_max_frame_time_constant :: proc(t: ^testing.T) {
	expect_close(t, f32(MAX_FRAME_TIME), 0.25)
}

// ---------------------------------------------------------------------------
// reset_input_state / should_run / can_render
// ---------------------------------------------------------------------------

@(test)
engine_reset_input_state_clears_flags_preserves_gamepad_handles :: proc(t: ^testing.T) {
	with_engine_env(
		t,
		proc(t: ^testing.T) {
			append(&state.input.text_input, 'z')
			state.input.mouse_left = true
			state.input.keys_down[3] = true
			state.force_reload = true
			state.force_restart = true
			state.reload_keys_prev = {f5 = true, f6 = true}
			state.running = false
			state.gamepad_instance_id = 42
			// Nil gamepad: preserve id, skip sync.
			state.gamepad = nil

			reset_input_state()
			testing.expect_value(t, len(state.input.text_input), 0)
			testing.expect(t, !state.input.mouse_left)
			testing.expect(t, !state.input.keys_down[3])
			testing.expect(t, !state.force_reload)
			testing.expect(t, !state.force_restart)
			testing.expect(t, !state.reload_keys_prev.f5)
			testing.expect(t, !state.reload_keys_prev.f6)
			testing.expect(t, state.running)
			testing.expect_value(t, state.gamepad_instance_id, sdl.JoystickID(42))
			testing.expect(t, state.gamepad == nil)
		},
	)
}

@(test)
engine_should_run_and_can_render :: proc(t: ^testing.T) {
	with_nil_state(
		t,
		proc(t: ^testing.T) {
			testing.expect(t, !should_run())
			testing.expect(t, !can_render())
		},
	)

	with_engine_env(
		t,
		proc(t: ^testing.T) {
			state.running = true
			state.can_render = true
			testing.expect(t, should_run())
			testing.expect(t, can_render())

			state.running = false
			testing.expect(t, !should_run())
			testing.expect(t, can_render())

			state.running = true
			state.can_render = false
			testing.expect(t, should_run())
			testing.expect(t, !can_render())
		},
	)
}

// ---------------------------------------------------------------------------
// Hot-reload flags
// ---------------------------------------------------------------------------

@(test)
engine_force_reload_restart_peek_consume_take :: proc(t: ^testing.T) {
	with_engine_env(
		t,
		proc(t: ^testing.T) {
			testing.expect(t, !peek_force_reload())
			testing.expect(t, !peek_force_restart())
			testing.expect(t, !take_force_reload())
			testing.expect(t, !take_force_restart())

			state.force_reload = true
			state.force_restart = true
			testing.expect(t, peek_force_reload())
			testing.expect(t, peek_force_restart())
			testing.expect(t, state.force_reload)
			testing.expect(t, state.force_restart)

			consume_force_reload()
			testing.expect(t, !state.force_reload)
			testing.expect(t, state.force_restart)
			consume_force_restart()
			testing.expect(t, !state.force_restart)

			state.force_reload = true
			state.force_restart = true
			testing.expect(t, take_force_reload())
			testing.expect(t, !state.force_reload)
			testing.expect(t, take_force_restart())
			testing.expect(t, !state.force_restart)
			testing.expect(t, !take_force_reload())
			testing.expect(t, !take_force_restart())
		},
	)
}

@(test)
engine_force_flags_nil_state_safe :: proc(t: ^testing.T) {
	with_nil_state(
		t,
		proc(t: ^testing.T) {
			testing.expect(t, !peek_force_reload())
			testing.expect(t, !peek_force_restart())
			testing.expect(t, !take_force_reload())
			testing.expect(t, !take_force_restart())
			consume_force_reload()
			consume_force_restart()
		},
	)
}

// ---------------------------------------------------------------------------
// copy_state_fields / release_input_allocations
// ---------------------------------------------------------------------------

@(test)
engine_copy_state_fields_transfers_live_handles :: proc(t: ^testing.T) {
	src: State
	dst: State
	src.window = transmute(^sdl.Window)uintptr(0x1111)
	src.gpu = transmute(^sdl.GPUDevice)uintptr(0x2222)
	src.can_render = true
	src.fullscreen = true
	src.running = true
	src.perf_frequency = 99
	src.last_counter = 88
	src.dpi = {scale = 2, logical_w = 10, logical_h = 20, drawable_w = 20, drawable_h = 40}
	src.view = {zoom = 2, pan = {1, 2}, zoom_min = 0.5, zoom_max = 4}
	src.gamepad_instance_id = 7
	src.force_reload = true
	append(&src.input.text_input, 'q')
	defer delete(src.input.text_input)

	copy_state_fields(&dst, &src)
	testing.expect(t, dst.window == src.window)
	testing.expect(t, dst.gpu == src.gpu)
	testing.expect(t, dst.can_render)
	testing.expect(t, dst.fullscreen)
	testing.expect(t, dst.running)
	testing.expect_value(t, dst.perf_frequency, u64(99))
	testing.expect_value(t, dst.last_counter, u64(88))
	testing.expect_value(t, dst.dpi.logical_w, i32(10))
	expect_close(t, dst.view.zoom, 2)
	testing.expect_value(t, dst.gamepad_instance_id, sdl.JoystickID(7))
	// Input heap is not copied.
	testing.expect_value(t, len(dst.input.text_input), 0)
	testing.expect(t, !dst.force_reload)
}

@(test)
engine_release_input_allocations_frees_text :: proc(t: ^testing.T) {
	s: State
	append(&s.input.text_input, 'a', 'b', 'c')
	testing.expect_value(t, len(s.input.text_input), 3)
	release_input_allocations(&s)
	// Callers zero input after release (see reset_input_state); delete alone frees the
	// backing store. Safe to call again on a cleared array.
	s.input.text_input = {}
	release_input_allocations(&s)
}

// ---------------------------------------------------------------------------
// init / init_window / begin_frame / end_frame / shutdown / on_hot_reload
// ---------------------------------------------------------------------------

@(test)
engine_init_requires_state_and_window :: proc(t: ^testing.T) {
	with_nil_state(
		t,
		proc(t: ^testing.T) {
			testing.expect(t, !init())
		},
	)

	with_engine_env(
		t,
		proc(t: ^testing.T) {
			testing.expect(t, state.window == nil)
			testing.expect(t, !init())
		},
	)
}

@(test)
engine_init_window_idempotent_and_lifecycle :: proc(t: ^testing.T) {
	with_engine_window_env(
		t,
		proc(t: ^testing.T) {
			testing.expect(t, state.window != nil)
			testing.expect(t, state.gpu != nil)
			testing.expect(t, should_run())
			testing.expect(t, can_render())

			cfg := Window_Config {
				title = "ignored",
				width = 100,
				height = 100,
				min_width = 10,
				min_height = 10,
			}
			testing.expect(t, init_window(cfg))

			state.view.zoom = 0
			testing.expect(t, init())
			expect_close(t, state.view.zoom, VIEW_ZOOM_DEFAULT)

			begin_frame()
			testing.expect(t, ui_pass() == .Layout)
			end_frame()

			on_hot_reload()
			testing.expect(t, can_render())
		},
	)
}

@(test)
engine_init_window_creates_when_missing :: proc(t: ^testing.T) {
	sync.mutex_lock(&test_global_state_guard)
	defer sync.mutex_unlock(&test_global_state_guard)

	test_state: State
	saved_state := state
	saved_theme := theme
	defer {
		state = saved_state
		widget_ctx_sync()
		theme = saved_theme
	}

	state = &test_state
	widget_ctx_sync()
	theme = nil
	testing.expect(t, state.window == nil)
	ok := init_window(
		{
			title = "oni init_window test",
			width = 200,
			height = 150,
			min_width = 32,
			min_height = 32,
		},
	)
	if !ok {
		testing.expectf(t, false, "init_window failed: %s", sdl.GetError())
		return
	}
	defer shutdown()
	testing.expect(t, state.window != nil)
	testing.expect(t, init_window({title = "again", width = 1, height = 1}))
}

@(test)
engine_shutdown_nil_state_safe :: proc(t: ^testing.T) {
	with_nil_state(
		t,
		proc(t: ^testing.T) {
			shutdown()
		},
	)
}

// ---------------------------------------------------------------------------
// poll_events — quit / close / focus / fullscreen window events
// ---------------------------------------------------------------------------

@(test)
engine_poll_events_quit_and_close_request :: proc(t: ^testing.T) {
	with_engine_sdl_env(
		t,
		proc(t: ^testing.T) {
			state.running = true
			engine_test_push(t, {type = .QUIT})
			poll_events()
			testing.expect(t, !state.running)

			state.running = true
			engine_test_push(t, {type = .WINDOW_CLOSE_REQUESTED})
			poll_events()
			testing.expect(t, !state.running)
		},
	)
}

@(test)
engine_poll_events_window_fullscreen_and_focus :: proc(t: ^testing.T) {
	with_engine_sdl_env(
		t,
		proc(t: ^testing.T) {
			state.input.keys_down[5] = true
			state.input.mouse_left = true
			state.input.modifiers.ctrl = true
			append(&state.input.text_input, 'k')
			state.input.mouse_wheel_y = 1

			engine_test_push(t, {type = .WINDOW_ENTER_FULLSCREEN})
			engine_test_push(t, {type = .WINDOW_FOCUS_LOST})
			poll_events()
			testing.expect(t, state.fullscreen)
			testing.expect(t, !state.input.keys_down[5])
			testing.expect(t, !state.input.mouse_left)
			testing.expect(t, !state.input.modifiers.ctrl)
			testing.expect_value(t, len(state.input.text_input), 0)
			expect_close(t, state.input.mouse_wheel_y, 1)

			engine_test_push(t, {type = .WINDOW_LEAVE_FULLSCREEN})
			poll_events()
			testing.expect(t, !state.fullscreen)
		},
	)
}

// ---------------------------------------------------------------------------
// poll_events — keyboard
// ---------------------------------------------------------------------------

@(test)
engine_poll_events_key_down_up_and_shortcuts :: proc(t: ^testing.T) {
	with_engine_sdl_env(
		t,
		proc(t: ^testing.T) {
			a := int(sdl.Scancode.A)
			engine_test_push(
				t,
				{
					key = {
						type = .KEY_DOWN,
						scancode = .A,
						key = sdl.K_A,
						mod = sdl.KMOD_SHIFT,
						repeat = false,
					},
				},
			)
			poll_events()
			testing.expect(t, state.input.keys_down[a])
			testing.expect(t, state.input.modifiers.shift)

			engine_test_push(
				t,
				{key = {type = .KEY_UP, scancode = .A, key = sdl.K_A, mod = {}}},
			)
			poll_events()
			testing.expect(t, !state.input.keys_down[a])
			testing.expect(t, !state.input.modifiers.shift)

			// Repeat KEY_DOWN is ignored for key state / shortcuts.
			state.force_reload = false
			engine_test_push(
				t,
				{
					key = {
						type = .KEY_DOWN,
						scancode = .F5,
						key = sdl.K_F5,
						repeat = true,
					},
				},
			)
			poll_events()
			testing.expect(t, !state.force_reload)

			engine_test_push(
				t,
				{key = {type = .KEY_DOWN, scancode = .ESCAPE, key = sdl.K_ESCAPE}},
			)
			poll_events()
			testing.expect(t, !state.running)

			state.running = true
			engine_test_push(
				t,
				{key = {type = .KEY_DOWN, scancode = .F5, key = sdl.K_F5}},
			)
			poll_events()
			testing.expect(t, state.force_reload)

			engine_test_push(
				t,
				{key = {type = .KEY_DOWN, scancode = .F6, key = sdl.K_F6}},
			)
			poll_events()
			testing.expect(t, state.force_restart)

			// Keycode-only F5/F6 paths (scancode may differ from switch cases).
			state.force_reload = false
			state.force_restart = false
			engine_test_push(
				t,
				{key = {type = .KEY_DOWN, scancode = .UNKNOWN, key = sdl.K_F5}},
			)
			poll_events()
			testing.expect(t, state.force_reload)

			engine_test_push(
				t,
				{key = {type = .KEY_DOWN, scancode = .UNKNOWN, key = sdl.K_F6}},
			)
			poll_events()
			testing.expect(t, state.force_restart)
		},
	)
}

@(test)
engine_poll_events_ctrl_zoom_and_reset :: proc(t: ^testing.T) {
	with_engine_sdl_env(
		t,
		proc(t: ^testing.T) {
			state.view = view_default()
			state.input.mouse_x = 100
			state.input.mouse_y = 50
			before_zoom := state.view.zoom

			engine_test_push(
				t,
				{
					key = {
						type = .KEY_DOWN,
						scancode = .EQUALS,
						mod = sdl.KMOD_CTRL,
					},
				},
			)
			poll_events()
			testing.expect(t, state.view.zoom > before_zoom)

			zoomed := state.view.zoom
			engine_test_push(
				t,
				{
					key = {
						type = .KEY_DOWN,
						scancode = .MINUS,
						mod = sdl.KMOD_CTRL,
					},
				},
			)
			poll_events()
			testing.expect(t, state.view.zoom < zoomed)

			engine_test_push(
				t,
				{
					key = {
						type = .KEY_DOWN,
						scancode = ._0,
						mod = sdl.KMOD_CTRL,
					},
				},
			)
			poll_events()
			expect_close(t, state.view.zoom, VIEW_ZOOM_DEFAULT)
			expect_vec2(t, state.view.pan, {})

			// Without ctrl, zoom keys do nothing.
			state.view.zoom = 2
			engine_test_push(
				t,
				{key = {type = .KEY_DOWN, scancode = .EQUALS, mod = {}}},
			)
			poll_events()
			expect_close(t, state.view.zoom, 2)

			// Keypad variants
			engine_test_push(
				t,
				{
					key = {
						type = .KEY_DOWN,
						scancode = .KP_PLUS,
						mod = sdl.KMOD_CTRL,
					},
				},
			)
			poll_events()
			testing.expect(t, state.view.zoom > 2)

			engine_test_push(
				t,
				{
					key = {
						type = .KEY_DOWN,
						scancode = .KP_MINUS,
						mod = sdl.KMOD_CTRL,
					},
				},
			)
			poll_events()

			engine_test_push(
				t,
				{
					key = {
						type = .KEY_DOWN,
						scancode = .KP_0,
						mod = sdl.KMOD_CTRL,
					},
				},
			)
			poll_events()
			expect_close(t, state.view.zoom, VIEW_ZOOM_DEFAULT)
		},
	)
}

@(test)
engine_poll_events_text_input :: proc(t: ^testing.T) {
	with_engine_sdl_env(
		t,
		proc(t: ^testing.T) {
			cstr := strings.clone_to_cstring("hi", context.temp_allocator)
			engine_test_push(t, {text = {type = .TEXT_INPUT, text = cstr}})
			poll_events()
			testing.expect_value(t, string(state.input.text_input[:]), "hi")

			engine_test_push(t, {text = {type = .TEXT_INPUT, text = nil}})
			poll_events()
			testing.expect_value(t, string(state.input.text_input[:]), "hi")
		},
	)
}

// ---------------------------------------------------------------------------
// poll_events — mouse
// ---------------------------------------------------------------------------

@(test)
engine_poll_events_mouse_motion_buttons_wheel :: proc(t: ^testing.T) {
	with_engine_sdl_env(
		t,
		proc(t: ^testing.T) {
			state.dpi.scale = 2
			engine_test_push(
				t,
				{motion = {type = .MOUSE_MOTION, x = 200, y = 100}},
			)
			poll_events()
			expect_close(t, state.input.mouse_x, 100)
			expect_close(t, state.input.mouse_y, 50)

			engine_test_push(
				t,
				{
					button = {
						type = .MOUSE_BUTTON_DOWN,
						button = sdl.BUTTON_LEFT,
						x = 40,
						y = 60,
					},
				},
			)
			poll_events()
			testing.expect(t, state.input.mouse_left)
			expect_close(t, state.input.mouse_x, 20)
			expect_close(t, state.input.mouse_y, 30)

			engine_test_push(
				t,
				{
					button = {
						type = .MOUSE_BUTTON_DOWN,
						button = sdl.BUTTON_RIGHT,
						x = 40,
						y = 60,
					},
				},
			)
			engine_test_push(
				t,
				{
					button = {
						type = .MOUSE_BUTTON_DOWN,
						button = sdl.BUTTON_MIDDLE,
						x = 40,
						y = 60,
					},
				},
			)
			poll_events()
			testing.expect(t, state.input.mouse_right)
			testing.expect(t, state.input.mouse_middle)

			// Middle-button pan
			state.view.pan = {}
			state.input.mouse_x = 20
			state.input.mouse_y = 30
			engine_test_push(
				t,
				{motion = {type = .MOUSE_MOTION, x = 60, y = 100}},
			)
			poll_events()
			expect_close(t, state.view.pan.x, 10) // (30-20)
			expect_close(t, state.view.pan.y, 20) // (50-30)

			engine_test_push(
				t,
				{
					button = {
						type = .MOUSE_BUTTON_UP,
						button = sdl.BUTTON_LEFT,
						x = 40,
						y = 60,
					},
				},
			)
			engine_test_push(
				t,
				{
					button = {
						type = .MOUSE_BUTTON_UP,
						button = sdl.BUTTON_RIGHT,
						x = 40,
						y = 60,
					},
				},
			)
			engine_test_push(
				t,
				{
					button = {
						type = .MOUSE_BUTTON_UP,
						button = sdl.BUTTON_MIDDLE,
						x = 40,
						y = 60,
					},
				},
			)
			poll_events()
			testing.expect(t, !state.input.mouse_left)
			testing.expect(t, !state.input.mouse_right)
			testing.expect(t, !state.input.mouse_middle)

			// Alt+left drag pans
			state.view.pan = {}
			state.input.modifiers.alt = true
			state.input.mouse_left = true
			state.input.mouse_x = 10
			state.input.mouse_y = 10
			engine_test_push(
				t,
				{motion = {type = .MOUSE_MOTION, x = 40, y = 40}},
			)
			poll_events()
			expect_close(t, state.view.pan.x, 10)
			expect_close(t, state.view.pan.y, 10)

			engine_test_push(
				t,
				{
					wheel = {
						type = .MOUSE_WHEEL,
						x = 1.5,
						y = -2.25,
						mouse_x = 80,
						mouse_y = 120,
					},
				},
			)
			poll_events()
			expect_close(t, state.input.mouse_wheel_x, 1.5)
			expect_close(t, state.input.mouse_wheel_y, -2.25)
			expect_close(t, state.input.mouse_x, 40)
			expect_close(t, state.input.mouse_y, 60)
		},
	)
}

// ---------------------------------------------------------------------------
// poll_events — gamepad
// ---------------------------------------------------------------------------

@(test)
engine_poll_events_gamepad_axis_button_and_remove :: proc(t: ^testing.T) {
	with_engine_sdl_env(
		t,
		proc(t: ^testing.T) {
			state.gamepad_instance_id = 99

			engine_test_push(
				t,
				{
					gaxis = {
						type = .GAMEPAD_AXIS_MOTION,
						which = 99,
						axis = u8(sdl.GamepadAxis.LEFTX),
						value = 32767,
					},
				},
			)
			poll_events()
			testing.expect(t, state.input.gamepad.left_stick_x > 0.5)

			// Wrong instance id ignored
			state.input.gamepad.left_stick_x = 0
			engine_test_push(
				t,
				{
					gaxis = {
						type = .GAMEPAD_AXIS_MOTION,
						which = 1,
						axis = u8(sdl.GamepadAxis.LEFTX),
						value = 32767,
					},
				},
			)
			poll_events()
			expect_close(t, state.input.gamepad.left_stick_x, 0)

			engine_test_push(
				t,
				{
					gbutton = {
						type = .GAMEPAD_BUTTON_DOWN,
						which = 99,
						button = u8(sdl.GamepadButton.DPAD_UP),
					},
				},
			)
			poll_events()
			testing.expect(t, state.input.gamepad.dpad_up)

			engine_test_push(
				t,
				{
					gbutton = {
						type = .GAMEPAD_BUTTON_UP,
						which = 99,
						button = u8(sdl.GamepadButton.DPAD_UP),
					},
				},
			)
			poll_events()
			testing.expect(t, !state.input.gamepad.dpad_up)

			// START toggles fullscreen only when a window exists — with nil window, flag stays false.
			engine_test_push(
				t,
				{
					gbutton = {
						type = .GAMEPAD_BUTTON_DOWN,
						which = 99,
						button = u8(sdl.GamepadButton.START),
					},
				},
			)
			poll_events()
			testing.expect(t, !state.fullscreen)

			// REMOVED with matching id closes when handle is set; with nil handle, no-op.
			engine_test_push(
				t,
				{gdevice = {type = .GAMEPAD_REMOVED, which = 99}},
			)
			poll_events()
			testing.expect(t, state.gamepad == nil)

			// ADDED with bogus id fails OpenGamepad gracefully.
			engine_test_push(
				t,
				{gdevice = {type = .GAMEPAD_ADDED, which = 123456}},
			)
			poll_events()
			testing.expect(t, state.gamepad == nil)
		},
	)
}

// ---------------------------------------------------------------------------
// poll_reload_keys
// ---------------------------------------------------------------------------

@(test)
engine_poll_reload_keys_updates_prev_without_false_trigger :: proc(t: ^testing.T) {
	with_engine_sdl_env(
		t,
		proc(t: ^testing.T) {
			// Pretend F5 was held last frame; if hardware is not holding F5 now,
			// edge detect must not fire and prev must clear.
			state.reload_keys_prev = {f5 = true, f6 = true}
			state.force_reload = false
			state.force_restart = false
			poll_reload_keys()
			kb := sdl.GetKeyboardState(nil)
			if kb != nil {
				if !kb[int(sdl.Scancode.F5)] {
					testing.expect(t, !state.force_reload)
					testing.expect(t, !state.reload_keys_prev.f5)
				}
				if !kb[int(sdl.Scancode.F6)] {
					testing.expect(t, !state.force_restart)
					testing.expect(t, !state.reload_keys_prev.f6)
				}
			}
		},
	)
}

@(test)
engine_poll_events_calls_poll_reload_keys :: proc(t: ^testing.T) {
	with_engine_sdl_env(
		t,
		proc(t: ^testing.T) {
			state.reload_keys_prev = {f5 = true, f6 = true}
			poll_events()
			kb := sdl.GetKeyboardState(nil)
			if kb != nil && !kb[int(sdl.Scancode.F5)] {
				testing.expect(t, !state.reload_keys_prev.f5)
			}
		},
	)
}

// ---------------------------------------------------------------------------
// Window resize events (need a real window for dpi_sync side effects)
// ---------------------------------------------------------------------------

@(test)
engine_poll_events_resize_triggers_dpi_sync :: proc(t: ^testing.T) {
	with_engine_sdl_window_env(
		t,
		proc(t: ^testing.T) {
			state.dpi.logical_w = 1
			state.dpi.logical_h = 1
			engine_test_push(t, {type = .WINDOW_RESIZED})
			poll_events()
			testing.expect(t, state.dpi.logical_w > 1)
			testing.expect(t, state.can_render)

			state.dpi.logical_w = 1
			engine_test_push(t, {type = .WINDOW_PIXEL_SIZE_CHANGED})
			poll_events()
			testing.expect(t, state.dpi.logical_w > 1)

			state.dpi.logical_w = 1
			engine_test_push(t, {type = .WINDOW_DISPLAY_SCALE_CHANGED})
			poll_events()
			testing.expect(t, state.dpi.logical_w > 1)
		},
	)
}

@(test)
engine_poll_events_f11_toggles_fullscreen :: proc(t: ^testing.T) {
	with_engine_sdl_window_env(
		t,
		proc(t: ^testing.T) {
			was := state.fullscreen
			engine_test_push(
				t,
				{key = {type = .KEY_DOWN, scancode = .F11, key = sdl.K_F11}},
			)
			poll_events()
			// May fail on some WMs; only assert when SDL accepted the change.
			if state.fullscreen != was {
				engine_test_push(
					t,
					{key = {type = .KEY_DOWN, scancode = .F11, key = sdl.K_F11}},
				)
				poll_events()
				testing.expect_value(t, state.fullscreen, was)
			}
		},
	)
}

@(test)
engine_poll_events_gamepad_start_toggles_fullscreen_with_window :: proc(t: ^testing.T) {
	with_engine_sdl_window_env(
		t,
		proc(t: ^testing.T) {
			state.gamepad_instance_id = 7
			was := state.fullscreen
			engine_test_push(
				t,
				{
					gbutton = {
						type = .GAMEPAD_BUTTON_DOWN,
						which = 7,
						button = u8(sdl.GamepadButton.START),
					},
				},
			)
			poll_events()
			if state.fullscreen != was {
				engine_test_push(
					t,
					{
						gbutton = {
							type = .GAMEPAD_BUTTON_DOWN,
							which = 7,
							button = u8(sdl.GamepadButton.START),
						},
					},
				)
				poll_events()
				testing.expect_value(t, state.fullscreen, was)
			}
		},
	)
}

@(test)
engine_window_config_fields_accepted :: proc(t: ^testing.T) {
	cfg := Window_Config {
		title                 = "title",
		width                 = 640,
		height                = 480,
		min_width             = 100,
		min_height             = 80,
	}
	testing.expect_value(t, cfg.width, i32(640))
	testing.expect_value(t, cfg.height, i32(480))
	testing.expect_value(t, cfg.min_width, i32(100))
	testing.expect_value(t, cfg.min_height, i32(80))
	testing.expect(t, cfg.title == "title")
}

// ---------------------------------------------------------------------------
// Gap coverage: dpi_sync failure / edge branches
// ---------------------------------------------------------------------------

@(test)
engine_dpi_sync_get_window_size_failure_disables_render :: proc(t: ^testing.T) {
	with_engine_sdl_window_env(
		t,
		proc(t: ^testing.T) {
			state.can_render = true
			test_hook_dpi_sync_fail_get_size = true
			dpi_sync()
			testing.expect(t, !state.can_render)
		},
	)
}

@(test)
engine_dpi_sync_get_window_size_in_pixels_failure_disables_render :: proc(t: ^testing.T) {
	with_engine_sdl_window_env(
		t,
		proc(t: ^testing.T) {
			state.can_render = true
			test_hook_dpi_sync_fail_get_pixels = true
			dpi_sync()
			testing.expect(t, !state.can_render)
		},
	)
}

@(test)
engine_dpi_sync_zero_logical_width_uses_scale_one :: proc(t: ^testing.T) {
	with_engine_sdl_window_env(
		t,
		proc(t: ^testing.T) {
			test_hook_dpi_sync_force_logical_w_zero = true
			dpi_sync()
			testing.expect_value(t, state.dpi.logical_w, i32(0))
			expect_close(t, state.dpi.scale, 1)
			testing.expect(t, state.can_render) // drawable still positive
		},
	)
}

@(test)
engine_dpi_sync_zero_drawable_disables_render :: proc(t: ^testing.T) {
	with_engine_sdl_window_env(
		t,
		proc(t: ^testing.T) {
			state.can_render = true
			test_hook_dpi_sync_force_drawable_zero = true
			dpi_sync()
			testing.expect_value(t, state.dpi.drawable_w, i32(0))
			testing.expect_value(t, state.dpi.drawable_h, i32(0))
			testing.expect(t, !state.can_render)
		},
	)
}

@(test)
engine_dpi_sync_destroyed_window_disables_render :: proc(t: ^testing.T) {
	sync.mutex_lock(&test_global_state_guard)
	defer sync.mutex_unlock(&test_global_state_guard)
	clear_test_hooks()
	defer clear_test_hooks()

	if !sdl.Init({.VIDEO}) {
		testing.expectf(t, false, "SDL_Init failed: %s", sdl.GetError())
		return
	}
	defer sdl.Quit()

	window := sdl.CreateWindow("oni dpi destroy", 100, 100, {})
	if window == nil {
		testing.expectf(t, false, "CreateWindow failed: %s", sdl.GetError())
		return
	}

	test_state: State
	saved := state
	defer {state = saved}
	state = &test_state
	widget_ctx_sync()
	state.window = window
	state.can_render = true
	sdl.DestroyWindow(window)
	// Dangling handle: GetWindowSize should fail.
	dpi_sync()
	testing.expect(t, !state.can_render)
	state.window = nil
}

// ---------------------------------------------------------------------------
// Gap coverage: set_fullscreen SDL reject
// ---------------------------------------------------------------------------

@(test)
engine_set_fullscreen_sdl_failure_leaves_flag_unchanged :: proc(t: ^testing.T) {
	with_engine_sdl_window_env(
		t,
		proc(t: ^testing.T) {
			state.fullscreen = false
			test_hook_set_fullscreen_fail = true
			testing.expect(t, !set_fullscreen(true))
			testing.expect(t, !state.fullscreen)
		},
	)
}

// ---------------------------------------------------------------------------
// Gap coverage: create_window failure teardowns
// ---------------------------------------------------------------------------

@(private)
engine_test_create_window_cfg :: proc() -> Window_Config {
	return {
		title = "oni create_window fail",
		width = 160,
		height = 120,
		min_width = 32,
		min_height = 32,
	}
}

@(test)
engine_create_window_fail_init_returns_false :: proc(t: ^testing.T) {
	sync.mutex_lock(&test_global_state_guard)
	defer sync.mutex_unlock(&test_global_state_guard)
	clear_test_hooks()
	defer clear_test_hooks()

	test_state: State
	saved := state
	defer {state = saved}
	state = &test_state
	widget_ctx_sync()
	test_hook_create_window_fail = .Init
	testing.expect(t, !create_window(engine_test_create_window_cfg()))
	testing.expect(t, state.window == nil)
	testing.expect(t, state.gpu == nil)
}

@(test)
engine_create_window_fail_window_tears_down :: proc(t: ^testing.T) {
	sync.mutex_lock(&test_global_state_guard)
	defer sync.mutex_unlock(&test_global_state_guard)
	clear_test_hooks()
	defer clear_test_hooks()

	test_state: State
	saved := state
	defer {state = saved}
	state = &test_state
	widget_ctx_sync()
	test_hook_create_window_fail = .Window
	testing.expect(t, !create_window(engine_test_create_window_cfg()))
	testing.expect(t, state.window == nil)
	testing.expect(t, state.gpu == nil)
}

@(test)
engine_create_window_fail_gpu_tears_down_window :: proc(t: ^testing.T) {
	sync.mutex_lock(&test_global_state_guard)
	defer sync.mutex_unlock(&test_global_state_guard)
	clear_test_hooks()
	defer clear_test_hooks()

	test_state: State
	saved := state
	defer {state = saved}
	state = &test_state
	widget_ctx_sync()
	test_hook_create_window_fail = .Gpu
	testing.expect(t, !create_window(engine_test_create_window_cfg()))
	testing.expect(t, state.window == nil)
	testing.expect(t, state.gpu == nil)
}

@(test)
engine_create_window_fail_claim_tears_down :: proc(t: ^testing.T) {
	sync.mutex_lock(&test_global_state_guard)
	defer sync.mutex_unlock(&test_global_state_guard)
	clear_test_hooks()
	defer clear_test_hooks()

	test_state: State
	saved := state
	defer {state = saved}
	state = &test_state
	widget_ctx_sync()
	test_hook_create_window_fail = .Claim
	testing.expect(t, !create_window(engine_test_create_window_cfg()))
	testing.expect(t, state.window == nil)
	testing.expect(t, state.gpu == nil)
}

@(test)
engine_create_window_fail_swapchain_tears_down :: proc(t: ^testing.T) {
	sync.mutex_lock(&test_global_state_guard)
	defer sync.mutex_unlock(&test_global_state_guard)
	clear_test_hooks()
	defer clear_test_hooks()

	test_state: State
	saved := state
	defer {state = saved}
	state = &test_state
	widget_ctx_sync()
	test_hook_create_window_fail = .Swapchain
	testing.expect(t, !create_window(engine_test_create_window_cfg()))
	testing.expect(t, state.window == nil)
	testing.expect(t, state.gpu == nil)
}

// ---------------------------------------------------------------------------
// Gap coverage: init font_init failure cleanup
// ---------------------------------------------------------------------------

@(test)
engine_init_font_init_failure_cleans_up_and_returns_false :: proc(t: ^testing.T) {
	sync.mutex_lock(&test_global_state_guard)
	defer sync.mutex_unlock(&test_global_state_guard)
	clear_test_hooks()
	defer clear_test_hooks()

	test_state: State
	saved := state
	saved_theme := theme
	defer {
		state = saved
		widget_ctx_sync()
		theme = saved_theme
	}
	state = &test_state
	widget_ctx_sync()
	theme = nil

	testing.expect(t, create_window(engine_test_create_window_cfg()))
	defer shutdown()

	test_hook_font_init_fail = true
	testing.expect(t, !init())
	testing.expect(t, state.fonts.library == nil)
	// Window/GPU from create_window remain; init only tears down GPU stack resources.
	testing.expect(t, state.window != nil)
	testing.expect(t, state.gpu != nil)
}

// ---------------------------------------------------------------------------
// Gap coverage: reset_input_state with live gamepad
// ---------------------------------------------------------------------------

@(test)
engine_reset_input_state_syncs_connected_gamepad :: proc(t: ^testing.T) {
	with_engine_sdl_env(
		t,
		proc(t: ^testing.T) {
			gamepad_open_first_available()
			if state.gamepad == nil {
				// No physical gamepad — still verify nil path stays safe (already covered).
				return
			}
			defer gamepad_close()

			state.input.gamepad.left_stick_x = 0.9
			state.force_reload = true
			reset_input_state()
			testing.expect(t, !state.force_reload)
			testing.expect(t, state.gamepad != nil)
			testing.expect(t, state.input.gamepad.connected)
		},
	)
}

// ---------------------------------------------------------------------------
// Gap coverage: poll_reload_keys rising edge + nil keyboard
// ---------------------------------------------------------------------------

@(test)
engine_poll_reload_keys_nil_keyboard_is_noop :: proc(t: ^testing.T) {
	with_engine_env(
		t,
		proc(t: ^testing.T) {
			// SDL not initialized → GetKeyboardState returns nil.
			state.force_reload = false
			state.reload_keys_prev = {}
			poll_reload_keys()
			testing.expect(t, !state.force_reload)
			testing.expect(t, !state.reload_keys_prev.f5)
		},
	)
}

@(test)
engine_poll_reload_keys_rising_edge_sets_force_flags :: proc(t: ^testing.T) {
	with_engine_env(
		t,
		proc(t: ^testing.T) {
			test_hook_keyboard_override = true
			test_hook_keyboard_f5 = false
			test_hook_keyboard_f6 = false
			state.reload_keys_prev = {}
			state.force_reload = false
			state.force_restart = false

			poll_reload_keys()
			testing.expect(t, !state.force_reload)
			testing.expect(t, !state.force_restart)

			test_hook_keyboard_f5 = true
			test_hook_keyboard_f6 = true
			poll_reload_keys()
			testing.expect(t, state.force_reload)
			testing.expect(t, state.force_restart)
			testing.expect(t, state.reload_keys_prev.f5)
			testing.expect(t, state.reload_keys_prev.f6)

			// Held: no re-trigger
			state.force_reload = false
			state.force_restart = false
			poll_reload_keys()
			testing.expect(t, !state.force_reload)
			testing.expect(t, !state.force_restart)

			// Release then press again
			test_hook_keyboard_f5 = false
			test_hook_keyboard_f6 = false
			poll_reload_keys()
			testing.expect(t, !state.reload_keys_prev.f5)
			test_hook_keyboard_f5 = true
			poll_reload_keys()
			testing.expect(t, state.force_reload)
		},
	)
}

// ---------------------------------------------------------------------------
// Gap coverage: out-of-range scancode
// ---------------------------------------------------------------------------

@(test)
engine_poll_events_ignores_out_of_range_scancode :: proc(t: ^testing.T) {
	with_engine_sdl_env(
		t,
		proc(t: ^testing.T) {
			oob := sdl.Scancode(KEY_COUNT)
			engine_test_push(
				t,
				{key = {type = .KEY_DOWN, scancode = oob, key = sdl.K_A}},
			)
			poll_events()
			// Must not write past keys_down array; no crash and no in-range key set.
			testing.expect(t, !state.input.keys_down[0])

			engine_test_push(
				t,
				{key = {type = .KEY_UP, scancode = oob, key = sdl.K_A}},
			)
			poll_events()
		},
	)
}

// ---------------------------------------------------------------------------
// Gap coverage: copy_state_fields full field set
// ---------------------------------------------------------------------------

@(test)
engine_copy_state_fields_copies_all_live_subsystems :: proc(t: ^testing.T) {
	src: State
	dst: State
	src.window = transmute(^sdl.Window)uintptr(1)
	src.gpu = transmute(^sdl.GPUDevice)uintptr(2)
	src.gpu_state.pipeline = transmute(^sdl.GPUGraphicsPipeline)uintptr(3)
	src.assets.paths = make(map[string]Asset_Id)
	defer delete(src.assets.paths)
	src.assets.paths["x"] = Asset_Id(9)
	src.textures.atlas.width = 128
	src.fonts.library = transmute(FT_Library)uintptr(4)
	src.dpi = {scale = 1.5, logical_w = 10, logical_h = 20, drawable_w = 15, drawable_h = 30}
	src.view = {zoom = 2, pan = {3, 4}, zoom_min = 0.5, zoom_max = 4}
	src.can_render = true
	src.fullscreen = true
	src.perf_frequency = 11
	src.last_counter = 22
	src.running = true
	src.ui.frame = 7
	src.gamepad = transmute(^sdl.Gamepad)uintptr(5)
	src.gamepad_instance_id = 99
	src.force_reload = true
	src.force_restart = true
	append(&src.input.text_input, 'z')
	defer delete(src.input.text_input)

	copy_state_fields(&dst, &src)
	testing.expect(t, dst.window == src.window)
	testing.expect(t, dst.gpu == src.gpu)
	testing.expect(t, dst.gpu_state.pipeline == src.gpu_state.pipeline)
	testing.expect(t, dst.assets.paths["x"] == Asset_Id(9))
	testing.expect_value(t, dst.textures.atlas.width, i32(128))
	testing.expect(t, dst.fonts.library == src.fonts.library)
	expect_close(t, dst.dpi.scale, 1.5)
	expect_close(t, dst.view.zoom, 2)
	expect_vec2(t, dst.view.pan, {3, 4})
	testing.expect(t, dst.can_render)
	testing.expect(t, dst.fullscreen)
	testing.expect_value(t, dst.perf_frequency, u64(11))
	testing.expect_value(t, dst.last_counter, u64(22))
	testing.expect(t, dst.running)
	testing.expect_value(t, dst.ui.frame, u64(7))
	testing.expect(t, dst.gamepad == src.gamepad)
	testing.expect_value(t, dst.gamepad_instance_id, sdl.JoystickID(99))
	testing.expect_value(t, len(dst.input.text_input), 0)
	testing.expect(t, !dst.force_reload)
	testing.expect(t, !dst.force_restart)
}

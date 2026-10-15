package oni

Tick_Proc :: proc(dt: f32)
Ready_Proc :: proc() -> bool

@(private)
has_init_run_once := false

@(private)
run_init_once :: proc(prc: proc()) {
	if has_init_run_once do return
	has_init_run_once = true
	if prc != nil do prc()
}

/*
Runs one full frame: pacing wait, timing, input, UI begin, tick, present, end.

Under on-demand effective pacing, waits for input/wake/timeout when idle.
Pass app-specific tick and draw callbacks; returns early if state is nil
or the window cannot render. Housekeeping-only idle timeouts may skip the
frame body when nothing is dirty. Wake-deadline-only iterations may still
run tick but skip `present_frame` when nothing marked oneshot dirty.
Typical app draw calls o.Render inside present_frame (Layout + Draw + prune);
host end_frame calls ui_end_frame again afterward.
*/
run_frame :: proc(tick: Tick_Proc, draw: Draw_Proc, init: proc()) {
	if state == nil do return

	frame_wait_if_idle()

	dt := frame_time()
	input_begin_frame()

	poll_events()
	settings_poll()

	if !can_render() do return

	pacing := frame_pacing_effective()

	if pacing == .On_Demand && !frame_work_pending() {
		return
	}

	// Snapshot oneshot dirty before consume so on-demand can present this frame
	// even though Request_Frame during tick must survive for the next iteration.
	entered_dirty := state.frame_dirty
	frame_consume_dirty()

	ui_begin_frame()

	if tick != nil do tick(f32(dt))

	run_init_once(init)

	if frame_should_present(entered_dirty) {
		present_frame(draw)
	}

	frame_after_present()
	end_frame()
}

/*
Creates the SDL window without initializing the GPU runtime.

Call once before init_runtime; safe to call again if the window already
exists. Sets running to false on failure.
*/
init_window_only :: proc(config: Window_Config) -> bool {
	if state == nil do return false
	if state.window != nil do return true

	if !init_window(config) {
		state.running = false
		return false
	}

	state.running = true
	return true
}

/*
Initializes the GPU runtime, fonts, and UI after the window exists.

Optionally runs on_ready for app setup (e.g. theme build). Sets running
to false if init or the callback fails.
*/
init_runtime :: proc(on_ready: Ready_Proc) -> bool {
	if state == nil || state.window == nil do return false

	if !init() {
		state.running = false
		return false
	}

	if on_ready != nil && !on_ready() {
		state.running = false
		return false
	}

	return true
}

/*
Copies engine-owned fields from src into dst during persistent realloc.

Releases heap allocations owned by src input state; dst receives live
SDL/GPU handles and survives the old block being freed.
*/
migrate_state :: proc(dst: ^State, src: ^State) {
	copy_state_fields(dst, src)
	release_input_allocations(src)
}

/*
Resets input and syncs DPI after a successful persistent realloc.

Call after migrate_state and rebinding globals; does not touch GPU assets.
*/
after_realloc :: proc() {
	reset_input_state()
	dpi_sync()
}

/*
Resets input state after a failed persistent realloc.

Call when allocation fails so stale input and reload flags are cleared
without assuming a valid engine block.
*/
realloc_failed :: proc() {
	reset_input_state()
}

/*
Notifies the engine that the app library was hot-reloaded.

Reloads GPU pipeline state and refreshes DPI; call from app_hot_reloaded
after rebinding persistent state.
*/
on_reload :: proc() {
	on_hot_reload()
}

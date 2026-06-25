package oni

Tick_Proc :: proc(dt: f32)
Ready_Proc :: proc() -> bool

/*
Runs one full frame: timing, input, tick, UI end, and present.

Pass app-specific tick and draw callbacks; returns early if state is nil
or the window cannot render.
*/
run_frame :: proc(tick: Tick_Proc, draw: Draw_Proc) {
	if state == nil do return

	dt := frame_time()
	input_begin_frame()
	poll_events()

	if !can_render() do return

	ui_begin_frame()
	if tick != nil do tick(f32(dt))
	end_frame()
	present_frame(draw)
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

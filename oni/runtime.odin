package oni

Tick_Proc :: proc(dt: f32)
Ready_Proc :: proc() -> bool

run_frame :: proc(tick: Tick_Proc, draw: Draw_Proc) {
	if state == nil do return

	dt := frame_time()
	input_begin_frame()
	poll_events()

	if !can_render() do return

	begin_frame()
	if tick != nil do tick(f32(dt))
	end_frame()
	present_frame(draw)
}

init_window_only :: proc(config: Window_Config) -> bool {
	if state == nil do return false
	if state.window != nil do return true

	if !init_window(config) {
		state.running = false
		return false
	}

	return true
}

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

migrate_state :: proc(dst: ^State, src: ^State) {
	copy_state_fields(dst, src)
	release_input_allocations(src)
}

after_realloc :: proc() {
	reset_input_state()
	dpi_sync()
}

realloc_failed :: proc() {
	reset_input_state()
}

on_reload :: proc() {
	on_hot_reload()
}

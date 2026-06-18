package app

import "core:fmt"
import "core:mem"
import oni "../oni"

window_config :: proc() -> oni.Window_Config {
	return {
		title      = WINDOW_TITLE,
		width      = WINDOW_WIDTH,
		height     = WINDOW_HEIGHT,
		min_width  = MIN_WINDOW_W,
		min_height = MIN_WINDOW_H,
	}
}

reset_app_state :: proc() {
	persistent.app = {}
	persistent.app.theme = build_theme()
}

@(export)
app_init_window :: proc() {
	ensure_persistent()
	if !oni.Init_Window_Only(window_config()) {
		persistent.engine.running = false
	}
}

@(export)
app_init :: proc() {
	ensure_persistent()
	if persistent.engine.window == nil {
		persistent.engine.running = false
		return
	}

	if !oni.Init_Runtime(proc() -> bool {
		persistent.app.theme = build_theme()
		return true
	}) {
		persistent.engine.running = false
	}
}

@(export)
app_update :: proc() {
	if persistent == nil do return
	bind()
	oni.Run_Frame(app_tick, app_draw)
}

@(export)
app_should_run :: proc() -> bool {
	if persistent == nil do return false
	bind()
	return oni.Should_Run()
}

@(export)
app_shutdown :: proc() {
	if persistent == nil do return
	bind()
	oni.Shutdown()
	free(persistent)
	persistent = nil
}

@(export)
app_shutdown_window :: proc() {}

@(export)
app_memory :: proc() -> rawptr {
	return persistent
}

@(export)
app_memory_size :: proc() -> int {
	return size_of(Persistent)
}

@(export)
app_hot_reloaded :: proc(mem: rawptr) {
	persistent = cast(^Persistent)mem
	bind()
	oni.On_Reload()
}

@(export)
app_reset :: proc() {
	if persistent == nil do return
	bind()
	oni.Reset_Input_State()
	reset_app_state()
}

@(export)
app_realloc :: proc(new_size: int) {
	if persistent == nil do return

	ptr, err := mem.alloc(new_size)
	if err != nil {
		fmt.eprintln("Failed to allocate Persistent:", err)
		bind()
		oni.Realloc_Failed()
		reset_app_state()
		return
	}

	old := persistent
	persistent = cast(^Persistent)ptr
	mem.zero(persistent, new_size)

	oni.Migrate_State(&persistent.engine, &old.engine)
	free(old)

	bind()
	oni.After_Realloc()
	reset_app_state()
}

@(export)
app_force_reload :: proc() -> bool {
	if persistent == nil do return false
	bind()
	return oni.Take_Force_Reload()
}

@(export)
app_force_restart :: proc() -> bool {
	if persistent == nil do return false
	bind()
	return oni.Take_Force_Restart()
}

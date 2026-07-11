package app

import o "../oni"
import g "./globlas"
import "core:fmt"
import "core:mem"

/*
Root heap allocation shared between the host and hot-reloaded app library.

Holds engine state and app state; layout size is exported for reload detection.
*/
Persistent :: struct {
	engine: o.State,
	app:    g.Global_State,
}

persistent: ^Persistent

// Optional once-per-run hook; wire from app.odin when needed (see templates/app.odin).
init: proc()

/*
Re-binds o engine, theme, and globals.app to the current persistent state.

Call after any operation that may change the persistent pointer, such as
allocation, hot reload, or realloc.
*/
bind :: proc() {
	o.Bind(&persistent.engine, &persistent.app.theme)
	g.app = &persistent.app
}

/*
Allocates persistent state on first use and binds o globals.

Safe to call from any exported entry point before touching engine state.
*/
ensure_persistent :: proc() {
	if persistent == nil {
		persistent = new(Persistent)
		persistent.app.Route = .Widgets
	}
	bind()
}

/*
Per-frame app update passed to o.Run_Frame.

Handles mouse-wheel zoom around the cursor in screen space.
*/
app_tick :: proc(dt: f32) {
	g.app.frame_dt = dt

	if persistent.engine.input.mouse_wheel_y == 0 do return

	mouse := o.Input_Mouse_Screen()
	factor := ZOOM_WHEEL_STEP
	if persistent.engine.input.mouse_wheel_y < 0 {
		factor = 1 / ZOOM_WHEEL_STEP
	}
	o.View_Zoom_By_Screen(mouse, factor)
}

/*
Returns the initial SDL window configuration for this app.
*/
window_config :: proc() -> o.Window_Config {
	return {
		title = WINDOW_TITLE,
		width = WINDOW_WIDTH,
		height = WINDOW_HEIGHT,
		min_width = MIN_WINDOW_W,
		min_height = MIN_WINDOW_H,
	}
}

/*
Clears app-local state and rebuilds the default theme.

Engine state is preserved; used after realloc failure and full restarts.
*/
reset_app_state :: proc() {
	persistent.app = {}
	persistent.app.theme = build_theme()
	persistent.app.Route = .Widgets
}

/*
Creates the SDL window without initializing the GPU runtime.

Exported hot-reload entry point called once by the host before app_init.
*/
@(export)
app_init_window :: proc() {
	ensure_persistent()
	if !o.Init_Window_Only(window_config()) {
		persistent.engine.running = false
		return
	}
	persistent.engine.running = true
}

/*
Initializes the GPU runtime and app theme after the window exists.

Exported hot-reload entry point. Sets running to false if init fails.
*/
@(export)
app_init :: proc() {
	ensure_persistent()
	if persistent.engine.window == nil {
		persistent.engine.running = false
		return
	}

	if !o.Init_Runtime(proc() -> bool {
		persistent.app.theme = build_theme()
		return true
	}) {
		persistent.engine.running = false
	}
}

/*
Runs one frame: input, tick, draw, and present.

Exported hot-reload entry point called each loop iteration by the host.
*/
@(export)
app_update :: proc() {
	if persistent == nil do return
	bind()

	o.Run_Frame(app_tick, app_draw, init)
}

/*
Reports whether the main loop should continue.

Exported hot-reload entry point. Returns false after a failed init or quit.
*/
@(export)
app_should_run :: proc() -> bool {
	if persistent == nil do return false
	bind()
	return o.Should_Run()
}

/*
Tears down the GPU runtime and frees persistent state.

Exported hot-reload entry point called when the host exits.
*/
@(export)
app_shutdown :: proc() {
	if persistent == nil do return
	bind()
	o.Shutdown()
	free(persistent)
	persistent = nil
	g.app = nil
}

/*
Window teardown hook for the hot-reload API.

The host owns the window across reloads; this export is intentionally empty.
*/
@(export)
app_shutdown_window :: proc() {}

/*
Returns the heap pointer to persistent state for hot reload.

Exported hot-reload entry point. The host passes this to app_hot_reloaded
after swapping the shared library.
*/
@(export)
app_memory :: proc() -> rawptr {
	return persistent
}

/*
Returns the size of Persistent for layout-change detection.

Exported hot-reload entry point. A size mismatch triggers realloc on reload.
*/
@(export)
app_memory_size :: proc() -> int {
	return size_of(Persistent)
}

/*
Restores persistent state after the host reloads the app library.

Exported hot-reload entry point. Receives the pointer from app_memory and
notifies o so engine resources survive the DLL swap.
*/
@(export)
app_hot_reloaded :: proc(mem: rawptr) {
	persistent = cast(^Persistent)mem
	bind()
	o.On_Reload()
}

/*
Resets app state while keeping the window and GPU runtime alive.

Exported hot-reload entry point used for full restarts (F6) when memory
layout is unchanged.
*/
@(export)
app_reset :: proc() {
	if persistent == nil do return
	bind()
	o.Reset_Input_State()
	reset_app_state()
}

/*
Reallocates persistent state when the struct layout changes.

Exported hot-reload entry point. Migrates engine state into the new block,
frees the old allocation, and rebuilds app-local state.
*/
@(export)
app_realloc :: proc(new_size: int) {
	if persistent == nil do return

	ptr, err := mem.alloc(new_size)
	if err != nil {
		fmt.eprintln("Failed to allocate Persistent:", err)
		bind()
		o.Realloc_Failed()
		reset_app_state()
		return
	}

	old := persistent
	persistent = cast(^Persistent)ptr
	mem.zero(persistent, new_size)

	o.Migrate_State(&persistent.engine, &old.engine)
	free(old)

	bind()
	o.After_Realloc()
	reset_app_state()
}

/*
Reads and clears the force-reload flag (F5).

Exported hot-reload entry point. Prefer peek/consume when the host
coordinates reload timing.
*/
@(export)
app_force_reload :: proc() -> bool {
	if persistent == nil do return false
	bind()
	return o.Take_Force_Reload()
}

/*
Reads and clears the force-restart flag (F6).

Exported hot-reload entry point. Prefer peek/consume when the host
coordinates reload timing.
*/
@(export)
app_force_restart :: proc() -> bool {
	if persistent == nil do return false
	bind()
	return o.Take_Force_Restart()
}

/*
Returns whether a hot reload was requested without clearing the flag.

Exported hot-reload entry point used by the host reloader each frame.
*/
@(export)
app_peek_force_reload :: proc() -> bool {
	if persistent == nil do return false
	bind()
	return o.Peek_Force_Reload()
}

/*
Returns whether a full restart was requested without clearing the flag.

Exported hot-reload entry point used by the host reloader each frame.
*/
@(export)
app_peek_force_restart :: proc() -> bool {
	if persistent == nil do return false
	bind()
	return o.Peek_Force_Restart()
}

/*
Clears the force-reload flag after a successful library swap.

Exported hot-reload entry point called by the host reloader.
*/
@(export)
app_consume_force_reload :: proc() {
	if persistent == nil do return
	bind()
	o.Consume_Force_Reload()
}

/*
Clears the force-restart flag after a successful library swap.

Exported hot-reload entry point called by the host reloader.
*/
@(export)
app_consume_force_restart :: proc() {
	if persistent == nil do return
	bind()
	o.Consume_Force_Restart()
}

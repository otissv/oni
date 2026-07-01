package oni

import sdl "vendor:sdl3"

/*
Per-widget cache entry keyed by UI_Id for shaped text and frame tracking.
*/
UI_Widget_Entry :: struct {
	shaped:     Shaped_Text,
	last_frame: u64,
	mounting:   Mount,
	unmounting: Mount,
}

/*
Per-frame UI bookkeeping: pass, scope/style stacks, widgets, and layout.
*/
UI_State :: struct {
	frame:               u64,
	pass:                UI_Pass,
	scope_stack:         [dynamic]UI_Id,
	style_stack:         [dynamic]Style_Context,
	widgets:             map[UI_Id]UI_Widget_Entry,
	layout:              Layout_State,
	layout_ids_prev:     map[UI_Id]bool,
	layout_ids_snapshot: map[UI_Id]bool,
}

/*
Top-level engine state: window, GPU, assets, input, view, and UI subsystems.
*/
State :: struct {
	window:              ^sdl.Window,
	gpu:                 ^sdl.GPUDevice,
	gpu_state:           GPU_State,
	assets:              Asset_Cache,
	textures:            Texture_State,
	fonts:               Font_State,
	view:                View,
	running:             bool,
	input:               Input_State,
	dpi:                 Dpi_Info,
	perf_frequency:      u64,
	last_counter:        u64,
	fullscreen:          bool,
	can_render:          bool,
	ui:                  UI_State,
	gamepad:             ^sdl.Gamepad,
	gamepad_instance_id: sdl.JoystickID,
	force_reload:        bool,
	force_restart:       bool,
	reload_keys_prev:    struct {
		f5, f6: bool,
	},
}

state: ^State
theme: ^Theme

/*
Re-binds package-level state and theme globals to the given pointers.

Call after any operation that may change the persistent pointer, such as
allocation, hot reload, or realloc.
*/
bind :: proc(s: ^State, t: ^Theme) {
	state = s
	theme = t
}

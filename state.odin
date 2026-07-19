package oni

import sdl "vendor:sdl3"

/*
Per-widget cache entry keyed by UI_Id for lifecycle and frame tracking.
*/
UI_Widget_Entry :: struct {
	last_frame: u64,
	mounting:   Mount,
	unmounting: Mount,
}

/*
Cross-frame scrollport metrics used for AUTO scrollbar visibility and APIs.
*/
Scrollport_Metrics :: struct {
	content_size:  Vec2,
	viewport_size: Vec2,
	scroll:        Vec2,
	max_scroll:    Vec2,
}

/*
Scrollbar thumb-drag latch kept across frames while the pointer is held.
*/
Scroll_Bar_Drag :: struct {
	active:     bool,
	grab_offset: f32,
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
	label_crc:           map[string]u32,
	scrollports:         map[UI_Id]Scrollport_Metrics,
	scroll_bar_drags:    map[UI_Id]Scroll_Bar_Drag,
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
	shortcuts:           Shortcut_State,
	dpi:                 Dpi_Info,
	perf_frequency:      u64,
	last_counter:        u64,
	fullscreen:          bool,
	can_render:          bool,
	ui:                  UI_State,
	widget:              Widget_Context,
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
Keeps the package-level widget context pointer aligned with engine state.

Call after assigning `state` directly (tests) or when entering UI entry points.
*/
widget_ctx_sync :: proc() {
	w_ctx = state != nil ? &state.widget : nil
}

/*
Re-binds package-level state, theme, and widget-context globals to the given pointers.

Call after any operation that may change the persistent pointer, such as
allocation, hot reload, or realloc.
*/
bind :: proc(s: ^State, t: ^Theme) {
	state = s
	theme = t
	theme_widget_style_invalidate()
	widget_ctx_sync()
}

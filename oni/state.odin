package oni

import sdl "vendor:sdl3"

UI_Widget_Entry :: struct {
	shaped:     Shaped_Text,
	last_frame: u64,
}

UI_State :: struct {
	frame:       u64,
	scope_stack: [dynamic]UI_Id,
	widgets:     map[UI_Id]UI_Widget_Entry,
}

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
}

state: ^State
theme_ref: ^Theme

bind :: proc(s: ^State, theme: ^Theme) {
	state = s
	theme_ref = theme
}

theme :: proc() -> ^Theme {
	return theme_ref
}

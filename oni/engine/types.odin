package engine

Vec2 :: [2]f32

Rect :: struct {
	x, y, w, h: f32,
}

Color :: struct {
	r, g, b, a: u8,
}

Dpi_Info :: struct {
	scale:                  f32,
	logical_w, logical_h:   i32,
	drawable_w, drawable_h: i32,
}

Asset_Id :: distinct i32

UI_Id :: distinct u64

Texture_Handle :: struct {
	id:   Asset_Id,
	w, h: f32,
}

Atlas_Region :: struct {
	texture_id: Asset_Id,
	x, y, w, h: f32,
}

Font_Handle :: struct {
	id:      Asset_Id,
	size_px: f32,
}

Theme :: struct {
	bg, surface, border, text, text_muted: Color,
	accent, accent_hover, accent_pressed: Color,
	danger, success: Color,
	spacing_xs, spacing_sm, spacing_md, spacing_lg: f32,
	radius_sm, radius_md: f32,
	font_body, font_heading: Font_Handle,
}

INVALID_ASSET_ID :: Asset_Id(-1)
TEXTURE_WHITE_ID :: Asset_Id(0)

KEY_COUNT :: 512

GAMEPAD_BUTTON_COUNT :: 32

Input_Modifiers :: struct {
	shift, ctrl, alt, super: bool,
}

Gamepad_Input :: struct {
	connected:     bool,
	dpad_left:     bool,
	dpad_right:    bool,
	dpad_up:       bool,
	dpad_down:     bool,
	left_stick_x:  f32,
	left_stick_y:  f32,
	right_stick_x: f32,
	right_stick_y: f32,
	left_trigger:  f32,
	right_trigger: f32,
	buttons_down:  [GAMEPAD_BUTTON_COUNT]bool,
}

Input_State :: struct {
	mouse_x, mouse_y:                      f32,
	mouse_left, mouse_right, mouse_middle: bool,
	mouse_wheel_x, mouse_wheel_y:          f32,
	keys_down:                             [KEY_COUNT]bool,
	text_input:                            [dynamic]u8,
	modifiers:                             Input_Modifiers,
	gamepad:                               Gamepad_Input,
}

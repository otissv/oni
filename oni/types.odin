package oni

Vec2 :: [2]f32

INVALID_ASSET_ID :: Asset_Id(-1)
TEXTURE_WHITE_ID :: Asset_Id(0)

// Padding
Pd_int :: f32

GAMEPAD_BUTTON_COUNT :: 32

PADDING_SM :: f32(8)
PADDING_MD :: f32(12)
PADDING_LG :: f32(16)
PADDING_XL :: f32(20)

RADIUS_SM :: f32(4)
RADIUS_MD :: f32(8)
RADIUS_LG :: f32(12)
RADIUS_XL :: f32(16)

BORDER_SM :: f32(1)
BORDER_MD :: f32(2)
BORDER_LG :: f32(3)
BORDER_XL :: f32(4)

WIDTH_SM :: f32(120)
WIDTH_MD :: f32(160)
WIDTH_LG :: f32(200)
WIDTH_XL :: f32(240)

HEIGHT_SM :: f32(36)
HEIGHT_MD :: f32(48)
HEIGHT_LG :: f32(56)
HEIGHT_XL :: f32(64)

KEY_COUNT :: 512


Widget_Event :: struct($S: typeid) {
	state:        S,
	mouse_button: u8,
	key:          Scancode,
}

Widget_State :: struct {
	is_hovered:        bool,
	is_Pressed:        bool,
	is_focused:        bool,
	is_left_clicked:   bool,
	is_right_clicked:  bool,
	is_middle_clicked: bool,
	is_left_released:  bool,
	is_right_released: bool,
	is_disabled:       bool,
}

Widget_Merged_State :: struct($S: typeid, $C: typeid) {
	using state: S,
	config:      C,
}

// Padding
Pd_pos :: struct {
	x, y: f32,
}

Pd_struct :: struct {
	t, b, l, r:     f32,
	tl, tr, bl, br: f32,
	x, y:           f32,
	sm, md, lg, xl: bool,
}

Padding :: union {
	struct{},
	f32,
	Pd_pos,
	Pd_struct,
	proc(state: Widget_State, event: Widget_Event(Widget_State)) -> Padding,
}

// Radius
Radius_struct :: struct {
	t, b, l, r:     f32,
	tl, tr, bl, br: f32,
	x, y:           f32,
	sm, md, lg, xl: bool,
}

Radius :: union {
	struct{},
	f32,
	Radius_struct,
	proc(state: Widget_State, event: Widget_Event(Widget_State)) -> Radius,
}

// Border
Bd_struct :: struct {
	t, b, l, r:     f32,
	sm, md, lg, xl: bool,
}

Border :: union {
	struct{},
	f32,
	Bd_struct,
	proc(state: Widget_State, event: Widget_Event(Widget_State)) -> Border,
}

Dim_struct :: struct {
	min, max:       f32,
	percent:        f32,
	sm, md, lg, xl: bool,
	grow:           bool,
}

Width :: union {
	struct{},
	f32,
	Dim_struct,
	proc(state: Widget_State, event: Widget_Event(Widget_State)) -> Width,
}

Height :: union {
	struct{},
	f32,
	Dim_struct,
	proc(state: Widget_State, event: Widget_Event(Widget_State)) -> Height,
}

ChildGap :: union {
	struct{},
	u16,
	proc(state: Widget_State, event: Widget_Event(Widget_State)) -> ChildGap,
}

Text_Warp :: enum {
	None,
	Newlines,
	Balance,
}

Text_Align :: enum {
	Left,
	Center,
	Right,
}

@(private)
Align_X :: enum {
	Unset,
	Left,
	Right,
	Center,
}

@(private)
Align_Y :: enum {
	Unset,
	Top,
	Bottom,
	Center,
}

Align_Pos :: struct {
	x: Align_X,
	y: Align_Y,
}

Align :: union {
	struct{},
	Align_Pos,
	proc(state: Widget_State, event: Widget_Event(Widget_State)) -> Align,
}

Direction_Layout :: enum {
	Stacked,
	Horizontal,
}

Direction :: union {
	struct{},
	Direction_Layout,
	proc(state: Widget_State, event: Widget_Event(Widget_State)) -> Direction,
}


AspectRatio :: union {
	f32,
	proc(state: Widget_State, event: Widget_Event(Widget_State)) -> AspectRatio,
}

Image :: union {
	rawptr,
	proc(state: Widget_State, event: Widget_Event(Widget_State)) -> Image,
}


// Clip :: union {
// 	proc(state: Widget_State, event: Widget_Event(Widget_State)) -> Clip,
// }

// Transition :: union {
// 	struct{},
// 	proc(state: Widget_State, event: Widget_Event(Widget_State)) -> Transition,
// }


Rect :: struct {
	x, y, w, h: f32,
}

RGBA :: struct {
	r, g, b, a: u8,
}


Draw_Space :: enum {
	Artboard,
	Screen,
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
	palette:      Palette,
	alignChild:   Align,
	bd:           Border,
	bdColor:      Colors,
	bg:           Colors,
	childGap:     ChildGap,
	color:        Colors,
	direction:    Direction,
	font_body:    Font_Handle,
	font_heading: Font_Handle,
	height:       Height,
	pd:           Padding,
	rd:           Radius,
	width:        Width,
}

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

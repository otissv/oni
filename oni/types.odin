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

Widget_ID :: string

Widget_Mouse_Button_State :: struct {
	down:     bool,
	pressed:  bool,
	released: bool,
}

Widget_Mouse_Key_State :: struct {
	down:     bool,
	pressed:  bool,
	released: bool,
}


Widget_Context :: struct {
	auto_focused_id:      Widget_ID,
	focused_id:           Widget_ID,
	auto_element_index:   u32,
	static_ids:           map[string]Widget_ID,
	mouse_x:              f32,
	mouse_y:              f32,
	mouse_moved:          bool,
	left_mouse:           Widget_Mouse_Button_State,
	right_mouse:          Widget_Mouse_Button_State,
	middle_mouse:         Widget_Mouse_Button_State,
	keys:                 [KEY_COUNT]Widget_Mouse_Key_State,
	element_was_hovered:  map[string]bool,
	element_pointer_down: map[string]bool,
}

Widget_Merged_State :: struct($S: typeid, $C: typeid) {
	using state: S,
	config:      C,
}

w_ctx: Widget_Context

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

Widget_Kind :: enum {
	RECT,
	TEXT,
	BUTTON,
}

Cfg_Tri :: enum {
	Unset,
	Inherit,
	Value,
}

Cfg :: struct($T: typeid) {
	mode:  Cfg_Tri,
	value: T,
}

Length_Kind :: enum {
	Auto,
	Fixed,
	Percent,
	Inherit,
}

Length :: struct {
	kind:  Length_Kind,
	value: f32,
}

Widget_Config :: struct {
	id:             string,
	kind:           Widget_Kind,
	align:          Cfg(Text_Align),
	aspect_ratio:   Cfg(Aspect_Ratio),
	auto_focus:     Cfg(bool),
	background:     Cfg(Colors),
	border:         Cfg(Border),
	border_color:   Cfg(Colors),
	color:          Cfg(Colors),
	direction:      Cfg(Widget_Direction),
	disabled:       Cfg(bool),
	flex:           Cfg(f32),
	font:           Cfg(Font_Handle),
	font_size:      Cfg(f32),
	gap:            Cfg(Gap),
	height:         Height,
	justify:        Cfg(Justify),
	letter_spacing: Cfg(f32),
	line_height:    Cfg(f32),
	max_h:          Cfg(f32),
	max_w:          Cfg(f32),
	min_h:          Cfg(f32),
	min_w:          Cfg(f32),
	padding:        Cfg(Padding),
	radius:         Cfg(Radius),
	space:          Cfg(Draw_Space),
	text_direction: Cfg(Text_Direction),
	width:          Width,
	wrap:           Cfg(Text_Warp),
	x:              Cfg(f32),
	y:              Cfg(f32),
	overflow:       Cfg(Overflow),
	overflow_y:     Cfg(Overflow),
	overflow_x:     Cfg(Overflow),
	visibility:     Cfg(Visibility),
	z_index:        Cfg(f32),
	position:       Cfg(Position),
	self:           Cfg(Justify),
}

Widget_Text_Flag :: enum {
	Uncached,
}

Widget_Text_Flags :: bit_set[Widget_Text_Flag;i32]

Resolved_Widget_Style :: struct {
	align:          Text_Align,
	aspect_ratio:   Aspect_Ratio,
	auto_focus:     bool,
	background:     Colors,
	border:         Border,
	border_color:   Colors,
	color:          Colors,
	direction:      Direction_Layout,
	disabled:       bool,
	flex:           f32,
	font:           Font_Handle,
	font_size:      f32,
	gap:            u16,
	height:         Length,
	justify:        Justify_Pos,
	letter_spacing: f32,
	line_height:    f32,
	max_h:          f32,
	max_w:          f32,
	min_h:          f32,
	min_w:          f32,
	padding:        Padding,
	radius:         Radius,
	space:          Draw_Space,
	text_direction: Text_Direction,
	width:          Length,
	wrap:           Text_Warp,
	x:              f32,
	y:              f32,
	overflow:       Overflow,
	overflow_y:     Overflow,
	overflow_x:     Overflow,
	visibility:     Visibility,
	z_index:        f32,
	position:       Position,
	self:           Justify_Pos,
}

Resolved_Widget_Config :: struct {
	id:          string,
	kind:        Widget_Kind,
	using style: Resolved_Widget_Style,
}

Style_Context :: struct {
	using style: Resolved_Widget_Style,
	content_w:   f32,
	content_h:   f32,
}

Whitespace :: union {
	enum {
		Auto,
		Wrap,
	},
}

Position :: union {
	enum {
		Relative,
		Absolute,
		Fixed,
		Sticky,
	},
	proc(state: Widget_State, event: Widget_Event(Widget_State)) -> Position,
}

Visibility :: union {
	enum {
		Visible,
		Hidden,
	},
	proc(state: Widget_State, event: Widget_Event(Widget_State)) -> Visibility,
}

Overflow :: union {
	enum {
		Auto,
		Scroll,
		Hidden,
	},
	proc(state: Widget_State, event: Widget_Event(Widget_State)) -> Overflow,
}

// Padding
Pd :: struct {
	t, b, l, r: f32,
}

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
	Pd,
	Pd_pos,
	Pd_struct,
	proc(state: Widget_State, event: Widget_Event(Widget_State)) -> Padding,
}

// Radius

Radius_corners :: struct {
	tl: f32,
	tr: f32,
	bl: f32,
	br: f32,
}

Radius_struct :: struct {
	tl, tr, bl, br: f32,
	t, b, l, r:     f32,
	x, y:           f32,
	sm, md, lg, xl: bool,
}

Radius :: union {
	struct{},
	f32,
	Radius_struct,
	Radius_corners,
	proc(state: Widget_State, event: Widget_Event(Widget_State)) -> Radius,
}

Bd :: struct {
	t, b, l, r: f32,
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
	Bd,
	proc(state: Widget_State, event: Widget_Event(Widget_State)) -> Border,
}

Dim_struct :: struct {
	min, max:       f32,
	percent:        f32,
	sm, md, lg, xl: bool,
	grow:           bool,
}

Width_Mode :: enum {
	Inherit,
	Auto,
	Fit_Content,
	Min_Content,
	Max_Content,
}

Width :: union {
	struct{},
	Width_Mode,
	f32,
	Dim_struct,
	proc(state: Widget_State, event: Widget_Event(Widget_State)) -> Width,
}

Height_Mode :: enum {
	Inherit,
	Auto,
	Fit_Content,
	Min_Content,
	Max_Content,
}

Height :: union {
	struct{},
	Height_Mode,
	f32,
	Dim_struct,
	proc(state: Widget_State, event: Widget_Event(Widget_State)) -> Height,
}

Gap :: union {
	struct{},
	u16,
	proc(state: Widget_State, event: Widget_Event(Widget_State)) -> Gap,
}

Text_Warp :: union {
	struct{},
	enum {
		None,
		Newlines,
		Balance,
	},
	proc(state: Widget_State, event: Widget_Event(Widget_State)) -> Text_Warp,
}

Text_Align :: union {
	struct{},
	enum {
		Left,
		Center,
		Right,
	},
	proc(state: Widget_State, event: Widget_Event(Widget_State)) -> Text_Align,
}

Justify_Align :: enum {
	Start,
	Center,
	End,
	Stretch,
	Space_between,
	Space_around,
	Space_evenly,
}

Justify_X :: union {
	struct{},
	Justify_Align,
	proc(state: Widget_State, event: Widget_Event(Widget_State)) -> Justify_X,
}

Justify_Y :: union {
	struct{},
	Justify_Align,
	proc(state: Widget_State, event: Widget_Event(Widget_State)) -> Justify_Y,
}

Justify_Pos :: struct {
	x: Justify_X,
	y: Justify_Y,
}

Justify :: union {
	struct{},
	Justify_Pos,
	proc(state: Widget_State, event: Widget_Event(Widget_State)) -> Justify,
}


Direction_Layout :: enum {
	Horizontal,
	Vertical,
	Horizontal_Wrap,
	Vertical_Wrap,
}

Widget_Direction :: union {
	struct{},
	Direction_Layout,
	proc(state: Widget_State, event: Widget_Event(Widget_State)) -> Widget_Direction,
}


Aspect_Ratio :: union {
	struct{},
	enum {
		Auto,
		None,
	},
	f32,
	proc(state: Widget_State, event: Widget_Event(Widget_State)) -> Aspect_Ratio,
}

Image :: union {
	struct{},
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


SizingType :: enum {
	Fit,
	Grow,
	Percent,
	Fixed,
}

SizingConstraintsMinMax :: struct {
	min: f32,
	max: f32,
}

SizingConstraints :: struct #raw_union {
	sizeMinMax:  SizingConstraintsMinMax,
	sizePercent: f32,
}

SizingAxis :: struct {
	constraints: SizingConstraints,
	type:        SizingType,
}

SizingFit :: proc(sizeMinMax: SizingConstraintsMinMax = {}) -> SizingAxis {
	return SizingAxis{type = SizingType.Fit, constraints = {sizeMinMax = sizeMinMax}}
}

SizingGrow :: proc(sizeMinMax: SizingConstraintsMinMax = {}) -> SizingAxis {
	return SizingAxis{type = SizingType.Grow, constraints = {sizeMinMax = sizeMinMax}}
}

SizingFixed :: proc(size: f32) -> SizingAxis {
	return SizingAxis{type = SizingType.Fixed, constraints = {sizeMinMax = {size, size}}}
}

SizingPercent :: proc(sizePercent: f32) -> SizingAxis {
	return SizingAxis{type = SizingType.Percent, constraints = {sizePercent = sizePercent}}
}

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
	justify:      Justify,
	border:       Border,
	border_color: Colors,
	background:   Colors,
	gap:          Gap,
	color:        Colors,
	direction:    Widget_Direction,
	font_body:    Font_Handle,
	font_heading: Font_Handle,
	height:       Height,
	padding:      Padding,
	radius:       Radius,
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

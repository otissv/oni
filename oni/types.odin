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

/*
Per-frame edge-detected state for one mouse button in widget input handling.
*/
Widget_Mouse_Button_State :: struct {
	down:     bool,
	pressed:  bool,
	released: bool,
}

/*
Per-frame edge-detected state for one keyboard key in widget input handling.
*/
Widget_Mouse_Key_State :: struct {
	down:     bool,
	pressed:  bool,
	released: bool,
}


/*
Global per-frame widget input context: focus, mouse, keys, and hover tracking.
*/
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

/*
Merges a widget-specific state struct with its resolved config type.
*/
Widget_Merged_State :: struct($S: typeid, $C: typeid) {
	using state: S,
	config:      C,
}

w_ctx: Widget_Context

/*
Snapshot of widget state plus optional input metadata for event callbacks.
*/
Widget_Event :: struct($S: typeid) {
	state:        S,
	mouse_button: u8,
	key:          Scancode,
}

/*
Per-frame interaction flags for a widget: hover, press, focus, and click edges.
*/
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
	UNSET,
	Inherit,
	Value,
}

/*
Tri-state config field: unset, inherit from parent, or explicit value.
*/
Cfg :: struct($T: typeid) {
	mode:  Cfg_Tri,
	value: T,
}

Length_Kind :: enum {
	AUTO,
	FIXED,
	PERCENT,
	INHERIT,
}

/*
Resolved axis length as fixed pixels, percent of parent, inherit, or auto.
*/
Length :: struct {
	kind:  Length_Kind,
	value: f32,
}

/*
Author-time widget style overrides using tri-state Cfg fields and dimension unions.
*/
Widget_Config :: struct {
	id:             string,
	kind:           Widget_Kind,
	title:          string,
	align:          Cfg(Text_Align),
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
	overflow_y:     Cfg(Overflow),
	overflow_x:     Cfg(Overflow),
	visibility:     Cfg(Visibility),
	z_index:        Cfg(f32),
	position:       Cfg(Position),
	self:           Cfg(Justify),
	texture_fit:    Cfg(Style_Image_Fit),
	texture_pos:    Cfg(Style_Image_Pos),
}

Widget_Text_Flag :: enum {
	UNCACHED,
}

Widget_Text_Flags :: bit_set[Widget_Text_Flag;i32]

/*
Fully resolved widget style after merging theme, parent, and prop overrides.
*/
Resolved_Widget_Style :: struct {
	align:          Text_Align,
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
	texture_fit:    Style_Image_Fit,
	texture_pos:    Style_Image_Pos,
}

/*
Resolved widget identity and style ready for layout and drawing.
*/
Resolved_Widget_Config :: struct {
	id:          string,
	kind:        Widget_Kind,
	using style: Resolved_Widget_Style,
}

/*
Style stack entry with resolved style and current content box dimensions.
*/
Style_Context :: struct {
	using style: Resolved_Widget_Style,
	content_w:   f32,
	content_h:   f32,
}

Whitespace :: union {
	enum {
		AUTO,
		WRAP,
	},
}

Position :: union {
	enum {
		RELATIVE,
		ABSOLUTE,
		FIXED,
		STICKY,
	},
	proc(state: Widget_State, event: Widget_Event(Widget_State)) -> Position,
}

Visibility :: union {
	enum {
		VISIBLE,
		HIDDEN,
	},
	proc(state: Widget_State, event: Widget_Event(Widget_State)) -> Visibility,
}

Overflow :: union {
	enum {
		AUTO,
		SCROLL,
		HIDDEN,
	},
	proc(state: Widget_State, event: Widget_Event(Widget_State)) -> Overflow,
}

/*
Per-side padding values: top, bottom, left, and right.
*/
Pd :: struct {
	t, b, l, r: f32,
}

/*
Symmetric horizontal/vertical padding shorthand.
*/
Pd_pos :: struct {
	x, y: f32,
}

/*
Full padding specification with per-side, corner, axis, and preset flags.
*/
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

/*
Per-corner border radius values.
*/
Radius_corners :: struct {
	tl: f32,
	tr: f32,
	bl: f32,
	br: f32,
}

/*
Full radius specification with corners, sides, axis, and preset flags.
*/
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

/*
Per-side border width values: top, bottom, left, and right.
*/
Bd :: struct {
	t, b, l, r: f32,
}

/*
Full border specification with per-side widths and preset flags.
*/
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

/*
Width/height dimension with min/max, percent, grow, and preset flags.
*/
Dim_struct :: struct {
	min, max:       f32,
	percent:        f32,
	sm, md, lg, xl: bool,
	grow:           bool,
}

Width_Mode :: enum {
	INHERIT,
	AUTO,
}

Width :: union {
	struct{},
	Width_Mode,
	f32,
	Dim_struct,
	proc(state: Widget_State, event: Widget_Event(Widget_State)) -> Width,
}

Height_Mode :: enum {
	INHERIT,
	AUTO,
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
		NONE,
		NEWLINES,
		BALANCE,
	},
	proc(state: Widget_State, event: Widget_Event(Widget_State)) -> Text_Warp,
}

Text_Align :: union {
	struct{},
	enum {
		LEFT,
		CENTER,
		RIGHT,
	},
	proc(state: Widget_State, event: Widget_Event(Widget_State)) -> Text_Align,
}

Justify_Align :: enum {
	START,
	CENTER,
	END,
	STRETCH,
	SPACE_BETWEEN,
	SPACE_AROUND,
	SPACE_EVENLY,
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

/*
Main- and cross-axis flex alignment as independent Justify_X/Y unions.
*/
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
	HORIZONTAL,
	VERTICAL,
	HORIZONTAL_WRAP,
	VERTICAL_WRAP,
	HORIZONTAL_REVERSE,
	VERTICAL_REVERSE,
	HORIZONTAL_WRAP_REVERSE,
	VERTICAL_WRAP_REVERSE,
}

Widget_Direction :: union {
	struct{},
	Direction_Layout,
	proc(state: Widget_State, event: Widget_Event(Widget_State)) -> Widget_Direction,
}

Image_Fit :: enum {
	FILL,
	CONTAIN,
	COVER,
	SCALE_DOWN,
	NONE,
}

Style_Image_Fit :: union {
	struct{},
	Image_Fit,
	proc(state: Widget_State, event: Widget_Event(Widget_State)) -> Image_Fit,
}

/*
Image inset positioning using top/bottom/left/right offsets.
*/
Image_Pos :: struct {
	t, b, l, r: f32,
}

/*
Image anchor position as normalized x/y percentages in 0-1.
*/
Image_Pos_X_Y :: struct {
	x, y: f32,
}

/*
Fully resolved texture position with anchor and pixel offsets.
*/
Resolved_Image_Pos :: struct {
	x, y:               f32,
	offset_x, offset_y: f32,
}

Style_Image_Pos :: union {
	struct{},
	Image_Pos,
	Image_Pos_X_Y,
	Resolved_Image_Pos,
	proc(state: Widget_State, event: Widget_Event(Widget_State)) -> Image_Pos,
}

SizingType :: enum {
	FIT,
	GROW,
	PERCENT,
	FIXED,
}

/*
Optional min and max size bounds for a sizing axis.
*/
SizingConstraintsMinMax :: struct {
	min: f32,
	max: f32,
}

/*
Sizing constraint payload: either min/max bounds or a parent percentage.
*/
SizingConstraints :: struct #raw_union {
	sizeMinMax:  SizingConstraintsMinMax,
	sizePercent: f32,
}

/*
One axis sizing rule with type (fit, grow, percent, fixed) and constraints.
*/
SizingAxis :: struct {
	constraints: SizingConstraints,
	type:        SizingType,
}

/*
Builds a SizingAxis that sizes to content within optional min/max bounds.
*/
SizingFit :: proc(sizeMinMax: SizingConstraintsMinMax = {}) -> SizingAxis {
	return SizingAxis{type = SizingType.FIT, constraints = {sizeMinMax = sizeMinMax}}
}

/*
Builds a SizingAxis that expands to fill available space with optional min/max.
*/
SizingGrow :: proc(sizeMinMax: SizingConstraintsMinMax = {}) -> SizingAxis {
	return SizingAxis{type = SizingType.GROW, constraints = {sizeMinMax = sizeMinMax}}
}

/*
Builds a SizingAxis with an exact fixed pixel size.
*/
SizingFixed :: proc(size: f32) -> SizingAxis {
	return SizingAxis{type = SizingType.FIXED, constraints = {sizeMinMax = {size, size}}}
}

/*
Builds a SizingAxis sized as a fraction of the parent axis.
*/
SizingPercent :: proc(sizePercent: f32) -> SizingAxis {
	return SizingAxis{type = SizingType.PERCENT, constraints = {sizePercent = sizePercent}}
}

/*
Axis-aligned rectangle in logical coordinates.
*/
Rect :: struct {
	x, y, w, h: f32,
}

/*
8-bit per-channel sRGB color with premultiplied-friendly alpha.
*/
RGBA :: struct {
	r, g, b, a: u8,
}


Draw_Space :: enum {
	ARTBOARD,
	SCREEN,
}

/*
Window DPI scale and logical vs drawable pixel dimensions.
*/
Dpi_Info :: struct {
	scale:                  f32,
	logical_w, logical_h:   i32,
	drawable_w, drawable_h: i32,
}

Asset_Id :: distinct i32

UI_Id :: distinct u64

/*
Reference to a loaded texture asset with pixel dimensions.
*/
Texture_Handle :: struct {
	id:   Asset_Id,
	w, h: f32,
}

/*
Sub-rectangle within an atlas or standalone texture, in pixel coordinates.
*/
Atlas_Region :: struct {
	texture_id: Asset_Id,
	x, y, w, h: f32,
}

/*
Reference to a loaded font face at a specific raster size in pixels.
*/
Font_Handle :: struct {
	id:      Asset_Id,
	size_px: f32,
}

/*
Global theme defaults for palette, typography, spacing, and widget chrome.
*/
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

/*
Keyboard modifier key state: shift, ctrl, alt, and super.
*/
Input_Modifiers :: struct {
	shift, ctrl, alt, super: bool,
}

/*
Normalized gamepad axes, d-pad, triggers, and per-button down state.
*/
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

/*
Per-frame input snapshot: mouse, keyboard, text input, modifiers, and gamepad.
*/
Input_State :: struct {
	mouse_x, mouse_y:                      f32,
	mouse_left, mouse_right, mouse_middle: bool,
	mouse_wheel_x, mouse_wheel_y:          f32,
	keys_down:                             [KEY_COUNT]bool,
	text_input:                            [dynamic]u8,
	modifiers:                             Input_Modifiers,
	gamepad:                               Gamepad_Input,
}

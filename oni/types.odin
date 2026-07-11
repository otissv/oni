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
Per-frame edge-detected frame_state for one mouse button in widget input handling.
*/
Widget_Mouse_Button_State :: struct {
	down:     bool,
	pressed:  bool,
	released: bool,
}

/*
Per-frame edge-detected frame_state for one keyboard key in widget input handling.
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
	auto_focused_id:       Widget_ID,
	focused_id:            Widget_ID,
	tab_order:             [dynamic]Widget_ID,
	tab_focus_previous_id: Widget_ID,
	tab_focus_changed:     bool,
	auto_element_index:    u32,
	static_ids:            map[string]Widget_ID,
	mouse_x:               f32,
	mouse_y:               f32,
	mouse_moved:           bool,
	left_mouse:            Widget_Mouse_Button_State,
	right_mouse:           Widget_Mouse_Button_State,
	middle_mouse:          Widget_Mouse_Button_State,
	keys:                  [KEY_COUNT]Widget_Mouse_Key_State,
	element_was_hovered:   map[string]bool,
	element_pointer_down:  map[string]bool,
}

/*
Merges a widget-specific frame_state struct with its resolved config type.
*/
Widget_Merged_State :: struct($S: typeid, $C: typeid) {
	using frame_state: S,
	config:            C,
}

w_ctx: Widget_Context

/*
Snapshot of widget frame_state plus optional input metadata for event callbacks.
*/
Widget_Event :: struct($S: typeid) {
	frame_state:  S,
	mouse_button: u8,
	key:          Scancode,
}


Mount :: enum {
	UNSET,
	RUNNING,
	COMPLETED,
}

/*
Per-frame interaction flags for a widget: hover, press, focus, and click edges.
*/
Widget_Frame_State :: struct {
	mounting:          Mount,
	unmounting:        Mount,
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
	TABLE,
	TABLE_CAPTION,
	TABLE_HEAD,
	TABLE_HEADING,
	TABLE_BODY,
	TABLE_ROW,
	TABLE_CELL,
	TABLE_FOOT,
}

Cfg_Tri :: enum {
	UNSET,
	Value,
}

/*
Tri-frame_state config field: unset or explicit value.

Inherit is expressed inside each value union as `.INHERIT`, not on Cfg.
*/
Cfg :: struct($T: typeid) {
	mode:  Cfg_Tri,
	value: T,
}

/*
Shared inherit tag used as a variant on Widget_Config value unions.
*/
Inherit :: enum {
	INHERIT,
}

/*
Numeric style field that may be an explicit f32 or `.INHERIT` from the parent.
*/
F32_I :: union {
	Inherit,
	f32,
}

/*
Resolves an F32_I field: `.INHERIT` takes parent, f32 is kept, unset is 0.
*/
f32_i_resolve :: proc(v: F32_I, parent: f32) -> f32 {
	switch x in v {
	case Inherit:
		return parent
	case f32:
		return x
	}
	return 0
}

/*
Returns the concrete f32 from an F32_I, or 0 when unset/inherit.
*/
f32_i_px :: proc(v: F32_I) -> f32 {
	#partial switch x in v {
	case f32:
		return x
	}
	return 0
}

/*
Returns whether an F32_I field was authored (inherit or explicit value).
*/
f32_i_is_set :: proc(v: F32_I) -> bool {
	return v != nil
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
Author-time widget style overrides using tri-frame_state Cfg fields and dimension unions.
*/
Widget_Config :: struct {
	id:                    string,
	kind:                  Widget_Kind,
	title:                 string,
	align:                 Cfg(Text_Align),
	auto_focus:            Cfg(Style_Bool),
	background:            Cfg(Colors),
	border:                Cfg(Border),
	border_color:          Cfg(Colors),
	color:                 Cfg(Colors),
	direction:             Cfg(Widget_Direction),
	disabled:              Cfg(Style_Bool),
	flex:                  Cfg(Style_F32),
	font:                  Cfg(Style_Font),
	font_size:             Cfg(Style_F32),
	font_style:            Cfg(Font_Style),
	font_weight:           Cfg(Font_Weight),
	gap_x:                 Cfg(Gap_X),
	gap_y:                 Cfg(Gap_Y),
	height:                Height,
	justify:               Cfg(Justify),
	letter_spacing:        Cfg(Style_F32),
	line_height:           Cfg(Style_F32),
	max_h:                 Cfg(Style_F32),
	max_w:                 Cfg(Style_F32),
	min_h:                 Cfg(Style_F32),
	min_w:                 Cfg(Style_F32),
	overflow_x:            Cfg(Overflow),
	overflow_y:            Cfg(Overflow),
	padding:               Cfg(Padding),
	position:              Cfg(Position),
	radius:                Cfg(Radius),
	self:                  Cfg(Justify),
	space:                 Cfg(Style_Space),
	tabbable:              Cfg(Style_Bool),
	text_decoration:       Cfg(Text_Decoration),
	text_decoration_color: Cfg(Colors),
	text_decoration_style: Cfg(Text_Decoration_Style),
	text_direction:        Cfg(Text_Direction),
	texture_fit:           Cfg(Style_Texture_Fit),
	texture_pos:           Cfg(Style_Texture_Pos),
	visibility:            Cfg(Visibility),
	width:                 Width,
	wrap:                  Cfg(Text_Wrap),
	x:                     Cfg(Style_F32),
	y:                     Cfg(Style_F32),
	z_index:               Cfg(Style_F32),
}

Resolved_Widget_Style :: struct {
	align:                 Text_Align,
	auto_focus:            bool,
	background:            Colors,
	border:                Border,
	border_color:          Colors,
	color:                 Colors,
	direction:             Direction_Layout,
	disabled:              bool,
	flex:                  f32,
	font:                  Font_Handle,
	font_size:             f32,
	font_style:            Font_Style,
	font_weight:           Font_Weight,
	gap_x:                 u16,
	gap_y:                 u16,
	height:                Length,
	justify:               Justify_Pos,
	letter_spacing:        f32,
	line_height:           f32,
	max_h:                 f32,
	max_w:                 f32,
	min_h:                 f32,
	min_w:                 f32,
	padding:               Padding,
	radius:                Radius,
	space:                 Draw_Space,
	text_decoration:       Text_Decoration,
	text_decoration_color: Colors,
	text_decoration_style: Text_Decoration_Style,
	text_direction:        Text_Direction,
	width:                 Length,
	wrap:                  Text_Wrap,
	x:                     f32,
	y:                     f32,
	overflow:              Overflow,
	overflow_y:            Overflow,
	overflow_x:            Overflow,
	visibility:            Visibility,
	z_index:               f32,
	position:              Position,
	self:                  Justify_Pos,
	texture_fit:           Style_Texture_Fit,
	texture_pos:           Style_Texture_Pos,
	tabbable:              bool,
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

Position :: union {
	Inherit,
	enum {
		RELATIVE,
		ABSOLUTE,
		FIXED,
		STICKY,
	},
	proc(frame_state: Widget_Frame_State, event: Widget_Event(Widget_Frame_State)) -> Position,
}

Visibility :: union {
	Inherit,
	enum {
		VISIBLE,
		HIDDEN,
	},
	proc(frame_state: Widget_Frame_State, event: Widget_Event(Widget_Frame_State)) -> Visibility,
}

Overflow :: union {
	Inherit,
	enum {
		AUTO,
		SCROLL,
		HIDDEN,
	},
	proc(frame_state: Widget_Frame_State, event: Widget_Event(Widget_Frame_State)) -> Overflow,
}

/*
Per-side padding values: top, bottom, left, and right.
*/
Pd :: struct {
	t, b, l, r: F32_I,
}

/*
Symmetric horizontal/vertical padding shorthand.
*/
Pd_pos :: struct {
	x, y: F32_I,
}

/*
Full padding specification with per-side, corner, axis, and preset flags.
*/
Pd_struct :: struct {
	t, b, l, r:     F32_I,
	tl, tr, bl, br: F32_I,
	x, y:           F32_I,
	sm, md, lg, xl: bool,
}


Padding :: union {
	Inherit,
	struct{},
	f32,
	Pd,
	Pd_pos,
	Pd_struct,
	proc(frame_state: Widget_Frame_State, event: Widget_Event(Widget_Frame_State)) -> Padding,
}

/*
Resolved per-side padding in pixels for layout and draw.
*/
Pd_px :: struct {
	t, b, l, r: f32,
}

/*
Per-corner border radius values (each corner may be `.INHERIT`).
*/
Radius_corners :: struct {
	tl: F32_I,
	tr: F32_I,
	bl: F32_I,
	br: F32_I,
}

/*
Full radius specification with corners, sides, axis, and preset flags.
*/
Radius_struct :: struct {
	tl, tr, bl, br: F32_I,
	t, b, l, r:     F32_I,
	x, y:           F32_I,
	sm, md, lg, xl: bool,
}

Radius :: union {
	Inherit,
	struct{},
	f32,
	Radius_struct,
	Radius_corners,
	proc(frame_state: Widget_Frame_State, event: Widget_Event(Widget_Frame_State)) -> Radius,
}

/*
Resolved per-corner radii in pixels for layout and draw.
*/
Radius_px :: struct {
	tl, tr, bl, br: f32,
}

/*
Per-side border width values: top, bottom, left, and right.
*/
Bd :: struct {
	t, b, l, r: F32_I,
}

/*
Full border specification with per-side widths and preset flags.
*/
Bd_struct :: struct {
	t, b, l, r:     F32_I,
	sm, md, lg, xl: bool,
}

Border :: union {
	Inherit,
	struct{},
	f32,
	Bd_struct,
	Bd,
	proc(frame_state: Widget_Frame_State, event: Widget_Event(Widget_Frame_State)) -> Border,
}

/*
Resolved per-side border widths in pixels for layout and draw.
*/
Bd_px :: struct {
	t, b, l, r: f32,
}

/*
Source priority for collapsed table border conflict resolution.
*/
Table_Border_Source :: enum {
	TABLE,
	ROW_GROUP,
	ROW,
	CELL,
}

/*
One resolved border segment used during collapsed table layout.

Color is resolved at draw from the winning source node (`order`).
*/
Table_Border_Side :: struct {
	width:  f32,
	color:  RGBA,
	source: Table_Border_Source,
	order:  int,
}

/*
Per-side collapsed borders resolved for one table cell.
*/
Table_Cell_Borders :: struct {
	t, b, l, r: Table_Border_Side,
}

/*
Grid coordinates for a table cell inside its owning table.
*/
Table_Grid_Pos :: struct {
	row, col: int,
}

/*
Width/height dimension with min/max, percent, grow, and preset flags.
*/
Dim_struct :: struct {
	min, max:       F32_I,
	percent:        F32_I,
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
	proc(frame_state: Widget_Frame_State, event: Widget_Event(Widget_Frame_State)) -> Width,
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
	proc(frame_state: Widget_Frame_State, event: Widget_Event(Widget_Frame_State)) -> Height,
}

Gap_X :: union {
	Inherit,
	struct{},
	u16,
	proc(frame_state: Widget_Frame_State, event: Widget_Event(Widget_Frame_State)) -> Gap_X,
}

Gap_Y :: union {
	Inherit,
	struct{},
	u16,
	proc(frame_state: Widget_Frame_State, event: Widget_Event(Widget_Frame_State)) -> Gap_Y,
}

Text_Wrap_Kind :: enum {
	NONE,
	NEWLINES,
	BALANCE,
}

Text_Wrap :: union {
	Inherit,
	Text_Wrap_Kind,
	proc(frame_state: Widget_Frame_State, event: Widget_Event(Widget_Frame_State)) -> Text_Wrap,
}

Text_Align_Kind :: enum {
	LEFT,
	CENTER,
	RIGHT,
}

Text_Align :: union {
	Inherit,
	Text_Align_Kind,
	proc(frame_state: Widget_Frame_State, event: Widget_Event(Widget_Frame_State)) -> Text_Align,
}

Text_Direction_Kind :: enum {
	LTR,
	RTL,
}

Text_Direction :: union {
	Inherit,
	Text_Direction_Kind,
	proc(
		frame_state: Widget_Frame_State,
		event: Widget_Event(Widget_Frame_State),
	) -> Text_Direction,
}

/*
Which decoration lines are drawn on text.
*/
Text_Decoration_Line :: enum {
	UNDERLINE,
	LINE_THROUGH,
	OVERLINE,
}

Text_Decoration_Lines :: bit_set[Text_Decoration_Line;u8]

Text_Decoration :: union {
	Inherit,
	Text_Decoration_Lines,
	proc(
		frame_state: Widget_Frame_State,
		event: Widget_Event(Widget_Frame_State),
	) -> Text_Decoration,
}

/*
Stroke pattern for text decorations (CSS text-decoration-style).
*/
Text_Decoration_Style_Kind :: enum {
	SOLID,
	DOUBLE,
	DOTTED,
	DASHED,
	WAVY,
}

Text_Decoration_Style :: union {
	Inherit,
	Text_Decoration_Style_Kind,
	proc(
		frame_state: Widget_Frame_State,
		event: Widget_Event(Widget_Frame_State),
	) -> Text_Decoration_Style,
}

Justify_Align :: enum {
	START,
	CENTER,
	END,
	STRETCH,
	SPACE_BETWEEN,
	SPACE_AROUND,
	SPACE_EVENLY,
	MAX_CONTENT,
	MIN_CONTENT,
	TABLE_CELL,
}

Justify_X :: union {
	Inherit,
	struct{},
	Justify_Align,
	proc(frame_state: Widget_Frame_State, event: Widget_Event(Widget_Frame_State)) -> Justify_X,
}

Justify_Y :: union {
	Inherit,
	struct{},
	Justify_Align,
	proc(frame_state: Widget_Frame_State, event: Widget_Event(Widget_Frame_State)) -> Justify_Y,
}

/*
Main- and cross-axis flex alignment as independent Justify_X/Y unions.
*/
Justify_Pos :: struct {
	x: Justify_X,
	y: Justify_Y,
}

Justify :: union {
	Inherit,
	struct{},
	Justify_Pos,
	Justify_Align,
	proc(frame_state: Widget_Frame_State, event: Widget_Event(Widget_Frame_State)) -> Justify,
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
	Inherit,
	struct{},
	Direction_Layout,
	proc(
		frame_state: Widget_Frame_State,
		event: Widget_Event(Widget_Frame_State),
	) -> Widget_Direction,
}

Texture_Fit :: enum {
	FILL,
	CONTAIN,
	COVER,
	SCALE_DOWN,
	NONE,
}

Style_Texture_Fit :: union {
	Inherit,
	struct{},
	Texture_Fit,
	proc(frame_state: Widget_Frame_State, event: Widget_Event(Widget_Frame_State)) -> Texture_Fit,
}


/*
Texture inset positioning using top/bottom/left/right offsets.
*/
Texture_Pos :: struct {
	t, b, l, r: F32_I,
}

/*
Texture anchor position as normalized x/y percentages in 0-1.
*/
Texture_Pos_X_Y :: struct {
	x, y: F32_I,
}

/*
Fully resolved texture position with anchor and pixel offsets.
*/
Resolved_Texture_Pos :: struct {
	x, y:               f32,
	offset_x, offset_y: f32,
}

Style_Texture_Pos :: union {
	Inherit,
	struct{},
	Texture_Pos,
	Texture_Pos_X_Y,
	Resolved_Texture_Pos,
	proc(frame_state: Widget_Frame_State, event: Widget_Event(Widget_Frame_State)) -> Texture_Pos,
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
Draw-space style value with inherit support.
*/
Style_Space :: union {
	Inherit,
	Draw_Space,
	proc(frame_state: Widget_Frame_State, event: Widget_Event(Widget_Frame_State)) -> Style_Space,
}

/*
Scalar style value (flex, font_size, offsets, etc.) with inherit support.
*/
Style_F32 :: union {
	Inherit,
	f32,
	proc(frame_state: Widget_Frame_State, event: Widget_Event(Widget_Frame_State)) -> Style_F32,
}

/*
Boolean style value with inherit support.
*/
Style_Bool :: union {
	Inherit,
	bool,
	proc(frame_state: Widget_Frame_State, event: Widget_Event(Widget_Frame_State)) -> Style_Bool,
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
Font upright vs italic style selection.
*/
Font_Styles :: enum {
	NORMAL,
	ITALIC,
}

/*
Font style: named style, inherit, or a reactive proc.
*/
Font_Style :: union {
	Inherit,
	Font_Styles,
	proc(frame_state: Widget_Frame_State, event: Widget_Event(Widget_Frame_State)) -> Font_Style,
}

/*
Named CSS font weights (100–900). Regular is Normal (400).
*/
Font_Weights :: enum {
	Thin, // 100
	Extra_Light, // 200
	Light, // 300
	Normal, // 400
	Medium, // 500
	Semi_Bold, // 600
	Bold, // 700
	Extra_Bold, // 800
	Heavy, // 900
}

/*
Font weight: named weight, numeric 100–900, inherit, or a reactive proc.
*/
Font_Weight :: union {
	Inherit,
	Font_Weights,
	f32,
	proc(frame_state: Widget_Frame_State, event: Widget_Event(Widget_Frame_State)) -> Font_Weight,
}


/*
One source file in a font family registration.
*/
Font_Face_Desc :: struct {
	path:   string,
	style:  Font_Style,
	weight: Font_Weight,
}

/*
Reference to a registered font family with a default logical size in pixels.
*/
Font_Handle :: struct {
	id:      Asset_Id,
	size_px: f32,
}

/*
Font handle style value with inherit support.
*/
Style_Font :: union {
	Inherit,
	Font_Handle,
	proc(frame_state: Widget_Frame_State, event: Widget_Event(Widget_Frame_State)) -> Style_Font,
}

/*
Reference to a resolved raster face instance (path + size + weight/style/synthesis).
*/
Font_Face_Handle :: struct {
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
	gap_x:        Gap_X,
	gap_y:        Gap_Y,
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
Keyboard modifier key frame_state: shift, ctrl, alt, and super.
*/
Input_Modifiers :: struct {
	shift, ctrl, alt, super: bool,
}

/*
Normalized gamepad axes, d-pad, triggers, and per-button down frame_state.
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

package oni

/*
2D vector in logical design pixels (x, y).
*/
Vec2 :: [2]f32

/*
Sentinel asset id meaning “no asset” / invalid handle.
*/
INVALID_ASSET_ID :: Asset_Id(-1)

/*
Built-in 1×1 white texture used as a default fill sample.
*/
TEXTURE_WHITE_ID :: Asset_Id(0)

/*
Scalar padding length in logical pixels (legacy alias for f32).
*/
Pd_int :: f32

/*
Maximum number of tracked gamepad buttons in `Gamepad_Input`.
*/
GAMEPAD_BUTTON_COUNT :: 32

/*
Small spacing preset (8px).
*/
PADDING_SM :: f32(8)

/*
Medium spacing preset (12px).
*/
PADDING_MD :: f32(12)

/*
Large spacing preset (16px).
*/
PADDING_LG :: f32(16)

/*
Extra-large spacing preset (20px).
*/
PADDING_XL :: f32(20)

/*
Small margin preset (8px).
*/
MARGIN_SM :: f32(8)

/*
Medium margin preset (12px).
*/
MARGIN_MD :: f32(12)

/*
Large margin preset (16px).
*/
MARGIN_LG :: f32(16)

/*
Extra-large margin preset (20px).
*/
MARGIN_XL :: f32(20)

/*
Small corner radius preset (4px).
*/
RADIUS_SM :: f32(4)

/*
Medium corner radius preset (8px).
*/
RADIUS_MD :: f32(8)

/*
Large corner radius preset (12px).
*/
RADIUS_LG :: f32(12)

/*
Extra-large corner radius preset (16px).
*/
RADIUS_XL :: f32(16)

/*
Thin border width preset (1px).
*/
BORDER_SM :: f32(1)

/*
Medium border width preset (2px).
*/
BORDER_MD :: f32(2)

/*
Thick border width preset (3px).
*/
BORDER_LG :: f32(3)

/*
Extra-thick border width preset (4px).
*/
BORDER_XL :: f32(4)

/*
Small fixed width preset (120px).
*/
WIDTH_SM :: f32(120)

/*
Medium fixed width preset (160px).
*/
WIDTH_MD :: f32(160)

/*
Large fixed width preset (200px).
*/
WIDTH_LG :: f32(200)

/*
Extra-large fixed width preset (240px).
*/
WIDTH_XL :: f32(240)

/*
Small fixed height preset (36px).
*/
HEIGHT_SM :: f32(36)

/*
Medium fixed height preset (48px).
*/
HEIGHT_MD :: f32(48)

/*
Large fixed height preset (56px).
*/
HEIGHT_LG :: f32(56)

/*
Extra-large fixed height preset (64px).
*/
HEIGHT_XL :: f32(64)

/*
Size of keyboard key state arrays (`keys`, `keys_down`, `keys_repeat`).
*/
KEY_COUNT :: 512

/*
Stable string identity for a widget (focus, GetElementById, style maps).
*/
Widget_ID :: string

/*
Per-frame edge-detected frame_state for one mouse button in widget input handling.
*/
Widget_Mouse_Button_State :: struct {
	// True while the button is held this frame.
	down:     bool,
	// True on the frame the button transitioned down.
	pressed:  bool,
	// True on the frame the button transitioned up.
	released: bool,
	// Click count for this press (1 = single, 2 = double, …).
	clicks:   int,
}

/*
Per-frame edge-detected frame_state for one keyboard key in widget input handling.
*/
Widget_Mouse_Key_State :: struct {
	// True while the key is held this frame.
	down:     bool,
	// True on the frame the key transitioned down.
	pressed:  bool,
	// True on the frame the key transitioned up.
	released: bool,
	// True when the OS reports a key-repeat pulse this frame.
	repeat:   bool,
}


/*
Global per-frame widget input context: focus, mouse, keys, and hover tracking.

Lives inside State (Persistent) so hot reload rebinds the same heap storage.
Cross-frame string fields own auto-generated ids; user-facing ids are borrowed.
*/
Widget_Context :: struct {
	// Widget id that received auto-focus this frame (may be owned).
	auto_focused_id:             Widget_ID,
	// True when `auto_focused_id` was allocated by the engine and must be freed.
	auto_focused_id_owned:       bool,
	// Currently focused widget id (may be owned).
	focused_id:                  Widget_ID,
	// True when `focused_id` was allocated by the engine and must be freed.
	focused_id_owned:            bool,
	// Ordered list of tabbable widget ids for Tab / Shift+Tab navigation.
	tab_order:                   [dynamic]Widget_ID,
	// Previous focused id before the latest tab move (may be owned).
	tab_focus_previous_id:       Widget_ID,
	// True when `tab_focus_previous_id` is engine-owned.
	tab_focus_previous_id_owned: bool,
	// True when tab navigation changed focus this frame.
	tab_focus_changed:           bool,
	// Id of the labeled control a label click should focus.
	label_focus_id:              Widget_ID,
	// Id of the labeled control a label activate should trigger.
	label_activate_id:           Widget_ID,
	// Frame number when the last label activate was issued.
	label_activate_frame:        u64,
	// Monotonic counter for auto-generated element ids within a pass.
	auto_element_index:          u32,
	// Maps author static keys to retained widget ids for the current pass pair.
	static_ids:                  map[string]Widget_ID,
	// Per-scroll-container content offsets in logical pixels.
	scroll_offsets:              map[string]Vec2,
	// When true, the scroll container should reveal the focused child.
	scroll_auto_reveal:          map[string]bool,
	// Pointer X in logical design pixels.
	mouse_x:                     f32,
	// Pointer Y in logical design pixels.
	mouse_y:                     f32,
	// True when the pointer moved since the previous frame.
	mouse_moved:                 bool,
	// Left mouse button edge state for this frame.
	left_mouse:                  Widget_Mouse_Button_State,
	// Right mouse button edge state for this frame.
	right_mouse:                 Widget_Mouse_Button_State,
	// Middle mouse button edge state for this frame.
	middle_mouse:                Widget_Mouse_Button_State,
	// Per-scancode key edge state for this frame.
	keys:                        [KEY_COUNT]Widget_Mouse_Key_State,
	// Widgets that were hovered on the previous frame (for leave edges).
	element_was_hovered:         map[string]bool,
	// Widgets that currently have pointer-down captured on them.
	element_pointer_down:        map[string]bool,
	// Layout UI id under the pointer after hit-testing.
	pointer_hit_ui_id:           UI_Id,
	// True when `pointer_hit_ui_id` is valid for this frame.
	pointer_hit_valid:           bool,
	// True when a handler stopped further pointer propagation.
	pointer_propagation_stopped: bool,
	// Set when a hovered tabbable claims focus on this press so a later
	// non-hovered widget (including a duplicate id) does not clear it.
	pointer_focus_claimed:       bool,
	// Per-widget text editing caret/selection/undo state.
	text_edit_states:            map[string]Text_Edit_State,
	// Pending clipboard/edit command for the focused text field.
	text_edit_command:           Text_Edit_Command,
	// Pending caret navigation key (+ modifiers) for the focused text field.
	text_edit_nav:               Text_Edit_Nav,
	// True when `text_edit_nav` should be applied this frame.
	text_edit_nav_pending:       bool,
}

/*
Text selection range as UTF-8 byte offsets into the plain string.

`anchor` is where the selection started; `head` is the active caret end.
*/
Text_Selection :: struct {
	// Selection start byte offset (inclusive).
	anchor: int,
	// Active caret / selection end byte offset.
	head:   int,
}

/*
Pending keyboard navigation for a focused text field.
*/
Text_Edit_Nav :: struct {
	// Scancode that requested caret motion (arrows, Home/End, etc.).
	key:   Scancode,
	// Extend selection when true (Shift held).
	shift: bool,
	// Word/line jump when true (Ctrl held).
	ctrl:  bool,
}

/*
Clipboard and edit commands routed to the focused text field.
*/
Text_Edit_Command :: enum {
	// No pending command.
	NONE,
	// Select the entire field contents.
	SELECT_ALL,
	// Copy selection (or all text) to the clipboard.
	COPY,
	// Cut selection to the clipboard.
	CUT,
	// Paste clipboard text at the caret/selection.
	PASTE,
	// Undo the last edit.
	UNDO,
	// Redo the last undone edit.
	REDO,
}

/*
Maximum number of entries retained in a text undo or redo stack.
*/
TEXT_UNDO_STACK_LIMIT :: 64

/*
One snapshot on a text undo/redo stack.
*/
Text_Undo_Entry :: struct {
	// Field text at this history point (heap-owned copy).
	text:      string,
	// Caret byte offset at this history point.
	caret:     int,
	// Selection at this history point.
	selection: Text_Selection,
}

/*
Bounded undo or redo history for a text field.
*/
Text_Undo_Stack :: struct {
	// Chronological snapshots (oldest first).
	entries:      [dynamic]Text_Undo_Entry,
	// Max entries retained before oldest are dropped.
	limit:        int,
	// Frame when the latest push occurred (coalescing helper).
	pushed_frame: u64,
}

/*
Mutable editing state for one text input widget across frames.
*/
Text_Edit_State :: struct {
	// Caret byte offset into the plain string.
	caret:                int,
	// Active selection (collapsed when head == anchor).
	selection:            Text_Selection,
	// True while a pointer drag is extending the selection.
	drag_active:          bool,
	// Blink timer phase for the caret (seconds).
	blink_phase:          f32,
	// Undo history for this field.
	undo:                 Text_Undo_Stack,
	// Redo history for this field.
	redo:                 Text_Undo_Stack,
	// Preferred column for vertical caret motion (logical x).
	preferred_column:     f32,
	// True when `preferred_column` is valid.
	has_preferred_column: bool,
}

/*
One shaped glyph cluster used for caret hit-testing and drawing.
*/
Text_Edit_Glyph :: struct {
	// Source cluster index into the plain string.
	cluster:    int,
	// Left edge of the glyph advance box in local text coordinates.
	x0:         f32,
	// Right edge of the glyph advance box in local text coordinates.
	x1:         f32,
	// Line index within the field geometry.
	line_index: int,
	// Distance from baseline to top of the line box.
	ascent:     f32,
	// Distance from baseline to bottom of the line box.
	descent:    f32,
}

/*
Laid-out geometry for measuring and editing text in a field.
*/
Text_Edit_Geometry :: struct {
	// Plain (unstyled) string being edited.
	plain:        string,
	// True when the source is rich text rather than plain.
	rich:         bool,
	// Origin of each line in local text coordinates.
	line_origins: []Vec2,
	// Line box height used for vertical caret motion.
	line_height:  f32,
	// Shaped glyphs for hit-testing and caret placement.
	glyphs:       []Text_Edit_Glyph,
}

/*
Merges a widget-specific frame_state struct with its resolved config type.
*/
Widget_Merged_State :: struct($S: typeid, $C: typeid) {
	// Per-frame interaction flags for this widget instance.
	using frame_state: S,
	// Resolved author config / style for this widget instance.
	config:            C,
}

/*
Bound to &state.widget by bind(); nil when no engine state is active.
*/
w_ctx: ^Widget_Context

/*
Snapshot of widget frame_state plus optional input metadata for event callbacks.
*/
Widget_Event :: struct($S: typeid) {
	// Interaction flags at the time of the event.
	frame_state:  S,
	// Mouse button index that triggered the event (0 if none).
	mouse_button: u8,
	// Keyboard scancode that triggered the event (0 if none).
	key:          Scancode,
}


/*
Lifecycle phase for mount / unmount animations and one-shot handlers.
*/
Mount :: enum {
	// No mount/unmount work pending.
	UNSET,
	// Mount or unmount callback is in progress.
	RUNNING,
	// Mount or unmount callback has finished.
	COMPLETED,
}

/*
Per-frame interaction flags for a widget: hover, press, focus, and click edges.

`is_hovered` is CSS-like: true for the topmost pointer hit and its layout ancestors.
`is_pointer_target` is true only for the topmost hit (exact target).
*/
Widget_Frame_State :: struct {
	// Mount lifecycle phase for this widget.
	mounting:          Mount,
	// Unmount lifecycle phase for this widget.
	unmounting:        Mount,
	// True for the pointer hit and its layout ancestors.
	is_hovered:        bool,
	// True only for the exact topmost pointer hit target.
	is_pointer_target: bool,
	// True while a primary press is held on this widget.
	is_Pressed:        bool,
	// True when this widget currently has keyboard focus.
	is_focused:        bool,
	// True on the frame of a left-button click.
	is_left_clicked:   bool,
	// True on the frame of a right-button click.
	is_right_clicked:  bool,
	// True on the frame of a middle-button click.
	is_middle_clicked: bool,
	// True on the frame the left button was released over this widget.
	is_left_released:  bool,
	// True on the frame the right button was released over this widget.
	is_right_released: bool,
	// True when the widget ignores pointer and keyboard interaction.
	is_disabled:       bool,
}

/*
Discriminant for built-in widget kinds used in config and layout.
*/
Widget_Kind :: enum {
	// Generic rectangular container / box.
	RECT,
	// Plain text run.
	TEXT,
	// Rich (styled) text run.
	RICH_TEXT,
	// Single-line or multi-line plain text input.
	TEXT_INPUT,
	// Rich text input field.
	RICH_TEXT_INPUT,
	// Clickable button.
	BUTTON,
	// Toggle checkbox.
	CHECKBOX,
	// Navigational or inline link.
	LINK,
	// Table root.
	TABLE,
	// Table caption.
	TABLE_CAPTION,
	// Table head section.
	TABLE_HEAD,
	// Table column heading cell.
	TABLE_HEADING,
	// Table body section.
	TABLE_BODY,
	// Table row.
	TABLE_ROW,
	// Table data cell.
	TABLE_CELL,
	// Table foot section.
	TABLE_FOOT,
	// Standalone scrollbar control.
	SCROLL_BAR,
	// Select / combobox root.
	SELECT,
	// Select trigger (opens the list).
	SELECT_TRIGGER,
	// Select displayed value.
	SELECT_VALUE,
	// Group of option items.
	OPTION_GROUP,
	// Single option item.
	OPTION,
	// Radio button group root.
	RADIO_GROUP,
	// Single radio button.
	RADIO,
	// Continuous slider.
	SLIDER,
	// Color picker control.
	COLOR_PICKER,
	// Calendar grid.
	CALENDAR,
	// Date picker root.
	DATE_PICKER,
	// Date picker trigger.
	DATE_PICKER_TRIGGER,
	// Date picker displayed value.
	DATE_PICKER_VALUE,
	// Date picker text input.
	DATE_PICKER_INPUT,
	// CSS-like grid container.
	GRID,
	// Tabs root.
	TABS,
	// Tabs trigger list.
	TABS_LIST,
	// Single tab trigger.
	TABS_TRIGGER,
	// Tab panel content.
	TABS_CONTENT,
	// Popover root.
	POPOVER,
	// Popover trigger.
	POPOVER_TRIGGER,
	// Popover floating content panel.
	POPOVER_CONTENT,
	// Modal dialog root.
	DIALOG,
	// Dialog trigger.
	DIALOG_TRIGGER,
	// Dialog viewport-fixed scrim overlay.
	DIALOG_SCRIM,
	// Dialog centered content panel.
	DIALOG_CONTENT,
}

/*
Axis for a scrollbar thumb (horizontal scrolls scroll_x, vertical scrolls scroll_y).
*/
Scroll_Axis :: enum {
	// Horizontal scrollbar (content `scroll_x`).
	X,
	// Vertical scrollbar (content `scroll_y`).
	Y,
}

/*
Axis orientation for a slider track.
*/
Slider_Orientation :: enum {
	// Track runs left-to-right.
	HORIZONTAL,
	// Track runs top-to-bottom.
	VERTICAL,
}

/*
Tri-state authoring mode for a `Cfg` field.
*/
Cfg_Tri :: enum {
	// Field was not authored; keep parent / default.
	UNSET,
	// Field has an explicit authored value.
	Value,
}

/*
Tri-frame_state config field: unset or explicit value.

Inherit is expressed inside each value union as `.INHERIT`, not on Cfg.
*/
Cfg :: struct($T: typeid) {
	// Whether the field is unset or carries a value.
	mode:  Cfg_Tri,
	// Authored value when `mode` is `.Value`.
	value: T,
}

/*
Author-time scroll override. Nil means keep the widget-context scroll offset;
an f32 (including 0) overwrites context for that axis.
*/
Scroll_Value :: union {
	f32,
}

/*
Shared inherit tag used as a variant on Widget_Config value unions.
*/
Inherit :: enum {
	// Take the resolved value from the parent style context.
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

/*
How a resolved axis length should be interpreted by layout.
*/
Length_Kind :: enum {
	// Zero-value / unresolved Length. Layout treats this as content-sized on both
	// axes (historical test default). Author-time unset width resolves to `.GROW`
	// and unset height to `.AUTO` via `resolve_length_from_*`.
	UNSET,
	// Width: content size (empty may stretch). Height: fill parent content area.
	AUTO,
	// Explicit pixel size in `value`.
	FIXED,
	// Percentage of the parent content box (`value` is 0–100).
	PERCENT,
	// Match the parent axis size.
	INHERIT,
	// CSS fit-content: shrink to content, clamped to available when known.
	FIT,
	// Take free space on this axis (flex weight 1 when `flex` unset).
	GROW,
	// CSS min-content on this axis.
	MIN_CONTENT,
	// CSS max-content on this axis.
	MAX_CONTENT,
}

/*
Resolved axis length: fixed, percent, inherit, auto, fit-content, grow,
min-content, or max-content.
*/
Length :: struct {
	// Interpretation of `value`.
	kind:  Length_Kind,
	// Pixel or percent magnitude depending on `kind`.
	value: f32,
}

/*
Author-time widget style overrides using tri-frame_state Cfg fields and dimension unions.
*/
Widget_Config :: struct {
	// Stable widget id for focus, lookup, and scroll maps.
	id:                    string,
	// Built-in widget kind discriminant.
	kind:                  Widget_Kind,
	// Optional accessible / tooltip title string.
	title:                 string,
	// Horizontal text alignment inside the content box.
	align:                 Cfg(Text_Align),
	// Request focus automatically when the widget mounts.
	auto_focus:            Cfg(Style_Bool),
	// Background fill color.
	background:            Cfg(Colors),
	// Border widths.
	border:                Cfg(Border),
	// Border stroke color.
	border_color:          Cfg(Colors),
	// Foreground / text color.
	color:                 Cfg(Colors),
	// Flex layout direction (row/column and wrap variants).
	direction:             Cfg(Widget_Direction),
	// When true, the widget ignores interaction.
	disabled:              Cfg(Style_Bool),
	// Flex grow/shrink weight along the main axis.
	flex:                  Cfg(Style_F32),
	// Font family handle for text.
	font:                  Cfg(Style_Font),
	// Font size in logical pixels.
	font_size:             Cfg(Style_F32),
	// Normal vs italic face selection.
	font_style:            Cfg(Font_Style),
	// Font weight (named or numeric).
	font_weight:           Cfg(Font_Weight),
	// Horizontal gap between flex/grid children.
	gap_x:                 Cfg(Gap_X),
	// Vertical gap between flex/grid children.
	gap_y:                 Cfg(Gap_Y),
	// Author-time height (keyword, px, or dim struct).
	height:                Height,
	// Main/cross axis justify alignment.
	justify:               Cfg(Justify),
	// Extra spacing between letter advances.
	letter_spacing:        Cfg(Style_F32),
	// Multiplier or absolute line box height for text.
	line_height:           Cfg(Style_F32),
	// Maximum height clamp in logical pixels.
	max_h:                 Cfg(Style_F32),
	// Maximum width clamp in logical pixels.
	max_w:                 Cfg(Style_F32),
	// Minimum height clamp in logical pixels.
	min_h:                 Cfg(Style_F32),
	// Minimum width clamp in logical pixels.
	min_w:                 Cfg(Style_F32),
	// Paint/layout order among siblings (higher draws later).
	order:                 Cfg(Style_F32),
	// Horizontal overflow behavior (clip/scroll/auto).
	overflow_x:            Cfg(Overflow),
	// Vertical overflow behavior (clip/scroll/auto).
	overflow_y:            Cfg(Overflow),
	// Opacity multiplier in 0–1.
	opacity:               Cfg(Style_F32),
	// Outer margin outside the border box.
	margin:                Cfg(Margin),
	// Inner padding inside the border box.
	padding:               Cfg(Padding),
	// Whether this widget can be the pointer hit target.
	pointer_events:        Cfg(Pointer_Events),
	// CSS-like position mode (relative/absolute/fixed/sticky).
	position:              Cfg(Position),
	// Corner radii.
	radius:                Cfg(Radius),
	// Self alignment on the cross axis (flex `align-self`).
	self:                  Cfg(Justify),
	// Draw space (artboard, screen, popover, overlay).
	space:                 Cfg(Style_Space),
	// When true, the widget participates in Tab order.
	tabbable:              Cfg(Style_Bool),
	// Not styled; set true on text fields that accept keyboard text.
	accepts_text_input:    bool,
	// Optional override of `w_ctx` scroll_x; not inherited.
	scroll_x:              Scroll_Value,
	// Optional override of `w_ctx` scroll_y; not inherited.
	scroll_y:              Scroll_Value,
	// Tab stop width in space columns for preserve wrapping.
	tab_size:              Cfg(Style_F32),
	// Text decoration lines (underline, strike, overline).
	text_decoration:       Cfg(Text_Decoration),
	// Color of text decoration strokes.
	text_decoration_color: Cfg(Colors),
	// Stroke pattern for text decorations.
	text_decoration_style: Cfg(Text_Decoration_Style),
	// Base paragraph direction (LTR/RTL).
	text_direction:        Cfg(Text_Direction),
	// How a texture fills its box (contain/cover/…).
	texture_fit:           Cfg(Style_Texture_Fit),
	// Texture anchor / inset position inside its box.
	texture_pos:           Cfg(Style_Texture_Pos),
	// Visibility (visible/hidden/none).
	visibility:            Cfg(Visibility),
	// Author-time width (keyword, px, or dim struct).
	width:                 Width,
	// Soft-wrap mode for text.
	wrap:                  Cfg(Text_Wrap),
	// Extra spacing between words.
	word_spacing:          Cfg(Style_F32),
	// Left inset for positioned widgets.
	x:                     Cfg(Style_F32),
	// Top inset for positioned widgets.
	y:                     Cfg(Style_F32),
	// Right inset for positioned widgets.
	right:                 Cfg(Style_F32),
	// Bottom inset for positioned widgets.
	bottom:                Cfg(Style_F32),
	// Stacking order within the same draw space.
	z_index:               Cfg(Style_F32),
	// Explicit grid column track list.
	grid_template_columns: Cfg(Grid_Template_Columns),
	// Explicit grid row track list.
	grid_template_rows:    Cfg(Grid_Template_Rows),
	// Implicit column track size for auto-placed items.
	grid_auto_columns:     Cfg(Grid_Auto_Track),
	// Implicit row track size for auto-placed items.
	grid_auto_rows:        Cfg(Grid_Auto_Track),
	// Auto-placement flow direction.
	grid_auto_flow:        Cfg(Grid_Auto_Flow),
	// Named grid template areas string.
	grid_template_areas:   Cfg(string),
	// Item grid column start line.
	grid_column_start:     Cfg(Grid_Line_Value),
	// Item grid column end line.
	grid_column_end:       Cfg(Grid_Line_Value),
	// Item grid row start line.
	grid_row_start:        Cfg(Grid_Line_Value),
	// Item grid row end line.
	grid_row_end:          Cfg(Grid_Line_Value),
	// Shorthand grid-column placement string.
	grid_column:           Cfg(string),
	// Shorthand grid-row placement string.
	grid_row:              Cfg(string),
	// Named grid-area placement string.
	grid_area:             Cfg(string),
}

/*
Fully resolved concrete style values after inheritance and theme defaults.
*/
Resolved_Widget_Style :: struct {
	// Horizontal text alignment.
	align:                         Text_Align,
	// Auto-focus flag after resolve.
	auto_focus:                    bool,
	// Background color token / value.
	background:                    Colors,
	// Cached RGBA for `background` when resolvable.
	background_rgba:               RGBA,
	// True when `background_rgba` is valid.
	background_rgba_ok:            bool,
	// Resolved border widths.
	border:                        Border,
	// Border color token / value.
	border_color:                  Colors,
	// Cached RGBA for `border_color` when resolvable.
	border_color_rgba:             RGBA,
	// True when `border_color_rgba` is valid.
	border_color_rgba_ok:          bool,
	// Foreground / text color token / value.
	color:                         Colors,
	// Cached RGBA for `color` when resolvable.
	color_rgba:                    RGBA,
	// True when `color_rgba` is valid.
	color_rgba_ok:                 bool,
	// Concrete flex direction after resolve.
	direction:                     Direction_Layout,
	// Disabled flag after resolve.
	disabled:                      bool,
	// Flex weight after resolve.
	flex:                          f32,
	// Resolved font handle.
	font:                          Font_Handle,
	// Font size in logical pixels.
	font_size:                     f32,
	// Resolved font style.
	font_style:                    Font_Style,
	// Resolved font weight.
	font_weight:                   Font_Weight,
	// Horizontal gap in logical pixels.
	gap_x:                         u16,
	// Vertical gap in logical pixels.
	gap_y:                         u16,
	// Resolved height length.
	height:                        Length,
	// Resolved justify on both axes.
	justify:                       Justify_Pos,
	// Letter spacing in logical pixels.
	letter_spacing:                f32,
	// Line height multiplier / size.
	line_height:                   f32,
	// Max height clamp (0 = none).
	max_h:                         f32,
	// Max width clamp (0 = none).
	max_w:                         f32,
	// Min height clamp.
	min_h:                         f32,
	// Min width clamp.
	min_w:                         f32,
	// Resolved margin.
	margin:                        Margin,
	// Resolved padding.
	padding:                       Padding,
	// Resolved corner radii.
	radius:                        Radius,
	// Draw space used when painting.
	space:                         Draw_Space,
	// Text decoration lines.
	text_decoration:               Text_Decoration,
	// Text decoration color token / value.
	text_decoration_color:         Colors,
	// Cached RGBA for text decoration color.
	text_decoration_color_rgba:    RGBA,
	// True when text decoration RGBA is valid.
	text_decoration_color_rgba_ok: bool,
	// Text decoration stroke style.
	text_decoration_style:         Text_Decoration_Style,
	// Paragraph base direction.
	text_direction:                Text_Direction,
	// Resolved width length.
	width:                         Length,
	// Text wrap mode.
	wrap:                          Text_Wrap,
	// Left positioned inset.
	x:                             f32,
	// Top positioned inset.
	y:                             f32,
	// Right positioned inset.
	right:                         f32,
	// Bottom positioned inset.
	bottom:                        f32,
	// True when `x` was authored / resolved as set.
	x_set:                         bool,
	// True when `y` was authored / resolved as set.
	y_set:                         bool,
	// True when `right` was authored / resolved as set.
	right_set:                     bool,
	// True when `bottom` was authored / resolved as set.
	bottom_set:                    bool,
	// Opacity in 0–1.
	opacity:                       f32,
	// Sibling paint/layout order.
	order:                         f32,
	// Combined overflow used by older call sites.
	overflow:                      Overflow,
	// Vertical overflow mode.
	overflow_y:                    Overflow,
	// Horizontal overflow mode.
	overflow_x:                    Overflow,
	// Pointer hit-testing policy.
	pointer_events:                Pointer_Events,
	// Visibility after resolve.
	visibility:                    Visibility,
	// Stacking order within draw space.
	z_index:                       f32,
	// Position mode after resolve.
	position:                      Position,
	// Cross-axis self alignment.
	self:                          Justify_Pos,
	// Texture fit mode.
	texture_fit:                   Style_Texture_Fit,
	// Texture position.
	texture_pos:                   Style_Texture_Pos,
	// Participates in Tab order when true.
	tabbable:                      bool,
	// Accepts typed text when true.
	accepts_text_input:            bool,
	// Resolved horizontal scroll offset.
	scroll_x:                      f32,
	// Resolved vertical scroll offset.
	scroll_y:                      f32,
	// Tab stop width in space columns.
	tab_size:                      f32,
	// Extra word spacing in logical pixels.
	word_spacing:                  f32,
	// Resolved grid column tracks.
	grid_template_columns:         Grid_Template_Tracks,
	// Resolved grid row tracks.
	grid_template_rows:            Grid_Template_Tracks,
	// Implicit column track size.
	grid_auto_columns:             Grid_Track_Size,
	// Implicit row track size.
	grid_auto_rows:                Grid_Track_Size,
	// Auto-placement flow.
	grid_auto_flow:                Grid_Auto_Flow,
	// Named template areas string.
	grid_template_areas:           string,
	// Item column start line.
	grid_column_start:             Grid_Line,
	// Item column end line.
	grid_column_end:               Grid_Line,
	// Item row start line.
	grid_row_start:                Grid_Line,
	// Item row end line.
	grid_row_end:                  Grid_Line,
	// Shorthand column placement.
	grid_column:                   string,
	// Shorthand row placement.
	grid_row:                      string,
	// Named area placement.
	grid_area:                     string,
}

/*
Default tab stop width for preserve text, in space columns.
*/
DEFAULT_TAB_SIZE :: 4

/*
Resolved widget identity and style ready for layout and drawing.
*/
Resolved_Widget_Config :: struct {
	// Stable widget id.
	id:          string,
	// Widget kind discriminant.
	kind:        Widget_Kind,
	// Embedded resolved style fields.
	using style: Resolved_Widget_Style,
}

/*
Style stack entry with resolved style and current content box dimensions.
*/
Style_Context :: struct {
	// Inherited / current resolved style at this stack depth.
	using style: Resolved_Widget_Style,
	// Content box width available to children.
	content_w:   f32,
	// Content box height available to children.
	content_h:   f32,
}

/*
CSS-like position mode for a widget box.
*/
Position :: union {
	Inherit,
	enum {
		// Positioned in normal flow; offsets relative to itself.
		RELATIVE,
		// Removed from flow; offsets relative to the containing block.
		ABSOLUTE,
		// Removed from flow; offsets relative to the viewport / screen space.
		FIXED,
		// Like relative until it sticks within the scrollport.
		STICKY,
	},
	proc(frame_state: Widget_Frame_State, event: Widget_Event(Widget_Frame_State)) -> Position,
}

/*
Whether the widget paints and participates in layout.
*/
Visibility :: union {
	Inherit,
	enum {
		// Paint and lay out normally.
		VISIBLE,
		// Lay out but do not paint (space reserved).
		HIDDEN,
		// Remove from the layout tree entirely.
		NONE,
	},
	proc(frame_state: Widget_Frame_State, event: Widget_Event(Widget_Frame_State)) -> Visibility,
}

/*
Controls whether the widget can be the pointer hit target.
*/
Pointer_Events :: union {
	Inherit,
	enum {
		// Normal hit-testing.
		AUTO,
		// Never the pointer target; hits pass through.
		NONE,
	},
	proc(
		frame_state: Widget_Frame_State,
		event: Widget_Event(Widget_Frame_State),
	) -> Pointer_Events,
}

/*
Overflow clipping / scrolling policy for one axis.
*/
Overflow :: union {
	Inherit,
	enum {
		// Scroll when content overflows; otherwise clip as needed.
		AUTO,
		// Always provide a scrollable overflow region.
		SCROLL,
		// Clip overflowing content without scrolling.
		HIDDEN,
	},
	proc(frame_state: Widget_Frame_State, event: Widget_Event(Widget_Frame_State)) -> Overflow,
}

/*
Per-side padding values: top, bottom, left, and right.
*/
Pd :: struct {
	// Top padding (may be `.INHERIT`).
	t: F32_I,
	// Bottom padding (may be `.INHERIT`).
	b: F32_I,
	// Left padding (may be `.INHERIT`).
	l: F32_I,
	// Right padding (may be `.INHERIT`).
	r: F32_I,
}

/*
Symmetric horizontal/vertical padding shorthand.
*/
Pd_pos :: struct {
	// Left and right padding.
	x: F32_I,
	// Top and bottom padding.
	y: F32_I,
}

/*
Full padding specification with per-side, corner, axis, and preset flags.
*/
Pd_struct :: struct {
	// Top padding.
	t:  F32_I,
	// Bottom padding.
	b:  F32_I,
	// Left padding.
	l:  F32_I,
	// Right padding.
	r:  F32_I,
	// Top-left corner padding override.
	tl: F32_I,
	// Top-right corner padding override.
	tr: F32_I,
	// Bottom-left corner padding override.
	bl: F32_I,
	// Bottom-right corner padding override.
	br: F32_I,
	// Horizontal (left/right) padding.
	x:  F32_I,
	// Vertical (top/bottom) padding.
	y:  F32_I,
	// Apply `PADDING_SM` when true.
	sm: bool,
	// Apply `PADDING_MD` when true.
	md: bool,
	// Apply `PADDING_LG` when true.
	lg: bool,
	// Apply `PADDING_XL` when true.
	xl: bool,
}


/*
Author-time padding inside the border box.

Accepts inherit, empty (theme default), uniform f32, per-side, axis shorthand,
full struct, or a reactive proc.
*/
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
	// Top padding in logical pixels.
	t: f32,
	// Bottom padding in logical pixels.
	b: f32,
	// Left padding in logical pixels.
	l: f32,
	// Right padding in logical pixels.
	r: f32,
}

/*
Per-side margin values: top, bottom, left, and right.
*/
Mg :: struct {
	// Top margin (may be `.INHERIT`).
	t: F32_I,
	// Bottom margin (may be `.INHERIT`).
	b: F32_I,
	// Left margin (may be `.INHERIT`).
	l: F32_I,
	// Right margin (may be `.INHERIT`).
	r: F32_I,
}

/*
Symmetric horizontal/vertical margin shorthand.
*/
Mg_pos :: struct {
	// Left and right margin.
	x: F32_I,
	// Top and bottom margin.
	y: F32_I,
}

/*
Full margin specification with per-side, corner, axis, and preset flags.
*/
Mg_struct :: struct {
	// Top margin.
	t:  F32_I,
	// Bottom margin.
	b:  F32_I,
	// Left margin.
	l:  F32_I,
	// Right margin.
	r:  F32_I,
	// Top-left corner margin override.
	tl: F32_I,
	// Top-right corner margin override.
	tr: F32_I,
	// Bottom-left corner margin override.
	bl: F32_I,
	// Bottom-right corner margin override.
	br: F32_I,
	// Horizontal (left/right) margin.
	x:  F32_I,
	// Vertical (top/bottom) margin.
	y:  F32_I,
	// Apply `MARGIN_SM` when true.
	sm: bool,
	// Apply `MARGIN_MD` when true.
	md: bool,
	// Apply `MARGIN_LG` when true.
	lg: bool,
	// Apply `MARGIN_XL` when true.
	xl: bool,
}

/*
Author-time margin outside the border box.

Same value shapes as `Padding`. Margin does not paint or expand hit-testing;
it only reserves space between this widget and its neighbors in layout.
*/
Margin :: union {
	Inherit,
	struct{},
	f32,
	Mg,
	Mg_pos,
	Mg_struct,
	proc(frame_state: Widget_Frame_State, event: Widget_Event(Widget_Frame_State)) -> Margin,
}

/*
Resolved per-side margin in pixels for layout.
*/
Mg_px :: struct {
	// Top margin in logical pixels.
	t: f32,
	// Bottom margin in logical pixels.
	b: f32,
	// Left margin in logical pixels.
	l: f32,
	// Right margin in logical pixels.
	r: f32,
}

/*
Per-corner border radius values (each corner may be `.INHERIT`).
*/
Radius_corners :: struct {
	// Top-left corner radius.
	tl: F32_I,
	// Top-right corner radius.
	tr: F32_I,
	// Bottom-left corner radius.
	bl: F32_I,
	// Bottom-right corner radius.
	br: F32_I,
}

/*
Full radius specification with corners, sides, axis, and preset flags.
*/
Radius_struct :: struct {
	// Top-left corner radius.
	tl: F32_I,
	// Top-right corner radius.
	tr: F32_I,
	// Bottom-left corner radius.
	bl: F32_I,
	// Bottom-right corner radius.
	br: F32_I,
	// Top edge radii (tl/tr).
	t:  F32_I,
	// Bottom edge radii (bl/br).
	b:  F32_I,
	// Left edge radii (tl/bl).
	l:  F32_I,
	// Right edge radii (tr/br).
	r:  F32_I,
	// Horizontal corner radii.
	x:  F32_I,
	// Vertical corner radii.
	y:  F32_I,
	// Apply `RADIUS_SM` when true.
	sm: bool,
	// Apply `RADIUS_MD` when true.
	md: bool,
	// Apply `RADIUS_LG` when true.
	lg: bool,
	// Apply `RADIUS_XL` when true.
	xl: bool,
}

/*
Author-time corner radius: inherit, empty, uniform f32, full struct, corners, or proc.
*/
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
	// Top-left radius in logical pixels.
	tl: f32,
	// Top-right radius in logical pixels.
	tr: f32,
	// Bottom-left radius in logical pixels.
	bl: f32,
	// Bottom-right radius in logical pixels.
	br: f32,
}

/*
Per-side border width values: top, bottom, left, and right.
*/
Bd :: struct {
	// Top border width (may be `.INHERIT`).
	t: F32_I,
	// Bottom border width (may be `.INHERIT`).
	b: F32_I,
	// Left border width (may be `.INHERIT`).
	l: F32_I,
	// Right border width (may be `.INHERIT`).
	r: F32_I,
}

/*
Full border specification with per-side widths and preset flags.
*/
Bd_struct :: struct {
	// Top border width.
	t:  F32_I,
	// Bottom border width.
	b:  F32_I,
	// Left border width.
	l:  F32_I,
	// Right border width.
	r:  F32_I,
	// Apply `BORDER_SM` when true.
	sm: bool,
	// Apply `BORDER_MD` when true.
	md: bool,
	// Apply `BORDER_LG` when true.
	lg: bool,
	// Apply `BORDER_XL` when true.
	xl: bool,
}

/*
Author-time border widths: inherit, empty, uniform f32, full struct, sides, or proc.
*/
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
	// Top border width in logical pixels.
	t: f32,
	// Bottom border width in logical pixels.
	b: f32,
	// Left border width in logical pixels.
	l: f32,
	// Right border width in logical pixels.
	r: f32,
}

/*
Source priority for collapsed table border conflict resolution.
*/
Table_Border_Source :: enum {
	// Border authored on the table root.
	TABLE,
	// Border authored on a row group (thead/tbody/tfoot).
	ROW_GROUP,
	// Border authored on a table row.
	ROW,
	// Border authored on a table cell.
	CELL,
}

/*
One resolved border segment used during collapsed table layout.

Color is resolved at draw from the winning source node (`order`).
*/
Table_Border_Side :: struct {
	// Winning border width in logical pixels.
	width:  f32,
	// Cached color when already resolved at this stage.
	color:  RGBA,
	// Which table node contributed the winning border.
	source: Table_Border_Source,
	// Paint/conflict order of the winning source node.
	order:  int,
}

/*
Per-side collapsed borders resolved for one table cell.
*/
Table_Cell_Borders :: struct {
	// Top collapsed border segment.
	t: Table_Border_Side,
	// Bottom collapsed border segment.
	b: Table_Border_Side,
	// Left collapsed border segment.
	l: Table_Border_Side,
	// Right collapsed border segment.
	r: Table_Border_Side,
}

/*
Grid coordinates for a table cell inside its owning table.
*/
Table_Grid_Pos :: struct {
	// Zero-based row index.
	row: int,
	// Zero-based column index.
	col: int,
}

/*
Width/height dimension with min/max, percent, and preset flags.

Axis keywords use `Width_Mode` / `Height_Mode` (`.GROW` / `.FIT` /
`.MIN_CONTENT` / `.MAX_CONTENT`).
*/
Dim_struct :: struct {
	// Minimum size clamp (may be `.INHERIT`).
	min:     F32_I,
	// Maximum size clamp (may be `.INHERIT`).
	max:     F32_I,
	// Percentage of the parent content box (0–100).
	percent: F32_I,
	// Apply the SM width/height preset when true.
	sm:      bool,
	// Apply the MD width/height preset when true.
	md:      bool,
	// Apply the LG width/height preset when true.
	lg:      bool,
	// Apply the XL width/height preset when true.
	xl:      bool,
}

/*
Author-time width keyword.

Unset width resolves to `.GROW` (see `resolve_length_from_width`).

`.AUTO` — content size; may stretch to bounds when content is empty.
`.FIT` — CSS `fit-content`: shrink to content, clamped to available space.
`.GROW` — take free space on this axis (flex weight 1 when `flex` unset). Default when unset.
`.MIN_CONTENT` — CSS `min-content`: smallest size without avoidable overflow.
`.MAX_CONTENT` — CSS `max-content`: size that fits content without soft-wrap.
`.INHERIT` — match parent axis size.
*/
Width_Mode :: enum {
	// Match the parent width.
	INHERIT,
	// Size from content; may stretch when empty.
	AUTO,
	// CSS fit-content on the horizontal axis.
	FIT,
	// Grow into free horizontal space. Default when width is unset.
	GROW,
	// CSS min-content width.
	MIN_CONTENT,
	// CSS max-content width.
	MAX_CONTENT,
}

/*
Author-time width: empty (defaults to `.GROW`), keyword, fixed px, dim struct, or reactive proc.
*/
Width :: union {
	struct{},
	Width_Mode,
	f32,
	Dim_struct,
	proc(frame_state: Widget_Frame_State, event: Widget_Event(Widget_Frame_State)) -> Width,
}

/*
Author-time height keyword.

Unset height is content-sized (`Length_Kind.UNSET` via `resolve_length_from_height`).

`.GROW` — fill free vertical space (flex weight 1 when `flex` unset).
`.AUTO` — fill the parent content area (scrollport viewport; does not grow with content).
`.FIT` — shrink to content size, clamped to available space (CSS `fit-content`).
`.MIN_CONTENT` — CSS `min-content` height.
`.MAX_CONTENT` — CSS `max-content` height.
`.INHERIT` — match parent axis size.
*/
Height_Mode :: enum {
	// Match the parent height.
	INHERIT,
	// Fill the parent content area (scrollport viewport).
	AUTO,
	// CSS fit-content on the vertical axis.
	FIT,
	// Fill free vertical space.
	GROW,
	// CSS min-content height.
	MIN_CONTENT,
	// CSS max-content height.
	MAX_CONTENT,
}

/*
Author-time height: empty (content-sized), keyword, fixed px, dim struct, or reactive proc.
*/
Height :: union {
	struct{},
	Height_Mode,
	f32,
	Dim_struct,
	proc(frame_state: Widget_Frame_State, event: Widget_Event(Widget_Frame_State)) -> Height,
}

/*
Horizontal gap between children (inherit, empty, pixels, or reactive proc).
*/
Gap_X :: union {
	Inherit,
	struct{},
	u16,
	proc(frame_state: Widget_Frame_State, event: Widget_Event(Widget_Frame_State)) -> Gap_X,
}

/*
Vertical gap between children (inherit, empty, pixels, or reactive proc).
*/
Gap_Y :: union {
	Inherit,
	struct{},
	u16,
	proc(frame_state: Widget_Frame_State, event: Widget_Event(Widget_Frame_State)) -> Gap_Y,
}

/*
Soft-wrap policy for text layout.
*/
Text_Wrap_Kind :: enum {
	// No wrapping; text stays on one line (may overflow).
	NONE,
	// Wrap only at explicit newline characters.
	NEWLINES,
	// Soft-wrap at break opportunities, then balance line lengths.
	// Unbreakable runs never split mid-word; they may overflow the box.
	BALANCE,
	// Wrap at the container width, preserving whitespace/newlines.
	PRESERVE,
}

/*
Text wrap style value with inherit support.
*/
Text_Wrap :: union {
	Inherit,
	Text_Wrap_Kind,
	proc(frame_state: Widget_Frame_State, event: Widget_Event(Widget_Frame_State)) -> Text_Wrap,
}

/*
Horizontal alignment of text inside its content box.
*/
Text_Align_Kind :: enum {
	// Align text to the left edge.
	LEFT,
	// Center text horizontally.
	CENTER,
	// Align text to the right edge.
	RIGHT,
}

/*
Text alignment style value with inherit support.
*/
Text_Align :: union {
	Inherit,
	Text_Align_Kind,
	proc(frame_state: Widget_Frame_State, event: Widget_Event(Widget_Frame_State)) -> Text_Align,
}

/*
Base paragraph direction for bidirectional text.
*/
Text_Direction_Kind :: enum {
	// Left-to-right base direction.
	LTR,
	// Right-to-left base direction.
	RTL,
}

/*
Text direction style value with inherit support.
*/
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
	// Draw a line under the text.
	UNDERLINE,
	// Draw a line through the middle of the text.
	LINE_THROUGH,
	// Draw a line above the text.
	OVERLINE,
}

/*
Set of text decoration lines that may be combined.
*/
Text_Decoration_Lines :: bit_set[Text_Decoration_Line;u8]

/*
Text decoration lines style value with inherit support.
*/
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
	// Single solid stroke.
	SOLID,
	// Double solid stroke.
	DOUBLE,
	// Dotted stroke.
	DOTTED,
	// Dashed stroke.
	DASHED,
	// Wavy stroke.
	WAVY,
}

/*
Text decoration style value with inherit support.
*/
Text_Decoration_Style :: union {
	Inherit,
	Text_Decoration_Style_Kind,
	proc(
		frame_state: Widget_Frame_State,
		event: Widget_Event(Widget_Frame_State),
	) -> Text_Decoration_Style,
}

/*
Flex/grid alignment keyword shared by justify and align-self.
*/
Justify_Align :: enum {
	// Pack toward the start of the axis.
	START,
	// Center along the axis.
	CENTER,
	// Pack toward the end of the axis.
	END,
	// Stretch items to fill the axis.
	STRETCH,
	// Distribute free space between items.
	SPACE_BETWEEN,
	// Distribute free space around items.
	SPACE_AROUND,
	// Distribute free space evenly including ends.
	SPACE_EVENLY,
	// Size / align using max-content heuristics.
	MAX_CONTENT,
	// Size / align using min-content heuristics.
	MIN_CONTENT,
	// Table-cell vertical alignment semantics.
	TABLE_CELL,
}

/*
Horizontal justify/align value with inherit support.
*/
Justify_X :: union {
	Inherit,
	struct{},
	Justify_Align,
	proc(frame_state: Widget_Frame_State, event: Widget_Event(Widget_Frame_State)) -> Justify_X,
}

/*
Vertical justify/align value with inherit support.
*/
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
	// Horizontal alignment.
	x: Justify_X,
	// Vertical alignment.
	y: Justify_Y,
}

/*
Justify style value: inherit, empty, both axes, single keyword, or reactive proc.
*/
Justify :: union {
	Inherit,
	struct{},
	Justify_Pos,
	Justify_Align,
	proc(frame_state: Widget_Frame_State, event: Widget_Event(Widget_Frame_State)) -> Justify,
}


/*
Concrete flex layout direction after style resolve.
*/
Direction_Layout :: enum {
	// Row, left-to-right, no wrap.
	HORIZONTAL,
	// Column, top-to-bottom, no wrap.
	VERTICAL,
	// Row that wraps onto additional lines.
	HORIZONTAL_WRAP,
	// Column that wraps onto additional columns.
	VERTICAL_WRAP,
	// Row, right-to-left, no wrap.
	HORIZONTAL_REVERSE,
	// Column, bottom-to-top, no wrap.
	VERTICAL_REVERSE,
	// Row reverse that wraps.
	HORIZONTAL_WRAP_REVERSE,
	// Column reverse that wraps.
	VERTICAL_WRAP_REVERSE,
}

/*
Widget flex direction style value with inherit support.
*/
Widget_Direction :: union {
	Inherit,
	struct{},
	Direction_Layout,
	proc(
		frame_state: Widget_Frame_State,
		event: Widget_Event(Widget_Frame_State),
	) -> Widget_Direction,
}

/*
How a texture is scaled into its destination box (CSS object-fit).
*/
Texture_Fit :: enum {
	// Stretch to fill the box, ignoring aspect ratio.
	FILL,
	// Letterbox to fit inside the box, preserving aspect ratio.
	CONTAIN,
	// Cover the box, cropping overflow, preserving aspect ratio.
	COVER,
	// Like contain, but never scale up above intrinsic size.
	SCALE_DOWN,
	// Use intrinsic size; do not scale to the box.
	NONE,
}

/*
Texture fit style value with inherit support.
*/
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
	// Top inset (may be `.INHERIT`).
	t: F32_I,
	// Bottom inset (may be `.INHERIT`).
	b: F32_I,
	// Left inset (may be `.INHERIT`).
	l: F32_I,
	// Right inset (may be `.INHERIT`).
	r: F32_I,
}

/*
Texture anchor position as normalized x/y percentages in 0-1.
*/
Texture_Pos_X_Y :: struct {
	// Horizontal anchor in 0–1 (0 = left, 1 = right).
	x: F32_I,
	// Vertical anchor in 0–1 (0 = top, 1 = bottom).
	y: F32_I,
}

/*
Fully resolved texture position with anchor and pixel offsets.
*/
Resolved_Texture_Pos :: struct {
	// Normalized horizontal anchor in 0–1.
	x:        f32,
	// Normalized vertical anchor in 0–1.
	y:        f32,
	// Additional horizontal pixel offset after anchoring.
	offset_x: f32,
	// Additional vertical pixel offset after anchoring.
	offset_y: f32,
}

/*
Texture position style value with inherit support.
*/
Style_Texture_Pos :: union {
	Inherit,
	struct{},
	Texture_Pos,
	Texture_Pos_X_Y,
	Resolved_Texture_Pos,
	proc(frame_state: Widget_Frame_State, event: Widget_Event(Widget_Frame_State)) -> Texture_Pos,
}

/*
Axis-aligned rectangle in logical coordinates.
*/
Rect :: struct {
	// Left edge X in logical pixels.
	x: f32,
	// Top edge Y in logical pixels.
	y: f32,
	// Width in logical pixels.
	w: f32,
	// Height in logical pixels.
	h: f32,
}

/*
Coordinate space a draw command paints into (and hit-tests against).
*/
Draw_Space :: enum {
	// Transformed artboard / canvas space.
	ARTBOARD,
	// Window / screen logical space.
	SCREEN,
	// Screen-coordinate overlay; paints/hits above screen + artboard.
	POPOVER,
	// Framework chrome (error banner); paints/hits above popover.
	OVERLAY,
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
LCD subpixel geometry for the window's display.

Unknown / None → no LCD text (C.6). Vertical layouts map to Unknown until LCD_V ships.
*/
Display_Subpixel_Order :: enum u8 {
	// Subpixel order unknown; disable LCD text.
	Unknown = 0,
	// No subpixel geometry (grayscale AA only).
	None    = 1,
	// Red-green-blue horizontal subpixels.
	RGB     = 2,
	// Blue-green-red horizontal subpixels.
	BGR     = 3,
}

/*
User preference for display subpixel order (`dpi subpixel=` in settings.kdl).

Auto queries the OS on dpi_sync; other values force the runtime order.
*/
Dpi_Subpixel_Setting :: enum u8 {
	// Query the OS each dpi sync.
	Auto = 0,
	// Force grayscale (no LCD).
	None = 1,
	// Force RGB subpixel order.
	RGB  = 2,
	// Force BGR subpixel order.
	BGR  = 3,
}

/*
Window DPI scale, logical vs drawable pixels, and display subpixel order.
*/
Dpi_Info :: struct {
	// Logical-to-drawable scale factor (1.0 = 100% DPI).
	scale:          f32,
	// Window width in logical design pixels.
	logical_w:      i32,
	// Window height in logical design pixels.
	logical_h:      i32,
	// Drawable / framebuffer width in physical pixels.
	drawable_w:     i32,
	// Drawable / framebuffer height in physical pixels.
	drawable_h:     i32,
	// Active LCD subpixel order for text rasterization.
	subpixel_order: Display_Subpixel_Order,
}

/*
Opaque id for a loaded GPU/CPU asset (texture, font family, face, …).
*/
Asset_Id :: distinct i32

/*
Opaque id for a layout UI node within a frame.
*/
UI_Id :: distinct u64

/*
Reference to a loaded texture asset with pixel dimensions.
*/
Texture_Handle :: struct {
	// Asset id of the texture (or `INVALID_ASSET_ID`).
	id: Asset_Id,
	// Intrinsic width in texture pixels.
	w:  f32,
	// Intrinsic height in texture pixels.
	h:  f32,
}

/*
Sub-rectangle within an atlas or standalone texture, in pixel coordinates.
*/
Atlas_Region :: struct {
	// Texture that owns this region.
	texture_id: Asset_Id,
	// Left edge in texture pixels.
	x:          f32,
	// Top edge in texture pixels.
	y:          f32,
	// Region width in texture pixels.
	w:          f32,
	// Region height in texture pixels.
	h:          f32,
}

/*
Font upright vs italic style selection.
*/
Font_Styles :: enum {
	// Upright / roman face.
	NORMAL,
	// Italic (or oblique) face.
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
	// Weight 100.
	Thin,
	// Weight 200.
	Extra_Light,
	// Weight 300.
	Light,
	// Weight 400 (regular).
	Normal,
	// Weight 500.
	Medium,
	// Weight 600.
	Semi_Bold,
	// Weight 700.
	Bold,
	// Weight 800.
	Extra_Bold,
	// Weight 900.
	Heavy,
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
	// Filesystem path to the font file.
	path:   string,
	// Upright vs italic for this face.
	style:  Font_Style,
	// Weight for this face.
	weight: Font_Weight,
}

/*
Reference to a registered font family with a default logical size in pixels.
*/
Font_Handle :: struct {
	// Asset id of the font family.
	id:      Asset_Id,
	// Default size in logical pixels when style does not override.
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
	// Asset id of the concrete face instance.
	id:      Asset_Id,
	// Raster size in logical pixels.
	size_px: f32,
}

/*
Global theme defaults for palette, typography, spacing, and widget chrome.
*/
Theme :: struct {
	// Named color palette for the app.
	palette:      Palette,
	// Default justify for containers.
	justify:      Justify,
	// Default border widths.
	border:       Border,
	// Default border color.
	border_color: Colors,
	// Default background color.
	background:   Colors,
	// Default horizontal gap.
	gap_x:        Gap_X,
	// Default vertical gap.
	gap_y:        Gap_Y,
	// Default foreground / text color.
	color:        Colors,
	// Default flex direction.
	direction:    Widget_Direction,
	// Default body font.
	font_body:    Font_Handle,
	// Default heading font.
	font_heading: Font_Handle,
	// Default height for controls.
	height:       Height,
	// Default margin.
	margin:       Margin,
	// Default padding.
	padding:      Padding,
	// Default corner radius.
	radius:       Radius,
	// Default width for controls.
	width:        Width,
	// Focus ring color.
	ring:         Colors,
}

/*
Keyboard modifier key frame_state: shift, ctrl, alt, and super.
*/
Input_Modifiers :: struct {
	// Shift key is down.
	shift: bool,
	// Ctrl / Control key is down.
	ctrl:  bool,
	// Alt / Option key is down.
	alt:   bool,
	// Super / Meta / Windows / Command key is down.
	super: bool,
}

/*
Normalized gamepad axes, d-pad, triggers, and per-button down frame_state.
*/
Gamepad_Input :: struct {
	// True when a gamepad is connected and polled.
	connected:     bool,
	// D-pad left is held.
	dpad_left:     bool,
	// D-pad right is held.
	dpad_right:    bool,
	// D-pad up is held.
	dpad_up:       bool,
	// D-pad down is held.
	dpad_down:     bool,
	// Left stick X in roughly -1…1.
	left_stick_x:  f32,
	// Left stick Y in roughly -1…1.
	left_stick_y:  f32,
	// Right stick X in roughly -1…1.
	right_stick_x: f32,
	// Right stick Y in roughly -1…1.
	right_stick_y: f32,
	// Left trigger in 0…1.
	left_trigger:  f32,
	// Right trigger in 0…1.
	right_trigger: f32,
	// Per-button held state indexed by gamepad button id.
	buttons_down:  [GAMEPAD_BUTTON_COUNT]bool,
}

/*
Per-frame input snapshot: mouse, keyboard, text input, modifiers, and gamepad.
*/
Input_State :: struct {
	// Pointer X in logical design pixels.
	mouse_x:             f32,
	// Pointer Y in logical design pixels.
	mouse_y:             f32,
	// Left mouse button is held.
	mouse_left:          bool,
	// Right mouse button is held.
	mouse_right:         bool,
	// Middle mouse button is held.
	mouse_middle:        bool,
	// Click count for the latest left press.
	mouse_left_clicks:   int,
	// Click count for the latest right press.
	mouse_right_clicks:  int,
	// Click count for the latest middle press.
	mouse_middle_clicks: int,
	// Horizontal wheel delta this frame.
	mouse_wheel_x:       f32,
	// Vertical wheel delta this frame.
	mouse_wheel_y:       f32,
	// Per-scancode key held state.
	keys_down:           [KEY_COUNT]bool,
	// Per-scancode key-repeat pulses this frame.
	keys_repeat:         [KEY_COUNT]bool,
	// UTF-8 text committed this frame (IME / key typing).
	text_input:          [dynamic]u8,
	// Current IME composition string (borrowed / transient).
	ime_text:            string,
	// IME caret offset within `ime_text`.
	ime_cursor:          int,
	// IME selection / composition length hint.
	ime_length:          int,
	// Modifier keys for this frame.
	modifiers:           Input_Modifiers,
	// Primary gamepad snapshot for this frame.
	gamepad:             Gamepad_Input,
}

package oni

import "core:fmt"
import "core:hash"


/*
Appends an element to this frame's tab order in declaration order.

Call during the layout pass for widgets with tabbable set.
*/
register_tabbable :: proc(element_id: Widget_ID) {
	if w_ctx.tab_order == nil {
		w_ctx.tab_order = make([dynamic]Widget_ID)
	}
	append(&w_ctx.tab_order, element_id)
}

@(private)
element_key_is_active :: proc(key: string) -> bool {
	if key == string(w_ctx.focused_id) do return true

	for id in w_ctx.tab_order {
		if string(id) == key do return true
	}

	if w_ctx.static_ids != nil {
		for _, static_id in w_ctx.static_ids {
			if string(static_id) == key do return true
		}
	}

	return false
}

/*
Removes stale hover and pointer-down entries for elements no longer in the UI.
*/
widget_prune_element_maps :: proc() {
	if w_ctx.element_was_hovered != nil {
		remove_keys := make([dynamic]string, context.temp_allocator)
		for key in w_ctx.element_was_hovered {
			if !element_key_is_active(key) {
				append(&remove_keys, key)
			}
		}
		for key in remove_keys {
			delete_key(&w_ctx.element_was_hovered, key)
		}
	}

	if w_ctx.element_pointer_down != nil {
		remove_keys := make([dynamic]string, context.temp_allocator)
		for key in w_ctx.element_pointer_down {
			if !element_key_is_active(key) {
				append(&remove_keys, key)
			}
		}
		for key in remove_keys {
			delete_key(&w_ctx.element_pointer_down, key)
		}
	}
}

/*
Releases heap-owned widget input maps.

Call during UI shutdown.
*/
widget_ctx_shutdown :: proc() {
	if w_ctx.tab_order != nil {
		delete(w_ctx.tab_order)
		w_ctx.tab_order = nil
	}
	if w_ctx.static_ids != nil {
		delete(w_ctx.static_ids)
		w_ctx.static_ids = nil
	}
	if w_ctx.element_was_hovered != nil {
		delete(w_ctx.element_was_hovered)
		w_ctx.element_was_hovered = nil
	}
	if w_ctx.element_pointer_down != nil {
		delete(w_ctx.element_pointer_down)
		w_ctx.element_pointer_down = nil
	}

	w_ctx = {}
}

/*
Clears focus when the focused element is no longer in the tab order.
*/
widget_prune_focus :: proc() {
	if w_ctx.focused_id == "" do return

	for id in w_ctx.tab_order {
		if id == w_ctx.focused_id do return
	}

	w_ctx.focused_id = {}
}

/*
Moves focus to the next or previous tabbable element in declaration order.

Returns false when the tab order is empty.
*/
widget_focus_tab :: proc(reverse: bool) -> bool {
	n := len(w_ctx.tab_order)
	if n == 0 do return false

	previous_id := w_ctx.focused_id

	current_idx := -1
	for id, i in w_ctx.tab_order {
		if id == w_ctx.focused_id {
			current_idx = i
			break
		}
	}

	next_idx: int
	if current_idx == -1 {
		next_idx = reverse ? n - 1 : 0
	} else if reverse {
		next_idx = current_idx - 1
		if next_idx < 0 do next_idx = n - 1
	} else {
		next_idx = current_idx + 1
		if next_idx >= n do next_idx = 0
	}

	next_id := w_ctx.tab_order[next_idx]
	if next_id == previous_id do return false

	w_ctx.focused_id = next_id
	w_ctx.tab_focus_previous_id = previous_id
	w_ctx.tab_focus_changed = true
	return true
}

/*
Advances focus to the next tabbable element when Tab is pressed.

Shift+Tab moves focus backward.
*/
widget_process_tab_navigation :: proc() {
	tab_key := w_ctx.keys[int(Scancode.TAB)]
	if !tab_key.pressed do return

	reverse := false
	if state != nil {
		reverse = state.input.modifiers.shift
	}

	widget_focus_tab(reverse)
}

/*
Moves keyboard focus to the next tabbable element in declaration order.
*/
focus_next :: proc() -> bool {
	return widget_focus_tab(false)
}

/*
Moves keyboard focus to the previous tabbable element in declaration order.
*/
focus_prev :: proc() -> bool {
	return widget_focus_tab(true)
}

/*
Returns the next auto-generated element id for this frame.

Ids are unique within a frame and reset at ui_begin_frame.
*/
auto_element_id :: proc() -> Widget_ID {
	idx := w_ctx.auto_element_index
	w_ctx.auto_element_index += 1

	id := fmt.tprintf("__auto_element__{0}", idx)

	return id
}


/*
Maps a stable user id to the auto-generated key used this frame.

Skipped when id is empty.
*/
register_static_id :: proc(id: string, static_id: string) {
	if id == "" do return

	if w_ctx.static_ids == nil {
		w_ctx.static_ids = make(map[string]Widget_ID)
	}

	w_ctx.static_ids[id] = static_id
}

/*
Returns a frame-local key for an element and registers its static id mapping.
*/
element_key :: proc(id: string) -> string {
	key := auto_element_id()
	register_static_id(id, key)

	return key
}

/*
Clears per-frame pressed and released flags on a mouse button state.
*/
clear_button_transients :: proc(button: ^Widget_Mouse_Button_State) {
	button.pressed = false
	button.released = false
}

/*
Clears per-frame pressed and released flags on a keyboard key state.
*/
clear_key_transients :: proc(key: ^Widget_Mouse_Key_State) {
	key.pressed = false
	key.released = false
}

/*
Updates mouse button down state and sets pressed/released edge flags.
*/
@(private)
sync_widget_button :: proc(button: ^Widget_Mouse_Button_State, is_down: bool) {
	if is_down {
		if !button.down do button.pressed = true
	} else {
		if button.down do button.released = true
	}

	button.down = is_down
}

/*
Updates keyboard key down state and sets pressed/released edge flags.
*/
@(private)
sync_widget_key :: proc(key: ^Widget_Mouse_Key_State, is_down: bool) {
	if is_down {
		if !key.down do key.pressed = true
	} else {
		if key.down do key.released = true
	}

	key.down = is_down
}

/*
Copies engine input into widget context and tracks mouse movement.

Syncs mouse position and all button/key states for hit testing.
*/
sync_widget_input :: proc() {
	if state == nil do return

	new_x := state.input.mouse_x
	new_y := state.input.mouse_y
	if new_x != w_ctx.mouse_x || new_y != w_ctx.mouse_y {
		w_ctx.mouse_moved = true
	}
	w_ctx.mouse_x = new_x
	w_ctx.mouse_y = new_y

	sync_widget_button(&w_ctx.left_mouse, state.input.mouse_left)
	sync_widget_button(&w_ctx.right_mouse, state.input.mouse_right)
	sync_widget_button(&w_ctx.middle_mouse, state.input.mouse_middle)

	for scancode in 0 ..< KEY_COUNT {
		sync_widget_key(&w_ctx.keys[scancode], state.input.keys_down[scancode])
	}
}

/*
Returns whether the mouse pointer is inside a rect in the given draw space.

Converts screen coordinates to world space for artboard rects.
*/
pointer_over :: proc(rect: Rect, space: Draw_Space) -> bool {
	mouse := Vec2{w_ctx.mouse_x, w_ctx.mouse_y}

	if space == .ARTBOARD {
		mouse = View_Screen_To_World(mouse)
	}

	return(
		mouse.x >= rect.x &&
		mouse.x < rect.x + rect.w &&
		mouse.y >= rect.y &&
		mouse.y < rect.y + rect.h \
	)
}

/*
Returns the hit-test rect for a widget, honoring fixed width and height.
*/
widget_hit_rect :: proc(layout_id: UI_Id, style: Resolved_Widget_Style) -> Rect {
	rect := ui_layout_rect(layout_id)

	if style.width.kind == .FIXED {
		rect.w = style.width.value
	} else if w := length_resolve(style.width, rect.w); w > 0 {
		rect.w = w
	}

	if style.height.kind == .FIXED {
		rect.h = style.height.value
	} else if h := length_resolve(style.height, rect.h); h > 0 {
		rect.h = h
	}

	return rect
}

/*
Casts a typed widget state pointer to the generic Widget_Frame_State view.
*/
to_ui_state :: proc(state: ^$S) -> Widget_Frame_State {

	return (^Widget_Frame_State)(cast(rawptr)state)^
}

/*
Wraps a typed widget state pointer in a generic Widget_Event.
*/
to_ui_event :: proc(frame_state: ^$S) -> Widget_Event(Widget_Frame_State) {
	return {frame_state = to_ui_state(state)}
}

/*
Detects hover enter/leave transitions and updates per-element hover memory.
*/
consume_hover_transition :: proc(element_id: string, hovered: bool) -> (entered, left: bool) {
	if w_ctx.element_was_hovered == nil {
		w_ctx.element_was_hovered = make(map[string]bool)
	}

	was_hovered := w_ctx.element_was_hovered[element_id]
	entered = hovered && !was_hovered
	left = was_hovered && !hovered
	w_ctx.element_was_hovered[element_id] = hovered

	return
}

/*
Builds uniform or axis-pair padding from x and optional y values.

When y is zero, all sides use x.
*/
resolve_padding_xy :: proc(x, y: f32) -> Pd {
	if y == 0 do return {t = x, b = x, l = x, r = x}

	return {t = y, b = y, l = x, r = x}
}

/*
Resolves a padding struct into concrete side values.

Handles preset sizes and explicit per-side or axis shorthand.
*/
resolve_padding_struct :: proc(s: Pd_struct) -> (padding: Pd, ok: bool) {
	switch {
	case s.sm:
		v := PADDING_SM
		return Pd{t = v, b = v, l = v, r = v}, true
	case s.md:
		v := PADDING_MD
		return Pd{t = v, b = v, l = v, r = v}, true
	case s.lg:
		v := PADDING_LG
		return Pd{t = v, b = v, l = v, r = v}, true
	case s.xl:
		v := PADDING_XL
		return Pd{t = v, b = v, l = v, r = v}, true
	}

	if s.l != 0 || s.r != 0 || s.t != 0 || s.b != 0 {
		return Pd{t = s.t, b = s.b, l = s.l, r = s.r}, true
	}
	if s.x != 0 || s.y != 0 {
		return resolve_padding_xy(s.x, s.y), true
	}

	return {}, false
}

/*
Resolves a static Padding union value into concrete side insets.

Does not evaluate proc-valued padding; use resolve_padding for that.
*/
resolve_padding_value :: proc(p: Padding) -> (padding: Pd, ok: bool) {
	switch v in p {
	case struct{}:
		return {}, false
	case f32:
		if v == 0 do return {}, false
		return {v, v, v, v}, true
	case Pd_pos:
		if v.x == 0 && v.y == 0 do return {}, false
		return resolve_padding_xy(v.x, v.y), true
	case Pd_struct:
		return resolve_padding_struct(v)
	case Pd:
		return v, true
	case proc(frame_state: Widget_Frame_State, event: Widget_Event(Widget_Frame_State)) -> Padding:
		return {}, false
	}

	return {}, false
}

/*
Resolves padding from a union value, evaluating proc callbacks when present.
*/
resolve_padding :: proc(
	p: Padding,
	state: ^$S,
	event: Widget_Event(S),
) -> (
	padding: Pd,
	ok: bool,
) {
	#partial switch v in p {
	case proc(state: Widget_Frame_State, event: Widget_Event(Widget_Frame_State)) -> Padding:
		ui_state := to_ui_state(state)
		ui_event := to_ui_event(state)
		return resolve_padding(v(ui_state, ui_event), state, event)
	}

	return resolve_padding_value(p)
}

/*
Resolves a radius struct into per-corner values.

Handles presets, shorthand axes, and explicit corner overrides.
*/
resolve_radius_struct :: proc(s: Radius_struct) -> (radius: Radius_corners, ok: bool) {
	switch {
	case s.sm:
		v := RADIUS_SM
		return {tl = v, tr = v, bl = v, br = v}, true
	case s.md:
		v := RADIUS_MD
		return {tl = v, tr = v, bl = v, br = v}, true
	case s.lg:
		v := RADIUS_LG
		return {tl = v, tr = v, bl = v, br = v}, true
	case s.xl:
		v := RADIUS_XL
		return {tl = v, tr = v, bl = v, br = v}, true
	}

	if s.tl != 0 || s.tr != 0 || s.bl != 0 || s.br != 0 {
		return {s.tl, s.tr, s.bl, s.br}, true
	}

	tl, tr, bl, br := s.tl, s.tr, s.bl, s.br
	if s.t != 0 {
		if tl == 0 do tl = s.t
		if tr == 0 do tr = s.t
	}
	if s.b != 0 {
		if bl == 0 do bl = s.b
		if br == 0 do br = s.b
	}
	if s.l != 0 {
		if tl == 0 do tl = s.l
		if bl == 0 do bl = s.l
	}
	if s.r != 0 {
		if tr == 0 do tr = s.r
		if br == 0 do br = s.r
	}
	if tl != 0 || tr != 0 || bl != 0 || br != 0 {
		return {tl, tr, bl, br}, true
	}
	if s.x != 0 || s.y != 0 {
		return {s.x, s.x, s.y, s.y}, true
	}

	return {}, false
}

/*
Resolves border radius from a union value, evaluating proc callbacks when present.
*/
resolve_radius :: proc(
	r: Radius,
	state: ^$S,
	event: Widget_Event(S),
) -> (
	radius: Radius_corners,
	ok: bool,
) {
	ui_state := to_ui_state(state)
	ui_event := to_ui_event(state)
	switch v in r {
	case struct{}:
		return {}, false
	case f32:
		if v == 0 do return {}, false
		return resolve_radius_struct({t = v, b = v, l = v, r = v})
	case Radius_struct:
		return resolve_radius_struct(v)
	case Radius_corners:
		return v, true
	case proc(frame_state: Widget_Frame_State, event: Widget_Event(Widget_Frame_State)) -> Radius:
		return resolve_radius(v(ui_state, ui_event), state, event)
	}

	return {}, false
}

/*
Resolves a border struct into per-side widths.

Handles preset sizes and explicit per-side values.
*/
resolve_border_struct :: proc(s: Bd_struct) -> (width: Bd, ok: bool) {
	switch {
	case s.sm:
		v := BORDER_SM
		return Bd{t = v, b = v, l = v, r = v}, true
	case s.md:
		v := BORDER_MD
		return Bd{t = v, b = v, l = v, r = v}, true
	case s.lg:
		v := BORDER_LG
		return Bd{t = v, b = v, l = v, r = v}, true
	case s.xl:
		v := BORDER_XL
		return Bd{t = v, b = v, l = v, r = v}, true
	}

	if s.l != 0 || s.r != 0 || s.t != 0 || s.b != 0 {
		return Bd{s.t, s.b, s.l, s.r}, true
	}

	return {}, false
}

/*
Resolves a static Border union value into per-side widths.

Does not evaluate proc-valued borders; use resolve_border for that.
*/
resolve_border_value :: proc(b: Border) -> (border: Bd, ok: bool) {
	switch v in b {
	case struct{}:
		return {}, false
	case f32:
		if v == 0 do return {}, false
		return {v, v, v, v}, true
	case Bd_struct:
		return resolve_border_struct(v)
	case Bd:
		return v, true
	case proc(frame_state: Widget_Frame_State, event: Widget_Event(Widget_Frame_State)) -> Border:
		return {}, false
	}

	return {}, false
}

/*
Resolves border width from a union value, evaluating proc callbacks when present.
*/
resolve_border :: proc(b: Border, state: ^$S, event: Widget_Event(S)) -> (border: Bd, ok: bool) {
	#partial switch v in b {
	case proc(state: Widget_Frame_State, event: Widget_Event(Widget_Frame_State)) -> Border:
		ui_state := to_ui_state(state)
		ui_event := to_ui_event(state)
		return resolve_border(v(ui_state, ui_event), state, event)
	}

	return resolve_border_value(b)
}

/*
Resolves a static Gap_X union value to a pixel gap.

Does not evaluate proc-valued gaps; use resolve_child_gap_x for that.
*/
resolve_gap_x_value :: proc(g: Gap_X) -> (gap: u16, ok: bool) {
	switch v in g {
	case struct{}:
		return 0, false
	case u16:
		return v, true
	case proc(frame_state: Widget_Frame_State, event: Widget_Event(Widget_Frame_State)) -> Gap_X:
		return 0, false
	}

	return 0, false
}

/*
Resolves child gap_x from a union value, evaluating proc callbacks when present.
*/
resolve_child_gap_x :: proc(g: Gap_X, state: ^$S, event: Widget_Event(S)) -> (gap: u16, ok: bool) {
	#partial switch v in g {
	case proc(frame_state: Widget_Frame_State, event: Widget_Event(Widget_Frame_State)) -> Gap_X:
		ui_state := to_ui_state(state)
		ui_event := to_ui_event(state)
		return resolve_child_gap_x(v(ui_state, ui_event), state, event)
	}

	return resolve_gap_x_value(g)
}

/*
Resolves a static Gap_Y union value to a pixel gap.

Does not evaluate proc-valued gaps; use resolve_child_gap_y for that.
*/
resolve_gap_y_value :: proc(g: Gap_Y) -> (gap: u16, ok: bool) {
	switch v in g {
	case struct{}:
		return 0, false
	case u16:
		return v, true
	case proc(frame_state: Widget_Frame_State, event: Widget_Event(Widget_Frame_State)) -> Gap_Y:
		return 0, false
	}

	return 0, false
}

/*
Resolves child gap_y from a union value, evaluating proc callbacks when present.
*/
resolve_child_gap_y :: proc(g: Gap_Y, state: ^$S, event: Widget_Event(S)) -> (gap: u16, ok: bool) {
	#partial switch v in g {
	case proc(frame_state: Widget_Frame_State, event: Widget_Event(Widget_Frame_State)) -> Gap_Y:
		ui_state := to_ui_state(state)
		ui_event := to_ui_event(state)
		return resolve_child_gap_y(v(ui_state, ui_event), state, event)
	}

	return resolve_gap_y_value(g)
}

/*
Resolves both axes of a justify position when both are explicit align values.
*/
resolve_align_pos :: proc(pos: Justify_Pos) -> (align: Justify_Pos, ok: bool) {
	x, x_ok := resolve_justify_x(pos.x)
	if !x_ok do return {}, false

	y, y_ok := resolve_justify_y(pos.y)
	if !y_ok do return {}, false

	return {x = x, y = y}, true
}

/*
Resolves whichever justify axes are set, leaving others at their defaults.
*/
resolve_justify_pos_partial :: proc(pos: Justify_Pos) -> (align: Justify_Pos, ok: bool) {
	x := false
	y := false

	if resolved_x, x_ok := resolve_justify_x(pos.x); x_ok {
		align.x = resolved_x
		x = true
	}

	if resolved_y, y_ok := resolve_justify_y(pos.y); y_ok {
		align.y = resolved_y
		y = true
	}

	return align, x || y
}

/*
Extracts a main-axis justify align from a Justify_X union when present.
*/
resolve_justify_x :: proc(x: Justify_X) -> (Justify_X, bool) {
	#partial switch v in x {
	case Justify_Align:
		return v, true
	}

	return Justify_Align.START, false
}

/*
Extracts a cross-axis justify align from a Justify_Y union when present.
*/
resolve_justify_y :: proc(y: Justify_Y) -> (Justify_Y, bool) {
	#partial switch v in y {
	case Justify_Align:
		return v, true
	}

	return Justify_Align.START, false
}

/*
Resolves a static Justify union value to a justify position.

Does not evaluate proc-valued justify; use resolve_align for that.
*/
resolve_justify_value :: proc(a: Justify) -> (align: Justify_Pos, ok: bool) {
	switch v in a {
	case struct{}:
		return {}, false
	case Justify_Pos:
		return resolve_align_pos(v)
	case Justify_Align:
		return resolve_align_pos({x = v, y = v})
	case proc(frame_state: Widget_Frame_State, event: Widget_Event(Widget_Frame_State)) -> Justify:
		return {}, false
	}

	return {}, false
}

/*
Resolves justify alignment from a union value, evaluating proc callbacks when present.
*/
resolve_align :: proc(
	a: Justify,
	state: ^$S,
	event: Widget_Event(S),
) -> (
	align: Justify_Pos,
	ok: bool,
) {
	#partial switch v in a {
	case proc(state: Widget_Frame_State, event: Widget_Event(Widget_Frame_State)) -> Justify:
		ui_state := to_ui_state(state)
		ui_event := to_ui_event(state)

		return resolve_align(v(ui_state, ui_event), state, event)
	}

	return resolve_justify_value(a)
}

/*
Resolves a static Widget_Direction union value to a layout direction.
*/
resolve_direction_value :: proc(d: Widget_Direction) -> (direction: Direction_Layout, ok: bool) {
	switch v in d {
	case struct{}:
		return .HORIZONTAL, false
	case Direction_Layout:
		return v, true
	case proc(
		     frame_state: Widget_Frame_State,
		     event: Widget_Event(Widget_Frame_State),
	     ) -> Widget_Direction:
		return .HORIZONTAL, false
	}
	return .HORIZONTAL, false
}

/*
Resolves layout direction from a union value, evaluating proc callbacks when present.
*/
resolve_direction :: proc(
	d: Widget_Direction,
	state: ^$S,
	event: Widget_Event(S),
) -> (
	direction: Widget_Direction,
	ok: bool,
) {
	#partial switch v in d {
	case proc(
		     state: Widget_Frame_State,
		     event: Widget_Event(Widget_Frame_State),
	     ) -> Widget_Direction:
		ui_state := to_ui_state(state)
		ui_event := to_ui_event(state)

		return resolve_direction(v(ui_state, ui_event), state, event)
	}

	if layout, layout_ok := resolve_direction_value(d); layout_ok do return layout, true

	return .HORIZONTAL, false
}

/*
Extracts a Justify_Align from a Justify_X union when present.
*/
justify_align_from_x :: proc(x: Justify_X) -> (Justify_Align, bool) {
	#partial switch v in x {
	case Justify_Align:
		return v, true
	}

	return .START, false
}

/*
Extracts a Justify_Align from a Justify_Y union when present.
*/
justify_align_from_y :: proc(y: Justify_Y) -> (Justify_Align, bool) {
	#partial switch v in y {
	case Justify_Align:
		return v, true
	}

	return .START, false
}

/*
Returns whether a justify align distributes free space between items.
*/
justify_align_is_space :: proc(align: Justify_Align) -> bool {
	return align == .SPACE_BETWEEN || align == .SPACE_AROUND || align == .SPACE_EVENLY
}

/*
Returns whether a justify align equalizes children to sibling content size.
*/
justify_align_is_content :: proc(align: Justify_Align) -> bool {
	return align == .MAX_CONTENT || align == .MIN_CONTENT
}

/*
Computes the leading offset for an item given free space and a justify align.
*/
justify_align_position_offset :: proc(free_space, size: f32, align: Justify_Align) -> f32 {
	switch align {
	case .START, .STRETCH, .MAX_CONTENT, .MIN_CONTENT, .TABLE_CELL:
		return 0
	case .CENTER:
		return max(0, (free_space - size) * 0.5)
	case .END:
		return max(0, free_space - size)
	case .SPACE_BETWEEN, .SPACE_AROUND, .SPACE_EVENLY:
		return 0
	}
	return 0
}

/*
Computes the main-axis position offset from a Justify_X axis value.
*/
justify_align_position_offset_x :: proc(free_space, size: f32, axis: Justify_X) -> f32 {
	if align, ok := justify_align_from_x(axis); ok {
		return justify_align_position_offset(free_space, size, align)
	}
	return 0
}

/*
Computes the cross-axis position offset from a Justify_Y axis value.
*/
justify_align_position_offset_y :: proc(free_space, size: f32, axis: Justify_Y) -> f32 {
	if align, ok := justify_align_from_y(axis); ok {
		return justify_align_position_offset(free_space, size, align)
	}
	return 0
}

/*
Returns whether a Justify_Y axis requests stretch along the cross axis.
*/
justify_axis_is_stretch_y :: proc(y: Justify_Y) -> bool {
	#partial switch v in y {
	case Justify_Align:
		return v == .STRETCH
	}

	return false
}

/*
Returns whether a Justify_X axis requests stretch along the cross axis.
*/
justify_axis_is_stretch_x :: proc(x: Justify_X) -> bool {
	#partial switch v in x {
	case Justify_Align:
		return v == .STRETCH
	}

	return false
}

/*
Detects a click when the pointer was pressed and released while hovered.

Tracks per-element pointer-down state across frames.
*/
consume_pointer_click :: proc(
	element_id: string,
	hovered, left_pressed, left_released: bool,
) -> (
	clicked: bool,
) {
	if w_ctx.element_pointer_down == nil {
		w_ctx.element_pointer_down = make(map[string]bool)
	}

	if hovered && left_pressed {
		w_ctx.element_pointer_down[element_id] = true
	}

	if left_released {
		clicked = w_ctx.element_pointer_down[element_id] && hovered
		w_ctx.element_pointer_down[element_id] = false
	}

	return
}


/*
Returns persistent shaped text storage for a widget id, creating it if needed.

Updates last_frame so the entry survives ui_end_frame pruning.
*/
widget_shaped :: proc(id: Widget_ID) -> ^Shaped_Text {
	ui_init()

	ui_id := UI_Id(hash.crc32(transmute([]u8)id))

	if _, ok := state.ui.widgets[ui_id]; !ok {
		state.ui.widgets[ui_id] = UI_Widget_Entry{}
	}

	entry := &state.ui.widgets[ui_id]
	entry.last_frame = state.ui.frame

	// Shaped_Text is heap-allocated so its address stays stable while it is
	// registered in the shape pool; the widgets map relocates its values on
	// rehash, which would otherwise dangle the pool's cached pointers.
	if entry.shaped == nil {
		entry.shaped = new(Shaped_Text)
		entry.shaped.pool_slot = INVALID_SHAPE_POOL_SLOT
	}

	return entry.shaped
}

/*
Releases and frees the heap-allocated shaped text held by a widget entry.

Safe to call when the entry has no shaped text allocated yet.
*/
widget_entry_release_shaped :: proc(entry: ^UI_Widget_Entry) {
	if entry == nil || entry.shaped == nil do return
	shaped_text_release(entry.shaped)
	free(entry.shaped)
	entry.shaped = nil
}

/*
Returns the per-widget cache entry for a layout id, creating it when missing.

Updates last_frame so the entry survives ui_end_frame pruning.
*/
widget_lifecycle_entry :: proc(layout_id: UI_Id) -> ^UI_Widget_Entry {
	ui_init()

	if _, ok := state.ui.widgets[layout_id]; !ok {
		state.ui.widgets[layout_id] = UI_Widget_Entry{}
	}

	entry := &state.ui.widgets[layout_id]
	entry.last_frame = state.ui.frame

	return entry
}

/*
Removes a widget lifecycle entry and releases any shaped text it holds.

Call when a widget leaves the layout tree so mount/unmount state resets on remount.
*/
widget_lifecycle_remove :: proc(layout_id: UI_Id) {
	if state.ui.widgets == nil do return
	if entry, ok := &state.ui.widgets[layout_id]; ok {
		widget_entry_release_shaped(entry)
		delete_key(&state.ui.widgets, layout_id)
	}
}

/*
Converts texture position values above 1 from percent (0–100) to normalized 0–1.
*/
@(private)
texture_pos_normalize :: proc(v: f32) -> f32 {
	if v > 1 do return v * 0.01
	return v
}

/*
Resolves a static Style_Texture_Pos union to anchor and offset values.

Does not evaluate proc-valued positions; use resolve_texture_pos for that.
*/
resolve_texture_pos_value :: proc(p: Style_Image_Pos) -> (pos: Resolved_Image_Pos, ok: bool) {
	switch v in p {
	case struct{}:
		return {0.5, 0.5, 0, 0}, true
	case Image_Pos:
		pos = {0.5, 0.5, 0, 0}
		if v.l > 0 && v.r == 0 {
			pos.x = 0
			pos.offset_x = v.l
		} else if v.r > 0 && v.l == 0 {
			pos.x = 1
			pos.offset_x = -v.r
		}
		if v.t > 0 && v.b == 0 {
			pos.y = 0
			pos.offset_y = v.t
		} else if v.b > 0 && v.t == 0 {
			pos.y = 1
			pos.offset_y = -v.b
		}
		return pos, true
	case Image_Pos_X_Y:
		return {texture_pos_normalize(v.x), texture_pos_normalize(v.y), 0, 0}, true
	case Resolved_Image_Pos:
		return v, true
	case proc(
		     frame_state: Widget_Frame_State,
		     event: Widget_Event(Widget_Frame_State),
	     ) -> Image_Pos:
		return {}, false
	}

	return {}, false
}

/*
Resolves texture anchor position from a union value, evaluating proc callbacks when present.
*/
resolve_texture_pos :: proc(
	p: Style_Image_Pos,
	state: ^$S,
	event: Widget_Event(S),
) -> (
	pos: Resolved_Image_Pos,
	ok: bool,
) {
	#partial switch v in p {
	case proc(state: Widget_Frame_State, event: Widget_Event(Widget_Frame_State)) -> Image_Pos:
		ui_state := to_ui_state(state)
		ui_event := to_ui_event(state)
		return resolve_texture_pos_value(Style_Image_Pos(v(ui_state, ui_event)))
	}

	return resolve_texture_pos_value(p)
}

/*
Resolves a static Style_Texture_Fit union to a texture fit mode.

Does not evaluate proc-valued fit; use resolve_texture_fit for that.
*/
resolve_texture_fit_value :: proc(f: Style_Image_Fit) -> (fit: Image_Fit, ok: bool) {
	switch v in f {
	case struct{}:
		return {}, false
	case Image_Fit:
		return v, true
	case proc(
		     frame_state: Widget_Frame_State,
		     event: Widget_Event(Widget_Frame_State),
	     ) -> Image_Fit:
		return {}, false
	}

	return {}, false
}

/*
Resolves texture fit mode from a union value, evaluating proc callbacks when present.
*/
resolve_texture_fit :: proc(
	f: Style_Image_Fit,
	state: ^$S,
	event: Widget_Event(S),
) -> (
	fit: Image_Fit,
	ok: bool,
) {
	#partial switch v in f {
	case proc(state: Widget_Frame_State, event: Widget_Event(Widget_Frame_State)) -> Image_Fit:
		ui_state := to_ui_state(state)
		ui_event := to_ui_event(state)
		return resolve_texture_fit_value(Style_Image_Fit(v(ui_state, ui_event)))
	}

	return resolve_texture_fit_value(f)
}

/*
Computes source and destination rects for a texture fit mode and anchor position.

Handles fill, contain, cover, none, and scale-down fitting.
*/
texture_fit_rects :: proc(
	src, container: Rect,
	fit: Image_Fit,
	pos: Resolved_Image_Pos,
) -> (
	out_src: Rect,
	out_dst: Rect,
) {
	out_src = src
	out_dst = container

	iw := src.w
	ih := src.h
	cw := container.w
	ch := container.h
	if iw <= 0 || ih <= 0 || cw <= 0 || ch <= 0 do return

	px := pos.x
	py := pos.y
	ox_off := pos.offset_x
	oy_off := pos.offset_y

	switch fit {
	case .FILL:
		return
	case .CONTAIN:
		scale := min(cw / iw, ch / ih)
		dw := iw * scale
		dh := ih * scale
		ox := (cw - dw) * px + ox_off
		oy := (ch - dh) * py + oy_off
		out_dst = Rect{container.x + ox, container.y + oy, dw, dh}
	case .COVER:
		scale := max(cw / iw, ch / ih)
		sw := cw / scale
		sh := ch / scale
		excess_w := iw - sw
		excess_h := ih - sh
		sx := src.x + excess_w * px - ox_off / scale
		sy := src.y + excess_h * py - oy_off / scale
		out_src = Rect{sx, sy, sw, sh}
	case .NONE:
		ox := (cw - iw) * px + ox_off
		oy := (ch - ih) * py + oy_off
		out_dst = Rect{container.x + ox, container.y + oy, iw, ih}
	case .SCALE_DOWN:
		if iw <= cw && ih <= ch {
			ox := (cw - iw) * px + ox_off
			oy := (ch - ih) * py + oy_off
			out_dst = Rect{container.x + ox, container.y + oy, iw, ih}
		} else {
			scale := min(cw / iw, ch / ih)
			dw := iw * scale
			dh := ih * scale
			ox := (cw - dw) * px + ox_off
			oy := (ch - dh) * py + oy_off
			out_dst = Rect{container.x + ox, container.y + oy, dw, dh}
		}
	}

	return
}

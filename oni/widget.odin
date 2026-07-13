package oni

import "core:fmt"
import "core:strings"


AUTO_ELEMENT_ID_PREFIX :: "__auto_element__"

/*
Returns whether a widget identity string was allocated by the engine (auto id).

User-facing config.id values are borrowed and must not be freed.
*/
@(private)
widget_key_is_owned :: proc(key: string) -> bool {
	return strings.has_prefix(key, AUTO_ELEMENT_ID_PREFIX)
}

/*
Returns a key safe to store across frames.

Auto-generated ids are cloned off the temp allocator; user ids are returned as-is.
*/
@(private)
widget_retain_key :: proc(key: string) -> string {
	if key == "" || !widget_key_is_owned(key) do return key
	return strings.clone(key)
}

/*
Frees a key previously retained for cross-frame storage.
*/
@(private)
widget_release_key :: proc(key: string) {
	if widget_key_is_owned(key) {
		delete(key)
	}
}

/*
Sets keyboard focus, owning auto-generated ids across temp allocator wipes.
*/
widget_set_focused_id :: proc(id: Widget_ID) {
	if w_ctx == nil do return
	if w_ctx.focused_id_owned {
		widget_release_key(w_ctx.focused_id)
	}
	if id == "" {
		w_ctx.focused_id = {}
		w_ctx.focused_id_owned = false
		return
	}
	w_ctx.focused_id = widget_retain_key(id)
	w_ctx.focused_id_owned = widget_key_is_owned(w_ctx.focused_id)
}

/*
Records the auto-focus target so it is not re-applied every frame.
*/
widget_set_auto_focused_id :: proc(id: Widget_ID) {
	if w_ctx == nil do return
	if w_ctx.auto_focused_id_owned {
		widget_release_key(w_ctx.auto_focused_id)
	}
	if id == "" {
		w_ctx.auto_focused_id = {}
		w_ctx.auto_focused_id_owned = false
		return
	}
	w_ctx.auto_focused_id = widget_retain_key(id)
	w_ctx.auto_focused_id_owned = widget_key_is_owned(w_ctx.auto_focused_id)
}

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

@(private)
widget_map_delete_key :: proc(m: ^map[string]bool, key: string) {
	delete_key(m, key)
	widget_release_key(key)
}

@(private)
widget_map_clear_owned :: proc(m: ^map[string]bool) {
	if m == nil || m^ == nil do return
	for key in m^ {
		widget_release_key(key)
	}
	delete(m^)
	m^ = nil
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
			widget_map_delete_key(&w_ctx.element_was_hovered, key)
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
			widget_map_delete_key(&w_ctx.element_pointer_down, key)
		}
	}
}

/*
Releases heap-owned widget input maps.

Call during UI shutdown.
*/
widget_ctx_shutdown :: proc() {
	if w_ctx == nil do return

	if w_ctx.tab_order != nil {
		delete(w_ctx.tab_order)
		w_ctx.tab_order = nil
	}
	if w_ctx.static_ids != nil {
		delete(w_ctx.static_ids)
		w_ctx.static_ids = nil
	}
	widget_map_clear_owned(&w_ctx.element_was_hovered)
	widget_map_clear_owned(&w_ctx.element_pointer_down)

	if w_ctx.focused_id_owned {
		widget_release_key(w_ctx.focused_id)
	}
	if w_ctx.auto_focused_id_owned {
		widget_release_key(w_ctx.auto_focused_id)
	}
	if widget_key_is_owned(w_ctx.tab_focus_previous_id) {
		widget_release_key(w_ctx.tab_focus_previous_id)
	}

	w_ctx^ = {}
}

/*
Clears focus when the focused element is no longer in the tab order.
*/
widget_prune_focus :: proc() {
	if w_ctx.focused_id == "" do return

	for id in w_ctx.tab_order {
		if id == w_ctx.focused_id do return
	}

	widget_set_focused_id("")
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

	// Keep previous_id alive for same-frame lost-focus checks; release at begin_frame.
	w_ctx.focused_id_owned = false
	widget_set_focused_id(next_id)
	if widget_key_is_owned(w_ctx.tab_focus_previous_id) {
		widget_release_key(w_ctx.tab_focus_previous_id)
	}
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
Allocated on the temp allocator; retain with widget_retain_key before storing
across free_all(temp).
*/
auto_element_id :: proc() -> Widget_ID {
	idx := w_ctx.auto_element_index
	w_ctx.auto_element_index += 1

	return fmt.tprintf("{0}{1}", AUTO_ELEMENT_ID_PREFIX, idx)
}


/*
Maps a stable user id to the runtime element key used this frame.

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
Returns the runtime identity for an element.

When id is non-empty it is used directly (stable across frames). Otherwise an
auto id is allocated for this frame only.
*/
element_key :: proc(id: string) -> string {
	if id != "" {
		register_static_id(id, id)
		return id
	}
	return auto_element_id()
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
	widget_ctx_sync()

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
Returns whether this layout id is hovered in the CSS sense.

When a paint-list hit is resolved, the topmost hit and all of its layout
ancestors are hovered. Otherwise falls back to geometry (and hit_skip).
*/
pointer_hits :: proc(layout_id: UI_Id, rect: Rect, space: Draw_Space) -> bool {
	if w_ctx.pointer_hit_valid {
		return pointer_hover_contains(layout_id)
	}
	if ui_layout_hit_skip(layout_id) do return false
	return pointer_over(rect, space)
}

/*
Returns whether this layout id is the topmost pointer hit target.
*/
pointer_is_target :: proc(layout_id: UI_Id) -> bool {
	return w_ctx.pointer_hit_valid && layout_id == w_ctx.pointer_hit_ui_id
}

@(private)
pointer_hover_contains :: proc(layout_id: UI_Id) -> bool {
	if !w_ctx.pointer_hit_valid do return false
	if layout_id == w_ctx.pointer_hit_ui_id do return true
	return layout_is_ancestor_of(layout_id, w_ctx.pointer_hit_ui_id)
}

/*
Stops remaining ancestor pointer-event handlers for the rest of this frame.

IMGUI-style latch: call from a widget handler (e.g. on_click) to prevent
parents that dispatch after Children from receiving bubbled pointer events.
Enter/leave and keyboard handlers are unaffected.
*/
stop_propagation :: proc() {
	if w_ctx == nil do return
	w_ctx.pointer_propagation_stopped = true
}

/*
Sets the batch draw stack index for subsequent geometry.
*/
draw_set_stack_index :: proc(stack_index: u32) {
	batch_set_stack_index(stack_index)
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
	return {frame_state = to_ui_state(frame_state)}
}

/*
Detects hover enter/leave transitions and updates per-element hover memory.
*/
consume_hover_transition :: proc(element_id: string, hovered: bool) -> (entered, left: bool) {
	if w_ctx.element_was_hovered == nil {
		w_ctx.element_was_hovered = make(map[string]bool)
	}

	was_hovered, exists := w_ctx.element_was_hovered[element_id]
	entered = hovered && !was_hovered
	left = was_hovered && !hovered
	if !exists {
		w_ctx.element_was_hovered[widget_retain_key(element_id)] = hovered
	} else {
		w_ctx.element_was_hovered[element_id] = hovered
	}

	return
}

/*
Builds uniform or axis-pair padding from x and optional y values.

When y is zero, all sides use x.
*/
resolve_padding_xy :: proc(x, y: f32) -> Pd_px {
	if y == 0 do return {t = x, b = x, l = x, r = x}

	return {t = y, b = y, l = x, r = x}
}

/*
Resolves an F32_I padding/border field against a parent pixel value.
*/
@(private)
resolve_side_f32_i :: proc(v: F32_I, parent: f32) -> f32 {
	return f32_i_resolve(v, parent)
}

/*
Resolves a padding struct into concrete side values.

Handles preset sizes and explicit per-side or axis shorthand.
Per-field `.INHERIT` takes the matching parent side.
*/
resolve_padding_struct :: proc(s: Pd_struct, parent: Pd_px = {}) -> (padding: Pd_px, ok: bool) {
	switch {
	case s.sm:
		v := PADDING_SM
		return Pd_px{t = v, b = v, l = v, r = v}, true
	case s.md:
		v := PADDING_MD
		return Pd_px{t = v, b = v, l = v, r = v}, true
	case s.lg:
		v := PADDING_LG
		return Pd_px{t = v, b = v, l = v, r = v}, true
	case s.xl:
		v := PADDING_XL
		return Pd_px{t = v, b = v, l = v, r = v}, true
	}

	any_side :=
		f32_i_is_set(s.l) ||
		f32_i_is_set(s.r) ||
		f32_i_is_set(s.t) ||
		f32_i_is_set(s.b)
	if any_side {
		return Pd_px {
				t = resolve_side_f32_i(s.t, parent.t),
				b = resolve_side_f32_i(s.b, parent.b),
				l = resolve_side_f32_i(s.l, parent.l),
				r = resolve_side_f32_i(s.r, parent.r),
			},
			true
	}
	if f32_i_is_set(s.x) || f32_i_is_set(s.y) {
		return resolve_padding_xy(
				resolve_side_f32_i(s.x, parent.l),
				resolve_side_f32_i(s.y, parent.t),
			),
			true
	}

	return {}, false
}

/*
Resolves a static Padding union value into concrete side insets.

Does not evaluate proc-valued padding; use resolve_padding for that.
*/
resolve_padding_value :: proc(p: Padding, parent: Pd_px = {}) -> (padding: Pd_px, ok: bool) {
	switch v in p {
	case Inherit:
		return parent, true
	case struct{}:
		return {}, false
	case f32:
		if v == 0 do return {}, false
		return {v, v, v, v}, true
	case Pd_pos:
		if !f32_i_is_set(v.x) && !f32_i_is_set(v.y) do return {}, false
		return resolve_padding_xy(
				resolve_side_f32_i(v.x, parent.l),
				resolve_side_f32_i(v.y, parent.t),
			),
			true
	case Pd_struct:
		return resolve_padding_struct(v, parent)
	case Pd:
		return Pd_px {
				t = resolve_side_f32_i(v.t, parent.t),
				b = resolve_side_f32_i(v.b, parent.b),
				l = resolve_side_f32_i(v.l, parent.l),
				r = resolve_side_f32_i(v.r, parent.r),
			},
			true
	case proc(frame_state: Widget_Frame_State, event: Widget_Event(Widget_Frame_State)) -> Padding:
		return {}, false
	}

	return {}, false
}

/*
Returns concrete parent padding from the current style stack.
*/
@(private)
padding_parent_px :: proc() -> Pd_px {
	if len(state.ui.style_stack) == 0 do return {}
	padding, ok := resolve_padding_value(ui_style_current().padding)
	if ok do return padding
	return {}
}

/*
Resolves a radius struct into concrete per-corner pixel values.

Handles presets, shorthand axes, and explicit corner overrides.
Per-field `.INHERIT` takes the matching parent corner.
*/
resolve_radius_struct :: proc(
	s: Radius_struct,
	parent: Radius_px = {},
) -> (
	radius: Radius_px,
	ok: bool,
) {
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

	any_corner :=
		f32_i_is_set(s.tl) ||
		f32_i_is_set(s.tr) ||
		f32_i_is_set(s.bl) ||
		f32_i_is_set(s.br)
	if any_corner {
		return {
				tl = resolve_side_f32_i(s.tl, parent.tl),
				tr = resolve_side_f32_i(s.tr, parent.tr),
				bl = resolve_side_f32_i(s.bl, parent.bl),
				br = resolve_side_f32_i(s.br, parent.br),
			},
			true
	}

	tl := resolve_side_f32_i(s.tl, parent.tl)
	tr := resolve_side_f32_i(s.tr, parent.tr)
	bl := resolve_side_f32_i(s.bl, parent.bl)
	br := resolve_side_f32_i(s.br, parent.br)

	if f32_i_is_set(s.t) {
		tv := resolve_side_f32_i(s.t, parent.tl)
		if !f32_i_is_set(s.tl) do tl = tv
		if !f32_i_is_set(s.tr) do tr = tv
	}
	if f32_i_is_set(s.b) {
		bv := resolve_side_f32_i(s.b, parent.bl)
		if !f32_i_is_set(s.bl) do bl = bv
		if !f32_i_is_set(s.br) do br = bv
	}
	if f32_i_is_set(s.l) {
		lv := resolve_side_f32_i(s.l, parent.tl)
		if !f32_i_is_set(s.tl) do tl = lv
		if !f32_i_is_set(s.bl) do bl = lv
	}
	if f32_i_is_set(s.r) {
		rv := resolve_side_f32_i(s.r, parent.tr)
		if !f32_i_is_set(s.tr) do tr = rv
		if !f32_i_is_set(s.br) do br = rv
	}
	if tl != 0 || tr != 0 || bl != 0 || br != 0 || any_corner {
		return {tl, tr, bl, br}, true
	}
	if f32_i_is_set(s.x) || f32_i_is_set(s.y) {
		x := resolve_side_f32_i(s.x, parent.tl)
		y := resolve_side_f32_i(s.y, parent.bl)
		return {x, x, y, y}, true
	}

	return {}, false
}

/*
Resolves Radius_corners with per-corner `.INHERIT` against parent pixels.
*/
resolve_radius_corners :: proc(
	c: Radius_corners,
	parent: Radius_px = {},
) -> (
	radius: Radius_px,
	ok: bool,
) {
	any :=
		f32_i_is_set(c.tl) ||
		f32_i_is_set(c.tr) ||
		f32_i_is_set(c.bl) ||
		f32_i_is_set(c.br)
	if !any do return {}, false
	return {
			tl = resolve_side_f32_i(c.tl, parent.tl),
			tr = resolve_side_f32_i(c.tr, parent.tr),
			bl = resolve_side_f32_i(c.bl, parent.bl),
			br = resolve_side_f32_i(c.br, parent.br),
		},
		true
}

/*
Returns concrete parent radius from the current style stack.
*/
@(private)
radius_parent_px :: proc() -> Radius_px {
	if len(state.ui.style_stack) == 0 do return {}
	radius, ok := resolve_radius_value(ui_style_current().radius)
	if ok do return radius
	return {}
}

/*
Resolves a static Radius union value into concrete per-corner radii.

Does not evaluate proc-valued radii; use resolve_radius for that.
*/
resolve_radius_value :: proc(r: Radius, parent: Radius_px = {}) -> (radius: Radius_px, ok: bool) {
	switch v in r {
	case Inherit:
		return parent, true
	case struct{}:
		return {}, false
	case f32:
		if v == 0 do return {}, false
		return resolve_radius_struct({t = v, b = v, l = v, r = v}, parent)
	case Radius_struct:
		return resolve_radius_struct(v, parent)
	case Radius_corners:
		return resolve_radius_corners(v, parent)
	case proc(frame_state: Widget_Frame_State, event: Widget_Event(Widget_Frame_State)) -> Radius:
		return {}, false
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
	radius: Radius_px,
	ok: bool,
) {
	ui_state := to_ui_state(state)
	ui_event := to_ui_event(state)
	p := radius_parent_px()
	switch v in r {
	case Inherit:
		return p, true
	case struct{}:
		return {}, false
	case f32:
		if v == 0 do return {}, false
		return resolve_radius_struct({t = v, b = v, l = v, r = v}, p)
	case Radius_struct:
		return resolve_radius_struct(v, p)
	case Radius_corners:
		return resolve_radius_corners(v, p)
	case proc(frame_state: Widget_Frame_State, event: Widget_Event(Widget_Frame_State)) -> Radius:
		return resolve_radius(v(ui_state, ui_event), state, event)
	}

	return {}, false
}

/*
Builds Radius_corners author value from resolved pixels (for style stack storage).
*/
radius_px_to_corners :: proc(r: Radius_px) -> Radius_corners {
	return {tl = r.tl, tr = r.tr, bl = r.bl, br = r.br}
}

/*
Resolves a border struct into per-side widths.

Handles preset sizes and explicit per-side values.
Per-field `.INHERIT` takes the matching parent side.
*/
resolve_border_struct :: proc(s: Bd_struct, parent: Bd_px = {}) -> (width: Bd_px, ok: bool) {
	switch {
	case s.sm:
		v := BORDER_SM
		return Bd_px{t = v, b = v, l = v, r = v}, true
	case s.md:
		v := BORDER_MD
		return Bd_px{t = v, b = v, l = v, r = v}, true
	case s.lg:
		v := BORDER_LG
		return Bd_px{t = v, b = v, l = v, r = v}, true
	case s.xl:
		v := BORDER_XL
		return Bd_px{t = v, b = v, l = v, r = v}, true
	}

	any :=
		f32_i_is_set(s.t) || f32_i_is_set(s.b) || f32_i_is_set(s.l) || f32_i_is_set(s.r)
	if !any do return {}, false
	return Bd_px {
			t = resolve_side_f32_i(s.t, parent.t),
			b = resolve_side_f32_i(s.b, parent.b),
			l = resolve_side_f32_i(s.l, parent.l),
			r = resolve_side_f32_i(s.r, parent.r),
		},
		true
}

/*
Resolves a static Border union value into per-side widths.

Does not evaluate proc-valued borders; use resolve_border for that.
*/
resolve_border_value :: proc(b: Border, parent: Bd_px = {}) -> (border: Bd_px, ok: bool) {
	switch v in b {
	case Inherit:
		return parent, true
	case struct{}:
		return {}, false
	case f32:
		if v == 0 do return {}, false
		return {v, v, v, v}, true
	case Bd_struct:
		return resolve_border_struct(v, parent)
	case Bd:
		return Bd_px {
				t = resolve_side_f32_i(v.t, parent.t),
				b = resolve_side_f32_i(v.b, parent.b),
				l = resolve_side_f32_i(v.l, parent.l),
				r = resolve_side_f32_i(v.r, parent.r),
			},
			true
	case proc(frame_state: Widget_Frame_State, event: Widget_Event(Widget_Frame_State)) -> Border:
		return {}, false
	}

	return {}, false
}

/*
Returns concrete parent border from the current style stack.
*/
@(private)
border_parent_px :: proc() -> Bd_px {
	if len(state.ui.style_stack) == 0 do return {}
	border, ok := resolve_border_value(ui_style_current().border)
	if ok do return border
	return {}
}

/*
Resolves border width from a union value, evaluating proc callbacks when present.
*/
resolve_border :: proc(
	b: Border,
	state: ^$S,
	event: Widget_Event(S),
) -> (
	border: Bd_px,
	ok: bool,
) {
	#partial switch v in b {
	case proc(state: Widget_Frame_State, event: Widget_Event(Widget_Frame_State)) -> Border:
		ui_state := to_ui_state(state)
		ui_event := to_ui_event(state)
		return resolve_border(v(ui_state, ui_event), state, event)
	}

	return resolve_border_value(b, border_parent_px())
}

resolve_padding :: proc(
	p: Padding,
	state: ^$S,
	event: Widget_Event(S),
) -> (
	padding: Pd_px,
	ok: bool,
) {
	#partial switch v in p {
	case proc(state: Widget_Frame_State, event: Widget_Event(Widget_Frame_State)) -> Padding:
		ui_state := to_ui_state(state)
		ui_event := to_ui_event(state)
		return resolve_padding(v(ui_state, ui_event), state, event)
	}

	return resolve_padding_value(p, padding_parent_px())
}

/*
Builds author Bd from resolved pixels (for style stack storage).
*/
border_px_to_bd :: proc(b: Bd_px) -> Bd {
	return {t = b.t, b = b.b, l = b.l, r = b.r}
}

/*
Builds author Pd from resolved pixels (for style stack storage).
*/
padding_px_to_pd :: proc(p: Pd_px) -> Pd {
	return {t = p.t, b = p.b, l = p.l, r = p.r}
}

/*
Resolves a static Gap_X union value to a pixel gap.

Does not evaluate proc-valued gaps; use resolve_child_gap_x for that.
*/
resolve_gap_x_value :: proc(g: Gap_X) -> (gap: u16, ok: bool) {
	switch v in g {
	case Inherit:
		return 0, false
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
	case Inherit:
		return 0, false
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
	case Inherit:
		return {}, false
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
	case Inherit:
		return .HORIZONTAL, false
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
		if _, exists := w_ctx.element_pointer_down[element_id]; !exists {
			w_ctx.element_pointer_down[widget_retain_key(element_id)] = true
		} else {
			w_ctx.element_pointer_down[element_id] = true
		}
	}

	if left_released {
		clicked = w_ctx.element_pointer_down[element_id] && hovered
		if _, exists := w_ctx.element_pointer_down[element_id]; !exists {
			w_ctx.element_pointer_down[widget_retain_key(element_id)] = false
		} else {
			w_ctx.element_pointer_down[element_id] = false
		}
	}

	return
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
Removes a widget lifecycle entry.

Call when a widget leaves the layout tree so mount/unmount state resets on remount.
*/
widget_lifecycle_remove :: proc(layout_id: UI_Id) {
	if state.ui.widgets == nil do return
	delete_key(&state.ui.widgets, layout_id)
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
resolve_texture_pos_value :: proc(p: Style_Texture_Pos) -> (pos: Resolved_Texture_Pos, ok: bool) {
	switch v in p {
	case Inherit:
		return {}, false
	case struct{}:
		return {0.5, 0.5, 0, 0}, true
	case Texture_Pos:
		pos = {0.5, 0.5, 0, 0}
		l := f32_i_px(v.l)
		r := f32_i_px(v.r)
		t := f32_i_px(v.t)
		b := f32_i_px(v.b)
		if l > 0 && r == 0 {
			pos.x = 0
			pos.offset_x = l
		} else if r > 0 && l == 0 {
			pos.x = 1
			pos.offset_x = -r
		}
		if t > 0 && b == 0 {
			pos.y = 0
			pos.offset_y = t
		} else if b > 0 && t == 0 {
			pos.y = 1
			pos.offset_y = -b
		}
		return pos, true
	case Texture_Pos_X_Y:
		return {
				texture_pos_normalize(f32_i_px(v.x)),
				texture_pos_normalize(f32_i_px(v.y)),
				0,
				0,
			},
			true
	case Resolved_Texture_Pos:
		return v, true
	case proc(
		     frame_state: Widget_Frame_State,
		     event: Widget_Event(Widget_Frame_State),
	     ) -> Texture_Pos:
		return {}, false
	}

	return {}, false
}

/*
Resolves texture anchor position from a union value, evaluating proc callbacks when present.
*/
resolve_texture_pos :: proc(
	p: Style_Texture_Pos,
	state: ^$S,
	event: Widget_Event(S),
) -> (
	pos: Resolved_Texture_Pos,
	ok: bool,
) {
	#partial switch v in p {
	case proc(state: Widget_Frame_State, event: Widget_Event(Widget_Frame_State)) -> Texture_Pos:
		ui_state := to_ui_state(state)
		ui_event := to_ui_event(state)
		return resolve_texture_pos_value(Style_Texture_Pos(v(ui_state, ui_event)))
	}

	return resolve_texture_pos_value(p)
}

/*
Resolves a static Style_Texture_Fit union to a texture fit mode.

Does not evaluate proc-valued fit; use resolve_texture_fit for that.
*/
resolve_texture_fit_value :: proc(f: Style_Texture_Fit) -> (fit: Texture_Fit, ok: bool) {
	switch v in f {
	case Inherit:
		return {}, false
	case struct{}:
		return {}, false
	case Texture_Fit:
		return v, true
	case proc(
		     frame_state: Widget_Frame_State,
		     event: Widget_Event(Widget_Frame_State),
	     ) -> Texture_Fit:
		return {}, false
	}

	return {}, false
}

/*
Resolves texture fit mode from a union value, evaluating proc callbacks when present.
*/
resolve_texture_fit :: proc(
	f: Style_Texture_Fit,
	state: ^$S,
	event: Widget_Event(S),
) -> (
	fit: Texture_Fit,
	ok: bool,
) {
	#partial switch v in f {
	case proc(state: Widget_Frame_State, event: Widget_Event(Widget_Frame_State)) -> Texture_Fit:
		ui_state := to_ui_state(state)
		ui_event := to_ui_event(state)
		return resolve_texture_fit_value(Style_Texture_Fit(v(ui_state, ui_event)))
	}

	return resolve_texture_fit_value(f)
}

/*
Computes source and destination rects for a texture fit mode and anchor position.

Handles fill, contain, cover, none, and scale-down fitting.
*/
texture_fit_rects :: proc(
	src, container: Rect,
	fit: Texture_Fit,
	pos: Resolved_Texture_Pos,
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

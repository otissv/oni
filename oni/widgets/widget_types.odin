package widgets

import oni ".."
import "core:fmt"
import sdl "vendor:sdl3"


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
	keys:                 [oni.KEY_COUNT]Widget_Mouse_Key_State,
	element_was_hovered:  map[string]bool,
	element_pointer_down: map[string]bool,
}

Widget_Merged_State :: struct($S: typeid, $C: typeid) {
	using state: S,
	config:      C,
}

w_ctx: Widget_Context


merge_state_config :: proc(state: $S, config: $C) -> Widget_Merged_State(S, C) {
	return {state = state, config = config}
}

merge_state_event :: proc(
	state: $S,
	config: $C,
	mouse_button: u8 = 0,
	key: oni.Scancode = oni.Scancode(0),
) -> oni.Widget_Event(Widget_Merged_State(S, C)) {
	return {state = merge_state_config(state, config), mouse_button = mouse_button, key = key}
}

// auto_element_id :: proc() -> Widget_ID {
// 	idx := w_ctx.auto_element_index
// 	w_ctx.auto_element_index += 1

// 	// parent-scoped hashing so auto ids stay stable without
// 	// allocating a fresh UUID string for every element on every frame.
// 	return u64(auto_element_index)
// }

auto_element_id :: proc() -> Widget_ID {
	idx := w_ctx.auto_element_index
	w_ctx.auto_element_index += 1

	id := fmt.tprintf("__auto_element__{0}", idx)

	return id
}


register_static_id :: proc(id: string, static_id: string) {
	if id == "" do return

	if w_ctx.static_ids == nil {
		w_ctx.static_ids = make(map[string]Widget_ID)
	}

	w_ctx.static_ids[id] = static_id
}

element_key :: proc(id: string) -> string {
	key := auto_element_id()
	register_static_id(id, key)
	return key
}

GetElementById :: proc(id: string) -> (static_id: string, ok: bool) {
	if w_ctx.static_ids == nil do return {}, false
	static_id, ok = w_ctx.static_ids[id]
	return
}

FocusElement :: proc(id: string) -> bool {
	element_id, ok := GetElementById(id)
	if !ok do return false

	w_ctx.focused_id = element_id
	return true
}

clear_button_transients :: proc(button: ^Widget_Mouse_Button_State) {
	button.pressed = false
	button.released = false
}

clear_key_transients :: proc(key: ^Widget_Mouse_Key_State) {
	key.pressed = false
	key.released = false
}

sync_mouse_state :: proc() {
	x, y: f32
	buttons := sdl.GetMouseState(&x, &y)

	w_ctx.mouse_x = x
	w_ctx.mouse_y = y
	w_ctx.left_mouse.down = .LEFT in buttons
	w_ctx.right_mouse.down = .RIGHT in buttons
	w_ctx.middle_mouse.down = .MIDDLE in buttons
}

update_mouse_button :: proc(button: ^Widget_Mouse_Button_State, is_down: bool) {
	if is_down {
		if !button.down do button.pressed = true
		button.down = true
	} else {
		if button.down do button.released = true
		button.down = false
	}
}

update_key_state :: proc(key: ^Widget_Mouse_Key_State, is_down, is_repeat: bool) {
	if is_down {
		if !key.down && !is_repeat do key.pressed = true
		key.down = true
	} else {
		if key.down do key.released = true
		key.down = false
	}
}

Shutdown :: proc() {
	if w_ctx.static_ids != nil {
		delete(w_ctx.static_ids)
	}
	if w_ctx.element_was_hovered != nil {
		delete(w_ctx.element_was_hovered)
	}
	if w_ctx.element_pointer_down != nil {
		delete(w_ctx.element_pointer_down)
	}
}

BeginFrame :: proc() {
	w_ctx.auto_element_index = 0

	if w_ctx.static_ids != nil {
		clear(&w_ctx.static_ids)
	}

	w_ctx.mouse_moved = false

	clear_button_transients(&w_ctx.left_mouse)
	clear_button_transients(&w_ctx.right_mouse)
	clear_button_transients(&w_ctx.middle_mouse)

	for &key in w_ctx.keys {
		clear_key_transients(&key)
	}

	sync_mouse_state()
}

ProcessEvent :: proc(event: ^sdl.Event) {
	#partial switch event.type {
	case .MOUSE_MOTION:
		w_ctx.mouse_moved = true
		w_ctx.mouse_x = event.motion.x
		w_ctx.mouse_y = event.motion.y

	case .MOUSE_BUTTON_DOWN:
		w_ctx.mouse_x = event.button.x
		w_ctx.mouse_y = event.button.y

		switch event.button.button {
		case sdl.BUTTON_LEFT:
			update_mouse_button(&w_ctx.left_mouse, true)
		case sdl.BUTTON_RIGHT:
			update_mouse_button(&w_ctx.right_mouse, true)
		case sdl.BUTTON_MIDDLE:
			update_mouse_button(&w_ctx.middle_mouse, true)
		}

	case .MOUSE_BUTTON_UP:
		w_ctx.mouse_x = event.button.x
		w_ctx.mouse_y = event.button.y

		switch event.button.button {
		case sdl.BUTTON_LEFT:
			update_mouse_button(&w_ctx.left_mouse, false)
		case sdl.BUTTON_RIGHT:
			update_mouse_button(&w_ctx.right_mouse, false)
		case sdl.BUTTON_MIDDLE:
			update_mouse_button(&w_ctx.middle_mouse, false)
		}

	case .KEY_DOWN:
		idx := int(event.key.scancode)
		if idx >= 0 && idx < oni.KEY_COUNT {
			update_key_state(&w_ctx.keys[idx], true, event.key.repeat)
		}

	case .KEY_UP:
		idx := int(event.key.scancode)
		if idx >= 0 && idx < oni.KEY_COUNT {
			update_key_state(&w_ctx.keys[idx], false, false)
		}

	case .WINDOW_FOCUS_LOST:
		for &key in w_ctx.keys {
			key.down = false
		}
	}
}

SetPointerState :: proc(position: [2]f32, pointerDown: bool)

SyncPointer :: proc() {
	SetPointerState({w_ctx.mouse_x, w_ctx.mouse_y}, w_ctx.left_mouse.down)
}

to_ui_state :: proc(state: ^$S) -> oni.Widget_State {
	return (^oni.Widget_State)(cast(rawptr)state)^
}

to_ui_event :: proc(state: ^$S) -> oni.Widget_Event(oni.Widget_State) {
	return {state = to_ui_state(state)}
}

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

resolve_padding_struct :: proc(s: oni.Pd_struct) -> (padding: oni.Pd, ok: bool) {
	switch {
	case s.sm:
		v := oni.PADDING_SM
		return oni.Pd{t = v, b = v, l = v, r = v}, true
	case s.md:
		v := oni.PADDING_MD
		return oni.Pd{t = v, b = v, l = v, r = v}, true
	case s.lg:
		v := oni.PADDING_LG
		return oni.Pd{t = v, b = v, l = v, r = v}, true
	case s.xl:
		v := oni.PADDING_XL
		return oni.Pd{t = v, b = v, l = v, r = v}, true
	}

	if s.l != 0 || s.r != 0 || s.t != 0 || s.b != 0 {
		return {s.l, s.r, s.t, s.b}, true
	}
	if s.x != 0 || s.y != 0 {
		return {s.x, s.x, s.y, s.y}, true
	}

	return {}, false
}

resolve_padding :: proc(
	p: oni.Padding,
	state: ^$S,
	event: oni.Widget_Event(S),
) -> (
	padding: oni.Pd,
	ok: bool,
) {
	ui_state := to_ui_state(state)
	ui_event := to_ui_event(state)
	switch v in p {
	case struct{}:
		return {}, false
	case f32:
		if v == 0 do return {}, false
		return {v, v, v, v}, true
	case oni.Pd_pos:
		if v.x == 0 && v.y == 0 do return {}, false
		return {v.x, v.x, v.y, v.y}, true
	case oni.Pd_struct:
		return resolve_padding_struct(v)
	case oni.Pd:
		return v, true
	case proc(state: oni.Widget_State, event: oni.Widget_Event(oni.Widget_State)) -> oni.Padding:
		return resolve_padding(v(ui_state, ui_event), state, event)
	}
	return {}, false
}

resolve_radius_struct :: proc(s: oni.Radius_struct) -> (radius: oni.Radius_corners, ok: bool) {
	switch {
	case s.sm:
		v := oni.RADIUS_SM
		return {tl = v, tr = v, bl = v, br = v}, true
	case s.md:
		v := oni.RADIUS_MD
		return {tl = v, tr = v, bl = v, br = v}, true
	case s.lg:
		v := oni.RADIUS_LG
		return {tl = v, tr = v, bl = v, br = v}, true
	case s.xl:
		v := oni.RADIUS_XL
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

resolve_radius :: proc(
	r: oni.Radius,
	state: ^$S,
	event: oni.Widget_Event(S),
) -> (
	radius: oni.Radius_corners,
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
	case oni.Radius_struct:
		return resolve_radius_struct(v)
	case oni.Radius_corners:
		return v, true
	case proc(state: oni.Widget_State, event: oni.Widget_Event(oni.Widget_State)) -> oni.Radius:
		return resolve_radius(v(ui_state, ui_event), state, event)
	}
	return {}, false
}

resolve_border_struct :: proc(s: oni.Bd_struct) -> (width: oni.Bd, ok: bool) {
	switch {
	case s.sm:
		v := oni.BORDER_SM
		return oni.Bd{t = v, b = v, l = v, r = v}, true
	case s.md:
		v := oni.BORDER_MD
		return oni.Bd{t = v, b = v, l = v, r = v}, true
	case s.lg:
		v := oni.BORDER_LG
		return oni.Bd{t = v, b = v, l = v, r = v}, true
	case s.xl:
		v := oni.BORDER_XL
		return oni.Bd{t = v, b = v, l = v, r = v}, true
	}

	if s.l != 0 || s.r != 0 || s.t != 0 || s.b != 0 {
		return oni.Bd{s.t, s.b, s.l, s.r}, true
	}

	return {}, false
}

resolve_border :: proc(
	b: oni.Border,
	state: ^$S,
	event: oni.Widget_Event(S),
) -> (
	bd: oni.Bd,
	ok: bool,
) {
	ui_state := to_ui_state(state)
	ui_event := to_ui_event(state)
	switch v in b {
	case struct{}:
		return {}, false
	case f32:
		if v == 0 do return {}, false
		return {v, v, v, v}, true
	case oni.Bd_struct:
		return resolve_border_struct(v)
	case oni.Bd:
		return v, true
	case proc(state: oni.Widget_State, event: oni.Widget_Event(oni.Widget_State)) -> oni.Border:
		return resolve_border(v(ui_state, ui_event), state, event)
	}
	return {}, false
}

resolve_width_struct :: proc(s: oni.Dim_struct) -> (axis: oni.SizingAxis, ok: bool) {
	switch {
	case s.sm:
		return oni.SizingFit({min = oni.WIDTH_SM}), true
	case s.md:
		return oni.SizingFit({min = oni.WIDTH_MD}), true
	case s.lg:
		return oni.SizingFit({min = oni.WIDTH_LG}), true
	case s.xl:
		return oni.SizingFit({min = oni.WIDTH_XL}), true
	}

	if s.percent != 0 {
		return oni.SizingPercent(s.percent), true
	}
	if s.grow {
		return oni.SizingGrow({min = s.min, max = s.max}), true
	}
	if s.min != 0 || s.max != 0 {
		return oni.SizingFit({min = s.min, max = s.max}), true
	}

	return {}, false
}

resolve_height_struct :: proc(s: oni.Dim_struct) -> (axis: oni.SizingAxis, ok: bool) {
	switch {
	case s.sm:
		return oni.SizingFit({min = oni.HEIGHT_SM}), true
	case s.md:
		return oni.SizingFit({min = oni.HEIGHT_MD}), true
	case s.lg:
		return oni.SizingFit({min = oni.HEIGHT_LG}), true
	case s.xl:
		return oni.SizingFit({min = oni.HEIGHT_XL}), true
	}

	if s.percent != 0 {
		return oni.SizingPercent(s.percent), true
	}
	if s.grow {
		return oni.SizingGrow({min = s.min, max = s.max}), true
	}
	if s.min != 0 || s.max != 0 {
		return oni.SizingFit({min = s.min, max = s.max}), true
	}

	return {}, false
}

resolve_width :: proc(
	w: oni.Width,
	state: ^$S,
	event: oni.Widget_Event(S),
) -> (
	axis: oni.SizingAxis,
	ok: bool,
) {
	ui_state := to_ui_state(state)
	ui_event := to_ui_event(state)
	switch v in w {
	case struct{}:
		return {}, false
	case f32:
		if v == 0 do return {}, false
		return oni.SizingFixed(v), true
	case oni.Dim_struct:
		return resolve_width_struct(v)
	case proc(state: oni.Widget_State, event: oni.Widget_Event(oni.Widget_State)) -> oni.Width:
		return resolve_width(v(ui_state, ui_event), state, event)
	}
	return {}, false
}

resolve_height :: proc(
	h: oni.Height,
	state: ^$S,
	event: oni.Widget_Event(S),
) -> (
	axis: oni.SizingAxis,
	ok: bool,
) {
	ui_state := to_ui_state(state)
	ui_event := to_ui_event(state)
	switch v in h {
	case struct{}:
		return {}, false
	case f32:
		if v == 0 do return {}, false
		return oni.SizingFixed(v), true
	case oni.Dim_struct:
		return resolve_height_struct(v)
	case proc(state: oni.Widget_State, event: oni.Widget_Event(oni.Widget_State)) -> oni.Height:
		return resolve_height(v(ui_state, ui_event), state, event)
	}
	return {}, false
}

resolve_child_gap :: proc(
	g: oni.Gap,
	state: ^$S,
	event: oni.Widget_Event(S),
) -> (
	gap: u16,
	ok: bool,
) {
	ui_state := to_ui_state(state)
	ui_event := to_ui_event(state)
	switch v in g {
	case struct{}:
		return 0, false
	case u16:
		return v, true
	case proc(state: oni.Widget_State, event: oni.Widget_Event(oni.Widget_State)) -> oni.Gap:
		return resolve_child_gap(v(ui_state, ui_event), state, event)
	}
	return 0, false
}

resolve_align_pos :: proc(pos: oni.Align_Pos) -> (align: oni.Align_Pos, ok: bool) {
	if pos.x == .Unset || pos.y == .Unset do return {}, false

	x: oni.Align_X
	switch pos.x {
	case .Unset:
		return {}, false
	case .Left:
		x = .Left
	case .Right:
		x = .Right
	case .Center:
		x = .Center
	}

	y: oni.Align_Y
	switch pos.y {
	case .Unset:
		return {}, false
	case .Top:
		y = .Top
	case .Bottom:
		y = .Bottom
	case .Center:
		y = .Center
	}

	return {x = x, y = y}, true
}

resolve_align :: proc(
	a: oni.Align,
	state: ^$S,
	event: oni.Widget_Event(S),
) -> (
	align: oni.Align_Pos,
	ok: bool,
) {
	ui_state := to_ui_state(state)
	ui_event := to_ui_event(state)
	switch v in a {
	case struct{}:
		return {}, false
	case oni.Align_Pos:
		return resolve_align_pos(v)
	case proc(state: oni.Widget_State, event: oni.Widget_Event(oni.Widget_State)) -> oni.Align:
		return resolve_align(v(ui_state, ui_event), state, event)
	}
	return {}, false
}

resolve_direction :: proc(
	d: oni.Direction,
	state: ^$S,
	event: oni.Widget_Event(S),
) -> (
	direction: oni.Direction,
	ok: bool,
) {
	ui_state := to_ui_state(state)
	ui_event := to_ui_event(state)
	switch v in d {

	case oni.Direction_Layout:
		return v, true
	case proc(state: oni.Widget_State, event: oni.Widget_Event(oni.Widget_State)) -> oni.Direction:
		return resolve_direction(v(ui_state, ui_event), state, event)
	}
	return .Horizontal, false
}


resolve_aspect_ratio :: proc(
	a: oni.AspectRatio,
	state: ^$S,
	event: oni.Widget_Event(S),
) -> (
	aspectRatio: f32,
	ok: bool,
) {
	ui_state := to_ui_state(state)
	ui_event := to_ui_event(state)
	switch v in a {
	case f32:
		if v == 0 do return {}, false
		return v, true
	case proc(
		     state: oni.Widget_State,
		     event: oni.Widget_Event(oni.Widget_State),
	     ) -> oni.AspectRatio:
		return resolve_aspect_ratio(v(ui_state, ui_event), state, event)
	}
	return {}, false
}


sizing_axis_is_set :: proc(axis: oni.SizingAxis) -> bool {
	switch axis.type {
	case .Fixed, .Grow:
		return true
	case .Percent:
		return axis.constraints.sizePercent != 0
	case .Fit:
		return axis.constraints.sizeMinMax.min != 0 || axis.constraints.sizeMinMax.max != 0
	}
	return false
}


element_config_to_declaration :: proc(
	config: oni.Widget_config,
	state: ^$S,
	event: oni.Widget_Event(S),
) -> oni.Widget_config {
	decl := oni.Widget_config{}


	if padding, padding_ok := resolve_padding(config.pd, state, event); padding_ok {
		decl.pd = padding
	}

	if radius, radius_ok := resolve_radius(config.rd, state, event); radius_ok {
		decl.rd = radius
	}

	border_width: oni.Border
	border_ok := false
	if width, width_ok := resolve_border(config.bd, state, event); width_ok {
		border_width = width
		border_ok = true
	}

	if border_ok {
		decl.bd = border_width
	}
	if color, color_ok := oni.resolve_color(config.bdColor, state, event); color_ok {
		decl.bdColor = color
	}
	if bg, bg_ok := oni.resolve_color(config.bg, state, event); bg_ok {
		decl.bdColor = bg
	}

	if gap, gap_ok := resolve_child_gap(config.gap, state, event); gap_ok {
		decl.gap = gap
	}
	if align, align_ok := resolve_align(config.alignChild, state, event); align_ok {
		//TODO: Resolve Text_Align to Align_Pos
		decl.align = align
	}
	if direction, direction_ok := resolve_direction(config.direction, state, event); direction_ok {
		decl.direction = direction
	}

	// if width, width_ok := resolve_width(config.width, state, event); width_ok {
	// 	decl.layout.sizing.width = width
	// }
	// if height, height_ok := resolve_height(config.height, state, event); height_ok {
	// 	decl.layout.sizing.height = height
	// }

	return decl
}

merge_element_declaration :: proc(
	base: oni.Widget_config,
	override: oni.Widget_config,
	state: ^$S,
	event: oni.Widget_Event(S),
) -> oni.Widget_config {
	result := base


	if override.align != nil {
		result.align = override.align
	}


	if override.alignChild != nil {
		result.alignChild = override.alignChild
	}
	if override.aspectRatio != nil {
		result.aspectRatio = override.aspectRatio
	}
	if override.auto_focus {
		result.auto_focus = override.auto_focus
	}
	if override.bd != nil {
		result.bd = override.bd
	}
	if override.bdColor != nil {
		result.bdColor = override.bdColor
	}
	if override.bg != nil {
		result.bg = override.bg
	}
	if override.gap != nil {
		result.gap = override.gap
	}
	if override.color != nil {
		result.color = override.color
	}
	if override.direction != nil {
		result.direction = override.direction
	}
	if override.disabled {
		result.disabled = override.disabled
	}
	if override.font != {} {
		result.font = override.font
	}
	if override.font_size != 0 {
		result.font_size = override.font_size
	}
	if override.letter_spacing != 0 {
		result.letter_spacing = override.letter_spacing
	}
	if override.line_height != 0 {
		result.line_height = override.line_height
	}
	if override.pd != nil {
		result.pd = override.pd
	}
	if override.rd != nil {
		result.rd = override.rd
	}
	if override.space != nil {
		result.space = override.space
	}
	if override.wrap != nil {
		result.wrap = override.wrap
	}


	return element_config_to_declaration(result, state, event)
}

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


widget_shaped :: proc(id: Widget_ID) -> ^oni.Shaped_Text {
	entry: ^oni.UI_Widget_Entry
	if e, ok := &state.ui.widgets[id]; ok {
		entry = e
	} else {
		state.ui.widgets[id] = {
			shaped = {pool_slot = INVALID_SHAPE_POOL_SLOT},
		}
		entry = &state.ui.widgets[id]
	}

	entry.last_frame = state.ui.frame
	return &entry.shaped
}

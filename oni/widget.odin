package oni

import "core:fmt"
import "core:hash"
import sdl "vendor:sdl3"


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

beginMouseFrame :: proc() {
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

pointer_over :: proc(rect: Rect, space: Draw_Space) -> bool {
	mouse := Vec2{w_ctx.mouse_x, w_ctx.mouse_y}
	if space == .Artboard {
		mouse = View_Screen_To_World(mouse)
	}
	return(
		mouse.x >= rect.x &&
		mouse.x < rect.x + rect.w &&
		mouse.y >= rect.y &&
		mouse.y < rect.y + rect.h \
	)
}

to_ui_state :: proc(state: ^$S) -> Widget_State {
	return (^Widget_State)(cast(rawptr)state)^
}

to_ui_event :: proc(state: ^$S) -> Widget_Event(Widget_State) {
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
		return {s.l, s.r, s.t, s.b}, true
	}
	if s.x != 0 || s.y != 0 {
		return {s.x, s.x, s.y, s.y}, true
	}

	return {}, false
}

resolve_padding :: proc(
	p: Padding,
	state: ^$S,
	event: Widget_Event(S),
) -> (
	padding: Pd,
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
	case Pd_pos:
		if v.x == 0 && v.y == 0 do return {}, false
		return {v.x, v.x, v.y, v.y}, true
	case Pd_struct:
		return resolve_padding_struct(v)
	case Pd:
		return v, true
	case proc(state: Widget_State, event: Widget_Event(Widget_State)) -> Padding:
		return resolve_padding(v(ui_state, ui_event), state, event)
	}
	return {}, false
}

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
	case proc(state: Widget_State, event: Widget_Event(Widget_State)) -> Radius:
		return resolve_radius(v(ui_state, ui_event), state, event)
	}
	return {}, false
}

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

resolve_border :: proc(b: Border, state: ^$S, event: Widget_Event(S)) -> (border: Bd, ok: bool) {
	ui_state := to_ui_state(state)
	ui_event := to_ui_event(state)
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
	case proc(state: Widget_State, event: Widget_Event(Widget_State)) -> Border:
		return resolve_border(v(ui_state, ui_event), state, event)
	}
	return {}, false
}

resolve_child_gap :: proc(g: Gap, state: ^$S, event: Widget_Event(S)) -> (gap: u16, ok: bool) {
	ui_state := to_ui_state(state)
	ui_event := to_ui_event(state)
	switch v in g {
	case struct{}:
		return 0, false
	case u16:
		return v, true
	case proc(state: Widget_State, event: Widget_Event(Widget_State)) -> Gap:
		return resolve_child_gap(v(ui_state, ui_event), state, event)
	}
	return 0, false
}

resolve_align_pos :: proc(pos: Justify_Pos) -> (align: Justify_Pos, ok: bool) {
	if pos.x == .Unset || pos.y == .Unset do return {}, false

	x: Justify_X
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

	y: Justify_Y
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
	a: Justify,
	state: ^$S,
	event: Widget_Event(S),
) -> (
	align: Justify_Pos,
	ok: bool,
) {
	ui_state := to_ui_state(state)
	ui_event := to_ui_event(state)
	switch v in a {
	case struct{}:
		return {}, false
	case Justify_Pos:
		return resolve_align_pos(v)
	case proc(state: Widget_State, event: Widget_Event(Widget_State)) -> Justify:
		return resolve_align(v(ui_state, ui_event), state, event)
	}
	return {}, false
}

resolve_direction :: proc(
	d: Direction,
	state: ^$S,
	event: Widget_Event(S),
) -> (
	direction: Direction,
	ok: bool,
) {
	ui_state := to_ui_state(state)
	ui_event := to_ui_event(state)
	switch v in d {

	case Direction_Layout:
		return v, true
	case proc(state: Widget_State, event: Widget_Event(Widget_State)) -> Direction:
		return resolve_direction(v(ui_state, ui_event), state, event)
	}
	return .Horizontal, false
}

element_config_to_declaration :: proc(
	config: Widget_config,
	state: ^$S,
	event: Widget_Event(S),
) -> Widget_config {
	decl := config


	if padding, padding_ok := resolve_padding(config.padding, state, event); padding_ok {
		decl.padding = padding
	}

	if radius, radius_ok := resolve_radius(config.radius, state, event); radius_ok {
		decl.radius = radius
	}

	border_width: Border
	border_ok := false
	if width, width_ok := resolve_border(config.border, state, event); width_ok {
		border_width = width
		border_ok = true
	}

	if border_ok {
		decl.border = border_width
	}
	if color, color_ok := to_rgba(config.border_color, state, event); color_ok {
		decl.border_color = color
	}
	if background, bg_ok := to_rgba(config.background, state, event); bg_ok {
		decl.background = background
	}
	if color, color_ok := to_rgba(config.color, state, event); color_ok {
		decl.color = color
	}

	if gap, gap_ok := resolve_child_gap(config.gap, state, event); gap_ok {
		decl.gap = gap
	}
	if align, align_ok := resolve_align(config.justify, state, event); align_ok {
		decl.justify = align
	}
	if direction, direction_ok := resolve_direction(config.direction, state, event); direction_ok {
		decl.direction = direction
	}

	return decl
}

merge_element_declaration :: proc(
	base: Widget_config,
	override: Widget_config,
	state: ^$S,
	event: Widget_Event(S),
) -> Widget_config {
	result := base


	if override.align != nil {
		result.align = override.align
	}


	if override.justify != nil {
		result.justify = override.justify
	}
	if override.aspect_ratio != nil {
		result.aspect_ratio = override.aspect_ratio
	}
	if override.auto_focus {
		result.auto_focus = override.auto_focus
	}
	if override.border != nil {
		result.border = override.border
	}
	if override.border_color != nil {
		result.border_color = override.border_color
	}
	if override.background != nil {
		result.background = override.background
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
	if override.padding != nil {
		result.padding = override.padding
	}
	if override.radius != nil {
		result.radius = override.radius
	}
	if override.id != "" {
		result.id = override.id
	}
	if override.x != {} {
		result.x = override.x
	}
	if override.y != {} {
		result.y = override.y
	}
	if override.width != {} {
		result.width = override.width
	}
	if override.height != {} {
		result.height = override.height
	}
	result.space = override.space
	if override.wrap != nil {
		result.wrap = override.wrap
	}
	if override.text_direction != .LTR {
		result.text_direction = override.text_direction
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


widget_shaped :: proc(id: Widget_ID) -> ^Shaped_Text {
	ui_init()

	ui_id := UI_Id(hash.crc32(transmute([]u8)id))
	if _, ok := state.ui.widgets[ui_id]; !ok {
		state.ui.widgets[ui_id] = UI_Widget_Entry {
			shaped = {pool_slot = INVALID_SHAPE_POOL_SLOT},
		}
	}

	entry := &state.ui.widgets[ui_id]
	entry.last_frame = state.ui.frame
	return &entry.shaped
}

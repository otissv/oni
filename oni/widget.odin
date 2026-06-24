package oni

import "core:fmt"
import "core:hash"


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

@(private)
sync_widget_button :: proc(button: ^Widget_Mouse_Button_State, is_down: bool) {
	if is_down {
		if !button.down do button.pressed = true
	} else {
		if button.down do button.released = true
	}

	button.down = is_down
}

@(private)
sync_widget_key :: proc(key: ^Widget_Mouse_Key_State, is_down: bool) {
	if is_down {
		if !key.down do key.pressed = true
	} else {
		if key.down do key.released = true
	}

	key.down = is_down
}

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

	sync_widget_input()
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

widget_hit_rect :: proc(layout_id: UI_Id, style: Resolved_Widget_Style) -> Rect {
	rect := ui_layout_rect(layout_id)

	if style.width.kind == .Fixed {
		rect.w = style.width.value
	} else if w := length_resolve(style.width, rect.w); w > 0 {
		rect.w = w
	}

	if style.height.kind == .Fixed {
		rect.h = style.height.value
	} else if h := length_resolve(style.height, rect.h); h > 0 {
		rect.h = h
	}

	return rect
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

resolve_padding_xy :: proc(x, y: f32) -> Pd {
	if y == 0 do return {t = x, b = x, l = x, r = x}

	return {t = y, b = y, l = x, r = x}
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
		return Pd{t = s.t, b = s.b, l = s.l, r = s.r}, true
	}
	if s.x != 0 || s.y != 0 {
		return resolve_padding_xy(s.x, s.y), true
	}

	return {}, false
}

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
	case proc(state: Widget_State, event: Widget_Event(Widget_State)) -> Padding:
		return {}, false
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
	#partial switch v in p {
	case proc(state: Widget_State, event: Widget_Event(Widget_State)) -> Padding:
		ui_state := to_ui_state(state)
		ui_event := to_ui_event(state)
		return resolve_padding(v(ui_state, ui_event), state, event)
	}

	return resolve_padding_value(p)
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
	case proc(state: Widget_State, event: Widget_Event(Widget_State)) -> Border:
		return {}, false
	}

	return {}, false
}

resolve_border :: proc(b: Border, state: ^$S, event: Widget_Event(S)) -> (border: Bd, ok: bool) {
	#partial switch v in b {
	case proc(state: Widget_State, event: Widget_Event(Widget_State)) -> Border:
		ui_state := to_ui_state(state)
		ui_event := to_ui_event(state)
		return resolve_border(v(ui_state, ui_event), state, event)
	}

	return resolve_border_value(b)
}

resolve_gap_value :: proc(g: Gap) -> (gap: u16, ok: bool) {
	switch v in g {
	case struct{}:
		return 0, false
	case u16:
		return v, true
	case proc(state: Widget_State, event: Widget_Event(Widget_State)) -> Gap:
		return 0, false
	}

	return 0, false
}

resolve_child_gap :: proc(g: Gap, state: ^$S, event: Widget_Event(S)) -> (gap: u16, ok: bool) {
	#partial switch v in g {
	case proc(state: Widget_State, event: Widget_Event(Widget_State)) -> Gap:
		ui_state := to_ui_state(state)
		ui_event := to_ui_event(state)
		return resolve_child_gap(v(ui_state, ui_event), state, event)
	}

	return resolve_gap_value(g)
}

resolve_align_pos :: proc(pos: Justify_Pos) -> (align: Justify_Pos, ok: bool) {
	x, x_ok := resolve_justify_x(pos.x)
	if !x_ok do return {}, false

	y, y_ok := resolve_justify_y(pos.y)
	if !y_ok do return {}, false

	return {x = x, y = y}, true
}

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

resolve_justify_x :: proc(x: Justify_X) -> (Justify_X, bool) {
	#partial switch v in x {
	case Justify_Align:
		return v, true
	}

	return Justify_Align.Start, false
}

resolve_justify_y :: proc(y: Justify_Y) -> (Justify_Y, bool) {
	#partial switch v in y {
	case Justify_Align:
		return v, true
	}

	return Justify_Align.Start, false
}

resolve_justify_value :: proc(a: Justify) -> (align: Justify_Pos, ok: bool) {
	switch v in a {
	case struct{}:
		return {}, false
	case Justify_Pos:
		return resolve_align_pos(v)
	case proc(state: Widget_State, event: Widget_Event(Widget_State)) -> Justify:
		return {}, false
	}

	return {}, false
}

resolve_align :: proc(
	a: Justify,
	state: ^$S,
	event: Widget_Event(S),
) -> (
	align: Justify_Pos,
	ok: bool,
) {
	#partial switch v in a {
	case proc(state: Widget_State, event: Widget_Event(Widget_State)) -> Justify:
		ui_state := to_ui_state(state)
		ui_event := to_ui_event(state)

		return resolve_align(v(ui_state, ui_event), state, event)
	}

	return resolve_justify_value(a)
}

resolve_direction_value :: proc(d: Widget_Direction) -> (direction: Direction_Layout, ok: bool) {
	switch v in d {
	case struct{}:
		return .Horizontal, false
	case Direction_Layout:
		return v, true
	case proc(state: Widget_State, event: Widget_Event(Widget_State)) -> Widget_Direction:
		return .Horizontal, false
	}
	return .Horizontal, false
}

resolve_direction :: proc(
	d: Widget_Direction,
	state: ^$S,
	event: Widget_Event(S),
) -> (
	direction: Widget_Direction,
	ok: bool,
) {
	#partial switch v in d {
	case proc(state: Widget_State, event: Widget_Event(Widget_State)) -> Widget_Direction:
		ui_state := to_ui_state(state)
		ui_event := to_ui_event(state)

		return resolve_direction(v(ui_state, ui_event), state, event)
	}

	if layout, layout_ok := resolve_direction_value(d); layout_ok do return layout, true

	return .Horizontal, false
}

justify_align_from_x :: proc(x: Justify_X) -> (Justify_Align, bool) {
	#partial switch v in x {
	case Justify_Align:
		return v, true
	}

	return .Start, false
}

justify_align_from_y :: proc(y: Justify_Y) -> (Justify_Align, bool) {
	#partial switch v in y {
	case Justify_Align:
		return v, true
	}

	return .Start, false
}

justify_align_is_space :: proc(align: Justify_Align) -> bool {
	return align == .Space_between || align == .Space_around || align == .Space_evenly
}

justify_align_position_offset :: proc(free_space, size: f32, align: Justify_Align) -> f32 {
	switch align {
	case .Start, .Stretch:
		return 0
	case .Center:
		return max(0, (free_space - size) * 0.5)
	case .End:
		return max(0, free_space - size)
	case .Space_between, .Space_around, .Space_evenly:
		return 0
	}
	return 0
}

justify_align_position_offset_x :: proc(free_space, size: f32, axis: Justify_X) -> f32 {
	if align, ok := justify_align_from_x(axis); ok {
		return justify_align_position_offset(free_space, size, align)
	}
	return 0
}

justify_align_position_offset_y :: proc(free_space, size: f32, axis: Justify_Y) -> f32 {
	if align, ok := justify_align_from_y(axis); ok {
		return justify_align_position_offset(free_space, size, align)
	}
	return 0
}

justify_axis_is_stretch_y :: proc(y: Justify_Y) -> bool {
	#partial switch v in y {
	case Justify_Align:
		return v == .Stretch
	}

	return false
}

justify_axis_is_stretch_x :: proc(x: Justify_X) -> bool {
	#partial switch v in x {
	case Justify_Align:
		return v == .Stretch
	}

	return false
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

@(private)
texture_pos_normalize :: proc(v: f32) -> f32 {
	if v > 1 do return v * 0.01
	return v
}

resolve_texture_pos_value :: proc(p: Style_Texture_Pos) -> (pos: Resolved_Texture_Pos, ok: bool) {
	switch v in p {
	case struct{}:
		return {0.5, 0.5, 0, 0}, true
	case Texture_Pos:
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
	case Texture_Pos_X_Y:
		return {texture_pos_normalize(v.x), texture_pos_normalize(v.y), 0, 0}, true
	case Resolved_Texture_Pos:
		return v, true
	case proc(state: Widget_State, event: Widget_Event(Widget_State)) -> Texture_Pos:
		return {}, false
	}

	return {}, false
}

resolve_texture_pos :: proc(
	p: Style_Texture_Pos,
	state: ^$S,
	event: Widget_Event(S),
) -> (
	pos: Resolved_Texture_Pos,
	ok: bool,
) {
	#partial switch v in p {
	case proc(state: Widget_State, event: Widget_Event(Widget_State)) -> Texture_Pos:
		ui_state := to_ui_state(state)
		ui_event := to_ui_event(state)
		return resolve_texture_pos_value(Style_Texture_Pos(v(ui_state, ui_event)))
	}

	return resolve_texture_pos_value(p)
}

resolve_texture_fit_value :: proc(f: Style_Texture_Fit) -> (fit: Texture_Fit, ok: bool) {
	switch v in f {
	case struct{}:
		return {}, false
	case Texture_Fit:
		return v, true
	case proc(state: Widget_State, event: Widget_Event(Widget_State)) -> Texture_Fit:
		return {}, false
	}

	return {}, false
}

resolve_texture_fit :: proc(
	f: Style_Texture_Fit,
	state: ^$S,
	event: Widget_Event(S),
) -> (
	fit: Texture_Fit,
	ok: bool,
) {
	#partial switch v in f {
	case proc(state: Widget_State, event: Widget_Event(Widget_State)) -> Texture_Fit:
		ui_state := to_ui_state(state)
		ui_event := to_ui_event(state)
		return resolve_texture_fit_value(Style_Texture_Fit(v(ui_state, ui_event)))
	}

	return resolve_texture_fit_value(f)
}

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

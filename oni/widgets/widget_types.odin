package widgets

import oni ".."
import "core:fmt"
import "core:hash"
import sdl "vendor:sdl3"


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


auto_element_id :: proc() -> oni.Widget_ID {
	idx := oni.w_ctx.auto_element_index
	oni.w_ctx.auto_element_index += 1

	id := fmt.tprintf("__auto_element__{0}", idx)

	return id
}

register_static_id :: proc(id: string, static_id: string) {
	if id == "" do return

	if oni.w_ctx.static_ids == nil {
		oni.w_ctx.static_ids = make(map[string]oni.Widget_ID)
	}

	oni.w_ctx.static_ids[id] = static_id
}

element_key :: proc(id: string) -> string {
	key := auto_element_id()
	register_static_id(id, key)
	return key
}

GetElementById :: proc(id: string) -> (static_id: string, ok: bool) {
	if oni.w_ctx.static_ids == nil do return {}, false
	static_id, ok = oni.w_ctx.static_ids[id]
	return
}

FocusElement :: proc(id: string) -> bool {
	element_id, ok := GetElementById(id)
	if !ok do return false

	oni.w_ctx.focused_id = element_id
	return true
}

clear_button_transients :: proc(button: ^oni.Widget_Mouse_Button_State) {
	button.pressed = false
	button.released = false
}

clear_key_transients :: proc(key: ^oni.Widget_Mouse_Key_State) {
	key.pressed = false
	key.released = false
}

sync_mouse_state :: proc() {
	x, y: f32
	buttons := sdl.GetMouseState(&x, &y)

	oni.w_ctx.mouse_x = x
	oni.w_ctx.mouse_y = y
	oni.w_ctx.left_mouse.down = .LEFT in buttons
	oni.w_ctx.right_mouse.down = .RIGHT in buttons
	oni.w_ctx.middle_mouse.down = .MIDDLE in buttons
}

update_mouse_button :: proc(button: ^oni.Widget_Mouse_Button_State, is_down: bool) {
	if is_down {
		if !button.down do button.pressed = true
		button.down = true
	} else {
		if button.down do button.released = true
		button.down = false
	}
}

update_key_state :: proc(key: ^oni.Widget_Mouse_Key_State, is_down, is_repeat: bool) {
	if is_down {
		if !key.down && !is_repeat do key.pressed = true
		key.down = true
	} else {
		if key.down do key.released = true
		key.down = false
	}
}

Shutdown :: proc() {
	if oni.w_ctx.static_ids != nil {
		delete(oni.w_ctx.static_ids)
	}
	if oni.w_ctx.element_was_hovered != nil {
		delete(oni.w_ctx.element_was_hovered)
	}
	if oni.w_ctx.element_pointer_down != nil {
		delete(oni.w_ctx.element_pointer_down)
	}
}

BeginFrame :: proc() {
	oni.ui_begin_frame()

	oni.w_ctx.auto_element_index = 0

	if oni.w_ctx.static_ids != nil {
		clear(&oni.w_ctx.static_ids)
	}

	oni.w_ctx.mouse_moved = false

	clear_button_transients(&oni.w_ctx.left_mouse)
	clear_button_transients(&oni.w_ctx.right_mouse)
	clear_button_transients(&oni.w_ctx.middle_mouse)

	for &key in oni.w_ctx.keys {
		clear_key_transients(&key)
	}

	sync_mouse_state()
}

EndLayoutPass :: proc() {
	oni.ui_end_layout_pass()
}

EndFrame :: proc() {
	oni.ui_end_frame()
}

ProcessEvent :: proc(event: ^sdl.Event) {
	#partial switch event.type {
	case .MOUSE_MOTION:
		oni.w_ctx.mouse_moved = true
		oni.w_ctx.mouse_x = event.motion.x
		oni.w_ctx.mouse_y = event.motion.y

	case .MOUSE_BUTTON_DOWN:
		oni.w_ctx.mouse_x = event.button.x
		oni.w_ctx.mouse_y = event.button.y

		switch event.button.button {
		case sdl.BUTTON_LEFT:
			update_mouse_button(&oni.w_ctx.left_mouse, true)
		case sdl.BUTTON_RIGHT:
			update_mouse_button(&oni.w_ctx.right_mouse, true)
		case sdl.BUTTON_MIDDLE:
			update_mouse_button(&oni.w_ctx.middle_mouse, true)
		}

	case .MOUSE_BUTTON_UP:
		oni.w_ctx.mouse_x = event.button.x
		oni.w_ctx.mouse_y = event.button.y

		switch event.button.button {
		case sdl.BUTTON_LEFT:
			update_mouse_button(&oni.w_ctx.left_mouse, false)
		case sdl.BUTTON_RIGHT:
			update_mouse_button(&oni.w_ctx.right_mouse, false)
		case sdl.BUTTON_MIDDLE:
			update_mouse_button(&oni.w_ctx.middle_mouse, false)
		}

	case .KEY_DOWN:
		idx := int(event.key.scancode)
		if idx >= 0 && idx < oni.KEY_COUNT {
			update_key_state(&oni.w_ctx.keys[idx], true, event.key.repeat)
		}

	case .KEY_UP:
		idx := int(event.key.scancode)
		if idx >= 0 && idx < oni.KEY_COUNT {
			update_key_state(&oni.w_ctx.keys[idx], false, false)
		}

	case .WINDOW_FOCUS_LOST:
		for &key in oni.w_ctx.keys {
			key.down = false
		}
	}
}

SetPointerState :: proc(position: [2]f32, pointerDown: bool) {
	_ = position
	_ = pointerDown
}

SyncPointer :: proc() {
	SetPointerState({oni.w_ctx.mouse_x, oni.w_ctx.mouse_y}, oni.w_ctx.left_mouse.down)
}

pointer_over :: proc(rect: oni.Rect, space: oni.Draw_Space) -> bool {
	mouse := oni.Vec2{oni.w_ctx.mouse_x, oni.w_ctx.mouse_y}
	if oni.draw_resolve_space(space) == .Artboard {
		mouse = oni.View_Screen_To_World(mouse)
	}
	return(
		mouse.x >= rect.x &&
		mouse.x < rect.x + rect.w &&
		mouse.y >= rect.y &&
		mouse.y < rect.y + rect.h \
	)
}

to_ui_state :: proc(state: ^$S) -> oni.Widget_State {
	return (^oni.Widget_State)(cast(rawptr)state)^
}

to_ui_event :: proc(state: ^$S) -> oni.Widget_Event(oni.Widget_State) {
	return {state = to_ui_state(state)}
}

consume_hover_transition :: proc(element_id: string, hovered: bool) -> (entered, left: bool) {
	if oni.w_ctx.element_was_hovered == nil {
		oni.w_ctx.element_was_hovered = make(map[string]bool)
	}

	was_hovered := oni.w_ctx.element_was_hovered[element_id]
	entered = hovered && !was_hovered
	left = was_hovered && !hovered
	oni.w_ctx.element_was_hovered[element_id] = hovered
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
		return oni.Pd{t = s.t, b = s.b, l = s.l, r = s.r}, true
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
	border: oni.Bd,
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

resolve_align_pos :: proc(pos: oni.Justify_Pos) -> (align: oni.Justify_Pos, ok: bool) {
	x, x_ok := resolve_justify_x(pos.x)
	if !x_ok do return {}, false
	y, y_ok := resolve_justify_y(pos.y)
	if !y_ok do return {}, false
	return {x = x, y = y}, true
}

resolve_justify_x :: proc(x: oni.Justify_X) -> (oni.Justify_X, bool) {
	#partial switch v in x {
	case oni.Justify_Align:
		return v, true
	}
	return oni.Justify_Align.Start, false
}

resolve_justify_y :: proc(y: oni.Justify_Y) -> (oni.Justify_Y, bool) {
	#partial switch v in y {
	case oni.Justify_Align:
		return v, true
	}
	return oni.Justify_Align.Start, false
}

resolve_align :: proc(
	a: oni.Justify,
	state: ^$S,
	event: oni.Widget_Event(S),
) -> (
	align: oni.Justify_Pos,
	ok: bool,
) {
	ui_state := to_ui_state(state)
	ui_event := to_ui_event(state)
	switch v in a {
	case struct{}:
		return {}, false
	case oni.Justify_Pos:
		return resolve_align_pos(v)
	case proc(state: oni.Widget_State, event: oni.Widget_Event(oni.Widget_State)) -> oni.Justify:
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
	case struct{}:
		return oni.Direction_Layout.Horizontal, false
	case oni.Direction_Layout:
		return v, true
	case proc(state: oni.Widget_State, event: oni.Widget_Event(oni.Widget_State)) -> oni.Direction:
		return resolve_direction(v(ui_state, ui_event), state, event)
	}
	return oni.Direction_Layout.Horizontal, false
}


resolve_aspect_ratio :: proc(
	a: oni.Aspect_Ratio,
	state: ^$S,
	event: oni.Widget_Event(S),
) -> (
	aspect_ratio: f32,
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
	     ) -> oni.Aspect_Ratio:
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
	decl := config


	if padding, padding_ok := resolve_padding(config.padding, state, event); padding_ok {
		decl.padding = padding
	}

	if radius, radius_ok := resolve_radius(config.radius, state, event); radius_ok {
		decl.radius = radius
	}

	border_width: oni.Border
	border_ok := false
	if width, width_ok := resolve_border(config.border, state, event); width_ok {
		border_width = width
		border_ok = true
	}

	if border_ok {
		decl.border = border_width
	}
	if color, color_ok := oni.to_rgba(config.border_color, state, event); color_ok {
		decl.border_color = color
	}
	if background, bg_ok := oni.to_rgba(config.background, state, event); bg_ok {
		decl.background = background
	}
	if color, color_ok := oni.to_rgba(config.color, state, event); color_ok {
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


	#partial switch justify in override.justify {
	case oni.Justify_Pos:
		result.justify = justify
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
	#partial switch background in override.background {
	case oni.Color, oni.RGBA, oni.Hex, oni.HSLA, oni.HWBA, oni.LCHA, oni.OKLCHA:
		result.background = background
	case proc(state: oni.Widget_State, event: oni.Widget_Event(oni.Widget_State)) -> oni.Colors:
		result.background = background
	}
	#partial switch gap in override.gap {
	case u16:
		result.gap = gap
	}
	#partial switch color in override.color {
	case oni.Color, oni.RGBA, oni.Hex, oni.HSLA, oni.HWBA, oni.LCHA, oni.OKLCHA:
		result.color = color
	case proc(state: oni.Widget_State, event: oni.Widget_Event(oni.Widget_State)) -> oni.Colors:
		result.color = color
	}
	#partial switch direction in override.direction {
	case oni.Direction_Layout:
		result.direction = direction
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
	#partial switch padding in override.padding {
	case oni.Pd, f32:
		result.padding = padding
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
	if override.flex > 0 {
		result.flex = override.flex
	}
	if override.min_w != 0 {
		result.min_w = override.min_w
	}
	if override.max_w != 0 {
		result.max_w = override.max_w
	}
	if override.min_h != 0 {
		result.min_h = override.min_h
	}
	if override.max_h != 0 {
		result.max_h = override.max_h
	}
	if override.space == .Inherit {
		result.space = oni.widget_current_inherit_space()
	} else {
		result.space = override.space
	}
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
	if oni.w_ctx.element_pointer_down == nil {
		oni.w_ctx.element_pointer_down = make(map[string]bool)
	}

	if hovered && left_pressed {
		oni.w_ctx.element_pointer_down[element_id] = true
	}

	if left_released {
		clicked = oni.w_ctx.element_pointer_down[element_id] && hovered
		oni.w_ctx.element_pointer_down[element_id] = false
	}

	return
}


widget_shaped :: proc(id: oni.Widget_ID) -> ^oni.Shaped_Text {
	oni.ui_init()

	ui_id := oni.UI_Id(hash.crc32(transmute([]u8)id))
	if _, ok := oni.state.ui.widgets[ui_id]; !ok {
		oni.state.ui.widgets[ui_id] = oni.UI_Widget_Entry {
			shaped = {pool_slot = oni.INVALID_SHAPE_POOL_SLOT},
		}
	}

	entry := &oni.state.ui.widgets[ui_id]
	entry.last_frame = oni.state.ui.frame
	return &entry.shaped
}

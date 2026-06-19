package widgets

import oni ".."


Widget_Text_Flag :: enum {
	Uncached,
}

Widget_Text_Flags :: bit_set[Widget_Text_Flag;i32]

Text_Variant :: enum {
	DEFAULT,
	H1,
	H2,
	H3,
	H4,
	H5,
	H6,
}

Text_Size :: enum {
	Default,
	Small,
	Large,
	Icon,
}

Text_Config :: struct {
	kind:           string,
	id:             oni.UI_Id,
	rect:           oni.Rect,
	align:          oni.Text_Align,
	auto_focus:     bool,
	color:          oni.Colors,
	direction:      oni.Text_Direction,
	disabled:       bool,
	flags:          Widget_Text_Flags,
	font_size:      f32,
	font:           oni.Font_Handle,
	letter_spacing: f32,
	line_height:    f32,
	space:          oni.Draw_Space,
	wrap:           oni.Text_Warp,
	size:           Text_Size,
	text:           string,
	variant:        Text_Variant,
	max_w:          f32,
}

Text_State :: struct {
	using _: oni.Widget_State,
}

Text_Merged_State :: oni.Widget_Merged_State(Text_State, Text_Config)

Text_Event :: oni.Widget_Event(Text_Merged_State)

Text_Props :: struct {
	using _:           Text_Config,
	on_focus:          proc(event: Text_Event),
	on_blur:           proc(event: Text_Event),
	on_mouse_enter:    proc(event: Text_Event),
	on_mouse_leave:    proc(event: Text_Event),
	on_mouse_pressed:  proc(event: Text_Event),
	on_mouse_down:     proc(event: Text_Event),
	on_mouse_released: proc(event: Text_Event),
	on_mouse_move:     proc(event: Text_Event),
	on_click:          proc(event: Text_Event),
	on_contextmenu:    proc(event: Text_Event),
	on_key_pressed:    proc(event: Text_Event),
	on_key_down:       proc(event: Text_Event),
	on_key_released:   proc(event: Text_Event),
}

Text :: proc(props: Text_Props) -> oni.Vec2 {

	state := Text_Merged_State {
		state = Text_State {
			is_disabled = props.disabled,
			// is_focused  = ui_ctx.focused_id.id == key.id,
		},
	}
	event := Text_Event {
		state = state,
	}


	font := props.font != {} ? props.font : oni.theme.font_body
	rect := props.rect
	text := props.text
	font_size := props.font_size != 0 ? props.font_size : 16

	color := props.color
	max_w := props.max_w

	rgbaColor: oni.RGBA
	has_color := false

	#partial switch c in color {
	case oni.Color:
		if c == .Invalid {
			rgbaColor = oni.theme.palette[.Text]
			has_color = true
		}
	case:
		if color == {} {
			if state.is_disabled {
				rgbaColor = oni.theme.palette[.Text_muted]
				has_color = true
			}
		}
	}

	if !has_color {
		if resolved, ok := oni.resolve_color(color, &state, event); ok {
			rgbaColor = resolved
		}
	}

	resolved_font, layout_scale, ok := oni.font_resolve(font, font_size, props.space)
	if !ok do return {}

	face := oni.font_face_from_handle(resolved_font)
	if face == nil || len(text) == 0 do return {}

	pos := oni.Vec2{rect.x, rect.y}
	shape_max_w := max_w > 0 ? max_w / layout_scale : max_w

	if .Uncached in props.flags {
		lines := oni.font_shape_line_build(face, text, shape_max_w, props.direction)
		if len(lines) == 0 do return {}
		defer oni.font_destroy_shaped_lines(lines)
		return oni.font_draw_shaped_lines(
			resolved_font,
			face,
			lines,
			pos,
			rgbaColor,
			max_w,
			font_size * props.line_height,
			layout_scale,
		)
	}

	cache := oni.ui_widget_shaped(props.id)
	lines := oni.shaped_text_ensure(
		cache,
		resolved_font.id,
		face,
		text,
		shape_max_w,
		props.direction,
	)
	if len(lines) == 0 do return {}
	return oni.font_draw_shaped_lines(
		resolved_font,
		face,
		lines,
		pos,
		rgbaColor,
		max_w,
		font_size * props.line_height,
		layout_scale,
	)
}


// ui_text_layout :: proc(
// 	id: oni.UI_Id,
// 	text: string,
// 	font: oni.Font_Handle,
// 	max_w: f32,
// 	direction: oni.Text_Direction = .LTR,
// 	font_size: f32 = 0,
// 	line_height: f32 = 0,
// 	space: oni.Draw_Space = .Screen,
// 	flags: Widget_Text_Flags = {},
// ) -> oni.Vec2 {
// 	resolved, layout_scale, ok := oni.font_resolve(font, font_size, space)
// 	if !ok do return {}

// 	face := oni.font_face_from_handle(resolved)
// 	if face == nil || len(text) == 0 do return {}

// 	shape_max_w := max_w > 0 ? max_w / layout_scale : max_w

// 	if .Uncached in flags {
// 		lines := oni.font_shape_line_build(face, text, shape_max_w, direction)
// 		if len(lines) == 0 do return {}
// 		defer oni.font_destroy_shaped_lines(lines)
// 		return oni.font_measure_lines(face, lines, line_height, layout_scale)
// 	}

// 	cache := oni.ui_widget_shaped(id)
// 	lines := oni.shaped_text_ensure(cache, resolved.id, face, text, shape_max_w, direction)
// 	if len(lines) == 0 do return {}
// 	return oni.font_measure_lines(face, lines, line_height, layout_scale)
// }

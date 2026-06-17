package app

Widget_Text_Flag :: enum {
	Uncached,
}

Widget_Text_Flags :: bit_set[Widget_Text_Flag; i32]

ui_label :: proc(
	id: UI_Id,
	rect: Rect,
	text: string,
	font: Font_Handle,
	color: Color,
	flags: Widget_Text_Flags = {},
) -> Vec2 {
	return ui_text_draw(id, rect, text, font, color, 0, .LTR, flags)
}

ui_text :: proc(
	id: UI_Id,
	rect: Rect,
	text: string,
	font: Font_Handle,
	color: Color,
	flags: Widget_Text_Flags = {},
) -> Vec2 {
	return ui_text_draw(id, rect, text, font, color, rect.w, .LTR, flags)
}

ui_text_draw :: proc(
	id: UI_Id,
	rect: Rect,
	text: string,
	font: Font_Handle,
	color: Color,
	max_w: f32,
	direction: Text_Direction,
	flags: Widget_Text_Flags,
) -> Vec2 {
	face := font_face_from_handle(font)
	if face == nil || len(text) == 0 do return {}

	pos := Vec2{rect.x, rect.y}

	if .Uncached in flags {
		lines := font_shape_line_build(face, text, max_w, direction)
		if len(lines) == 0 do return {}
		defer font_destroy_shaped_lines(lines)
		return font_draw_shaped_lines(font, face, lines, pos, color, max_w)
	}

	cache := ui_widget_shaped(id)
	lines := shaped_text_ensure(cache, font.id, face, text, max_w, direction)
	if len(lines) == 0 do return {}
	return font_draw_shaped_lines(font, face, lines, pos, color, max_w)
}

ui_label_measure :: proc(
	id: UI_Id,
	text: string,
	font: Font_Handle,
	flags: Widget_Text_Flags = {},
) -> Vec2 {
	return ui_text_measure(id, text, font, 0, .LTR, flags)
}

ui_text_measure :: proc(
	id: UI_Id,
	text: string,
	font: Font_Handle,
	max_w: f32,
	direction: Text_Direction = .LTR,
	flags: Widget_Text_Flags = {},
) -> Vec2 {
	face := font_face_from_handle(font)
	if face == nil || len(text) == 0 do return {}

	if .Uncached in flags {
		lines := font_shape_line_build(face, text, max_w, direction)
		if len(lines) == 0 do return {}
		defer font_destroy_shaped_lines(lines)
		return font_measure_lines(face, lines)
	}

	cache := ui_widget_shaped(id)
	lines := shaped_text_ensure(cache, font.id, face, text, max_w, direction)
	if len(lines) == 0 do return {}
	return font_measure_lines(face, lines)
}

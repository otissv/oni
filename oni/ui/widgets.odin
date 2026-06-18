package ui

import ngin "../engine"

Widget_Text_Flag :: enum {
	Uncached,
}

Widget_Text_Flags :: bit_set[Widget_Text_Flag;i32]

ui_label :: proc(
	id: ngin.UI_Id,
	rect: ngin.Rect,
	text: string,
	font: ngin.Font_Handle,
	color: ngin.Color,
	flags: Widget_Text_Flags = {},
) -> ngin.Vec2 {
	return ui_text_draw(id, rect, text, font, color, 0, .LTR, flags)
}

ui_text :: proc(
	id: ngin.UI_Id,
	rect: ngin.Rect,
	text: string,
	font: ngin.Font_Handle,
	color: ngin.Color,
	flags: Widget_Text_Flags = {},
) -> ngin.Vec2 {
	return ui_text_draw(id, rect, text, font, color, rect.w, .LTR, flags)
}

ui_text_draw :: proc(
	id: ngin.UI_Id,
	rect: ngin.Rect,
	text: string,
	font: ngin.Font_Handle,
	color: ngin.Color,
	max_w: f32,
	direction: ngin.Text_Direction,
	flags: Widget_Text_Flags,
) -> ngin.Vec2 {
	face := ngin.font_face_from_handle(font)
	if face == nil || len(text) == 0 do return {}

	pos := ngin.Vec2{rect.x, rect.y}

	if .Uncached in flags {
		lines := ngin.font_shape_line_build(face, text, max_w, direction)
		if len(lines) == 0 do return {}
		defer ngin.font_destroy_shaped_lines(lines)
		return ngin.font_draw_shaped_lines(font, face, lines, pos, color, max_w)
	}

	cache := ui_widget_shaped(id)
	lines := ngin.shaped_text_ensure(cache, font.id, face, text, max_w, direction)
	if len(lines) == 0 do return {}
	return ngin.font_draw_shaped_lines(font, face, lines, pos, color, max_w)
}

ui_label_measure :: proc(
	id: ngin.UI_Id,
	text: string,
	font: ngin.Font_Handle,
	flags: Widget_Text_Flags = {},
) -> ngin.Vec2 {
	return ui_text_measure(id, text, font, 0, .LTR, flags)
}

ui_text_measure :: proc(
	id: ngin.UI_Id,
	text: string,
	font: ngin.Font_Handle,
	max_w: f32,
	direction: ngin.Text_Direction = .LTR,
	flags: Widget_Text_Flags = {},
) -> ngin.Vec2 {
	face := ngin.font_face_from_handle(font)
	if face == nil || len(text) == 0 do return {}

	if .Uncached in flags {
		lines := ngin.font_shape_line_build(face, text, max_w, direction)
		if len(lines) == 0 do return {}
		defer ngin.font_destroy_shaped_lines(lines)
		return ngin.font_measure_lines(face, lines)
	}

	cache := ui_widget_shaped(id)
	lines := ngin.shaped_text_ensure(cache, font.id, face, text, max_w, direction)
	if len(lines) == 0 do return {}
	return ngin.font_measure_lines(face, lines)
}

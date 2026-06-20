package app

import oni "../oni"
import w "../oni/widgets"
import "core:fmt"


Heading :: proc() {
	theme := &persistent.app.theme
	x: f32 = 100
	y: f32 = 100

	w.Text(
		{
			id = "heading",
			rect = {x, y, 480, 28},
			text = "Artboard text — zoomable",
			font = theme.font_heading,
			color = oni.theme.palette[.Accent],
			font_size = 20,
			line_height = 0,
			space = .Artboard,
		},
	)
}

Paragraph :: proc() {
	theme := &persistent.app.theme
	text_rect := oni.Rect{100, 132, 480, 200}


	paragraph_color :: proc(
		state: oni.Widget_State,
		widget_event: oni.Widget_Event(oni.Widget_State),
	) -> oni.Colors {
		if state.is_Pressed do return oni.RGBA{0, 0, 0, 255}
		if state.is_hovered do return oni.RGBA{210, 60, 60, 255}
		return oni.theme.palette[.Text]
	}

	paragraph := w.Text_Props {
		id          = "paragraph",
		rect        = text_rect,
		text        = "ui_paragraph in artboard space. Scroll to zoom (quantized 0.1 steps). Pan with middle mouse or Alt+drag. Glyphs re-rasterize at the display size so text stays sharp.",
		font        = theme.font_body,
		font_size   = 20,
		line_height = 1.5,
		space       = .Artboard,
		flags       = {},
		max_w       = text_rect.w,
	}
	paragraph.color = paragraph_color
	w.Text(paragraph)
}

Hud :: proc() {
	theme := &persistent.app.theme
	zoom := oni.View_Effective_Zoom()

	hud := fmt.tprintf(
		"Screen HUD  zoom: %.1fx  (scroll / Ctrl+=/- zoom, Ctrl+0 reset, Alt+LMB pan)",
		zoom,
	)
	w.Text(
		{
			id = "hud-zoom",
			rect = {16, 16, 600, 24},
			text = hud,
			font = theme.font_body,
			color = oni.theme.palette[.White],
			text_direction = .LTR,
			font_size = 16,
			line_height = 1,
			space = .Screen,
		},
	)
}


app_draw :: proc() {
	w.BeginFrame()

	oni.Begin_Artboard()

	panel := oni.Rect{80, 80, 520, 340}
	oni.Draw_Rectangle(panel, oni.theme.palette[.Surface], 10)

	Heading()
	Paragraph()
	oni.End_Artboard()

	oni.Begin_Screen()
	Hud()
	oni.End_Screen()
}

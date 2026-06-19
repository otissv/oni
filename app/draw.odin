package app

import oni "../oni"
import w "../oni/widgets"
import "core:fmt"

app_draw :: proc() {
	theme := &persistent.app.theme
	zoom := oni.View_Effective_Zoom()

	oni.Draw_Push_Artboard()

	panel := oni.Rect{80, 80, 520, 340}
	oni.Draw_Rectangle(panel, oni.theme.palette[.Surface], 10)

	x: f32 = 100
	y: f32 = 100

	w.Text(
		{
			id = oni.ui_id("heading"),
			rect = {x, y, 480, 28},
			text = "Artboard text — zoomable",
			font = theme.font_heading,
			color = oni.theme.palette[.Accent],
			direction = .LTR,
			font_size = 20,
			line_height = 0,
			space = .Artboard,
		},
	)
	y += 32

	text_rect := oni.Rect{x, y, 480, 200}
	w.Text(
		{
			id = oni.ui_id("paragraph"),
			rect = text_rect,
			text = "ui_paragraph in artboard space. Scroll to zoom (quantized 0.1 steps). Pan with middle mouse or Alt+drag. Glyphs re-rasterize at the display size so text stays sharp.",
			font = theme.font_body,
			color = oni.theme.palette[.Text],
			direction = .LTR,
			font_size = 20,
			line_height = 1.5,
			space = .Artboard,
			flags = {},
			max_w = text_rect.w,
		},
	)

	oni.Draw_Pop_Artboard()

	oni.Draw_Push_Screen()

	hud := fmt.tprintf(
		"Screen HUD  zoom: %.1fx  (scroll / Ctrl+=/- zoom, Ctrl+0 reset, Alt+LMB pan)",
		zoom,
	)
	w.Text(
		{
			id = oni.ui_id("hud-zoom"),
			rect = {16, 16, 600, 24},
			text = hud,
			font = theme.font_body,
			color = oni.theme.palette[.White],
			direction = .LTR,
			font_size = 16,
			line_height = 1,
			space = .Screen,
		},
	)

	oni.Draw_Pop_Screen()
}

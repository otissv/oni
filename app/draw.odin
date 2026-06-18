package app

import oni "../oni"
import widgets "../oni/widgets"
import "core:fmt"

app_draw :: proc() {
	theme := &persistent.app.theme
	zoom := oni.View_Effective_Zoom()

	oni.Draw_Push_Artboard()

	panel := oni.Rect{80, 80, 520, 340}
	oni.Draw_Rectangle(panel, oni.Theme_Get_Color(theme, .Surface), theme.radius_md)

	x: f32 = 100
	y: f32 = 100

	widgets.ui_text(
		oni.ui_id("heading"),
		{x, y, 480, 28},
		"Artboard text — zoomable",
		theme.font_heading,
		oni.Theme_Get_Color(theme, .Accent),
		.LTR,
		20,
		0,
		.Artboard,
	)
	y += 32

	para_rect := oni.Rect{x, y, 480, 200}
	widgets.ui_paragraph(
		oni.ui_id("paragraph"),
		para_rect,
		"ui_paragraph in artboard space. Scroll to zoom (quantized 0.1 steps). Pan with middle mouse or Alt+drag. Glyphs re-rasterize at the display size so text stays sharp.",
		theme.font_body,
		oni.Theme_Get_Color(theme, .Text_Muted),
		.LTR,
		16,
		0,
		.Artboard,
	)

	oni.Draw_Pop_Artboard()

	oni.Draw_Push_Screen()

	hud := fmt.tprintf(
		"Screen HUD  zoom: %.1fx  (scroll / Ctrl+=/- zoom, Ctrl+0 reset, Alt+LMB pan)",
		zoom,
	)
	widgets.ui_text(
		oni.ui_id("hud-zoom"),
		{16, 16, 600, 24},
		hud,
		theme.font_body,
		oni.Theme_Get_Color(theme, .Text),
		.LTR,
		14,
		0,
		.Screen,
	)

	oni.Draw_Pop_Screen()
}

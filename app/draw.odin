package app

import "core:fmt"
import "oni:engine"
import ui "oni:ui"

app_draw :: proc() {
	theme := &persistent.app.theme
	zoom := engine.View_Effective_Zoom()

	engine.Draw_Push_Artboard()

	panel := engine.Rect{80, 80, 520, 340}
	engine.Draw_Rectangle(panel, engine.Theme_Get_Color(theme, .Surface), theme.radius_md)

	x: f32 = 100
	y: f32 = 100

	ui.ui_text(
		ui.ui_id("heading"),
		{x, y, 480, 28},
		"Artboard text — zoomable",
		theme.font_heading,
		engine.Theme_Get_Color(theme, .Accent),
		.LTR,
		20,
		0,
		.Artboard,
	)
	y += 32

	para_rect := engine.Rect{x, y, 480, 200}
	ui.ui_paragraph(
		ui.ui_id("paragraph"),
		para_rect,
		"ui_paragraph in artboard space. Scroll to zoom (quantized 0.1 steps). Pan with middle mouse or Alt+drag. Glyphs re-rasterize at the display size so text stays sharp.",
		theme.font_body,
		engine.Theme_Get_Color(theme, .Text_Muted),
		.LTR,
		16,
		0,
		.Artboard,
	)

	engine.Draw_Pop_Artboard()

	engine.Draw_Push_Screen()

	hud := fmt.tprintf(
		"Screen HUD  zoom: %.1fx  (scroll / Ctrl+=/- zoom, Ctrl+0 reset, Alt+LMB pan)",
		zoom,
	)
	ui.ui_text(
		ui.ui_id("hud-zoom"),
		{16, 16, 600, 24},
		hud,
		theme.font_body,
		engine.Theme_Get_Color(theme, .Text),
		.LTR,
		14,
		0,
		.Screen,
	)

	engine.Draw_Pop_Screen()
}

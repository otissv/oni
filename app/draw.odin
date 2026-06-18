package app

import "oni:engine"
import ui "oni:ui"

app_draw :: proc() {
	theme := &persistent.app.theme

	panel := engine.Rect{80, 80, 520, 340}
	engine.Draw_Rectangle(panel, engine.Theme_Get_Color(theme, .Surface), theme.radius_md)

	x: f32 = 100
	y: f32 = 100

	// ui.ui_text(
	// 	ui.ui_id("heading"),
	// 	{x, y, 480, 28},
	// 	"ui_text — heading font, accent",
	// 	theme.font_heading,
	// 	engine.Theme_Get_Color(theme, .Accent),
	// 	.LTR,
	// )
	// y += 36

	// ui.ui_text(
	// 	ui.ui_id("body-text"),
	// 	{x, y, 480, 22},
	// 	"ui_text — body font, default text color",
	// 	theme.font_body,
	// 	engine.Theme_Get_Color(theme, .Text),
	// 	.LTR,
	// )
	// y += 28

	// ui.ui_text(
	// 	ui.ui_id("body-success"),
	// 	{x, y, 480, 22},
	// 	"ui_text — body font, success color",
	// 	theme.font_body,
	// 	engine.Theme_Get_Color(theme, .Success),
	// 	.LTR,
	// )
	// y += 28

	// ui.ui_text(
	// 	ui.ui_id("body-danger"),
	// 	{x, y, 480, 22},
	// 	"ui_text — body font, danger color",
	// 	theme.font_body,
	// 	engine.Theme_Get_Color(theme, .Danger),
	// 	.LTR,
	// )
	// y += 40

	para_rect := engine.Rect{x, y, 480, 120}
	ui.ui_paragraph(
		ui.ui_id("paragraph"),
		para_rect,
		"ui_paragraph wraps long copy inside the rect width. This example uses the body font with muted text color — useful for descriptions, tooltips, or dialogue blocks.",
		theme.font_body,
		engine.Theme_Get_Color(theme, .Text_Muted),
		.LTR,
		50,
		50 * 1.5,
	)
}

package app

import "oni:engine"

app_draw :: proc() {
	theme := &persistent.app.theme
	engine.Draw_Rectangle(
		{100, 100, 200, 80},
		engine.Theme_Get_Color(theme, .Accent),
		theme.radius_sm,
	)
}

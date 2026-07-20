package app

import o "../oni"


WINDOW_WIDTH :: 1280
WINDOW_HEIGHT :: 720
WINDOW_TITLE :: "Oni GUI"

MIN_WINDOW_W :: 320
MIN_WINDOW_H :: 180
INTER_FONT_PATH :: "assets/fonts/Inter-VariableFont_opsz,wght.ttf"
INTER_ITALIC_FONT_PATH :: "assets/fonts/Inter-Italic-VariableFont_opsz,wght.ttf"
FONT_BODY_SIZE :: f32(16)
FONT_HEADING_SIZE :: f32(20)

/*
Builds the default app theme with Inter body and heading fonts.

Registers the Inter family (roman + italic variable fonts) and logs errors on
failure. Palette, spacing, and layout defaults come from o.
*/
build_theme :: proc() -> o.Theme {
	inter, inter_ok := o.Register_Font_Family(
		"Inter",
		{
			{path = INTER_FONT_PATH, style = .NORMAL, weight = .Normal},
			{path = INTER_ITALIC_FONT_PATH, style = .ITALIC, weight = .Normal},
		},
	)
	if !inter_ok {
		o.Log_Errorf("build_theme: failed to register Inter font family")
	}

	body := o.Font_With_Size(inter, FONT_BODY_SIZE)
	heading := o.Font_With_Size(inter, FONT_HEADING_SIZE)

	return o.Theme {
		palette = o.palette,
		font_body = body,
		font_heading = heading,
		justify = o.Justify_Pos{x = .START, y = .START},
		direction = .HORIZONTAL,
		border_color = .BLACK,
		ring = .RING,
		background = .BACKGROUND,
		padding = 0,
		radius = 0,
		border = 0,
		width = 0,
		height = 0,
	}
}

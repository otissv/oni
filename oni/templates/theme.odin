package app

import oni "../oni"


ZOOM_WHEEL_STEP :: oni.VIEW_ZOOM_STEP
WINDOW_WIDTH :: 1280
WINDOW_HEIGHT :: 720
WINDOW_TITLE :: "Odin + SDL3"

MIN_WINDOW_W :: 320
MIN_WINDOW_H :: 180
INTER_FONT_PATH :: "assets/fonts/Inter-VariableFont_opsz,wght.ttf"
INTER_ITALIC_FONT_PATH :: "assets/fonts/Inter-Italic-VariableFont_opsz,wght.ttf"
FONT_BODY_SIZE :: f32(16)
FONT_HEADING_SIZE :: f32(20)

/*
Builds the default app theme with Inter body and heading fonts.

Registers the Inter family (roman + italic variable fonts) and logs errors on
failure. Palette, spacing, and layout defaults come from oni.
*/
build_theme :: proc() -> oni.Theme {
	inter, inter_ok := oni.Register_Font_Family(
		"Inter",
		{
			{path = INTER_FONT_PATH, style = .NORMAL, weight = oni.FONT_WEIGHT_NORMAL},
			{path = INTER_ITALIC_FONT_PATH, style = .ITALIC, weight = oni.FONT_WEIGHT_NORMAL},
		},
	)
	if !inter_ok {
		oni.Log_Errorf("build_theme: failed to register Inter font family")
	}

	body := oni.Font_With_Size(inter, FONT_BODY_SIZE)
	heading := oni.Font_With_Size(inter, FONT_HEADING_SIZE)

	return oni.Theme {
		palette = oni.palette,
		font_body = body,
		font_heading = heading,
		gap_x = 20,
		gap_y = 20,
		justify = oni.Justify_Pos{x = .START, y = .START},
		direction = .HORIZONTAL,
		border_color = .BLACK,
		background = .TRANSPARENT,
		padding = 0,
		radius = 0,
		border = 0,
		width = 0,
		height = 0,
	}
}

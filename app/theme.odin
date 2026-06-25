package app

import oni "../oni"


ZOOM_WHEEL_STEP :: oni.VIEW_ZOOM_STEP
WINDOW_WIDTH :: 1280
WINDOW_HEIGHT :: 720
WINDOW_TITLE :: "Odin + SDL3"

MIN_WINDOW_W :: 320
MIN_WINDOW_H :: 180
INTER_FONT_PATH :: "assets/fonts/Inter-VariableFont_opsz,wght.ttf"
FONT_BODY_SIZE :: f32(16)
FONT_HEADING_SIZE :: f32(20)

/*
Builds the default app theme with Inter body and heading fonts.

Loads font faces from INTER_FONT_PATH and logs errors for any face that
fails to load. Palette, spacing, and layout defaults come from oni.
*/
build_theme :: proc() -> oni.Theme {
	body, body_ok := oni.Load_Font_Face(INTER_FONT_PATH, FONT_BODY_SIZE)
	heading, heading_ok := oni.Load_Font_Face(INTER_FONT_PATH, FONT_HEADING_SIZE)
	if !body_ok {
		oni.Log_Errorf("build_theme: failed to load body font %q", INTER_FONT_PATH)
	}
	if !heading_ok {
		oni.Log_Errorf("build_theme: failed to load heading font %q", INTER_FONT_PATH)
	}

	return oni.Theme {
		palette = oni.palette,
		font_body = body,
		font_heading = heading,
		gap = 20,
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

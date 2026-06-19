package app

import oni "../oni"

INTER_FONT_PATH :: "assets/fonts/Inter-VariableFont_opsz,wght.ttf"
FONT_BODY_SIZE :: f32(16)
FONT_HEADING_SIZE :: f32(20)

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
		alignChild = oni.Align_Pos{x = .Left, y = .Top},
		direction = .Horizontal,
		bdColor = .Black,
		bg = .Transparent,
		pd = 0,
		rd = 0,
		bd = 0,
		width = 0,
		height = 0,
	}
}

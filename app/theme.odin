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
		bg              = {30, 30, 35, 255},
		surface         = {42, 42, 48, 255},
		border          = {64, 64, 72, 255},
		text            = {235, 235, 240, 255},
		text_muted      = {160, 160, 170, 255},
		accent          = {88, 130, 255, 255},
		accent_hover    = {110, 150, 255, 255},
		accent_pressed  = {70, 110, 230, 255},
		danger          = {235, 90, 90, 255},
		success         = {90, 200, 130, 255},
		spacing_xs      = 4,
		spacing_sm      = 8,
		spacing_md      = 16,
		spacing_lg      = 24,
		radius_sm       = 4,
		radius_md       = 8,
		font_body       = body,
		font_heading    = heading,
	}
}

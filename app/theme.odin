package app

Theme_Color_Role :: enum {
	Bg,
	Surface,
	Border,
	Text,
	Text_Muted,
	Accent,
	Accent_Hover,
	Accent_Pressed,
	Danger,
	Success,
}

theme_dark :: proc() -> Theme {
	body, body_ok := font_load_face(INTER_FONT_PATH, FONT_BODY_SIZE)
	heading, heading_ok := font_load_face(INTER_FONT_PATH, FONT_HEADING_SIZE)
	if !body_ok {
		log_errorf("theme_dark: failed to load body font %q", INTER_FONT_PATH)
	}
	if !heading_ok {
		log_errorf("theme_dark: failed to load heading font %q", INTER_FONT_PATH)
	}

	return Theme {
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

theme_light :: proc() -> Theme {
	body, body_ok := font_load_face(INTER_FONT_PATH, FONT_BODY_SIZE)
	heading, heading_ok := font_load_face(INTER_FONT_PATH, FONT_HEADING_SIZE)
	if !body_ok {
		log_errorf("theme_light: failed to load body font %q", INTER_FONT_PATH)
	}
	if !heading_ok {
		log_errorf("theme_light: failed to load heading font %q", INTER_FONT_PATH)
	}

	return Theme {
		bg              = {248, 248, 250, 255},
		surface         = {255, 255, 255, 255},
		border          = {210, 210, 218, 255},
		text            = {24, 24, 28, 255},
		text_muted      = {110, 110, 120, 255},
		accent          = {58, 100, 235, 255},
		accent_hover    = {78, 120, 245, 255},
		accent_pressed  = {48, 88, 215, 255},
		danger          = {210, 60, 60, 255},
		success         = {40, 160, 90, 255},
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

theme_default :: proc(assets: ^Asset_Cache) -> Theme {
	_ = assets
	return theme_dark()
}

theme_color :: proc(t: ^Theme, role: Theme_Color_Role) -> Color {
	switch role {
	case .Bg:
		return t.bg
	case .Surface:
		return t.surface
	case .Border:
		return t.border
	case .Text:
		return t.text
	case .Text_Muted:
		return t.text_muted
	case .Accent:
		return t.accent
	case .Accent_Hover:
		return t.accent_hover
	case .Accent_Pressed:
		return t.accent_pressed
	case .Danger:
		return t.danger
	case .Success:
		return t.success
	}
	return {}
}

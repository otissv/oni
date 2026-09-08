package app

import o "../oni"

/*
Builds the default app theme with fonts from settings.kdl.

Replaces registered font families from settings, then sets body/heading sizes.
Engine Inter faces are used when settings omit faces.
Palette, spacing, and layout defaults come from o.
*/
build_theme :: proc() -> o.Theme {
	s := o.Settings_Get()
	body_size := o.SETTINGS_DEFAULT_FONT_BODY_SIZE
	heading_size := o.SETTINGS_DEFAULT_FONT_HEADING_SIZE
	if s != nil {
		body_size = s.font_body_size
		heading_size = s.font_heading_size
	}

	family, family_ok := o.Settings_Register_Fonts()
	if !family_ok {
		name := o.SETTINGS_DEFAULT_FONT_FAMILY
		if s != nil do name = s.font_family
		o.Log_Errorf("build_theme: failed to register %s font family", name)
	}

	body := o.Font_With_Size(family, body_size)
	heading := o.Font_With_Size(family, heading_size)

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

package oni

shortcut_defaults :: proc() {
	shortcut_bind_key(
		SHORTCUT_VIEW_ZOOM_IN,
		{key = .EQUALS, ctrl = true},
		.Global,
		"",
		{},
		0,
		true,
		.Builtin,
	)
	shortcut_bind_key(
		SHORTCUT_VIEW_ZOOM_IN,
		{key = .KP_PLUS, ctrl = true},
		.Global,
		"",
		{},
		0,
		true,
		.Builtin,
	)
	_ = shortcut_bind_wheel_src(SHORTCUT_VIEW_ZOOM_IN, 1, {ctrl = true}, {}, .Builtin)

	shortcut_bind_key(
		SHORTCUT_VIEW_ZOOM_OUT,
		{key = .MINUS, ctrl = true},
		.Global,
		"",
		{},
		0,
		true,
		.Builtin,
	)
	shortcut_bind_key(
		SHORTCUT_VIEW_ZOOM_OUT,
		{key = .KP_MINUS, ctrl = true},
		.Global,
		"",
		{},
		0,
		true,
		.Builtin,
	)
	_ = shortcut_bind_wheel_src(SHORTCUT_VIEW_ZOOM_OUT, -1, {ctrl = true}, {}, .Builtin)

	shortcut_bind_key(
		SHORTCUT_VIEW_RESET,
		{key = ._0, ctrl = true},
		.Global,
		"",
		{},
		0,
		true,
		.Builtin,
	)
	shortcut_bind_key(
		SHORTCUT_VIEW_RESET,
		{key = .KP_0, ctrl = true},
		.Global,
		"",
		{},
		0,
		true,
		.Builtin,
	)

	shortcut_bind_key(
		SHORTCUT_WINDOW_TOGGLE_FULLSCREEN,
		{key = .F11},
		.Global,
		"",
		{},
		0,
		true,
		.Builtin,
	)
	_ = shortcut_bind_gamepad_src(SHORTCUT_WINDOW_TOGGLE_FULLSCREEN, .START, {}, .Builtin)

	shortcut_bind_key(SHORTCUT_HOST_RELOAD, {key = .F5}, .Global, "", {}, 0, true, .Builtin)
	shortcut_bind_key(SHORTCUT_HOST_RESTART, {key = .F6}, .Global, "", {}, 0, true, .Builtin)


}

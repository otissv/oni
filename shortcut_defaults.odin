package oni


shortcut_defaults :: proc() {
	shortcut_bind_key(
		{
			id = SHORTCUT_VIEW_ZOOM_IN,
			chord = {key = .EQUALS, ctrl = true},
			scope = .Global,
			enabled = true,
			source = .Builtin,
		},
	)

	shortcut_bind_key(
		{
			id = SHORTCUT_VIEW_ZOOM_IN,
			chord = {key = .KP_PLUS, ctrl = true},
			scope = .Global,
			enabled = true,
			source = .Builtin,
		},
	)

	_ = shortcut_bind_wheel(
		{
			id = SHORTCUT_VIEW_ZOOM_IN,
			wheel_sign = 1,
			chord = {ctrl = true},
			enabled = true,
			source = .Builtin,
		},
	)

	shortcut_bind_key(
		{
			id = SHORTCUT_VIEW_ZOOM_OUT,
			chord = {key = .MINUS, ctrl = true},
			scope = .Global,
			enabled = true,
			source = .Builtin,
		},
	)

	shortcut_bind_key(
		{
			id = SHORTCUT_VIEW_ZOOM_OUT,
			chord = {key = .KP_MINUS, ctrl = true},
			scope = .Global,
			enabled = true,
			source = .Builtin,
		},
	)
	_ = shortcut_bind_wheel(
		{
			id = SHORTCUT_VIEW_ZOOM_OUT,
			wheel_sign = -1,
			chord = {ctrl = true},
			enabled = true,
			source = .Builtin,
		},
	)

	shortcut_bind_key(
		{
			id = SHORTCUT_VIEW_RESET,
			chord = {key = ._0, ctrl = true},
			scope = .Global,
			enabled = true,
			source = .Builtin,
		},
	)

	shortcut_bind_key(
		{
			id = SHORTCUT_VIEW_RESET,
			chord = {key = .KP_0, ctrl = true},
			scope = .Global,
			enabled = true,
			source = .Builtin,
		},
	)

	shortcut_bind_key(
		{
			id = SHORTCUT_WINDOW_TOGGLE_FULLSCREEN,
			chord = {key = .F11},
			scope = .Global,
			enabled = true,
			source = .Builtin,
		},
	)
	_ = shortcut_bind_gamepad(
		{
			id = SHORTCUT_WINDOW_TOGGLE_FULLSCREEN,
			button = .START,
			enabled = true,
			source = .Builtin,
		},
	)

	shortcut_bind_key(
		{
			id = SHORTCUT_HOST_RELOAD,
			chord = {key = .F5},
			scope = .Global,
			enabled = true,
			source = .Builtin,
		},
	)

	shortcut_bind_key(
		{
			id = SHORTCUT_HOST_RESTART,
			chord = {key = .F6},
			scope = .Global,
			enabled = true,
			source = .Builtin,
		},
	)
}

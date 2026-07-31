package oni

/*
Universal builtins: host reload/restart. Applies to every app type.
*/
shortcut_defaults_universal :: proc() {
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

/*
View and window builtins for tool/application UIs.
*/
shortcut_defaults_view :: proc(app_type: App_Type_Filter) {
	shortcut_bind_key(
		{
			id = SHORTCUT_VIEW_ZOOM_IN,
			chord = {key = .EQUALS, ctrl = true},
			scope = .Global,
			enabled = true,
			source = .Builtin,
			app_type = app_type,
		},
	)

	shortcut_bind_key(
		{
			id = SHORTCUT_VIEW_ZOOM_IN,
			chord = {key = .KP_PLUS, ctrl = true},
			scope = .Global,
			enabled = true,
			source = .Builtin,
			app_type = app_type,
		},
	)

	_ = shortcut_bind_wheel(
		{
			id = SHORTCUT_VIEW_ZOOM_IN,
			wheel_sign = 1,
			chord = {ctrl = true},
			enabled = true,
			source = .Builtin,
			app_type = app_type,
		},
	)

	shortcut_bind_key(
		{
			id = SHORTCUT_VIEW_ZOOM_OUT,
			chord = {key = .MINUS, ctrl = true},
			scope = .Global,
			enabled = true,
			source = .Builtin,
			app_type = app_type,
		},
	)

	shortcut_bind_key(
		{
			id = SHORTCUT_VIEW_ZOOM_OUT,
			chord = {key = .KP_MINUS, ctrl = true},
			scope = .Global,
			enabled = true,
			source = .Builtin,
			app_type = app_type,
		},
	)
	_ = shortcut_bind_wheel(
		{
			id = SHORTCUT_VIEW_ZOOM_OUT,
			wheel_sign = -1,
			chord = {ctrl = true},
			enabled = true,
			source = .Builtin,
			app_type = app_type,
		},
	)

	shortcut_bind_key(
		{
			id = SHORTCUT_VIEW_RESET,
			chord = {key = ._0, ctrl = true},
			scope = .Global,
			enabled = true,
			source = .Builtin,
			app_type = app_type,
		},
	)

	shortcut_bind_key(
		{
			id = SHORTCUT_VIEW_RESET,
			chord = {key = .KP_0, ctrl = true},
			scope = .Global,
			enabled = true,
			source = .Builtin,
			app_type = app_type,
		},
	)

	shortcut_bind_key(
		{
			id = SHORTCUT_WINDOW_TOGGLE_FULLSCREEN,
			chord = {key = .F11},
			scope = .Global,
			enabled = true,
			source = .Builtin,
			app_type = app_type,
		},
	)

	_ = shortcut_bind_gamepad(
		{
			id = SHORTCUT_WINDOW_TOGGLE_FULLSCREEN,
			button = .START,
			enabled = true,
			source = .Builtin,
			app_type = app_type,
		},
	)
}

/*
Game-oriented builtins: gamepad fullscreen toggle.
*/
shortcut_defaults_game :: proc(app_type: App_Type_Filter) {
	_ = shortcut_bind_gamepad(
		{
			id = SHORTCUT_WINDOW_TOGGLE_FULLSCREEN,
			button = .START,
			enabled = true,
			source = .Builtin,
			app_type = app_type,
		},
	)
}

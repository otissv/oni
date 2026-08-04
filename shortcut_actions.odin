package oni

Shortcut_Action_Type :: enum {
	// App
	SHORTCUT_APP_QUIT,
	SHORTCUT_HOST_RELOAD,
	SHORTCUT_HOST_RESTART,

	// View
	SHORTCUT_VIEW_ZOOM_IN,
	SHORTCUT_VIEW_ZOOM_OUT,
	SHORTCUT_VIEW_RESET,
	SHORTCUT_WINDOW_TOGGLE_FULLSCREEN,

	// Edit — clipboard / history
	SHORTCUT_EDIT_SELECT_ALL,
	SHORTCUT_EDIT_COPY,
	SHORTCUT_EDIT_CUT,
	SHORTCUT_EDIT_PASTE,
	SHORTCUT_EDIT_UNDO,
	SHORTCUT_EDIT_REDO,

	// Edit — caret navigation
	SHORTCUT_EDIT_MOVE_LEFT,
	SHORTCUT_EDIT_MOVE_RIGHT,
	SHORTCUT_EDIT_MOVE_UP,
	SHORTCUT_EDIT_MOVE_DOWN,
	SHORTCUT_EDIT_MOVE_HOME,
	SHORTCUT_EDIT_MOVE_END,
	SHORTCUT_EDIT_PAGE_UP,
	SHORTCUT_EDIT_PAGE_DOWN,

	// Edit — mutation
	SHORTCUT_EDIT_BACKSPACE,
	SHORTCUT_EDIT_DELETE,
	SHORTCUT_EDIT_NEWLINE,
}


shortcut_action_types: [Shortcut_Action_Type]string = {
	// App
	.SHORTCUT_APP_QUIT                 = "app.quit",
	.SHORTCUT_HOST_RELOAD              = "host.reload",
	.SHORTCUT_HOST_RESTART             = "host.restart",

	// View
	.SHORTCUT_VIEW_ZOOM_IN             = "view.zoom_in",
	.SHORTCUT_VIEW_ZOOM_OUT            = "view.zoom_out",
	.SHORTCUT_VIEW_RESET               = "view.reset",
	.SHORTCUT_WINDOW_TOGGLE_FULLSCREEN = "window.toggle_fullscreen",

	// Edit — clipboard / history
	.SHORTCUT_EDIT_SELECT_ALL          = "edit.select_all",
	.SHORTCUT_EDIT_COPY                = "edit.copy",
	.SHORTCUT_EDIT_CUT                 = "edit.cut",
	.SHORTCUT_EDIT_PASTE               = "edit.paste",
	.SHORTCUT_EDIT_UNDO                = "edit.undo",
	.SHORTCUT_EDIT_REDO                = "edit.redo",

	// Edit — caret navigation
	.SHORTCUT_EDIT_MOVE_LEFT           = "edit.move_left",
	.SHORTCUT_EDIT_MOVE_RIGHT          = "edit.move_right",
	.SHORTCUT_EDIT_MOVE_UP             = "edit.move_up",
	.SHORTCUT_EDIT_MOVE_DOWN           = "edit.move_down",
	.SHORTCUT_EDIT_MOVE_HOME           = "edit.move_home",
	.SHORTCUT_EDIT_MOVE_END            = "edit.move_end",
	.SHORTCUT_EDIT_PAGE_UP             = "edit.page_up",
	.SHORTCUT_EDIT_PAGE_DOWN           = "edit.page_down",

	// Edit — mutation
	.SHORTCUT_EDIT_BACKSPACE           = "edit.backspace",
	.SHORTCUT_EDIT_DELETE              = "edit.delete",
	.SHORTCUT_EDIT_NEWLINE             = "edit.newline",
}

shortcut_labels: [Shortcut_Action_Type]string = {
	// App
	.SHORTCUT_APP_QUIT                 = "Quit",
	.SHORTCUT_HOST_RELOAD              = "Hot Reload",
	.SHORTCUT_HOST_RESTART             = "Hot Restart",

	// View
	.SHORTCUT_VIEW_ZOOM_IN             = "Zoom In",
	.SHORTCUT_VIEW_ZOOM_OUT            = "Zoom Out",
	.SHORTCUT_VIEW_RESET               = "Reset View",
	.SHORTCUT_WINDOW_TOGGLE_FULLSCREEN = "Toggle Fullscreen",

	// Edit — clipboard / history
	.SHORTCUT_EDIT_SELECT_ALL          = "Select All",
	.SHORTCUT_EDIT_COPY                = "Copy",
	.SHORTCUT_EDIT_CUT                 = "Cut",
	.SHORTCUT_EDIT_PASTE               = "Paste",
	.SHORTCUT_EDIT_UNDO                = "Undo",
	.SHORTCUT_EDIT_REDO                = "Redo",

	// Edit — caret navigation
	.SHORTCUT_EDIT_MOVE_LEFT           = "Move Left",
	.SHORTCUT_EDIT_MOVE_RIGHT          = "Move Right",
	.SHORTCUT_EDIT_MOVE_UP             = "Move Up",
	.SHORTCUT_EDIT_MOVE_DOWN           = "Move Down",
	.SHORTCUT_EDIT_MOVE_HOME           = "Move to Start",
	.SHORTCUT_EDIT_MOVE_END            = "Move to End",
	.SHORTCUT_EDIT_PAGE_UP             = "Page Up",
	.SHORTCUT_EDIT_PAGE_DOWN           = "Page Down",

	// Edit — mutation
	.SHORTCUT_EDIT_BACKSPACE           = "Backspace",
	.SHORTCUT_EDIT_DELETE              = "Delete",
	.SHORTCUT_EDIT_NEWLINE             = "New Line",
}


register_shortcut_actions :: proc() {
	// App
	shortcut_register_action(Shortcut_Action_Type.SHORTCUT_APP_QUIT, shortcut_action_app_quit)
	shortcut_register_action(
		Shortcut_Action_Type.SHORTCUT_HOST_RELOAD,
		shortcut_action_host_reload,
	)
	shortcut_register_action(
		Shortcut_Action_Type.SHORTCUT_HOST_RESTART,
		shortcut_action_host_restart,
	)

	// View
	shortcut_register_action(
		Shortcut_Action_Type.SHORTCUT_VIEW_ZOOM_IN,
		shortcut_action_view_zoom_in,
	)
	shortcut_register_action(
		Shortcut_Action_Type.SHORTCUT_VIEW_ZOOM_OUT,
		shortcut_action_view_zoom_out,
	)
	shortcut_register_action(Shortcut_Action_Type.SHORTCUT_VIEW_RESET, shortcut_action_view_reset)
	shortcut_register_action(
		Shortcut_Action_Type.SHORTCUT_WINDOW_TOGGLE_FULLSCREEN,
		shortcut_action_toggle_fullscreen,
	)

	// Edit — clipboard / history
	shortcut_register_action(
		Shortcut_Action_Type.SHORTCUT_EDIT_SELECT_ALL,
		text_edit_action_select_all,
	)
	shortcut_register_action(Shortcut_Action_Type.SHORTCUT_EDIT_COPY, text_edit_action_copy)
	shortcut_register_action(Shortcut_Action_Type.SHORTCUT_EDIT_CUT, text_edit_action_cut)
	shortcut_register_action(Shortcut_Action_Type.SHORTCUT_EDIT_PASTE, text_edit_action_paste)
	shortcut_register_action(Shortcut_Action_Type.SHORTCUT_EDIT_UNDO, text_edit_action_undo)
	shortcut_register_action(Shortcut_Action_Type.SHORTCUT_EDIT_REDO, text_edit_action_redo)

	// Edit — caret navigation
	shortcut_register_action(
		Shortcut_Action_Type.SHORTCUT_EDIT_MOVE_LEFT,
		text_edit_action_nav_key,
	)
	shortcut_register_action(
		Shortcut_Action_Type.SHORTCUT_EDIT_MOVE_RIGHT,
		text_edit_action_nav_key,
	)
	shortcut_register_action(
		Shortcut_Action_Type.SHORTCUT_EDIT_MOVE_UP,
		text_edit_action_nav_key,
	)
	shortcut_register_action(
		Shortcut_Action_Type.SHORTCUT_EDIT_MOVE_DOWN,
		text_edit_action_nav_key,
	)
	shortcut_register_action(
		Shortcut_Action_Type.SHORTCUT_EDIT_MOVE_HOME,
		text_edit_action_nav_key,
	)
	shortcut_register_action(
		Shortcut_Action_Type.SHORTCUT_EDIT_MOVE_END,
		text_edit_action_nav_key,
	)
	shortcut_register_action(
		Shortcut_Action_Type.SHORTCUT_EDIT_PAGE_UP,
		text_edit_action_nav_key,
	)
	shortcut_register_action(
		Shortcut_Action_Type.SHORTCUT_EDIT_PAGE_DOWN,
		text_edit_action_nav_key,
	)

	// Edit — mutation
	shortcut_register_action(
		Shortcut_Action_Type.SHORTCUT_EDIT_BACKSPACE,
		text_edit_action_nav_key,
	)
	shortcut_register_action(
		Shortcut_Action_Type.SHORTCUT_EDIT_DELETE,
		text_edit_action_nav_key,
	)
	shortcut_register_action(
		Shortcut_Action_Type.SHORTCUT_EDIT_NEWLINE,
		text_edit_action_nav_key,
	)
}

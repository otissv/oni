package oni

@(private)
text_edit_bind_focused_kind :: proc(
	action: Shortcut_Action_Type,
	chord: Shortcut_Chord,
	kind: Widget_Kind,
	app_type: App_Type_Filter,
	repeat := false,
) {
	shortcut_bind_key(
		{
			id = shortcut_action_types[action],
			chord = chord,
			scope = .Focused_Kind,
			scope_kind = kind,
			enabled = true,
			source = .Builtin,
			app_type = app_type,
			repeat = repeat,
		},
	)
}

@(private)
text_edit_bind_nav_variants :: proc(
	action: Shortcut_Action_Type,
	key: Scancode,
	kind: Widget_Kind,
	app_type: App_Type_Filter,
) {
	chords := [?]Shortcut_Chord {
		{key = key},
		{key = key, ctrl = true},
		{key = key, shift = true},
		{key = key, ctrl = true, shift = true},
	}

	for chord in chords {
		text_edit_bind_focused_kind(action, chord, kind, app_type, repeat = true)
	}
}

@(private)
text_edit_bind_edit_chords :: proc(
	action: Shortcut_Action_Type,
	chord: Shortcut_Chord,
	kind: Widget_Kind,
	app_type: App_Type_Filter,
) {
	text_edit_bind_focused_kind(action, chord, kind, app_type, repeat = false)
}

text_edit_bind_default_shortcuts :: proc(app_type: App_Type_Filter) {
	_ = app_type
	edit_filter := App_Type_Filter(struct{}{})
	input_kinds := [?]Widget_Kind{.TEXT_INPUT, .RICH_TEXT_INPUT}

	for kind in input_kinds {
		text_edit_bind_edit_chords(
			.SHORTCUT_EDIT_SELECT_ALL,
			{key = .A, ctrl = true},
			kind,
			edit_filter,
		)
		text_edit_bind_edit_chords(
			.SHORTCUT_EDIT_COPY,
			{key = .C, ctrl = true},
			kind,
			edit_filter,
		)
		text_edit_bind_edit_chords(
			.SHORTCUT_EDIT_CUT,
			{key = .X, ctrl = true},
			kind,
			edit_filter,
		)
		text_edit_bind_edit_chords(
			.SHORTCUT_EDIT_PASTE,
			{key = .V, ctrl = true},
			kind,
			edit_filter,
		)
		text_edit_bind_edit_chords(
			.SHORTCUT_EDIT_UNDO,
			{key = .Z, ctrl = true},
			kind,
			edit_filter,
		)
		text_edit_bind_edit_chords(
			.SHORTCUT_EDIT_REDO,
			{key = .Z, ctrl = true, shift = true},
			kind,
			edit_filter,
		)

		when ODIN_OS != .Darwin {
			text_edit_bind_edit_chords(
				.SHORTCUT_EDIT_REDO,
				{key = .Y, ctrl = true},
				kind,
				edit_filter,
			)
		}

		text_edit_bind_nav_variants(.SHORTCUT_EDIT_MOVE_LEFT, .LEFT, kind, edit_filter)
		text_edit_bind_nav_variants(.SHORTCUT_EDIT_MOVE_RIGHT, .RIGHT, kind, edit_filter)
		text_edit_bind_nav_variants(.SHORTCUT_EDIT_MOVE_UP, .UP, kind, edit_filter)
		text_edit_bind_nav_variants(.SHORTCUT_EDIT_MOVE_DOWN, .DOWN, kind, edit_filter)
		text_edit_bind_nav_variants(.SHORTCUT_EDIT_MOVE_HOME, .HOME, kind, edit_filter)
		text_edit_bind_nav_variants(.SHORTCUT_EDIT_MOVE_END, .END, kind, edit_filter)
		text_edit_bind_nav_variants(.SHORTCUT_EDIT_PAGE_UP, .PAGEUP, kind, edit_filter)
		text_edit_bind_nav_variants(.SHORTCUT_EDIT_PAGE_DOWN, .PAGEDOWN, kind, edit_filter)

		text_edit_bind_focused_kind(
			.SHORTCUT_EDIT_BACKSPACE,
			{key = .BACKSPACE},
			kind,
			edit_filter,
			repeat = true,
		)
		text_edit_bind_focused_kind(
			.SHORTCUT_EDIT_BACKSPACE,
			{key = .BACKSPACE, ctrl = true},
			kind,
			edit_filter,
			repeat = true,
		)
		text_edit_bind_focused_kind(
			.SHORTCUT_EDIT_DELETE,
			{key = .DELETE},
			kind,
			edit_filter,
			repeat = true,
		)
		text_edit_bind_focused_kind(
			.SHORTCUT_EDIT_DELETE,
			{key = .DELETE, ctrl = true},
			kind,
			edit_filter,
			repeat = true,
		)
		text_edit_bind_focused_kind(
			.SHORTCUT_EDIT_NEWLINE,
			{key = .RETURN},
			kind,
			edit_filter,
			repeat = false,
		)
		text_edit_bind_focused_kind(
			.SHORTCUT_EDIT_NEWLINE,
			{key = .KP_ENTER},
			kind,
			edit_filter,
			repeat = false,
		)
	}

	selectable_kinds := [2]Widget_Kind{.TEXT, .RICH_TEXT}

	for kind in selectable_kinds {
		text_edit_bind_edit_chords(
			.SHORTCUT_EDIT_COPY,
			{key = .C, ctrl = true},
			kind,
			edit_filter,
		)
	}
}

text_edit_action_select_all :: proc(_: ^Shortcut_Event) {
	text_edit_set_command(.SELECT_ALL)
}

text_edit_action_copy :: proc(_: ^Shortcut_Event) {
	text_edit_set_command(.COPY)
}

text_edit_action_cut :: proc(_: ^Shortcut_Event) {
	text_edit_set_command(.CUT)
}

text_edit_action_paste :: proc(_: ^Shortcut_Event) {
	text_edit_set_command(.PASTE)
}

text_edit_action_undo :: proc(_: ^Shortcut_Event) {
	text_edit_set_command(.UNDO)
}

text_edit_action_redo :: proc(_: ^Shortcut_Event) {
	text_edit_set_command(.REDO)
}

text_edit_action_nav_key :: proc(event: ^Shortcut_Event) {
	if event == nil do return

	ctrl := event.chord.ctrl || event.chord.super
	text_edit_set_nav(event.chord.key, event.chord.shift, ctrl)
}

text_edit_shortcut_process :: proc(focused_key: string, kind: Widget_Kind) {
	shortcut_process_edit_keys(focused_key, kind)
}

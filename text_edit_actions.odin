package oni

SHORTCUT_EDIT_SELECT_ALL :: "edit.select_all"
SHORTCUT_EDIT_COPY :: "edit.copy"
SHORTCUT_EDIT_CUT :: "edit.cut"
SHORTCUT_EDIT_PASTE :: "edit.paste"
SHORTCUT_EDIT_UNDO :: "edit.undo"

text_edit_register_shortcut_actions :: proc() {
	shortcut_register_action(SHORTCUT_EDIT_SELECT_ALL, text_edit_action_select_all)
	shortcut_register_action(SHORTCUT_EDIT_COPY, text_edit_action_copy)
	shortcut_register_action(SHORTCUT_EDIT_CUT, text_edit_action_cut)
	shortcut_register_action(SHORTCUT_EDIT_PASTE, text_edit_action_paste)
	shortcut_register_action(SHORTCUT_EDIT_UNDO, text_edit_action_undo)
}

text_edit_bind_default_shortcuts :: proc() {
	input_kinds := [?]Widget_Kind{.TEXT_INPUT, .RICH_TEXT_INPUT}

	for kind in input_kinds {
		shortcut_bind_key(
			{
				id = SHORTCUT_EDIT_SELECT_ALL,
				chord = {key = .A, ctrl = true},
				scope = .Focused_Kind,
				scope_kind = kind,
				enabled = true,
				source = .Builtin,
			},
		)
		shortcut_bind_key(
			{
				id = SHORTCUT_EDIT_COPY,
				chord = {key = .C, ctrl = true},
				scope = .Focused_Kind,
				scope_kind = kind,
				enabled = true,
				source = .Builtin,
			},
		)
		shortcut_bind_key(
			{
				id = SHORTCUT_EDIT_CUT,
				chord = {key = .X, ctrl = true},
				scope = .Focused_Kind,
				scope_kind = kind,
				enabled = true,
				source = .Builtin,
			},
		)
		shortcut_bind_key(
			{
				id = SHORTCUT_EDIT_PASTE,
				chord = {key = .V, ctrl = true},
				scope = .Focused_Kind,
				scope_kind = kind,
				enabled = true,
				source = .Builtin,
			},
		)
		shortcut_bind_key(
			{
				id = SHORTCUT_EDIT_UNDO,
				chord = {key = .Z, ctrl = true},
				scope = .Focused_Kind,
				scope_kind = kind,
				enabled = true,
				source = .Builtin,
			},
		)
	}

	selectable_kinds := [2]Widget_Kind{.TEXT, .RICH_TEXT}

	for kind in selectable_kinds {
		shortcut_bind_key(
			{
				id = SHORTCUT_EDIT_COPY,
				chord = {key = .C, ctrl = true},
				scope = .Focused_Kind,
				scope_kind = kind,
				enabled = true,
				source = .Builtin,
			},
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

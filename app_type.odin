package oni

/*
Opaque app classification stored in engine state.

Apps define their own enum (e.g. Application, Game) and pass values through
App_Type_Set / App_Type_As. Bindings may restrict triggers to one type via
App_Type_Filter; an unset filter applies to every type.
*/
App_Type_Id :: distinct int

App_Type_Filter :: union {
	struct{}, // any app type (zero value)
	App_Type_Id,
}

App_Type_Defaults_Installer :: proc(app_type: App_Type_Id)

@(private)
app_type_defaults_installer: App_Type_Defaults_Installer

/*
Returns the current app type id stored in engine state.
*/
app_type :: proc() -> App_Type_Id {
	if state == nil do return App_Type_Id(0)

	return state.app_type
}

/*
Sets the current app type and refreshes type-specific builtin shortcuts.

Universal builtins (no App_Type_Filter restriction) are kept.
*/
app_type_set :: proc(type: App_Type_Id) {
	if state == nil do return

	if state.app_type == type do return

	state.app_type = type

	if state.shortcuts.defaults_installed {
		shortcut_refresh_app_type_defaults()
	}
}

/*
Returns the current app type cast to the caller's enum type.
*/
app_type_as :: proc($T: typeid) -> T {
	if state == nil do return T(0)

	return T(state.app_type)
}

/*
Sets the current app type from the caller's enum type.
*/
app_type_set_enum :: proc($T: typeid, value: T) {
	app_type_set(App_Type_Id(int(value)))
}

/*
Registers the proc that installs builtin shortcuts for the active app type.

Call before Init_Runtime (e.g. from ensure_persistent). The installer runs
during shortcut_install_defaults and whenever the app type changes.
*/
register_app_type_defaults :: proc(installer: App_Type_Defaults_Installer) {
	app_type_defaults_installer = installer
}

@(private)
app_type_filter_matches :: proc(filter: App_Type_Filter) -> bool {
	type_id, is_type := filter.(App_Type_Id)

	if is_type {
		if state == nil do return false

		return type_id == state.app_type
	}

	return true
}

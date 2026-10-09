package oni

/*
Resolves Cfg(Grid_Template_Columns) from theme, parent, or explicit author value.
*/
@(private)
resolve_cfg_grid_template_columns :: proc(
	field: Cfg(Grid_Template_Columns),
	parent: Grid_Template_Tracks,
	theme: Grid_Template_Tracks,
	state: ^$S,
	event: Widget_Event(S),
) -> Grid_Template_Tracks {
	switch field.mode {
	case .UNSET:
		return theme
	case .Value:
		#partial switch v in field.value {
		case Inherit:
			return parent
		case proc(
			     frame_state: Widget_Frame_State,
			     event: Widget_Event(Widget_Frame_State),
		     ) -> Grid_Template_Columns:
			ui_state := to_ui_state(state)
			ui_event := to_ui_event(state)
			return resolve_cfg_grid_template_columns(
				{mode = .Value, value = v(ui_state, ui_event)},
				parent,
				theme,
				state,
				event,
			)
		case:
			return grid_resolve_template_columns(field.value)
		}
	}
	return theme
}

/*
Resolves Cfg(Grid_Template_Rows) from theme, parent, or explicit author value.
*/
@(private)
resolve_cfg_grid_template_rows :: proc(
	field: Cfg(Grid_Template_Rows),
	parent: Grid_Template_Tracks,
	theme: Grid_Template_Tracks,
	state: ^$S,
	event: Widget_Event(S),
) -> Grid_Template_Tracks {
	switch field.mode {
	case .UNSET:
		return theme
	case .Value:
		#partial switch v in field.value {
		case Inherit:
			return parent
		case proc(
			     frame_state: Widget_Frame_State,
			     event: Widget_Event(Widget_Frame_State),
		     ) -> Grid_Template_Rows:
			ui_state := to_ui_state(state)
			ui_event := to_ui_event(state)
			return resolve_cfg_grid_template_rows(
				{mode = .Value, value = v(ui_state, ui_event)},
				parent,
				theme,
				state,
				event,
			)
		case:
			return grid_resolve_template_rows(field.value)
		}
	}
	return theme
}

/*
Resolves Cfg(Grid_Auto_Track) from theme, parent, or explicit author value.
*/
@(private)
resolve_cfg_grid_auto_track :: proc(
	field: Cfg(Grid_Auto_Track),
	parent: Grid_Track_Size,
	theme: Grid_Track_Size,
	state: ^$S,
	event: Widget_Event(S),
) -> Grid_Track_Size {
	switch field.mode {
	case .UNSET:
		return theme
	case .Value:
		#partial switch v in field.value {
		case Inherit:
			return parent
		case proc(
			     frame_state: Widget_Frame_State,
			     event: Widget_Event(Widget_Frame_State),
		     ) -> Grid_Auto_Track:
			ui_state := to_ui_state(state)
			ui_event := to_ui_event(state)
			return resolve_cfg_grid_auto_track(
				{mode = .Value, value = v(ui_state, ui_event)},
				parent,
				theme,
				state,
				event,
			)
		case:
			return grid_resolve_auto_track(field.value)
		}
	}
	return theme
}

/*
Resolves Cfg(Grid_Auto_Flow) from theme, parent, or explicit author value.
*/
@(private)
resolve_cfg_grid_auto_flow :: proc(
	field: Cfg(Grid_Auto_Flow),
	parent: Grid_Auto_Flow,
	theme: Grid_Auto_Flow,
) -> Grid_Auto_Flow {
	switch field.mode {
	case .UNSET:
		return theme
	case .Value:
		return field.value
	}
	return theme
}

/*
Resolves Cfg(Grid_Line_Value) from theme, parent, or explicit author value.
*/
@(private)
resolve_cfg_grid_line :: proc(
	field: Cfg(Grid_Line_Value),
	parent: Grid_Line,
	theme: Grid_Line,
	state: ^$S,
	event: Widget_Event(S),
) -> Grid_Line {
	switch field.mode {
	case .UNSET:
		return theme
	case .Value:
		#partial switch v in field.value {
		case Inherit:
			return parent
		case proc(
			     frame_state: Widget_Frame_State,
			     event: Widget_Event(Widget_Frame_State),
		     ) -> Grid_Line_Value:
			ui_state := to_ui_state(state)
			ui_event := to_ui_event(state)
			return resolve_cfg_grid_line(
				{mode = .Value, value = v(ui_state, ui_event)},
				parent,
				theme,
				state,
				event,
			)
		case:
			return grid_resolve_line_value(field.value)
		}
	}
	return theme
}

/*
Resolves Cfg(string) for grid template areas / shorthands with inherit support.
*/
@(private)
resolve_cfg_grid_string :: proc(field: Cfg(string), parent: string) -> string {
	switch field.mode {
	case .UNSET:
		return parent
	case .Value:
		return field.value
	}
	return parent
}

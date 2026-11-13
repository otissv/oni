package oni_widgets

import o ".."

File_Drop_Target_Config :: o.Widget_Config

File_Drop_Target_State :: struct {
	using frame_state: o.Widget_Frame_State,
	config: o.Resolved_Widget_Config,
	drag: o.File_Drag_State,
	is_drag_over: bool,
}

File_Drop_Target_Event :: o.Widget_Event(File_Drop_Target_State)

/* Paths are borrowed for this callback only. Clone paths retained by the app. */
File_Drop_Event :: struct {
	frame_state: File_Drop_Target_State,
	status: o.File_Drop_Status,
	paths: []string,
	position: o.Vec2,
	error_code: o.File_Drop_Error,
	omitted_batches: u64,
}

File_Drop_Target_Props :: struct {
	config: File_Drop_Target_Config,
	child: proc(frame_state: File_Drop_Target_State),
	accept: proc(paths: []string) -> bool,
	on_drop: proc(event: File_Drop_Event),
	on_drag_enter: proc(frame_state: File_Drop_Target_State),
	on_drag_leave: proc(frame_state: File_Drop_Target_State),
}

@(private)
file_drop_target_theme_base :: proc(_: ^File_Drop_Target_State) -> File_Drop_Target_Config {

	return {kind = .RECT}
}

/*
Composable native file-drop box. Layout registers a target; Draw paints its
children and then dispatches complete batches. Children must have the same tree
in both passes. accept is a synchronous metadata predicate; on_drop receives
both Selected and Failed results. File I/O belongs on app workers, or use
Load_Texture for non-blocking image imports. Disabled/inert boxes do not consume.
*/
File_Drop_Target :: proc(props: File_Drop_Target_Props) {
	key := o.element_key(props.config.id)
	id := o.ui_id(key)
	frame := File_Drop_Target_State{
		is_disabled = o.cfg_style_bool(props.config.disabled),
		drag = o.Get_File_Drag_State(),
		is_drag_over = o.File_Drop_Target_Hovered(id),
	}
	event := widget_refresh_merged(props, &frame, file_drop_target_theme_base)
	config := frame.config
	frame.is_disabled = config.disabled

	if o.ui_pass() == .Layout {
		_ = o.File_Drop_Register_Target(id, !config.disabled && props.on_drop != nil)
		widget_children(props.child, id, config, frame, key, props.config)

		return
	}

	if !o.ui_has_layout_node(id) {

		return
	}

	rect := o.ui_layout_rect(id)
	background, _ := o.style_background_rgba(config, &frame, event)
	border_color, _ := o.style_border_color_rgba(config, &frame, event)
	radius, _ := o.resolve_radius(config.radius, &frame, event)
	border, _ := o.resolve_border(config.border, &frame, event)
	widget_draw_box_background(id, rect, background, radius)
	widget_children(props.child, id, config, frame, key, props.config)
	widget_draw_box_border(id, rect, radius, border, border_color)

	if config.disabled || props.on_drop == nil {

		return
	}

	if o.file_drop_target_entered(id) && props.on_drag_enter != nil {
		props.on_drag_enter(frame)
	}
	if o.file_drop_target_left(id) && props.on_drag_leave != nil {
		props.on_drag_leave(frame)
	}

	for _ in 0 ..< o.FILE_DROP_MAX_BATCHES + 1 {
		result, ok := o.Take_File_Drop(id)

		if !ok {

			break
		}
		defer o.Destroy_File_Drop_Result(&result)

		if result.status == .Selected && props.accept != nil && !props.accept(result.paths) {
			result.status = .Failed
			result.error_code = .Rejected
		}
		props.on_drop({
			frame_state = frame,
			status = result.status,
			paths = result.paths,
			position = result.position,
			error_code = result.error_code,
			omitted_batches = result.omitted_batches,
		})
	}
}

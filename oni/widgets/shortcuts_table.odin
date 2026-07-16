package widgets

import o ".."
import set "../set"
import "core:fmt"
import "core:strings"
import sdl "vendor:sdl3"

/*
Interactive session state for Shortcuts_Table.

Caller owns this (typically in Persistent app state) so capture/status survive frames
and hot reloads. Initialize with Shortcuts_Table_Session_Init; free with Destroy.
*/
Shortcuts_Table_Session :: struct {
	initialized:    bool,
	mode:           Shortcuts_Table_Mode,
	rebind_index:   int, // binding index when mode == .Rebind; -1 otherwise
	add_action_id:  string, // owned; action id when mode == .Add
	status:         string, // owned status line; empty uses default summary
	picking_action: bool, // Add flow: show registered-action picker
}

Shortcuts_Table_Mode :: enum u8 {
	Idle,
	Rebind,
	Add,
}

Shortcuts_Table_Config :: o.Widget_Config

Shortcuts_Table_State :: o.Widget_Merged_State(o.Widget_Frame_State, o.Resolved_Widget_Config)

Shortcuts_Table_Event :: o.Widget_Event(Shortcuts_Table_State)

/*
Props for the shortcuts settings table.

`session` is required. `bindings_path` empty uses SHORTCUT_DEFAULT_BINDINGS_PATH.
*/
Shortcuts_Table_Props :: struct {
	config:        Shortcuts_Table_Config,
	session:       ^Shortcuts_Table_Session,
	bindings_path: string,
}

@(private)
shortcuts_table_ctx: struct {
	session:       ^Shortcuts_Table_Session,
	bindings_path: string,
	id_prefix:     string,
	row_index:     int,
	cell_id:       string,
	text_id:       string,
	cell_text:     string,
	btn_id:        string,
	btn_text_id:   string,
	btn_label:     string,
	action_id:     string,
	action_label:  string,
	chord:         string,
	scope:         string,
	source:        string,
	enabled:       bool,
	is_user:       bool,
	listening:     bool,
	conflict_text: string,
	conflict_i:    int,
	status_text:   string,
}

/*
Resets session fields for first use.
*/
Shortcuts_Table_Session_Init :: proc(s: ^Shortcuts_Table_Session) {
	if s == nil do return
	if s.initialized {
		Shortcuts_Table_Session_Destroy(s)
	}
	s^ = {}
	s.initialized = true
	s.rebind_index = -1
}

/*
Frees owned session strings.
*/
Shortcuts_Table_Session_Destroy :: proc(s: ^Shortcuts_Table_Session) {
	if s == nil do return
	if s.status != "" {
		delete(s.status)
		s.status = ""
	}
	if s.add_action_id != "" {
		delete(s.add_action_id)
		s.add_action_id = ""
	}
	s^ = {}
}

@(private)
shortcuts_table_set_status :: proc(session: ^Shortcuts_Table_Session, msg: string) {
	if session == nil do return
	if session.status != "" {
		delete(session.status)
	}
	session.status = strings.clone(msg)
}

@(private)
shortcuts_table_path :: proc(path: string) -> string {
	if path != "" do return path
	return o.SHORTCUT_DEFAULT_BINDINGS_PATH
}

@(private)
shortcuts_table_scope_label :: proc(
	scope: o.Shortcut_Scope,
	key: string,
	kind: o.Widget_Kind,
) -> string {
	switch scope {
	case .Global:
		return "Global"
	case .Context:
		if key != "" do return fmt.tprintf("Context:%s", key)
		return "Context"
	case .Focused_Id:
		if key != "" do return fmt.tprintf("Focus:%s", key)
		return "Focused Id"
	case .Focused_Any:
		return "Focused Any"
	case .Focused_Kind:
		return fmt.tprintf("Kind:%v", kind)
	}
	return "?"
}

@(private)
shortcuts_table_source_label :: proc(source: o.Shortcut_Source) -> string {
	switch source {
	case .User:
		return "User"
	case .Builtin:
		return "Builtin"
	}
	return "?"
}

@(private)
shortcuts_table_discard_capture :: proc() {
	_, _, _ = o.Shortcut_Capture_Take()
}

@(private)
shortcuts_table_cancel_capture :: proc(session: ^Shortcuts_Table_Session) {
	if session == nil do return
	if o.Shortcut_Capture_Active() {
		o.Shortcut_Capture_Cancel()
		shortcuts_table_discard_capture()
	}
	session.mode = .Idle
	session.rebind_index = -1
	session.picking_action = false
	if session.add_action_id != "" {
		delete(session.add_action_id)
		session.add_action_id = ""
	}
}

@(private)
shortcuts_table_unbind_binding :: proc(binding: o.Shortcut_Binding) {
	id := strings.clone(binding.id, context.temp_allocator)
	switch binding.trigger {
	case .Key:
		o.Shortcut_Unbind(id, binding.chord)
	case .Wheel_Y:
		o.Shortcut_Unbind_Wheel(id, binding.wheel_sign)
	case .Mouse_Button:
		o.Shortcut_Unbind_Mouse(id, binding.mouse_button, binding.chord)
	case .Sequence:
		seq := binding.sequence
		keys := seq[:binding.sequence_len]
		o.Shortcut_Unbind_Sequence(id, keys, binding.chord)
	case .Gamepad:
		o.Shortcut_Unbind_Gamepad(id, sdl.GamepadButton(binding.gamepad_button))
	}
}

@(private)
shortcuts_table_bind_capture :: proc(
	id: string,
	result: o.Shortcut_Capture_Result,
	scope: o.Shortcut_Scope,
	scope_key: string,
	scope_kind: o.Widget_Kind,
	priority: i32,
) -> bool {
	opts := o.Shortcut_Bind_Opts {
		scope      = scope,
		scope_key  = scope_key,
		scope_kind = scope_kind,
		priority   = priority,
		source     = .User,
	}
	switch result.trigger {
	case .Key:
		return o.Shortcut_Bind(id, result.chord, opts)
	case .Wheel_Y:
		return o.Shortcut_Bind_Wheel(
			{
				id = id,
				wheel_sign = result.wheel_sign,
				chord = result.chord,
				scope = scope,
				scope_key = scope_key,
				scope_kind = scope_kind,
				priority = priority,
				enabled = true,
				source = .User,
			},
		)
	case .Mouse_Button:
		return o.Shortcut_Bind_Mouse(
			{
				id = id,
				button = result.mouse_button,
				chord = result.chord,
				scope = scope,
				scope_key = scope_key,
				scope_kind = scope_kind,
				priority = priority,
				enabled = true,
				source = .User,
			},
		)
	case .Sequence:
		if result.sequence_len < 2 do return false
		seq := result.sequence
		keys := seq[:result.sequence_len]
		return o.Shortcut_Bind_Sequence(
			{
				id = id,
				keys = keys,
				chord = result.chord,
				scope = scope,
				scope_key = scope_key,
				scope_kind = scope_kind,
				priority = priority,
				enabled = true,
				source = .User,
			},
		)
	case .Gamepad:
		return o.Shortcut_Bind_Gamepad(
			{
				id = id,
				button = sdl.GamepadButton(result.gamepad_button),
				scope = scope,
				scope_key = scope_key,
				scope_kind = scope_kind,
				priority = priority,
				enabled = true,
				source = .User,
			},
		)
	}
	return false
}

@(private)
shortcuts_table_apply_rebind :: proc(index: int, result: o.Shortcut_Capture_Result) -> bool {
	binding, ok := o.Shortcut_Binding_Get(index)
	if !ok do return false
	id := strings.clone(binding.id, context.temp_allocator)
	scope := binding.scope
	scope_key := strings.clone(binding.scope_key, context.temp_allocator)
	scope_kind := binding.scope_kind
	priority := binding.priority
	shortcuts_table_unbind_binding(binding)
	return shortcuts_table_bind_capture(id, result, scope, scope_key, scope_kind, priority)
}

@(private)
shortcuts_table_format_capture :: proc(
	result: o.Shortcut_Capture_Result,
	allocator := context.allocator,
) -> string {
	return o.Shortcut_Format_Binding(
		{
			trigger = result.trigger,
			chord = result.chord,
			wheel_sign = result.wheel_sign,
			mouse_button = result.mouse_button,
			sequence = result.sequence,
			sequence_len = result.sequence_len,
			gamepad_button = result.gamepad_button,
		},
		allocator,
	)
}

@(private)
shortcuts_table_poll_capture :: proc(session: ^Shortcuts_Table_Session) {
	if session == nil do return
	if session.mode == .Idle do return
	if o.Shortcut_Capture_Active() do return

	result, done, cancelled := o.Shortcut_Capture_Take()
	mode := session.mode
	index := session.rebind_index
	add_id := session.add_action_id
	session.mode = .Idle
	session.rebind_index = -1
	session.add_action_id = ""

	if cancelled {
		if add_id != "" do delete(add_id)
		shortcuts_table_set_status(session, "Capture cancelled")
		return
	}
	if !done {
		if add_id != "" do delete(add_id)
		shortcuts_table_set_status(session, "Capture idle")
		return
	}

	ok := false
	switch mode {
	case .Rebind:
		ok = shortcuts_table_apply_rebind(index, result)
	case .Add:
		if add_id != "" {
			ok = shortcuts_table_bind_capture(add_id, result, .Global, "", {}, 0)
		}
	case .Idle:
	}

	chord := shortcuts_table_format_capture(result, context.temp_allocator)
	if ok {
		shortcuts_table_set_status(session, fmt.tprintf("Bound to %s", chord))
	} else {
		shortcuts_table_set_status(session, "Bind failed")
	}
	if add_id != "" do delete(add_id)
}

@(private)
shortcuts_table_start_rebind :: proc(session: ^Shortcuts_Table_Session, index: int) {
	if session == nil do return
	if index < 0 || index >= o.Shortcut_Binding_Count() do return
	shortcuts_table_cancel_capture(session)
	session.mode = .Rebind
	session.rebind_index = index
	session.picking_action = false
	o.Shortcut_Capture_Begin(.Any)
	shortcuts_table_set_status(
		session,
		"Press a key, click, wheel, or gamepad button (Esc cancels)",
	)
}

@(private)
shortcuts_table_start_add :: proc(session: ^Shortcuts_Table_Session, action_id: string) {
	if session == nil || action_id == "" do return
	shortcuts_table_cancel_capture(session)
	session.mode = .Add
	session.rebind_index = -1
	session.picking_action = false
	session.add_action_id = strings.clone(action_id)
	o.Shortcut_Capture_Begin(.Any)
	shortcuts_table_set_status(
		session,
		fmt.tprintf(
			"Bind %s — press a key, click, wheel, or gamepad (Esc cancels)",
			o.Shortcut_Action_Label(action_id),
		),
	)
}

@(private)
shortcuts_table_theme_base :: proc(frame_state: ^Shortcuts_Table_State) -> Shortcuts_Table_Config {
	_ = frame_state
	return Shortcuts_Table_Config {
		kind = .RECT,
		direction = set.Direction(.VERTICAL),
		gap_y = set.Gap_Y(12),
		justify = set.Justify(o.Justify_Pos{x = .STRETCH, y = .START}),
	}
}

@(private)
shortcuts_table_tool_btn_child :: proc(_: Button_State) {
	Text({config = {id = shortcuts_table_ctx.btn_text_id, text = shortcuts_table_ctx.btn_label}})
}

@(private)
shortcuts_table_tool_button :: proc(
	id_suffix: string,
	label: string,
	on_click: proc(event: Button_Event),
) {
	prefix := shortcuts_table_ctx.id_prefix
	shortcuts_table_ctx.btn_id = fmt.tprintf("%s_%s", prefix, id_suffix)
	shortcuts_table_ctx.btn_text_id = fmt.tprintf("%s_%s_text", prefix, id_suffix)
	shortcuts_table_ctx.btn_label = label
	Button(
		{
			config = {
				id = shortcuts_table_ctx.btn_id,
				padding = set.Padding(o.Pd_struct{x = 10, y = 6}),
				radius = set.Radius(5),
				border = set.Border(1),
				background = set.Background(o.Color.CARD),
			},
			on_click = on_click,
			child = shortcuts_table_tool_btn_child,
		},
	)
}

@(private)
shortcuts_table_on_save :: proc(_: Button_Event) {
	path := shortcuts_table_path(shortcuts_table_ctx.bindings_path)
	session := shortcuts_table_ctx.session
	if o.Shortcut_Save_Bindings(path) {
		shortcuts_table_set_status(session, fmt.tprintf("Saved to %s", path))
	} else {
		shortcuts_table_set_status(session, "Save failed")
	}
}

@(private)
shortcuts_table_on_reload :: proc(_: Button_Event) {
	path := shortcuts_table_path(shortcuts_table_ctx.bindings_path)
	session := shortcuts_table_ctx.session
	shortcuts_table_cancel_capture(session)
	if o.Shortcut_Load_Bindings(path, true) {
		shortcuts_table_set_status(session, fmt.tprintf("Loaded %s", path))
	} else {
		shortcuts_table_set_status(session, "Load failed (missing or invalid file)")
	}
}

@(private)
shortcuts_table_on_reset :: proc(_: Button_Event) {
	session := shortcuts_table_ctx.session
	shortcuts_table_cancel_capture(session)
	o.Shortcut_Clear_User_Bindings()
	shortcuts_table_set_status(session, "Cleared user bindings")
}

@(private)
shortcuts_table_on_cancel :: proc(_: Button_Event) {
	session := shortcuts_table_ctx.session
	shortcuts_table_cancel_capture(session)
	shortcuts_table_set_status(session, "Capture cancelled")
}

@(private)
shortcuts_table_on_add :: proc(_: Button_Event) {
	session := shortcuts_table_ctx.session
	if session == nil do return
	if session.picking_action {
		session.picking_action = false
		shortcuts_table_set_status(session, "")
		return
	}
	shortcuts_table_cancel_capture(session)
	session.picking_action = true
	shortcuts_table_set_status(session, "Choose an action to bind")
}

@(private)
shortcuts_table_toolbar_child :: proc(_: Rectangle_State) {
	shortcuts_table_tool_button("save", "Save", shortcuts_table_on_save)
	shortcuts_table_tool_button("reload", "Reload", shortcuts_table_on_reload)
	shortcuts_table_tool_button("reset", "Reset User", shortcuts_table_on_reset)
	shortcuts_table_tool_button("add", "Add Binding", shortcuts_table_on_add)
	shortcuts_table_tool_button("cancel", "Cancel Capture", shortcuts_table_on_cancel)
}

@(private)
shortcuts_table_cell_text_child :: proc(_: Table_Cell_State) {
	Text({config = {id = shortcuts_table_ctx.text_id, text = shortcuts_table_ctx.cell_text}})
}

@(private)
shortcuts_table_cell_text :: proc(cell_id: string, text_id: string, text: string) {
	shortcuts_table_ctx.cell_id = cell_id
	shortcuts_table_ctx.text_id = text_id
	shortcuts_table_ctx.cell_text = text
	Table_Cell(
		{
			config = {
				id = cell_id,
				border = set.Border(.INHERIT),
				padding = set.Padding(o.Pd_struct{x = 8, y = 4}),
			},
			child = shortcuts_table_cell_text_child,
		},
	)
}

@(private)
shortcuts_table_heading_row :: proc(_: Table_Row_State) {
	prefix := shortcuts_table_ctx.id_prefix
	shortcuts_table_cell_text(
		fmt.tprintf("%s_h_action", prefix),
		fmt.tprintf("%s_h_action_t", prefix),
		"Action",
	)
	shortcuts_table_cell_text(
		fmt.tprintf("%s_h_binding", prefix),
		fmt.tprintf("%s_h_binding_t", prefix),
		"Binding",
	)
	shortcuts_table_cell_text(
		fmt.tprintf("%s_h_scope", prefix),
		fmt.tprintf("%s_h_scope_t", prefix),
		"Scope",
	)
	shortcuts_table_cell_text(
		fmt.tprintf("%s_h_source", prefix),
		fmt.tprintf("%s_h_source_t", prefix),
		"Source",
	)
	shortcuts_table_cell_text(
		fmt.tprintf("%s_h_enabled", prefix),
		fmt.tprintf("%s_h_enabled_t", prefix),
		"Enabled",
	)
	shortcuts_table_cell_text(
		fmt.tprintf("%s_h_actions", prefix),
		fmt.tprintf("%s_h_actions_t", prefix),
		"",
	)
}

@(private)
shortcuts_table_on_rebind :: proc(_: Button_Event) {
	shortcuts_table_start_rebind(shortcuts_table_ctx.session, shortcuts_table_ctx.row_index)
}

@(private)
shortcuts_table_on_remove :: proc(_: Button_Event) {
	session := shortcuts_table_ctx.session
	index := shortcuts_table_ctx.row_index
	binding, ok := o.Shortcut_Binding_Get(index)
	if !ok || binding.source != .User {
		shortcuts_table_set_status(session, "Only user bindings can be removed")
		return
	}
	if session != nil && session.mode == .Rebind && session.rebind_index == index {
		shortcuts_table_cancel_capture(session)
	}
	if o.Shortcut_Remove_Binding_At(index) {
		shortcuts_table_set_status(session, "Removed binding")
	} else {
		shortcuts_table_set_status(session, "Remove failed")
	}
}

@(private)
shortcuts_table_on_toggle :: proc(_: Button_Event) {
	session := shortcuts_table_ctx.session
	index := shortcuts_table_ctx.row_index
	binding, ok := o.Shortcut_Binding_Get(index)
	if !ok do return
	if o.Shortcut_Set_Binding_Enabled_At(index, !binding.enabled) {
		shortcuts_table_set_status(
			session,
			binding.enabled ? "Disabled binding" : "Enabled binding",
		)
	}
}

@(private)
shortcuts_table_row_btn_child :: proc(_: Button_State) {
	Text({config = {id = shortcuts_table_ctx.btn_text_id, text = shortcuts_table_ctx.btn_label}})
}

@(private)
shortcuts_table_actions_cell_child :: proc(_: Table_Cell_State) {
	prefix := shortcuts_table_ctx.id_prefix
	i := shortcuts_table_ctx.row_index

	shortcuts_table_ctx.btn_id = fmt.tprintf("%s_rebind_%d", prefix, i)
	shortcuts_table_ctx.btn_text_id = fmt.tprintf("%s_rebind_%d_t", prefix, i)
	shortcuts_table_ctx.btn_label = shortcuts_table_ctx.listening ? "Listening…" : "Rebind"
	Button(
		{
			config = {
				id = shortcuts_table_ctx.btn_id,
				padding = set.Padding(o.Pd_struct{x = 6, y = 2}),
				radius = set.Radius(4),
				border = set.Border(1),
			},
			on_click = shortcuts_table_on_rebind,
			child = shortcuts_table_row_btn_child,
		},
	)

	if shortcuts_table_ctx.is_user {
		shortcuts_table_ctx.btn_id = fmt.tprintf("%s_remove_%d", prefix, i)
		shortcuts_table_ctx.btn_text_id = fmt.tprintf("%s_remove_%d_t", prefix, i)
		shortcuts_table_ctx.btn_label = "Remove"
		Button(
			{
				config = {
					id = shortcuts_table_ctx.btn_id,
					padding = set.Padding(o.Pd_struct{x = 6, y = 2}),
					radius = set.Radius(4),
					border = set.Border(1),
				},
				on_click = shortcuts_table_on_remove,
				child = shortcuts_table_row_btn_child,
			},
		)
	}
}

@(private)
shortcuts_table_enabled_cell_child :: proc(_: Table_Cell_State) {
	prefix := shortcuts_table_ctx.id_prefix
	i := shortcuts_table_ctx.row_index
	shortcuts_table_ctx.btn_id = fmt.tprintf("%s_en_%d", prefix, i)
	shortcuts_table_ctx.btn_text_id = fmt.tprintf("%s_en_%d_t", prefix, i)
	shortcuts_table_ctx.btn_label = shortcuts_table_ctx.enabled ? "On" : "Off"
	Button(
		{
			config = {
				id = shortcuts_table_ctx.btn_id,
				padding = set.Padding(o.Pd_struct{x = 6, y = 2}),
				radius = set.Radius(4),
				border = set.Border(1),
			},
			on_click = shortcuts_table_on_toggle,
			child = shortcuts_table_row_btn_child,
		},
	)
}

@(private)
shortcuts_table_binding_row_child :: proc(_: Table_Row_State) {
	prefix := shortcuts_table_ctx.id_prefix
	i := shortcuts_table_ctx.row_index

	shortcuts_table_cell_text(
		fmt.tprintf("%s_r%d_action", prefix, i),
		fmt.tprintf("%s_r%d_action_t", prefix, i),
		shortcuts_table_ctx.action_label,
	)
	shortcuts_table_cell_text(
		fmt.tprintf("%s_r%d_binding", prefix, i),
		fmt.tprintf("%s_r%d_binding_t", prefix, i),
		shortcuts_table_ctx.chord,
	)
	shortcuts_table_cell_text(
		fmt.tprintf("%s_r%d_scope", prefix, i),
		fmt.tprintf("%s_r%d_scope_t", prefix, i),
		shortcuts_table_ctx.scope,
	)
	shortcuts_table_cell_text(
		fmt.tprintf("%s_r%d_source", prefix, i),
		fmt.tprintf("%s_r%d_source_t", prefix, i),
		shortcuts_table_ctx.source,
	)

	Table_Cell(
		{
			config = {
				id = fmt.tprintf("%s_r%d_enabled", prefix, i),
				border = set.Border(.INHERIT),
				padding = set.Padding(o.Pd_struct{x = 8, y = 4}),
			},
			child = shortcuts_table_enabled_cell_child,
		},
	)

	Table_Cell(
		{
			config = {
				id = fmt.tprintf("%s_r%d_actions", prefix, i),
				direction = set.Direction(.HORIZONTAL),
				gap_x = set.Gap_X(4),
				border = set.Border(.INHERIT),
				padding = set.Padding(o.Pd_struct{x = 8, y = 4}),
			},
			child = shortcuts_table_actions_cell_child,
		},
	)
}

@(private)
shortcuts_table_emit_binding_row :: proc(index: int, binding: o.Shortcut_Binding) {
	session := shortcuts_table_ctx.session
	shortcuts_table_ctx.row_index = index
	shortcuts_table_ctx.action_label = strings.clone(
		o.Shortcut_Action_Label(binding.id),
		context.temp_allocator,
	)
	shortcuts_table_ctx.chord = o.Shortcut_Format_Binding(binding, context.temp_allocator)
	shortcuts_table_ctx.scope = strings.clone(
		shortcuts_table_scope_label(binding.scope, binding.scope_key, binding.scope_kind),
		context.temp_allocator,
	)
	shortcuts_table_ctx.source = shortcuts_table_source_label(binding.source)
	shortcuts_table_ctx.enabled = binding.enabled
	shortcuts_table_ctx.is_user = binding.source == .User
	shortcuts_table_ctx.listening =
		session != nil && session.mode == .Rebind && session.rebind_index == index

	Table_Row(
		{
			config = {
				id = fmt.tprintf("%s_row_%d", shortcuts_table_ctx.id_prefix, index),
				border = set.Border(.INHERIT),
			},
			child = shortcuts_table_binding_row_child,
		},
	)
}

@(private)
shortcuts_table_body_child :: proc(_: Table_Body_State) {
	n := o.Shortcut_Binding_Count()
	for i in 0 ..< n {
		binding, ok := o.Shortcut_Binding_Get(i)
		if !ok do continue
		shortcuts_table_emit_binding_row(i, binding)
	}
}

@(private)
shortcuts_table_head_row_child :: proc(_: Table_Head_State) {
	Table_Row(
		{
			config = {
				id = fmt.tprintf("%s_head_row", shortcuts_table_ctx.id_prefix),
				radius = set.Radius(o.Radius_corners{tl = .INHERIT, tr = .INHERIT}),
				border = set.Border(.INHERIT),
			},
			child = shortcuts_table_heading_row,
		},
	)
}

@(private)
shortcuts_table_table_child :: proc(_: Table_State) {
	prefix := shortcuts_table_ctx.id_prefix
	Table_Head(
		{
			config = {
				id = fmt.tprintf("%s_head", prefix),
				radius = set.Radius(o.Radius_corners{tl = .INHERIT, tr = .INHERIT}),
				border = set.Border(.INHERIT),
			},
			child = shortcuts_table_head_row_child,
		},
	)
	Table_Body(
		{config = {id = fmt.tprintf("%s_body", prefix)}, child = shortcuts_table_body_child},
	)
}

@(private)
shortcuts_table_on_pick_action :: proc(_: Button_Event) {
	shortcuts_table_start_add(shortcuts_table_ctx.session, shortcuts_table_ctx.action_id)
}

@(private)
shortcuts_table_picker_btn_child :: proc(_: Button_State) {
	Text({config = {id = shortcuts_table_ctx.btn_text_id, text = shortcuts_table_ctx.btn_label}})
}

@(private)
shortcuts_table_picker_child :: proc(_: Rectangle_State) {
	actions := o.Shortcut_List_Actions(context.temp_allocator)
	defer o.Shortcut_Free_Action_List(actions, context.temp_allocator)
	prefix := shortcuts_table_ctx.id_prefix
	for action, i in actions {
		shortcuts_table_ctx.action_id = action
		shortcuts_table_ctx.btn_id = fmt.tprintf("%s_pick_%d", prefix, i)
		shortcuts_table_ctx.btn_text_id = fmt.tprintf("%s_pick_%d_t", prefix, i)
		shortcuts_table_ctx.btn_label = o.Shortcut_Action_Label(action)
		Button(
			{
				config = {
					id = shortcuts_table_ctx.btn_id,
					padding = set.Padding(o.Pd_struct{x = 8, y = 4}),
				},
				on_click = shortcuts_table_on_pick_action,
				child = shortcuts_table_picker_btn_child,
			},
		)
	}
}

@(private)
shortcuts_table_conflict_row_child :: proc(_: Rectangle_State) {
	Text(
		{
			config = {
				id = fmt.tprintf(
					"%s_conflict_%d_t",
					shortcuts_table_ctx.id_prefix,
					shortcuts_table_ctx.conflict_i,
				),
				text = shortcuts_table_ctx.conflict_text,
				color = set.Colors(o.Color.DESTRUCTIVE),
			},
		},
	)
}

@(private)
shortcuts_table_conflicts_child :: proc(_: Rectangle_State) {
	conflicts := o.Shortcut_Collect_Conflicts(context.temp_allocator)
	prefix := shortcuts_table_ctx.id_prefix
	for c, i in conflicts {
		trigger := o.Shortcut_Format_Binding(
			{
				trigger = c.trigger,
				chord = c.chord,
				wheel_sign = c.wheel_sign,
				mouse_button = c.mouse_button,
				sequence = c.sequence,
				sequence_len = c.sequence_len,
				gamepad_button = c.gamepad_button,
			},
			context.temp_allocator,
		)
		shortcuts_table_ctx.conflict_i = i
		shortcuts_table_ctx.conflict_text = fmt.tprintf(
			"Conflict: %s vs %s on %s (%s)",
			o.Shortcut_Action_Label(c.id_a),
			o.Shortcut_Action_Label(c.id_b),
			trigger,
			shortcuts_table_scope_label(c.scope, "", {}),
		)
		Rectangle(
			{
				config = {id = fmt.tprintf("%s_conflict_%d", prefix, i)},
				child = shortcuts_table_conflict_row_child,
			},
		)
	}
}

@(private)
shortcuts_table_root_child :: proc(_: Rectangle_State) {
	session := shortcuts_table_ctx.session
	prefix := shortcuts_table_ctx.id_prefix

	conflicts := o.Shortcut_Collect_Conflicts(context.temp_allocator)
	status := ""
	if session != nil {
		status = session.status
	}
	if status == "" {
		status = fmt.tprintf(
			"%d bindings · %d conflicts",
			o.Shortcut_Binding_Count(),
			len(conflicts),
		)
	}
	shortcuts_table_ctx.status_text = status

	Text(
		{
			config = {
				id = fmt.tprintf("%s_status", prefix),
				text = shortcuts_table_ctx.status_text,
				color = set.Colors(o.Color.FOREGROUND),
			},
		},
	)

	Rectangle(
		{
			config = {
				id = fmt.tprintf("%s_toolbar", prefix),
				direction = set.Direction(.HORIZONTAL),
				gap_x = set.Gap_X(8),
			},
			child = shortcuts_table_toolbar_child,
		},
	)

	if session != nil && session.picking_action {
		Rectangle(
			{
				config = {
					id = fmt.tprintf("%s_picker", prefix),
					direction = set.Direction(.VERTICAL),
					gap_y = set.Gap_Y(4),
				},
				child = shortcuts_table_picker_child,
			},
		)
	}

	if len(conflicts) > 0 {
		Rectangle(
			{
				config = {
					id = fmt.tprintf("%s_conflicts", prefix),
					direction = set.Direction(.VERTICAL),
					gap_y = set.Gap_Y(4),
				},
				child = shortcuts_table_conflicts_child,
			},
		)
	}

	Table(
		{
			config = {
				id = fmt.tprintf("%s_table", prefix),
				direction = set.Direction(.VERTICAL),
				justify = set.Justify(o.Justify_Pos{x = .STRETCH, y = .START}),
			},
			child = shortcuts_table_table_child,
		},
	)
}

/*
Renders a full shortcuts settings panel: toolbar, conflicts, and bindings table.

Supports save/load/reset, add (action picker + capture), rebind, enable/disable,
and remove (user bindings). Pass a Persistent-owned session via props.session.
*/
Shortcuts_Table :: proc(props: Shortcuts_Table_Props) {
	if props.session == nil do return
	if !props.session.initialized {
		Shortcuts_Table_Session_Init(props.session)
	}

	shortcuts_table_poll_capture(props.session)

	cfg := props.config
	if cfg.id == "" {
		cfg.id = "shortcuts_table"
	}
	shortcuts_table_ctx = {
		session       = props.session,
		bindings_path = props.bindings_path,
		id_prefix     = cfg.id,
	}

	merged := cfg
	base := shortcuts_table_theme_base(nil)
	if merged.kind == {} do merged.kind = base.kind
	if merged.direction.mode == .UNSET do merged.direction = base.direction
	if merged.gap_y.mode == .UNSET do merged.gap_y = base.gap_y
	if merged.justify.mode == .UNSET do merged.justify = base.justify

	Rectangle({config = merged, child = shortcuts_table_root_child})
}

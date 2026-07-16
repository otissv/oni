package oni_docs

import ui "../../app/ui"
import o "../../oni"
import set "../../oni/set"
import w "../../oni/widgets"
import "core:fmt"
import "core:strings"
import sdl "vendor:sdl3"

@(private)
shortcuts_demo: struct {
	initialized:  bool,
	rebind_index: int, // -1 = idle
	status:       string, // owned
	ping_count:   int,
}

@(private)
shortcuts_row_ctx: struct {
	index:        int,
	action:       string,
	chord:        string,
	scope:        string,
	source:       string,
	rebind_label: string,
	cell_id:      string,
	text_id:      string,
	cell_text:    string,
	btn_id:       string,
	btn_text_id:  string,
}

@(private)
shortcuts_set_status :: proc(msg: string) {
	if shortcuts_demo.status != "" {
		delete(shortcuts_demo.status)
	}
	shortcuts_demo.status = strings.clone(msg)
}

@(private)
shortcuts_ensure_init :: proc() {
	if shortcuts_demo.initialized do return
	shortcuts_demo.initialized = true
	shortcuts_demo.rebind_index = -1
}

@(private)
shortcuts_scope_label :: proc(scope: o.Shortcut_Scope, key: string, kind: o.Widget_Kind) -> string {
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
shortcuts_source_label :: proc(source: o.Shortcut_Source) -> string {
	switch source {
	case .User:
		return "User"
	case .Builtin:
		return "Builtin"
	}
	return "?"
}

@(private)
shortcuts_discard_capture :: proc() {
	_, _, _ = o.Shortcut_Capture_Take()
}

@(private)
shortcuts_apply_capture :: proc(index: int, result: o.Shortcut_Capture_Result) -> bool {
	binding, ok := o.Shortcut_Binding_Get(index)
	if !ok do return false

	id := strings.clone(binding.id, context.temp_allocator)
	opts := o.Shortcut_Bind_Opts {
		scope      = binding.scope,
		scope_key  = binding.scope_key,
		scope_kind = binding.scope_kind,
		priority   = binding.priority,
		source     = .User,
	}

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

	switch result.trigger {
	case .Key:
		return o.Shortcut_Bind(id, result.chord, opts)
	case .Wheel_Y:
		return o.Shortcut_Bind_Wheel(id, result.wheel_sign, result.chord, opts)
	case .Mouse_Button:
		return o.Shortcut_Bind_Mouse(id, result.mouse_button, result.chord, opts)
	case .Sequence:
		if result.sequence_len < 2 do return false
		seq := result.sequence
		keys := seq[:result.sequence_len]
		return o.Shortcut_Bind_Sequence(id, keys, result.chord, opts)
	case .Gamepad:
		return o.Shortcut_Bind_Gamepad(id, sdl.GamepadButton(result.gamepad_button), opts)
	}
	return false
}

@(private)
shortcuts_poll_capture :: proc() {
	if shortcuts_demo.rebind_index < 0 do return
	if o.Shortcut_Capture_Active() do return

	result, done, cancelled := o.Shortcut_Capture_Take()
	index := shortcuts_demo.rebind_index
	shortcuts_demo.rebind_index = -1

	if cancelled {
		shortcuts_set_status("Capture cancelled")
		return
	}
	if !done {
		shortcuts_set_status("Capture idle")
		return
	}
	if shortcuts_apply_capture(index, result) {
		chord := o.Shortcut_Format_Binding(
			{
				trigger = result.trigger,
				chord = result.chord,
				wheel_sign = result.wheel_sign,
				mouse_button = result.mouse_button,
				sequence = result.sequence,
				sequence_len = result.sequence_len,
				gamepad_button = result.gamepad_button,
			},
			context.temp_allocator,
		)
		shortcuts_set_status(fmt.tprintf("Rebound to %s", chord))
	} else {
		shortcuts_set_status("Rebind failed")
	}
}

@(private)
shortcuts_start_rebind :: proc(index: int) {
	if index < 0 || index >= o.Shortcut_Binding_Count() do return
	if o.Shortcut_Capture_Active() {
		o.Shortcut_Capture_Cancel()
		shortcuts_discard_capture()
	}
	shortcuts_demo.rebind_index = index
	o.Shortcut_Capture_Begin(.Any)
	shortcuts_set_status("Press a key, click, wheel, or gamepad button (Esc cancels)")
}

@(private)
shortcuts_toolbar :: proc(_: w.Rectangle_State) {
	ui.Button({
		id = "shortcuts_save",
		variant = .DEFAULT,
		radius = set.Radius(5),
		on_click = proc(_: ui.Button_Event) {
			path := o.SHORTCUT_DEFAULT_BINDINGS_PATH
			if o.Shortcut_Save_Bindings(path) {
				shortcuts_set_status(fmt.tprintf("Saved to %s", path))
			} else {
				shortcuts_set_status("Save failed")
			}
		},
		child = proc(_: ui.Button_state) {
			w.Text({config = {id = "shortcuts_save_text", text = "Save"}})
		},
	})

	ui.Button({
		id = "shortcuts_reload",
		variant = .SECONDARY,
		radius = set.Radius(5),
		on_click = proc(_: ui.Button_Event) {
			path := o.SHORTCUT_DEFAULT_BINDINGS_PATH
			if o.Shortcut_Load_Bindings(path, true) {
				shortcuts_set_status(fmt.tprintf("Loaded %s", path))
			} else {
				shortcuts_set_status("Load failed (missing or invalid file)")
			}
		},
		child = proc(_: ui.Button_state) {
			w.Text({config = {id = "shortcuts_reload_text", text = "Reload"}})
		},
	})

	ui.Button({
		id = "shortcuts_reset",
		variant = .OUTLINE,
		radius = set.Radius(5),
		on_click = proc(_: ui.Button_Event) {
			o.Shortcut_Clear_User_Bindings()
			shortcuts_set_status("Cleared user bindings")
		},
		child = proc(_: ui.Button_state) {
			w.Text({config = {id = "shortcuts_reset_text", text = "Reset User"}})
		},
	})

	ui.Button({
		id = "shortcuts_cancel",
		variant = .GHOST,
		radius = set.Radius(5),
		on_click = proc(_: ui.Button_Event) {
			if o.Shortcut_Capture_Active() {
				o.Shortcut_Capture_Cancel()
				shortcuts_discard_capture()
			}
			shortcuts_demo.rebind_index = -1
			shortcuts_set_status("Capture cancelled")
		},
		child = proc(_: ui.Button_state) {
			w.Text({config = {id = "shortcuts_cancel_text", text = "Cancel Capture"}})
		},
	})
}

@(private)
shortcuts_cell_child :: proc(_: w.Table_Cell_State) {
	w.Text({
		config = {
			id = shortcuts_row_ctx.text_id,
			text = shortcuts_row_ctx.cell_text,
		},
	})
}

@(private)
shortcuts_cell_text :: proc(cell_id: string, text_id: string, text: string) {
	shortcuts_row_ctx.cell_id = cell_id
	shortcuts_row_ctx.text_id = text_id
	shortcuts_row_ctx.cell_text = text
	w.Table_Cell({
		config = {
			id = cell_id,
			border = set.Border(.INHERIT),
			padding = set.Padding(o.Pd_struct{x = 8, y = 4}),
		},
		child = shortcuts_cell_child,
	})
}

@(private)
shortcuts_heading_row :: proc(_: w.Table_Row_State) {
	shortcuts_cell_text("shortcuts_h_0", "shortcuts_h_0_text", "Action")
	shortcuts_cell_text("shortcuts_h_1", "shortcuts_h_1_text", "Binding")
	shortcuts_cell_text("shortcuts_h_2", "shortcuts_h_2_text", "Scope")
	shortcuts_cell_text("shortcuts_h_3", "shortcuts_h_3_text", "Source")
	shortcuts_cell_text("shortcuts_h_4", "shortcuts_h_4_text", "")
}

@(private)
shortcuts_rebind_click :: proc(_: ui.Button_Event) {
	shortcuts_start_rebind(shortcuts_row_ctx.index)
}

@(private)
shortcuts_rebind_btn_child :: proc(_: ui.Button_state) {
	w.Text({
		config = {
			id = shortcuts_row_ctx.btn_text_id,
			text = shortcuts_row_ctx.rebind_label,
		},
	})
}

@(private)
shortcuts_rebind_cell_child :: proc(_: w.Table_Cell_State) {
	ui.Button({
		id = shortcuts_row_ctx.btn_id,
		variant = .GHOST,
		size = .SMALL,
		radius = set.Radius(4),
		on_click = shortcuts_rebind_click,
		child = shortcuts_rebind_btn_child,
	})
}

@(private)
shortcuts_binding_row_child :: proc(_: w.Table_Row_State) {
	i := shortcuts_row_ctx.index

	shortcuts_cell_text(
		fmt.tprintf("shortcuts_r%d_c0", i),
		fmt.tprintf("shortcuts_r%d_c0_text", i),
		shortcuts_row_ctx.action,
	)
	shortcuts_cell_text(
		fmt.tprintf("shortcuts_r%d_c1", i),
		fmt.tprintf("shortcuts_r%d_c1_text", i),
		shortcuts_row_ctx.chord,
	)
	shortcuts_cell_text(
		fmt.tprintf("shortcuts_r%d_c2", i),
		fmt.tprintf("shortcuts_r%d_c2_text", i),
		shortcuts_row_ctx.scope,
	)
	shortcuts_cell_text(
		fmt.tprintf("shortcuts_r%d_c3", i),
		fmt.tprintf("shortcuts_r%d_c3_text", i),
		shortcuts_row_ctx.source,
	)

	shortcuts_row_ctx.btn_id = fmt.tprintf("shortcuts_rebind_%d", i)
	shortcuts_row_ctx.btn_text_id = fmt.tprintf("shortcuts_rebind_%d_text", i)

	w.Table_Cell({
		config = {
			id = fmt.tprintf("shortcuts_r%d_c_btn", i),
			border = set.Border(.INHERIT),
			padding = set.Padding(o.Pd_struct{x = 8, y = 4}),
		},
		child = shortcuts_rebind_cell_child,
	})
}

@(private)
shortcuts_binding_row :: proc(index: int, binding: o.Shortcut_Binding) {
	shortcuts_row_ctx = {
		index        = index,
		action       = strings.clone(o.Shortcut_Action_Label(binding.id), context.temp_allocator),
		chord        = o.Shortcut_Format_Binding(binding, context.temp_allocator),
		scope        = strings.clone(
			shortcuts_scope_label(binding.scope, binding.scope_key, binding.scope_kind),
			context.temp_allocator,
		),
		source       = shortcuts_source_label(binding.source),
		rebind_label = shortcuts_demo.rebind_index == index ? "Listening…" : "Rebind",
	}

	w.Table_Row({
		config = {
			id = fmt.tprintf("shortcuts_row_%d", index),
			border = set.Border(.INHERIT),
		},
		child = shortcuts_binding_row_child,
	})
}

@(private)
shortcuts_table_body :: proc(_: w.Table_Body_State) {
	n := o.Shortcut_Binding_Count()
	for i in 0 ..< n {
		binding, ok := o.Shortcut_Binding_Get(i)
		if !ok do continue
		shortcuts_binding_row(i, binding)
	}
}

@(private)
shortcuts_table_head_row :: proc(_: w.Table_Head_State) {
	w.Table_Row({
		config = {
			id = "shortcuts_table_head_row",
			radius = set.Radius(o.Radius_corners{tl = .INHERIT, tr = .INHERIT}),
			border = set.Border(.INHERIT),
		},
		child = shortcuts_heading_row,
	})
}

@(private)
shortcuts_table_child :: proc(_: w.Table_State) {
	w.Table_Head({
		config = {
			id = "shortcuts_table_head",
			radius = set.Radius(o.Radius_corners{tl = .INHERIT, tr = .INHERIT}),
			border = set.Border(.INHERIT),
		},
		child = shortcuts_table_head_row,
	})

	w.Table_Body({
		config = {id = "shortcuts_table_body"},
		child = shortcuts_table_body,
	})
}

@(private)
shortcuts_status_text: string

@(private)
shortcuts_route_child :: proc(_: w.Rectangle_State) {
	conflicts := o.Shortcut_Collect_Conflicts(context.temp_allocator)
	shortcuts_status_text = shortcuts_demo.status
	if shortcuts_status_text == "" {
		shortcuts_status_text = fmt.tprintf(
			"%d bindings · %d conflicts · CTRL+P demo ping (%d)",
			o.Shortcut_Binding_Count(),
			len(conflicts),
			shortcuts_demo.ping_count,
		)
	}

	ui.Heading({id = "shortcuts_title", text = "Shortcuts", variant = .H2, theme = o.theme})

	w.Text({
		config = {
			id = "shortcuts_status",
			text = shortcuts_status_text,
			color = set.Colors(o.theme.palette[.FOREGROUND]),
		},
	})

	w.Rectangle({
		config = {
			id = "shortcuts_toolbar",
			direction = set.Direction(.HORIZONTAL),
			gap_x = set.Gap_X(8),
		},
		child = shortcuts_toolbar,
	})

	w.Table({
		config = {
			id = "shortcuts_table",
			direction = set.Direction(.VERTICAL),
			justify = set.Justify(o.Justify_Pos{x = .STRETCH, y = .START}),
			border = set.Border(1),
			radius = set.Radius(8),
		},
		child = shortcuts_table_child,
	})
}

shortcuts_route :: proc() {
	shortcuts_ensure_init()
	shortcuts_poll_capture()

	w.Rectangle({
		config = {
			id = "shortcuts_route",
			direction = set.Direction(.VERTICAL),
			gap_y = set.Gap_Y(12),
			justify = set.Justify(o.Justify_Pos{x = .STRETCH, y = .START}),
		},
		child = shortcuts_route_child,
	})
}

/*
Increments the demo ping counter (bound to CTRL+P by default).
*/
shortcuts_demo_ping :: proc() {
	shortcuts_demo.ping_count += 1
	shortcuts_set_status(fmt.tprintf("Demo ping %d", shortcuts_demo.ping_count))
}

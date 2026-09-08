package oni

import "core:strconv"
import "core:strings"
import kdl "libs:ode_kdl/src"

@(private)
Settings_Kdl_Node :: enum {
	Root,
	Window,
	Dpi,
	Fonts,
	Family,
	Face,
	Shortcuts,
	Bind,
	Field,
}

@(private)
Settings_Kdl_Bind_Acc :: struct {
	trigger:    string,
	action:     string,
	enabled:    bool,
	has_enabled: bool,
	scope:      Shortcut_Scope,
	scope_key:  string,
	scope_kind: Widget_Kind,
	priority:   i32,
	app_type:   App_Type_Filter,
}

/*
Parses a settings.kdl document into heap-owned Settings.

Starts from compiled defaults and overlays nodes present in the document.
On error, the returned Settings may be partially filled and must be destroyed.
*/
settings_parse_document :: proc(
	data: string,
	allocator := context.allocator,
) -> (
	Settings,
	Shortcut_Import_Error,
) {
	out := settings_defaults(allocator)
	if strings.trim_space(data) == "" {
		return out, {ok = true, line = 0}
	}

	parser: kdl.Parser
	kdl.init(&parser, data)
	defer kdl.destroy(&parser)

	stack: [dynamic]Settings_Kdl_Node
	defer delete(stack)
	append(&stack, Settings_Kdl_Node.Root)

	bind: Settings_Kdl_Bind_Acc
	field_name: string
	faces_replaced := false
	ok := true
	line := 1

	for ok {
		ev := kdl.next_event(&parser)
		switch ev.type {
		case .EOF:
			if len(stack) != 1 {
				ok = false
				break
			}

			settings_ensure_default_faces(&out, allocator)
			return out, {ok = true, line = 0}
		case .Parse_Error:
			ok = false
		case .Comment:
		case .Start_Node:
			parent := stack[len(stack) - 1]
			kind, field, start_ok := settings_kdl_start(parent, ev.name)
			if !start_ok {
				ok = false
				break
			}
			field_name = field
			if kind == .Family {
				if !faces_replaced {
					settings_kdl_clear_faces(&out)
					faces_replaced = true
				}
			}
			if kind == .Face {
				if !faces_replaced {
					settings_kdl_clear_faces(&out)
					faces_replaced = true
				}
				append(&out.font_faces, Font_Face_Desc{style = .NORMAL, weight = .Normal})
			}
			if kind == .Bind {
				bind = {enabled = true}
			}
			append(&stack, kind)
		case .End_Node:
			if len(stack) <= 1 {
				ok = false
				break
			}
			kind := stack[len(stack) - 1]
			pop(&stack)
			if kind == .Bind {
				if !settings_kdl_commit_bind(&out, bind, allocator) {
					ok = false
					break
				}
				if bind.trigger != "" do delete(bind.trigger)
				if bind.action != "" do delete(bind.action)
				if bind.scope_key != "" do delete(bind.scope_key)
				bind = {}
			}
			field_name = ""
		case .Argument, .Property:
			kind := stack[len(stack) - 1]
			name := ev.name if ev.type == .Property else field_name
			if kind == .Face || (kind == .Field && settings_kdl_is_face_field(name)) {
				if len(out.font_faces) == 0 {
					ok = false
					break
				}
				if !settings_kdl_apply_face(
					&out.font_faces[len(out.font_faces) - 1],
					name,
					ev.value,
					ev.type,
					allocator,
				) {
					ok = false
					break
				}
			} else if kind == .Family {
				if !settings_kdl_apply_family(&out, name, ev.value, ev.type, allocator) {
					ok = false
					break
				}
			} else if kind == .Bind {
				if !settings_kdl_apply_bind(&bind, name, ev.value, ev.type, allocator) {
					ok = false
					break
				}
			} else if !settings_kdl_apply(&out, kind, name, ev.value, allocator) {
				ok = false
				break
			}
		}
	}

	if bind.trigger != "" do delete(bind.trigger)
	if bind.action != "" do delete(bind.action)
	if bind.scope_key != "" do delete(bind.scope_key)
	return out, {ok = false, line = line}
}

/*
Serializes current engine settings and user shortcut bindings to KDL.

Caller owns the returned string.
*/
settings_export :: proc(allocator := context.allocator) -> string {
	if state == nil do return strings.clone("", allocator)
	settings_ensure()
	s := state.settings

	emitter: kdl.Emitter
	if kdl.init(&emitter) != nil {
		return strings.clone("", allocator)
	}
	defer kdl.destroy(&emitter)

	kdl.emit_node(&emitter, "window")
	kdl.start_emitting_children(&emitter)
	kdl.emit_node(&emitter, "mode")
	kdl.emit_arg(&emitter, settings_kdl_str(settings_kdl_window_mode_name(s.window_mode)))
	kdl.emit_node(&emitter, "title")
	kdl.emit_arg(&emitter, settings_kdl_str(s.window_title))
	kdl.emit_node(&emitter, "width")
	kdl.emit_arg(&emitter, settings_kdl_i64(i64(s.window_width)))
	kdl.emit_node(&emitter, "height")
	kdl.emit_arg(&emitter, settings_kdl_i64(i64(s.window_height)))
	kdl.emit_node(&emitter, "min-width")
	kdl.emit_arg(&emitter, settings_kdl_i64(i64(s.min_width)))
	kdl.emit_node(&emitter, "min-height")
	kdl.emit_arg(&emitter, settings_kdl_i64(i64(s.min_height)))
	kdl.finish_emitting_children(&emitter)

	kdl.emit_node(&emitter, "dpi")
	if s.dpi_scale > 0 {
		kdl.emit_property(&emitter, "scale", settings_kdl_f32(s.dpi_scale))
	} else {
		kdl.emit_property(&emitter, "scale", settings_kdl_str("auto"))
	}

	kdl.emit_node(&emitter, "fonts")
	kdl.start_emitting_children(&emitter)
	kdl.emit_node(&emitter, "body-size")
	kdl.emit_arg(&emitter, settings_kdl_f32(s.font_body_size))
	kdl.emit_node(&emitter, "heading-size")
	kdl.emit_arg(&emitter, settings_kdl_f32(s.font_heading_size))
	kdl.emit_node(&emitter, "family")
	kdl.emit_arg(&emitter, settings_kdl_str(s.font_family))
	kdl.start_emitting_children(&emitter)
	for face in s.font_faces {
		kdl.emit_node(&emitter, "face")
		kdl.start_emitting_children(&emitter)
		kdl.emit_node(&emitter, "path")
		kdl.emit_arg(&emitter, settings_kdl_str(face.path))
		kdl.emit_node(&emitter, "style")
		kdl.emit_arg(&emitter, settings_kdl_str(settings_kdl_style_name(face.style)))
		kdl.emit_node(&emitter, "weight")
		kdl.emit_arg(&emitter, settings_kdl_str(settings_kdl_weight_name(face.weight)))
		kdl.finish_emitting_children(&emitter)
	}
	kdl.finish_emitting_children(&emitter)
	kdl.finish_emitting_children(&emitter)

	kdl.emit_node(&emitter, "shortcuts")
	kdl.start_emitting_children(&emitter)
	if state.shortcuts.bindings != nil {
		for binding in state.shortcuts.bindings {
			if binding.source != .User do continue
			settings_kdl_emit_bind(&emitter, binding)
		}
	}
	kdl.finish_emitting_children(&emitter)

	kdl.emit_end(&emitter)
	return strings.clone(kdl.get_buffer(&emitter), allocator)
}

@(private)
settings_kdl_clear_faces :: proc(s: ^Settings) {
	for face in s.font_faces {
		if face.path != "" do delete(face.path)
	}
	clear(&s.font_faces)
}

@(private)
settings_kdl_start :: proc(
	parent: Settings_Kdl_Node,
	name: string,
) -> (
	Settings_Kdl_Node,
	string,
	bool,
) {
	key := settings_kdl_norm(name)
	switch parent {
	case .Root:
		switch key {
		case "window":
			return .Window, "", true
		case "dpi":
			return .Dpi, "", true
		case "fonts":
			return .Fonts, "", true
		case "shortcuts":
			return .Shortcuts, "", true
		case "bind":
			return .Bind, "", true
		}
	case .Window:
		switch key {
		case "title", "width", "height", "min-width", "min-height", "mode":
			return .Field, key, true
		}
	case .Dpi:
		if key == "scale" do return .Field, "scale", true
	case .Fonts:
		switch key {
		case "body-size", "heading-size":
			return .Field, key, true
		case "family":
			return .Family, "", true
		}
	case .Family:
		switch key {
		case "face":
			return .Face, "", true
		case "name":
			return .Field, "family", true
		}
	case .Face:
		switch key {
		case "path", "style", "weight":
			return .Field, key, true
		}
	case .Shortcuts:
		if key == "bind" do return .Bind, "", true
	case .Bind, .Field:
	}
	return .Root, "", false
}

@(private)
settings_kdl_apply :: proc(
	s: ^Settings,
	kind: Settings_Kdl_Node,
	name: string,
	value: kdl.Value,
	allocator := context.allocator,
) -> bool {
	key := settings_kdl_norm(name)
	switch kind {
	case .Window:
		return settings_kdl_apply_window(s, key, value, allocator)
	case .Field:
		switch key {
		case "title", "width", "height", "min-width", "min-height", "mode":
			return settings_kdl_apply_window(s, key, value, allocator)
		case "scale":
			return settings_kdl_apply_dpi(s, "scale", value)
		case "family", "body-size", "heading-size":
			return settings_kdl_apply_fonts(s, key, value, allocator)
		case "":
			return true
		}
		return false
	case .Dpi:
		return settings_kdl_apply_dpi(s, key, value)
	case .Fonts:
		return settings_kdl_apply_fonts(s, key, value, allocator)
	case .Root, .Family, .Face, .Shortcuts, .Bind:
		return false
	}
	return false
}

@(private)
settings_kdl_is_face_field :: proc(name: string) -> bool {
	switch settings_kdl_norm(name) {
	case "path", "style", "weight":
		return true
	}
	return false
}

@(private)
settings_kdl_apply_family :: proc(
	s: ^Settings,
	name: string,
	value: kdl.Value,
	ev: kdl.Event_Type,
	allocator := context.allocator,
) -> bool {
	key := settings_kdl_norm(name)
	if ev == .Argument && key == "" {
		key = "family"
	}
	if key == "name" {
		key = "family"
	}
	return settings_kdl_apply_fonts(s, key, value, allocator)
}

@(private)
settings_kdl_apply_window :: proc(
	s: ^Settings,
	key: string,
	value: kdl.Value,
	allocator := context.allocator,
) -> bool {
	switch key {
	case "title":
		str, ok := settings_kdl_as_string(value)
		if !ok do return false
		if s.window_title != "" do delete(s.window_title)
		s.window_title = strings.clone(str, allocator)
		return true
	case "width":
		n, ok := settings_kdl_as_i32(value)
		if !ok do return false
		s.window_width = n
		return true
	case "height":
		n, ok := settings_kdl_as_i32(value)
		if !ok do return false
		s.window_height = n
		return true
	case "min-width":
		n, ok := settings_kdl_as_i32(value)
		if !ok do return false
		s.min_width = n
		return true
	case "min-height":
		n, ok := settings_kdl_as_i32(value)
		if !ok do return false
		s.min_height = n
		return true
	case "mode":
		str, ok := settings_kdl_as_string(value)
		if !ok do return false
		mode, mode_ok := settings_kdl_parse_window_mode(str)
		if !mode_ok do return false
		s.window_mode = mode
		return true
	case "":
		return true
	}
	return false
}

@(private)
settings_kdl_apply_dpi :: proc(s: ^Settings, key: string, value: kdl.Value) -> bool {
	if key != "" && key != "scale" do return false
	if kdl.is_null(value) {
		s.dpi_scale = 0
		return true
	}
	if str, is_str := settings_kdl_as_string(value); is_str {
		if settings_kdl_norm(str) == "auto" {
			s.dpi_scale = 0
			return true
		}
	}
	n, ok := settings_kdl_as_f32(value)
	if !ok do return false
	s.dpi_scale = n
	return true
}

@(private)
settings_kdl_apply_fonts :: proc(
	s: ^Settings,
	key: string,
	value: kdl.Value,
	allocator := context.allocator,
) -> bool {
	switch key {
	case "family":
		str, ok := settings_kdl_as_string(value)
		if !ok do return false
		if s.font_family != "" do delete(s.font_family)
		s.font_family = strings.clone(str, allocator)
		return true
	case "body-size":
		n, ok := settings_kdl_as_f32(value)
		if !ok do return false
		s.font_body_size = n
		return true
	case "heading-size":
		n, ok := settings_kdl_as_f32(value)
		if !ok do return false
		s.font_heading_size = n
		return true
	case "":
		return true
	}
	return false
}

@(private)
settings_kdl_apply_face :: proc(
	face: ^Font_Face_Desc,
	name: string,
	value: kdl.Value,
	ev: kdl.Event_Type,
	allocator := context.allocator,
) -> bool {
	key := settings_kdl_norm(name)
	if ev == .Argument && key == "" do key = "path"
	switch key {
	case "path":
		str, ok := settings_kdl_as_string(value)
		if !ok do return false
		if face.path != "" do delete(face.path)
		face.path = strings.clone(str, allocator)
		return true
	case "style":
		str, ok := settings_kdl_as_string(value)
		if !ok do return false
		style, style_ok := settings_kdl_parse_style(str)
		if !style_ok do return false
		face.style = style
		return true
	case "weight":
		if str, is_str := settings_kdl_as_string(value); is_str {
			weight, weight_ok := settings_kdl_parse_weight(str)
			if !weight_ok do return false
			face.weight = weight
			return true
		}
		n, ok := settings_kdl_as_f32(value)
		if !ok do return false
		face.weight = n
		return true
	case "":
		return true
	}
	return false
}

@(private)
settings_kdl_apply_bind :: proc(
	bind: ^Settings_Kdl_Bind_Acc,
	name: string,
	value: kdl.Value,
	ev: kdl.Event_Type,
	allocator := context.allocator,
) -> bool {
	key := settings_kdl_norm(name)
	if ev == .Argument {
		if bind.trigger == "" {
			str, ok := settings_kdl_as_string(value)
			if !ok do return false
			bind.trigger = strings.clone(str, allocator)
			return true
		}
		if bind.action == "" {
			str, ok := settings_kdl_as_string(value)
			if !ok do return false
			bind.action = strings.clone(str, allocator)
			return true
		}
		return false
	}

	switch key {
	case "trigger":
		str, ok := settings_kdl_as_string(value)
		if !ok do return false
		if bind.trigger != "" do delete(bind.trigger)
		bind.trigger = strings.clone(str, allocator)
		return true
	case "action":
		str, ok := settings_kdl_as_string(value)
		if !ok do return false
		if bind.action != "" do delete(bind.action)
		bind.action = strings.clone(str, allocator)
		return true
	case "enabled":
		b, ok := settings_kdl_as_bool(value)
		if !ok do return false
		bind.enabled = b
		bind.has_enabled = true
		return true
	case "scope":
		str, ok := settings_kdl_as_string(value)
		if !ok do return false
		bind.scope = shortcut_parse_scope(str)
		return true
	case "scope-key":
		str, ok := settings_kdl_as_string(value)
		if !ok do return false
		if bind.scope_key != "" do delete(bind.scope_key)
		bind.scope_key = strings.clone(str, allocator)
		return true
	case "scope-kind":
		if str, is_str := settings_kdl_as_string(value); is_str {
			kind, kind_ok := settings_kdl_parse_widget_kind(str)
			if !kind_ok do return false
			bind.scope_kind = kind
			return true
		}
		n, ok := settings_kdl_as_i32(value)
		if !ok do return false
		bind.scope_kind = Widget_Kind(n)
		return true
	case "priority":
		n, ok := settings_kdl_as_i32(value)
		if !ok do return false
		bind.priority = n
		return true
	case "app-type":
		n, ok := settings_kdl_as_i32(value)
		if !ok do return false
		bind.app_type = App_Type_Filter(App_Type_Id(n))
		return true
	}
	return false
}

@(private)
settings_kdl_commit_bind :: proc(
	s: ^Settings,
	bind: Settings_Kdl_Bind_Acc,
	allocator := context.allocator,
) -> bool {
	if bind.trigger == "" || bind.action == "" do return false
	row: Shortcut_Parsed_Binding
	row.enabled = true
	row.source = .User
	row.scope = .Global
	if !shortcut_parse_trigger(bind.trigger, &row) do return false
	row.id = strings.clone(bind.action, allocator)
	row.enabled = bind.has_enabled ? bind.enabled : true
	row.scope = bind.scope
	if bind.scope_key != "" {
		row.scope_key = strings.clone(bind.scope_key, allocator)
	}
	row.scope_kind = bind.scope_kind
	row.priority = bind.priority
	row.app_type = bind.app_type
	row.source = .User
	append(&s.shortcut_rows, row)
	return true
}

@(private)
settings_kdl_emit_bind :: proc(emitter: ^kdl.Emitter, binding: Shortcut_Binding) {
	trigger := shortcut_format_trigger_token(binding, context.temp_allocator)
	kdl.emit_node(emitter, "bind")
	kdl.emit_property(emitter, "trigger", settings_kdl_str(trigger))
	kdl.emit_property(emitter, "action", settings_kdl_str(binding.id))
	if !binding.enabled {
		kdl.emit_property(emitter, "enabled", settings_kdl_bool(false))
	}
	if binding.scope != .Global {
		kdl.emit_property(emitter, "scope", settings_kdl_str(shortcut_scope_name_lower(binding.scope)))
	}
	if binding.scope_key != "" {
		kdl.emit_property(emitter, "scope-key", settings_kdl_str(binding.scope_key))
	}
	if binding.scope == .Focused_Kind && binding.scope_kind != {} {
		kdl.emit_property(emitter, "scope-kind", settings_kdl_i64(i64(binding.scope_kind)))
	}
	if binding.priority != 0 {
		kdl.emit_property(emitter, "priority", settings_kdl_i64(i64(binding.priority)))
	}
	if type_id, is_type := binding.app_type.(App_Type_Id); is_type {
		kdl.emit_property(emitter, "app-type", settings_kdl_i64(i64(type_id)))
	}
}

@(private)
settings_kdl_norm :: proc(name: string) -> string {
	replaced, _ := strings.replace_all(name, "_", "-", context.temp_allocator)
	return strings.to_lower(replaced, context.temp_allocator)
}

@(private)
settings_kdl_str :: proc(s: string) -> kdl.Value {
	return {variant = s}
}

@(private)
settings_kdl_bool :: proc(b: bool) -> kdl.Value {
	return {variant = b}
}

@(private)
settings_kdl_i64 :: proc(n: i64) -> kdl.Value {
	num: kdl.Number = n
	return {variant = num}
}

@(private)
settings_kdl_f32 :: proc(n: f32) -> kdl.Value {
	if n == f32(i64(n)) {
		return settings_kdl_i64(i64(n))
	}
	num: kdl.Number = f64(n)
	return {variant = num}
}

@(private)
settings_kdl_as_string :: proc(v: kdl.Value) -> (string, bool) {
	#partial switch val in v.variant {
	case string:
		return val, true
	case kdl.Number:
		#partial switch n in val {
		case string:
			return n, true
		}
	}
	return "", false
}

@(private)
settings_kdl_as_i32 :: proc(v: kdl.Value) -> (i32, bool) {
	#partial switch val in v.variant {
	case string:
		n, ok := strconv.parse_i64(val)
		return i32(n), ok
	case kdl.Number:
		switch n in val {
		case i64:
			return i32(n), true
		case f64:
			return i32(n), true
		case string:
			parsed, ok := strconv.parse_i64(n)
			return i32(parsed), ok
		}
	}
	return 0, false
}

@(private)
settings_kdl_as_f32 :: proc(v: kdl.Value) -> (f32, bool) {
	#partial switch val in v.variant {
	case string:
		n, ok := strconv.parse_f32(val)
		return n, ok
	case kdl.Number:
		switch n in val {
		case i64:
			return f32(n), true
		case f64:
			return f32(n), true
		case string:
			parsed, ok := strconv.parse_f32(n)
			return parsed, ok
		}
	}
	return 0, false
}

@(private)
settings_kdl_as_bool :: proc(v: kdl.Value) -> (bool, bool) {
	#partial switch val in v.variant {
	case bool:
		return val, true
	case string:
		return shortcut_parse_bool(val), true
	case kdl.Number:
		n, ok := settings_kdl_as_i32(v)
		if !ok do return false, false
		return n != 0, true
	}
	return false, false
}

@(private)
settings_kdl_parse_style :: proc(s: string) -> (Font_Styles, bool) {
	switch settings_kdl_norm(s) {
	case "normal", "roman", "upright":
		return .NORMAL, true
	case "italic", "oblique":
		return .ITALIC, true
	}
	return .NORMAL, false
}

@(private)
settings_kdl_parse_window_mode :: proc(s: string) -> (Window_Mode, bool) {
	switch settings_kdl_norm(s) {
	case "window":
		return .Window, true
	case "borderless":
		return .Borderless, true
	case "maximize":
		return .Maximize, true
	case "fullscreen":
		return .Fullscreen, true
	}
	return .Window, false
}

@(private)
settings_kdl_window_mode_name :: proc(mode: Window_Mode) -> string {
	switch mode {
	case .Window:
		return "window"
	case .Borderless:
		return "borderless"
	case .Maximize:
		return "maximize"
	case .Fullscreen:
		return "fullscreen"
	}
	return "window"
}

@(private)
settings_kdl_parse_weight :: proc(s: string) -> (Font_Weights, bool) {
	switch settings_kdl_norm(s) {
	case "thin", "100":
		return .Thin, true
	case "extra-light", "extralight", "200":
		return .Extra_Light, true
	case "light", "300":
		return .Light, true
	case "normal", "regular", "400":
		return .Normal, true
	case "medium", "500":
		return .Medium, true
	case "semi-bold", "semibold", "600":
		return .Semi_Bold, true
	case "bold", "700":
		return .Bold, true
	case "extra-bold", "extrabold", "800":
		return .Extra_Bold, true
	case "heavy", "black", "900":
		return .Heavy, true
	}
	return .Normal, false
}

@(private)
settings_kdl_style_name :: proc(style: Font_Style) -> string {
	if kind, ok := style.(Font_Styles); ok {
		switch kind {
		case .NORMAL:
			return "normal"
		case .ITALIC:
			return "italic"
		}
	}
	return "normal"
}

@(private)
settings_kdl_weight_name :: proc(weight: Font_Weight) -> string {
	if kind, ok := weight.(Font_Weights); ok {
		switch kind {
		case .Thin:
			return "thin"
		case .Extra_Light:
			return "extra-light"
		case .Light:
			return "light"
		case .Normal:
			return "normal"
		case .Medium:
			return "medium"
		case .Semi_Bold:
			return "semi-bold"
		case .Bold:
			return "bold"
		case .Extra_Bold:
			return "extra-bold"
		case .Heavy:
			return "heavy"
		}
	}
	return "normal"
}

@(private)
settings_kdl_parse_widget_kind :: proc(s: string) -> (Widget_Kind, bool) {
	switch settings_kdl_norm(s) {
	case "rect":
		return .RECT, true
	case "text":
		return .TEXT, true
	case "rich-text":
		return .RICH_TEXT, true
	case "text-input":
		return .TEXT_INPUT, true
	case "rich-text-input":
		return .RICH_TEXT_INPUT, true
	case "button":
		return .BUTTON, true
	case "table":
		return .TABLE, true
	case "select":
		return .SELECT, true
	case "select-trigger":
		return .SELECT_TRIGGER, true
	case "select-value":
		return .SELECT_VALUE, true
	case "option-group":
		return .OPTION_GROUP, true
	case "option":
		return .OPTION, true
	}
	return .RECT, false
}

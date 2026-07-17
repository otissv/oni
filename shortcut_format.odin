package oni

import "core:fmt"
import "core:strconv"
import "core:strings"
import "core:unicode"
import "core:unicode/utf8"
import sdl "vendor:sdl3"

/*
Human-friendly bindings file format (versionless):

	# comments
	CTRL+EQUAL = view.zoom_in
	CTRL+WHEEL+UP = view.zoom_in
	CTRL+WHEEL+UP = view.zoom_in { enabled = false }
	G,S = goto.save { scope = context, scope_key = "artboard" }
	GAMEPAD_START = window.toggle_fullscreen

Config rows are always user overrides: they replace any builtin with the same
trigger. Only user bindings are exported.
*/

@(private)
Shortcut_Parsed_Binding :: struct {
	id:             string,
	trigger:        Shortcut_Trigger,
	chord:          Shortcut_Chord,
	wheel_sign:     i8,
	sequence:       [SHORTCUT_SEQUENCE_MAX]Scancode,
	sequence_len:   u8,
	gamepad_button: i32,
	mouse_button:   u8,
	scope:          Shortcut_Scope,
	scope_key:      string,
	scope_kind:     Widget_Kind,
	priority:       i32,
	enabled:        bool,
	source:         Shortcut_Source,
}

/*
Serializes all user bindings to the human-friendly text format.

Caller owns the returned string (allocator).
*/
shortcut_export_bindings :: proc(allocator := context.allocator) -> string {
	if state == nil do return strings.clone("", allocator)
	b := strings.builder_make(allocator)
	fmt.sbprintf(&b, "# trigger = action {{ options }}\n")
	fmt.sbprintf(&b, "# User overrides only. Builtins live in the engine.\n")
	fmt.sbprintf(&b, "# Tokens: CTRL+EQUAL, CTRL+WHEEL+UP, LEFT_CLICK, GAMEPAD_START, G,S\n")
	fmt.sbprintf(&b, "# Options: enabled, scope, scope_key, scope_kind, priority\n")
	for binding in state.shortcuts.bindings {
		if binding.source != .User do continue
		shortcut_export_friendly(&b, binding)
	}
	return strings.to_string(b)
}

/*
Imports bindings from Shortcut_Export text.

Validates the entire payload before mutating. When `replace_user` is true and
validation succeeds, clears user bindings then applies rows.
No version header; blank lines and `#` comments are skipped.
*/
shortcut_import_bindings :: proc(data: string, replace_user := true) -> bool {
	err := shortcut_import_bindings_ex(data, replace_user)
	return err.ok
}

/*
Like Shortcut_Import_Bindings but returns the 1-based failing line (0 = empty/apply).
*/
shortcut_import_bindings_ex :: proc(data: string, replace_user := true) -> Shortcut_Import_Error {
	if state == nil do return {ok = false, line = 0}
	shortcut_init()
	lines := strings.split_lines(data, context.temp_allocator)

	parsed := make([dynamic]Shortcut_Parsed_Binding, context.temp_allocator)
	for line, i in lines {
		trimmed := strings.trim_space(line)
		if trimmed == "" || strings.has_prefix(trimmed, "#") do continue
		row: Shortcut_Parsed_Binding
		if !shortcut_parse_friendly_line(trimmed, &row) do return {ok = false, line = i + 1}
		append(&parsed, row)
	}

	if replace_user {
		shortcut_clear_user_bindings()
	}

	for &row in parsed {
		// Config always installs as user and overrides matching builtin triggers.
		shortcut_remove_trigger_matches(row)
		if !shortcut_apply_parsed(row) do return {ok = false, line = 0}
	}
	return {ok = true, line = 0}
}

@(private)
shortcut_export_friendly :: proc(b: ^strings.Builder, binding: Shortcut_Binding) {
	trigger := shortcut_format_trigger_token(binding, context.temp_allocator)
	fmt.sbprintf(b, "%s = %s", trigger, binding.id)

	needs_opts :=
		!binding.enabled ||
		binding.scope != .Global ||
		binding.scope_key != "" ||
		binding.priority != 0 ||
		(binding.scope == .Focused_Kind && binding.scope_kind != {})

	if needs_opts {
		fmt.sbprintf(b, " {{")
		first := true
		if !binding.enabled {
			fmt.sbprintf(b, " enabled = false")
			first = false
		}
		if binding.scope != .Global {
			if !first do fmt.sbprintf(b, ",")
			fmt.sbprintf(b, " scope = %s", shortcut_scope_name_lower(binding.scope))
			first = false
		}
		if binding.scope_key != "" {
			if !first do fmt.sbprintf(b, ",")
			fmt.sbprintf(b, " scope_key = %q", binding.scope_key)
			first = false
		}
		if binding.scope == .Focused_Kind {
			if !first do fmt.sbprintf(b, ",")
			fmt.sbprintf(b, " scope_kind = %d", int(binding.scope_kind))
			first = false
		}
		if binding.priority != 0 {
			if !first do fmt.sbprintf(b, ",")
			fmt.sbprintf(b, " priority = %d", binding.priority)
		}
		_ = first
		fmt.sbprintf(b, " }}")
	}
	fmt.sbprintf(b, "\n")
}

@(private)
shortcut_format_trigger_token :: proc(
	binding: Shortcut_Binding,
	allocator := context.allocator,
) -> string {
	b := strings.builder_make(allocator)
	shortcut_write_mods(&b, binding.chord)
	switch binding.trigger {
	case .Key:
		strings.write_string(&b, shortcut_key_token(binding.chord.key, context.temp_allocator))
	case .Wheel_Y:
		if binding.wheel_sign > 0 {
			strings.write_string(&b, "WHEEL+UP")
		} else if binding.wheel_sign < 0 {
			strings.write_string(&b, "WHEEL+DOWN")
		} else {
			strings.write_string(&b, "WHEEL")
		}
	case .Mouse_Button:
		strings.write_string(&b, shortcut_mouse_token(binding.mouse_button))
	case .Sequence:
		for i in 0 ..< int(binding.sequence_len) {
			if i > 0 do strings.write_string(&b, ",")
			strings.write_string(
				&b,
				shortcut_key_token(binding.sequence[i], context.temp_allocator),
			)
		}
	case .Gamepad:
		name := string(sdl.GetGamepadStringForButton(sdl.GamepadButton(binding.gamepad_button)))
		if len(name) > 0 {
			fmt.sbprintf(&b, "GAMEPAD_%s", shortcut_upper_snake(name, context.temp_allocator))
		} else {
			fmt.sbprintf(&b, "GAMEPAD_%d", binding.gamepad_button)
		}
	}
	return strings.to_string(b)
}

@(private)
shortcut_write_mods :: proc(b: ^strings.Builder, chord: Shortcut_Chord) {
	if chord.ctrl do strings.write_string(b, "CTRL+")
	if chord.shift do strings.write_string(b, "SHIFT+")
	if chord.alt do strings.write_string(b, "ALT+")
	if chord.super do strings.write_string(b, "MOD+")
}

@(private)
shortcut_key_token :: proc(key: Scancode, allocator := context.allocator) -> string {
	#partial switch key {
	case .EQUALS:
		return "EQUAL"
	case .MINUS:
		return "MINUS"
	case .KP_PLUS:
		return "KP_PLUS"
	case .KP_MINUS:
		return "KP_MINUS"
	case .KP_MULTIPLY:
		return "KP_MULTIPLY"
	case .KP_DIVIDE:
		return "KP_DIVIDE"
	case .KP_PERIOD:
		return "KP_PERIOD"
	case .KP_0:
		return "KP_0"
	case .PERIOD:
		return "PERIOD"
	case .COMMA:
		return "COMMA"
	case .SLASH:
		return "SLASH"
	case .BACKSLASH:
		return "BACKSLASH"
	case .SEMICOLON:
		return "SEMICOLON"
	case .APOSTROPHE:
		return "APOSTROPHE"
	case .GRAVE:
		return "GRAVE"
	case .LEFTBRACKET:
		return "LEFT_BRACKET"
	case .RIGHTBRACKET:
		return "RIGHT_BRACKET"
	case .SPACE:
		return "SPACE"
	case .RETURN:
		return "ENTER"
	case .ESCAPE:
		return "ESC"
	case .TAB:
		return "TAB"
	case .BACKSPACE:
		return "BACKSPACE"
	case .DELETE:
		return "DELETE"
	case .INSERT:
		return "INSERT"
	case .HOME:
		return "HOME"
	case .END:
		return "END"
	case .PAGEUP:
		return "PAGE_UP"
	case .PAGEDOWN:
		return "PAGE_DOWN"
	case .UP:
		return "UP"
	case .DOWN:
		return "DOWN"
	case .LEFT:
		return "LEFT"
	case .RIGHT:
		return "RIGHT"
	}

	name := string(sdl.GetScancodeName(sdl.Scancode(key)))
	if len(name) > 0 {
		return shortcut_upper_snake(name, allocator)
	}
	return fmt.aprintf("KEY_%d", int(key), allocator = allocator)
}

@(private)
shortcut_upper_snake :: proc(name: string, allocator := context.allocator) -> string {
	b := strings.builder_make(allocator)
	prev_underscore := true
	for r in name {
		if r == ' ' || r == '-' || r == '+' || r == '/' {
			if !prev_underscore {
				strings.write_rune(&b, '_')
				prev_underscore = true
			}
			continue
		}
		if r == '_' {
			if !prev_underscore {
				strings.write_rune(&b, '_')
				prev_underscore = true
			}
			continue
		}
		strings.write_rune(&b, unicode.to_upper(r))
		prev_underscore = false
	}
	return strings.to_string(b)
}

@(private)
shortcut_mouse_token :: proc(button: u8) -> string {
	switch button {
	case sdl.BUTTON_LEFT:
		return "LEFT_CLICK"
	case sdl.BUTTON_RIGHT:
		return "RIGHT_CLICK"
	case sdl.BUTTON_MIDDLE:
		return "MIDDLE_CLICK"
	}
	return "MOUSE"
}

@(private)
shortcut_scope_name_lower :: proc(scope: Shortcut_Scope) -> string {
	switch scope {
	case .Context:
		return "context"
	case .Focused_Id:
		return "focused_id"
	case .Focused_Any:
		return "focused_any"
	case .Focused_Kind:
		return "focused_kind"
	case .Global:
		return "global"
	}
	return "global"
}

@(private)
shortcut_parse_friendly_line :: proc(line: string, out: ^Shortcut_Parsed_Binding) -> bool {
	out^ = {
		enabled = true,
		source  = .User,
		scope   = .Global,
	}

	// Prefer first " = " so options like { enabled = false } stay in the RHS,
	// while triggers such as CTRL+EQUAL still round-trip.
	sep := strings.index(line, " = ")
	trigger_text: string
	rest: string
	if sep >= 0 {
		trigger_text = strings.trim_space(line[:sep])
		rest = strings.trim_space(line[sep + 3:])
	} else {
		eq := strings.index_byte(line, '=')
		if eq <= 0 do return false
		trigger_text = strings.trim_space(line[:eq])
		rest = strings.trim_space(line[eq + 1:])
	}
	if trigger_text == "" || rest == "" do return false

	action_text := rest
	opts_text := ""
	if brace := strings.index_byte(rest, '{'); brace >= 0 {
		action_text = strings.trim_space(rest[:brace])
		end := strings.last_index_byte(rest, '}')
		if end <= brace do return false
		opts_text = rest[brace + 1:end]
	}
	if action_text == "" do return false
	out.id = action_text
	out.source = .User

	if opts_text != "" && !shortcut_parse_opts(opts_text, out) do return false
	out.source = .User // config never owns "builtin"
	return shortcut_parse_trigger(trigger_text, out)
}

@(private)
shortcut_parse_opts :: proc(text: string, out: ^Shortcut_Parsed_Binding) -> bool {
	parts := strings.split(text, ",", context.temp_allocator)
	for part in parts {
		kv := strings.trim_space(part)
		if kv == "" do continue
		eq := strings.index_byte(kv, '=')
		if eq <= 0 do return false
		key := strings.to_lower(strings.trim_space(kv[:eq]), context.temp_allocator)
		value := strings.trim_space(kv[eq + 1:])
		switch key {
		case "enabled":
			out.enabled = shortcut_parse_bool(value)
		case "scope":
			out.scope = shortcut_parse_scope(value)
		case "scope_key":
			out.scope_key = shortcut_parse_quoted(value)
		case "scope_kind":
			out.scope_kind = Widget_Kind(shortcut_parse_int(value))
		case "priority":
			out.priority = i32(shortcut_parse_int(value))
		case:
			return false
		}
	}
	return true
}

@(private)
shortcut_parse_quoted :: proc(value: string) -> string {
	if len(value) >= 2 && value[0] == '"' && value[len(value) - 1] == '"' {
		return value[1:len(value) - 1]
	}
	return value
}

@(private)
shortcut_parse_trigger :: proc(text: string, out: ^Shortcut_Parsed_Binding) -> bool {
	trimmed := strings.trim_space(text)
	if trimmed == "" do return false

	// Sequence: G,S or Ctrl+G,S (mods apply to final key)
	if strings.contains_rune(trimmed, ',') {
		return shortcut_parse_sequence_trigger(trimmed, out)
	}

	mods, primary, ok := shortcut_split_mods_primary(trimmed)
	if !ok do return false
	out.chord.ctrl = mods.ctrl
	out.chord.shift = mods.shift
	out.chord.alt = mods.alt
	out.chord.super = mods.super

	token := strings.to_lower(primary, context.temp_allocator)
	token, _ = strings.replace_all(token, "-", "_", context.temp_allocator)

	if token == "wheel+up" ||
	   token == "wheel_up" ||
	   token == "wheelup" ||
	   token == "wheelscrollup" {
		out.trigger = .Wheel_Y
		out.wheel_sign = 1
		return true
	}
	if token == "wheel+down" ||
	   token == "wheel_down" ||
	   token == "wheeldown" ||
	   token == "wheelscrolldown" {
		out.trigger = .Wheel_Y
		out.wheel_sign = -1
		return true
	}
	if token == "wheel" || token == "wheelscroll" {
		out.trigger = .Wheel_Y
		out.wheel_sign = 0
		return true
	}
	if token == "wheelscrollright" ||
	   token == "wheel+right" ||
	   token == "wheel_right" ||
	   token == "wheelright" ||
	   token == "wheelscrollleft" ||
	   token == "wheel+left" ||
	   token == "wheel_left" ||
	   token == "wheelleft" {
		return false
	}
	if token == "left_click" || token == "leftclick" || token == "mouseleft" || token == "mouse1" {
		out.trigger = .Mouse_Button
		out.mouse_button = sdl.BUTTON_LEFT
		return true
	}
	if token == "right_click" ||
	   token == "rightclick" ||
	   token == "mouseright" ||
	   token == "mouse2" {
		out.trigger = .Mouse_Button
		out.mouse_button = sdl.BUTTON_RIGHT
		return true
	}
	if token == "middle_click" ||
	   token == "middleclick" ||
	   token == "mousemiddle" ||
	   token == "mouse3" {
		out.trigger = .Mouse_Button
		out.mouse_button = sdl.BUTTON_MIDDLE
		return true
	}

	if strings.has_prefix(token, "gamepad_") {
		btn_name := token[8:]
		btn, bok := shortcut_parse_gamepad_button(btn_name)
		if !bok do return false
		out.trigger = .Gamepad
		out.gamepad_button = i32(btn)
		return true
	}
	if strings.has_prefix(token, "gamepad") && len(token) > 7 {
		btn_name := token[7:]
		btn, bok := shortcut_parse_gamepad_button(btn_name)
		if !bok do return false
		out.trigger = .Gamepad
		out.gamepad_button = i32(btn)
		return true
	}

	key, kok := shortcut_parse_key_token(primary)
	if !kok do return false
	out.trigger = .Key
	out.chord.key = key
	return true
}

@(private)
shortcut_parse_sequence_trigger :: proc(text: string, out: ^Shortcut_Parsed_Binding) -> bool {
	parts := strings.split(text, ",", context.temp_allocator)
	if len(parts) < 2 || len(parts) > SHORTCUT_SEQUENCE_MAX do return false

	mods: Shortcut_Chord
	keys: [SHORTCUT_SEQUENCE_MAX]Scancode
	for part, i in parts {
		piece := strings.trim_space(part)
		if piece == "" do return false
		part_mods, primary, ok := shortcut_split_mods_primary(piece)
		if !ok do return false
		if i == 0 {
			mods = part_mods
		} else if part_mods.ctrl || part_mods.shift || part_mods.alt || part_mods.super {
			// Final key may carry mods: G,Ctrl+S
			if i == len(parts) - 1 {
				mods = part_mods
			} else {
				return false
			}
		}
		key, kok := shortcut_parse_key_token(primary)
		if !kok do return false
		keys[i] = key
	}

	out.trigger = .Sequence
	out.sequence = keys
	out.sequence_len = u8(len(parts))
	out.chord = {
		key   = keys[len(parts) - 1],
		ctrl  = mods.ctrl,
		shift = mods.shift,
		alt   = mods.alt,
		super = mods.super,
	}
	return true
}

@(private)
shortcut_split_mods_primary :: proc(
	text: string,
) -> (
	mods: Shortcut_Chord,
	primary: string,
	ok: bool,
) {
	rest := strings.trim_space(text)
	if rest == "" do return {}, "", false

	for len(rest) > 0 {
		lower := strings.to_lower(rest, context.temp_allocator)
		plus := strings.index_byte(rest, '+')
		if plus <= 0 do break
		mod := strings.trim_space(lower[:plus])
		matched := false
		switch mod {
		case "ctrl", "control", "ctl":
			mods.ctrl = true
			matched = true
		case "shift":
			mods.shift = true
			matched = true
		case "alt", "option", "opt":
			mods.alt = true
			matched = true
		case "mod", "super", "meta", "cmd", "command", "win", "gui":
			mods.super = true
			matched = true
		}
		if !matched do break
		rest = strings.trim_space(rest[plus + 1:])
	}

	if rest == "" do return {}, "", false
	return mods, rest, true
}

@(private)
shortcut_parse_key_token :: proc(token: string) -> (Scancode, bool) {
	t := strings.trim_space(token)
	if t == "" do return .UNKNOWN, false

	lower := strings.to_lower(t, context.temp_allocator)
	lower, _ = strings.replace_all(lower, "-", "_", context.temp_allocator)

	switch lower {
	case "=", "equal", "equals":
		return .EQUALS, true
	case "-", "minus":
		return .MINUS, true
	case "kp_plus", "kp+":
		return .KP_PLUS, true
	case "kp_minus", "kp-":
		return .KP_MINUS, true
	case "kp_multiply", "kp*":
		return .KP_MULTIPLY, true
	case "kp_divide", "kp/":
		return .KP_DIVIDE, true
	case "kp_period", "kp.":
		return .KP_PERIOD, true
	case "kp_0":
		return .KP_0, true
	case ".", "period":
		return .PERIOD, true
	case ",", "comma":
		return .COMMA, true
	case "/", "slash":
		return .SLASH, true
	case "\\", "backslash":
		return .BACKSLASH, true
	case ";", "semicolon":
		return .SEMICOLON, true
	case "'", "apostrophe":
		return .APOSTROPHE, true
	case "`", "grave":
		return .GRAVE, true
	case "[", "left_bracket", "leftbracket":
		return .LEFTBRACKET, true
	case "]", "right_bracket", "rightbracket":
		return .RIGHTBRACKET, true
	case "space", "spc":
		return .SPACE, true
	case "enter", "return", "ret":
		return .RETURN, true
	case "esc", "escape":
		return .ESCAPE, true
	case "tab":
		return .TAB, true
	case "backspace", "bksp":
		return .BACKSPACE, true
	case "delete", "del":
		return .DELETE, true
	case "insert", "ins":
		return .INSERT, true
	case "home":
		return .HOME, true
	case "end":
		return .END, true
	case "page_up", "pageup", "pgup":
		return .PAGEUP, true
	case "page_down", "pagedown", "pgdn", "pgdown":
		return .PAGEDOWN, true
	case "up":
		return .UP, true
	case "down":
		return .DOWN, true
	case "left":
		return .LEFT, true
	case "right":
		return .RIGHT, true
	}

	if strings.has_prefix(lower, "key_") {
		n, nok := strconv.parse_int(lower[4:])
		if nok do return Scancode(n), true
	}
	if strings.has_prefix(lower, "key") {
		n, nok := strconv.parse_int(lower[3:])
		if nok do return Scancode(n), true
	}

	// SDL name lookup: as-is, spaced, and single letters.
	if code := sdl.GetScancodeFromName(strings.clone_to_cstring(t, context.temp_allocator));
	   code != .UNKNOWN {
		return Scancode(code), true
	}
	spaced := shortcut_insert_spaces_pascal(t, context.temp_allocator)
	if code := sdl.GetScancodeFromName(strings.clone_to_cstring(spaced, context.temp_allocator));
	   code != .UNKNOWN {
		return Scancode(code), true
	}
	snake_spaced, _ := strings.replace_all(lower, "_", " ", context.temp_allocator)
	if code := sdl.GetScancodeFromName(
		strings.clone_to_cstring(snake_spaced, context.temp_allocator),
	); code != .UNKNOWN {
		return Scancode(code), true
	}
	if len(t) == 1 {
		upper := strings.to_upper(t, context.temp_allocator)
		if code := sdl.GetScancodeFromName(
			strings.clone_to_cstring(upper, context.temp_allocator),
		); code != .UNKNOWN {
			return Scancode(code), true
		}
	}
	return .UNKNOWN, false
}

@(private)
shortcut_insert_spaces_pascal :: proc(token: string, allocator := context.allocator) -> string {
	b := strings.builder_make(allocator)
	for r, i in token {
		if i > 0 && unicode.is_upper(r) {
			prev, _ := utf8.decode_last_rune_in_string(token[:i])
			if unicode.is_lower(prev) || unicode.is_digit(prev) {
				strings.write_rune(&b, ' ')
			}
		}
		strings.write_rune(&b, r)
	}
	return strings.to_string(b)
}

@(private)
shortcut_parse_gamepad_button :: proc(name: string) -> (sdl.GamepadButton, bool) {
	n := strings.trim_space(name)
	if n == "" do return .INVALID, false
	if v, ok := strconv.parse_int(n); ok {
		return sdl.GamepadButton(v), true
	}
	lower := strings.to_lower(n, context.temp_allocator)
	lower, _ = strings.replace_all(lower, "-", "_", context.temp_allocator)
	spaced, _ := strings.replace_all(lower, "_", " ", context.temp_allocator)
	dashed, _ := strings.replace_all(lower, "_", "-", context.temp_allocator)
	pascal_spaced := shortcut_insert_spaces_pascal(n, context.temp_allocator)
	candidates := [?]cstring {
		strings.clone_to_cstring(lower, context.temp_allocator),
		strings.clone_to_cstring(dashed, context.temp_allocator),
		strings.clone_to_cstring(spaced, context.temp_allocator),
		strings.clone_to_cstring(n, context.temp_allocator),
		strings.clone_to_cstring(pascal_spaced, context.temp_allocator),
		strings.clone_to_cstring(
			strings.to_lower(pascal_spaced, context.temp_allocator),
			context.temp_allocator,
		),
	}
	for c in candidates {
		btn := sdl.GetGamepadButtonFromString(c)
		if btn != .INVALID do return btn, true
	}
	return .INVALID, false
}

/*
Removes every binding whose trigger matches `row` (any action id / scope).
Used so config lines override builtins that share the same trigger.
*/
@(private)
shortcut_remove_trigger_matches :: proc(row: Shortcut_Parsed_Binding) {
	if state == nil do return
	probe := Shortcut_Binding {
		trigger        = row.trigger,
		chord          = row.chord,
		wheel_sign     = row.wheel_sign,
		sequence       = row.sequence,
		sequence_len   = row.sequence_len,
		gamepad_button = row.gamepad_button,
		mouse_button   = row.mouse_button,
	}
	for i := len(state.shortcuts.bindings) - 1; i >= 0; i -= 1 {
		if !shortcut_triggers_conflict(state.shortcuts.bindings[i], probe) do continue
		shortcut_free_binding(&state.shortcuts.bindings[i])
		ordered_remove(&state.shortcuts.bindings, i)
	}
}

@(private)
shortcut_apply_parsed :: proc(row: Shortcut_Parsed_Binding) -> bool {
	switch row.trigger {
	case .Key:
		return shortcut_bind_key(
			{
				id = row.id,
				chord = row.chord,
				scope = row.scope,
				scope_key = row.scope_key,
				scope_kind = row.scope_kind,
				priority = row.priority,
				enabled = row.enabled,
				source = .User,
			},
		)
	case .Wheel_Y:
		return shortcut_bind_wheel(
			{
				id = row.id,
				wheel_sign = row.wheel_sign,
				chord = row.chord,
				scope = row.scope,
				scope_key = row.scope_key,
				scope_kind = row.scope_kind,
				priority = row.priority,
				enabled = row.enabled,
				source = .User,
			},
		)
	case .Mouse_Button:
		return shortcut_bind_mouse(
			{
				id = row.id,
				button = row.mouse_button,
				chord = row.chord,
				scope = row.scope,
				scope_key = row.scope_key,
				scope_kind = row.scope_kind,
				priority = row.priority,
				enabled = row.enabled,
				source = .User,
			},
		)
	case .Sequence:
		seq := row.sequence
		keys := seq[:row.sequence_len]
		return shortcut_bind_sequence(
			{
				id = row.id,
				keys = keys,
				chord = row.chord,
				scope = row.scope,
				scope_key = row.scope_key,
				scope_kind = row.scope_kind,
				priority = row.priority,
				enabled = row.enabled,
				source = .User,
			},
		)
	case .Gamepad:
		return shortcut_bind_gamepad(
			{
				id = row.id,
				button = sdl.GamepadButton(row.gamepad_button),
				scope = row.scope,
				scope_key = row.scope_key,
				scope_kind = row.scope_kind,
				priority = row.priority,
				enabled = row.enabled,
				source = .User,
			},
		)
	}
	return false
}

package oni

import "core:strconv"
import "core:strings"
import sdl "vendor:sdl3"

/*
Stable action ids for built-in engine shortcuts.

Apps bind extra ids and register handlers with Shortcut_Register_Action.
`app.quit` has a builtin handler but no default binding (apps opt in).
Host reload/restart are remappable builtins (default F5/F6).
*/
SHORTCUT_VIEW_ZOOM_IN :: "view.zoom_in"
SHORTCUT_VIEW_ZOOM_OUT :: "view.zoom_out"
SHORTCUT_VIEW_RESET :: "view.reset"
SHORTCUT_WINDOW_TOGGLE_FULLSCREEN :: "window.toggle_fullscreen"
SHORTCUT_APP_QUIT :: "app.quit"
SHORTCUT_HOST_RELOAD :: "host.reload"
SHORTCUT_HOST_RESTART :: "host.restart"

SHORTCUT_CONTEXT_POPOVER :: "popover"
SHORTCUT_SEQUENCE_MAX :: 4
SHORTCUT_SEQUENCE_TIMEOUT_FRAMES :: u32(45)
SHORTCUT_MOUSE_BUTTON_COUNT :: 8
SHORTCUT_DEFAULT_BINDINGS_PATH :: "oni-shortcuts.conf"

/*
When a binding is eligible to fire.
*/
Shortcut_Scope :: enum u8 {
	Global,
	Context, // scope_key on context stack (or auto popover)
	Focused_Id, // focused widget id == scope_key
	Focused_Any, // any focused widget
	Focused_Kind, // focused widget's Widget_Kind == scope_kind
}

/*
Keyboard / pointer chord: primary key (when used) plus required modifiers (exact match).

For wheel and mouse-button triggers, `key` is unused; only modifier flags apply.
*/
Shortcut_Chord :: struct {
	key:                     Scancode,
	ctrl, shift, alt, super: bool,
}

Shortcut_Trigger :: enum u8 {
	Key,
	Wheel_Y,
	Sequence, // ordered keys; modifiers apply to the final key
	Gamepad,
	Mouse_Button, // left/right/middle press; modifiers exact-match
}

/*
Binding ownership. Config rows are always User. Engine defaults use Builtin.
Public Bind_Opts default to User (zero value); pass Builtin only from install_defaults.
*/
Shortcut_Source :: enum u8 {
	User,
	Builtin,
}

/*
One remappable binding from a trigger to an action id.
*/
Shortcut_Binding :: struct {
	id:             string, // owned
	trigger:        Shortcut_Trigger,
	chord:          Shortcut_Chord,
	wheel_sign:     i8, // +1 / -1 / 0 (any)
	sequence:       [SHORTCUT_SEQUENCE_MAX]Scancode,
	sequence_len:   u8,
	gamepad_button: i32, // sdl.GamepadButton as i32
	mouse_button:   u8, // sdl.BUTTON_LEFT / RIGHT / MIDDLE
	scope:          Shortcut_Scope,
	scope_key:      string, // owned
	scope_kind:     Widget_Kind,
	priority:       i32,
	enabled:        bool,
	source:         Shortcut_Source,
}

Shortcut_Bind_Opts :: struct {
	scope:      Shortcut_Scope,
	scope_key:  string,
	scope_kind: Widget_Kind,
	priority:   i32,
	disabled:   bool,
	source:     Shortcut_Source, // default User; pass .Builtin only when restoring builtins
}

Shortcut_Event :: struct {
	id:           string,
	chord:        Shortcut_Chord,
	wheel_y:      f32,
	mouse_screen: Vec2,
	focused_id:   string,
	focused_kind: Widget_Kind,
}

Shortcut_Action_Proc :: proc(event: ^Shortcut_Event)
Shortcut_Reload_Hook :: proc()

Shortcut_Conflict :: struct {
	id_a, id_b:     string,
	trigger:        Shortcut_Trigger,
	chord:          Shortcut_Chord,
	wheel_sign:     i8,
	sequence:       [SHORTCUT_SEQUENCE_MAX]Scancode,
	sequence_len:   u8,
	gamepad_button: i32,
	mouse_button:   u8,
	scope:          Shortcut_Scope,
}

Shortcut_Capture_Mode :: enum u8 {
	Key,
	Wheel,
	Mouse,
	Sequence, // accumulate keys; Enter confirms (min 2); Escape cancels
	Gamepad,
	Any, // first key / wheel / mouse / gamepad
}

Shortcut_Capture_Result :: struct {
	trigger:        Shortcut_Trigger,
	chord:          Shortcut_Chord,
	wheel_sign:     i8,
	mouse_button:   u8,
	sequence:       [SHORTCUT_SEQUENCE_MAX]Scancode,
	sequence_len:   u8,
	gamepad_button: i32,
}

Shortcut_Capture_State :: struct {
	active:    bool,
	done:      bool,
	cancelled: bool,
	mode:      Shortcut_Capture_Mode,
	result:    Shortcut_Capture_Result,
}

Shortcut_Import_Error :: struct {
	ok:   bool,
	line: int, // 1-based; 0 when header/empty
}

Shortcut_State :: struct {
	bindings:             [dynamic]Shortcut_Binding,
	actions:              map[string]Shortcut_Action_Proc,
	action_labels:        map[string]string, // owned values
	contexts:             [dynamic]string, // owned
	pending_contexts:     [dynamic]string, // owned; promoted next begin_frame
	kind_by_id:           map[string]Widget_Kind,
	text_input_by_id:     map[string]bool,
	consumed_keys:        [KEY_COUNT]bool,
	consumed_wheel:       bool,
	consumed_mouse:       [SHORTCUT_MOUSE_BUTTON_COUNT]bool,
	consumed_gamepad:     [GAMEPAD_BUTTON_COUNT]bool,
	gamepad_prev:         [GAMEPAD_BUTTON_COUNT]bool,
	text_input_active:    bool, // sticky manual override
	processed:            bool,
	defaults_installed:   bool,
	sequence_buf:         [SHORTCUT_SEQUENCE_MAX]Scancode,
	sequence_len:         u8,
	sequence_idle_frames: u32,
	capture:              Shortcut_Capture_State,
	reload_hook:          Shortcut_Reload_Hook,
}

shortcut_init :: proc() {
	if state == nil do return
	if state.shortcuts.actions == nil {
		state.shortcuts.actions = make(map[string]Shortcut_Action_Proc)
	}
	if state.shortcuts.action_labels == nil {
		state.shortcuts.action_labels = make(map[string]string)
	}
}

shortcut_shutdown :: proc() {
	if state == nil do return
	shortcut_clear_bindings()
	shortcut_clear_actions()
	shortcut_clear_action_labels()
	shortcut_free_context_list(&state.shortcuts.contexts)
	shortcut_free_context_list(&state.shortcuts.pending_contexts)
	if state.shortcuts.kind_by_id != nil {
		delete(state.shortcuts.kind_by_id)
		state.shortcuts.kind_by_id = nil
	}
	if state.shortcuts.text_input_by_id != nil {
		delete(state.shortcuts.text_input_by_id)
		state.shortcuts.text_input_by_id = nil
	}
	state.shortcuts = {}
}

shortcut_begin_frame :: proc() {
	if state == nil do return
	shortcut_free_context_list(&state.shortcuts.contexts)
	// Promote contexts pushed during last frame's draw pass.
	if len(state.shortcuts.pending_contexts) > 0 {
		for ctx in state.shortcuts.pending_contexts {
			append(&state.shortcuts.contexts, ctx)
		}
		clear(&state.shortcuts.pending_contexts)
	}
	if state.shortcuts.kind_by_id != nil {
		clear(&state.shortcuts.kind_by_id)
	}
	if state.shortcuts.text_input_by_id != nil {
		clear(&state.shortcuts.text_input_by_id)
	}
	state.shortcuts.consumed_keys = {}
	state.shortcuts.consumed_wheel = false
	state.shortcuts.consumed_mouse = {}
	state.shortcuts.consumed_gamepad = {}
	state.shortcuts.processed = false
	if state.shortcuts.sequence_len > 0 {
		state.shortcuts.sequence_idle_frames += 1
		if state.shortcuts.sequence_idle_frames >= SHORTCUT_SEQUENCE_TIMEOUT_FRAMES {
			shortcut_sequence_reset()
		}
	}
}

/*
Records a widget id → kind for Focused_Kind scope matching.

Called from layout when a named widget is pushed.
*/
shortcut_note_kind :: proc(id: string, kind: Widget_Kind) {
	if state == nil || id == "" do return
	if state.shortcuts.kind_by_id == nil {
		state.shortcuts.kind_by_id = make(map[string]Widget_Kind)
	}
	state.shortcuts.kind_by_id[id] = kind
}

/*
Marks a widget id as accepting plain-key text input for this frame.

Focused text-input widgets suppress non-command shortcuts automatically.
*/
shortcut_note_text_input :: proc(id: string) {
	if state == nil || id == "" do return
	if state.shortcuts.text_input_by_id == nil {
		state.shortcuts.text_input_by_id = make(map[string]bool)
	}
	state.shortcuts.text_input_by_id[id] = true
}

shortcut_register_action :: proc(id: string, action: Shortcut_Action_Proc) {
	if state == nil || id == "" || action == nil do return
	shortcut_init()
	state.shortcuts.actions[id] = action
}

shortcut_unregister_action :: proc(id: string) {
	if state == nil || state.shortcuts.actions == nil || id == "" do return
	delete_key(&state.shortcuts.actions, id)
}

shortcut_clear_actions :: proc() {
	if state == nil do return
	if state.shortcuts.actions != nil {
		clear(&state.shortcuts.actions)
		delete(state.shortcuts.actions)
		state.shortcuts.actions = nil
	}
}

/*
Sets a human-readable label for an action id (bindings-table display).

Caller may pass a temporary string; it is cloned. Empty label removes the entry.
*/
shortcut_set_action_label :: proc(id: string, label: string) {
	if state == nil || id == "" do return
	shortcut_init()
	if old, ok := state.shortcuts.action_labels[id]; ok {
		delete(old)
		delete_key(&state.shortcuts.action_labels, id)
	}
	if label == "" do return
	state.shortcuts.action_labels[id] = strings.clone(label)
}

shortcut_action_label :: proc(id: string) -> string {
	if state == nil || id == "" do return id
	if state.shortcuts.action_labels != nil {
		if label, ok := state.shortcuts.action_labels[id]; ok && label != "" {
			return label
		}
	}
	return id
}

@(private)
shortcut_clear_action_labels :: proc() {
	if state == nil || state.shortcuts.action_labels == nil do return
	for _, label in state.shortcuts.action_labels {
		delete(label)
	}
	clear(&state.shortcuts.action_labels)
	delete(state.shortcuts.action_labels)
	state.shortcuts.action_labels = nil
}

/*
Registers a hook invoked after builtin actions are rebound on hot reload.

Apps use this to re-register action procs that live in the reloaded library.
*/
shortcut_set_reload_hook :: proc(hook: Shortcut_Reload_Hook) {
	if state == nil do return
	state.shortcuts.reload_hook = hook
}

shortcut_bind :: proc(id: string, chord: Shortcut_Chord, opts: Shortcut_Bind_Opts = {}) -> bool {
	return shortcut_bind_key(
		id,
		chord,
		opts.scope,
		opts.scope_key,
		opts.scope_kind,
		opts.priority,
		!opts.disabled,
		opts.source,
	)
}

shortcut_bind_key :: proc(
	id: string,
	chord: Shortcut_Chord,
	scope: Shortcut_Scope,
	scope_key: string,
	scope_kind: Widget_Kind,
	priority: i32,
	enabled: bool,
	source: Shortcut_Source,
) -> bool {
	if state == nil || id == "" || chord.key == .UNKNOWN do return false
	shortcut_init()

	for &b in state.shortcuts.bindings {
		if b.trigger == .Key && b.id == id && shortcut_chord_equal(b.chord, chord) {
			shortcut_update_scope(&b, scope, scope_key, scope_kind)
			b.priority = priority
			b.enabled = enabled
			b.source = source
			return true
		}
	}

	binding := Shortcut_Binding {
		id         = strings.clone(id),
		trigger    = .Key,
		chord      = chord,
		scope      = scope,
		scope_key  = scope_key != "" ? strings.clone(scope_key) : "",
		scope_kind = scope_kind,
		priority   = priority,
		enabled    = enabled,
		source     = source,
	}
	append(&state.shortcuts.bindings, binding)
	return true
}

/*
Binds vertical mouse-wheel motion to an action id.

`mods` uses only ctrl/shift/alt/super (exact match). `mods.key` is ignored.
wheel_sign: +1 (up), -1 (down), or 0 (any non-zero).
*/
shortcut_bind_wheel :: proc(
	id: string,
	wheel_sign: i8,
	mods: Shortcut_Chord = {},
	opts: Shortcut_Bind_Opts = {},
) -> bool {
	return shortcut_bind_wheel_src(id, wheel_sign, mods, opts, opts.source)
}

@(private)
shortcut_bind_wheel_src :: proc(
	id: string,
	wheel_sign: i8,
	mods: Shortcut_Chord,
	opts: Shortcut_Bind_Opts,
	source: Shortcut_Source,
) -> bool {
	if state == nil || id == "" do return false
	shortcut_init()
	chord := Shortcut_Chord {
		ctrl  = mods.ctrl,
		shift = mods.shift,
		alt   = mods.alt,
		super = mods.super,
	}

	for &b in state.shortcuts.bindings {
		if b.trigger == .Wheel_Y &&
		   b.id == id &&
		   b.wheel_sign == wheel_sign &&
		   shortcut_chord_mods_equal(b.chord, chord) {
			shortcut_update_scope(&b, opts.scope, opts.scope_key, opts.scope_kind)
			b.priority = opts.priority
			b.enabled = !opts.disabled
			b.source = source
			b.chord = chord
			return true
		}
	}

	binding := Shortcut_Binding {
		id         = strings.clone(id),
		trigger    = .Wheel_Y,
		chord      = chord,
		wheel_sign = wheel_sign,
		scope      = opts.scope,
		scope_key  = opts.scope_key != "" ? strings.clone(opts.scope_key) : "",
		scope_kind = opts.scope_kind,
		priority   = opts.priority,
		enabled    = !opts.disabled,
		source     = source,
	}
	append(&state.shortcuts.bindings, binding)
	return true
}

/*
Binds a mouse-button press (sdl.BUTTON_LEFT / RIGHT / MIDDLE) with optional modifiers.
*/
shortcut_bind_mouse :: proc(
	id: string,
	button: u8,
	mods: Shortcut_Chord = {},
	opts: Shortcut_Bind_Opts = {},
) -> bool {
	return shortcut_bind_mouse_src(id, button, mods, opts, opts.source)
}

@(private)
shortcut_bind_mouse_src :: proc(
	id: string,
	button: u8,
	mods: Shortcut_Chord,
	opts: Shortcut_Bind_Opts,
	source: Shortcut_Source,
) -> bool {
	if state == nil || id == "" || button == 0 do return false
	shortcut_init()
	chord := Shortcut_Chord {
		ctrl  = mods.ctrl,
		shift = mods.shift,
		alt   = mods.alt,
		super = mods.super,
	}

	for &b in state.shortcuts.bindings {
		if b.trigger == .Mouse_Button &&
		   b.id == id &&
		   b.mouse_button == button &&
		   shortcut_chord_mods_equal(b.chord, chord) {
			shortcut_update_scope(&b, opts.scope, opts.scope_key, opts.scope_kind)
			b.priority = opts.priority
			b.enabled = !opts.disabled
			b.source = source
			b.chord = chord
			return true
		}
	}

	binding := Shortcut_Binding {
		id           = strings.clone(id),
		trigger      = .Mouse_Button,
		chord        = chord,
		mouse_button = button,
		scope        = opts.scope,
		scope_key    = opts.scope_key != "" ? strings.clone(opts.scope_key) : "",
		scope_kind   = opts.scope_kind,
		priority     = opts.priority,
		enabled      = !opts.disabled,
		source       = source,
	}
	append(&state.shortcuts.bindings, binding)
	return true
}

/*
Binds an ordered key sequence (e.g. G then S). Modifiers apply to the final key.
*/
shortcut_bind_sequence :: proc(
	id: string,
	keys: []Scancode,
	mods: Shortcut_Chord = {},
	opts: Shortcut_Bind_Opts = {},
) -> bool {
	return shortcut_bind_sequence_src(id, keys, mods, opts, opts.source)
}

@(private)
shortcut_bind_sequence_src :: proc(
	id: string,
	keys: []Scancode,
	mods: Shortcut_Chord,
	opts: Shortcut_Bind_Opts,
	source: Shortcut_Source,
) -> bool {
	if state == nil || id == "" || len(keys) < 2 || len(keys) > SHORTCUT_SEQUENCE_MAX do return false
	for k in keys {
		if k == .UNKNOWN do return false
	}
	shortcut_init()

	seq: [SHORTCUT_SEQUENCE_MAX]Scancode
	for k, i in keys {
		seq[i] = k
	}
	slen := u8(len(keys))
	chord := Shortcut_Chord {
		key   = keys[len(keys) - 1],
		ctrl  = mods.ctrl,
		shift = mods.shift,
		alt   = mods.alt,
		super = mods.super,
	}

	for &b in state.shortcuts.bindings {
		if b.trigger == .Sequence &&
		   b.id == id &&
		   b.sequence_len == slen &&
		   shortcut_sequence_equal(b.sequence, seq, slen) &&
		   shortcut_chord_mods_equal(b.chord, chord) {
			shortcut_update_scope(&b, opts.scope, opts.scope_key, opts.scope_kind)
			b.priority = opts.priority
			b.enabled = !opts.disabled
			b.source = source
			b.chord = chord
			return true
		}
	}

	binding := Shortcut_Binding {
		id           = strings.clone(id),
		trigger      = .Sequence,
		chord        = chord,
		sequence     = seq,
		sequence_len = slen,
		scope        = opts.scope,
		scope_key    = opts.scope_key != "" ? strings.clone(opts.scope_key) : "",
		scope_kind   = opts.scope_kind,
		priority     = opts.priority,
		enabled      = !opts.disabled,
		source       = source,
	}
	append(&state.shortcuts.bindings, binding)
	return true
}

shortcut_bind_gamepad :: proc(
	id: string,
	button: sdl.GamepadButton,
	opts: Shortcut_Bind_Opts = {},
) -> bool {
	return shortcut_bind_gamepad_src(id, button, opts, opts.source)
}

@(private)
shortcut_bind_gamepad_src :: proc(
	id: string,
	button: sdl.GamepadButton,
	opts: Shortcut_Bind_Opts,
	source: Shortcut_Source,
) -> bool {
	if state == nil || id == "" || button == .INVALID do return false
	shortcut_init()
	btn := i32(button)

	for &b in state.shortcuts.bindings {
		if b.trigger == .Gamepad && b.id == id && b.gamepad_button == btn {
			shortcut_update_scope(&b, opts.scope, opts.scope_key, opts.scope_kind)
			b.priority = opts.priority
			b.enabled = !opts.disabled
			b.source = source
			return true
		}
	}

	binding := Shortcut_Binding {
		id             = strings.clone(id),
		trigger        = .Gamepad,
		gamepad_button = btn,
		scope          = opts.scope,
		scope_key      = opts.scope_key != "" ? strings.clone(opts.scope_key) : "",
		scope_kind     = opts.scope_kind,
		priority       = opts.priority,
		enabled        = !opts.disabled,
		source         = source,
	}
	append(&state.shortcuts.bindings, binding)
	return true
}

shortcut_unbind :: proc(id: string, chord: Shortcut_Chord) {
	if state == nil || id == "" do return
	for i := len(state.shortcuts.bindings) - 1; i >= 0; i -= 1 {
		b := state.shortcuts.bindings[i]
		if b.trigger == .Key && b.id == id && shortcut_chord_equal(b.chord, chord) {
			shortcut_free_binding(&state.shortcuts.bindings[i])
			ordered_remove(&state.shortcuts.bindings, i)
		}
	}
}

shortcut_unbind_wheel :: proc(id: string, wheel_sign: i8 = 0) {
	if state == nil || id == "" do return
	for i := len(state.shortcuts.bindings) - 1; i >= 0; i -= 1 {
		b := state.shortcuts.bindings[i]
		if b.trigger != .Wheel_Y || b.id != id do continue
		if wheel_sign != 0 && b.wheel_sign != wheel_sign do continue
		shortcut_free_binding(&state.shortcuts.bindings[i])
		ordered_remove(&state.shortcuts.bindings, i)
	}
}

shortcut_unbind_mouse :: proc(id: string, button: u8, mods: Shortcut_Chord = {}) {
	if state == nil || id == "" || button == 0 do return
	chord := Shortcut_Chord {
		ctrl  = mods.ctrl,
		shift = mods.shift,
		alt   = mods.alt,
		super = mods.super,
	}
	for i := len(state.shortcuts.bindings) - 1; i >= 0; i -= 1 {
		b := state.shortcuts.bindings[i]
		if b.trigger != .Mouse_Button || b.id != id do continue
		if b.mouse_button != button do continue
		if !shortcut_chord_mods_equal(b.chord, chord) do continue
		shortcut_free_binding(&state.shortcuts.bindings[i])
		ordered_remove(&state.shortcuts.bindings, i)
	}
}

shortcut_unbind_sequence :: proc(id: string, keys: []Scancode, mods: Shortcut_Chord = {}) {
	if state == nil || id == "" || len(keys) < 2 || len(keys) > SHORTCUT_SEQUENCE_MAX do return
	seq: [SHORTCUT_SEQUENCE_MAX]Scancode
	for k, i in keys {
		seq[i] = k
	}
	slen := u8(len(keys))
	chord := Shortcut_Chord {
		ctrl  = mods.ctrl,
		shift = mods.shift,
		alt   = mods.alt,
		super = mods.super,
	}
	for i := len(state.shortcuts.bindings) - 1; i >= 0; i -= 1 {
		b := state.shortcuts.bindings[i]
		if b.trigger != .Sequence || b.id != id do continue
		if b.sequence_len != slen do continue
		if !shortcut_sequence_equal(b.sequence, seq, slen) do continue
		if !shortcut_chord_mods_equal(b.chord, chord) do continue
		shortcut_free_binding(&state.shortcuts.bindings[i])
		ordered_remove(&state.shortcuts.bindings, i)
	}
}

shortcut_unbind_gamepad :: proc(id: string, button: sdl.GamepadButton) {
	if state == nil || id == "" || button == .INVALID do return
	btn := i32(button)
	for i := len(state.shortcuts.bindings) - 1; i >= 0; i -= 1 {
		b := state.shortcuts.bindings[i]
		if b.trigger != .Gamepad || b.id != id do continue
		if b.gamepad_button != btn do continue
		shortcut_free_binding(&state.shortcuts.bindings[i])
		ordered_remove(&state.shortcuts.bindings, i)
	}
}

shortcut_unbind_all :: proc(id: string) {
	if state == nil || id == "" do return
	for i := len(state.shortcuts.bindings) - 1; i >= 0; i -= 1 {
		if state.shortcuts.bindings[i].id == id {
			shortcut_free_binding(&state.shortcuts.bindings[i])
			ordered_remove(&state.shortcuts.bindings, i)
		}
	}
}

shortcut_set_enabled :: proc(id: string, enabled: bool) {
	if state == nil || id == "" do return
	for &b in state.shortcuts.bindings {
		if b.id == id {
			b.enabled = enabled
		}
	}
}

shortcut_clear_bindings :: proc() {
	if state == nil do return
	for &b in state.shortcuts.bindings {
		shortcut_free_binding(&b)
	}
	clear(&state.shortcuts.bindings)
	delete(state.shortcuts.bindings)
	state.shortcuts.bindings = nil
	state.shortcuts.defaults_installed = false
}

/*
Removes user bindings only; keeps builtin defaults.
*/
shortcut_clear_user_bindings :: proc() {
	if state == nil do return
	for i := len(state.shortcuts.bindings) - 1; i >= 0; i -= 1 {
		if state.shortcuts.bindings[i].source == .User {
			shortcut_free_binding(&state.shortcuts.bindings[i])
			ordered_remove(&state.shortcuts.bindings, i)
		}
	}
}

shortcut_push_context :: proc(name: string) {
	if state == nil || name == "" do return
	owned := strings.clone(name)
	// Draw-pass pushes apply next frame so layout-time process still sees tick/layout contexts.
	if state.ui.pass == .Draw {
		append(&state.shortcuts.pending_contexts, owned)
		return
	}
	append(&state.shortcuts.contexts, owned)
}

shortcut_pop_context :: proc() {
	if state == nil do return
	if state.ui.pass == .Draw {
		n := len(state.shortcuts.pending_contexts)
		if n > 0 {
			delete(state.shortcuts.pending_contexts[n - 1])
			ordered_remove(&state.shortcuts.pending_contexts, n - 1)
		}
		return
	}
	n := len(state.shortcuts.contexts)
	if n > 0 {
		delete(state.shortcuts.contexts[n - 1])
		ordered_remove(&state.shortcuts.contexts, n - 1)
	}
}

@(private)
shortcut_free_context_list :: proc(list: ^[dynamic]string) {
	if list == nil do return
	for ctx in list^ {
		delete(ctx)
	}
	clear(list)
	delete(list^)
	list^ = nil
}

shortcut_set_text_input_active :: proc(active: bool) {
	if state == nil do return
	state.shortcuts.text_input_active = active
}

shortcut_text_input_active :: proc() -> bool {
	return state != nil && state.shortcuts.text_input_active
}

shortcut_consume_key :: proc(key: Scancode) {
	if state == nil do return
	idx := int(key)
	if idx >= 0 && idx < KEY_COUNT {
		state.shortcuts.consumed_keys[idx] = true
	}
}

shortcut_key_consumed :: proc(key: Scancode) -> bool {
	if state == nil do return false
	idx := int(key)
	if idx < 0 || idx >= KEY_COUNT do return false
	return state.shortcuts.consumed_keys[idx]
}

shortcut_consume_wheel :: proc() {
	if state == nil do return
	state.shortcuts.consumed_wheel = true
}

shortcut_wheel_consumed :: proc() -> bool {
	return state != nil && state.shortcuts.consumed_wheel
}

shortcut_consume_mouse :: proc(button: u8) {
	if state == nil do return
	if int(button) < SHORTCUT_MOUSE_BUTTON_COUNT {
		state.shortcuts.consumed_mouse[button] = true
	}
}

shortcut_mouse_consumed :: proc(button: u8) -> bool {
	if state == nil do return false
	if int(button) >= SHORTCUT_MOUSE_BUTTON_COUNT do return false
	return state.shortcuts.consumed_mouse[button]
}

shortcut_gamepad_consumed :: proc(button: sdl.GamepadButton) -> bool {
	if state == nil do return false
	idx, ok := gamepad_button_index(button)
	if !ok do return false
	return state.shortcuts.consumed_gamepad[idx]
}

/*
Starts capture for remapping UIs. Escape cancels.

Key: next non-modifier key completes.
Wheel / Mouse / Gamepad: next matching input completes.
Sequence: non-modifier keys accumulate; Enter confirms (min 2); Escape cancels.
Any: first key, wheel, mouse, or gamepad input completes.
While active, Shortcut_Process does not fire actions.
*/
shortcut_capture_begin :: proc(mode: Shortcut_Capture_Mode = .Key) {
	if state == nil do return
	state.shortcuts.capture = {
		active = true,
		mode   = mode,
	}
}

shortcut_capture_cancel :: proc() {
	if state == nil do return
	state.shortcuts.capture = {
		cancelled = true,
	}
}

shortcut_capture_active :: proc() -> bool {
	return state != nil && state.shortcuts.capture.active
}

/*
Returns the captured trigger when done. Clears done/cancelled flags after read.
*/
shortcut_capture_take :: proc() -> (result: Shortcut_Capture_Result, done: bool, cancelled: bool) {
	if state == nil do return {}, false, false
	c := state.shortcuts.capture
	if c.done || c.cancelled {
		state.shortcuts.capture = {}
	}
	return c.result, c.done, c.cancelled
}

shortcut_install_defaults :: proc() {
	if state == nil do return
	shortcut_init()
	shortcut_register_builtin_actions()
	if state.shortcuts.defaults_installed do return

	shortcut_defaults()

	// app.quit action is registered; Escape is not bound by default.
	state.shortcuts.defaults_installed = true
}

shortcut_rebind_builtin_actions :: proc() {
	if state == nil do return
	shortcut_init()
	shortcut_register_builtin_actions()
	if state.shortcuts.reload_hook != nil {
		state.shortcuts.reload_hook()
	}
}

@(private)
shortcut_register_builtin_actions :: proc() {
	shortcut_register_action(SHORTCUT_VIEW_ZOOM_IN, shortcut_action_view_zoom_in)
	shortcut_register_action(SHORTCUT_VIEW_ZOOM_OUT, shortcut_action_view_zoom_out)
	shortcut_register_action(SHORTCUT_VIEW_RESET, shortcut_action_view_reset)
	shortcut_register_action(SHORTCUT_WINDOW_TOGGLE_FULLSCREEN, shortcut_action_toggle_fullscreen)
	shortcut_register_action(SHORTCUT_APP_QUIT, shortcut_action_app_quit)
	shortcut_register_action(SHORTCUT_HOST_RELOAD, shortcut_action_host_reload)
	shortcut_register_action(SHORTCUT_HOST_RESTART, shortcut_action_host_restart)

	shortcut_set_action_label(SHORTCUT_VIEW_ZOOM_IN, "Zoom In")
	shortcut_set_action_label(SHORTCUT_VIEW_ZOOM_OUT, "Zoom Out")
	shortcut_set_action_label(SHORTCUT_VIEW_RESET, "Reset View")
	shortcut_set_action_label(SHORTCUT_WINDOW_TOGGLE_FULLSCREEN, "Toggle Fullscreen")
	shortcut_set_action_label(SHORTCUT_APP_QUIT, "Quit")
	shortcut_set_action_label(SHORTCUT_HOST_RELOAD, "Hot Reload")
	shortcut_set_action_label(SHORTCUT_HOST_RESTART, "Hot Restart")
}

shortcut_process :: proc() {
	if state == nil || w_ctx == nil do return
	if state.shortcuts.processed do return
	state.shortcuts.processed = true

	focused := w_ctx.focused_id
	focused_kind := shortcut_focused_kind(focused)
	mouse := input_mouse_screen()
	mods := state.input.modifiers
	text_filter := shortcut_text_input_effective(focused)

	if state.shortcuts.capture.active {
		shortcut_process_capture(mods)
		shortcut_sync_gamepad_prev()
		return
	}

	// Key chords
	for scancode in 0 ..< KEY_COUNT {
		if state.shortcuts.consumed_keys[scancode] do continue
		key_state := w_ctx.keys[scancode]
		if !key_state.pressed do continue
		if shortcut_is_modifier_scancode(Scancode(scancode)) do continue

		best_i, ok := shortcut_best_key_binding(
			Scancode(scancode),
			mods,
			focused,
			focused_kind,
			text_filter,
		)
		if ok {
			if shortcut_fire_binding(best_i, mouse, focused, focused_kind, 0) {
				state.shortcuts.consumed_keys[scancode] = true
				shortcut_sequence_reset()
				continue
			}
		}

		// Feed unmatched presses into sequence matcher.
		if shortcut_process_sequence_key(
			Scancode(scancode),
			mods,
			mouse,
			focused,
			focused_kind,
			text_filter,
		) {
			state.shortcuts.consumed_keys[scancode] = true
		}
	}

	// Wheel (exact modifier match)
	if !state.shortcuts.consumed_wheel && state.input.mouse_wheel_y != 0 {
		sign: i8 = state.input.mouse_wheel_y > 0 ? 1 : -1
		best_i, ok := shortcut_best_wheel_binding(sign, mods, focused, focused_kind)
		if ok {
			if shortcut_fire_binding(
				best_i,
				mouse,
				focused,
				focused_kind,
				state.input.mouse_wheel_y,
			) {
				state.shortcuts.consumed_wheel = true
			}
		}
	}

	// Mouse button presses (exact modifier match)
	shortcut_process_mouse_buttons(mods, mouse, focused, focused_kind)

	// Gamepad edges
	for btn_i in 0 ..< GAMEPAD_BUTTON_COUNT {
		down := state.input.gamepad.buttons_down[btn_i]
		pressed := down && !state.shortcuts.gamepad_prev[btn_i]
		state.shortcuts.gamepad_prev[btn_i] = down
		if !pressed || state.shortcuts.consumed_gamepad[btn_i] do continue

		best_i, ok := shortcut_best_gamepad_binding(i32(btn_i), focused, focused_kind)
		if ok {
			if shortcut_fire_binding(best_i, mouse, focused, focused_kind, 0) {
				state.shortcuts.consumed_gamepad[btn_i] = true
			}
		}
	}
}

@(private)
shortcut_text_input_effective :: proc(focused_id: string) -> bool {
	if state.shortcuts.text_input_active do return true
	if focused_id == "" || state.shortcuts.text_input_by_id == nil do return false
	return state.shortcuts.text_input_by_id[focused_id]
}

/*
Collects bindings that share the same trigger and overlapping scopes with different action ids.
*/
shortcut_collect_conflicts :: proc(allocator := context.allocator) -> []Shortcut_Conflict {
	if state == nil do return nil
	out := make([dynamic]Shortcut_Conflict, allocator)
	n := len(state.shortcuts.bindings)
	for i in 0 ..< n {
		a := state.shortcuts.bindings[i]
		if !a.enabled do continue
		for j in i + 1 ..< n {
			b := state.shortcuts.bindings[j]
			if !b.enabled || a.id == b.id do continue
			if !shortcut_triggers_conflict(a, b) do continue
			if !shortcut_scopes_overlap(a, b) do continue
			append(
				&out,
				Shortcut_Conflict {
					id_a = a.id,
					id_b = b.id,
					trigger = a.trigger,
					chord = a.chord,
					wheel_sign = a.wheel_sign,
					sequence = a.sequence,
					sequence_len = a.sequence_len,
					gamepad_button = a.gamepad_button,
					mouse_button = a.mouse_button,
					scope = a.scope,
				},
			)
		}
	}
	return out[:]
}

@(private)
shortcut_parse_int :: proc(s: string) -> int {
	v, _ := strconv.parse_int(s)
	return v
}

@(private)
shortcut_parse_bool :: proc(s: string) -> bool {
	switch strings.to_lower(strings.trim_space(s), context.temp_allocator) {
	case "true", "1", "yes", "on":
		return true
	}
	return false
}

@(private)
shortcut_parse_scope :: proc(s: string) -> Shortcut_Scope {
	switch strings.to_lower(s, context.temp_allocator) {
	case "context":
		return .Context
	case "focused_id", "focused-id", "focusedid":
		return .Focused_Id
	case "focused_any", "focused-any", "focusedany":
		return .Focused_Any
	case "focused_kind", "focused-kind", "focusedkind":
		return .Focused_Kind
	case "global", "":
		return .Global
	}
	return .Global
}

@(private)
shortcut_update_scope :: proc(
	b: ^Shortcut_Binding,
	scope: Shortcut_Scope,
	scope_key: string,
	scope_kind: Widget_Kind,
) {
	b.scope = scope
	b.scope_kind = scope_kind
	if b.scope_key != scope_key {
		if b.scope_key != "" do delete(b.scope_key)
		b.scope_key = scope_key != "" ? strings.clone(scope_key) : ""
	}
}

@(private)
shortcut_fire_binding :: proc(
	index: int,
	mouse: Vec2,
	focused: string,
	focused_kind: Widget_Kind,
	wheel_y: f32,
) -> bool {
	b := state.shortcuts.bindings[index]
	action, has_action := state.shortcuts.actions[b.id]
	if !has_action || action == nil do return false
	event := Shortcut_Event {
		id           = b.id,
		chord        = b.chord,
		wheel_y      = wheel_y,
		mouse_screen = mouse,
		focused_id   = focused,
		focused_kind = focused_kind,
	}
	action(&event)
	if shortcut_chord_is_command(b.chord) {
		clear(&state.input.text_input)
	}
	return true
}

@(private)
shortcut_process_capture :: proc(mods: Input_Modifiers) {
	mode := state.shortcuts.capture.mode

	// Escape always cancels.
	esc := w_ctx.keys[int(Scancode.ESCAPE)]
	if esc.pressed {
		state.shortcuts.capture = {
			cancelled = true,
		}
		state.shortcuts.consumed_keys[int(Scancode.ESCAPE)] = true
		return
	}

	switch mode {
	case .Key, .Any:
		if shortcut_capture_try_key(mods) do return
		if mode == .Any {
			if shortcut_capture_try_wheel(mods) do return
			if shortcut_capture_try_mouse(mods) do return
			_ = shortcut_capture_try_gamepad()
		}
	case .Wheel:
		_ = shortcut_capture_try_wheel(mods)
	case .Mouse:
		_ = shortcut_capture_try_mouse(mods)
	case .Gamepad:
		_ = shortcut_capture_try_gamepad()
	case .Sequence:
		shortcut_capture_try_sequence(mods)
	}
}

@(private)
shortcut_capture_finish :: proc(result: Shortcut_Capture_Result) {
	state.shortcuts.capture = {
		done   = true,
		result = result,
	}
}

@(private)
shortcut_capture_try_key :: proc(mods: Input_Modifiers) -> bool {
	for scancode in 0 ..< KEY_COUNT {
		key_state := w_ctx.keys[scancode]
		if !key_state.pressed do continue
		key := Scancode(scancode)
		if shortcut_is_modifier_scancode(key) do continue
		if key == .ESCAPE do continue
		shortcut_capture_finish(
			{
				trigger = .Key,
				chord = {
					key = key,
					ctrl = mods.ctrl,
					shift = mods.shift,
					alt = mods.alt,
					super = mods.super,
				},
			},
		)
		state.shortcuts.consumed_keys[scancode] = true
		return true
	}
	return false
}

@(private)
shortcut_capture_try_wheel :: proc(mods: Input_Modifiers) -> bool {
	if state.input.mouse_wheel_y == 0 do return false
	sign: i8 = state.input.mouse_wheel_y > 0 ? 1 : -1
	shortcut_capture_finish(
		{
			trigger = .Wheel_Y,
			wheel_sign = sign,
			chord = {ctrl = mods.ctrl, shift = mods.shift, alt = mods.alt, super = mods.super},
		},
	)
	state.shortcuts.consumed_wheel = true
	return true
}

@(private)
shortcut_capture_try_mouse :: proc(mods: Input_Modifiers) -> bool {
	buttons := [3]u8{sdl.BUTTON_LEFT, sdl.BUTTON_RIGHT, sdl.BUTTON_MIDDLE}
	for button in buttons {
		if !shortcut_mouse_button_pressed(button) do continue
		shortcut_capture_finish(
			{
				trigger = .Mouse_Button,
				mouse_button = button,
				chord = {ctrl = mods.ctrl, shift = mods.shift, alt = mods.alt, super = mods.super},
			},
		)
		if int(button) < SHORTCUT_MOUSE_BUTTON_COUNT {
			state.shortcuts.consumed_mouse[button] = true
		}
		return true
	}
	return false
}

@(private)
shortcut_capture_try_gamepad :: proc() -> bool {
	for btn_i in 0 ..< GAMEPAD_BUTTON_COUNT {
		down := state.input.gamepad.buttons_down[btn_i]
		pressed := down && !state.shortcuts.gamepad_prev[btn_i]
		if !pressed do continue
		shortcut_capture_finish({trigger = .Gamepad, gamepad_button = i32(btn_i)})
		state.shortcuts.consumed_gamepad[btn_i] = true
		return true
	}
	return false
}

@(private)
shortcut_capture_try_sequence :: proc(mods: Input_Modifiers) {
	enter := w_ctx.keys[int(Scancode.RETURN)]
	if enter.pressed {
		state.shortcuts.consumed_keys[int(Scancode.RETURN)] = true
		cap := &state.shortcuts.capture
		if cap.result.sequence_len >= 2 {
			cap.result.trigger = .Sequence
			cap.result.chord = {
				ctrl  = mods.ctrl,
				shift = mods.shift,
				alt   = mods.alt,
				super = mods.super,
			}
			shortcut_capture_finish(cap.result)
		}
		return
	}

	for scancode in 0 ..< KEY_COUNT {
		key_state := w_ctx.keys[scancode]
		if !key_state.pressed do continue
		key := Scancode(scancode)
		if shortcut_is_modifier_scancode(key) do continue
		if key == .ESCAPE || key == .RETURN do continue
		cap := &state.shortcuts.capture
		if cap.result.sequence_len >= SHORTCUT_SEQUENCE_MAX do continue
		cap.result.sequence[cap.result.sequence_len] = key
		cap.result.sequence_len += 1
		state.shortcuts.consumed_keys[scancode] = true
		return
	}
}

@(private)
shortcut_sync_gamepad_prev :: proc() {
	for btn_i in 0 ..< GAMEPAD_BUTTON_COUNT {
		state.shortcuts.gamepad_prev[btn_i] = state.input.gamepad.buttons_down[btn_i]
	}
}

@(private)
shortcut_process_sequence_key :: proc(
	key: Scancode,
	mods: Input_Modifiers,
	mouse: Vec2,
	focused: string,
	focused_kind: Widget_Kind,
	text_filter: bool,
) -> bool {
	// Ignore modifier-only; sequences are non-modifier keys.
	if text_filter && !(mods.ctrl || mods.alt || mods.super) {
		shortcut_sequence_reset()
		return false
	}

	if state.shortcuts.sequence_len >= SHORTCUT_SEQUENCE_MAX {
		shortcut_sequence_reset()
	}
	state.shortcuts.sequence_buf[state.shortcuts.sequence_len] = key
	state.shortcuts.sequence_len += 1
	state.shortcuts.sequence_idle_frames = 0

	best_i, complete, ok := shortcut_best_sequence_binding(
		mods,
		focused,
		focused_kind,
		text_filter,
	)
	if !ok {
		// Restart sequence with this key alone if it could start one.
		shortcut_sequence_reset()
		state.shortcuts.sequence_buf[0] = key
		state.shortcuts.sequence_len = 1
		best_i, complete, ok = shortcut_best_sequence_binding(
			mods,
			focused,
			focused_kind,
			text_filter,
		)
		if !ok {
			shortcut_sequence_reset()
			return false
		}
	}
	if !complete do return false
	fired := shortcut_fire_binding(best_i, mouse, focused, focused_kind, 0)
	shortcut_sequence_reset()
	return fired
}

@(private)
shortcut_sequence_reset :: proc() {
	state.shortcuts.sequence_len = 0
	state.shortcuts.sequence_idle_frames = 0
	state.shortcuts.sequence_buf = {}
}

@(private)
shortcut_best_sequence_binding :: proc(
	mods: Input_Modifiers,
	focused: string,
	focused_kind: Widget_Kind,
	text_filter: bool,
) -> (
	index: int,
	complete: bool,
	ok: bool,
) {
	best_i := -1
	best_pri: i32
	best_rank: i32
	found := false
	is_complete := false
	cur_len := state.shortcuts.sequence_len

	for b, i in state.shortcuts.bindings {
		if !b.enabled || b.trigger != .Sequence do continue
		if b.sequence_len < cur_len do continue
		if !shortcut_sequence_prefix(
			b.sequence,
			b.sequence_len,
			state.shortcuts.sequence_buf,
			cur_len,
		) {
			continue
		}
		if cur_len == b.sequence_len {
			if !shortcut_modifiers_match(b.chord, mods) do continue
		}
		if text_filter && cur_len == b.sequence_len && !shortcut_chord_is_command(b.chord) {
			continue
		}
		if !shortcut_scope_matches(b, focused, focused_kind) do continue

		rank := shortcut_scope_rank(b.scope)
		done := cur_len == b.sequence_len
		if shortcut_better_candidate(b.priority, rank, best_pri, best_rank, found) {
			best_i = i
			best_pri = b.priority
			best_rank = rank
			found = true
			is_complete = done
		} else if found && done && !is_complete {
			// Prefer completing a sequence over keeping an incomplete prefix of equal priority.
			if b.priority == best_pri && rank == best_rank {
				best_i = i
				is_complete = true
			}
		}
	}
	return best_i, is_complete, found
}

@(private)
shortcut_focused_kind :: proc(focused_id: string) -> Widget_Kind {
	if state == nil || focused_id == "" do return .RECT
	if state.shortcuts.kind_by_id != nil {
		if kind, ok := state.shortcuts.kind_by_id[focused_id]; ok {
			return kind
		}
	}
	return .RECT
}

@(private)
shortcut_popover_active :: proc() -> bool {
	if state == nil do return false
	return len(state.ui.layout.paint_list_popover) > 0
}

@(private)
shortcut_free_binding :: proc(b: ^Shortcut_Binding) {
	if b.id != "" do delete(b.id)
	if b.scope_key != "" do delete(b.scope_key)
	b^ = {}
}

@(private)
shortcut_chord_equal :: proc(a, b: Shortcut_Chord) -> bool {
	return(
		a.key == b.key &&
		a.ctrl == b.ctrl &&
		a.shift == b.shift &&
		a.alt == b.alt &&
		a.super == b.super \
	)
}

@(private)
shortcut_chord_mods_equal :: proc(a, b: Shortcut_Chord) -> bool {
	return a.ctrl == b.ctrl && a.shift == b.shift && a.alt == b.alt && a.super == b.super
}

@(private)
shortcut_chord_is_command :: proc(chord: Shortcut_Chord) -> bool {
	return chord.ctrl || chord.alt || chord.super
}

@(private)
shortcut_modifiers_match :: proc(chord: Shortcut_Chord, mods: Input_Modifiers) -> bool {
	return(
		chord.ctrl == mods.ctrl &&
		chord.shift == mods.shift &&
		chord.alt == mods.alt &&
		chord.super == mods.super \
	)
}

@(private)
shortcut_sequence_equal :: proc(a, b: [SHORTCUT_SEQUENCE_MAX]Scancode, len: u8) -> bool {
	for i in 0 ..< int(len) {
		if a[i] != b[i] do return false
	}
	return true
}

@(private)
shortcut_sequence_prefix :: proc(
	full: [SHORTCUT_SEQUENCE_MAX]Scancode,
	full_len: u8,
	prefix: [SHORTCUT_SEQUENCE_MAX]Scancode,
	prefix_len: u8,
) -> bool {
	if prefix_len > full_len do return false
	for i in 0 ..< int(prefix_len) {
		if full[i] != prefix[i] do return false
	}
	return true
}

@(private)
shortcut_is_modifier_scancode :: proc(key: Scancode) -> bool {
	#partial switch key {
	case .LCTRL, .RCTRL, .LSHIFT, .RSHIFT, .LALT, .RALT, .LGUI, .RGUI:
		return true
	}
	return false
}

@(private)
shortcut_scope_matches :: proc(
	b: Shortcut_Binding,
	focused_id: string,
	focused_kind: Widget_Kind,
) -> bool {
	switch b.scope {
	case .Global:
		return true
	case .Context:
		if b.scope_key == "" do return false
		if b.scope_key == SHORTCUT_CONTEXT_POPOVER && shortcut_popover_active() {
			return true
		}
		for ctx in state.shortcuts.contexts {
			if ctx == b.scope_key do return true
		}
		return false
	case .Focused_Id:
		return focused_id != "" && focused_id == b.scope_key
	case .Focused_Any:
		return focused_id != ""
	case .Focused_Kind:
		return focused_id != "" && focused_kind == b.scope_kind
	}
	return false
}

@(private)
shortcut_scope_rank :: proc(scope: Shortcut_Scope) -> i32 {
	switch scope {
	case .Context:
		return 4
	case .Focused_Id:
		return 3
	case .Focused_Kind:
		return 2
	case .Focused_Any:
		return 1
	case .Global:
		return 0
	}
	return 0
}

@(private)
shortcut_better_candidate :: proc(
	priority, rank: i32,
	best_priority, best_rank: i32,
	best_valid: bool,
) -> bool {
	if !best_valid do return true
	if priority != best_priority do return priority > best_priority
	return rank > best_rank
}

@(private)
shortcut_triggers_conflict :: proc(a, b: Shortcut_Binding) -> bool {
	if a.trigger != b.trigger do return false
	switch a.trigger {
	case .Key:
		return shortcut_chord_equal(a.chord, b.chord)
	case .Wheel_Y:
		return a.wheel_sign == b.wheel_sign && shortcut_chord_mods_equal(a.chord, b.chord)
	case .Mouse_Button:
		return a.mouse_button == b.mouse_button && shortcut_chord_mods_equal(a.chord, b.chord)
	case .Sequence:
		return(
			a.sequence_len == b.sequence_len &&
			shortcut_sequence_equal(a.sequence, b.sequence, a.sequence_len) &&
			shortcut_chord_mods_equal(a.chord, b.chord) \
		)
	case .Gamepad:
		return a.gamepad_button == b.gamepad_button
	}
	return false
}

/*
Returns whether two bindings can both be eligible in the same input situation.
*/
@(private)
shortcut_scopes_overlap :: proc(a, b: Shortcut_Binding) -> bool {
	if a.scope == .Global || b.scope == .Global do return true
	if a.scope == b.scope {
		switch a.scope {
		case .Context, .Focused_Id:
			return a.scope_key == b.scope_key
		case .Focused_Kind:
			return a.scope_kind == b.scope_kind
		case .Focused_Any, .Global:
			return true
		}
	}
	// Focused_Any overlaps any focused scope.
	if a.scope == .Focused_Any || b.scope == .Focused_Any {
		return(
			a.scope == .Focused_Id ||
			a.scope == .Focused_Kind ||
			a.scope == .Focused_Any ||
			b.scope == .Focused_Id ||
			b.scope == .Focused_Kind ||
			b.scope == .Focused_Any \
		)
	}
	// Focused_Id vs Focused_Kind: overlap when that id could have that kind (conservative).
	if (a.scope == .Focused_Id && b.scope == .Focused_Kind) ||
	   (b.scope == .Focused_Id && a.scope == .Focused_Kind) {
		return true
	}
	return false
}

@(private)
shortcut_best_key_binding :: proc(
	key: Scancode,
	mods: Input_Modifiers,
	focused_id: string,
	focused_kind: Widget_Kind,
	text_filter: bool,
) -> (
	index: int,
	ok: bool,
) {
	best_i := -1
	best_pri: i32
	best_rank: i32
	found := false

	for b, i in state.shortcuts.bindings {
		if !b.enabled || b.trigger != .Key do continue
		if b.chord.key != key do continue
		if !shortcut_modifiers_match(b.chord, mods) do continue
		if text_filter && !shortcut_chord_is_command(b.chord) do continue
		if !shortcut_scope_matches(b, focused_id, focused_kind) do continue

		rank := shortcut_scope_rank(b.scope)
		if shortcut_better_candidate(b.priority, rank, best_pri, best_rank, found) {
			best_i = i
			best_pri = b.priority
			best_rank = rank
			found = true
		}
	}
	return best_i, found
}

@(private)
shortcut_best_wheel_binding :: proc(
	sign: i8,
	mods: Input_Modifiers,
	focused_id: string,
	focused_kind: Widget_Kind,
) -> (
	index: int,
	ok: bool,
) {
	best_i := -1
	best_pri: i32
	best_rank: i32
	found := false

	for b, i in state.shortcuts.bindings {
		if !b.enabled || b.trigger != .Wheel_Y do continue
		if b.wheel_sign != 0 && b.wheel_sign != sign do continue
		if !shortcut_modifiers_match(b.chord, mods) do continue
		if !shortcut_scope_matches(b, focused_id, focused_kind) do continue

		rank := shortcut_scope_rank(b.scope)
		if shortcut_better_candidate(b.priority, rank, best_pri, best_rank, found) {
			best_i = i
			best_pri = b.priority
			best_rank = rank
			found = true
		}
	}
	return best_i, found
}

@(private)
shortcut_process_mouse_buttons :: proc(
	mods: Input_Modifiers,
	mouse: Vec2,
	focused: string,
	focused_kind: Widget_Kind,
) {
	buttons := [3]u8{sdl.BUTTON_LEFT, sdl.BUTTON_RIGHT, sdl.BUTTON_MIDDLE}
	for button in buttons {
		if int(button) >= SHORTCUT_MOUSE_BUTTON_COUNT do continue
		if state.shortcuts.consumed_mouse[button] do continue
		if !shortcut_mouse_button_pressed(button) do continue

		best_i, ok := shortcut_best_mouse_binding(button, mods, focused, focused_kind)
		if !ok do continue
		if shortcut_fire_binding(best_i, mouse, focused, focused_kind, 0) {
			state.shortcuts.consumed_mouse[button] = true
		}
	}
}

@(private)
shortcut_mouse_button_pressed :: proc(button: u8) -> bool {
	switch button {
	case sdl.BUTTON_LEFT:
		return w_ctx.left_mouse.pressed
	case sdl.BUTTON_RIGHT:
		return w_ctx.right_mouse.pressed
	case sdl.BUTTON_MIDDLE:
		return w_ctx.middle_mouse.pressed
	}
	return false
}

@(private)
shortcut_best_mouse_binding :: proc(
	button: u8,
	mods: Input_Modifiers,
	focused_id: string,
	focused_kind: Widget_Kind,
) -> (
	index: int,
	ok: bool,
) {
	best_i := -1
	best_pri: i32
	best_rank: i32
	found := false

	for b, i in state.shortcuts.bindings {
		if !b.enabled || b.trigger != .Mouse_Button do continue
		if b.mouse_button != button do continue
		if !shortcut_modifiers_match(b.chord, mods) do continue
		if !shortcut_scope_matches(b, focused_id, focused_kind) do continue

		rank := shortcut_scope_rank(b.scope)
		if shortcut_better_candidate(b.priority, rank, best_pri, best_rank, found) {
			best_i = i
			best_pri = b.priority
			best_rank = rank
			found = true
		}
	}
	return best_i, found
}

@(private)
shortcut_best_gamepad_binding :: proc(
	button: i32,
	focused_id: string,
	focused_kind: Widget_Kind,
) -> (
	index: int,
	ok: bool,
) {
	best_i := -1
	best_pri: i32
	best_rank: i32
	found := false

	for b, i in state.shortcuts.bindings {
		if !b.enabled || b.trigger != .Gamepad do continue
		if b.gamepad_button != button do continue
		if !shortcut_scope_matches(b, focused_id, focused_kind) do continue

		rank := shortcut_scope_rank(b.scope)
		if shortcut_better_candidate(b.priority, rank, best_pri, best_rank, found) {
			best_i = i
			best_pri = b.priority
			best_rank = rank
			found = true
		}
	}
	return best_i, found
}

@(private)
shortcut_action_view_zoom_in :: proc(event: ^Shortcut_Event) {
	view_zoom_in_screen(event.mouse_screen)
}

@(private)
shortcut_action_view_zoom_out :: proc(event: ^Shortcut_Event) {
	view_zoom_out_screen(event.mouse_screen)
}

@(private)
shortcut_action_view_reset :: proc(event: ^Shortcut_Event) {
	_ = event
	view_reset()
}

@(private)
shortcut_action_toggle_fullscreen :: proc(event: ^Shortcut_Event) {
	_ = event
	toggle_fullscreen()
}

@(private)
shortcut_action_app_quit :: proc(event: ^Shortcut_Event) {
	_ = event
	if state != nil {
		state.running = false
	}
}

@(private)
shortcut_action_host_reload :: proc(event: ^Shortcut_Event) {
	_ = event
	if state != nil {
		state.force_reload = true
	}
}

@(private)
shortcut_action_host_restart :: proc(event: ^Shortcut_Event) {
	_ = event
	if state != nil {
		state.force_restart = true
	}
}

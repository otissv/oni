package oni

import "core:fmt"
import "core:os"
import "core:strings"
import sdl "vendor:sdl3"

/*
Returns the number of bindings in the table.
*/
shortcut_binding_count :: proc() -> int {
	if state == nil do return 0
	return len(state.shortcuts.bindings)
}

/*
Returns a shallow copy of the binding at index.

String fields borrow engine-owned storage; valid until the binding is mutated or cleared.
*/
shortcut_binding_get :: proc(index: int) -> (binding: Shortcut_Binding, ok: bool) {
	if state == nil do return {}, false
	if index < 0 || index >= len(state.shortcuts.bindings) do return {}, false
	return state.shortcuts.bindings[index], true
}

/*
Allocates a snapshot of all bindings with cloned string fields.

Caller owns the slice and must free each binding's id/scope_key then the slice.
*/
shortcut_list_bindings :: proc(allocator := context.allocator) -> []Shortcut_Binding {
	if state == nil do return nil
	n := len(state.shortcuts.bindings)
	out := make([]Shortcut_Binding, n, allocator)
	for b, i in state.shortcuts.bindings {
		out[i] = b
		out[i].id = strings.clone(b.id, allocator)
		out[i].scope_key = b.scope_key != "" ? strings.clone(b.scope_key, allocator) : ""
	}
	return out
}

/*
Frees a slice from Shortcut_List_Bindings.
*/
shortcut_free_binding_list :: proc(list: []Shortcut_Binding, allocator := context.allocator) {
	for &b in list {
		if b.id != "" do delete(b.id, allocator)
		if b.scope_key != "" do delete(b.scope_key, allocator)
	}
	delete(list, allocator)
}

/*
Formats a scancode for display (e.g. "S", "F5", "Left Ctrl").
*/
shortcut_format_scancode :: proc(key: Scancode, allocator := context.allocator) -> string {
	name := string(sdl.GetScancodeName(sdl.Scancode(key)))
	if len(name) > 0 {
		return strings.clone(name, allocator)
	}
	return fmt.aprintf("Scancode(%d)", int(key), allocator = allocator)
}

/*
Formats a chord for display (e.g. "CTRL+SHIFT+S").
*/
shortcut_format_chord :: proc(chord: Shortcut_Chord, allocator := context.allocator) -> string {
	b := strings.builder_make(allocator)
	shortcut_write_mods(&b, chord)
	if chord.key != .UNKNOWN {
		strings.write_string(&b, shortcut_key_token(chord.key, context.temp_allocator))
	} else {
		s := strings.to_string(b)
		if len(s) > 0 && s[len(s) - 1] == '+' {
			return strings.clone(s[:len(s) - 1], allocator)
		}
		if len(s) == 0 {
			return strings.clone("(none)", allocator)
		}
		return s
	}
	return strings.to_string(b)
}

/*
Formats a binding trigger for a bindings-table row (UPPER_SNAKE tokens).
*/
shortcut_format_binding :: proc(binding: Shortcut_Binding, allocator := context.allocator) -> string {
	return shortcut_format_trigger_token(binding, allocator)
}

/*
Writes the bindings table to a UTF-8 text file.
*/
shortcut_save_bindings :: proc(path: string) -> bool {
	if state == nil || path == "" do return false
	data := shortcut_export_bindings(context.temp_allocator)
	return os.write_entire_file(path, transmute([]byte)data) == nil
}

/*
Loads bindings from a UTF-8 text file previously written by Shortcut_Save_Bindings.

Missing files return false without mutating bindings.
*/
shortcut_load_bindings :: proc(path: string, replace_user := true) -> bool {
	err := shortcut_load_bindings_ex(path, replace_user)
	return err.ok
}

shortcut_load_bindings_ex :: proc(path: string, replace_user := true) -> Shortcut_Import_Error {
	if state == nil || path == "" do return {ok = false, line = 0}
	data, read_err := os.read_entire_file(path, context.temp_allocator)
	if read_err != nil do return {ok = false, line = 0}
	return shortcut_import_bindings_ex(string(data), replace_user)
}

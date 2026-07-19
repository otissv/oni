package oni

import "base:runtime"
import "core:fmt"
import "core:hash"
import "core:mem"
import "core:path/filepath"
import "core:strings"


Error_Level :: enum {
	ERROR,
	WARN,
}

Error_Entry :: struct {
	key:       u64,
	level:     Error_Level,
	message:   string,
	file:      string,
	line:      i32,
	procedure: string,
	expanded:  bool,
	dismissed: bool,
}

Error_State :: struct {
	entries:       [dynamic]Error_Entry,
	banner_height: f32,
}

@(private)
error_level_label :: proc(level: Error_Level) -> string {
	switch level {
	case .ERROR:
		return "ERROR"
	case .WARN:
		return "WARN"
	}

	return "ERROR"
}

@(private)
error_entry_key :: proc(
	level: Error_Level,
	message: string,
	file: string,
	line: i32,
	procedure: string,
) -> u64 {
	h: u64 = 14695981039346656037
	h ~= u64(level)
	h *= 1099511628211
	h ~= u64(hash.crc32(transmute([]u8)message))
	h *= 1099511628211
	h ~= u64(hash.crc32(transmute([]u8)file))
	h *= 1099511628211
	h ~= u64(line)
	h *= 1099511628211
	h ~= u64(hash.crc32(transmute([]u8)procedure))

	return h
}

error_init :: proc() {
	if state == nil do return

	if state.errors.entries == nil {
		state.errors.entries = make([dynamic]Error_Entry)
	}
}

error_shutdown :: proc() {
	if state == nil || state.errors.entries == nil do return

	for &entry in state.errors.entries {
		delete(entry.message)
		delete(entry.file)
		delete(entry.procedure)
	}

	delete(state.errors.entries)
	state.errors.entries = nil
	state.errors.banner_height = 0
}

error_format_log_line :: proc(entry: Error_Entry) -> string {
	return fmt.tprintf(
		"[%s] [%s:%d:%s] %s",
		error_level_label(entry.level),
		entry.file,
		entry.line,
		entry.procedure,
		entry.message,
	)
}

error_push :: proc(level: Error_Level, message: string, loc: runtime.Source_Code_Location) {
	if state == nil do return

	error_init()

	file := filepath.base(loc.file_path)
	key := error_entry_key(level, message, file, loc.line, loc.procedure)

	for &entry in state.errors.entries {
		if entry.key != key do continue

		entry.dismissed = false
		entry.level = level

		return
	}

	append(
		&state.errors.entries,
		Error_Entry {
			key = key,
			level = level,
			message = strings.clone(message),
			file = strings.clone(file),
			line = loc.line,
			procedure = strings.clone(loc.procedure),
		},
	)
}

/*
Reports an app-visible error: logs to stderr and stores it for the error banner.
*/
error_report :: proc(message: string, loc := #caller_location) {
	write_log("ERROR", message, loc)
	error_push(.ERROR, message, loc)
}

/*
Reports a formatted app-visible error: logs to stderr and stores it for the error banner.
*/
error_reportf :: proc(format: string, args: ..any, loc := #caller_location) {
	msg := fmt.tprintf(format, ..args)
	error_report(msg, loc)
}

/*
Reports an app-visible warning: logs to stderr and stores it for the error banner.
*/
error_warn :: proc(message: string, loc := #caller_location) {
	write_log("WARN", message, loc)
	error_push(.WARN, message, loc)
}

/*
Reports a formatted app-visible warning: logs to stderr and stores it for the error banner.
*/
error_warnf :: proc(format: string, args: ..any, loc := #caller_location) {
	msg := fmt.tprintf(format, ..args)
	error_warn(msg, loc)
}

error_active_count :: proc() -> int {
	if state == nil || state.errors.entries == nil do return 0

	count := 0

	for entry in state.errors.entries {
		if !entry.dismissed do count += 1
	}

	return count
}

error_banner_height :: proc() -> f32 {
	if state == nil do return 0

	return state.errors.banner_height
}

error_set_banner_height :: proc(height: f32) {
	if state == nil do return

	state.errors.banner_height = height
}

error_toggle_expanded :: proc(key: u64) {
	if state == nil || state.errors.entries == nil do return

	for &entry in state.errors.entries {
		if entry.key == key {
			entry.expanded = !entry.expanded

			return
		}
	}
}

error_dismiss :: proc(key: u64) {
	if state == nil || state.errors.entries == nil do return

	for &entry in state.errors.entries {
		if entry.key == key {
			entry.dismissed = true

			return
		}
	}
}

error_dismiss_all :: proc() {
	if state == nil || state.errors.entries == nil do return

	for &entry in state.errors.entries {
		entry.dismissed = true
	}
}

error_active_entries :: proc(allocator: mem.Allocator) -> []Error_Entry {
	if state == nil || state.errors.entries == nil do return nil

	active := make([dynamic]Error_Entry, allocator)

	for entry in state.errors.entries {
		if entry.dismissed do continue

		append(&active, entry)
	}

	return active[:]
}

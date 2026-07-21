package oni

import "base:runtime"
import "core:fmt"
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
	summary:   string,
	log_line:  string,
	expanded:  bool,
}

Error_State :: struct {
	entries:      [dynamic]Error_Entry,
	index:        map[u64]int,
	active_count: int,
	arena:        mem.Arena,
	arena_backing: [dynamic]byte,
}

ERROR_ARENA_INITIAL :: 4096
ERROR_ARENA_REPACK_MIN_WASTE :: 2048

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
error_hash_mix :: proc(h: ^u64, data: []u8) {
	for b in data {
		h^ ~= u64(b)
		h^ *= 1099511628211
	}
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
	error_hash_mix(&h, transmute([]u8)message)
	error_hash_mix(&h, transmute([]u8)file)
	h ~= u64(line)
	h *= 1099511628211
	error_hash_mix(&h, transmute([]u8)procedure)

	return h
}

@(private)
error_arena_allocator :: proc() -> mem.Allocator {
	return mem.arena_allocator(&state.errors.arena)
}

@(private)
error_clone_to_arena :: proc(value: string) -> string {
	return strings.clone(value, error_arena_allocator())
}

@(private)
error_build_summary :: proc(level: Error_Level, message: string) -> string {
	formatted := fmt.tprintf("[%s] %s", error_level_label(level), message)

	return error_clone_to_arena(formatted)
}

@(private)
error_build_log_line :: proc(
	level: Error_Level,
	file: string,
	line: i32,
	procedure: string,
	message: string,
) -> string {
	formatted := fmt.tprintf(
		"[%s] [%s:%d:%s] %s",
		error_level_label(level),
		file,
		line,
		procedure,
		message,
	)

	return error_clone_to_arena(formatted)
}

@(private)
error_arena_reset :: proc() {
	errors := &state.errors

	mem.arena_free_all(&errors.arena)
}

@(private)
error_arena_destroy :: proc() {
	errors := &state.errors

	delete(errors.arena_backing)
	errors.arena_backing = nil
	errors.arena = {}
}

@(private)
error_repack_arena :: proc() {
	errors := &state.errors

	if len(errors.entries) == 0 {
		error_arena_reset()

		return
	}

	n := len(errors.entries)
	temp_messages := make([]string, n, context.temp_allocator)
	temp_files := make([]string, n, context.temp_allocator)
	temp_procedures := make([]string, n, context.temp_allocator)
	temp_summaries := make([]string, n, context.temp_allocator)
	temp_log_lines := make([]string, n, context.temp_allocator)

	for entry, i in errors.entries {
		temp_messages[i] = strings.clone(entry.message, context.temp_allocator)
		temp_files[i] = strings.clone(entry.file, context.temp_allocator)
		temp_procedures[i] = strings.clone(entry.procedure, context.temp_allocator)
		temp_summaries[i] = strings.clone(entry.summary, context.temp_allocator)
		temp_log_lines[i] = strings.clone(entry.log_line, context.temp_allocator)
	}

	error_arena_reset()
	alloc := error_arena_allocator()

	for &entry, i in errors.entries {
		entry.message = strings.clone(temp_messages[i], alloc)
		entry.file = strings.clone(temp_files[i], alloc)
		entry.procedure = strings.clone(temp_procedures[i], alloc)
		entry.summary = strings.clone(temp_summaries[i], alloc)
		entry.log_line = strings.clone(temp_log_lines[i], alloc)
	}
}

@(private)
error_maybe_repack_arena :: proc() {
	errors := &state.errors

	if len(errors.entries) == 0 {
		error_arena_reset()

		return
	}

	used := errors.arena.peak_used
	remaining := len(errors.entries) * 256

	if used > remaining && used - remaining >= ERROR_ARENA_REPACK_MIN_WASTE {
		error_repack_arena()
	}
}

@(private)
error_remove_at :: proc(index: int) {
	errors := &state.errors
	entry := errors.entries[index]

	delete_key(&errors.index, entry.key)

	last := len(errors.entries) - 1

	if index != last {
		errors.entries[index] = errors.entries[last]
		errors.index[errors.entries[index].key] = index
	}

	pop(&errors.entries)
	errors.active_count -= 1
}

error_init :: proc() {
	if state == nil do return

	errors := &state.errors

	if errors.entries != nil do return

	errors.entries = make([dynamic]Error_Entry)
	errors.index = make(map[u64]int)
	errors.active_count = 0

	if len(errors.arena_backing) == 0 {
		resize(&errors.arena_backing, ERROR_ARENA_INITIAL)
	}

	mem.arena_init(&errors.arena, errors.arena_backing[:])
}

error_shutdown :: proc() {
	if state == nil || state.errors.entries == nil do return

	errors := &state.errors

	clear(&errors.index)
	delete(errors.index)
	errors.index = nil

	delete(errors.entries)
	errors.entries = nil
	errors.active_count = 0

	error_arena_destroy()
}

error_format_log_line :: proc(entry: Error_Entry) -> string {
	return entry.log_line
}

error_push :: proc(level: Error_Level, message: string, loc: runtime.Source_Code_Location) {
	if state == nil do return

	error_init()

	file := filepath.base(loc.file_path)
	key := error_entry_key(level, message, file, loc.line, loc.procedure)

	if index, found := state.errors.index[key]; found {
		entry := &state.errors.entries[index]
		entry.level = level

		return
	}

	message_copy := error_clone_to_arena(message)
	file_copy := error_clone_to_arena(file)
	procedure_copy := error_clone_to_arena(loc.procedure)
	summary := error_build_summary(level, message_copy)
	log_line := error_build_log_line(level, file_copy, loc.line, procedure_copy, message_copy)

	index := len(state.errors.entries)

	append(
		&state.errors.entries,
		Error_Entry {
			key = key,
			level = level,
			message = message_copy,
			file = file_copy,
			line = loc.line,
			procedure = procedure_copy,
			summary = summary,
			log_line = log_line,
		},
	)
	state.errors.index[key] = index
	state.errors.active_count += 1
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

	return state.errors.active_count
}

error_entries :: proc() -> []Error_Entry {
	if state == nil || state.errors.entries == nil do return nil

	return state.errors.entries[:]
}

error_toggle_expanded :: proc(key: u64) {
	if state == nil || state.errors.entries == nil do return

	if index, found := state.errors.index[key]; found {
		state.errors.entries[index].expanded = !state.errors.entries[index].expanded
	}
}

error_dismiss :: proc(key: u64) {
	if state == nil || state.errors.entries == nil do return

	if index, found := state.errors.index[key]; found {
		error_remove_at(index)
		error_maybe_repack_arena()
	}
}

error_dismiss_all :: proc() {
	if state == nil || state.errors.entries == nil do return

	clear(&state.errors.index)
	clear(&state.errors.entries)
	state.errors.active_count = 0
	error_arena_reset()
}

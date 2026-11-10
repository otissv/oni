package oni

import "core:c"
import "core:mem"
import "core:strings"
import "core:sync"
import "core:unicode/utf8"
import sdl "vendor:sdl3"

FILE_DIALOG_MAX_FILTERS :: 128
FILE_DIALOG_MAX_SELECTIONS :: 1024
FILE_DIALOG_MAX_PATH_BYTES :: 128 * 1024
FILE_DIALOG_MAX_RESULT_BYTES :: 16 * 1024 * 1024

File_Dialog_Filter :: struct {
	name:    string,
	pattern: string,
}

/*
Native picker hints. Patterns are semicolon-separated extensions ("png;jpg")
or "*". Folder pickers reject filters; save pickers reject allow_many.
Location may be a default filename for file dialogs, or a directory ending in
a separator. Native backends may ignore presentation hints and filters.
*/
File_Dialog_Options :: struct {
	title:        string,
	location:     string,
	accept_label: string,
	cancel_label: string,
	filters:      []File_Dialog_Filter,
	allow_many:   bool,
}

File_Dialog_Status :: enum { Cancelled, Selected, Failed }
File_Dialog_Error :: enum {
	None,
	Invalid_Options,
	Not_Initialized,
	Wrong_Thread,
	Busy,
	Backend,
	Invalid_Result,
	Allocation_Failed,
	Limit_Exceeded,
}

/*
Owned result; do not shallow-copy ownership. Destroy with Destroy_File_Dialog_Result.
Paths are native UTF-8 selections, including content:// URIs on Android. No file
is opened or written. selected_filter is zero-based, or -1 when unavailable.
Error text is owned and best-effort; error_code remains available if allocation
fails. The stored allocator must remain valid until destruction.
*/
File_Dialog_Result :: struct {
	status:          File_Dialog_Status,
	paths:           []string,
	selected_filter: int,
	error_code:      File_Dialog_Error,
	error:           string,
	allocator:       mem.Allocator,
}

/*
Shows the native modal file picker on the SDL main thread. The call services
SDL's event pump while waiting; app tick, draw and hot reload resume on return.
Use from input handlers, never from Layout. Results use allocator (heap by
default), and always need destruction. Native filters are hints, not validation.
*/
open_file_dialog :: proc(options: File_Dialog_Options = {}, allocator := context.allocator) -> File_Dialog_Result {
	return file_dialog_run(.OPENFILE, options, allocator)
}

/*
Shows a native save-path picker. Selects a path only: the app handles writing,
extension policy and safe replacement. The same modal/ownership contract as
Open_File_Dialog applies.
*/
save_file_dialog :: proc(options: File_Dialog_Options = {}, allocator := context.allocator) -> File_Dialog_Result {
	return file_dialog_run(.SAVEFILE, options, allocator)
}

/*
Shows a native folder picker, optionally allowing multiple folders. The same
modal/ownership contract as Open_File_Dialog applies.
*/
pick_folder :: proc(options: File_Dialog_Options = {}, allocator := context.allocator) -> File_Dialog_Result {
	return file_dialog_run(.OPENFOLDER, options, allocator)
}

/*
Releases every owned path, path array and error string with the origin allocator.
Safe for zero, cancelled, failed and already-destroyed results.
*/
destroy_file_dialog_result :: proc(result: ^File_Dialog_Result) {
	if result == nil do return
	for path in result.paths {
		if len(path) > 0 do delete(path, result.allocator)
	}
	if len(result.paths) > 0 do delete(result.paths, result.allocator)
	if len(result.error) > 0 do delete(result.error, result.allocator)
	result^ = {}
}

@(private)
file_dialog_active: bool

@(private)
file_dialog_failure :: proc(code: File_Dialog_Error, message: string, allocator: mem.Allocator) -> File_Dialog_Result {
	result := File_Dialog_Result{status = .Failed, error_code = code, selected_filter = -1, allocator = allocator}
	if len(message) > 0 {
		text, err := strings.clone(message, allocator)
		if err == nil && len(text) == len(message) {
			result.error = text
		} else {
			result.error_code = .Allocation_Failed
		}
	}
	return result
}

@(private)
file_dialog_valid_text :: proc(text: string, limit: int) -> bool {
	if len(text) > limit || !utf8.valid_string(text) do return false
	for byte in text {
		if byte == 0 do return false
	}
	return true
}

@(private)
file_dialog_validate :: proc(kind: sdl.FileDialogType, options: File_Dialog_Options) -> string {
	if kind != .OPENFILE && kind != .SAVEFILE && kind != .OPENFOLDER do return "Invalid dialog kind"
	if kind == .SAVEFILE && options.allow_many do return "Save dialogs select one path"
	if kind == .OPENFOLDER && len(options.filters) > 0 do return "Folder pickers do not accept file filters"
	if len(options.filters) > FILE_DIALOG_MAX_FILTERS do return "Too many file filters"
	if !file_dialog_valid_text(options.location, FILE_DIALOG_MAX_PATH_BYTES) do return "Invalid default location"
	for text in ([]string{options.title, options.accept_label, options.cancel_label}) {
		if !file_dialog_valid_text(text, 16 * 1024) do return "Invalid dialog label"
	}
	for filter in options.filters {
		if filter.name == "" || !file_dialog_valid_text(filter.name, 16 * 1024) do return "Invalid filter name"
		if filter.pattern == "*" do continue
		if len(filter.pattern) == 0 || len(filter.pattern) > 16 * 1024 do return "Invalid filter pattern"
		segment_length := 0
		for byte in filter.pattern {
			if byte == ';' {
				if segment_length == 0 do return "Empty filter extension"
				segment_length = 0
				continue
			}
			if !((byte >= 'a' && byte <= 'z') || (byte >= 'A' && byte <= 'Z') ||
			     (byte >= '0' && byte <= '9') || byte == '-' || byte == '_' || byte == '.') {
				return "Invalid character in filter extension"
			}
			segment_length += 1
		}
		if segment_length == 0 do return "Empty filter extension"
	}
	return ""
}

// Only SDL allocations cross the foreign callback boundary. The caller's
// allocator (which may be thread-affine) is used exclusively on the main thread.
@(private)
File_Dialog_Completion :: struct {
	done:            bool,
	paths:           [FILE_DIALOG_MAX_SELECTIONS]cstring,
	count:           int,
	selected_filter: int,
	status:          File_Dialog_Status,
	error_code:      File_Dialog_Error,
	error:           cstring,
}

@(private)
file_dialog_callback :: proc "c" (userdata: rawptr, paths: [^]cstring, filter: c.int) {
	completion := cast(^File_Dialog_Completion)userdata
	completion.selected_filter = int(filter)
	defer sync.atomic_store(&completion.done, true)
	if paths == nil {
		completion.status = .Failed
		completion.error_code = .Backend
		completion.error = cstring(sdl.strdup(sdl.GetError()))
		if completion.error == nil do completion.error_code = .Allocation_Failed
		return
	}
	// Native backends can represent an empty selection as one empty string.
	if paths[0] == nil || (string(paths[0]) == "" && paths[1] == nil) do return
	total_bytes := 0
	for index := 0; paths[index] != nil; index += 1 {
		path := string(paths[index])
		if index >= FILE_DIALOG_MAX_SELECTIONS || len(path) > FILE_DIALOG_MAX_PATH_BYTES ||
		   total_bytes + len(path) > FILE_DIALOG_MAX_RESULT_BYTES {
			completion.status = .Failed
			completion.error_code = .Limit_Exceeded
			return
		}
		if len(path) == 0 || !utf8.valid_string(path) {
			completion.status = .Failed
			completion.error_code = .Invalid_Result
			return
		}
		copy := cstring(sdl.strdup(paths[index]))
		if copy == nil {
			completion.status = .Failed
			completion.error_code = .Allocation_Failed
			return
		}
		completion.paths[index] = copy
		completion.count += 1
		total_bytes += len(path)
	}
	completion.status = .Selected
}

@(private)
file_dialog_free_completion :: proc(completion: ^File_Dialog_Completion) {
	for i in 0 ..< completion.count {
		sdl.free(rawptr(completion.paths[i]))
	}
	sdl.free(rawptr(completion.error))
	completion^ = {}
}

@(private)
file_dialog_native_show :: proc(kind: sdl.FileDialogType, callback: sdl.DialogFileCallback, userdata: rawptr, props: sdl.PropertiesID) {
	sdl.ShowFileDialogWithProperties(kind, callback, userdata, props)
}

@(private)
file_dialog_native_pump :: proc() {
	sdl.PumpEvents()
	sdl.Delay(5)
}

@(private)
file_dialog_resume_input :: proc() {
	sdl.PumpEvents()
	if state != nil {
		input_clear_keyboard_mouse()
		state.input.mouse_wheel_x = 0
		state.input.mouse_wheel_y = 0
		state.input.gamepad = {connected = state.input.gamepad.connected}
		state.widget.keys = {}
		state.widget.left_mouse = {}
		state.widget.right_mouse = {}
		state.widget.middle_mouse = {}
		for key in state.widget.element_pointer_down {
			state.widget.element_pointer_down[key] = false
		}
		keyboard := sdl.GetKeyboardState(nil)
		if keyboard != nil {
			state.reload_keys_prev = {keyboard[int(sdl.Scancode.F5)], keyboard[int(sdl.Scancode.F6)]}
		}
		mouse_x, mouse_y: f32
		_ = sdl.GetMouseState(&mouse_x, &mouse_y)
		input_set_mouse_position(mouse_x, mouse_y)
	}
	// Preserve window, quit, device and application events for the normal loop.
	for event in ([]sdl.EventType{
		.KEY_DOWN, .KEY_UP, .TEXT_INPUT, .TEXT_EDITING, .TEXT_EDITING_CANDIDATES,
		.MOUSE_MOTION, .MOUSE_BUTTON_DOWN, .MOUSE_BUTTON_UP, .MOUSE_WHEEL,
		.GAMEPAD_AXIS_MOTION, .GAMEPAD_BUTTON_DOWN, .GAMEPAD_BUTTON_UP,
	}) {
		sdl.FlushEvent(event)
	}
}

@(private)
file_dialog_set_text :: proc(props: sdl.PropertiesID, key: cstring, value: string) -> File_Dialog_Error {
	if value == "" do return .None
	text, err := strings.clone_to_cstring(value)
	if err != nil || text == nil do return .Allocation_Failed
	defer delete(text)
	if !sdl.SetStringProperty(props, key, text) do return .Backend
	return .None
}

@(private)
file_dialog_run :: proc(
	kind: sdl.FileDialogType,
	options: File_Dialog_Options,
	allocator: mem.Allocator,
	show := file_dialog_native_show,
	pump := file_dialog_native_pump,
) -> File_Dialog_Result {
	if message := file_dialog_validate(kind, options); message != "" {
		return file_dialog_failure(.Invalid_Options, message, allocator)
	}
	if .VIDEO not_in sdl.WasInit({.VIDEO}) {
		return file_dialog_failure(.Not_Initialized, "SDL video is not initialized", allocator)
	}
	if !sdl.IsMainThread() {
		return file_dialog_failure(.Wrong_Thread, "Native dialogs require the SDL main thread", allocator)
	}
	if file_dialog_active {
		return file_dialog_failure(.Busy, "A native dialog is already active", allocator)
	}
	file_dialog_active = true
	defer file_dialog_active = false
	props := sdl.CreateProperties()
	if props == 0 do return file_dialog_failure(.Backend, string(sdl.GetError()), allocator)
	defer sdl.DestroyProperties(props)
	labels := [?]struct {key: cstring, value: string} {
		{sdl.PROP_FILE_DIALOG_TITLE_STRING, options.title},
		{sdl.PROP_FILE_DIALOG_LOCATION_STRING, options.location},
		{sdl.PROP_FILE_DIALOG_ACCEPT_STRING, options.accept_label},
		{sdl.PROP_FILE_DIALOG_CANCEL_STRING, options.cancel_label},
	}
	for label in labels {
		if code := file_dialog_set_text(props, label.key, label.value); code != .None {
			message := code == .Allocation_Failed ? "Could not allocate dialog label" : string(sdl.GetError())
			return file_dialog_failure(code, message, allocator)
		}
	}
	if !sdl.SetBooleanProperty(props, sdl.PROP_FILE_DIALOG_MANY_BOOLEAN, options.allow_many) {
		return file_dialog_failure(.Backend, string(sdl.GetError()), allocator)
	}

	if state != nil && state.window != nil {
		if !sdl.SetPointerProperty(props, sdl.PROP_FILE_DIALOG_WINDOW_POINTER, state.window) {
			return file_dialog_failure(.Backend, string(sdl.GetError()), allocator)
		}
	}
	filters: [FILE_DIALOG_MAX_FILTERS]sdl.DialogFileFilter
	request_allocator := context.allocator
	defer {
		for filter in filters[:len(options.filters)] {
			if filter.name != nil do delete(filter.name, request_allocator)
			if filter.pattern != nil do delete(filter.pattern, request_allocator)
		}
	}
	for filter, index in options.filters {
		name, name_err := strings.clone_to_cstring(filter.name, request_allocator)
		filters[index].name = name
		pattern, pattern_err := strings.clone_to_cstring(filter.pattern, request_allocator)
		filters[index].pattern = pattern
		if name_err != nil || pattern_err != nil || name == nil || pattern == nil {
			return file_dialog_failure(.Allocation_Failed, "Could not allocate native file filters", allocator)
		}
	}
	if len(options.filters) > 0 {
		if !sdl.SetPointerProperty(props, sdl.PROP_FILE_DIALOG_FILTERS_POINTER, &filters[0]) ||
		   !sdl.SetNumberProperty(props, sdl.PROP_FILE_DIALOG_NFILTERS_NUMBER, i64(len(options.filters))) {
			return file_dialog_failure(.Backend, string(sdl.GetError()), allocator)
		}
	}
	completion := File_Dialog_Completion{selected_filter = -1}
	defer file_dialog_free_completion(&completion)
	defer {
		file_dialog_resume_input()
		if state != nil {
			request_frame()
			state.last_counter = sdl.GetPerformanceCounter()
		}
	}
	show(kind, file_dialog_callback, &completion, props)
	for !sync.atomic_load(&completion.done) {
		pump()
	}
	if completion.status == .Failed {
		message := completion.error != nil ? string(completion.error) : "Native picker could not return a valid selection"
		return file_dialog_failure(completion.error_code, message, allocator)
	}
	result := File_Dialog_Result{status = completion.status, selected_filter = -1, allocator = allocator}
	if completion.status == .Cancelled do return result
	if !options.allow_many && completion.count != 1 {
		return file_dialog_failure(.Invalid_Result, "Native picker returned multiple paths for a single selection", allocator)
	}
	paths, err := make([]string, completion.count, allocator)
	if err != nil || len(paths) != completion.count do return file_dialog_failure(.Allocation_Failed, "Could not allocate selected paths", allocator)
	result.paths = paths
	for i in 0 ..< completion.count {
		path, path_err := strings.clone(string(completion.paths[i]), allocator)
		if path_err != nil || len(path) != len(string(completion.paths[i])) {
			destroy_file_dialog_result(&result)
			return file_dialog_failure(.Allocation_Failed, "Could not copy selected path", allocator)
		}
		result.paths[i] = path
	}
	if completion.selected_filter >= 0 && completion.selected_filter < len(options.filters) {
		result.selected_filter = completion.selected_filter
	}
	return result
}

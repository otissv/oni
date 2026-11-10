#+test
package oni

import "core:mem"
import "base:runtime"
import "core:strings"
import "core:testing"
import "core:thread"
import sdl "vendor:sdl3"

@(private)
file_dialog_test_mode: enum { Selected, Cancelled, Empty_Cancelled, Failed, Many, Deferred, Reentrant, Modal_Input }
@(private)
file_dialog_test_kind: sdl.FileDialogType
@(private)
file_dialog_test_props_ok: bool
@(private)
file_dialog_test_thread: ^thread.Thread
@(private)
file_dialog_test_reentrant_code: File_Dialog_Error
@(private)
file_dialog_test_worker_code: File_Dialog_Error
@(private)
file_dialog_test_pending: struct {
	callback: sdl.DialogFileCallback,
	userdata: rawptr,
}

@(private)
file_dialog_test_show :: proc(kind: sdl.FileDialogType, callback: sdl.DialogFileCallback, userdata: rawptr, props: sdl.PropertiesID) {
	file_dialog_test_kind = kind
	filters := cast([^]sdl.DialogFileFilter)sdl.GetPointerProperty(props, sdl.PROP_FILE_DIALOG_FILTERS_POINTER, nil)
	file_dialog_test_props_ok = string(sdl.GetStringProperty(props, sdl.PROP_FILE_DIALOG_TITLE_STRING, "")) == "Choose a file" &&
	                           string(sdl.GetStringProperty(props, sdl.PROP_FILE_DIALOG_LOCATION_STRING, "")) == "/tmp/" &&
	                           filters != nil && string(filters[0].pattern) == "txt;md" &&
	                           sdl.GetNumberProperty(props, sdl.PROP_FILE_DIALOG_NFILTERS_NUMBER, 0) == 1 &&
	                           string(sdl.GetStringProperty(props, sdl.PROP_FILE_DIALOG_ACCEPT_STRING, "")) == "Choose" &&
	                           string(sdl.GetStringProperty(props, sdl.PROP_FILE_DIALOG_CANCEL_STRING, "")) == "Dismiss" &&
	                           sdl.GetPointerProperty(props, sdl.PROP_FILE_DIALOG_WINDOW_POINTER, nil) == rawptr(state.window)
	switch file_dialog_test_mode {
	case .Selected:
		path := strings.clone_to_cstring("/tmp/日本語.txt")
		defer delete(path)
		paths := [?]cstring{path, nil}
		callback(userdata, raw_data(paths[:]), 0)
		(cast([^]u8)path)[0] = 'X'
	case .Cancelled:
		paths := [?]cstring{nil}
		callback(userdata, raw_data(paths[:]), -1)
	case .Empty_Cancelled:
		paths := [?]cstring{"", nil}
		callback(userdata, raw_data(paths[:]), -1)
	case .Failed:
		sdl.SetError("native picker failed")
		callback(userdata, nil, -1)
		sdl.SetError("changed after callback")
	case .Many:
		paths := [?]cstring{"/tmp/a.txt", "/tmp/b.md", nil}
		callback(userdata, raw_data(paths[:]), 100)
	case .Modal_Input:
		key := sdl.Event{type = .KEY_DOWN}
		key.key.scancode = .A
		assert(sdl.PushEvent(&key))
		button := sdl.Event{type = .MOUSE_BUTTON_DOWN}
		assert(sdl.PushEvent(&button))
		pad := sdl.Event{type = .GAMEPAD_BUTTON_DOWN}
		assert(sdl.PushEvent(&pad))
		quit := sdl.Event{type = .QUIT}
		assert(sdl.PushEvent(&quit))
		paths := [?]cstring{nil}
		callback(userdata, raw_data(paths[:]), -1)
	case .Reentrant:
		nested := pick_folder()
		file_dialog_test_reentrant_code = nested.error_code
		destroy_file_dialog_result(&nested)
		paths := [?]cstring{nil}
		callback(userdata, raw_data(paths[:]), -1)
	case .Deferred:
		file_dialog_test_pending = {callback, userdata}
	}
}

@(private)
file_dialog_test_worker :: proc() {
	paths := [?]cstring{"/tmp/worker.txt", nil}
	file_dialog_test_pending.callback(file_dialog_test_pending.userdata, raw_data(paths[:]), -1)
}

@(private)
file_dialog_test_pump :: proc() {
	if file_dialog_test_thread == nil {
		file_dialog_test_thread = thread.create_and_start(file_dialog_test_worker)
		if file_dialog_test_thread == nil {
			sdl.SetError("Could not create test worker")
			file_dialog_test_pending.callback(file_dialog_test_pending.userdata, nil, -1)
		}
	}
}

@(test)
file_dialog_options_reject_invalid_text_filters_and_mode_combinations :: proc(t: ^testing.T) {
	invalid_utf8 := [1]u8{255}
	for options in ([]File_Dialog_Options{
		{title = "bad\x00title"}, {location = string(invalid_utf8[:])},
		{filters = []File_Dialog_Filter{{name = "", pattern = "txt"}}},
		{filters = []File_Dialog_Filter{{name = "Bad", pattern = "*.txt"}}},
		{filters = []File_Dialog_Filter{{name = "Bad", pattern = "txt;;md"}}},
		{filters = []File_Dialog_Filter{{name = "Bad", pattern = "txt;*"}}},
	}) {
		result := file_dialog_run(.OPENFILE, options, context.allocator, file_dialog_test_show)
		defer destroy_file_dialog_result(&result)
		testing.expect_value(t, result.status, .Failed)
		testing.expect_value(t, result.error_code, .Invalid_Options)
	}
	testing.expect(t, file_dialog_validate(.OPENFILE, {filters = []File_Dialog_Filter{{name = "Archive", pattern = "tar.gz;7z;my_file-ext"}, {name = "All", pattern = "*"}}}) == "")
	testing.expect(t, file_dialog_validate(.SAVEFILE, {allow_many = true}) != "")
	testing.expect(t, file_dialog_validate(.OPENFOLDER, {filters = []File_Dialog_Filter{{name = "Text", pattern = "txt"}}}) != "")
}

@(test)
file_dialog_selected_paths_are_owned_and_properties_reach_backend :: proc(t: ^testing.T) {
	with_engine_sdl_window_env(t, proc(t: ^testing.T) {
		file_dialog_test_mode = .Selected
		result := file_dialog_run(.OPENFILE, {
			title = "Choose a file", location = "/tmp/", accept_label = "Choose", cancel_label = "Dismiss",
			filters = []File_Dialog_Filter{{name = "Text", pattern = "txt;md"}},
		}, context.allocator, file_dialog_test_show)
		defer destroy_file_dialog_result(&result)
		testing.expect(t, file_dialog_test_props_ok)
		testing.expect_value(t, result.status, .Selected)
		testing.expect_value(t, result.selected_filter, 0)
		testing.expect_value(t, len(result.paths), 1)
		if len(result.paths) == 1 {
			testing.expect_value(t, result.paths[0], "/tmp/日本語.txt")
		}
		destroy_file_dialog_result(&result)
		destroy_file_dialog_result(&result)
		testing.expect_value(t, len(result.paths), 0)
	})
}

@(test)
file_dialog_cancel_and_native_failure_are_distinct_and_owned :: proc(t: ^testing.T) {
	with_engine_sdl_env(t, proc(t: ^testing.T) {
		file_dialog_test_mode = .Cancelled
		cancelled := file_dialog_run(.SAVEFILE, {}, context.allocator, file_dialog_test_show)
		defer destroy_file_dialog_result(&cancelled)
		testing.expect_value(t, file_dialog_test_kind, .SAVEFILE)
		testing.expect_value(t, cancelled.status, .Cancelled)
		testing.expect_value(t, cancelled.error_code, .None)
		file_dialog_test_mode = .Empty_Cancelled
		empty := file_dialog_run(.OPENFILE, {}, context.allocator, file_dialog_test_show)
		defer destroy_file_dialog_result(&empty)
		testing.expect_value(t, empty.status, .Cancelled)
		file_dialog_test_mode = .Failed
		failed := file_dialog_run(.OPENFOLDER, {}, context.allocator, file_dialog_test_show)
		defer destroy_file_dialog_result(&failed)
		testing.expect_value(t, file_dialog_test_kind, .OPENFOLDER)
		testing.expect_value(t, failed.status, .Failed)
		testing.expect_value(t, failed.error_code, .Backend)
		testing.expect_value(t, failed.error, "native picker failed")
	})
}

@(test)
file_dialog_multiple_selection_and_unknown_filter_are_explicit :: proc(t: ^testing.T) {
	with_engine_sdl_env(t, proc(t: ^testing.T) {
		file_dialog_test_mode = .Many
		for kind in ([]sdl.FileDialogType{.OPENFILE, .OPENFOLDER}) {
			result := file_dialog_run(kind, {allow_many = true}, context.allocator, file_dialog_test_show)
			defer destroy_file_dialog_result(&result)
			testing.expect_value(t, result.status, .Selected)
			testing.expect_value(t, len(result.paths), 2)
			testing.expect_value(t, result.selected_filter, -1)
		}
		single := file_dialog_run(.SAVEFILE, {}, context.allocator, file_dialog_test_show)
		defer destroy_file_dialog_result(&single)
		testing.expect_value(t, single.error_code, .Invalid_Result)
	})
}

@(test)
file_dialog_worker_completion_is_pumped_and_copied_on_owner_thread :: proc(t: ^testing.T) {
	with_engine_sdl_env(t, proc(t: ^testing.T) {
		file_dialog_test_mode = .Deferred
		file_dialog_test_thread = nil
		defer {
			thread.join(file_dialog_test_thread)
			thread.destroy(file_dialog_test_thread)
			file_dialog_test_thread = nil
			file_dialog_test_pending = {}
		}
		result := file_dialog_run(.OPENFILE, {}, context.allocator, file_dialog_test_show, file_dialog_test_pump)
		defer destroy_file_dialog_result(&result)
		testing.expect_value(t, result.status, .Selected)
		testing.expect_value(t, len(result.paths), 1)
		if len(result.paths) == 1 {
			testing.expect_value(t, result.paths[0], "/tmp/worker.txt")
		}
	})
}

@(test)
file_dialog_result_retains_allocator_and_allocation_failure_cleans_up :: proc(t: ^testing.T) {
	with_engine_sdl_env(t, proc(t: ^testing.T) {
		tracking: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking, context.allocator)
		defer mem.tracking_allocator_destroy(&tracking)
		file_dialog_test_mode = .Selected
		result := file_dialog_run(.OPENFILE, {}, mem.tracking_allocator(&tracking), file_dialog_test_show)
		context.allocator = mem.nil_allocator()
		destroy_file_dialog_result(&result)
		testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	})
	with_engine_sdl_env(t, proc(t: ^testing.T) {
		file_dialog_test_mode = .Selected
		result := file_dialog_run(.OPENFILE, {}, mem.nil_allocator(), file_dialog_test_show)
		defer destroy_file_dialog_result(&result)
		testing.expect_value(t, result.status, .Failed)
		testing.expect_value(t, result.error_code, .Allocation_Failed)
	})
}

@(test)
file_dialog_native_backend_reports_unavailable_driver :: proc(t: ^testing.T) {
	with_engine_sdl_env(t, proc(t: ^testing.T) {
		old := strings.clone_from_cstring(sdl.GetHint(sdl.HINT_FILE_DIALOG_DRIVER))
		defer delete(old)
		defer {
			if old != "" {
				previous := strings.clone_to_cstring(old, context.temp_allocator)
				sdl.SetHint(sdl.HINT_FILE_DIALOG_DRIVER, previous)
			} else {
				sdl.ResetHint(sdl.HINT_FILE_DIALOG_DRIVER)
			}
		}
		sdl.SetHint(sdl.HINT_FILE_DIALOG_DRIVER, "oni-test-unavailable-driver")
		result := open_file_dialog()
		defer destroy_file_dialog_result(&result)
		testing.expect_value(t, result.status, .Failed)
		testing.expect_value(t, result.error_code, .Backend)
	})
}

@(test)
file_dialog_failed_partial_callback_copies_are_released :: proc(t: ^testing.T) {
	invalid := [2]u8{255, 0}
	paths := [?]cstring{"/tmp/copied-first", cstring(&invalid[0]), nil}
	completion: File_Dialog_Completion
	before := sdl.GetNumAllocations()
	file_dialog_callback(&completion, raw_data(paths[:]), -1)
	testing.expect_value(t, completion.status, .Failed)
	testing.expect_value(t, completion.error_code, .Invalid_Result)
	testing.expect_value(t, completion.count, 1)
	file_dialog_free_completion(&completion)
	testing.expect_value(t, sdl.GetNumAllocations(), before)

	many: [FILE_DIALOG_MAX_SELECTIONS + 2]cstring
	for i in 0 ..< len(many) - 1 { many[i] = "/tmp/path" }
	file_dialog_callback(&completion, raw_data(many[:]), -1)
	testing.expect_value(t, completion.error_code, .Limit_Exceeded)
	file_dialog_free_completion(&completion)
	testing.expect_value(t, sdl.GetNumAllocations(), before)

	long_path := make([]u8, FILE_DIALOG_MAX_PATH_BYTES + 2)
	defer delete(long_path)
	for i in 0 ..< len(long_path) - 1 { long_path[i] = 'a' }
	oversized := [?]cstring{cstring(raw_data(long_path)), nil}
	file_dialog_callback(&completion, raw_data(oversized[:]), -1)
	testing.expect_value(t, completion.error_code, .Limit_Exceeded)
	file_dialog_free_completion(&completion)
	testing.expect_value(t, sdl.GetNumAllocations(), before)
}

@(private)
File_Dialog_Test_Allocator :: struct {
	backing: mem.Allocator,
	remaining: int,
}

@(private)
file_dialog_test_allocator :: proc(data: rawptr, mode: runtime.Allocator_Mode,
                                   size, alignment: int, old_memory: rawptr, old_size: int,
                                   loc := #caller_location) -> ([]byte, runtime.Allocator_Error) {
	budget := cast(^File_Dialog_Test_Allocator)data
	if mode == .Alloc || mode == .Alloc_Non_Zeroed {
		if budget.remaining == 0 do return nil, .Out_Of_Memory
		budget.remaining -= 1
	}
	return budget.backing.procedure(budget.backing.data, mode, size, alignment, old_memory, old_size, loc)
}

@(test)
file_dialog_partial_result_allocation_failure_releases_every_path :: proc(t: ^testing.T) {
	with_engine_sdl_env(t, proc(t: ^testing.T) {
		tracking: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking, context.allocator)
		defer mem.tracking_allocator_destroy(&tracking)
		file_dialog_test_mode = .Many
		budget := File_Dialog_Test_Allocator{mem.tracking_allocator(&tracking), 2}
		allocator := mem.Allocator{procedure = file_dialog_test_allocator, data = &budget}
		result := file_dialog_run(.OPENFILE, {allow_many = true}, allocator, file_dialog_test_show)
		defer destroy_file_dialog_result(&result)
		testing.expect_value(t, result.error_code, .Allocation_Failed)
		testing.expect_value(t, len(result.paths), 0)
		testing.expect_value(t, tracking.current_memory_allocated, i64(0))
	})
}

@(private)
file_dialog_test_wrong_thread :: proc() {
	result := open_file_dialog({}, runtime.default_allocator())
	defer destroy_file_dialog_result(&result)
	file_dialog_test_worker_code = result.error_code
}

@(test)
file_dialog_reentrant_and_worker_thread_requests_are_rejected :: proc(t: ^testing.T) {
	with_engine_sdl_env(t, proc(t: ^testing.T) {
		file_dialog_test_mode = .Reentrant
		result := file_dialog_run(.OPENFILE, {}, context.allocator, file_dialog_test_show)
		defer destroy_file_dialog_result(&result)
		testing.expect_value(t, file_dialog_test_reentrant_code, .Busy)
		worker := thread.create_and_start(file_dialog_test_wrong_thread)
		testing.expect(t, worker != nil)
		if worker == nil do return
		thread.join(worker)
		thread.destroy(worker)
		testing.expect_value(t, file_dialog_test_worker_code, .Wrong_Thread)
	})
}

@(test)
file_dialog_requires_initialized_video_and_defaults_are_destroyable :: proc(t: ^testing.T) {
	with_engine_env(t, proc(t: ^testing.T) {
		result := open_file_dialog()
		defer destroy_file_dialog_result(&result)
		testing.expect_value(t, result.error_code, .Not_Initialized)
		empty: File_Dialog_Result
		destroy_file_dialog_result(&empty)
		destroy_file_dialog_result(nil)
	})
}

@(test)
file_dialog_discards_modal_input_without_losing_quit_or_reload_state :: proc(t: ^testing.T) {
	with_engine_sdl_env(t, proc(t: ^testing.T) {
		file_dialog_test_mode = .Modal_Input
		state.running = false
		state.force_reload = true
		state.input.keys_down[int(sdl.Scancode.A)] = true
		state.input.mouse_left = true
		state.input.gamepad = {connected = true, dpad_left = true}
		state.widget.keys[int(sdl.Scancode.A)] = {down = true, pressed = true}
		state.widget.left_mouse = {down = true, pressed = true}
		_ = consume_pointer_click("modal-click", true, true, false)
		result := file_dialog_run(.OPENFILE, {}, context.allocator, file_dialog_test_show)
		defer destroy_file_dialog_result(&result)
		testing.expect_value(t, result.status, .Cancelled)
		testing.expect(t, !sdl.HasEvent(.KEY_DOWN))
		testing.expect(t, !sdl.HasEvent(.MOUSE_BUTTON_DOWN))
		testing.expect(t, sdl.HasEvent(.QUIT))
		testing.expect(t, !sdl.HasEvent(.GAMEPAD_BUTTON_DOWN))
		testing.expect(t, state.input.gamepad.connected && !state.input.gamepad.dpad_left)
		testing.expect(t, !state.input.keys_down[int(sdl.Scancode.A)])
		testing.expect(t, !state.input.mouse_left)
		testing.expect(t, !state.widget.keys[int(sdl.Scancode.A)].pressed)
		testing.expect(t, !state.widget.left_mouse.pressed)
		testing.expect(t, !state.widget.element_pointer_down["modal-click"])
		testing.expect(t, !state.running && state.force_reload)
		testing.expect(t, state.frame_dirty)
	})
}

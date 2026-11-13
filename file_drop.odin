package oni

import "core:math"
import "core:mem"
import "core:strings"
import "core:unicode/utf8"
import sdl "vendor:sdl3"

FILE_DROP_MAX_BATCHES :: 32
FILE_DROP_MAX_FILES :: 1024
FILE_DROP_MAX_PATH_BYTES :: 128 * 1024
FILE_DROP_MAX_OWNED_BYTES :: 16 * 1024 * 1024
FILE_DROP_MAX_TARGETS :: 1024
FILE_DROP_EVENTS_PER_POLL :: 64
FILE_DROP_BYTES_PER_POLL :: 256 * 1024

File_Drop_Status :: enum { None, Selected, Failed }
File_Drop_Error :: enum { None, Invalid_Data, Limit_Exceeded, Allocation_Failed, Queue_Full, Rejected }

/*
One completed native file-drop transaction. Paths are native UTF-8 paths (or
platform URIs); receiving them performs no file I/O. Ownership moves out of
Take_File_Drop and must be released with Destroy_File_Drop_Result. Do not copy
ownership. The allocator must outlive the result. Position uses logical screen
coordinates; system-open requests with no window have has_position = false.
*/
File_Drop_Result :: struct {
	status: File_Drop_Status,
	paths: []string,
	position: Vec2,
	has_position: bool,
	error_code: File_Drop_Error,
	omitted_batches: u64,
	allocator: mem.Allocator,
	byte_count: int,
}

File_Drag_State :: struct {
	active, has_position: bool,
	position: Vec2,
}

@(private)
File_Drop_Entry :: struct {
	result: File_Drop_Result,
	target: UI_Id,
	routed: bool,
}

@(private)
File_Drop_Context :: struct {
	drag: File_Drag_State,
	pending: [dynamic]string,
	pending_bytes, owned_bytes: int,
	pending_error: File_Drop_Error,
	collecting: bool,
	window_id: sdl.WindowID,
	ready: [FILE_DROP_MAX_BATCHES]File_Drop_Entry,
	count: int,
	overflow: File_Drop_Entry,
	targets: map[UI_Id]bool,
	hover_target, previous_hover_target: UI_Id,
}

file_drag_state :: proc() -> File_Drag_State {
	if state == nil {

		return {}
	}

	return state.file_drop.drag
}

destroy_file_drop_result :: proc(result: ^File_Drop_Result) {
	if result == nil {

		return
	}

	for path in result.paths {
		delete(path, result.allocator)
	}
	delete(result.paths, result.allocator)
	result^ = {}
}

/*
Moves the oldest completed result to the caller. A zero target consumes the
window queue, including system-open requests and unclaimed drops. Nonzero
targets consume only their routed results during Draw. Queue overflow is an
explicit Failed result with omitted_batches, never a partial successful batch.
Main-thread API, like the engine input and UI APIs.
*/
take_file_drop :: proc(target: UI_Id = {}) -> (result: File_Drop_Result, ok: bool) {
	if state == nil || target != {} && ui_pass() != .Draw {

		return {}, false
	}

	d := &state.file_drop
	for entry, i in d.ready[:d.count] {
		if target != {} && (!entry.routed || entry.target != target) {
			continue
		}

		result = entry.result
		d.owned_bytes -= result.byte_count
		for j in i ..< d.count - 1 {
			d.ready[j] = d.ready[j + 1]
		}
		d.count -= 1
		d.ready[d.count] = {}
		request_frame()

		return result, true
	}

	if d.overflow.result.status != .None &&
	   (target == {} || d.overflow.routed && d.overflow.target == target) {
		result = d.overflow.result
		d.overflow = {}
		request_frame()

		return result, true
	}

	return {}, false
}

@(private)
file_drop_clear_pending :: proc() {
	d := &state.file_drop
	for path in d.pending {
		delete(path, d.pending.allocator)
	}
	clear(&d.pending)
	d.owned_bytes -= d.pending_bytes
	d.pending_bytes = 0
	d.pending_error = .None
	d.collecting = false
	d.drag = {}
}

@(private)
file_drop_fail_pending :: proc(code: File_Drop_Error) {
	drag := state.file_drop.drag
	file_drop_clear_pending()
	state.file_drop.drag = drag
	state.file_drop.collecting = true
	state.file_drop.pending_error = code
}

// Called for an explicit reset; completed results retain their owned data.
file_drop_cancel :: proc() {
	if state == nil {

		return
	}

	file_drop_clear_pending()
	file_drop_begin_ui_frame()
	state.file_drop.previous_hover_target = {}
}

file_drop_shutdown :: proc() {
	if state == nil {

		return
	}

	d := &state.file_drop
	file_drop_clear_pending()
	for &entry in d.ready[:d.count] {
		destroy_file_drop_result(&entry.result)
	}
	delete(d.pending)
	delete(d.targets)
	d^ = {}
}

@(private)
file_drop_set_position :: proc(event: sdl.DropEvent, window_size: Vec2) {
	d := &state.file_drop
	d.drag.has_position = event.windowID != 0 && window_size.x > 0 && window_size.y > 0 &&
		!math.is_nan(event.x) && !math.is_inf(event.x) && !math.is_nan(event.y) && !math.is_inf(event.y)

	if !d.drag.has_position {

		return
	}

	// SDL coordinates are relative to the window, not the drawable framebuffer.
	w := state.dpi.drawable_w > 0 ? f32(state.dpi.drawable_w) : window_size.x
	h := state.dpi.drawable_h > 0 ? f32(state.dpi.drawable_h) : window_size.y
	d.drag.position = screen_to_logical(event.x * w / window_size.x, event.y * h / window_size.y, state.dpi)
	d.drag.has_position = !math.is_nan(d.drag.position.x) && !math.is_inf(d.drag.position.x) &&
		!math.is_nan(d.drag.position.y) && !math.is_inf(d.drag.position.y)
}

@(private)
file_drop_capture_path :: proc(data: cstring) -> int {
	d := &state.file_drop
	if d.pending_error != .None {

		return 0
	}

	if data == nil {
		file_drop_fail_pending(.Invalid_Data)

		return 0
	}

	bytes := cast([^]u8)data
	length := 0
	for length <= FILE_DROP_MAX_PATH_BYTES && bytes[length] != 0 {
		length += 1
	}

	if length > FILE_DROP_MAX_PATH_BYTES || len(d.pending) >= FILE_DROP_MAX_FILES ||
	   length > FILE_DROP_MAX_OWNED_BYTES - d.owned_bytes {
		file_drop_fail_pending(.Limit_Exceeded)

		return length
	}

	path := string(bytes[:length])
	if length == 0 || !utf8.valid_string(path) {
		file_drop_fail_pending(.Invalid_Data)

		return length
	}

	if d.pending.allocator.procedure == nil {
		allocation_error: mem.Allocator_Error
		d.pending, allocation_error = make([dynamic]string, 0, 16)

		if allocation_error != nil {
			file_drop_fail_pending(.Allocation_Failed)

			return length
		}
	}

	owned, clone_error := strings.clone(path, d.pending.allocator)
	if clone_error != nil {
		file_drop_fail_pending(.Allocation_Failed)

		return length
	}

	_, append_error := append(&d.pending, owned)
	if append_error != nil {
		delete(owned, d.pending.allocator)
		file_drop_fail_pending(.Allocation_Failed)

		return length
	}

	d.pending_bytes += length
	d.owned_bytes += length

	return length
}

@(private)
file_drop_complete :: proc() {
	d := &state.file_drop
	if !d.collecting || len(d.pending) == 0 && d.pending_error == .None {
		file_drop_clear_pending()

		return
	}

	if d.count == FILE_DROP_MAX_BATCHES {
		omitted := d.overflow.result.omitted_batches + 1
		d.overflow = {result = {
			status = .Failed, error_code = .Queue_Full,
			position = d.drag.position, has_position = d.drag.has_position,
			omitted_batches = omitted,
		}}
		file_drop_clear_pending()

		return
	}

	result := File_Drop_Result{
		status = .Selected,
		position = d.drag.position,
		has_position = d.drag.has_position,
		allocator = d.pending.allocator,
	}

	if d.pending_error != .None {
		result.status = .Failed
		result.error_code = d.pending_error
	} else {
		allocation_error: mem.Allocator_Error
		result.paths, allocation_error = make([]string, len(d.pending), d.pending.allocator)

		if allocation_error != nil {
			result.status = .Failed
			result.error_code = .Allocation_Failed
		} else {
			copy(result.paths, d.pending[:])
			result.byte_count = d.pending_bytes
			clear(&d.pending)
			d.pending_bytes = 0
		}
	}

	d.ready[d.count] = {result = result}
	d.count += 1
	file_drop_clear_pending()
}

/*
Copies SDL-owned event data before the next SDL poll can invalidate it. SDL3
owns the event strings; Oni frees only its own copies. Coordinates and window
identity are supplied by the owner thread, also allowing deterministic tests.
*/
file_drop_process_event :: proc(event: sdl.DropEvent, owner_window: sdl.WindowID, window_size: Vec2) -> int {
	if state == nil || event.windowID != 0 && event.windowID != owner_window {

		return 0
	}

	if event.type != .DROP_BEGIN && event.type != .DROP_POSITION && event.type != .DROP_FILE &&
	   event.type != .DROP_TEXT && event.type != .DROP_COMPLETE {

		return 0
	}

	d := &state.file_drop
	if event.type == .DROP_BEGIN {
		file_drop_clear_pending()
		d.collecting = true
		d.window_id = event.windowID
		d.drag.active = true
		request_frame()

		return 0
	}

	if event.type == .DROP_TEXT {

		return 0
	}

	if event.type == .DROP_COMPLETE && (!d.collecting || d.window_id != event.windowID) {

		return 0
	}

	if !d.collecting || d.window_id != event.windowID {
		file_drop_clear_pending()
		d.collecting = true
		d.window_id = event.windowID
	}
	d.drag.active = true
	file_drop_set_position(event, window_size)
	request_frame()

	#partial switch event.type {
	case .DROP_FILE:
		return file_drop_capture_path(event.data)
	case .DROP_COMPLETE:
		file_drop_complete()
	case .DROP_POSITION:
	case:
	}

	return 0
}

file_drop_begin_ui_frame :: proc() {
	state.file_drop.previous_hover_target = state.file_drop.hover_target
	clear(&state.file_drop.targets)
	state.file_drop.hover_target = {}
}

/* Register during Layout, after deriving the same UI_Id used by the box. */
file_drop_register_target :: proc(id: UI_Id, enabled: bool) -> bool {
	if state == nil || ui_pass() != .Layout || id == {} {

		return false
	}

	d := &state.file_drop
	if d.targets == nil {
		allocation_error: mem.Allocator_Error
		d.targets, allocation_error = make(map[UI_Id]bool, FILE_DROP_MAX_TARGETS)

		if allocation_error != nil {

			return false
		}
	}

	if len(d.targets) >= FILE_DROP_MAX_TARGETS && id not_in d.targets {

		return false
	}
	d.targets[id] = enabled

	return true
}

file_drop_target_hovered :: proc(id: UI_Id) -> bool {
	return state != nil && state.file_drop.drag.active && state.file_drop.hover_target == id && id != {}
}

file_drop_target_entered :: proc(id: UI_Id) -> bool {
	return file_drop_target_hovered(id) && state.file_drop.previous_hover_target != id
}

file_drop_target_left :: proc(id: UI_Id) -> bool {
	return state != nil && id != {} && state.file_drop.previous_hover_target == id && !file_drop_target_hovered(id)
}

@(private)
file_drop_target_at :: proc(point: Vec2) -> UI_Id {
	if point.x < 0 || point.y < 0 || point.x >= f32(state.dpi.logical_w) || point.y >= f32(state.dpi.logical_h) {

		return {}
	}

	layout := &state.ui.layout
	lists := [4][]int{layout.paint_list_overlay[:], layout.paint_list_popover[:], layout.paint_list_screen[:], layout.paint_list_artboard[:]}
	spaces := [4]Draw_Space{.OVERLAY, .POPOVER, .SCREEN, .ARTBOARD}
	for list, i in lists {
		id, hit := layout_hit_test_list(list, spaces[i], point)

		if !hit {
			continue
		}

		node_index := layout.id_to_node[id]
		for node_index >= 0 {
			node := &layout.nodes[node_index]

			if node.space != spaces[i] {

				return {}
			}

			if enabled, registered := state.file_drop.targets[node.ui_id]; registered {
				if enabled && !node.config.disabled {

					return node.ui_id
				}

				return {}
			}
			node_index = node.parent
		}

		return {}
	}

	return {}
}

file_drop_resolve_targets :: proc() {
	d := &state.file_drop
	if len(d.targets) == 0 {
		for &entry in d.ready[:d.count] { entry.routed = true }
		d.overflow.routed = true

		return
	}

	if d.drag.active && d.drag.has_position {
		d.hover_target = file_drop_target_at(d.drag.position)
	}
	for &entry in d.ready[:d.count] {
		if !entry.routed {
			if entry.result.has_position {
				entry.target = file_drop_target_at(entry.result.position)
			}
			entry.routed = true
		}
	}
	if !d.overflow.routed && d.overflow.result.status != .None {
		if d.overflow.result.has_position {
			d.overflow.target = file_drop_target_at(d.overflow.result.position)
		}
		d.overflow.routed = true
	}
}

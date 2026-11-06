package oni

import v "./vector"

vector_svg_path_command_hash :: v.Commands_Hash

@(private)
vector_svg_same_geometry_structure :: proc(a, b: []Vector_Path_Command) -> bool {
	if len(a) != len(b) { return false }
	for &command, i in a {
		other := &b[i]
		if command.kind != other.kind { return false }
		if command.kind == .Arc && (command.radii != other.radii || command.rotation != other.rotation ||
			command.large_arc != other.large_arc || command.sweep != other.sweep) { return false }
	}
	return true
}

@(private)
vector_svg_lru_unlink :: proc(handle: Vector_Path_Handle) {
	if state == nil || handle.index == 0 {

		return
	}

	entry := vector_path_entry(handle)
	if entry == nil || !entry.svg_retained {

		return
	}

	prev := entry.svg_lru_prev
	next := entry.svg_lru_next
	if prev.index != 0 {
		prev_entry := vector_path_entry(prev)
		if prev_entry != nil {
			prev_entry.svg_lru_next = next
		}
	} else {
		state.vector.svg_lru_first = next
	}

	if next.index != 0 {
		next_entry := vector_path_entry(next)
		if next_entry != nil {
			next_entry.svg_lru_prev = prev
		}
	} else {
		state.vector.svg_lru_last = prev
	}

	entry.svg_lru_prev = {}
	entry.svg_lru_next = {}
}

@(private)
vector_svg_lru_touch :: proc(handle: Vector_Path_Handle) {
	if state == nil || handle.index == 0 {

		return
	}

	entry := vector_path_entry(handle)
	if entry == nil || !entry.svg_retained {

		return
	}

	if state.vector.svg_lru_last == handle {

		return
	}

	vector_svg_lru_unlink(handle)
	entry.svg_lru_prev = state.vector.svg_lru_last
	entry.svg_lru_next = {}
	if state.vector.svg_lru_last.index != 0 {
		last := vector_path_entry(state.vector.svg_lru_last)
		if last != nil {
			last.svg_lru_next = handle
		}
	} else {
		state.vector.svg_lru_first = handle
	}
	state.vector.svg_lru_last = handle
}

@(private)
vector_svg_lru_append :: proc(handle: Vector_Path_Handle) {
	entry := vector_path_entry(handle)
	if entry == nil {

		return
	}

	entry.svg_lru_prev = state.vector.svg_lru_last
	entry.svg_lru_next = {}
	if state.vector.svg_lru_last.index != 0 {
		last := vector_path_entry(state.vector.svg_lru_last)
		if last != nil {
			last.svg_lru_next = handle
		}
	} else {
		state.vector.svg_lru_first = handle
	}
	state.vector.svg_lru_last = handle
}

@(private)
vector_svg_evict_oldest :: proc() -> bool {
	handle := state.vector.svg_lru_first
	for handle.index != 0 {
		entry := vector_path_entry(handle)
		next := entry.svg_lru_next if entry != nil else Vector_Path_Handle{}
		if entry != nil && entry.live && entry.svg_retained && entry.last_used < state.ui.frame {
			_ = Vector_Destroy_Path(handle)

			return true
		}
		handle = next
	}

	return false
}

// Content addressing also shares immutable geometry between independently
// compiled instances. Stored command hashes make hash collisions harmless.
@(private)
vector_svg_path :: proc(commands: []Vector_Path_Command, command_hash: [2]u64 = {}, structure: [2]u64 = {}, mesh_only: bool = false) -> (Vector_Path_Handle, Vector_Error) {
	// Precomputed hashes come from immutable, validated SVG snapshots.
	validated := command_hash != {}
	borrow_commands := mesh_only && validated && structure != {}
	command_hash := command_hash
	structure := structure
	if command_hash == {} { command_hash = vector_svg_path_command_hash(commands, &structure) }
	map_key := command_hash
	for {
		handle, found := state.vector.svg_paths[map_key]
		if !found {

			break
		}

		entry := vector_path_entry(handle)
		if entry != nil && entry.svg_command_hash == command_hash {
			if entry.svg_mesh_only {
				if err := vector_svg_bind_snapshot_commands(entry, commands, borrow_commands); err != .None { return {}, err }
			}
			if entry.last_used != state.ui.frame {
				entry.last_used = state.ui.frame
				vector_svg_lru_touch(handle)
			}

			return handle, .None
		}

		map_key[1] += 1
	}

	bytes := u64(len(commands)) * size_of(Vector_Path_Command)
	if bytes > VECTOR_CPU_CACHE_BUDGET {

		return {}, .Limit_Exceeded
	}

	// Prior-frame content is no longer borrowed by recording. Recycle compatible
	// storage so changing SVG paths can retain their tessellation capacity.
	oldest := state.vector.svg_lru_first
	if entry := vector_path_entry(oldest); entry != nil && entry.last_used < state.ui.frame &&
	   ((structure != {} && entry.svg_structure != {}) ? structure == entry.svg_structure : vector_svg_same_geometry_structure(entry.commands, commands)) {
		if !validated {
			if validation := v.Validate_Commands(commands); validation != .None { return {}, vector_path_error(validation) }
		}
		if entry.svg_mesh_only {
			if err := vector_svg_bind_snapshot_commands(entry, commands, borrow_commands); err != .None { return {}, err }
		} else { copy(entry.commands, commands) }
		delete_key(&state.vector.svg_paths, entry.svg_key)
		_ = Vector_Path_Geometry_Changed(oldest)
		entry.svg_key, entry.svg_command_hash = map_key, command_hash
		entry.svg_structure = structure
		entry.last_used = state.ui.frame
		state.vector.svg_paths[map_key] = oldest
		vector_svg_lru_touch(oldest)
		return oldest, .None
	}

	retained_bytes := borrow_commands ? 0 : bytes
	for state.vector.svg_path_bytes > VECTOR_CPU_CACHE_BUDGET - retained_bytes || len(state.vector.svg_paths) >= VECTOR_MAX_FRAME_NODES {
		if !vector_svg_evict_oldest() {

			return {}, .Limit_Exceeded
		}
	}

	handle: Vector_Path_Handle
	err: Vector_Error
	if borrow_commands {
		borrowed := (cast([^]Vector_Path_Command)rawptr(raw_data(commands)))[:len(commands)]
		handle, err = vector_register_path(borrowed, context.allocator, true)
	} else { handle, err = Vector_Create_Path(commands) }
	if err != .None {

		return {}, err
	}

	if reserve(&state.vector.svg_paths, len(state.vector.svg_paths) + 1) != nil {
		_ = Vector_Destroy_Path(handle)

		return {}, .Allocation_Failed
	}

	entry := vector_path_entry(handle)
	entry.svg_retained = true
	entry.svg_key = map_key
	entry.svg_command_hash = command_hash
	entry.svg_structure = structure
	entry.last_used = state.ui.frame
	state.vector.svg_paths[map_key] = handle
	if !borrow_commands { state.vector.svg_path_bytes += bytes }
	vector_svg_lru_append(handle)

	return handle, .None
}

// Generic consumers need owned commands; the flat synchronous recorder only
// borrows its immutable snapshot until the mesh is recorded.
@(private)
vector_svg_bind_snapshot_commands :: proc(entry: ^Vector_Path_Entry, commands: []Vector_Path_Command, mesh_only: bool) -> Vector_Error {
	if mesh_only {
		entry.commands = (cast([^]Vector_Path_Command)rawptr(raw_data(commands)))[:len(commands)]
		return .None
	}
	bytes := u64(len(commands)) * size_of(Vector_Path_Command)
	if bytes > VECTOR_CPU_CACHE_BUDGET || state.vector.svg_path_bytes > VECTOR_CPU_CACHE_BUDGET - bytes { return .Limit_Exceeded }
	owned, err := vector_copy_path_commands(commands)
	if err != .None { return err }
	entry.commands = owned
	entry.command_allocator = context.allocator
	entry.svg_mesh_only = false
	state.vector.svg_path_bytes += bytes
	return .None
}

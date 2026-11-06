package oni_vector

import "core:hash/xxhash"
import "core:mem"

// Hashes command values, excluding structure padding.
Commands_Hash :: proc(commands: []Command, structure: ^[2]u64 = nil) -> [2]u64 {
	if structure != nil { structure^ = {} }
	compact := structure != nil && len(commands) > 0 && len(commands) <= 40
	key := [2]u64{0, u64(len(commands)) << 58}
	storage: [64][11]u64 = ---
	stream: xxhash.XXH3_state
	if len(commands) > len(storage) { _ = xxhash.XXH3_128_reset(&stream) }
	for base := 0; base < len(commands); base += len(storage) {
		count := min(len(storage), len(commands) - base)
		for &command, i in commands[base:][:count] {
			if compact {
				if command.kind == .Arc || command.kind < .Move || command.kind > .Close {
					compact, key = false, {}
				} else if i < 21 { key[0] |= u64(command.kind) << u64(i * 3)
				} else { key[1] |= u64(command.kind) << u64((i - 21) * 3) }
			}
			when size_of(Command_Kind) == size_of(u64) && offset_of(Command, points) == size_of(u64) &&
			     offset_of(Command, large_arc) == 10 * size_of(u64) {
				copy(storage[i][:10], (cast([^]u64)rawptr(&command))[:10])
				storage[i][10] = u64(command.large_arc) | (u64(command.sweep) << 8)
			} else {
				storage[i] = {
					u64(command.kind), transmute(u64)command.points[0].x, transmute(u64)command.points[0].y,
					transmute(u64)command.points[1].x, transmute(u64)command.points[1].y,
					transmute(u64)command.points[2].x, transmute(u64)command.points[2].y,
					transmute(u64)command.radii.x, transmute(u64)command.radii.y,
					transmute(u64)command.rotation, u64(command.large_arc) | (u64(command.sweep) << 8),
				}
			}
		}
		bytes := mem.slice_to_bytes(storage[:count])
		if len(commands) <= len(storage) {
			if structure != nil && compact { structure^ = key }
			return transmute([2]u64)xxhash.XXH3_128_default(bytes)
		}
		_ = xxhash.XXH3_128_update(&stream, bytes)
	}
	if len(commands) == 0 { return transmute([2]u64)xxhash.XXH3_128_default(nil) }
	return transmute([2]u64)xxhash.XXH3_128_digest(&stream)
}

// The snapshot owns these commands, so padding can be canonicalized in place
// before hashing rather than copying the complete command stream again.
@(private)
commands_owned_hash :: proc(commands: []Command, structure: ^[2]u64 = nil) -> [2]u64 {
	when ODIN_ENDIAN == .Little && size_of(Command_Kind) == 8 && size_of(Command) == 88 &&
	     offset_of(Command, points) == 8 && offset_of(Command, large_arc) == 80 && offset_of(Command, sweep) == 81 {
		if structure != nil { structure^ = {} }
		compact := structure != nil && len(commands) > 0 && len(commands) <= 40
		key := [2]u64{0, u64(len(commands)) << 58}
		for &command, i in commands {
			(cast(^u64)rawptr(&command.large_arc))^ = u64(command.large_arc) | (u64(command.sweep) << 8)
			if compact {
				if command.kind == .Arc || command.kind < .Move || command.kind > .Close { compact, key = false, {}
				} else if i < 21 { key[0] |= u64(command.kind) << u64(i * 3)
				} else { key[1] |= u64(command.kind) << u64((i - 21) * 3) }
			}
		}
		if compact { structure^ = key }
		return transmute([2]u64)xxhash.XXH3_128_default(mem.slice_to_bytes(commands))
	} else { return Commands_Hash(commands, structure) }
}


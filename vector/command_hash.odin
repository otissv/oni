package oni_vector

import "core:hash/xxhash"
import "core:mem"

// Hashes command values, excluding structure padding.
Commands_Hash :: proc(commands: []Command) -> [2]u64 {
	storage: [64][12]u64 = ---
	stream: xxhash.XXH3_state
	if len(commands) > len(storage) { _ = xxhash.XXH3_128_reset(&stream) }
	for base := 0; base < len(commands); base += len(storage) {
		count := min(len(storage), len(commands) - base)
		for &command, i in commands[base:][:count] {
			storage[i] = {
			u64(command.kind), transmute(u64)command.points[0].x, transmute(u64)command.points[0].y,
			transmute(u64)command.points[1].x, transmute(u64)command.points[1].y,
			transmute(u64)command.points[2].x, transmute(u64)command.points[2].y,
			transmute(u64)command.radii.x, transmute(u64)command.radii.y,
			transmute(u64)command.rotation, command.large_arc ? 1 : 0, command.sweep ? 1 : 0,
			}
		}
		bytes := mem.slice_to_bytes(storage[:count])
		if len(commands) <= len(storage) { return transmute([2]u64)xxhash.XXH3_128_default(bytes) }
		_ = xxhash.XXH3_128_update(&stream, bytes)
	}
	if len(commands) == 0 { return transmute([2]u64)xxhash.XXH3_128_default(nil) }
	return transmute([2]u64)xxhash.XXH3_128_digest(&stream)
}


#+test
package oni_vector

import "core:mem"
import "core:testing"

@(test)
owned_command_fingerprint_matches_source_without_mutating_it :: proc(t: ^testing.T) {
	source: [130]Command
	mem.set(raw_data(mem.slice_to_bytes(source[:])), 0xa5, size_of(source))
	for &command, i in source {
		command.kind = .Cubic
		command.points = {{f64(i), 2}, {3, 4}, {5, 6}}
		command.radii, command.rotation = {7, 8}, 9
		command.large_arc, command.sweep = i % 2 == 0, i % 3 == 0
	}
	source[0].kind = .Move
	before := make([]byte, size_of(source))
	defer delete(before)
	copy(before, mem.slice_to_bytes(source[:]))
	for count in ([8]int{0, 1, 2, 3, 40, 64, 65, 130}) {
		owned := make([]Command, count)
		defer delete(owned)
		copy(owned, source[:count])
		owned_structure, source_structure: [2]u64
		hash := commands_owned_hash(owned, &owned_structure)
		testing.expect_value(t, hash, Commands_Hash(source[:count], &source_structure))
		testing.expect_value(t, hash, Commands_Hash(owned))
		testing.expect_value(t, owned_structure, source_structure)
	}
	for value, i in before { testing.expect_value(t, mem.slice_to_bytes(source[:])[i], value) }
}

@(test)
command_hash_excludes_padding_and_covers_every_field :: proc(t: ^testing.T) {
	a, b: [65]Command
	mem.set(raw_data(mem.slice_to_bytes(a[:])), 0xa5, size_of(a))
	for &command in a {
		command.kind = .Cubic
		command.points = {{1, 2}, {3, 4}, {5, 6}}
		command.radii, command.rotation = {7, 8}, 9
		command.large_arc, command.sweep = false, true
	}
	for &command in b {
		command.kind = .Cubic
		command.points = {{1, 2}, {3, 4}, {5, 6}}
		command.radii, command.rotation = {7, 8}, 9
		command.large_arc, command.sweep = false, true
	}
	for count in ([5]int{0, 1, 40, 64, 65}) {
		testing.expect_value(t, Commands_Hash(a[:count]), Commands_Hash(b[:count]))
	}
	baseline := Commands_Hash(b[:])
	for field in 0 ..< 12 {
		saved := b[64]
		switch field {
		case 0: b[64].kind = .Line
		case 1, 2, 3, 4, 5, 6: b[64].points[(field - 1) / 2][(field - 1) % 2] += 1
		case 7, 8: b[64].radii[field - 7] += 1
		case 9: b[64].rotation += 1
		case 10: b[64].large_arc = true
		case 11: b[64].sweep = false
		}
		testing.expect(t, Commands_Hash(b[:]) != baseline)
		b[64] = saved
	}
}

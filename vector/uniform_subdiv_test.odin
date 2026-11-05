#+test
package oni_vector

import "core:testing"

@(test)
uniform_subdivision_changes_flatten_count :: proc(t: ^testing.T) {
	commands := make([dynamic]Command)
	defer delete(commands)
	append(&commands, Command{kind = .Move, points = {{0, 0}, {}, {}}})
	append(&commands, Command{kind = .Cubic, points = {{10, 20}, {20, -20}, {30, 0}}})
	append(&commands, Command{kind = .Close})
	limits := DEFAULT_LIMITS
	flat0, e0 := Flatten(commands[:], IDENTITY, limits)
	testing.expect_value(t, e0, Error.None)
	defer Destroy_Flat_Path(&flat0)
	limits.uniform_subdivision = 2
	flat1, e1 := Flatten(commands[:], IDENTITY, limits)
	testing.expect_value(t, e1, Error.None)
	defer Destroy_Flat_Path(&flat1)
	testing.expectf(t, len(flat1.points) != len(flat0.points), "adaptive=%d uniform=%d", len(flat0.points), len(flat1.points))
}

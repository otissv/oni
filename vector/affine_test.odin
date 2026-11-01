#+test
package oni_vector

import "core:testing"

@(test)
commands_affine_detects_uniform_scale_about_a_centre :: proc(t: ^testing.T) {
	old_commands := [4]Command{
		{kind = .Move, points = {{2, 2}, {}, {}}},
		{kind = .Cubic, points = {{3, 2}, {4, 3}, {4, 4}}},
		{kind = .Cubic, points = {{4, 5}, {3, 6}, {2, 6}}},
		{kind = .Close},
	}
	centre := Point{2, 4}
	factor := 1.25
	new_commands := old_commands
	for &command, command_index in new_commands {
		count := command.kind == .Cubic ? 3 : (command.kind == .Move ? 1 : 0)
		for point_index in 0 ..< count {
			command.points[point_index] = centre + (old_commands[command_index].points[point_index] - centre) * factor
		}
	}
	affine, ok := Commands_Affine(old_commands[:], new_commands[:])
	testing.expect(t, ok)
	testing.expect_value(t, affine[0], factor)
	testing.expect_value(t, affine[3], factor)
	mapped := Transform_Point(affine, old_commands[1].points[2])
	testing.expect_value(t, mapped, new_commands[1].points[2])
}

@(test)
commands_affine_rejects_non_affine_control_point_edits :: proc(t: ^testing.T) {
	old_commands := [5]Command{
		{kind = .Move, points = {{0, 0}, {}, {}}},
		{kind = .Line, points = {{10, 0}, {}, {}}},
		{kind = .Line, points = {{10, 10}, {}, {}}},
		{kind = .Line, points = {{0, 10}, {}, {}}},
		{kind = .Close},
	}
	new_commands := old_commands
	new_commands[1].points[0] = {20, 0}
	_, ok := Commands_Affine(old_commands[:], new_commands[:])
	testing.expect(t, !ok)
}

@(test)
affine_compose_and_invert_round_trip_points :: proc(t: ^testing.T) {
	a := Affine{1.5, 0.25, -0.5, 2, 3, -4}
	inverse, ok := Affine_Invert(a)
	testing.expect(t, ok)
	identity := Affine_Compose(a, inverse)
	point := Point{7, -2}
	mapped := Transform_Point(identity, point)
	testing.expect(t, abs(mapped.x - point.x) < 1e-9)
	testing.expect(t, abs(mapped.y - point.y) < 1e-9)
}

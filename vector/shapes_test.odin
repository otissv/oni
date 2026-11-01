#+test
package oni_vector

import "core:testing"

@(test)
shape_helpers_build_closed_fills_and_conservative_bounds :: proc(t: ^testing.T) {
	path: Path
	defer Destroy_Path(&path)
	testing.expect_value(t, Rectangle(&path, {2, 3}, {10, 20}, {2, 3}), Error.None)
	testing.expect_value(t, Ellipse(&path, {30, 30}, {5, 10}), Error.None)
	mesh, err := Tessellate(path.commands[:], IDENTITY, .Nonzero)
	defer Destroy_Mesh(&mesh)
	testing.expect_value(t, err, Error.None)
	testing.expect(t, test_area(mesh) > 330 && test_area(mesh) < 360)
	bounds, bounds_error := Path_Bounds(path.commands[:], IDENTITY)
	testing.expect_value(t, bounds_error, Error.None)
	testing.expect(t, !bounds.empty && bounds.min.x <= 2 && bounds.min.y <= 3 && bounds.max.x >= 35 && bounds.max.y >= 40)
	before := len(path.commands)
	testing.expect_value(t, Ellipse(&path, {0, 0}, {-1, 1}), Error.Invalid_Value)
	testing.expect_value(t, len(path.commands), before)
}

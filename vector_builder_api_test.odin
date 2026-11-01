#+test
package oni

import "core:testing"

@(test)
vector_public_builder_supports_curves_arcs_and_shapes_with_owned_cleanup :: proc(t: ^testing.T) {
	path: Vector_Path
	defer Vector_Destroy_Path_Data(&path)
	testing.expect_value(t, Vector_Move_To(&path, {0, 0}), Vector_Path_Error.None)
	testing.expect_value(t, Vector_Line_To(&path, {5, 0}), Vector_Path_Error.None)
	testing.expect_value(t, Vector_Quadratic_To(&path, {8, 2}, {5, 5}), Vector_Path_Error.None)
	testing.expect_value(t, Vector_Cubic_To(&path, {3, 8}, {0, 8}, {0, 5}), Vector_Path_Error.None)
	testing.expect_value(t, Vector_Arc_To(&path, {2, 2}, 0, false, true, {0, 0}), Vector_Path_Error.None)
	testing.expect_value(t, Vector_Close(&path), Vector_Path_Error.None)
	testing.expect_value(t, Vector_Rectangle(&path, {10, 10}, {5, 5}, {1, 1}), Vector_Path_Error.None)
	testing.expect_value(t, Vector_Circle(&path, {20, 20}, 2), Vector_Path_Error.None)
	testing.expect_value(t, Vector_Ellipse(&path, {30, 20}, {3, 2}), Vector_Path_Error.None)
	testing.expect_value(t, Vector_Polyline(&path, []Vector_Point{{40, 0}, {45, 4}}, false), Vector_Path_Error.None)
	bounds, err := Vector_Geometry_Bounds(path.commands[:])
	testing.expect_value(t, err, Vector_Path_Error.None)
	testing.expect_value(t, bounds.max.x, f64(45))
}

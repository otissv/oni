#+test
package oni_vector

import "core:math"
import "core:testing"

@(test)
review_odd_dash_offset :: proc(t: ^testing.T) {
	path := stroke_line()
	defer Destroy_Path(&path)
	mesh, err := Tessellate_Stroke(
		path.commands[:],
		IDENTITY,
		{width = 4, miter_limit = 4, dash = []f64{10}, dash_offset = 15},
	)
	defer Destroy_Mesh(&mesh)
	testing.expect_value(t, err, Error.None)
	testing.expect(t, !stroke_covers_point(mesh, {1, 0}), "odd dash [10] repeats as [10,10]: offset 15 starts in a gap")
}

@(test)
review_path_length_multiple_subpaths :: proc(t: ^testing.T) {
	path := stroke_line()
	defer Destroy_Path(&path)
	_ = Move_To(&path, {0, 20})
	_ = Line_To(&path, {100, 20})
	mesh, err := Tessellate_Stroke(
		path.commands[:],
		IDENTITY,
		{width = 4, miter_limit = 4, dash = []f64{25, 25}, path_length = 100},
	)
	defer Destroy_Mesh(&mesh)
	testing.expect_value(t, err, Error.None)
	testing.expect(t, stroke_covers_point(mesh, {40, 0}), "total length 200 / pathLength 100 makes first dash 50 units long")
}

@(test)
review_wrapped_dash_stays_open :: proc(t: ^testing.T) {
	path: Path
	defer Destroy_Path(&path)
	_ = Rectangle(&path, {0, 0}, {40, 40})
	mesh, err := Tessellate_Stroke(
		path.commands[:],
		IDENTITY,
		{width = 4, miter_limit = 4, dash = []f64{30, 20}},
	)
	defer Destroy_Mesh(&mesh)
	testing.expect_value(t, err, Error.None)
	testing.expect(t, !stroke_covers_point(mesh, {15, 5}), "seam-wrapped dash must not gain a diagonal closing segment")
}

@(test)
review_scaled_round_cap_tolerance :: proc(t: ^testing.T) {
	path := stroke_line()
	defer Destroy_Path(&path)
	mesh, err := Tessellate_Stroke(
		path.commands[:],
		{100, 0, 0, 100, 0, 0},
		{width = 10, cap = .Round, miter_limit = 4},
	)
	defer Destroy_Mesh(&mesh)
	testing.expect_value(t, err, Error.None)
	angle := -math.PI / 2 - math.PI / 16
	testing.expect(
		t,
		stroke_covers_point(mesh, {math.cos(angle) * 499.5, math.sin(angle) * 499.5}),
		"point half a pixel inside exact cap is missing; error exceeds 0.25px",
	)
}

@(test)
review_dash_expansion_respects_limits :: proc(t: ^testing.T) {
	path := stroke_line()
	defer Destroy_Path(&path)
	limits := DEFAULT_LIMITS
	limits.max_commands = 16
	limits.max_flattened_segments = 16
	outline: Path
	defer Destroy_Path(&outline)
	err := stroke_build_outline(
		&outline,
		path.commands[:],
		IDENTITY,
		{width = 1, miter_limit = 4, dash = []f64{0.5, 0.5}},
		limits,
	)
	testing.expectf(
		t,
		err == .Limit_Exceeded,
		"outline expanded to %v commands despite 16-command/segment limits, err=%v",
		len(outline.commands),
		err,
	)
}

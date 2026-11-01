#+test
package oni_vector

import "core:testing"

@(test)
audit_outer_miter :: proc(t: ^testing.T) {
	path: Path
	defer Destroy_Path(&path)
	_ = Move_To(&path, {0, 0})
	_ = Line_To(&path, {40, 0})
	_ = Line_To(&path, {40, 40})
	mesh, err := Tessellate_Stroke(path.commands[:], IDENTITY, {width = 10, join = .Miter, miter_limit = 4})
	defer Destroy_Mesh(&mesh)
	testing.expect_value(t, err, Error.None)
	testing.expect(t, stroke_covers_point(mesh, {44, -4}), "outer miter corner is missing")
}

@(test)
audit_path_length_offset :: proc(t: ^testing.T) {
	path := stroke_line()
	defer Destroy_Path(&path)
	mesh, err := Tessellate_Stroke(
		path.commands[:],
		IDENTITY,
		{width = 4, miter_limit = 4, dash = []f64{25, 25}, path_length = 50, dash_offset = 10},
	)
	defer Destroy_Mesh(&mesh)
	testing.expect_value(t, err, Error.None)
	testing.expect(t, !stroke_covers_point(mesh, {35, 0}), "offset 10 in pathLength units should end first dash at x=30")
}

@(test)
audit_closed_dash_seam :: proc(t: ^testing.T) {
	path: Path
	defer Destroy_Path(&path)
	_ = Rectangle(&path, {0, 0}, {40, 40})
	mesh, err := Tessellate_Stroke(path.commands[:], IDENTITY, {width = 10, miter_limit = 4, dash = []f64{1000, 1}})
	defer Destroy_Mesh(&mesh)
	testing.expect_value(t, err, Error.None)
	testing.expect(t, stroke_covers_point(mesh, {-4, -4}), "continuous dash across seam requires a join")
}

@(test)
audit_zero_dash_is_solid :: proc(t: ^testing.T) {
	path := stroke_line()
	defer Destroy_Path(&path)
	mesh, err := Tessellate_Stroke(path.commands[:], IDENTITY, {width = 4, miter_limit = 4, dash = []f64{0, 0}})
	defer Destroy_Mesh(&mesh)
	testing.expect_value(t, err, Error.None)
	testing.expect(t, stroke_covers_point(mesh, {50, 0}), "zero-sum dash array must render solid")
}

@(test)
stroke_scaled_cubic_stays_within_device_tolerance :: proc(t: ^testing.T) {
	path: Path
	defer Destroy_Path(&path)
	_ = Move_To(&path, {0, 0})
	_ = Cubic_To(&path, {10, 20}, {20, -20}, {30, 0})
	transform := Affine{4, 0, 0, 4, 0, 0}
	style := Stroke{width = 1, cap = .Round, join = .Round, miter_limit = 4}
	mesh, err := Tessellate_Stroke(path.commands[:], transform, style)
	defer Destroy_Mesh(&mesh)
	testing.expect_value(t, err, Error.None)

	// Sample the exact transformed cubic and require coverage within 0.25 + half-width.
	half := style.width * stroke_linear_scale(transform) * 0.5
	for sample in 0 ..< 51 {
		time := f64(sample) / 50
		u := 1 - time
		point := Point{
			(u * u * u) * 0 + 3 * (u * u) * time * 10 + 3 * u * (time * time) * 20 + (time * time * time) * 30,
			(u * u * u) * 0 + 3 * (u * u) * time * 20 + 3 * u * (time * time) * (-20) + (time * time * time) * 0,
		}
		device := Transform_Point(transform, point)
		nearest := f64(1e20)
		for i := 0; i < len(mesh.indices); i += 3 {
			a := mesh.vertices[mesh.indices[i]]
			b := mesh.vertices[mesh.indices[i + 1]]
			c := mesh.vertices[mesh.indices[i + 2]]
			centroid := Point{
				(f64(a.x) + f64(b.x) + f64(c.x)) / 3,
				(f64(a.y) + f64(b.y) + f64(c.y)) / 3,
			}
			nearest = min(nearest, stroke_len(device - centroid))
		}
		testing.expectf(t, nearest <= half + 0.25 + 0.05, "device error=%v half=%v t=%v", nearest, half, time)
	}
}

@(test)
stroke_round_join_covers_outer_corner :: proc(t: ^testing.T) {
	path: Path
	defer Destroy_Path(&path)
	_ = Move_To(&path, {0, 0})
	_ = Line_To(&path, {40, 0})
	_ = Line_To(&path, {40, 40})
	mesh, err := Tessellate_Stroke(path.commands[:], IDENTITY, {width = 10, join = .Round, miter_limit = 4})
	defer Destroy_Mesh(&mesh)
	testing.expect_value(t, err, Error.None)
	testing.expect(t, stroke_covers_point(mesh, {44, -2}), "outer round join corner is missing")
}

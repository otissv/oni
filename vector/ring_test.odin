#+test
package oni_vector

import "core:math"
import "core:testing"

@(private)
ring_test_winding :: proc(flat: Flat_Path, p: Point) -> (winding: int) {
	for contour in flat.contours {
		for i in 0 ..< contour.count {
			a := flat.points[contour.first + i]
			b := flat.points[contour.first + (i + 1) % contour.count]
			cross := (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)
			if a.y <= p.y && b.y > p.y && cross > 0 { winding += 1 }
			if a.y > p.y && b.y <= p.y && cross < 0 { winding -= 1 }
		}
	}
	return
}

@(test)
ring_morph_keeps_source_slots_for_reversed_hole_winding :: proc(t: ^testing.T) {
	path: Path
	defer Destroy_Path(&path)
	_ = Polyline(&path, []Point{{-10, -10}, {10, -10}, {10, 10}, {-10, 10}}, true)
	_ = Polyline(&path, []Point{{-3, -3}, {-3, 3}, {3, 3}, {3, -3}}, true)
	limits := DEFAULT_LIMITS
	limits.uniform_subdivision = -1
	mesh: Mesh
	defer Destroy_Mesh(&mesh)
	testing.expect_value(t, Tessellate_Into(&mesh, path.commands[:], IDENTITY, .Nonzero, limits), Error.None)
	testing.expect(t, mesh.contour_slots)
	testing.expect_value(t, mesh.vertices[4], [2]f32{-3, -3})
	testing.expect_value(t, mesh.vertices[5], [2]f32{-3, 3})
	for &command in path.commands {
		if command.kind == .Move || command.kind == .Line { command.points[0] += {1, 2} }
	}
	usage: Build_Usage
	testing.expect_value(t, Tessellate_Into(&mesh, path.commands[:], IDENTITY, .Nonzero, limits, usage = &usage), Error.None)
	testing.expect(t, usage.stable_remesh)
	testing.expect(t, !stroke_covers_point(mesh, {1, 2}))
	testing.expect(t, stroke_covers_point(mesh, {8, 2}))
}

@(test)
ring_fast_path_handles_star_shaped_nonconvex_hole :: proc(t: ^testing.T) {
	path: Path
	defer Destroy_Path(&path)
	for radius in ([2]f64{20, 7}) {
		points: [16]Point
		for &p, i in points {
			angle := f64(i) * math.TAU / 16
			r := radius * (1 + .3 * math.cos(3 * angle))
			p = {r * math.cos(angle), r * math.sin(angle)}
		}
		_ = Polyline(&path, points[:], true)
	}
	flat, flatten_error := Flatten(path.commands[:], IDENTITY)
	defer Destroy_Flat_Path(&flat)
	testing.expect_value(t, flatten_error, Error.None)
	mesh: Mesh
	defer Destroy_Mesh(&mesh)
	work := Exact_Work{allowed = DEFAULT_LIMITS.max_exact_ops, width = 4096}
	pairs := 0
	handled, err := ring_mesh(flat, &mesh, .Even_Odd, DEFAULT_LIMITS, &pairs, &work)
	testing.expect(t, handled)
	testing.expect_value(t, err, Error.None)
	testing.expect(t, !stroke_covers_point(mesh, {}))
	testing.expect(t, stroke_covers_point(mesh, {15, 0}))
	for y in -24 ..= 24 {
		for x in -24 ..= 24 {
			point := Point{f64(x) + .317, f64(y) + .271}
			winding := ring_test_winding(flat, point)
			testing.expect(t, stroke_covers_point(mesh, point) == (winding & 1 != 0))
		}
	}
}

@(test)
ring_fast_path_handles_nested_convex_contours_without_sweep :: proc(t: ^testing.T) {
	path: Path
	defer Destroy_Path(&path)
	_ = Ellipse(&path, {0, 0}, {20, 15})
	_ = Ellipse(&path, {0, 0}, {8, 5})
	flat, flatten_error := Flatten(path.commands[:], IDENTITY)
	defer Destroy_Flat_Path(&flat)
	testing.expect_value(t, flatten_error, Error.None)
	mesh: Mesh
	defer Destroy_Mesh(&mesh)
	work := Exact_Work{allowed = DEFAULT_LIMITS.max_exact_ops, width = 4096}
	pairs := 0
	handled, err := ring_mesh(flat, &mesh, .Even_Odd, DEFAULT_LIMITS, &pairs, &work)
	testing.expect(t, handled)
	testing.expect_value(t, err, Error.None)
	testing.expect(t, len(mesh.indices) > 0)
	testing.expect(t, !stroke_covers_point(mesh, {}))
}

@(test)
ring_fast_path_matches_winding_under_shear_reflection_and_offset_holes :: proc(t: ^testing.T) {
	for offset in ([3]Point{{0, 0}, {2, 1}, {-3, -1}}) {
		for transform in ([3]Affine{IDENTITY, {1.2, .3, .7, .8, 0, 0}, {-1.3, .2, .5, 1.1, 0, 0}}) {
			path: Path
			_ = Ellipse(&path, {0, 0}, {20, 15})
			_ = Ellipse(&path, offset, {8, 5})
			mesh, err := Tessellate(path.commands[:], transform, .Even_Odd)
			testing.expect_value(t, err, Error.None)
			for y in -18 ..= 18 {
				for x in -23 ..= 23 {
					point := Point{f64(x) + .37, f64(y) + .23}
					outer := point.x * point.x / 400 + point.y * point.y / 225
					inner := (point.x - offset.x) * (point.x - offset.x) / 64 + (point.y - offset.y) * (point.y - offset.y) / 25
					if math.abs(outer - 1) < .08 || math.abs(inner - 1) < .15 { continue }
					testing.expect_value(t, stroke_covers_point(mesh, Transform_Point(transform, point)), outer < 1 && inner > 1)
				}
			}
			Destroy_Mesh(&mesh)
			Destroy_Path(&path)
		}
	}
}

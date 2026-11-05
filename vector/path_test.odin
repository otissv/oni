#+test
package oni_vector

import "core:math"
import "core:testing"

@(private)
test_area :: proc(mesh: Mesh) -> (area: f64) {
	for i := 0; i < len(mesh.indices); i += 3 {
		a := mesh.vertices[mesh.indices[i]]
		b := mesh.vertices[mesh.indices[i + 1]]
		c := mesh.vertices[mesh.indices[i + 2]]
		area += abs(f64(b.x - a.x) * f64(c.y - a.y) - f64(b.y - a.y) * f64(c.x - a.x)) * 0.5
	}
	return
}

@(private)
test_square :: proc(path: ^Path, x, y, size: f64, reverse: bool) {
	_ = Move_To(path, {x, y})
	if reverse {
		_ = Line_To(path, {x, y + size})
		_ = Line_To(path, {x + size, y + size})
		_ = Line_To(path, {x + size, y})
	} else {
		_ = Line_To(path, {x + size, y})
		_ = Line_To(path, {x + size, y + size})
		_ = Line_To(path, {x, y + size})
	}
	_ = Close(path)
}

@(test)
fill_rules_resolve_holes_and_coincident_contours :: proc(t: ^testing.T) {
	for reverse in ([2]bool{false, true}) {
		path: Path
		defer Destroy_Path(&path)
		test_square(&path, 0, 0, 10, false)
		test_square(&path, 2, 2, 6, reverse)
		for rule in Fill_Rule {
			mesh, err := Tessellate(path.commands[:], IDENTITY, rule)
			defer Destroy_Mesh(&mesh)
			testing.expect_value(t, err, Error.None)
			wanted := f64(100)
			if reverse || rule == .Even_Odd {
				wanted = 64
			}
			testing.expectf(t, abs(test_area(mesh) - wanted) < 0.001, "area=%v wanted=%v", test_area(mesh), wanted)
		}
	}
	path: Path
	defer Destroy_Path(&path)
	test_square(&path, 0, 0, 10, false)
	test_square(&path, 0, 0, 10, true)
	mesh, err := Tessellate(path.commands[:], IDENTITY, .Nonzero)
	defer Destroy_Mesh(&mesh)
	testing.expect_value(t, err, Error.None)
	testing.expect_value(t, test_area(mesh), f64(0))
}

@(test)
fill_self_intersection_is_split_without_double_coverage :: proc(t: ^testing.T) {
	path: Path
	defer Destroy_Path(&path)
	_ = Move_To(&path, {0, 0})
	_ = Line_To(&path, {10, 10})
	_ = Line_To(&path, {0, 10})
	_ = Line_To(&path, {10, 0})
	_ = Close(&path)
	mesh, err := Tessellate(path.commands[:], IDENTITY, .Even_Odd)
	defer Destroy_Mesh(&mesh)
	testing.expect_value(t, err, Error.None)
	testing.expectf(t, abs(test_area(mesh) - 50) < 0.001, "area=%v", test_area(mesh))
}

@(test)
flatten_cubic_preserves_collinear_reversal_and_bounds_work :: proc(t: ^testing.T) {
	path: Path
	defer Destroy_Path(&path)
	_ = Move_To(&path, {0, 0})
	_ = Cubic_To(&path, {100, 0}, {-100, 0}, {1, 0})
	flat, err := Flatten(path.commands[:], IDENTITY)
	defer Destroy_Flat_Path(&flat)
	testing.expect_value(t, err, Error.None)
	testing.expect(t, len(flat.points) > 4)
	limits := DEFAULT_LIMITS
	limits.max_flattened_segments = 2
	limited, limited_error := Flatten(path.commands[:], IDENTITY, limits)
	defer Destroy_Flat_Path(&limited)
	testing.expect_value(t, limited_error, Error.Limit_Exceeded)
	testing.expect_value(t, len(limited.points), 0)
}

@(test)
flatten_quadratic_meets_device_space_error_under_shear :: proc(t: ^testing.T) {
	path: Path
	defer Destroy_Path(&path)
	_ = Move_To(&path, {0, 0})
	_ = Quadratic_To(&path, {50, 100}, {100, 0})
	transform := Affine{2, 0.5, 0.75, 3, 0, 0}
	flat, err := Flatten(path.commands[:], transform)
	defer Destroy_Flat_Path(&flat)
	testing.expect_value(t, err, Error.None)
	for sample in 0 ..< 1001 {
		time := f64(sample) / 1000
		point := Transform_Point(transform, Point{100 * time, 200 * time * (1 - time)})
		distance := f64(1e20)
		for i in 1 ..< len(flat.points) {
			distance = min(distance, point_segment_distance(point, flat.points[i - 1], flat.points[i]))
		}
		testing.expectf(t, distance <= 0.252, "device-space error=%v", distance)
	}
}

@(test)
path_rejects_nonfinite_values_and_invalid_command_order :: proc(t: ^testing.T) {
	path: Path
	defer Destroy_Path(&path)
	testing.expect_value(t, Line_To(&path, {1, 2}), Error.Invalid_Path)
	testing.expect_value(t, Move_To(&path, {math.nan_f64(), 2}), Error.Invalid_Value)
	testing.expect_value(t, len(path.commands), 0)
}

@(test)
rational_comparison_uses_exact_fallback_without_overflow :: proc(t: ^testing.T) {
	a := Rational{num = (i128(1) << 100) + 1, den = i128(1) << 90}
	b := Rational{num = i128(1) << 100, den = i128(1) << 90}
	order, err := rational_compare(a, b)
	testing.expect_value(t, err, Error.None)
	testing.expect(t, order > 0)
}

@(test)
closed_cubic_does_not_duplicate_its_existing_endpoint :: proc(t: ^testing.T) {
	path: Path
	defer Destroy_Path(&path)
	_ = Move_To(&path, {0, 0})
	_ = Cubic_To(&path, {12, 0}, {12, 12}, {0, 0})
	_ = Close(&path)
	flat, err := Flatten(path.commands[:], IDENTITY)
	defer Destroy_Flat_Path(&flat)
	testing.expect_value(t, err, Error.None)
	testing.expect(t, flat.points[len(flat.points) - 2] != flat.points[len(flat.points) - 1])
}

@(test)
self_intersecting_star_is_not_classified_as_a_convex_polygon :: proc(t: ^testing.T) {
	path: Path
	defer Destroy_Path(&path)
	points := [5]Point{{0, -10}, {5.878, 8.09}, {-9.51, -3.09}, {9.51, -3.09}, {-5.878, 8.09}}
	_ = Move_To(&path, points[0])
	for point in points[1:] {
		_ = Line_To(&path, point)
	}
	_ = Close(&path)
	flat, err := Flatten(path.commands[:], IDENTITY)
	defer Destroy_Flat_Path(&flat)
	testing.expect_value(t, err, Error.None)
	mesh: Mesh
	defer Destroy_Mesh(&mesh)
	convex, convex_error := convex_mesh(flat, &mesh, DEFAULT_LIMITS, nil)
	testing.expect_value(t, convex_error, Error.None)
	testing.expect(t, !convex)
	for rule in Fill_Rule {
		filled, fill_error := Tessellate(path.commands[:], IDENTITY, rule)
		defer Destroy_Mesh(&filled)
		testing.expect_value(t, fill_error, Error.None)
		testing.expect(t, len(filled.indices) > 0)
	}
}

@(test)
close_then_continue_starts_a_new_contour :: proc(t: ^testing.T) {
	path: Path
	defer Destroy_Path(&path)
	test_square(&path, 0, 0, 10, false)
	_ = Line_To(&path, {-10, 0})
	_ = Line_To(&path, {0, -10})
	mesh, err := Tessellate(path.commands[:], IDENTITY, .Nonzero)
	defer Destroy_Mesh(&mesh)
	testing.expect_value(t, err, Error.None)
	testing.expect_value(t, test_area(mesh), f64(150))
	flat, flatten_error := Flatten(path.commands[:], IDENTITY)
	defer Destroy_Flat_Path(&flat)
	testing.expect_value(t, flatten_error, Error.None)
	testing.expect_value(t, len(flat.contours), 2)
}

@(test)
flatten_rejects_out_of_range_controls_before_subdivision :: proc(t: ^testing.T) {
	commands := [2]Command{
		{kind = .Move},
		{kind = .Cubic, points = {{1e300, 1e300}, {-1e300, -1e300}, {1, 1}}},
	}
	flat, err := Flatten(commands[:], IDENTITY)
	defer Destroy_Flat_Path(&flat)
	testing.expect_value(t, err, Error.Invalid_Value)
}

@(test)
fill_degenerate_and_reflected_contours_preserve_coverage :: proc(t: ^testing.T) {
	path: Path
	defer Destroy_Path(&path)
	test_square(&path, 0, 0, 10, false)
	_ = Move_To(&path, {10, 10})
	_ = Line_To(&path, {10, 10})
	_ = Line_To(&path, {20, 20})
	_ = Line_To(&path, {10, 10})
	for rule in Fill_Rule {
		for transform in ([3]Affine{IDENTITY, {-1, 0, 0.5, 1, 0, 0}, {1, 0, 1, 0, 0, 0}}) {
			mesh, err := Tessellate(path.commands[:], transform, rule)
			defer Destroy_Mesh(&mesh)
			testing.expect_value(t, err, Error.None)
			wanted := transform[3] == 0 ? f64(0) : f64(100)
			testing.expect_value(t, test_area(mesh), wanted)
		}
	}
}

@(test)
fill_nearly_parallel_extreme_edges_and_tangent_contours :: proc(t: ^testing.T) {
	path: Path
	defer Destroy_Path(&path)
	m := f64(1 << 20)
	_ = Move_To(&path, {-m, -m})
	_ = Line_To(&path, {m, m - 1})
	_ = Line_To(&path, {-m, m})
	_ = Line_To(&path, {m, -m + 1})
	_ = Close(&path)
	for rule in Fill_Rule {
		mesh, err := Tessellate(path.commands[:], IDENTITY, rule)
		defer Destroy_Mesh(&mesh)
		testing.expect_value(t, err, Error.None)
		testing.expect(t, test_area(mesh) > 0)
		for point in mesh.vertices {
			testing.expect(t, finite(f64(point.x)) && finite(f64(point.y)))
		}
	}
	Destroy_Path(&path)
	test_square(&path, 0, 0, 10, false)
	test_square(&path, 10, 10, 10, true)
	mesh, err := Tessellate(path.commands[:], IDENTITY, .Nonzero)
	defer Destroy_Mesh(&mesh)
	testing.expect_value(t, err, Error.None)
	testing.expect_value(t, test_area(mesh), f64(200))
}

@(test)
mesh_memory_and_work_limits_fail_without_partial_geometry :: proc(t: ^testing.T) {
	path: Path
	defer Destroy_Path(&path)
	test_square(&path, 0, 0, 10, false)
	limits := DEFAULT_LIMITS
	limits.max_mesh_bytes = 1
	mesh, err := Tessellate(path.commands[:], IDENTITY, .Nonzero, limits)
	defer Destroy_Mesh(&mesh)
	testing.expect_value(t, err, Error.Mesh_Memory_Limit)
	testing.expect_value(t, len(mesh.indices), 0)
	testing.expect_value(t, cap(mesh.vertices), 0)
}

@(test)
elliptical_arcs_meet_error_after_shear_and_reflection :: proc(t: ^testing.T) {
	path: Path
	defer Destroy_Path(&path)
	_ = Ellipse(&path, {0, 0}, {30, 10})
	transform := Affine{-3, 0.7, 2, 4, 0, 0}
	flat, err := Flatten(path.commands[:], transform)
	defer Destroy_Flat_Path(&flat)
	testing.expect_value(t, err, Error.None)
	for sample in 0 ..< 2000 {
		a := f64(sample) * 2 * math.PI / 2000
		point := Transform_Point(transform, {30 * math.cos(a), 10 * math.sin(a)})
		distance := f64(1e20)
		for i in 1 ..< len(flat.points) {
			distance = min(distance, point_segment_distance(point, flat.points[i - 1], flat.points[i]))
		}
		testing.expectf(t, distance <= 0.25, "arc device-space error %v", distance)
	}
}

@(test)
arrangement_matches_winding_and_never_overlaps_triangle_interiors :: proc(t: ^testing.T) {
	path: Path
	defer Destroy_Path(&path)
	_ = Polyline(&path, []Point{{0, -10}, {5.878, 8.09}, {-9.51, -3.09}, {9.51, -3.09}, {-5.878, 8.09}}, true)
	test_square(&path, -3, -3, 6, false)
	flat, flatten_error := Flatten(path.commands[:], IDENTITY)
	defer Destroy_Flat_Path(&flat)
	testing.expect_value(t, flatten_error, Error.None)
	for rule in Fill_Rule {
		mesh, err := Tessellate(path.commands[:], IDENTITY, rule)
		defer Destroy_Mesh(&mesh)
		testing.expect_value(t, err, Error.None)
		for y in -40 ..< 40 {
			for x in -40 ..< 40 {
				p := Point{f64(x) * 0.25 + 0.0371, f64(y) * 0.25 + 0.0713}
				winding := 0
				for contour in flat.contours {
					for i in 0 ..< contour.count {
						a := flat.points[contour.first + i]
						b := flat.points[contour.first + (i + 1) % contour.count]
						cross := (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)
						if a.y <= p.y && b.y > p.y && cross > 0 { winding += 1 }
						if a.y > p.y && b.y <= p.y && cross < 0 { winding -= 1 }
					}
				}
				hits := 0
				boundary := false
				for i := 0; i < len(mesh.indices); i += 3 {
					positive, negative := false, false
					for j in 0 ..< 3 {
						af := mesh.vertices[mesh.indices[i + j]]
						bf := mesh.vertices[mesh.indices[i + (j + 1) % 3]]
						a, b := Point{f64(af.x), f64(af.y)}, Point{f64(bf.x), f64(bf.y)}
						cross := (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)
						positive ||= cross > 0
						negative ||= cross < 0
						boundary ||= abs(cross) < 1e-5
					}
					hits += int(!(positive && negative))
				}
				if !boundary {
					expected := rule == .Nonzero ? winding != 0 : winding & 1 != 0
					testing.expectf(t, hits == int(expected), "rule %v point %v hits %v winding %v", rule, p, hits, winding)
				}
			}
		}
	}
}

@(test)
tessellate_into_reuses_capacity_for_stable_topology :: proc(t: ^testing.T) {
	path: Path
	defer Destroy_Path(&path)
	test_square(&path, 0, 0, 10, false)
	mesh: Mesh
	defer Destroy_Mesh(&mesh)
	testing.expect_value(t, Tessellate_Into(&mesh, path.commands[:], IDENTITY, .Nonzero), Error.None)
	vertices, indices := cap(mesh.vertices), cap(mesh.indices)
	for _ in 0 ..< 100 {
		testing.expect_value(t, Tessellate_Into(&mesh, path.commands[:], IDENTITY, .Nonzero), Error.None)
		testing.expect_value(t, cap(mesh.vertices), vertices)
		testing.expect_value(t, cap(mesh.indices), indices)
	}
}

@(test)
simple_concave_polygon_has_exact_area_without_overlapping_fans :: proc(t: ^testing.T) {
	path: Path
	defer Destroy_Path(&path)
	_ = Polyline(&path, []Point{{0, 0}, {10, 0}, {10, 4}, {4, 4}, {4, 10}, {0, 10}}, true)
	for rule in Fill_Rule {
		mesh, err := Tessellate(path.commands[:], IDENTITY, rule)
		defer Destroy_Mesh(&mesh)
		testing.expect_value(t, err, Error.None)
		testing.expect_value(t, test_area(mesh), f64(64))
		testing.expect_value(t, len(mesh.indices), 12)
	}
}

@(test)
duplicate_vertices_do_not_hide_concavity_from_fast_path :: proc(t: ^testing.T) {
	path: Path
	defer Destroy_Path(&path)
	points := []Point{{10, 4}, {4, 4}, {4, 10}, {0, 10}, {0, 0}, {10, 0}}
	_ = Move_To(&path, points[0])
	for point in points { _ = Line_To(&path, point); _ = Line_To(&path, point) }
	_ = Close(&path)
	mesh, err := Tessellate(path.commands[:], IDENTITY, .Nonzero)
	defer Destroy_Mesh(&mesh)
	testing.expect_value(t, err, Error.None)
	testing.expect_value(t, test_area(mesh), f64(64))
}

@(test)
integer_cross_is_exact_across_the_narrow_predicate_boundary :: proc(t: ^testing.T) {
	for magnitude in ([4]i64{1024, 1 << 30, (1 << 30) + 1, 1 << 31}) {
		for sign in ([2]i64{-1, 1}) {
			a := Integer_Point{magnitude, sign * magnitude}
			b := Integer_Point{-magnitude, sign * magnitude}
			testing.expect_value(t, integer_cross(a, b), 2 * i128(sign) * i128(magnitude) * i128(magnitude))
		}
	}
}

@(test)
finite_classification_accepts_all_finite_ieee_classes :: proc(t: ^testing.T) {
	for bits in ([8]u64{0, 1 << 63, 1, (1 << 63) | 1, 0x0010000000000000, 0x7fefffffffffffff, 0x7ff0000000000000, 0xfff8000000000001}) {
		value := transmute(f64)bits
		testing.expect_value(t, finite(value), !math.is_nan(value) && !math.is_inf(value))
	}
}

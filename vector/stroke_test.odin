#+test
package oni_vector

import "core:math"
import "core:mem"
import "core:testing"

@(private)
stroke_area :: proc(mesh: Mesh) -> (area: f64) {
	for i := 0; i < len(mesh.indices); i += 3 {
		a := mesh.vertices[mesh.indices[i]]
		b := mesh.vertices[mesh.indices[i + 1]]
		c := mesh.vertices[mesh.indices[i + 2]]
		area += abs(f64(b.x - a.x) * f64(c.y - a.y) - f64(b.y - a.y) * f64(c.x - a.x)) * 0.5
	}

	return
}

@(private)
stroke_covers_point :: proc(mesh: Mesh, point: Point) -> bool {
	px, py := f32(point.x), f32(point.y)
	for i := 0; i < len(mesh.indices); i += 3 {
		a := mesh.vertices[mesh.indices[i]]
		b := mesh.vertices[mesh.indices[i + 1]]
		c := mesh.vertices[mesh.indices[i + 2]]
		area := (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
		if area == 0 {
			continue
		}

		w0 := ((b.x - px) * (c.y - py) - (b.y - py) * (c.x - px)) / area
		w1 := ((c.x - px) * (a.y - py) - (c.y - py) * (a.x - px)) / area
		w2 := 1 - w0 - w1
		if w0 >= -1e-4 && w1 >= -1e-4 && w2 >= -1e-4 {
			return true
		}
	}

	return false
}

@(private)
stroke_line :: proc() -> (path: Path) {
	_ = Move_To(&path, {0, 0})
	_ = Line_To(&path, {100, 0})

	return
}

@(test)
stroke_rejects_invalid_style_values :: proc(t: ^testing.T) {
	testing.expect_value(t, Validate_Stroke({width = -1, miter_limit = 4}), Error.Invalid_Value)
	testing.expect_value(t, Validate_Stroke({width = 1, miter_limit = 0}), Error.Invalid_Value)
	testing.expect_value(t, Validate_Stroke({width = 1, miter_limit = 4, dash_offset = math.nan_f64()}), Error.Invalid_Value)
	testing.expect_value(t, Validate_Stroke({width = 1, miter_limit = 4, path_length = -2}), Error.Invalid_Value)
	testing.expect_value(t, Validate_Stroke({width = 1, miter_limit = 4, dash = []f64{-1, 2}}), Error.Invalid_Value)
	testing.expect_value(t, Validate_Stroke(DEFAULT_STROKE), Error.None)
}

@(test)
stroke_butt_line_coverage_matches_width_and_length :: proc(t: ^testing.T) {
	path := stroke_line()
	defer Destroy_Path(&path)
	style := Stroke{width = 10, cap = .Butt, join = .Miter, miter_limit = 4}
	mesh, err := Tessellate_Stroke(path.commands[:], IDENTITY, style)
	defer Destroy_Mesh(&mesh)
	testing.expect_value(t, err, Error.None)
	testing.expectf(t, abs(stroke_area(mesh) - 1000) < 1.0, "area=%v", stroke_area(mesh))
	testing.expect(t, stroke_covers_point(mesh, {50, 0}))
	testing.expect(t, stroke_covers_point(mesh, {50, 4.5}))
	testing.expect(t, !stroke_covers_point(mesh, {50, 6}))
	testing.expect(t, !stroke_covers_point(mesh, {-1, 0}))
	testing.expect(t, !stroke_covers_point(mesh, {101, 0}))
}

@(test)
stroke_square_and_round_caps_extend_open_ends :: proc(t: ^testing.T) {
	path := stroke_line()
	defer Destroy_Path(&path)
	square := Stroke{width = 10, cap = .Square, join = .Miter, miter_limit = 4}
	mesh_square, err_square := Tessellate_Stroke(path.commands[:], IDENTITY, square)
	defer Destroy_Mesh(&mesh_square)
	testing.expect_value(t, err_square, Error.None)
	testing.expect(t, stroke_covers_point(mesh_square, {-4, 0}))
	testing.expect(t, stroke_covers_point(mesh_square, {104, 0}))
	testing.expectf(t, abs(stroke_area(mesh_square) - 1100) < 2.0, "square area=%v", stroke_area(mesh_square))

	round := Stroke{width = 10, cap = .Round, join = .Miter, miter_limit = 4}
	mesh_round, err_round := Tessellate_Stroke(path.commands[:], IDENTITY, round)
	defer Destroy_Mesh(&mesh_round)
	testing.expect_value(t, err_round, Error.None)
	testing.expect(t, stroke_covers_point(mesh_round, {-4, 0}))
	testing.expect(t, stroke_covers_point(mesh_round, {104, 0}))
	testing.expectf(t, stroke_area(mesh_round) > 1000 + 0.5 * math.PI * 25 - 5, "round area=%v", stroke_area(mesh_round))
}

@(test)
stroke_joins_respect_miter_limit_and_bevel_fallback :: proc(t: ^testing.T) {
	path: Path
	defer Destroy_Path(&path)
	_ = Move_To(&path, {0, 0})
	_ = Line_To(&path, {40, 0})
	_ = Line_To(&path, {40, 1})
	miter := Stroke{width = 8, cap = .Butt, join = .Miter, miter_limit = 1.1}
	mesh_bevel_like, err := Tessellate_Stroke(path.commands[:], IDENTITY, miter)
	defer Destroy_Mesh(&mesh_bevel_like)
	testing.expect_value(t, err, Error.None)
	bevel := Stroke{width = 8, cap = .Butt, join = .Bevel, miter_limit = 4}
	mesh_bevel, err_bevel := Tessellate_Stroke(path.commands[:], IDENTITY, bevel)
	defer Destroy_Mesh(&mesh_bevel)
	testing.expect_value(t, err_bevel, Error.None)
	testing.expectf(
		t,
		abs(stroke_area(mesh_bevel_like) - stroke_area(mesh_bevel)) < 2.0,
		"miter-limit area=%v bevel=%v",
		stroke_area(mesh_bevel_like),
		stroke_area(mesh_bevel),
	)

	round := Stroke{width = 8, cap = .Butt, join = .Round, miter_limit = 4}
	mesh_round, err_round := Tessellate_Stroke(path.commands[:], IDENTITY, round)
	defer Destroy_Mesh(&mesh_round)
	testing.expect_value(t, err_round, Error.None)
	testing.expect(t, stroke_covers_point(mesh_round, {40, 0}))
}

@(test)
stroke_closed_contour_seams_without_end_caps :: proc(t: ^testing.T) {
	path: Path
	defer Destroy_Path(&path)
	_ = Rectangle(&path, {0, 0}, {40, 40})
	style := Stroke{width = 4, cap = .Square, join = .Miter, miter_limit = 4}
	mesh, err := Tessellate_Stroke(path.commands[:], IDENTITY, style)
	defer Destroy_Mesh(&mesh)
	testing.expect_value(t, err, Error.None)
	// Perimeter 160 * width 4 ≈ 640, plus outer miters; must stay well below a filled square.
	// Centred stroke ring around a 40×40 square: outer/inner difference ≈ 640.
	testing.expectf(t, stroke_area(mesh) > 450 && stroke_area(mesh) < 900, "area=%v", stroke_area(mesh))
	testing.expect(t, stroke_covers_point(mesh, {20, 0}))
	testing.expect(t, !stroke_covers_point(mesh, {20, 20}))
}

@(test)
stroke_zero_length_segments_emit_caps_only_when_required :: proc(t: ^testing.T) {
	path: Path
	defer Destroy_Path(&path)
	_ = Move_To(&path, {10, 10})
	_ = Line_To(&path, {10, 10})
	butt := Stroke{width = 6, cap = .Butt, join = .Miter, miter_limit = 4}
	mesh_butt, err_butt := Tessellate_Stroke(path.commands[:], IDENTITY, butt)
	defer Destroy_Mesh(&mesh_butt)
	testing.expect_value(t, err_butt, Error.None)
	testing.expect_value(t, len(mesh_butt.indices), 0)

	round := Stroke{width = 6, cap = .Round, join = .Miter, miter_limit = 4}
	mesh_round, err_round := Tessellate_Stroke(path.commands[:], IDENTITY, round)
	defer Destroy_Mesh(&mesh_round)
	testing.expect_value(t, err_round, Error.None)
	testing.expect(t, stroke_covers_point(mesh_round, {10, 10}))
	testing.expectf(t, abs(stroke_area(mesh_round) - math.PI * 9) < 1.5, "area=%v", stroke_area(mesh_round))
}

@(test)
stroke_dashes_and_path_length_normalize_progression :: proc(t: ^testing.T) {
	path := stroke_line()
	defer Destroy_Path(&path)
	dash := []f64{20, 20}
	style := Stroke{width = 4, cap = .Butt, join = .Miter, miter_limit = 4, dash = dash, dash_offset = 0}
	mesh, err := Tessellate_Stroke(path.commands[:], IDENTITY, style)
	defer Destroy_Mesh(&mesh)
	testing.expect_value(t, err, Error.None)
	testing.expect(t, stroke_covers_point(mesh, {5, 0}))
	testing.expect(t, !stroke_covers_point(mesh, {30, 0}))
	testing.expect(t, stroke_covers_point(mesh, {45, 0}))
	// on [0,20]+[40,60]+[80,100] = 60 → area 240
	testing.expectf(t, abs(stroke_area(mesh) - 240) < 8.0, "dash area=%v", stroke_area(mesh))

	scaled_dash := []f64{25, 75}
	base := Stroke{width = 4, cap = .Butt, join = .Miter, miter_limit = 4, dash = scaled_dash}
	mesh_base, err_base := Tessellate_Stroke(path.commands[:], IDENTITY, base)
	defer Destroy_Mesh(&mesh_base)
	testing.expect_value(t, err_base, Error.None)
	testing.expectf(t, abs(stroke_area(mesh_base) - 100) < 8.0, "base pathLength area=%v", stroke_area(mesh_base))

	scaled := Stroke{width = 4, cap = .Butt, join = .Miter, miter_limit = 4, dash = scaled_dash, path_length = 50}
	mesh_scaled, err_scaled := Tessellate_Stroke(path.commands[:], IDENTITY, scaled)
	defer Destroy_Mesh(&mesh_scaled)
	testing.expect_value(t, err_scaled, Error.None)
	// pathLength 50 / geom 100 → geometric on length 25/0.5 = 50 → area 200
	testing.expectf(t, abs(stroke_area(mesh_scaled) - 200) < 8.0, "pathLength area=%v", stroke_area(mesh_scaled))
}

@(test)
stroke_non_scaling_ignores_linear_scale_for_width :: proc(t: ^testing.T) {
	path := stroke_line()
	defer Destroy_Path(&path)
	style := Stroke{width = 4, cap = .Butt, join = .Miter, miter_limit = 4, non_scaling = true}
	scaled := Affine{2, 0, 0, 2, 0, 0}
	mesh, err := Tessellate_Stroke(path.commands[:], scaled, style)
	defer Destroy_Mesh(&mesh)
	testing.expect_value(t, err, Error.None)
	testing.expect(t, stroke_covers_point(mesh, {100, 0}))
	testing.expect(t, stroke_covers_point(mesh, {100, 1.5}))
	testing.expect(t, !stroke_covers_point(mesh, {100, 3}))
	testing.expectf(t, abs(stroke_area(mesh) - 800) < 8.0, "non-scaling area=%v", stroke_area(mesh))
}

@(test)
stroke_scales_and_reflects_under_affine_transform :: proc(t: ^testing.T) {
	path := stroke_line()
	defer Destroy_Path(&path)
	style := Stroke{width = 4, cap = .Butt, join = .Miter, miter_limit = 4}
	reflect := Affine{-1, 0, 0, 1, 100, 0}
	mesh, err := Tessellate_Stroke(path.commands[:], reflect, style)
	defer Destroy_Mesh(&mesh)
	testing.expect_value(t, err, Error.None)
	testing.expect(t, stroke_covers_point(mesh, {50, 0}))
	testing.expect(t, stroke_covers_point(mesh, {50, 1.5}))
	testing.expectf(t, abs(stroke_area(mesh) - 400) < 4.0, "reflected area=%v", stroke_area(mesh))

	shear := Affine{1, 0, 0.5, 1, 0, 0}
	mesh_shear, err_shear := Tessellate_Stroke(path.commands[:], shear, style)
	defer Destroy_Mesh(&mesh_shear)
	testing.expect_value(t, err_shear, Error.None)
	testing.expect(t, len(mesh_shear.indices) > 0)
}

@(test)
stroke_self_overlap_has_single_coverage_not_stacked_opacity :: proc(t: ^testing.T) {
	path: Path
	defer Destroy_Path(&path)
	_ = Move_To(&path, {0, 0})
	_ = Line_To(&path, {40, 0})
	_ = Line_To(&path, {20, 0})
	style := Stroke{width = 10, cap = .Butt, join = .Bevel, miter_limit = 4}
	mesh, err := Tessellate_Stroke(path.commands[:], IDENTITY, style)
	defer Destroy_Mesh(&mesh)
	testing.expect_value(t, err, Error.None)
	// Retrace covers [20,40] twice in the centreline; combined coverage must stay one strip.
	testing.expectf(t, abs(stroke_area(mesh) - 400) < 8.0, "overlap area=%v", stroke_area(mesh))
}

@(test)
stroke_bounds_include_width_extents :: proc(t: ^testing.T) {
	path := stroke_line()
	defer Destroy_Path(&path)
	style := Stroke{width = 10, cap = .Square, join = .Miter, miter_limit = 4}
	bounds, err := Stroke_Bounds(path.commands[:], IDENTITY, style)
	testing.expect_value(t, err, Error.None)
	testing.expect(t, !bounds.empty)
	testing.expect(t, bounds.min.x <= -5.25)
	testing.expect(t, bounds.max.x >= 105.25)
	testing.expect(t, bounds.min.y <= -5.25)
	testing.expect(t, bounds.max.y >= 5.25)
}

@(test)
stroke_tessellation_cleans_partial_allocations_on_failure :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	path: Path
	_ = Move_To(&path, {0, 0})
	_ = Cubic_To(&path, {30, 80}, {70, -80}, {100, 0})
	_ = Line_To(&path, {40, 40})
	_ = Line_To(&path, {0, 0})
	defer Destroy_Path(&path)
	style := Stroke{width = 6, cap = .Round, join = .Round, miter_limit = 4, dash = []f64{12, 8}}
	success := false
	for allowed in 0 ..< 256 {
		failing := Test_Failing_Allocator{backing = mem.tracking_allocator(&tracking), remaining = allowed}
		context.allocator = {procedure = test_failing_allocator_proc, data = &failing}
		mesh, err := Tessellate_Stroke(path.commands[:], IDENTITY, style)
		Destroy_Mesh(&mesh)
		context.allocator = tracking.backing
		testing.expect_value(t, tracking.current_memory_allocated, i64(0))
		testing.expect_value(t, len(tracking.allocation_map), 0)
		if !failing.rejected {
			testing.expect_value(t, err, Error.None)
			success = true
			break
		}

		testing.expect_value(t, err, Error.Allocation_Failed)
	}

	testing.expect(t, success, "stroke must succeed after every failure boundary cleans up")
}

@(test)
stroke_round_cap_circles_have_positive_area :: proc(t: ^testing.T) {
	path: Path
	defer Destroy_Path(&path)
	_ = Move_To(&path, {0, 0})
	_ = Line_To(&path, {0, 0})
	style := Stroke{width = 10, cap = .Round, join = .Miter, miter_limit = 4}
	mesh, err := Tessellate_Stroke(path.commands[:], IDENTITY, style)
	defer Destroy_Mesh(&mesh)
	testing.expect_value(t, err, Error.None)
	testing.expectf(t, abs(stroke_area(mesh) - math.PI * 25) < 3.0, "area=%v verts=%v", stroke_area(mesh), len(mesh.vertices))
}

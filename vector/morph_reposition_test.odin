#+test
package oni_vector

import "core:fmt"
import "core:math"
import "core:testing"

@(test)
endpoint_quantization_matches_rounding_at_ties_and_limits :: proc(t: ^testing.T) {
	for value in ([12]f64{0, -.0, .5, -.5, .49999999999999994, -.49999999999999994, 1.5, -1.5, 1073741824, -1073741824, 1073741823.5, -1073741823.5}) {
		p := Point{value / 1024, -value / 1024}
		got := quantize_endpoint(p)
		testing.expect_value(t, got, Integer_Point{i64(math.round(p.x * 1024)), i64(math.round(p.y * 1024))})
	}
	for i in -10000 ..< 10000 {
		value := f64(i) * .013711
		p := Point{value, -value * 1.573}
		testing.expect_value(t, quantize_endpoint(p), Integer_Point{i64(math.round(p.x * 1024)), i64(math.round(p.y * 1024))})
	}
}

@(test)
endpoint_cubic_validation_rejects_each_nonfinite_field :: proc(t: ^testing.T) {
	for field in 0 ..< 9 {
		commands := make_circleish()
		defer delete(commands)
		limits := DEFAULT_LIMITS
		limits.uniform_subdivision = -1
		mesh: Mesh
		defer Destroy_Mesh(&mesh)
		testing.expect_value(t, Tessellate_Into(&mesh, commands[:], IDENTITY, .Nonzero, limits), Error.None)
		if field < 6 { commands[1].points[field / 2][field % 2] = math.nan_f64() }
		if field == 6 || field == 7 { commands[1].radii[field - 6] = math.inf_f64(1) }
		if field == 8 { commands[1].rotation = math.nan_f64() }
		testing.expect_value(t, Tessellate_Into(&mesh, commands[:], IDENTITY, .Nonzero, limits), Error.Invalid_Value)
		testing.expect_value(t, len(mesh.indices), 0)
	}
}

@(test)
morph_orientation_filter_preserves_signs_and_rejects_degeneracy :: proc(t: ^testing.T) {
	vertices := [3][2]f32{{0, 0}, {10, 0}, {0, 10}}
	indices := [3]u32{0, 1, 2}
	mesh: Mesh
	defer Destroy_Mesh(&mesh)
	append(&mesh.vertices, ..vertices[:])
	append(&mesh.indices, ..indices[:])
	points := [3]Integer_Point{{0, 0}, {20480, 0}, {0, 20480}}
	testing.expect(t, mesh_reposition_orientation_ok(mesh, points[:]))
	points[2] = {0, -20480}
	testing.expect(t, !mesh_reposition_orientation_ok(mesh, points[:]))
	points[2] = {40960, 0}
	testing.expect(t, !mesh_reposition_orientation_ok(mesh, points[:]))
	points[2] = {0, 20480}
	mesh.vertices[2] = {20, 0}
	testing.expect(t, !mesh_reposition_orientation_ok(mesh, points[:]))
	mesh.indices[2] = 10
	testing.expect(t, !mesh_reposition_orientation_ok(mesh, points[:]))
}

@(test)
endpoint_morph_retriangulates_when_an_ear_inverts :: proc(t: ^testing.T) {
	commands := [5]Command{
		{kind = .Move}, {kind = .Line, points = {{10, 0}, {}, {}}},
		{kind = .Line, points = {{10, 10}, {}, {}}},
		{kind = .Line, points = {{0, 10}, {}, {}}}, {kind = .Close},
	}
	limits := DEFAULT_LIMITS
	limits.uniform_subdivision = -1
	mesh: Mesh
	defer Destroy_Mesh(&mesh)
	testing.expect_value(t, Tessellate_Into(&mesh, commands[:], IDENTITY, .Nonzero, limits), Error.None)
	commands[2].points[0] = {1, 1}
	testing.expect_value(t, Tessellate_Into(&mesh, commands[:], IDENTITY, .Nonzero, limits), Error.None)
	testing.expect(t, !stroke_covers_point(mesh, {3, 3}))
	testing.expect(t, stroke_covers_point(mesh, {1, .25}))
}

@(test)
endpoint_morph_preserves_validation_and_resource_limits :: proc(t: ^testing.T) {
	for invalid in 0 ..< 6 {
		commands := [5]Command{
			{kind = .Move}, {kind = .Line, points = {{10, 0}, {}, {}}},
			{kind = .Line, points = {{10, 10}, {}, {}}},
			{kind = .Line, points = {{0, 10}, {}, {}}}, {kind = .Close},
		}
		limits := DEFAULT_LIMITS
		limits.uniform_subdivision = -1
		mesh: Mesh
		defer Destroy_Mesh(&mesh)
		testing.expect_value(t, Tessellate_Into(&mesh, commands[:], IDENTITY, .Nonzero, limits), Error.None)
		expected := Error.Invalid_Value
		switch invalid {
		case 0: commands[1].points[0].x = math.nan_f64()
		case 1: commands[1].points[1].x = math.nan_f64()
		case 2: limits.max_commands = 1; expected = .Limit_Exceeded
		case 3: limits.max_coordinate = 0
		case 4: limits.max_triangles = 1; expected = .Limit_Exceeded
		case 5: limits.tolerance = 0
		}
		testing.expect_value(t, Tessellate_Into(&mesh, commands[:], IDENTITY, .Nonzero, limits), expected)
		testing.expect_value(t, len(mesh.indices), 0)
	}
}

@(test)
endpoint_morph_accepts_redundant_close_commands :: proc(t: ^testing.T) {
	commands := [7]Command{
		{kind = .Move, points = {{0, 0}, {}, {}}},
		{kind = .Line, points = {{10, 0}, {}, {}}},
		{kind = .Line, points = {{10, 10}, {}, {}}},
		{kind = .Line, points = {{0, 10}, {}, {}}},
		{kind = .Close}, {kind = .Close}, {kind = .Close},
	}
	limits := DEFAULT_LIMITS
	limits.uniform_subdivision = -1
	mesh: Mesh
	defer Destroy_Mesh(&mesh)
	testing.expect_value(t, Tessellate_Into(&mesh, commands[:], IDENTITY, .Nonzero, limits), Error.None)
	work := Exact_Work{allowed = DEFAULT_LIMITS.max_exact_ops, width = DEFAULT_LIMITS.max_integer_bits}
	ok, err := mesh_reposition_from_endpoint_commands(commands[:], IDENTITY, &mesh, &work)
	testing.expect(t, ok)
	testing.expect_value(t, err, Error.None)
}

make_circleish :: proc() -> [dynamic]Command {
	commands := make([dynamic]Command)
	append(&commands, Command{kind = .Move, points = {{10, 0}, {}, {}}})
	for i in 0 ..< 32 {
		t0 := f64(i) / 32 * math.TAU
		t1 := f64(i + 1) / 32 * math.TAU
		p0x, p0y := 10 * math.cos(t0), 10 * math.sin(t0)
		p3x, p3y := 10 * math.cos(t1), 10 * math.sin(t1)
		append(&commands, Command{kind = .Cubic, points = {
			{p0x - math.sin(t0), p0y + math.cos(t0)},
			{p3x + math.sin(t1), p3y - math.cos(t1)},
			{p3x, p3y},
		}})
	}
	append(&commands, Command{kind = .Close})
	return commands
}

@(test)
morph_reposition_skips_retriangulate :: proc(t: ^testing.T) {
	commands := make_circleish()
	defer delete(commands)
	xf := Affine{2, 0, 0, 2, 0, 0}
	lim := DEFAULT_LIMITS
	lim.uniform_subdivision = 2
	mesh: Mesh
	defer Destroy_Mesh(&mesh)
	usage: Build_Usage
	testing.expect_value(t, Tessellate_Into(&mesh, commands[:], xf, .Nonzero, lim, usage = &usage), Error.None)
	fmt.printf("first segs=%d tris=%d verts=%d inds=%d\n", usage.flattened_segments, usage.triangles, len(mesh.vertices), len(mesh.indices))
	for &c in commands {
		if c.kind == .Cubic || c.kind == .Move {
			count := c.kind == .Cubic ? 3 : 1
			for &p in c.points[:count] {
				p.x += 0.1
				p.y -= 0.05
			}
		}
	}
	usage2: Build_Usage
	prev_inds := len(mesh.indices)
	prev_verts := len(mesh.vertices)
	testing.expect_value(t, Tessellate_Into(&mesh, commands[:], xf, .Nonzero, lim, usage = &usage2), Error.None)
	fmt.printf("second segs=%d tris=%d verts=%d inds=%d exact=%d pairs=%d\n", usage2.flattened_segments, usage2.triangles, len(mesh.vertices), len(mesh.indices), usage2.exact_ops, usage2.pair_tests)
	testing.expect_value(t, len(mesh.indices), prev_inds)
	testing.expect_value(t, len(mesh.vertices), prev_verts)
	testing.expect(t, usage2.exact_ops < 1000, fmt.tprintf("exact_ops=%d suggests full retess", usage2.exact_ops))
	testing.expect_value(t, usage2.pair_tests, 0)
}

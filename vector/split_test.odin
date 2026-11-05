#+test
package oni_vector

import "core:mem"
import "core:testing"

@(test)
split_morph_preserves_original_slots_when_the_crossing_is_not_first :: proc(t: ^testing.T) {
	path: Path
	defer Destroy_Path(&path)
	points := [6]Point{{-8, -6}, {-8, 6}, {0, 0}, {8, -6}, {8, 6}, {0, 0}}
	_ = Polyline(&path, points[:], true)
	limits := DEFAULT_LIMITS
	limits.uniform_subdivision = -1
	mesh: Mesh
	defer Destroy_Mesh(&mesh)
	testing.expect_value(t, Tessellate_Into(&mesh, path.commands[:], IDENTITY, .Nonzero, limits), Error.None)
	testing.expect_value(t, len(mesh.vertices), len(points))
	for point, i in points { testing.expect_value(t, mesh.vertices[i], [2]f32{f32(point.x), f32(point.y)}) }
	for &command in path.commands {
		if command.kind == .Move || command.kind == .Line { command.points[0] += {1, 2} }
	}
	usage: Build_Usage
	testing.expect_value(t, Tessellate_Into(&mesh, path.commands[:], IDENTITY, .Nonzero, limits, usage = &usage), Error.None)
	testing.expect(t, usage.stable_remesh)
	testing.expect(t, stroke_covers_point(mesh, {-5, 2}) && stroke_covers_point(mesh, {7, 2}))
	testing.expect(t, !stroke_covers_point(mesh, {1, 7}))
}

@(test)
split_fast_path_preserves_disjoint_lobes_and_rejects_nested_lobes :: proc(t: ^testing.T) {
	for rule in Fill_Rule {
		path: Path
		_ = Polyline(&path, []Point{{0, 0}, {-8, -6}, {-8, 6}, {0, 0}, {8, -6}, {8, 6}}, true)
		mesh, err := Tessellate(path.commands[:], IDENTITY, rule)
		testing.expect_value(t, err, Error.None)
		testing.expect(t, stroke_covers_point(mesh, {-6, 0}))
		testing.expect(t, stroke_covers_point(mesh, {6, 0}))
		testing.expect(t, !stroke_covers_point(mesh, {0, 5}))
		Destroy_Mesh(&mesh)
		flat, _ := Flatten(path.commands[:], IDENTITY)
		work := Exact_Work{allowed = DEFAULT_LIMITS.max_exact_ops, width = 4096}
		pairs, simple_work := 0, 0
		arena := Scratch_Arena{backing = context.allocator}
		handled, split_error := split_mesh(flat, &mesh, DEFAULT_LIMITS, &pairs, &simple_work, &work, mem.Allocator{procedure = scratch_allocator_proc, data = &arena})
		testing.expect(t, handled)
		testing.expect_value(t, split_error, Error.None)
		Destroy_Mesh(&mesh)
		scratch_arena_destroy(&arena)
		Destroy_Flat_Path(&flat)
		Destroy_Path(&path)
	}
	path: Path
	defer Destroy_Path(&path)
	_ = Polyline(&path, []Point{{0, 0}, {20, 0}, {20, 20}, {0, 20}, {0, 0}, {5, 10}, {10, 5}}, true)
	mesh, err := Tessellate(path.commands[:], IDENTITY, .Even_Odd)
	defer Destroy_Mesh(&mesh)
	testing.expect_value(t, err, Error.None)
	testing.expect(t, !stroke_covers_point(mesh, {5, 5}))
	testing.expect(t, stroke_covers_point(mesh, {15, 15}))
}
